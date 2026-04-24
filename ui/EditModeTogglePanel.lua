-- ============================================================
-- CkraigCooldownManager :: UI :: EditModeTogglePanel
-- ============================================================
-- A panel shown during Edit Mode that lists all LibEditMode
-- registered frames with checkboxes to show/hide their
-- blue selection overlays.
-- ============================================================

local addonName, CCM = ...
local LibEditMode = LibStub("LibEditMode")

-- SavedVariable: persisted across sessions
CCM_EditModeTogglePanelDB = CCM_EditModeTogglePanelDB or {}

-- Pre-populate lib.hiddenFrames from saved state so that resetSelection()
-- already knows which frames to skip BEFORE our "enter" callback fires.
-- SavedVariables may not be loaded yet at file-parse time, so defer to
-- ADDON_LOADED to be safe.
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, event, loadedAddon)
    if loadedAddon == addonName then
        self:UnregisterAllEvents()
        CCM_EditModeTogglePanelDB = CCM_EditModeTogglePanelDB or {}
        for key, val in pairs(CCM_EditModeTogglePanelDB) do
            if val and key ~= "_panelCollapsed" then
                LibEditMode.hiddenFrames[key] = true
            end
        end
    end
end)

local PANEL_WIDTH = 280
local CHECKBOX_HEIGHT = 22
local HEADER_HEIGHT = 26
local BUTTON_ROW_HEIGHT = 24
local PADDING = 8
local COLLAPSED_KEY = "_panelCollapsed"

-- ── Panel Frame ────────────────────────────────────────────
local panel = CreateFrame("Frame", "CCM_EditModeTogglePanel", UIParent, "BackdropTemplate")
panel:SetSize(PANEL_WIDTH, 100)
panel:SetFrameStrata("DIALOG")
panel:SetFrameLevel(500)
panel:SetMovable(false)
panel:EnableMouse(true)
panel:SetClampedToScreen(true)
panel:Hide()

panel:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
panel:SetBackdropColor(0.08, 0.08, 0.12, 0.95)

-- Title bar
local titleBar = CreateFrame("Frame", nil, panel)
titleBar:SetHeight(HEADER_HEIGHT)
titleBar:SetPoint("TOPLEFT", panel, "TOPLEFT", PADDING, -PADDING)
titleBar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PADDING, -PADDING)
titleBar:EnableMouse(true)

local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleText:SetPoint("LEFT", titleBar, "LEFT", 2, 0)
titleText:SetText("Edit Mode Frames")
titleText:SetTextColor(0.9, 0.8, 0.5)

-- Collapse / Expand toggle button (right side of title)
local collapseBtn = CreateFrame("Button", nil, titleBar)
collapseBtn:SetSize(20, 20)
collapseBtn:SetPoint("RIGHT", titleBar, "RIGHT", 0, 0)
collapseBtn:SetNormalFontObject("GameFontNormalLarge")
collapseBtn:SetHighlightFontObject("GameFontHighlightLarge")
collapseBtn.label = collapseBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
collapseBtn.label:SetAllPoints()
collapseBtn.label:SetText("-")
collapseBtn.label:SetTextColor(0.9, 0.8, 0.5)

-- Button row (below title, above checkboxes)
local buttonRow = CreateFrame("Frame", nil, panel)
buttonRow:SetHeight(BUTTON_ROW_HEIGHT)
buttonRow:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, -2)
buttonRow:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, -2)

local showAllBtn = CreateFrame("Button", nil, buttonRow, "UIPanelButtonTemplate")
showAllBtn:SetSize(60, 20)
showAllBtn:SetPoint("LEFT", buttonRow, "LEFT", 0, 0)
showAllBtn:SetText("All")
showAllBtn:SetNormalFontObject("GameFontNormalSmall")
showAllBtn:SetHighlightFontObject("GameFontHighlightSmall")

local hideAllBtn = CreateFrame("Button", nil, buttonRow, "UIPanelButtonTemplate")
hideAllBtn:SetSize(64, 20)
hideAllBtn:SetPoint("LEFT", showAllBtn, "RIGHT", 4, 0)
hideAllBtn:SetText("None")
hideAllBtn:SetNormalFontObject("GameFontNormalSmall")
hideAllBtn:SetHighlightFontObject("GameFontHighlightSmall")

-- ── Checkbox container ─────────────────────────────────────
local container = CreateFrame("Frame", nil, panel)
container:SetPoint("TOPLEFT", buttonRow, "BOTTOMLEFT", 0, -4)
container:SetPoint("TOPRIGHT", buttonRow, "BOTTOMRIGHT", 0, -4)

local checkboxes = {}

local isCollapsed = false

local function ResizePanel(checkboxCount)
    if isCollapsed then
        buttonRow:Hide()
        container:Hide()
        local collapsedHeight = PADDING + HEADER_HEIGHT + PADDING
        panel:SetHeight(collapsedHeight)
    else
        buttonRow:Show()
        container:Show()
        local contentHeight = checkboxCount * CHECKBOX_HEIGHT
        local totalHeight = PADDING + HEADER_HEIGHT + 2 + BUTTON_ROW_HEIGHT + 4 + contentHeight + PADDING
        panel:SetHeight(totalHeight)
        container:SetHeight(contentHeight)
    end
end

local function SetCollapsed(collapsed)
    isCollapsed = collapsed
    CCM_EditModeTogglePanelDB[COLLAPSED_KEY] = collapsed or nil
    collapseBtn.label:SetText(collapsed and "+" or "-")
    ResizePanel(#checkboxes)
end

collapseBtn:SetScript("OnClick", function()
    SetCollapsed(not isCollapsed)
end)

local function BuildCheckboxes()
    -- Hide and recycle old checkboxes
    for _, cb in ipairs(checkboxes) do
        cb:Hide()
    end
    wipe(checkboxes)

    -- ── Gather all entries ─────────────────────────────────
    -- 1) LibEditMode registered frames
    local allEntries = {}

    local frames = LibEditMode:GetRegisteredFrames()
    if frames then
        for _, entry in ipairs(frames) do
            local shouldHide = not not CCM_EditModeTogglePanelDB[entry.name]
            table.insert(allEntries, {
                name = entry.name,
                kind = "libem",
                isHidden = shouldHide,
            })
        end
    end

    -- 2) DynamicIcons cluster overlays
    if _G.DYNAMICICONS and _G.DYNAMICICONS.ShowClusterAnchorsEditMode then
        local isHidden = not not CCM_EditModeTogglePanelDB["Dynamic Icon Clusters"]
        table.insert(allEntries, {
            name     = "Dynamic Icon Clusters",
            kind     = "dynamicicons",
            isHidden = isHidden,
        })
    end

    if #allEntries == 0 then return end

    -- ── Build checkboxes ───────────────────────────────────
    local yOffset = 0
    for i, entry in ipairs(allEntries) do
        local cb = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
        cb:SetSize(CHECKBOX_HEIGHT, CHECKBOX_HEIGHT)
        cb:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -yOffset)

        local label = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        label:SetPoint("RIGHT", container, "RIGHT", 0, 0)
        label:SetJustifyH("LEFT")
        label:SetText(entry.name)
        label:SetWordWrap(false)
        cb.label = label

        cb:SetChecked(not entry.isHidden)

        cb.entryName = entry.name
        cb.entryKind = entry.kind
        cb.entryFrame = entry.frame

        cb:SetScript("OnClick", function(self)
            local checked = self:GetChecked()
            local hidden = not checked

            if self.entryKind == "libem" then
                LibEditMode:SetFrameEditModeHidden(self.entryName, hidden)
            elseif self.entryKind == "dynamicicons" then
                if hidden then
                    _G.DYNAMICICONS:HideClusterAnchorsEditMode()
                else
                    _G.DYNAMICICONS:ShowClusterAnchorsEditMode()
                end
            end

            -- Persist
            if hidden then
                CCM_EditModeTogglePanelDB[self.entryName] = true
            else
                CCM_EditModeTogglePanelDB[self.entryName] = nil
            end
        end)

        checkboxes[i] = cb
        yOffset = yOffset + CHECKBOX_HEIGHT
    end

    -- Resize panel to fit
    ResizePanel(#checkboxes)
end

-- ── Show All / Hide All logic ──────────────────────────────
local function SetAllCheckboxes(checked)
    for _, cb in ipairs(checkboxes) do
        cb:SetChecked(checked)
        local hidden = not checked

        if cb.entryKind == "libem" then
            LibEditMode:SetFrameEditModeHidden(cb.entryName, hidden)
        elseif cb.entryKind == "dynamicicons" then
            if hidden then
                _G.DYNAMICICONS:HideClusterAnchorsEditMode()
            else
                _G.DYNAMICICONS:ShowClusterAnchorsEditMode()
            end
        end

        if hidden then
            CCM_EditModeTogglePanelDB[cb.entryName] = true
        else
            CCM_EditModeTogglePanelDB[cb.entryName] = nil
        end
    end
end

showAllBtn:SetScript("OnClick", function() SetAllCheckboxes(true) end)
hideAllBtn:SetScript("OnClick", function() SetAllCheckboxes(false) end)

-- ── Edit Mode callbacks ────────────────────────────────────
local function AnchorToEditModeManager()
    panel:ClearAllPoints()
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        panel:SetPoint("TOPRIGHT", EditModeManagerFrame, "TOPLEFT", -4, 0)
    else
        panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -300, -100)
    end
end

LibEditMode:RegisterCallback("enter", function()
    -- Restore persisted collapsed state
    isCollapsed = not not CCM_EditModeTogglePanelDB[COLLAPSED_KEY]
    collapseBtn.label:SetText(isCollapsed and "+" or "-")

    BuildCheckboxes()
    AnchorToEditModeManager()
    panel:Show()

    -- Force re-hide after all other OnShow hooks have fired.
    -- DynamicIcons hooks EditModeManagerFrame:OnShow and re-shows clusters,
    -- and other modules may do similar things. This deferred pass guarantees
    -- our persisted hidden states win.
    C_Timer.After(0, function()
        if not LibEditMode:IsInEditMode() then return end
        -- Re-hide LibEditMode frames
        for key, val in pairs(CCM_EditModeTogglePanelDB) do
            if val and key ~= "_panelCollapsed" then
                if LibEditMode.hiddenFrames[key] then
                    LibEditMode:SetFrameEditModeHidden(key, true)
                end
                if key == "Dynamic Icon Clusters" and _G.DYNAMICICONS then
                    _G.DYNAMICICONS:HideClusterAnchorsEditMode()
                end
            end
        end
    end)
end)

LibEditMode:RegisterCallback("exit", function()
    panel:Hide()
end)
