-- ============================================================
-- CkraigCooldownManager :: ResourceBars :: WarriorWhirlwindTracker
-- ============================================================
-- Tracks Improved Whirlwind stacks for Fury Warrior.
-- Displayed as a single StatusBar with divider ticks.
-- Based on WarriorTracker.lua by Ckraigfriend (GPL-3.0).
-- ============================================================

local RB = CCM_ResourceBars
if not RB then return end

local LSM = LibStub("LibSharedMedia-3.0", true)

local WarriorWhirlwindTracker = {}
local wrapper = nil
local bar = nil
local ticks = {}
local updateFrame = nil
local eventFrame = nil

-- ============================================================
-- Constants
-- ============================================================
local IW_MAX_STACKS = 4
local IW_DURATION = 20
local DEFAULT_NUM_SEGMENTS = 4
local REQUIRED_TALENT_ID = 12950    -- Improved Whirlwind
local UNHINGED_TALENT_ID = 386628   -- Unhinged
local THUNDER_BLAST_ID = 435607

local GENERATOR_IDS = {
    [190411] = true,  -- Whirlwind
    [435607] = true,  -- Thunder Blast
}

local SPENDER_IDS = {
    [23881]  = true,  -- Bloodthirst
    [85288]  = true,  -- Raging Blow
    [280735] = true,  -- Execute
    [202168] = true,  -- Impending Victory
    [184367] = true,  -- Rampage
    [335096] = true,  -- Bloodbath
    [335097] = true,  -- Crushing Blow
    [5308]   = true,  -- Execute (base)
}

-- ============================================================
-- Whirlwind stack state
-- ============================================================
local iwStacks = 0
local iwExpiresAt = nil
local noConsumeUntil = 0
local seenCastGUID = {}

-- ============================================================
-- Helpers
-- ============================================================
local function IsFuryWarrior()
    local _, class = UnitClass("player")
    if class ~= "WARRIOR" then return false end
    local spec = GetSpecialization()
    return spec == 2
end

local function HasUnhingedTalent()
    return C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(UNHINGED_TALENT_ID) or false
end

local function GetStacks()
    if iwExpiresAt and GetTime() >= iwExpiresAt then
        iwStacks = 0
        iwExpiresAt = nil
    end
    return IW_MAX_STACKS, iwStacks or 0
end

-- ============================================================
-- Spell event handler
-- ============================================================
local function OnSpellEvent(event, unit, castGUID, spellID)
    if event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" then
        iwStacks = 0
        iwExpiresAt = nil
        seenCastGUID = {}
        return
    end

    if unit ~= "player" then return end
    if event ~= "UNIT_SPELLCAST_SUCCEEDED" then return end
    if castGUID and seenCastGUID[castGUID] then return end
    if castGUID then seenCastGUID[castGUID] = true end

    -- Unhinged: certain spells prevent consumption for 2s
    if HasUnhingedTalent() and (
        spellID == 50622 or spellID == 46924 or spellID == 227847 or
        spellID == 184362 or spellID == 446035
    ) then
        noConsumeUntil = GetTime() + 2
    end

    -- Generators: Whirlwind / Thunder Blast
    if GENERATOR_IDS[spellID] or (spellID == 6343 and C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(THUNDER_BLAST_ID)) then
        local hasTarget = UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target")
        if hasTarget then
            -- Range check
            if C_Spell and C_Spell.IsSpellInRange then
                local inRange = C_Spell.IsSpellInRange(spellID, "target")
                if inRange == false then return end
            end
        end
        C_Timer.After(0.15, function()
            if UnitAffectingCombat("player") then
                iwStacks = IW_MAX_STACKS
                iwExpiresAt = GetTime() + IW_DURATION
            end
        end)
        return
    end

    -- Spenders
    if SPENDER_IDS[spellID] then
        if (GetTime() < noConsumeUntil) and (spellID == 23881) then return end
        if (iwStacks or 0) <= 0 then return end
        iwStacks = math.max(0, (iwStacks or 0) - 1)
        if iwStacks == 0 then iwExpiresAt = nil end
        return
    end
end

-- ============================================================
-- Tick dividers
-- ============================================================
local function UpdateTicks(numSegments)
    for _, tick in ipairs(ticks) do tick:Hide() end
    if not bar then return end
    local w = bar:GetWidth()
    local h = bar:GetHeight()
    for i = 1, (numSegments or DEFAULT_NUM_SEGMENTS) - 1 do
        if not ticks[i] then
            local tf = CreateFrame("Frame", nil, bar)
            tf:SetFrameLevel(bar:GetFrameLevel() + 5)
            ticks[i] = tf:CreateTexture(nil, "OVERLAY", nil, 7)
            ticks[i]:SetColorTexture(0, 0, 0, 1)
            ticks[i]._frame = tf
        end
        local tf = ticks[i]._frame
        tf:SetSize(2, h)
        tf:ClearAllPoints()
        tf:SetPoint("LEFT", bar, "LEFT", i * (w / (numSegments or DEFAULT_NUM_SEGMENTS)) - 1, 0)
        ticks[i]:SetAllPoints(tf)
        tf:Show()
        ticks[i]:Show()
    end
end

-- ============================================================
-- Apply bar texture + gradient/color
-- ============================================================
local function ApplyBarAppearance(settings)
    if not bar then return end

    local textureKey = settings.texture or "Blizzard Raid Bar"
    local texture = (LSM and LSM:Fetch("statusbar", textureKey)) or "Interface\\TargetingFrame\\UI-StatusBar"
    bar:SetStatusBarTexture(texture)
    local sbTex = bar:GetStatusBarTexture()
    if sbTex then
        sbTex:SetTexelSnappingBias(0)
        sbTex:SetSnapToPixelGrid(false)
    end

    local gs = settings.gradientStart
    local ge = settings.gradientEnd
    if gs and ge and sbTex and sbTex.SetGradient then
        sbTex:SetGradient("HORIZONTAL",
            CreateColor(gs.r, gs.g, gs.b, gs.a or 1),
            CreateColor(ge.r, ge.g, ge.b, ge.a or 1)
        )
    else
        local c = settings.barColor or { r = 0.78, g = 0.61, b = 0.43, a = 1 }
        bar:SetStatusBarColor(c.r, c.g, c.b, c.a or 1)
    end

    if bar.bg then
        local bgTexKey = settings.bgTexture
        local bgc = settings.bgColor or { r = 0.08, g = 0.08, b = 0.08, a = 0.75 }
        if bgTexKey and bgTexKey ~= "" and LSM then
            local path = LSM:Fetch("statusbar", bgTexKey)
            if path then
                bar.bg:SetTexture(path)
                bar.bg:SetTexelSnappingBias(0)
                bar.bg:SetSnapToPixelGrid(false)
                bar.bg:SetVertexColor(bgc.r, bgc.g, bgc.b, bgc.a or 0.75)
            else
                bar.bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bgc.a or 0.75)
                bar.bg:SetVertexColor(1, 1, 1, 1)
            end
        else
            bar.bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bgc.a or 0.75)
            bar.bg:SetVertexColor(1, 1, 1, 1)
        end
    end
end

-- ============================================================
-- Core update
-- ============================================================
local function UpdateTracker()
    if not wrapper then return end
    local settings = RB:GetModuleSettings("warriorWhirlwindTracker")

    if not IsFuryWarrior() or not RB:ShouldShow(settings) then
        wrapper:Hide()
        return
    end

    local numSegments = settings.numSegments or DEFAULT_NUM_SEGMENTS
    local _, stacks = GetStacks()

    bar:SetMinMaxValues(0, numSegments)
    bar:SetValue(math.max(0, math.min(numSegments, stacks)))
    wrapper:Show()
end

-- ============================================================
-- Module interface
-- ============================================================
function WarriorWhirlwindTracker:Init(class, specID)
    if class ~= "WARRIOR" then return end

    local settings = RB:EnsureDefaults("warriorWhirlwindTracker")

    if wrapper then
        self:Refresh(class, specID)
        return
    end

    local borderSize = settings.borderSize or 1
    wrapper = CreateFrame("Frame", "CCM_RB_warriorWhirlwindTracker", UIParent, "BackdropTemplate")
    wrapper:SetSize(settings.width or 120, settings.height or 24)
    wrapper:SetMovable(true)
    wrapper:EnableMouse(true)
    wrapper:RegisterForDrag("LeftButton")
    wrapper:SetClampedToScreen(true)
    wrapper:SetFrameStrata("MEDIUM")
    wrapper._moduleName = "warriorWhirlwindTracker"
    wrapper._locked = true
    wrapper._borderSize = borderSize

    if borderSize > 0 then
        wrapper:SetBackdrop({
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = borderSize,
        })
        local bc = settings.borderColor or { r = 0, g = 0, b = 0, a = 1 }
        wrapper:SetBackdropBorderColor(bc.r, bc.g, bc.b, bc.a)
    end

    bar = CreateFrame("StatusBar", nil, wrapper)
    bar:SetPoint("TOPLEFT", borderSize, -borderSize)
    bar:SetPoint("BOTTOMRIGHT", -borderSize, borderSize)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()

    wrapper:SetScript("OnDragStart", function(self)
        if self._locked then return end
        local modSettings = RB:GetModuleSettings("warriorWhirlwindTracker")
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
        local modSettings = RB:GetModuleSettings("warriorWhirlwindTracker")
        modSettings.position = { point = "CENTER", relPoint = "CENTER", x = x, y = y }
    end)

    RB.bars["warriorWhirlwindTracker"] = wrapper

    wrapper:HookScript("OnShow", function() RB:OnBarVisibilityChanged() end)
    wrapper:HookScript("OnHide", function() RB:OnBarVisibilityChanged() end)

    bar:SetScript("OnSizeChanged", function()
        local s = RB:GetModuleSettings("warriorWhirlwindTracker")
        UpdateTicks(s and s.numSegments or DEFAULT_NUM_SEGMENTS)
    end)

    -- Events
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        eventFrame:RegisterEvent("PLAYER_DEAD")
        eventFrame:RegisterEvent("PLAYER_ALIVE")
        eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
        eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
        eventFrame:SetScript("OnEvent", function(_, event, unit, castGUID, spellID)
            if event == "UNIT_SPELLCAST_SUCCEEDED" or event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" then
                OnSpellEvent(event, unit, castGUID, spellID)
            end
            UpdateTracker()
        end)
    end

    -- OnUpdate for smooth polling & expiration checks
    if not updateFrame then
        updateFrame = CreateFrame("Frame")
    end
    updateFrame:SetScript("OnUpdate", function(self, elapsed)
        self._elapsed = (self._elapsed or 0) + elapsed
        if self._elapsed < 0.066 then return end
        self._elapsed = 0
        UpdateTracker()
    end)
    updateFrame:Show()

    ApplyBarAppearance(settings)
    UpdateTicks(settings.numSegments or DEFAULT_NUM_SEGMENTS)
    RB:ApplyPosition(wrapper, settings)
    UpdateTracker()
end

function WarriorWhirlwindTracker:Refresh(class, specID)
    if class ~= "WARRIOR" or not IsFuryWarrior() then
        self:HideAll()
        return
    end
    if not wrapper then
        self:Init(class, specID)
        return
    end

    local settings = RB:EnsureDefaults("warriorWhirlwindTracker")

    if updateFrame and not updateFrame:GetScript("OnUpdate") then
        updateFrame:SetScript("OnUpdate", function(self, elapsed)
            self._elapsed = (self._elapsed or 0) + elapsed
            if self._elapsed < 0.066 then return end
            self._elapsed = 0
            UpdateTracker()
        end)
        updateFrame:Show()
    end

    wrapper:SetSize(settings.width or 120, settings.height or 24)
    local borderSize = settings.borderSize or 1
    wrapper._borderSize = borderSize
    if borderSize > 0 then
        wrapper:SetBackdrop({
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = borderSize,
        })
        local bc = settings.borderColor or { r = 0, g = 0, b = 0, a = 1 }
        wrapper:SetBackdropBorderColor(bc.r, bc.g, bc.b, bc.a)
    else
        wrapper:SetBackdrop(nil)
    end

    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", borderSize, -borderSize)
    bar:SetPoint("BOTTOMRIGHT", -borderSize, borderSize)

    ApplyBarAppearance(settings)
    UpdateTicks(settings.numSegments or DEFAULT_NUM_SEGMENTS)
    RB:ApplyPosition(wrapper, settings)
    UpdateTracker()
end

function WarriorWhirlwindTracker:HideAll()
    if wrapper then wrapper:Hide() end
    if updateFrame then
        updateFrame:SetScript("OnUpdate", nil)
        updateFrame:Hide()
    end
end

function WarriorWhirlwindTracker:OnSpecChanged(class, specID)
    if class ~= "WARRIOR" or not IsFuryWarrior() then
        self:HideAll()
        return
    end
    self:Refresh(class, specID)
end

function WarriorWhirlwindTracker:Update()
    UpdateTracker()
end

RB:RegisterModule("warriorWhirlwindTracker", WarriorWhirlwindTracker)
