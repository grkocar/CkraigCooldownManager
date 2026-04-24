-- ============================================================
-- CkraigCooldownManager :: ResourceBars :: VengeanceSoulTracker
-- ============================================================
-- Tracks Soul Fragment count for Vengeance Demon Hunter.
-- Displayed as a single StatusBar with divider ticks.
-- ============================================================

local RB = CCM_ResourceBars
if not RB then return end

local LSM = LibStub("LibSharedMedia-3.0", true)

local VengeanceSoulTracker = {}
local wrapper = nil
local bar = nil
local ticks = {}
local updateFrame = nil

-- ============================================================
-- Constants
-- ============================================================
local SOUL_SPELL_ID = 247454
local DEFAULT_NUM_SOULS = 6

-- ============================================================
-- Helpers
-- ============================================================
local function IsVengeanceDH()
    local _, class = UnitClass("player")
    if class ~= "DEMONHUNTER" then return false end
    local spec = GetSpecialization()
    return spec == 2
end

local function GetSoulCount()
    if C_Spell and C_Spell.GetSpellCastCount then
        return C_Spell.GetSpellCastCount(SOUL_SPELL_ID) or 0
    end
    return 0
end

-- ============================================================
-- Tick dividers
-- ============================================================
local function UpdateTicks(numSouls)
    for _, tick in ipairs(ticks) do tick:Hide() end
    if not bar then return end
    local w = bar:GetWidth()
    local h = bar:GetHeight()
    for i = 1, (numSouls or DEFAULT_NUM_SOULS) - 1 do
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
        tf:SetPoint("LEFT", bar, "LEFT", i * (w / (numSouls or DEFAULT_NUM_SOULS)) - 1, 0)
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
        local c = settings.barColor or { r = 0.46, g = 0.98, b = 1.00, a = 1 }
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
local function UpdateSouls()
    if not wrapper then return end
    local settings = RB:GetModuleSettings("vengeanceSoulTracker")

    if not IsVengeanceDH() or not RB:ShouldShow(settings) then
        wrapper:Hide()
        return
    end

    local numSouls = settings.numSouls or DEFAULT_NUM_SOULS
    bar:SetMinMaxValues(0, numSouls)
    bar:SetValue(GetSoulCount())
    wrapper:Show()
end

-- ============================================================
-- Module interface
-- ============================================================
function VengeanceSoulTracker:Init(class, specID)
    if class ~= "DEMONHUNTER" then return end

    local settings = RB:EnsureDefaults("vengeanceSoulTracker")

    if wrapper then
        self:Refresh(class, specID)
        return
    end

    local borderSize = settings.borderSize or 1
    wrapper = CreateFrame("Frame", "CCM_RB_vengeanceSoulTracker", UIParent, "BackdropTemplate")
    wrapper:SetSize(settings.width or 120, settings.height or 24)
    wrapper:SetMovable(true)
    wrapper:EnableMouse(true)
    wrapper:RegisterForDrag("LeftButton")
    wrapper:SetClampedToScreen(true)
    wrapper:SetFrameStrata("MEDIUM")
    wrapper._moduleName = "vengeanceSoulTracker"
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
        local modSettings = RB:GetModuleSettings("vengeanceSoulTracker")
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
        local modSettings = RB:GetModuleSettings("vengeanceSoulTracker")
        modSettings.position = { point = "CENTER", relPoint = "CENTER", x = x, y = y }
    end)

    RB.bars["vengeanceSoulTracker"] = wrapper

    wrapper:HookScript("OnShow", function() RB:OnBarVisibilityChanged() end)
    wrapper:HookScript("OnHide", function() RB:OnBarVisibilityChanged() end)

    bar:SetScript("OnSizeChanged", function()
        local s = RB:GetModuleSettings("vengeanceSoulTracker")
        UpdateTicks(s and s.numSouls or DEFAULT_NUM_SOULS)
    end)

    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_POWER_UPDATE" or event == "UNIT_AURA" then
            if unit ~= "player" then return end
        end
        UpdateSouls()
    end)

    -- No OnUpdate needed — soul count only changes on events

    ApplyBarAppearance(settings)
    UpdateTicks(settings.numSouls or DEFAULT_NUM_SOULS)
    RB:ApplyPosition(wrapper, settings)
    UpdateSouls()
end

function VengeanceSoulTracker:Refresh(class, specID)
    if class ~= "DEMONHUNTER" or not IsVengeanceDH() then
        self:HideAll()
        return
    end
    if not wrapper then
        self:Init(class, specID)
        return
    end

    local settings = RB:EnsureDefaults("vengeanceSoulTracker")

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
    UpdateTicks(settings.numSouls or DEFAULT_NUM_SOULS)
    RB:ApplyPosition(wrapper, settings)
    UpdateSouls()
end

function VengeanceSoulTracker:HideAll()
    if wrapper then wrapper:Hide() end
end

function VengeanceSoulTracker:OnSpecChanged(class, specID)
    if class ~= "DEMONHUNTER" or not IsVengeanceDH() then
        self:HideAll()
        return
    end
    self:Refresh(class, specID)
end

function VengeanceSoulTracker:Update()
    UpdateSouls()
end

RB:RegisterModule("vengeanceSoulTracker", VengeanceSoulTracker)
