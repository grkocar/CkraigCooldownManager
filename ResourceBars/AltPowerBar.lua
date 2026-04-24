-- ============================================================
-- CkraigCooldownManager :: ResourceBars :: AltPowerBar
-- ============================================================
-- Alternate power bar (used in some encounters/quests).
-- For DH Devourer spec: shows soul bar with tick marks every 5.
-- ============================================================

local RB = CCM_ResourceBars
if not RB then return end

local AltPowerBar = {}
local bar = nil

-- ============================================================
-- Devourer (DH spec 3) tick marks — mirrors PRD DevourText.lua
-- ============================================================
local TICK_TALENT_SPELL_ID = 1247534  -- talent that changes max to 35
local TICK_WIDTH  = 2
local TICK_COLOR  = { 0, 0, 0, 1 }   -- black dividers

local tickPool       = {}
local lastTickMax    = nil
local lastTickBarW   = nil
local lastTickBarH   = nil
local inVoidMetamorphosis = false

-- Cached IsDevourer result — invalidated on PLAYER_SPECIALIZATION_CHANGED
local _isDevourerCached = nil
local function IsDevourer()
    if _isDevourerCached ~= nil then return _isDevourerCached end
    local _, class = UnitClass("player")
    if class ~= "DEMONHUNTER" then
        _isDevourerCached = false
        return false
    end
    local spec = GetSpecialization and GetSpecialization()
    _isDevourerCached = (spec == 3)
    return _isDevourerCached
end
local function InvalidateDevourerCache()
    _isDevourerCached = nil
end

-- PRD DevourText.lua exact pattern: read soul count from aura stacks
local function GetDevourValue()
    if not (Constants and Constants.UnitPowerSpellIDs) then return 0 end
    if inVoidMetamorphosis and Constants.UnitPowerSpellIDs.SILENCE_THE_WHISPERS_SPELL_ID then
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(Constants.UnitPowerSpellIDs.SILENCE_THE_WHISPERS_SPELL_ID)
        if aura then return aura.applications or 0 end
    elseif Constants.UnitPowerSpellIDs.DARK_HEART_SPELL_ID then
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(Constants.UnitPowerSpellIDs.DARK_HEART_SPELL_ID)
        if aura then return aura.applications or 0 end
    end
    return 0
end

local function UpdateVoidMetamorphosisState()
    if Constants and Constants.UnitPowerSpellIDs and Constants.UnitPowerSpellIDs.VOID_METAMORPHOSIS_SPELL_ID then
        inVoidMetamorphosis = C_UnitAuras.GetPlayerAuraBySpellID(Constants.UnitPowerSpellIDs.VOID_METAMORPHOSIS_SPELL_ID) and true or false
    end
end

local function GetDevourerMax()
    if inVoidMetamorphosis then
        return 30
    end
    local hasTalent = IsPlayerSpell and IsPlayerSpell(TICK_TALENT_SPELL_ID) or false
    return hasTalent and 35 or 50
end

local function GetOrCreateTick(index, parent)
    if tickPool[index] then return tickPool[index] end
    -- Use a child frame so ticks render above the StatusBar texture
    local tickFrame = CreateFrame("Frame", nil, parent)
    tickFrame:SetFrameLevel(parent:GetFrameLevel() + 5)
    local tick = tickFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    tick:SetColorTexture(TICK_COLOR[1], TICK_COLOR[2], TICK_COLOR[3], TICK_COLOR[4])
    tick._frame = tickFrame
    tickPool[index] = tick
    return tick
end

local function HideAllTicks()
    for i = 1, #tickPool do
        tickPool[i]:Hide()
        if tickPool[i]._frame then tickPool[i]._frame:Hide() end
    end
    lastTickMax = nil
    lastTickBarW = nil
    lastTickBarH = nil
end

local function BuildTicks(forceRebuild)
    if not bar or not IsDevourer() then
        HideAllTicks()
        return
    end

    UpdateVoidMetamorphosisState()
    local maxSouls = GetDevourerMax()
    local numTicks = (maxSouls / 5) - 1  -- internal dividers only

    local barWidth  = bar:GetWidth()
    local barHeight = bar:GetHeight()
    if barWidth  == 0 then barWidth  = 200 end
    if barHeight == 0 then barHeight = 20  end

    if not forceRebuild
        and lastTickMax  == maxSouls
        and lastTickBarW == barWidth
        and lastTickBarH == barHeight then
        return
    end
    lastTickMax  = maxSouls
    lastTickBarW = barWidth
    lastTickBarH = barHeight

    -- Hide old ticks
    for i = 1, #tickPool do
        tickPool[i]:Hide()
        if tickPool[i]._frame then tickPool[i]._frame:Hide() end
    end

    for i = 1, numTicks do
        local tick = GetOrCreateTick(i, bar)
        local tf = tick._frame
        tf:SetSize(TICK_WIDTH, barHeight)
        tf:ClearAllPoints()
        local xOffset = (barWidth / (numTicks + 1)) * i
        tf:SetPoint("LEFT", bar, "LEFT", xOffset - (TICK_WIDTH / 2), 0)
        tick:SetAllPoints(tf)
        tf:Show()
        tick:Show()
    end
end

-- ============================================================
-- AltPowerBar module
-- ============================================================
function AltPowerBar:Init(class, specID)
    local settings = RB:EnsureDefaults("altPowerBar")
    if bar then
        self:Refresh(class, specID)
        return
    end

    bar = RB:CreateStatusBar("altPowerBar", UIParent, settings)
    bar:SetMinMaxValues(0, 1)

    -- Text overlay frame above tick marks (ticks are at +5, text at +6)
    local textOverlay = CreateFrame("Frame", nil, bar)
    textOverlay:SetAllPoints(bar)
    textOverlay:SetFrameLevel(bar:GetFrameLevel() + 6)
    if bar.text then
        bar.text:SetParent(textOverlay)
    end

    bar.nameText = textOverlay:CreateFontString(nil, "OVERLAY")
    bar.nameText:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
    bar.nameText:SetPoint("TOP", bar, "BOTTOM", 0, -2)

    bar:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    bar:RegisterUnitEvent("UNIT_POWER_BAR_SHOW", "player")
    bar:RegisterUnitEvent("UNIT_POWER_BAR_HIDE", "player")
    bar:RegisterEvent("PLAYER_ENTERING_WORLD")
    bar:RegisterUnitEvent("UNIT_AURA", "player")
    bar:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    bar:RegisterEvent("TRAIT_CONFIG_UPDATED")
    bar:RegisterEvent("PLAYER_TALENT_UPDATE")
    bar:SetScript("OnEvent", function(self, event, unit)
        if event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_BAR_SHOW"
            or event == "UNIT_POWER_BAR_HIDE" or event == "UNIT_AURA" then
            if unit and unit ~= "player" then return end
        end
        -- Track void metamorphosis state changes for tick rebuilds
        if event == "UNIT_AURA" then
            local wasVoid = inVoidMetamorphosis
            UpdateVoidMetamorphosisState()
            if inVoidMetamorphosis ~= wasVoid then
                BuildTicks(true)
            end
        elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "TRAIT_CONFIG_UPDATED"
            or event == "PLAYER_TALENT_UPDATE" then
            InvalidateDevourerCache()
            C_Timer.After(0.2, function() BuildTicks(true) end)
        end
        AltPowerBar:Update()
    end)

    RB:ApplyPosition(bar, settings)
    self:ApplyColor()
    self:Update()
end

function AltPowerBar:Update()
    if not bar then return end
    local settings = RB:GetModuleSettings("altPowerBar")

    if not RB:ShouldShow(settings) then
        bar:Hide()
        HideAllTicks()
        return
    end

    -- Devourer DH: always show when in spec 3, using soul count
    local isDevourer = IsDevourer()

    if not isDevourer then
        -- Generic: check if alt power bar is active
        local barType = UnitAlternatePowerInfo and UnitAlternatePowerInfo("player")
        if not barType then
            bar:Hide()
            HideAllTicks()
            return
        end
    end

    local power, maxPower

    if isDevourer then
        -- PRD DevourText pattern: read soul count from aura stacks (clean number)
        -- Note: UpdateVoidMetamorphosisState already called in OnEvent for UNIT_AURA
        UpdateVoidMetamorphosisState()
        power = GetDevourValue()
        maxPower = GetDevourerMax()
    else
        power, maxPower = RB:SafeGetUnitPower("player", Enum.PowerType.Alternate)
        if not power then power = 0 end
    end

    if not maxPower or maxPower == 0 then maxPower = 1 end

    -- Only update min/max when it changes
    if maxPower ~= bar._lastMax then
        bar:SetMinMaxValues(0, maxPower)
        bar._lastMax = maxPower
    end
    bar:SetValue(power)

    -- Text
    if settings.showText and bar.text then
        RB:FormatBarText(bar.text, power, maxPower, "current", "power")
        bar.text:Show()
    elseif bar.text then
        bar.text:Hide()
    end

    -- Show bar name if available
    if isDevourer then
        if bar.nameText then bar.nameText:SetText(""); bar.nameText:Hide() end
    else
        local barInfo = UnitAlternatePowerInfo and select(10, UnitAlternatePowerInfo("player"))
        if barInfo and bar.nameText then
            bar.nameText:SetText(barInfo)
        end
    end

    bar:Show()

    -- Build / refresh tick marks for Devourer
    BuildTicks()
end

-- Apply color (called from Refresh/Init only, not every Update tick)
function AltPowerBar:ApplyColor()
    if not bar then return end
    local settings = RB:GetModuleSettings("altPowerBar")
    local c = settings.customColor or { r = 0.9, g = 0.6, b = 0.1, a = 1 }
    if settings.useGradient then
        local gs = settings.gradientStart or c
        local ge = settings.gradientEnd or c
        local sbTex = bar:GetStatusBarTexture()
        if sbTex and sbTex.SetGradient then
            local cs, ce = RB:GetGradientColors()
            cs:SetRGBA(gs.r, gs.g, gs.b, gs.a or 1)
            ce:SetRGBA(ge.r, ge.g, ge.b, ge.a or 1)
            sbTex:SetGradient("HORIZONTAL", cs, ce)
        else
            bar:SetStatusBarColor(c.r, c.g, c.b, c.a or 1)
        end
    else
        bar:SetStatusBarColor(c.r, c.g, c.b, c.a or 1)
    end
end

function AltPowerBar:Refresh(class, specID)
    if not bar then return end
    local settings = RB:EnsureDefaults("altPowerBar")
    RB:UpdateBarStyle(bar, settings)
    RB:ApplyPosition(bar, settings)
    InvalidateDevourerCache()
    self:ApplyColor()
    self:Update()
end

function AltPowerBar:HideAll()
    if bar then
        bar:Hide()
    end
    HideAllTicks()
end

function AltPowerBar:OnSpecChanged(class, specID)
    self:Refresh(class, specID)
    BuildTicks(true)
end

RB:RegisterModule("altPowerBar", AltPowerBar)
