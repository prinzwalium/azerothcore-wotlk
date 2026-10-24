-- AzerothCore GM Admin Panel: Quick Actions tab.
--
-- The most common GM toggles and movement utilities, plus a free-form command
-- box. Every action goes through ACGMPanel.Commands.Send so the console shows
-- what was run and what the server answered.

local ADDON = ACGMPanel

-- Runs a command and echoes it to the console.
local function Run(command)
    ADDON.Console.Receive("sent", command)
    ADDON.Commands.Send(command, function() return true end)
end

-- Creates a fixed-size button anchored left-to-right within a row.
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

-- A button that flips between two commands, used where on and off have
-- different syntax (".cheat god" vs ".cheat god off").
local function Toggle(row, label, cmd, labelOff, cmdOff, after, width)
    local on = false
    local b = CreateFrame("Button", nil, row, "GameMenuButtonTemplate")
    b:SetSize(width or 105, 24)
    if after then
        b:SetPoint("LEFT", after, "RIGHT", 6, 0)
    else
        b:SetPoint("LEFT", 6, 0)
    end
    b:SetText(labelOff)
    b:SetScript("OnClick", function()
        on = not on
        b:SetText(on and label or labelOff)
        Run(on and cmd or cmdOff)
    end)
    return b
end

-- Rows are stacked vertically inside the tab container.
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

function ADDON.QuickActions.Create(parent)
    -- Self toggles. Verified against the command scripts:
    --   .gm fly, .cheat god, .gm visible, .gear repair, .cooldown, .save,
    --   .gps, .reload config, .server info, .server restart <seconds>.
    local r1 = Row(parent)
    local b = Toggle(r1, "Fly: on", ".gm fly on", "Fly: off", ".gm fly off")
    b = Toggle(r1, "God: on", ".cheat god on", "God: off", ".cheat god off", b)
    b = Button(r1, "Speed 1x", ".modify speed 1", b)
    b = Button(r1, "Speed 5x", ".modify speed 5", b)

    local r2 = Row(parent, r1)
    b = Toggle(r2, "Visible", ".gm visible on", "Invisible", ".gm visible off")
    b = Button(r2, "Repair gear", ".gear repair", b)
    b = Button(r2, "Clear cds", ".cooldown", b)
    b = Button(r2, "Save", ".save", b)

    local r3 = Row(parent, r2)
    b = Button(r3, "GPS", ".gps")
    b = Button(r3, "Cheat status", ".cheat status", b)
    b = Button(r3, "Max skill", ".maxskill", b)

    -- A free-form input for any other command; the console tab shows output.
    local r4 = Row(parent, r3, 34)
    local label = r4:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 6, 0)
    label:SetText("Command:")

    local input = CreateFrame("EditBox", nil, r4, "InputBoxTemplate")
    input:SetSize(300, 20)
    input:SetPoint("LEFT", label, "RIGHT", 8, 0)
    input:SetAutoFocus(false)
    input:SetScript("OnEnterPressed", function(self)
        local text = strtrim(self:GetText())
        if text ~= "" then
            Run(text)
        end
        self:SetText("")
        self:ClearFocus()
    end)

    -- Server administration: reloads and shutdown, deliberately at the bottom
    -- and away from the routine actions.
    local r5 = Row(parent, r4)
    b = Button(r5, "Reload config", ".reload config")
    b = Button(r5, "Server info", ".server info", b)
end
