-- AzerothCore GM Admin Panel: initialization and saved settings.

local ADDON_NAME = "ACGMPanel"

ACGMPanel = {}
ACGMPanel.version = "1.0.0"

-- Subtables are populated by their own files, but every file refers to the
-- others at load time (e.g. Console's header), so declare them upfront.
ACGMPanel.Commands = {}
ACGMPanel.Console = {}
ACGMPanel.Panel = {}
ACGMPanel.QuickActions = {}
ACGMPanel.Playerbots = {}
ACGMPanel.Tickets = {}

-- Defaults for saved settings. Anything the user changes is stored under
-- ACGMPanelDB (per-account), everything else falls back to these values.
local DEFAULTS =
{
    commandPrefix  = "AzerothCore", -- fixed by the server protocol
    verbose        = true,          -- show ack/ok feedback in the console
    showTimestamps = true,
    maxHistory     = 250,           -- console lines kept
    favorites      = {},           -- quick buttons added by the user
    recentPlayers  = {},            -- names typed into the player editbox
}

-- Frame handling saved variables and the event that makes the panel usable
-- (PLAYER_LOGIN, when the spellbook etc. are all registered).
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        if not ACGMPanelDB then
            ACGMPanelDB = {}
        end
        for key, value in pairs(DEFAULTS) do
            if ACGMPanelDB[key] == nil then
                ACGMPanelDB[key] = value
            end
        end
        if not ACGMPanelDB.commandPrefix or ACGMPanelDB.commandPrefix ~= "AzerothCore" then
            ACGMPanelDB.commandPrefix = "AzerothCore"
        end
    elseif event == "PLAYER_LOGIN" then
        -- Attach the chat filter and probe the channel. The panel frame is
        -- built lazily on first open.
        ACGMPanel.Commands.Init()
        -- C_Timer does not exist on the 3.3.5 client; a one-shot OnUpdate
        -- frame is the period replacement.
        local delay = CreateFrame("Frame")
        local elapsed = 0
        delay:SetScript("OnUpdate", function(self, tt)
            elapsed = elapsed + tt
            if elapsed >= 5 then
                ACGMPanel.Commands.Ping()
                self:SetScript("OnUpdate", nil)
            end
        end)
    end
end)

-- Detect whether the account may run commands: the panel is usable by anyone
-- but every button simply fails without permission, because the server checks
-- RBAC per command. A positive/negative answer to the login-time '.account'
-- probe is cached here for cosmetic UI hints.
SLASH_ACGMPANEL1 = "/acgm"
SLASH_ACGMPANEL2 = "/gmpanel"
SlashCmdList["ACGMPANEL"] = function(msg)
    ACGMPanel.Panel.Toggle()
end

_G["ACGMPanel"] = ACGMPanel
