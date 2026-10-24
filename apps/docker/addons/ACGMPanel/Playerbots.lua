-- AzerothCore GM Admin Panel: Playerbots tab.
--
-- Playerbot administration uses the module's own command surface: the `bots`
-- command tree. All of it goes through the same addon channel, so the console
-- tab shows the output of everything pressed here.

local ADDON = ACGMPanel

-- Runs a command and echoes it to the console.
local function Run(command)
    ADDON.Console.Receive("sent", command)
    ADDON.Commands.Send(command, function() return true end)
end

local function Button(row, label, command, after, width)
    local b = CreateFrame("Button", nil, row, "GameMenuButtonTemplate")
    b:SetSize(width or 105, 24)
    if after then
        b:SetPoint("LEFT", after, "RIGHT", 6, 0)
    else
        b:SetPoint("LEFT", 6, 0)
    end
    b:SetText(label)
    b:SetScript("OnClick", function() Run(command) end)
    return b
end

local function Row(parent, above, height)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(470, height or 30)
    if above then
        row:SetPoint("TOP", above, "BOTTOM", 0, -6)
    else
        row:SetPoint("TOP", parent, "TOP", 0, -10)
    end
    return row
end

function ADDON.Playerbots.Create(parent)
    -- Verified against mod-playerbots' command tree: .playerbots bot ...
    -- and .playerbots account ... (see the module's Playerbot Commands wiki).
    local r1 = Row(parent)
    local b = Button(r1, "List bots", ".playerbots bot list")
    b = Button(r1, "Add bot", ".playerbots bot add", b)
    b = Button(r1, "Remove bot", ".playerbots bot remove", b)
    b = Button(r1, "Init bot", ".playerbots bot init", b)

    local r2 = Row(parent, r1)
    b = Button(r2, "Linked accts", ".playerbots account linkedAccounts")
    b = Button(r2, "Bot debug", ".playerbots debug", b)

    local r3 = Row(parent, r2, 34)
    local label = r3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 6, 0)
    label:SetText("Command:")

    local input = CreateFrame("EditBox", nil, r3, "InputBoxTemplate")
    input:SetSize(300, 20)
    input:SetPoint("LEFT", label, "RIGHT", 8, 0)
    input:SetAutoFocus(false)
    input:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        if text ~= "" then
            Run(text)
        end
        self:SetText("")
        self:ClearFocus()
    end)

    local hint = r3:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", r3, "BOTTOMLEFT", 6, -2)
    hint:SetText("Add/remove take a character name (e.g. '.playerbots bot add Arglor'); output appears in the Console tab.")
end
