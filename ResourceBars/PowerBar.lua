-- ============================================================
-- CkraigCooldownManager :: ResourceBars :: PowerBar
-- ============================================================
-- Player power status bar (mana, rage, energy, etc.) with
-- automatic power type detection per spec.
-- ============================================================

local RB = CCM_ResourceBars
if not RB then return end

local PowerBar = {}
local bar = nil

-- Cached power type — invalidated on spec change / shapeshift / displaypower change
local _cachedPowerType = nil
local _cachedClass = nil

local function InvalidatePowerTypeCache()
    _cachedPowerType = nil
end

function PowerBar:Init(class, specID)
    local settings = RB:EnsureDefaults("powerBar")
    _cachedPowerType = nil
    if bar then
        self:Refresh(class, specID)
        return
    end

    bar = RB:CreateStatusBar("powerBar", UIParent, settings)
    bar:SetMinMaxValues(0, 1)

    bar:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    bar:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    bar:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
    bar:RegisterEvent("PLAYER_ENTERING_WORLD")
    bar:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    bar:RegisterEvent("PLAYER_REGEN_ENABLED")
    bar:RegisterEvent("PLAYER_REGEN_DISABLED")
    bar:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    bar:SetScript("OnEvent", function(self, event, unit)
        if unit and unit ~= "player" then return end
        -- Invalidate power type cache on events that can change it
        if event == "UNIT_DISPLAYPOWER" or event == "UPDATE_SHAPESHIFT_FORM" then
            InvalidatePowerTypeCache()
            PowerBar:ApplyColor()
        end
        PowerBar:Update()
    end)

    RB:ApplyPosition(bar, settings)
    self:ApplyColor()
    self:Update()
end

function PowerBar:GetCurrentPowerType()
    if _cachedPowerType then return _cachedPowerType end
    if not _cachedClass then
        local _, cls = UnitClass("player")
        _cachedClass = cls
    end
    if _cachedClass == "DRUID" then
        -- Druids change power type based on shapeshift form — don't cache across forms
        return UnitPowerType("player")
    end
    _cachedPowerType = RB:GetPlayerPowerType()
    return _cachedPowerType
end

function PowerBar:Update()
    if not bar then return end
    local settings = RB:GetModuleSettings("powerBar")

    if not RB:ShouldShow(settings) then
        bar:Hide()
        return
    end

    local powerType = self:GetCurrentPowerType()
    local power, maxPower = RB:SafeGetUnitPower("player", powerType)
    if not power then power = 0 end
    if not maxPower or maxPower == 0 then maxPower = 1 end

    if maxPower ~= bar._lastMax then
        bar:SetMinMaxValues(0, maxPower)
        bar._lastMax = maxPower
    end
    bar:SetValue(power)
    bar:Show()

    -- Text
    if settings.showText and bar.text then
        RB:FormatBarText(bar.text, power, maxPower, settings.textFormat or "current", "power")
        bar.text:Show()
    elseif bar.text then
        bar.text:Hide()
    end
end

-- Apply color settings (called from Refresh/Init only — not every Update tick)
function PowerBar:ApplyColor()
    if not bar then return end
    local settings = RB:GetModuleSettings("powerBar")
    local powerType = self:GetCurrentPowerType()
    if settings.useGradient then
        local gs = settings.gradientStart or settings.customColor or { r = 0.2, g = 0.2, b = 0.8, a = 1 }
        local ge = settings.gradientEnd or settings.customColor or { r = 0.0, g = 0.0, b = 0.5, a = 1 }
        local sbTex = bar:GetStatusBarTexture()
        if sbTex and sbTex.SetGradient then
            local cs, ce = RB:GetGradientColors()
            cs:SetRGBA(gs.r, gs.g, gs.b, gs.a or 1)
            ce:SetRGBA(ge.r, ge.g, ge.b, ge.a or 1)
            sbTex:SetGradient("HORIZONTAL", cs, ce)
        else
            local c = settings.customColor or { r = 0.2, g = 0.2, b = 0.8, a = 1 }
            bar:SetStatusBarColor(c.r, c.g, c.b, c.a or 1)
        end
    elseif settings.usePowerColor then
        local pc = RB.POWER_COLORS[powerType] or { r = 0.2, g = 0.2, b = 0.8 }
        bar:SetStatusBarColor(pc.r, pc.g, pc.b, 1)
    else
        local c = settings.customColor or { r = 0.2, g = 0.2, b = 0.8, a = 1 }
        bar:SetStatusBarColor(c.r, c.g, c.b, c.a or 1)
    end
end

function PowerBar:Refresh(class, specID)
    if not bar then return end
    local settings = RB:EnsureDefaults("powerBar")
    RB:UpdateBarStyle(bar, settings)
    RB:ApplyPosition(bar, settings)
    InvalidatePowerTypeCache()
    self:ApplyColor()
    self:Update()
end

function PowerBar:OnSpecChanged(class, specID)
    InvalidatePowerTypeCache()
    self:Refresh(class, specID)
end

RB:RegisterModule("powerBar", PowerBar)
