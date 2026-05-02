-- Atlas Woodcutting - Tool Validation System
-- Handles tool detection, durability, and level requirements

local VORPcore = exports.vorp_core:GetCore()
local Config = AtlasWoodConfig

-- Tool validation results structure:
-- {
--   hasValidTool = boolean,
--   bestTool = { name = string, tier = number, durability = number, slot = number } or nil,
--   levelValid = boolean,
--   requiredLevel = number or nil,
--   errorMessage = string or nil,
--   willBreak = boolean -- if tool will break after this action
-- }

-- Get all axes from player inventory with their durability and slot info
local function GetPlayerAxes(source)
    local axes = {}
    
    for axeName, axeData in pairs(Config.Axes) do
        local success, item = pcall(function()
            return exports.vorp_inventory:getItem(source, axeName)
        end)
        
        if success and item then
            -- VORP inventory returns array of items (player can have multiple)
            if type(item) == "table" and #item > 0 then
                for _, axeItem in ipairs(item) do
                    table.insert(axes, {
                        name = axeName,
                        tier = axeData.tier,
                        power = axeData.power,
                        durability = axeItem.metadata and axeItem.metadata.durability or 100, -- Default 100 if no metadata
                        slot = axeItem.slot,
                        id = axeItem.id -- Unique item ID for removal
                    })
                end
            end
        end
    end
    
    return axes
end

-- Find the best (highest tier) axe available
local function GetBestAxe(axes)
    if #axes == 0 then return nil end
    
    -- Sort by tier (highest first), then by durability (highest first)
    table.sort(axes, function(a, b)
        if a.tier == b.tier then
            return a.durability > b.durability -- Same tier = prefer higher durability
        end
        return a.tier > b.tier -- Higher tier = better
    end)
    
    return axes[1] -- Return best axe
end

-- Check if player meets level requirement for grove tier
local function CheckLevelRequirement(source, groveTier)
    -- Debug mode bypass
    if Config.DebugLogging then
        if Config.DebugLogging then
            print("^3[TOOL VALIDATION]^7 Debug mode enabled - bypassing level requirements")
        end
        return true, nil
    end
    
    local requiredLevel = Config.GroveUnlocks[groveTier]
    if not requiredLevel then
        return true, nil -- No level requirement
    end
    
    -- Get player's woodcutting level using sync method
    local success, playerLevel = pcall(function()
        return exports['Atlas_skilling']:GetSkillLevelSync(source, 'woodcutting')
    end)
    
    if not success or not playerLevel then
        print("^1[TOOL VALIDATION]^7 Failed to get player woodcutting level")
        return false, "Unable to check your woodcutting level"
    end
    
    if playerLevel < requiredLevel then
        return false, requiredLevel
    end
    
    return true, nil
end

-- Main tool validation function (global)
function ValidateWoodcuttingTools(source, groveTier)
    print("^2[VALIDATE TOOLS]^7 ValidateWoodcuttingTools called for player " .. source .. " grove tier " .. groveTier)
    
    local result = {
        hasValidTool = false,
        bestTool = nil,
        levelValid = false,
        requiredLevel = nil,
        errorMessage = nil,
        willBreak = false
    }
    
    -- Debug mode - bypass all requirements
    if Config.DebugLogging then
        print("^2[VALIDATE TOOLS]^7 Debug mode enabled - bypassing all requirements")
        result.hasValidTool = true
        result.levelValid = true
        result.bestTool = { name = "debug_axe", tier = 5, durability = 100, power = 3.0 }
        return result
    end
    
    -- Step 1: Check level requirements
    local levelValid, requiredLevel = CheckLevelRequirement(source, groveTier)
    result.levelValid = levelValid
    result.requiredLevel = requiredLevel
    
    if not levelValid then
        if type(requiredLevel) == "number" then
            result.errorMessage = "Requires Woodcutting Level " .. requiredLevel
        else
            result.errorMessage = requiredLevel -- Error message string
        end
        return result
    end
    
    -- Step 2: Get player's axes
    local axes = GetPlayerAxes(source)
    
    if #axes == 0 then
        result.errorMessage = "Requires Axe (Crude or better)"
        return result
    end
    
    -- Step 3: Find best axe
    local bestAxe = GetBestAxe(axes)
    
    if not bestAxe then
        result.errorMessage = "No usable axe found"
        return result
    end
    
    -- Step 4: Check if tool will break after this action
    result.willBreak = (bestAxe.durability <= 5)
    
    -- Step 5: Success!
    result.hasValidTool = true
    result.bestTool = bestAxe
    
    return result
end

-- Handle tool durability reduction and breaking (global)
function HandleAxeDurability(source, toolData)
    if Config.DebugLogging then
        print("^3[TOOL DURABILITY]^7 Debug mode - skipping durability handling")
        return true
    end
    
    local newDurability = toolData.durability - 5
    
    if newDurability <= 0 then
        -- Tool breaks - replace with broken version
        local brokenName = "broken_" .. toolData.name
        
        -- Remove original tool
        local success1 = pcall(function()
            exports.vorp_inventory:subItem(source, toolData.name, 1, toolData.metadata or {})
        end)
        
        if not success1 then
            print("^1[TOOL DURABILITY]^7 Failed to remove broken tool: " .. toolData.name)
            return false
        end
        
        -- Add broken version
        local success2 = pcall(function()
            exports.vorp_inventory:addItem(source, brokenName, 1, { durability = 0 })
        end)
        
        if not success2 then
            print("^1[TOOL DURABILITY]^7 Failed to add broken tool: " .. brokenName)
            -- Try to give back original tool to prevent item loss
            pcall(function()
                exports.vorp_inventory:addItem(source, toolData.name, 1, { durability = 1 })
            end)
            return false
        end
        
        -- Notify player
        local User = VORPcore.getUser(source)
        if User then
            VORPcore.NotifyRightTip(source, "~r~Your " .. toolData.name:gsub("_", " ") .. " has broken!", 4000)
        end
        
        print("^3[TOOL DURABILITY]^7 Tool broken: " .. toolData.name .. " -> " .. brokenName)
        return true
        
    else
        -- Reduce durability
        local success = pcall(function()
            -- Update the existing item's durability
            exports.vorp_inventory:subItem(source, toolData.name, 1, toolData.metadata or {})
            exports.vorp_inventory:addItem(source, toolData.name, 1, { durability = newDurability })
        end)
        
        if success then
            print("^3[TOOL DURABILITY]^7 " .. toolData.name .. " durability: " .. toolData.durability .. " -> " .. newDurability)
            return true
        else
            print("^1[TOOL DURABILITY]^7 Failed to update durability for: " .. toolData.name)
            return false
        end
    end
end

-- Get prompt text based on validation result (global)
function GetWoodcuttingPromptText(validationResult)
    if validationResult.hasValidTool and validationResult.levelValid then
        return "CHOP TREE", false -- Text, isDisabled
    elseif not validationResult.levelValid then
        return "CHOP TREE (Requires Level " .. (validationResult.requiredLevel or "?") .. ")", true
    elseif not validationResult.hasValidTool then
        return "CHOP TREE (Requires Axe)", true
    else
        return "CHOP TREE (Error)", true
    end
end

print("^2[Atlas Woodcutting]^7 Tool validation system loaded")
