-- SegmentBars.lua
-- Generic segmented bar tracker for any spell/aura by spell ID.
-- Each tracked spell gets a segmented StatusBar (like Soul Fragments in soulstrackerveng.lua)
-- where the number of segments = manually assigned max count (charges/stacks).
-- Tracks via C_Spell.GetSpellCastCount (charges) or UnitAura stacks.

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- ============================================================
-- Module table
-- ============================================================
local SegmentBars = {}
_G.CCM_SegmentBars = SegmentBars

-- ============================================================
-- SavedVariables fallback
-- ============================================================
CCM_SegmentBarsDB = CCM_SegmentBarsDB or {}

-- ============================================================
-- Defaults
-- ============================================================
local DEFAULTS = {
    enabled = true,
    hideWhenMounted = false,
    barWidth = 140,
    barHeight = 20,
    barSpacing = 4,
    anchorX = 0,
    anchorY = -180,
    locked = true,
    fillingTexture = "Blizzard Raid Bar",
    tickTexture = "Blizzard Raid Bar",
    tickWidth = 2,
    tickColor = { 0, 0, 0, 1 },
    bgColor = { 0.08, 0.08, 0.08, 0.75 },
    frameStrata = "LOW",
    showLabel = true,
    showCount = true,
    labelFontSize = 11,
    labelFont = "Friz Quadrata TT",
    -- Per-spell entries live in .spells = { [spellID] = { maxSegments=N, ... } }
    spells = {},
    -- Named groups (each has its own position + optional per-group sizing)
    -- { [groupName] = { anchorX=N, anchorY=N, barWidth=N, barHeight=N, barSpacing=N } }
    groups = {},
}

local SPELL_DEFAULTS = {
    maxSegments = 3,
    gradientStart = { 0.20, 0.80, 1.00, 1 },
    gradientEnd   = { 0.00, 0.40, 0.80, 1 },
    order = 0,
    group = "",    -- "" = standalone, any string = group name
    anchorX = nil, -- per-bar position (standalone only); nil = auto-assign
    anchorY = nil,
}

-- ============================================================
-- Settings access (profile-aware)
-- ============================================================
function SegmentBars:GetSettings()
    if CkraigProfileManager and CkraigProfileManager.db and CkraigProfileManager.db.profile then
        local s = CkraigProfileManager.db.profile.segmentBars
        if s then return s end
    end
    return CCM_SegmentBarsDB
end

local function EnsureDB()
    local settings = SegmentBars:GetSettings()
    for k, v in pairs(DEFAULTS) do
        if settings[k] == nil then
            if type(v) == "table" then
                settings[k] = {}
                for kk, vv in pairs(v) do settings[k][kk] = vv end
            else
                settings[k] = v
            end
        end
    end
    if type(settings.spells) ~= "table" then settings.spells = {} end
    if type(settings.groups) ~= "table" then settings.groups = {} end

    -- Migration: spells without a group field → assign to "Default" group
    local needsMigration = false
    for _, entry in pairs(settings.spells) do
        if entry.group == nil then needsMigration = true; break end
    end
    if needsMigration then
        if not settings.groups["Default"] then
            settings.groups["Default"] = {
                anchorX = settings.anchorX or 0,
                anchorY = settings.anchorY or -180,
                barWidth = settings.barWidth or 140,
                barHeight = settings.barHeight or 20,
                barSpacing = settings.barSpacing or 4,
            }
        end
        for _, entry in pairs(settings.spells) do
            if entry.group == nil then
                entry.group = "Default"
            end
        end
    end
end

local function EnsureSpellDefaults(spellEntry)
    for k, v in pairs(SPELL_DEFAULTS) do
        if spellEntry[k] == nil then
            if type(v) == "table" then
                spellEntry[k] = { unpack(v) }
            else
                spellEntry[k] = v
            end
        end
    end
end

-- ============================================================
-- Helpers
-- ============================================================
local function IsPlayerMounted()
    return IsMounted and IsMounted()
end

-- Returns ("CLASS", "SpecName") and the combined key "CLASS_SpecName"
local function GetPlayerClassSpec()
    local _, class = UnitClass("player")
    class = class or "UNKNOWN"
    local specName = "Default"
    if GetSpecialization then
        local specIndex = GetSpecialization()
        if specIndex then
            specName = select(2, GetSpecializationInfo(specIndex)) or "Default"
        end
    end
    return class, specName, class .. "_" .. specName
end

local function GetLSMStatusbar(name)
    if LSM then
        local path = LSM:Fetch("statusbar", name)
        if path then return path end
    end
    return "Interface\\TARGETINGFRAME\\UI-StatusBar"
end

local function GetLSMFont(name)
    if LSM then
        local path = LSM:Fetch("font", name)
        if path then return path end
    end
    return STANDARD_TEXT_FONT
end

-- ===============================================================
-- The BuffIconCooldownViewer icons each have:
--   .cooldownID      — the CDM cooldown key (always clean, table field)
--   .auraInstanceID  — Blizzard unique per-aura instance ID (clean number)
--   .auraDataUnit    — "player" or "target"
--
-- C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID) does the
-- lookup entirely in C++ — no Lua == comparison, no taint, works in combat.
-- Returns { applications = N, ... } for the live aura.
--
-- We build a map: user's spellID → { auraInstanceID, unit } from the viewer
-- frames, resolving cooldownID → spellID via C_CooldownViewer.
-- The map is rebuilt out of combat. During combat we also hook
-- SetAuraInstanceInfo/ClearAuraInstanceInfo for live updates.
-- ============================================================

local auraInstanceMap = {}     -- [trackedSpellID] = { auraInstanceID=N, unit="player" }
local hookedCDMFrames = {}     -- [frame] = true (prevent double-hooking)

-- issecretvalue() test: handles potential future secret auraInstanceIDs
local function HasAuraInstanceID(value)
    if value == nil then return false end
    if issecretvalue and issecretvalue(value) then return true end
    if type(value) == "number" and value == 0 then return false end
    return true
end

-- Resolve a CDM cooldownID to a set of spell IDs the user might have entered
local function ResolveCooldownIDToSpellIDs(cooldownID)
    local ids = {}
    local numID = tonumber(cooldownID)
    if not numID then return ids end
    ids[numID] = true
    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, numID)
        if ok and info then
            if info.spellID and tonumber(info.spellID) then ids[tonumber(info.spellID)] = true end
            if info.overrideSpellID and tonumber(info.overrideSpellID) then ids[tonumber(info.overrideSpellID)] = true end
            if info.overrideTooltipSpellID and tonumber(info.overrideTooltipSpellID) then ids[tonumber(info.overrideTooltipSpellID)] = true end
            if type(info.linkedSpellIDs) == "table" then
                for _, linked in ipairs(info.linkedSpellIDs) do
                    if tonumber(linked) then ids[tonumber(linked)] = true end
                end
            end
        end
    end
    return ids
end

-- Get the set of spell IDs the user is tracking
local function GetTrackedSpellIDs()
    local settings = SegmentBars:GetSettings()
    local tracked = {}
    if settings and settings.spells then
        for idStr in pairs(settings.spells) do
            local id = tonumber(idStr)
            if id then tracked[id] = true end
        end
    end
    return tracked
end

-- Process one CDM icon frame: map its cooldownID → tracked spellIDs → auraInstanceMap
local function ProcessCDMIcon(icon)
    if not icon then return end
    local cooldownID = icon.cooldownID
    if not cooldownID then return end
    local auraInstanceID = icon.auraInstanceID
    local unit = icon.auraDataUnit or "player"
    if not HasAuraInstanceID(auraInstanceID) then return end

    local trackedIDs = GetTrackedSpellIDs()
    local resolvedIDs = ResolveCooldownIDToSpellIDs(cooldownID)

    for resolvedID in pairs(resolvedIDs) do
        if trackedIDs[resolvedID] then
            auraInstanceMap[resolvedID] = { auraInstanceID = auraInstanceID, unit = unit }
        end
    end
end

-- Hook a CDM icon frame for live SetAuraInstanceInfo/ClearAuraInstanceInfo
local function HookCDMIcon(icon)
    if not icon or hookedCDMFrames[icon] then return end
    hookedCDMFrames[icon] = true

    if icon.SetAuraInstanceInfo then
        hooksecurefunc(icon, "SetAuraInstanceInfo", function(self)
            ProcessCDMIcon(self)
        end)
    end
    if icon.ClearAuraInstanceInfo then
        hooksecurefunc(icon, "ClearAuraInstanceInfo", function(self)
            -- Aura removed — clear any entries that pointed to this frame
            local cooldownID = self.cooldownID
            if not cooldownID then return end
            local resolvedIDs = ResolveCooldownIDToSpellIDs(cooldownID)
            for resolvedID in pairs(resolvedIDs) do
                auraInstanceMap[resolvedID] = nil
            end
        end)
    end
end

-- Scan viewer, build map, and hook all icons
local function BuildAuraInstanceMap()
    wipe(auraInstanceMap)
    local function ScanViewer(viewer)
        if not viewer then return end
        local pool = viewer.itemFramePool
        if pool then
            for icon in pool:EnumerateActive() do
                if icon and (icon.Icon or icon.icon) then
                    ProcessCDMIcon(icon)
                    HookCDMIcon(icon)
                end
            end
        else
            -- Fallback: walk children (rare, only if pool unavailable)
            local container = viewer.viewerFrame or viewer
            local children = { container:GetChildren() }
            for _, icon in ipairs(children) do
                if icon and (icon.Icon or icon.icon) then
                    ProcessCDMIcon(icon)
                    HookCDMIcon(icon)
                end
            end
        end
    end
    ScanViewer(_G["EssentialCooldownViewer"])
    ScanViewer(_G["UtilityCooldownViewer"])
end

-- ============================================================
-- Combat-safe duration cache (NaowhQOL pattern)
-- Stores last known CLEAN cooldown/recharge duration per spell.
-- Populated out of combat using tonumber(tostring(...)) to
-- sanitize any tainted values into clean Lua numbers.
-- ============================================================
local durationCache = {}      -- [spellID] = number (clean seconds)
local spellCastTime = {}      -- [spellID] = GetTime() when last cast
local inCombatFlag = false

-- Live cooldown snapshot: updated every SPELL_UPDATE_COOLDOWN/CHARGES
-- Captures whatever the API returns via tonumber(tostring(...)).
-- When CDR reduces a cooldown, these values update even in combat.
local cdStartSnapshot = {}    -- [spellID] = clean startTime number
local cdDurSnapshot = {}      -- [spellID] = clean duration number

local function SafeGetChargeDuration(spellID)
    if not (C_Spell and C_Spell.GetSpellCharges) then return 0 end
    local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
    if ok and info then
        local dur = tonumber(tostring(info.cooldownDuration or 0)) or 0
        if dur > 1.5 then return dur end
    end
    return 0
end

local function SafeGetCooldownDuration(spellID)
    -- Try DurationObject method
    if C_Spell and C_Spell.GetSpellCooldownDuration then
        local ok, durObj = pcall(C_Spell.GetSpellCooldownDuration, spellID)
        if ok and durObj then
            local ok2, total = pcall(durObj.GetTotalDuration, durObj)
            total = tonumber(tostring(total or 0)) or 0
            if ok2 and total > 1.5 then return total end
        end
    end
    -- Fallback: raw cooldown info
    local ok, cdInfo = pcall(C_Spell.GetSpellCooldown, spellID)
    if ok and cdInfo then
        local dur = tonumber(tostring(cdInfo.duration or 0)) or 0
        if dur > 1.5 then return dur end
    end
    return 0
end

local function CacheSpellDuration(spellID)
    local dur = SafeGetChargeDuration(spellID)
    if dur > 0 then durationCache[spellID] = dur; return end
    dur = SafeGetCooldownDuration(spellID)
    if dur > 0 then durationCache[spellID] = dur; return end
    -- Aura duration
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, data = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if ok and data then
            local d = tonumber(tostring(data.duration or 0)) or 0
            if d > 0 then durationCache[spellID] = d end
        end
    end
end

local function CacheAllDurations()
    local settings = SegmentBars:GetSettings()
    if not settings or not settings.spells then return end
    for idStr in pairs(settings.spells) do
        local spellID = tonumber(idStr)
        if spellID then CacheSpellDuration(spellID) end
    end
end

-- Snapshot live cooldown state for all tracked spells.
-- Called on SPELL_UPDATE_COOLDOWN / SPELL_UPDATE_CHARGES.
-- tonumber(tostring(...)) extracts clean numbers from tainted values;
-- if the API returns secret values (tostring → "?"), tonumber → nil
-- and we keep whatever was cached before.
local function SnapshotAllCooldowns()
    local settings = SegmentBars:GetSettings()
    if not settings or not settings.spells then return end
    for idStr in pairs(settings.spells) do
        local spellID = tonumber(idStr)
        if spellID then
        -- Try charges first
        if C_Spell and C_Spell.GetSpellCharges then
            local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
            if ok and info then
                local s = tonumber(tostring(info.cooldownStartTime or 0)) or 0
                local d = tonumber(tostring(info.cooldownDuration or 0)) or 0
                if d > 1.5 and s > 0 then
                    cdStartSnapshot[spellID] = s
                    cdDurSnapshot[spellID] = d
                end
            end
        end
        -- Try regular cooldown (overwrite if better)
        if not cdDurSnapshot[spellID] or cdDurSnapshot[spellID] <= 1.5 then
            local ok, cdInfo = pcall(C_Spell.GetSpellCooldown, spellID)
            if ok and cdInfo then
                local s = tonumber(tostring(cdInfo.startTime or 0)) or 0
                local d = tonumber(tostring(cdInfo.duration or 0)) or 0
                if d > 1.5 and s > 0 then
                    cdStartSnapshot[spellID] = s
                    cdDurSnapshot[spellID] = d
                end
            end
        end
        end -- if spellID
    end
end

-- Get remaining cooldown using clean numbers (combat-safe)
-- Returns (remaining, duration) or (nil, nil)
local function GetCleanRemaining(spellID)
    -- 1) Try DurationObject (combat-safe, returns tainted but extractable)
    if C_Spell and C_Spell.GetSpellChargeDuration then
        local ok, durObj = pcall(C_Spell.GetSpellChargeDuration, spellID)
        if ok and durObj then
            local okR, rem = pcall(durObj.GetRemainingDuration, durObj)
            local okT, total = pcall(durObj.GetTotalDuration, durObj)
            rem = tonumber(tostring(rem or 0)) or 0
            total = tonumber(tostring(total or 0)) or 0
            if okR and total > 1.5 and rem > 0 then
                return rem, total
            end
        end
    end
    if C_Spell and C_Spell.GetSpellCooldownDuration then
        local ok, durObj = pcall(C_Spell.GetSpellCooldownDuration, spellID)
        if ok and durObj then
            local okR, rem = pcall(durObj.GetRemainingDuration, durObj)
            local okT, total = pcall(durObj.GetTotalDuration, durObj)
            rem = tonumber(tostring(rem or 0)) or 0
            total = tonumber(tostring(total or 0)) or 0
            if okR and total > 1.5 and rem > 0 then
                return rem, total
            end
        end
    end
    -- 2) Try charge info start+duration (extract clean numbers)
    if C_Spell and C_Spell.GetSpellCharges then
        local ok, info = pcall(C_Spell.GetSpellCharges, spellID)
        if ok and info then
            local chStart = tonumber(tostring(info.cooldownStartTime or 0)) or 0
            local chDur = tonumber(tostring(info.cooldownDuration or 0)) or 0
            if chDur > 1.5 and chStart > 0 then
                local rem = math.max(0, (chStart + chDur) - GetTime())
                if rem > 0 then return rem, chDur end
            end
        end
    end
    -- 3) Try cooldown info
    local ok, cdInfo = pcall(C_Spell.GetSpellCooldown, spellID)
    if ok and cdInfo then
        local cdStart = tonumber(tostring(cdInfo.startTime or 0)) or 0
        local cdDur = tonumber(tostring(cdInfo.duration or 0)) or 0
        if cdDur > 1.5 and cdStart > 0 then
            local rem = math.max(0, (cdStart + cdDur) - GetTime())
            if rem > 0 then return rem, cdDur end
        end
    end
    -- 4) Live snapshot (updated on SPELL_UPDATE_COOLDOWN, reflects CDR)
    local snapStart = cdStartSnapshot[spellID]
    local snapDur = cdDurSnapshot[spellID]
    if snapStart and snapDur and snapDur > 1.5 and snapStart > 0 then
        local rem = math.max(0, (snapStart + snapDur) - GetTime())
        if rem > 0 then return rem, snapDur end
    end
    -- 5) Fallback: castTime + cached duration (always clean, no CDR awareness)
    local castT = spellCastTime[spellID]
    local baseDur = durationCache[spellID]
    if castT and baseDur and baseDur > 0 then
        local rem = math.max(0, (castT + baseDur) - GetTime())
        if rem > 0 then return rem, baseDur end
    end
    return nil, nil
end

-- Combat-safe stack cache: updated on every UNIT_AURA eve
-- Stores the last known clean count for each tracked spell
local lastKnownStacks = {}   -- [spellID] = clean number

-- Read stacks via auraInstanceID (combat-safe, no taint)

local function ReadAuraInstanceStacks(spellID)
    local entry = auraInstanceMap[spellID]
    if not entry then return nil end
    if not HasAuraInstanceID(entry.auraInstanceID) then return nil end
    if C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
        local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(entry.unit, entry.auraInstanceID)
        if auraData then
            local s = auraData.applications or 0
            return (s > 0) and s or 1
        end
    end
    return nil
end



-- ============================================================
-- Spell data access
-- ============================================================
-- Priority: auraInstanceID (combat-safe) → charges → GetPlayerAuraBySpellID → aura scan → cast count
-- ============================================================

local function GetSpellCount(spellID)
    -- 1) auraInstanceID from CDM viewer (combat-safe, no taint)
    local auraStacks = ReadAuraInstanceStacks(spellID)
    if auraStacks then
        lastKnownStacks[spellID] = auraStacks
        return auraStacks
    end

    if C_Spell and C_Spell.GetSpellCharges then
        local info = C_Spell.GetSpellCharges(spellID)
        if info and info.currentCharges ~= nil then
            local charges = info.currentCharges
            lastKnownStacks[spellID] = charges
            return charges
        end
    end
    -- 3) Direct aura lookup by spell ID (C++ does the match, no Lua == needed)

    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local data = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
        if data then
            local s = data.applications or 0
            local result = (s > 0) and s or 1
            lastKnownStacks[spellID] = result
            return result
        end
    end
    -- 4) GetSpellCastCount — may be SECRET in 12.0.1
    --    Pass directly to display functions (SetValue/SetText accept secrets)
    if C_Spell and C_Spell.GetSpellCastCount then
        local cnt = C_Spell.GetSpellCastCount(spellID)
        if cnt ~= nil then
            return cnt  -- may be secret; callers must not compare
        end
    end
    -- 5) Fallback: last known stacks from previous successful read
    if lastKnownStacks[spellID] then
        return lastKnownStacks[spellID]
    end
    return 0
end

local function GetSpellLabel(spellID)
    if C_Spell and C_Spell.GetSpellName then
        local name = C_Spell.GetSpellName(spellID)
        if name then return name end
    end
    return tostring(spellID)
end

-- ============================================================
-- Bar frames management
-- ============================================================
local barFrames = {}   -- [spellID] = bar frame
local groupFrames = {} -- [groupName] = group container frame

local function GetOrCreateGroupFrame(groupName)
    if groupFrames[groupName] then return groupFrames[groupName] end
    local gf = CreateFrame("Frame", "CCM_SB_Group_" .. groupName, UIParent)
    gf:SetSize(140, 20)
    gf:SetFrameStrata("LOW")
    gf:SetClampedToScreen(true)
    gf:SetMovable(true)
    gf:EnableMouse(false)
    gf:RegisterForDrag("LeftButton")
    gf.groupName = groupName
    gf:SetScript("OnDragStart", function(self)
        local settings = SegmentBars:GetSettings()
        if settings.locked then return end
        self:StartMoving()
    end)
    gf:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local settings = SegmentBars:GetSettings()
        if not settings.groups[self.groupName] then
            settings.groups[self.groupName] = {}
        end
        local _, _, _, x, y = self:GetPoint(1)
        settings.groups[self.groupName].anchorX = x
        settings.groups[self.groupName].anchorY = y
    end)
    groupFrames[groupName] = gf
    return gf
end

local function CreateBarForSpell(spellID)
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetSize(140, 20)
    f:SetFrameStrata("LOW")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(false)
    f:RegisterForDrag("LeftButton")
    f.spellID = spellID
    f:SetScript("OnDragStart", function(self)
        local settings = SegmentBars:GetSettings()
        if settings.locked then return end
        local entry = settings.spells[tostring(self.spellID)]
        -- Only standalone bars drag individually
        if entry and entry.group and entry.group ~= "" then return end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local settings = SegmentBars:GetSettings()
        local entry = settings.spells[tostring(self.spellID)]
        if entry then
            local _, _, _, x, y = self:GetPoint(1)
            entry.anchorX = x
            entry.anchorY = y
        end
    end)

    local statusBar = CreateFrame("StatusBar", nil, f)
    statusBar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    statusBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    statusBar:SetMinMaxValues(0, 3)
    statusBar:SetValue(0)

    local bg = statusBar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(statusBar)
    bg:SetColorTexture(0.08, 0.08, 0.08, 0.75)

    -- Black border edges
    local borderTop = f:CreateTexture(nil, "OVERLAY")
    borderTop:SetColorTexture(0, 0, 0, 1)
    borderTop:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    borderTop:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    borderTop:SetHeight(1)

    local borderBottom = f:CreateTexture(nil, "OVERLAY")
    borderBottom:SetColorTexture(0, 0, 0, 1)
    borderBottom:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    borderBottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    borderBottom:SetHeight(1)

    local borderLeft = f:CreateTexture(nil, "OVERLAY")
    borderLeft:SetColorTexture(0, 0, 0, 1)
    borderLeft:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    borderLeft:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    borderLeft:SetWidth(1)

    local borderRight = f:CreateTexture(nil, "OVERLAY")
    borderRight:SetColorTexture(0, 0, 0, 1)
    borderRight:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    borderRight:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    borderRight:SetWidth(1)

    local label = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", statusBar, "LEFT", 4, 0)
    label:SetText("")

    local countText = statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    countText:SetPoint("RIGHT", statusBar, "RIGHT", -4, 0)
    countText:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    countText:SetText("")

    -- Timer text (shows recharge remaining, centered on bar)
    local cdText = statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cdText:SetPoint("CENTER", statusBar, "CENTER", 0, 0)
    cdText:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
    cdText:SetText("")
    cdText:Hide()

    f.statusBar = statusBar
    f.bg = bg
    f.label = label
    f.countText = countText
    f.cdText = cdText
    f.ticks = {}

    barFrames[spellID] = f
    return f
end

local function GetOrCreateBar(spellID)
    if barFrames[spellID] then return barFrames[spellID] end
    return CreateBarForSpell(spellID)
end

local function RemoveBar(spellID)
    local f = barFrames[spellID]
    if f then
        f:Hide()
        f:SetParent(nil)
        barFrames[spellID] = nil
    end
end

-- ============================================================
-- Tick drawing (segment dividers)
-- ============================================================
local function UpdateBarTicks(barFrame, numSegments, tickTexturePath, tickColor, tickWidth)
    local ticks = barFrame.ticks
    for _, t in ipairs(ticks) do t:Hide() end
    local sb = barFrame.statusBar
    local w = sb:GetWidth()
    local h = sb:GetHeight()
    for i = 1, numSegments - 1 do
        if not ticks[i] then
            ticks[i] = sb:CreateTexture(nil, "OVERLAY")
        end
        local t = ticks[i]
        t:SetTexture(tickTexturePath)
        t:SetVertexColor(tickColor[1], tickColor[2], tickColor[3], tickColor[4] or 1)
        t:SetSize(tickWidth, h)
        t:SetPoint("LEFT", sb, "LEFT", i * (w / numSegments) - (tickWidth / 2), 0)
        t:Show()
    end
end

-- ============================================================
-- Apply appearance to one bar
-- ============================================================
local function ApplyBarAppearance(barFrame, settings, spellEntry, widthOverride, heightOverride)
    local w = widthOverride or settings.barWidth or 140
    local h = heightOverride or settings.barHeight or 20
    barFrame:SetSize(w, h)
    barFrame:SetFrameStrata(settings.frameStrata or "LOW")

    local sb = barFrame.statusBar
    local maxSeg = spellEntry.maxSegments or 3
    sb:SetMinMaxValues(0, maxSeg)

    -- Filling texture
    local texPath = GetLSMStatusbar(settings.fillingTexture or "Blizzard Raid Bar")
    sb:SetStatusBarTexture(texPath)

    -- Gradient
    local gs = spellEntry.gradientStart or SPELL_DEFAULTS.gradientStart
    local ge = spellEntry.gradientEnd or SPELL_DEFAULTS.gradientEnd
    local barTex = sb:GetStatusBarTexture()
    if barTex and barTex.SetGradient then
        barTex:SetGradient("HORIZONTAL",
            CreateColor(gs[1], gs[2], gs[3], gs[4] or 1),
            CreateColor(ge[1], ge[2], ge[3], ge[4] or 1)
        )
    else
        sb:SetStatusBarColor(gs[1], gs[2], gs[3], gs[4] or 1)
    end

    -- Background
    local bgc = settings.bgColor or DEFAULTS.bgColor
    barFrame.bg:SetColorTexture(bgc[1], bgc[2], bgc[3], bgc[4] or 0.75)

    -- Ticks
    local tickPath = GetLSMStatusbar(settings.tickTexture or "Blizzard Raid Bar")
    local tickColor = settings.tickColor or DEFAULTS.tickColor
    local tickW = settings.tickWidth or 2
    UpdateBarTicks(barFrame, maxSeg, tickPath, tickColor, tickW)

    -- Label (spell name, left-aligned)
    if settings.showLabel then
        barFrame.label:Show()
        local fontPath = GetLSMFont(settings.labelFont or "Friz Quadrata TT")
        barFrame.label:SetFont(fontPath, settings.labelFontSize or 11, "OUTLINE")
        barFrame.label:SetText(GetSpellLabel(barFrame.spellID))
    else
        barFrame.label:Hide()
    end
    -- Count text (right-aligned)
    if barFrame.countText then
        local fontPath = GetLSMFont(settings.labelFont or "Friz Quadrata TT")
        barFrame.countText:SetFont(fontPath, settings.labelFontSize or 11, "OUTLINE")
    end
    -- Timer text font
    if barFrame.cdText then
        local fontPath = GetLSMFont(settings.labelFont or "Friz Quadrata TT")
        barFrame.cdText:SetFont(fontPath, settings.labelFontSize or 11, "OUTLINE")
    end
end

-- ============================================================
-- Layout bars: standalone bars get their own position,
-- grouped bars stack inside their group container.
-- ============================================================
local function LayoutBars()
    local settings = SegmentBars:GetSettings()
    EnsureDB()
    local w = settings.barWidth or 140
    local h = settings.barHeight or 20
    local spacing = settings.barSpacing or 4

    local _, _, currentKey = GetPlayerClassSpec()

    -- Separate spells into standalone vs grouped
    local standalone = {} -- { {id, entry, order}, ... }
    local groups = {}     -- { [groupName] = { {id, entry, order}, ... } }
    for idStr, entry in pairs(settings.spells) do
        local id = tonumber(idStr)
        if id and (not entry.classSpec or entry.classSpec == currentKey) then
            EnsureSpellDefaults(entry)
            local gName = entry.group
            if gName and gName ~= "" then
                if not groups[gName] then groups[gName] = {} end
                table.insert(groups[gName], { id = id, entry = entry, order = entry.order or 0 })
            else
                table.insert(standalone, { id = id, entry = entry, order = entry.order or 0 })
            end
        end
    end

    -- Remove bars for spells no longer tracked
    for spellID in pairs(barFrames) do
        if not settings.spells[tostring(spellID)] then
            RemoveBar(spellID)
        end
    end

    -- Layout standalone bars (each at its own position on UIParent)
    local standaloneIdx = 0
    table.sort(standalone, function(a, b)
        if a.order == b.order then return a.id < b.id end
        return a.order < b.order
    end)
    for _, info in ipairs(standalone) do
        local bar = GetOrCreateBar(info.id)
        ApplyBarAppearance(bar, settings, info.entry)
        bar:SetParent(UIParent)
        bar:ClearAllPoints()
        -- Auto-assign position for bars that haven't been placed yet
        if info.entry.anchorX == nil then
            info.entry.anchorX = (settings.anchorX or 0)
            info.entry.anchorY = (settings.anchorY or -180) - standaloneIdx * (h + spacing)
        end
        bar:SetPoint("CENTER", UIParent, "CENTER", info.entry.anchorX, info.entry.anchorY)
        bar:Show()
        standaloneIdx = standaloneIdx + 1
    end

    -- Layout grouped bars
    for gName, gSpells in pairs(groups) do
        table.sort(gSpells, function(a, b)
            if a.order == b.order then return a.id < b.id end
            return a.order < b.order
        end)

        -- Ensure group has saved position
        if not settings.groups[gName] then
            settings.groups[gName] = {
                anchorX = settings.anchorX or 0,
                anchorY = settings.anchorY or -180,
                barWidth = settings.barWidth or 140,
                barHeight = settings.barHeight or 20,
                barSpacing = settings.barSpacing or 4,
            }
        end
        local gData = settings.groups[gName]

        local gf = GetOrCreateGroupFrame(gName)
        gf:ClearAllPoints()
        gf:SetPoint("CENTER", UIParent, "CENTER", gData.anchorX or 0, gData.anchorY or -180)
        gf:SetFrameStrata(settings.frameStrata or "LOW")

        -- Per-group sizing (fall back to global)
        local gw = gData.barWidth or w
        local gh = gData.barHeight or h
        local gs = gData.barSpacing or spacing

        local yOffset = 0
        for _, info in ipairs(gSpells) do
            local bar = GetOrCreateBar(info.id)
            ApplyBarAppearance(bar, settings, info.entry, gw, gh)
            bar:SetParent(gf)
            bar:ClearAllPoints()
            bar:SetPoint("TOP", gf, "TOP", 0, -yOffset)
            bar:Show()
            yOffset = yOffset + gh + gs
        end

        local totalH = #gSpells > 0 and (yOffset - gs) or gh
        gf:SetSize(gw, math.max(totalH, 1))
        gf:Show()
    end

    -- Hide unused group frames
    for gName, gf in pairs(groupFrames) do
        if not groups[gName] then
            gf:Hide()
        end
    end
end

-- ============================================================
-- Update bar counts + statusbar fill (event-driven, API calls allowed)
-- Called from sbDispatch on SPELL_UPDATE_COOLDOWN etc.
-- ============================================================
local function UpdateBarCounts()
    local settings = SegmentBars:GetSettings()
    EnsureDB()
    local _, _, currentKey = GetPlayerClassSpec()
    local showCount = settings.showCount ~= false
    for idStr, entry in pairs(settings.spells) do
        local spellID = tonumber(idStr)
        if spellID and (not entry.classSpec or entry.classSpec == currentKey) then
            local bar = barFrames[spellID]
            if bar then
                local maxSeg = entry.maxSegments or 3
                bar.statusBar:SetMinMaxValues(0, maxSeg)

                local count = GetSpellCount(spellID) or 0
                -- count may be a secret value from GetSpellCastCount
                -- SetValue accepts secrets; for text we must use pcall
                bar.statusBar:SetValue(count)

                if bar.countText then
                    if showCount then
                        -- Secret values can't be used in format strings directly
                        -- Try SetFormattedText in pcall; fall back to SetText with count
                        local ok = pcall(bar.countText.SetFormattedText, bar.countText, "%d / %d", count, maxSeg)
                        if not ok then
                            -- count is a secret — pass directly to SetText (displays as number)
                            bar.countText:SetText(count)
                        end
                        bar.countText:Show()
                    else
                        bar.countText:SetText("")
                        bar.countText:Hide()
                    end
                end
            end
        end
    end
end

-- ============================================================
-- Update timer text only (lightweight, uses cached snapshots, zero API calls)
-- Called from sbPollFrame at 10Hz while active cooldowns exist
-- ============================================================
local function UpdateBarTimerText()
    local settings = SegmentBars:GetSettings()
    if not settings then return end
    local _, _, currentKey = GetPlayerClassSpec()
    local showCount = settings.showCount ~= false
    local now = GetTime()
    local anyActive = false
    for idStr, entry in pairs(settings.spells) do
        local spellID = tonumber(idStr)
        if spellID and (not entry.classSpec or entry.classSpec == currentKey) then
            local bar = barFrames[spellID]
            if bar and bar.cdText then
                if showCount then
                    -- Use cached snapshot values — zero API calls
                    local snapStart = cdStartSnapshot[spellID]
                    local snapDur = cdDurSnapshot[spellID]
                    local remaining
                    if snapStart and snapDur and snapDur > 1.5 and snapStart > 0 then
                        remaining = (snapStart + snapDur) - now
                        if remaining <= 0 then remaining = nil end
                    end
                    -- Fallback to castTime + cached duration
                    if not remaining then
                        local castT = spellCastTime[spellID]
                        local baseDur = durationCache[spellID]
                        if castT and baseDur and baseDur > 0 then
                            remaining = (castT + baseDur) - now
                            if remaining <= 0 then remaining = nil end
                        end
                    end
                    if remaining and remaining > 0.05 then
                        bar.cdText:SetFormattedText("%.1f", remaining)
                        bar.cdText:Show()
                        anyActive = true
                    else
                        bar.cdText:SetText("")
                        bar.cdText:Hide()
                    end
                else
                    bar.cdText:SetText("")
                    bar.cdText:Hide()
                end
            end
        end
    end
    return anyActive
end

-- Legacy wrapper used by FullRefresh
local function UpdateAllBars()
    UpdateBarCounts()
    UpdateBarTimerText()
end

-- ============================================================
-- Show/hide OnUpdate frame for smooth timer countdown (zero CPU when idle)
-- Only updates timer text using cached start/duration — zero API calls per tick.
-- ============================================================
local sbPollFrame = CreateFrame("Frame")
sbPollFrame:Hide()
sbPollFrame._elapsed = 0

local function StopPollTimer()
    sbPollFrame:Hide()
end

sbPollFrame:SetScript("OnUpdate", function(self, elapsed)
    self._elapsed = self._elapsed + elapsed
    if self._elapsed < 0.5 then return end
    self._elapsed = 0

    local settings = SegmentBars:GetSettings()
    if not settings or settings.enabled == false then
        self:Hide()
        return
    end
    local anyActive = UpdateBarTimerText()
    if not anyActive then
        self:Hide() -- nothing active → sleep (zero CPU)
    end
end)

local function StartPollTimer()
    if sbPollFrame:IsShown() then return end
    sbPollFrame._elapsed = 0
    sbPollFrame:Show()
end

-- ============================================================
-- Master visibility
-- ============================================================
local function HideAll()
    for _, bar in pairs(barFrames) do bar:Hide() end
    for _, gf in pairs(groupFrames) do gf:Hide() end
end

local function UpdateVisibility()
    if not (CkraigProfileManager and CkraigProfileManager.db) then
        HideAll()
        return
    end
    local settings = SegmentBars:GetSettings()
    EnsureDB()

    if settings.enabled == false then
        HideAll()
        return
    end
    if settings.hideWhenMounted and IsPlayerMounted() then
        HideAll()
        return
    end

    -- No spells configured → hide
    local hasSpells = false
    for _ in pairs(settings.spells) do hasSpells = true; break end
    if not hasSpells then
        HideAll()
        return
    end

    -- Show standalone bars and group containers for current spec
    local _, _, currentKey = GetPlayerClassSpec()
    for idStr, entry in pairs(settings.spells) do
        local id = tonumber(idStr)
        if id and (not entry.classSpec or entry.classSpec == currentKey) then
            local bar = barFrames[id]
            if bar then bar:Show() end
            if entry.group and entry.group ~= "" then
                local gf = groupFrames[entry.group]
                if gf then gf:Show() end
            end
        end
    end
end

-- ============================================================
-- Full refresh
-- ============================================================
local function FullRefresh()
    EnsureDB()
    LayoutBars()
    CacheAllDurations()
    UpdateAllBars()
    StartPollTimer()
    UpdateVisibility()
    -- Update locked state for all frames
    local settings = SegmentBars:GetSettings()
    local locked = settings.locked ~= false
    for spellID, bar in pairs(barFrames) do
        local entry = settings.spells[tostring(spellID)]
        local isGrouped = entry and entry.group and entry.group ~= ""
        -- Grouped bars never get mouse; the group frame handles drag
        bar:EnableMouse(not locked and not isGrouped)
    end
    for _, gf in pairs(groupFrames) do gf:EnableMouse(not locked) end
end

local function UpdateLocked()
    local settings = SegmentBars:GetSettings()
    local locked = settings.locked ~= false
    for spellID, bar in pairs(barFrames) do
        local entry = settings.spells[tostring(spellID)]
        local isGrouped = entry and entry.group and entry.group ~= ""
        bar:EnableMouse(not locked and not isGrouped)
    end
    for _, gf in pairs(groupFrames) do gf:EnableMouse(not locked) end
end

-- ============================================================
-- Events (show/hide dispatch: coalesces rapid events into one update)
-- ============================================================
local eventFrame = CreateFrame("Frame")
local sbDispatch = CreateFrame("Frame")
sbDispatch:Hide()
local sbDispatchNeedsAuraRebuild = false
local sbDispatchNeedsCacheDurations = false

sbDispatch:SetScript("OnUpdate", function(self)
    self:Hide()
    local settings = SegmentBars:GetSettings()
    if not settings or not settings.spells or not next(settings.spells) then return end
    if sbDispatchNeedsAuraRebuild then
        sbDispatchNeedsAuraRebuild = false
        BuildAuraInstanceMap()
    end
    if sbDispatchNeedsCacheDurations then
        sbDispatchNeedsCacheDurations = false
        CacheAllDurations()
    end
    SnapshotAllCooldowns()
    UpdateBarCounts()
    StartPollTimer()
    UpdateVisibility()
end)

-- Events registered at PLAYER_LOGIN, gated by enabled state
eventFrame:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        inCombatFlag = UnitAffectingCombat("player")
        C_Timer.After(0.5, function()
            BuildAuraInstanceMap()
            FullRefresh()
        end)
        return
    end
    if event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        UpdateVisibility()
        return
    end
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        C_Timer.After(0.5, function()
            BuildAuraInstanceMap()
            FullRefresh()
        end)
        return
    end
    -- Track spell casts for combat-safe timer fallback
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, castSpellID = ...
        if castSpellID then
            local settings = SegmentBars:GetSettings()
            if settings and settings.spells then
                local key = tostring(castSpellID)
                if settings.spells[key] then
                    spellCastTime[castSpellID] = GetTime()
                    if not inCombatFlag then
                        CacheSpellDuration(castSpellID)
                    end
                    StartPollTimer()
                end
            end
        end
        return
    end
   -- Enter combat: cache durations while values are still clean
    if event == "PLAYER_REGEN_DISABLED" then
        inCombatFlag = true
        CacheAllDurations()
        SnapshotAllCooldowns()
        UpdateBarCounts()  -- one clean read before combat starts
        return
    end
    -- Leave combat: rebuild everything with clean values
    if event == "PLAYER_REGEN_ENABLED" then
        inCombatFlag = false
        BuildAuraInstanceMap()
        CacheAllDurations()
        for spellID in pairs(spellCastTime) do
            local rem = GetCleanRemaining(spellID)
            if not rem or rem <= 0 then
                spellCastTime[spellID] = nil
            end
        end
        wipe(lastKnownStacks)  -- clear stale cache
        UpdateAllBars()
        StartPollTimer()
        UpdateVisibility()
        return
    end
    -- UNIT_AURA during combat: update stacks immediately
    -- GetPlayerAuraBySpellID is a C++ lookup — safe in combat
    if event == "UNIT_AURA" and arg1 == "player" then
        UpdateBarCounts()
        SnapshotAllCooldowns()
        StartPollTimer()
        return
    end
    -- Batch frequent events into one dispatch next render frame
    if not InCombatLockdown() then
        sbDispatchNeedsAuraRebuild = true
        sbDispatchNeedsCacheDurations = true
    end
    sbDispatch:Show()
end)

-- ============================================================
-- Profile change hook
-- ============================================================
function SegmentBars:OnProfileChanged()
    C_Timer.After(0.5, function()
        FullRefresh()
    end)
end

-- ============================================================
-- Add / Remove spells API
-- ============================================================
function SegmentBars:AddSpell(spellID, maxSegments)
    local settings = self:GetSettings()
    EnsureDB()
    local key = tostring(spellID)
    if settings.spells[key] then return end
    local _, _, classSpecKey = GetPlayerClassSpec()
    settings.spells[key] = {
        maxSegments = maxSegments or 3,
        gradientStart = { unpack(SPELL_DEFAULTS.gradientStart) },
        gradientEnd = { unpack(SPELL_DEFAULTS.gradientEnd) },
        order = 0,
        classSpec = classSpecKey,
    }
    FullRefresh()
end

function SegmentBars:RemoveSpell(spellID)
    local settings = self:GetSettings()
    EnsureDB()
    settings.spells[tostring(spellID)] = nil
    RemoveBar(spellID)
    FullRefresh()
end

-- ============================================================
-- CDM Catalog Scanner
-- ============================================================
-- Scans EssentialCooldownViewer / UtilityCooldownViewer children for all available spells.
-- Returns a sorted list of { cooldownID, spellID, name, icon }.
-- Must be called out of combat (frame properties may be tainted).
-- ============================================================

local function ScanCDMCatalog()
    local results = {}
    local seen = {}

    local function ScanViewer(viewer)
        if not viewer then return end
        local container = viewer.viewerFrame or viewer
        local ok, children = pcall(function() return { container:GetChildren() } end)
        if not ok or not children then return end

        for _, icon in ipairs(children) do
            if icon and (icon.Icon or icon.icon) then
                local cdID = tonumber(icon.cooldownID)
                if cdID and not seen[cdID] then
                    seen[cdID] = true
                    local spellID = cdID
                    local spellName, iconTexture

                    -- Resolve via CooldownViewer info
                    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                        local ok2, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
                        if ok2 and info then
                            local linked = info.linkedSpellIDs and info.linkedSpellIDs[1]
                            spellID = linked or info.overrideSpellID or info.spellID or cdID
                        end
                    end

                    if C_Spell and C_Spell.GetSpellName then
                        spellName = C_Spell.GetSpellName(spellID)
                    end
                    if C_Spell and C_Spell.GetSpellTexture then
                        iconTexture = C_Spell.GetSpellTexture(spellID)
                    end

                    if spellName then
                        table.insert(results, {
                            cooldownID = cdID,
                            spellID = spellID,
                            name = spellName,
                            icon = iconTexture or "Interface\\ICONS\\INV_Misc_QuestionMark",
                        })
                    end
                end
            end
        end
    end

    ScanViewer(_G["EssentialCooldownViewer"])
    ScanViewer(_G["UtilityCooldownViewer"])

    table.sort(results, function(a, b) return (a.name or "") < (b.name or "") end)
    return results
end

-- Expose scanning for Ace3 options
function SegmentBars:ScanCDMCatalog()
    return ScanCDMCatalog()
end

-- ============================================================
-- Options Panel
-- ============================================================
local optionsPanelCreated = false

function SegmentBars:CreateOptionsPanel()
    if optionsPanelCreated then return end
    optionsPanelCreated = true

    local panel = CreateFrame("Frame", "CCM_SegmentBarsPanel", UIParent)
    panel:SetSize(600, 600)
    panel.name = "Segment Bars"
    _G.CCM_SegmentBarsPanel = panel

    -- Background
    local bgTex = panel:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints(panel)
    bgTex:SetColorTexture(0.05, 0.05, 0.05, 0.8)

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("|cff00ccffSegment Bars|r")

    -- Warning subtitle
    local warning = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    warning:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    warning:SetText("|cffff4444Segment Bars are designed for spells with charges/stacks. Buffs will not track perfectly here — use Cooldown Bars instead.|r")
    warning:SetJustifyH("LEFT")
    warning:SetWidth(540)

    -- ---- Global settings area ----
    local yLine = -56

    -- Enable checkbox
    local enableCB = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    enableCB:SetPoint("TOPLEFT", 16, yLine)
    enableCB.Text:SetText("Enable Segment Bars")
    enableCB:SetScript("OnClick", function(self)
        local settings = SegmentBars:GetSettings()
        settings.enabled = self:GetChecked()
        ReloadUI()
    end)

    -- Hide when mounted checkbox
    local mountCB = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    mountCB:SetPoint("TOPLEFT", 16, yLine - 26)
    mountCB.Text:SetText("Hide When Mounted")
    mountCB:SetScript("OnClick", function(self)
        local settings = SegmentBars:GetSettings()
        settings.hideWhenMounted = self:GetChecked()
        UpdateVisibility()
    end)

    -- Show label checkbox
    local labelCB = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    labelCB:SetPoint("TOPLEFT", 220, yLine)
    labelCB.Text:SetText("Show Spell Name")
    labelCB:SetScript("OnClick", function(self)
        local settings = SegmentBars:GetSettings()
        settings.showLabel = self:GetChecked()
        LayoutBars()
    end)

    -- Lock checkbox
    local lockCB = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    lockCB:SetPoint("TOPLEFT", 220, yLine - 26)
    lockCB.Text:SetText("Lock Position")
    lockCB:SetScript("OnClick", function(self)
        local settings = SegmentBars:GetSettings()
        settings.locked = self:GetChecked()
        UpdateLocked()
    end)

    -- Show Count checkbox
    local countCB = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    countCB:SetPoint("TOPLEFT", 420, yLine)
    countCB.Text:SetText("Show Stack Count")
    countCB:SetScript("OnClick", function(self)
        local settings = SegmentBars:GetSettings()
        settings.showCount = self:GetChecked()
        UpdateAllBars()
    end)

    -- Bar Width slider
    local widthLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    widthLabel:SetPoint("TOPLEFT", 16, yLine - 60)
    widthLabel:SetText("Bar Width:")

    local widthSlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    widthSlider:SetPoint("TOPLEFT", 100, yLine - 58)
    widthSlider:SetSize(150, 16)
    widthSlider:SetMinMaxValues(40, 400)
    widthSlider:SetValueStep(1)
    widthSlider:SetObeyStepOnDrag(true)
    widthSlider.Low:SetText("40")
    widthSlider.High:SetText("400")
    widthSlider:SetScript("OnValueChanged", function(self, val)
        local settings = SegmentBars:GetSettings()
        settings.barWidth = math.floor(val)
        self.Text:SetText(tostring(math.floor(val)))
        FullRefresh()
    end)

    -- Bar Height slider
    local heightLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heightLabel:SetPoint("TOPLEFT", 300, yLine - 60)
    heightLabel:SetText("Bar Height:")

    local heightSlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    heightSlider:SetPoint("TOPLEFT", 380, yLine - 58)
    heightSlider:SetSize(150, 16)
    heightSlider:SetMinMaxValues(6, 60)
    heightSlider:SetValueStep(1)
    heightSlider:SetObeyStepOnDrag(true)
    heightSlider.Low:SetText("6")
    heightSlider.High:SetText("60")
    heightSlider:SetScript("OnValueChanged", function(self, val)
        local settings = SegmentBars:GetSettings()
        settings.barHeight = math.floor(val)
        self.Text:SetText(tostring(math.floor(val)))
        FullRefresh()
    end)

    -- ============================================================
    -- Available Spells from CDM (catalog picker)
    -- ============================================================
    local catalogHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    catalogHeader:SetPoint("TOPLEFT", 16, yLine - 96)
    catalogHeader:SetText("|cffaaaaaa— Available Spells from Cooldown Manager —|r")

    -- Catalog scroll area
    local catalogScroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    catalogScroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, yLine - 114)
    catalogScroll:SetSize(560, 120)

    local catalogChild = CreateFrame("Frame")
    catalogChild:SetSize(540, 1)
    catalogScroll:SetScrollChild(catalogChild)

    -- Catalog border
    local catalogBorder = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    catalogBorder:SetPoint("TOPLEFT", catalogScroll, "TOPLEFT", -2, 2)
    catalogBorder:SetPoint("BOTTOMRIGHT", catalogScroll, "BOTTOMRIGHT", 18, -2)
    catalogBorder:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    catalogBorder:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

    local catalogRowWidgets = {}

    local function ClearCatalogRows()
        for _, row in ipairs(catalogRowWidgets) do
            if row.frame then row.frame:Hide(); row.frame:SetParent(nil) end
        end
        wipe(catalogRowWidgets)
    end

    -- Forward declare RebuildSpellList (defined below)
    local RebuildSpellList

    local function RebuildCatalog()
        ClearCatalogRows()
        local catalog = ScanCDMCatalog()
        local settings = SegmentBars:GetSettings()
        EnsureDB()

        local rowH = 26
        local yOff = 0
        for _, entry in ipairs(catalog) do
            -- Skip spells already tracked
            local alreadyTracked = settings.spells[tostring(entry.spellID)] ~= nil
                or settings.spells[tostring(entry.cooldownID)] ~= nil

            local row = CreateFrame("Frame", nil, catalogChild)
            row:SetSize(540, rowH)
            row:SetPoint("TOPLEFT", 0, -yOff)

            -- Hover highlight
            local hl = row:CreateTexture(nil, "BACKGROUND")
            hl:SetAllPoints(row)
            hl:SetColorTexture(1, 1, 1, 0)
            row:EnableMouse(true)
            row:SetScript("OnEnter", function() hl:SetColorTexture(1, 1, 1, 0.05) end)
            row:SetScript("OnLeave", function() hl:SetColorTexture(1, 1, 1, 0) end)

            -- Icon
            local iconTex = row:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(20, 20)
            iconTex:SetPoint("LEFT", 4, 0)
            iconTex:SetTexture(entry.icon)

            -- Spell name + ID
            local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameFS:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)
            nameFS:SetWidth(280)
            nameFS:SetJustifyH("LEFT")
            nameFS:SetText(entry.name .. "  |cff888888(" .. entry.spellID .. ")|r")

            if alreadyTracked then
                -- Already tracked indicator
                local trackLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                trackLabel:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                trackLabel:SetText("|cff44ff44Tracking|r")
            else
                -- Segments input
                local segLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                segLbl:SetPoint("LEFT", row, "LEFT", 340, 0)
                segLbl:SetText("Segs:")

                local segInput = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
                segInput:SetPoint("LEFT", segLbl, "RIGHT", 2, 0)
                segInput:SetSize(30, 18)
                segInput:SetAutoFocus(false)
                segInput:SetNumeric(true)
                segInput:SetText("3")

                -- Add button
                local addBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                addBtn:SetSize(40, 20)
                addBtn:SetPoint("LEFT", segInput, "RIGHT", 6, 0)
                addBtn:SetText("Add")
                local capturedSpellID = entry.spellID
                addBtn:SetScript("OnClick", function()
                    local maxSeg = tonumber(segInput:GetText()) or 3
                    if maxSeg < 1 then maxSeg = 1 end
                    if maxSeg > 99 then maxSeg = 99 end
                    SegmentBars:AddSpell(capturedSpellID, maxSeg)
                    -- Also rebuild aura map for new spell
                    BuildAuraInstanceMap()
                    RebuildCatalog()
                    RebuildSpellList()
                end)
            end

            table.insert(catalogRowWidgets, { frame = row })
            yOff = yOff + rowH
        end

        if #catalog == 0 then
            local emptyLabel = catalogChild:CreateFontString(nil, "OVERLAY", "GameFontDisable")
            emptyLabel:SetPoint("TOPLEFT", 8, -4)
            emptyLabel:SetText("No spells found. Open Cooldown Manager first so icons appear.")
            local emptyRow = CreateFrame("Frame", nil, catalogChild)
            emptyRow:SetSize(540, 24)
            emptyRow:SetPoint("TOPLEFT", 0, 0)
            table.insert(catalogRowWidgets, { frame = emptyRow })
            yOff = 24
        end

        catalogChild:SetHeight(math.max(yOff, 1))
    end

    -- Rescan button
    local rescanBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    rescanBtn:SetSize(80, 20)
    rescanBtn:SetPoint("TOPRIGHT", catalogScroll, "TOPRIGHT", 14, 16)
    rescanBtn:SetText("Rescan")
    rescanBtn:SetScript("OnClick", function() RebuildCatalog() end)

    -- ============================================================
    -- Manual add (fallback if spell not in CDM)
    -- ============================================================
    local manualY = yLine - 244
    local manualLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    manualLabel:SetPoint("TOPLEFT", 16, manualY)
    manualLabel:SetText("Manual Add Spell ID:")

    local addBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    addBox:SetPoint("TOPLEFT", 150, manualY + 4)
    addBox:SetSize(80, 22)
    addBox:SetAutoFocus(false)
    addBox:SetNumeric(true)

    local segLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    segLabel:SetPoint("TOPLEFT", 240, manualY)
    segLabel:SetText("Segs:")

    local segBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    segBox:SetPoint("TOPLEFT", 275, manualY + 4)
    segBox:SetSize(40, 22)
    segBox:SetAutoFocus(false)
    segBox:SetNumeric(true)
    segBox:SetText("3")

    -- ============================================================
    -- Tracked Spells (configured bars)
    -- ============================================================
    local trackedHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    trackedHeader:SetPoint("TOPLEFT", 16, manualY - 30)
    trackedHeader:SetText("|cffaaaaaa— Tracked Spells —|r")

    -- Scroll frame for tracked spell list
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, manualY - 48)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 16)

    local scrollChild = CreateFrame("Frame")
    scrollChild:SetSize(550, 1)
    scrollFrame:SetScrollChild(scrollChild)

    local spellRowWidgets = {}

    local function ClearSpellRows()
        for _, row in ipairs(spellRowWidgets) do
            if row.frame then row.frame:Hide(); row.frame:SetParent(nil) end
        end
        wipe(spellRowWidgets)
    end

    RebuildSpellList = function()
        ClearSpellRows()
        local settings = SegmentBars:GetSettings()
        EnsureDB()

        -- Sort by order then ID
        local sorted = {}
        for idStr, entry in pairs(settings.spells) do
            local id = tonumber(idStr)
            if id then
                EnsureSpellDefaults(entry)
                table.insert(sorted, { id = id, entry = entry })
            end
        end
        table.sort(sorted, function(a, b)
            local oa = a.entry.order or 0
            local ob = b.entry.order or 0
            if oa == ob then return a.id < b.id end
            return oa < ob
        end)

        local rowH = 58
        local yOff = 0
        for idx, info in ipairs(sorted) do
            local row = CreateFrame("Frame", nil, scrollChild)
            row:SetSize(540, rowH)
            row:SetPoint("TOPLEFT", 0, -yOff)

            -- Spell icon
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(20, 20)
            icon:SetPoint("TOPLEFT", 4, -4)
            local spellIcon
            if C_Spell and C_Spell.GetSpellTexture then
                spellIcon = C_Spell.GetSpellTexture(info.id)
            end
            icon:SetTexture(spellIcon or "Interface\\ICONS\\INV_Misc_QuestionMark")

            -- Name + class/spec tag
            local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameText:SetPoint("LEFT", icon, "RIGHT", 6, 0)
            nameText:SetWidth(200)
            nameText:SetJustifyH("LEFT")
            local csTag = info.entry.classSpec and ("  |cff66aa66[" .. info.entry.classSpec .. "]|r") or ""
            nameText:SetText(GetSpellLabel(info.id) .. "  |cff888888(" .. info.id .. ")|r" .. csTag)

            -- Max segments input (row 1 right side)
            local segLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            segLbl:SetPoint("TOPLEFT", 250, -6)
            segLbl:SetText("Segments:")

            local segInput = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
            segInput:SetPoint("LEFT", segLbl, "RIGHT", 4, 0)
            segInput:SetSize(40, 18)
            segInput:SetAutoFocus(false)
            segInput:SetNumeric(true)
            segInput:SetText(tostring(info.entry.maxSegments or 3))
            local capturedID = info.id
            segInput:SetScript("OnEnterPressed", function(self)
                local val = tonumber(self:GetText())
                if val and val >= 1 and val <= 99 then
                    local s = SegmentBars:GetSettings()
                    local key = tostring(capturedID)
                    if s.spells[key] then
                        s.spells[key].maxSegments = val
                    end
                    FullRefresh()
                end
                self:ClearFocus()
            end)

            -- Group editbox (row 2: left side)
            local grpLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            grpLbl:SetPoint("TOPLEFT", 30, -28)
            grpLbl:SetText("Group:")

            -- Forward-declare refresh function for group size inputs
            local RefreshGroupSizeInputs

            local grpInput = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
            grpInput:SetPoint("LEFT", grpLbl, "RIGHT", 4, 0)
            grpInput:SetSize(80, 18)
            grpInput:SetAutoFocus(false)
            grpInput:SetText(info.entry.group or "")
            grpInput:SetScript("OnEnterPressed", function(self)
                local s = SegmentBars:GetSettings()
                local key = tostring(capturedID)
                if s.spells[key] then
                    local text = self:GetText() or ""
                    text = strtrim(text)
                    s.spells[key].group = text
                    info.entry.group = text
                    -- Clear per-bar position when joining a group
                    if text ~= "" then
                        s.spells[key].anchorX = nil
                        s.spells[key].anchorY = nil
                    end
                end
                if RefreshGroupSizeInputs then RefreshGroupSizeInputs() end
                FullRefresh()
                self:ClearFocus()
            end)

            local grpHint = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            grpHint:SetPoint("LEFT", grpInput, "RIGHT", 6, 0)
            grpHint:SetText("|cff666666empty = standalone|r")

            -- Per-group W / H / S inputs (row 2, right side)
            local function GetGroupData(gName)
                local s = SegmentBars:GetSettings()
                if not gName or gName == "" then return nil end
                if not s.groups[gName] then
                    s.groups[gName] = {
                        anchorX = s.anchorX or 0, anchorY = s.anchorY or -180,
                        barWidth = s.barWidth or 140, barHeight = s.barHeight or 20, barSpacing = s.barSpacing or 4,
                    }
                end
                return s.groups[gName]
            end

            local grpW_lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            grpW_lbl:SetPoint("TOPLEFT", 280, -28)
            grpW_lbl:SetText("W:")
            local grpW_input = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
            grpW_input:SetPoint("LEFT", grpW_lbl, "RIGHT", 2, 0)
            grpW_input:SetSize(36, 18)
            grpW_input:SetAutoFocus(false)
            grpW_input:SetNumeric(true)

            local grpH_lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            grpH_lbl:SetPoint("TOPLEFT", 340, -28)
            grpH_lbl:SetText("H:")
            local grpH_input = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
            grpH_input:SetPoint("LEFT", grpH_lbl, "RIGHT", 2, 0)
            grpH_input:SetSize(30, 18)
            grpH_input:SetAutoFocus(false)
            grpH_input:SetNumeric(true)

            local grpS_lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            grpS_lbl:SetPoint("TOPLEFT", 396, -28)
            grpS_lbl:SetText("S:")
            local grpS_input = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
            grpS_input:SetPoint("LEFT", grpS_lbl, "RIGHT", 2, 0)
            grpS_input:SetSize(26, 18)
            grpS_input:SetAutoFocus(false)
            grpS_input:SetNumeric(true)

            -- Populate and enable/disable based on group
            RefreshGroupSizeInputs = function()
                local gName = info.entry.group or ""
                local gd = GetGroupData(gName)
                if gd then
                    grpW_input:SetText(tostring(gd.barWidth or 140))
                    grpH_input:SetText(tostring(gd.barHeight or 20))
                    grpS_input:SetText(tostring(gd.barSpacing or 4))
                    grpW_input:Enable(); grpH_input:Enable(); grpS_input:Enable()
                    grpW_lbl:SetAlpha(1); grpH_lbl:SetAlpha(1); grpS_lbl:SetAlpha(1)
                else
                    grpW_input:SetText(""); grpH_input:SetText(""); grpS_input:SetText("")
                    grpW_input:Disable(); grpH_input:Disable(); grpS_input:Disable()
                    grpW_lbl:SetAlpha(0.35); grpH_lbl:SetAlpha(0.35); grpS_lbl:SetAlpha(0.35)
                end
            end
            RefreshGroupSizeInputs()

            grpW_input:SetScript("OnEnterPressed", function(self)
                local gd = GetGroupData(info.entry.group)
                if gd then
                    local v = tonumber(self:GetText())
                    if v and v >= 20 and v <= 600 then gd.barWidth = math.floor(v) end
                end
                FullRefresh(); self:ClearFocus()
            end)
            grpH_input:SetScript("OnEnterPressed", function(self)
                local gd = GetGroupData(info.entry.group)
                if gd then
                    local v = tonumber(self:GetText())
                    if v and v >= 4 and v <= 80 then gd.barHeight = math.floor(v) end
                end
                FullRefresh(); self:ClearFocus()
            end)
            grpS_input:SetScript("OnEnterPressed", function(self)
                local gd = GetGroupData(info.entry.group)
                if gd then
                    local v = tonumber(self:GetText())
                    if v and v >= 0 and v <= 40 then gd.barSpacing = math.floor(v) end
                end
                FullRefresh(); self:ClearFocus()
            end)

            -- Gradient start color button (row 1)
            local gsBtn = CreateFrame("Button", nil, row)
            gsBtn:SetSize(18, 18)
            gsBtn:SetPoint("TOPLEFT", 400, -4)
            local gsTex = gsBtn:CreateTexture(nil, "ARTWORK")
            gsTex:SetAllPoints(gsBtn)
            local gs = info.entry.gradientStart or SPELL_DEFAULTS.gradientStart
            gsTex:SetColorTexture(gs[1], gs[2], gs[3], gs[4] or 1)
            gsBtn:SetScript("OnClick", function()
                local currentSettings = SegmentBars:GetSettings()
                local spellData = currentSettings.spells[tostring(capturedID)]
                if not spellData then return end
                local cur = spellData.gradientStart or { unpack(SPELL_DEFAULTS.gradientStart) }
                if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
                    ColorPickerFrame:SetupColorPickerAndShow({
                        r = cur[1], g = cur[2], b = cur[3], opacity = cur[4] or 1,
                        hasOpacity = true,
                        swatchFunc = function()
                            local r, g, b = ColorPickerFrame:GetColorRGB()
                            local a = ColorPickerFrame:GetColorAlpha()
                            spellData.gradientStart = { r, g, b, a }
                            gsTex:SetColorTexture(r, g, b, a)
                            FullRefresh()
                        end,
                        cancelFunc = function(prev)
                            spellData.gradientStart = { prev.r, prev.g, prev.b, prev.opacity or 1 }
                            gsTex:SetColorTexture(prev.r, prev.g, prev.b, prev.opacity or 1)
                            FullRefresh()
                        end,
                    })
                end
            end)

            local gsLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            gsLbl:SetPoint("LEFT", gsBtn, "RIGHT", 2, 0)
            gsLbl:SetText("Start")

            -- Gradient end color button (row 1)
            local geBtn = CreateFrame("Button", nil, row)
            geBtn:SetSize(18, 18)
            geBtn:SetPoint("TOPLEFT", 460, -4)
            local geTex = geBtn:CreateTexture(nil, "ARTWORK")
            geTex:SetAllPoints(geBtn)
            local ge = info.entry.gradientEnd or SPELL_DEFAULTS.gradientEnd
            geTex:SetColorTexture(ge[1], ge[2], ge[3], ge[4] or 1)
            geBtn:SetScript("OnClick", function()
                local currentSettings = SegmentBars:GetSettings()
                local spellData = currentSettings.spells[tostring(capturedID)]
                if not spellData then return end
                local cur = spellData.gradientEnd or { unpack(SPELL_DEFAULTS.gradientEnd) }
                if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
                    ColorPickerFrame:SetupColorPickerAndShow({
                        r = cur[1], g = cur[2], b = cur[3], opacity = cur[4] or 1,
                        hasOpacity = true,
                        swatchFunc = function()
                            local r, g, b = ColorPickerFrame:GetColorRGB()
                            local a = ColorPickerFrame:GetColorAlpha()
                            spellData.gradientEnd = { r, g, b, a }
                            geTex:SetColorTexture(r, g, b, a)
                            FullRefresh()
                        end,
                        cancelFunc = function(prev)
                            spellData.gradientEnd = { prev.r, prev.g, prev.b, prev.opacity or 1 }
                            geTex:SetColorTexture(prev.r, prev.g, prev.b, prev.opacity or 1)
                            FullRefresh()
                        end,
                    })
                end
            end)

            local geLbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            geLbl:SetPoint("LEFT", geBtn, "RIGHT", 2, 0)
            geLbl:SetText("End")

            -- Remove button
            local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            removeBtn:SetSize(20, 18)
            removeBtn:SetPoint("TOPLEFT", 520, -4)
            removeBtn:SetText("X")
            removeBtn:SetScript("OnClick", function()
                SegmentBars:RemoveSpell(capturedID)
                RebuildSpellList()
                RebuildCatalog()
            end)

            -- Separator line
            local sep = row:CreateTexture(nil, "ARTWORK")
            sep:SetHeight(1)
            sep:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            sep:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
            sep:SetColorTexture(0.3, 0.3, 0.3, 0.5)

            table.insert(spellRowWidgets, { frame = row })
            yOff = yOff + rowH
        end

        scrollChild:SetHeight(math.max(yOff, 1))
    end

    -- Manual add button
    local manualAddBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    manualAddBtn:SetPoint("TOPLEFT", 325, manualY + 4)
    manualAddBtn:SetSize(60, 22)
    manualAddBtn:SetText("Add")
    manualAddBtn:SetScript("OnClick", function()
        local spellID = tonumber(addBox:GetText())
        local maxSeg = tonumber(segBox:GetText()) or 3
        if not spellID or spellID <= 0 then return end
        if maxSeg < 1 then maxSeg = 1 end
        if maxSeg > 99 then maxSeg = 99 end
        SegmentBars:AddSpell(spellID, maxSeg)
        BuildAuraInstanceMap()
        addBox:SetText("")
        segBox:SetText("3")
        RebuildSpellList()
        RebuildCatalog()
    end)

    -- Refresh on show
    panel:SetScript("OnShow", function()
        local settings = SegmentBars:GetSettings()
        EnsureDB()
        enableCB:SetChecked(settings.enabled ~= false)
        mountCB:SetChecked(settings.hideWhenMounted == true)
        labelCB:SetChecked(settings.showLabel ~= false)
        lockCB:SetChecked(settings.locked ~= false)
        countCB:SetChecked(settings.showCount ~= false)
        widthSlider:SetValue(settings.barWidth or 140)
        heightSlider:SetValue(settings.barHeight or 20)
        RebuildCatalog()
        RebuildSpellList()
    end)
end

-- ============================================================
-- Init on PLAYER_LOGIN
-- ============================================================
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    EnsureDB()
    local settings = SegmentBars:GetSettings()
    if settings and settings.enabled ~= false then
        -- Register all events only when enabled
        eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        eventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
        eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        eventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
        eventFrame:RegisterUnitEvent("UNIT_AURA", "player")
        eventFrame:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        C_Timer.After(0.5, function()
            BuildAuraInstanceMap()
            FullRefresh()
        end)
    end
end)
