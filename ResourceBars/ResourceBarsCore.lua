-- ============================================================
-- CkraigCooldownManager :: ResourceBars :: Core
-- ============================================================
-- Shared framework for all resource bars (health, power, class).
-- Provides bar creation, styling, positioning, visibility,
-- and the class/spec detection system.
-- ============================================================

local CCM = _G.CkraigCooldownManager
local LSM = LibStub("LibSharedMedia-3.0", true)
local LibEditMode = LibStub("LibEditMode", true)

-- ============================================================
-- Module namespace
-- ============================================================
CCM_ResourceBars = CCM_ResourceBars or {}
local RB = CCM_ResourceBars

RB.bars = {}           -- registry: name -> bar frame
RB.modules = {}        -- registry: name -> module table
RB.playerClass = nil
RB.playerSpec = nil

-- ============================================================
-- Shared utilities for hot-path performance
-- ============================================================
-- FontString launderer: converts secret/tainted numbers to clean values
-- via C-side SetFormattedText → GetText → tonumber  (avoids pcall overhead)
local _launderFS = nil
local function GetLaunderFS()
    if not _launderFS then
        local f = CreateFrame("Frame", nil, UIParent)
        f:Hide()
        _launderFS = f:CreateFontString(nil, "BACKGROUND")
        _launderFS:SetFontObject("GameFontNormal")
        _launderFS:Hide()
    end
    return _launderFS
end

function RB:LaunderNumber(secret)
    if type(secret) ~= "number" then return 0 end
    local fs = GetLaunderFS()
    fs:SetFormattedText("%d", secret)
    return tonumber(fs:GetText()) or 0
end

-- Pre-allocated reusable Color objects (avoids CreateColor table allocs in hot paths)
RB._gradStart = nil
RB._gradEnd = nil
function RB:GetGradientColors()
    if not self._gradStart then
        self._gradStart = CreateColor(1, 1, 1, 1)
        self._gradEnd = CreateColor(1, 1, 1, 1)
    end
    return self._gradStart, self._gradEnd
end

-- ============================================================
-- Class constants
-- ============================================================
RB.CLASS_INFO = {
    WARRIOR     = { name = "Warrior",       powerType = Enum.PowerType.Rage },
    PALADIN     = { name = "Paladin",       powerType = Enum.PowerType.Mana },
    HUNTER      = { name = "Hunter",        powerType = Enum.PowerType.Focus },
    ROGUE       = { name = "Rogue",         powerType = Enum.PowerType.Energy },
    PRIEST      = { name = "Priest",        powerType = Enum.PowerType.Mana },
    DEATHKNIGHT = { name = "Death Knight",  powerType = Enum.PowerType.RunicPower },
    SHAMAN      = { name = "Shaman",        powerType = Enum.PowerType.Mana },
    MAGE        = { name = "Mage",          powerType = Enum.PowerType.Mana },
    WARLOCK     = { name = "Warlock",       powerType = Enum.PowerType.Mana },
    MONK        = { name = "Monk",          powerType = Enum.PowerType.Energy },
    DRUID       = { name = "Druid",         powerType = Enum.PowerType.Mana },
    DEMONHUNTER = { name = "Demon Hunter",  powerType = Enum.PowerType.Fury },
    EVOKER      = { name = "Evoker",        powerType = Enum.PowerType.Mana },
}

-- Spec-specific power overrides
RB.SPEC_POWER = {
    -- Warrior
    [71]  = Enum.PowerType.Rage,   -- Arms
    [72]  = Enum.PowerType.Rage,   -- Fury
    [73]  = Enum.PowerType.Rage,   -- Protection
    -- Paladin
    [65]  = Enum.PowerType.Mana,   -- Holy
    [66]  = Enum.PowerType.Mana,   -- Protection
    [70]  = Enum.PowerType.Mana,   -- Retribution
    -- Hunter
    [253] = Enum.PowerType.Focus,  -- BM
    [254] = Enum.PowerType.Focus,  -- MM
    [255] = Enum.PowerType.Focus,  -- Survival
    -- Rogue
    [259] = Enum.PowerType.Energy, -- Assassination
    [260] = Enum.PowerType.Energy, -- Outlaw
    [261] = Enum.PowerType.Energy, -- Subtlety
    -- Priest
    [256] = Enum.PowerType.Mana,   -- Discipline
    [257] = Enum.PowerType.Mana,   -- Holy
    [258] = Enum.PowerType.Insanity,-- Shadow
    -- DK
    [250] = Enum.PowerType.RunicPower, -- Blood
    [251] = Enum.PowerType.RunicPower, -- Frost
    [252] = Enum.PowerType.RunicPower, -- Unholy
    -- Shaman
    [262] = Enum.PowerType.Maelstrom,  -- Elemental
    [263] = Enum.PowerType.Mana,       -- Enhancement (uses maelstrom weapon stacks, power is mana)
    [264] = Enum.PowerType.Mana,       -- Restoration
    -- Mage
    [62]  = Enum.PowerType.Mana,   -- Arcane
    [63]  = Enum.PowerType.Mana,   -- Fire
    [64]  = Enum.PowerType.Mana,   -- Frost
    -- Warlock
    [265] = Enum.PowerType.Mana,   -- Affliction
    [266] = Enum.PowerType.Mana,   -- Demonology
    [267] = Enum.PowerType.Mana,   -- Destruction
    -- Monk
    [268] = Enum.PowerType.Energy, -- Brewmaster
    [269] = Enum.PowerType.Energy, -- Windwalker
    [270] = Enum.PowerType.Mana,   -- Mistweaver
    -- Druid
    [102] = Enum.PowerType.LunarPower, -- Balance
    [103] = Enum.PowerType.Energy,     -- Feral
    [104] = Enum.PowerType.Rage,       -- Guardian
    [105] = Enum.PowerType.Mana,       -- Restoration
    -- DH
    [577] = Enum.PowerType.Fury,   -- Havoc
    [581] = Enum.PowerType.Fury,   -- Vengeance (Pain merged into Fury in TWW)
    -- Evoker
    [1467] = Enum.PowerType.Mana,  -- Devastation
    [1468] = Enum.PowerType.Mana,  -- Preservation
    [1473] = Enum.PowerType.Mana,  -- Augmentation
}

-- Power type display names
RB.POWER_NAMES = {
    [Enum.PowerType.Mana]       = "Mana",
    [Enum.PowerType.Rage]       = "Rage",
    [Enum.PowerType.Focus]      = "Focus",
    [Enum.PowerType.Energy]     = "Energy",
    [Enum.PowerType.RunicPower] = "Runic Power",
    [Enum.PowerType.Insanity]   = "Insanity",
    [Enum.PowerType.Fury]       = "Fury",
    [Enum.PowerType.Pain]       = "Pain",
    [Enum.PowerType.Maelstrom]  = "Maelstrom",
    [Enum.PowerType.LunarPower] = "Astral Power",
}

-- ============================================================
-- Utilities
-- ============================================================
function RB:GetPlayerClass()
    if not self.playerClass then
        local _, class = UnitClass("player")
        self.playerClass = class
    end
    return self.playerClass
end

function RB:GetPlayerSpec()
    local specIndex = GetSpecialization and GetSpecialization()
    if specIndex then
        local specID = GetSpecializationInfo(specIndex)
        self.playerSpec = specID
        return specID
    end
    return nil
end

function RB:GetPlayerPowerType()
    local specID = self:GetPlayerSpec()
    if specID and self.SPEC_POWER[specID] then
        return self.SPEC_POWER[specID]
    end
    local class = self:GetPlayerClass()
    if class and self.CLASS_INFO[class] then
        return self.CLASS_INFO[class].powerType
    end
    return Enum.PowerType.Mana
end

function RB:GetSettings()
    if CkraigProfileManager and CkraigProfileManager.db and CkraigProfileManager.db.profile then
        CkraigProfileManager.db.profile.resourceBars = CkraigProfileManager.db.profile.resourceBars or {}
        return CkraigProfileManager.db.profile.resourceBars
    end
    CCM_ResourceBarsDB = CCM_ResourceBarsDB or {}
    return CCM_ResourceBarsDB
end

function RB:GetModuleSettings(moduleName)
    local settings = self:GetSettings()
    settings[moduleName] = settings[moduleName] or {}
    return settings[moduleName]
end

-- ============================================================
-- Default settings per module
-- ============================================================
RB.MODULE_DEFAULTS = {
    healthBar = {
        enabled = true,
        width = 200,
        height = 20,
        texture = "Blizzard Raid Bar",
        bgColor = { r = 0.15, g = 0.15, b = 0.15, a = 0.8 },
        borderSize = 1,
        borderColor = { r = 0, g = 0, b = 0, a = 1 },
        useClassColor = true,
        customColor = { r = 0.2, g = 0.8, b = 0.2, a = 1 },
        useGradient = false,
        gradientStart = { r = 0.2, g = 0.8, b = 0.2, a = 1 },
        gradientEnd = { r = 0.0, g = 0.5, b = 0.0, a = 1 },
        showText = true,
        textFormat = "percent",
        textSize = 12,
        anchor = "viewer",
        anchorTarget = "essential",
        anchorPosition = "ABOVE",
        anchorOffset = 0,
        widthMatchAnchor = true,
        position = { point = "CENTER", x = 0, y = -80 },
        hideWhenMounted = false,
        hideOutOfCombat = false,
        showAbsorb = true,
        absorbColor = { r = 0.8, g = 0.8, b = 0.2, a = 0.5 },
        absorbTexture = "Blizzard Raid Bar",
        absorbSide = "right",
        showRightClickMenu = false,
    },
    powerBar = {
        enabled = true,
        width = 200,
        height = 14,
        texture = "Blizzard Raid Bar",
        bgColor = { r = 0.15, g = 0.15, b = 0.15, a = 0.8 },
        borderSize = 1,
        borderColor = { r = 0, g = 0, b = 0, a = 1 },
        usePowerColor = true,
        customColor = { r = 0.2, g = 0.2, b = 0.8, a = 1 },
        useGradient = false,
        gradientStart = { r = 0.2, g = 0.2, b = 0.8, a = 1 },
        gradientEnd = { r = 0.0, g = 0.0, b = 0.5, a = 1 },
        showText = true,
        textFormat = "current",
        textSize = 11,
        anchor = "viewer",
        anchorTarget = "essential",
        anchorPosition = "ABOVE",
        anchorOffset = 0,
        widthMatchAnchor = true,
        position = { point = "CENTER", x = 0, y = -100 },
        hideWhenMounted = false,
        hideOutOfCombat = false,
    },
    altPowerBar = {
        enabled = false,
        width = 200,
        height = 12,
        texture = "Blizzard Raid Bar",
        bgColor = { r = 0.15, g = 0.15, b = 0.15, a = 0.8 },
        borderSize = 1,
        borderColor = { r = 0, g = 0, b = 0, a = 1 },
        customColor = { r = 0.9, g = 0.6, b = 0.1, a = 1 },
        useGradient = false,
        gradientStart = { r = 0.9, g = 0.6, b = 0.1, a = 1 },
        gradientEnd = { r = 1.0, g = 0.3, b = 0.0, a = 1 },
        showText = true,
        textSize = 10,
        anchor = "viewer",
        anchorTarget = "essential",
        anchorPosition = "ABOVE",
        anchorOffset = 0,
        widthMatchAnchor = true,
        position = { point = "CENTER", x = 0, y = -115 },
    },
    ironfurTracker = {
        enabled = true,
        width = 180,
        height = 24,
        maxSegments = 20,
        texture = "Blizzard Raid Bar",
        bgColor = { r = 0.08, g = 0.08, b = 0.08, a = 0.85 },
        borderSize = 1,
        borderColor = { r = 0, g = 0, b = 0, a = 1 },
        segmentColor = { r = 0.5, g = 0.8, b = 1.0, a = 1 },
        tickColor = { r = 0, g = 0, b = 0, a = 1 },
        showText = true,
        textSize = 20,
        textPosition = "CENTER",
        anchor = "viewer",
        anchorTarget = "essential",
        anchorPosition = "ABOVE",
        anchorOffset = 0,
        widthMatchAnchor = true,
        position = { point = "CENTER", x = 0, y = -200 },
        hideWhenMounted = false,
        hideOutOfCombat = false,
    },
    monkOrbTracker = {
        enabled = true,
        width = 120,
        height = 24,
        numOrbs = 5,
        texture = "Blizzard Raid Bar",
        barColor = { r = 0.00, g = 1.00, b = 0.59, a = 1 },
        gradientStart = { r = 0.46, g = 0.98, b = 1.00, a = 1 },
        gradientEnd = { r = 0.00, g = 0.50, b = 1.00, a = 1 },
        bgColor = { r = 0.08, g = 0.08, b = 0.08, a = 0.75 },
        bgTexture = "",
        borderSize = 1,
        borderColor = { r = 0, g = 0, b = 0, a = 1 },
        anchor = "viewer",
        anchorTarget = "essential",
        anchorPosition = "ABOVE",
        anchorOffset = 0,
        widthMatchAnchor = true,
        position = { point = "CENTER", x = 0, y = -200 },
        hideWhenMounted = false,
        hideOutOfCombat = false,
    },
    vengeanceSoulTracker = {
        enabled = true,
        width = 120,
        height = 24,
        numSouls = 6,
        texture = "Blizzard Raid Bar",
        barColor = { r = 0.46, g = 0.98, b = 1.00, a = 1 },
        gradientStart = { r = 0.46, g = 0.98, b = 1.00, a = 1 },
        gradientEnd = { r = 0.00, g = 0.50, b = 1.00, a = 1 },
        bgColor = { r = 0.08, g = 0.08, b = 0.08, a = 0.75 },
        bgTexture = "",
        borderSize = 1,
        borderColor = { r = 0, g = 0, b = 0, a = 1 },
        anchor = "viewer",
        anchorTarget = "essential",
        anchorPosition = "ABOVE",
        anchorOffset = 0,
        widthMatchAnchor = true,
        position = { point = "CENTER", x = 0, y = -200 },
        hideWhenMounted = false,
        hideOutOfCombat = false,
    },
    warriorWhirlwindTracker = {
        enabled = true,
        width = 120,
        height = 24,
        numSegments = 4,
        texture = "Blizzard Raid Bar",
        barColor = { r = 0.78, g = 0.61, b = 0.43, a = 1 },
        gradientStart = { r = 0.78, g = 0.61, b = 0.43, a = 1 },
        gradientEnd = { r = 0.50, g = 0.30, b = 0.15, a = 1 },
        bgColor = { r = 0.08, g = 0.08, b = 0.08, a = 0.75 },
        bgTexture = "",
        borderSize = 1,
        borderColor = { r = 0, g = 0, b = 0, a = 1 },
        anchor = "viewer",
        anchorTarget = "essential",
        anchorPosition = "ABOVE",
        anchorOffset = 0,
        widthMatchAnchor = true,
        position = { point = "CENTER", x = 0, y = -200 },
        hideWhenMounted = false,
        hideOutOfCombat = false,
    },
    maelstromTracker = {
        enabled = true,
        width = 120,
        height = 24,
        numStacks = 10,
        texture = "Blizzard Raid Bar",
        colorMode = "threshold",
        barColor = { r = 0.00, g = 0.50, b = 1.00, a = 1 },
        gradientStart = { r = 0.00, g = 0.50, b = 1.00, a = 1 },
        gradientEnd = { r = 0.00, g = 0.25, b = 0.60, a = 1 },
        threshold1 = 6,
        threshold2 = 10,
        thresholdColor1 = { r = 0.00, g = 0.50, b = 1.00, a = 1 },
        thresholdColor2 = { r = 1.00, g = 0.80, b = 0.00, a = 1 },
        thresholdColor3 = { r = 1.00, g = 0.30, b = 0.00, a = 1 },
        bgColor = { r = 0.08, g = 0.08, b = 0.08, a = 0.75 },
        bgTexture = "",
        borderSize = 1,
        borderColor = { r = 0, g = 0, b = 0, a = 1 },
        anchor = "viewer",
        anchorTarget = "essential",
        anchorPosition = "ABOVE",
        anchorOffset = 0,
        widthMatchAnchor = true,
        position = { point = "CENTER", x = 0, y = -200 },
        hideWhenMounted = false,
        hideOutOfCombat = false,
    },
}

function RB:EnsureDefaults(moduleName)
    local settings = self:GetModuleSettings(moduleName)
    local defaults = self.MODULE_DEFAULTS[moduleName]
    if not defaults then return settings end
    for k, v in pairs(defaults) do
        if settings[k] == nil then
            if type(v) == "table" then
                settings[k] = {}
                for k2, v2 in pairs(v) do settings[k][k2] = v2 end
            else
                settings[k] = v
            end
        end
    end
    return settings
end

-- ============================================================
-- Power colors (Blizzard standard)
-- ============================================================
RB.POWER_COLORS = {
    [Enum.PowerType.Mana]       = { r = 0.00, g = 0.00, b = 1.00 },
    [Enum.PowerType.Rage]       = { r = 1.00, g = 0.00, b = 0.00 },
    [Enum.PowerType.Focus]      = { r = 1.00, g = 0.50, b = 0.25 },
    [Enum.PowerType.Energy]     = { r = 1.00, g = 1.00, b = 0.00 },
    [Enum.PowerType.RunicPower] = { r = 0.00, g = 0.82, b = 1.00 },
    [Enum.PowerType.Insanity]   = { r = 0.40, g = 0.00, b = 0.80 },
    [Enum.PowerType.Fury]       = { r = 0.79, g = 0.26, b = 0.99 },
    [Enum.PowerType.Pain]       = { r = 1.00, g = 0.61, b = 0.00 },
    [Enum.PowerType.Maelstrom]  = { r = 0.00, g = 0.50, b = 1.00 },
    [Enum.PowerType.LunarPower] = { r = 0.30, g = 0.52, b = 0.90 },
}

-- Class colors
RB.CLASS_COLORS = {}
for class, _ in pairs(RB.CLASS_INFO) do
    local c = RAID_CLASS_COLORS[class]
    if c then
        RB.CLASS_COLORS[class] = { r = c.r, g = c.g, b = c.b }
    end
end

-- ============================================================
-- Status Bar Factory
-- ============================================================
function RB:CreateStatusBar(name, parent, settings)
    local borderSize = settings.borderSize or 1

    -- Outer wrapper: handles border, drag, positioning
    local wrapper = CreateFrame("Frame", "CCM_RB_" .. name, parent or UIParent, "BackdropTemplate")
    wrapper:SetSize(settings.width or 200, settings.height or 20)
    wrapper:SetMovable(true)
    wrapper:EnableMouse(true)
    wrapper:RegisterForDrag("LeftButton")
    wrapper:SetClampedToScreen(true)
    wrapper:SetFrameStrata("MEDIUM")

    -- Border via backdrop
    if borderSize > 0 then
        wrapper:SetBackdrop({
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = borderSize,
        })
        local bc = settings.borderColor or { r = 0, g = 0, b = 0, a = 1 }
        wrapper:SetBackdropBorderColor(bc.r, bc.g, bc.b, bc.a)
    end

    -- Inner StatusBar: inset by borderSize so it doesn't paint over the border
    local bar = CreateFrame("StatusBar", "CCM_RB_" .. name .. "_Inner", wrapper)
    bar:SetPoint("TOPLEFT", borderSize, -borderSize)
    bar:SetPoint("BOTTOMRIGHT", -borderSize, borderSize)
    bar:SetFrameLevel(wrapper:GetFrameLevel() + 1)

    -- Background
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()

    -- Status bar texture
    local texPath = (LSM and settings.texture) and LSM:Fetch("statusbar", settings.texture) or "Interface\\TargetingFrame\\UI-StatusBar"
    bar:SetStatusBarTexture(texPath)
    local sbTex = bar:GetStatusBarTexture()
    if sbTex then
        sbTex:SetTexelSnappingBias(0)
        sbTex:SetSnapToPixelGrid(false)
    end
    bar.bg:SetTexture(texPath)
    bar.bg:SetTexelSnappingBias(0)
    bar.bg:SetSnapToPixelGrid(false)

    local bgc = settings.bgColor or { r = 0.15, g = 0.15, b = 0.15, a = 0.8 }
    bar.bg:SetVertexColor(bgc.r, bgc.g, bgc.b, bgc.a)

    -- Text overlay (on inner bar so it's above the fill texture)
    wrapper.text = bar:CreateFontString(nil, "OVERLAY")
    wrapper.text:SetFont(STANDARD_TEXT_FONT, settings.textSize or 12, "OUTLINE")
    wrapper.text:SetPoint("CENTER", wrapper, "CENTER", 0, 0)
    wrapper.text:SetJustifyH("CENTER")

    -- Drag to reposition (on wrapper)
    wrapper:SetScript("OnDragStart", function(self)
        if self._locked then return end
        local modSettings = RB:GetModuleSettings(self._moduleName)
        if modSettings and modSettings.anchor == "viewer" then return end
        self:StartMoving()
    end)
    wrapper:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local x = (cx * scale) - ux
        local y = (cy * scale) - uy
        local modSettings = RB:GetModuleSettings(self._moduleName)
        modSettings.position = { point = "CENTER", relPoint = "CENTER", x = x, y = y }
    end)

    wrapper._moduleName = name
    wrapper._locked = true
    wrapper._borderSize = borderSize
    -- Store the inner bar on the wrapper so callers can use it seamlessly
    wrapper._innerBar = bar

    -- Proxy common StatusBar methods onto the wrapper so existing code works
    wrapper.SetMinMaxValues = function(self, ...) return bar:SetMinMaxValues(...) end
    wrapper.SetValue = function(self, ...) return bar:SetValue(...) end
    wrapper.SetStatusBarColor = function(self, ...) return bar:SetStatusBarColor(...) end
    wrapper.SetStatusBarTexture = function(self, ...) return bar:SetStatusBarTexture(...) end
    wrapper.GetStatusBarTexture = function(self) return bar:GetStatusBarTexture() end
    wrapper.GetValue = function(self) return bar:GetValue() end
    wrapper.GetMinMaxValues = function(self) return bar:GetMinMaxValues() end

    self.bars[name] = wrapper

    -- Hook show/hide for smart stacking
    wrapper:HookScript("OnShow", function() RB:OnBarVisibilityChanged() end)
    wrapper:HookScript("OnHide", function() RB:OnBarVisibilityChanged() end)

    return wrapper
end

-- ============================================================
-- Segmented Point Bar Factory
-- ============================================================
function RB:CreateSegmentedBar(name, parent, maxPoints, settings)
    local container = CreateFrame("Frame", "CCM_RB_" .. name, parent or UIParent, "BackdropTemplate")
    container:SetMovable(true)
    container:EnableMouse(true)
    container:RegisterForDrag("LeftButton")
    container:SetClampedToScreen(true)
    container:SetFrameStrata("MEDIUM")

    container.segments = {}
    container._maxPoints = maxPoints
    container._moduleName = name

    local segWidth = settings.segmentWidth or 20
    local segHeight = settings.segmentHeight or 12
    local segSpacing = settings.segmentSpacing or 2
    local borderSize = settings.borderSize or 1

    local totalWidth = maxPoints * segWidth + (maxPoints - 1) * segSpacing
    container:SetSize(totalWidth, segHeight)

    for i = 1, maxPoints do
        local seg = CreateFrame("Frame", nil, container, "BackdropTemplate")
        seg:SetSize(segWidth, segHeight)
        local xOff = (i - 1) * (segWidth + segSpacing)
        seg:SetPoint("LEFT", container, "LEFT", xOff, 0)

        -- Background (inset by border)
        seg.bg = seg:CreateTexture(nil, "BACKGROUND")
        seg.bg:SetPoint("TOPLEFT", borderSize, -borderSize)
        seg.bg:SetPoint("BOTTOMRIGHT", -borderSize, borderSize)
        seg.bg:SetColorTexture(0.15, 0.15, 0.15, 0.8)

        -- Fill (inset by border)
        seg.fill = seg:CreateTexture(nil, "ARTWORK")
        seg.fill:SetPoint("TOPLEFT", borderSize, -borderSize)
        seg.fill:SetPoint("BOTTOMRIGHT", -borderSize, borderSize)
        seg.fill:SetColorTexture(1, 1, 1, 1)
        seg.fill:Hide()

        -- Partial fill (inset by border)
        seg.partial = seg:CreateTexture(nil, "ARTWORK", nil, 1)
        seg.partial:SetPoint("LEFT", borderSize, 0)
        seg.partial:SetPoint("TOP", 0, -borderSize)
        seg.partial:SetPoint("BOTTOM", 0, borderSize)
        seg.partial:SetWidth(0)
        seg.partial:SetColorTexture(1, 1, 1, 0.4)
        seg.partial:Hide()

        -- Border
        if borderSize > 0 then
            seg:SetBackdrop({
                edgeFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeSize = borderSize,
            })
            local bc = settings.borderColor or { r = 0, g = 0, b = 0, a = 1 }
            seg:SetBackdropBorderColor(bc.r, bc.g, bc.b, bc.a)
        end

        container.segments[i] = seg
    end

    -- Drag
    container:SetScript("OnDragStart", function(self)
        if self._locked then return end
        local modSettings = RB:GetModuleSettings(self._moduleName)
        if modSettings and modSettings.anchor == "viewer" then return end
        self:StartMoving()
    end)
    container:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save CENTER-relative position for consistent restore
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local scale = self:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local x = (cx * scale) - ux
        local y = (cy * scale) - uy
        local modSettings = RB:GetModuleSettings(self._moduleName)
        modSettings.position = { point = "CENTER", relPoint = "CENTER", x = x, y = y }
    end)

    container._locked = true
    self.bars[name] = container

    -- Hook show/hide for smart stacking
    container:HookScript("OnShow", function() RB:OnBarVisibilityChanged() end)
    container:HookScript("OnHide", function() RB:OnBarVisibilityChanged() end)

    return container
end

-- ============================================================
-- Anchor helpers
-- ============================================================

-- Viewer frame names the user can anchor to
RB.ANCHOR_TARGETS = {
    essential = "EssentialCooldownViewer",
    utility   = "UtilityCooldownViewer",
    dynamicIcons = "BuffIconCooldownViewer",
    cooldownBars = "BuffBarCooldownViewer",
}

RB.ANCHOR_TARGET_LABELS = {
    essential    = "Essential",
    utility      = "Utility",
    dynamicIcons = "Dynamic Icons",
    cooldownBars = "Cooldown Bars",
}

function RB:GetViewerAnchorFrame(targetKey)
    local frameName = self.ANCHOR_TARGETS[targetKey or "essential"]
    if not frameName then return nil end
    return _G[frameName]
end

function RB:GetAnchorFrame(settings)
    if not settings or settings.anchor == "free" then return nil end
    if settings.anchor == "viewer" then
        return self:GetViewerAnchorFrame(settings.anchorTarget or "essential")
    end
    return nil
end

-- ============================================================
-- Positioning
-- ============================================================

-- Stack order for bars anchored to the same viewer.
-- "classResource" covers both segmented and stagger (only one active per spec).
RB.STACK_ORDER = { "healthBar", "powerBar", "classResource", "altPowerBar", "ironfurTracker", "monkOrbTracker", "vengeanceSoulTracker", "warriorWhirlwindTracker", "maelstromTracker" }

-- Returns true if a bar module is currently visible (enabled + bar exists + shown)
function RB:IsBarVisible(name)
    local settings = self:GetModuleSettings(name)
    if not settings or not settings.enabled then return false end
    -- classResource may be either segmented or stagger
    if name == "classResource" then
        local seg = self.bars["classResource"]
        local stag = self.bars["classResource_stagger"]
        local bar = seg or stag
        return bar and bar:IsShown()
    end
    local bar = self.bars[name]
    return bar and bar:IsShown()
end

-- Get the actual frame for a module name (classResource → whichever is active)
function RB:GetBarFrame(name)
    if name == "classResource" then
        local seg = self.bars["classResource"]
        local stag = self.bars["classResource_stagger"]
        if seg and seg:IsShown() then return seg end
        if stag and stag:IsShown() then return stag end
        return seg or stag
    end
    return self.bars[name]
end

-- Apply smart stacking for all bars anchored to a given viewer + position.
-- Bars chain in STACK_ORDER with zero spacing, skipping hidden/disabled bars.
-- The first visible bar gets the viewer offset; subsequent bars attach flush.
function RB:ApplyViewerStack(targetKey, position)
    local viewerFrame = self:GetViewerAnchorFrame(targetKey)
    if not viewerFrame then return end

    local prevFrame = viewerFrame
    local isFirst = true

    for _, name in ipairs(self.STACK_ORDER) do
        local settings = self:GetModuleSettings(name)
        if settings and settings.anchor == "viewer"
            and (settings.anchorTarget or "essential") == targetKey
            and (settings.anchorPosition or "BELOW") == position then

            -- Gather all frames for this module (classResource may have stagger)
            local frames = {}
            if name == "classResource" then
                local seg = self.bars["classResource"]
                local stag = self.bars["classResource_stagger"]
                if seg and seg:IsShown() then frames[#frames + 1] = seg end
                if stag and stag:IsShown() then frames[#frames + 1] = stag end
            else
                local bar = self.bars[name]
                if bar and bar:IsShown() then frames[#frames + 1] = bar end
            end

            for _, bar in ipairs(frames) do
                -- Width match
                if settings.widthMatchAnchor then
                    local aw = viewerFrame:GetWidth()
                    if aw and aw > 0 then
                        if bar.segments then
                            self:ResizeSegmentedBar(bar, bar._maxPoints or 5, settings)
                        else
                            bar:SetSize(aw, bar:GetHeight())
                        end
                    end
                end

                bar:ClearAllPoints()
                local offset = isFirst and (settings.anchorOffset or 2) or 0

                if position == "ABOVE" then
                    bar:SetPoint("BOTTOM", prevFrame, "TOP", 0, offset)
                elseif position == "LEFT" then
                    bar:SetPoint("RIGHT", prevFrame, "LEFT", -offset, 0)
                elseif position == "RIGHT" then
                    bar:SetPoint("LEFT", prevFrame, "RIGHT", offset, 0)
                else -- BELOW
                    bar:SetPoint("TOP", prevFrame, "BOTTOM", 0, -offset)
                end

                prevFrame = bar
                isFirst = false
            end
        end
    end
end

-- Restack all viewers that have bars anchored to them.
function RB:RestackAllViewers()
    local seen = {}
    for _, name in ipairs(self.STACK_ORDER) do
        local settings = self:GetModuleSettings(name)
        if settings and settings.anchor == "viewer" then
            local key = (settings.anchorTarget or "essential") .. "_" .. (settings.anchorPosition or "BELOW")
            if not seen[key] then
                seen[key] = true
                self:ApplyViewerStack(settings.anchorTarget or "essential", settings.anchorPosition or "BELOW")
            end
        end
    end
end

-- Position a single bar — free mode only.  Viewer bars use ApplyViewerStack.
function RB:ApplyPosition(bar, settings)
    if not bar or not settings then return end

    -- Viewer-anchored bars are positioned by ApplyViewerStack
    if settings.anchor == "viewer" then
        self:RestackAllViewers()
        return
    end

    -- Free positioning
    bar:ClearAllPoints()
    local pos = settings.position
    if pos then
        bar:SetPoint("CENTER", UIParent, "CENTER", pos.x or 0, pos.y or 0)
    else
        bar:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-- ============================================================
-- Anchor resize hooks (for width-match)
-- ============================================================
RB._anchorHooks = {}  -- [targetKey] = true if hooked

function RB:HookAnchorResize(targetKey)
    if self._anchorHooks[targetKey] then return end
    local anchorFrame = self:GetViewerAnchorFrame(targetKey)
    if not anchorFrame then return end
    self._anchorHooks[targetKey] = true
    hooksecurefunc(anchorFrame, "SetSize", function()
        RB:OnAnchorResized(targetKey)
    end)
end

function RB:OnAnchorResized(targetKey)
    -- Restack all positions for this viewer
    local positions = {}
    for _, name in ipairs(self.STACK_ORDER) do
        local settings = self:GetModuleSettings(name)
        if settings and settings.anchor == "viewer"
            and (settings.anchorTarget or "essential") == targetKey then
            local pos = settings.anchorPosition or "BELOW"
            positions[pos] = true
        end
    end
    for pos in pairs(positions) do
        self:ApplyViewerStack(targetKey, pos)
    end
end

-- ============================================================
-- Styling update
-- ============================================================
function RB:UpdateBarStyle(bar, settings)
    if not bar or not settings then return end

    local borderSize = settings.borderSize or 1

    -- bar is the wrapper frame
    if settings.widthMatchAnchor and settings.anchor == "viewer" then
        -- Width will be set by ApplyPosition from anchor, only set height
        bar:SetHeight(settings.height or 20)
    else
        bar:SetSize(settings.width or 200, settings.height or 20)
    end
    bar._borderSize = borderSize

    -- Update inner bar inset
    local inner = bar._innerBar
    if inner then
        inner:ClearAllPoints()
        inner:SetPoint("TOPLEFT", borderSize, -borderSize)
        inner:SetPoint("BOTTOMRIGHT", -borderSize, borderSize)

        local texPath = (LSM and settings.texture) and LSM:Fetch("statusbar", settings.texture) or "Interface\\TargetingFrame\\UI-StatusBar"
        inner:SetStatusBarTexture(texPath)
        local sbTex = inner:GetStatusBarTexture()
        if sbTex then
            sbTex:SetTexelSnappingBias(0)
            sbTex:SetSnapToPixelGrid(false)
        end
        if inner.bg then
            inner.bg:SetTexture(texPath)
            inner.bg:SetTexelSnappingBias(0)
            inner.bg:SetSnapToPixelGrid(false)
            local bgc = settings.bgColor or { r = 0.15, g = 0.15, b = 0.15, a = 0.8 }
            inner.bg:SetVertexColor(bgc.r, bgc.g, bgc.b, bgc.a)
        end
    end

    if bar.text then
        bar.text:SetFont(STANDARD_TEXT_FONT, settings.textSize or 12, "OUTLINE")
    end

    -- Update border
    if borderSize > 0 then
        bar:SetBackdrop({
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = borderSize,
        })
        local bc = settings.borderColor or { r = 0, g = 0, b = 0, a = 1 }
        bar:SetBackdropBorderColor(bc.r, bc.g, bc.b, bc.a)
    else
        bar:SetBackdrop(nil)
    end
end

-- ============================================================
-- Segmented bar update
-- ============================================================
function RB:UpdateSegments(container, currentPoints, maxPoints, color, partialFrac, perSegmentColors)
    if not container or not container.segments then return end
    for i = 1, (container._maxPoints or #container.segments) do
        local seg = container.segments[i]
        if not seg then break end
        if i <= maxPoints then
            seg:Show()
            local c = (perSegmentColors and perSegmentColors[i]) or color
            if i <= currentPoints then
                seg.fill:SetColorTexture(c.r or 1, c.g or 1, c.b or 1, c.a or 1)
                seg.fill:Show()
                seg.partial:Hide()
            elseif i == currentPoints + 1 and partialFrac and partialFrac > 0 then
                local modSettings = container._moduleName and RB:GetModuleSettings(container._moduleName)
                local borderSize = (modSettings and modSettings.borderSize) or 1
                local innerW = seg:GetWidth() - (borderSize * 2)
                seg.fill:Hide()
                seg.partial:ClearAllPoints()
                seg.partial:SetPoint("LEFT", borderSize, 0)
                seg.partial:SetPoint("TOP", 0, -borderSize)
                seg.partial:SetPoint("BOTTOM", 0, borderSize)
                seg.partial:SetWidth(math.max(1, innerW * partialFrac))
                seg.partial:SetColorTexture(c.r or 1, c.g or 1, c.b or 1, 0.5)
                seg.partial:Show()
            else
                seg.fill:Hide()
                seg.partial:Hide()
            end
        else
            seg:Hide()
        end
    end
end

-- ============================================================
-- Resize segmented bar for different max points
-- ============================================================
function RB:ResizeSegmentedBar(container, maxPoints, settings)
    if not container or not container.segments then return end
    local segWidth = settings.segmentWidth or 20
    local segHeight = settings.segmentHeight or 12
    local segSpacing = settings.segmentSpacing or 2
    local borderSize = settings.borderSize or 1

    -- Width-match: compute segment width from anchor width
    if settings.widthMatchAnchor and settings.anchor == "viewer" then
        local anchorFrame = self:GetAnchorFrame(settings)
        if anchorFrame then
            local anchorWidth = anchorFrame:GetWidth()
            if anchorWidth and anchorWidth > 0 and maxPoints > 0 then
                segWidth = (anchorWidth - (maxPoints - 1) * segSpacing) / maxPoints
                if segWidth < 4 then segWidth = 4 end
            end
        end
    end

    local totalWidth = maxPoints * segWidth + (maxPoints - 1) * segSpacing
    container:SetSize(totalWidth, segHeight)
    container._maxPoints = maxPoints

    for i = 1, #container.segments do
        local seg = container.segments[i]
        seg:SetSize(segWidth, segHeight)
        local xOff = (i - 1) * (segWidth + segSpacing)
        seg:ClearAllPoints()
        seg:SetPoint("LEFT", container, "LEFT", xOff, 0)

        -- Update bg/fill/partial insets for current border size
        if seg.bg then
            seg.bg:ClearAllPoints()
            seg.bg:SetPoint("TOPLEFT", borderSize, -borderSize)
            seg.bg:SetPoint("BOTTOMRIGHT", -borderSize, borderSize)
        end
        if seg.fill then
            seg.fill:ClearAllPoints()
            seg.fill:SetPoint("TOPLEFT", borderSize, -borderSize)
            seg.fill:SetPoint("BOTTOMRIGHT", -borderSize, borderSize)
        end
        if seg.partial then
            seg.partial:ClearAllPoints()
            seg.partial:SetPoint("LEFT", borderSize, 0)
            seg.partial:SetPoint("TOP", 0, -borderSize)
            seg.partial:SetPoint("BOTTOM", 0, borderSize)
        end

        -- Update border backdrop
        if borderSize > 0 then
            seg:SetBackdrop({
                edgeFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeSize = borderSize,
            })
            local bc = settings.borderColor or { r = 0, g = 0, b = 0, a = 1 }
            seg:SetBackdropBorderColor(bc.r, bc.g, bc.b, bc.a)
        else
            seg:SetBackdrop(nil)
        end

        -- Hide segments beyond the active max
        if i > maxPoints then
            seg:Hide()
        else
            seg:Show()
        end
    end
end

-- ============================================================
-- Text formatting  (taint-safe — exact PRD patterns)
-- ============================================================

-- Safe helper: call a function that may return a secret/tainted number.
-- Uses pcall to catch taint; returns the value (possibly secret) or nil.
function RB:SafeNumberCall(fn, ...)
    local ok, res = pcall(fn, ...)
    if not ok then return nil end
    if type(res) == "number" then return res end
    local n = tonumber(res)
    if type(n) == "number" then return n end
    return nil
end

-- Safely retrieve UnitPower / UnitPowerMax
function RB:SafeGetUnitPower(unit, powerType)
    local cur = self:SafeNumberCall(UnitPower, unit, powerType)
    local max = self:SafeNumberCall(UnitPowerMax, unit, powerType)
    return cur, max
end

-- Safely retrieve UnitHealth / UnitHealthMax
function RB:SafeGetUnitHealth(unit)
    local cur = self:SafeNumberCall(UnitHealth, unit)
    local max = self:SafeNumberCall(UnitHealthMax, unit)
    return cur, max
end

-- Abbreviate helper — exact PRD pattern.
-- Calls Blizzard's GLOBAL AbbreviateNumbers (FrameXML built-in).
-- It handles secret/tainted numbers natively. Fallback: tostring.
local function abbr(val)
    if type(AbbreviateNumbers) == "function" and type(val) == "number" then
        return AbbreviateNumbers(val)
    end
    return tostring(val)
end

-- Make accessible for other modules (e.g. ClassResources stagger)
function RB:AbbreviateNumbers(val)
    return abbr(val)
end

-- SafeUnitHealthPercent — exact copy of PRD PlayerHealthText.lua
-- Returns a secret number 0-100 (or nil).
function RB:SafeUnitHealthPercent(unit)
    if type(UnitHealthPercent) == "function" then
        local curve = _G.CurveConstants and _G.CurveConstants.ScaleTo100 or nil
        local ok, val = pcall(UnitHealthPercent, unit, false, curve)
        if ok and type(val) == "number" then
            return val
        end
    end
    return nil
end

-- FormatBarText — copied directly from PRD PlayerPowerText.lua / PlayerHealthText.lua patterns.
-- barType: "health" or "power"
function RB:FormatBarText(fontString, current, max, format, barType)
    if not fontString then return end
    if type(current) ~= "number" or type(max) ~= "number" then
        fontString:SetText("")
        return
    end

    -- Percent calculation (PRD PlayerPowerText.lua pattern)
    local pct = nil
    if barType == "health" then
        pct = RB:SafeUnitHealthPercent("player")
    else
        if max > 0 then
            local ok, result = pcall(function() return (current / max) * 100 end)
            if ok and type(result) == "number" and result == result then
                pct = result
            end
        end
    end

    -- Display — exact PRD PlayerPowerText.lua format branches
    if format == "percent" and pct then
        fontString:SetFormattedText("%.0f%%", pct)
    elseif format == "current" and type(current) == "number" then
        if type(AbbreviateNumbers) == "function" then
            fontString:SetText(AbbreviateNumbers(current))
        else
            fontString:SetFormattedText("%d", current)
        end
    elseif format == "both" and type(current) == "number" and type(max) == "number" and pct then
        if type(AbbreviateNumbers) == "function" then
            fontString:SetText(AbbreviateNumbers(current) .. " / " .. AbbreviateNumbers(max) .. " (" .. string.format("%.0f%%", pct) .. ")")
        else
            fontString:SetFormattedText("%d / %d (%.0f%%)", current, max, pct)
        end
    elseif format == "deficit" then
        fontString:SetFormattedText("-%d", current)
    else
        fontString:SetFormattedText("%d", current)
    end
end

-- ============================================================
-- Visibility helpers
-- ============================================================
function RB:ShouldShow(settings)
    if not settings.enabled then return false end
    if settings.hideWhenMounted and IsMounted and IsMounted() then return false end
    if settings.hideOutOfCombat and not InCombatLockdown() then return false end
    return true
end

-- Called when any bar's visibility changes — restacks viewer chains
RB._restacking = false
function RB:OnBarVisibilityChanged()
    if self._restacking then return end
    self._restacking = true
    self:RestackAllViewers()
    self._restacking = false
end

-- ============================================================
-- Module registration
-- ============================================================
function RB:RegisterModule(name, module)
    self.modules[name] = module
end

-- One-time migration: force anchor defaults on existing profiles
function RB:MigrateAnchorDefaults()
    local settings = self:GetSettings()
    if not settings then return end
    if settings._anchorMigrationDone then return end
    local allModules = {
        "healthBar", "powerBar", "altPowerBar", "ironfurTracker",
        "monkOrbTracker", "vengeanceSoulTracker", "warriorWhirlwindTracker",
        "maelstromTracker", "classResource",
    }
    for _, name in ipairs(allModules) do
        local mod = settings[name]
        if mod then
            mod.anchor = "viewer"
            mod.anchorTarget = "essential"
            mod.anchorPosition = "ABOVE"
            mod.anchorOffset = 0
            mod.widthMatchAnchor = true
        end
    end
    settings._anchorMigrationDone = true
end

function RB:InitAllModules()
    self:MigrateAnchorDefaults()
    local class = self:GetPlayerClass()
    local specID = self:GetPlayerSpec()
    for name, mod in pairs(self.modules) do
        if mod.Init then
            mod:Init(class, specID)
        end
    end
    self:SetupAnchorHooks()
end

function RB:SetupAnchorHooks()
    for name, _ in pairs(self.modules) do
        local settings = self:GetModuleSettings(name)
        if settings and settings.anchor == "viewer" and settings.widthMatchAnchor then
            self:HookAnchorResize(settings.anchorTarget or "essential")
        end
    end
end

function RB:RefreshAllModules()
    local class = self:GetPlayerClass()
    local specID = self:GetPlayerSpec()
    for name, mod in pairs(self.modules) do
        if mod.Refresh then
            mod:Refresh(class, specID)
        end
    end
end

function RB:OnSpecChanged()
    self.playerSpec = nil
    local specID = self:GetPlayerSpec()
    local class = self:GetPlayerClass()
    for name, mod in pairs(self.modules) do
        if mod.OnSpecChanged then
            mod:OnSpecChanged(class, specID)
        end
    end
end

-- ============================================================
-- Event frame
-- ============================================================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        RB:GetPlayerClass()
        RB:GetPlayerSpec()
        C_Timer.After(0.5, function()
            RB:InitAllModules()
        end)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        C_Timer.After(0.2, function()
            RB:OnSpecChanged()
        end)
    end
end)
