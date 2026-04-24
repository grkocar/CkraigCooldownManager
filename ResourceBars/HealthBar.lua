-- ============================================================
-- CkraigCooldownManager :: ResourceBars :: HealthBar
-- ============================================================
-- Player health status bar with absorb overlay, class color,
-- text display, and configurable positioning.
-- ============================================================

local RB = CCM_ResourceBars
if not RB then return end

local HealthBar = {}
local bar = nil
local absorbBar = nil
local menuButton = nil

-- Hide/show helpers for the secure menuButton
-- All secure frame APIs (Hide/Show/EnableMouse) are protected in combat,
-- so we only use SetAlpha and skip the rest during combat lockdown.
local _menuPendingState = nil  -- "show" or "hide" deferred until combat ends

local function HideMenuButton()
    if not menuButton then return end
    menuButton:SetAlpha(0)
    if not InCombatLockdown() then
        menuButton:EnableMouse(false)
        _menuPendingState = nil
    else
        _menuPendingState = "hide"
    end
end

local function ShowMenuButton()
    if not menuButton then return end
    menuButton:SetAlpha(1)
    if not InCombatLockdown() then
        menuButton:EnableMouse(true)
        _menuPendingState = nil
    else
        _menuPendingState = "show"
    end
end

-- Flush any deferred state when combat ends
local function FlushMenuPending()
    if not menuButton then return end
    if _menuNeedsSync then
        SyncMenuButtonPosition()
    end
    if _menuPendingState == "hide" then
        menuButton:EnableMouse(false)
    elseif _menuPendingState == "show" then
        menuButton:EnableMouse(true)
    end
    _menuPendingState = nil
end

-- Position the secure menuButton to match the health bar without anchoring to it
-- (anchoring a SecureUnitButtonTemplate to bar would taint bar:Show/Hide)
local _menuNeedsSync = false

local function SyncMenuButtonPosition()
    if not menuButton or not bar then return end
    if InCombatLockdown() then
        _menuNeedsSync = true
        return
    end
    local left = bar:GetLeft()
    local bottom = bar:GetBottom()
    local width = bar:GetWidth()
    local height = bar:GetHeight()
    if not left or not bottom then return end
    local scale = bar:GetEffectiveScale() / menuButton:GetEffectiveScale()
    menuButton:ClearAllPoints()
    menuButton:SetSize(width * scale, height * scale)
    menuButton:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale)
    _menuNeedsSync = false
end

function HealthBar:Init(class, specID)
    local settings = RB:EnsureDefaults("healthBar")
    if bar then
        self:Refresh(class, specID)
        return
    end

    bar = RB:CreateStatusBar("healthBar", UIParent, settings)
    bar:SetMinMaxValues(0, 1)

    -- Absorb overlay — StatusBar approach (matches AbsorbBars_Blizzard.lua pattern)
    local innerBar = bar._innerBar or bar
    absorbBar = CreateFrame("StatusBar", nil, innerBar)
    absorbBar:SetFrameLevel(innerBar:GetFrameLevel() + 2)
    absorbBar:SetMinMaxValues(0, 1)
    absorbBar:SetValue(0)

    -- Apply absorb texture from settings (or fall back to health bar texture)
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local absorbTex = (LSM and settings.absorbTexture) and LSM:Fetch("statusbar", settings.absorbTexture)
            or (innerBar:GetStatusBarTexture() and innerBar:GetStatusBarTexture():GetTexture())
            or "Interface\\TargetingFrame\\UI-StatusBar"
    absorbBar:SetStatusBarTexture(absorbTex)
    local absorbSbTex = absorbBar:GetStatusBarTexture()
    if absorbSbTex then
        absorbSbTex:SetTexelSnappingBias(0)
        absorbSbTex:SetSnapToPixelGrid(false)
    end

    local ac = settings.absorbColor or { r = 0.8, g = 0.8, b = 0.2, a = 0.5 }
    absorbBar:SetStatusBarColor(ac.r, ac.g, ac.b, ac.a)

    -- Anchor & reverse fill based on absorbSide setting
    local side = settings.absorbSide or "right"
    absorbBar:ClearAllPoints()
    absorbBar:SetPoint("TOPLEFT", innerBar, "TOPLEFT")
    absorbBar:SetPoint("BOTTOMRIGHT", innerBar, "BOTTOMRIGHT")
    if side == "right" then
        absorbBar:SetReverseFill(true)
    else
        absorbBar:SetReverseFill(false)
    end
    absorbBar:Hide()

    -- Right-click menu overlay (SecureUnitButtonTemplate)
    -- Parent to UIParent (not bar) to avoid tainting the health bar frame with RegisterUnitWatch
    menuButton = CreateFrame("Button", "CCM_RB_HealthBar_MenuButton", UIParent, "SecureUnitButtonTemplate")
    SyncMenuButtonPosition()
    menuButton:SetFrameStrata(bar:GetFrameStrata())
    menuButton:SetFrameLevel(bar:GetFrameLevel() + 10)
    menuButton:SetAttribute("unit", "player")
    menuButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    menuButton:SetAttribute("*type1", "target")
    menuButton:SetAttribute("*type2", "togglemenu")
    menuButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Right-click for player menu", 1, 1, 1)
        GameTooltip:Show()
    end)
    menuButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if not settings.showRightClickMenu then
        HideMenuButton()
    end

    -- Events — use unit-filtered registration for UNIT_HEALTH/UNIT_MAXHEALTH/UNIT_ABSORB
    bar:RegisterUnitEvent("UNIT_HEALTH", "player")
    bar:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
    bar:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", "player")
    bar:RegisterEvent("PLAYER_ENTERING_WORLD")
    bar:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    bar:RegisterEvent("PLAYER_REGEN_ENABLED")
    bar:RegisterEvent("PLAYER_REGEN_DISABLED")
    bar:SetScript("OnEvent", function(self, event, unit)
        if event == "PLAYER_REGEN_ENABLED" then
            FlushMenuPending()
        end
        if unit and unit ~= "player" then return end
        HealthBar:Update()
    end)

    RB:ApplyPosition(bar, settings)
    self:ApplyColor()
    self:Update()
end

function HealthBar:Update()
    if not bar then return end
    local settings = RB:GetModuleSettings("healthBar")

    if not RB:ShouldShow(settings) then
        bar:Hide()
        HideMenuButton()
        return
    end

    local health, maxHealth = RB:SafeGetUnitHealth("player")
    if not health then health = 0 end
    if not maxHealth or maxHealth == 0 then maxHealth = 1 end

    -- Only update min/max when it changes (== works on secret numbers)
    if maxHealth ~= bar._lastMax then
        bar:SetMinMaxValues(0, maxHealth)
        bar._lastMax = maxHealth
    end
    bar:SetValue(health)
    bar:Show()

    -- Text
    if settings.showText and bar.text then
        RB:FormatBarText(bar.text, health, maxHealth, settings.textFormat or "percent", "health")
        bar.text:Show()
    elseif bar.text then
        bar.text:Hide()
    end

    -- Absorbs — StatusBar approach (matches AbsorbBars_Blizzard.lua pattern)
    if settings.showAbsorb and absorbBar then
        local absorb = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs("player") or 0
        absorbBar:SetMinMaxValues(0, maxHealth)
        absorbBar:SetValue(absorb)
        absorbBar:Show()
    elseif absorbBar then
        absorbBar:SetValue(0)
        absorbBar:Hide()
    end
end

-- Apply color settings (called from Refresh and Init only — not every Update tick)
function HealthBar:ApplyColor()
    if not bar then return end
    local settings = RB:GetModuleSettings("healthBar")
    if settings.useGradient then
        local gs = settings.gradientStart or settings.customColor or { r = 0.2, g = 0.8, b = 0.2, a = 1 }
        local ge = settings.gradientEnd or settings.customColor or { r = 0.0, g = 0.5, b = 0.0, a = 1 }
        local sbTex = bar:GetStatusBarTexture()
        if sbTex and sbTex.SetGradient then
            local cs, ce = RB:GetGradientColors()
            cs:SetRGBA(gs.r, gs.g, gs.b, gs.a or 1)
            ce:SetRGBA(ge.r, ge.g, ge.b, ge.a or 1)
            sbTex:SetGradient("HORIZONTAL", cs, ce)
        else
            local c = settings.customColor or { r = 0.2, g = 0.8, b = 0.2, a = 1 }
            bar:SetStatusBarColor(c.r, c.g, c.b, c.a or 1)
        end
    elseif settings.useClassColor then
        local class = RB:GetPlayerClass()
        local cc = RB.CLASS_COLORS[class] or { r = 0.2, g = 0.8, b = 0.2 }
        bar:SetStatusBarColor(cc.r, cc.g, cc.b, 1)
    else
        local c = settings.customColor or { r = 0.2, g = 0.8, b = 0.2, a = 1 }
        bar:SetStatusBarColor(c.r, c.g, c.b, c.a or 1)
    end

    -- Right-click menu visibility
    if menuButton then
        if settings.showRightClickMenu then
            SyncMenuButtonPosition()
            ShowMenuButton()
        else
            HideMenuButton()
        end
    end

    -- Cache absorb style (only changes on settings update)
    if absorbBar then
        local ac = settings.absorbColor or { r = 0.8, g = 0.8, b = 0.2, a = 0.5 }
        absorbBar:SetStatusBarColor(ac.r, ac.g, ac.b, ac.a)

        -- Re-apply absorb texture from settings
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        local innerBar = bar._innerBar or bar
        local absorbTex = (LSM and settings.absorbTexture) and LSM:Fetch("statusbar", settings.absorbTexture)
                or (innerBar:GetStatusBarTexture() and innerBar:GetStatusBarTexture():GetTexture())
                or "Interface\\TargetingFrame\\UI-StatusBar"
        absorbBar:SetStatusBarTexture(absorbTex)
        local absorbSbTex = absorbBar:GetStatusBarTexture()
        if absorbSbTex then
            absorbSbTex:SetTexelSnappingBias(0)
            absorbSbTex:SetSnapToPixelGrid(false)
        end

        -- Update fill direction based on absorbSide
        local side = settings.absorbSide or "right"
        absorbBar:ClearAllPoints()
        absorbBar:SetPoint("TOPLEFT", innerBar, "TOPLEFT")
        absorbBar:SetPoint("BOTTOMRIGHT", innerBar, "BOTTOMRIGHT")
        if side == "right" then
            absorbBar:SetReverseFill(true)
        else
            absorbBar:SetReverseFill(false)
        end
    end
end

function HealthBar:Refresh(class, specID)
    if not bar then return end
    local settings = RB:EnsureDefaults("healthBar")
    RB:UpdateBarStyle(bar, settings)
    RB:ApplyPosition(bar, settings)
    self:ApplyColor()
    self:Update()
end

function HealthBar:OnSpecChanged(class, specID)
    self:Refresh(class, specID)
end

RB:RegisterModule("healthBar", HealthBar)
