-- resources/[grand_systems]/grand_admin/client/notify.lua
-- Notification shim, loaded first so every other client script can call Notify().
--
-- Degrades cleanly: ox_lib toast when available, otherwise chat, and always
-- mirrors the message to the admin panel.

local function DetectFrontend()
    if Frontend then return Frontend end

    if GetResourceState('ox_lib') == 'started' then
        Frontend = 'oxlib'
    else
        Frontend = 'chat'
    end

    return Frontend
end

-- Grand RP Section 01 palette, RGB so chat colours match the UI
local Colours = {
    success = { 0, 255, 136 },   -- emerald cash
    error   = { 255, 30, 56 },   -- crimson
    warning = { 255, 145, 0 },   -- vitals orange
    primary = { 255, 188, 0 },   -- grand gold
    info    = { 0, 176, 255 }    -- sapphire bank
}

--- Sends a message through the best available channel.
---@param message string
---@param kind? string  'success' | 'error' | 'warning' | 'info' | 'primary'
function Notify(message, kind)
    if not message then return end

    kind = kind or 'info'
    DetectFrontend()

    -- Mirror everything into the panel so its toasts and indicators stay in sync.
    SendNUIMessage({
        action = 'notify',
        message = tostring(message),
        type = kind
    })

    if Frontend == 'oxlib' then
        local ok = pcall(function()
            lib.notify({
                title = 'Admin',
                description = tostring(message),
                type = kind == 'primary' and 'inform' or kind,
                duration = 4000
            })
        end)
        if ok then return end
    end

    TriggerEvent('chat:addMessage', {
        color = Colours[kind] or Colours.info,
        multiline = true,
        args = { 'Admin', tostring(message) }
    })
end

exports('Notify', Notify)
