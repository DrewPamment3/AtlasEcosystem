local VORPcore = exports.vorp_core:GetCore()
local VORPMenu = exports.vorp_menu:GetMenuData()

-- 1. THE COMMAND
-- Usage: Type /skills in chat to open the menu
RegisterCommand('skills', function()
    print("^2[Atlas Debug]^7 Opening Skills Menu via command...")
    TriggerServerEvent('atlas_skilling:getSkills')
end, false)

-- 2. MENU RENDERER
RegisterNetEvent('atlas_skilling:openMenu')
AddEventHandler('atlas_skilling:openMenu', function(skillData)
    if not VORPMenu then
        print("^1[Atlas Error]^7 VORP Menu export is nil! Check if vorp_menu is started.")
        return
    end

    VORPMenu.CloseAll()
    local elements = {}

    local skillsToDisplay = {
        { label = "Woodcutting", xp = skillData.woodcutting_xp },
        { label = "Mining",      xp = skillData.mining_xp },
        { label = "Smelting",    xp = skillData.smelting_xp },
        { label = "Fishing",     xp = skillData.fishing_xp },
        { label = "Smithing",    xp = skillData.smithing_xp },
        { label = "Gunsmithing", xp = skillData.gunsmithing_xp },
        { label = "Cooking",     xp = skillData.cooking_xp },
        { label = "Farming",     xp = skillData.farming_xp },
        { label = "Stable Hand", xp = skillData.stable_hand_xp },
        { label = "Ranch Hand",  xp = skillData.ranch_hand_xp },
        { label = "Hunting",     xp = skillData.hunting_xp }
    }

    for _, skill in ipairs(skillsToDisplay) do
        local level = math.floor(math.sqrt(skill.xp / Config.XPFormulaDivisor)) + 1
        if level > Config.MaxLevel then level = Config.MaxLevel end

        table.insert(elements, {
            label = skill.label .. " | Level: " .. level,
            value = {},
            desc = "Total Experience: " .. skill.xp
        })
    end

    VORPMenu.Open('default', GetCurrentResourceName(), 'skill_menu', {
        title = 'Character Skills',
        align = 'top-right',
        elements = elements
    }, function(data, menu)
        menu.close()
    end, function(data, menu)
        menu.close()
    end)
end)

-- 3. XP NOTIFICATION
RegisterNetEvent('atlas_skilling:xpNotification')
AddEventHandler('atlas_skilling:xpNotification', function(skill, amount, totalXP)
    local skillLabel = skill:gsub("^%l", string.upper)
    VORPcore.NotifyTop("~t6~" .. skillLabel .. " XP", "Gained ~t2~+" .. amount .. " ~q~XP (Total: " .. totalXP .. ")",
        4000)
    PlaySoundFrontend("SELECT", "HUD_SHOP_SOUNDSET", true, 0)
end)

-- 4. LEVEL UP UI
RegisterNetEvent('atlas_skilling:levelUp')
AddEventHandler('atlas_skilling:levelUp', function(newLevel)
    VORPcore.NotifyCenter("~t6~LEVEL UP! ~q~You are now Level " .. newLevel, 5000)
    PlaySoundFrontend("PE_RANK_UP", "HUD_AWARDS_SOUNDSET", true, 0)
end)
