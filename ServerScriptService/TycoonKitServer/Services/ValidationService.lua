--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("TycoonKit"):WaitForChild("Config"):WaitForChild("GameConfig"))

local ValidationService = {}

export type PurchaseValidationResult = {
	ok: boolean,
	reason: string?,
	buttonName: string?,
	structureName: string?,
	price: number?,
	prerequisite: string?,
	gamepassId: number?,
}

local function findConfiguration(model: Instance): Configuration?
	local config = model:FindFirstChild("Configuration")
	if config and config:IsA("Configuration") then
		return config
	end
	return nil
end

local function getNumberValue(config: Configuration, childName: string): number?
	local child = config:FindFirstChild(childName)
	if not child then
		return nil
	end
	if child:IsA("NumberValue") or child:IsA("IntValue") then
		return child.Value
	end
	return nil
end

local function getStringValue(config: Configuration, childName: string): string?
	local child = config:FindFirstChild(childName)
	if not child then
		return nil
	end
	if child:IsA("StringValue") then
		return child.Value
	end
	return nil
end

local function requireButtonConfiguration(buttonModel: Model): (boolean, string?, number?, string?, number?)
	local config = findConfiguration(buttonModel)
	if not config then
		return false, "MissingConfiguration"
	end

	local price = getNumberValue(config, "Price")
	if price == nil or price < 0 then
		return false, "MissingOrInvalidPrice"
	end

	local prerequisite = getStringValue(config, "Prerequisite")
	if prerequisite == "" then
		prerequisite = nil
	end

	local gamepassId = getNumberValue(config, "GamepassId")
	if gamepassId ~= nil and gamepassId <= 0 then
		gamepassId = nil
	end

	return true, nil, price, prerequisite, gamepassId
end

function ValidationService.FindStructureForButton(structuresFolder: Instance, buttonName: string): Model?
	if not GameConfig.Rules.MatchByName then
		return nil
	end

	local structure = structuresFolder:FindFirstChild(buttonName)
	if structure and structure:IsA("Model") then
		return structure
	end

	if not GameConfig.Rules.RequireExactCase then
		for _, child in structuresFolder:GetChildren() do
			if child:IsA("Model") and string.lower(child.Name) == string.lower(buttonName) then
				return child
			end
		end
	end

	return nil
end

function ValidationService.ValidatePurchaseRequest(
	buttonModel: Instance?,
	structuresFolder: Instance,
	alreadyPurchased: {[string]: boolean},
	currentCash: number
): PurchaseValidationResult
	if buttonModel == nil or not buttonModel:IsA("Model") then
		return { ok = false, reason = "InvalidButtonModel" }
	end

	local buttonName = buttonModel.Name
	if alreadyPurchased[buttonName] then
		return { ok = false, reason = "AlreadyPurchased", buttonName = buttonName }
	end

	local okConfig, errorReason, price, prerequisite, gamepassId = requireButtonConfiguration(buttonModel)
	if not okConfig then
		return { ok = false, reason = errorReason, buttonName = buttonName }
	end

	if prerequisite ~= nil and prerequisite ~= "" and not alreadyPurchased[prerequisite] then
		return {
			ok = false,
			reason = "MissingPrerequisite",
			buttonName = buttonName,
			prerequisite = prerequisite,
		}
	end

	local structure = ValidationService.FindStructureForButton(structuresFolder, buttonName)
	if structure == nil then
		if GameConfig.Debug.WarnOnMissingStructure then
			warn(("[TycoonKit] No matching structure for button '%s'"):format(buttonName))
		end
		return { ok = false, reason = "MissingMatchingStructure", buttonName = buttonName }
	end

	if currentCash < (price :: number) then
		return {
			ok = false,
			reason = "NotEnoughCash",
			buttonName = buttonName,
			price = price,
		}
	end

	return {
		ok = true,
		buttonName = buttonName,
		structureName = structure.Name,
		price = price,
		prerequisite = prerequisite,
		gamepassId = gamepassId,
	}
end

function ValidationService.ReadDropperConfiguration(dropperModel: Instance): (boolean, string?, number?, number?, string?)
	if not dropperModel:IsA("Model") then
		return false, "DropperMustBeModel"
	end

	local config = findConfiguration(dropperModel)
	if not config then
		return false, "MissingConfiguration"
	end

	local baseValue = getNumberValue(config, "BaseValue")
	if baseValue == nil or baseValue < 0 then
		return false, "MissingOrInvalidBaseValue"
	end

	local rate = getNumberValue(config, "Rate")
	if rate == nil or rate <= 0 then
		return false, "MissingOrInvalidRate"
	end

	local tag = getStringValue(config, "Tag")
	if tag == nil or tag == "" then
		return false, "MissingTag"
	end

	return true, nil, baseValue, rate, tag
end

function ValidationService.ValidateDropperConfiguration(dropperModel: Instance): (boolean, string?)
	local ok, reason = ValidationService.ReadDropperConfiguration(dropperModel)
	return ok, reason
end

function ValidationService.ReadUpgraderConfiguration(upgraderModel: Instance): (boolean, string?, number?, string?)
	if not upgraderModel:IsA("Model") then
		return false, "UpgraderMustBeModel"
	end

	local config = findConfiguration(upgraderModel)
	if not config then
		return false, "MissingConfiguration"
	end

	local addAmount = getNumberValue(config, "AddAmount")
	if addAmount == nil or addAmount <= 0 then
		return false, "MissingOrInvalidAddAmount"
	end

	local tagFilter = getStringValue(config, "TagFilter")
	if tagFilter == nil or tagFilter == "" then
		return false, "MissingTagFilter"
	end

	return true, nil, addAmount, tagFilter
end

function ValidationService.ValidateUpgraderConfiguration(upgraderModel: Instance): (boolean, string?)
	local ok, reason = ValidationService.ReadUpgraderConfiguration(upgraderModel)
	return ok, reason
end

return ValidationService
