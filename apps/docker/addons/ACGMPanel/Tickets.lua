-- AzerothCore GM Admin Panel: Tickets tab.
--
-- The ticket command tree is the GM support workflow: list, view, respond,
-- close. Output for all of it lands in the Console tab.

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

function ADDON.Tickets.Create(parent)
    -- Commands verified against cs_ticket.cpp's ticketCommandTable.
    local r1 = Row(parent)
    local b = Button(r1, "Open list", ".ticket list")
    b = Button(r1, "Online list", ".ticket onlinelist", b)
    b = Button(r1, "Escalated", ".ticket escalatedlist", b)

    local r2 = Row(parent, r1)
    b = Button(r2, "Closed list", ".ticket closedlist")
    b = Button(r2, "Toggle system", ".ticket togglesystem", b)

    -- Id-driven actions: view / close / complete / delete / escalate.
    local r3 = Row(parent, r2, 34)
    local label = r3:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 6, 0)
    label:SetText("Ticket id:")

    local idInput = CreateFrame("EditBox", nil, r3, "InputBoxTemplate")
    idInput:SetSize(70, 20)
    idInput:SetPoint("LEFT", label, "RIGHT", 8, 0)
    idInput:SetAutoFocus(false)
    idInput:SetNumeric(true)

    local function WithId(command)
        return function()
            local id = idInput:GetText()
            if id == "" then
                ADDON.Console.Receive("info", "Enter a ticket id first.")
                return
            end
            Run(command .. " " .. id)
        end
    end

    local bView = CreateFrame("Button", nil, r3, "GameMenuButtonTemplate")
    bView:SetSize(80, 24)
    bView:SetPoint("LEFT", idInput, "RIGHT", 8, 0)
    bView:SetText("View")
    bView:SetScript("OnClick", WithId(".ticket viewid"))

    local bClose = CreateFrame("Button", nil, r3, "GameMenuButtonTemplate")
    bClose:SetSize(80, 24)
    bClose:SetPoint("LEFT", bView, "RIGHT", 6, 0)
    bClose:SetText("Close")
    bClose:SetScript("OnClick", WithId(".ticket close"))

    local bComplete = CreateFrame("Button", nil, r3, "GameMenuButtonTemplate")
    bComplete:SetSize(90, 24)
    bComplete:SetPoint("LEFT", bClose, "RIGHT", 6, 0)
    bComplete:SetText("Complete")
    bComplete:SetScript("OnClick", WithId(".ticket complete"))

    local bDelete = CreateFrame("Button", nil, r3, "GameMenuButtonTemplate")
    bDelete:SetSize(80, 24)
    bDelete:SetPoint("LEFT", bComplete, "RIGHT", 6, 0)
    bDelete:SetText("Delete")
    bDelete:SetScript("OnClick", WithId(".ticket delete"))

    -- Response: a free-form line appended to the ticket's response text.
    local r4 = Row(parent, r3, 34)
    local rlabel = r4:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rlabel:SetPoint("LEFT", 6, 0)
    rlabel:SetText("Response:")

    local response = CreateFrame("EditBox", nil, r4, "InputBoxTemplate")
    response:SetSize(300, 20)
    response:SetPoint("LEFT", rlabel, "RIGHT", 8, 0)
    response:SetAutoFocus(false)

    local bRespond = CreateFrame("Button", nil, r4, "GameMenuButtonTemplate")
    bRespond:SetSize(90, 24)
    bRespond:SetPoint("LEFT", response, "RIGHT", 8, 0)
    bRespond:SetText("Respond")
    bRespond:SetScript("OnClick", function()
        local id = idInput:GetText()
        local text = response:GetText()
        if id == "" then
            ADDON.Console.Receive("info", "Enter a ticket id first.")
            return
        end
        if text == "" then
            ADDON.Console.Receive("info", "Enter response text first.")
            return
        end
        Run(".ticket response appendln " .. id .. " " .. text)
        response:SetText("")
    end)

    local hint = r4:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", r4, "BOTTOMLEFT", 6, -2)
    hint:SetText("Respond appends a line to the ticket response with .ticket response appendln <id> <text>.")
end
