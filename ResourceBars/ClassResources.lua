-- ============================================================
-- CkraigCooldownManager :: ResourceBars :: ClassResources
-- ============================================================
-- Unified class resource system. Handles ALL class-specific
-- resource types: combo points, runes, holy power, chi,
-- essence, soul shards, arcane charges, stagger, etc.
-- Auto-detects class and spec to show the correct resource.
-- ============================================================

local RB = CCM_ResourceBars
if not RB then return end

local ClassResources = {}
local container = nil
local staggerBar = nil
local _currentResourceType = nil
local _partialUpdateFrame = nil

-- ============================================================
-- Class resource definitions
-- ============================================================
local RESOURCE_DEFS = {
    -- ROGUE: Combo Points (all specs)
    ROGUE = {
        { specs = {259, 260, 261}, resource = "comboPoints", segmented = true,
          powerType = Enum.PowerType.ComboPoints, maxFunc = function() return RB:SafeNumberCall(UnitPowerMax, "player", Enum.PowerType.ComboPoints) or 5 end,
          hasCharged = true,
          color = { r = 1.0, g = 0.8, b = 0.0 },
          colors = {
              { r = 1.0, g = 0.8, b = 0.0 }, { r = 1.0, g = 0.7, b = 0.0 },
              { r = 1.0, g = 0.6, b = 0.0 }, { r = 1.0, g = 0.5, b = 0.0 },
              { r = 1.0, g = 0.3, b = 0.0 }, { r = 1.0, g = 0.2, b = 0.0 },
              { r = 1.0, g = 0.1, b = 0.0 },
          },
        },
    },
    -- DRUID: Combo Points (all specs, visible in Cat Form)
    DRUID = {
        { specs = {102, 103, 104, 105}, resource = "comboPoints", segmented = true,
          powerType = Enum.PowerType.ComboPoints, maxFunc = function() return RB:SafeNumberCall(UnitPowerMax, "player", Enum.PowerType.ComboPoints) or 5 end,
          hasCharged = true,
          requiresCatForm = true,
          color = { r = 1.0, g = 0.8, b = 0.0 },
          colors = {
              { r = 1.0, g = 0.8, b = 0.0 }, { r = 1.0, g = 0.7, b = 0.0 },
              { r = 1.0, g = 0.6, b = 0.0 }, { r = 1.0, g = 0.5, b = 0.0 },
              { r = 1.0, g = 0.3, b = 0.0 }, { r = 1.0, g = 0.2, b = 0.0 },
              { r = 1.0, g = 0.1, b = 0.0 },
          },
        },
    },
    -- PALADIN: Holy Power
    PALADIN = {
        { specs = {65, 66, 70}, resource = "holyPower", segmented = true,
          powerType = Enum.PowerType.HolyPower, maxFunc = function() return RB:SafeNumberCall(UnitPowerMax, "player", Enum.PowerType.HolyPower) or 5 end,
          color = { r = 0.95, g = 0.90, b = 0.60 },
          colors = {
              { r = 0.85, g = 0.75, b = 0.40 }, { r = 0.90, g = 0.82, b = 0.50 },
              { r = 0.95, g = 0.88, b = 0.55 }, { r = 1.00, g = 0.92, b = 0.60 },
              { r = 1.00, g = 0.96, b = 0.65 },
          },
        },
    },
    -- MONK: Chi (Windwalker) + Stagger (Brewmaster)
    MONK = {
        { specs = {269}, resource = "chi", segmented = true,
          powerType = Enum.PowerType.Chi, maxFunc = function() return RB:SafeNumberCall(UnitPowerMax, "player", Enum.PowerType.Chi) or 5 end,
          color = { r = 0.71, g = 1.0, b = 0.92 },
          colors = {
              { r = 0.50, g = 0.90, b = 0.80 }, { r = 0.55, g = 0.92, b = 0.82 },
              { r = 0.60, g = 0.95, b = 0.85 }, { r = 0.65, g = 0.97, b = 0.88 },
              { r = 0.71, g = 1.00, b = 0.92 }, { r = 0.71, g = 1.00, b = 0.92 },
          },
        },
        { specs = {268}, resource = "stagger", segmented = false,
          statusBar = true,
          color = { r = 0.52, g = 1.0, b = 0.52 },
        },
    },
    -- WARLOCK: Soul Shards
    WARLOCK = {
        { specs = {265, 266, 267}, resource = "soulShards", segmented = true,
          powerType = Enum.PowerType.SoulShards, maxFunc = function() return RB:SafeNumberCall(UnitPowerMax, "player", Enum.PowerType.SoulShards) or 5 end,
          hasPartial = true,
          color = { r = 0.58, g = 0.31, b = 0.76 },
          colors = {
              { r = 0.48, g = 0.21, b = 0.66 }, { r = 0.53, g = 0.26, b = 0.71 },
              { r = 0.58, g = 0.31, b = 0.76 }, { r = 0.63, g = 0.36, b = 0.81 },
              { r = 0.68, g = 0.41, b = 0.86 },
          },
        },
    },
    -- MAGE: Arcane Charges (Arcane only)
    MAGE = {
        { specs = {62}, resource = "arcaneCharges", segmented = true,
          powerType = Enum.PowerType.ArcaneCharges, maxFunc = function() return RB:SafeNumberCall(UnitPowerMax, "player", Enum.PowerType.ArcaneCharges) or 4 end,
          color = { r = 0.10, g = 0.68, b = 0.98 },
          colors = {
              { r = 0.10, g = 0.58, b = 0.88 }, { r = 0.10, g = 0.63, b = 0.93 },
              { r = 0.10, g = 0.68, b = 0.98 }, { r = 0.15, g = 0.73, b = 1.00 },
          },
        },
    },
    -- EVOKER: Essence
    EVOKER = {
        { specs = {1467, 1468, 1473}, resource = "essence", segmented = true,
          powerType = Enum.PowerType.Essence, maxFunc = function() return RB:SafeNumberCall(UnitPowerMax, "player", Enum.PowerType.Essence) or 5 end,
          hasPartial = true,
          color = { r = 0.27, g = 0.78, b = 0.71 },
          colors = {
              { r = 0.17, g = 0.68, b = 0.61 }, { r = 0.22, g = 0.73, b = 0.66 },
              { r = 0.27, g = 0.78, b = 0.71 }, { r = 0.32, g = 0.83, b = 0.76 },
              { r = 0.37, g = 0.88, b = 0.81 }, { r = 0.42, g = 0.93, b = 0.86 },
          },
        },
    },
    -- DEATHKNIGHT: Runes (per-spec colors)
    DEATHKNIGHT = {
        -- Blood: red
        { specs = {250}, resource = "runes", segmented = true,
          maxPoints = 6, isRunes = true,
          color = { r = 0.77, g = 0.12, b = 0.23 },
          colors = {
              { r = 0.77, g = 0.12, b = 0.23 }, { r = 0.77, g = 0.12, b = 0.23 },
              { r = 0.77, g = 0.12, b = 0.23 }, { r = 0.77, g = 0.12, b = 0.23 },
              { r = 0.77, g = 0.12, b = 0.23 }, { r = 0.77, g = 0.12, b = 0.23 },
          },
        },
        -- Frost: blue
        { specs = {251}, resource = "runes", segmented = true,
          maxPoints = 6, isRunes = true,
          color = { r = 0.25, g = 0.58, b = 0.82 },
          colors = {
              { r = 0.25, g = 0.58, b = 0.82 }, { r = 0.25, g = 0.58, b = 0.82 },
              { r = 0.25, g = 0.58, b = 0.82 }, { r = 0.25, g = 0.58, b = 0.82 },
              { r = 0.25, g = 0.58, b = 0.82 }, { r = 0.25, g = 0.58, b = 0.82 },
          },
        },
        -- Unholy: green
        { specs = {252}, resource = "runes", segmented = true,
          maxPoints = 6, isRunes = true,
          color = { r = 0.30, g = 0.69, b = 0.30 },
          colors = {
              { r = 0.30, g = 0.69, b = 0.30 }, { r = 0.30, g = 0.69, b = 0.30 },
              { r = 0.30, g = 0.69, b = 0.30 }, { r = 0.30, g = 0.69, b = 0.30 },
              { r = 0.30, g = 0.69, b = 0.30 }, { r = 0.30, g = 0.69, b = 0.30 },
          },
        },
    },
    -- DEMONHUNTER: No extra segmented resource (Fury is power bar)
    -- But we provide a placeholder for potential future hero talent resources
    DEMONHUNTER = {},
    -- WARRIOR: No extra segmented resource (Rage is power bar)
    WARRIOR = {},
    -- HUNTER: No extra segmented resource (Focus is power bar)
    HUNTER = {},
    -- PRIEST: No extra segmented resource (Insanity is power bar for Shadow)
    PRIEST = {},
    -- SHAMAN: No extra segmented resource (Maelstrom is power bar for Ele)
    SHAMAN = {},
}

-- Expose RESOURCE_DEFS so options panel can read default colors/max segments
RB.RESOURCE_DEFS = RESOURCE_DEFS

-- ============================================================
-- Default settings for class resources
-- ============================================================
RB.MODULE_DEFAULTS.classResource = {
    enabled = true,
    segmentWidth = 22,
    segmentHeight = 14,
    segmentSpacing = 3,
    borderSize = 1,
    borderColor = { r = 0, g = 0, b = 0, a = 1 },
    anchor = "viewer",
    anchorTarget = "essential",
    anchorPosition = "ABOVE",
    anchorOffset = 0,
    widthMatchAnchor = true,
    position = { point = "CENTER", x = 0, y = -60 },
    hideWhenMounted = false,
    hideOutOfCombat = false,
    usePerPointColor = true,
    segmentColors = {},  -- per-segment overrides: { [1]={r,g,b}, [2]={r,g,b}, ... }
    -- Charged combo point colors (Rogue/Druid)
    chargedColor = { r = 0.2, g = 0.6, b = 1.0 },
    chargedBgColor = { r = 0.1, g = 0.3, b = 0.5, a = 0.7 },
    -- Rune options (Death Knight)
    showRuneTimers = true,
    -- Resource count text (segmented bars)
    showResourceText = false,
    resourceTextSize = 12,
    -- Stagger bar (Brewmaster) overrides
    staggerWidth = 200,
    staggerHeight = 14,
    staggerTexture = "Blizzard Raid Bar",
    staggerBgColor = { r = 0.15, g = 0.15, b = 0.15, a = 0.8 },
    staggerShowText = true,
    staggerTextFormat = "both",
    staggerTextSize = 11,
}

-- ============================================================
-- Find active resource def for current class/spec
-- ============================================================
local function GetActiveResourceDef()
    local class = RB:GetPlayerClass()
    local specID = RB:GetPlayerSpec()
    local defs = RESOURCE_DEFS[class]
    if not defs then return nil end

    for _, def in ipairs(defs) do
        if def.specs then
            for _, sid in ipairs(def.specs) do
                if sid == specID then
                    return def
                end
            end
        end
    end
    return nil
end

-- ============================================================
-- Stagger helpers (Brewmaster Monk)
-- ============================================================
-- Pre-allocated stagger color tables to avoid GC churn
local STAGGER_COLOR_GREEN  = { r = 0.52, g = 1.0, b = 0.52 }
local STAGGER_COLOR_YELLOW = { r = 1.0, g = 0.8, b = 0.0 }
local STAGGER_COLOR_RED    = { r = 1.0, g = 0.2, b = 0.2 }

local function GetStaggerInfo()
    local stagger = (UnitStagger and UnitStagger("player")) or 0
    local _, maxHealth = RB:SafeGetUnitHealth("player")
    if not maxHealth or maxHealth == 0 then maxHealth = 1 end

    -- Use pcall for safe arithmetic on secret/tainted numbers (PRD pattern)
    local pct = 0
    local ok, result = pcall(function() return stagger / maxHealth end)
    if ok and type(result) == "number" and result == result then
        pct = result
    end

    local color
    if pct >= 0.6 then
        color = STAGGER_COLOR_RED
    elseif pct >= 0.3 then
        color = STAGGER_COLOR_YELLOW
    else
        color = STAGGER_COLOR_GREEN
    end

    return stagger, maxHealth, pct, color
end

-- ============================================================
-- Rune helpers (Death Knight)
-- ============================================================
local function GetRuneStates()
    local runeStates = {}
    for i = 1, 6 do
        local start, duration, runeReady = GetRuneCooldown(i)
        local remaining = 0
        if not runeReady and start and duration and duration > 0 then
            remaining = math.max(0, (start + duration) - GetTime())
        end
        runeStates[#runeStates + 1] = {
            index = i,
            ready = runeReady,
            start = start or 0,
            duration = duration or 0,
            remaining = remaining,
        }
    end
    -- Sort: ready runes first, then by least remaining cooldown
    table.sort(runeStates, function(a, b)
        if a.ready ~= b.ready then
            return a.ready
        end
        return a.remaining < b.remaining
    end)
    local readyCount = 0
    for _, s in ipairs(runeStates) do
        if s.ready then readyCount = readyCount + 1 end
    end
    return readyCount, runeStates
end

-- ============================================================
-- Init
-- ============================================================
function ClassResources:Init(class, specID)
    local settings = RB:EnsureDefaults("classResource")
    self:BuildBar(class, specID, settings)
end

function ClassResources:BuildBar(class, specID, settings)
    local def = GetActiveResourceDef()
    if not def or not def.resource then
        self:HideAll()
        _currentResourceType = nil
        return
    end

    -- If resource type changed, destroy old bar
    if _currentResourceType ~= def.resource then
        self:HideAll()
        _currentResourceType = def.resource
    end

    if def.statusBar then
        -- Stagger-style continuous bar
        self:BuildStaggerBar(settings, def)
    elseif def.segmented then
        -- Segmented point bar
        self:BuildSegmentedBar(settings, def)
    end
end

function ClassResources:BuildSegmentedBar(settings, def)
    local maxPoints
    if def.maxPoints then
        maxPoints = def.maxPoints
    elseif def.maxFunc then
        maxPoints = def.maxFunc()
    else
        maxPoints = 5
    end
    if maxPoints < 1 then maxPoints = 5 end

    if not container then
        container = RB:CreateSegmentedBar("classResource", UIParent, math.max(maxPoints, 10), settings)
    end

    RB:ResizeSegmentedBar(container, maxPoints, settings)
    RB:ApplyPosition(container, settings)

    -- Create resource count text if it doesn't exist
    if not container.resourceText then
        -- Use an overlay frame above the segments so text isn't hidden behind fills
        local textOverlay = CreateFrame("Frame", nil, container)
        textOverlay:SetAllPoints(container)
        textOverlay:SetFrameLevel(container:GetFrameLevel() + 10)
        container.resourceText = textOverlay:CreateFontString(nil, "OVERLAY")
        container.resourceText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        container.resourceText:SetTextColor(1, 1, 1, 1)
        container.resourceText:SetPoint("CENTER", container, "CENTER")
    end

    -- Register events
    container:UnregisterAllEvents()
    if def.isRunes then
        container:RegisterEvent("RUNE_POWER_UPDATE")
        container:RegisterEvent("RUNE_TYPE_UPDATE")
    else
        container:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
        container:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    end
    if def.hasCharged then
        container:RegisterUnitEvent("UNIT_POWER_POINT_CHARGE", "player")
    end
    if def.requiresCatForm then
        container:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    end
    container:RegisterEvent("PLAYER_ENTERING_WORLD")
    container:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    container:RegisterEvent("PLAYER_REGEN_ENABLED")
    container:RegisterEvent("PLAYER_REGEN_DISABLED")
    container:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

    container:SetScript("OnEvent", function(self, event, unit)
        if event == "PLAYER_SPECIALIZATION_CHANGED" then return end
        -- RUNE_POWER_UPDATE / RUNE_TYPE_UPDATE send runeIndex (number), not "player"
        if event ~= "RUNE_POWER_UPDATE" and event ~= "RUNE_TYPE_UPDATE" then
            if unit and unit ~= "player" then return end
        end
        -- If the partial OnUpdate is running (hasPartial), skip event-driven updates
        -- for power events — the 20 Hz OnUpdate already handles smooth updates.
        -- Still process non-power events (mount, regen, entering world).
        if def.hasPartial and (event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER") then
            return
        end
        ClassResources:UpdateSegmented(def)
    end)

    -- Partial fill update frame for essence/shards
    if def.hasPartial then
        if not _partialUpdateFrame then
            _partialUpdateFrame = CreateFrame("Frame")
        end
        _partialUpdateFrame._elapsed = 0
        _partialUpdateFrame:SetScript("OnUpdate", function(self, elapsed)
            self._elapsed = self._elapsed + elapsed
            if self._elapsed < 0.05 then return end
            self._elapsed = 0
            ClassResources:UpdateSegmented(def)
        end)
        _partialUpdateFrame:Show()
    elseif _partialUpdateFrame then
        _partialUpdateFrame:SetScript("OnUpdate", nil)
        _partialUpdateFrame:Hide()
    end

    container:Show()
    if staggerBar then staggerBar:Hide() end
    self:UpdateSegmented(def)
end

function ClassResources:BuildStaggerBar(settings, def)
    if not staggerBar then
        local staggerSettings = {
            width = settings.staggerWidth or 200,
            height = settings.staggerHeight or 14,
            texture = settings.staggerTexture or "Blizzard Raid Bar",
            bgColor = settings.staggerBgColor or { r = 0.15, g = 0.15, b = 0.15, a = 0.8 },
            borderSize = settings.borderSize or 1,
            borderColor = settings.borderColor or { r = 0, g = 0, b = 0, a = 1 },
            textSize = settings.staggerTextSize or 11,
        }
        staggerBar = RB:CreateStatusBar("classResource_stagger", UIParent, staggerSettings)
        staggerBar:SetMinMaxValues(0, 100)
        -- Override _moduleName so drag-save writes to "classResource" settings
        -- (ApplyPosition reads from "classResource", not "classResource_stagger")
        staggerBar._moduleName = "classResource"
    end

    -- Live-update all visual properties from current settings
    local styleSettings = {
        width = settings.staggerWidth or 200,
        height = settings.staggerHeight or 14,
        texture = settings.staggerTexture or "Blizzard Raid Bar",
        bgColor = settings.staggerBgColor or { r = 0.15, g = 0.15, b = 0.15, a = 0.8 },
        borderSize = settings.borderSize or 1,
        borderColor = settings.borderColor or { r = 0, g = 0, b = 0, a = 1 },
        textSize = settings.staggerTextSize or 11,
    }
    RB:UpdateBarStyle(staggerBar, styleSettings)
    RB:ApplyPosition(staggerBar, settings)

    staggerBar:UnregisterAllEvents()
    staggerBar:RegisterUnitEvent("UNIT_HEALTH", "player")
    staggerBar:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
    staggerBar:RegisterUnitEvent("UNIT_AURA", "player")
    staggerBar:RegisterEvent("PLAYER_ENTERING_WORLD")
    staggerBar:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    staggerBar:RegisterEvent("PLAYER_REGEN_ENABLED")
    staggerBar:RegisterEvent("PLAYER_REGEN_DISABLED")

    -- Stagger needs OnUpdate for smooth tracking
    if not _partialUpdateFrame then
        _partialUpdateFrame = CreateFrame("Frame")
    end
    _partialUpdateFrame._elapsed = 0
    _partialUpdateFrame:SetScript("OnUpdate", function(self, elapsed)
        self._elapsed = self._elapsed + elapsed
        if self._elapsed < 0.05 then return end
        self._elapsed = 0
        ClassResources:UpdateStagger()
    end)
    _partialUpdateFrame:Show()

    -- Events handled by the 20 Hz OnUpdate — skip redundant event-driven updates
    -- for UNIT_HEALTH/UNIT_AURA. Still process non-tick events.
    staggerBar:SetScript("OnEvent", function(self, event, unit)
        if unit and unit ~= "player" then return end
        if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_AURA" then
            return -- OnUpdate handles these at 20 Hz
        end
        ClassResources:UpdateStagger()
    end)

    staggerBar:Show()
    if container then container:Hide() end
    self:UpdateStagger()
end

-- ============================================================
-- Update: Rune segments with per-rune fill animation (DK)
-- ============================================================
function ClassResources:UpdateRuneSegments(def)
    if not container or not container.segments then return end
    local settings = RB:GetModuleSettings("classResource")

    if not RB:ShouldShow(settings) then
        container:Hide()
        return
    end

    local readyCount, runeStates = GetRuneStates()
    local maxPoints = 6
    local borderSize = settings.borderSize or 1

    if maxPoints ~= container._maxPoints then
        RB:ResizeSegmentedBar(container, maxPoints, settings)
    end

    local color = def.color or { r = 0.77, g = 0.12, b = 0.23 }

    for i = 1, maxPoints do
        local seg = container.segments[i]
        if not seg then break end

        local state = runeStates[i]

        -- Per-segment color
        local c = color
        if settings.usePerPointColor then
            local savedColors = settings.segmentColors or {}
            local defColors = def.colors or {}
            c = savedColors[i] or defColors[i] or color
        end

        -- Create timer text if it doesn't exist yet
        if not seg.timerText then
            seg.timerText = seg:CreateFontString(nil, "OVERLAY")
            seg.timerText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
            seg.timerText:SetTextColor(1, 1, 1, 1)
            seg.timerText:SetPoint("CENTER", seg, "CENTER")
        end
        local fontH = math.max(8, (seg:GetHeight() - borderSize * 2) * 0.7)
        seg.timerText:SetFont("Fonts\\FRIZQT__.TTF", fontH, "OUTLINE")

        -- Store state on segment for OnUpdate closure
        seg._runeIndex = state.index
        seg._runeColor = c
        seg._borderSize = borderSize
        seg._showTimers = (settings.showRuneTimers ~= false)

        if state.ready then
            -- Fully recharged rune
            seg.fill:SetColorTexture(c.r, c.g, c.b, c.a or 1)
            seg.fill:ClearAllPoints()
            seg.fill:SetPoint("TOPLEFT", borderSize, -borderSize)
            seg.fill:SetPoint("BOTTOMRIGHT", -borderSize, borderSize)
            seg.fill:Show()
            seg.partial:Hide()
            seg.timerText:Hide()
            seg._cooling = false
        else
            -- Rune on cooldown — animate fill from left
            seg.fill:Hide()
            seg.partial:SetColorTexture(c.r, c.g, c.b, 0.7)
            seg.partial:ClearAllPoints()
            seg.partial:SetPoint("LEFT", borderSize, 0)
            seg.partial:SetPoint("TOP", 0, -borderSize)
            seg.partial:SetPoint("BOTTOM", 0, borderSize)
            -- Initial width
            local innerW = seg:GetWidth() - (borderSize * 2)
            local now = GetTime()
            local pct0 = (state.duration > 0) and ((now - state.start) / state.duration) or 0
            pct0 = math.max(0, math.min(pct0, 1))
            seg.partial:SetWidth(math.max(1, innerW * pct0))
            seg.partial:Show()
            seg._cooling = true

            -- Show initial timer
            if seg._showTimers and state.remaining > 0 then
                seg.timerText:SetFormattedText("%.1f", state.remaining)
                seg.timerText:Show()
            else
                seg.timerText:Hide()
            end
        end
    end

    -- Single throttled OnUpdate on the container for ALL cooling runes
    if not container._runeOnUpdate then
        container._runeOnUpdate = true
        container:SetScript("OnUpdate", function(self, elapsed)
            self._runeElapsed = (self._runeElapsed or 0) + elapsed
            if self._runeElapsed < 0.033 then return end
            self._runeElapsed = 0
            for i = 1, 6 do
                local seg = self.segments and self.segments[i]
                if seg and seg._cooling and seg._runeIndex then
                    local start, duration, ready = GetRuneCooldown(seg._runeIndex)
                    local iw = seg:GetWidth() - (seg._borderSize * 2)
                    local rc = seg._runeColor

                    if ready then
                        seg.fill:SetColorTexture(rc.r, rc.g, rc.b, rc.a or 1)
                        seg.fill:ClearAllPoints()
                        seg.fill:SetPoint("TOPLEFT", seg._borderSize, -seg._borderSize)
                        seg.fill:SetPoint("BOTTOMRIGHT", -seg._borderSize, seg._borderSize)
                        seg.fill:Show()
                        seg.partial:Hide()
                        if seg.timerText then seg.timerText:Hide() end
                        seg._cooling = false
                    else
                        local t = GetTime()
                        local pct = (duration > 0) and ((t - start) / duration) or 0
                        pct = math.max(0, math.min(pct, 1))
                        seg.partial:SetWidth(math.max(1, iw * pct))

                        if seg._showTimers and seg.timerText then
                            local rem = (start + duration) - t
                            if rem > 0 then
                                seg.timerText:SetFormattedText("%.1f", rem)
                                seg.timerText:Show()
                            else
                                seg.timerText:Hide()
                            end
                        elseif seg.timerText then
                            seg.timerText:Hide()
                        end
                    end
                end
            end
        end)
    end

    container:Show()
end

-- ============================================================
-- Update: Segmented resources
-- ============================================================
function ClassResources:UpdateSegmented(def)
    if not container then return end
    local settings = RB:GetModuleSettings("classResource")

    if not RB:ShouldShow(settings) then
        container:Hide()
        return
    end

    -- Druid combo points only visible in Cat Form (shapeshift form index 2)
    if def.requiresCatForm then
        local form = GetShapeshiftForm and GetShapeshiftForm() or 0
        if form ~= 2 then
            container:Hide()
            return
        end
    end

    local currentPoints, maxPoints, partialFrac

    -- Death Knight runes: use dedicated handler with fill animation
    if def.isRunes then
        self:UpdateRuneSegments(def)
        return
    end

    local powerType = def.powerType
    currentPoints = RB:SafeNumberCall(UnitPower, "player", powerType) or 0
    maxPoints = def.maxFunc and def.maxFunc() or 5

    if def.hasPartial then
        -- PRD pattern: UnitPower with true flag returns raw fractional value
        -- Soul Shards: raw is x10 (35 = 3.5 shards). Essence: raw is x5.
        local rawPower = UnitPower("player", powerType, true) or 0
        local displayMod = (UnitPowerDisplayMod and UnitPowerDisplayMod(powerType)) or 1
        if displayMod == 0 then displayMod = 1 end
        local fractional = rawPower / displayMod
        local remainder = fractional - math.floor(fractional)
        if remainder > 0 then
            partialFrac = remainder
        end
    end

    if maxPoints ~= container._maxPoints then
        RB:ResizeSegmentedBar(container, maxPoints, settings)
    end

    -- Determine color
    local color = def.color or { r = 1, g = 1, b = 1 }
    if settings.usePerPointColor and def.colors then
        local pts = tonumber(currentPoints) or 0
        if pts > 0 then
            color = def.colors[math.min(pts, #def.colors)] or color
        end
    end

    -- Build per-segment color table
    local perSegColors = nil
    if settings.usePerPointColor then
        if not container._perSegColors then container._perSegColors = {} end
        perSegColors = container._perSegColors
        local savedColors = settings.segmentColors or {}
        local defColors = def.colors or {}
        for idx = 1, maxPoints do
            perSegColors[idx] = savedColors[idx] or defColors[idx] or color
        end
        for idx = maxPoints + 1, #perSegColors do
            perSegColors[idx] = nil
        end
    end

    -- Charged combo points (Rogue/Druid): detect and override colors + bg
    local chargedSet = nil
    if def.hasCharged and GetUnitChargedPowerPoints then
        local charged = GetUnitChargedPowerPoints("player")
        if charged then
            if not container._chargedSet then container._chargedSet = {} end
            chargedSet = container._chargedSet
            for k in pairs(chargedSet) do chargedSet[k] = nil end
            for _, idx in ipairs(charged) do
                chargedSet[idx] = true
            end
        end
    end
    if chargedSet then
        local cColor = settings.chargedColor or { r = 0.2, g = 0.6, b = 1.0 }
        local cBg = settings.chargedBgColor or { r = 0.1, g = 0.3, b = 0.5, a = 0.7 }
        if perSegColors then
            for idx in pairs(chargedSet) do
                perSegColors[idx] = cColor
            end
        end
        if container and container.segments then
            for idx = 1, maxPoints do
                local seg = container.segments[idx]
                if seg and seg.bg then
                    if chargedSet[idx] then
                        seg.bg:SetColorTexture(cBg.r, cBg.g, cBg.b, cBg.a or 0.7)
                    else
                        seg.bg:SetColorTexture(0.15, 0.15, 0.15, 0.8)
                    end
                end
            end
        end
    end

    RB:UpdateSegments(container, currentPoints, maxPoints, color, partialFrac, perSegColors)

    -- Resource count text
    if container.resourceText then
        if settings.showResourceText then
            local fontSize = settings.resourceTextSize or 12
            container.resourceText:SetFont("Fonts\\FRIZQT__.TTF", fontSize, "OUTLINE")
            if partialFrac and partialFrac > 0 then
                container.resourceText:SetFormattedText("%.1f/%d", currentPoints + partialFrac, maxPoints)
            else
                container.resourceText:SetFormattedText("%d/%d", currentPoints, maxPoints)
            end
            container.resourceText:Show()
        else
            container.resourceText:Hide()
        end
    end

    container:Show()
end

-- ============================================================
-- Update: Stagger (Brewmaster)
-- ============================================================
function ClassResources:UpdateStagger()
    if not staggerBar then return end
    local settings = RB:GetModuleSettings("classResource")

    if not RB:ShouldShow(settings) then
        staggerBar:Hide()
        return
    end

    local stagger, maxHealth, pct, color = GetStaggerInfo()
    if not maxHealth or maxHealth == 0 then maxHealth = 1 end

    staggerBar:SetMinMaxValues(0, maxHealth)
    staggerBar:SetValue(stagger)
    staggerBar:SetStatusBarColor(color.r, color.g, color.b, 1)

    if settings.staggerShowText and staggerBar.text then
        local fmt = settings.staggerTextFormat or "both"
        -- pct is already a clean number from GetStaggerInfo; use AbbreviateNumbers directly on stagger (PRD pattern)
        if fmt == "percent" then
            staggerBar.text:SetFormattedText("%.0f%%", pct * 100)
        elseif fmt == "current" then
            if type(AbbreviateNumbers) == "function" then
                staggerBar.text:SetText(AbbreviateNumbers(stagger))
            else
                staggerBar.text:SetFormattedText("%d", stagger)
            end
        elseif fmt == "deficit" then
            if type(AbbreviateNumbers) == "function" then
                staggerBar.text:SetText("-" .. AbbreviateNumbers(stagger))
            else
                staggerBar.text:SetFormattedText("-%d", stagger)
            end
        else -- "both"
            if type(AbbreviateNumbers) == "function" then
                staggerBar.text:SetText(AbbreviateNumbers(stagger) .. " (" .. string.format("%.0f%%", pct * 100) .. ")")
            else
                staggerBar.text:SetFormattedText("%d (%.0f%%)", stagger, pct * 100)
            end
        end
        staggerBar.text:Show()
    elseif staggerBar.text then
        staggerBar.text:Hide()
    end

    staggerBar:Show()
end

-- ============================================================
-- Hide all
-- ============================================================
function ClassResources:HideAll()
    if container then
        container:UnregisterAllEvents()
        -- Clear the rune animation OnUpdate
        container:SetScript("OnUpdate", nil)
        container._runeOnUpdate = nil
        container:Hide()
    end
    if staggerBar then
        staggerBar:UnregisterAllEvents()
        staggerBar:Hide()
    end
    if _partialUpdateFrame then
        _partialUpdateFrame:SetScript("OnUpdate", nil)
        _partialUpdateFrame:Hide()
    end
end

-- ============================================================
-- Refresh / Spec change
-- ============================================================
function ClassResources:Refresh(class, specID)
    local settings = RB:EnsureDefaults("classResource")
    self:BuildBar(class, specID, settings)
end

function ClassResources:OnSpecChanged(class, specID)
    _currentResourceType = nil
    self:HideAll()
    local settings = RB:EnsureDefaults("classResource")
    self:BuildBar(class, specID, settings)
end

RB:RegisterModule("classResource", ClassResources)
