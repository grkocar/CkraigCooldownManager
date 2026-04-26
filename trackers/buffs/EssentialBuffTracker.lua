if not InterfaceOptionsFramePanelContainer then
    InterfaceOptionsFramePanelContainer = UIParent
end
-- Config removed: all configuration is now in the Interface Options panel via the Modern Settings API
-- All dropdowns and color pickers are now handled by the Modern Settings API panel below
-- Modern Settings API panel for Essential Buffs
-- All checkboxes are now handled by the Modern Settings API panel
-- ShowConfig and all custom config UI code removed; all configuration is now in the Interface Options panel
-- ======================================================
-- MyEssentialBuffTracker (Deterministic ordering, Aspect Ratio,
-- Multi-row center layout, Combat-safe skinning, EditMode safe)
-- Target: _G["EssentialCooldownViewer"]
-- ======================================================

MyEssentialBuffTracker = MyEssentialBuffTracker or {}
local _ebt_dirty = false
local _ebt_batchTimerPending = false
local _ebt_throttle = 0.15 -- seconds
local UpdateEssentialBatch

local function IsInCombat() return InCombatLockdown() end

-- Pre-baked callback to avoid closure allocation per C_Timer.After (~6-7x/sec in combat)
local function _ebt_batchTimerCallback()
    _ebt_batchTimerPending = false
    if UpdateEssentialBatch then
        UpdateEssentialBatch()
    end
    if _ebt_dirty and IsInCombat() then
        ScheduleEssentialBatch(false)
    end
end

local function ScheduleEssentialBatch(immediate)
    if _ebt_batchTimerPending then
        return
    end

    _ebt_batchTimerPending = true
    local delay = immediate and 0 or _ebt_throttle
    C_Timer.After(delay, _ebt_batchTimerCallback)
end

local function MarkEssentialDirty(reason)
    _ebt_dirty = true
    if IsInCombat() then
        ScheduleEssentialBatch(false)
    end
end

local _ebt_lastActiveCount_batch = -1

UpdateEssentialBatch = function()
    if not _ebt_dirty then return end
    _ebt_dirty = false
    -- Only update if in combat
    if not IsInCombat() then return end
    local viewer = _G["EssentialCooldownViewer"]
    if not viewer or not viewer:IsShown() then return end
    -- Skip heavy layout when active icon count hasn't changed (cluster mode always runs)
    local pool = viewer.itemFramePool
    if pool then
        local count = pool:GetNumActive()
        local settings = MyEssentialBuffTracker:GetSettings()
        local forceLayout = settings and settings.multiClusterMode
        if count == _ebt_lastActiveCount_batch and not forceLayout then return end
        _ebt_lastActiveCount_batch = count
    end
    if MyEssentialIconViewers and MyEssentialIconViewers.ApplyViewerLayout then
        pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
    end
end

-- Hook combat state events to manage batch frame lifecycle
local function SetupEssentialEventHooks()
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("PLAYER_REGEN_DISABLED")
    ef:RegisterEvent("PLAYER_REGEN_ENABLED")
    ef:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_REGEN_DISABLED" then
            if _ebt_dirty then ScheduleEssentialBatch(true) end
        elseif event == "PLAYER_REGEN_ENABLED" then
            _ebt_dirty = false
        end
    end)
end

SetupEssentialEventHooks()
-- Allows other modules (e.g. TrinketRacials, PowerPotionSuccessIcon) to inject frames into Essential layout
-- ---------------------------
MyEssentialBuffTracker._externalIcons = MyEssentialBuffTracker._externalIcons or {}

function MyEssentialBuffTracker:RegisterExternalIcon(frame)
    if not frame then return end
    -- Ensure .Icon ref exists so layout recognizes frame
    if not frame.Icon and not frame.icon then
        for _, region in ipairs({ frame:GetRegions() }) do
            if region and region:IsObjectType("Texture") and region:GetDrawLayer() == "ARTWORK" then
                frame.Icon = region
                break
            end
        end
    end
    self._externalIcons[frame] = true
    self:RefreshEssentialLayout()
end

function MyEssentialBuffTracker:UnregisterExternalIcon(frame)
    if not frame then return end
    self._externalIcons[frame] = nil
    self:RefreshEssentialLayout()
end

function MyEssentialBuffTracker:RefreshEssentialLayout()
    local viewer = _G["EssentialCooldownViewer"]
    if viewer and viewer:IsShown() and MyEssentialIconViewers and MyEssentialIconViewers.ApplyViewerLayout then
        -- Reset ticker child count so the next tick doesn't skip the rescan
        if viewer._MyEssentialBuffTrackerTickerFrame then
            viewer._MyEssentialBuffTrackerTickerFrame._lastChildCount = 0
        end
        pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
    end
end

-- Cache frequently used global functions as locals for performance
local tonumber = tonumber
local tostring = tostring
local ipairs = ipairs
local pairs = pairs

-- Initialize database reference
function MyEssentialBuffTracker:InitializeDB()
    if CkraigProfileManager and CkraigProfileManager.db then
        self.db = CkraigProfileManager.db
        return true
    else
        -- Fallback
        MyEssentialBuffTrackerDB = MyEssentialBuffTrackerDB or {}
        self.db = {
            profile = { essentialBuffs = MyEssentialBuffTrackerDB },
            char = {},
            global = {},
            faction = {},
            realm = {},
            factionrealm = {},
            profiles = {},
            keys = nil,
            sv = nil,
            defaults = nil,
            parent = nil
        }
        return false
    end
end

-- Get settings from profile
function MyEssentialBuffTracker:GetSettings()
    if not self.db then
        self:InitializeDB()
    end
    return self.db.profile.essentialBuffs
end

local UpdateCooldownManagerVisibility  -- forward declaration

function MyEssentialBuffTracker:OnProfileChanged()
    C_Timer.After(0.1, function()
        UpdateCooldownManagerVisibility()
    end)
end

-- Initialize on load or when ProfileManager is ready
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    -- Try to initialize with ProfileManager
    if not MyEssentialBuffTracker:InitializeDB() then
        -- If ProfileManager isn't ready yet, wait a bit more
        C_Timer.After(0.5, function()
            MyEssentialBuffTracker:InitializeDB()
        end)
    end
end)
local strsplit = strsplit
local strfind = strfind
local strmatch = strmatch
local strsub = strsub
local strupper = strupper
local strlower = strlower
local strlen = strlen
local table_wipe = table.wipe
local math_floor = math.floor
local math_ceil = math.ceil
local math_max = math.max
local math_min = math.min
local GetTime = GetTime
local IsMounted = IsMounted
local GetSpellCooldown = GetSpellCooldown

-- Hide Cooldown Manager when mounted

-- Mount hide/show option
local function IsPlayerMounted()
    return IsMounted and IsMounted()
end

-- Reusable combat-deferred frame (avoids creating a new frame each time)
local ebtCombatDeferFrame
UpdateCooldownManagerVisibility = function()
    local viewer = _G["EssentialCooldownViewer"]
    if viewer then
        if not (CkraigProfileManager and CkraigProfileManager.db) then return end
        local settings = MyEssentialBuffTracker:GetSettings()
        if settings.enabled == false then
            viewer:Hide()
            return
        end
        local shouldHide = settings.hideWhenMounted and IsPlayerMounted()
        if shouldHide then
            viewer:Hide()
        elseif InCombatLockdown() then
            if not ebtCombatDeferFrame then
                ebtCombatDeferFrame = CreateFrame("Frame")
                ebtCombatDeferFrame:SetScript("OnEvent", function(self)
                    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
                    local v = _G["EssentialCooldownViewer"]
                    if v then v:Show() end
                end)
            end
            ebtCombatDeferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        else
            viewer:Show()
        end
    end
end

local mountEventFrame = CreateFrame("Frame")
mountEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
mountEventFrame:SetScript("OnEvent", function(self, event)
    UpdateCooldownManagerVisibility()
    -- On initial login, only listen for mount changes when hideWhenMounted is on
    if event == "PLAYER_ENTERING_WORLD" then
        local s = MyEssentialBuffTracker:GetSettings()
        if s and s.hideWhenMounted then
            self:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
        end
    end
end)

local DEFAULTS = {
    columns         = 9,
    hSpacing        = 0,
    vSpacing        = 0,
    growUp          = true,
    locked          = true,
    iconSize        = 36,
    aspectRatio     = "1:1",
    aspectRatioCrop = nil,
    spacing         = 0, 
    rowLimit        = 9,
    rowGrowDirection= "down",

    -- New settings
    iconCornerRadius = 1,
    cooldownTextSize = 16,
    cooldownTextPosition = "CENTER",
    cooldownTextX = 0,
    cooldownTextY = 0,
    chargeTextSize = 14,
    chargeTextPosition = "BOTTOMRIGHT",
    chargeTextX = 0,
    chargeTextY = 0,

    enabled = true,
    showCooldownText = true,
    showChargeText = true,
    hideWhenMounted = false,

    -- Assisted Combat Highlight (mirrors Blizzard's blue rotation helper glow)
    assistedCombatHighlight = false,

    -- Static Grid Mode
    staticGridMode = false,
    gridRows = 4,
    gridColumns = 4,
    gridSlotMap = {},

    -- Per-row icon sizes (optional override, otherwise uses iconSize)
    rowSizes = {},
    -- Per-row vertical offsets (pixels to push each row down)
    rowOffsets = {},

    -- Border
    borderSize = 1,
    borderColor = {0, 0, 0, 1},

    -- Per-spell glows
    spellGlows = {},
    -- Per-spell sounds
    spellSounds = {},

    -- Cluster mode
    multiClusterMode = false,
    clusterCount = 5,
    clusterUnlocked = false,
    clusterFlow = "horizontal",
    clusterFlows = {},
    clusterVerticalGrows = {},
    clusterVerticalPins = {},
    clusterIconSizes = {},
    clusterSampleDisplayModes = {},
    clusterAlwaysShowSpells = {},
    clusterAssignments = {},
    clusterPositions = {},
    clusterManualOrders = {},
    clusterCenterIcons = true,
    clusterDuplicates = {},
    iconDragUnlock = false,
    clusterFreePositionModes = {},
    clusterIconFreePositions = {},
    -- Per-spell aura→cooldown override (show actual spell CD instead of buff timer)
    cooldownOverrideSpells = {},
}
    local settings = MyEssentialBuffTracker:GetSettings()
    if settings.borderSize == nil then settings.borderSize = DEFAULTS.borderSize end
    settings.borderColor = settings.borderColor or DEFAULTS.borderColor

local LCG = LibStub("LibCustomGlow-1.0", true)
local LibEditMode = LibStub("LibEditMode", true)
local LSM = LibStub("LibSharedMedia-3.0", true)

-- Reusable glow color array (avoids table allocation per icon per dispatch)
local ebtGlowColor = { 1, 1, 1, 1 }
local ebtProcOpts = { color = ebtGlowColor, key = "ebtGlow" }
local ebtEnabledSoundLookup = {}
local ebtSoundCfgSource = nil
local ebtSoundCfgRevision = -1
local ebtSoundActivePrevByKey = {}
local ebtSoundPrevCfgByKey = {}
local ebtSoundPrevModeByKey = {}
local ebtSoundReadyPrevByKey = {}
local ebtSoundLastPlayByKey = {}
local ebtSoundMinInterval = 0.75
-- Pre-allocated sound dispatch tables (avoid per-tick GC)
local _ebt_activeSoundCfgByKey = {}
local _ebt_activeSoundModeByKey = {}
local _ebt_activeSoundReadyByKey = {}

local function GetSpellSoundsRevision_EBT(settings)
    return tonumber(settings and settings.spellSoundsRevision) or 0
end

-- Pooled tables for ApplyViewerLayout (avoids GC churn on every cooldown/aura event)
local _ebt_icons = {}
local _ebt_shownIcons = {}
local _ebt_rows = {}
-- _ebt_iconSortComparator defined below (after ebtIconMeta)

-- Skin version system: skip re-skinning when settings haven't changed
local _ebt_skinVersion = 1
local _ebt_lastSkinFingerprint = ""

local function GetEBTSkinFingerprint(settings)
    return string.format("%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s",
        settings.iconSize or 0,
        settings.iconCornerRadius or 0,
        settings.aspectRatioCrop or 0,
        settings.cooldownTextSize or 0,
        settings.cooldownTextPosition or "CENTER",
        settings.cooldownTextX or 0,
        settings.cooldownTextY or 0,
        settings.chargeTextSize or 0,
        settings.chargeTextPosition or "BOTTOMRIGHT",
        settings.chargeTextX or 0,
        settings.chargeTextY or 0,
        settings.showCooldownText and 1 or 0,
        settings.showChargeText and 1 or 0,
        settings.borderSize or 0)
end

local function InvalidateEBTSkin()
    _ebt_skinVersion = _ebt_skinVersion + 1
    _ebt_lastSkinFingerprint = ""
end

-- Side tables: avoid writing addon fields onto Blizzard secure frames (prevents taint)
local ebtIconMeta = setmetatable({}, { __mode = "k" })   -- icon frame -> { skinned, skinPending, lastX, lastY, lastSizeW, lastSizeH, creationOrder, cdHooked, isOnCD, cachedKey, glowing, glowType, pixelBorders }
local ebtViewerMeta = setmetatable({}, { __mode = "k" }) -- viewer frame -> { lastNumRows, iconCount }
local ebtNeutralizedAtlases = setmetatable({}, { __mode = "k" }) -- texture -> true (atlas hook applied)
local ebtBackdropPending = setmetatable({}, { __mode = "k" }) -- frame -> true (backdrop deferred)

-- Hoisted sort comparator for ApplyViewerLayout (avoids closure allocation per call)
local function _ebt_iconSortComparator(a, b)
    local aOrder = a.layoutIndex or a:GetID() or (ebtIconMeta[a] and ebtIconMeta[a].creationOrder) or 0
    local bOrder = b.layoutIndex or b:GetID() or (ebtIconMeta[b] and ebtIconMeta[b].creationOrder) or 0
    return aOrder < bOrder
end

local function GetIconMeta(icon)
    local m = ebtIconMeta[icon]
    if not m then m = {} ebtIconMeta[icon] = m end
    return m
end

local function GetViewerMeta(viewer)
    local m = ebtViewerMeta[viewer]
    if not m then m = {} ebtViewerMeta[viewer] = m end
    return m
end

local function StopGlow_EBT(icon)
    local m = ebtIconMeta[icon]
    local gt = m and m.glowType
    if gt == "autocast" then LCG.AutoCastGlow_Stop(icon, "ebtGlow")
    elseif gt == "button" then LCG.ButtonGlow_Stop(icon)
    elseif gt == "proc" then LCG.ProcGlow_Stop(icon, "ebtGlow")
    else LCG.PixelGlow_Stop(icon, "ebtGlow") end
end

local function RebuildEnabledSoundLookup_EBT(spellSounds)
    for k in pairs(ebtEnabledSoundLookup) do ebtEnabledSoundLookup[k] = nil end
    ebtSoundCfgSource = spellSounds
    ebtSoundCfgRevision = tonumber((MyEssentialBuffTracker and MyEssentialBuffTracker.GetSettings and GetSpellSoundsRevision_EBT(MyEssentialBuffTracker:GetSettings())) or 0) or 0

    if type(spellSounds) ~= "table" then
        return false
    end

    local hasEnabled = false
    for skey, cfg in pairs(spellSounds) do
        if type(cfg) == "table" and cfg.enabled then
            ebtEnabledSoundLookup[tostring(skey)] = cfg
            hasEnabled = true
        end
    end
    return hasEnabled
end

local function ResolveSoundPath_EBT(soundKey)
    if not soundKey or soundKey == "" then return nil end
    if LSM and LSM.Fetch then
        local ok, path = pcall(LSM.Fetch, LSM, "sound", soundKey, true)
        if ok and path and path ~= "" then
            return path
        end
    end
    return soundKey
end

local function TrimString_EBT(s)
    if type(s) ~= "string" then return "" end
    return s:match("^%s*(.-)%s*$") or ""
end

local function ResolveSpellName_EBT(spellKey)
    local spellID = tonumber(spellKey)
    if spellID and C_Spell and C_Spell.GetSpellName then
        local name = C_Spell.GetSpellName(spellID)
        if name and name ~= "" then
            return name
        end
    end
    return tostring(spellKey or "Spell")
end

local function ResolveTtsText_EBT(spellKey, cfg)
    local text = TrimString_EBT(cfg and cfg.ttsText)
    if text ~= "" then
        return text
    end
    return ResolveSpellName_EBT(spellKey)
end

local function SpeakText_EBT(text)
    if not text or text == "" then return false end
    if not (C_VoiceChat and C_VoiceChat.SpeakText and C_TTSSettings and C_TTSSettings.GetVoiceOptionID and Enum and Enum.TtsVoiceType) then
        return false
    end

    local voiceID = C_TTSSettings.GetVoiceOptionID(Enum.TtsVoiceType.Standard)
    if not voiceID then return false end

    local rate = (C_TTSSettings.GetSpeechRate and C_TTSSettings.GetSpeechRate()) or 0
    local volume = (C_TTSSettings.GetSpeechVolume and C_TTSSettings.GetSpeechVolume()) or 100
    local ok = pcall(C_VoiceChat.SpeakText, voiceID, text, rate, volume, false)
    return ok and true or false
end

local function PlaySpellSound_EBT(spellKey, cfg)
    if not cfg then return end
    local keyStr = tostring(spellKey or "")
    if keyStr == "" then return end

    local now = GetTime and GetTime() or 0
    local last = ebtSoundLastPlayByKey[keyStr]
    if last and (now - last) < ebtSoundMinInterval then
        return
    end

    ebtSoundLastPlayByKey[keyStr] = now

    local output = tostring(cfg.output or "sound")
    local playSound = (output == "sound" or output == "both")
    local playTts = (output == "tts" or output == "both")
    local didPlay = false

    if playSound then
        local soundPath = ResolveSoundPath_EBT(cfg.sound)
        if soundPath then
            local ok = pcall(PlaySoundFile, soundPath, "Master")
            didPlay = didPlay or (ok and true or false)
        end
    end

    if playTts then
        local ttsText = ResolveTtsText_EBT(keyStr, cfg)
        didPlay = SpeakText_EBT(ttsText) or didPlay
    elseif playSound and not didPlay then
        -- Fallback for missing/invalid SharedMedia sounds.
        didPlay = SpeakText_EBT(ResolveTtsText_EBT(keyStr, cfg)) or didPlay
    end

    if not didPlay then
        ebtSoundLastPlayByKey[keyStr] = nil
    end
end

local function IsReadyForSound_EBT(icon, spellKey)
    local spellID = tonumber(spellKey)
    -- Use clean booleans from C_Spell.GetSpellCooldown.
    -- NOTE: icon.isOnActualCooldown is a SECRET BOOLEAN — ~= nil comparison triggers taint.
    if spellID and C_Spell and C_Spell.GetSpellCooldown then
        -- Resolve talent override (e.g., Berserk → Incarnation)
        local resolved = spellID
        if FindSpellOverrideByID then
            resolved = FindSpellOverrideByID(spellID) or spellID
        end
        local info = C_Spell.GetSpellCooldown(resolved)
        if info then
            -- Treat GCD as ready to avoid rapid cooldown/ready flapping.
            if info.isOnGCD then
                return true
            end
            if info.isActive == true then
                return false
            end
            return true
        end
    end
    return IsIconReady(icon) and true or false
end

local function ResetSoundState_EBT(resetLastPlayed)
    for k in pairs(ebtSoundActivePrevByKey) do ebtSoundActivePrevByKey[k] = nil end
    for k in pairs(ebtSoundPrevCfgByKey) do ebtSoundPrevCfgByKey[k] = nil end
    for k in pairs(ebtSoundPrevModeByKey) do ebtSoundPrevModeByKey[k] = nil end
    for k in pairs(ebtSoundReadyPrevByKey) do ebtSoundReadyPrevByKey[k] = nil end
    if resetLastPlayed then
        for k in pairs(ebtSoundLastPlayByKey) do ebtSoundLastPlayByKey[k] = nil end
    end
end

local POSITION_PRESETS = {
    ["CENTER"] = {x = 0, y = 0, point = "CENTER"},
    ["TOP"] = {x = 0, y = 0, point = "TOP"},
    ["BOTTOM"] = {x = 0, y = 0, point = "BOTTOM"},
    ["LEFT"] = {x = 0, y = 0, point = "LEFT"},
    ["RIGHT"] = {x = 0, y = 0, point = "RIGHT"},
    ["TOPLEFT"] = {x = 0, y = 0, point = "TOPLEFT"},
    ["TOPRIGHT"] = {x = 0, y = 0, point = "TOPRIGHT"},
    ["BOTTOMLEFT"] = {x = 0, y = 0, point = "BOTTOMLEFT"},
    ["BOTTOMRIGHT"] = {x = 0, y = 0, point = "BOTTOMRIGHT"},
}

-- ---------------------------
-- Utilities
-- ---------------------------
local function EnsureDB()
    local settings = MyEssentialBuffTracker:GetSettings()
    -- Use == nil checks for all settings to preserve user-set values including 0
    if settings.columns == nil then settings.columns = DEFAULTS.columns end
    if settings.hSpacing == nil then settings.hSpacing = DEFAULTS.hSpacing end
    if settings.vSpacing == nil then settings.vSpacing = DEFAULTS.vSpacing end
    if settings.growUp == nil then settings.growUp = DEFAULTS.growUp end
    if settings.locked == nil then settings.locked = DEFAULTS.locked end
    if settings.iconSize == nil then settings.iconSize = DEFAULTS.iconSize end
    if settings.aspectRatio == nil then settings.aspectRatio = DEFAULTS.aspectRatio end
    if settings.aspectRatioCrop == nil then settings.aspectRatioCrop = DEFAULTS.aspectRatioCrop end
    if settings.spacing == nil then settings.spacing = DEFAULTS.spacing end
    if settings.rowLimit == nil then settings.rowLimit = DEFAULTS.rowLimit end
    if settings.rowGrowDirection == nil then settings.rowGrowDirection = DEFAULTS.rowGrowDirection end

    if settings.iconCornerRadius == nil then settings.iconCornerRadius = DEFAULTS.iconCornerRadius end
    if settings.cooldownTextSize == nil then settings.cooldownTextSize = DEFAULTS.cooldownTextSize end
    if settings.cooldownTextPosition == nil then settings.cooldownTextPosition = DEFAULTS.cooldownTextPosition end
    if settings.cooldownTextX == nil then settings.cooldownTextX = DEFAULTS.cooldownTextX end
    if settings.cooldownTextY == nil then settings.cooldownTextY = DEFAULTS.cooldownTextY end
    if settings.chargeTextSize == nil then settings.chargeTextSize = DEFAULTS.chargeTextSize end
    if settings.chargeTextPosition == nil then settings.chargeTextPosition = DEFAULTS.chargeTextPosition end
    if settings.chargeTextX == nil then settings.chargeTextX = DEFAULTS.chargeTextX end
    if settings.chargeTextY == nil then settings.chargeTextY = DEFAULTS.chargeTextY end

    if settings.enabled == nil then settings.enabled = DEFAULTS.enabled end
    if settings.showCooldownText == nil then settings.showCooldownText = DEFAULTS.showCooldownText end
    if settings.showChargeText == nil then settings.showChargeText = DEFAULTS.showChargeText end
    if settings.hideWhenMounted == nil then settings.hideWhenMounted = DEFAULTS.hideWhenMounted end
    if settings.assistedCombatHighlight == nil then settings.assistedCombatHighlight = DEFAULTS.assistedCombatHighlight end

    if settings.staticGridMode == nil then settings.staticGridMode = DEFAULTS.staticGridMode end
    if settings.gridRows == nil then settings.gridRows = DEFAULTS.gridRows end
    if settings.gridColumns == nil then settings.gridColumns = DEFAULTS.gridColumns end
    if settings.gridSlotMap == nil then settings.gridSlotMap = {} end

    -- Per-row sizes
    if settings.rowSizes == nil then settings.rowSizes = {} end
    if settings.rowOffsets == nil then settings.rowOffsets = {} end

    -- Per-spell glows
    if settings.spellGlows == nil then settings.spellGlows = {} end
    if settings.spellSounds == nil then settings.spellSounds = {} end
    if settings.spellSoundsRevision == nil then settings.spellSoundsRevision = 0 end

    for k, v in pairs(settings.spellSounds) do
        if type(v) ~= "table" then
            settings.spellSounds[k] = { enabled = (v == true), sound = "", output = "sound", ttsText = "", mode = "ready" }
        else
            if v.mode == nil or v.mode == "" then
                v.mode = "ready"
            end
            if v.mode == "show" then
                v.mode = "ready"
            elseif v.mode == "expire" then
                v.mode = "cooldown"
            end
            if v.mode ~= "ready" and v.mode ~= "cooldown" and v.mode ~= "both" then
                v.mode = "ready"
            end
            if v.output == nil or v.output == "" then
                v.output = "sound"
            end
            if v.output ~= "sound" and v.output ~= "tts" and v.output ~= "both" then
                v.output = "sound"
            end
            if type(v.sound) ~= "string" then
                v.sound = ""
            end
            if type(v.ttsText) ~= "string" then
                v.ttsText = ""
            end
        end
    end

    -- Cluster mode
    if settings.multiClusterMode == nil then settings.multiClusterMode = DEFAULTS.multiClusterMode end
    if settings.clusterCount == nil then settings.clusterCount = DEFAULTS.clusterCount end
    if settings.clusterUnlocked == nil then settings.clusterUnlocked = DEFAULTS.clusterUnlocked end
    if settings.clusterFlow == nil then settings.clusterFlow = DEFAULTS.clusterFlow end
    if settings.clusterFlows == nil then settings.clusterFlows = {} end
    if settings.clusterVerticalGrows == nil then settings.clusterVerticalGrows = {} end
    if settings.clusterVerticalPins == nil then settings.clusterVerticalPins = {} end
    if settings.clusterIconSizes == nil then settings.clusterIconSizes = {} end
    if settings.clusterSampleDisplayModes == nil then settings.clusterSampleDisplayModes = {} end
    if settings.clusterAlwaysShowSpells == nil then settings.clusterAlwaysShowSpells = {} end
    if settings.clusterAssignments == nil then settings.clusterAssignments = {} end
    if settings.clusterPositions == nil then settings.clusterPositions = {} end
    if settings.clusterManualOrders == nil then settings.clusterManualOrders = {} end
    if settings.clusterCenterIcons == nil then settings.clusterCenterIcons = DEFAULTS.clusterCenterIcons end
    if settings.clusterDuplicates == nil then settings.clusterDuplicates = {} end
    if settings.iconDragUnlock == nil then settings.iconDragUnlock = false end
    if settings.clusterFreePositionModes == nil then settings.clusterFreePositionModes = {} end
    if settings.clusterIconFreePositions == nil then settings.clusterIconFreePositions = {} end
    if settings.cooldownOverrideSpells == nil then settings.cooldownOverrideSpells = {} end
end

-- ---------------------------
-- Icon key identification for glow system
-- Uses ONLY direct frame fields (clean, never tainted) to avoid "table index is secret".
-- Resolves cooldownID â†’ spellID through Blizzard's C_CooldownViewer API.
-- ---------------------------
local function GetEssentialIconKey(icon)
    if not icon then return nil end

    -- 1. Try direct .cooldownID field â†’ resolve to spellID via C_CooldownViewer
    local cdID = icon.cooldownID
    if cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
        if ok and info and info.spellID then
            return info.spellID
        end
    end

    -- 2. Direct .spellID field (some frames set this directly)
    if icon.spellID then return icon.spellID end

    -- 3. Direct .auraInstanceID â†’ resolve to spellId via C_UnitAuras
    local auraID = icon.auraInstanceID
    if auraID and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
        local ok, data = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", auraID)
        if ok and data and data.spellId then
            return data.spellId
        end
    end

    -- 4. Fall back to cooldownID itself (may differ from spellID but still clean)
    if cdID then return cdID end

    -- 5. Addon-set creation order (from side table)
    local m = ebtIconMeta[icon]
    if m and m.creationOrder then return m.creationOrder end

    return nil
end

local KnownEssentialItemsByKey = {}

local function CollectEssentialDisplayedItems(viewer)
    local items = {}
    if not viewer then return items end
    -- Clear stale cache
    wipe(KnownEssentialItemsByKey)

    -- Use itemFramePool if available (zero-allocation)
    local pool = viewer.itemFramePool
    if not pool then return items end

    local seen = {}
    for icon in pool:EnumerateActive() do
        if icon and (icon.Icon or icon.icon) and icon:IsShown() then
            -- Resolve spell ID through clean direct fields only
            local spellID = nil
            local cdID = icon.cooldownID
            if cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
                if ok and info and info.spellID then spellID = info.spellID end
            end
            if not spellID then spellID = icon.spellID end
            if not spellID and icon.auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
                local ok, data = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", icon.auraInstanceID)
                if ok and data and data.spellId then spellID = data.spellId end
            end
            if spellID and not seen[spellID] then
                seen[spellID] = true
                local name, iconTex
                if C_Spell and C_Spell.GetSpellName then
                    name = C_Spell.GetSpellName(spellID)
                end
                if C_Spell and C_Spell.GetSpellTexture then
                    iconTex = C_Spell.GetSpellTexture(spellID)
                end
                if not iconTex then
                    local childIcon = icon.Icon or icon.icon
                    if childIcon and childIcon.GetTexture then
                        iconTex = childIcon:GetTexture()
                    end
                end
                if name then
                    table.insert(items, { key = spellID, name = name, icon = iconTex })
                    KnownEssentialItemsByKey[spellID] = items[#items]
                end
            end
        end
    end
    return items
end

-- Expose for options panels
function MyEssentialBuffTracker:GetDisplayedItems()
    local viewer = _G["EssentialCooldownViewer"]
    if not viewer then return {} end
    local ok, items = pcall(CollectEssentialDisplayedItems, viewer)
    if ok and type(items) == "table" then return items end
    return {}
end

_G.CCM_GetEssentialSpellList = function()
    if MyEssentialBuffTracker and MyEssentialBuffTracker.GetDisplayedItems then
        return MyEssentialBuffTracker:GetDisplayedItems()
    end
    return {}
end

-- Hook icon's Cooldown widget to track cooldown state without reading tainted values.
-- SetCooldown = on cooldown (Blizzard only calls this for real CDs via CooldownFrame_Set)
-- Clear = cooldown cleared (CooldownFrame_Set calls Clear for 0-duration)
-- OnCooldownDone = cooldown animation finished
--
-- Cooldown Override: for spells in cooldownOverrideSpells, replace Blizzard's
-- aura/buff timer with the actual spell cooldown from C_Spell.GetSpellCooldownDuration.
local _ebt_cdOverrideGuard = {}   -- cd widget -> true while we're calling Set inside a hook
local _ebt_alertHooked = {}       -- icon -> true when SpellActivationAlert suppression is installed
local IsSpellStillOnCooldown      -- forward declaration (defined after TryCooldownOverride)

-- Fast cached key lookup: avoids pcall on every hook invocation.
-- Uses GetIconMeta for storage so it participates in the existing weak-key table.
local function GetCachedEssentialIconKey(icon)
    local m = GetIconMeta(icon)
    local cdID = icon.cooldownID
    if cdID == m._cdOverrideCachedCdID then
        return m._cdOverrideKey
    end
    local key = GetEssentialIconKey(icon)
    m._cdOverrideCachedCdID = cdID
    m._cdOverrideKey = key
    -- Invalidate the enable.d cache so it's re-evaluated
    m._cdOverrideEnabled = nil
    return key
end

-- Check whether icon is a cooldown-override spell right now
local function IsCDOverrideActive(icon)
    -- Fast path: use cache if cooldownID hasn't changed
    local m = GetIconMeta(icon)
    if icon.cooldownID == m._cdOverrideCachedCdID and m._cdOverrideEnabled ~= nil then
        return m._cdOverrideEnabled
    end
    local settings = MyEssentialBuffTracker:GetSettings()
    if not settings or not settings.cooldownOverrideSpells then
        m._cdOverrideEnabled = false
        return false
    end
    local key = GetCachedEssentialIconKey(icon)
    local result = key and settings.cooldownOverrideSpells[tostring(key)] == true or false
    m._cdOverrideEnabled = result
    return result
end

-- Hide Blizzard's built-in aura glow when showing actual cooldown
local function SuppressBlizzardAuraGlow(icon)
    -- SpellActivationAlert (the spinning proc glow overlay)
    local alert = icon.SpellActivationAlert
    if alert then
        alert:Hide()
        if alert.ProcStartFlipbook then alert.ProcStartFlipbook:Hide() end
        if alert.ProcLoopFlipbook then alert.ProcLoopFlipbook:Hide() end
        if alert.ProcAltGlow then alert.ProcAltGlow:Hide() end
    end
    -- Also use the manager API if available
    if ActionButtonSpellAlertManager and ActionButtonSpellAlertManager.HideAlert then
        pcall(ActionButtonSpellAlertManager.HideAlert, ActionButtonSpellAlertManager, icon)
    end
    -- CooldownFlash (the ready-flash at the end of the buff timer)
    local flash = icon.CooldownFlash
    if flash then
        flash:Hide()
        if flash.FlashAnim then flash.FlashAnim:Stop() end
    end
    -- Desaturate this specific icon only if its real cooldown is running (not GCD)
    local iconKey = GetCachedEssentialIconKey(icon)
    if iconKey and IsSpellStillOnCooldown(iconKey) then
        local iconTex = icon.Icon or icon.icon
        if iconTex and iconTex.SetDesaturated then
            iconTex:SetDesaturated(true)
        end
    end
end

-- Re-saturate a single icon when its cooldown override ends
local function RestoreIconSaturation(icon)
    local iconTex = icon.Icon or icon.icon
    if iconTex and iconTex.SetDesaturated then
        iconTex:SetDesaturated(false)
    end
end

-- Install one-time hooks on the icon so Blizzard's alert is auto-suppressed
local function HookAlertSuppression(icon)
    if _ebt_alertHooked[icon] then return end
    _ebt_alertHooked[icon] = true

    -- Hook SpellActivationAlert:Show so we hide it immediately for override spells
    local alert = icon.SpellActivationAlert
    if alert and alert.Show then
        hooksecurefunc(alert, "Show", function(self)
            if IsCDOverrideActive(icon) then
                self:Hide()
            end
        end)
    end
    -- Hook CooldownFlash:Show as well
    local flash = icon.CooldownFlash
    if flash and flash.Show then
        hooksecurefunc(flash, "Show", function(self)
            if IsCDOverrideActive(icon) then
                self:Hide()
                if self.FlashAnim then self.FlashAnim:Stop() end
            end
        end)
    end
end

local function TryCooldownOverride(icon, cd)
    if _ebt_cdOverrideGuard[cd] then return end
    local settings = MyEssentialBuffTracker:GetSettings()
    if not settings or not settings.cooldownOverrideSpells then return end
    local key = GetCachedEssentialIconKey(icon)
    if not key then return end
    local keyStr = tostring(key)
    local m = GetIconMeta(icon)
    if not settings.cooldownOverrideSpells[keyStr] then
        m._cdOverrideEnabled = false
        return
    end
    m._cdOverrideEnabled = true

    -- Resolve talent override (e.g., Berserk 50334 → Incarnation 102558)
    -- The CDM icon key is the BASE spellID, but the actual spell in use may be
    -- a talent override.  GetSpellCooldownDuration needs the active spell ID.
    local resolvedKey = key
    if FindSpellOverrideByID then
        resolvedKey = FindSpellOverrideByID(key) or key
    end

    -- 12.0.5+: Use clean booleans for GCD gating, duration object for display.
    -- NOTE: cdInfo.startTime/.duration are secret numbers (arithmetic forbidden).
    --       cdInfo.isActive may be false during an active buff even though the
    --       spell IS on recovery — so do NOT gate on isActive. Let
    --       GetSpellCooldownDuration decide (returns nil when truly no CD).
    local CCM = _G.CkraigCooldownManager
    if CCM and CCM.Is1205 then
        local cdInfo = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(resolvedKey)
        -- Only skip GCD-only (isOnGCD is a clean boolean)
        if cdInfo and cdInfo.isOnGCD then return end
        local durObj = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(resolvedKey)
        if not durObj then return end
        _ebt_cdOverrideGuard[cd] = true
        if cd.SetUseAuraDisplayTime then cd:SetUseAuraDisplayTime(false) end
        cd:SetCooldownFromDurationObject(durObj)
        if cd.SetDrawSwipe then cd:SetDrawSwipe(true) end
        if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.8) end
        _ebt_cdOverrideGuard[cd] = nil
        SuppressBlizzardAuraGlow(icon)
        return
    end

    -- Pre-12.0.5: Use duration object (handles secret numbers C-side)
    if not (C_Spell and C_Spell.GetSpellCooldownDuration) then return end
    local durObj = C_Spell.GetSpellCooldownDuration(resolvedKey)
    if not durObj then return end
    _ebt_cdOverrideGuard[cd] = true
    -- Reset aura display mode so Blizzard doesn't color the swipe as a buff
    if cd.SetUseAuraDisplayTime then
        cd:SetUseAuraDisplayTime(false)
    end
    cd:SetCooldownFromDurationObject(durObj)
    -- Force standard dark swipe color instead of the green buff swipe
    if cd.SetSwipeColor then
        cd:SetSwipeColor(0, 0, 0, 0.8)
    end
    _ebt_cdOverrideGuard[cd] = nil
    -- Kill Blizzard's aura glow / flash since we're showing the real CD
    SuppressBlizzardAuraGlow(icon)
end

-- Returns true if the spell is still on actual cooldown (not GCD).
-- NOTE: On 12.0.5, icon.isOnActualCooldown is a SECRET BOOLEAN — cannot use == or ~= comparison.
-- Use Lua truthiness (if value then) which does NOT trigger taint.
-- cdInfo.isActive and cdInfo.isOnGCD from C_Spell.GetSpellCooldown ARE clean booleans.
local _ebt_is1205 = nil -- lazy-init
IsSpellStillOnCooldown = function(spellID)
    if _ebt_is1205 == nil then
        _ebt_is1205 = _G.CkraigCooldownManager and _G.CkraigCooldownManager.Is1205 or false
    end
    -- Resolve talent override (e.g., Berserk → Incarnation)
    local resolved = spellID
    if FindSpellOverrideByID then
        resolved = FindSpellOverrideByID(spellID) or spellID
    end
    -- Use clean booleans from C_Spell.GetSpellCooldown (isActive / isOnGCD are NOT secret)
    if not (C_Spell and C_Spell.GetSpellCooldown) then return false end
    local cdInfo = C_Spell.GetSpellCooldown(resolved)
    if not cdInfo then return false end
    if cdInfo.isOnGCD then return false end
    return cdInfo.isActive == true
end

local function HookCooldownTracking(icon)
    local m = GetIconMeta(icon)
    if m.cdHooked then return end
    local cd = icon.Cooldown
    if not cd then return end
    m.cdHooked = true
    m.isOnCD = false
    -- Install alert suppression hooks for CD override spells
    HookAlertSuppression(icon)
    -- Hook SetSwipeColor so Blizzard can't re-apply the green buff swipe on override spells
    if cd.SetSwipeColor then
        hooksecurefunc(cd, "SetSwipeColor", function(self, r, g, b, a)
            if _ebt_cdOverrideGuard[cd] then return end
            if IsCDOverrideActive(icon) then
                -- If Blizzard sets anything other than our dark swipe, force it back
                if r ~= 0 or g ~= 0 or b ~= 0 then
                    _ebt_cdOverrideGuard[cd] = true
                    self:SetSwipeColor(0, 0, 0, 0.8)
                    _ebt_cdOverrideGuard[cd] = nil
                end
            end
        end)
    end
    -- Hook RefreshIconDesaturation (Lua mixin method, per-object safe) to keep
    -- override icons desaturated after Blizzard's refresh re-saturates them.
    if icon.RefreshIconDesaturation then
        hooksecurefunc(icon, "RefreshIconDesaturation", function(self)
            if IsCDOverrideActive(self) then
                local key = GetCachedEssentialIconKey(self)
                if key and IsSpellStillOnCooldown(key) then
                    local tex = self.Icon or self.icon
                    if tex and tex.SetDesaturated then
                        tex:SetDesaturated(true)
                    end
                end
            end
        end)
    end
    -- Hook SetUseAuraDisplayTime so Blizzard can't re-enable it on override spells
    if cd.SetUseAuraDisplayTime then
        hooksecurefunc(cd, "SetUseAuraDisplayTime", function(self, useAura)
            if _ebt_cdOverrideGuard[cd] then return end
            if useAura and IsCDOverrideActive(icon) then
                _ebt_cdOverrideGuard[cd] = true
                self:SetUseAuraDisplayTime(false)
                _ebt_cdOverrideGuard[cd] = nil
            end
        end)
    end
    -- 12.0.5+: Hook RefreshSpellCooldownInfo for more reliable CD override timing.
    -- This fires AFTER CacheCooldownValues() has computed everything (including wasSetFromAura),
    -- so our override replaces the final display at the right point in the refresh cycle.
    local _ebt_hookIs1205 = _G.CkraigCooldownManager and _G.CkraigCooldownManager.Is1205
    if _ebt_hookIs1205 and icon.RefreshSpellCooldownInfo then
        hooksecurefunc(icon, "RefreshSpellCooldownInfo", function(self)
            if _ebt_cdOverrideGuard[cd] then return end
            TryCooldownOverride(self, cd)
        end)
    end
    hooksecurefunc(cd, "SetCooldown", function()
        local im = ebtIconMeta[icon]
        if im then im.isOnCD = true end
        -- On 12.0.5, RefreshSpellCooldownInfo hook handles the override
        if not _ebt_hookIs1205 then
            TryCooldownOverride(icon, cd)
        end
    end)
    if cd.SetCooldownFromDurationObject then
        hooksecurefunc(cd, "SetCooldownFromDurationObject", function()
            local im = ebtIconMeta[icon]
            if im then im.isOnCD = true end
            if not _ebt_hookIs1205 then
                TryCooldownOverride(icon, cd)
            end
        end)
    end
    hooksecurefunc(cd, "Clear", function()
        local im = ebtIconMeta[icon]
        if not im then return end
        if not IsCDOverrideActive(icon) then
            im.isOnCD = false
            return
        end
        local key = GetCachedEssentialIconKey(icon)
        if key and IsSpellStillOnCooldown(key) then
            im.isOnCD = true
            TryCooldownOverride(icon, cd)
            return
        end
        RestoreIconSaturation(icon)
        im.isOnCD = false
    end)
    cd:HookScript("OnCooldownDone", function()
        local im = ebtIconMeta[icon]
        if not im then return end
        if not IsCDOverrideActive(icon) then
            im.isOnCD = false
            return
        end
        local key = GetCachedEssentialIconKey(icon)
        if key and IsSpellStillOnCooldown(key) then
            im.isOnCD = true
            TryCooldownOverride(icon, cd)
            return
        end
        RestoreIconSaturation(icon)
        im.isOnCD = false
    end)
    -- Immediately try the override for icons that already have a cooldown running
    TryCooldownOverride(icon, cd)
end

local function IsIconReady(icon)
    if not icon then return false end
    local m = ebtIconMeta[icon]
    if not m or not m.cdHooked then return true end
    return not m.isOnCD
end

local function IsIconOnCooldown(icon)
    return not IsIconReady(icon)
end

local function SafeNumber(val, default)
    local num = tonumber(val)
    if num ~= nil then return num end
    return default
end

local function IsEditModeActive()
    return EditModeManagerFrame and EditModeManagerFrame:IsShown()
end

-- ---------------------------
-- MyEssentialIconViewers Core (initialize early)
-- ---------------------------
-- Only define MyEssentialIconViewers for EssentialCooldownViewer in this file
MyEssentialIconViewers = MyEssentialIconViewers or {}
MyEssentialIconViewers.__pendingIcons = MyEssentialIconViewers.__pendingIcons or {}
MyEssentialIconViewers.__iconSkinEventFrame = MyEssentialIconViewers.__iconSkinEventFrame or nil
MyEssentialIconViewers.__pendingBackdrops = MyEssentialIconViewers.__pendingBackdrops or {}
MyEssentialIconViewers.__backdropEventFrame = MyEssentialIconViewers.__backdropEventFrame or nil

-- ---------------------------
-- Helper functions for skinning
-- ---------------------------
local function StripTextureMasks(texture)
    if not texture or not texture.GetMaskTexture then return end
    local i = 1
    local mask = texture:GetMaskTexture(i)
    while mask do
        texture:RemoveMaskTexture(mask)
        i = i + 1
        mask = texture:GetMaskTexture(i)
    end
end

local function StripBlizzardOverlay(icon)
    if not icon or not icon.GetRegions then return end
    for _, region in ipairs({ icon:GetRegions() }) do
        if region and region.IsObjectType and region:IsObjectType("Texture") and region.GetAtlas then
            if region:GetAtlas() == "UI-HUD-CoolDownManager-IconOverlay" then
                region:SetTexture("")
                region:Hide()
                region.Show = noop
            end
        end
    end
end

local noop = function() end
local function NeutralizeAtlasTexture(texture)
    if not texture then return end
    if not ebtNeutralizedAtlases[texture] then
        ebtNeutralizedAtlases[texture] = true
        if texture.SetAtlas then texture:SetAtlas(nil) end
        if texture.SetTexture then texture:SetTexture(nil) end
        if texture.SetAlpha then texture:SetAlpha(0) end
        texture.SetAtlas = noop
        texture.SetTexture = noop
        texture.SetAlpha = noop
    end
end

local function HideDebuffBorder(icon)
    if not icon then return end
    if icon.DebuffBorder then NeutralizeAtlasTexture(icon.DebuffBorder) end
    local name = icon.GetName and icon:GetName()
    if name and _G[name .. "DebuffBorder"] then NeutralizeAtlasTexture(_G[name .. "DebuffBorder"]) end
    if icon.GetRegions then
        for _, region in ipairs({ icon:GetRegions() }) do
            if region and region.IsObjectType and region:IsObjectType("Texture") then
                local rname = region.GetName and region:GetName()
                if rname and rname:find("DebuffBorder", 1, true) then
                    NeutralizeAtlasTexture(region)
                end
            end
        end
    end
end

-- Combat-safe deferred backdrop system
local function ProcessPendingBackdrops()
    if not MyEssentialIconViewers.__pendingBackdrops then return end
    for frame, info in pairs(MyEssentialIconViewers.__pendingBackdrops) do
        if frame and info then
            if not InCombatLockdown() then
                local okW, w = pcall(frame.GetWidth, frame)
                local okH, h = pcall(frame.GetHeight, frame)
                local dimsOk = false
                if okW and okH and w and h then
                    dimsOk = type(w) == "number" and type(h) == "number" and w > 0 and h > 0
                end
                if dimsOk then
                    local success = pcall(frame.SetBackdrop, frame, info.backdrop)
                    if success and info.color then
                        local r,g,b,a = unpack(info.color)
                        frame:SetBackdropBorderColor(r,g,b,a or 1)
                    end
                    frame:Show()
                    ebtBackdropPending[frame] = nil
                    MyEssentialIconViewers.__pendingBackdrops[frame] = nil
                end
            end
        end
    end
end

local function EnsureBackdropEventFrame()
    if MyEssentialIconViewers.__backdropEventFrame then return end
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("PLAYER_REGEN_ENABLED")
    ef:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_ENABLED" then
            ProcessPendingBackdrops()
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
    end)
    MyEssentialIconViewers.__backdropEventFrame = ef
end

local function SafeSetBackdrop(frame, backdropInfo, color)
    if not frame or not frame.SetBackdrop then return false end

    if InCombatLockdown() then
        ebtBackdropPending[frame] = true
        MyEssentialIconViewers.__pendingBackdrops = MyEssentialIconViewers.__pendingBackdrops or {}
        MyEssentialIconViewers.__pendingBackdrops[frame] = { backdrop = backdropInfo, color = color }
        EnsureBackdropEventFrame()
        MyEssentialIconViewers.__backdropEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return false
    end

    local okW, w = pcall(frame.GetWidth, frame)
    local okH, h = pcall(frame.GetHeight, frame)
    local dimsOk = false
    if okW and okH and w and h then
        dimsOk = type(w) == "number" and type(h) == "number" and w > 0 and h > 0
    end

    if not dimsOk then
        ebtBackdropPending[frame] = true
        MyEssentialIconViewers.__pendingBackdrops = MyEssentialIconViewers.__pendingBackdrops or {}
        MyEssentialIconViewers.__pendingBackdrops[frame] = { backdrop = backdropInfo, color = color }
        EnsureBackdropEventFrame()
        MyEssentialIconViewers.__backdropEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return false
    end

    local ok = pcall(frame.SetBackdrop, frame, backdropInfo)
    if ok and color then
        local r,g,b,a = unpack(color)
        frame:SetBackdropBorderColor(r,g,b,a or 1)
    end
    return ok
end

-- ---------------------------
-- Aspect ratio helper
-- ---------------------------
local function ConvertAspectRatio(value)
    if not value then return 1.0 end
    if type(value) == "number" then return value end
    local w,h = value:match("^(%d+%.?%d*):(%d+%.?%d*)$")
    if w and h then return tonumber(w)/tonumber(h) end
    w,h = value:match("^(%d+%.?%d*)x(%d+%.?%d*)$")
    if w and h then return tonumber(w)/tonumber(h) end
    return 1.0
end

-- ---------------------------
-- Force reskin helper (fixes live preview)
-- ---------------------------
local function ForceReskinViewer(viewer)
    if not viewer then return end
    InvalidateEBTSkin()
end

-- ---------------------------
-- SkinIcon (combined, robust)
-- ---------------------------
function MyEssentialIconViewers:SkinIcon(icon, settings)
    -- Version guard: skip if already skinned at current version
    local m = GetIconMeta(icon)
    if m._ebt_skinVer == _ebt_skinVersion then
        return true
    end

    -- Pixel-perfect: enforce texel snapping and nearest filtering
    local iconTexture = icon.Icon or icon.icon
    if iconTexture then
        if iconTexture.SetTexelSnappingBias then iconTexture:SetTexelSnappingBias(0) end
        if iconTexture.SetTextureFilter then iconTexture:SetTextureFilter("nearest") end
        -- Ensure icon size is whole integer (default to 32 if not set)
        local w = icon:GetWidth() or 32
        local h = icon:GetHeight() or 32
        w = math.floor(w + 0.5)
        h = math.floor(h + 0.5)
        icon:SetSize(w, h)
    end
    -- Add 1-pixel black border using three overlay textures (no right border)
    local m = GetIconMeta(icon)
    if not m.pixelBorders then
        m.pixelBorders = {}
        -- Top
        local top = icon:CreateTexture(nil, "OVERLAY")
        top:SetColorTexture(0, 0, 0, 1)
        top:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        top:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 0)
        top:SetHeight(1)
        m.pixelBorders.top = top
        -- Bottom
        local bottom = icon:CreateTexture(nil, "OVERLAY")
        bottom:SetColorTexture(0, 0, 0, 1)
        bottom:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)
        bottom:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
        bottom:SetHeight(1)
        m.pixelBorders.bottom = bottom
        -- Left
        local leftB = icon:CreateTexture(nil, "OVERLAY")
        leftB:SetColorTexture(0, 0, 0, 1)
        leftB:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        leftB:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)
        leftB:SetWidth(1)
        m.pixelBorders.left = leftB
    end
    for _, border in pairs(m.pixelBorders) do
        border:SetHeight(1)
        border:SetWidth(1)
        border:Show()
    end
        -- ...existing code...
    if not icon then return false end

    local iconTexture = icon.Icon or icon.icon
    if not iconTexture then return false end

    settings = settings or MyEssentialBuffTracker:GetSettings()

    -- Aspect ratio + corner radius (texcoord cropping)
    local cornerRadius = settings.iconCornerRadius or DEFAULTS.iconCornerRadius

    local aspectRatioValue = 1.0
    if settings.aspectRatioCrop and type(settings.aspectRatioCrop) == "number" then
        aspectRatioValue = settings.aspectRatioCrop
    elseif settings.aspectRatio then
        aspectRatioValue = ConvertAspectRatio(settings.aspectRatio)
    end

    iconTexture:ClearAllPoints()
    iconTexture:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
    iconTexture:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)

    StripTextureMasks(iconTexture)

    local left, right, top, bottom = 0, 1, 0, 1

    if aspectRatioValue ~= 1.0 then
        if aspectRatioValue > 1.0 then
            local crop = 1 - (1 / aspectRatioValue)
            local off = crop / 2
            top = top + off
            bottom = bottom - off
        else
            local crop = 1 - aspectRatioValue
            local off = crop / 2
            left = left + off
            right = right - off
        end
    end

    if cornerRadius and cornerRadius ~= 0 then
        local extra = 0.07 + (cornerRadius * 0.005)
        if extra > 0.24 then extra = 0.24 end
        left   = left   + extra
        right  = right  - extra
        top    = top    + extra
        bottom = bottom - extra
    end

    iconTexture:SetTexCoord(left, right, top, bottom)

    -- Cooldown swipe / flash alignment
    local cdPadding = 0

    if icon.CooldownFlash then
        icon.CooldownFlash:ClearAllPoints()
        icon.CooldownFlash:SetPoint("TOPLEFT", icon, "TOPLEFT", cdPadding, -cdPadding)
        icon.CooldownFlash:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -cdPadding, cdPadding)
    end

    if icon.Cooldown or icon.cooldown then
        local cd = icon.Cooldown or icon.cooldown
        cd:ClearAllPoints()
        cd:SetPoint("TOPLEFT", icon, "TOPLEFT", cdPadding, -cdPadding)
        cd:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -cdPadding, cdPadding)

        if cd.SetSwipeTexture then cd:SetSwipeTexture("Interface\\Buttons\\WHITE8X8") end
        if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.8) end
        if cd.SetDrawEdge then cd:SetDrawEdge(true) end
        if cd.SetDrawSwipe then cd:SetDrawSwipe(true) end
    end

    -- Pandemic + out of range alignment
    local picon = icon.PandemicIcon or icon.pandemicIcon or icon.Pandemic or icon.pandemic
    if not picon then
        local m2 = GetIconMeta(icon)
        if m2._cachedPandemic ~= nil then
            picon = m2._cachedPandemic
        elseif icon.GetChildren then
            for i2 = 1, select("#", icon:GetChildren()) do
                local child = select(i2, icon:GetChildren())
                local n = child.GetName and child:GetName()
                if n and n:find("Pandemic") then
                    picon = child
                    break
                end
            end
            m2._cachedPandemic = picon or false
        end
    end
    if picon and picon.ClearAllPoints then
        picon:ClearAllPoints()
        picon:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        picon:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
    end

    local oor = icon.OutOfRange or icon.outOfRange or icon.oor
    if oor and oor.ClearAllPoints then
        oor:ClearAllPoints()
        oor:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        oor:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
    end

    -- Charge / stack text detection and placement
    local chargeText = nil

    if icon.GetApplicationsFontString then
        local ok, result = pcall(icon.GetApplicationsFontString, icon)
        if ok then chargeText = result end
    end

    if not chargeText and icon.ChargeCount and icon.ChargeCount.Current then
        chargeText = icon.ChargeCount.Current
    end

    if not chargeText then
        chargeText = icon._chargeText or icon._customCountText or icon.Count or icon.count
            or icon.Charges or icon.charges or icon.StackCount
    end

    if not chargeText and icon.GetRegions then
        for _, region in ipairs({ icon:GetRegions() }) do
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                local t = region:GetText()
                if t and tonumber(t) and tonumber(t) > 0 then
                    chargeText = region
                    break
                end
            end
        end
    end

    if chargeText and chargeText.SetFont then
        if settings.showChargeText then
            chargeText:Show()
            local fontSize = SafeNumber(settings.chargeTextSize, DEFAULTS.chargeTextSize)
            chargeText:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
            chargeText:ClearAllPoints()

            local position = POSITION_PRESETS[settings.chargeTextPosition] or POSITION_PRESETS["BOTTOMRIGHT"]
            local offsetX = SafeNumber(settings.chargeTextX, 0)
            local offsetY = SafeNumber(settings.chargeTextY, 0)
            chargeText:SetPoint(position.point, icon, position.point, position.x + offsetX, position.y + offsetY)
            -- Cache for dispatch re-enforcement (Blizzard resets on proc/refresh)
            m.chargeTextRef = chargeText
            m.chargeAnchor = position.point
            m.chargeOffX = position.x + offsetX
            m.chargeOffY = position.y + offsetY
            -- Force use of CooldownChargeDB for charge/stack text color
            local color = (_G.CooldownChargeDB and _G.CooldownChargeDB["TextColor_ChargeText_Essential"]) or {1,1,1,1}
            if color and chargeText.SetTextColor then
                chargeText:SetTextColor(color[1], color[2], color[3], color[4] or 1)
            end
        else
            chargeText:Hide()
            m.chargeTextRef = nil
        end
    end

    -- Cooldown text detection and placement
    local cdText = nil
    if icon.Cooldown or icon.cooldown then
        local cd = icon.Cooldown or icon.cooldown
        cdText = cd.Text or cd.text

        if not cdText then
            -- Check cached result first
            local m3 = GetIconMeta(icon)
            if m3._cachedCdText ~= nil then
                cdText = m3._cachedCdText
            else
                if cd.GetChildren then
                    for i3 = 1, select("#", cd:GetChildren()) do
                        local child = select(i3, cd:GetChildren())
                        if child and child.GetObjectType and child:GetObjectType() == "FontString" then
                            cdText = child
                            break
                        end
                    end
                end

                if not cdText and cd.GetRegions then
                    for i3 = 1, select("#", cd:GetRegions()) do
                        local region = select(i3, cd:GetRegions())
                        if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                            cdText = region
                            break
                        end
                    end
                end
                m3._cachedCdText = cdText or false
            end
        end
    end

    if cdText and cdText.SetFont then
        if settings.showCooldownText then
            cdText:Show()
            local fontSize = SafeNumber(settings.cooldownTextSize, DEFAULTS.cooldownTextSize)
            cdText:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
            cdText:ClearAllPoints()

            local position = POSITION_PRESETS[settings.cooldownTextPosition] or POSITION_PRESETS["CENTER"]
            local offsetX = SafeNumber(settings.cooldownTextX, 0)
            local offsetY = SafeNumber(settings.cooldownTextY, 0)
            cdText:SetPoint(position.point, icon, position.point, position.x + offsetX, position.y + offsetY)
            -- Cache for dispatch re-enforcement
            m.cdTextRef = cdText
            m.cdAnchor = position.point
            m.cdOffX = position.x + offsetX
            m.cdOffY = position.y + offsetY
            -- Force use of CooldownChargeDB for cooldown text color
            local color = (_G.CooldownChargeDB and _G.CooldownChargeDB["TextColor_CooldownText_Essential"]) or {1,1,1,1}
            if color and cdText.SetTextColor then
                cdText:SetTextColor(color[1], color[2], color[3], color[4] or 1)
            end
        else
            cdText:Hide()
            m.cdTextRef = nil
        end
    end

    -- Strip overlays and debuff borders
    StripBlizzardOverlay(icon)
    HideDebuffBorder(icon)

    -- ElvUI-style icon crop
    local iconTexture = icon.Icon or icon.icon
    if iconTexture then
        iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    -- Add 1-pixel black border using four overlay textures


        -- ...existing code...
    local ms = GetIconMeta(icon)
    ms.skinned = true
    ms.skinPending = nil
    ms._ebt_skinVer = _ebt_skinVersion
    return true
end

-- ---------------------------
-- Process pending icons (called after combat)
-- ---------------------------
function MyEssentialIconViewers:ProcessPendingIcons()
    for icon, data in pairs(self.__pendingIcons) do
        if icon and icon:IsShown() and not (ebtIconMeta[icon] and ebtIconMeta[icon].skinned) then
            pcall(self.SkinIcon, self, icon, data.settings)
        end
        self.__pendingIcons[icon] = nil
    end
end

local function EnsurePendingEventFrame()
    if MyEssentialIconViewers.__iconSkinEventFrame then return end
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("PLAYER_REGEN_ENABLED")
    ef:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_ENABLED" then
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            MyEssentialIconViewers:ProcessPendingIcons()
            ProcessPendingBackdrops()
        end
    end)
    MyEssentialIconViewers.__iconSkinEventFrame = ef
end

-- ===========================
-- Essential Cluster Mode
-- ===========================
local MAX_EBT_CLUSTER_GROUPS = 20

local DEFAULT_EBT_CLUSTER_POSITIONS = {
    [1] = { point = "CENTER", x = -300, y = -200 },
    [2] = { point = "CENTER", x = -150, y = -200 },
    [3] = { point = "CENTER", x = 0,    y = -200 },
    [4] = { point = "CENTER", x = 150,  y = -200 },
    [5] = { point = "CENTER", x = 300,  y = -200 },
}

local function GetEBTDefaultClusterPosition(index)
    if DEFAULT_EBT_CLUSTER_POSITIONS[index] then
        return DEFAULT_EBT_CLUSTER_POSITIONS[index]
    end
    local col = ((index - 1) % 5) - 2
    local row = math.floor((index - 1) / 5)
    return { point = "CENTER", x = col * 150, y = -200 - row * 150 }
end

-- Key normalization
local function EBTNormalizeKeyToString(key)
    if key == nil then return nil end
    return tostring(key)
end

-- Manual order management
local function GetEBTClusterManualOrder(settings, clusterIndex)
    settings.clusterManualOrders = settings.clusterManualOrders or {}
    if not settings.clusterManualOrders[clusterIndex] then
        settings.clusterManualOrders[clusterIndex] = {}
    end
    return settings.clusterManualOrders[clusterIndex]
end

local function MoveKeyInEBTClusterOrder(settings, clusterIndex, key, direction)
    local normalizedKey = EBTNormalizeKeyToString(key)
    if not normalizedKey then return false end
    local orderList = GetEBTClusterManualOrder(settings, clusterIndex)
    local fromIndex
    for i, existing in ipairs(orderList) do
        if tostring(existing) == normalizedKey then
            fromIndex = i
            break
        end
    end
    if not fromIndex then
        table.insert(orderList, normalizedKey)
        fromIndex = #orderList
    end
    local toIndex = fromIndex + (direction or 0)
    if toIndex < 1 or toIndex > #orderList then
        return false
    end
    orderList[fromIndex], orderList[toIndex] = orderList[toIndex], orderList[fromIndex]
    return true
end

local function BuildEBTOrderedKeysForCluster(settings, clusterIndex, availableKeys)
    local ordered = {}
    local added = {}

    settings.clusterAssignments = settings.clusterAssignments or {}
    local orderList = GetEBTClusterManualOrder(settings, clusterIndex)

    local function CanUseKey(key)
        local normalizedKey = EBTNormalizeKeyToString(key)
        if not normalizedKey then return nil end
        local assigned = tonumber(settings.clusterAssignments[normalizedKey]) or 1
        if assigned ~= clusterIndex then return nil end
        if availableKeys and not availableKeys[normalizedKey] then return nil end
        return normalizedKey
    end

    for _, key in ipairs(orderList) do
        local usable = CanUseKey(key)
        if usable and not added[usable] then
            table.insert(ordered, usable)
            added[usable] = true
        end
    end

    local leftovers = {}
    for key, assigned in pairs(settings.clusterAssignments) do
        if (tonumber(assigned) or 1) == clusterIndex then
            local usable = CanUseKey(key)
            if usable and not added[usable] then
                table.insert(leftovers, usable)
                added[usable] = true
            end
        end
    end

    table.sort(leftovers, function(a, b)
        local aNum = tonumber(a)
        local bNum = tonumber(b)
        if aNum and bNum then return aNum < bNum end
        return tostring(a) < tostring(b)
    end)

    for _, key in ipairs(leftovers) do
        table.insert(ordered, key)
    end

    return ordered
end

-- Build available key set from the viewer pool
local function BuildEBTAvailableKeySet(viewer)
    local keys = {}
    local pool = viewer and viewer.itemFramePool
    if pool then
        for icon in pool:EnumerateActive() do
            if icon and icon:IsShown() then
                local key = GetEssentialIconKey(icon)
                if key then keys[tostring(key)] = true end
            end
        end
    end
    -- Include always-show spells
    local settings = MyEssentialBuffTracker:GetSettings()
    if settings.clusterAlwaysShowSpells then
        for key in pairs(settings.clusterAlwaysShowSpells) do
            keys[tostring(key)] = true
        end
    end
    -- Include duplicate spells
    if settings.clusterDuplicates then
        for key in pairs(settings.clusterDuplicates) do
            keys[tostring(key)] = true
        end
    end
    return keys
end

-- Cluster anchor creation and management
local function EnsureEBTClusterAnchorForIndex(viewer, settings, index)
    local vm = GetViewerMeta(viewer)
    vm.clusterAnchors = vm.clusterAnchors or {}
    local anchors = vm.clusterAnchors

    if anchors[index] then
        return anchors[index]
    end

    local anchor = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    anchor:SetSize(120, 120)
    anchor:SetMovable(true)
    anchor:EnableMouse(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetClampedToScreen(true)
    anchor:SetFrameStrata("MEDIUM")

    anchor:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    anchor:SetBackdropColor(0, 0, 0, 0.12)
    anchor:SetBackdropBorderColor(0.2, 0.8, 0.4, 0.9)  -- green tint to differentiate from DI

    anchor._clusterIndex = index

    anchor:SetScript("OnDragStart", function(self)
        local s = MyEssentialBuffTracker:GetSettings()
        if not s or not s.clusterUnlocked then return end
        if InCombatLockdown() then return end
        self:StartMoving()
    end)
    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local s = MyEssentialBuffTracker:GetSettings()
        if not s then return end
        s.clusterPositions = s.clusterPositions or {}
        local point, _, relPoint, x, y = self:GetPoint(1)
        s.clusterPositions[self._clusterIndex] = {
            point = point or "CENTER",
            relPoint = relPoint or "CENTER",
            x = x or 0,
            y = y or 0,
        }
    end)
    anchor:SetScript("OnMouseUp", nil)

    anchors[index] = anchor

    local saved = settings.clusterPositions and settings.clusterPositions[index]
    local fallback = GetEBTDefaultClusterPosition(index)
    local point = (saved and saved.point) or fallback.point
    local relPoint = (saved and saved.relPoint) or point
    local x = (saved and saved.x) or fallback.x
    local y = (saved and saved.y) or fallback.y
    anchor:ClearAllPoints()
    anchor:SetPoint(point, UIParent, relPoint, x, y)
    anchor:Hide()

    return anchor
end

-- Persistent icon system for Essential
local _ebt_persistentIcons = {}
local _ebt_persistentPool = {}

local function GetOrCreateEBTPersistentIcon(spellKey)
    if _ebt_persistentIcons[spellKey] then
        return _ebt_persistentIcons[spellKey]
    end
    local frame = table.remove(_ebt_persistentPool)
    if not frame then
        frame = CreateFrame("Frame", nil, UIParent)
        frame:SetFrameStrata("MEDIUM")
        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        frame.Icon = icon
        local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetDrawEdge(true)
        frame.Cooldown = cd
        for _, side in ipairs({"TOP", "BOTTOM", "LEFT", "RIGHT"}) do
            local border = frame:CreateTexture(nil, "OVERLAY")
            border:SetColorTexture(0, 0, 0, 1)
            if side == "TOP" then
                border:SetHeight(1); border:SetPoint("TOPLEFT"); border:SetPoint("TOPRIGHT")
            elseif side == "BOTTOM" then
                border:SetHeight(1); border:SetPoint("BOTTOMLEFT"); border:SetPoint("BOTTOMRIGHT")
            elseif side == "LEFT" then
                border:SetWidth(1); border:SetPoint("TOPLEFT"); border:SetPoint("BOTTOMLEFT")
            else
                border:SetWidth(1); border:SetPoint("TOPRIGHT"); border:SetPoint("BOTTOMRIGHT")
            end
        end
    end
    frame._spellKey = spellKey
    frame._isPersistentIcon = true
    frame.spellID = tonumber(spellKey)
    local spellID = tonumber(spellKey)
    if spellID and C_Spell and C_Spell.GetSpellTexture then
        local tex = C_Spell.GetSpellTexture(spellID)
        if tex then frame.Icon:SetTexture(tex) end
    end
    _ebt_persistentIcons[spellKey] = frame
    return frame
end

local function UpdateEBTPersistentIconCooldown(frame)
    local spellID = tonumber(frame._spellKey)
    if not spellID then
        frame.Cooldown:Clear(); frame:SetAlpha(0.5); return
    end
    local durObj
    if C_Spell and C_Spell.GetSpellCooldownDuration then
        durObj = C_Spell.GetSpellCooldownDuration(spellID)
    end
    local cdInfo
    if C_Spell and C_Spell.GetSpellCooldown then
        cdInfo = C_Spell.GetSpellCooldown(spellID)
    end
    if durObj and cdInfo and cdInfo.isOnGCD ~= true then
        frame.Cooldown:SetCooldownFromDurationObject(durObj)
        frame:SetAlpha(1.0)
    else
        frame.Cooldown:Clear()
        frame:SetAlpha(0.5)
    end
end

local function HideAllEBTPersistentIcons()
    for _, frame in pairs(_ebt_persistentIcons) do
        frame:Hide()
    end
end

-- Persistent + duplicate icon update (event-driven, zero CPU when idle)
local _ebt_persistentUpdateFrame = CreateFrame("Frame")
_ebt_persistentUpdateFrame:Hide()
_ebt_persistentUpdateFrame._batchPending = false
_ebt_persistentUpdateFrame._nextAllowed = 0
local _ebt_persistentThrottle = 0.1

local function RunEBTPersistentDuplicateUpdate()
    _ebt_persistentUpdateFrame._nextAllowed = GetTime() + _ebt_persistentThrottle
    local anyVisible = false
    for _, frame in pairs(_ebt_persistentIcons) do
        if frame:IsShown() then
            UpdateEBTPersistentIconCooldown(frame)
            anyVisible = true
        end
    end
    for _, frame in pairs(_ebt_duplicateIcons) do
        if frame:IsShown() then
            local src = frame._sourceIcon
            if src and frame.Cooldown then
                local cdStart = src._ebt_cdStart
                local cdDur = src._ebt_cdDur
                -- Prefer fresh durationObject lookup for the spell
                local spellID = frame.spellID or tonumber(frame._spellKey)
                local durObj = spellID and C_Spell and C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(spellID)
                if durObj then
                    frame.Cooldown:SetCooldownFromDurationObject(durObj)
                elseif cdStart and cdDur then
                    frame.Cooldown:SetCooldown(cdStart, cdDur)
                else
                    frame.Cooldown:Clear()
                end
                frame:SetAlpha(1.0)
                local hookedTex = src._ebt_iconTexture
                if hookedTex and frame.Icon then
                    frame.Icon:SetTexture(hookedTex)
                end
            else
                UpdateEBTPersistentIconCooldown(frame)
            end
            anyVisible = true
        end
    end
    if not anyVisible then
        _ebt_persistentUpdateFrame:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
    end
end

-- Pre-baked callback for C_Timer.After (avoids closure allocation per event)
local function _ebt_persistentTimerCallback()
    _ebt_persistentUpdateFrame._batchPending = false
    RunEBTPersistentDuplicateUpdate()
end

local function ScheduleEBTPersistentDuplicateUpdate(immediate)
    if _ebt_persistentUpdateFrame._batchPending then
        return
    end

    local now = GetTime()
    local delay = 0
    if not immediate and now < (_ebt_persistentUpdateFrame._nextAllowed or 0) then
        delay = _ebt_persistentUpdateFrame._nextAllowed - now
    end

    _ebt_persistentUpdateFrame._batchPending = true
    C_Timer.After(delay, _ebt_persistentTimerCallback)
end
-- Event registration deferred until persistent icons are created (avoids idle CPU)
_ebt_persistentUpdateFrame:SetScript("OnEvent", function(self)
    ScheduleEBTPersistentDuplicateUpdate(false)
end)

-- Duplicate icon system for Essential
local _ebt_duplicateIcons = {}
local _ebt_duplicatePool = {}

local _ebt_hookedCooldowns = {}
local function HookEBTSourceIconForDuplicates(sourceIcon)
    if not sourceIcon then return end
    local cd = sourceIcon.Cooldown
    if cd and not _ebt_hookedCooldowns[cd] then
        _ebt_hookedCooldowns[cd] = true
        hooksecurefunc(cd, "SetCooldown", function(_self, start, duration)
            sourceIcon._ebt_cdStart = start
            sourceIcon._ebt_cdDur = duration
        end)
        if cd.SetCooldownFromDurationObject then
            hooksecurefunc(cd, "SetCooldownFromDurationObject", function(_self, durObj)
                sourceIcon._ebt_cdDurObj = durObj
            end)
        end
        hooksecurefunc(cd, "Clear", function()
            sourceIcon._ebt_cdStart = 0
            sourceIcon._ebt_cdDur = 0
            sourceIcon._ebt_cdDurObj = nil
        end)
    end
    local iconTex = sourceIcon.Icon or sourceIcon.icon
    if iconTex and iconTex.SetTexture and not sourceIcon._ebt_hookedTexture then
        sourceIcon._ebt_hookedTexture = true
        hooksecurefunc(iconTex, "SetTexture", function(_self, tex)
            sourceIcon._ebt_iconTexture = tex
        end)
        pcall(function()
            local t = iconTex:GetTexture()
            if t then sourceIcon._ebt_iconTexture = t end
        end)
    end
end

local function GetOrCreateEBTDuplicateIcon(spellKey, clusterIndex)
    local cacheKey = tostring(spellKey) .. "_dup_" .. tostring(clusterIndex)
    if _ebt_duplicateIcons[cacheKey] then
        return _ebt_duplicateIcons[cacheKey]
    end
    local frame = table.remove(_ebt_duplicatePool)
    if not frame then
        frame = CreateFrame("Frame", nil, UIParent)
        frame:SetFrameStrata("MEDIUM")
        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        frame.Icon = icon
        local cd = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetDrawEdge(true)
        frame.Cooldown = cd
        for _, side in ipairs({"TOP", "BOTTOM", "LEFT", "RIGHT"}) do
            local border = frame:CreateTexture(nil, "OVERLAY")
            border:SetColorTexture(0, 0, 0, 1)
            if side == "TOP" then
                border:SetHeight(1); border:SetPoint("TOPLEFT"); border:SetPoint("TOPRIGHT")
            elseif side == "BOTTOM" then
                border:SetHeight(1); border:SetPoint("BOTTOMLEFT"); border:SetPoint("BOTTOMRIGHT")
            elseif side == "LEFT" then
                border:SetWidth(1); border:SetPoint("TOPLEFT"); border:SetPoint("BOTTOMLEFT")
            else
                border:SetWidth(1); border:SetPoint("TOPRIGHT"); border:SetPoint("BOTTOMRIGHT")
            end
        end
    end
    frame._spellKey = spellKey
    frame._isDuplicateIcon = true
    frame._dupCluster = clusterIndex
    frame.spellID = tonumber(spellKey)
    local spellID = tonumber(spellKey)
    if spellID and C_Spell and C_Spell.GetSpellTexture then
        local tex = C_Spell.GetSpellTexture(spellID)
        if tex then frame.Icon:SetTexture(tex) end
    end
    _ebt_duplicateIcons[cacheKey] = frame
    return frame
end

local function HideAllEBTDuplicateIcons()
    for _, frame in pairs(_ebt_duplicateIcons) do
        frame:Hide()
    end
end

-- Sample icon rendering for cluster preview
local _ebt_sampleIconTextureCache = {}

local function RenderEBTClusterSampleIcons(viewer, settings, clusterCount, rowLimit, defaultIconSize, spacing, opts)
    local vm = GetViewerMeta(viewer)
    vm.clusterSampleIcons = vm.clusterSampleIcons or {}
    local unlockPreview = opts and opts.unlockPreview
    local availableKeys = opts and opts.availableKeys

    for groupIndex = 1, clusterCount do
        local anchor = vm.clusterAnchors and vm.clusterAnchors[groupIndex]
        if anchor then
            local orderedKeys = BuildEBTOrderedKeysForCluster(settings, groupIndex, availableKeys)
            local sampleCount = #orderedKeys

            local clusterFlow = string.lower(tostring(settings.clusterFlows[groupIndex] or settings.clusterFlow or DEFAULTS.clusterFlow))
            local clusterIconSize = SafeNumber(settings.clusterIconSizes[groupIndex], defaultIconSize)
            local centerClusterIcons = settings.clusterCenterIcons ~= false

            if not vm.clusterSampleIcons[groupIndex] then
                vm.clusterSampleIcons[groupIndex] = {}
            end
            local textureList = vm.clusterSampleIcons[groupIndex]

            local lineSize = sampleCount
            local lineCount = 1
            if rowLimit and rowLimit > 0 then
                lineSize = math.max(1, rowLimit)
                lineCount = math.ceil(math.max(1, sampleCount) / lineSize)
            end

            local columns, rows
            if clusterFlow == "vertical" then
                rows = math.min(math.max(1, sampleCount), lineSize)
                columns = lineCount
            else
                columns = math.min(math.max(1, sampleCount), lineSize)
                rows = lineCount
            end

            local groupWidth = columns * clusterIconSize + math.max(0, columns - 1) * spacing
            local groupHeight = rows * clusterIconSize + math.max(0, rows - 1) * spacing
            anchor:SetSize(math.max(120, groupWidth + 10), math.max(120, groupHeight + 30))

            for idx = 1, sampleCount do
                local key = orderedKeys[idx]
                local tex = textureList[idx]
                if not tex then
                    tex = anchor:CreateTexture(nil, "BACKGROUND")
                    textureList[idx] = tex
                end

                local spellID = tonumber(key)
                local iconTex = _ebt_sampleIconTextureCache[key]
                if not iconTex and spellID and C_Spell and C_Spell.GetSpellTexture then
                    iconTex = C_Spell.GetSpellTexture(spellID)
                    if iconTex then _ebt_sampleIconTextureCache[key] = iconTex end
                end
                if iconTex then
                    tex:SetTexture(iconTex)
                else
                    tex:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")
                end

                tex:SetSize(clusterIconSize, clusterIconSize)

                local placementIndex = idx
                local rowIndex, colIndex
                if clusterFlow == "vertical" then
                    rowIndex = (placementIndex - 1) % lineSize
                    colIndex = math.floor((placementIndex - 1) / lineSize)
                else
                    rowIndex = math.floor((placementIndex - 1) / lineSize)
                    colIndex = (placementIndex - 1) % lineSize
                end

                tex:ClearAllPoints()
                if centerClusterIcons then
                    local x = -groupWidth / 2 + clusterIconSize / 2 + colIndex * (clusterIconSize + spacing)
                    local y = groupHeight / 2 - clusterIconSize / 2 - rowIndex * (clusterIconSize + spacing)
                    tex:SetPoint("CENTER", anchor, "CENTER", x, y)
                else
                    local x = 5 + colIndex * (clusterIconSize + spacing)
                    local y = -(15 + rowIndex * (clusterIconSize + spacing))
                    tex:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y)
                end

                if unlockPreview then
                    tex:SetAlpha(0.6)
                    tex:SetDesaturated(false)
                else
                    tex:SetAlpha(0.2)
                    tex:SetDesaturated(true)
                end
                tex:Show()
            end

            for idx = sampleCount + 1, #textureList do
                if textureList[idx] then textureList[idx]:Hide() end
            end
        end
    end

    for groupIndex = clusterCount + 1, MAX_EBT_CLUSTER_GROUPS do
        local textureList = vm.clusterSampleIcons[groupIndex]
        if textureList then
            for _, texture in ipairs(textureList) do
                if texture then texture:Hide() end
            end
        end
    end
end

local function HideEBTClusterSampleIcons(viewer)
    local vm = ebtViewerMeta[viewer]
    if not vm or not vm.clusterSampleIcons then return end
    for _, textureList in pairs(vm.clusterSampleIcons) do
        for _, texture in ipairs(textureList) do
            if texture then texture:Hide() end
        end
    end
end

-- Cluster icon drag-and-drop state
local _ebt_dragState = {
    draggingIcon = nil,
    sourceCluster = nil,
}

-- Free-position mode: right-click an icon to select it, then use arrow keys to nudge it
local _ebt_freePosSelected = nil
local _ebt_freePosViewer   = nil
local _ebt_freePosKeyFrame = nil

local function EBTFreePosDeselect()
    if _ebt_freePosSelected then
        local icon = _ebt_freePosSelected
        if icon._ebtSelectHighlight then icon._ebtSelectHighlight:Hide() end
        _ebt_freePosSelected = nil
        _ebt_freePosViewer   = nil
    end
    if _ebt_freePosKeyFrame then
        _ebt_freePosKeyFrame:EnableKeyboard(false)
    end
end

local function EBTFreePosNudge(dx, dy)
    local icon = _ebt_freePosSelected
    if not icon then return end
    local ci = icon._ebtDragCluster
    local iconKey = GetEssentialIconKey(icon)
    if not ci or not iconKey then return end
    local keyStr = tostring(iconKey)
    local s = MyEssentialBuffTracker:GetSettings()
    if not s then return end
    s.clusterIconFreePositions = s.clusterIconFreePositions or {}
    s.clusterIconFreePositions[ci] = s.clusterIconFreePositions[ci] or {}
    local pos = s.clusterIconFreePositions[ci][keyStr] or {x=0, y=0}
    local newX = (pos.x or 0) + dx
    local newY = (pos.y or 0) + dy
    s.clusterIconFreePositions[ci][keyStr] = {x=newX, y=newY}
    if _ebt_freePosViewer then
        local vm = GetViewerMeta(_ebt_freePosViewer)
        local anchor = vm.clusterAnchors and vm.clusterAnchors[ci]
        if anchor then
            icon:ClearAllPoints()
            icon:SetPoint("CENTER", anchor, "CENTER", newX, newY)
        end
    end
end

local function EBTFreePosSelect(icon, viewer)
    EBTFreePosDeselect()
    _ebt_freePosSelected = icon
    _ebt_freePosViewer   = viewer
    -- Yellow highlight overlay
    if not icon._ebtSelectHighlight then
        local hl = icon:CreateTexture(nil, "OVERLAY", nil, 7)
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.9, 0, 0.4)
        icon._ebtSelectHighlight = hl
    end
    icon._ebtSelectHighlight:Show()
    -- Build key capture frame once
    if not _ebt_freePosKeyFrame then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetAllPoints(UIParent)
        f:SetFrameStrata("TOOLTIP")
        f:EnableMouse(false)
        f:EnableKeyboard(false)
        f:SetScript("OnKeyDown", function(self, key)
            if not _ebt_freePosSelected then
                self:EnableKeyboard(false)
                return
            end
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                EBTFreePosDeselect()
                return
            end
            local step = IsShiftKeyDown() and 10 or 1
            if     key == "UP"    then self:SetPropagateKeyboardInput(false); EBTFreePosNudge(0,  step)
            elseif key == "DOWN"  then self:SetPropagateKeyboardInput(false); EBTFreePosNudge(0, -step)
            elseif key == "LEFT"  then self:SetPropagateKeyboardInput(false); EBTFreePosNudge(-step, 0)
            elseif key == "RIGHT" then self:SetPropagateKeyboardInput(false); EBTFreePosNudge( step, 0)
            else   self:SetPropagateKeyboardInput(true)
            end
        end)
        _ebt_freePosKeyFrame = f
    end
    _ebt_freePosKeyFrame:EnableKeyboard(true)
end

local function RemoveKeyFromEBTOrderList(orderList, key)
    if type(orderList) ~= "table" then return end
    local normalized = tostring(key)
    for i = #orderList, 1, -1 do
        if tostring(orderList[i]) == normalized then
            table.remove(orderList, i)
        end
    end
end

local function RemoveKeyFromAllEBTClusterOrders(settings, key)
    settings.clusterManualOrders = settings.clusterManualOrders or {}
    for _, orderList in pairs(settings.clusterManualOrders) do
        RemoveKeyFromEBTOrderList(orderList, key)
    end
end

local function FindEBTClusterForCursor(vm, clusterCount, mx, my)
    if not vm or not vm.clusterAnchors then return nil end

    for ci = 1, clusterCount do
        local anchor = vm.clusterAnchors[ci]
        if anchor and anchor:IsShown() then
            local left, right = anchor:GetLeft(), anchor:GetRight()
            local bottom, top = anchor:GetBottom(), anchor:GetTop()
            if left and right and bottom and top and mx >= left and mx <= right and my >= bottom and my <= top then
                return ci, anchor
            end
        end
    end

    local closestCluster, closestAnchor, closestDist = nil, nil, 1e9
    for ci = 1, clusterCount do
        local anchor = vm.clusterAnchors[ci]
        if anchor and anchor:IsShown() then
            local cx, cy = anchor:GetCenter()
            if cx and cy then
                local dx, dy = mx - cx, my - cy
                local dist = dx * dx + dy * dy
                if dist < closestDist then
                    closestDist = dist
                    closestCluster = ci
                    closestAnchor = anchor
                end
            end
        end
    end

    return closestCluster, closestAnchor
end

local function FindEBTNearestKeyInCluster(vm, clusterIndex, draggedIcon, mx, my)
    if not vm or not vm.clusterIconsByIndex then return nil end
    local iconList = vm.clusterIconsByIndex[clusterIndex]
    if type(iconList) ~= "table" then return nil end

    local nearestKey, nearestDist = nil, 1e9
    for _, child in ipairs(iconList) do
        if child and child ~= draggedIcon and (child.Icon or child.icon) then
            local cx, cy = child:GetCenter()
            local key = GetEssentialIconKey(child)
            if cx and cy and key then
                local dx, dy = mx - cx, my - cy
                local dist = dx * dx + dy * dy
                if dist < nearestDist then
                    nearestDist = dist
                    nearestKey = tostring(key)
                end
            end
        end
    end

    return nearestKey
end

-- Setup drag handlers for cluster icons
local function SetupEBTClusterIconDrag(icon, viewer, clusterIndex)
    if not icon or InCombatLockdown() then return end

    icon._ebtDragCluster = clusterIndex
    icon:SetMovable(true)
    icon:RegisterForDrag("LeftButton")
    icon:EnableMouse(true)

    icon:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        local s = MyEssentialBuffTracker:GetSettings()
        if not s or not s.clusterUnlocked then return end
        local ci = self._ebtDragCluster or clusterIndex

        _ebt_dragState.draggingIcon = self
        _ebt_dragState.sourceCluster = ci
        self:StartMoving()
        self:SetAlpha(0.6)
    end)

    -- Right-click in free-position mode: select icon for arrow-key nudging
    icon:SetScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" then return end
        if InCombatLockdown() then return end
        local s = MyEssentialBuffTracker:GetSettings()
        if not s or not s.clusterUnlocked then return end
        local ci = self._ebtDragCluster or clusterIndex
        if not (s.clusterFreePositionModes and s.clusterFreePositionModes[ci]) then return end
        -- Toggle: right-click selected icon again to deselect
        if _ebt_freePosSelected == self then
            EBTFreePosDeselect()
        else
            EBTFreePosSelect(self, viewer)
        end
    end)

    icon:SetScript("OnDragStop", function(self)
        if InCombatLockdown() then return end
        self:StopMovingOrSizing()
        self:SetAlpha(1.0)

        if _ebt_dragState.draggingIcon ~= self then return end

        local s = MyEssentialBuffTracker:GetSettings()
        local iconKey = GetEssentialIconKey(self)
        if not s or not iconKey then
            _ebt_dragState.draggingIcon = nil
            _ebt_dragState.sourceCluster = nil
            pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
            return
        end

        local keyStr = tostring(iconKey)
        local sourceCluster = tonumber(_ebt_dragState.sourceCluster) or 1
        local clusterCount = math.max(1, math.min(MAX_EBT_CLUSTER_GROUPS, SafeNumber(s.clusterCount, DEFAULTS.clusterCount) or DEFAULTS.clusterCount))

        -- Free position mode: save offset from cluster anchor, re-anchor directly (no layout pass)
        if s.clusterFreePositionModes and s.clusterFreePositionModes[sourceCluster] then
            local vm = GetViewerMeta(viewer)
            local anchor = vm.clusterAnchors and vm.clusterAnchors[sourceCluster]
            if anchor then
                local ix, iy = self:GetCenter()
                local ax, ay = anchor:GetCenter()
                if ix and iy and ax and ay then
                    local offsetX = ix - ax
                    local offsetY = iy - ay
                    s.clusterIconFreePositions = s.clusterIconFreePositions or {}
                    s.clusterIconFreePositions[sourceCluster] = s.clusterIconFreePositions[sourceCluster] or {}
                    s.clusterIconFreePositions[sourceCluster][keyStr] = { x = offsetX, y = offsetY }
                    self:ClearAllPoints()
                    self:SetPoint("CENTER", anchor, "CENTER", offsetX, offsetY)
                end
            end
            _ebt_dragState.draggingIcon = nil
            _ebt_dragState.sourceCluster = nil
            return
        end

        local uiScale = UIParent and UIParent:GetEffectiveScale() or 1
        local mx, my = GetCursorPosition()
        mx = mx / uiScale
        my = my / uiScale

        local vm = GetViewerMeta(viewer)
        local targetCluster, _ = FindEBTClusterForCursor(vm, clusterCount, mx, my)
        targetCluster = tonumber(targetCluster) or sourceCluster

        s.clusterAssignments = s.clusterAssignments or {}
        s.clusterAssignments[keyStr] = targetCluster

        RemoveKeyFromAllEBTClusterOrders(s, keyStr)
        local targetOrderList = GetEBTClusterManualOrder(s, targetCluster)
        local targetKey = FindEBTNearestKeyInCluster(vm, targetCluster, self, mx, my)

        if targetKey then
            local inserted = false
            for idx, existing in ipairs(targetOrderList) do
                if tostring(existing) == targetKey then
                    table.insert(targetOrderList, idx, keyStr)
                    inserted = true
                    break
                end
            end
            if not inserted then
                table.insert(targetOrderList, keyStr)
            end
        else
            table.insert(targetOrderList, keyStr)
        end

        _ebt_dragState.draggingIcon = nil
        _ebt_dragState.sourceCluster = nil
        pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
    end)
end

-- Apply drag handlers to all cluster icons when unlocked
local function ApplyEBTClusterIconDragHandlers(viewer, settings, clusterCount, groupedIcons)
    if not viewer or not settings.clusterUnlocked then return end
    if InCombatLockdown() then return end

    for ci = 1, clusterCount do
        local icons = groupedIcons and groupedIcons[ci]
        if type(icons) == "table" then
            for _, child in ipairs(icons) do
                if child and (child.Icon or child.icon) then
                    if child._ebtDragCluster ~= ci then
                        child._ebtDragCluster = ci
                        pcall(SetupEBTClusterIconDrag, child, viewer, ci)
                    end
                end
            end
        end
    end
end

-- Cluster drag state management
local function ApplyEBTClusterDragState(viewer, settings, forceNow)
    if not viewer then return end
    if InCombatLockdown() and not forceNow then return end
    local vm = GetViewerMeta(viewer)
    if not vm.clusterAnchors then return end
    local clusterCount = math.max(1, math.min(MAX_EBT_CLUSTER_GROUPS, SafeNumber(settings.clusterCount, DEFAULTS.clusterCount)))

    for i = 1, MAX_EBT_CLUSTER_GROUPS do
        local anchor = vm.clusterAnchors[i]
        if anchor then
            local inRange = (i <= clusterCount)
            local enabled = settings.clusterUnlocked and inRange
            local sampleMode = string.lower(tostring((settings.clusterSampleDisplayModes and settings.clusterSampleDisplayModes[i]) or "off"))
            local showForSamples = inRange and (sampleMode == "always")

            if enabled then
                anchor:Show()
                anchor:EnableMouse(true)
                anchor:SetBackdropColor(0, 0, 0, 0.3)
                anchor:SetBackdropBorderColor(0.2, 0.8, 0.4, 0.9)
            elseif showForSamples then
                anchor:Show()
                anchor:EnableMouse(false)
                anchor:SetBackdropColor(0, 0, 0, 0.05)
                anchor:SetBackdropBorderColor(0.2, 0.8, 0.4, 0.3)
            else
                anchor:Hide()
            end
        end
    end
end

-- Context menu for Essential cluster anchors
local ebtClusterContextMenu = CreateFrame("Frame", "EBTClusterContextMenu", UIParent, "UIDropDownMenuTemplate")

local _EBTEasyMenu = EasyMenu or function(menuList, menuFrame, anchor, x, y, displayMode)
    UIDropDownMenu_Initialize(menuFrame, function(self, level)
        for _, info in ipairs(menuList) do
            local btn = UIDropDownMenu_CreateInfo()
            btn.text = info.text
            btn.isTitle = info.isTitle
            btn.notCheckable = info.notCheckable
            btn.isNotRadio = info.isNotRadio
            btn.keepShownOnClick = info.keepShownOnClick
            btn.icon = info.icon
            btn.func = info.func
            if info.checked ~= nil then
                if type(info.checked) == "function" then
                    btn.checked = info.checked()
                else
                    btn.checked = info.checked
                end
            end
            UIDropDownMenu_AddButton(btn, level or 1)
        end
    end, displayMode)
    ToggleDropDownMenu(1, nil, menuFrame, anchor, x, y)
end

function ShowEBTClusterContextMenu(anchor, settings, clusterIndex)
    local menuList = {}
    table.insert(menuList, { text = "Always Show Spells:", isTitle = true, notCheckable = true })

    settings.clusterAlwaysShowSpells = settings.clusterAlwaysShowSpells or {}
    local spellsInCluster = {}
    for spellKey, ci in pairs(settings.clusterAssignments or {}) do
        if tonumber(ci) == clusterIndex then
            local id = tonumber(spellKey)
            local name = id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) or ("Spell " .. tostring(spellKey))
            local tex = id and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id) or nil
            table.insert(spellsInCluster, { key = tostring(spellKey), name = name, icon = tex })
        end
    end
    table.sort(spellsInCluster, function(a, b) return (a.name or "") < (b.name or "") end)

    if #spellsInCluster == 0 then
        table.insert(menuList, { text = "(no spells assigned yet)", isTitle = true, notCheckable = true })
    else
        for _, spell in ipairs(spellsInCluster) do
            table.insert(menuList, {
                text = spell.name,
                icon = spell.icon,
                isNotRadio = true,
                keepShownOnClick = true,
                checked = function() return settings.clusterAlwaysShowSpells[spell.key] end,
                func = function()
                    if settings.clusterAlwaysShowSpells[spell.key] then
                        settings.clusterAlwaysShowSpells[spell.key] = nil
                    else
                        settings.clusterAlwaysShowSpells[spell.key] = true
                    end
                    local viewer = _G["EssentialCooldownViewer"]
                    if viewer then
                        pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
                    end
                end,
            })
        end
    end

    table.insert(menuList, { text = "", isTitle = true, notCheckable = true })
    table.insert(menuList, { text = "Close", notCheckable = true, func = function() CloseDropDownMenus() end })

    _EBTEasyMenu(menuList, ebtClusterContextMenu, "cursor", 0, 0, "MENU")
end

-- Drag-and-drop logic for icons to assign to clusters
function MyEssentialBuffTracker:ApplyIconDragState()
    local settings = self:GetSettings()
    local viewer = _G["EssentialCooldownViewer"]
    if not viewer then return end
    local container = viewer.viewerFrame or viewer

    -- If unlock mode is enabled, force show the viewer and all icons
    if settings.iconDragUnlock then
        viewer:Show()
        container:Show()
    end

    local children = {container:GetChildren()}
    if #children == 0 then return end

    -- Get or create cluster anchors
    local clusterAnchors = {}
    for i = 1, (settings.clusterCount or 5) do
        clusterAnchors[i] = EnsureEBTClusterAnchorForIndex(viewer, settings, i)
        clusterAnchors[i]:Show()
    end

    for _, icon in ipairs(children) do
        if icon and icon.Icon then
            if settings.iconDragUnlock then
                icon:Show()
                icon:SetMovable(true)
                icon:EnableMouse(true)
                icon:RegisterForDrag("LeftButton")
                icon:SetScript("OnDragStart", icon.StartMoving)
                icon:SetScript("OnDragStop", function(self)
                    self:StopMovingOrSizing()
                    local iconKey = GetEssentialIconKey(self)
                    if iconKey then
                        for idx, anchor in ipairs(clusterAnchors) do
                            if anchor:IsMouseOver() then
                                settings.clusterAssignments = settings.clusterAssignments or {}
                                settings.clusterAssignments[tostring(iconKey)] = idx
                                break
                            end
                        end
                    end
                    -- Snap icon back to layout after assignment
                    MyEssentialIconViewers:ApplyViewerLayout(viewer)
                end)
            else
                icon:SetMovable(false)
                icon:EnableMouse(false)
                icon:RegisterForDrag()
                icon:SetScript("OnDragStart", nil)
                icon:SetScript("OnDragStop", nil)
            end
        end
    end

    -- Hide anchors if not unlocked
    if not settings.iconDragUnlock then
        for _, anchor in ipairs(clusterAnchors) do anchor:Hide() end
    end
end

-- ---------------------------
-- ApplyViewerLayout (layout + skinning)
-- ---------------------------
function MyEssentialIconViewers:ApplyViewerLayout(viewer)
    if not viewer or not viewer.GetName then return end
    if not viewer:IsShown() then return end

    local settings = MyEssentialBuffTracker:GetSettings()
    local container = viewer.viewerFrame or viewer

    local icons = _ebt_icons
    wipe(icons)
    -- Use pool iterator when available (zero-allocation), fallback to GetChildren
    local pool = viewer.itemFramePool
    if pool then
        for child in pool:EnumerateActive() do
            if child and child.Icon then
                icons[#icons + 1] = child
            end
        end
    else
        for i = 1, select("#", container:GetChildren()) do
            local child = select(i, container:GetChildren())
            if child and child.Icon then
                icons[#icons + 1] = child
            end
        end
    end
    if #icons == 0 then
        GetViewerMeta(viewer).lastNumRows = 0
        return
    end

    for i, icon in ipairs(icons) do
        local im = GetIconMeta(icon)
        im.creationOrder = im.creationOrder or i
    end
    table.sort(icons, _ebt_iconSortComparator)

    -- Auto-detect skin settings change via fingerprint
    local skinFP = GetEBTSkinFingerprint(settings)
    if skinFP ~= _ebt_lastSkinFingerprint then
        _ebt_lastSkinFingerprint = skinFP
        _ebt_skinVersion = _ebt_skinVersion + 1
    end

    local inCombat = InCombatLockdown()
    for _, icon in ipairs(icons) do
        local im = GetIconMeta(icon)
        if im._ebt_skinVer ~= _ebt_skinVersion and not im.skinPending then
            im.skinPending = true
            if inCombat then
                EnsurePendingEventFrame()
                MyEssentialIconViewers.__pendingIcons[icon] = { icon=icon, settings=settings, viewer=viewer }
                MyEssentialIconViewers.__iconSkinEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            else
                pcall(MyEssentialIconViewers.SkinIcon, MyEssentialIconViewers, icon, settings)
                im.skinPending = nil
            end
        end
    end

    -- Always wipe position caches: Blizzard's GridLayout/EditMode can reposition
    -- icons between dispatches, making our cached targets stale. SetPoint calls
    -- are cheap (~18 icons), the real CPU savings come from the skin fingerprint.
    for _, icon in ipairs(icons) do
        local cm = GetIconMeta(icon)
        cm.lastX = nil
        cm.lastY = nil
        cm.lastSizeW = nil
        cm.lastSizeH = nil
    end

    local shownIcons = _ebt_shownIcons
    wipe(shownIcons)
    for _, icon in ipairs(icons) do
        if icon:IsShown() then shownIcons[#shownIcons + 1] = icon end
    end

    -- Merge external icons from the registry
    if MyEssentialBuffTracker._externalIcons then
        for extFrame in pairs(MyEssentialBuffTracker._externalIcons) do
            if extFrame and extFrame:IsShown() and (extFrame.Icon or extFrame.icon) then
                local em = GetIconMeta(extFrame)
                em.lastX = nil
                em.lastY = nil
                em.lastSizeW = nil
                em.lastSizeH = nil
                em.creationOrder = em.creationOrder or 99999
                em.isExternal = true
                shownIcons[#shownIcons + 1] = extFrame
            end
        end
        table.sort(shownIcons, _ebt_iconSortComparator)
    end

    if #shownIcons == 0 then
        GetViewerMeta(viewer).lastNumRows = 0
        return
    end

    local iconSize = SafeNumber(settings.iconSize, DEFAULTS.iconSize)

    -- Default base size
    for _, icon in ipairs(shownIcons) do
        local im = GetIconMeta(icon)
        if im.lastSizeW ~= iconSize or im.lastSizeH ~= iconSize then
            icon:SetSize(iconSize, iconSize)
            im.lastSizeW = iconSize
            im.lastSizeH = iconSize
        end
    end

    local iconWidth, iconHeight = iconSize, iconSize
    local spacing = settings.spacing or DEFAULTS.spacing

    -- ===========================
    -- CLUSTER MODE
    -- ===========================
    if settings.multiClusterMode then
        local clusterCount = math.max(1, math.min(MAX_EBT_CLUSTER_GROUPS, SafeNumber(settings.clusterCount, DEFAULTS.clusterCount) or DEFAULTS.clusterCount))
        settings.clusterCount = clusterCount
        settings.clusterFlows = settings.clusterFlows or {}
        settings.clusterVerticalGrows = settings.clusterVerticalGrows or {}
        settings.clusterVerticalPins = settings.clusterVerticalPins or {}
        settings.clusterIconSizes = settings.clusterIconSizes or {}
        settings.clusterSampleDisplayModes = settings.clusterSampleDisplayModes or {}
        settings.clusterAssignments = settings.clusterAssignments or {}
        settings.clusterManualOrders = settings.clusterManualOrders or {}
        if settings.clusterCenterIcons == nil then settings.clusterCenterIcons = DEFAULTS.clusterCenterIcons end
        local centerClusterIcons = settings.clusterCenterIcons ~= false

        local groupedIcons = {}
        for i = 1, clusterCount do
            groupedIcons[i] = {}
            EnsureEBTClusterAnchorForIndex(viewer, settings, i)
        end

        -- Hide excess anchors
        local vm = GetViewerMeta(viewer)
        if vm.clusterAnchors then
            for i = clusterCount + 1, MAX_EBT_CLUSTER_GROUPS do
                local anchor = vm.clusterAnchors[i]
                if anchor then anchor:Hide() end
            end
        end

        -- Assign icons to clusters
        for _, icon in ipairs(shownIcons) do
            local key = GetEssentialIconKey(icon)
            local assignedGroup = tonumber(key and settings.clusterAssignments[tostring(key)]) or 1
            if assignedGroup < 1 or assignedGroup > clusterCount then
                assignedGroup = 1
            end
            table.insert(groupedIcons[assignedGroup], icon)
        end

        -- Inject persistent "always show" icons
        settings.clusterAlwaysShowSpells = settings.clusterAlwaysShowSpells or {}
        local _ebt_activeRealKeys = {}
        for ci = 1, clusterCount do
            for _, icon in ipairs(groupedIcons[ci]) do
                local key = GetEssentialIconKey(icon)
                if key then _ebt_activeRealKeys[tostring(key)] = true end
            end
        end
        local anyPersistentIcon = false
        for spellKey, enabled in pairs(settings.clusterAlwaysShowSpells) do
            if enabled and not _ebt_activeRealKeys[tostring(spellKey)] then
                local ci = tonumber(settings.clusterAssignments[tostring(spellKey)]) or 1
                if ci >= 1 and ci <= clusterCount then
                    local pIcon = GetOrCreateEBTPersistentIcon(spellKey)
                    pIcon:Show()
                    local iconState = GetIconMeta(pIcon)
                    if not iconState.creationOrder then iconState.creationOrder = 99998 end
                    iconState.skinned = true
                    pIcon._isPersistentIcon = true
                    table.insert(groupedIcons[ci], pIcon)
                    anyPersistentIcon = true
                end
            end
        end
        -- Hide persistent icons whose spell now has a real icon
        for key, frame in pairs(_ebt_persistentIcons) do
            if not settings.clusterAlwaysShowSpells[key] or _ebt_activeRealKeys[key] then
                frame:Hide()
            end
        end
        if anyPersistentIcon then
            _ebt_persistentUpdateFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
            ScheduleEBTPersistentDuplicateUpdate(true)
        end

        -- Build lookup of real icons for duplicate source linking
        local _ebt_realIconByKey = {}
        for ci = 1, clusterCount do
            for _, icon in ipairs(groupedIcons[ci]) do
                if not icon._isDuplicateIcon and not icon._isPersistentIcon then
                    local key = GetEssentialIconKey(icon)
                    if key and not _ebt_realIconByKey[tostring(key)] then
                        _ebt_realIconByKey[tostring(key)] = icon
                    end
                end
            end
        end

        -- Inject duplicate icons
        settings.clusterDuplicates = settings.clusterDuplicates or {}
        local anyDuplicateIcon = false
        local _ebt_activeDupKeys = {}
        for spellKey, dupClusters in pairs(settings.clusterDuplicates) do
            if type(dupClusters) == "table" then
                local sourceIcon = _ebt_realIconByKey[tostring(spellKey)]
                if sourceIcon and sourceIcon:IsShown() then
                    HookEBTSourceIconForDuplicates(sourceIcon)
                    for ci, enabled in pairs(dupClusters) do
                        ci = tonumber(ci)
                        if enabled and ci and ci >= 1 and ci <= clusterCount then
                            local dupIcon = GetOrCreateEBTDuplicateIcon(spellKey, ci)
                            dupIcon._sourceIcon = sourceIcon
                            dupIcon:Show()
                            local iconState = GetIconMeta(dupIcon)
                            if not iconState.creationOrder then iconState.creationOrder = 99997 end
                            iconState.skinned = true
                            dupIcon._isDuplicateIcon = true
                            table.insert(groupedIcons[ci], dupIcon)
                            anyDuplicateIcon = true
                            _ebt_activeDupKeys[tostring(spellKey) .. "_dup_" .. tostring(ci)] = true
                        end
                    end
                end
            end
        end
        -- Hide unused duplicate icons
        for cacheKey, frame in pairs(_ebt_duplicateIcons) do
            if not _ebt_activeDupKeys[cacheKey] then
                frame:Hide()
            end
        end
        if anyDuplicateIcon then
            _ebt_persistentUpdateFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
            ScheduleEBTPersistentDuplicateUpdate(true)
        end

        local rowLimit = SafeNumber(settings.rowLimit or settings.columns, DEFAULTS.rowLimit)
        local availableKeys = BuildEBTAvailableKeySet(viewer)

        -- Sort each group using manual order
        local orderIndexByCluster = {}
        for i = 1, clusterCount do
            orderIndexByCluster[i] = {}
            local orderedKeys = BuildEBTOrderedKeysForCluster(settings, i, availableKeys)
            for idx, key in ipairs(orderedKeys) do
                orderIndexByCluster[i][tostring(key)] = idx
            end

            table.sort(groupedIcons[i], function(a, b)
                local keyA = GetEssentialIconKey(a)
                local keyB = GetEssentialIconKey(b)
                local posA = keyA and orderIndexByCluster[i][tostring(keyA)] or nil
                local posB = keyB and orderIndexByCluster[i][tostring(keyB)] or nil
                if posA and posB and posA ~= posB then return posA < posB end
                if posA and not posB then return true end
                if posB and not posA then return false end
                local aOrder = (ebtIconMeta[a] and ebtIconMeta[a].creationOrder) or 0
                local bOrder = (ebtIconMeta[b] and ebtIconMeta[b].creationOrder) or 0
                return aOrder < bOrder
            end)
        end

        -- Keep real icon layout active while unlocked so drag/drop can reorder live icons.
        RenderEBTClusterSampleIcons(viewer, settings, clusterCount, rowLimit, iconSize, spacing, {
            unlockPreview = false,
            availableKeys = availableKeys,
        })

        -- Position icons inside each cluster anchor
        local totalVisibleIcons = 0
        for groupIndex = 1, clusterCount do
            local anchor = vm.clusterAnchors and vm.clusterAnchors[groupIndex]
            local groupIcons = groupedIcons[groupIndex]
            if anchor and groupIcons then
                local clusterFlow = string.lower(tostring(settings.clusterFlows[groupIndex] or settings.clusterFlow or DEFAULTS.clusterFlow))
                local verticalGrow = string.lower(tostring(settings.clusterVerticalGrows[groupIndex] or "down"))
                local verticalPin = string.lower(tostring(settings.clusterVerticalPins[groupIndex] or "center"))
                local clusterIconSize = SafeNumber(settings.clusterIconSizes[groupIndex], iconSize)
                if clusterFlow ~= "vertical" then clusterFlow = "horizontal" end
                if verticalGrow ~= "up" then verticalGrow = "down" end
                if verticalPin ~= "top" and verticalPin ~= "bottom" then verticalPin = "center" end

                local sampleMode = string.lower(tostring((settings.clusterSampleDisplayModes and settings.clusterSampleDisplayModes[groupIndex]) or "off"))
                local followSampleSlots = (sampleMode == "always") or (not centerClusterIcons)

                local sampleKeys = {}
                local slotByKey = {}
                if followSampleSlots then
                    sampleKeys = BuildEBTOrderedKeysForCluster(settings, groupIndex, availableKeys)
                    for idx, key in ipairs(sampleKeys) do
                        slotByKey[key] = idx
                    end
                end

                local groupCount = #groupIcons
                totalVisibleIcons = totalVisibleIcons + groupCount
                local anchorWidth = anchor:GetWidth() or 120
                local anchorHeight = anchor:GetHeight() or 120

                if groupCount > 0 then
                    -- Free position mode: place each icon at its saved position relative to anchor center
                    local freeMode = settings.clusterFreePositionModes and settings.clusterFreePositionModes[groupIndex]
                    if freeMode then
                        local savedPos = (settings.clusterIconFreePositions and settings.clusterIconFreePositions[groupIndex]) or {}
                        for idx, icon in ipairs(groupIcons) do
                            icon:SetSize(clusterIconSize, clusterIconSize)
                            icon:ClearAllPoints()
                            local iconKey = GetEssentialIconKey(icon)
                            local keyStr = iconKey and tostring(iconKey) or ("_idx_" .. idx)
                            local pos = savedPos[keyStr]
                            if pos then
                                icon:SetPoint("CENTER", anchor, "CENTER", pos.x or 0, pos.y or 0)
                            else
                                -- Fallback grid until user drags icon into place
                                local col = (idx - 1) % 3
                                local row_i = math.floor((idx - 1) / 3)
                                icon:SetPoint("CENTER", anchor, "CENTER",
                                    (col - 1) * (clusterIconSize + spacing),
                                    -row_i * (clusterIconSize + spacing))
                            end
                        end
                    else
                    local iconPlacements = {}
                    local maxPlacement = groupCount
                    if followSampleSlots then
                        maxPlacement = 0
                        local usedPlacements = {}
                        for idx, icon in ipairs(groupIcons) do
                            local key = GetEssentialIconKey(icon)
                            local placement = key and slotByKey[tostring(key)] or nil
                            if placement and usedPlacements[placement] then placement = nil end
                            if not placement then
                                placement = 1
                                while usedPlacements[placement] do placement = placement + 1 end
                            end
                            usedPlacements[placement] = true
                            iconPlacements[idx] = placement
                            if placement > maxPlacement then maxPlacement = placement end
                        end
                        if #sampleKeys > maxPlacement then maxPlacement = #sampleKeys end
                    else
                        for idx = 1, groupCount do iconPlacements[idx] = idx end
                    end

                    local layoutCount = math.max(groupCount, maxPlacement)
                    local lineSize = layoutCount
                    local lineCount = 1
                    if rowLimit and rowLimit > 0 then
                        lineSize = math.max(1, rowLimit)
                        lineCount = math.ceil(layoutCount / lineSize)
                    end

                    local columns, rows
                    if clusterFlow == "vertical" then
                        rows = math.min(layoutCount, lineSize)
                        columns = lineCount
                    else
                        columns = math.min(layoutCount, lineSize)
                        rows = lineCount
                    end

                    local yBase = -15 - (clusterIconSize / 2)
                    if clusterFlow == "vertical" then
                        if verticalPin == "top" then
                            yBase = anchorHeight - 5 - (clusterIconSize / 2)
                        elseif verticalPin == "bottom" then
                            yBase = 5 + (clusterIconSize / 2)
                        else
                            yBase = anchorHeight / 2
                        end
                    end

                    -- Pre-compute icons per row for per-row centering
                    local iconsPerRow = {}
                    local rowSeqCol = {}  -- per-row sequential column counter
                    for idx2 = 1, groupCount do
                        local pi = iconPlacements[idx2] or idx2
                        local ri
                        if clusterFlow == "vertical" then
                            ri = math.floor((pi - 1) / lineSize)
                        else
                            ri = math.floor((pi - 1) / lineSize)
                        end
                        iconsPerRow[ri] = (iconsPerRow[ri] or 0) + 1
                    end

                    local rowColCounter = {}
                    for idx, icon in ipairs(groupIcons) do
                        local placementIndex = iconPlacements[idx] or idx
                        local rowIndex, colIndex
                        if clusterFlow == "vertical" then
                            rowIndex = (placementIndex - 1) % lineSize
                            colIndex = math.floor((placementIndex - 1) / lineSize)
                        else
                            rowIndex = math.floor((placementIndex - 1) / lineSize)
                            -- Use sequential per-row column for centering
                            rowColCounter[rowIndex] = (rowColCounter[rowIndex] or 0)
                            colIndex = rowColCounter[rowIndex]
                            rowColCounter[rowIndex] = rowColCounter[rowIndex] + 1
                        end

                        icon:SetSize(clusterIconSize, clusterIconSize)
                        icon:ClearAllPoints()

                        if clusterFlow == "vertical" then
                            local x = 5 + (clusterIconSize / 2) + colIndex * (clusterIconSize + spacing)
                            local y
                            if verticalPin == "center" then
                                y = yBase + rowIndex * (clusterIconSize + spacing)
                            elseif verticalGrow == "up" then
                                y = yBase + rowIndex * (clusterIconSize + spacing)
                            else
                                y = yBase - rowIndex * (clusterIconSize + spacing)
                            end
                            icon:SetPoint("CENTER", anchor, "BOTTOMLEFT", x, y)
                        else
                            if centerClusterIcons then
                                local rowCols = iconsPerRow[rowIndex] or columns
                                local rowWidth = rowCols * clusterIconSize + (rowCols - 1) * spacing
                                local groupHeight = rows * clusterIconSize + (rows - 1) * spacing
                                local x = -rowWidth / 2 + clusterIconSize / 2 + colIndex * (clusterIconSize + spacing)
                                local y = groupHeight / 2 - clusterIconSize / 2 - rowIndex * (clusterIconSize + spacing)
                                icon:SetPoint("CENTER", anchor, "CENTER", x, y)
                            else
                                local x = 5 + (clusterIconSize / 2) + colIndex * (clusterIconSize + spacing)
                                local y = (anchorHeight - 5) - (clusterIconSize / 2) - rowIndex * (clusterIconSize + spacing)
                                icon:SetPoint("CENTER", anchor, "BOTTOMLEFT", x, y)
                            end
                        end
                    end -- for loop (normal layout)
                    end -- if freeMode else end
                end -- if groupCount > 0
            end
        end

        vm.clusterIconsByIndex = groupedIcons
        ApplyEBTClusterDragState(viewer, settings)
        ApplyEBTClusterIconDragHandlers(viewer, settings, clusterCount, groupedIcons)
        GetViewerMeta(viewer).lastNumRows = 1
        GetViewerMeta(viewer).iconCount = totalVisibleIcons
        -- Shrink viewer itself â€” icons live on cluster anchors now
        if not InCombatLockdown() then viewer:SetSize(2, 2) end
        return
    else
        -- Non-cluster mode: hide cluster artifacts
        HideEBTClusterSampleIcons(viewer)
        HideAllEBTPersistentIcons()
        HideAllEBTDuplicateIcons()
        local vm = GetViewerMeta(viewer)
        if vm.clusterAnchors then
            for i = 1, MAX_EBT_CLUSTER_GROUPS do
                local anchor = vm.clusterAnchors[i]
                if anchor then anchor:Hide() end
            end
        end
    end

    -- Static Grid Mode (per-row size does NOT affect static grid)
    if settings.staticGridMode then
        local gridRows = SafeNumber(settings.gridRows, DEFAULTS.gridRows)
        local gridCols = SafeNumber(settings.gridColumns, DEFAULTS.gridColumns)
        local totalWidth = gridCols * iconWidth + (gridCols - 1) * spacing
        local totalHeight = gridRows * iconHeight + (gridRows - 1) * spacing

        settings.gridSlotMap = settings.gridSlotMap or {}

        local usedSlots = {}
        for _, icon in ipairs(shownIcons) do
            local iconID = icon.spellID or icon.auraInstanceID or icon:GetID() or (ebtIconMeta[icon] and ebtIconMeta[icon].creationOrder)
            local key = tostring(iconID)
            if settings.gridSlotMap[key] then usedSlots[settings.gridSlotMap[key]] = true end
        end

        local nextSlot = 1
        for _, icon in ipairs(shownIcons) do
            local iconID = icon.spellID or icon.auraInstanceID or icon:GetID() or (ebtIconMeta[icon] and ebtIconMeta[icon].creationOrder)
            local key = tostring(iconID)
            if not settings.gridSlotMap[key] then
                while usedSlots[nextSlot] do nextSlot = nextSlot + 1 end
                settings.gridSlotMap[key] = nextSlot
                usedSlots[nextSlot] = true
                nextSlot = nextSlot + 1
            end
        end

        for _, icon in ipairs(shownIcons) do
            local iconID = icon.spellID or icon.auraInstanceID or icon:GetID() or (ebtIconMeta[icon] and ebtIconMeta[icon].creationOrder)
            local key = tostring(iconID)
            local slotNum = settings.gridSlotMap[key]
            if slotNum then
                local row = math.floor((slotNum - 1) / gridCols)
                local col = (slotNum - 1) % gridCols
                local x = -totalWidth / 2 + iconWidth / 2 + col * (iconWidth + spacing)
                local y = -totalHeight / 2 + iconHeight / 2 + row * (iconHeight + spacing)
                local im = GetIconMeta(icon)
                if im.lastX ~= x or im.lastY ~= y then
                    icon:ClearAllPoints()
                    icon:SetPoint("TOPLEFT", container, "TOPLEFT", x, y)
                    im.lastX = x
                    im.lastY = y
                end
            end
        end

        GetViewerMeta(viewer).lastNumRows = gridRows

        if not InCombatLockdown() then viewer:SetSize(totalWidth, totalHeight) end
        return
    end

    -- Dynamic mode
    local rowLimit = SafeNumber(settings.rowLimit or settings.columns, DEFAULTS.rowLimit)

    -- Single-row mode
    if rowLimit <= 0 then
        local rowSize = (settings.rowSizes and settings.rowSizes[1]) or iconSize
        for _, icon in ipairs(shownIcons) do
            local im = GetIconMeta(icon)
            if im.lastSizeW ~= rowSize or im.lastSizeH ~= rowSize then
                icon:SetSize(rowSize, rowSize)
                im.lastSizeW = rowSize
                im.lastSizeH = rowSize
            end
        end
        local totalWidth = #shownIcons * rowSize + (#shownIcons - 1) * spacing
        local startX = -totalWidth / 2 + rowSize / 2
        for i, icon in ipairs(shownIcons) do
            local x = startX + (i-1)*(rowSize+spacing)
            local im = GetIconMeta(icon)
            if im.lastX ~= x or im.lastY ~= 0 then
                icon:ClearAllPoints()
                icon:SetPoint("TOPLEFT", container, "TOPLEFT", x, 0)
                im.lastX = x
                im.lastY = 0
            end
        end
        GetViewerMeta(viewer).lastNumRows = 1
        if not InCombatLockdown() then
            viewer:SetSize(totalWidth, rowSize)
        end
    else
        -- Multi-row mode with per-row size
        local numRows = math.ceil(#shownIcons/rowLimit)
        local rows = _ebt_rows
        local maxRowWidth = 0

        for r = 1, numRows do
            if not rows[r] then rows[r] = {} else wipe(rows[r]) end
            local startIdx = (r-1)*rowLimit + 1
            local endIdx = math.min(r*rowLimit, #shownIcons)
            for i=startIdx,endIdx do rows[r][#rows[r] + 1] = shownIcons[i] end
        end
        -- Clear any stale rows from previous call with more rows
        for r = numRows + 1, #rows do wipe(rows[r]) end

        local growDir = (settings.rowGrowDirection or DEFAULTS.rowGrowDirection):lower()

        local y = 0
        local cumulativeOffset = 0
        for r = 1, numRows do
            local row = rows[r]
            local rowSize = (settings.rowSizes and settings.rowSizes[r]) or iconSize
            local w = rowSize
            local h = rowSize
            local rowOffset = (settings.rowOffsets and settings.rowOffsets[r]) or 0
            cumulativeOffset = cumulativeOffset + rowOffset

            local rowWidth = #row * w + (#row - 1) * spacing
            if rowWidth > maxRowWidth then maxRowWidth = rowWidth end

            -- Center row horizontally at the TOP of the container
            local startX = -rowWidth/2 + w/2

            for i, icon in ipairs(row) do
                local x = startX + (i-1)*(w+spacing)
                local yPos = -(y + cumulativeOffset)
                local im = GetIconMeta(icon)
                if im.lastSizeW ~= w or im.lastSizeH ~= h then
                    icon:SetSize(w, h)
                    im.lastSizeW = w
                    im.lastSizeH = h
                end
                if im.lastX ~= x or im.lastY ~= yPos then
                    icon:ClearAllPoints()
                    icon:SetPoint("TOP", container, "TOP", x, yPos)
                    im.lastX = x
                    im.lastY = yPos
                end
            end
            y = y + h + 1 -- move down by icon height + 1 pixel for next row
        end

        local totalHeight = y - 1 -- last row doesn't need extra pixel

        GetViewerMeta(viewer).lastNumRows = numRows

        if not InCombatLockdown() then
            viewer:SetSize(maxRowWidth, totalHeight)
        end
    end
    GetViewerMeta(viewer).iconCount = #shownIcons
end

function MyEssentialIconViewers:RescanViewer(viewer)
    if not viewer or not viewer.GetName then return end
    MyEssentialIconViewers:ApplyViewerLayout(viewer)
end

MyEssentialBuffTracker = MyEssentialBuffTracker or {}
MyEssentialBuffTracker.IconViewers = MyEssentialIconViewers
-- ---------------------------
-- Robust event-driven viewer update logic
-- ---------------------------
local function IsCooldownIconFrame(frame)
    return frame and (frame.icon or frame.Icon) and frame.Cooldown
end

function MyEssentialIconViewers:ApplyViewerSkin(viewer)
    if not viewer or not viewer.GetName then return end
    local settings = MyEssentialBuffTracker:GetSettings()
    if not settings then return end

    if self.ApplyViewerLayout then
        self:ApplyViewerLayout(viewer)
    end
    if not InCombatLockdown() and next(self.__pendingIcons) then
        self:ProcessPendingIcons()
    end
end

function MyEssentialIconViewers:HookViewers()
    local viewers = {"EssentialCooldownViewer"}
    for _, name in ipairs(viewers) do
        local viewer = _G[name]
        local vm = GetViewerMeta(viewer)
        if viewer and not vm.hooked then
            vm.hooked = true

            viewer:HookScript("OnShow", function(f)
                MyEssentialIconViewers:ApplyViewerSkin(f)
            end)

            viewer:HookScript("OnSizeChanged", function(f)
                local fvm = ebtViewerMeta[f]
                if fvm and (fvm.layoutSuppressed or fvm.layoutRunning) then
                    return
                end
                if MyEssentialIconViewers.ApplyViewerLayout then
                    MyEssentialIconViewers:ApplyViewerLayout(f)
                end
            end)

            -- Show/hide dispatch for glow + pending icon processing (zero CPU when idle)
            local ebtDispatch = CreateFrame("Frame")
            ebtDispatch:RegisterEvent("SPELL_UPDATE_COOLDOWN")
            ebtDispatch:RegisterUnitEvent("UNIT_AURA", "player")
            ebtDispatch:RegisterEvent("PLAYER_REGEN_ENABLED")
            ebtDispatch._lastActiveCount = -1
            ebtDispatch._nextAllowed = 0
            ebtDispatch._timerPending = false

            local function ScheduleEBTDispatch(immediate)
                if ebtDispatch._timerPending then return end

                local now = GetTime()
                local delay = 0
                if not immediate and now < (ebtDispatch._nextAllowed or 0) then
                    delay = ebtDispatch._nextAllowed - now
                end

                ebtDispatch._timerPending = true
                C_Timer.After(delay, ebtDispatch._callback)
            end

            -- Pre-baked dispatch callback (avoids closure allocation ~6x/sec in combat)
            ebtDispatch._callback = function()
                    ebtDispatch._timerPending = false
                    ebtDispatch._nextAllowed = GetTime() + 0.15

                    -- Layout on icon count change only (or always in cluster mode)
                    local pool = viewer.itemFramePool
                    local layoutRan = false
                    if pool and not InCombatLockdown() then
                        local count = pool:GetNumActive()
                        local settings_now = MyEssentialBuffTracker:GetSettings()
                        local forceLayout = settings_now and settings_now.multiClusterMode
                        if count ~= ebtDispatch._lastActiveCount or forceLayout then
                            ebtDispatch._lastActiveCount = count
                            -- Enforce scale before layout
                            if _G.CkraigCooldownManager and _G.CkraigCooldownManager.EnforceCooldownViewerScale then
                                _G.CkraigCooldownManager.EnforceCooldownViewerScale(viewer)
                            end
                            pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
                            layoutRan = true
                        end
                    end

                    -- Pending icons (out of combat)
                    if not InCombatLockdown() and next(MyEssentialIconViewers.__pendingIcons) then
                        MyEssentialIconViewers:ProcessPendingIcons()
                    end

                    -- Enforce charge/cooldown text positions (only after layout ran)
                    if layoutRan and pool and pool:GetNumActive() > 0 then
                        for icon in pool:EnumerateActive() do
                            local im = GetIconMeta(icon)
                            if im.chargeTextRef then
                                im.chargeTextRef:ClearAllPoints()
                                im.chargeTextRef:SetPoint(im.chargeAnchor, icon, im.chargeAnchor, im.chargeOffX, im.chargeOffY)
                            end
                            if im.cdTextRef then
                                im.cdTextRef:ClearAllPoints()
                                im.cdTextRef:SetPoint(im.cdAnchor, icon, im.cdAnchor, im.cdOffX, im.cdOffY)
                            end
                        end
                    end

                    -- Glow + sound update
                    local settings = MyEssentialBuffTracker:GetSettings()
                    local spellGlows = settings and settings.spellGlows or {}
                    local spellSounds = settings and settings.spellSounds or {}
                    local soundRevision = GetSpellSoundsRevision_EBT(settings)
                    if spellSounds ~= ebtSoundCfgSource or soundRevision ~= ebtSoundCfgRevision then
                        RebuildEnabledSoundLookup_EBT(spellSounds)
                        ebtSoundCfgRevision = soundRevision
                    end
                    local hasSounds = InCombatLockdown() and next(ebtEnabledSoundLookup) ~= nil
                    if hasSounds then
                        for k in pairs(_ebt_activeSoundCfgByKey) do _ebt_activeSoundCfgByKey[k] = nil end
                        for k in pairs(_ebt_activeSoundModeByKey) do _ebt_activeSoundModeByKey[k] = nil end
                        for k in pairs(_ebt_activeSoundReadyByKey) do _ebt_activeSoundReadyByKey[k] = nil end
                    end
                    local activeSoundCfgByKey = hasSounds and _ebt_activeSoundCfgByKey or nil
                    local activeSoundModeByKey = hasSounds and _ebt_activeSoundModeByKey or nil
                    local activeSoundReadyByKey = hasSounds and _ebt_activeSoundReadyByKey or nil
                    local hasGlows = next(spellGlows) ~= nil
                    local canGlow = (LCG and hasGlows)

                    -- Use Blizzard's itemFramePool (zero-allocation iterator)
                    local pool = viewer.itemFramePool
                    if pool and pool:GetNumActive() > 0 then
                        local inCombat = InCombatLockdown()
                        for icon in pool:EnumerateActive() do
                            if icon and (icon.Icon or icon.icon) then
                                HookCooldownTracking(icon)
                                local im = GetIconMeta(icon)
                                -- Only re-resolve key when the underlying ID changes
                                local curCdID = icon.cooldownID
                                local curAuraID = icon.auraInstanceID
                                if curCdID ~= im._lastCdID or curAuraID ~= im._lastAuraID then
                                    im._lastCdID = curCdID
                                    im._lastAuraID = curAuraID
                                    local freshKey = GetEssentialIconKey(icon)
                                    if freshKey then
                                        im.cachedKey = freshKey
                                        im.cachedKeyStr = tostring(freshKey)
                                    end
                                end

                                local key = im.cachedKey
                                if key then
                                    if canGlow then
                                    local glowCfg = spellGlows[key] or spellGlows[im.cachedKeyStr]
                                    local shouldGlow = false
                                    if glowCfg and glowCfg.enabled and icon:IsShown() then
                                        shouldGlow = IsIconReady(icon)
                                        -- Enhanced: also check C_Spell.IsSpellUsable for better readiness detection
                                        if shouldGlow and C_Spell and C_Spell.IsSpellUsable and key then
                                            local numKey = tonumber(key)
                                            if numKey then
                                                local usable = C_Spell.IsSpellUsable(numKey)
                                                if usable == false then
                                                    shouldGlow = false
                                                end
                                            end
                                        end
                                    end
                                    local glowType = glowCfg and glowCfg.glowType or "pixel"
                                    if shouldGlow then
                                        if not im.glowing or im.glowType ~= glowType then
                                            if im.glowing then
                                                StopGlow_EBT(icon)
                                            end
                                            local c = glowCfg.color
                                            ebtGlowColor[1] = c and c.r or 1
                                            ebtGlowColor[2] = c and c.g or 1
                                            ebtGlowColor[3] = c and c.b or 0
                                            ebtGlowColor[4] = c and c.a or 1
                                            if glowType == "autocast" then
                                                LCG.AutoCastGlow_Start(icon, ebtGlowColor, 4, 0.6, nil, 0, 0, "ebtGlow")
                                            elseif glowType == "button" then
                                                LCG.ButtonGlow_Start(icon, ebtGlowColor, 0.5)
                                            elseif glowType == "proc" then
                                                LCG.ProcGlow_Start(icon, ebtProcOpts)
                                            else
                                                LCG.PixelGlow_Start(icon, ebtGlowColor, 8, 0.25, nil, nil, 0, 0, false, "ebtGlow")
                                            end
                                            im.glowing = true
                                            im.glowType = glowType
                                        end
                                    else
                                        if im.glowing then
                                            StopGlow_EBT(icon)
                                            im.glowing = false
                                            im.glowType = nil
                                        end
                                    end
                                    elseif im.glowing then
                                        StopGlow_EBT(icon)
                                        im.glowing = false
                                        im.glowType = nil
                                    end

                                    if hasSounds and icon:IsShown() then
                                        local keyStr = im.cachedKeyStr or tostring(key)
                                        local soundCfg = ebtEnabledSoundLookup[keyStr]
                                        if soundCfg then
                                            local mode = tostring(soundCfg.mode or "ready")
                                            if mode == "show" then
                                                mode = "ready"
                                            elseif mode == "expire" then
                                                mode = "cooldown"
                                            end
                                            if mode ~= "ready" and mode ~= "cooldown" and mode ~= "both" then
                                                mode = "ready"
                                            end
                                            activeSoundCfgByKey[keyStr] = soundCfg
                                            activeSoundModeByKey[keyStr] = mode
                                            local isReady = IsReadyForSound_EBT(icon, key)
                                            if activeSoundReadyByKey[keyStr] == nil then
                                                activeSoundReadyByKey[keyStr] = isReady
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end

                    if hasSounds then
                        for keyStr, cfg in pairs(activeSoundCfgByKey) do
                            local mode = activeSoundModeByKey[keyStr] or "ready"
                            local prevReady = ebtSoundReadyPrevByKey[keyStr]
                            local curReady = activeSoundReadyByKey[keyStr] and true or false
                            if prevReady ~= nil then
                                local playOnReady = (mode == "ready" or mode == "both")
                                local playOnCooldown = (mode == "cooldown" or mode == "both")
                                if playOnReady and curReady and not prevReady then
                                    PlaySpellSound_EBT(keyStr, cfg)
                                elseif playOnCooldown and (not curReady) and prevReady then
                                    PlaySpellSound_EBT(keyStr, cfg)
                                end
                            end
                        end

                        ResetSoundState_EBT(false)
                        for keyStr, cfg in pairs(activeSoundCfgByKey) do
                            ebtSoundActivePrevByKey[keyStr] = true
                            ebtSoundPrevCfgByKey[keyStr] = cfg
                            ebtSoundPrevModeByKey[keyStr] = activeSoundModeByKey[keyStr] or "ready"
                            ebtSoundReadyPrevByKey[keyStr] = activeSoundReadyByKey[keyStr] and true or false
                        end
                    else
                        ResetSoundState_EBT(false)
                    end
            end

            -- ===========================
            -- Assisted Combat Highlight (blue rotation helper glow)
            -- Polls C_AssistedCombat.GetNextCastSpell() at Blizzard's rate and
            -- applies a blue PixelGlow on matching icons.  Separate glow key so it
            -- doesn't conflict with the per-spell glow system.
            -- ===========================
            local ebtAssistedTicker = nil
            local ebtAssistedLastSpellID = nil
            local EBT_ASSISTED_COLOR = { 0.3, 0.6, 1.0, 1.0 }

            local function EBTAssistedTick()
                local settings = MyEssentialBuffTracker:GetSettings()
                if not settings or not settings.assistedCombatHighlight then
                    if ebtAssistedLastSpellID ~= nil then
                        ebtAssistedLastSpellID = nil
                        local pool = viewer.itemFramePool
                        if pool and LCG then
                            for icon in pool:EnumerateActive() do
                                local im = GetIconMeta(icon)
                                if im.assistedGlowing then
                                    LCG.PixelGlow_Stop(icon, "ebtAssisted")
                                    im.assistedGlowing = false
                                end
                            end
                        end
                    end
                    return
                end
                if not C_AssistedCombat or not C_AssistedCombat.GetNextCastSpell then return end
                if not LCG then return end

                local nextSpellID = C_AssistedCombat.GetNextCastSpell(false)
                if nextSpellID == ebtAssistedLastSpellID then return end
                ebtAssistedLastSpellID = nextSpellID

                local pool = viewer.itemFramePool
                if not pool then return end

                for icon in pool:EnumerateActive() do
                    if icon and (icon.Icon or icon.icon) and icon:IsShown() then
                        local im = GetIconMeta(icon)
                        local key = im.cachedKey
                        if not key then
                            key = GetEssentialIconKey(icon)
                            if key then
                                im.cachedKey = key
                                im.cachedKeyStr = tostring(key)
                            end
                        end

                        local shouldHighlight = (nextSpellID ~= nil and key == nextSpellID)
                        if shouldHighlight and not im.assistedGlowing then
                            LCG.PixelGlow_Start(icon, EBT_ASSISTED_COLOR, 12, 0.25, 8, 2, 0, 0, false, "ebtAssisted")
                            im.assistedGlowing = true
                        elseif not shouldHighlight and im.assistedGlowing then
                            LCG.PixelGlow_Stop(icon, "ebtAssisted")
                            im.assistedGlowing = false
                        end
                    end
                end
            end

            local function StartEBTAssistedTicker()
                if ebtAssistedTicker then return end
                local rate = AssistedCombatManager and AssistedCombatManager:GetUpdateRate() or 0.2
                if rate < 0.1 then rate = 0.1 end
                ebtAssistedTicker = C_Timer.NewTicker(rate, EBTAssistedTick)
            end

            local function StopEBTAssistedTicker()
                if ebtAssistedTicker then
                    ebtAssistedTicker:Cancel()
                    ebtAssistedTicker = nil
                end
                -- Clear any lingering glows
                if ebtAssistedLastSpellID ~= nil then
                    ebtAssistedLastSpellID = nil
                    local pool = viewer.itemFramePool
                    if pool and LCG then
                        for icon in pool:EnumerateActive() do
                            local im = GetIconMeta(icon)
                            if im.assistedGlowing then
                                LCG.PixelGlow_Stop(icon, "ebtAssisted")
                                im.assistedGlowing = false
                            end
                        end
                    end
                end
            end

            -- Only tick when viewer is visible AND in combat (zero CPU otherwise)
            viewer:HookScript("OnShow", function()
                if InCombatLockdown() then StartEBTAssistedTicker() end
            end)
            viewer:HookScript("OnHide", function() StopEBTAssistedTicker() end)
            -- Combat enter/leave hooks for assisted ticker lifecycle
            local ebtAssistedCombatFrame = CreateFrame("Frame")
            ebtAssistedCombatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
            ebtAssistedCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            ebtAssistedCombatFrame:SetScript("OnEvent", function(_, event)
                if event == "PLAYER_REGEN_DISABLED" then
                    if viewer:IsShown() then StartEBTAssistedTicker() end
                else
                    StopEBTAssistedTicker()
                end
            end)

            ebtDispatch:SetScript("OnEvent", function(self, event, arg1)
                ScheduleEBTDispatch(false)
            end)

            -- Hook Blizzard layout for instant response
            if viewer.RefreshLayout then
                hooksecurefunc(viewer, "RefreshLayout", function()
                    ebtDispatch._lastActiveCount = -1 -- force layout on next dispatch
                    ScheduleEBTDispatch(true)
                end)
            end

            self:ApplyViewerSkin(viewer)
        end
    end
end

-- Initialize event-driven hooks on login
local function InitEventDrivenHooks()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_LOGIN" then
            EnsureDB()
            MyEssentialIconViewers:HookViewers()
            local viewer = _G["EssentialCooldownViewer"]
            if viewer then
                pcall(MyEssentialIconViewers.RescanViewer, MyEssentialIconViewers, viewer)
            end
        end
    end)
end

InitEventDrivenHooks()

-- -----------------------------------------------
-- LibEditMode integration for Essential Buffs
-- -----------------------------------------------
-- IMPORTANT: EssentialCooldownViewer inherits EditModeCooldownViewerSystemTemplate
-- so Blizzard already handles its Edit Mode positioning. We must NOT register
-- the viewer itself with LibEditMode:AddFrame (that causes taint).
-- Instead, we create a separate invisible anchor frame for our custom settings.

local ebtSettingsAnchor   -- our custom anchor (safe to register with LibEditMode)

local function EnsureEBTSettingsAnchor()
    if ebtSettingsAnchor then return ebtSettingsAnchor end
    if not LibEditMode then return nil end

    local viewer = _G["EssentialCooldownViewer"]

    local anchor = CreateFrame("Frame", "EBTSettingsAnchor", UIParent, "BackdropTemplate")
    anchor:SetSize(220, 24)
    anchor:EnableMouse(true)
    anchor:SetFrameStrata("MEDIUM")

    anchor:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    anchor:SetBackdropColor(0, 0, 0, 0.12)
    anchor:SetBackdropBorderColor(0.4, 0.8, 1.0, 0.9)

    local label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    label:SetPoint("CENTER")
    label:SetText("Essential Buff Settings")
    label:SetTextColor(1, 1, 1, 1)
    label:SetFont(label:GetFont(), 16, "OUTLINE")

    -- Anchor directly below the Blizzard EssentialCooldownViewer box
    anchor:ClearAllPoints()
    anchor:SetPoint("TOP", viewer, "BOTTOM", 0, -2)
    anchor:Hide()

    -- Register the ANCHOR (our own frame) with LibEditMode â€” not the Blizzard viewer
    local defaultPos = { point = "TOP", x = 0, y = -200 }
    LibEditMode:AddFrame(anchor, nil, defaultPos, "Essential Buffs Settings")

    -- Settings sliders on our anchor
    local frameSettings = {}

    -- Per-row icon size sliders (rows 1-4)
    for r = 1, 4 do
        table.insert(frameSettings, {
            kind = LibEditMode.SettingType.Slider,
            name = "Row " .. r .. " Icon Size",
            default = DEFAULTS.iconSize,
            get = function()
                local s = MyEssentialBuffTracker:GetSettings()
                return (s.rowSizes and s.rowSizes[r]) or s.iconSize or DEFAULTS.iconSize
            end,
            set = function(_, newValue)
                local s = MyEssentialBuffTracker:GetSettings()
                s.rowSizes = s.rowSizes or {}
                s.rowSizes[r] = newValue
                local v = _G["EssentialCooldownViewer"]
                if v then
                    ForceReskinViewer(v)
                    MyEssentialIconViewers:ApplyViewerSkin(v)
                end
            end,
            minValue = 10,
            maxValue = 120,
            valueStep = 1,
        })
    end

    -- Spacing
    table.insert(frameSettings, {
        kind = LibEditMode.SettingType.Slider,
        name = "Spacing",
        default = DEFAULTS.spacing,
        get = function()
            return MyEssentialBuffTracker:GetSettings().spacing or DEFAULTS.spacing
        end,
        set = function(_, newValue)
            local s = MyEssentialBuffTracker:GetSettings()
            s.spacing = newValue
            local v = _G["EssentialCooldownViewer"]
            if v then
                ForceReskinViewer(v)
                MyEssentialIconViewers:ApplyViewerSkin(v)
            end
        end,
        minValue = -50,
        maxValue = 100,
        valueStep = 1,
    })

    -- Icons Per Row
    table.insert(frameSettings, {
        kind = LibEditMode.SettingType.Slider,
        name = "Icons Per Row",
        default = DEFAULTS.rowLimit,
        get = function()
            local s = MyEssentialBuffTracker:GetSettings()
            return s.rowLimit or s.columns or DEFAULTS.rowLimit
        end,
        set = function(_, newValue)
            local s = MyEssentialBuffTracker:GetSettings()
            s.rowLimit = newValue
            s.columns = newValue
            local v = _G["EssentialCooldownViewer"]
            if v then
                ForceReskinViewer(v)
                MyEssentialIconViewers:ApplyViewerSkin(v)
            end
        end,
        minValue = 1,
        maxValue = 30,
        valueStep = 1,
    })

    LibEditMode:AddFrameSettings(anchor, frameSettings)

    ebtSettingsAnchor = anchor
    return anchor
end

-- Wire LibEditMode callbacks
local function SetupEBTEditModeCallbacks()
    if not LibEditMode then return end

    LibEditMode:RegisterCallback("enter", function()
        local settings = MyEssentialBuffTracker:GetSettings()
        if settings.enabled == false then return end
        local viewer = _G["EssentialCooldownViewer"]
        if viewer then
            viewer:SetAlpha(1)
        end
        if ebtSettingsAnchor then ebtSettingsAnchor:Show() end
    end)

    LibEditMode:RegisterCallback("exit", function()
        if ebtSettingsAnchor then ebtSettingsAnchor:Hide() end
        local viewer = _G["EssentialCooldownViewer"]
        if viewer then
            viewer:SetAlpha(1)
            MyEssentialIconViewers:ApplyViewerSkin(viewer)
        end
    end)

    LibEditMode:RegisterCallback("layout", function(layoutName)
        -- Anchor stays attached to viewer â€” Blizzard manages viewer position per layout
    end)
end

-- Initialize EditMode on PLAYER_LOGIN
local ebtEditModeInit = CreateFrame("Frame")
ebtEditModeInit:RegisterEvent("PLAYER_LOGIN")
ebtEditModeInit:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(0.5, function()
            EnsureEBTSettingsAnchor()
            SetupEBTEditModeCallbacks()
        end)
        self:UnregisterAllEvents()
    end
end)

-- ShowConfig popup removed -- all settings are in the Blizzard subcategory panel (CreateOptionsPanel)

-- ---------------------------
-- Initialization
-- ---------------------------
local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:RegisterEvent("PLAYER_ENTERING_WORLD")
init:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        EnsureDB()
        MyEssentialIconViewers:HookViewers()
        local viewer = _G["EssentialCooldownViewer"]
        if viewer then
            pcall(MyEssentialIconViewers.RescanViewer, MyEssentialIconViewers, viewer)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, function()
            local settings = MyEssentialBuffTracker:GetSettings()
            if settings.enabled == false then return end
            local viewer = _G["EssentialCooldownViewer"]
            if viewer and not viewer:IsShown() then
                viewer:Show()
                C_Timer.After(5, function()
                    if viewer then viewer:Hide() end
                end)
            end
        end)
    end
end)

-- ---------------------------
-- UI helpers used by CreateOptionsPanel()
-- ---------------------------

-- Compact dropdown (modern WowStyle1DropdownTemplate)
local function CreateDropdown(parent, labelText, options, initial, onChanged)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(210, 50)
    local currentValue = initial

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 0, 0)
    label:SetText(labelText)
    label:SetTextColor(0.85, 0.85, 0.85, 1)
    label:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")

    local dropdown = CreateFrame("DropdownButton", nil, container, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("TOPLEFT", 0, -20)
    dropdown:SetSize(180, 26)

    dropdown:SetupMenu(function(dd, rootDescription)
        for _, option in ipairs(options) do
            rootDescription:CreateRadio(tostring(option),
                function(v) return currentValue == v end,
                function(v)
                    currentValue = v
                    onChanged(v)
                    local viewer = _G["EssentialCooldownViewer"]
                    if viewer then
                        ForceReskinViewer(viewer)
                        pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
                        pcall(ProcessPendingBackdrops)
                    end
                end,
                option
            )
        end
    end)

    return container
end

-- Compact slider with input
local function CreateSlider(parent, labelText, min, max, step, initial, onChanged)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(210, 40)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 0, 0)
    label:SetText(labelText)
    label:SetTextColor(0.85, 0.85, 0.85, 1)
    label:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")

    local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 0, -18)
    slider:SetSize(140, 16)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(initial)

    -- Value text inline with label
    local valueText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    valueText:SetPoint("LEFT", label, "RIGHT", 8, 0)
    valueText:SetText(tostring(initial))
    valueText:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    valueText:SetTextColor(1, 1, 1, 1)

    slider:HookScript("OnValueChanged", function(self, val)
        valueText:SetText(tostring(step >= 1 and math.floor(val + 0.5) or val))
    end)

    local input = CreateFrame("EditBox", nil, container, "InputBoxTemplate")
    input:SetSize(50, 20)
    input:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    input:SetAutoFocus(false)
    input:SetText(tostring(initial))
    input:SetTextColor(1, 1, 1, 1)
    input:SetMaxLetters(6)

    local function UpdateValue(val)
        if step >= 1 then val = math.floor(val + 0.5) end
        onChanged(val)
        local viewer = _G["EssentialCooldownViewer"]
        if viewer then
            ForceReskinViewer(viewer)
            pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
            pcall(ProcessPendingBackdrops)
        end
    end

    slider:SetScript("OnValueChanged", function(self, val)
        UpdateValue(val)
        input:SetText(tostring(val))
    end)

    input:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val and val >= min and val <= max then
            slider:SetValue(val)
        else
            self:SetText(tostring(slider:GetValue()))
        end
        self:ClearFocus()
    end)

    input:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(slider:GetValue()))
        self:ClearFocus()
    end)

    container:SetScript("OnShow", function()
        local val = slider:GetValue()
        input:SetText(tostring(val))
        valueText:SetText(tostring(step >= 1 and math.floor(val + 0.5) or val))
    end)

    return container
end

-- Compact checkbox
local function CreateCheckbox(parent, labelText, initial, onChanged)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(210, 24)

    local checkbox = CreateFrame("CheckButton", nil, container)
    checkbox:SetPoint("LEFT", 0, 0)
    checkbox:SetSize(20, 20)
    checkbox:SetChecked(initial)

    -- Use Atlas textures for checkbox visuals
    checkbox.bg = checkbox:CreateTexture(nil, "BACKGROUND")
    checkbox.bg:SetAllPoints(checkbox)
    checkbox.bg:SetAtlas("checkbox-minimal")

    checkbox.check = checkbox:CreateTexture(nil, "OVERLAY")
    checkbox.check:SetAllPoints(checkbox)
    checkbox.check:SetAtlas("checkmark-minimal")
    checkbox:SetCheckedTexture(checkbox.check)

    checkbox.disabled = checkbox:CreateTexture(nil, "OVERLAY")
    checkbox.disabled:SetAllPoints(checkbox)
    checkbox.disabled:SetAtlas("checkmark-minimal-disabled")
    checkbox:SetDisabledCheckedTexture(checkbox.disabled)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", checkbox, "RIGHT", 8, 0)
    label:SetText(labelText)
    label:SetTextColor(0.85, 0.85, 0.85, 1)
    label:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")

    checkbox:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        onChanged(checked)
        local viewer = _G["EssentialCooldownViewer"]
        if viewer then
            ForceReskinViewer(viewer)
            pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
            pcall(ProcessPendingBackdrops)
        end
    end)

    return container
end


-- Addon Options Panel integration
local optionsPanel



-- Old CreateOptionsPanel removed; options are now handled by Ace3 AceConfig (ui/options/EssentialBuffsOptions.lua)
function MyEssentialBuffTracker:CreateOptionsPanel() return nil end

-- ---------------------------
-- Initialization
-- ---------------------------
local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:RegisterEvent("PLAYER_ENTERING_WORLD")
init:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        EnsureDB()
        MyEssentialIconViewers:HookViewers()
        local viewer = _G["EssentialCooldownViewer"]
        if viewer then
            pcall(MyEssentialIconViewers.RescanViewer, MyEssentialIconViewers, viewer)
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.5, function()
            local settings = MyEssentialBuffTracker:GetSettings()
            if settings.enabled == false then return end
            local viewer = _G["EssentialCooldownViewer"]
            if viewer and not viewer:IsShown() then
                viewer:Show()
                C_Timer.After(5, function()
                    if viewer then viewer:Hide() end
                end)
            end
        end)
    end
end)
