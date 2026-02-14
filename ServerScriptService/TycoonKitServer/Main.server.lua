--!strict
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TycoonKitFolder = ReplicatedStorage:WaitForChild("TycoonKit")
local RemotesFolder = TycoonKitFolder:WaitForChild("Remotes")
local RequestPurchaseRemote = RemotesFolder:WaitForChild("RequestPurchase") :: RemoteEvent
local CollectDropRemote = RemotesFolder:WaitForChild("CollectDrop") :: RemoteEvent
local DropVisualRemote = RemotesFolder:WaitForChild("DropVisual") :: RemoteEvent
local PurchaseResultRemote = RemotesFolder:WaitForChild("PurchaseResult") :: RemoteEvent
local CashUpdatedRemote = RemotesFolder:WaitForChild("CashUpdated") :: RemoteEvent

local GameConfig = require(TycoonKitFolder:WaitForChild("Config"):WaitForChild("GameConfig"))
local ValidationService = require(script.Parent:WaitForChild("Services"):WaitForChild("ValidationService"))

local TycoonsFolder = workspace:WaitForChild("Tycoons")
local PlayerDataStore = DataStoreService:GetDataStore("TycoonKitPlayerData_v1")

local DROP_TICK_RATE = 0.1

type PendingDrop = {
	amount: number,
	expiresAt: number,
}

type RuntimeState = {
	cash: number,
	purchased: {[string]: boolean},
	tycoon: Instance?,
	tagBonus: {[string]: number},
	nextDropAtByDropper: {[string]: number},
	pendingDrops: {[string]: PendingDrop},
	moneyMultiplier: number,
	bonusesInitialized: boolean,
	structuresInitialized: boolean,
}

local playerState: {[number]: RuntimeState} = {}

local function debugPrint(...: any)
	if GameConfig.Debug.Enabled and GameConfig.Debug.PrintPurchaseFlow then
		print("[TycoonKit]", ...)
	end
end

local function fireCashUpdated(player: Player, cash: number)
	CashUpdatedRemote:FireClient(player, cash)
end

local function getOwnedTycoon(player: Player): Instance?
	for _, tycoon in TycoonsFolder:GetChildren() do
		local ownerUserId = tycoon:GetAttribute("OwnerUserId")
		if typeof(ownerUserId) == "number" and ownerUserId == player.UserId then
			return tycoon
		end
	end
	return nil
end

local function setStructureUnlocked(structure: Instance, unlocked: boolean)
	if not structure:IsA("Model") then
		return
	end

	for _, desc in structure:GetDescendants() do
		if desc:IsA("BasePart") then
			desc.Transparency = unlocked and 0 or 1
			desc.CanCollide = unlocked
		end
	end
end

local function unlockStructure(tycoon: Instance, structureName: string): (boolean, string?)
	local structures = tycoon:FindFirstChild("Structures")
	if not structures then
		return false, "MissingStructuresFolder"
	end

	local structure = structures:FindFirstChild(structureName)
	if not structure then
		return false, "StructureNotFound"
	end

	setStructureUnlocked(structure, true)
	return true, nil
end

local function recomputeMoneyMultiplier(player: Player): number
	local x2Id = GameConfig.Monetization.MoneyX2PassId
	local x3Id = GameConfig.Monetization.MoneyX3PassId
	local hasX2, hasX3 = false, false

	if typeof(x2Id) == "number" and x2Id > 0 then
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, x2Id)
		end)
		hasX2 = ok and owns
	end

	if typeof(x3Id) == "number" and x3Id > 0 then
		local ok, owns = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, x3Id)
		end)
		hasX3 = ok and owns
	end

	if hasX3 then
		return GameConfig.Monetization.PassX3Multiplier
	elseif hasX2 then
		return GameConfig.Monetization.PassX2Multiplier
	end

	return 1
end

local function validateGamepassRequirement(player: Player, gamepassId: number?): (boolean, string?)
	if gamepassId == nil then
		return true, nil
	end

	local success, ownsPass = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamepassId)
	end)
	if not success then
		return false, "GamepassCheckFailed"
	end
	if not ownsPass then
		return false, "MissingRequiredGamepass"
	end

	return true, nil
end

local function handleCashPurchase(state: RuntimeState, price: number): (boolean, string?)
	if state.cash < price then
		return false, "NotEnoughCash"
	end
	state.cash -= price
	return true, nil
end

local function applyUpgraderBonusIfAny(state: RuntimeState, tycoon: Instance, purchasedName: string)
	local upgradersFolder = tycoon:FindFirstChild("Upgraders")
	if not upgradersFolder then
		return
	end

	local upgraderModel = upgradersFolder:FindFirstChild(purchasedName)
	if not upgraderModel then
		return
	end

	local ok, reason, addAmount, tagFilter = ValidationService.ReadUpgraderConfiguration(upgraderModel)
	if not ok then
		warn(("[TycoonKit] Invalid upgrader config for %s: %s"):format(purchasedName, tostring(reason)))
		return
	end

	local current = state.tagBonus[tagFilter :: string] or 0
	state.tagBonus[tagFilter :: string] = current + (addAmount :: number)
	debugPrint("Applied upgrader bonus", purchasedName, tagFilter, addAmount)
end

local function applyPurchasedStructuresIfNeeded(player: Player, state: RuntimeState)
	if state.structuresInitialized then
		return
	end

	local tycoon = getOwnedTycoon(player)
	if not tycoon then
		return
	end

	local buttons = tycoon:FindFirstChild("Buttons")
	local structures = tycoon:FindFirstChild("Structures")
	if not buttons or not structures then
		return
	end

	for purchasedName, bought in state.purchased do
		if not bought then
			continue
		end
		local buttonModel = buttons:FindFirstChild(purchasedName)
		if buttonModel and buttonModel:IsA("Model") then
			local structure = ValidationService.FindStructureForButton(structures, purchasedName)
			if structure then
				setStructureUnlocked(structure, true)
			end
		end
	end

	state.structuresInitialized = true
end

local function ensureBonusesInitialized(player: Player, state: RuntimeState)
	if state.bonusesInitialized then
		return
	end

	local tycoon = getOwnedTycoon(player)
	if not tycoon then
		return
	end

	state.tycoon = tycoon
	state.tagBonus = {}
	for purchasedName, bought in state.purchased do
		if bought then
			applyUpgraderBonusIfAny(state, tycoon, purchasedName)
		end
	end
	state.bonusesInitialized = true
end

local function serializePurchased(purchasedMap: {[string]: boolean}): {string}
	local purchasedArray = {}
	for name, value in purchasedMap do
		if value then
			table.insert(purchasedArray, name)
		end
	end
	return purchasedArray
end

local function deserializePurchased(raw: any): {[string]: boolean}
	local result: {[string]: boolean} = {}
	if typeof(raw) ~= "table" then
		return result
	end
	for _, name in raw do
		if typeof(name) == "string" then
			result[name] = true
		end
	end
	return result
end

local function loadPlayerData(player: Player): any
	if not GameConfig.Progression.SaveEnabled or GameConfig.Progression.StartFromZeroOnJoin then
		return nil
	end

	local key = tostring(player.UserId)
	local ok, data = pcall(function()
		return PlayerDataStore:GetAsync(key)
	end)
	if not ok then
		warn(("[TycoonKit] Data load failed for %s"):format(player.Name))
		return nil
	end
	return data
end

local function savePlayerState(player: Player, state: RuntimeState, reason: string)
	if not GameConfig.Progression.SaveEnabled then
		return
	end
	if GameConfig.Progression.StartFromZeroOnJoin then
		return
	end

	local payload = {
		cash = state.cash,
		purchased = serializePurchased(state.purchased),
		timestamp = os.time(),
		reason = reason,
	}

	local key = tostring(player.UserId)
	local ok, err = pcall(function()
		PlayerDataStore:SetAsync(key, payload)
	end)
	if not ok then
		warn(("[TycoonKit] Data save failed for %s: %s"):format(player.Name, tostring(err)))
	end
end

local function buildInitialStateForPlayer(player: Player)
	local initialCash = GameConfig.Economy.StartingCash
	local state: RuntimeState = {
		cash = initialCash,
		purchased = {},
		tycoon = nil,
		tagBonus = {},
		nextDropAtByDropper = {},
		pendingDrops = {},
		moneyMultiplier = recomputeMoneyMultiplier(player),
		bonusesInitialized = false,
		structuresInitialized = false,
	}

	local loadedData = loadPlayerData(player)
	if typeof(loadedData) == "table" then
		if typeof(loadedData.cash) == "number" then
			state.cash = math.clamp(loadedData.cash, 0, GameConfig.Economy.MaxCash)
		end
		state.purchased = deserializePurchased(loadedData.purchased)
	end

	playerState[player.UserId] = state
	fireCashUpdated(player, state.cash)
end

local function releaseState(player: Player)
	playerState[player.UserId] = nil
end

local function purchaseButton(player: Player, buttonName: string): (boolean, string?)
	local state = playerState[player.UserId]
	if not state then
		return false, "MissingPlayerState"
	end

	local tycoon = getOwnedTycoon(player)
	state.tycoon = tycoon
	if not tycoon then
		return false, "NoOwnedTycoon"
	end

	local buttons = tycoon:FindFirstChild("Buttons")
	local structures = tycoon:FindFirstChild("Structures")
	if not buttons or not structures then
		return false, "TycoonMissingFolders"
	end

	local buttonModel = buttons:FindFirstChild(buttonName)
	local validation = ValidationService.ValidatePurchaseRequest(buttonModel, structures, state.purchased, state.cash)
	if not validation.ok then
		return false, validation.reason or "ValidationFailed"
	end

	local passOk, passReason = validateGamepassRequirement(player, validation.gamepassId)
	if not passOk then
		return false, passReason
	end

	local paidOk, paidReason = handleCashPurchase(state, validation.price :: number)
	if not paidOk then
		return false, paidReason
	end

	local unlocked, unlockReason = unlockStructure(tycoon, validation.structureName :: string)
	if not unlocked then
		return false, unlockReason
	end

	state.purchased[validation.buttonName :: string] = true
	applyUpgraderBonusIfAny(state, tycoon, validation.buttonName :: string)
	state.bonusesInitialized = true
	state.structuresInitialized = true
	fireCashUpdated(player, state.cash)
	debugPrint(player.Name, "purchased", validation.buttonName, "remainingCash", state.cash)

	return true, "Purchased"
end

local function spawnLogicalDrop(player: Player, state: RuntimeState, dropperName: string, amount: number)
	local dropId = HttpService:GenerateGUID(false)
	state.pendingDrops[dropId] = {
		amount = amount,
		expiresAt = os.clock() + GameConfig.Drops.DropLifetime,
	}
	DropVisualRemote:FireClient(player, "Spawn", dropperName, dropId, amount)
end

local function processDroppersForPlayer(player: Player, state: RuntimeState, nowClock: number)
	ensureBonusesInitialized(player, state)
	applyPurchasedStructuresIfNeeded(player, state)

	local tycoon = getOwnedTycoon(player)
	state.tycoon = tycoon
	if not tycoon then
		return
	end

	local droppersFolder = tycoon:FindFirstChild("Droppers")
	if not droppersFolder then
		return
	end

	for _, dropper in droppersFolder:GetChildren() do
		if not dropper:IsA("Model") then
			continue
		end

		if not state.purchased[dropper.Name] then
			continue
		end

		local ok, reason, baseValue, rate, tag = ValidationService.ReadDropperConfiguration(dropper)
		if not ok then
			warn(("[TycoonKit] Invalid dropper config for %s: %s"):format(dropper.Name, tostring(reason)))
			continue
		end

		local nextAt = state.nextDropAtByDropper[dropper.Name] or 0
		if nowClock < nextAt then
			continue
		end

		state.nextDropAtByDropper[dropper.Name] = nowClock + (rate :: number)
		local bonus = state.tagBonus[tag :: string] or 0
		local amount = math.max(0, (baseValue :: number) + bonus)
		amount = amount * state.moneyMultiplier
		spawnLogicalDrop(player, state, dropper.Name, amount)
	end
end

local function cleanupExpiredDrops(state: RuntimeState, nowClock: number)
	for dropId, dropData in state.pendingDrops do
		if dropData.expiresAt <= nowClock then
			state.pendingDrops[dropId] = nil
		end
	end
end

RequestPurchaseRemote.OnServerEvent:Connect(function(player: Player, buttonName: string)
	if typeof(buttonName) ~= "string" or buttonName == "" then
		return
	end

	local ok, reason = purchaseButton(player, buttonName)
	PurchaseResultRemote:FireClient(player, ok, buttonName, reason)
	if not ok and GameConfig.Debug.Enabled then
		warn(("[TycoonKit] Purchase failed for %s on button %s: %s")
			:format(player.Name, buttonName, tostring(reason)))
	end
end)

CollectDropRemote.OnServerEvent:Connect(function(player: Player, dropId: string)
	if typeof(dropId) ~= "string" or dropId == "" then
		return
	end

	local state = playerState[player.UserId]
	if not state then
		return
	end

	local dropData = state.pendingDrops[dropId]
	if not dropData then
		return
	end

	state.pendingDrops[dropId] = nil
	state.cash += dropData.amount
	if state.cash > GameConfig.Economy.MaxCash then
		state.cash = GameConfig.Economy.MaxCash
	end
	fireCashUpdated(player, state.cash)
end)

task.spawn(function()
	while true do
		local nowClock = os.clock()
		for _, player in Players:GetPlayers() do
			local state = playerState[player.UserId]
			if state then
				processDroppersForPlayer(player, state, nowClock)
				cleanupExpiredDrops(state, nowClock)
			end
		end
		task.wait(DROP_TICK_RATE)
	end
end)

task.spawn(function()
	local interval = tonumber(GameConfig.Progression.AutosaveInterval) or 60
	interval = math.max(10, interval)
	while true do
		task.wait(interval)
		for _, player in Players:GetPlayers() do
			local state = playerState[player.UserId]
			if state then
				savePlayerState(player, state, "autosave")
			end
		end
	end
end)

Players.PlayerAdded:Connect(function(player)
	buildInitialStateForPlayer(player)
end)

Players.PlayerRemoving:Connect(function(player)
	local state = playerState[player.UserId]
	if state then
		savePlayerState(player, state, "leaving")
	end
	releaseState(player)
end)

for _, player in Players:GetPlayers() do
	buildInitialStateForPlayer(player)
end

game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		local state = playerState[player.UserId]
		if state then
			savePlayerState(player, state, "bindtoclose")
		end
	end
end)
