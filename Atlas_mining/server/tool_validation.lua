-- Atlas Mining - Tool Validation System
-- Handles tool detection, durability, and level requirements
-- Modeled after Atlas_woodcutting/server/tool_validation.lua

local VORPcore = exports.vorp_core:GetCore()
local Config = AtlasMiningConfig

-- ============================================================
-- TOOL DETECTION
-- ============================================================

-- Get all pickaxes from player inventory with their durability and slot info
local function GetPlayerPickaxes(source)
    local pickaxes = {}
    
    for pickaxeName, pickaxeData in pairs(Config.Pickaxes) do
        if Config.DebugLogging then
            print("^3[GET PICKAXES DEBUG]^7 Checking for pickaxe: " .. pickaxeName)
        end
        
        local success, item = pcall(function()
            return exports.vorp_inventory:getItem(source, pickaxeName)
        end)
        
        if success and item then
            if Config.DebugLogging then
                print("^2[GET PICKAXES]^7 Player " .. source .. " has " .. pickaxeName .. ": " .. tostring(item))
            end
            
            local hasItem = false
            local itemData = nil
            
            if type(item) == "table" then
                if item.count and item.count > 0 then
                    hasItem = true
                    itemData = item
                elseif #item > 0 then
                    hasItem = true
                    itemData = item[1]
                end
            elseif type(item) == "number" and item > 0 then
                hasItem = true
                itemData = { count = item }
            end
            
            if hasItem then
                local durability = 100
                if itemData and itemData.metadata and itemData.metadata.durability then
                    durability = itemData.metadata.durability
                end
                
                table.insert(pickaxes, {
                    name = pickaxeName,
                    tier = pickaxeData.tier,
                    power = pickaxeData.power,
                    durability = durability,
                    slot = itemData and itemData.slot or 0,
                    id = itemData and itemData.id or 0,
                    metadata = itemData and itemData.metadata or {}
                })
            end
        end
    end
    
    return pickaxes
end

-- Find the best (highest tier) pickaxe available
local function GetBestPickaxe(pickaxes)
    if #pickaxes == 0 then return nil end
    
    table.sort(pickaxes, function(a, b)
        if a.tier == b.tier then
            return a.durability > b.durability
        end
        return a.tier > b.tier
    end)
    
    return pickaxes[1]
end

-- ============================================================
-- LEVEL VALIDATION
-- ============================================================

local function CheckLevelRequirement(source, campTier)
    if Config.DebugLogging then
        print("^3[TOOL VALIDATION]^7 Debug mode enabled - bypassing level requirements")
        return true, nil
    end
    
    local requiredLevel = Config.CampUnlocks[campTier]
    if not requiredLevel then
        return true, nil
    end
    
    local success, playerLevel = pcall(function()
        return exports['Atlas_skilling']:GetSkillLevelSync(source, 'mining')
    end)
    
    if not success or not playerLevel then
        print("^1[TOOL VALIDATION]^7 Failed to get player mining level")
        return false, "Unable to check your mining level"
    end
    
    if playerLevel < requiredLevel then
        return false, requiredLevel
    end
    
    return true, nil
end

-- ============================================================
-- MAIN VALIDATION FUNCTION (global)
-- ============================================================

function ValidateMiningTools(source, campTier)
    local result = {
        hasValidTool = false,
        bestTool = nil,
        levelValid = false,
        requiredLevel = nil,
        errorMessage = nil,
        willBreak = false
    }
    
    if Config.DebugLogging then
        result.hasValidTool = true
        result.levelValid = true
        result.bestTool = { name = "debug_pickaxe", tier = 5, durability = 100, power = 3.0 }
        return result
    end
    
    -- Step 1: Check level requirements
    local levelValid, requiredLevel = CheckLevelRequirement(source, campTier)
    result.levelValid = levelValid
    result.requiredLevel = requiredLevel
    
    if not levelValid then
        if type(requiredLevel) == "number" then
            result.errorMessage = "Requires Mining Level " .. requiredLevel
        else
            result.errorMessage = requiredLevel
        end
        return result
    end
    
    -- Step 2: Get player's pickaxes
    local pickaxes = GetPlayerPickaxes(source)
    
    if #pickaxes == 0 then
        result.errorMessage = "Requires Pickaxe (Crude or better)"
        return result
    end
    
    -- Step 3: Find best pickaxe
    local bestPickaxe = GetBestPickaxe(pickaxes)
    
    if not bestPickaxe then
        result.errorMessage = "No usable pickaxe found"
        return result
    end
    
    -- Step 4: Check if tool will break after this action
    result.willBreak = (bestPickaxe.durability <= 5)
    
    -- Step 5: Success!
    result.hasValidTool = true
    result.bestTool = bestPickaxe
    
    return result
end

-- ============================================================
-- TOOL DURABILITY (global)
-- ============================================================

function HandlePickaxeDurability(source, toolData)
    if Config.DebugLogging then
        return true
    end
    
    local newDurability = toolData.durability - 5
    
    if newDurability <= 0 then
        local brokenName = "broken_" .. toolData.name
        
        local success1 = pcall(function()
            exports.vorp_inventory:subItem(source, toolData.name, 1, toolData.metadata or {})
        end)
        
        if not success1 then
            print("^1[TOOL DURABILITY]^7 Failed to remove broken tool: " .. toolData.name)
            return false
        end
        
        local success2 = pcall(function()
            exports.vorp_inventory:addItem(source, brokenName, 1, { durability = 0 })
        end)
        
        if not success2 then
            print("^1[TOOL DURABILITY]^7 Failed to add broken tool: " .. brokenName)
            pcall(function()
                exports.vorp_inventory:addItem(source, toolData.name, 1, { durability = 1 })
            end)
            return false
        end
        
        local User = VORPcore.getUser(source)
        if User then
            VORPcore.NotifyRightTip(source, "~r~Your " .. toolData.name:gsub("_", " ") .. " has broken!", 4000)
        end
        
        print("^3[TOOL DURABILITY]^7 Tool broken: " .. toolData.name .. " -> " .. brokenName)
        return true
    else
        local success = pcall(function()
            exports.vorp_inventory:subItem(source, toolData.name, 1, toolData.metadata or {})
            exports.vorp_inventory:addItem(source, toolData.name, 1, { durability = newDurability })
        end)
        
        if success then
            if Config.DebugLogging then
                print("^3[TOOL DURABILITY]^7 " .. toolData.name .. " durability: " .. toolData.durability .. " -> " .. newDurability)
            end
            return true
        else
            print("^1[TOOL DURABILITY]^7 Failed to update durability for: " .. toolData.name)
            return false
        end
    end
end

-- ============================================================
-- PROMPT TEXT HELPER (global)
-- ============================================================

function GetMiningPromptText(validationResult)
    if validationResult.hasValidTool and validationResult.levelValid then
        return "MINE ROCK", false
    elseif not validationResult.levelValid then
        return "MINE ROCK (Requires Level " .. (validationResult.requiredLevel or "?") .. ")", true
    elseif not validationResult.hasValidTool then
        return "MINE ROCK (Requires Pickaxe)", true
    else
        return "MINE ROCK (Error)", true
    end
end

-- ============================================================
-- GLOBAL EXPORT
-- ============================================================

_G.ValidateMiningTools = ValidateMiningTools
_G.HandlePickaxeDurability = HandlePickaxeDurability
_G.GetMiningPromptText = GetMiningPromptText

print("^2[Atlas Mining]^7 Tool validation system loaded (from tool_validation.lua)")
