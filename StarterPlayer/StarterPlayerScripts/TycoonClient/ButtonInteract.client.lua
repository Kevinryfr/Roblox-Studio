--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer

local TycoonKitFolder = ReplicatedStorage:WaitForChild("TycoonKit")
local RemotesFolder = TycoonKitFolder:WaitForChild("Remotes")
local RequestPurchaseRemote = RemotesFolder:WaitForChild("RequestPurchase") :: RemoteEvent
local PurchaseResultRemote = RemotesFolder:WaitForChild("PurchaseResult") :: RemoteEvent
local GameConfig = require(TycoonKitFolder:WaitForChild("Config"):WaitForChild("GameConfig"))

local clickedCooldownByButton: {[string]: number} = {}
local hookedButtons: {[Instance]: boolean} = {}
local BUTTON_COOLDOWN = 0.2

local function playSound(soundId: string?)
	if not soundId or soundId == "" or soundId == "rbxassetid://0" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 0.8
	sound.PlayOnRemove = true
	sound.Parent = workspace
	sound:Destroy()
end

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

local function findButtonHead(buttonName: string): BasePart?
	local tycoon = findOwnedTycoon()
	if not tycoon then
		return nil
	end
	local buttons = tycoon:FindFirstChild("Buttons")
	if not buttons then
		return nil
	end
	local button = buttons:FindFirstChild(buttonName)
	if not button or not button:IsA("Model") then
		return nil
	end
	local head = button:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	return nil
end

local function animateSuccess(buttonName: string)
	local head = findButtonHead(buttonName)
	if not head then
		return
	end

	local original = head.Size
	local shrink = original * 0.9
	local tween1 = TweenService:Create(head, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = shrink})
	local tween2 = TweenService:Create(head, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = original})

	tween1.Completed:Connect(function()
		tween2:Play()
	end)
	tween1:Play()
end

local function animateFailure(buttonName: string)
	local head = findButtonHead(buttonName)
	if not head then
		return
	end

	local original = head.Color
	head.Color = Color3.fromRGB(255, 80, 80)
	task.delay(0.12, function()
		if head.Parent then
			head.Color = original
		end
	end)
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
		animateSuccess(buttonName)
		playSound(GameConfig.Sounds.Purchase)
		playSound(GameConfig.Sounds.Unlock)
		print(("[TycoonKit] Compra OK: %s"):format(buttonName))
	else
		animateFailure(buttonName)
		playSound(GameConfig.Sounds.Error)
		warn(("[TycoonKit] Compra fallida: %s (%s)"):format(buttonName, tostring(reason)))
	end
end)

task.defer(function()
	while true do
		init()
		task.wait(2)
	end
end)
