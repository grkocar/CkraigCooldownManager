    -- luacheck: globals GetSpellInfo GetNumSpellBookSlots GetSpellBookItemID GetSpellBookItemName GetSpellBookItemTexture InterfaceOptions_AddCategory IsSpellKnown GetItemInfo GetItemCount GetItemCooldown CreateFrame UIParent C_Timer print select pairs ipairs STANDARD_TEXT_FONT
    CCM_TrackedSpellsSettings = CCM_TrackedSpellsSettings or {
        iconSize = 40,
        spacing = 10,
        direction = "RIGHT",
        chargePosition = "BOTTOMRIGHT",
        chargeOffsetX = 0,
        chargeOffsetY = 0,
        showInCombatOnly = false,
        groups = {},
    }
-- luacheck: globals GetSpellInfo GetNumSpellBookSlots GetSpellBookItemID GetSpellBookItemName GetSpellBookItemTexture InterfaceOptions_AddCategory

-- Spell/item info lookup (must be defined before any function that uses it)
local function SafeGetSpellOrItemInfo(id)
    -- Try spell first (Retail)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        if info and info.name and info.iconID then
            return info.name, info.iconID, "spell"
        end
    end
    -- Try item
    local itemName, _, itemIcon = GetItemInfo(id)
    if itemIcon then
        return itemName or ("Item #"..id), itemIcon, "item"
    end
    -- Force item cache and retry
    if not itemIcon and Item and Item.CreateFromItemID then
        local item = Item:CreateFromItemID(id)
        if item then
            item:ContinueOnItemLoad(function()
                local name, _, icon = GetItemInfo(id)
                if icon then
                    return name or ("Item #"..id), icon, "item"
                end
            end)
        end
    end
    return nil, nil, nil
end
_G.SafeGetSpellOrItemInfo = SafeGetSpellOrItemInfo

    -- Persistence: uses CCM_TrackedSpellsDB (SavedVariable) as primary store
    local PROFILE_KEY = "trackedSpells"

    local function GetPlayerClassSpec()
        local class = select(2, UnitClass("player")) or "UNKNOWN"
        local spec = nil
        if GetSpecialization then
            local specIndex = GetSpecialization()
            if specIndex then
                spec = select(2, GetSpecializationInfo(specIndex))
            end
        end
        return class, spec or "NOSPEC"
    end

    local function DeepCopyTable(tbl)
        if type(tbl) ~= "table" then return tbl end
        local copy = {}
        for k, v in pairs(tbl) do
            if type(v) == "table" then
                copy[k] = DeepCopyTable(v)
            else
                copy[k] = v
            end
        end
        return copy
    end

    local function LoadSettings()
        local class, spec = GetPlayerClassSpec()
        local key = class .. "_" .. spec

        -- Primary: read from CCM_TrackedSpellsDB SavedVariable
        local db = CCM_TrackedSpellsDB
        if type(db) ~= "table" then db = {} end

        -- Migration: if db has new format (db.settings exists), use it
        -- Otherwise try AceDB profile for one-time migration
        local data = nil
        if db.settings or db.classSpecGroups then
            data = db
        elseif CkraigProfileManager and CkraigProfileManager.GetProfileData then
            local profileData = CkraigProfileManager:GetProfileData(PROFILE_KEY)
            if profileData and (profileData.classSpecGroups or profileData.iconSize) then
                data = profileData
                -- Migrate: copy AceDB data into the SavedVariable
                CCM_TrackedSpellsDB = {
                    settings = {
                        iconSize = profileData.iconSize,
                        spacing = profileData.spacing,
                        direction = profileData.direction,
                        chargePosition = profileData.chargePosition,
                        columns = profileData.columns,
                        chargeTextSize = profileData.chargeTextSize,
                        chargeTextX = profileData.chargeTextX,
                        chargeTextY = profileData.chargeTextY,
                        enabled = profileData.enabled,
                    },
                    classSpecGroups = DeepCopyTable(profileData.classSpecGroups or {}),
                }
                db = CCM_TrackedSpellsDB
            end
        end
        if not data then data = {} end

        local settings = data.settings or data
        local groupsForSpec = (data.classSpecGroups and data.classSpecGroups[key]) or {}
        local allGroups = DeepCopyTable(groupsForSpec)

        -- Clear the global settings table to avoid leftover spells from previous spec
        if CCM_TrackedSpellsSettings then
            CCM_TrackedSpellsSettings.groups = {}
        end

        CCM_TrackedSpellsSettings = {
            iconSize = settings.iconSize or 40,
            spacing = settings.spacing or 10,
            direction = settings.direction or "RIGHT",
            chargePosition = settings.chargePosition or "BOTTOMRIGHT",
            columns = settings.columns or 6,
            chargeTextSize = settings.chargeTextSize or 14,
            chargeTextX = settings.chargeTextX or 0,
            chargeTextY = settings.chargeTextY or 0,
            enabled = (settings.enabled == nil) or settings.enabled,
            showInCombatOnly = settings.showInCombatOnly or false,
            groups = allGroups,
        }
    end

    local function SaveSettings()
        local class, spec = GetPlayerClassSpec()
        local key = class .. "_" .. spec

        -- Ensure CCM_TrackedSpellsDB is structured
        if type(CCM_TrackedSpellsDB) ~= "table" or not CCM_TrackedSpellsDB.settings then
            CCM_TrackedSpellsDB = { settings = {}, classSpecGroups = {} }
        end

        -- Write settings
        CCM_TrackedSpellsDB.settings = {
            iconSize = CCM_TrackedSpellsSettings.iconSize,
            spacing = CCM_TrackedSpellsSettings.spacing,
            direction = CCM_TrackedSpellsSettings.direction,
            chargePosition = CCM_TrackedSpellsSettings.chargePosition,
            columns = CCM_TrackedSpellsSettings.columns,
            chargeTextSize = CCM_TrackedSpellsSettings.chargeTextSize,
            chargeTextX = CCM_TrackedSpellsSettings.chargeTextX,
            chargeTextY = CCM_TrackedSpellsSettings.chargeTextY,
            enabled = CCM_TrackedSpellsSettings.enabled,
            showInCombatOnly = CCM_TrackedSpellsSettings.showInCombatOnly,
        }

        -- Write groups for this class/spec
        CCM_TrackedSpellsDB.classSpecGroups = CCM_TrackedSpellsDB.classSpecGroups or {}
        CCM_TrackedSpellsDB.classSpecGroups[key] = DeepCopyTable(CCM_TrackedSpellsSettings.groups)

        -- Also sync to AceDB profile if available
        if CkraigProfileManager and CkraigProfileManager.SetProfileData then
            pcall(CkraigProfileManager.SetProfileData, CkraigProfileManager, PROFILE_KEY, DeepCopyTable(CCM_TrackedSpellsDB))
        end
    end

    local function CreateSlider(parent, label, min, max, step, value, onChange)
        local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
        slider:SetMinMaxValues(min, max)
        slider:SetValueStep(step)
        slider:SetValue(value)
        slider:SetWidth(180)
        slider:SetHeight(20)
        slider.Text = slider:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        slider.Text:SetPoint("LEFT", slider, "RIGHT", 8, 0)
        slider.Text:SetTextColor(0.85, 0.85, 0.85, 1)
        slider.Text:SetText(label .. ": " .. math.floor(value))
        slider:SetScript("OnValueChanged", function(self, v)
            onChange(v)
            slider.Text:SetText(label .. ": " .. math.floor(v))
        end)
        return slider
    end

    local function CreateDropdown(parent, label, options, value, onChange)
        local container = CreateFrame("Frame", nil, parent)
        container:SetSize(220, 50)
        container.label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        container.label:SetPoint("TOPLEFT", 0, 0)
        container.label:SetText(label)
        container.label:SetTextColor(0.85, 0.85, 0.85, 1)
        local dropdown = CreateFrame("DropdownButton", nil, container, "WowStyle1DropdownTemplate")
        dropdown:SetPoint("TOPLEFT", container.label, "BOTTOMLEFT", 0, -2)
        dropdown:SetWidth(180)
        dropdown.currentValue = value
        dropdown:SetupMenu(function(dd, rootDescription)
            for _, opt in ipairs(options) do
                rootDescription:CreateRadio(
                    opt,
                    function() return dropdown.currentValue == opt end,
                    function()
                        dropdown.currentValue = opt
                        onChange(opt)
                    end,
                    opt
                )
            end
        end)
        container.dropdown = dropdown
        return container
    end

    -- Creates the icon configuration controls inside the provided frames.
    -- This function should be called from the options panel setup code,
    -- passing in the appropriate `content` and `spellListFrame` frames.
    function CCM_CreateIconSettingsControls(content, spellListFrame)
        -- Icon Size Slider
        local iconSizeSlider = CreateSlider(content, "Icon Size", 20, 100, 1, CCM_TrackedSpellsSettings.iconSize, function(v)
            CCM_TrackedSpellsSettings.iconSize = v
            SaveSettings()
            UpdateCustomSpellIcons()
        end)
        iconSizeSlider:SetPoint("TOPLEFT", spellListFrame, "BOTTOMLEFT", 0, -60)

        local spacingSlider = CreateSlider(content, "Icon Spacing", 0, 50, 1, CCM_TrackedSpellsSettings.spacing, function(v)
            CCM_TrackedSpellsSettings.spacing = v
            SaveSettings()
            UpdateCustomSpellIcons()
        end)
        spacingSlider:SetPoint("TOPLEFT", iconSizeSlider, "BOTTOMLEFT", 0, -40)

        local directions = {"RIGHT", "LEFT", "UP", "DOWN"}
        local directionDropdown = CreateDropdown(content, "Growth Direction", directions, CCM_TrackedSpellsSettings.direction, function(opt)
            CCM_TrackedSpellsSettings.direction = opt
            SaveSettings()
            UpdateCustomSpellIcons()
        end)
        directionDropdown:SetPoint("TOPLEFT", spacingSlider, "BOTTOMLEFT", 0, -40)

        local positions = {"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT"}
        local chargeDropdown = CreateDropdown(content, "Charge/Stack Position", positions, CCM_TrackedSpellsSettings.chargePosition, function(opt)
            CCM_TrackedSpellsSettings.chargePosition = opt
            SaveSettings()
            UpdateCustomSpellIcons()
        end)
        chargeDropdown:SetPoint("TOPLEFT", directionDropdown, "BOTTOMLEFT", 0, -40)
    end


-- Auto-populate tracked spells from spellbook for current spec/class
local function AutoPopulateTrackedSpells()
    local class, _ = UnitClass("player")
    local specIndex = GetSpecialization and GetSpecialization()
    local specName = specIndex and select(2, GetSpecializationInfo(specIndex)) or "Default"
    print("[CCM] Scanning spellbook for class:", class, "spec:", specName)
    local foundIDs = {}
    -- Retail 11.x: use C_SpellBook API
    if C_SpellBook and C_SpellBook.GetNumSpellBookItems then
        local bankEnum = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
        if bankEnum then
            local numSpells = C_SpellBook.GetNumSpellBookItems(bankEnum) or 0
            for i = 1, numSpells do
                local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, i, bankEnum)
                if ok and info and info.spellID and not info.isPassive and not info.isOffSpec then
                    table.insert(foundIDs, info.spellID)
                end
            end
        else
            -- Fallback: try numeric bank value
            local ok, numSpells = pcall(C_SpellBook.GetNumSpellBookItems, 0)
            if ok and numSpells then
                for i = 1, numSpells do
                    local ok2, info = pcall(C_SpellBook.GetSpellBookItemInfo, i, 0)
                    if ok2 and info and info.spellID and not info.isPassive and not info.isOffSpec then
                        table.insert(foundIDs, info.spellID)
                    end
                end
            end
        end
    -- Legacy fallback
    elseif GetNumSpellBookSlots then
        local numSlots = GetNumSpellBookSlots() or 0
        for slot = 1, numSlots do
            local spellID = GetSpellBookItemID and GetSpellBookItemID(slot, "spell")
            if spellID then
                local name = GetSpellBookItemName and GetSpellBookItemName(slot, "spell")
                if name then
                    table.insert(foundIDs, spellID)
                end
            end
        end
    end
    if #foundIDs > 0 then
        -- Add found spells to Group 1 (create if needed)
        local groups = CCM_TrackedSpellsSettings.groups or {}
        if #groups == 0 then
            table.insert(groups, {name = "Group 1", spellIDs = {}})
        end
        groups[1].spellIDs = groups[1].spellIDs or {}
        local existingIDs = {}
        for _, id in ipairs(groups[1].spellIDs) do
            existingIDs[id] = true
        end
        local addedCount = 0
        for _, id in ipairs(foundIDs) do
            if not existingIDs[id] then
                table.insert(groups[1].spellIDs, id)
                addedCount = addedCount + 1
            end
        end
        CCM_TrackedSpellsSettings.groups = groups
        SaveSettings()
        print("[CCM] Added", addedCount, "spells from spellbook to", groups[1].name or "Group 1")
        UpdateSpellList()
        UpdateCustomSpellIcons()
    else
        print("[CCM] No spells found in spellbook.")
    end
end
_G.AutoPopulateTrackedSpells = AutoPopulateTrackedSpells
-- CCM_TrackedSpells.lua
-- Track custom spells from the player's spellbook, similar to racials in PROCS.LUA

-- SavedVariables for custom spells (structured table, NOT a flat array)
CCM_TrackedSpellsDB = CCM_TrackedSpellsDB or {}

-- Collect all spell IDs from all groups (for legacy compatibility)
local function FindPlayerCustomSpells()
    local found = {}
    local groups = CCM_TrackedSpellsSettings and CCM_TrackedSpellsSettings.groups or {}
    for _, group in ipairs(groups) do
        for _, spellID in ipairs(group.spellIDs or {}) do
            table.insert(found, spellID)
        end
    end
    return found
end

local ICON_SIZE = 40
local ICON_SPACING = 50
local ICON_ROW_SPACING = 10
local ICONS_PER_ROW = 6
local ICON_START_X = 0
local ICON_START_Y = 0

local iconFrames = {}

local anchorFrame = CreateFrame("Frame", "CCM_CustomSpellAnchorFrame", UIParent)
anchorFrame:SetSize(240, 60)
anchorFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0) -- Offset from main anchor
anchorFrame:EnableMouse(false)
anchorFrame:SetMovable(true)
anchorFrame:SetFrameStrata("TOOLTIP")
anchorFrame:RegisterForDrag("LeftButton")
anchorFrame:SetScript("OnDragStart", function(self)
    self:StartMoving()
    self:Show()
end)
anchorFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
end)
local anchorTex = anchorFrame:CreateTexture(nil, "BACKGROUND")
anchorTex:SetAllPoints(anchorFrame)
anchorTex:SetColorTexture(0, 0.8, 0, 0.15)
anchorTex:Hide()
anchorFrame:Hide()

-- Options panel for tracked spells

local function CreateTrackedSpellsOptionsPanel()
    local panel = CreateFrame("Frame", "CCM_TrackedSpellsPanel", UIParent)
    panel:SetSize(600, 400)
    panel.name = "CCM Tracked Spells"

    -- ScrollFrame setup
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -24, 4)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(560, 2200)
    scrollFrame:SetScrollChild(content)

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Tracked Custom Spells")
    local desc = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetWidth(550)
    desc:SetText("Configure which custom spells are tracked. Icons will show cooldowns and charges.")
    desc:SetJustifyH("LEFT")

    -- Unlock/Lock Button
    local moveButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    moveButton:SetSize(140, 22)
    moveButton:SetPoint("TOPRIGHT", content, "TOPRIGHT", -16, -16)
    moveButton:SetText("Unlock/Lock Icons")
    moveButton:SetScript("OnClick", function()
        local groups = CCM_TrackedSpellsSettings.groups or {}
        if not CCM_TrackedSpellsSettings.groupsMoving then
            CCM_TrackedSpellsSettings.groupsMoving = true
            for gIdx, group in ipairs(groups) do
                local anchorName = "CCM_GroupAnchorFrame"..gIdx
                local groupAnchor = _G[anchorName]
                if groupAnchor then
                    groupAnchor:EnableMouse(true)
                    groupAnchor:RegisterForDrag("LeftButton")
                    groupAnchor:SetMovable(true)
                    groupAnchor:SetScript("OnDragStart", function(self)
                        self:StartMoving()
                        self:Show()
                    end)
                    groupAnchor:SetScript("OnDragStop", function(self)
                        self:StopMovingOrSizing()
                        -- Save new position
                        local x, y = groupAnchor:GetCenter()
                        local uiParentX, uiParentY = UIParent:GetCenter()
                        group.placement = group.placement or {}
                        group.placement.x = math.floor((x or 0) - (uiParentX or 0))
                        group.placement.y = math.floor((y or 0) - (uiParentY or 0))
                        SaveSettings()
                    end)
                    groupAnchor:SetAlpha(1)
                    groupAnchor:Show()
                    -- Add green background texture if not present
                    if not groupAnchor.ccmGreenTex then
                        local tex = groupAnchor:CreateTexture(nil, "BACKGROUND")
                        tex:SetAllPoints(groupAnchor)
                        tex:SetColorTexture(0, 0.8, 0, 0.15)
                        groupAnchor.ccmGreenTex = tex
                    end
                    groupAnchor.ccmGreenTex:Show()
                end
            end
            print("[CCM] Drag each group anchor. Click again to lock.")
        else
            CCM_TrackedSpellsSettings.groupsMoving = false
            for gIdx, group in ipairs(groups) do
                local anchorName = "CCM_GroupAnchorFrame"..gIdx
                local groupAnchor = _G[anchorName]
                if groupAnchor then
                    groupAnchor:EnableMouse(false)
                    groupAnchor:SetAlpha(1)
                    groupAnchor._ccmUnlockInitialized = nil
                    if groupAnchor.ccmGreenTex then
                        groupAnchor.ccmGreenTex:Hide()
                    end
                end
            end
            SaveSettings()
            print("[CCM] All group anchors locked.")
        end
    end)

    local enableCheck = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
    enableCheck:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
    enableCheck.Text:SetText("Enable Custom Spell Tracking")
    enableCheck:SetChecked(CCM_TrackedSpellsSettings.enabled ~= false)
    enableCheck:SetScript("OnClick", function(self)
        CCM_TrackedSpellsSettings.enabled = self:GetChecked()
        SaveSettings()
        ReloadUI()
    end)

    -- Show in Combat Only Checkbox
    local combatOnlyCheck = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
    combatOnlyCheck:SetPoint("TOPLEFT", enableCheck, "BOTTOMLEFT", 0, 0)
    combatOnlyCheck.Text:SetText("Show Icons In Combat Only")
    combatOnlyCheck:SetChecked(CCM_TrackedSpellsSettings.showInCombatOnly == true)
    combatOnlyCheck:SetScript("OnClick", function(self)
        CCM_TrackedSpellsSettings.showInCombatOnly = self:GetChecked()
        SaveSettings()
        UpdateCustomSpellIcons()
    end)

    local spellInputLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    spellInputLabel:SetPoint("TOPLEFT", enableCheck, "BOTTOMLEFT", 0, -24)
    spellInputLabel:SetText("Add Spell ID or Name:")
    spellInputLabel:SetTextColor(1, 1, 1, 1)

    local spellInput = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    spellInput:SetSize(160, 20)
    spellInput:SetPoint("LEFT", spellInputLabel, "RIGHT", 8, 0)
    spellInput:SetAutoFocus(false)
    spellInput:SetText("")
    spellInput:SetMaxLetters(40)

    -- Group selection dropdown
    local groupDropdown = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate")
    groupDropdown:SetPoint("LEFT", spellInput, "RIGHT", 8, 0)
    groupDropdown:SetWidth(140)
    local selectedGroupIdx = 1
    local function EnsureMinimumGroups()
        local groups = CCM_TrackedSpellsSettings.groups or {}
        if #groups < 5 then
            for i = #groups + 1, 5 do
                table.insert(groups, {name = "Group "..i, spellIDs = {}})
            end
            CCM_TrackedSpellsSettings.groups = groups
            SaveSettings()
        end
    end

    local function RefreshGroupDropdown()
        EnsureMinimumGroups()
    end

    groupDropdown:SetupMenu(function(dd, rootDescription)
        EnsureMinimumGroups()
        local groups = CCM_TrackedSpellsSettings.groups or {}
        for idx, group in ipairs(groups) do
            local name = group.name or ("Group "..idx)
            rootDescription:CreateRadio(
                name,
                function() return selectedGroupIdx == idx end,
                function() selectedGroupIdx = idx end,
                idx
            )
        end
    end)
    RefreshGroupDropdown()


    local addButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    addButton:SetSize(60, 20)
    addButton:SetPoint("LEFT", groupDropdown, "RIGHT", 4, 0)
    addButton:SetText("Add")

    -- New Group button
    local newGroupButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    newGroupButton:SetSize(60, 20)
    newGroupButton:SetPoint("LEFT", addButton, "RIGHT", 8, 0)
    newGroupButton:SetText("New Group")
    newGroupButton:SetScript("OnClick", function()
        local groups = CCM_TrackedSpellsSettings.groups or {}
        local newIdx = #groups + 1
        table.insert(groups, {name = "Group "..newIdx, spellIDs = {}})
        CCM_TrackedSpellsSettings.groups = groups
        selectedGroupIdx = newIdx
        SaveSettings()
        UpdateSpellList()
        RefreshGroupDropdown()
    end)

    local spellListLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    spellListLabel:SetPoint("TOPLEFT", spellInputLabel, "BOTTOMLEFT", 0, -24)
    spellListLabel:SetText("Tracked Spell IDs:")
    spellListLabel:SetTextColor(1, 1, 1, 1)

    local resetSpellSizesTopButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetSpellSizesTopButton:SetSize(220, 20)
    resetSpellSizesTopButton:SetPoint("LEFT", spellListLabel, "RIGHT", 12, 0)
    resetSpellSizesTopButton:SetText("Reset Sizes (Selected Group)")
    resetSpellSizesTopButton:SetScript("OnClick", function()
        local groupsLocal = CCM_TrackedSpellsSettings.groups or {}
        local group = groupsLocal[selectedGroupIdx]
        if group then
            group.spellSizes = {}
            SaveSettings()
            UpdateSpellList()
            UpdateCustomSpellIcons()
        end
    end)

    local spellListFrame = CreateFrame("Frame", nil, content)
    spellListFrame:SetPoint("TOPLEFT", spellListLabel, "BOTTOMLEFT", 0, -8)
    spellListFrame:SetSize(540, 220)

    local spellListEntries = {}
    function UpdateSpellList()
        for _, entry in ipairs(spellListEntries) do
            if entry.ClearAllPoints then entry:ClearAllPoints() end
            entry:Hide()
        end
        wipe(spellListEntries)
        -- Show groups and their spell IDs
        local groups = CCM_TrackedSpellsSettings.groups or {}
        local yOffset = 0
        for gIdx, group in ipairs(groups) do
            local groupLabel = spellListFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            groupLabel:SetPoint("TOPLEFT", 0, -yOffset)
            groupLabel:SetText("Group " .. gIdx .. ": " .. (group.name or "Unnamed"))
            groupLabel:SetTextColor(0.8, 1, 0.8, 1)
            groupLabel:Show()
            table.insert(spellListEntries, groupLabel)
            yOffset = yOffset + 24
            for i, spellID in ipairs(group.spellIDs or {}) do
                local groupIndex = gIdx
                local spellIndex = i
                local entry = spellListFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                entry:SetPoint("TOPLEFT", 0, -yOffset)
                local name, _, _ = SafeGetSpellOrItemInfo(spellID)
                if name then
                    entry:SetText(string.format("%d: %s", spellID, name))
                else
                    entry:SetText(string.format("%d", spellID))
                end
                entry:SetTextColor(1, 1, 1, 1)

                -- Per-spell show count toggle
                local groupRef = groups[groupIndex]
                groupRef.spellShowCount = groupRef.spellShowCount or {}
                local toggleBtn = CreateFrame("Button", nil, spellListFrame, "UIPanelButtonTemplate")
                toggleBtn:SetSize(60, 18)
                toggleBtn:SetPoint("LEFT", entry, "RIGHT", 12, 0)
                local function updateToggleText()
                    local current = groupRef.spellShowCount[tostring(spellID)]
                    local showCount = (current == nil) or current -- default true
                    toggleBtn:SetText(showCount and "Count: On" or "Count: Off")
                end
                updateToggleText()
                toggleBtn:SetScript("OnClick", function()
                    local current = groupRef.spellShowCount[tostring(spellID)]
                    local showCount = (current == nil) or current -- default true
                    groupRef.spellShowCount[tostring(spellID)] = not showCount
                    -- Also update the live CCM_TrackedSpellsSettings.groups table
                    local liveGroups = CCM_TrackedSpellsSettings.groups or {}
                    if liveGroups[groupIndex] then
                        liveGroups[groupIndex].spellShowCount = liveGroups[groupIndex].spellShowCount or {}
                        liveGroups[groupIndex].spellShowCount[tostring(spellID)] = not showCount
                    end
                    updateToggleText()
                    SaveSettings()
                    UpdateCustomSpellIcons()
                end)

                local removeBtn = CreateFrame("Button", nil, spellListFrame, "UIPanelButtonTemplate")
                removeBtn:SetSize(40, 18)
                removeBtn:SetPoint("LEFT", toggleBtn, "RIGHT", 8, 0)
                removeBtn:SetText("Remove")
                removeBtn:SetScript("OnClick", function()
                    local groups = CCM_TrackedSpellsSettings.groups or {}
                    local groupRef = groups[groupIndex]
                    if groupRef and groupRef.spellIDs and groupRef.spellIDs[spellIndex] then
                        table.remove(groupRef.spellIDs, spellIndex)
                        if groupRef.spellShowCount then groupRef.spellShowCount[tostring(spellID)] = nil end
                        SaveSettings()
                        UpdateSpellList()
                        UpdateCustomSpellIcons()
                    end
                end)

                local upBtn = CreateFrame("Button", nil, spellListFrame, "UIPanelButtonTemplate")
                upBtn:SetSize(28, 18)
                upBtn:SetPoint("LEFT", removeBtn, "RIGHT", 8, 0)
                upBtn:SetText("Up")
                upBtn:SetScript("OnClick", function()
                    local groupsLocal = CCM_TrackedSpellsSettings.groups or {}
                    local groupRef = groupsLocal[groupIndex]
                    if groupRef and groupRef.spellIDs and spellIndex > 1 and groupRef.spellIDs[spellIndex - 1] then
                        groupRef.spellIDs[spellIndex], groupRef.spellIDs[spellIndex - 1] = groupRef.spellIDs[spellIndex - 1], groupRef.spellIDs[spellIndex]
                        SaveSettings()
                        UpdateSpellList()
                        UpdateCustomSpellIcons()
                    end
                end)

                local downBtn = CreateFrame("Button", nil, spellListFrame, "UIPanelButtonTemplate")
                downBtn:SetSize(28, 18)
                downBtn:SetPoint("LEFT", upBtn, "RIGHT", 6, 0)
                downBtn:SetText("Dn")
                downBtn:SetScript("OnClick", function()
                    local groupsLocal = CCM_TrackedSpellsSettings.groups or {}
                    local groupRef = groupsLocal[groupIndex]
                    if groupRef and groupRef.spellIDs and groupRef.spellIDs[spellIndex + 1] then
                        groupRef.spellIDs[spellIndex], groupRef.spellIDs[spellIndex + 1] = groupRef.spellIDs[spellIndex + 1], groupRef.spellIDs[spellIndex]
                        SaveSettings()
                        UpdateSpellList()
                        UpdateCustomSpellIcons()
                    end
                end)

                local dupBtn = CreateFrame("Button", nil, spellListFrame, "UIPanelButtonTemplate")
                dupBtn:SetSize(28, 18)
                dupBtn:SetPoint("LEFT", downBtn, "RIGHT", 6, 0)
                dupBtn:SetText("Dup")
                dupBtn:SetScript("OnClick", function()
                    local groupsLocal = CCM_TrackedSpellsSettings.groups or {}
                    local groupRef = groupsLocal[groupIndex]
                    if groupRef and groupRef.spellIDs then
                        table.insert(groupRef.spellIDs, spellIndex + 1, spellID)
                        SaveSettings()
                        UpdateSpellList()
                        UpdateCustomSpellIcons()
                    end
                end)

                local sizeSlider = CreateFrame("Slider", nil, spellListFrame, "OptionsSliderTemplate")
                sizeSlider:SetSize(90, 14)
                sizeSlider:SetPoint("LEFT", dupBtn, "RIGHT", 12, 0)
                sizeSlider:SetMinMaxValues(8, 200)
                sizeSlider:SetValueStep(1)
                sizeSlider:SetObeyStepOnDrag(true)

                local groupRef = groups[groupIndex]
                groupRef.spellSizes = groupRef.spellSizes or {}
                groupRef.spellOffsets = groupRef.spellOffsets or {}
                local sizeKey = tostring(spellID)
                local existingSize = tonumber(groupRef.spellSizes[sizeKey])
                local existingOffset = tonumber(groupRef.spellOffsets[sizeKey]) or 0
                local defaultSize = tonumber((groupRef.placement and groupRef.placement.iconSize) or CCM_TrackedSpellsSettings.iconSize or 40) or 40
                sizeSlider:SetValue(existingSize or defaultSize)

                local sizeValue = spellListFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                sizeValue:SetPoint("LEFT", sizeSlider, "RIGHT", 8, 0)
                sizeValue:SetText(tostring(existingSize or defaultSize))

                local sizeInput = CreateFrame("EditBox", nil, spellListFrame, "InputBoxTemplate")
                sizeInput:SetSize(38, 18)
                sizeInput:SetPoint("LEFT", sizeValue, "RIGHT", 8, 0)
                sizeInput:SetAutoFocus(false)
                sizeInput:SetMaxLetters(3)
                sizeInput:SetText(tostring(existingSize or defaultSize))

                local offsetLabel = spellListFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                offsetLabel:SetPoint("TOPLEFT", entry, "BOTTOMLEFT", 24, -8)
                offsetLabel:SetText("Up/Down")

                local offsetSlider = CreateFrame("Slider", nil, spellListFrame, "OptionsSliderTemplate")
                offsetSlider:SetSize(90, 14)
                offsetSlider:SetPoint("LEFT", offsetLabel, "RIGHT", 10, 0)
                offsetSlider:SetMinMaxValues(-500, 500)
                offsetSlider:SetValueStep(1)
                offsetSlider:SetObeyStepOnDrag(true)
                offsetSlider:SetValue(existingOffset)

                local offsetValue = spellListFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                offsetValue:SetPoint("LEFT", offsetSlider, "RIGHT", 8, 0)
                offsetValue:SetText(tostring(existingOffset))

                local offsetInput = CreateFrame("EditBox", nil, spellListFrame, "InputBoxTemplate")
                offsetInput:SetSize(42, 18)
                offsetInput:SetPoint("LEFT", offsetValue, "RIGHT", 8, 0)
                offsetInput:SetAutoFocus(false)
                offsetInput:SetMaxLetters(5)
                offsetInput:SetText(tostring(existingOffset))

                sizeSlider:SetScript("OnValueChanged", function(self, value)
                    if self._initializing then
                        return
                    end
                    local typed = math.floor((tonumber(value) or defaultSize) + 0.5)
                    local groupsLocal = CCM_TrackedSpellsSettings.groups or {}
                    local localGroup = groupsLocal[groupIndex]
                    if not localGroup then
                        return
                    end
                    localGroup.spellSizes = localGroup.spellSizes or {}
                    if typed and typed >= 8 and typed <= 200 then
                        localGroup.spellSizes[sizeKey] = math.floor(typed)
                        sizeValue:SetText(tostring(math.floor(typed)))
                        sizeInput:SetText(tostring(math.floor(typed)))
                    else
                        localGroup.spellSizes[sizeKey] = nil
                        sizeValue:SetText(tostring(defaultSize))
                        sizeInput:SetText(tostring(defaultSize))
                    end
                    SaveSettings()
                    UpdateCustomSpellIcons()
                end)

                offsetSlider:SetScript("OnValueChanged", function(self, value)
                    if self._initializing then
                        return
                    end
                    local typed = math.floor((tonumber(value) or 0) + 0.5)
                    local groupsLocal = CCM_TrackedSpellsSettings.groups or {}
                    local localGroup = groupsLocal[groupIndex]
                    if not localGroup then
                        return
                    end
                    localGroup.spellOffsets = localGroup.spellOffsets or {}
                    if typed ~= 0 then
                        localGroup.spellOffsets[sizeKey] = typed
                    else
                        localGroup.spellOffsets[sizeKey] = nil
                    end
                    offsetValue:SetText(tostring(typed))
                    offsetInput:SetText(tostring(typed))
                    SaveSettings()
                    UpdateCustomSpellIcons()
                end)

                local function ApplySizeInput()
                    local typed = tonumber(sizeInput:GetText() or "")
                    if not typed then
                        sizeInput:SetText(tostring(existingSize or defaultSize))
                        return
                    end
                    typed = math.floor(typed + 0.5)
                    if typed < 8 then typed = 8 end
                    if typed > 200 then typed = 200 end
                    sizeSlider:SetValue(typed)
                    sizeInput:ClearFocus()
                end
                sizeInput:SetScript("OnEnterPressed", ApplySizeInput)
                sizeInput:SetScript("OnEditFocusLost", ApplySizeInput)
                sizeInput:SetScript("OnEscapePressed", function(self)
                    self:SetText(tostring(existingSize or defaultSize))
                    self:ClearFocus()
                end)

                local function ApplyOffsetInput()
                    local typed = tonumber(offsetInput:GetText() or "")
                    if not typed then
                        offsetInput:SetText(tostring(existingOffset))
                        return
                    end
                    typed = math.floor(typed + 0.5)
                    if typed < -500 then typed = -500 end
                    if typed > 500 then typed = 500 end
                    offsetSlider:SetValue(typed)
                    offsetInput:ClearFocus()
                end
                offsetInput:SetScript("OnEnterPressed", ApplyOffsetInput)
                offsetInput:SetScript("OnEditFocusLost", ApplyOffsetInput)
                offsetInput:SetScript("OnEscapePressed", function(self)
                    self:SetText(tostring(existingOffset))
                    self:ClearFocus()
                end)

                sizeSlider._initializing = true
                sizeSlider:SetValue(existingSize or defaultSize)
                sizeSlider._initializing = nil

                offsetSlider._initializing = true
                offsetSlider:SetValue(existingOffset)
                offsetSlider._initializing = nil

                removeBtn:Show()
                upBtn:Show()
                downBtn:Show()
                dupBtn:Show()
                sizeSlider:Show()
                sizeValue:Show()
                sizeInput:Show()
                offsetLabel:Show()
                offsetSlider:Show()
                offsetValue:Show()
                offsetInput:Show()
                entry:Show()
                table.insert(spellListEntries, entry)
                table.insert(spellListEntries, toggleBtn)
                table.insert(spellListEntries, removeBtn)
                table.insert(spellListEntries, upBtn)
                table.insert(spellListEntries, downBtn)
                table.insert(spellListEntries, dupBtn)
                table.insert(spellListEntries, sizeSlider)
                table.insert(spellListEntries, sizeValue)
                table.insert(spellListEntries, sizeInput)
                table.insert(spellListEntries, offsetLabel)
                table.insert(spellListEntries, offsetSlider)
                table.insert(spellListEntries, offsetValue)
                table.insert(spellListEntries, offsetInput)
                yOffset = yOffset + 52
            end
        end
        spellListFrame:SetHeight(math.max(220, yOffset + 12))
    end
    addButton:SetScript("OnClick", function()
        local text = (spellInput:GetText() or ""):match("^%s*(.-)%s*$")
        if text == "" then return end
        local val = tonumber(text)
        if not val then
            -- Try resolving spell name to ID (English names)
            if C_Spell and C_Spell.GetSpellInfo then
                local info = C_Spell.GetSpellInfo(text)
                if info and info.spellID then
                    val = info.spellID
                end
            end
            if not val then
                print("|cffff4444[CCM]|r Could not find spell: " .. text)
                return
            end
        end
        local groups = CCM_TrackedSpellsSettings.groups or {}
        if #groups == 0 then
            table.insert(groups, {name="Group 1", spellIDs={}})
        end
        local idx = selectedGroupIdx or 1
        if not groups[idx] then idx = 1 end
        table.insert(groups[idx].spellIDs, val)
        CCM_TrackedSpellsSettings.groups = groups
        spellInput:SetText("")
        SaveSettings()
        local ok, err = pcall(UpdateSpellList)
        if not ok then print("|cffff4444[CCM]|r Spell list refresh error: " .. tostring(err)) end
        UpdateCustomSpellIcons()
    end)


    local autoButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    autoButton:SetSize(120, 22)
    autoButton:SetPoint("TOPLEFT", spellListFrame, "BOTTOMLEFT", 0, -16)
    autoButton:SetText("Scan Spellbook")
    autoButton:SetScript("OnClick", function()
        AutoPopulateTrackedSpells()
    end)

    -- Refresh Spells List button
    local refreshButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    refreshButton:SetSize(140, 22)
    refreshButton:SetPoint("LEFT", autoButton, "RIGHT", 12, 0)
    refreshButton:SetText("Refresh Spells List")
    refreshButton:SetScript("OnClick", function()
        -- Reload settings for the current spec, re-scan spellbook, and update the UI
        if LoadSettings then LoadSettings() end
        AutoPopulateTrackedSpells()
        if UpdateSpellList then UpdateSpellList() end
        if UpdateCustomSpellIcons then UpdateCustomSpellIcons() end
        print("[CCM] Spells list refreshed for current spec.")
    end)

    local iconSizeSlider = CreateSlider(content, "Icon Size", 20, 100, 1, CCM_TrackedSpellsSettings.iconSize, function(v)
        CCM_TrackedSpellsSettings.iconSize = v
        SaveSettings()
        UpdateCustomSpellIcons()
    end)
    iconSizeSlider:SetPoint("TOPLEFT", autoButton, "BOTTOMLEFT", 0, -24)

    local spacingSlider = CreateSlider(content, "Icon Spacing", 0, 50, 1, CCM_TrackedSpellsSettings.spacing, function(v)
        CCM_TrackedSpellsSettings.spacing = v
        SaveSettings()
        UpdateCustomSpellIcons()
    end)
    spacingSlider:SetPoint("TOPLEFT", iconSizeSlider, "BOTTOMLEFT", 0, -40)

    local directions = {"RIGHT", "LEFT", "UP", "DOWN"}
    local directionDropdown = CreateDropdown(content, "Growth Direction", directions, CCM_TrackedSpellsSettings.direction, function(opt)
        CCM_TrackedSpellsSettings.direction = opt
        SaveSettings()
        UpdateCustomSpellIcons()
    end)
    directionDropdown:SetPoint("TOPLEFT", spacingSlider, "BOTTOMLEFT", 0, -40)

    local positions = {"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT"}
    local chargeDropdown = CreateDropdown(content, "Charge/Stack Position", positions, CCM_TrackedSpellsSettings.chargePosition, function(opt)
        CCM_TrackedSpellsSettings.chargePosition = opt
        SaveSettings()
        UpdateCustomSpellIcons()
    end)
    chargeDropdown:SetPoint("TOPLEFT", directionDropdown, "BOTTOMLEFT", 0, -40)

        -- Columns Slider (per-group)
        local function getSelectedGroup()
            local groups = CCM_TrackedSpellsSettings.groups or {}
            return groups[selectedGroupIdx]
        end
        local function getSelectedGroupIconsPerRow()
            local group = getSelectedGroup()
            return (group and group.placement and group.placement.columns) or CCM_TrackedSpellsSettings.columns or 6
        end
        local function getSelectedGroupIconSize()
            local group = getSelectedGroup()
            return (group and group.placement and group.placement.iconSize) or CCM_TrackedSpellsSettings.iconSize or 40
        end
        local iconsPerRowSlider = CreateSlider(content, "Icons Per Row", 1, 20, 1, getSelectedGroupIconsPerRow(), function(v)
            local group = getSelectedGroup()
            if group then
                group.placement = group.placement or {}
                group.placement.columns = v
            else
                CCM_TrackedSpellsSettings.columns = v
            end
            SaveSettings()
            UpdateCustomSpellIcons()
        end)
        iconsPerRowSlider:SetPoint("TOPLEFT", chargeDropdown, "BOTTOMLEFT", 0, -40)

        local groupIconSizeSlider = CreateSlider(content, "Group Icon Size", 8, 200, 1, getSelectedGroupIconSize(), function(v)
            local group = getSelectedGroup()
            if group then
                group.placement = group.placement or {}
                group.placement.iconSize = v
            else
                CCM_TrackedSpellsSettings.iconSize = v
            end
            SaveSettings()
            UpdateCustomSpellIcons()
        end)
        groupIconSizeSlider:SetPoint("TOPLEFT", iconsPerRowSlider, "BOTTOMLEFT", 0, -40)

        local resetSpellSizesButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        resetSpellSizesButton:SetSize(220, 22)
        resetSpellSizesButton:SetPoint("TOPLEFT", groupIconSizeSlider, "BOTTOMLEFT", 0, -12)
        resetSpellSizesButton:SetText("Reset Spell Sizes (Group)")
        resetSpellSizesButton:SetScript("OnClick", function()
            local group = getSelectedGroup()
            if group then
                group.spellSizes = {}
                group.spellOffsets = {}
                SaveSettings()
                UpdateSpellList()
                UpdateCustomSpellIcons()
            end
        end)

        -- Update icons per row slider value when group changes
        local oldRefreshGroupDropdown = RefreshGroupDropdown
        function RefreshGroupDropdown()
            oldRefreshGroupDropdown()
            if iconsPerRowSlider and iconsPerRowSlider.SetValue then
                iconsPerRowSlider:SetValue(getSelectedGroupIconsPerRow())
            end
            if groupIconSizeSlider and groupIconSizeSlider.SetValue then
                groupIconSizeSlider:SetValue(getSelectedGroupIconSize())
            end
        end

        -- Charge Text Size Slider
        local chargeTextSizeSlider = CreateSlider(content, "Charge Text Size", 8, 32, 1, CCM_TrackedSpellsSettings.chargeTextSize or 14, function(v)
            CCM_TrackedSpellsSettings.chargeTextSize = v
            SaveSettings()
            UpdateCustomSpellIcons()
        end)
        chargeTextSizeSlider:SetPoint("TOPLEFT", resetSpellSizesButton, "BOTTOMLEFT", 0, -24)

        -- Charge Text X Slider
        local chargeTextXSlider = CreateSlider(content, "Charge Text X", -200, 200, 1, CCM_TrackedSpellsSettings.chargeTextX or 0, function(v)
            CCM_TrackedSpellsSettings.chargeTextX = v
            SaveSettings()
            UpdateCustomSpellIcons()
        end)
        chargeTextXSlider:SetPoint("TOPLEFT", chargeTextSizeSlider, "BOTTOMLEFT", 0, -40)

        -- Charge Text Y Slider
        local chargeTextYSlider = CreateSlider(content, "Charge Text Y", -200, 200, 1, CCM_TrackedSpellsSettings.chargeTextY or 0, function(v)
            CCM_TrackedSpellsSettings.chargeTextY = v
            SaveSettings()
            UpdateCustomSpellIcons()
        end)
        chargeTextYSlider:SetPoint("TOPLEFT", chargeTextXSlider, "BOTTOMLEFT", 0, -40)

      
    UpdateSpellList()
    RefreshGroupDropdown()

    _G.CCM_TrackedSpellsPanel = panel
    if InterfaceOptions_AddCategory and not panel._addedToOptions then
        InterfaceOptions_AddCategory(panel)
        panel._addedToOptions = true
    end
end

SLASH_CUSTOMSPELLMOVE1 = "/customspellmove"
SlashCmdList["CUSTOMSPELLMOVE"] = function()
    if not anchorFrame.moving then
        anchorFrame:EnableMouse(true)
        anchorFrame:Show()
        anchorTex:Show()
        anchorFrame:SetAlpha(1)
        print("[CCM] Drag custom spell icons. Type /customspellmove again to lock.")
        anchorFrame.moving = true
    else
        anchorFrame:EnableMouse(false)
        anchorTex:Hide()
        anchorFrame:Hide()
        anchorFrame.moving = false
        print("[CCM] Custom spell icons locked.")
    end
end

local function CreateOrGetIconFrame(index)
    if not iconFrames[index] then
        local frame = CreateFrame("Frame", nil, UIParent)
        frame:SetSize(ICON_SIZE, ICON_SIZE)
        frame:SetFrameStrata("MEDIUM")
        frame.texture = frame:CreateTexture(nil, "ARTWORK")
        frame.texture:SetAllPoints()
        -- ElvUI-style icon crop
        frame.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
        frame.cooldown:SetAllPoints(frame)
        frame.cooldown:SetDrawSwipe(true)
        frame.cooldown:SetDrawBling(true)
        frame.cooldown:SetHideCountdownNumbers(false)
        frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        frame.count:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
        frame.count:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
        -- Add 1-pixel black border using four overlay textures
        if not frame.pixelBorders then
            frame.pixelBorders = {}
            -- Top
            local top = frame:CreateTexture(nil, "OVERLAY")
            top:SetColorTexture(0, 0, 0, 1)
            top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
            top:SetHeight(1)
            frame.pixelBorders.top = top
            -- Bottom
            local bottom = frame:CreateTexture(nil, "OVERLAY")
            bottom:SetColorTexture(0, 0, 0, 1)
            bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
            bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
            bottom:SetHeight(1)
            frame.pixelBorders.bottom = bottom
            -- Left
            local leftB = frame:CreateTexture(nil, "OVERLAY")
            leftB:SetColorTexture(0, 0, 0, 1)
            leftB:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
            leftB:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
            leftB:SetWidth(1)
            frame.pixelBorders.left = leftB
            -- Right
            local rightB = frame:CreateTexture(nil, "OVERLAY")
            rightB:SetColorTexture(0, 0, 0, 1)
            rightB:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
            rightB:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
            rightB:SetWidth(1)
            frame.pixelBorders.right = rightB
        end
        for _, border in pairs(frame.pixelBorders) do border:Show() end
        -- Add shadow texture if not present
        if not frame.shadow then
            local shadow = frame:CreateTexture(nil, "BACKGROUND")
            shadow:SetTexture("Interface\\BUTTONS\\UI-Quickslot-Depress")
            shadow:SetAllPoints(frame)
            shadow:SetVertexColor(0, 0, 0, 0.6)
            frame.shadow = shadow
        end
        frame:Hide()
        iconFrames[index] = frame
    end
    return iconFrames[index]
end

local function ShowIconAt(frame, x, y)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", anchorFrame, "CENTER", x, y)
    frame:Show()
end

local function GetSafeCastCountText(castCount)
    if castCount == nil then
        return nil
    end

    -- Try to treat as a number first to avoid taint
    local n = tonumber(castCount)
    if n then
        return tostring(n)
    end

    -- Fallback: try tostring, but do not compare tainted strings
    local okToString, text = pcall(tostring, castCount)
    if okToString and text then
        local okNum = tonumber(text)
        if okNum then
            return tostring(okNum)
        elseif text ~= "" then
            return text
        end
    end
    return nil
end

function UpdateCustomSpellIcons()
    -- Check if tracking is disabled
    if CCM_TrackedSpellsSettings.enabled == false then
        for i = 1, #iconFrames do
            iconFrames[i]:Hide()
        end
        -- Hide group anchors too
        for gIdx = 1, 20 do
            local ga = _G["CCM_GroupAnchorFrame"..gIdx]
            if ga then ga:Hide() end
        end
        anchorFrame:Hide()
        return
    end
    -- Hide icons out of combat if option is enabled
    if CCM_TrackedSpellsSettings.showInCombatOnly and not InCombatLockdown() then
        for i = 1, #iconFrames do
            iconFrames[i]:Hide()
        end
        for gIdx = 1, 20 do
            local ga = _G["CCM_GroupAnchorFrame"..gIdx]
            if ga then ga:Hide() end
        end
        anchorFrame:Hide()
        return
    end

    local index = 1
    local spells = FindPlayerCustomSpells()
    local totalIcons = #spells
    local columns = CCM_TrackedSpellsSettings.columns or 6
    local iconSize = CCM_TrackedSpellsSettings.iconSize or 40
    local iconSpacing = CCM_TrackedSpellsSettings.spacing or 10
    local direction = CCM_TrackedSpellsSettings.direction or "RIGHT"
    local chargePosition = CCM_TrackedSpellsSettings.chargePosition or "BOTTOMRIGHT"
    local cooldownTextSize = CCM_TrackedSpellsSettings.cooldownTextSize or 14
    local cooldownTextX = CCM_TrackedSpellsSettings.cooldownTextX or 0
    local cooldownTextY = CCM_TrackedSpellsSettings.cooldownTextY or 0
    local chargeTextSize = CCM_TrackedSpellsSettings.chargeTextSize or 14
    local chargeTextX = CCM_TrackedSpellsSettings.chargeTextX or 0
    local chargeTextY = CCM_TrackedSpellsSettings.chargeTextY or 0

    -- Render icons for each group
    local groups = CCM_TrackedSpellsSettings.groups or {}
    local iconIdx = 1
    for gIdx, group in ipairs(groups) do
        -- Placement settings per group
        local anchorX = group.placement and group.placement.x or 0
        local anchorY = group.placement and group.placement.y or (-80 * (gIdx-1))
        local anchorName = "CCM_GroupAnchorFrame"..gIdx
        local groupAnchor = _G[anchorName]
        if not groupAnchor then
            groupAnchor = CreateFrame("Frame", anchorName, UIParent)
            groupAnchor:SetSize(240, 60)
            groupAnchor:SetFrameStrata("MEDIUM")
            -- Add green background texture
            local tex = groupAnchor:CreateTexture(nil, "BACKGROUND")
            tex:SetAllPoints(groupAnchor)
            tex:SetColorTexture(0, 0, 0, 0.9)
            groupAnchor.ccmGreenTex = tex
            tex:Hide()
        end
        -- Always create and position border (if not present)
        if not groupAnchor.ccmBorder then
            groupAnchor.ccmBorder = {}
            local border = groupAnchor.ccmBorder
            -- Top
            border.top = groupAnchor:CreateTexture(nil, "ARTWORK")
            border.top:SetColorTexture(0, 0, 0, 1)
            border.top:SetDrawLayer("ARTWORK", 7)
            border.top:SetPoint("TOPLEFT", groupAnchor, "TOPLEFT", 0, 0)
            border.top:SetPoint("TOPRIGHT", groupAnchor, "TOPRIGHT", 0, 0)
            border.top:SetHeight(2)
            border.top:Hide()
            -- Bottom
            border.bottom = groupAnchor:CreateTexture(nil, "ARTWORK")
            border.bottom:SetColorTexture(0, 0, 0, 1)
            border.bottom:SetDrawLayer("ARTWORK", 7)
            border.bottom:SetPoint("BOTTOMLEFT", groupAnchor, "BOTTOMLEFT", 0, 0)
            border.bottom:SetPoint("BOTTOMRIGHT", groupAnchor, "BOTTOMRIGHT", 0, 0)
            border.bottom:SetHeight(2)
            border.bottom:Hide()
            -- Left
            border.left = groupAnchor:CreateTexture(nil, "ARTWORK")
            border.left:SetColorTexture(0, 0, 0, 1)
            border.left:SetDrawLayer("ARTWORK", 7)
            border.left:SetPoint("TOPLEFT", groupAnchor, "TOPLEFT", 0, 0)
            border.left:SetPoint("BOTTOMLEFT", groupAnchor, "BOTTOMLEFT", 0, 0)
            border.left:SetWidth(2)
            border.left:Hide()
            -- Right
            border.right = groupAnchor:CreateTexture(nil, "ARTWORK")
            border.right:SetColorTexture(0, 0, 0, 1)
            border.right:SetDrawLayer("ARTWORK", 7)
            border.right:SetPoint("TOPRIGHT", groupAnchor, "TOPRIGHT", 0, 0)
            border.right:SetPoint("BOTTOMRIGHT", groupAnchor, "BOTTOMRIGHT", 0, 0)
            border.right:SetWidth(2)
            border.right:Hide()
        end
        if not CCM_TrackedSpellsSettings.groupsMoving then
            groupAnchor:ClearAllPoints()
            groupAnchor:SetPoint("CENTER", UIParent, "CENTER", anchorX, anchorY)
        elseif not groupAnchor._ccmUnlockInitialized then
            groupAnchor:ClearAllPoints()
            groupAnchor:SetPoint("CENTER", UIParent, "CENTER", anchorX, anchorY)
            groupAnchor._ccmUnlockInitialized = true
        end
        groupAnchor:Show()
        -- Show/hide green background and group number based on unlock state
            if CCM_TrackedSpellsSettings.groupsMoving then
                if groupAnchor.ccmGreenTex then groupAnchor.ccmGreenTex:Show() end
                if groupAnchor.ccmBorder then
                    for _, side in pairs(groupAnchor.ccmBorder) do
                        side:ClearAllPoints()
                        side:Hide()
                        side:SetColorTexture(0, 0, 0, 1)
                        side:SetAlpha(1)
                        side:SetDrawLayer("ARTWORK", 7)
                    end
                    -- Re-anchor in case frame size changes
                    groupAnchor.ccmBorder.top:SetPoint("TOPLEFT", groupAnchor, "TOPLEFT", 0, 0)
                    groupAnchor.ccmBorder.top:SetPoint("TOPRIGHT", groupAnchor, "TOPRIGHT", 0, 0)
                    groupAnchor.ccmBorder.top:SetHeight(2)
                    groupAnchor.ccmBorder.bottom:SetPoint("BOTTOMLEFT", groupAnchor, "BOTTOMLEFT", 0, 0)
                    groupAnchor.ccmBorder.bottom:SetPoint("BOTTOMRIGHT", groupAnchor, "BOTTOMRIGHT", 0, 0)
                    groupAnchor.ccmBorder.bottom:SetHeight(2)
                    groupAnchor.ccmBorder.left:SetPoint("TOPLEFT", groupAnchor, "TOPLEFT", 0, 0)
                    groupAnchor.ccmBorder.left:SetPoint("BOTTOMLEFT", groupAnchor, "BOTTOMLEFT", 0, 0)
                    groupAnchor.ccmBorder.left:SetWidth(2)
                    groupAnchor.ccmBorder.right:SetPoint("TOPRIGHT", groupAnchor, "TOPRIGHT", 0, 0)
                    groupAnchor.ccmBorder.right:SetPoint("BOTTOMRIGHT", groupAnchor, "BOTTOMRIGHT", 0, 0)
                    groupAnchor.ccmBorder.right:SetWidth(2)
                    for _, side in pairs(groupAnchor.ccmBorder) do side:Show() end
                end
            else
                if groupAnchor.ccmGreenTex then groupAnchor.ccmGreenTex:Hide() end
                if groupAnchor.ccmBorder then
                    for _, side in pairs(groupAnchor.ccmBorder) do side:Hide() end
                end
            end
        for i, id in ipairs(group.spellIDs or {}) do
            local isKnown = true
            local name, icon, spellType = SafeGetSpellOrItemInfo(id)
            if spellType == "spell" and IsSpellKnown and not IsSpellKnown(id) then
                isKnown = false
            end
            if isKnown then
                local frame = CreateOrGetIconFrame(iconIdx)
                local groupPlacement = group.placement or {}
                local baseIconSize = tonumber(groupPlacement.iconSize) or iconSize
                local spellSizes = group.spellSizes or {}
                local spellOffsets = group.spellOffsets or {}
                local spellIconSize = tonumber(spellSizes[tostring(id)]) or baseIconSize
                local spellYOffset = tonumber(spellOffsets[tostring(id)]) or 0
                frame:SetSize(spellIconSize, spellIconSize)
                local showCount = true
                if group.spellShowCount and group.spellShowCount[tostring(id)] ~= nil then
                    showCount = group.spellShowCount[tostring(id)]
                end
                if not icon then
                    frame.texture:SetTexture("Interface\\Icons\\inv_misc_questionmark")
                    frame.count:SetText("")
                    frame.cooldown:Clear()
                else
                    frame.texture:SetTexture(icon)
                    -- Ensure cooldown frame displays timer text and swipe (matches TrinketRacials)
                    frame.cooldown:SetDrawSwipe(true)
                    frame.cooldown:SetSwipeColor(0, 0, 0, 0.8)
                    frame.cooldown:SetDrawBling(true)
                    frame.cooldown:SetHideCountdownNumbers(false)

                    -- Priority: if spell has an active aura/buff on player, show aura duration
                    -- Otherwise fall back to spell cooldown
                    local auraShown = false
                    if spellType == "spell" and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
                        local auraData = C_UnitAuras.GetPlayerAuraBySpellID(id)
                        if auraData and auraData.auraInstanceID and auraData.duration and auraData.duration > 0 then
                            -- Use durationObject API (secret-safe, works in combat)
                            local durObj = C_UnitAuras.GetAuraDuration and C_UnitAuras.GetAuraDuration("player", auraData.auraInstanceID)
                            if durObj then
                                frame.cooldown:SetCooldownFromDurationObject(durObj)
                            else
                                -- Fallback for older clients without GetAuraDuration
                                local ok = pcall(frame.cooldown.SetCooldown, frame.cooldown, auraData.expirationTime - auraData.duration, auraData.duration)
                                if not ok then frame.cooldown:Clear() end
                            end
                            auraShown = true
                            -- Show stack count from aura if available
                            if showCount and auraData.applications and auraData.applications > 1 then
                                frame.count:SetText(tostring(auraData.applications))
                            elseif showCount then
                                -- Still show charges or cast count below
                            end
                        end
                    end

                    if showCount then
                        if spellType == "spell" then
                            local chargesInfo = C_Spell and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(id)
                            if chargesInfo then
                                -- currentCharges is NOT secret (directly)
                                local charges = chargesInfo.currentCharges
                                if charges ~= nil then
                                    frame.count:SetText(tostring(charges))
                                else
                                    frame.count:SetText("")
                                end
                                if not auraShown then
                                    local chargeDurObj = C_Spell and C_Spell.GetSpellChargeDuration and C_Spell.GetSpellChargeDuration(id)
                                    if chargeDurObj then
                                        frame.cooldown:SetCooldownFromDurationObject(chargeDurObj)
                                    else
                                        frame.cooldown:Clear()
                                    end
                                end
                            else
                                if not auraShown then
                                    local durObj = C_Spell and C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(id)
                                    local cdInfo = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(id)
                                    if durObj and cdInfo and cdInfo.isOnGCD ~= true then
                                        frame.cooldown:SetCooldownFromDurationObject(durObj)
                                    else
                                        frame.cooldown:Clear()
                                    end
                                end
                                -- GetSpellCastCount may return secret — SetText accepts it
                                local castCount = C_Spell and C_Spell.GetSpellCastCount and C_Spell.GetSpellCastCount(id)
                                if castCount ~= nil then
                                    frame.count:SetText(castCount)
                                else
                                    frame.count:SetText("")
                                end
                            end
                        elseif spellType == "item" then
                            local count = GetItemCount and GetItemCount(id) or 0
                            frame.count:SetText(count > 1 and count or "")
                            if not auraShown then
                                local start, duration, enable = GetItemCooldown and GetItemCooldown(id)
                                if enable and duration and duration > 1.5 then
                                    if not pcall(frame.cooldown.SetCooldown, frame.cooldown, start, duration) then
                                        frame.cooldown:Clear()
                                    end
                                else
                                    frame.cooldown:Clear()
                                end
                            end
                        end
                    else
                        frame.count:SetText("")
                        if not auraShown then
                            -- Show cooldown overlay even if count is hidden
                            if spellType == "spell" then
                                local chargesInfo = C_Spell and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(id)
                                if chargesInfo then
                                    local chargeDurObj = C_Spell and C_Spell.GetSpellChargeDuration and C_Spell.GetSpellChargeDuration(id)
                                    if chargeDurObj then
                                        frame.cooldown:SetCooldownFromDurationObject(chargeDurObj)
                                    else
                                        frame.cooldown:Clear()
                                    end
                                else
                                    local durObj = C_Spell and C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(id)
                                    local cdInfo = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(id)
                                    if durObj and cdInfo and cdInfo.isOnGCD ~= true then
                                        frame.cooldown:SetCooldownFromDurationObject(durObj)
                                    else
                                        frame.cooldown:Clear()
                                    end
                                end
                            elseif spellType == "item" then
                                local start, duration, enable = GetItemCooldown and GetItemCooldown(id)
                                if enable and duration and duration > 1.5 then
                                    if not pcall(frame.cooldown.SetCooldown, frame.cooldown, start, duration) then
                                        frame.cooldown:Clear()
                                    end
                                else
                                    frame.cooldown:Clear()
                                end
                            end
                        end
                    end
                end
                -- Position icon based on columns and direction
                local columns = group.placement and group.placement.columns or columns
                columns = math.max(1, math.floor(tonumber(columns) or 1))
                local iconSpacing = group.placement and group.placement.spacing or iconSpacing
                local iconSize = baseIconSize
                local direction = group.placement and group.placement.direction or direction
                local chargePosition = group.placement and group.placement.chargePosition or chargePosition
                local chargeTextSize = group.placement and group.placement.chargeTextSize or chargeTextSize
                local chargeTextX = group.placement and group.placement.chargeTextX or chargeTextX
                local chargeTextY = group.placement and group.placement.chargeTextY or chargeTextY

                local row, col, x, y
                -- Center each row/column
                local totalIcons = #(group.spellIDs or {})
                if direction == "RIGHT" or direction == "LEFT" then
                    row = math.floor((i - 1) / columns)
                    col = (i - 1) % columns
                    -- How many icons in this row?
                    local iconsInRow = math.min(columns, totalIcons - row * columns)
                    local rowWidth = (iconsInRow - 1) * (iconSize + iconSpacing)
                    local xOffset = -rowWidth / 2
                    if direction == "RIGHT" then
                        x = col * (iconSize + iconSpacing) + xOffset
                        y = 0 - row * (iconSize + iconSpacing)
                    else -- LEFT
                        x = -col * (iconSize + iconSpacing) - xOffset
                        y = 0 - row * (iconSize + iconSpacing)
                    end
                elseif direction == "DOWN" or direction == "UP" then
                    col = math.floor((i - 1) / columns)
                    row = (i - 1) % columns
                    -- How many icons in this column?
                    local iconsInCol = math.min(columns, totalIcons - col * columns)
                    local colHeight = (iconsInCol - 1) * (iconSize + iconSpacing)
                    local yOffset = -colHeight / 2
                    if direction == "DOWN" then
                        x = 0 + col * (iconSize + iconSpacing)
                        y = -row * (iconSize + iconSpacing) + yOffset
                    else -- UP
                        x = 0 + col * (iconSize + iconSpacing)
                        y = row * (iconSize + iconSpacing) - yOffset
                    end
                else
                    -- fallback to RIGHT
                    row = math.floor((i - 1) / columns)
                    col = (i - 1) % columns
                    local iconsInRow = math.min(columns, totalIcons - row * columns)
                    local rowWidth = (iconsInRow - 1) * (iconSize + iconSpacing)
                    local xOffset = -rowWidth / 2
                    x = col * (iconSize + iconSpacing) + xOffset
                    y = 0 - row * (iconSize + iconSpacing)
                end

                frame:ClearAllPoints()
                frame:SetPoint("CENTER", groupAnchor, "CENTER", x, y + spellYOffset)
                frame:Show()
                frame.count:SetFont(STANDARD_TEXT_FONT, chargeTextSize, "OUTLINE")
                frame.count:ClearAllPoints()
                frame.count:SetPoint(chargePosition, frame, chargePosition, chargeTextX, chargeTextY)
                iconIdx = iconIdx + 1
            end
        end
    end
    for i = iconIdx, #iconFrames do
        iconFrames[i]:Hide()
    end
    -- Show/hide anchorFrame for legacy
    if iconIdx > 1 then
        anchorFrame:Show()
    else
        anchorFrame:Hide()
    end
end


local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")

-- Tracking events only registered when enabled (saves CPU/FPS when disabled)
local trackingEventsRegistered = false
local function RegisterTrackingEvents()
    if trackingEventsRegistered then return end
    trackingEventsRegistered = true
    eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    eventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
    eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
end
local function UnregisterTrackingEvents()
    if not trackingEventsRegistered then return end
    trackingEventsRegistered = false
    eventFrame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
    eventFrame:UnregisterEvent("SPELL_UPDATE_CHARGES")
    eventFrame:UnregisterEvent("UNIT_AURA")
end

-- Register if currently enabled
if CCM_TrackedSpellsSettings.enabled ~= false then
    RegisterTrackingEvents()
end

-- Show/hide dispatch frame for cooldown updates (zero CPU when idle, no closure allocation)
local dispatchFrame = CreateFrame("Frame")
dispatchFrame:Hide()
dispatchFrame._lastRun = 0
dispatchFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    local now = GetTime()
    if now - self._lastRun < 0.5 then return end
    self._lastRun = now
    UpdateCustomSpellIcons()
end)

local function ThrottledUpdate()
    dispatchFrame:Show() -- coalesces multiple events into one dispatch next frame
end

local function OnSpecOrTalentChange()
    LoadSettings()
    if CCM_TrackedSpellsSettings.enabled == false then
        UnregisterTrackingEvents()
    else
        RegisterTrackingEvents()
    end
    UpdateCustomSpellIcons()
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_TALENT_GROUP_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
        OnSpecOrTalentChange()
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        UpdateCustomSpellIcons()
    elseif event == "UNIT_AURA" or event == "SPELL_UPDATE_CHARGES" then
        -- Aura stack changes + charge changes: update immediately in combat
        -- (throttle can delay stale display by 0.5s which feels broken)
        UpdateCustomSpellIcons()
    else
        ThrottledUpdate()
    end
end)

local loginInitFrame = CreateFrame("Frame")
loginInitFrame:RegisterEvent("PLAYER_LOGIN")
local didInit = false
local function ThrottledInit()
    if didInit then return end
    didInit = true
    LoadSettings()
    UpdateCustomSpellIcons()
end
loginInitFrame:SetScript("OnEvent", function()
    C_Timer.After(0, ThrottledInit)
end)

_G.CCM_TrackedSpells = _G.CCM_TrackedSpells or {}
_G.CCM_TrackedSpells.UpdateCustomSpellIcons = UpdateCustomSpellIcons
_G.CCM_TrackedSpells.CreateTrackedSpellsOptionsPanel = CreateTrackedSpellsOptionsPanel

-- SafeGetSpellOrItemInfo is defined at the top of the file
