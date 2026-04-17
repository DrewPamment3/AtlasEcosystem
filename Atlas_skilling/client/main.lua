local VORPcore = exports.vorp_core:GetCore()

-- This matches the name in TriggerClientEvent
RegisterNetEvent('atlas_skilling:xpNotification')
AddEventHandler('atlas_skilling:xpNotification', function(skill, amount, totalXP)
    -- Format skill name (e.g., 'woodcutting' -> 'Woodcutting')
    local skillLabel = skill:gsub("^%l", string.upper)

    -- VORP Top-Right Notification
    -- ~t6~ is Gold, ~t2~ is Green, ~q~ is White
    VORPcore.NotifyTop(
        "~t6~" .. skillLabel .. " XP",
        "Gained ~t2~+" .. amount .. " ~q~XP (Total: " .. totalXP .. ")",
        4000
    )

    -- Play a satisfying RDR2 sound effect
    -- 'SELECT' in 'HUD_SHOP_SOUNDSET' is a clean, classic click/shimmer
    PlaySoundFrontend("SELECT", "HUD_SHOP_SOUNDSET", true, 0)
end)
