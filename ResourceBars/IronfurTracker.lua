-- ============================================================
-- CkraigCooldownManager :: ResourceBars :: IronfurTracker
-- ============================================================
-- Tracks Ironfur stacks for Guardian Druid.
-- Each cast of Ironfur creates a timed segment that drains
-- independently, displayed as overlapping status bars.
-- ============================================================

local RB = CCM_ResourceBars
if not RB then return end

local LSM = LibStub("LibSharedMedia-3.0", true)

local IronfurTracker = {}
local wrapper = nil          -- outer container (BackdropTemplate)
local centerText = nil       -- overlay frame for the count text
local activeSegments = {}    -- { expire = time, duration = secs } per slot
local eventFrame = nil       -- persists across Refresh cycles
local segmentBars = {}       -- StatusBar frames (overlapping inside wrapper)

-- ============================================================
-- Spell / Talent constants
-- ============================================================
local IRONFUR_SPELL_ID       = 192081
local BASE_SEGMENT_DURATION  = 7
local REINFORCED_FUR_ID      = 393611
local GUARDIAN_OF_ELUNE_ID   = 155578
local MANGLE_SPELL_ID        = 33917
local GOOE_MANGLE_WINDOW     = 5
local MAX_SEGMENTS            = 30

local lastMangleTime   = 0
local gooeBonusActive  = false

-- ============================================================
-- Helpers
-- ============================================================
local function HasTalent(spellID)
    if C_Spell and C_Spell.IsSpellKnown then
        return C_Spell.IsSpellKnown(spellID)
    elseif IsPlayerSpell then
        return IsPlayerSpell(spellID)
    else
        local name = GetSpellInfo(spellID)
        return name ~= nil
    end
end

local function GetSegmentDuration(forceGoOE)
    local dur = BASE_SEGMENT_DURATION
    if HasTalent(REINFORCED_FUR_ID) then dur = dur + 2 end
    if forceGoOE then dur = dur + 3 end
    return dur
end

local function IsGuardianDruid()
    local _, class = UnitClass("player")
    if class ~= "DRUID" then return false end
    local spec = GetSpecialization()
    local specID = spec and GetSpecializationInfo(spec)
    return specID == 104
end

local function InBearForm()
    return (GetShapeshiftFormID and GetShapeshiftFormID() == 1)
        or (GetShapeshiftForm and GetShapeshiftForm() == 1)
end

-- Cached visibility — refreshed only on spec/form change events, not every OnUpdate tick
local _if_cachedVisible = nil
local function RefreshIronfurVisibility()
    _if_cachedVisible = IsGuardianDruid() and InBearForm()
end
local function IsIronfurVisible()
    if _if_cachedVisible == nil then RefreshIronfurVisibility() end
    return _if_cachedVisible
end

-- Pre-baked strings for stack count 1-30 to avoid tostring() per tick
local _if_countStrings = {}
for i = 1, MAX_SEGMENTS do _if_countStrings[i] = tostring(i) end

local function LayoutSegmentBar(seg, inset)
    seg:ClearAllPoints()
    seg:SetPoint("TOPLEFT", wrapper, "TOPLEFT", inset, -inset)
    seg:SetPoint("BOTTOMRIGHT", wrapper, "BOTTOMRIGHT", -inset, inset)
end

-- ============================================================
-- Create / update segment StatusBars (call on init & settings)
-- ============================================================
local function CreateOrUpdateSegmentBars()
    if not wrapper then return end
    local settings = RB:GetModuleSettings("ironfurTracker")
    local borderSize = settings.borderSize or 1
    local segCount = settings.maxSegments or 20
    local textureKey = settings.texture or "Blizzard Raid Bar"
    local texture = (LSM and LSM:Fetch("statusbar", textureKey)) or "Interface\\TargetingFrame\\UI-StatusBar"

    local inset = borderSize
    local segHeight = math.max(1, wrapper:GetHeight() - inset * 2)

    for i = 1, segCount do
        local seg = segmentBars[i]
        if not seg then
            seg = CreateFrame("StatusBar", nil, wrapper)
            seg:SetMinMaxValues(0, GetSegmentDuration())
            seg:SetValue(0)
            seg.tick = seg:CreateTexture(nil, "OVERLAY")
            seg.tick:SetPoint("RIGHT", seg, "RIGHT", 0, 0)
            seg.tick:Hide()
            seg:SetScript("OnSizeChanged", function(self, _, height)
                if self.tick then
                    self.tick:SetSize(2, height)
                end
            end)
            segmentBars[i] = seg
        end
        seg:SetStatusBarTexture(texture)
        local sbTex = seg:GetStatusBarTexture()
        if sbTex then
            sbTex:SetTexelSnappingBias(0)
            sbTex:SetSnapToPixelGrid(false)
        end
        LayoutSegmentBar(seg, inset)
        seg:Hide()
        local tc = settings.tickColor or { r = 0, g = 0, b = 0, a = 1 }
        seg.tick:SetColorTexture(tc.r, tc.g, tc.b, tc.a or 1)
        seg.tick:SetSize(2, segHeight)
        -- Set segment bar color (no longer set per-tick — only on init/refresh)
        local c = settings.segmentColor or { r = 0.5, g = 0.8, b = 1.0, a = 1 }
        seg:SetStatusBarColor(c.r, c.g, c.b, c.a or 1)
        seg:SetMinMaxValues(0, GetSegmentDuration())
    end
end

-- ============================================================
-- Update font position helper
-- ============================================================
local function UpdateFontPosition(settings)
    if not centerText or not centerText.text then return end
    centerText.text:SetFont(STANDARD_TEXT_FONT, settings.textSize or 20, "OUTLINE")
    local pos = settings.textPosition or "CENTER"
    centerText.text:ClearAllPoints()
    if pos == "LEFT" then
        centerText.text:SetPoint("LEFT", centerText, "LEFT", 10, 0)
        centerText.text:SetJustifyH("LEFT")
    elseif pos == "RIGHT" then
        centerText.text:SetPoint("RIGHT", centerText, "RIGHT", -10, 0)
        centerText.text:SetJustifyH("RIGHT")
    else
        centerText.text:SetPoint("CENTER", centerText, "CENTER", 0, 0)
        centerText.text:SetJustifyH("CENTER")
    end
end

-- ============================================================
-- Core update — runs via throttled OnUpdate on wrapper
-- ============================================================
local function UpdateIronfur()
    if not wrapper then return end
    local settings = RB:GetModuleSettings("ironfurTracker")

    if not IsIronfurVisible() or not RB:ShouldShow(settings) then
        -- Clear all active segments when leaving bear form
        for i = 1, MAX_SEGMENTS do activeSegments[i] = nil end
        if wrapper then wrapper:Hide() end
        if centerText then centerText:Hide() end
        return
    end

    -- Recalculate segment bar widths when wrapper width changes
    -- (e.g., widthMatchAnchor resizes wrapper dynamically via ApplyViewerStack)
    local borderSize = settings.borderSize or 1
    local inset = borderSize
    local curW = wrapper:GetWidth() - inset * 2
    local curH = wrapper:GetHeight() - inset * 2
    if curW ~= (wrapper._lastSegW or 0) or curH ~= (wrapper._lastSegH or 0) then
        wrapper._lastSegW = curW
        wrapper._lastSegH = curH
        for i, seg in ipairs(segmentBars) do
            LayoutSegmentBar(seg, inset)
        end
    end

    local now = GetTime()
    local shown = 0

    for i, seg in ipairs(segmentBars) do
        local data = activeSegments[i]
        if data and data.expire > now then
            seg:Show()
            seg.tick:Show()

            local remaining = data.expire - now
            local segDuration = data.duration or GetSegmentDuration()
            if seg._duration ~= segDuration then
                seg:SetMinMaxValues(0, segDuration)
                seg._duration = segDuration
            end
            seg:SetValue(remaining)

            -- Move tick to drain edge
            local barWidth = seg:GetWidth()
            local pct = remaining / segDuration
            pct = math.max(0, math.min(pct, 1))
            local tickX = barWidth * pct
            tickX = math.max(0, math.min(barWidth - seg.tick:GetWidth(), tickX))
            seg.tick:ClearAllPoints()
            seg.tick:SetPoint("LEFT", seg, "LEFT", tickX, 0)

            shown = shown + 1
        else
            seg:Hide()
            seg.tick:Hide()
        end
    end

    -- Stack count text — use pre-baked strings to avoid tostring() per tick
    if shown > 0 then
        if settings.showText then
            centerText.text:SetText(_if_countStrings[shown] or tostring(shown))
        else
            centerText.text:SetText("")
        end
        centerText:Show()
    else
        centerText.text:SetText("")
        centerText:Hide()
    end

    if wrapper then
        wrapper:Show()
    end
end

-- ============================================================
-- Add a new Ironfur segment
-- ============================================================
local function AddIronfurSegment()
    local now = GetTime()
    local useGoOE = false
    if gooeBonusActive and (now - lastMangleTime) <= GOOE_MANGLE_WINDOW then
        useGoOE = true
    end
    gooeBonusActive = false

    local dur = GetSegmentDuration(useGoOE)
    for i = 1, MAX_SEGMENTS do
        if not activeSegments[i] or activeSegments[i].expire <= now then
            activeSegments[i] = { expire = now + dur, duration = dur }
            break
        end
    end
    UpdateIronfur()
end

-- ============================================================
-- Module interface
-- ============================================================
function IronfurTracker:Init(class, specID)
    if class ~= "DRUID" then return end

    local settings = RB:EnsureDefaults("ironfurTracker")

    if wrapper then
        self:Refresh(class, specID)
        return
    end

    -- Outer wrapper (BackdropTemplate for border)
    local borderSize = settings.borderSize or 1
    wrapper = CreateFrame("Frame", "CCM_RB_ironfurTracker", UIParent, "BackdropTemplate")
    wrapper:SetSize(settings.width or 180, settings.height or 24)
    wrapper:SetMovable(true)
    wrapper:EnableMouse(true)
    wrapper:RegisterForDrag("LeftButton")
    wrapper:SetClampedToScreen(true)
    wrapper:SetFrameStrata("MEDIUM")
    wrapper._moduleName = "ironfurTracker"
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

    -- Background
    wrapper.bg = wrapper:CreateTexture(nil, "BACKGROUND")
    wrapper.bg:SetAllPoints()
    local bgc = settings.bgColor or { r = 0.08, g = 0.08, b = 0.08, a = 0.85 }
    wrapper.bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bgc.a)

    -- Drag handlers
    wrapper:SetScript("OnDragStart", function(self)
        if self._locked then return end
        local modSettings = RB:GetModuleSettings("ironfurTracker")
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
        local modSettings = RB:GetModuleSettings("ironfurTracker")
        modSettings.position = { point = "CENTER", relPoint = "CENTER", x = x, y = y }
    end)

    -- Center text overlay
    centerText = CreateFrame("Frame", nil, wrapper)
    centerText:SetAllPoints(wrapper)
    centerText:SetFrameLevel(wrapper:GetFrameLevel() + 10)
    centerText.text = centerText:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    centerText.text:SetPoint("CENTER", centerText, "CENTER", 0, 0)
    centerText.text:SetFont(STANDARD_TEXT_FONT, settings.textSize or 20, "OUTLINE")
    centerText.text:SetTextColor(1, 1, 1, 1)

    -- Register in RB.bars so smart stacking works
    RB.bars["ironfurTracker"] = wrapper

    -- Hook show/hide for smart stacking
    wrapper:HookScript("OnShow", function() RB:OnBarVisibilityChanged() end)
    wrapper:HookScript("OnHide", function() RB:OnBarVisibilityChanged() end)

    -- Create segment bars and set up font
    CreateOrUpdateSegmentBars()
    UpdateFontPosition(settings)

    -- Events for tracking casts + form changes (persists across Refresh)
    if not eventFrame then
        eventFrame = CreateFrame("Frame")
        eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        eventFrame:SetScript("OnEvent", function(_, event, unit, _, spellID)
            if event == "UPDATE_SHAPESHIFT_FORM" then
                RefreshIronfurVisibility()
                UpdateIronfur()
                return
            end
            if unit ~= "player" then return end
            if spellID == MANGLE_SPELL_ID and HasTalent(GUARDIAN_OF_ELUNE_ID) then
                lastMangleTime = GetTime()
                gooeBonusActive = true
            elseif spellID == IRONFUR_SPELL_ID then
                AddIronfurSegment()
            end
        end)
    end

    -- OnUpdate for smooth drain — throttled to ~30 FPS
    wrapper:SetScript("OnUpdate", function(self, elapsed)
        self._elapsed = (self._elapsed or 0) + elapsed
        if self._elapsed < 0.033 then return end
        self._elapsed = 0
        UpdateIronfur()
    end)

    RB:ApplyPosition(wrapper, settings)
    UpdateIronfur()
end

function IronfurTracker:Refresh(class, specID)
    RefreshIronfurVisibility()
    if class ~= "DRUID" or not IsGuardianDruid() then
        self:HideAll()
        return
    end
    if not wrapper then
        self:Init(class, specID)
        return
    end

    local settings = RB:EnsureDefaults("ironfurTracker")

    -- Restart OnUpdate if it was stopped by HideAll
    if not wrapper:GetScript("OnUpdate") then
        wrapper:SetScript("OnUpdate", function(self, elapsed)
            self._elapsed = (self._elapsed or 0) + elapsed
            if self._elapsed < 0.033 then return end
            self._elapsed = 0
            UpdateIronfur()
        end)
    end

    -- Update wrapper size / border
    wrapper:SetSize(settings.width or 180, settings.height or 24)
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

    -- Background
    local bgc = settings.bgColor or { r = 0.08, g = 0.08, b = 0.08, a = 0.85 }
    wrapper.bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bgc.a)

    CreateOrUpdateSegmentBars()
    UpdateFontPosition(settings)
    RB:ApplyPosition(wrapper, settings)
    UpdateIronfur()
end

function IronfurTracker:HideAll()
    if wrapper then
        wrapper:SetScript("OnUpdate", nil)
        wrapper:Hide()
    end
    if centerText then centerText:Hide() end
end

function IronfurTracker:OnSpecChanged(class, specID)
    if class ~= "DRUID" or specID ~= 104 then
        self:HideAll()
        return
    end
    self:Refresh(class, specID)
end

function IronfurTracker:Update()
    UpdateIronfur()
end

RB:RegisterModule("ironfurTracker", IronfurTracker)
