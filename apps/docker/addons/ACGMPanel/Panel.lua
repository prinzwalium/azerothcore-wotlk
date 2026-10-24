-- AzerothCore GM Admin Panel: main window, tabs, slash toggle, minimap button.

local ADDON = ACGMPanel
local panels = {}
local currentTab = "quick"

-- Tab definition. Each tab module provides Create(parent) and is laid out by
-- the shared scaffolding here.
local TABS =
{
    { id = "quick",      label = "Quick",      module = "QuickActions" },
    { id = "console",    label = "Console",    module = "Console"      },
    { id = "playerbots", label = "Playerbots", module = "Playerbots"  },
    { id = "tickets",    label = "Tickets",    module = "Tickets"     },
}

-- Minimal UI scaffolding: shared border/backdrop used across the panel.
local BACKDROP =
{
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

local function ApplyBackdrop(frame)
    frame:SetBackdrop(BACKDROP)
end

function ADDON.Panel.CreateInWorldUI()
    if ADDON.Panel.frame then
        return
    end

    local f = CreateFrame("Frame", "ACGMPanelFrame", UIParent)
    f:SetSize(520, 400)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:SetUserPlaced(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    ApplyBackdrop(f)
    f:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self:StartMoving()
        end
    end)
    f:SetScript("OnMouseUp", function(self)
        self:StopMovingOrSizing()
    end)
    tinsert(UISpecialFrames, "ACGMPanelFrame")

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOP", 0, -14)
    f.title:SetText("AzerothCore GM Admin Panel")

    f.close = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    f.close:SetPoint("TOPRIGHT", -18, -14)
    f.close:SetSize(18, 18)
    f.close:SetText("x")
    f.close:SetScript("OnClick", function()
        ADDON.Panel.Hide()
    end)

    -- Tab buttons along the top.
    local prev
    for i, tab in ipairs(TABS) do
        local b = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
        b:SetSize(90, 22)
        if prev then
            b:SetPoint("TOPLEFT", prev, "TOPRIGHT", 4, 0)
        else
            b:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -40)
        end
        b:SetText(tab.label)
        b:SetScript("OnClick", function()
            ADDON.Panel.SelectTab(tab.id)
        end)
        b.tabId = tab.id
        tab.button = b
        prev = b
    end

    -- Content area: each tab gets its own container, shown one at a time.
    for _, tab in ipairs(TABS) do
        local container = CreateFrame("Frame", nil, f)
        container:SetPoint("TOPLEFT", f, "TOPLEFT", 20, -70)
        container:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -20, 20)
        container:Hide()
        panels[tab.id] = container
        if ADDON[tab.module] and ADDON[tab.module].Create then
            ADDON[tab.module].Create(container)
        end
    end

    ADDON.Panel.frame = f
    f:Hide()

    ADDON.Panel.CreateMinimapButton()
    ADDON.Panel.SelectTab(currentTab)
end

function ADDON.Panel.SelectTab(id)
    currentTab = id
    for _, tab in ipairs(TABS) do
        local container = panels[tab.id]
        if tab.id == id then
            container:Show()
            tab.button:LockHighlight()
        else
            container:Hide()
            tab.button:UnlockHighlight()
        end
    end
end

function ADDON.Panel.GetConsoleFrame()
    local consoleTab = panels["console"]
    if consoleTab and consoleTab.messages then
        return consoleTab.messages
    end
    return nil
end

function ADDON.Panel.Toggle()
    if ADDON.Panel.frame and ADDON.Panel.frame:IsShown() then
        ADDON.Panel.Hide()
    else
        ADDON.Panel.Show()
    end
end

function ADDON.Panel.Show()
    ADDON.Panel.CreateInWorldUI()
    ADDON.Panel.frame:Show()
end

function ADDON.Panel.Hide()
    if ADDON.Panel.frame then
        ADDON.Panel.frame:Hide()
    end
end

function ADDON.Panel.CreateMinimapButton()
    if ADDON.Panel.minimapButton then
        return
    end
    local button = CreateFrame("Button", "ACGMPanelMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetPoint("CENTER", Minimap, "CENTER", 80, 0)
    button:SetNormalTexture("Interface\\CHARACTERFRAME\\UI-CharacterFrame-GroupIndicator")
    button:SetHighlightTexture("Interface\\MINIMAP\\UI-Minimap-ZoomButton-Highlight")
    button:SetScript("OnClick", function()
        ADDON.Panel.Toggle()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("AzerothCore GM Panel", 0.4, 0.7, 0.85)
        GameTooltip:AddLine("Click to open", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    ADDON.Panel.minimapButton = button
end
