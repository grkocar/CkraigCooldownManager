

-- Hide Cooldown Manager when mounted

-- Mount hide/show option
local function IsPlayerMounted()
    return IsMounted and IsMounted()
end

-- SafeGetChildren removed — use select() pattern or pool:EnumerateActive() instead
local HideClusterAnchors
local UpdateCooldownManagerVisibility
local _di_optionsPreviewEnabled = false
local _di_settingsPanelSamplePreviewEnabled = false
local _di_startupSamplePreviewEnabled = false
local _di_startupSamplePreviewTimer = nil
local _di_startupSamplePreviewTriggered = false
local _di_cooldownSettingsHooksInstalled = false

local function IsSamplePreviewEnabled()
    return _di_settingsPanelSamplePreviewEnabled or _di_startupSamplePreviewEnabled
end

local function CancelStartupSamplePreviewTimer()
    if _di_startupSamplePreviewTimer then
        _di_startupSamplePreviewTimer:Cancel()
        _di_startupSamplePreviewTimer = nil
    end
end

local function ApplySamplePreviewState()
    UpdateCooldownManagerVisibility()
    if DYNAMICICONS and DYNAMICICONS.RefreshLayout then
        DYNAMICICONS:RefreshLayout()
    end
end

local function InstallCooldownSettingsSampleHooks()
    if _di_cooldownSettingsHooksInstalled then return true end

    local settingsFrame = _G.CooldownViewerSettings
    if not settingsFrame then
        if UIParentLoadAddOn then
            pcall(UIParentLoadAddOn, "Blizzard_CooldownViewer")
            settingsFrame = _G.CooldownViewerSettings
        end
        if not settingsFrame then
            return false
        end
    end

    settingsFrame:HookScript("OnShow", function()
        _di_settingsPanelSamplePreviewEnabled = true
        ApplySamplePreviewState()
    end)
    settingsFrame:HookScript("OnHide", function()
        _di_settingsPanelSamplePreviewEnabled = false
        ApplySamplePreviewState()
    end)

    _di_cooldownSettingsHooksInstalled = true
    _di_settingsPanelSamplePreviewEnabled = settingsFrame.IsShown and settingsFrame:IsShown() or false
    return true
end

UpdateCooldownManagerVisibility = function()
    local viewer = _G["BuffIconCooldownViewer"]
    if viewer then
        if _di_inEditMode or (EditModeManagerFrame and EditModeManagerFrame:IsShown()) then
            viewer:Show()
            return
        end
        if _di_optionsPreviewEnabled then
            viewer:Show()
            return
        end
        if IsSamplePreviewEnabled() then
            viewer:Show()
            return
        end
        -- Don't force-show until ProfileManager has loaded the real settings
        if not (CkraigProfileManager and CkraigProfileManager.db) then return end
        local settings = DYNAMICICONS:GetSettings()
        if settings.enabled == false then
            viewer:Hide()
            return
        end
        if settings.hideWhenMounted then
            if IsPlayerMounted() then
                viewer:Hide()
                if _G.DYNAMICICONS and _G.DYNAMICICONS.HideMountSuppressedDisplays then
                    _G.DYNAMICICONS:HideMountSuppressedDisplays()
                end
            else
                viewer:Show()
            end
        else
            viewer:Show()
        end
    end
end

local mountEventFrame = CreateFrame("Frame")
mountEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
mountEventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
mountEventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
mountEventFrame:SetScript("OnEvent", function(self, event)
    UpdateCooldownManagerVisibility()
    if event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Profile swap via LibDualSpec fires OnProfileChanged, but the viewer's
        -- cooldown list may not be fully rebuilt yet.  Schedule a second layout
        -- pass so cluster positions and icons settle correctly.
        C_Timer.After(1.0, function()
            if DYNAMICICONS and DYNAMICICONS.OnProfileChanged then
                DYNAMICICONS:OnProfileChanged()
            end
        end)
    end
end)

local DEFAULTS = {
    columns         = 3,
    hSpacing        = 2,
    vSpacing        = 2,
    growUp          = true,
    locked          = true,
    iconSize        = 36,
    aspectRatio     = "1:1",
    aspectRatioCrop = nil,
    spacing         = 0,
    rowLimit        = 0,
    rowGrowDirection= "up",

    -- New settings
    iconCornerRadius = 1,
    cooldownTextSize = 16,
    cooldownTextPosition = "CENTER",
    cooldownTextX = 0,
    cooldownTextY = 0,
    chargeTextSize = 18,
    chargeTextPosition = "TOP",
    chargeTextX = 0,
    chargeTextY = 13,

    enabled = true,
    showCooldownText = true,
    showChargeText = true,
    hideWhenMounted = false,
    showSwipe = true,

    -- Static Grid Mode
    staticGridMode = false,
    gridRows = 4,
    gridColumns = 4,
    gridSlotMap = {},

    -- Per-row icon sizes (optional override, otherwise uses iconSize)
    rowSizes = {},

    -- Multi-cluster dynamic mode
    multiClusterMode = false,
    clusterCount = 5,
    clusterUnlocked = false,
    clusterFlow = "horizontal",
    clusterFlows = {},
    clusterVerticalGrows = {},
    clusterVerticalPins = {},
    clusterIconSizes = {},
    clusterHorizontalSpacings = {},
    clusterSampleDisplayModes = {},
    clusterAlwaysShowSpells = {},
    clusterAssignments = {},
    showAllCooldownSettingsInOptions = false,
    clusterPositions = {},
    clusterManualOrders = {},
    clusterCenterIcons = true,
    -- Duplicate spells across clusters: clusterDuplicates[key] = { [clusterIndex] = true, ... }
    clusterDuplicates = {},
    -- Per-spell glows: spellGlows[key] = { enabled, mode, glowType, color }
    spellGlows = {},
    -- Per-spell sounds: spellSounds[key] = { enabled, sound, mode }
    -- mode = "show" | "expire" | "both"
    spellSounds = {},
    startupSamplePreview = true,
    -- Per-cluster text sizes (0 or nil = use global)
    clusterCooldownTextSizes = {},
    clusterChargeTextSizes = {},
    -- Per-cluster text colors (nil = use global/ChargeDB)
    clusterCooldownTextColors = {},
    clusterChargeTextColors = {},
}

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

local LCG = LibStub("LibCustomGlow-1.0", true)
local LSM = LibStub("LibSharedMedia-3.0", true)
local LibEditMode = LibStub("LibEditMode", true)
local _di_inEditMode = false

-- Reusable glow color array (avoids table allocation per icon per dispatch)
local diGlowColor = { 1, 1, 1, 1 }
local _di_enabledGlowLookup = {}
local _di_glowCfgSource = nil
local _di_enabledSoundLookup = {}
local _di_soundCfgSource = nil
local _di_soundCfgRevision = -1
local _di_soundHasEnabled = false
local _di_soundLastPlayByKey = {}
local _di_soundActivePrevByKey = {}
local _di_soundPrevCfgByKey = {}
local _di_soundPrevModeByKey = {}
local _di_soundMinInterval = 0.20
local _di_glowDispatchInterval = 0.5
local _di_glowDirty = true
local _di_glowIdleElapsed = 0
local _di_glowWatchdog = 2.0
local _di_glowEventFrame = nil
local _di_glowTicker = nil
local _di_glowTickerInterval = nil

local function GetSpellSoundsRevision_DI(settings)
    return tonumber(settings and settings.spellSoundsRevision) or 0
end

-- Forward declarations for glow functions (bodies defined after all dependencies)
local StopGlow_DI, StartGlow_DI, IsSpellOnCooldown_DI, DispatchGlows_DI, EnsureGlowDispatchRunning

local function RunGlowDispatchTick()
    _di_glowIdleElapsed = _di_glowIdleElapsed + (_di_glowTickerInterval or _di_glowDispatchInterval)
    if not _di_glowDirty and _di_glowIdleElapsed < _di_glowWatchdog then
        return
    end

    local viewer = _G["BuffIconCooldownViewer"]
    if not viewer or not viewer:IsShown() then return end
    local settings = DYNAMICICONS:GetSettings()
    if not settings then return end
    _di_glowDirty = false
    _di_glowIdleElapsed = 0
    DispatchGlows_DI(viewer, settings)
end

local function StopGlowTicker_DI()
    if _di_glowTicker then
        _di_glowTicker:Cancel()
        _di_glowTicker = nil
    end
    _di_glowTickerInterval = nil
end

local function EnsureGlowTicker_DI()
    local interval = tonumber(_di_glowDispatchInterval) or 0.5
    if interval < 0.2 then interval = 0.2 end

    if _di_glowTicker and _di_glowTickerInterval == interval then
        return
    end

    StopGlowTicker_DI()
    _di_glowTickerInterval = interval
    _di_glowTicker = C_Timer.NewTicker(interval, RunGlowDispatchTick)
end

local _di_glowHasEnabled = false   -- true when RebuildEnabledGlowLookup_DI last returned true

local function _di_glowShouldTick()
    if not _di_glowHasEnabled and not _di_soundHasEnabled then return false end
    local viewer = _G["BuffIconCooldownViewer"]
    if not viewer or not viewer:IsShown() then return false end
    return InCombatLockdown()
end

local function _di_startGlowTickerIfNeeded()
    if _di_glowShouldTick() then
        _di_glowDirty = true
        _di_glowIdleElapsed = _di_glowWatchdog
        EnsureGlowTicker_DI()
    end
end

local function _di_stopGlowTickerAndFlush()
    StopGlowTicker_DI()
    -- One final dispatch so glow states are correct when combat ends
    local viewer = _G["BuffIconCooldownViewer"]
    if viewer and viewer:IsShown() then
        local settings = DYNAMICICONS:GetSettings()
        if settings then DispatchGlows_DI(viewer, settings) end
    end
end

local function EnsureGlowEventFrame_DI(enabled)
    if enabled then
        if not _di_glowEventFrame then
            _di_glowEventFrame = CreateFrame("Frame")
            _di_glowEventFrame:SetScript("OnEvent", function(_, event)
                if event == "PLAYER_REGEN_DISABLED" then
                    _di_startGlowTickerIfNeeded()
                    return
                elseif event == "PLAYER_REGEN_ENABLED" then
                    _di_stopGlowTickerAndFlush()
                    return
                end
                -- Combat events: just set dirty flag
                _di_glowDirty = true
                _di_glowIdleElapsed = _di_glowWatchdog
            end)
            _di_glowEventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
            _di_glowEventFrame:RegisterUnitEvent("UNIT_AURA", "player")
            _di_glowEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
            _di_glowEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            _di_glowEventFrame:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")
            _di_glowEventFrame:RegisterEvent("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")
        end
    elseif _di_glowEventFrame then
        _di_glowEventFrame:UnregisterAllEvents()
        _di_glowEventFrame = nil
    end
end

-- Hoisted pcall helper: avoids closure allocation per icon per frame
local _di_pcall_unit, _di_pcall_auraID
local function _di_checkAuraDuration()
    local d = C_UnitAuras.GetAuraDataByAuraInstanceID(_di_pcall_unit, _di_pcall_auraID)
    return d and d.duration and d.duration > 0
end

-- Hoisted ProcGlow options table (reused every dispatch, avoids allocation)
local _di_procGlowOpts = { color = diGlowColor, key = "diGlow" }

local function RebuildEnabledGlowLookup_DI(spellGlows)
    for k in pairs(_di_enabledGlowLookup) do _di_enabledGlowLookup[k] = nil end
    _di_glowCfgSource = spellGlows
    _di_glowDispatchInterval = 0.65

    if type(spellGlows) ~= "table" then
        return false
    end

    local hasEnabled = false
    for skey, cfg in pairs(spellGlows) do
        if type(cfg) == "table" and cfg.enabled then
            local glowTypeRaw = cfg.glowType
            cfg.__ccmGlowTypeRaw = glowTypeRaw
            cfg.__ccmGlowType = glowTypeRaw or "pixel"
            _di_enabledGlowLookup[tostring(skey)] = cfg
            hasEnabled = true
        end
    end

    return hasEnabled
end

local function RebuildEnabledSoundLookup_DI(spellSounds)
    for k in pairs(_di_enabledSoundLookup) do _di_enabledSoundLookup[k] = nil end
    _di_soundCfgSource = spellSounds
    _di_soundCfgRevision = tonumber((DYNAMICICONS and DYNAMICICONS.GetSettings and GetSpellSoundsRevision_DI(DYNAMICICONS:GetSettings())) or 0) or 0

    if type(spellSounds) ~= "table" then
        return false
    end

    local hasEnabled = false
    for skey, cfg in pairs(spellSounds) do
        if type(cfg) == "table" and cfg.enabled then
            _di_enabledSoundLookup[tostring(skey)] = cfg
            hasEnabled = true
        end
    end

    return hasEnabled
end

local function ResolveSoundPath_DI(soundKey)
    if not soundKey or soundKey == "" then return nil end
    if LSM and LSM.Fetch then
        local ok, path = pcall(LSM.Fetch, LSM, "sound", soundKey, true)
        if ok and path and path ~= "" then
            return path
        end
    end
    return soundKey
end

local function TrimString_DI(s)
    if type(s) ~= "string" then return "" end
    return s:match("^%s*(.-)%s*$") or ""
end

local function ResolveSpellName_DI(spellKey)
    local spellID = tonumber(spellKey)
    if spellID and C_Spell and C_Spell.GetSpellName then
        local name = C_Spell.GetSpellName(spellID)
        if name and name ~= "" then
            return name
        end
    end
    return tostring(spellKey or "Spell")
end

local function ResolveTtsText_DI(spellKey, cfg)
    local text = TrimString_DI(cfg and cfg.ttsText)
    if text ~= "" then
        return text
    end
    return ResolveSpellName_DI(spellKey)
end

local function SpeakText_DI(text)
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

local function PlaySpellSound_DI(spellKey, cfg)
    if not cfg then return end
    local keyStr = tostring(spellKey or "")
    if keyStr == "" then return end

    local now = GetTime and GetTime() or 0
    local last = _di_soundLastPlayByKey[keyStr]
    if last and (now - last) < _di_soundMinInterval then
        return
    end

    _di_soundLastPlayByKey[keyStr] = now

    local output = tostring(cfg.output or "sound")
    local playSound = (output == "sound" or output == "both")
    local playTts = (output == "tts" or output == "both")
    local didPlay = false

    if playSound then
        local soundPath = ResolveSoundPath_DI(cfg.sound)
        if soundPath then
            local ok = pcall(PlaySoundFile, soundPath, "Master")
            didPlay = didPlay or (ok and true or false)
        end
    end

    if playTts then
        local ttsText = ResolveTtsText_DI(keyStr, cfg)
        didPlay = SpeakText_DI(ttsText) or didPlay
    end

    if not didPlay then
        _di_soundLastPlayByKey[keyStr] = nil
    end
end

-- Per-icon cooldown key cache (key never changes for a given icon frame)
local _di_iconKeyCache = setmetatable({}, { __mode = "k" })

-- Reusable tables for ApplyViewerLayout (avoids creating new tables every 0.1s)
local _di_layoutIcons = {}
local _di_layoutShown = {}
-- _di_iconSortComparator defined below (after IconRuntimeState)
local function ClearTable(tbl)
    for k in pairs(tbl) do tbl[k] = nil end
end

local function IsUsingFallbackDB(db)
    return db
        and db.profile
        and type(db.profile.dynamicIcons) == "table"
        and db.profile.dynamicIcons == _G.DYNAMICICONSDB
end

local function DeepCopyTable(source)
    if type(source) ~= "table" then
        return source
    end

    local copy = {}
    for k, v in pairs(source) do
        if type(v) == "table" then
            copy[k] = DeepCopyTable(v)
        else
            copy[k] = v
        end
    end
    return copy
end

-- ---------------------------
-- Utilities
-- ---------------------------
local function EnsureDB()
    -- Initialize database if not done yet
    if not DYNAMICICONS.db
        or (CkraigProfileManager and CkraigProfileManager.db and DYNAMICICONS.db ~= CkraigProfileManager.db)
    then
        DYNAMICICONS:InitializeDB()
    end
    
    local settings = DYNAMICICONS:GetSettings()

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
    if settings.showSwipe == nil then settings.showSwipe = DEFAULTS.showSwipe end

    if settings.staticGridMode == nil then settings.staticGridMode = DEFAULTS.staticGridMode end
    if settings.gridRows == nil then settings.gridRows = DEFAULTS.gridRows end
    if settings.gridColumns == nil then settings.gridColumns = DEFAULTS.gridColumns end
    if settings.gridSlotMap == nil then settings.gridSlotMap = {} end

    -- Per-row sizes
    if settings.rowSizes == nil then settings.rowSizes = {} end

    -- Multi-cluster mode
    if settings.multiClusterMode == nil then settings.multiClusterMode = DEFAULTS.multiClusterMode end
    if settings.clusterCount == nil then settings.clusterCount = DEFAULTS.clusterCount end
    if settings.clusterUnlocked == nil then settings.clusterUnlocked = DEFAULTS.clusterUnlocked end
    if settings.clusterFlow == nil then settings.clusterFlow = DEFAULTS.clusterFlow end
    if settings.clusterFlows == nil then settings.clusterFlows = {} end
    if settings.clusterVerticalGrows == nil then settings.clusterVerticalGrows = {} end
    if settings.clusterVerticalPins == nil then settings.clusterVerticalPins = {} end
    if settings.clusterIconSizes == nil then settings.clusterIconSizes = {} end
    if settings.clusterHorizontalSpacings == nil then settings.clusterHorizontalSpacings = {} end
    if settings.clusterSampleDisplayModes == nil then settings.clusterSampleDisplayModes = {} end
    if settings.clusterAlwaysShowSpells == nil then settings.clusterAlwaysShowSpells = {} end
    if settings.clusterAssignments == nil then settings.clusterAssignments = {} end
    if settings.showAllCooldownSettingsInOptions == nil then settings.showAllCooldownSettingsInOptions = DEFAULTS.showAllCooldownSettingsInOptions end
    if settings.clusterSampleIconsByKey == nil then settings.clusterSampleIconsByKey = {} end
    if settings.clusterPositions == nil then settings.clusterPositions = {} end
    if settings.clusterManualOrders == nil then settings.clusterManualOrders = {} end
    if settings.clusterCenterIcons == nil then settings.clusterCenterIcons = DEFAULTS.clusterCenterIcons end
    if settings.clusterDuplicates == nil then settings.clusterDuplicates = {} end
    if settings.spellGlows == nil then settings.spellGlows = {} end
    if settings.spellSounds == nil then settings.spellSounds = {} end
    if settings.spellSoundsRevision == nil then settings.spellSoundsRevision = 0 end
    if settings.startupSamplePreview == nil then settings.startupSamplePreview = DEFAULTS.startupSamplePreview end
    if settings.clusterCooldownTextSizes == nil then settings.clusterCooldownTextSizes = {} end
    if settings.clusterChargeTextSizes == nil then settings.clusterChargeTextSizes = {} end
    if settings.clusterCooldownTextColors == nil then settings.clusterCooldownTextColors = {} end
    if settings.clusterChargeTextColors == nil then settings.clusterChargeTextColors = {} end
    -- Sanitize corrupted spellGlows entries (boolean instead of table)
    for k, v in pairs(settings.spellGlows) do
        if type(v) ~= "table" then
            settings.spellGlows[k] = { enabled = (v == true), mode = "ready", glowType = "pixel", color = {r=1, g=1, b=0, a=1} }
        end
    end
    -- Sanitize corrupted spellSounds entries (boolean instead of table)
    for k, v in pairs(settings.spellSounds) do
        if type(v) ~= "table" then
            settings.spellSounds[k] = { enabled = (v == true), sound = "", output = "sound", ttsText = "", mode = "expire" }
        else
            if v.mode == nil or v.mode == "" then
                v.mode = "expire"
            elseif v.mode == "ready" then
                -- Backward compatibility with previous build.
                v.mode = "expire"
            end
            if v.output == nil or v.output == "" then
                v.output = "sound"
            end
            if v.output ~= "sound" and v.output ~= "tts" and v.output ~= "both" then
                v.output = "sound"
            end
            if type(v.ttsText) ~= "string" then
                v.ttsText = ""
            end
        end
    end
end

local function SafeNumber(val, default)
    local num = tonumber(val)
    if num ~= nil then return num end
    return default
end

local function IsEditModeActive()
    return _di_inEditMode or (EditModeManagerFrame and EditModeManagerFrame:IsShown())
end

local IconRuntimeState = setmetatable({}, { __mode = "k" })
local ViewerRuntimeState = setmetatable({}, { __mode = "k" })
local TextureRuntimeState = setmetatable({}, { __mode = "k" })
local BackdropPendingState = setmetatable({}, { __mode = "k" })
local SampleIconTextureCache = {}
local KnownDisplayedItemsByKey = {}
local PendingInteractionRefresh = setmetatable({}, { __mode = "k" })
local InteractionRefreshEventFrame = nil
local ApplyViewerInteractionState
local RefreshOptionsInteractionStatus


local function GetIconState(icon)
    local state = IconRuntimeState[icon]
    if not state then
        state = {}
        IconRuntimeState[icon] = state
    end
    return state
end

-- Hoisted sort comparator for ApplyViewerLayout (avoids closure allocation per call)
local function _di_iconSortComparator(a, b)
    local aState = IconRuntimeState[a]
    local bState = IconRuntimeState[b]
    local aOrder = aState and aState.creationOrder or 0
    local bOrder = bState and bState.creationOrder or 0
    return (a.layoutIndex or a:GetID() or aOrder) < (b.layoutIndex or b:GetID() or bOrder)
end

local function GetViewerState(viewer)
    local state = ViewerRuntimeState[viewer]
    if not state then
        state = {}
        ViewerRuntimeState[viewer] = state
    end
    return state
end

local function SetViewerMetric(viewer, key, value)
    local state = GetViewerState(viewer)
    state[key] = value
end

local function GetViewerMetric(viewer, key, defaultValue)
    local state = ViewerRuntimeState[viewer]
    if state and state[key] ~= nil then
        return state[key]
    end
    return defaultValue
end

local function QueueInteractionRefresh(viewer)
    if not viewer then return end
    PendingInteractionRefresh[viewer] = true
    if RefreshOptionsInteractionStatus then
        RefreshOptionsInteractionStatus()
    end

    if not InteractionRefreshEventFrame then
        InteractionRefreshEventFrame = CreateFrame("Frame")
        InteractionRefreshEventFrame:SetScript("OnEvent", function(self, event)
            if event ~= "PLAYER_REGEN_ENABLED" then return end

            local settings = DYNAMICICONS and DYNAMICICONS.GetSettings and DYNAMICICONS:GetSettings()
            UpdateCooldownManagerVisibility()
            for pendingViewer in pairs(PendingInteractionRefresh) do
                PendingInteractionRefresh[pendingViewer] = nil
                if pendingViewer and settings and ApplyViewerInteractionState then
                    ApplyViewerInteractionState(pendingViewer, settings, true)
                    if pendingViewer.IsShown and pendingViewer:IsShown() and not IsEditModeActive() then
                        pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, pendingViewer)
                    end
                end
            end

            if RefreshOptionsInteractionStatus then
                RefreshOptionsInteractionStatus()
            end

            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end)
    end

    InteractionRefreshEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

local MAX_CLUSTER_GROUPS = 20
local DEFAULT_CLUSTER_POSITIONS = {
    [1] = { point = "CENTER", x = -340, y = 120 },
    [2] = { point = "CENTER", x = -170, y = 120 },
    [3] = { point = "CENTER", x = 0, y = 120 },
    [4] = { point = "CENTER", x = 170, y = 120 },
    [5] = { point = "CENTER", x = 340, y = 120 },
}

local function GetDefaultClusterPosition(index)
    local preset = DEFAULT_CLUSTER_POSITIONS[index]
    if preset then
        return preset
    end

    local perRow = 5
    local spacingX = 170
    local spacingY = 170
    local col = (index - 1) % perRow
    local row = math.floor((index - 1) / perRow)

    return {
        point = "CENTER",
        x = -340 + (col * spacingX),
        y = 120 - (row * spacingY),
    }
end

local function NormalizeCooldownKey(value)
    if value == nil then return nil end

    local valueType = type(value)
    if valueType == "number" then
        if value <= 0 then return nil end
        return tostring(value)
    end

    if valueType == "string" then
        local trimmed = value:match("^%s*(.-)%s*$")
        if trimmed == "" then return nil end
        return trimmed
    end

    return nil
end

local function GetCooldownInfoForKey(key)
    local numericKey = tonumber(key)
    if not numericKey then
        return nil
    end

    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local okInfo, cooldownInfo = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, numericKey)
        if okInfo and cooldownInfo then
            return cooldownInfo
        end
    end

    return nil
end

local function GetCandidateSpellIDsFromCooldownInfo(cooldownInfo)
    local candidates = {}
    if not cooldownInfo then
        return candidates
    end

    local function PushSpellID(spellID)
        if type(spellID) == "number" and spellID > 0 then
            table.insert(candidates, spellID)
        end
    end

    PushSpellID(cooldownInfo.overrideTooltipSpellID)
    PushSpellID(cooldownInfo.overrideSpellID)
    PushSpellID(cooldownInfo.spellID)

    if type(cooldownInfo.linkedSpellIDs) == "table" then
        for _, linkedSpellID in ipairs(cooldownInfo.linkedSpellIDs) do
            PushSpellID(linkedSpellID)
        end
    end

    return candidates
end

local IsSpellKnownForPlayer

local function ResolveBestSpellIDForKey(key, cooldownInfo)
    local numericKey = tonumber(key)

    -- Keep CDM-native deterministic priority; do not remap to arbitrary
    -- "known" linked spells, which can surface unrelated names in options.
    if cooldownInfo then
        if type(cooldownInfo.overrideTooltipSpellID) == "number" and cooldownInfo.overrideTooltipSpellID > 0 then
            return cooldownInfo.overrideTooltipSpellID
        end
        if type(cooldownInfo.overrideSpellID) == "number" and cooldownInfo.overrideSpellID > 0 then
            return cooldownInfo.overrideSpellID
        end
        if type(cooldownInfo.spellID) == "number" and cooldownInfo.spellID > 0 then
            return cooldownInfo.spellID
        end
        if type(cooldownInfo.linkedSpellIDs) == "table" then
            for _, linkedSpellID in ipairs(cooldownInfo.linkedSpellIDs) do
                if type(linkedSpellID) == "number" and linkedSpellID > 0 then
                    return linkedSpellID
                end
            end
        end
    end

    return numericKey
end

local function GetIconCooldownKey(icon)
    if not icon then return nil end

    local cooldownID = nil
    if icon.GetCooldownID then
        cooldownID = icon:GetCooldownID()
    end

    if cooldownID == nil and icon.GetSpellID then
        cooldownID = icon:GetSpellID()
    end

    if cooldownID == nil and icon.GetCooldownInfo then
        local cooldownInfo = icon:GetCooldownInfo()
        if cooldownInfo then
            cooldownID = cooldownInfo.cooldownID or cooldownInfo.spellID
        end
    end

    if cooldownID == nil and icon.GetAuraSpellID then
        cooldownID = icon:GetAuraSpellID()
    end

    if cooldownID == nil then
        cooldownID = icon.cooldownID or icon.spellID
    end

    if cooldownID == nil and icon.GetID then
        cooldownID = icon:GetID()
    end

    if cooldownID == nil then
        cooldownID = GetIconState(icon).creationOrder
    end

    return NormalizeCooldownKey(cooldownID)
end

-- Strict key resolver used by options lists.
-- Only accepts real cooldown/spell identifiers from icon data, and never
-- falls back to frame IDs or creation-order counters.
local function GetIconCooldownKeyStrict(icon)
    if not icon then return nil end

    local cooldownID = nil
    if icon.GetCooldownID then
        cooldownID = icon:GetCooldownID()
    end

    if cooldownID == nil and icon.GetCooldownInfo then
        local cooldownInfo = icon:GetCooldownInfo()
        if cooldownInfo then
            cooldownID = cooldownInfo.cooldownID or cooldownInfo.spellID
        end
    end

    if cooldownID == nil and icon.GetSpellID then
        cooldownID = icon:GetSpellID()
    end

    if cooldownID == nil and icon.GetAuraSpellID then
        cooldownID = icon:GetAuraSpellID()
    end

    if cooldownID == nil then
        cooldownID = icon.cooldownID or icon.spellID
    end

    return NormalizeCooldownKey(cooldownID)
end

local function CollectDisplayedCooldownItems(viewer)
    local items = {}
    if not viewer then return items end

    local seen = {}

    local function AddItemByKey(rawKey, nameHint, iconHint)
        local key = NormalizeCooldownKey(rawKey)
        if not key or seen[key] then
            return
        end

        seen[key] = true

        local name = nameHint
        local iconTexture = iconHint

        local numericKey = tonumber(key)
        if numericKey then
            local cooldownInfo = GetCooldownInfoForKey(key)
            local bestSpellID = ResolveBestSpellIDForKey(key, cooldownInfo)

            if bestSpellID and C_Spell and C_Spell.GetSpellName and not name then
                name = C_Spell.GetSpellName(bestSpellID)
            end
            if bestSpellID and C_Spell and C_Spell.GetSpellTexture and not iconTexture then
                iconTexture = C_Spell.GetSpellTexture(bestSpellID)
            end
        end

        if numericKey and C_Spell and C_Spell.GetSpellName and not name then
            name = C_Spell.GetSpellName(numericKey)
        end

        if numericKey and C_Spell and C_Spell.GetSpellTexture and not iconTexture then
            iconTexture = C_Spell.GetSpellTexture(numericKey)
        end

        if not name then
            name = "CDID " .. key
        end

        table.insert(items, {
            key = key,
            name = name,
            icon = iconTexture,
        })

        if iconTexture then
            SampleIconTextureCache[key] = iconTexture
        end
    end

    -- Use Blizzard's itemFramePool when available (zero-allocation, no pcall)
    local pool = viewer and viewer.itemFramePool
    if pool then
        for child in pool:EnumerateActive() do
            if child and child:IsShown() and (child.Icon or child.icon) then
                local iconTexture = nil
                local childIcon = child.Icon or child.icon
                if childIcon and childIcon.GetTexture then
                    iconTexture = childIcon:GetTexture()
                end
                local key = GetIconCooldownKeyStrict(child)
                if key then
                    AddItemByKey(key, nil, iconTexture)
                end
            end
        end
    else
        local container = viewer.viewerFrame or viewer
        for i = 1, select("#", container:GetChildren()) do
            local child = select(i, container:GetChildren())
            if child and child:IsShown() and (child.Icon or child.icon) then
                local iconTexture = nil
                local childIcon = child.Icon or child.icon
                if childIcon and childIcon.GetTexture then
                    iconTexture = childIcon:GetTexture()
                end

                local key = GetIconCooldownKeyStrict(child)
                if key then
                    AddItemByKey(key, nil, iconTexture)
                end
            end
        end
    end

    table.sort(items, function(a, b)
        local aNum = tonumber(a.key)
        local bNum = tonumber(b.key)
        if aNum and bNum then
            return aNum < bNum
        end
        return tostring(a.key) < tostring(b.key)
    end)

    return items
end

local function ResolveCooldownKeySpellID(key)
    local numericKey = tonumber(key)
    if not numericKey then
        return nil
    end

    local cooldownInfo = GetCooldownInfoForKey(key)
    return ResolveBestSpellIDForKey(key, cooldownInfo)
end

IsSpellKnownForPlayer = function(spellID)
    if not spellID then
        return false
    end

    if IsSpellKnownOrOverridesKnown then
        if IsSpellKnownOrOverridesKnown(spellID) then
            return true
        end
    end

    if IsPlayerSpell then
        if IsPlayerSpell(spellID) then
            return true
        end
    end

    if C_SpellBook and C_SpellBook.IsSpellKnown then
        if C_SpellBook.IsSpellKnown(spellID) then
            return true
        end
    end

    return false
end

local function IsCooldownKeyKnownForPlayer(key)
    local cooldownInfo = GetCooldownInfoForKey(key)
    if cooldownInfo and cooldownInfo.isKnown then
        return true
    end

    local candidates = GetCandidateSpellIDsFromCooldownInfo(cooldownInfo)
    for _, spellID in ipairs(candidates) do
        if IsSpellKnownForPlayer(spellID) then
            return true
        end
    end

    local fallbackSpellID = ResolveCooldownKeySpellID(key)
    if fallbackSpellID then
        return IsSpellKnownForPlayer(fallbackSpellID)
    end

    return false
end

local function BuildAvailableCooldownKeySet(viewer, includeAllAvailable)
    local available = {}
    if not viewer then
        return available
    end

    -- Legacy behavior: when caller does not specify strict mode, include viewer cooldown IDs.
    if includeAllAvailable == nil then
        includeAllAvailable = true
    end

    local function AddIfUsable(rawKey)
        local normalizedKey = NormalizeCooldownKey(rawKey)
        if not normalizedKey then
            return
        end

        -- In strict mode (assignment list), keep exactly what the viewer shows.
        -- Known-check filtering can hide valid active entries.
        if includeAllAvailable and tonumber(normalizedKey) and not IsCooldownKeyKnownForPlayer(normalizedKey) then
            return
        end

        available[tostring(normalizedKey)] = true
    end

    if includeAllAvailable and viewer.GetCooldownIDs then
        local okIDs, cooldownIDs = pcall(viewer.GetCooldownIDs, viewer)
        if okIDs and cooldownIDs then
            for _, cooldownID in ipairs(cooldownIDs) do
                AddIfUsable(cooldownID)
            end
        end
    end

    local container = viewer.viewerFrame or viewer
    for i = 1, select("#", container:GetChildren()) do
        local child = select(i, container:GetChildren())
        if child and (includeAllAvailable or child:IsShown()) and (child.Icon or child.icon) then
            local key = GetIconCooldownKeyStrict(child)
            AddIfUsable(key)
        end
    end

    return available
end

local function SortCooldownItems(items)
    table.sort(items, function(a, b)
        local aNum = tonumber(a.key)
        local bNum = tonumber(b.key)
        if aNum and bNum then
            return aNum < bNum
        end
        return tostring(a.key) < tostring(b.key)
    end)
end

local function EnsureClusterManualOrders(settings)
    settings.clusterManualOrders = settings.clusterManualOrders or {}
    return settings.clusterManualOrders
end

local function NormalizeKeyToString(key)
    local normalized = NormalizeCooldownKey(key)
    if not normalized then
        return nil
    end
    return tostring(normalized)
end

local function GetClusterManualOrder(settings, clusterIndex)
    local orders = EnsureClusterManualOrders(settings)
    orders[clusterIndex] = orders[clusterIndex] or {}
    return orders[clusterIndex]
end

local function RemoveKeyFromAllClusterOrders(settings, key)
    local normalizedKey = NormalizeKeyToString(key)
    if not normalizedKey then return end

    local orders = EnsureClusterManualOrders(settings)
    for _, orderList in pairs(orders) do
        if type(orderList) == "table" then
            for i = #orderList, 1, -1 do
                if tostring(orderList[i]) == normalizedKey then
                    table.remove(orderList, i)
                end
            end
        end
    end
end

local function AddKeyToClusterOrderEnd(settings, clusterIndex, key)
    local normalizedKey = NormalizeKeyToString(key)
    if not normalizedKey then return end

    local orderList = GetClusterManualOrder(settings, clusterIndex)
    for _, existing in ipairs(orderList) do
        if tostring(existing) == normalizedKey then
            return
        end
    end
    table.insert(orderList, normalizedKey)
end

local function MoveKeyInClusterOrder(settings, clusterIndex, key, direction)
    local normalizedKey = NormalizeKeyToString(key)
    if not normalizedKey then return false end

    local orderList = GetClusterManualOrder(settings, clusterIndex)
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

local function BuildOrderedKeysForCluster(settings, clusterIndex, availableKeys)
    local ordered = {}
    local added = {}

    settings.clusterAssignments = settings.clusterAssignments or {}
    local orderList = GetClusterManualOrder(settings, clusterIndex)

    local function CanUseKey(key)
        local normalizedKey = NormalizeKeyToString(key)
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
        if aNum and bNum then
            return aNum < bNum
        end
        return tostring(a) < tostring(b)
    end)

    for _, key in ipairs(leftovers) do
        table.insert(ordered, key)
    end

    return ordered
end

local function GetNearestClusterIndex(viewer, clusterCount, x, y)
    local viewerState = ViewerRuntimeState[viewer]
    local anchors = viewerState and viewerState.clusterAnchors
    if not anchors then
        return 1
    end

    local nearestIndex = 1
    local nearestDistance = math.huge
    for i = 1, clusterCount do
        local anchor = anchors[i]
        if anchor and anchor.GetCenter then
            local ax, ay = anchor:GetCenter()
            if ax and ay then
                local dx = ax - x
                local dy = ay - y
                local distance = (dx * dx) + (dy * dy)
                if distance < nearestDistance then
                    nearestDistance = distance
                    nearestIndex = i
                end
            end
        end
    end

    return nearestIndex
end

-- ===============================
-- CPU Optimization: Event-driven batching, dirty flags, strict throttling
-- ===============================
local _di_dirty = false
local _di_batchTimerPending = false
local _di_throttle = 0.10 -- seconds (10 Hz — layout is heavyweight, no need for 33 Hz)
local UpdateDynamicIconsBatch

local function IsInCombat() return InCombatLockdown() end

-- Pre-baked callback to avoid closure allocation per C_Timer.After
local function _di_batchTimerCallback()
    _di_batchTimerPending = false
    if UpdateDynamicIconsBatch then
        UpdateDynamicIconsBatch()
    end
    if _di_dirty then
        ScheduleDynamicIconsBatch(false)
    end
end

local function ScheduleDynamicIconsBatch(immediate)
    if _di_batchTimerPending then
        return
    end

    _di_batchTimerPending = true
    local delay = immediate and 0 or _di_throttle
    C_Timer.After(delay, _di_batchTimerCallback)
end

local function MarkDynamicIconsDirty(reason)
    _di_dirty = true
    ScheduleDynamicIconsBatch(false)
end

UpdateDynamicIconsBatch = function()
    if not _di_dirty then return end
    _di_dirty = false
    local viewer = _G["BuffIconCooldownViewer"]
    if not viewer or not viewer:IsShown() then return end
    if BuffIconViewers and BuffIconViewers.ApplyViewerLayout then
        BuffIconViewers:ApplyViewerLayout(viewer)
    end
end

local function UpsertKnownDisplayedItems(viewer)
    local items = CollectDisplayedCooldownItems(viewer)
    local activeKeys = {}
    for _, item in ipairs(items) do
        if item and item.key then
            activeKeys[tostring(item.key)] = true
            KnownDisplayedItemsByKey[item.key] = {
                key = item.key,
                name = item.name,
                icon = item.icon,
            }
            if item.icon then
                SampleIconTextureCache[item.key] = item.icon
            end
        end
    end

    for key in pairs(KnownDisplayedItemsByKey) do
        if not activeKeys[tostring(key)] then
            KnownDisplayedItemsByKey[key] = nil
        end
    end
end

local function BuildDisplayedItemsForOptions(viewer, settings, includeAllAvailable)
    return CollectDisplayedCooldownItems(viewer)
end

DYNAMICICONS = DYNAMICICONS or {}

-- SetupDynamicIconsEventHooks is defined later

-- Hook combat state events to manage batch frame lifecycle
local function SetupDynamicIconsEventHooks()
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("PLAYER_REGEN_DISABLED")
    ef:RegisterEvent("PLAYER_REGEN_ENABLED")
    ef:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_REGEN_DISABLED" then
            -- Entering combat: flush any pending dirty state
            if _di_dirty then ScheduleDynamicIconsBatch(true) end
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- Leaving combat: flush pending updates instead of discarding
            if _di_dirty then ScheduleDynamicIconsBatch(true) end
        end
    end)
end

SetupDynamicIconsEventHooks()

-- ---------------------------
-- External Icon Registry
-- Allows other modules (e.g. PowerPotionSuccessIcon) to inject frames into cluster layout
-- ---------------------------
DYNAMICICONS._externalClusterIcons = DYNAMICICONS._externalClusterIcons or {}

function DYNAMICICONS:RegisterExternalIcon(frame, key, clusterIndex)
    if not frame then return end
    clusterIndex = tonumber(clusterIndex) or 1
    key = tostring(key or "")
    -- Tag the frame so GetIconCooldownKey can find its key
    frame.cooldownID = tonumber(key) or nil
    frame.spellID = tonumber(key) or nil
    -- Also store an Icon reference so the layout recognizes it as a valid icon frame
    if not frame.Icon and not frame.icon then
        -- Look for an existing ARTWORK texture child
        for _, region in ipairs({ frame:GetRegions() }) do
            if region and region:IsObjectType("Texture") and region:GetDrawLayer() == "ARTWORK" then
                frame.Icon = region
                break
            end
        end
    end
    -- Store in registry
    self._externalClusterIcons[frame] = {
        frame = frame,
        key = key,
        clusterIndex = clusterIndex,
    }
    -- Trigger a layout refresh
    self:RefreshLayout()
end

function DYNAMICICONS:UnregisterExternalIcon(frame)
    if not frame then return end
    self._externalClusterIcons[frame] = nil
    -- Trigger a layout refresh
    self:RefreshLayout()
end

function DYNAMICICONS:RefreshLayout()
    MarkDynamicIconsDirty("RefreshLayout")
end

function DYNAMICICONS:RefreshVisibility()
    UpdateCooldownManagerVisibility()
end

function DYNAMICICONS:EnsureCooldownSettingsHooks()
    return InstallCooldownSettingsSampleHooks()
end

function DYNAMICICONS:IsSamplePreviewEnabled()
    return IsSamplePreviewEnabled()
end

function DYNAMICICONS:TriggerStartupSamplePreview(duration)
    local settings = self:GetSettings()
    if not settings or settings.startupSamplePreview == false or not settings.multiClusterMode then
        return
    end

    CancelStartupSamplePreviewTimer()
    _di_startupSamplePreviewEnabled = true
    ApplySamplePreviewState()

    local previewDuration = tonumber(duration) or 0.2
    if previewDuration <= 0 then
        return
    end

    _di_startupSamplePreviewTimer = C_Timer.NewTimer(previewDuration, function()
        _di_startupSamplePreviewTimer = nil
        _di_startupSamplePreviewEnabled = false
        ApplySamplePreviewState()
    end)
end

function DYNAMICICONS:SetOptionsPreviewEnabled(enabled)
    _di_optionsPreviewEnabled = enabled and true or false
    UpdateCooldownManagerVisibility()
    self:RefreshLayout()
end

function DYNAMICICONS:IsOptionsPreviewEnabled()
    return _di_optionsPreviewEnabled and true or false
end

function DYNAMICICONS:GetDisplayedItemsForOptions()
    local viewer = _G["BuffIconCooldownViewer"]
    local ok, items = pcall(CollectDisplayedCooldownItems, viewer)
    if ok and type(items) == "table" then
        return items
    end
    return {}
end

function DYNAMICICONS:GetAssignmentItemsForOptions()
    local viewer = _G["BuffIconCooldownViewer"]
    local ok, items = pcall(CollectDisplayedCooldownItems, viewer)
    if ok and type(items) == "table" then
        return items
    end
    return {}
end

function DYNAMICICONS:GetAllCooldownSettingItemsForOptions()
    local viewer = _G["BuffIconCooldownViewer"]
    if not viewer then
        return {}
    end

    UpsertKnownDisplayedItems(viewer)
    local availableKeys = BuildAvailableCooldownKeySet(viewer, true)

    local items = {}
    for key in pairs(availableKeys) do
        local keyStr = tostring(key)
        local known = KnownDisplayedItemsByKey[keyStr] or KnownDisplayedItemsByKey[tonumber(keyStr)]
        local spellID = ResolveCooldownKeySpellID(keyStr)

        local name = known and known.name or nil
        if (not name or name == "") and spellID and C_Spell and C_Spell.GetSpellName then
            name = C_Spell.GetSpellName(spellID)
        end

        local icon = known and known.icon or nil
        if (not icon or icon == "") and spellID and C_Spell and C_Spell.GetSpellTexture then
            icon = C_Spell.GetSpellTexture(spellID)
        end
        if (not icon or icon == "") then
            local settings = self:GetSettings()
            icon = SampleIconTextureCache[keyStr]
            if (not icon or icon == "") and settings and settings.clusterSampleIconsByKey then
                icon = settings.clusterSampleIconsByKey[keyStr]
            end
        end

        table.insert(items, {
            key = keyStr,
            name = name or ("CDID " .. keyStr),
            icon = icon,
        })
    end

    SortCooldownItems(items)
    return items
end

_G.CCM_GetDynamicIconsSpellList = function()
    if not DYNAMICICONS or type(DYNAMICICONS.GetDisplayedItemsForOptions) ~= "function" then
        return {}
    end
    local ok, items = pcall(DYNAMICICONS.GetDisplayedItemsForOptions, DYNAMICICONS)
    if ok and type(items) == "table" then
        return items
    end
    return {}
end

_G.CCM_GetDynamicIconsAssignmentSpellList = function()
    if not DYNAMICICONS or type(DYNAMICICONS.GetAssignmentItemsForOptions) ~= "function" then
        return {}
    end
    local ok, items = pcall(DYNAMICICONS.GetAssignmentItemsForOptions, DYNAMICICONS)
    if ok and type(items) == "table" then
        return items
    end
    return {}
end

_G.CCM_GetDynamicIconsAllSettingsSpellList = function()
    if not DYNAMICICONS or type(DYNAMICICONS.GetAllCooldownSettingItemsForOptions) ~= "function" then
        return {}
    end
    local ok, items = pcall(DYNAMICICONS.GetAllCooldownSettingItemsForOptions, DYNAMICICONS)
    if ok and type(items) == "table" then
        return items
    end
    return {}
end

local function GetSampleTextureForKey(key)
    if not key then
        return "Interface\\ICONS\\INV_Misc_QuestionMark"
    end

    key = tostring(key)

    local cached = SampleIconTextureCache[key]
    if cached and cached ~= "" then
        return cached
    end

    local settings = DYNAMICICONS and DYNAMICICONS.GetSettings and DYNAMICICONS:GetSettings()
    local saved = settings and settings.clusterSampleIconsByKey and settings.clusterSampleIconsByKey[key]
    if saved and saved ~= "" then
        SampleIconTextureCache[key] = saved
        return saved
    end

    local spellID = tonumber(key)
    if spellID and C_Spell and C_Spell.GetSpellTexture then
        local texture = C_Spell.GetSpellTexture(spellID)
        if texture and texture ~= "" then
            SampleIconTextureCache[key] = texture
            if settings then
                settings.clusterSampleIconsByKey = settings.clusterSampleIconsByKey or {}
                settings.clusterSampleIconsByKey[key] = texture
            end
            return texture
        end
    end

    return "Interface\\ICONS\\INV_Misc_QuestionMark"
end

local function HideClusterSampleIcons(viewer)
    local viewerState = ViewerRuntimeState[viewer]
    if not viewerState or not viewerState.clusterSampleIcons then return end

    for _, textureList in pairs(viewerState.clusterSampleIcons) do
        if textureList then
            for _, texture in ipairs(textureList) do
                if texture then texture:Hide() end
            end
        end
    end
end

local function RenderClusterSampleIcons(viewer, settings, clusterCount, rowLimit, defaultIconSize, spacing, opts)
    opts = opts or {}
    local unlockPreview = opts.unlockPreview and true or false
    local forceShowSamples = opts.forceShowSamples and true or false
    local activeKeysByCluster = opts.activeKeysByCluster or {}
    local availableKeys = opts.availableKeys or {}
    local centerClusterIcons = settings.clusterCenterIcons ~= false

    local viewerState = GetViewerState(viewer)
    viewerState.clusterSampleIcons = viewerState.clusterSampleIcons or {}

    local groupedSampleKeys = {}
    for i = 1, clusterCount do
        groupedSampleKeys[i] = BuildOrderedKeysForCluster(settings, i, availableKeys)
    end

    for groupIndex = 1, clusterCount do
        local anchor = viewerState.clusterAnchors and viewerState.clusterAnchors[groupIndex]
        if anchor then
            local clusterIconSize = SafeNumber(settings.clusterIconSizes and settings.clusterIconSizes[groupIndex], defaultIconSize)
            local hSpacing = SafeNumber(settings.clusterHorizontalSpacings and settings.clusterHorizontalSpacings[groupIndex], spacing)
            local vSpacing = spacing
            local mode = string.lower(tostring((settings.clusterSampleDisplayModes and settings.clusterSampleDisplayModes[groupIndex]) or "off"))
            local showSamples = unlockPreview or forceShowSamples or mode == "always"

            local clusterFlow = string.lower(tostring(settings.clusterFlows[groupIndex] or settings.clusterFlow or DEFAULTS.clusterFlow))
            local verticalGrow = string.lower(tostring(settings.clusterVerticalGrows[groupIndex] or "down"))
            local verticalPin = string.lower(tostring(settings.clusterVerticalPins[groupIndex] or "center"))

            if clusterFlow ~= "vertical" then clusterFlow = "horizontal" end
            if verticalGrow ~= "up" then verticalGrow = "down" end
            if verticalPin ~= "top" and verticalPin ~= "bottom" then verticalPin = "center" end

            local sampleKeys = groupedSampleKeys[groupIndex]

            local sampleCount = #sampleKeys
            local textureList = viewerState.clusterSampleIcons[groupIndex] or {}
            viewerState.clusterSampleIcons[groupIndex] = textureList

            if not showSamples then
                for _, texture in ipairs(textureList) do
                    if texture then texture:Hide() end
                end
            else
                local lineSize = sampleCount
                local lineCount = 1
                if rowLimit and rowLimit > 0 and sampleCount > 0 then
                    lineSize = math.max(1, rowLimit)
                    lineCount = math.ceil(sampleCount / lineSize)
                end

                local columns
                local rows
                if sampleCount == 0 then
                    columns, rows = 1, 1
                elseif clusterFlow == "vertical" then
                    rows = math.min(sampleCount, lineSize)
                    columns = lineCount
                else
                    columns = math.min(sampleCount, lineSize)
                    rows = lineCount
                end

                local groupWidth = columns * clusterIconSize + (columns - 1) * hSpacing
                local groupHeight = rows * clusterIconSize + (rows - 1) * vSpacing

                if sampleCount == 0 then
                    anchor:SetSize(120, 120)
                else
                    local paddedW = math.max(120, groupWidth + 12)
                    local paddedH = math.max(120, groupHeight + 24)
                    anchor:SetSize(paddedW, paddedH)
                end

                local anchorHeight = anchor:GetHeight() or 120
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

                for idx, key in ipairs(sampleKeys) do
                    local rowIndex
                    local colIndex
                    if clusterFlow == "vertical" then
                        rowIndex = (idx - 1) % lineSize
                        colIndex = math.floor((idx - 1) / lineSize)
                    else
                        rowIndex = math.floor((idx - 1) / lineSize)
                        colIndex = (idx - 1) % lineSize
                    end

                    local texture = textureList[idx]
                    if not texture then
                        texture = anchor:CreateTexture(nil, "BACKGROUND")
                        textureList[idx] = texture
                    end

                    texture:SetTexture(GetSampleTextureForKey(key))
                    texture:SetSize(clusterIconSize, clusterIconSize)
                    texture:ClearAllPoints()
                    if texture.SetDesaturated then
                        texture:SetDesaturated(not unlockPreview)
                    end
                    if unlockPreview then
                        texture:SetVertexColor(1, 1, 1, 1)
                    else
                        texture:SetVertexColor(0.65, 0.65, 0.65, 0.85)
                    end

                    if clusterFlow == "vertical" then
                        local x = 5 + (clusterIconSize / 2) + colIndex * (clusterIconSize + hSpacing)
                        local y
                        if verticalPin == "center" or verticalGrow == "up" then
                            y = yBase + rowIndex * (clusterIconSize + vSpacing)
                        else
                            y = yBase - rowIndex * (clusterIconSize + vSpacing)
                        end
                        texture:SetPoint("CENTER", anchor, "BOTTOMLEFT", x, y)
                    else
                        if centerClusterIcons then
                            local x = -groupWidth / 2 + clusterIconSize / 2 + colIndex * (clusterIconSize + hSpacing)
                            local y = groupHeight / 2 - clusterIconSize / 2 - rowIndex * (clusterIconSize + vSpacing)
                            texture:SetPoint("CENTER", anchor, "CENTER", x, y)
                        else
                            local x = 5 + (clusterIconSize / 2) + colIndex * (clusterIconSize + hSpacing)
                            local y = (anchorHeight - 5) - (clusterIconSize / 2) - rowIndex * (clusterIconSize + vSpacing)
                            texture:SetPoint("CENTER", anchor, "BOTTOMLEFT", x, y)
                        end
                    end

                    texture:Show()
                end

                for idx = sampleCount + 1, #textureList do
                    if textureList[idx] then
                        textureList[idx]:Hide()
                    end
                end
            end
        end
    end

    for groupIndex = clusterCount + 1, MAX_CLUSTER_GROUPS do
        local textureList = viewerState.clusterSampleIcons[groupIndex]
        if textureList then
            for _, texture in ipairs(textureList) do
                if texture then texture:Hide() end
            end
        end
    end
end

-- Forward-declare so EnsureClusterAnchorForIndex can reference it (defined later)
local ShowIconClusterContextMenu

local function RepositionClusterAnchor(anchor, settings, index)
    local saved = settings.clusterPositions and settings.clusterPositions[index]
    local fallback = GetDefaultClusterPosition(index)
    local point = (saved and saved.point) or fallback.point
    local relPoint = (saved and saved.relPoint) or point
    local x = (saved and saved.x) or fallback.x
    local y = (saved and saved.y) or fallback.y
    anchor:ClearAllPoints()
    anchor:SetPoint(point, UIParent, relPoint, x, y)
end

local function EnsureClusterAnchorForIndex(viewer, settings, index)
    local viewerState = GetViewerState(viewer)
    viewerState.clusterAnchors = viewerState.clusterAnchors or {}
    local anchors = viewerState.clusterAnchors

    if anchors[index] then
        -- Re-apply position from current settings (may differ after profile/spec swap)
        RepositionClusterAnchor(anchors[index], settings, index)
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
    anchor:SetBackdropBorderColor(0.8, 0.6, 0.2, 0.9)

    local label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOP", 0, -4)
    label:SetText("Cluster " .. index)
    anchor._clusterLabel = label
    anchor._clusterIndex = index
    label:Hide()

    anchor:SetScript("OnDragStart", function(self)
        local s = DYNAMICICONS:GetSettings()
        -- Allow drag in Edit Mode even when clusters are locked
        local editModeActive = IsEditModeActive()
        if not editModeActive and (not s or not s.clusterUnlocked) then return end
        if InCombatLockdown() then return end
        self:SetMovable(true)
        self:StartMoving()
    end)
    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()

        local s = DYNAMICICONS:GetSettings()
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
    anchors[index] = anchor

    RepositionClusterAnchor(anchor, settings, index)
    anchor:Hide()

    -- Register with LibEditMode for proper Edit Mode selection/drag
    if LibEditMode then
        local fallback = GetDefaultClusterPosition(index)
        LibEditMode:AddFrame(anchor, function(frame, lName, pt, fx, fy)
            local s = DYNAMICICONS:GetSettings()
            if not s then return end
            s.clusterPositions = s.clusterPositions or {}
            s.clusterPositions[index] = {
                point = pt or "CENTER",
                relPoint = pt or "CENTER",
                x = fx or 0,
                y = fy or 0,
            }
            -- Refresh layout so icons follow the new position
            if DYNAMICICONS.RefreshLayout then
                DYNAMICICONS:RefreshLayout()
            end
        end, fallback, "Icon Cluster " .. index)

        LibEditMode:AddFrameSettings(anchor, {
            {
                kind = LibEditMode.SettingType.Slider,
                name = "Icon Size",
                default = 36,
                get = function()
                    local s = DYNAMICICONS:GetSettings()
                    return s and s.clusterIconSizes and s.clusterIconSizes[index] or (s and s.iconSize) or 36
                end,
                set = function(_, newValue)
                    local s = DYNAMICICONS:GetSettings()
                    if s then
                        s.clusterIconSizes = s.clusterIconSizes or {}
                        s.clusterIconSizes[index] = newValue
                        DYNAMICICONS:RefreshLayout()
                    end
                end,
                minValue = 8, maxValue = 128, valueStep = 1,
            },
            {
                kind = LibEditMode.SettingType.Dropdown,
                name = "Flow Direction",
                default = "horizontal",
                get = function()
                    local s = DYNAMICICONS:GetSettings()
                    return s and s.clusterFlows and s.clusterFlows[index] or "horizontal"
                end,
                set = function(_, newValue)
                    local s = DYNAMICICONS:GetSettings()
                    if s then
                        s.clusterFlows = s.clusterFlows or {}
                        s.clusterFlows[index] = newValue
                        DYNAMICICONS:RefreshLayout()
                    end
                end,
                values = {
                    { text = "Horizontal", value = "horizontal" },
                    { text = "Vertical",   value = "vertical" },
                },
            },
            {
                kind = LibEditMode.SettingType.Slider,
                name = "Horizontal Spacing",
                default = 0,
                get = function()
                    local s = DYNAMICICONS:GetSettings()
                    if not s then return 0 end
                    return s.clusterHorizontalSpacings and s.clusterHorizontalSpacings[index] or s.spacing or 0
                end,
                set = function(_, newValue)
                    local s = DYNAMICICONS:GetSettings()
                    if s then
                        s.clusterHorizontalSpacings = s.clusterHorizontalSpacings or {}
                        s.clusterHorizontalSpacings[index] = newValue
                        DYNAMICICONS:RefreshLayout()
                    end
                end,
                minValue = 0, maxValue = 100, valueStep = 1,
            },
            {
                kind = LibEditMode.SettingType.Dropdown,
                name = "Grow Direction",
                default = "down",
                get = function()
                    local s = DYNAMICICONS:GetSettings()
                    return s and s.clusterVerticalGrows and s.clusterVerticalGrows[index] or "down"
                end,
                set = function(_, newValue)
                    local s = DYNAMICICONS:GetSettings()
                    if s then
                        s.clusterVerticalGrows = s.clusterVerticalGrows or {}
                        s.clusterVerticalGrows[index] = newValue
                        DYNAMICICONS:RefreshLayout()
                    end
                end,
                values = {
                    { text = "Down", value = "down" },
                    { text = "Up",   value = "up" },
                },
            },
            {
                kind = LibEditMode.SettingType.Dropdown,
                name = "Vertical Pin",
                default = "top",
                get = function()
                    local s = DYNAMICICONS:GetSettings()
                    return s and s.clusterVerticalPins and s.clusterVerticalPins[index] or "top"
                end,
                set = function(_, newValue)
                    local s = DYNAMICICONS:GetSettings()
                    if s then
                        s.clusterVerticalPins = s.clusterVerticalPins or {}
                        s.clusterVerticalPins[index] = newValue
                        DYNAMICICONS:RefreshLayout()
                    end
                end,
                values = {
                    { text = "Pin Top",    value = "top" },
                    { text = "Pin Center", value = "center" },
                    { text = "Pin Bottom", value = "bottom" },
                },
            },
            {
                kind = LibEditMode.SettingType.Dropdown,
                name = "Display Mode",
                default = "off",
                get = function()
                    local s = DYNAMICICONS:GetSettings()
                    return s and s.clusterSampleDisplayModes and s.clusterSampleDisplayModes[index] or "off"
                end,
                set = function(_, newValue)
                    local s = DYNAMICICONS:GetSettings()
                    if s then
                        s.clusterSampleDisplayModes = s.clusterSampleDisplayModes or {}
                        s.clusterSampleDisplayModes[index] = newValue
                        DYNAMICICONS:RefreshLayout()
                    end
                end,
                values = {
                    { text = "Hide Inactive", value = "off" },
                    { text = "Show Inactive", value = "always" },
                },
            },
            { kind = LibEditMode.SettingType.Divider, name = "divider_text", default = false },
            {
                kind = LibEditMode.SettingType.Slider,
                name = "Cooldown Text Size",
                default = 0,
                get = function()
                    local s = DYNAMICICONS:GetSettings()
                    return s and s.clusterCooldownTextSizes and s.clusterCooldownTextSizes[index] or 0
                end,
                set = function(_, newValue)
                    local s = DYNAMICICONS:GetSettings()
                    if s then
                        s.clusterCooldownTextSizes = s.clusterCooldownTextSizes or {}
                        s.clusterCooldownTextSizes[index] = newValue > 0 and newValue or nil
                        DYNAMICICONS:RefreshLayout()
                    end
                end,
                minValue = 0, maxValue = 36, valueStep = 1,
                formatter = function(v) return v == 0 and "Global" or tostring(v) end,
            },
            {
                kind = LibEditMode.SettingType.ColorPicker,
                name = "Cooldown Text Color",
                default = CreateColor(1, 1, 1, 1),
                hasOpacity = true,
                get = function()
                    local s = DYNAMICICONS:GetSettings()
                    local c = s and s.clusterCooldownTextColors and s.clusterCooldownTextColors[index]
                    if c then return CreateColor(c.r or 1, c.g or 1, c.b or 1, c.a or 1) end
                    return CreateColor(1, 1, 1, 1)
                end,
                set = function(_, newValue)
                    local s = DYNAMICICONS:GetSettings()
                    if s then
                        s.clusterCooldownTextColors = s.clusterCooldownTextColors or {}
                        if newValue then
                            s.clusterCooldownTextColors[index] = { r = newValue.r, g = newValue.g, b = newValue.b, a = newValue.a or 1 }
                        else
                            s.clusterCooldownTextColors[index] = nil
                        end
                        DYNAMICICONS:RefreshLayout()
                    end
                end,
            },
            {
                kind = LibEditMode.SettingType.Slider,
                name = "Charge Text Size",
                default = 0,
                get = function()
                    local s = DYNAMICICONS:GetSettings()
                    return s and s.clusterChargeTextSizes and s.clusterChargeTextSizes[index] or 0
                end,
                set = function(_, newValue)
                    local s = DYNAMICICONS:GetSettings()
                    if s then
                        s.clusterChargeTextSizes = s.clusterChargeTextSizes or {}
                        s.clusterChargeTextSizes[index] = newValue > 0 and newValue or nil
                        DYNAMICICONS:RefreshLayout()
                    end
                end,
                minValue = 0, maxValue = 72, valueStep = 1,
                formatter = function(v) return v == 0 and "Global" or tostring(v) end,
            },
            {
                kind = LibEditMode.SettingType.ColorPicker,
                name = "Charge Text Color",
                default = CreateColor(1, 1, 1, 1),
                hasOpacity = true,
                get = function()
                    local s = DYNAMICICONS:GetSettings()
                    local c = s and s.clusterChargeTextColors and s.clusterChargeTextColors[index]
                    if c then return CreateColor(c.r or 1, c.g or 1, c.b or 1, c.a or 1) end
                    return CreateColor(1, 1, 1, 1)
                end,
                set = function(_, newValue)
                    local s = DYNAMICICONS:GetSettings()
                    if s then
                        s.clusterChargeTextColors = s.clusterChargeTextColors or {}
                        if newValue then
                            s.clusterChargeTextColors[index] = { r = newValue.r, g = newValue.g, b = newValue.b, a = newValue.a or 1 }
                        else
                            s.clusterChargeTextColors[index] = nil
                        end
                        DYNAMICICONS:RefreshLayout()
                    end
                end,
            },
        })
    end

    return anchor
end

-- ===========================
-- Persistent "Always Show" Icons
-- ===========================
local _di_persistentIcons = {}   -- { [spellKey] = frame }
local _di_persistentPool = {}    -- recycled frames

-- Forward-declare duplicate icon pool (populated later)
local _di_duplicateIcons = {}  -- { ["key_ci"] = frame }
local _di_duplicatePool = {}   -- recycled frames

-- Forward-declare so UpdatePersistentIconCooldown can reference it (defined later)
local HookSourceIconForDuplicates

local function GetOrCreatePersistentIcon(spellKey)
    if _di_persistentIcons[spellKey] then
        return _di_persistentIcons[spellKey]
    end
    local frame = table.remove(_di_persistentPool)
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
        -- Pixel borders
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
    frame.spellID = tonumber(spellKey)  -- for GetIconCooldownKey compatibility
    -- Set texture
    local spellID = tonumber(spellKey)
    if spellID and C_Spell and C_Spell.GetSpellTexture then
        local tex = C_Spell.GetSpellTexture(spellID)
        if tex then frame.Icon:SetTexture(tex) end
    end
    _di_persistentIcons[spellKey] = frame
    return frame
end

local function UpdatePersistentIconCooldown(frame)
    local iconState = GetIconState(frame)
    local spellID = nil
    if frame._spellKey then
        spellID = ResolveCooldownKeySpellID(tostring(frame._spellKey))
    end
    spellID = spellID or tonumber(frame._spellKey)
    if not spellID then
        frame.Cooldown:Clear()
        frame:SetAlpha(0.5)
        iconState.ccmCdStart = 0
        iconState.ccmCdDur = 0
        return
    end
    -- Hook Cooldown to capture values for duplicates
    HookSourceIconForDuplicates(frame)
    -- Use durationObject API (secret-safe, no pcall needed)
    local durObj = C_Spell and C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(spellID)
    local cdInfo = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
    if durObj and cdInfo and cdInfo.isOnGCD ~= true then
        frame.Cooldown:SetCooldownFromDurationObject(durObj)
        frame:SetAlpha(1.0)
        iconState.ccmCdStart = tonumber(tostring(cdInfo.startTime or 0)) or 0
        iconState.ccmCdDur = tonumber(tostring(cdInfo.duration or 0)) or 0
    else
        frame.Cooldown:Clear()
        frame:SetAlpha(0.5)
        iconState.ccmCdStart = 0
        iconState.ccmCdDur = 0
    end
end

-- Persistent + duplicate icon update (event-driven, zero CPU when idle)
_di_persistentUpdateFrame = CreateFrame("Frame")
_di_persistentUpdateFrame:Hide()
_di_persistentUpdateFrame._batchPending = false
_di_persistentUpdateFrame._nextAllowed = 0
local _di_persistentThrottle = 0.3

local function RunPersistentDuplicateUpdate()
    _di_persistentUpdateFrame._nextAllowed = GetTime() + _di_persistentThrottle
    for _, frame in pairs(_di_persistentIcons) do
        if frame:IsShown() then
            UpdatePersistentIconCooldown(frame)
        end
    end
    for _, frame in pairs(_di_duplicateIcons) do
        if frame:IsShown() then
            local src = frame._sourceIcon
            if src and frame.Cooldown then
                local srcState = IconRuntimeState[src]
                local cdStart = srcState and srcState.ccmCdStart
                local cdDur   = srcState and srcState.ccmCdDur
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
                -- Mirror texture captured by our hook
                local hookedTex = srcState and srcState.ccmIconTexture
                if hookedTex and frame.Icon then
                    frame.Icon:SetTexture(hookedTex)
                end
            else
                UpdatePersistentIconCooldown(frame)
            end
        end
    end
end

-- Pre-baked callback for C_Timer.After (avoids closure allocation per event)
local function _di_persistentTimerCallback()
    _di_persistentUpdateFrame._batchPending = false
    RunPersistentDuplicateUpdate()
end

local function SchedulePersistentDuplicateUpdate(immediate)
    if _di_persistentUpdateFrame._batchPending then
        return
    end

    local now = GetTime()
    local delay = 0
    if not immediate and now < (_di_persistentUpdateFrame._nextAllowed or 0) then
        delay = _di_persistentUpdateFrame._nextAllowed - now
    end

    _di_persistentUpdateFrame._batchPending = true
    C_Timer.After(delay, _di_persistentTimerCallback)
end

-- Event registration deferred until persistent icons are created (avoids idle CPU)
_di_persistentUpdateFrame:SetScript("OnEvent", function(self)
    SchedulePersistentDuplicateUpdate(false)
end)

local function HideAllPersistentIcons()
    for _, frame in pairs(_di_persistentIcons) do
        StopGlow_DI(frame)
        local state = IconRuntimeState[frame]
        if state then state.glowActive = nil end
        frame:Hide()
    end
    _di_persistentUpdateFrame:Hide()
end

-- ===========================
-- Duplicate Icons (clone a spell into additional clusters)
-- Tables forward-declared above persistent icons section
-- ===========================

-- Install hooks on a source icon so we can capture its cooldown and texture
-- without reading tainted values.  hooksecurefunc receives untainted args.
local _ccm_hookedCooldowns = {}  -- set of Cooldown widgets already hooked
HookSourceIconForDuplicates = function(sourceIcon)
    if not sourceIcon then return end
    local srcState = IconRuntimeState[sourceIcon]
    if not srcState then
        srcState = {}
        IconRuntimeState[sourceIcon] = srcState
    end
    -- Hook the Cooldown widget's SetCooldown
    local cd = sourceIcon.Cooldown
    if cd and not _ccm_hookedCooldowns[cd] then
        _ccm_hookedCooldowns[cd] = true
        hooksecurefunc(cd, "SetCooldown", function(_self, start, duration)
            local state = IconRuntimeState[sourceIcon]
            if not state then state = {}; IconRuntimeState[sourceIcon] = state end
            state.ccmCdStart = start
            state.ccmCdDur = duration
        end)
        if cd.SetCooldownFromDurationObject then
            hooksecurefunc(cd, "SetCooldownFromDurationObject", function(_self, durObj)
                local state = IconRuntimeState[sourceIcon]
                if not state then state = {}; IconRuntimeState[sourceIcon] = state end
                state.ccmCdDurObj = durObj
            end)
        end
        hooksecurefunc(cd, "Clear", function()
            local state = IconRuntimeState[sourceIcon]
            if not state then state = {}; IconRuntimeState[sourceIcon] = state end
            state.ccmCdStart = 0
            state.ccmCdDur = 0
            state.ccmCdDurObj = nil
        end)
    end
    -- Hook the Icon texture's SetTexture
    local iconTex = sourceIcon.Icon or sourceIcon.icon
    if iconTex and iconTex.SetTexture and not srcState.ccmHookedTexture then
        srcState.ccmHookedTexture = true
        hooksecurefunc(iconTex, "SetTexture", function(_self, tex)
            local state = IconRuntimeState[sourceIcon]
            if not state then state = {}; IconRuntimeState[sourceIcon] = state end
            state.ccmIconTexture = tex
        end)
        -- Capture current texture right away
        pcall(function()
            local t = iconTex:GetTexture()
            if t then
                local state = IconRuntimeState[sourceIcon]
                if not state then state = {}; IconRuntimeState[sourceIcon] = state end
                state.ccmIconTexture = t
            end
        end)
    end
end

-- Style a duplicate icon's cooldown text to match ChargeTextColorOptions colors + settings
local function StyleDuplicateIconText(frame, settings)
    if not frame or not frame.Cooldown then return end
    local cd = frame.Cooldown
    -- Find or detect the cooldown timer FontString
    local cdText = cd.Text or cd.text
    if not cdText and cd.GetRegions then
        for _, region in ipairs({ cd:GetRegions() }) do
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                cdText = region
                break
            end
        end
    end
    if cdText and cdText.SetFont then
        local s = settings or {}
        local showCD = s.showCooldownText ~= false
        if showCD then
            cdText:Show()
            local fontSize = SafeNumber(s.cooldownTextSize, DEFAULTS.cooldownTextSize)
            cdText:SetFont(STANDARD_TEXT_FONT, fontSize, "OUTLINE")
            cdText:ClearAllPoints()
            local position = POSITION_PRESETS[s.cooldownTextPosition] or POSITION_PRESETS["CENTER"]
            local offsetX = SafeNumber(s.cooldownTextX, 0)
            local offsetY = SafeNumber(s.cooldownTextY, 0)
            cdText:SetPoint(position.point, frame, position.point, position.x + offsetX, position.y + offsetY)
            -- Apply color from ChargeTextColorOptions
            local color = (_G.CooldownChargeDB and _G.CooldownChargeDB["TextColor_CooldownText_Buff"]) or {1,1,1,1}
            if color then
                cdText:SetTextColor(color[1], color[2], color[3], color[4] or 1)
            end
        else
            cdText:Hide()
        end
    end
    -- Also apply the swipe color to match normal icons (aura style)
    pcall(function()
        cd:SetSwipeColor(1, 0.95, 0.57, 0.7)  -- ITEM_AURA_COLOR
        cd:SetDrawSwipe(true)
    end)
end

local function GetOrCreateDuplicateIcon(spellKey, clusterIndex)
    local cacheKey = tostring(spellKey) .. "_dup_" .. tostring(clusterIndex)
    if _di_duplicateIcons[cacheKey] then
        return _di_duplicateIcons[cacheKey]
    end
    local frame = table.remove(_di_duplicatePool)
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
    frame.cooldownID = tonumber(spellKey)
    local spellID = tonumber(spellKey)
    if spellID and C_Spell and C_Spell.GetSpellTexture then
        local tex = C_Spell.GetSpellTexture(spellID)
        if tex then frame.Icon:SetTexture(tex) end
    end
    _di_duplicateIcons[cacheKey] = frame
    return frame
end

local function HideAllDuplicateIcons()
    for _, frame in pairs(_di_duplicateIcons) do
        frame:Hide()
    end
end

function DYNAMICICONS:HideMountSuppressedDisplays()
    local viewer = _G["BuffIconCooldownViewer"]
    if viewer then
        HideClusterSampleIcons(viewer)
        HideClusterAnchors(viewer)
    end
    HideAllPersistentIcons()
    HideAllDuplicateIcons()
end

-- ===========================
-- Glow function bodies (all dependencies now in scope)
-- ===========================
StopGlow_DI = function(icon)
    if not LCG then return end
    local state = IconRuntimeState[icon]
    if not state or not state.glowActive then return end
    local gt = state.glowType
    local ok = pcall(function()
        if gt == "autocast" then LCG.AutoCastGlow_Stop(icon, "diGlow")
        elseif gt == "button" then
            -- Button glow pool implementations differ across addons and can throw on stop;
            -- we avoid the pooled stop path entirely for stability.
            if icon._ButtonGlow and icon._ButtonGlow.Hide then
                icon._ButtonGlow:Hide()
            end
            icon._ButtonGlow = nil
        elseif gt == "proc" then LCG.ProcGlow_Stop(icon, "diGlow")
        else LCG.PixelGlow_Stop(icon, "diGlow") end
    end)
    if not ok then
        -- LibCustomGlow can error if another system already released the pooled glow object.
    end
    state.glowActive = false
end

StartGlow_DI = function(icon, glowType, color)
    if not LCG or not icon then return end
    local state = IconRuntimeState[icon]
    if not state then
        state = {}
        IconRuntimeState[icon] = state
    end
    -- If already showing the same glow type, skip
    if state.glowType == glowType and state.glowActive then return end
    -- Stop previous glow if type changed
    if state.glowActive then StopGlow_DI(icon) end
    if glowType == "button" then
        glowType = "pixel"
    end
    state.glowType = glowType
    local c = color
    diGlowColor[1] = c and c.r or 1
    diGlowColor[2] = c and c.g or 1
    diGlowColor[3] = c and c.b or 0
    diGlowColor[4] = c and c.a or 1
    local ok = pcall(function()
        if glowType == "autocast" then
            LCG.AutoCastGlow_Start(icon, diGlowColor, 10, 0.25, 1, -1, -1, "diGlow")
        elseif glowType == "button" then
            LCG.ButtonGlow_Start(icon, diGlowColor, 0.125)
        elseif glowType == "proc" then
            _di_procGlowOpts.color = diGlowColor
            LCG.ProcGlow_Start(icon, _di_procGlowOpts)
        else
            LCG.PixelGlow_Start(icon, diGlowColor, 5, 0.25, 2, 1, -1, -1, false, "diGlow")
        end
    end)
    state.glowActive = ok and true or false
end

IsSpellOnCooldown_DI = function(icon)
    -- tostring() then tonumber() strips WoW secret-number taint
    local state = icon and IconRuntimeState[icon]

    local dur = state and state.ccmCdDur
    dur = dur and tonumber(tostring(dur))

    -- Persistent inactive icons can use durationObject path, so pull fresh spell cooldown as fallback.
    if (not dur or dur <= 0) and icon and icon._isPersistentIcon then
        local spellID = icon.spellID or tonumber(icon._spellKey)
        if icon._spellKey then
            spellID = ResolveCooldownKeySpellID(tostring(icon._spellKey)) or spellID
        end
        if spellID and C_Spell and C_Spell.GetSpellCooldown then
            local cdInfo = C_Spell.GetSpellCooldown(spellID)
            if cdInfo and cdInfo.isOnGCD ~= true then
                dur = tonumber(tostring(cdInfo.duration or 0)) or 0
            end
        end
    end

    return dur and dur > 1.5
end

-- Hoisted out of DispatchGlows_DI to avoid closure allocation every 0.5s tick.
-- Uses only module-level variables (_di_enabledGlowLookup, IconRuntimeState, etc.)
local function _di_processGlowIcon(icon)
    if not icon or not (icon.Icon or icon.icon) then return end
    HookSourceIconForDuplicates(icon)
    local state = IconRuntimeState[icon]
    if not state then
        state = {}
        IconRuntimeState[icon] = state
    end

    local curCdID = icon.cooldownID
    local curAuraID = icon.auraInstanceID
    local curSpellID = icon.spellID
    local key

    if curCdID ~= nil or curAuraID ~= nil or curSpellID ~= nil then
        if state._glowKeyCdID ~= curCdID or state._glowKeyAuraID ~= curAuraID or state._glowKeySpellID ~= curSpellID then
            state._glowKeyCdID = curCdID
            state._glowKeyAuraID = curAuraID
            state._glowKeySpellID = curSpellID
            state._glowKey = GetIconCooldownKey(icon)
        end
        key = state._glowKey
    else
        key = GetIconCooldownKey(icon)
        state._glowKey = key
    end

    if key then
        local keyStr = tostring(key)
        local glowCfg = _di_enabledGlowLookup[key] or _di_enabledGlowLookup[keyStr]

        if glowCfg then
            local glowTypeRaw = glowCfg.glowType
            if glowCfg.__ccmGlowTypeRaw ~= glowTypeRaw then
                glowCfg.__ccmGlowTypeRaw = glowTypeRaw
                glowCfg.__ccmGlowType = glowTypeRaw or "pixel"
            end
        end

        if glowCfg then
            local onCooldown = IsSpellOnCooldown_DI(icon)
            local shouldGlow = (not onCooldown)

            if glowCfg and shouldGlow then
                StartGlow_DI(icon, glowCfg.__ccmGlowType or "pixel", glowCfg.color)
            elseif state and state.glowActive then
                StopGlow_DI(icon)
                state.glowActive = nil
            end
        else
            if state and state.glowActive then
                StopGlow_DI(icon)
                state.glowActive = nil
            end
        end
    elseif state and state.glowActive then
        StopGlow_DI(icon)
        state.glowActive = nil
    end
end

DispatchGlows_DI = function(viewer, settings)
    if not viewer or not settings then return end
    local spellGlows = settings.spellGlows
    local spellSounds = settings.spellSounds

    if spellGlows ~= _di_glowCfgSource then
        RebuildEnabledGlowLookup_DI(spellGlows)
    end
    local soundRevision = GetSpellSoundsRevision_DI(settings)
    if spellSounds ~= _di_soundCfgSource or soundRevision ~= _di_soundCfgRevision then
        RebuildEnabledSoundLookup_DI(spellSounds)
        _di_soundCfgRevision = soundRevision
    end

    if not next(_di_enabledGlowLookup) and not next(_di_enabledSoundLookup) then
        for k in pairs(_di_soundActivePrevByKey) do _di_soundActivePrevByKey[k] = nil end
        for k in pairs(_di_soundPrevCfgByKey) do _di_soundPrevCfgByKey[k] = nil end
        for k in pairs(_di_soundPrevModeByKey) do _di_soundPrevModeByKey[k] = nil end
        return
    end

    if not next(_di_enabledSoundLookup) then
        for k in pairs(_di_soundActivePrevByKey) do _di_soundActivePrevByKey[k] = nil end
        for k in pairs(_di_soundPrevCfgByKey) do _di_soundPrevCfgByKey[k] = nil end
        for k in pairs(_di_soundPrevModeByKey) do _di_soundPrevModeByKey[k] = nil end
    end

    local activeSoundCfgByKey = {}
    local activeSoundModeByKey = {}
    local function TrackActiveSound(icon)
        if not icon or not icon.IsShown or not icon:IsShown() then return end
        local key = GetIconCooldownKey(icon)
        if not key then return end
        local keyStr = tostring(key)
        local cfg = _di_enabledSoundLookup[keyStr] or _di_enabledSoundLookup[key]
        if not cfg then return end
        local mode = tostring(cfg.mode or "expire")
        if mode == "ready" then mode = "expire" end
        activeSoundCfgByKey[keyStr] = cfg
        activeSoundModeByKey[keyStr] = mode
    end

    local pool = viewer.itemFramePool
    if pool then
        for child in pool:EnumerateActive() do
            _di_processGlowIcon(child)
            TrackActiveSound(child)
        end
    end
    for _, frame in pairs(_di_persistentIcons) do
        if frame and frame:IsShown() then
            _di_processGlowIcon(frame)
            TrackActiveSound(frame)
        end
    end
    for _, frame in pairs(_di_duplicateIcons) do
        if frame and frame:IsShown() then
            _di_processGlowIcon(frame)
            TrackActiveSound(frame)
        end
    end

    -- Start trigger: key became visible this pass.
    for keyStr, cfg in pairs(activeSoundCfgByKey) do
        local mode = activeSoundModeByKey[keyStr] or "expire"
        local playOnShow = (mode == "show" or mode == "both")
        if playOnShow and not _di_soundActivePrevByKey[keyStr] then
            PlaySpellSound_DI(keyStr, cfg)
        end
    end

    -- Expire trigger: key was visible last pass and is now gone.
    for keyStr in pairs(_di_soundActivePrevByKey) do
        if not activeSoundCfgByKey[keyStr] then
            local mode = _di_soundPrevModeByKey[keyStr] or "expire"
            local playOnExpire = (mode == "expire" or mode == "both")
            if playOnExpire then
                PlaySpellSound_DI(keyStr, _di_soundPrevCfgByKey[keyStr] or _di_enabledSoundLookup[keyStr])
            end
        end
    end

    -- Commit active sound state for next transition comparison.
    for k in pairs(_di_soundActivePrevByKey) do _di_soundActivePrevByKey[k] = nil end
    for k in pairs(_di_soundPrevCfgByKey) do _di_soundPrevCfgByKey[k] = nil end
    for k in pairs(_di_soundPrevModeByKey) do _di_soundPrevModeByKey[k] = nil end
    for keyStr, cfg in pairs(activeSoundCfgByKey) do
        _di_soundActivePrevByKey[keyStr] = true
        _di_soundPrevCfgByKey[keyStr] = cfg
        _di_soundPrevModeByKey[keyStr] = activeSoundModeByKey[keyStr] or "expire"
    end
end

EnsureGlowDispatchRunning = function(settings)
    if not settings then return end

    local hasGlows = RebuildEnabledGlowLookup_DI(settings.spellGlows)
    local hasSounds = RebuildEnabledSoundLookup_DI(settings.spellSounds)
    _di_soundCfgRevision = GetSpellSoundsRevision_DI(settings)

    _di_glowHasEnabled = hasGlows and true or false
    _di_soundHasEnabled = hasSounds and true or false

    if _di_glowHasEnabled or _di_soundHasEnabled then
        EnsureGlowEventFrame_DI(true)
        -- Only start ticker during combat with viewer visible
        _di_startGlowTickerIfNeeded()
        -- Always do one immediate dispatch so effects render now.
        local viewer = _G["BuffIconCooldownViewer"]
        if viewer and viewer:IsShown() then
            _di_glowDirty = false
            _di_glowIdleElapsed = 0
            DispatchGlows_DI(viewer, settings)
        end
    else
        _di_glowHasEnabled = false
        _di_soundHasEnabled = false
        StopGlowTicker_DI()
        EnsureGlowEventFrame_DI(false)
    end
end

-- Stop all active glows on every icon (used on profile/spec change)
local function StopAllGlows_DI()
    if not LCG then return end
    local viewer = _G["BuffIconCooldownViewer"]
    if viewer then
        local pool = viewer.itemFramePool
        if pool then
            for child in pool:EnumerateActive() do
                local s = IconRuntimeState[child]
                if s and s.glowActive then
                    StopGlow_DI(child)
                    s.glowActive = nil
                end
                -- Clear cached glow key so it re-resolves with new profile
                if s then s._glowKey = nil; s._glowKeyCdID = nil; s._glowKeyAuraID = nil; s._glowKeySpellID = nil end
            end
        end
    end
    for _, frame in pairs(_di_persistentIcons) do
        local s = IconRuntimeState[frame]
        if s and s.glowActive then StopGlow_DI(frame); s.glowActive = nil end
        if s then s._glowKey = nil end
    end
    for _, frame in pairs(_di_duplicateIcons) do
        local s = IconRuntimeState[frame]
        if s and s.glowActive then StopGlow_DI(frame); s.glowActive = nil end
        if s then s._glowKey = nil end
    end
end

-- Invalidate all glow + assignment caches (called on profile/spec change)
local function InvalidateGlowAndAssignmentCaches()
    -- Force glow lookup to rebuild from the new profile's spellGlows table
    _di_glowCfgSource = nil
    for k in pairs(_di_enabledGlowLookup) do _di_enabledGlowLookup[k] = nil end
    _di_glowHasEnabled = false
    _di_soundCfgSource = nil
    _di_soundCfgRevision = -1
    for k in pairs(_di_enabledSoundLookup) do _di_enabledSoundLookup[k] = nil end
    _di_soundHasEnabled = false
    for k in pairs(_di_soundLastPlayByKey) do _di_soundLastPlayByKey[k] = nil end
    _di_glowDirty = true
    -- Clear displayed-items cache so assignment lists refresh
    for k in pairs(KnownDisplayedItemsByKey) do KnownDisplayedItemsByKey[k] = nil end
end

-- Right-click context menu for icon cluster anchors
local iconClusterContextMenu = CreateFrame("Frame", "CkraigIconClusterContextMenu", UIParent, "UIDropDownMenuTemplate")

-- EasyMenu compat shim (removed in modern WoW retail)
local _EasyMenu = EasyMenu or function(menuList, menuFrame, anchor, x, y, displayMode)
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

ShowIconClusterContextMenu = function(anchor, settings, clusterIndex)
    local menuList = {}
    table.insert(menuList, { text = "Assigned Spells:", isTitle = true, notCheckable = true })
    local viewer = _G["BuffIconCooldownViewer"]
    -- Use the same displayed-items list the options panel uses (filters out stale/unknown spells)
    local displayedItems = CollectDisplayedCooldownItems(viewer)
    local displayedKeys = {}
    for _, item in ipairs(displayedItems) do
        displayedKeys[tostring(item.key)] = item
    end
    local spellsInCluster = {}
    for spellKey, ci in pairs(settings.clusterAssignments or {}) do
        local normalizedKey = tostring(spellKey)
        if tonumber(ci) == clusterIndex and displayedKeys[normalizedKey] then
            local item = displayedKeys[normalizedKey]
            table.insert(spellsInCluster, { key = normalizedKey, name = item.name, icon = item.icon })
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
                isTitle = true,
                notCheckable = true,
            })
        end
    end

    table.insert(menuList, { text = "", isTitle = true, notCheckable = true })
    table.insert(menuList, { text = "Close", notCheckable = true, func = function() CloseDropDownMenus() end })

    _EasyMenu(menuList, iconClusterContextMenu, "cursor", 0, 0, "MENU")
end

local function ApplyClusterDragState(viewer, settings, forceNow)
    if not viewer then return end
    if InCombatLockdown() and not forceNow then
        QueueInteractionRefresh(viewer)
        return
    end
    local samplePreviewActive = IsSamplePreviewEnabled()
    local viewerState = ViewerRuntimeState[viewer]
    if not viewerState or not viewerState.clusterAnchors then return end
    for i = 1, MAX_CLUSTER_GROUPS do
        local anchor = viewerState.clusterAnchors[i]
        if anchor then
            local inRange = settings.multiClusterMode and i <= settings.clusterCount
            local enabled = settings.clusterUnlocked and inRange
            local sampleMode = string.lower(tostring((settings.clusterSampleDisplayModes and settings.clusterSampleDisplayModes[i]) or "off"))
            local showForSamples = inRange and sampleMode == "always"
            local shouldShowAnchor = enabled or showForSamples or (samplePreviewActive and inRange)
            anchor:EnableMouse(enabled)
            if enabled then
                anchor:SetBackdropColor(0.25, 0.18, 0.02, 0.45)
                anchor:SetBackdropBorderColor(1.0, 0.82, 0.0, 1)
            elseif samplePreviewActive and inRange then
                anchor:SetBackdropColor(0.25, 0.18, 0.02, 0)
                anchor:SetBackdropBorderColor(1.0, 0.82, 0.0, 0)
            else
                anchor:SetBackdropColor(0.25, 0.18, 0.02, 0)
                anchor:SetBackdropBorderColor(1.0, 0.82, 0.0, 0)
            end
            anchor:SetShown(shouldShowAnchor)
            if anchor._clusterLabel then
                anchor._clusterLabel:SetText("Cluster " .. i)
                anchor._clusterLabel:SetTextColor(1.0, 0.82, 0.0, 1)
                anchor._clusterLabel:SetShown(enabled)
            end
        end
    end
end

ApplyViewerInteractionState = function(viewer, settings, forceNow)
    if not viewer then return end
    settings = settings or DYNAMICICONS:GetSettings()
    if not settings then return end

    if InCombatLockdown() and not forceNow then
        QueueInteractionRefresh(viewer)
        return
    end

    viewer:SetMovable(not settings.locked)
    viewer:EnableMouse(not settings.locked)
    ApplyClusterDragState(viewer, settings, true)
end

HideClusterAnchors = function(viewer)
    if not viewer then return end
    local viewerState = ViewerRuntimeState[viewer]
    if viewerState and viewerState.clusterAnchors then
        for i = 1, MAX_CLUSTER_GROUPS do
            local anchor = viewerState.clusterAnchors[i]
            if anchor then
                anchor:Hide()
            end
        end
    end
end

-- Edit Mode overlay for cluster anchors is now handled by LibEditMode.
-- The old blue-box overlay code has been replaced by proper LibEditMode
-- registration in EnsureClusterAnchorForIndex. LibEditMode provides the
-- standard Edit Mode selection highlight, drag behaviour, and settings dialog.

local function ShowClusterAnchorsEditMode(viewer)
    -- LibEditMode handles showing registered frames during Edit Mode.
    -- We only need to ensure all cluster anchors exist so they appear.
    if not viewer then return end
    local settings = DYNAMICICONS:GetSettings()
    if not settings or not settings.multiClusterMode then return end
    for ci = 1, math.min(settings.clusterCount or 0, MAX_CLUSTER_GROUPS) do
        EnsureClusterAnchorForIndex(viewer, settings, ci)
    end
end

local function HideClusterAnchorsEditMode(viewer)
    -- LibEditMode handles hiding selection overlays on exit.
    -- We just need to re-apply normal drag/visibility state.
    if not viewer then return end
    local settings = DYNAMICICONS:GetSettings()
    if settings then
        ApplyClusterDragState(viewer, settings, true)
    end
end

-- Expose show/hide for the toggle panel
function DYNAMICICONS:ShowClusterAnchorsEditMode()
    local v = _G["BuffIconCooldownViewer"]
    if v then ShowClusterAnchorsEditMode(v) end
end

function DYNAMICICONS:HideClusterAnchorsEditMode()
    local v = _G["BuffIconCooldownViewer"]
    if v then HideClusterAnchorsEditMode(v) end
end

-- ---------------------------
-- BuffIconViewers Core (initialize early)
-- ---------------------------
BuffIconViewers = BuffIconViewers or {}
BuffIconViewers.__pendingIcons = BuffIconViewers.__pendingIcons or {}
BuffIconViewers.__iconSkinEventFrame = BuffIconViewers.__iconSkinEventFrame or nil
BuffIconViewers.__pendingBackdrops = BuffIconViewers.__pendingBackdrops or {}
BuffIconViewers.__backdropEventFrame = BuffIconViewers.__backdropEventFrame or nil
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
            end
        end
    end
end

local noop = function() end
local function NeutralizeAtlasTexture(texture)
    if not texture then return end
    local textureState = TextureRuntimeState[texture]
    if not textureState then
        textureState = {}
        TextureRuntimeState[texture] = textureState
    end
    if not textureState.atlasNeutralized then
        textureState.atlasNeutralized = true
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
    if icon.GetRegions then
        for _, region in ipairs({ icon:GetRegions() }) do
            if region and region.IsObjectType and region:IsObjectType("Texture") then
                local atlas = region.GetAtlas and region:GetAtlas()
                if atlas and tostring(atlas):find("Debuff", 1, true) then
                    NeutralizeAtlasTexture(region)
                end
            end
        end
    end
end

-- Combat-safe deferred backdrop system
local function ProcessPendingBackdrops()
    if not BuffIconViewers.__pendingBackdrops then return end
    for frame, info in pairs(BuffIconViewers.__pendingBackdrops) do
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
                        BackdropPendingState[frame] = nil
                    BuffIconViewers.__pendingBackdrops[frame] = nil
                end
            end
        end
    end
end

local function EnsureBackdropEventFrame()
    if BuffIconViewers.__backdropEventFrame then return end
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("PLAYER_REGEN_ENABLED")
    ef:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_ENABLED" then
            ProcessPendingBackdrops()
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
    end)
    BuffIconViewers.__backdropEventFrame = ef
end

local function SafeSetBackdrop(frame, backdropInfo, color)
    if not frame or not frame.SetBackdrop then return false end

    if InCombatLockdown() then
        BackdropPendingState[frame] = true
        BuffIconViewers.__pendingBackdrops = BuffIconViewers.__pendingBackdrops or {}
        BuffIconViewers.__pendingBackdrops[frame] = { backdrop = backdropInfo, color = color }
        EnsureBackdropEventFrame()
        BuffIconViewers.__backdropEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return false
    end

    local okW, w = pcall(frame.GetWidth, frame)
    local okH, h = pcall(frame.GetHeight, frame)
    local dimsOk = false
    if okW and okH and w and h then
        dimsOk = type(w) == "number" and type(h) == "number" and w > 0 and h > 0
    end

    if not dimsOk then
        BackdropPendingState[frame] = true
        BuffIconViewers.__pendingBackdrops = BuffIconViewers.__pendingBackdrops or {}
        BuffIconViewers.__pendingBackdrops[frame] = { backdrop = backdropInfo, color = color }
        EnsureBackdropEventFrame()
        BuffIconViewers.__backdropEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
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
    local viewerFrame = viewer.viewerFrame
    if type(viewerFrame) == "string" then
        viewerFrame = _G[viewerFrame]
    end
    local container = viewerFrame or viewer
    for _, child in ipairs({ container:GetChildren() }) do
        if child then
            local state = IconRuntimeState[child]
            if state then
                state.skinned = nil
                state.skinPending = nil
                state.skinError = nil
            end
        end
    end
end

-- ---------------------------
-- SkinIcon (combined, robust)
-- ---------------------------
function BuffIconViewers:SkinIcon(icon, settings)
    if not icon then return false end

    local iconTexture = icon.Icon or icon.icon
    if not iconTexture then return false end

    settings = settings or DYNAMICICONS:GetSettings()
    local iconState = GetIconState(icon)

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
        local extra = cornerRadius * 0.003
        if extra > 0.08 then extra = 0.08 end
        left   = left   + extra
        right  = right  - extra
        top    = top    + extra
        bottom = bottom - extra
    end

    -- Apply computed texture coordinates (aspect ratio + corner radius)
    iconTexture:SetTexCoord(left, right, top, bottom)

    -- Add 1-pixel black border using four overlay textures
    if not iconState.pixelBorders then
        iconState.pixelBorders = {}
        -- Top
        local topBorder = icon:CreateTexture(nil, "OVERLAY")
        topBorder:SetColorTexture(0, 0, 0, 1)
        topBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        topBorder:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 0)
        topBorder:SetHeight(1)
        iconState.pixelBorders.top = topBorder
        -- Bottom
        local bottomBorder = icon:CreateTexture(nil, "OVERLAY")
        bottomBorder:SetColorTexture(0, 0, 0, 1)
        bottomBorder:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)
        bottomBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
        bottomBorder:SetHeight(1)
        iconState.pixelBorders.bottom = bottomBorder
        -- Left
        local leftB = icon:CreateTexture(nil, "OVERLAY")
        leftB:SetColorTexture(0, 0, 0, 1)
        leftB:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        leftB:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)
        leftB:SetWidth(1)
        iconState.pixelBorders.left = leftB
        -- Right
        local rightB = icon:CreateTexture(nil, "OVERLAY")
        rightB:SetColorTexture(0, 0, 0, 1)
        rightB:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 0)
        rightB:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
        rightB:SetWidth(1)
        iconState.pixelBorders.right = rightB
    end
    for _, border in pairs(iconState.pixelBorders) do border:Show() end

    -- Add shadow texture if not present
    if not iconState.shadow then
        local shadow = icon:CreateTexture(nil, "BACKGROUND")
        shadow:SetTexture("Interface\\BUTTONS\\UI-Quickslot-Depress")
        shadow:SetAllPoints(icon)
        shadow:SetVertexColor(0, 0, 0, 0.6)
        iconState.shadow = shadow
    end

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
        if cd.SetDrawSwipe then cd:SetDrawSwipe(settings.showSwipe) end
    end

    -- Pandemic + out of range alignment
    local picon = icon.PandemicIcon or icon.pandemicIcon or icon.Pandemic or icon.pandemic
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
            iconState.chargeTextRef = chargeText
            iconState.chargeAnchor = position.point
            iconState.chargeOffX = position.x + offsetX
            iconState.chargeOffY = position.y + offsetY
            -- Set charge/stack text color from ChargeTextColorOptions
            local color = (_G.CooldownChargeDB and _G.CooldownChargeDB["TextColor_ChargeText_Buff"]) or {1,1,1,1}
            if color and chargeText.SetTextColor then
                chargeText:SetTextColor(color[1], color[2], color[3], color[4] or 1)
            end
        else
            chargeText:Hide()
            iconState.chargeTextRef = nil
        end
    end

    -- Cooldown text detection and placement
    local cdText = nil
    if icon.Cooldown or icon.cooldown then
        local cd = icon.Cooldown or icon.cooldown
        cdText = cd.Text or cd.text

        if not cdText and cd.GetChildren then
            for _, child in ipairs({ cd:GetChildren() }) do
                if child and child.GetObjectType and child:GetObjectType() == "FontString" then
                    cdText = child
                    break
                end
            end
        end

        if not cdText and cd.GetRegions then
            for _, region in ipairs({ cd:GetRegions() }) do
                if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                    cdText = region
                    break
                end
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
            iconState.cdTextRef = cdText
            iconState.cdAnchor = position.point
            iconState.cdOffX = position.x + offsetX
            iconState.cdOffY = position.y + offsetY
            -- Set cooldown text color from ChargeTextColorOptions
            local color = (_G.CooldownChargeDB and _G.CooldownChargeDB["TextColor_CooldownText_Buff"]) or {1,1,1,1}
            if color and cdText.SetTextColor then
                cdText:SetTextColor(color[1], color[2], color[3], color[4] or 1)
            end
        else
            cdText:Hide()
            iconState.cdTextRef = nil
        end
    end

    -- Strip overlays and debuff borders
    StripBlizzardOverlay(icon)
    HideDebuffBorder(icon)

    -- ElvUI-style icon crop
    iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    iconState.skinned = true
    iconState.skinPending = nil
    return true
end

-- ---------------------------
-- Process pending icons (called after combat)
-- ---------------------------
function BuffIconViewers:ProcessPendingIcons()
    for icon, data in pairs(self.__pendingIcons) do
        if icon and icon:IsShown() and not GetIconState(icon).skinned then
            pcall(self.SkinIcon, self, icon, data.settings)
        end
        self.__pendingIcons[icon] = nil
    end
end

local function EnsurePendingEventFrame()
    if BuffIconViewers.__iconSkinEventFrame then return end
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("PLAYER_REGEN_ENABLED")
    ef:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_ENABLED" then
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            BuffIconViewers:ProcessPendingIcons()
            ProcessPendingBackdrops()
        end
    end)
    BuffIconViewers.__iconSkinEventFrame = ef
end

-- ---------------------------
-- Per-cluster text overrides
-- ---------------------------
local function ApplyPerClusterTextOverrides(icon, settings, clusterIndex)
    if not icon or not clusterIndex or not settings then return end
    local iconState = IconRuntimeState[icon]
    if not iconState then return end

    -- Cooldown text size override
    local cdTextSize = settings.clusterCooldownTextSizes and settings.clusterCooldownTextSizes[clusterIndex]
    if cdTextSize and cdTextSize > 0 and iconState.cdTextRef and iconState.cdTextRef.SetFont then
        iconState.cdTextRef:SetFont(STANDARD_TEXT_FONT, cdTextSize, "OUTLINE")
    end

    -- Charge text size override
    local chargeTextSize = settings.clusterChargeTextSizes and settings.clusterChargeTextSizes[clusterIndex]
    if chargeTextSize and chargeTextSize > 0 and iconState.chargeTextRef and iconState.chargeTextRef.SetFont then
        iconState.chargeTextRef:SetFont(STANDARD_TEXT_FONT, chargeTextSize, "OUTLINE")
    end

    -- Cooldown text color override
    local cdColor = settings.clusterCooldownTextColors and settings.clusterCooldownTextColors[clusterIndex]
    if cdColor and iconState.cdTextRef and iconState.cdTextRef.SetTextColor then
        iconState.cdTextRef:SetTextColor(cdColor.r or 1, cdColor.g or 1, cdColor.b or 1, cdColor.a or 1)
    end

    -- Charge text color override
    local chargeColor = settings.clusterChargeTextColors and settings.clusterChargeTextColors[clusterIndex]
    if chargeColor and iconState.chargeTextRef and iconState.chargeTextRef.SetTextColor then
        iconState.chargeTextRef:SetTextColor(chargeColor.r or 1, chargeColor.g or 1, chargeColor.b or 1, chargeColor.a or 1)
    end
end

-- ---------------------------
-- ApplyViewerLayout (layout + skinning)
-- ---------------------------
function BuffIconViewers:ApplyViewerLayout(viewer)
    if not viewer or not viewer.GetName then return end
    if not viewer:IsShown() then return end

    if IsEditModeActive() then
        -- LibEditMode manages cluster anchor visibility during Edit Mode
        return
    end

    local settings = DYNAMICICONS:GetSettings()
    if settings and settings.hideWhenMounted and IsPlayerMounted() and not IsSamplePreviewEnabled() then
        if DYNAMICICONS and DYNAMICICONS.HideMountSuppressedDisplays then
            DYNAMICICONS:HideMountSuppressedDisplays()
        end
        return
    end

    local viewerFrame = viewer.viewerFrame
    if type(viewerFrame) == "string" then
        viewerFrame = _G[viewerFrame]
    end
    local container = viewerFrame or viewer

    -- Use Blizzard's itemFramePool when available (zero-allocation iterator)
    local icons = _di_layoutIcons
    ClearTable(icons)
    local pool = viewer.itemFramePool
    local iconCount = 0
    if pool then
        for child in pool:EnumerateActive() do
            if child and (child.Icon or child.icon) then
                iconCount = iconCount + 1
                icons[iconCount] = child
            end
        end
    else
        for i = 1, select("#", container:GetChildren()) do
            local child = select(i, container:GetChildren())
            if child and (child.Icon or child.icon) then
                iconCount = iconCount + 1
                icons[iconCount] = child
            end
        end
    end
    for i = iconCount + 1, #icons do icons[i] = nil end

    if #icons == 0 then
        SetViewerMetric(viewer, "lastNumRows", 0)
        if not settings.multiClusterMode then
            return
        end
    end

    for i, icon in ipairs(icons) do
        local state = GetIconState(icon)
        if state.creationOrder == nil then
            state.creationOrder = i
        end
    end
    table.sort(icons, _di_iconSortComparator)

    local inCombat = InCombatLockdown()
    for _, icon in ipairs(icons) do
        local iconState = GetIconState(icon)
        if not iconState.skinned and not iconState.skinPending then
            iconState.skinPending = true
            if inCombat then
                EnsurePendingEventFrame()
                BuffIconViewers.__pendingIcons[icon] = { icon=icon, settings=settings, viewer=viewer }
                BuffIconViewers.__iconSkinEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            else
                BuffIconViewers:SkinIcon(icon, settings)
                iconState.skinPending = nil
            end
        end
    end

    local shownIcons = _di_layoutShown
    ClearTable(shownIcons)
    local shownCount = 0
    for i = 1, #icons do
        local icon = icons[i]
        if icon:IsShown() then
            shownCount = shownCount + 1
            shownIcons[shownCount] = icon
        end
    end
    for i = shownCount + 1, #shownIcons do shownIcons[i] = nil end

    local clusterCountForDrag = math.max(1, math.min(MAX_CLUSTER_GROUPS, SafeNumber(settings.clusterCount, DEFAULTS.clusterCount) or DEFAULTS.clusterCount))

    if #shownIcons == 0 then
        SetViewerMetric(viewer, "lastNumRows", 0)
        if not settings.multiClusterMode then
            return
        end
    end

    local iconSize = SafeNumber(settings.iconSize, DEFAULTS.iconSize)

    -- Default base size
    for _, icon in ipairs(shownIcons) do
        icon:SetSize(iconSize, iconSize)
    end

    local iconWidth, iconHeight = iconSize, iconSize
    local spacing = settings.spacing or DEFAULTS.spacing

    -- Static Grid Mode (per-row size does NOT affect static grid)
    if settings.staticGridMode then
        local gridRows = SafeNumber(settings.gridRows, DEFAULTS.gridRows)
        local gridCols = SafeNumber(settings.gridColumns, DEFAULTS.gridColumns)
        local totalWidth = gridCols * iconWidth + (gridCols - 1) * spacing
        local totalHeight = gridRows * iconHeight + (gridRows - 1) * spacing

        settings.gridSlotMap = settings.gridSlotMap or {}

        local usedSlots = {}
        for _, icon in ipairs(shownIcons) do
            local iconID = icon.spellID or icon.auraInstanceID or icon:GetID() or GetIconState(icon).creationOrder
            local key = tostring(iconID)
            if settings.gridSlotMap[key] then usedSlots[settings.gridSlotMap[key]] = true end
        end

        local nextSlot = 1
        for _, icon in ipairs(shownIcons) do
            local iconID = icon.spellID or icon.auraInstanceID or icon:GetID() or GetIconState(icon).creationOrder
            local key = tostring(iconID)
            if not settings.gridSlotMap[key] then
                while usedSlots[nextSlot] do nextSlot = nextSlot + 1 end
                settings.gridSlotMap[key] = nextSlot
                usedSlots[nextSlot] = true
                nextSlot = nextSlot + 1
            end
        end

        for _, icon in ipairs(shownIcons) do
            local iconID = icon.spellID or icon.auraInstanceID or icon:GetID() or GetIconState(icon).creationOrder
            local key = tostring(iconID)
            local slotNum = settings.gridSlotMap[key]
            if slotNum then
                local row = math.floor((slotNum - 1) / gridCols)
                local col = (slotNum - 1) % gridCols
                local x = -totalWidth / 2 + iconWidth / 2 + col * (iconWidth + spacing)
                local y = -totalHeight / 2 + iconHeight / 2 + row * (iconHeight + spacing)
                icon:ClearAllPoints()
                icon:SetPoint("CENTER", container, "CENTER", x, y)
            end
        end

        SetViewerMetric(viewer, "lastNumRows", gridRows)

        viewer:SetSize(totalWidth, totalHeight)
        return
    end

    -- Multi-cluster dynamic mode
    if settings.multiClusterMode then
        local clusterCount = math.max(1, math.min(MAX_CLUSTER_GROUPS, SafeNumber(settings.clusterCount, DEFAULTS.clusterCount) or DEFAULTS.clusterCount))
        settings.clusterCount = clusterCount
        settings.clusterFlows = settings.clusterFlows or {}
        settings.clusterVerticalGrows = settings.clusterVerticalGrows or {}
        settings.clusterVerticalPins = settings.clusterVerticalPins or {}
        settings.clusterHorizontalSpacings = settings.clusterHorizontalSpacings or {}
        settings.clusterIconSizes = settings.clusterIconSizes or {}
        settings.clusterSampleDisplayModes = settings.clusterSampleDisplayModes or {}
        settings.clusterAssignments = settings.clusterAssignments or {}
        settings.clusterManualOrders = settings.clusterManualOrders or {}
        if settings.clusterCenterIcons == nil then settings.clusterCenterIcons = DEFAULTS.clusterCenterIcons end
        local centerClusterIcons = settings.clusterCenterIcons ~= false

        local groupedIcons = {}
        for i = 1, clusterCount do
            groupedIcons[i] = {}
            local anchor = EnsureClusterAnchorForIndex(viewer, settings, i)
            if anchor then
                if anchor._clusterLabel then
                    anchor._clusterLabel:SetText("Cluster " .. i)
                end
            end
        end

        local viewerState = ViewerRuntimeState[viewer]
        if viewerState and viewerState.clusterAnchors then
            for i = clusterCount + 1, MAX_CLUSTER_GROUPS do
                local anchor = viewerState.clusterAnchors[i]
                if anchor then
                    anchor:Hide()
                end
            end
        end

        for _, icon in ipairs(shownIcons) do
            local key = GetIconCooldownKey(icon)
            local assignedGroup = tonumber(key and settings.clusterAssignments[key]) or 1
            if assignedGroup < 1 or assignedGroup > clusterCount then
                assignedGroup = 1
            end
            table.insert(groupedIcons[assignedGroup], icon)
        end

        -- Merge external icons (e.g. PowerPotionSuccessIcon) into cluster groups
        if DYNAMICICONS._externalClusterIcons then
            for _, extData in pairs(DYNAMICICONS._externalClusterIcons) do
                local extFrame = extData.frame
                if extFrame and extFrame.IsShown and extFrame:IsShown() then
                    local ci = tonumber(extData.clusterIndex) or 1
                    if ci < 1 or ci > clusterCount then ci = 1 end
                    -- Ensure it has an Icon ref and creation order for sorting
                    local iconState = GetIconState(extFrame)
                    if not iconState.creationOrder then
                        iconState.creationOrder = 99999
                    end
                    extFrame._isExternalClusterIcon = true
                    table.insert(groupedIcons[ci], extFrame)
                end
            end
        end

        -- Inject persistent "always show" icons for spells not currently active
        settings.clusterAlwaysShowSpells = settings.clusterAlwaysShowSpells or {}
        local _di_activeRealKeys = {}
        for ci = 1, clusterCount do
            for _, icon in ipairs(groupedIcons[ci]) do
                local key = GetIconCooldownKey(icon)
                if key then _di_activeRealKeys[tostring(key)] = true end
            end
        end
        local anyPersistentIcon = false
        for spellKey, enabled in pairs(settings.clusterAlwaysShowSpells) do
            if enabled and not _di_activeRealKeys[tostring(spellKey)] then
                local ci = tonumber(settings.clusterAssignments[spellKey]) or 1
                if ci >= 1 and ci <= clusterCount then
                    local pIcon = GetOrCreatePersistentIcon(spellKey)
                    pIcon:Show()
                    local iconState = GetIconState(pIcon)
                    if not iconState.creationOrder then iconState.creationOrder = 99998 end
                    if not iconState.skinned then
                        pcall(BuffIconViewers.SkinIcon, BuffIconViewers, pIcon, settings)
                    end
                    pIcon._isPersistentIcon = true
                    table.insert(groupedIcons[ci], pIcon)
                    anyPersistentIcon = true
                end
            end
        end
        -- Hide persistent icons whose spell now has a real icon or no longer always-show
        for key, frame in pairs(_di_persistentIcons) do
            if not settings.clusterAlwaysShowSpells[key] or _di_activeRealKeys[key] then
                StopGlow_DI(frame)
                local state = IconRuntimeState[frame]
                if state then state.glowActive = nil end
                frame:Hide()
            end
        end
        if anyPersistentIcon then
            _di_persistentUpdateFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
            SchedulePersistentDuplicateUpdate(true)
        end

        -- Build a lookup of real icons by spell key for duplicate source linking
        local _di_realIconByKey = {}
        for ci = 1, clusterCount do
            for _, icon in ipairs(groupedIcons[ci]) do
                if not icon._isDuplicateIcon and not icon._isPersistentIcon then
                    local key = GetIconCooldownKey(icon)
                    if key and not _di_realIconByKey[tostring(key)] then
                        _di_realIconByKey[tostring(key)] = icon
                    end
                end
            end
        end

        -- Inject duplicate icons into secondary clusters
        settings.clusterDuplicates = settings.clusterDuplicates or {}
        local anyDuplicateIcon = false
        local _di_activeDupKeys = {}  -- track which dup icons are used this pass
        for spellKey, dupClusters in pairs(settings.clusterDuplicates) do
            if type(dupClusters) == "table" then
                -- Only duplicate when the real icon is actively showing
                local sourceIcon = _di_realIconByKey[tostring(spellKey)]
                if sourceIcon and sourceIcon:IsShown() then
                    HookSourceIconForDuplicates(sourceIcon)
                    for ci, enabled in pairs(dupClusters) do
                        ci = tonumber(ci)
                        if enabled and ci and ci >= 1 and ci <= clusterCount then
                            local dupIcon = GetOrCreateDuplicateIcon(spellKey, ci)
                            dupIcon._sourceIcon = sourceIcon
                            StyleDuplicateIconText(dupIcon, settings)
                            dupIcon:Show()
                            local iconState = GetIconState(dupIcon)
                            if not iconState.creationOrder then iconState.creationOrder = 99997 end
                            if not iconState.skinned then
                                pcall(BuffIconViewers.SkinIcon, BuffIconViewers, dupIcon, settings)
                            end
                            dupIcon._isDuplicateIcon = true
                            table.insert(groupedIcons[ci], dupIcon)
                            anyDuplicateIcon = true
                            _di_activeDupKeys[tostring(spellKey) .. "_dup_" .. tostring(ci)] = true
                        end
                    end
                end
            end
        end
        -- Hide duplicate icons not used this pass
        for cacheKey, frame in pairs(_di_duplicateIcons) do
            if not _di_activeDupKeys[cacheKey] then
                frame:Hide()
            end
        end
        if anyDuplicateIcon then
            _di_persistentUpdateFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
            SchedulePersistentDuplicateUpdate(true)
        end

        local rowLimit = SafeNumber(settings.rowLimit or settings.columns, DEFAULTS.rowLimit)
        local availableKeys = BuildAvailableCooldownKeySet(viewer)

        local orderIndexByCluster = {}
        for i = 1, clusterCount do
            orderIndexByCluster[i] = {}
            local orderedKeys = BuildOrderedKeysForCluster(settings, i, availableKeys)
            for idx, key in ipairs(orderedKeys) do
                orderIndexByCluster[i][tostring(key)] = idx
            end

            table.sort(groupedIcons[i], function(a, b)
                local keyA = GetIconCooldownKey(a)
                local keyB = GetIconCooldownKey(b)
                local posA = keyA and orderIndexByCluster[i][tostring(keyA)] or nil
                local posB = keyB and orderIndexByCluster[i][tostring(keyB)] or nil

                if posA and posB and posA ~= posB then
                    return posA < posB
                end
                if posA and not posB then return true end
                if posB and not posA then return false end

                local aOrder = GetIconState(a).creationOrder
                local bOrder = GetIconState(b).creationOrder
                return (a.layoutIndex or a:GetID() or aOrder) < (b.layoutIndex or b:GetID() or bOrder)
            end)
        end
        local totalVisibleIcons = 0
        local activeKeysByCluster = {}
        for i = 1, clusterCount do
            activeKeysByCluster[i] = {}
            for _, icon in ipairs(groupedIcons[i]) do
                local key = GetIconCooldownKey(icon)
                if key then
                    activeKeysByCluster[i][key] = true
                end
            end
        end
        if settings.clusterUnlocked then
            RenderClusterSampleIcons(viewer, settings, clusterCount, rowLimit, iconSize, spacing, {
                unlockPreview = true,
                availableKeys = availableKeys,
            })
            ApplyClusterDragState(viewer, settings)
            SetViewerMetric(viewer, "lastNumRows", 1)
            SetViewerMetric(viewer, "iconCount", 0)
            return
        else
            RenderClusterSampleIcons(viewer, settings, clusterCount, rowLimit, iconSize, spacing, {
                unlockPreview = false,
                forceShowSamples = IsSamplePreviewEnabled(),
                activeKeysByCluster = activeKeysByCluster,
                availableKeys = availableKeys,
            })
        end

        for groupIndex = 1, clusterCount do
            local viewerState = ViewerRuntimeState[viewer]
            local anchor = viewerState and viewerState.clusterAnchors and viewerState.clusterAnchors[groupIndex]
            local groupIcons = groupedIcons[groupIndex]
            if anchor and groupIcons then
                local clusterFlow = string.lower(tostring(settings.clusterFlows[groupIndex] or settings.clusterFlow or DEFAULTS.clusterFlow))
                local verticalGrow = string.lower(tostring(settings.clusterVerticalGrows[groupIndex] or "down"))
                local verticalPin = string.lower(tostring(settings.clusterVerticalPins[groupIndex] or "center"))
                local clusterIconSize = SafeNumber(settings.clusterIconSizes[groupIndex], iconSize)
                local hSpacing = SafeNumber(settings.clusterHorizontalSpacings and settings.clusterHorizontalSpacings[groupIndex], spacing)
                local vSpacing = spacing
                if clusterFlow ~= "vertical" then
                    clusterFlow = "horizontal"
                end
                if verticalGrow ~= "up" then
                    verticalGrow = "down"
                end
                if verticalPin ~= "top" and verticalPin ~= "bottom" then
                    verticalPin = "center"
                end

                local sampleMode = string.lower(tostring((settings.clusterSampleDisplayModes and settings.clusterSampleDisplayModes[groupIndex]) or "off"))
                local followSampleSlots = (sampleMode == "always") or (not centerClusterIcons)

                local sampleKeys = {}
                local slotByKey = {}
                if followSampleSlots then
                    sampleKeys = BuildOrderedKeysForCluster(settings, groupIndex, availableKeys)

                    for idx, key in ipairs(sampleKeys) do
                        slotByKey[key] = idx
                    end
                end

                local groupCount = #groupIcons
                totalVisibleIcons = totalVisibleIcons + groupCount

                local anchorWidth = anchor:GetWidth() or 120
                local anchorHeight = anchor:GetHeight() or 120

                if groupCount == 0 then
                    -- Keep anchor size stable so icon #1 reference point does not shift as groups grow.
                else
                    local iconPlacements = {}
                    local maxPlacement = groupCount
                    if followSampleSlots then
                        maxPlacement = 0
                        local usedPlacements = {}

                        for idx, icon in ipairs(groupIcons) do
                            local key = GetIconCooldownKey(icon)
                            local placement = key and slotByKey[key] or nil

                            if placement and usedPlacements[placement] then
                                placement = nil
                            end

                            if not placement then
                                placement = 1
                                while usedPlacements[placement] do
                                    placement = placement + 1
                                end
                            end

                            usedPlacements[placement] = true
                            iconPlacements[idx] = placement
                            if placement > maxPlacement then
                                maxPlacement = placement
                            end
                        end

                        if #sampleKeys > maxPlacement then
                            maxPlacement = #sampleKeys
                        end
                    else
                        for idx = 1, groupCount do
                            iconPlacements[idx] = idx
                        end
                    end

                    local layoutCount = math.max(groupCount, maxPlacement)

                    local lineSize = layoutCount
                    local lineCount = 1
                    if rowLimit and rowLimit > 0 then
                        lineSize = math.max(1, rowLimit)
                        lineCount = math.ceil(layoutCount / lineSize)
                    end

                    local columns
                    local rows
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

                    for idx, icon in ipairs(groupIcons) do
                        local placementIndex = iconPlacements[idx] or idx
                        local rowIndex
                        local colIndex
                        if clusterFlow == "vertical" then
                            rowIndex = (placementIndex - 1) % lineSize
                            colIndex = math.floor((placementIndex - 1) / lineSize)
                        else
                            rowIndex = math.floor((placementIndex - 1) / lineSize)
                            colIndex = (placementIndex - 1) % lineSize
                        end

                        local iconState = GetIconState(icon)
                        if not iconState.dragging then
                            icon:SetSize(clusterIconSize, clusterIconSize)
                            icon:ClearAllPoints()

                            if clusterFlow == "vertical" then
                                local x = 5 + (clusterIconSize / 2) + colIndex * (clusterIconSize + hSpacing)
                                local y
                                if verticalPin == "center" then
                                    y = yBase + rowIndex * (clusterIconSize + vSpacing)
                                elseif verticalGrow == "up" then
                                    y = yBase + rowIndex * (clusterIconSize + vSpacing)
                                else
                                    y = yBase - rowIndex * (clusterIconSize + vSpacing)
                                end
                                icon:SetPoint("CENTER", anchor, "BOTTOMLEFT", x, y)
                            else
                                if centerClusterIcons then
                                    local groupWidth = columns * clusterIconSize + (columns - 1) * hSpacing
                                    local groupHeight = rows * clusterIconSize + (rows - 1) * vSpacing
                                    local x = -groupWidth / 2 + clusterIconSize / 2 + colIndex * (clusterIconSize + hSpacing)
                                    local y = groupHeight / 2 - clusterIconSize / 2 - rowIndex * (clusterIconSize + vSpacing)
                                    icon:SetPoint("CENTER", anchor, "CENTER", x, y)
                                else
                                    local x = 5 + (clusterIconSize / 2) + colIndex * (clusterIconSize + hSpacing)
                                    local y = (anchorHeight - 5) - (clusterIconSize / 2) - rowIndex * (clusterIconSize + vSpacing)
                                    icon:SetPoint("CENTER", anchor, "BOTTOMLEFT", x, y)
                                end
                            end
                        end
                    end
                end
                -- Apply per-cluster text size and color overrides
                for _, icon in ipairs(groupIcons) do
                    ApplyPerClusterTextOverrides(icon, settings, groupIndex)
                end
            end
        end

        ApplyClusterDragState(viewer, settings)
        SetViewerMetric(viewer, "lastNumRows", 1)
        SetViewerMetric(viewer, "iconCount", totalVisibleIcons)
        viewer._diLayoutInProgress = true
        viewer:SetSize(2, 2)
        viewer._diLayoutInProgress = false
        DispatchGlows_DI(viewer, settings)
        EnsureGlowDispatchRunning(settings)
        return
    else
        HideClusterSampleIcons(viewer)
        HideAllPersistentIcons()
        HideAllDuplicateIcons()
        local viewerState = ViewerRuntimeState[viewer]
        if viewerState and viewerState.clusterAnchors then
        for i = 1, MAX_CLUSTER_GROUPS do
            local anchor = viewerState.clusterAnchors[i]
            if anchor then
                anchor:Hide()
            end
        end
        end
    end

    -- Dynamic mode
    local rowLimit = SafeNumber(settings.rowLimit or settings.columns, DEFAULTS.rowLimit)

    -- Re-anchor viewer at its current center so resizing expands equally left/right
    if not InCombatLockdown() then
        local cx, cy = viewer:GetCenter()
        local parentFrame = viewer:GetParent() or UIParent
        if cx and cy then
            viewer:ClearAllPoints()
            viewer:SetPoint("CENTER", parentFrame, "BOTTOMLEFT", cx, cy)
        end
    end

    -- Single-row mode
    if rowLimit <= 0 then
        local rowSize = (settings.rowSizes and settings.rowSizes[1]) or iconSize
        for _, icon in ipairs(shownIcons) do
            icon:SetSize(rowSize, rowSize)
        end
        local totalWidth = #shownIcons * rowSize + (#shownIcons - 1) * spacing
        local startX = -totalWidth / 2 + rowSize / 2
        for i, icon in ipairs(shownIcons) do
            local x = startX + (i-1)*(rowSize+spacing)
            icon:ClearAllPoints()
            icon:SetPoint("CENTER", container, "CENTER", x, 0)
        end
        SetViewerMetric(viewer, "lastNumRows", 1)
        viewer._diLayoutInProgress = true
        viewer:SetSize(totalWidth, rowSize)
        viewer._diLayoutInProgress = false
    else
        -- Multi-row mode with per-row size
        local numRows = math.ceil(#shownIcons/rowLimit)
        local rows = {}
        local maxRowWidth = 0

        for r = 1, numRows do
            rows[r] = {}
            local startIdx = (r-1)*rowLimit + 1
            local endIdx = math.min(r*rowLimit, #shownIcons)
            for i=startIdx,endIdx do table.insert(rows[r], shownIcons[i]) end
        end

        local growDir = (settings.rowGrowDirection or DEFAULTS.rowGrowDirection):lower()

        -- Compute per-row heights so totalHeight and Y offsets account for varying row sizes
        local rowHeights = {}
        local totalHeight = 0
        for r = 1, numRows do
            rowHeights[r] = (settings.rowSizes and settings.rowSizes[r]) or iconSize
            totalHeight = totalHeight + rowHeights[r]
            if r < numRows then totalHeight = totalHeight + spacing end
        end

        for r = 1, numRows do
            local row = rows[r]

            local w = rowHeights[r]
            local h = w

            local rowWidth = #row * w + (#row - 1) * spacing
            if rowWidth > maxRowWidth then maxRowWidth = rowWidth end

            local startX = -rowWidth/2 + w/2

            -- Compute Y by accumulating heights of preceding rows
            local yOffset = 0
            for rr = 1, r - 1 do
                yOffset = yOffset + rowHeights[rr] + spacing
            end

            local y
            if growDir == "up" then
                y = -totalHeight/2 + h/2 + yOffset
            else
                y = totalHeight/2 - h/2 - yOffset
            end

            for i, icon in ipairs(row) do
                local x = startX + (i-1)*(w+spacing)
                icon:SetSize(w, h)
                icon:ClearAllPoints()
                icon:SetPoint("CENTER", container, "CENTER", x, y)
            end
        end

        SetViewerMetric(viewer, "lastNumRows", numRows)

        viewer._diLayoutInProgress = true
        viewer:SetSize(maxRowWidth, totalHeight)
        viewer._diLayoutInProgress = false
    end
    SetViewerMetric(viewer, "iconCount", #shownIcons)
    DispatchGlows_DI(viewer, settings)
    EnsureGlowDispatchRunning(settings)
end

function BuffIconViewers:RescanViewer(viewer)
    if not viewer or not viewer.GetName then return end
    BuffIconViewers:ApplyViewerLayout(viewer)
end
DYNAMICICONS = DYNAMICICONS or {}
DYNAMICICONS.IconViewers = BuffIconViewers

-- Initialize database reference
function DYNAMICICONS:InitializeDB()
    local fallbackSettings = nil
    if IsUsingFallbackDB(self.db) then
        fallbackSettings = self.db.profile.dynamicIcons
    end

    if CkraigProfileManager and CkraigProfileManager.db then
        self.db = CkraigProfileManager.db

        -- If we started on fallback settings before ProfileManager was ready,
        -- carry values forward so the session keeps user edits.
        self.db.profile.dynamicIcons = self.db.profile.dynamicIcons or {}
        if type(fallbackSettings) == "table" then
            for key, value in pairs(fallbackSettings) do
                if self.db.profile.dynamicIcons[key] == nil then
                    if type(value) == "table" then
                        self.db.profile.dynamicIcons[key] = DeepCopyTable(value)
                    else
                        self.db.profile.dynamicIcons[key] = value
                    end
                end
            end
        end

        return true
    else
        -- Fallback
        DYNAMICICONSDB = DYNAMICICONSDB or {}
        self.db = {
            profile = { dynamicIcons = DYNAMICICONSDB },
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
function DYNAMICICONS:GetSettings()
    if not self.db
        or (CkraigProfileManager and CkraigProfileManager.db and self.db ~= CkraigProfileManager.db)
    then
        self:InitializeDB()
    end
    return self.db.profile.dynamicIcons
end

-- Handle profile changes
function DYNAMICICONS:OnProfileChanged()
    -- Re-point to the (possibly new) profile DB immediately
    self:InitializeDB()
    EnsureDB()

    -- Immediately stop all active glows and invalidate caches so old profile
    -- glow configs don't bleed into the new spec/profile.
    StopAllGlows_DI()
    InvalidateGlowAndAssignmentCaches()

    -- Batch refreshes after a short delay (single timer)
    C_Timer.After(0.5, function()
        -- Re-read settings from the new profile
        EnsureDB()
        local viewer = _G["BuffIconCooldownViewer"]
        if viewer then
            -- Re-apply cluster anchor positions from the new profile
            local settings = self:GetSettings()
            if settings and settings.multiClusterMode then
                for ci = 1, math.min(settings.clusterCount or 0, MAX_CLUSTER_GROUPS) do
                    EnsureClusterAnchorForIndex(viewer, settings, ci)
                end
            end
            ForceReskinViewer(viewer)
            -- Refresh displayed items so assignment list matches the new profile
            UpsertKnownDisplayedItems(viewer)
            pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, viewer)
            if BuffIconViewers and BuffIconViewers.UpdateAllBuffs then
                pcall(BuffIconViewers.UpdateAllBuffs, BuffIconViewers)
            end
            -- Re-initialize glows from the new profile's settings
            if settings then
                EnsureGlowDispatchRunning(settings)
            end
        end
        UpdateCooldownManagerVisibility()
        if _G.DYNAMICICONSPanel and _G.DYNAMICICONSPanel._rebuildConfigUI then
            _G.DYNAMICICONSPanel:_rebuildConfigUI()
        end
    end)
end

local function PrimeDisplayedItemsOnLogin()
    local function TryUpdate()
        local viewer = _G["BuffIconCooldownViewer"]
        if viewer then
            pcall(UpsertKnownDisplayedItems, viewer)
            -- Immediately run the first layout so icons appear without delay
            pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, viewer)
            if not _di_startupSamplePreviewTriggered then
                _di_startupSamplePreviewTriggered = true
                DYNAMICICONS:TriggerStartupSamplePreview(0.2)
            end
        end
    end

    C_Timer.After(0.5, TryUpdate)
end

-- Initialize on load or when ProfileManager is ready
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
local didInit = false
local initAttempts = 0
local function ThrottledInit()
    if didInit then return end

    -- Try to initialize with ProfileManager
    if DYNAMICICONS:InitializeDB() then
        didInit = true
        PrimeDisplayedItemsOnLogin()
        return
    end
--this is currently what makes the icons not to be slowed...
    initAttempts = initAttempts + 1
    if initAttempts < 50 then
        C_Timer.After(0.5, ThrottledInit)
    else
        -- Stop retrying after a while and continue on fallback DB.
        didInit = true
        PrimeDisplayedItemsOnLogin()
    end
end
initFrame:SetScript("OnEvent", function()
    C_Timer.After(0.5, ThrottledInit)
end)

-- Initialize on load
DYNAMICICONS:InitializeDB()
-- ---------------------------
-- HookViewer
-- ---------------------------
local function HookViewer()
    local viewer = _G["BuffIconCooldownViewer"]
    if not viewer then return end

    InstallCooldownSettingsSampleHooks()

    ApplyViewerInteractionState(viewer, DYNAMICICONS:GetSettings())

    if LibEditMode and not BuffIconViewers.__editModeHooksInstalled then
        -- Enter Edit Mode: ensure all cluster anchors exist so LibEditMode can show them
        LibEditMode:RegisterCallback("enter", function()
            _di_inEditMode = true
            local v = _G["BuffIconCooldownViewer"]
            if not v then return end
            if InCombatLockdown() then
                QueueInteractionRefresh(v)
                return
            end
            v:Show()
            local s = DYNAMICICONS:GetSettings()
            if s and s.multiClusterMode then
                local count = math.min(s.clusterCount or 0, MAX_CLUSTER_GROUPS)
                for ci = 1, count do
                    EnsureClusterAnchorForIndex(v, s, ci)
                end
                -- Hide anchors beyond cluster count in Edit Mode
                local viewerState = ViewerRuntimeState[v]
                if viewerState and viewerState.clusterAnchors then
                    for ci = 1, MAX_CLUSTER_GROUPS do
                        local anchor = viewerState.clusterAnchors[ci]
                        if anchor then
                            local hidden = ci > count
                            LibEditMode:SetFrameEditModeHidden("Icon Cluster " .. ci, hidden)
                        end
                    end
                end
            end
        end)

        -- Exit Edit Mode: restore normal visibility and interaction state
        LibEditMode:RegisterCallback("exit", function()
            _di_inEditMode = false
            local v = _G["BuffIconCooldownViewer"]
            if v and InCombatLockdown() then
                QueueInteractionRefresh(v)
                return
            end
            UpdateCooldownManagerVisibility()
            if v and v:IsShown() then
                pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, v)
            end
            if v then
                ApplyViewerInteractionState(v, DYNAMICICONS:GetSettings())
            end
        end)

        BuffIconViewers.__editModeHooksInstalled = true
    end

    viewer:HookScript("OnShow", function(self)
        pcall(BuffIconViewers.RescanViewer, BuffIconViewers, self)
        pcall(UpsertKnownDisplayedItems, self)
        -- Start glow ticker if in combat and glows are enabled
        _di_startGlowTickerIfNeeded()
        -- Always do one immediate glow dispatch on show
        if _di_glowHasEnabled then
            local s = DYNAMICICONS:GetSettings()
            if s then DispatchGlows_DI(self, s) end
        end
    end)
    viewer:HookScript("OnHide", function(self)
        -- Stop glow ticker when viewer is hidden (zero idle CPU)
        StopGlowTicker_DI()
    end)
    viewer:HookScript("OnSizeChanged", function(self)
        if self._diLayoutInProgress then return end
        pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, self)
        pcall(UpsertKnownDisplayedItems, self)
    end)

    -- Hook Blizzard's RefreshLayout for instant response to layout changes
    if not BuffIconViewers.__refreshLayoutHooked then
        hooksecurefunc(viewer, "RefreshLayout", function(self)
            if IsEditModeActive() then return end
            if not self:IsShown() then return end
            pcall(BuffIconViewers.RescanViewer, BuffIconViewers, self)
            pcall(UpsertKnownDisplayedItems, self)
        end)
        BuffIconViewers.__refreshLayoutHooked = true
    end

    -- Event-driven refresh with batching, dirty flag, and strict throttling
    local viewerState = GetViewerState(viewer)
    if not viewerState.eventFrame then
        local ef = CreateFrame("Frame")
        ef:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        ef:RegisterUnitEvent("UNIT_AURA", "player")
        ef:RegisterEvent("PLAYER_REGEN_ENABLED")
        ef:Hide()
        ef._dirty = false
        ef._batchTimer = nil

        local _firstLayoutDone = false
        local function ScheduleLayoutBatch()
            if ef._batchTimer then return end
            ef._batchTimer = true
            -- First layout runs immediately (no delay); subsequent ones are throttled
            local delay = _firstLayoutDone and 0.05 or 0
            C_Timer.After(delay, function()
                ef._batchTimer = nil
                _firstLayoutDone = true
                if ef._dirty then
                    ef._dirty = false
                    if IsEditModeActive() then return end
                    if not viewer or not viewer:IsShown() then return end

                    if _G.CkraigCooldownManager and _G.CkraigCooldownManager.EnforceCooldownViewerScale then
                        _G.CkraigCooldownManager.EnforceCooldownViewerScale(viewer)
                    end
                    pcall(BuffIconViewers.RescanViewer, BuffIconViewers, viewer)
                end
            end)
        end

        ef:SetScript("OnEvent", function(self, event, arg1)
            -- During combat, _di_batchFrame handles layout updates; skip here to avoid double-processing
            if event ~= "PLAYER_REGEN_ENABLED" and InCombatLockdown() then
                -- During combat, feed the batch frame instead
                MarkDynamicIconsDirty(event)
                return
            end
            ef._dirty = true
            ScheduleLayoutBatch()
        end)

        viewerState.eventFrame = ef
    end
end

-- Ensure DB and try to hook immediately if the frame exists now
EnsureDB()
HookViewer()

-- If the BuffIconCooldownViewer is created later by another addon, ensure we hook when it's available
local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("ADDON_LOADED")
hookFrame:SetScript("OnEvent", function(self, event, name)
    if _G["BuffIconCooldownViewer"] then
        HookViewer()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-- ---------------------------
-- Config Panel (Interface Options) with safe deferred registration
-- ---------------------------

-- Modern dropdown helper using WowStyle1DropdownTemplate (12.0.1+)
local function CreateDropdown(parent, labelText, options, getCurrentValue, onChanged)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(260, 44)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 0, 0)
    label:SetText(labelText)
    label:SetTextColor(0.85, 0.85, 0.85, 1)
    label:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")

    local dropdown = CreateFrame("DropdownButton", nil, container, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("TOPLEFT", 0, -18)
    dropdown:SetSize(180, 26)

    dropdown:SetupMenu(function(dd, rootDescription)
        for _, opt in ipairs(options) do
            local text = type(opt) == "table" and opt.text or tostring(opt)
            local value = type(opt) == "table" and opt.value or opt
            rootDescription:CreateRadio(
                text,
                function(v) return getCurrentValue() == v end,
                function(v) onChanged(v) end,
                value
            )
        end
    end)

    return container
end

-- Compact slider with input.
--- Creates a labeled slider with an associated numeric input box.
--- @param parent Frame Parent frame that will own the slider container.
--- @param labelText string Text to display as the label above the slider.
--- @param min number Minimum value for the slider.
--- @param max number Maximum value for the slider.
--- @param step number Increment step for the slider and input.
--- @param initial number Initial value to set on the slider/input.
--- @param onChanged fun(value:number)|nil Callback invoked when the value changes; receives the new numeric value.
--- @return Frame A frame that contains the label, slider, and associated input controls.
local function CreateSlider(parent, labelText, min, max, step, initial, onChanged)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(260, 40)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 0, 0)
    label:SetText(labelText)
    label:SetTextColor(0.85, 0.85, 0.85, 1)
    label:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")

    local slider = CreateFrame("Slider", nil, container, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 0, -18)
    slider:SetSize(160, 16)
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

    -- Note: OptionsSliderTemplate does not provide built-in stepper buttons, so no stepper controls are created here.

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
        local viewer = _G["BuffIconCooldownViewer"]
        if viewer then
            ForceReskinViewer(viewer)
            pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, viewer)
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
local function CreateCheck(parent, labelText, initial, onChanged, useAtlas)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(210, 24)

    local checkbox = CreateFrame("CheckButton", nil, container, useAtlas and "UICheckButtonTemplate" or nil)
    checkbox:SetPoint("LEFT", 0, 0)
    checkbox:SetSize(20, 20)
    checkbox:SetChecked(initial)

    local bg = container:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("LEFT", checkbox, 0, 0)
    bg:SetSize(20, 20)
    bg:SetColorTexture(0, 0, 0, 0)

    local check = checkbox:CreateTexture(nil, "OVERLAY")
    check:SetAllPoints(checkbox)
    if useAtlas then
        checkbox:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
        checkbox:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
        checkbox:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
        checkbox:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
        checkbox:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
        checkbox:SetDisabledTexture("Interface\\Buttons\\UI-CheckBox-Disabled")
        if bg then bg:Hide() end
        if check then check:Hide() end
    else
        check:SetColorTexture(0.2, 0.9, 0.3, 1)
        check:SetAlpha(initial and 1 or 0)
        checkbox:SetCheckedTexture(check)
    end

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", checkbox, "RIGHT", 8, 0)
    label:SetText(labelText)
    label:SetTextColor(0.85, 0.85, 0.85, 1)
    label:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")

    checkbox:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        if not useAtlas then
            check:SetAlpha(checked and 1 or 0)
        end
        onChanged(checked)
        local viewer = _G["BuffIconCooldownViewer"]
        if viewer then
            ForceReskinViewer(viewer)
            pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, viewer)
        end
    end)

    return container
end

-- Scrollable, full-featured options panel for Interface Options
local optionsPanel

-- Old CreateOptionsPanel removed; options are now handled by Ace3 AceConfig (ui/options/DynamicIconsOptions.lua)
function DYNAMICICONS:CreateOptionsPanel() return nil end
