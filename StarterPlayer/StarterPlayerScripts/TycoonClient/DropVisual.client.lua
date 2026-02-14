--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TycoonKitFolder = ReplicatedStorage:WaitForChild("TycoonKit")
local RemotesFolder = TycoonKitFolder:WaitForChild("Remotes")
local DropVisualRemote = RemotesFolder:WaitForChild("DropVisual") :: RemoteEvent
local CollectDropRemote = RemotesFolder:WaitForChild("CollectDrop") :: RemoteEvent

local POOL_SIZE = 100
local FALL_TIME = 0.2
local MOVE_SPEED = 16
local DROP_HEIGHT_OFFSET = 1.25

local colors = {
	Color3.fromRGB(255, 105, 180),
	Color3.fromRGB(100, 149, 237),
	Color3.fromRGB(144, 238, 144),
	Color3.fromRGB(255, 160, 122),
	Color3.fromRGB(186, 85, 211),
	Color3.fromRGB(255, 215, 0),
	Color3.fromRGB(64, 224, 208),
	Color3.fromRGB(255, 69, 0),
	Color3.fromRGB(147, 112, 219),
	Color3.fromRGB(255, 20, 147),
	Color3.fromRGB(0, 255, 127),
	Color3.fromRGB(255, 127, 80),
}

type ActiveDrop = {
	part: Part,
	tag: string,
}

local pool: {Part} = {}
local activeDrops: {[string]: ActiveDrop} = {}

local function makePart(): Part
	local part = Instance.new("Part")
	part.Name = "TycoonDropVisual"
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = Vector3.new(1.2, 1.2, 1.2)
	part.Transparency = 0
	return part
end

local function getPartFromPool(): Part
	local part = table.remove(pool)
	if part then
		return part
	end
	return makePart()
end

local function recyclePart(part: Part)
	part.Parent = nil
	part.Transparency = 0
	if #pool < POOL_SIZE then
		table.insert(pool, part)
	else
		part:Destroy()
	end
end

local function safeFinish(dropId: string, part: Part)
	if not activeDrops[dropId] then
		return
	end

	activeDrops[dropId] = nil
	recyclePart(part)
	CollectDropRemote:FireServer(dropId)
end

local function getCollectorPosition(): Vector3?
	local character = game.Players.LocalPlayer.Character
	if not character then
		return nil
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp.Position
	end

	return nil
end


local function findDropperPosition(dropperName: string): Vector3?
	local tycoons = workspace:FindFirstChild("Tycoons")
	if not tycoons then
		return nil
	end

	for _, tycoon in tycoons:GetChildren() do
		local droppers = tycoon:FindFirstChild("Droppers")
		if not droppers then
			continue
		end
		local dropper = droppers:FindFirstChild(dropperName)
		if dropper and dropper:IsA("Model") then
			local mouth = dropper:FindFirstChild("Mouth")
			if mouth and mouth:IsA("BasePart") then
				return mouth.Position
			end
			local pp = dropper.PrimaryPart
			if pp then
				return pp.Position
			end
		end
	end

	return nil
end

local function spawnVisual(dropperName: string, dropId: string)
	if activeDrops[dropId] then
		return
	end

	local collectorPos = getCollectorPosition()
	local dropperPos = findDropperPosition(dropperName)
	if not collectorPos or not dropperPos then
		return
	end

	local part = getPartFromPool()
	part.Color = colors[math.random(1, #colors)]
	part.Position = dropperPos
	part.Parent = workspace

	activeDrops[dropId] = {
		part = part,
		tag = dropperName,
	}

	local floorPos = Vector3.new(part.Position.X, part.Position.Y - DROP_HEIGHT_OFFSET, part.Position.Z)
	local targetPos = Vector3.new(collectorPos.X, floorPos.Y, collectorPos.Z)
	local distance = (Vector3.new(floorPos.X, 0, floorPos.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude
	local moveTime = math.max(0.08, distance / MOVE_SPEED)

	local fallTween = TweenService:Create(part, TweenInfo.new(FALL_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = floorPos,
	})

	fallTween.Completed:Connect(function()
		if not activeDrops[dropId] then
			return
		end

		local moveTween = TweenService:Create(part, TweenInfo.new(moveTime, Enum.EasingStyle.Linear), {
			Position = targetPos,
		})

		moveTween.Completed:Connect(function()
			safeFinish(dropId, part)
		end)

		moveTween:Play()
	end)

	fallTween:Play()

	task.delay(20, function()
		if activeDrops[dropId] then
			activeDrops[dropId] = nil
			recyclePart(part)
		end
	end)
end

DropVisualRemote.OnClientEvent:Connect(function(action: string, dropperName: string, dropId: string, _amount: number)
	if action ~= "Spawn" then
		return
	end
	if typeof(dropperName) ~= "string" or typeof(dropId) ~= "string" then
		return
	end
	spawnVisual(dropperName, dropId)
end)
