--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

local TycoonKitFolder = ReplicatedStorage:WaitForChild("TycoonKit")
local RemotesFolder = TycoonKitFolder:WaitForChild("Remotes")
local RequestPurchaseRemote = RemotesFolder:WaitForChild("RequestPurchase") :: RemoteEvent
local PurchaseResultRemote = RemotesFolder:WaitForChild("PurchaseResult") :: RemoteEvent

local clickedCooldownByButton: {[string]: number} = {}
local hookedButtons: {[Instance]: boolean} = {}
local BUTTON_COOLDOWN = 0.2

local function ownsTycoon(tycoon: Instance): boolean
	local ownerUserId = tycoon:GetAttribute("OwnerUserId")
	return typeof(ownerUserId) == "number" and ownerUserId == localPlayer.UserId
end

local function findOwnedTycoon(): Instance?
	local tycoons = workspace:FindFirstChild("Tycoons")
	if not tycoons then
		return nil
	end

	for _, tycoon in tycoons:GetChildren() do
		if ownsTycoon(tycoon) then
			return tycoon
		end
	end

	return nil
end

local function requestButtonPurchase(buttonModel: Model)
	local now = os.clock()
	local nextAt = clickedCooldownByButton[buttonModel.Name] or 0
	if now < nextAt then
		return
	end
	clickedCooldownByButton[buttonModel.Name] = now + BUTTON_COOLDOWN
	RequestPurchaseRemote:FireServer(buttonModel.Name)
end

local function ensureClickDetector(buttonModel: Model): ClickDetector?
	local head = buttonModel:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end

	local cd = head:FindFirstChildOfClass("ClickDetector")
	if cd then
		return cd
	end

	cd = Instance.new("ClickDetector")
	cd.MaxActivationDistance = 18
	cd.Parent = head
	return cd
end

local function hookButton(buttonModel: Instance)
	if not buttonModel:IsA("Model") then
		return
	end
	if hookedButtons[buttonModel] then
		return
	end

	local clickDetector = ensureClickDetector(buttonModel)
	if not clickDetector then
		return
	end

	hookedButtons[buttonModel] = true

	clickDetector.MouseClick:Connect(function(player)
		if player ~= localPlayer then
			return
		end
		requestButtonPurchase(buttonModel)
	end)
end

local function hookButtonsContainer(buttons: Instance)
	for _, child in buttons:GetChildren() do
		hookButton(child)
	end
	buttons.ChildAdded:Connect(hookButton)
end

local function init()
	local tycoon = findOwnedTycoon()
	if not tycoon then
		return
	end
	local buttons = tycoon:FindFirstChild("Buttons")
	if not buttons then
		return
	end
	hookButtonsContainer(buttons)
end

PurchaseResultRemote.OnClientEvent:Connect(function(ok: boolean, buttonName: string, reason: string?)
	if ok then
		print(("[TycoonKit] Compra OK: %s"):format(buttonName))
	else
		warn(("[TycoonKit] Compra fallida: %s (%s)"):format(buttonName, tostring(reason)))
	end
end)

task.defer(function()
	while true do
		init()
		task.wait(2)
	end
end)
