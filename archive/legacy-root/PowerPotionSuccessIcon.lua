-- CPU Optimization: Potion icon uses UNIT_SPELLCAST_SUCCEEDED (no polling needed)
-- luacheck: globals UnitAura GetItemInfo GetItemCount GetItemCooldown C_Timer CreateFrame UIParent
-- ======================================================
-- PowerPotionSuccessIcon (Displays icon on successful power potion cast)
-- ======================================================

-- SavedVariables
PowerPotionSuccessIconDB = PowerPotionSuccessIconDB or {}

-- Define PowerPotionSuccessIcon as a table
local PowerPotionSuccessIcon = {}
_G.PowerPotionSuccessIcon = PowerPotionSuccessIcon

-- Active icons table
local activeIcons = {}

local DEFAULT_POWER_POTIONS = {431932, 370816, 1236616, 1238443, 1236652, 1236994, 1236998, 1236551,383781}

local fallbackSettings = {
    enabled = true,
    locked = true,
    iconSize = 36,
    positionX = 200,
    positionY = 0,
    frameStrata = "BACKGROUND",
    showInDynamic = false,
    clusterIndex = 1,
    powerPotionsList = DEFAULT_POWER_POTIONS,
    timerDurations = {},
}

local function ApplyDefaultSettings(settings)
    if settings.enabled == nil then settings.enabled = true end
    if settings.locked == nil then settings.locked = true end
    if settings.iconSize == nil then settings.iconSize = 36 end
    if settings.positionX == nil then settings.positionX = 200 end
    if settings.positionY == nil then settings.positionY = 0 end
    if settings.frameStrata == nil then settings.frameStrata = "BACKGROUND" end
    if settings.showInDynamic == nil then settings.showInDynamic = false end
    if settings.clusterIndex == nil then settings.clusterIndex = 1 end

    if type(settings.powerPotionsList) ~= "table" or #settings.powerPotionsList == 0 then
        settings.powerPotionsList = {}
        for _, spellID in ipairs(DEFAULT_POWER_POTIONS) do
            settings.powerPotionsList[#settings.powerPotionsList + 1] = spellID
        end
    end

    if type(settings.timerDurations) ~= "table" then
        settings.timerDurations = {}
    end
    for _, spellID in ipairs(settings.powerPotionsList) do
        if settings.timerDurations[spellID] == nil then
            settings.timerDurations[spellID] = 30
        end
    end
end

local function EnsureSettings()
    local settings

    if CkraigProfileManager and CkraigProfileManager.db and CkraigProfileManager.db.profile then
        local profile = CkraigProfileManager.db.profile
        -- Use rawget so we don't get the AceDB __index default-table reference.
        -- If nil, create an owned table so inserts persist to SavedVariables.
        if rawget(profile, 'powerPotionSuccessIcon') == nil then
            profile.powerPotionSuccessIcon = {}
        end
        settings = profile.powerPotionSuccessIcon
        -- Also ensure powerPotionsList and timerDurations are owned tables, not default refs.
        if rawget(settings, 'powerPotionsList') == nil then
            settings.powerPotionsList = nil  -- will be filled by ApplyDefaultSettings
        end
        if rawget(settings, 'timerDurations') == nil then
            settings.timerDurations = nil
        end
    else
        PowerPotionSuccessIconDB.settings = PowerPotionSuccessIconDB.settings or {}
        settings = PowerPotionSuccessIconDB.settings
    end

    ApplyDefaultSettings(settings)
    return settings
end

function PowerPotionSuccessIcon:GetSettings()
    return EnsureSettings() or fallbackSettings
end

-- List of power potion item/spell IDs (loaded from settings)
local function GetPowerPotionsList()
    local settings = PowerPotionSuccessIcon:GetSettings()
    return settings.powerPotionsList or DEFAULT_POWER_POTIONS
end

-- Cache frequently used global functions as locals for performance
local UnitAura = UnitAura
local CreateFrame = CreateFrame
local C_Spell = C_Spell
local C_Item = C_Item
local C_Timer = C_Timer
local ipairs = ipairs
local pairs = pairs

-- Icon frame
local successIconFrame = CreateFrame("Frame", "PowerPotionSuccessIconFrame", UIParent)
successIconFrame:Hide()

local iconTexture = successIconFrame:CreateTexture(nil, "ARTWORK")
iconTexture:SetAllPoints(successIconFrame)

local cooldownFrame = CreateFrame("Cooldown", nil, successIconFrame, "CooldownFrameTemplate")
cooldownFrame:SetAllPoints(successIconFrame)

-- Hide all icons on player death
local deathEventFrame = CreateFrame("Frame")
deathEventFrame:RegisterEvent("PLAYER_DEAD")
deathEventFrame:SetScript("OnEvent", function()
    successIconFrame:Hide()
    PowerPotionSuccessIconDB.spellID = nil
    PowerPotionSuccessIconDB.startTime = nil
    for _, data in ipairs(activeIcons) do
        if data.frame then
            -- Unregister from Dynamic layout
            if DYNAMICICONS and DYNAMICICONS.UnregisterExternalIcon then
                DYNAMICICONS:UnregisterExternalIcon(data.frame)
            end
            data.frame:Hide()
        end
    end
    activeIcons = {}
end)

-- Apply settings to the frame
function PowerPotionSuccessIcon:ApplySettings()
    local settings = self:GetSettings()
    successIconFrame:SetSize(settings.iconSize or 36, settings.iconSize or 36)
    successIconFrame:SetPoint("CENTER", UIParent, "CENTER", settings.positionX or 200, settings.positionY or 0)
    successIconFrame:SetFrameStrata(settings.frameStrata or "BACKGROUND")
end

-- On profile changed
function PowerPotionSuccessIcon:OnProfileChanged()
    self:ApplySettings()
end

-- Check if Dynamic Icons integration is enabled
local function IsDynamicIntegrationActive()
    local settings = PowerPotionSuccessIcon:GetSettings()
    return settings and settings.showInDynamic
end

local function IsTrackedSpellCast(castSpellID)
    local potionsList = GetPowerPotionsList()
    for _, trackedID in ipairs(potionsList) do
        if castSpellID == trackedID then
            return true, trackedID
        end

        if C_Item and C_Item.GetItemSpell then
            local _, itemSpellID = C_Item.GetItemSpell(trackedID)
            if itemSpellID and itemSpellID == castSpellID then
                return true, trackedID
            end
        end
    end

    return false, nil
end

-- Function to show the icon
function PowerPotionSuccessIcon:ShowIcon(spellID, trackedID)
    local texture = C_Spell.GetSpellTexture(spellID)
    if texture then
        -- Create new icon frame
        local iconFrame = CreateFrame("Frame", nil, UIParent)
        local settings = self:GetSettings()
        iconFrame:SetSize(settings.iconSize or 36, settings.iconSize or 36)
        iconFrame:SetFrameStrata("HIGH")

        local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        iconTex:SetTexture(texture)
        -- ElvUI-style icon crop
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        -- Store as .Icon so Essential layout recognizes this frame
        iconFrame.Icon = iconTex

        -- Add 1-pixel black border using four overlay textures
        if not iconFrame.pixelBorders then
            iconFrame.pixelBorders = {}
            -- Top
            local top = iconFrame:CreateTexture(nil, "OVERLAY")
            top:SetColorTexture(0, 0, 0, 1)
            top:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 0, 0)
            top:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT", 0, 0)
            top:SetHeight(1)
            iconFrame.pixelBorders.top = top
            -- Bottom
            local bottom = iconFrame:CreateTexture(nil, "OVERLAY")
            bottom:SetColorTexture(0, 0, 0, 1)
            bottom:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMLEFT", 0, 0)
            bottom:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 0, 0)
            bottom:SetHeight(1)
            iconFrame.pixelBorders.bottom = bottom
            -- Left
            local leftB = iconFrame:CreateTexture(nil, "OVERLAY")
            leftB:SetColorTexture(0, 0, 0, 1)
            leftB:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 0, 0)
            leftB:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMLEFT", 0, 0)
            leftB:SetWidth(1)
            iconFrame.pixelBorders.left = leftB
            -- Right
            local rightB = iconFrame:CreateTexture(nil, "OVERLAY")
            rightB:SetColorTexture(0, 0, 0, 1)
            rightB:SetPoint("TOPRIGHT", iconFrame, "TOPRIGHT", 0, 0)
            rightB:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 0, 0)
            rightB:SetWidth(1)
            iconFrame.pixelBorders.right = rightB
        end
        for _, border in pairs(iconFrame.pixelBorders) do border:Show() end

        -- Add shadow texture if not present
        if not iconFrame.shadow then
            local shadow = iconFrame:CreateTexture(nil, "BACKGROUND")
            shadow:SetTexture("Interface\\BUTTONS\\UI-Quickslot-Depress")
            shadow:SetAllPoints(iconFrame)
            shadow:SetVertexColor(0, 0, 0, 0.6)
            iconFrame.shadow = shadow
        end

        local cooldown = CreateFrame("Cooldown", nil, iconFrame)
        cooldown:SetAllPoints()
        cooldown:SetDrawEdge(false)
        iconFrame.Cooldown = cooldown

        local startTime = GetTime()
        local settings = self:GetSettings()
        local durationKey = trackedID or spellID
        local duration = settings.timerDurations and settings.timerDurations[durationKey] or 30
        if duration <= 0 then duration = 30 end
        pcall(cooldown.SetCooldown, cooldown, startTime, duration)

        PowerPotionSuccessIconDB.spellID = spellID
        PowerPotionSuccessIconDB.startTime = startTime

        -- Add to active icons
        table.insert(activeIcons, {frame = iconFrame, spellID = spellID, endTime = startTime + duration})

        -- Register with Dynamic Icons layout if enabled
        if IsDynamicIntegrationActive() and DYNAMICICONS and DYNAMICICONS.RegisterExternalIcon then
            iconFrame:Show()
            DYNAMICICONS:RegisterExternalIcon(iconFrame, tostring(spellID), settings.clusterIndex or 1)
        else
            -- Fallback: standalone positioning
            self:RepositionIcons()
        end

        -- Hide after duration
        C_Timer.After(duration, function()
            -- Unregister from Dynamic before hiding
            if DYNAMICICONS and DYNAMICICONS.UnregisterExternalIcon then
                DYNAMICICONS:UnregisterExternalIcon(iconFrame)
            end
            iconFrame:Hide()
            -- Remove from activeIcons
            for i, data in ipairs(activeIcons) do
                if data.frame == iconFrame then
                    table.remove(activeIcons, i)
                    break
                end
            end
            if PowerPotionSuccessIconDB.spellID == spellID then
                PowerPotionSuccessIconDB.spellID = nil
                PowerPotionSuccessIconDB.startTime = nil
            end
            if not IsDynamicIntegrationActive() then
                self:RepositionIcons()
            end
        end)
    end
end

-- Function to reposition icons (fallback when Essential integration is not active)
function PowerPotionSuccessIcon:RepositionIcons()
    -- Skip standalone positioning if icons are managed by Dynamic Icons
    if IsDynamicIntegrationActive() then return end

    local num = #activeIcons
    if num == 0 then return end
    local settings = self:GetSettings()
    local locked = settings.locked
    local iconWidth = settings.iconSize or 36
    local gap = 10
    local totalWidth = num * iconWidth + (num - 1) * gap
    local startX = -totalWidth / 2
    local y = locked and (settings.positionY or 0) or (settings.positionY or 0)
    local centerX = locked and (settings.positionX or 200) or (settings.positionX or 200)
    for i, data in ipairs(activeIcons) do
        data.frame:ClearAllPoints()
        data.frame:SetPoint("CENTER", UIParent, "CENTER", centerX + startX + (i-1) * (iconWidth + gap), y)
        data.frame:SetMovable(not locked)
        if not locked then
            data.frame:EnableMouse(true)
            data.frame:RegisterForDrag("LeftButton")
            data.frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
            data.frame:SetScript("OnDragStop", function(self)
                self:StopMovingOrSizing()
                local x, y = self:GetCenter()
                local uiX = x - UIParent:GetWidth() / 2
                local uiY = y - UIParent:GetHeight() / 2
                -- Since icons are centered, adjust for the icon's position in the group
                local num = #activeIcons
                local iconWidth = settings.iconSize or 36
                local gap = 10
                local totalWidth = num * iconWidth + (num - 1) * gap
                local startX = -totalWidth / 2
                -- Find which icon this is
                local iconIndex = 1
                for idx, data in ipairs(activeIcons) do
                    if data.frame == self then
                        iconIndex = idx
                        break
                    end
                end
                local iconOffset = startX + (iconIndex - 1) * (iconWidth + gap)
                -- Adjust uiX to be the center of the group
                uiX = uiX - iconOffset
                local settings = PowerPotionSuccessIcon:GetSettings()
                settings.positionX = uiX
                settings.positionY = uiY
                PowerPotionSuccessIcon:RepositionIcons()
            end)
        else
            data.frame:SetMovable(false)
            data.frame:EnableMouse(false)
        end
    end
end


-- Event-driven batching and dirty flag system for icon updates
local ppsiDirty = false
local ppsiBatchScheduled = false
local ppsiBatchInterval = 0.5

local function RunPPSIBatch()
    ppsiBatchScheduled = false
    if ppsiDirty then
        ppsiDirty = false
        -- Only show icon if needed
        if PowerPotionSuccessIcon._pendingSpellID and PowerPotionSuccessIcon._pendingTrackedID then
            PowerPotionSuccessIcon:ShowIcon(PowerPotionSuccessIcon._pendingSpellID, PowerPotionSuccessIcon._pendingTrackedID)
            PowerPotionSuccessIcon._pendingSpellID = nil
            PowerPotionSuccessIcon._pendingTrackedID = nil
        end
    end
end

local function SchedulePPSIBatch()
    if not ppsiBatchScheduled then
        ppsiBatchScheduled = true
        C_Timer.After(ppsiBatchInterval, RunPPSIBatch)
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:SetScript("OnEvent", function(self, event, unit, _, spellID)
    if unit == "player" then
        local settings = PowerPotionSuccessIcon:GetSettings()
        if not settings.enabled then return end

        local isTracked, trackedID = IsTrackedSpellCast(spellID)
        if isTracked then
            PowerPotionSuccessIcon._pendingSpellID = spellID
            PowerPotionSuccessIcon._pendingTrackedID = trackedID
            ppsiDirty = true
            SchedulePPSIBatch()
        end
    end
end)

-- Restore icon on load if timer is still active
local function RestoreIcon()
    if PowerPotionSuccessIconDB.startTime and PowerPotionSuccessIconDB.spellID then
        local settings = PowerPotionSuccessIcon:GetSettings()
        local duration = settings.timerDurations and settings.timerDurations[PowerPotionSuccessIconDB.spellID] or 30
        local elapsed = GetTime() - PowerPotionSuccessIconDB.startTime
        if elapsed < duration then
            local remaining = duration - elapsed
            local texture = C_Spell.GetSpellTexture(PowerPotionSuccessIconDB.spellID)
            if texture then
                iconTexture:SetTexture(texture)
                successIconFrame:Show()
                pcall(cooldownFrame.SetCooldown, cooldownFrame, PowerPotionSuccessIconDB.startTime, duration)
                -- Schedule hide for remaining time
                C_Timer.After(remaining, function()
                    successIconFrame:Hide()
                    PowerPotionSuccessIconDB.spellID = nil
                    PowerPotionSuccessIconDB.startTime = nil
                end)
            end
        else
            -- Timer expired, clear
            PowerPotionSuccessIconDB.spellID = nil
            PowerPotionSuccessIconDB.startTime = nil
        end
    end
end

-- Initialize on load
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    PowerPotionSuccessIcon:GetSettings()
    PowerPotionSuccessIcon:ApplySettings()
    RestoreIcon()
end)

-- Create options panel
-- Function to populate the spell list in the options panel
local function PopulateSpellList(spellContainer, panel)
    local yOffset = 0
    local potionsList = GetPowerPotionsList()
    for i = 1, #potionsList do
        local entryID = potionsList[i]
        local spellInfo = C_Spell.GetSpellInfo(entryID)
        local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfo(entryID)
        -- Always show the entry, even if spellInfo is nil
        -- Icon
        local iconFrame = CreateFrame("Frame", nil, spellContainer)
        iconFrame:SetSize(32, 32)
        iconFrame:SetPoint("TOPLEFT", 0, yOffset)

        local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        local texture = C_Spell.GetSpellTexture(entryID) or itemIcon
        iconTex:SetTexture(texture or "Interface\\Icons\\inv_misc_questionmark")

        -- Name
        local nameText = spellContainer:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        nameText:SetPoint("LEFT", iconFrame, "RIGHT", 8, 0)
        if spellInfo and spellInfo.name then
            nameText:SetText(spellInfo.name .. " (" .. tostring(entryID) .. ")")
            nameText:SetTextColor(1, 1, 1, 1)
        elseif itemName then
            nameText:SetText(itemName .. " (Item ID: " .. tostring(entryID) .. ")")
            nameText:SetTextColor(1, 1, 1, 1)
        else
            nameText:SetText("Unknown ID: " .. tostring(entryID))
            nameText:SetTextColor(1, 0.5, 0.5, 1)
        end

        -- Slider
        local slider = CreateFrame("Slider", nil, spellContainer, "OptionsSliderTemplate")
        slider:SetPoint("LEFT", nameText, "RIGHT", 16, 0)
        slider:SetSize(120, 16)
        slider:SetMinMaxValues(5, 120)
        slider:SetValueStep(1)
        local settings = PowerPotionSuccessIcon:GetSettings()
        local currentDuration = settings.timerDurations and settings.timerDurations[entryID] or 30
        slider:SetValue(currentDuration)

        local valueText = spellContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        valueText:SetPoint("LEFT", slider, "RIGHT", 8, 0)
        valueText:SetText(tostring(currentDuration) .. "s")

        slider:SetScript("OnValueChanged", function(self, val)
            val = math.floor(val + 0.5)  -- Round to nearest int
            local settings = PowerPotionSuccessIcon:GetSettings()
            if not settings.timerDurations then settings.timerDurations = {} end
            settings.timerDurations[entryID] = val
            valueText:SetText(tostring(val) .. "s")
        end)

        -- Middle-click to input custom value
        slider:SetScript("OnMouseDown", function(self, button)
            if button == "MiddleButton" then
                local editBox = CreateFrame("EditBox", nil, self, "InputBoxTemplate")
                editBox:SetSize(60, 20)
                editBox:SetPoint("CENTER", self, "CENTER")
                editBox:SetAutoFocus(true)
                editBox:SetNumeric(true)
                editBox:SetText(tostring(math.floor(self:GetValue() + 0.5)))
                editBox:SetScript("OnEnterPressed", function()
                    local val = tonumber(editBox:GetText())
                    if val and val >= 5 and val <= 120 then
                        self:SetValue(val)
                    end
                    editBox:Hide()
                end)
                editBox:SetScript("OnEscapePressed", function()
                    editBox:Hide()
                end)
                editBox:Show()
            end
        end)

        -- Remove button
        local removeBtn = CreateFrame("Button", nil, spellContainer, "UIPanelButtonTemplate")
        removeBtn:SetSize(60, 20)
        removeBtn:SetPoint("LEFT", valueText, "RIGHT", 8, 0)
        removeBtn:SetText("Remove")
        removeBtn:SetScript("OnClick", function()
            local settings = PowerPotionSuccessIcon:GetSettings()
            if settings.powerPotionsList then
                for j, id in ipairs(settings.powerPotionsList) do
                    if id == entryID then
                        table.remove(settings.powerPotionsList, j)
                        break
                    end
                end
            end
            if panel and panel.RefreshSpellList then
                panel:RefreshSpellList()
            end
        end)

        -- Tooltip on icon (only if spellInfo is available)
        if spellInfo then
            local tooltip = CreateFrame("GameTooltip", "PowerPotionTooltip" .. i, nil, "GameTooltipTemplate")
            iconFrame:SetScript("OnEnter", function()
                tooltip:SetOwner(iconFrame, "ANCHOR_RIGHT")
                tooltip:SetSpellByID(entryID)
                tooltip:Show()
            end)
            iconFrame:SetScript("OnLeave", function()
                tooltip:Hide()
            end)
        elseif itemName then
            local tooltip = CreateFrame("GameTooltip", "PowerPotionTooltip" .. i, nil, "GameTooltipTemplate")
            iconFrame:SetScript("OnEnter", function()
                tooltip:SetOwner(iconFrame, "ANCHOR_RIGHT")
                tooltip:SetItemByID(entryID)
                tooltip:Show()
            end)
            iconFrame:SetScript("OnLeave", function()
                tooltip:Hide()
            end)
        else
            iconFrame:SetScript("OnEnter", function() end)
            iconFrame:SetScript("OnLeave", function() end)
        end

        yOffset = yOffset - 40  -- Next row
    end

end

function PowerPotionSuccessIcon:CreateOptionsPanel()
    local panel = CreateFrame("Frame", "PowerPotionSuccessIconPanel", UIParent)
    panel:SetSize(600, 700)

    -- ScrollFrame wrapping all content
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -24, 4)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(560, 1800)
    scrollFrame:SetScrollChild(content)

    -- Title
    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Power Potion Success Icon Configuration")

    -- Description
    local desc = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetWidth(550)
    desc:SetText("Configure the icon that appears when a power potion is successfully cast.")
    desc:SetJustifyH("LEFT")

    -- Note about reload
    local note = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    note:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -8)
    note:SetWidth(550)
    note:SetText("Note: Adding or removing potions requires a UI reload (/reload) to update this panel.")
    note:SetJustifyH("LEFT")
    note:SetTextColor(0.85, 0.85, 0.85, 1)

    -- Enable toggle
    local enableCheck = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
    enableCheck:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -16)
    enableCheck.Text:SetText("Enable Power Potion Success Icon")
    enableCheck:SetChecked(self:GetSettings().enabled)
    enableCheck:SetScript("OnClick", function(self)
        local settings = PowerPotionSuccessIcon:GetSettings()
        settings.enabled = self:GetChecked()
        -- Apply immediately if disabling
        if not settings.enabled then
            -- Hide all active icons and unregister from Dynamic
            for _, data in ipairs(activeIcons) do
                if DYNAMICICONS and DYNAMICICONS.UnregisterExternalIcon then
                    DYNAMICICONS:UnregisterExternalIcon(data.frame)
                end
                data.frame:Hide()
            end
            activeIcons = {}
        end
    end)

    -- Lock position toggle
    local lockCheck = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
    lockCheck:SetPoint("TOPLEFT", enableCheck, "BOTTOMLEFT", 0, -8)
    lockCheck.Text:SetText("Lock Icon Position (uncheck to drag)")
    lockCheck:SetChecked(self:GetSettings().locked ~= false)  -- Default to locked
    lockCheck:SetScript("OnClick", function(self)
        local settings = PowerPotionSuccessIcon:GetSettings()
        settings.locked = self:GetChecked()
        PowerPotionSuccessIcon:RepositionIcons()
    end)

    -- Show in Dynamic Icons checkbox
    local dynamicCheck = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
    dynamicCheck:SetPoint("TOPLEFT", lockCheck, "BOTTOMLEFT", 0, -8)
    dynamicCheck.Text:SetText("Show in Dynamic Icons")
    dynamicCheck:SetChecked(self:GetSettings().showInDynamic or false)
    dynamicCheck:SetScript("OnClick", function(self)
        local s = PowerPotionSuccessIcon:GetSettings()
        s.showInDynamic = self:GetChecked()
        if not s.showInDynamic and DYNAMICICONS and DYNAMICICONS.UnregisterExternalIcon then
            for _, data in ipairs(activeIcons) do
                DYNAMICICONS:UnregisterExternalIcon(data.frame)
            end
        end
        if s.showInDynamic and DYNAMICICONS and DYNAMICICONS.RegisterExternalIcon then
            for _, data in ipairs(activeIcons) do
                if data.frame and data.frame:IsShown() then
                    DYNAMICICONS:RegisterExternalIcon(data.frame, tostring(data.spellID), s.clusterIndex or 1)
                end
            end
        end
    end)

    -- Cluster index chooser
    local clusterLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    clusterLabel:SetPoint("TOPLEFT", dynamicCheck, "BOTTOMLEFT", 0, -12)
    clusterLabel:SetText("Target Cluster:")
    clusterLabel:SetTextColor(1, 1, 1, 1)

    local clusterDropdown = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate")
    clusterDropdown:SetPoint("LEFT", clusterLabel, "RIGHT", 4, 0)
    clusterDropdown:SetWidth(120)

    clusterDropdown:SetupMenu(function(dd, rootDescription)
        local maxClusters = 20
        if DYNAMICICONS and DYNAMICICONS.GetSettings then
            local ds = DYNAMICICONS:GetSettings()
            if ds and ds.clusterCount then maxClusters = ds.clusterCount end
        end
        local s = PowerPotionSuccessIcon:GetSettings()
        for i = 1, maxClusters do
            rootDescription:CreateRadio(
                "Cluster " .. i,
                function() return (PowerPotionSuccessIcon:GetSettings().clusterIndex or 1) == i end,
                function()
                    s.clusterIndex = i
                    -- Re-register active icons in the new cluster
                    if s.showInDynamic and DYNAMICICONS and DYNAMICICONS.RegisterExternalIcon then
                        for _, data in ipairs(activeIcons) do
                            if data.frame and data.frame:IsShown() then
                                DYNAMICICONS:UnregisterExternalIcon(data.frame)
                                DYNAMICICONS:RegisterExternalIcon(data.frame, tostring(data.spellID), i)
                            end
                        end
                    end
                end,
                i
            )
        end
    end)

    -- Icon size slider
    local sizeContainer = CreateFrame("Frame", nil, content)
    sizeContainer:SetSize(250, 40)
    sizeContainer:SetPoint("TOPLEFT", clusterLabel, "BOTTOMLEFT", 0, -24)

    local sizeLabel = sizeContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sizeLabel:SetPoint("TOPLEFT", 0, 11)
    sizeLabel:SetText("Icon Size")
    sizeLabel:SetTextColor(0.85, 0.85, 0.85, 1)

    local sizeSlider = CreateFrame("Slider", nil, sizeContainer, "OptionsSliderTemplate")
    sizeSlider:SetPoint("TOPLEFT", 0, -18)
    sizeSlider:SetSize(140, 16)
    sizeSlider:SetMinMaxValues(20, 100)
    sizeSlider:SetValueStep(1)
    local settings = self:GetSettings()
    sizeSlider:SetValue(settings.iconSize or 36)

    local sizeValueText = sizeContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sizeValueText:SetPoint("LEFT", sizeLabel, "RIGHT", 8, 0)
    sizeValueText:SetText(tostring(settings.iconSize or 36))

    -- Update active icons to the current saved size when opening options
    local currentSize = settings.iconSize or 36
    for _, data in ipairs(activeIcons) do
        data.frame:SetSize(currentSize, currentSize)
    end
    PowerPotionSuccessIcon:RepositionIcons()

    sizeSlider:SetScript("OnValueChanged", function(self, val)
        local settings = PowerPotionSuccessIcon:GetSettings()
        settings.iconSize = val
        sizeValueText:SetText(tostring(val))
        -- Update active icons size
        for _, data in ipairs(activeIcons) do
            data.frame:SetSize(val, val)
        end
        PowerPotionSuccessIcon:RepositionIcons()
    end)

    -- Middle-click to input custom value
    sizeSlider:SetScript("OnMouseDown", function(self, button)
        if button == "MiddleButton" then
            local editBox = CreateFrame("EditBox", nil, self, "InputBoxTemplate")
            editBox:SetSize(60, 20)
            editBox:SetPoint("CENTER", self, "CENTER")
            editBox:SetAutoFocus(true)
            editBox:SetNumeric(true)
            editBox:SetText(tostring(math.floor(self:GetValue() + 0.5)))
            editBox:SetScript("OnEnterPressed", function()
                local val = tonumber(editBox:GetText())
                if val and val >= 20 and val <= 100 then
                    self:SetValue(val)
                end
                editBox:Hide()
            end)
            editBox:SetScript("OnEscapePressed", function()
                editBox:Hide()
            end)
            editBox:Show()
        end
    end)

    -- Add new tracked spell/item ID (placed above list so it is always visible)
    local addLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    addLabel:SetPoint("TOPLEFT", sizeContainer, "BOTTOMLEFT", 0, -24)
    addLabel:SetText("Add New Spell/Item ID:")
    addLabel:SetTextColor(1, 1, 1, 1)

    local addEditBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    addEditBox:SetSize(120, 20)
    addEditBox:SetPoint("LEFT", addLabel, "RIGHT", 8, 0)
    addEditBox:SetAutoFocus(false)
    addEditBox:SetText("")
    addEditBox:SetNumeric(true)
    addEditBox:SetMaxLetters(10)

    local addBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    addBtn:SetSize(50, 20)
    addBtn:SetPoint("LEFT", addEditBox, "RIGHT", 8, 0)
    addBtn:SetText("Add")

    local function AddTrackedID()
        local id = tonumber(addEditBox:GetText())
        if not id or id <= 0 then return end

        local s = PowerPotionSuccessIcon:GetSettings()
        if not s.powerPotionsList then s.powerPotionsList = {} end
        if not tContains(s.powerPotionsList, id) then
            table.insert(s.powerPotionsList, id)
            if not s.timerDurations then s.timerDurations = {} end
            s.timerDurations[id] = s.timerDurations[id] or 30
            addEditBox:SetText("")
            if panel and panel.RefreshSpellList then
                panel:RefreshSpellList()
            end
        end
    end

    addBtn:SetScript("OnClick", AddTrackedID)
    addEditBox:SetScript("OnEnterPressed", function(self)
        AddTrackedID()
        self:ClearFocus()
    end)

    -- Spell list with icons and sliders
    local spellListLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    spellListLabel:SetPoint("TOPLEFT", addLabel, "BOTTOMLEFT", 0, -20)
    spellListLabel:SetText("Tracked Power Potions (with custom timers):")
    spellListLabel:SetTextColor(1, 1, 1, 1)

    local spellContainer = CreateFrame("Frame", nil, content)
    spellContainer:SetPoint("TOPLEFT", spellListLabel, "BOTTOMLEFT", 0, -8)
    spellContainer:SetSize(550, 200)  -- Larger to fit sliders
    panel.spellContainer = spellContainer

    function panel:RefreshSpellList()
        if self.spellContainer then
            self.spellContainer:Hide()
            self.spellContainer:SetParent(nil)
        end
        local potionCount = #GetPowerPotionsList()
        local listHeight = math.max(40, potionCount * 40 + 20)
        local refreshed = CreateFrame("Frame", nil, content)
        refreshed:SetPoint("TOPLEFT", spellListLabel, "BOTTOMLEFT", 0, -8)
        refreshed:SetSize(550, listHeight)
        refreshed:Show()
        self.spellContainer = refreshed
        PopulateSpellList(refreshed, panel)
    end

    panel:RefreshSpellList()

    _G.PowerPotionSuccessIconPanel = panel
    return panel
end