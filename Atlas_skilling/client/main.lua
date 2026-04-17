local VORPcore = exports.vorp_core:GetCore()
local VORPMenu = exports.vorp_menu:GetMenuData()

print("^2[Atlas Debug]^7 Client script loaded. MenuKey is: " .. tostring(Config.MenuKey))

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        -- Check for 'K' or the 'checkskills' command
        if IsControlJustPressed(0, Config.MenuKey) then
            print("^2[Atlas Debug]^7 'K' pressed. Sending request to server...")
            TriggerServerEvent('atlas_skilling:getSkills')
        end
    end
end)

RegisterNetEvent('atlas_skilling:openMenu')
AddEventHandler('atlas_skilling:openMenu', function(skillData)
    print("^2[Atlas Debug]^7 Received skill data from server. Opening Menu...")

    if not VORPMenu then
        print("^1[Atlas Error]^7 VORP Menu export is nil! Is vorp_menu started?")
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
