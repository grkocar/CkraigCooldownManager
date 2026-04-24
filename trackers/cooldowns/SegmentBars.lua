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
    labelFontSize = 11,
    labelFont = "Friz Quadrata TT",
    showCount = false,
    countFontSize = 11,
    countFont = "Friz Quadrata TT",
    -- Per-spell entries live in .spells = { [spellID] = { maxSegments=N, ... } }
    spells = {},
    -- Named groups (each has its own position + optional per-group sizing)
    -- { [groupName] = { anchorX=N, anchorY=N, barWidth=N, barHeight=N, barSpacing=N } }
    groups = {},
}

local SPELL_DEFAULTS = {
    maxSegments = 3,
    trackMode = "auto",      -- "auto" = try all sources, "charges" = charges/cast count only, "buff" = aura stacks only, "spellcount" = GetSpellCastCount only (e.g. Soul Fragments)
    gradientStart = { 0.20, 0.80, 1.00, 1 },
    gradientEnd   = { 0.00, 0.40, 0.80, 1 },
    order = 0,
    group = "",    -- "" = standalone, any string = group name
    anchorX = nil, -- per-bar position (standalone only); nil = auto-assign
    anchorY = nil,
    -- Per-bar overrides (nil = inherit from global defaults)
    barWidth = nil,
    barHeight = nil,
    fillingTexture = nil,
    frameStrata = nil,
    hideWhenMounted = nil,
    locked = nil,
    -- Label (spell name)
    showLabel = nil,         -- nil = inherit global
    labelFont = nil,
    labelFontSize = nil,
    labelAnchor = "LEFT",    -- LEFT, RIGHT, CENTER, TOP, BOTTOM
    labelOffsetX = 4,
    labelOffsetY = 0,
    -- Count text (numeric stack/charge count)
    showCount = nil,         -- nil = inherit global
    countFont = nil,
    countFontSize = nil,
    countAnchor = "RIGHT",   -- LEFT, RIGHT, CENTER
    countOffsetX = -4,
    countOffsetY = 0,
    -- Spell icon on bar
    showIcon = false,
    iconSize = nil,          -- nil = match bar height
    iconAnchor = "LEFT",     -- LEFT, RIGHT
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

    -- Migration: spells without a group field â†’ assign to "Default" group
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
-- Cached: only updated on PLAYER_SPECIALIZATION_CHANGED
local _sb_cachedClass, _sb_cachedSpec, _sb_cachedKey
local function GetPlayerClassSpec()
    if _sb_cachedKey then return _sb_cachedClass, _sb_cachedSpec, _sb_cachedKey end
    local _, class = UnitClass("player")
    class = class or "UNKNOWN"
    local specName = "Default"
    if GetSpecialization then
        local specIndex = GetSpecialization()
        if specIndex then
            specName = select(2, GetSpecializationInfo(specIndex)) or "Default"
        end
    end
    _sb_cachedClass = class
    _sb_cachedSpec = specName
    _sb_cachedKey = class .. "_" .. specName
    return class, specName, _sb_cachedKey
end
-- Invalidate cache on spec change (called from event handler)
local function InvalidateClassSpecCache()
    _sb_cachedClass = nil
    _sb_cachedSpec = nil
    _sb_cachedKey = nil
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
--   .cooldownID      â€” the CDM cooldown key (always clean, table field)
--   .auraInstanceID  â€” Blizzard unique per-aura instance ID (clean number)
--   .auraDataUnit    â€” "player" or "target"
--
-- NOTE: C_UnitAuras.GetAuraDataByAuraInstanceID is AllowedWhenUntainted ONLY;
-- addon (tainted) code in combat gets nil/error.  Instead we use
-- C_UnitAuras.GetAuraApplicationDisplayCount (AllowedWhenTainted) which
-- returns a display string, or the fallback chain (GetPlayerAuraBySpellID,
-- GetSpellCharges, etc.) which return secret values passable to SetValue/SetText.
--
-- We build a map: user's spellID â†’ { auraInstanceID, unit } from the viewer
-- frames, resolving cooldownID â†’ spellID via C_CooldownViewer.
-- The map is rebuilt out of combat. During combat we also hook
-- SetAuraInstanceInfo/ClearAuraInstanceInfo for live updates.
-- ============================================================

local auraInstanceMap = {}     -- [trackedSpellID] = { auraInstanceID=N, unit="player" }
local hookedCDMFrames = {}     -- [frame] = true (prevent double-hooking)
local lastKnownStacks = {}    -- [spellID] = clean number (combat-safe stack cache)
local UpdateBarCounts          -- forward declaration (defined after bar frame creation)

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
        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(numID)
        if info then
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

-- Get the set of spell IDs the user is tracking (cached, invalidated on full refresh)
local _sb_trackedCache = nil
local function GetTrackedSpellIDs()
    if _sb_trackedCache then return _sb_trackedCache end
    local settings = SegmentBars:GetSettings()
    local tracked = {}
    if settings and settings.spells then
        for idStr in pairs(settings.spells) do
            local id = tonumber(idStr)
            if id then tracked[id] = true end
        end
    end
    _sb_trackedCache = tracked
    return tracked
end

-- Invalidate tracked spell cache when settings change
local function InvalidateTrackedSpellCache()
    _sb_trackedCache = nil
end

-- Process one CDM icon frame: map its cooldownID â†’ tracked spellIDs â†’ auraInstanceMap
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

    -- Prefer stable aura callbacks when available (fires once per real state change)
    if icon.OnAuraInstanceInfoSet then
        hooksecurefunc(icon, "OnAuraInstanceInfoSet", function(self)
            ProcessCDMIcon(self)
        end)
    elseif icon.SetAuraInstanceInfo then
        -- Fallback for frames that don't expose OnAuraInstanceInfoSet
        hooksecurefunc(icon, "SetAuraInstanceInfo", function(self)
            ProcessCDMIcon(self)
        end)
    end
    if icon.OnAuraInstanceInfoCleared then
        hooksecurefunc(icon, "OnAuraInstanceInfoCleared", function(self)
            -- Aura removed: clear tracking + stale cache so segments go to 0
            local cooldownID = self.cooldownID
            if not cooldownID then return end
            local ok, resolvedIDs = pcall(ResolveCooldownIDToSpellIDs, cooldownID)
            if not ok then resolvedIDs = {} end
            local numID = tonumber(cooldownID)
            if numID then resolvedIDs[numID] = true end
            for resolvedID in pairs(resolvedIDs) do
                auraInstanceMap[resolvedID] = nil
                lastKnownStacks[resolvedID] = nil
            end
            UpdateBarCounts()
        end)
    elseif icon.ClearAuraInstanceInfo then
        hooksecurefunc(icon, "ClearAuraInstanceInfo", function(self)
            -- Aura removed: clear tracking + stale cache so segments go to 0
            local cooldownID = self.cooldownID
            if not cooldownID then return end
            local ok, resolvedIDs = pcall(ResolveCooldownIDToSpellIDs, cooldownID)
            if not ok then resolvedIDs = {} end
            local numID = tonumber(cooldownID)
            if numID then resolvedIDs[numID] = true end
            for resolvedID in pairs(resolvedIDs) do
                auraInstanceMap[resolvedID] = nil
                lastKnownStacks[resolvedID] = nil
            end
            UpdateBarCounts()
        end)
    end

    -- Hook methods that update stack displays directly from icon frames
    -- 12.0.5 removed SetCount; charges now live on icon.cooldownChargesCount
    -- and update via RefreshSpellChargeInfo().
    local _is1205 = _G.CkraigCooldownManager and _G.CkraigCooldownManager.Is1205
    if _is1205 then
        -- 12.0.5+ path: hook RefreshSpellChargeInfo (replaces SetCount)
        if icon.RefreshSpellChargeInfo then
            hooksecurefunc(icon, "RefreshSpellChargeInfo", function(self)
                if self.cooldownID then
                    local count = self.cooldownChargesCount or 0
                    local rawID = self.cooldownID
                    local numID = tonumber(rawID)
                    local resolvedIDs
                    if numID and inCombatFlag and cooldownIDCache[numID] then
                        resolvedIDs = cooldownIDCache[numID]
                    else
                        local ok, result = pcall(ResolveCooldownIDToSpellIDs, rawID)
                        resolvedIDs = ok and result or {}
                        if numID then resolvedIDs[numID] = true end
                    end
                    for resolvedID in pairs(resolvedIDs) do
                        if auraInstanceMap[resolvedID] then
                            auraInstanceMap[resolvedID].stackCount = count
                        end
                    end
                    UpdateBarCounts()
                end
            end)
        end
    else
        -- Pre-12.0.5 path: hook SetCount directly
        if icon.SetCount then
            hooksecurefunc(icon, "SetCount", function(self, count)
                -- Icon stack count changed: update our tracking
                if self.cooldownID then
                    -- In combat, ResolveCooldownIDToSpellIDs may fail (tainted APIs).
                    -- Use cached cooldownIDCache as fallback.
                    local rawID = self.cooldownID
                    local numID = tonumber(rawID)
                    local resolvedIDs
                    if numID and inCombatFlag and cooldownIDCache[numID] then
                        resolvedIDs = cooldownIDCache[numID]
                    else
                        local ok, result = pcall(ResolveCooldownIDToSpellIDs, rawID)
                        resolvedIDs = ok and result or {}
                        -- Direct ID fallback
                        if numID then resolvedIDs[numID] = true end
                    end
                    for resolvedID in pairs(resolvedIDs) do
                        if auraInstanceMap[resolvedID] then
                            auraInstanceMap[resolvedID].stackCount = count or 0
                        end
                    end
                    UpdateBarCounts()
                end
            end)
        end
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
            for i = 1, select("#", container:GetChildren()) do
                local icon = select(i, container:GetChildren())
                if icon and (icon.Icon or icon.icon) then
                    ProcessCDMIcon(icon)
                    HookCDMIcon(icon)
                end
            end
        end
    end
    ScanViewer(_G["EssentialCooldownViewer"])
    ScanViewer(_G["UtilityCooldownViewer"])
    ScanViewer(_G["BuffIconCooldownViewer"])
    ScanViewer(_G["BuffBarCooldownViewer"])
end

-- ============================================================
-- Combat-safe duration cache (NaowhQOL pattern)
-- Stores last known CLEAN cooldown/recharge duration per spell.
-- Populated out of combat using tonumber(tostring(...)) to
-- sanitize any tainted values into clean Lua numbers.

-- Cache cooldownID-to-spellID mappings for use during combat
local cooldownIDCache = {}    -- [cooldownID] = [spellID] = true

local function BuildCooldownIDCache()
    wipe(cooldownIDCache)
    local function CacheIcon(viewer)
        if not viewer or not viewer.itemFramePool then return end
        for icon in viewer.itemFramePool:EnumerateActive() do
            if icon and icon.cooldownID then
                local cooldownID = tonumber(icon.cooldownID)
                if cooldownID then
                    if not cooldownIDCache[cooldownID] then
                        cooldownIDCache[cooldownID] = {}
                    end
                    local ids = ResolveCooldownIDToSpellIDs(icon.cooldownID)
                    for spellID in pairs(ids) do
                        cooldownIDCache[cooldownID][spellID] = true
                    end
                end
            end
        end
    end
    CacheIcon(_G["EssentialCooldownViewer"])
    CacheIcon(_G["UtilityCooldownViewer"])
    CacheIcon(_G["BuffIconCooldownViewer"])
    CacheIcon(_G["BuffBarCooldownViewer"])
end

local inCombatFlag = false

-- Read stacks directly from CDM icon Count display (works in combat)
-- During combat, uses cached cooldownID mappings to avoid API restrictions
local _sb_is1205 = nil -- lazy-init on first call
local function ReadStacksFromCDMIcons(spellID)
    if _sb_is1205 == nil then
        _sb_is1205 = _G.CkraigCooldownManager and _G.CkraigCooldownManager.Is1205 or false
    end

    local function ScanViewer(viewer)
        if not viewer then return nil end
        local pool = viewer.itemFramePool
        if pool then
            for icon in pool:EnumerateActive() do
                if icon and icon.cooldownID then
                    local rawID = icon.cooldownID
                    -- Skip secret cooldownIDs — can't compare or tonumber them
                    if issecretvalue and issecretvalue(rawID) then
                        -- Can't match this icon; skip
                    else
                        local cooldownID = tonumber(rawID)
                        if cooldownID then
                            -- Match: direct ID match or cached/resolved match
                            local matched = false
                            if cooldownID == spellID then
                                matched = true
                            elseif cooldownIDCache[cooldownID] and cooldownIDCache[cooldownID][spellID] then
                                matched = true
                            elseif not inCombatFlag then
                                local resolvedIDs = ResolveCooldownIDToSpellIDs(rawID)
                                if resolvedIDs[spellID] then
                                    matched = true
                                    if not cooldownIDCache[cooldownID] then
                                        cooldownIDCache[cooldownID] = {}
                                    end
                                    for id in pairs(resolvedIDs) do
                                        cooldownIDCache[cooldownID][id] = true
                                    end
                                end
                            end

                            if matched then
                                -- 12.0.5+: read cooldownChargesCount directly (clean, always available)
                                -- Do NOT fall back to GetSpellCastCount — it returns the cumulative
                                -- total times the spell was cast this session, not current stacks.
                                -- For buff-stacks spells this returns a huge stale number.
                                if _sb_is1205 then
                                    local charges = icon.cooldownChargesCount
                                    if charges ~= nil then
                                        return tonumber(charges) or 0
                                    end
                                    -- cooldownChargesCount is nil for buff-stacks CDM icons;
                                    -- return nil so the caller falls through to GetPlayerAuraBySpellID.
                                    return nil
                                end

                                -- Pre-12.0.5: read Count text directly from icon frame
                                if icon.Count then
                                    local ok, text = pcall(icon.Count.GetText, icon.Count)
                                    if ok and text then
                                        if issecretvalue and issecretvalue(text) then
                                            -- Secret text: can't tonumber, skip
                                        else
                                            if text ~= "" then
                                                local count = tonumber(text)
                                                if count then return count end
                                            end
                                        end
                                    end
                                end
                                -- Try icon.stacks / icon.applications (may be secret)
                                if icon.stacks and not (issecretvalue and issecretvalue(icon.stacks)) then
                                    local stacks = tonumber(icon.stacks)
                                    if stacks and stacks >= 0 then return stacks end
                                end
                                if icon.applications and not (issecretvalue and issecretvalue(icon.applications)) then
                                    local apps = tonumber(icon.applications)
                                    if apps and apps >= 0 then return apps end
                                end
                                -- Matched but couldn't read clean count; fall through
                                return nil
                            end
                        end
                    end
                end
            end
        end
        return nil
    end
    
    local result = ScanViewer(_G["EssentialCooldownViewer"])
    if result ~= nil then return result end
    result = ScanViewer(_G["UtilityCooldownViewer"])
    if result ~= nil then return result end
    result = ScanViewer(_G["BuffIconCooldownViewer"])
    if result ~= nil then return result end
    result = ScanViewer(_G["BuffBarCooldownViewer"])
    if result ~= nil then return result end

    return result
end

-- ============================================================
local durationCache = {}      -- [spellID] = number (clean seconds)
local spellCastTime = {}      -- [spellID] = GetTime() when last cast

-- Live cooldown snapshot: updated every SPELL_UPDATE_COOLDOWN/CHARGES
-- Captures whatever the API returns via tonumber(tostring(...)).
-- When CDR reduces a cooldown, these values update even in combat.
local cdStartSnapshot = {}    -- [spellID] = clean startTime number
local cdDurSnapshot = {}      -- [spellID] = clean duration number

local function SafeGetChargeDuration(spellID)
    if not (C_Spell and C_Spell.GetSpellCharges) then return 0 end
    local info = C_Spell.GetSpellCharges(spellID)
    if info then
        local dur = tonumber(tostring(info.cooldownDuration or 0)) or 0
        if dur > 1.5 then return dur end
    end
    return 0
end

local function SafeGetCooldownDuration(spellID)
    -- Try DurationObject method
    if C_Spell and C_Spell.GetSpellCooldownDuration then
        local durObj = C_Spell.GetSpellCooldownDuration(spellID)
        if durObj then
            local total = durObj:GetTotalDuration()
            total = tonumber(tostring(total or 0)) or 0
            if total > 1.5 then return total end
        end
    end
    -- Fallback: raw cooldown info
    if not (C_Spell and C_Spell.GetSpellCooldown) then return 0 end
    local cdInfo = C_Spell.GetSpellCooldown(spellID)
    if cdInfo then
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
        local data = C_UnitAuras.GetPlayerAuraBySpellID(spellID)
        if data then
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
-- if the API returns secret values (tostring â†’ "?"), tonumber â†’ nil
-- and we keep whatever was cached before.
local function SnapshotAllCooldowns()
    local settings = SegmentBars:GetSettings()
    if not settings or not settings.spells then return end
    for idStr in pairs(settings.spells) do
        local spellID = tonumber(idStr)
        if spellID then
        -- Try charges first (no pcall: GetSpellCharges returns nil for unknown spells)
        if C_Spell and C_Spell.GetSpellCharges then
            local info = C_Spell.GetSpellCharges(spellID)
            if info then
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
            local cdInfo = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
            if cdInfo then
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
        local durObj = C_Spell.GetSpellChargeDuration(spellID)
        if durObj then
            local rem = durObj:GetRemainingDuration()
            local total = durObj:GetTotalDuration()
            rem = tonumber(tostring(rem or 0)) or 0
            total = tonumber(tostring(total or 0)) or 0
            if total > 1.5 and rem > 0 then
                return rem, total
            end
        end
    end
    if C_Spell and C_Spell.GetSpellCooldownDuration then
        local durObj = C_Spell.GetSpellCooldownDuration(spellID)
        if durObj then
            local rem = durObj:GetRemainingDuration()
            local total = durObj:GetTotalDuration()
            rem = tonumber(tostring(rem or 0)) or 0
            total = tonumber(tostring(total or 0)) or 0
            if total > 1.5 and rem > 0 then
                return rem, total
            end
        end
    end
    -- 2) Try charge info start+duration (extract clean numbers)
    if C_Spell and C_Spell.GetSpellCharges then
        local info = C_Spell.GetSpellCharges(spellID)
        if info then
            local chStart = tonumber(tostring(info.cooldownStartTime or 0)) or 0
            local chDur = tonumber(tostring(info.cooldownDuration or 0)) or 0
            if chDur > 1.5 and chStart > 0 then
                local rem = math.max(0, (chStart + chDur) - GetTime())
                if rem > 0 then return rem, chDur end
            end
        end
    end
    -- 3) Try cooldown info
    local cdInfo = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
    if cdInfo then
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

-- Combat-safe stack cache: updated on every UNIT_AURA event
-- (declared near auraInstanceMap above so HookCDMIcon closures can see it)

-- Read stacks via auraInstanceID (combat-safe, no taint)
-- Uses GetAuraDataByAuraInstanceID (like ArcUI) — .applications is a secret NUMBER
-- in combat, which works with StatusBar:SetValue (C-side, no taint).

local function ReadAuraInstanceStacks(spellID)
    local entry = auraInstanceMap[spellID]
    if not entry then return nil end
    
    -- First priority: stack count tracked directly from CDM icon SetCount hook
    if entry.stackCount ~= nil then
        local clean = tonumber(entry.stackCount)
        if clean ~= nil then return clean end
        -- Might be a secret value from a hooked SetCount; pass through for SetValue
        return entry.stackCount
    end
    
    -- Second priority: GetAuraDataByAuraInstanceID → .applications (secret NUMBER)
    -- This is the same API ArcUI uses — returns a table with .applications as a
    -- secret number in combat. Secret numbers work natively with SetValue().
    if HasAuraInstanceID(entry.auraInstanceID) and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
        local ok, auraData = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, entry.unit, entry.auraInstanceID)
        if ok and auraData then
            local apps = auraData.applications
            if apps ~= nil then
                -- apps is a secret number in combat — pass through for SetValue
                if issecretvalue and issecretvalue(apps) then
                    return apps  -- Secret number: SetValue handles it natively
                end
                local clean = tonumber(apps)
                if clean ~= nil then
                    return (clean > 0) and clean or 1
                end
            end
            -- Aura data exists but no applications field: at least 1 stack
            return 1
        end
    end
    
    -- Third priority: GetAuraApplicationDisplayCount (returns secret STRING — 
    -- only useful out of combat where we can tonumber it)
    if not inCombatFlag and HasAuraInstanceID(entry.auraInstanceID) and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
        local ok, displayStr = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, entry.unit, entry.auraInstanceID, 0, 9999)
        if ok and displayStr and not (issecretvalue and issecretvalue(displayStr)) then
            if displayStr ~= "" then
                local num = tonumber(displayStr)
                if num then return (num > 0) and num or 1 end
            end
        end
    end
    return nil
end


-- ============================================================
-- Spell data access
-- ============================================================
-- Priority: auraInstanceID (combat-safe) â†’ charges â†’ GetPlayerAuraBySpellID â†’ aura scan â†’ cast count
-- ============================================================

local function GetSpellCount(spellID, trackMode)
    trackMode = trackMode or "auto"

    -- ========== SPELL COUNT MODE ==========
    -- Uses C_Spell.GetSpellCastCount directly (e.g. Soul Fragments for Vengeance DH).
    -- GetSpellCastCount returns the current count for these spells, not cumulative casts.
    if trackMode == "spellcount" then
        if C_Spell and C_Spell.GetSpellCastCount then
            local cnt = C_Spell.GetSpellCastCount(spellID)
            if cnt ~= nil then
                if issecretvalue and issecretvalue(cnt) then
                    return cnt  -- secret number: SetValue handles it C-side
                end
                local clean = tonumber(cnt)
                if clean ~= nil then
                    lastKnownStacks[spellID] = clean
                    return clean
                end
            end
        end
        if lastKnownStacks[spellID] then return lastKnownStacks[spellID] end
        return 0
    end

    -- ========== CHARGES MODE ==========
    -- Only use C_Spell.GetSpellCharges / GetSpellCastCount, skip all aura logic.
    if trackMode == "charges" then
        -- In combat: try CDM icon displays first (shows charge count)
        if inCombatFlag then
            local iconStacks = ReadStacksFromCDMIcons(spellID)
            if iconStacks then
                lastKnownStacks[spellID] = iconStacks
                return iconStacks
            end
        end
        -- Spell charges
        if C_Spell and C_Spell.GetSpellCharges then
            local info = C_Spell.GetSpellCharges(spellID)
            if info and info.currentCharges ~= nil then
                local charges = info.currentCharges
                if issecretvalue and issecretvalue(charges) then
                    return charges
                end
                local clean = tonumber(charges)
                if clean ~= nil then
                    lastKnownStacks[spellID] = clean
                    return clean
                end
            end
        end
        -- GetSpellCastCount
        if C_Spell and C_Spell.GetSpellCastCount then
            local cnt = C_Spell.GetSpellCastCount(spellID)
            if cnt ~= nil then
                if issecretvalue and issecretvalue(cnt) then
                    if not lastKnownStacks[spellID] then return cnt end
                else
                    local clean = tonumber(cnt)
                    if clean and clean > 0 then
                        lastKnownStacks[spellID] = clean
                        return clean
                    end
                end
            end
        end
        if lastKnownStacks[spellID] then return lastKnownStacks[spellID] end
        return 0
    end

    -- ========== BUFF MODE ==========
    -- Only use aura/buff sources, skip charges/cast count.
    if trackMode == "buff" then
        -- In combat: try CDM icon displays
        if inCombatFlag then
            local iconStacks = ReadStacksFromCDMIcons(spellID)
            if iconStacks then
                lastKnownStacks[spellID] = iconStacks
                return iconStacks
            end
        end
        -- auraInstanceID from CDM viewer
        local auraStacks = ReadAuraInstanceStacks(spellID)
        if auraStacks ~= nil then
            local clean = tonumber(auraStacks)
            if clean ~= nil then lastKnownStacks[spellID] = clean end
            return auraStacks
        end
        -- Direct aura lookup
        if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
            local ok, data = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
            if ok then
                if data then
                    local apps = data.applications
                    if apps ~= nil then
                        if issecretvalue and issecretvalue(apps) then
                            return apps
                        end
                        local clean = tonumber(apps)
                        if clean ~= nil then
                            local result = (clean > 0) and clean or 1
                            lastKnownStacks[spellID] = result
                            return result
                        end
                    end
                    lastKnownStacks[spellID] = 1
                    return 1
                else
                    lastKnownStacks[spellID] = nil
                    return 0
                end
            end
        end
        if lastKnownStacks[spellID] then return lastKnownStacks[spellID] end
        return 0
    end

    -- ========== AUTO MODE (original behavior) ==========
    -- In combat: read stacks directly from CDM icon displays (Blizzard sets
    -- clean values on its own frames, so Count:GetText() is always readable)
    if inCombatFlag then
        local iconStacks = ReadStacksFromCDMIcons(spellID)
        if iconStacks then
            lastKnownStacks[spellID] = iconStacks
            return iconStacks
        end
    end

    -- 1) auraInstanceID from CDM viewer (GetAuraApplicationDisplayCount is
    --    AllowedWhenTainted; stack count from SetCount hook is always clean)
    local auraStacks = ReadAuraInstanceStacks(spellID)
    if auraStacks ~= nil then
        local clean = tonumber(auraStacks)
        if clean ~= nil then lastKnownStacks[spellID] = clean end
        return auraStacks
    end

    -- 2) Spell charges (AllowedWhenTainted: returns table with potentially
    --    secret fields in combat; secret numbers work with SetValue)
    if C_Spell and C_Spell.GetSpellCharges then
        local info = C_Spell.GetSpellCharges(spellID)
        if info and info.currentCharges ~= nil then
            local charges = info.currentCharges
            -- Secret numbers: issecretvalue check avoids tonumber crash
            if issecretvalue and issecretvalue(charges) then
                return charges  -- Secret number: SetValue handles it
            end
            local clean = tonumber(charges)
            if clean ~= nil then
                lastKnownStacks[spellID] = clean
                return clean
            end
        end
    end

    -- 3) Direct aura lookup by spell ID (AllowedWhenTainted + RequiresNonSecretAura)
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, data = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if ok then
            if data then
                local apps = data.applications
                if apps ~= nil then
                    if issecretvalue and issecretvalue(apps) then
                        return apps  -- Secret number: SetValue handles it
                    end
                    local clean = tonumber(apps)
                    if clean ~= nil then
                        local result = (clean > 0) and clean or 1
                        lastKnownStacks[spellID] = result
                        return result
                    end
                end
                -- Aura exists but applications is nil: at least 1 application
                lastKnownStacks[spellID] = 1
                return 1
            else
                -- API succeeded but returned nil: aura is definitely gone.
                -- Clear stale cache so segments go to 0.
                lastKnownStacks[spellID] = nil
                return 0
            end
        end
    end

    -- 4) GetSpellCastCount (AllowedWhenTainted: may return secret number in combat)
    --    IMPORTANT: only use if spell has no better source above; a secret 0 here
    --    would mask the real count for aura-stacks spells.
    if C_Spell and C_Spell.GetSpellCastCount then
        local cnt = C_Spell.GetSpellCastCount(spellID)
        if cnt ~= nil then
            if issecretvalue and issecretvalue(cnt) then
                -- Secret number. We can't tell if it's 0 or real.
                -- Only use it if we have no lastKnownStacks fallback.
                if not lastKnownStacks[spellID] then
                    return cnt
                end
            else
                local clean = tonumber(cnt)
                if clean and clean > 0 then
                    lastKnownStacks[spellID] = clean
                    return clean
                end
            end
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
        -- Convert to CENTER-relative offsets (StopMovingOrSizing sets TOPLEFT/BOTTOMLEFT)
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local anchorX = cx - ux
        local anchorY = cy - uy
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "CENTER", anchorX, anchorY)
        local settings = SegmentBars:GetSettings()
        if not settings.groups[self.groupName] then
            settings.groups[self.groupName] = {}
        end
        settings.groups[self.groupName].anchorX = anchorX
        settings.groups[self.groupName].anchorY = anchorY
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
        -- Convert to CENTER-relative offsets (StopMovingOrSizing sets TOPLEFT/BOTTOMLEFT)
        local cx, cy = self:GetCenter()
        local ux, uy = UIParent:GetCenter()
        local anchorX = cx - ux
        local anchorY = cy - uy
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "CENTER", anchorX, anchorY)
        local settings = SegmentBars:GetSettings()
        local entry = settings.spells[tostring(self.spellID)]
        if entry then
            entry.anchorX = anchorX
            entry.anchorY = anchorY
        end
    end)

    -- Container for all per-slot bars (replaces single StatusBar)
    local slotsContainer = CreateFrame("Frame", nil, f)
    slotsContainer:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    slotsContainer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)

    local bg = slotsContainer:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(slotsContainer)
    bg:SetColorTexture(0.08, 0.08, 0.08, 0.75)

    -- Invisible single StatusBar kept for legacy SetValue passthrough and tick positioning
    local statusBar = CreateFrame("StatusBar", nil, f)
    statusBar:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
    statusBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
    statusBar:SetMinMaxValues(0, 3)
    statusBar:SetValue(0)
    statusBar:SetAlpha(0)  -- invisible; slots do the real rendering

    -- Per-slot fill bars + offscreen detectors (ArcUI pattern)
    -- Each slot has SetMinMaxValues(i - 0.5, i) so it fills only when count >= i.
    -- Feed the same secret count to every slot; C-side clamping handles the rest.
    -- detectorTex:GetWidth() returns a NON-SECRET number usable for visibility.
    f.slots = {}

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

    -- Label overlay frame above fill bars and tick dividers so text is always readable
    local labelOverlay = CreateFrame("Frame", nil, slotsContainer)
    labelOverlay:SetAllPoints(slotsContainer)
    labelOverlay:SetFrameLevel(slotsContainer:GetFrameLevel() + 3)

    local label = labelOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", slotsContainer, "LEFT", 4, 0)
    label:SetText("")

    -- Count text (numeric stack/charge number)
    local countText = labelOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countText:SetPoint("RIGHT", slotsContainer, "RIGHT", -4, 0)
    countText:SetText("")

    -- Spell icon (optional, hidden by default)
    local spellIconFrame = CreateFrame("Frame", nil, f)
    spellIconFrame:SetSize(20, 20)
    spellIconFrame:SetPoint("RIGHT", f, "LEFT", -2, 0)
    local spellIconTex = spellIconFrame:CreateTexture(nil, "ARTWORK")
    spellIconTex:SetAllPoints(spellIconFrame)
    local iconPath = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID))
                     or "Interface\\ICONS\\INV_Misc_QuestionMark"
    spellIconTex:SetTexture(iconPath)
    spellIconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim borders
    spellIconFrame:Hide() -- hidden by default

    f.statusBar = statusBar
    f.slotsContainer = slotsContainer
    f.bg = bg
    f.label = label
    f.countText = countText
    f.spellIconFrame = spellIconFrame
    f.spellIconTex = spellIconTex
    f.ticks = {}

    barFrames[spellID] = f
    return f
end

local function GetOrCreateBar(spellID)
    if barFrames[spellID] then return barFrames[spellID] end
    return CreateBarForSpell(spellID)
end

-- Build or rebuild per-slot fill bars + offscreen detectors for a bar frame.
-- Called from ApplyBarAppearance whenever maxSegments or size changes.
local function BuildSlots(barFrame, maxSeg, texPath, gradientStart, gradientEnd, containerW, containerH)
    local slots = barFrame.slots or {}
    local container = barFrame.slotsContainer
    if not container then return end

    -- Hide old slots
    for _, slot in ipairs(slots) do
        if slot.fillBar then slot.fillBar:Hide() end
        if slot.detector then slot.detector:Hide() end
    end

    local cw = containerW or container:GetWidth()
    local ch = containerH or container:GetHeight()
    if cw < 1 then cw = 140 end
    if ch < 1 then ch = 20 end
    local slotW = cw / maxSeg

    for i = 1, maxSeg do
        local slot = slots[i] or {}
        slots[i] = slot

        -- Per-slot fill bar (visible, positioned inside container)
        if not slot.fillBar then
            slot.fillBar = CreateFrame("StatusBar", nil, container)
        end
        slot.fillBar:ClearAllPoints()
        slot.fillBar:SetSize(slotW, ch)
        slot.fillBar:SetPoint("LEFT", container, "LEFT", (i - 1) * slotW, 0)
        slot.fillBar:SetStatusBarTexture(texPath or "Interface\\TargetingFrame\\UI-StatusBar")
        -- Key: min/max range so it fills only when count >= this slot index
        slot.fillBar:SetMinMaxValues(i - 0.5, i)
        slot.fillBar:SetValue(0)
        slot.fillBar:SetFrameLevel(container:GetFrameLevel() + 1)
        slot.fillBar:Show()

        -- Apply gradient/color
        local gs = gradientStart or {0.2, 0.6, 1, 1}
        local ge = gradientEnd or {0.4, 0.8, 1, 1}
        local fillTex = slot.fillBar:GetStatusBarTexture()
        if fillTex and fillTex.SetGradient then
            fillTex:SetGradient("HORIZONTAL",
                CreateColor(gs[1], gs[2], gs[3], gs[4] or 1),
                CreateColor(ge[1], ge[2], ge[3], ge[4] or 1)
            )
        else
            slot.fillBar:SetStatusBarColor(gs[1], gs[2], gs[3], gs[4] or 1)
        end

        -- Offscreen 1px detector (non-secret GetWidth proxy)
        if not slot.detector then
            slot.detector = CreateFrame("StatusBar", nil, UIParent)
        end
        slot.detector:ClearAllPoints()
        slot.detector:SetSize(1, 10)
        slot.detector:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -500, 500)
        slot.detector:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        slot.detector:SetStatusBarColor(1, 1, 1, 1)
        slot.detector:SetAlpha(0)
        slot.detector:SetMinMaxValues(i - 0.5, i)
        slot.detector:SetValue(0)
        slot.detector:Show()
        slot.detectorTex = slot.detector:GetStatusBarTexture()
    end

    -- Hide excess slots from previous higher maxSeg
    for i = maxSeg + 1, #slots do
        if slots[i].fillBar then slots[i].fillBar:Hide() end
        if slots[i].detector then slots[i].detector:Hide() end
    end

    barFrame.slots = slots
    barFrame.numSlots = maxSeg
end

local function RemoveBar(spellID)
    local f = barFrames[spellID]
    if f then
        -- Clean up offscreen detector frames (parented to UIParent)
        if f.slots then
            for _, slot in ipairs(f.slots) do
                if slot.detector then slot.detector:Hide() end
            end
        end
        f:Hide()
        f:SetParent(nil)
        barFrames[spellID] = nil
    end
end

-- ============================================================
-- Tick drawing (segment dividers)
-- ============================================================
local function UpdateBarTicks(barFrame, numSegments, tickTexturePath, tickColor, tickWidth, containerW, containerH)
    local ticks = barFrame.ticks
    for _, t in ipairs(ticks) do t:Hide() end

    -- Lazy-create tick overlay frame above fill bars so dividers render on top
    if not barFrame.tickOverlay and barFrame.slotsContainer then
        barFrame.tickOverlay = CreateFrame("Frame", nil, barFrame.slotsContainer)
        barFrame.tickOverlay:SetAllPoints(barFrame.slotsContainer)
    end
    local overlay = barFrame.tickOverlay
    if overlay and barFrame.slotsContainer then
        overlay:SetFrameLevel(barFrame.slotsContainer:GetFrameLevel() + 2)
    end

    local container = overlay or barFrame.slotsContainer or barFrame.statusBar
    local w = containerW or barFrame.slotsContainer:GetWidth()
    local h = containerH or barFrame.slotsContainer:GetHeight()
    for i = 1, numSegments - 1 do
        if not ticks[i] then
            ticks[i] = container:CreateTexture(nil, "OVERLAY")
        end
        local t = ticks[i]
        t:SetTexture(tickTexturePath)
        t:SetVertexColor(tickColor[1], tickColor[2], tickColor[3], tickColor[4] or 1)
        t:SetSize(tickWidth, h)
        t:SetPoint("LEFT", container, "LEFT", i * (w / numSegments) - (tickWidth / 2), 0)
        t:Show()
    end
end

-- ============================================================
-- Helper: resolve per-bar setting with global fallback
-- ============================================================
local function SpellSetting(spellEntry, settings, key, default)
    if spellEntry[key] ~= nil then return spellEntry[key] end
    if settings[key] ~= nil then return settings[key] end
    return default
end

-- Anchor name → anchor point + default offsets
local ANCHOR_POINTS = {
    LEFT   = { point = "LEFT",   relPoint = "LEFT",   dx =  4, dy = 0 },
    RIGHT  = { point = "RIGHT",  relPoint = "RIGHT",  dx = -4, dy = 0 },
    CENTER = { point = "CENTER", relPoint = "CENTER", dx =  0, dy = 0 },
    TOP    = { point = "TOP",    relPoint = "TOP",    dx =  0, dy = -2 },
    BOTTOM = { point = "BOTTOM", relPoint = "BOTTOM", dx =  0, dy =  2 },
}

-- ============================================================
-- Apply appearance to one bar
-- ============================================================
local function ApplyBarAppearance(barFrame, settings, spellEntry, widthOverride, heightOverride)
    local w = widthOverride or spellEntry.barWidth or settings.barWidth or 140
    local h = heightOverride or spellEntry.barHeight or settings.barHeight or 20
    barFrame:SetSize(w, h)
    barFrame:SetFrameStrata(spellEntry.frameStrata or settings.frameStrata or "LOW")

    local sb = barFrame.statusBar
    local maxSeg = spellEntry.maxSegments or 3
    sb:SetMinMaxValues(0, maxSeg)

    -- Filling texture (per-bar override → global)
    local texName = spellEntry.fillingTexture or settings.fillingTexture or "Blizzard Raid Bar"
    local texPath = GetLSMStatusbar(texName)
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

    -- Compute container inner dimensions (1px border inset on each side)
    local containerW = w - 2
    local containerH = h - 2

    -- Build per-slot fill bars + detectors (combat-safe segment rendering)
    BuildSlots(barFrame, maxSeg, texPath, gs, ge, containerW, containerH)

    -- Background
    local bgc = settings.bgColor or DEFAULTS.bgColor
    barFrame.bg:SetColorTexture(bgc[1], bgc[2], bgc[3], bgc[4] or 0.75)

    -- Ticks
    local tickPath = GetLSMStatusbar(settings.tickTexture or "Blizzard Raid Bar")
    local tickColor = settings.tickColor or DEFAULTS.tickColor
    local tickW = settings.tickWidth or 2
    UpdateBarTicks(barFrame, maxSeg, tickPath, tickColor, tickW, containerW, containerH)

    -- Label (spell name)
    local showLabel = SpellSetting(spellEntry, settings, "showLabel", true)
    if showLabel then
        barFrame.label:Show()
        local labelFontName = spellEntry.labelFont or settings.labelFont or "Friz Quadrata TT"
        local labelFontSize = spellEntry.labelFontSize or settings.labelFontSize or 11
        barFrame.label:SetFont(GetLSMFont(labelFontName), labelFontSize, "OUTLINE")
        barFrame.label:SetText(GetSpellLabel(barFrame.spellID))
        -- Position label
        local anchor = ANCHOR_POINTS[spellEntry.labelAnchor or "LEFT"] or ANCHOR_POINTS.LEFT
        barFrame.label:ClearAllPoints()
        barFrame.label:SetPoint(anchor.point, barFrame.slotsContainer, anchor.relPoint,
            spellEntry.labelOffsetX or anchor.dx,
            spellEntry.labelOffsetY or anchor.dy)
    else
        barFrame.label:Hide()
    end

    -- Count text (numeric stack/charge count)
    local showCount = SpellSetting(spellEntry, settings, "showCount", false)
    if showCount and barFrame.countText then
        barFrame.countText:Show()
        local countFontName = spellEntry.countFont or settings.countFont or "Friz Quadrata TT"
        local countFontSize = spellEntry.countFontSize or settings.countFontSize or 11
        barFrame.countText:SetFont(GetLSMFont(countFontName), countFontSize, "OUTLINE")
        local cAnchor = ANCHOR_POINTS[spellEntry.countAnchor or "RIGHT"] or ANCHOR_POINTS.RIGHT
        barFrame.countText:ClearAllPoints()
        barFrame.countText:SetPoint(cAnchor.point, barFrame.slotsContainer, cAnchor.relPoint,
            spellEntry.countOffsetX or cAnchor.dx,
            spellEntry.countOffsetY or cAnchor.dy)
    elseif barFrame.countText then
        barFrame.countText:Hide()
    end

    -- Spell icon
    if barFrame.spellIconFrame then
        if spellEntry.showIcon then
            local iconSz = spellEntry.iconSize or h
            barFrame.spellIconFrame:SetSize(iconSz, iconSz)
            barFrame.spellIconFrame:ClearAllPoints()
            if spellEntry.iconAnchor == "RIGHT" then
                barFrame.spellIconFrame:SetPoint("LEFT", barFrame, "RIGHT", 2, 0)
            else
                barFrame.spellIconFrame:SetPoint("RIGHT", barFrame, "LEFT", -2, 0)
            end
            -- Refresh texture
            local iconPath = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(barFrame.spellID))
                             or "Interface\\ICONS\\INV_Misc_QuestionMark"
            barFrame.spellIconTex:SetTexture(iconPath)
            barFrame.spellIconFrame:Show()
        else
            barFrame.spellIconFrame:Hide()
        end
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
UpdateBarCounts = function()
    local settings = SegmentBars:GetSettings()
    EnsureDB()
    local _, _, currentKey = GetPlayerClassSpec()
    for idStr, entry in pairs(settings.spells) do
        local spellID = tonumber(idStr)
        if spellID and (not entry.classSpec or entry.classSpec == currentKey) then
            local bar = barFrames[spellID]
            if bar and bar.slots then
                local maxSeg = entry.maxSegments or 3
                local count = GetSpellCount(spellID, entry.trackMode) or 0
                -- count may be a secret number in combat. Secret numbers
                -- work natively with StatusBar:SetValue (C-side, no taint).

                -- Feed the same secret count to every per-slot fill bar + detector.
                -- Each slot has SetMinMaxValues(i-0.5, i): fills only when count >= i.
                -- detectorTex:GetWidth() returns a NON-SECRET number (> 0 = full).
                for i = 1, maxSeg do
                    local slot = bar.slots[i]
                    if slot then
                        slot.fillBar:SetValue(count)
                        if slot.detector then
                            slot.detector:SetValue(count)
                        end
                    end
                end

                -- Update count text — uses SetFormattedText (C-side) to safely
                -- handle secret numbers without taint in combat.
                if bar.countText and bar.countText:IsShown() then
                    bar.countText:SetFormattedText("%d", count)
                end

                -- Also feed the legacy hidden statusBar (for tick positioning etc.)
                bar.statusBar:SetMinMaxValues(0, maxSeg)
                bar.statusBar:SetValue(count)
            end
        end
    end
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

    -- No spells configured â†’ hide
    local hasSpells = false
    for _ in pairs(settings.spells) do hasSpells = true; break end
    if not hasSpells then
        HideAll()
        return
    end

    -- Show standalone bars and group containers for current spec
    -- Respect per-bar hideWhenMounted (fallback to global setting)
    local isMounted = IsPlayerMounted()
    local globalHideMount = settings.hideWhenMounted
    local _, _, currentKey = GetPlayerClassSpec()
    for idStr, entry in pairs(settings.spells) do
        local id = tonumber(idStr)
        if id and (not entry.classSpec or entry.classSpec == currentKey) then
            local bar = barFrames[id]
            if bar then
                local hideMount = entry.hideWhenMounted
                if hideMount == nil then hideMount = globalHideMount end
                if hideMount and isMounted then
                    bar:Hide()
                else
                    bar:Show()
                end
            end
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
    InvalidateTrackedSpellCache()
    EnsureDB()
    LayoutBars()
    CacheAllDurations()
    UpdateBarCounts()
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
-- CDM Catalog Scanner
-- ============================================================
-- Scans EssentialCooldownViewer / UtilityCooldownViewer / BuffIconCooldownViewer children for all available spells.
-- Returns a sorted list of { cooldownID, spellID, name, icon }.
-- Must be called out of combat (frame properties may be tainted).
-- ============================================================

local function ScanCDMCatalog()
    local results = {}
    local seen = {}

    local function ScanViewer(viewer)
        if not viewer then return end
        local container = viewer.viewerFrame or viewer

        for i = 1, select("#", container:GetChildren()) do
            local icon = select(i, container:GetChildren())
            if icon and (icon.Icon or icon.icon) then
                local cdID = tonumber(icon.cooldownID)
                if cdID and not seen[cdID] then
                    seen[cdID] = true
                    local spellID = cdID
                    local spellName, iconTexture

                    -- Resolve via CooldownViewer info
                    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                        if info then
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
    ScanViewer(_G["BuffIconCooldownViewer"])
    ScanViewer(_G["BuffBarCooldownViewer"])

    table.sort(results, function(a, b) return (a.name or "") < (b.name or "") end)
    return results
end

-- Expose for options panel
function SegmentBars:FullRefresh() FullRefresh() end
function SegmentBars:UpdateLocked() UpdateLocked() end
function SegmentBars:ScanCDMCatalog() return ScanCDMCatalog() end

-- ============================================================
-- Events (show/hide dispatch: coalesces rapid events into one update)
-- ============================================================
local eventFrame = CreateFrame("Frame")
local sbDispatch = CreateFrame("Frame")
local sbDispatchNeedsAuraRebuild = false
local sbDispatchNeedsCacheDurations = false
local sbDispatchTimerPending = false

local function RunSegmentDispatch()
    local settings = SegmentBars:GetSettings()
    if not settings or not settings.spells or not next(settings.spells) then return end
    if sbDispatchNeedsAuraRebuild then
        sbDispatchNeedsAuraRebuild = false
        BuildAuraInstanceMap()
        BuildCooldownIDCache()  -- Refresh cache after aura rebuild
    end
    if sbDispatchNeedsCacheDurations then
        sbDispatchNeedsCacheDurations = false
        CacheAllDurations()
    end
    -- SnapshotAllCooldowns uses tonumber(tostring(secretField)) on charge/cooldown
    -- info returned by C_Spell APIs. In 12.0.5 combat, tostring() on a secret value
    -- can throw a taint error that bypasses pcall, silently killing the dispatch and
    -- preventing UpdateBarCounts from ever running (bars freeze).
    -- Snapshot is only needed for GetCleanRemaining (cleanup on PLAYER_REGEN_ENABLED),
    -- not for live stack counting. Skip it entirely during combat.
    if not inCombatFlag then
        pcall(SnapshotAllCooldowns)
    end
    UpdateBarCounts()
    UpdateVisibility()
end

-- Pre-baked callback to avoid closure per C_Timer.After
local function _sb_dispatchCallback()
    sbDispatchTimerPending = false
    RunSegmentDispatch()
end

local function ScheduleSegmentDispatch()
    if sbDispatchTimerPending then return end
    sbDispatchTimerPending = true
    C_Timer.After(0, _sb_dispatchCallback)
end

-- Events registered at PLAYER_LOGIN, gated by enabled state
eventFrame:SetScript("OnEvent", function(self, event, arg1, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        inCombatFlag = UnitAffectingCombat("player")
        C_Timer.After(0.5, function()
            BuildAuraInstanceMap()
            BuildCooldownIDCache()
            FullRefresh()
        end)
        return
    end
    if event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
        UpdateVisibility()
        return
    end
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        InvalidateClassSpecCache()
        C_Timer.After(0.5, function()
            BuildAuraInstanceMap()
            BuildCooldownIDCache()
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
                end
            end
        end
        return
    end
   -- Enter combat: cache durations while values are still clean
    if event == "PLAYER_REGEN_DISABLED" then
        inCombatFlag = true
        pcall(BuildCooldownIDCache)    -- Try to refresh cache; may fail if APIs restricted
        pcall(CacheAllDurations)
        pcall(SnapshotAllCooldowns)
        UpdateBarCounts()  -- uses whatever cache/APIs we can reach
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
        UpdateBarCounts()
        UpdateVisibility()
        return
    end
    -- UNIT_AURA during combat: batch into dispatch instead of running every event
    if event == "UNIT_AURA" and arg1 == "player" then
        ScheduleSegmentDispatch()
        return
    end
    -- Batch frequent events into one dispatch next render frame
    if not InCombatLockdown() then
        sbDispatchNeedsAuraRebuild = true
        sbDispatchNeedsCacheDurations = true
    end
    ScheduleSegmentDispatch()
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
    -- Auto-detect max stacks using C_Spell.GetSpellMaxCumulativeAuraApplications
    -- The API may return a tainted ("secret") number when called from addon code,
    -- so we wrap the entire detection in pcall to avoid taint errors on comparison.
    if not maxSegments and C_Spell and C_Spell.GetSpellMaxCumulativeAuraApplications then
        local ok, result = pcall(function()
            local raw = C_Spell.GetSpellMaxCumulativeAuraApplications(spellID)
            if raw and raw > 0 then return raw end
        end)
        if ok and result then maxSegments = result end
    end
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
-- ============================================================
-- Options Panel

-- Old CreateOptionsPanel removed; options are now handled by Ace3 AceConfig (ui/options/SegmentBarsOptions.lua)
function SegmentBars:CreateOptionsPanel() return nil end

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
