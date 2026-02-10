--!strict
local GameConfig = {}

GameConfig.Progression = {
	SaveEnabled = true,
	StartFromZeroOnJoin = false,
	AutosaveInterval = 60,
}

GameConfig.Economy = {
	StartingCash = 0,
	MaxCash = 1e15,
}

GameConfig.Monetization = {
	MoneyX2PassId = 0,
	MoneyX3PassId = 0,
	AutoCollectorPassId = 0,
	MultiplierMode = "HighestOnly", -- only applies the highest owned multiplier pass
	PassX2Multiplier = 2,
	PassX3Multiplier = 3,
}

GameConfig.Upgraders = {
	GlobalUpgraderMultiplier = 1.5,
}

GameConfig.Drops = {
	DropLifetime = 20,
	MaxClientVisualDrops = 100,
}

GameConfig.Sounds = {
	Purchase = "rbxassetid://0",
	Error = "rbxassetid://0",
	Unlock = "rbxassetid://0",
	Collect = "rbxassetid://0",
}

GameConfig.Rules = {
	MatchByName = true,
	RequireExactCase = true,
	PrerequisiteEmptyMeansNone = true,
}

GameConfig.Debug = {
	Enabled = true,
	PrintPurchaseFlow = false,
	WarnOnMissingStructure = true,
}

return GameConfig
