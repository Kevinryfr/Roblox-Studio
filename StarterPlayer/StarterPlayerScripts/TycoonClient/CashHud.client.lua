--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local TycoonKitFolder = ReplicatedStorage:WaitForChild("TycoonKit")
local RemotesFolder = TycoonKitFolder:WaitForChild("Remotes")
local CashUpdatedRemote = RemotesFolder:WaitForChild("CashUpdated") :: RemoteEvent
local GameConfig = require(TycoonKitFolder:WaitForChild("Config"):WaitForChild("GameConfig"))

local function playCollectSound()
	local soundId = GameConfig.Sounds.Collect
	if not soundId or soundId == "" or soundId == "rbxassetid://0" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 0.7
	sound.PlayOnRemove = true
	sound.Parent = workspace
	sound:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "TycoonHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.Name = "CashLabel"
label.AnchorPoint = Vector2.new(0, 0)
label.Position = UDim2.fromOffset(16, 16)
label.Size = UDim2.fromOffset(320, 48)
label.BackgroundTransparency = 0.25
label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
label.TextColor3 = Color3.fromRGB(255, 255, 255)
label.TextScaled = true
label.Font = Enum.Font.GothamBold
label.Text = "$0"
label.Parent = gui

local lastCash = 0
CashUpdatedRemote.OnClientEvent:Connect(function(cash: number)
	if cash > lastCash then
		playCollectSound()
	end
	lastCash = cash
	label.Text = "$" .. tostring(math.floor(cash))
end)
