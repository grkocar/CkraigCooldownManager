    -- luacheck: globals GetSpellInfo GetNumSpellBookSlots GetSpellBookItemID GetSpellBookItemName GetSpellBookItemTexture IsSpellKnown GetItemInfo GetItemCount GetItemCooldown CreateFrame UIParent C_Timer print select pairs ipairs STANDARD_TEXT_FONT
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
-- luacheck: globals GetSpellInfo GetNumSpellBookSlots GetSpellBookItemID GetSpellBookItemName GetSpellBookItemTexture

-- Spell/item info lookup — delegate to centralised CCM.Utils version (Helpers.lua)
local CCM = _G.CkraigCooldownManager
local SafeGetSpellOrItemInfo = CCM.Utils.SafeGetSpellOrItemInfo
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

    -- Delegate to centralised CCM.Utils.DeepCopy (Helpers.lua)
    local DeepCopyTable = _G.CkraigCooldownManager.Utils.DeepCopy

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


-- Integration with Blizzard CooldownViewer for bars
local function AddSpellToCooldownViewer(spellID)
    if C_CooldownViewer and C_CooldownViewer.AddTrackedCooldown then
        local ok, err = pcall(C_CooldownViewer.AddTrackedCooldown, spellID)
        if not ok then
            print("[CCM] Failed to add spell", spellID, "to cooldown viewer:", err)
        end
    end
end

local function RemoveSpellFromCooldownViewer(spellID)
    if C_CooldownViewer and C_CooldownViewer.RemoveTrackedCooldown then
        local ok, err = pcall(C_CooldownViewer.RemoveTrackedCooldown, spellID)
        if not ok then
            print("[CCM] Failed to remove spell", spellID, "from cooldown viewer:", err)
        end
    end
end

local function SyncAllSpellsToCooldownViewer()
    local groups = CCM_TrackedSpellsSettings and CCM_TrackedSpellsSettings.groups or {}
    for _, group in ipairs(groups) do
        for _, spellID in ipairs(group.spellIDs or {}) do
            AddSpellToCooldownViewer(spellID)
        end
    end
end


-- Auto-populate tracked spells from spellbook for current spec/class
local function AutoPopulateTrackedSpells()
    local class, _ = UnitClass("player")
    local specIndex = GetSpecialization and GetSpecialization()
    local specName = specIndex and select(2, GetSpecializationInfo(specIndex)) or "Default"
    print("[CCM] Scanning spellbook for class:", class, "spec:", specName)
    local foundIDs = {}
    -- Retail 11.x+: iterate skill lines (GetNumSpellBookItems does NOT exist)
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local bankEnum = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
        if bankEnum == nil then bankEnum = 0 end
        local numLines = C_SpellBook.GetNumSpellBookSkillLines() or 0
        local mainSpecIdx = Enum and Enum.SpellBookSkillLineIndex and Enum.SpellBookSkillLineIndex.MainSpec or 3
        for lineIdx = 1, numLines do
            local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(lineIdx)
            if lineInfo and lineInfo.numSpellBookItems and lineInfo.numSpellBookItems > 0 then
                -- Only scan the current spec's skill line (skip General, Class, off-specs)
                local isMainSpec = (lineIdx == mainSpecIdx)
                if isMainSpec then
                    for i = 1, lineInfo.numSpellBookItems do
                        local slotIndex = lineInfo.itemIndexOffset + i
                        local ok, info = pcall(C_SpellBook.GetSpellBookItemInfo, slotIndex, bankEnum)
                        if ok and info and info.spellID and not info.isPassive and not info.isOffSpec then
                            table.insert(foundIDs, info.spellID)
                        elseif ok and info and info.actionID and not info.isPassive and not info.isOffSpec then
                            -- Flyouts or items that only have actionID
                            table.insert(foundIDs, info.actionID)
                        end
                    end
                end
            end
        end
    -- Legacy fallback (Classic)
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
        -- Build a set of already-tracked IDs across all groups
        local existingIDs = {}
        local groups = CCM_TrackedSpellsSettings.groups or {}
        for _, g in ipairs(groups) do
            for _, id in ipairs(g.spellIDs or {}) do
                existingIDs[id] = true
            end
        end
        -- Store scanned spells as pending (not yet added)
        _G.CCM_PendingScannedSpells = {}
        local newCount = 0
        for _, id in ipairs(foundIDs) do
            if not existingIDs[id] then
                table.insert(_G.CCM_PendingScannedSpells, id)
                newCount = newCount + 1
            end
        end
        if newCount > 0 then
            print("[CCM] Found", newCount, "new spells. Choose which to add in the Spell List tab.")
        else
            print("[CCM] All spellbook spells are already tracked.")
            _G.CCM_PendingScannedSpells = nil
        end
    else
        print("[CCM] No spells found in spellbook.")
        _G.CCM_PendingScannedSpells = nil
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

local CCM_C = _G.CkraigCooldownManager and _G.CkraigCooldownManager.Constants or {}
local ICON_SIZE = CCM_C.DEFAULT_ICON_SIZE or 40
local ICON_SPACING = CCM_C.DEFAULT_ICON_SPACING or 50
local ICON_ROW_SPACING = CCM_C.DEFAULT_ICON_ROW_SPACING or 10
local ICONS_PER_ROW = CCM_C.DEFAULT_ICONS_PER_ROW or 6
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


-- Old CreateTrackedSpellsOptionsPanel removed; options are now handled by Ace3 AceConfig (ui/options/TrackedSpellsOptions.lua)
local function CreateTrackedSpellsOptionsPanel() return nil end

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

-- External icon registration helpers
local function UnregisterAllExternalIcons()
    for i = 1, #iconFrames do
        local f = iconFrames[i]
        if f._ccmRegisteredViewer then
            if f._ccmRegisteredViewer == "essential" and MyEssentialBuffTracker and MyEssentialBuffTracker.UnregisterExternalIcon then
                MyEssentialBuffTracker:UnregisterExternalIcon(f)
            elseif f._ccmRegisteredViewer == "utility" and MyUtilityBuffTracker and MyUtilityBuffTracker.UnregisterExternalIcon then
                MyUtilityBuffTracker:UnregisterExternalIcon(f)
            end
            f._ccmRegisteredViewer = nil
        end
    end
end

local function RegisterIconWithViewer(frame, mode, sortOrder)
    -- Unregister from previous viewer if mode changed
    if frame._ccmRegisteredViewer and frame._ccmRegisteredViewer ~= mode then
        if frame._ccmRegisteredViewer == "essential" and MyEssentialBuffTracker and MyEssentialBuffTracker.UnregisterExternalIcon then
            MyEssentialBuffTracker:UnregisterExternalIcon(frame)
        elseif frame._ccmRegisteredViewer == "utility" and MyUtilityBuffTracker and MyUtilityBuffTracker.UnregisterExternalIcon then
            MyUtilityBuffTracker:UnregisterExternalIcon(frame)
        end
        frame._ccmRegisteredViewer = nil
    end
    -- Set up aliases needed by the viewer layout
    frame.Icon = frame.Icon or frame.texture
    frame.Cooldown = frame.Cooldown or frame.cooldown
    -- Set sort position (layoutIndex takes priority in the viewer's sort comparator)
    if sortOrder and sortOrder > 0 then
        frame.layoutIndex = sortOrder
    else
        frame.layoutIndex = nil
    end
    frame:Show()
    if mode == "essential" and MyEssentialBuffTracker and MyEssentialBuffTracker.RegisterExternalIcon then
        MyEssentialBuffTracker:RegisterExternalIcon(frame)
        frame._ccmRegisteredViewer = "essential"
    elseif mode == "utility" and MyUtilityBuffTracker and MyUtilityBuffTracker.RegisterExternalIcon then
        MyUtilityBuffTracker:RegisterExternalIcon(frame)
        frame._ccmRegisteredViewer = "utility"
    end
end

function UpdateCustomSpellIcons()
    -- Check if tracking is disabled
    if CCM_TrackedSpellsSettings.enabled == false then
        UnregisterAllExternalIcons()
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
        UnregisterAllExternalIcons()
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
            groupAnchor:SetMovable(true)
            groupAnchor:SetClampedToScreen(true)
            groupAnchor:RegisterForDrag("LeftButton")
            -- Add green background texture
            local tex = groupAnchor:CreateTexture(nil, "BACKGROUND")
            tex:SetAllPoints(groupAnchor)
            tex:SetColorTexture(0, 0, 0, 0.9)
            groupAnchor.ccmGreenTex = tex
            tex:Hide()

            groupAnchor:SetScript("OnDragStart", function(self)
                if not (CCM_TrackedSpellsSettings and CCM_TrackedSpellsSettings.groupsMoving) then return end
                if InCombatLockdown and InCombatLockdown() then return end
                self:StartMoving()
            end)

            groupAnchor:SetScript("OnDragStop", function(self)
                self:StopMovingOrSizing()
                local idx = self._groupIndex
                if not idx then return end
                local groupsLocal = CCM_TrackedSpellsSettings and CCM_TrackedSpellsSettings.groups
                local g = groupsLocal and groupsLocal[idx]
                if not g then return end

                g.placement = g.placement or {}
                local _, _, _, x, y = self:GetPoint(1)
                g.placement.x = x or 0
                g.placement.y = y or 0
                SaveSettings()
            end)
        end
        groupAnchor._groupIndex = gIdx
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
        local viewerMode = group.viewerMode or "standalone"
        if not CCM_TrackedSpellsSettings.groupsMoving then
            groupAnchor:ClearAllPoints()
            groupAnchor:SetPoint("CENTER", UIParent, "CENTER", anchorX, anchorY)
        elseif not groupAnchor._ccmUnlockInitialized then
            groupAnchor:ClearAllPoints()
            groupAnchor:SetPoint("CENTER", UIParent, "CENTER", anchorX, anchorY)
            groupAnchor._ccmUnlockInitialized = true
        end
        if viewerMode ~= "standalone" and not CCM_TrackedSpellsSettings.groupsMoving then
            groupAnchor:Hide()
        else
            groupAnchor:Show()
        end
        -- Show/hide green background and group number based on unlock state
            if CCM_TrackedSpellsSettings.groupsMoving then
                if groupAnchor.ccmGreenTex then groupAnchor.ccmGreenTex:Show() end
                if groupAnchor.EnableMouse then groupAnchor:EnableMouse(true) end
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
                if groupAnchor.EnableMouse then groupAnchor:EnableMouse(false) end
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
                local spellKey = tostring(id)
                local spellIconSize = tonumber(spellSizes[spellKey]) or baseIconSize
                local spellYOffset = tonumber(spellOffsets[spellKey]) or 0
                frame:SetSize(spellIconSize, spellIconSize)
                local showCount = true
                local spellCountCfg = group.spellCountSettings and group.spellCountSettings[spellKey]
                if spellCountCfg and spellCountCfg.show ~= nil then
                    showCount = spellCountCfg.show
                elseif group.spellShowCount and group.spellShowCount[spellKey] ~= nil then
                    showCount = group.spellShowCount[spellKey]
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
                                -- GetSpellCastCount may return secret â€” SetText accepts it
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
                local viewerMode = group.viewerMode or "standalone"
                if viewerMode == "essential" or viewerMode == "utility" then
                    local sortOrder = tonumber(group.viewerSortOrder) or 0
                    RegisterIconWithViewer(frame, viewerMode, sortOrder)
                else
                    -- Unregister if previously registered
                    if frame._ccmRegisteredViewer then
                        if frame._ccmRegisteredViewer == "essential" and MyEssentialBuffTracker and MyEssentialBuffTracker.UnregisterExternalIcon then
                            MyEssentialBuffTracker:UnregisterExternalIcon(frame)
                        elseif frame._ccmRegisteredViewer == "utility" and MyUtilityBuffTracker and MyUtilityBuffTracker.UnregisterExternalIcon then
                            MyUtilityBuffTracker:UnregisterExternalIcon(frame)
                        end
                        frame._ccmRegisteredViewer = nil
                    end
                    frame:SetPoint("CENTER", groupAnchor, "CENTER", x, y + spellYOffset)
                    frame:Show()
                end
                local countSize = tonumber(spellCountCfg and spellCountCfg.size) or chargeTextSize
                local countPosition = (spellCountCfg and spellCountCfg.position) or chargePosition
                local countX = tonumber(spellCountCfg and spellCountCfg.x) or chargeTextX
                local countY = tonumber(spellCountCfg and spellCountCfg.y) or chargeTextY
                frame.count:SetFont(STANDARD_TEXT_FONT, countSize, "OUTLINE")
                frame.count:ClearAllPoints()
                frame.count:SetPoint(countPosition, frame, countPosition, countX, countY)
                iconIdx = iconIdx + 1
            end
        end
    end
    for i = iconIdx, #iconFrames do
        local f = iconFrames[i]
        if f._ccmRegisteredViewer then
            if f._ccmRegisteredViewer == "essential" and MyEssentialBuffTracker and MyEssentialBuffTracker.UnregisterExternalIcon then
                MyEssentialBuffTracker:UnregisterExternalIcon(f)
            elseif f._ccmRegisteredViewer == "utility" and MyUtilityBuffTracker and MyUtilityBuffTracker.UnregisterExternalIcon then
                MyUtilityBuffTracker:UnregisterExternalIcon(f)
            end
            f._ccmRegisteredViewer = nil
        end
        f:Hide()
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

-- Throttled dispatch using a hidden frame OnUpdate (zero closure allocation)
local dispatchDirty = false
local dispatchElapsed = 0
local dispatchInterval = 0.25
local dispatchFrame = CreateFrame("Frame")
dispatchFrame:Hide()

dispatchFrame:SetScript("OnUpdate", function(self, elapsed)
    dispatchElapsed = dispatchElapsed + elapsed
    if dispatchElapsed >= dispatchInterval then
        dispatchElapsed = 0
        dispatchDirty = false
        self:Hide()
        UpdateCustomSpellIcons()
    end
end)

local function ThrottledUpdate()
    if dispatchDirty then return end
    dispatchDirty = true
    dispatchElapsed = 0
    dispatchFrame:Show()
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
    else
        -- UNIT_AURA, SPELL_UPDATE_CHARGES, SPELL_UPDATE_COOLDOWN all throttled
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
    SyncAllSpellsToCooldownViewer()  -- Sync existing spells to Blizzard cooldown viewer
    UpdateCustomSpellIcons()
end
loginInitFrame:SetScript("OnEvent", function()
    C_Timer.After(0, ThrottledInit)
end)

_G.CCM_TrackedSpells = _G.CCM_TrackedSpells or {}
_G.CCM_TrackedSpells.UpdateCustomSpellIcons = UpdateCustomSpellIcons
_G.CCM_TrackedSpells.SaveSettings = function() SaveSettings() end
_G.CCM_TrackedSpells.AddSpellToCooldownViewer = AddSpellToCooldownViewer
_G.CCM_TrackedSpells.RemoveSpellFromCooldownViewer = RemoveSpellFromCooldownViewer
_G.CCM_TrackedSpells.SyncAllSpellsToCooldownViewer = SyncAllSpellsToCooldownViewer

