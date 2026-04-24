-- ============================================================
-- CkraigCooldownManager :: ResourceBars :: MonkOrbTracker
-- ============================================================
-- Tracks Brewmaster Monk stagger orbs (Press the Advantage /
-- Exploding Keg cast count).  Displayed as a single StatusBar
-- with divider ticks for each orb slot.
-- ============================================================

local RB = CCM_ResourceBars
if not RB then return end

local LSM = LibStub("LibSharedMedia-3.0", true)

local MonkOrbTracker = {}
local wrapper = nil          -- outer container (BackdropTemplate)
local bar = nil              -- inner StatusBar
local ticks = {}             -- divider tick textures
local updateFrame = nil      -- OnUpdate ticker

-- ============================================================
-- Constants
-- ============================================================
local ORB_SPELL_ID = 322101
local DEFAULT_NUM_ORBS = 5

-- ============================================================
-- Helpers
-- ============================================================
local function IsBrewmasterMonk()
    local _, class = UnitClass("player")
    if class ~= "MONK" then return false end
    local spec = GetSpecialization()
    return spec == 1
end

local function GetOrbCount()
    if C_Spell and C_Spell.GetSpellCastCount then
        return C_Spell.GetSpellCastCount(ORB_SPELL_ID) or 0
    end
    return 0
end

-- ============================================================
-- Tick dividers
-- ============================================================
local function UpdateTicks(numOrbs)
    for _, tick in ipairs(ticks) do tick:Hide() end
    if not bar then return end
    local w = bar:GetWidth()
    local h = bar:GetHeight()
    for i = 1, (numOrbs or DEFAULT_NUM_ORBS) - 1 do
        if not ticks[i] then
            ticks[i] = bar:CreateTexture(nil, "OVERLAY")
            ticks[i]:SetColorTexture(0, 0, 0, 1)
        end
        ticks[i]:SetSize(2, h)
        ticks[i]:ClearAllPoints()
        ticks[i]:SetPoint("LEFT", bar, "LEFT", i * (w / (numOrbs or DEFAULT_NUM_ORBS)) - 1, 0)
        ticks[i]:Show()
    end
end

-- ============================================================
-- Apply bar texture + gradient/color
-- ============================================================
local function ApplyBarAppearance(settings)
    if not bar then return end

    -- Texture
    local textureKey = settings.texture or "Blizzard Raid Bar"
    local texture = (LSM and LSM:Fetch("statusbar", textureKey)) or "Interface\\TargetingFrame\\UI-StatusBar"
    bar:SetStatusBarTexture(texture)
    local sbTex = bar:GetStatusBarTexture()
    if sbTex then
        sbTex:SetTexelSnappingBias(0)
        sbTex:SetSnapToPixelGrid(false)
    end

    -- Gradient or solid color
    local gs = settings.gradientStart
    local ge = settings.gradientEnd
    if gs and ge and sbTex and sbTex.SetGradient then
        sbTex:SetGradient("HORIZONTAL",
            CreateColor(gs.r, gs.g, gs.b, gs.a or 1),
            CreateColor(ge.r, ge.g, ge.b, ge.a or 1)
        )
    else
        local c = settings.barColor or { r = 0.00, g = 1.00, b = 0.59, a = 1 }
        bar:SetStatusBarColor(c.r, c.g, c.b, c.a or 1)
    end

    -- Background
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
local function UpdateOrbs()
    if not wrapper then return end
    local settings = RB:GetModuleSettings("monkOrbTracker")

    if not IsBrewmasterMonk() or not RB:ShouldShow(settings) then
        wrapper:Hide()
        return
    end

    local numOrbs = settings.numOrbs or DEFAULT_NUM_ORBS
    bar:SetMinMaxValues(0, numOrbs)
    bar:SetValue(GetOrbCount())
    wrapper:Show()
end

-- ============================================================
-- Module interface
-- ============================================================
function MonkOrbTracker:Init(class, specID)
    if class ~= "MONK" then return end

    local settings = RB:EnsureDefaults("monkOrbTracker")

    if wrapper then
        self:Refresh(class, specID)
        return
    end

    -- Outer wrapper (BackdropTemplate for border)
    local borderSize = settings.borderSize or 1
    wrapper = CreateFrame("Frame", "CCM_RB_monkOrbTracker", UIParent, "BackdropTemplate")
    wrapper:SetSize(settings.width or 120, settings.height or 24)
    wrapper:SetMovable(true)
    wrapper:EnableMouse(true)
    wrapper:RegisterForDrag("LeftButton")
    wrapper:SetClampedToScreen(true)
    wrapper:SetFrameStrata("MEDIUM")
    wrapper._moduleName = "monkOrbTracker"
    wrapper._locked = true
    wrapper._borderSize = borderSize

    -- Border
    if borderSize > 0 then
        wrapper:SetBackdrop({
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = borderSize,
        })
        local bc = settings.borderColor or { r = 0, g = 0, b = 0, a = 1 }
        wrapper:SetBackdropBorderColor(bc.r, bc.g, bc.b, bc.a)
    end

    -- Inner StatusBar
    bar = CreateFrame("StatusBar", nil, wrapper)
    bar:SetPoint("TOPLEFT", borderSize, -borderSize)
    bar:SetPoint("BOTTOMRIGHT", -borderSize, borderSize)

    -- Background texture inside bar
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()

    -- Drag handlers
    wrapper:SetScript("OnDragStart", function(self)
        if self._locked then return end
        local modSettings = RB:GetModuleSettings("monkOrbTracker")
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
        local modSettings = RB:GetModuleSettings("monkOrbTracker")
        modSettings.position = { point = "CENTER", relPoint = "CENTER", x = x, y = y }
    end)

    -- Register in RB.bars for smart stacking
    RB.bars["monkOrbTracker"] = wrapper

    -- Hook show/hide for smart stacking
    wrapper:HookScript("OnShow", function() RB:OnBarVisibilityChanged() end)
    wrapper:HookScript("OnHide", function() RB:OnBarVisibilityChanged() end)

    -- Redraw ticks on resize
    bar:SetScript("OnSizeChanged", function()
        local s = RB:GetModuleSettings("monkOrbTracker")
        UpdateTicks(s and s.numOrbs or DEFAULT_NUM_ORBS)
    end)

    -- Events
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
    eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_POWER_UPDATE" or event == "UNIT_AURA" then
            if unit ~= "player" then return end
        end
        UpdateOrbs()
    end)

    -- No OnUpdate needed — orb count only changes on events

    ApplyBarAppearance(settings)
    UpdateTicks(settings.numOrbs or DEFAULT_NUM_ORBS)
    RB:ApplyPosition(wrapper, settings)
    UpdateOrbs()
end

function MonkOrbTracker:Refresh(class, specID)
    if class ~= "MONK" or not IsBrewmasterMonk() then
        self:HideAll()
        return
    end
    if not wrapper then
        self:Init(class, specID)
        return
    end

    local settings = RB:EnsureDefaults("monkOrbTracker")

    -- Update wrapper size / border
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

    -- Update inner bar inset
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", borderSize, -borderSize)
    bar:SetPoint("BOTTOMRIGHT", -borderSize, borderSize)

    ApplyBarAppearance(settings)
    UpdateTicks(settings.numOrbs or DEFAULT_NUM_ORBS)
    RB:ApplyPosition(wrapper, settings)
    UpdateOrbs()
end

function MonkOrbTracker:HideAll()
    if wrapper then wrapper:Hide() end
end

function MonkOrbTracker:OnSpecChanged(class, specID)
    if class ~= "MONK" or not IsBrewmasterMonk() then
        self:HideAll()
        return
    end
    self:Refresh(class, specID)
end

function MonkOrbTracker:Update()
    UpdateOrbs()
end

RB:RegisterModule("monkOrbTracker", MonkOrbTracker)
