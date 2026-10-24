-- AzerothCore GM Admin Panel: console buffer and Console tab.
--
-- Everything the server sends back -- acks, ok/fail, message lines -- lands
-- here, so the console doubles as the feedback area for every tab. The tab
-- itself is built by Create() and fed from the same history.

local ADDON = ACGMPanel

local history = {}

local COLORS =
{
    sent     = "|cffffcc00",
    ok       = "|cff88ff88",
    failed   = "|cffff6666",
    message  = "|cffffffff",
    info     = "|cff88ccff",
}

function ACGMPanel.Console.Init()
    -- The Console tab's scrolling frame is created by Create() when the
    -- panel is built; lines printed before that are kept in the history
    -- table and replayed into it.
end

function ACGMPanel.Console.Receive(kind, body)
    -- kind: "sent", "ok", "failed", "message", "info"
    if kind == "sent" then
        ACGMPanel.Console.AddLine(COLORS.sent .. "» " .. (body or ""))
    elseif kind == "ok" then
        ACGMPanel.Console.AddLine(COLORS.ok .. "OK")
    elseif kind == "failed" then
        ACGMPanel.Console.AddLine(COLORS.failed .. "Failed")
    elseif kind == "message" then
        ACGMPanel.Console.AddLine(COLORS.message .. (body or ""))
    elseif kind == "info" then
        ACGMPanel.Console.AddLine(COLORS.info .. (body or ""))
    end
end

function ACGMPanel.Console.AddLine(text)
    local max = ACGMPanelDB.maxHistory or 250
    if ACGMPanelDB.showTimestamps then
        text = "|cff999999" .. date("%H:%M:%S") .. "|r " .. text
    end
    table.insert(history, text)
    if #history > max then
        table.remove(history, 1)
    end

    local view = ACGMPanel.Panel and ACGMPanel.Panel.GetConsoleFrame()
    if view then
        view:AddMessage(text)
        view:ScrollToBottom()
    end
end

function ACGMPanel.Console.GetHistory()
    return history
end
-- AzerothCore GM Admin Panel: Console tab.
--
-- A scrolling message frame fed by ACGMPanel.Console plus an input box that
-- sends arbitrary commands. This is the "run anything" tab; the output of
-- every command from every tab lands here.

local ADDON = ACGMPanel

function ADDON.Console.Create(parent)
    local scroll = CreateFrame("ScrollingMessageFrame", nil, parent)
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -8, -34)
    scroll:SetFontObject(GameFontHighlightSmall)
    scroll:SetMaxLines(ACGMPanelDB.maxHistory or 250)
    scroll:SetFading(false)
    scroll:SetJustifyH("LEFT")
    scroll:EnableMouseWheel(true)
    parent.messages = scroll

    -- Replay anything that was logged before the frame existed.
    for _, line in ipairs(history) do
        scroll:AddMessage(line)
    end

    local input = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    input:SetSize(parent:GetWidth() - 60, 20)
    input:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 14, 8)
    input:SetAutoFocus(false)
    input:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        if text ~= "" then
            ADDON.Console.Receive("sent", text)
            ADDON.Commands.Send(text, function() return true end)
        end
        self:SetText("")
        self:ClearFocus()
    end)

    local hint = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", input, "TOPLEFT", 0, 2)
    hint:SetText("Enter a command (without the leading dot it is still parsed); history is kept in this tab.")
end
