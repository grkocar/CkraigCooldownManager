-- ======================================================
-- MyUtilityBuffTracker (Deterministic ordering, Aspect Ratio,
-- Multi-row center layout, Combat-safe skinning, EditMode safe)
-- Target: _G["UtilityCooldownViewer"]
-- ======================================================

-- SavedVariables
MyUtilityBuffTrackerDB = MyUtilityBuffTrackerDB or {}

-- SafeGetChildren removed — use select() pattern or pool:EnumerateActive() instead

-- Define MyUtilityBuffTracker as a table
MyUtilityBuffTracker = MyUtilityBuffTracker or {}

-- ---------------------------
-- External Icon Registration (mirrors MyEssentialBuffTracker API)
-- ---------------------------
MyUtilityBuffTracker._externalIcons = MyUtilityBuffTracker._externalIcons or {}

function MyUtilityBuffTracker:RegisterExternalIcon(frame)
    if not frame then return end
    if not frame.Icon and not frame.icon then
        for _, region in ipairs({ frame:GetRegions() }) do
            if region and region:IsObjectType("Texture") and region:GetDrawLayer() == "ARTWORK" then
                frame.Icon = region
                break
            end
        end
    end
    self._externalIcons[frame] = true
    self:RefreshUtilityLayout()
end

function MyUtilityBuffTracker:UnregisterExternalIcon(frame)
    if not frame then return end
    self._externalIcons[frame] = nil
    self:RefreshUtilityLayout()
end

function MyUtilityBuffTracker:RefreshUtilityLayout()
    local viewer = _G["UtilityCooldownViewer"]
    if viewer and viewer:IsShown() and UtilityIconViewers and UtilityIconViewers.ApplyViewerLayout then
        if viewer._MyUtilityBuffTrackerTickerFrame then
            viewer._MyUtilityBuffTrackerTickerFrame._lastChildCount = 0
        end
        pcall(UtilityIconViewers.ApplyViewerLayout, UtilityIconViewers, viewer)
    end
end

-- Profile system integration
local function InitializeDB()
    -- No registration needed - ProfileManager calls OnProfileChanged directly
end

function MyUtilityBuffTracker:GetSettings()
    if CkraigProfileManager and CkraigProfileManager.db and CkraigProfileManager.db.profile then
        return CkraigProfileManager.db.profile.utilityBuffs
    end
    -- Fallback to global DB
    return MyUtilityBuffTrackerDB
end

-- Delayed initialization to ensure ProfileManager is loaded
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    InitializeDB()
end)

-- Cache frequently used global functions as locals for performance
local tonumber = tonumber
local tostring = tostring
local ipairs = ipairs
local pairs = pairs
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

local function UpdateCooldownManagerVisibility()
    local viewer = _G["UtilityCooldownViewer"]
    if not viewer then return end
    if InCombatLockdown() then return end
    if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
        viewer:Show()
        return
    end
    -- Don't force-show until ProfileManager has loaded the real settings
    if not (CkraigProfileManager and CkraigProfileManager.db) then return end
    local settings = MyUtilityBuffTracker:GetSettings()
    if settings.enabled == false then
        viewer:Hide()
        return
    end
    if settings.hideWhenMounted then
        if IsPlayerMounted() then
            viewer:Hide()
        else
            viewer:Show()
        end
    else
        viewer:Show()
    end
end

function MyUtilityBuffTracker:RefreshVisibility()
    UpdateCooldownManagerVisibility()
end

local mountEventFrame = CreateFrame("Frame")
-- Events registered later at PLAYER_LOGIN, gated by enabled state
mountEventFrame:SetScript("OnEvent", function()
    UpdateCooldownManagerVisibility()
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

    -- Per-spell glow settings
    spellGlows = {},
    -- Per-spell sounds
    spellSounds = {},

    -- Per-spell cooldown override (show actual CD instead of buff timer)
    cooldownOverrideSpells = {},

    -- Multi-Cluster Mode
    multiClusterMode = false,
    clusterCount = 5,
    clusterUnlocked = false,
    clusterFlow = "horizontal",
    clusterFlows = {},
    clusterVerticalGrows = {},
    clusterVerticalPins = {},
    clusterIconSizes = {},
    clusterAssignments = {},
    clusterPositions = {},
    clusterManualOrders = {},
    clusterCenterIcons = true,
    clusterSampleDisplayModes = {},
    clusterFreePositionModes = {},
    clusterIconFreePositions = {},
}

local LCG = LibStub("LibCustomGlow-1.0", true)
local LSM = LibStub("LibSharedMedia-3.0", true)

-- Reusable glow color array (avoids table allocation per icon per dispatch)
local ubtGlowColor = { 1, 1, 1, 1 }
local ubtProcOpts = { color = ubtGlowColor, key = "ubtGlow" }
local ubtEnabledGlowLookup = {}
local _ubt_defaultGlowColor = { r = 1, g = 1, b = 1, a = 1 }
local ubtEnabledSoundLookup = {}
local ubtSoundCfgSource = nil
local ubtSoundCfgRevision = -1
local ubtSoundActivePrevByKey = {}
local ubtSoundPrevCfgByKey = {}
local ubtSoundPrevModeByKey = {}
local ubtSoundReadyPrevByKey = {}
local ubtSoundLastPlayByKey = {}
local ubtSoundMinInterval = 0.75
-- Pre-allocated sound dispatch tables (avoid per-tick GC)
local _ubt_activeSoundCfgByKey = {}
local _ubt_activeSoundModeByKey = {}
local _ubt_activeSoundReadyByKey = {}

local function GetSpellSoundsRevision_UBT(settings)
    return tonumber(settings and settings.spellSoundsRevision) or 0
end

local function HasCooldownOrReadyModeGlow_UBT(settings)
    local spellGlows = settings and settings.spellGlows
    if type(spellGlows) ~= "table" then return false end
    for _, cfg in pairs(spellGlows) do
        if type(cfg) == "table" and cfg.enabled then
            local m = tostring(cfg.mode or "ready"):lower()
            if m == "cooldown" or m == "ready" then
                return true
            end
        end
    end
    return false
end

local function HasReadyOrCooldownModeSound_UBT(settings)
    local spellSounds = settings and settings.spellSounds
    if type(spellSounds) ~= "table" then return false end
    for _, cfg in pairs(spellSounds) do
        if type(cfg) == "table" and cfg.enabled then
            local m = tostring(cfg.mode or "ready"):lower()
            if m == "ready" or m == "cooldown" or m == "both" or m == "show" or m == "expire" then
                return true
            end
        end
    end
    return false
end

local function StopGlow_UBT(icon)
    local gt = icon._ubtGlowType
    if gt == "autocast" then LCG.AutoCastGlow_Stop(icon, "ubtGlow")
    elseif gt == "button" then LCG.ButtonGlow_Stop(icon)
    elseif gt == "proc" then LCG.ProcGlow_Stop(icon, "ubtGlow")
    else LCG.PixelGlow_Stop(icon, "ubtGlow") end
end

local function RebuildEnabledSoundLookup_UBT(spellSounds)
    for k in pairs(ubtEnabledSoundLookup) do ubtEnabledSoundLookup[k] = nil end
    ubtSoundCfgSource = spellSounds
    ubtSoundCfgRevision = tonumber((MyUtilityBuffTracker and MyUtilityBuffTracker.GetSettings and GetSpellSoundsRevision_UBT(MyUtilityBuffTracker:GetSettings())) or 0) or 0

    if type(spellSounds) ~= "table" then
        return false
    end

    local hasEnabled = false
    for skey, cfg in pairs(spellSounds) do
        if type(cfg) == "table" and cfg.enabled then
            ubtEnabledSoundLookup[tostring(skey)] = cfg
            hasEnabled = true
        end
    end
    return hasEnabled
end

local function ResolveSoundPath_UBT(soundKey)
    if not soundKey or soundKey == "" then return nil end
    if LSM and LSM.Fetch then
        local ok, path = pcall(LSM.Fetch, LSM, "sound", soundKey, true)
        if ok and path and path ~= "" then
            return path
        end
    end
    return soundKey
end

local function TrimString_UBT(s)
    if type(s) ~= "string" then return "" end
    return s:match("^%s*(.-)%s*$") or ""
end

local function ResolveSpellName_UBT(spellKey)
    local spellID = tonumber(spellKey)
    if spellID and C_Spell and C_Spell.GetSpellName then
        local name = C_Spell.GetSpellName(spellID)
        if name and name ~= "" then
            return name
        end
    end
    return tostring(spellKey or "Spell")
end

local function ResolveTtsText_UBT(spellKey, cfg)
    local text = TrimString_UBT(cfg and cfg.ttsText)
    if text ~= "" then
        return text
    end
    return ResolveSpellName_UBT(spellKey)
end

local function SpeakText_UBT(text)
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

local function PlaySpellSound_UBT(spellKey, cfg)
    if not cfg then return end
    local keyStr = tostring(spellKey or "")
    if keyStr == "" then return end

    local now = GetTime and GetTime() or 0
    local last = ubtSoundLastPlayByKey[keyStr]
    if last and (now - last) < ubtSoundMinInterval then
        return
    end
    ubtSoundLastPlayByKey[keyStr] = now

    local output = tostring(cfg.output or "sound")
    local playSound = (output == "sound" or output == "both")
    local playTts = (output == "tts" or output == "both")
    local didPlay = false

    if playSound then
        local soundPath = ResolveSoundPath_UBT(cfg.sound)
        if soundPath then
            local ok = pcall(PlaySoundFile, soundPath, "Master")
            didPlay = didPlay or (ok and true or false)
        end
    end

    if playTts then
        local ttsText = ResolveTtsText_UBT(keyStr, cfg)
        didPlay = SpeakText_UBT(ttsText) or didPlay
    elseif playSound and not didPlay then
        -- Fallback for missing/invalid SharedMedia sounds.
        didPlay = SpeakText_UBT(ResolveTtsText_UBT(keyStr, cfg)) or didPlay
    end

    if not didPlay then
        ubtSoundLastPlayByKey[keyStr] = nil
    end
end

local function IsReadyForSound_UBT(icon, spellKey)
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

local function ResetSoundState_UBT(resetLastPlayed)
    for k in pairs(ubtSoundActivePrevByKey) do ubtSoundActivePrevByKey[k] = nil end
    for k in pairs(ubtSoundPrevCfgByKey) do ubtSoundPrevCfgByKey[k] = nil end
    for k in pairs(ubtSoundPrevModeByKey) do ubtSoundPrevModeByKey[k] = nil end
    for k in pairs(ubtSoundReadyPrevByKey) do ubtSoundReadyPrevByKey[k] = nil end
    if resetLastPlayed then
        for k in pairs(ubtSoundLastPlayByKey) do ubtSoundLastPlayByKey[k] = nil end
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
    -- Use == nil checks for all settings to preserve user-set values including 0
    if MyUtilityBuffTrackerDB.columns == nil then MyUtilityBuffTrackerDB.columns = DEFAULTS.columns end
    if MyUtilityBuffTrackerDB.hSpacing == nil then MyUtilityBuffTrackerDB.hSpacing = DEFAULTS.hSpacing end
    if MyUtilityBuffTrackerDB.vSpacing == nil then MyUtilityBuffTrackerDB.vSpacing = DEFAULTS.vSpacing end
    if MyUtilityBuffTrackerDB.growUp == nil then MyUtilityBuffTrackerDB.growUp = DEFAULTS.growUp end
    if MyUtilityBuffTrackerDB.locked == nil then MyUtilityBuffTrackerDB.locked = DEFAULTS.locked end
    if MyUtilityBuffTrackerDB.iconSize == nil then MyUtilityBuffTrackerDB.iconSize = DEFAULTS.iconSize end
    if MyUtilityBuffTrackerDB.aspectRatio == nil then MyUtilityBuffTrackerDB.aspectRatio = DEFAULTS.aspectRatio end
    if MyUtilityBuffTrackerDB.aspectRatioCrop == nil then MyUtilityBuffTrackerDB.aspectRatioCrop = DEFAULTS.aspectRatioCrop end
    if MyUtilityBuffTrackerDB.spacing == nil then MyUtilityBuffTrackerDB.spacing = DEFAULTS.spacing end
    if MyUtilityBuffTrackerDB.rowLimit == nil then MyUtilityBuffTrackerDB.rowLimit = DEFAULTS.rowLimit end
    if MyUtilityBuffTrackerDB.rowGrowDirection == nil then MyUtilityBuffTrackerDB.rowGrowDirection = DEFAULTS.rowGrowDirection end

    if MyUtilityBuffTrackerDB.iconCornerRadius == nil then MyUtilityBuffTrackerDB.iconCornerRadius = DEFAULTS.iconCornerRadius end
    if MyUtilityBuffTrackerDB.cooldownTextSize == nil then MyUtilityBuffTrackerDB.cooldownTextSize = DEFAULTS.cooldownTextSize end
    if MyUtilityBuffTrackerDB.cooldownTextPosition == nil then MyUtilityBuffTrackerDB.cooldownTextPosition = DEFAULTS.cooldownTextPosition end
    if MyUtilityBuffTrackerDB.cooldownTextX == nil then MyUtilityBuffTrackerDB.cooldownTextX = DEFAULTS.cooldownTextX end
    if MyUtilityBuffTrackerDB.cooldownTextY == nil then MyUtilityBuffTrackerDB.cooldownTextY = DEFAULTS.cooldownTextY end
    if MyUtilityBuffTrackerDB.chargeTextSize == nil then MyUtilityBuffTrackerDB.chargeTextSize = DEFAULTS.chargeTextSize end
    if MyUtilityBuffTrackerDB.chargeTextPosition == nil then MyUtilityBuffTrackerDB.chargeTextPosition = DEFAULTS.chargeTextPosition end
    if MyUtilityBuffTrackerDB.chargeTextX == nil then MyUtilityBuffTrackerDB.chargeTextX = DEFAULTS.chargeTextX end
    if MyUtilityBuffTrackerDB.chargeTextY == nil then MyUtilityBuffTrackerDB.chargeTextY = DEFAULTS.chargeTextY end

    if MyUtilityBuffTrackerDB.enabled == nil then MyUtilityBuffTrackerDB.enabled = DEFAULTS.enabled end
    if MyUtilityBuffTrackerDB.showCooldownText == nil then MyUtilityBuffTrackerDB.showCooldownText = DEFAULTS.showCooldownText end
    if MyUtilityBuffTrackerDB.showChargeText == nil then MyUtilityBuffTrackerDB.showChargeText = DEFAULTS.showChargeText end
    if MyUtilityBuffTrackerDB.hideWhenMounted == nil then MyUtilityBuffTrackerDB.hideWhenMounted = DEFAULTS.hideWhenMounted end
    if MyUtilityBuffTrackerDB.assistedCombatHighlight == nil then MyUtilityBuffTrackerDB.assistedCombatHighlight = DEFAULTS.assistedCombatHighlight end

    if MyUtilityBuffTrackerDB.staticGridMode == nil then MyUtilityBuffTrackerDB.staticGridMode = DEFAULTS.staticGridMode end
    if MyUtilityBuffTrackerDB.gridRows == nil then MyUtilityBuffTrackerDB.gridRows = DEFAULTS.gridRows end
    if MyUtilityBuffTrackerDB.gridColumns == nil then MyUtilityBuffTrackerDB.gridColumns = DEFAULTS.gridColumns end
    if MyUtilityBuffTrackerDB.gridSlotMap == nil then MyUtilityBuffTrackerDB.gridSlotMap = {} end

    -- Per-row sizes
    if MyUtilityBuffTrackerDB.rowSizes == nil then MyUtilityBuffTrackerDB.rowSizes = {} end

    -- Per-spell glows
    if MyUtilityBuffTrackerDB.spellGlows == nil then MyUtilityBuffTrackerDB.spellGlows = {} end
    if MyUtilityBuffTrackerDB.spellSounds == nil then MyUtilityBuffTrackerDB.spellSounds = {} end
    if MyUtilityBuffTrackerDB.spellSoundsRevision == nil then MyUtilityBuffTrackerDB.spellSoundsRevision = 0 end

    for k, v in pairs(MyUtilityBuffTrackerDB.spellSounds) do
        if type(v) ~= "table" then
            MyUtilityBuffTrackerDB.spellSounds[k] = { enabled = (v == true), sound = "", output = "sound", ttsText = "", mode = "ready" }
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

    -- Per-spell cooldown overrides
    if MyUtilityBuffTrackerDB.cooldownOverrideSpells == nil then MyUtilityBuffTrackerDB.cooldownOverrideSpells = {} end

    -- Multi-cluster mode
    if MyUtilityBuffTrackerDB.multiClusterMode == nil then MyUtilityBuffTrackerDB.multiClusterMode = DEFAULTS.multiClusterMode end
    if MyUtilityBuffTrackerDB.clusterCount == nil then MyUtilityBuffTrackerDB.clusterCount = DEFAULTS.clusterCount end
    if MyUtilityBuffTrackerDB.clusterUnlocked == nil then MyUtilityBuffTrackerDB.clusterUnlocked = false end
    if MyUtilityBuffTrackerDB.clusterFlows == nil then MyUtilityBuffTrackerDB.clusterFlows = {} end
    if MyUtilityBuffTrackerDB.clusterVerticalGrows == nil then MyUtilityBuffTrackerDB.clusterVerticalGrows = {} end
    if MyUtilityBuffTrackerDB.clusterVerticalPins == nil then MyUtilityBuffTrackerDB.clusterVerticalPins = {} end
    if MyUtilityBuffTrackerDB.clusterIconSizes == nil then MyUtilityBuffTrackerDB.clusterIconSizes = {} end
    if MyUtilityBuffTrackerDB.clusterAssignments == nil then MyUtilityBuffTrackerDB.clusterAssignments = {} end
    if MyUtilityBuffTrackerDB.clusterPositions == nil then MyUtilityBuffTrackerDB.clusterPositions = {} end
    if MyUtilityBuffTrackerDB.clusterManualOrders == nil then MyUtilityBuffTrackerDB.clusterManualOrders = {} end
    if MyUtilityBuffTrackerDB.clusterCenterIcons == nil then MyUtilityBuffTrackerDB.clusterCenterIcons = DEFAULTS.clusterCenterIcons end
    if MyUtilityBuffTrackerDB.clusterSampleDisplayModes == nil then MyUtilityBuffTrackerDB.clusterSampleDisplayModes = {} end
    if MyUtilityBuffTrackerDB.clusterFreePositionModes == nil then MyUtilityBuffTrackerDB.clusterFreePositionModes = {} end
    if MyUtilityBuffTrackerDB.clusterIconFreePositions == nil then MyUtilityBuffTrackerDB.clusterIconFreePositions = {} end
end

-- ---------------------------
-- Icon key identification for glow system
-- Uses ONLY direct frame fields (clean, never tainted) to avoid "table index is secret".
-- Resolves cooldownID â†’ spellID through Blizzard's C_CooldownViewer API.
-- ---------------------------
local function GetUtilityIconKey(icon)
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

    -- 5. Addon-set creation order
    if icon.__ubtCreationOrder then return icon.__ubtCreationOrder end

    return nil
end

local KnownUtilityItemsByKey = {}

local function CollectUtilityDisplayedItems(viewer)
    local items = {}
    if not viewer then return items end
    wipe(KnownUtilityItemsByKey)

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
                    KnownUtilityItemsByKey[spellID] = items[#items]
                end
            end
        end
    end
    return items
end

-- Expose for options panels
function MyUtilityBuffTracker:GetDisplayedItems()
    local viewer = _G["UtilityCooldownViewer"]
    if not viewer then return {} end
    local ok, items = pcall(CollectUtilityDisplayedItems, viewer)
    if ok and type(items) == "table" then return items end
    return {}
end

_G.CCM_GetUtilitySpellList = function()
    if MyUtilityBuffTracker and MyUtilityBuffTracker.GetDisplayedItems then
        return MyUtilityBuffTracker:GetDisplayedItems()
    end
    return {}
end

-- ======================================================
-- Cooldown Override (Utility): replace Blizzard's aura/buff timer with actual CD
-- ======================================================
local _ubt_cdOverrideGuard = {}   -- cd widget -> true while we call Set inside a hook
local _ubt_alertHooked = {}       -- icon -> true when alert suppression is installed
local IsUtilitySpellStillOnCooldown  -- forward declaration

-- Fast cached key lookup: avoids pcall on every hook invocation.
-- The key only changes when icon.cooldownID changes (which is rare in combat).
local function GetCachedUtilityIconKey(icon)
    local cdID = icon.cooldownID
    if cdID == icon._cdOverrideCachedCdID then
        return icon._cdOverrideKey
    end
    local key = GetUtilityIconKey(icon)
    icon._cdOverrideCachedCdID = cdID
    icon._cdOverrideKey = key
    -- Invalidate the enabled cache so it's re-evaluated
    icon._cdOverrideEnabled = nil
    return key
end

local function IsUtilityCDOverrideActive(icon)
    -- Fast path: use cache if cooldownID hasn't changed
    if icon.cooldownID == icon._cdOverrideCachedCdID and icon._cdOverrideEnabled ~= nil then
        return icon._cdOverrideEnabled
    end
    local settings = MyUtilityBuffTracker:GetSettings()
    if not settings or not settings.cooldownOverrideSpells then
        icon._cdOverrideEnabled = false
        return false
    end
    local key = GetCachedUtilityIconKey(icon)
    local result = key and settings.cooldownOverrideSpells[tostring(key)] == true or false
    icon._cdOverrideEnabled = result
    return result
end

-- Suppress Blizzard's built-in aura glow + desaturate override icon
local function SuppressUtilityAuraGlow(icon)
    local alert = icon.SpellActivationAlert
    if alert then
        alert:Hide()
        if alert.ProcStartFlipbook then alert.ProcStartFlipbook:Hide() end
        if alert.ProcLoopFlipbook then alert.ProcLoopFlipbook:Hide() end
        if alert.ProcAltGlow then alert.ProcAltGlow:Hide() end
    end
    if ActionButtonSpellAlertManager and ActionButtonSpellAlertManager.HideAlert then
        pcall(ActionButtonSpellAlertManager.HideAlert, ActionButtonSpellAlertManager, icon)
    end
    local flash = icon.CooldownFlash
    if flash then
        flash:Hide()
        if flash.FlashAnim then flash.FlashAnim:Stop() end
    end
    -- Desaturate only if real cooldown is running (not GCD)
    local iconKey = GetCachedUtilityIconKey(icon)
    if iconKey and IsUtilitySpellStillOnCooldown(iconKey) then
        local iconTex = icon.Icon or icon.icon
        if iconTex and iconTex.SetDesaturated then
            iconTex:SetDesaturated(true)
        end
    end
end

local function RestoreUtilityIconSaturation(icon)
    local iconTex = icon.Icon or icon.icon
    if iconTex and iconTex.SetDesaturated then
        iconTex:SetDesaturated(false)
    end
end

local function HookUtilityAlertSuppression(icon)
    if _ubt_alertHooked[icon] then return end
    _ubt_alertHooked[icon] = true
    local alert = icon.SpellActivationAlert
    if alert and alert.Show then
        hooksecurefunc(alert, "Show", function(self)
            if IsUtilityCDOverrideActive(icon) then self:Hide() end
        end)
    end
    local flash = icon.CooldownFlash
    if flash and flash.Show then
        hooksecurefunc(flash, "Show", function(self)
            if IsUtilityCDOverrideActive(icon) then
                self:Hide()
                if self.FlashAnim then self.FlashAnim:Stop() end
            end
        end)
    end
end

local function TryUtilityCooldownOverride(icon, cd)
    if _ubt_cdOverrideGuard[cd] then return end
    local settings = MyUtilityBuffTracker:GetSettings()
    if not settings or not settings.cooldownOverrideSpells then return end
    local key = GetCachedUtilityIconKey(icon)
    if not key then return end
    local keyStr = tostring(key)
    if not settings.cooldownOverrideSpells[keyStr] then
        icon._cdOverrideEnabled = false
        return
    end
    icon._cdOverrideEnabled = true

    -- Resolve talent override (e.g., Berserk 50334 → Incarnation 102558)
    local resolvedKey = key
    if FindSpellOverrideByID then
        resolvedKey = FindSpellOverrideByID(key) or key
    end

    -- 12.0.5+: Use clean booleans for GCD gating, duration object for display.
    -- NOTE: cdInfo.isActive may be false during an active buff even though the
    --       spell IS on recovery — do NOT gate on isActive.
    local CCM = _G.CkraigCooldownManager
    if CCM and CCM.Is1205 then
        local cdInfo = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(resolvedKey)
        if cdInfo and cdInfo.isOnGCD then return end
        local durObj = C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(resolvedKey)
        if not durObj then return end
        _ubt_cdOverrideGuard[cd] = true
        if cd.SetUseAuraDisplayTime then cd:SetUseAuraDisplayTime(false) end
        cd:SetCooldownFromDurationObject(durObj)
        if cd.SetDrawSwipe then cd:SetDrawSwipe(true) end
        if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.8) end
        _ubt_cdOverrideGuard[cd] = nil
        SuppressUtilityAuraGlow(icon)
        return
    end

    -- Pre-12.0.5: Use duration object (handles secret numbers C-side)
    if not (C_Spell and C_Spell.GetSpellCooldownDuration) then return end
    local durObj = C_Spell.GetSpellCooldownDuration(resolvedKey)
    if not durObj then return end
    _ubt_cdOverrideGuard[cd] = true
    if cd.SetUseAuraDisplayTime then
        cd:SetUseAuraDisplayTime(false)
    end
    cd:SetCooldownFromDurationObject(durObj)
    if cd.SetSwipeColor then
        cd:SetSwipeColor(0, 0, 0, 0.8)
    end
    _ubt_cdOverrideGuard[cd] = nil
    SuppressUtilityAuraGlow(icon)
end

IsUtilitySpellStillOnCooldown = function(spellID)
    -- Resolve talent override (e.g., Berserk → Incarnation)
    local resolved = spellID
    if FindSpellOverrideByID then
        resolved = FindSpellOverrideByID(spellID) or spellID
    end
    -- Use clean booleans from C_Spell.GetSpellCooldown (isActive / isOnGCD are NOT secret).
    if not (C_Spell and C_Spell.GetSpellCooldown) then return false end
    local cdInfo = C_Spell.GetSpellCooldown(resolved)
    if not cdInfo then return false end
    if cdInfo.isOnGCD then return false end
    return cdInfo.isActive == true
end

-- Hook icon's Cooldown widget to track cooldown state without reading tainted values.
-- SetCooldown = on cooldown (Blizzard only calls this for real CDs via CooldownFrame_Set)
-- Clear = cooldown cleared (CooldownFrame_Set calls Clear for 0-duration)
-- OnCooldownDone = cooldown animation finished
local function HookCooldownTracking(icon)
    if icon._cdHooked then return end
    local cd = icon.Cooldown
    if not cd then return end
    icon._cdHooked = true
    icon._isOnCD = false
    -- Install alert suppression hooks for CD override spells
    HookUtilityAlertSuppression(icon)
    -- Hook SetSwipeColor so Blizzard can't re-apply the green buff swipe on override spells
    if cd.SetSwipeColor then
        hooksecurefunc(cd, "SetSwipeColor", function(self, r, g, b, a)
            if _ubt_cdOverrideGuard[cd] then return end
            if IsUtilityCDOverrideActive(icon) then
                if r ~= 0 or g ~= 0 or b ~= 0 then
                    _ubt_cdOverrideGuard[cd] = true
                    self:SetSwipeColor(0, 0, 0, 0.8)
                    _ubt_cdOverrideGuard[cd] = nil
                end
            end
        end)
    end
    -- Hook RefreshIconDesaturation (Lua mixin, per-object safe)
    if icon.RefreshIconDesaturation then
        hooksecurefunc(icon, "RefreshIconDesaturation", function(self)
            if IsUtilityCDOverrideActive(self) then
                local key = GetCachedUtilityIconKey(self)
                if key and IsUtilitySpellStillOnCooldown(key) then
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
            if _ubt_cdOverrideGuard[cd] then return end
            if useAura and IsUtilityCDOverrideActive(icon) then
                _ubt_cdOverrideGuard[cd] = true
                self:SetUseAuraDisplayTime(false)
                _ubt_cdOverrideGuard[cd] = nil
            end
        end)
    end
    -- 12.0.5+: Hook RefreshSpellCooldownInfo for more reliable CD override timing.
    -- This fires AFTER CacheCooldownValues() has computed everything (including wasSetFromAura),
    -- so our override replaces the final display at the right point in the refresh cycle.
    local _ubt_hookIs1205 = _G.CkraigCooldownManager and _G.CkraigCooldownManager.Is1205
    if _ubt_hookIs1205 and icon.RefreshSpellCooldownInfo then
        hooksecurefunc(icon, "RefreshSpellCooldownInfo", function(self)
            if _ubt_cdOverrideGuard[cd] then return end
            TryUtilityCooldownOverride(self, cd)
        end)
    end
    hooksecurefunc(cd, "SetCooldown", function()
        icon._isOnCD = true
        -- On 12.0.5, RefreshSpellCooldownInfo hook handles the override
        if not _ubt_hookIs1205 then
            TryUtilityCooldownOverride(icon, cd)
        end
    end)
    if cd.SetCooldownFromDurationObject then
        hooksecurefunc(cd, "SetCooldownFromDurationObject", function()
            icon._isOnCD = true
            if not _ubt_hookIs1205 then
                TryUtilityCooldownOverride(icon, cd)
            end
        end)
    end
    hooksecurefunc(cd, "Clear", function()
        if not IsUtilityCDOverrideActive(icon) then
            icon._isOnCD = false
            return
        end
        local key = GetCachedUtilityIconKey(icon)
        if key and IsUtilitySpellStillOnCooldown(key) then
            icon._isOnCD = true
            TryUtilityCooldownOverride(icon, cd)
            return
        end
        RestoreUtilityIconSaturation(icon)
        icon._isOnCD = false
    end)
    cd:HookScript("OnCooldownDone", function()
        if not IsUtilityCDOverrideActive(icon) then
            icon._isOnCD = false
            return
        end
        local key = GetCachedUtilityIconKey(icon)
        if key and IsUtilitySpellStillOnCooldown(key) then
            icon._isOnCD = true
            TryUtilityCooldownOverride(icon, cd)
            return
        end
        RestoreUtilityIconSaturation(icon)
        icon._isOnCD = false
    end)
    -- Immediately try the override for icons that already have a cooldown running
    -- (Blizzard sets the cooldown before our hooks are installed)
    TryUtilityCooldownOverride(icon, cd)
end

local function IsIconReady(icon)
    if not icon then return false end
    if not icon._cdHooked then return true end
    return not icon._isOnCD
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

local IconRuntimeState = setmetatable({}, { __mode = "k" })
local ViewerRuntimeState = setmetatable({}, { __mode = "k" })
local TextureRuntimeState = setmetatable({}, { __mode = "k" })
local BackdropPendingState = setmetatable({}, { __mode = "k" })

local function GetIconState(icon)
    local state = IconRuntimeState[icon]
    if not state then
        state = {}
        IconRuntimeState[icon] = state
    end
    return state
end

-- Hoisted sort comparator for ApplyViewerLayout (avoids closure allocation per call)
local function _ubt_iconSortComparator(a, b)
    local aOrder = a.layoutIndex or a:GetID() or GetIconState(a).creationOrder
    local bOrder = b.layoutIndex or b:GetID() or GetIconState(b).creationOrder
    return aOrder < bOrder
end

local function SetViewerMetric(viewer, key, value)
    local state = ViewerRuntimeState[viewer]
    if not state then
        state = {}
        ViewerRuntimeState[viewer] = state
    end
    state[key] = value
end

local function GetViewerMetric(viewer, key, defaultValue)
    local state = ViewerRuntimeState[viewer]
    if state and state[key] ~= nil then
        return state[key]
    end
    return defaultValue
end

-- ---------------------------
-- UtilityIconViewers Core (initialize early)
-- ---------------------------
UtilityIconViewers = UtilityIconViewers or {}
UtilityIconViewers.__pendingIcons = UtilityIconViewers.__pendingIcons or {}
UtilityIconViewers.__iconSkinEventFrame = UtilityIconViewers.__iconSkinEventFrame or nil
UtilityIconViewers.__pendingBackdrops = UtilityIconViewers.__pendingBackdrops or {}
UtilityIconViewers.__backdropEventFrame = UtilityIconViewers.__backdropEventFrame or nil

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
    if not UtilityIconViewers.__pendingBackdrops then return end
    for frame, info in pairs(UtilityIconViewers.__pendingBackdrops) do
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
                    UtilityIconViewers.__pendingBackdrops[frame] = nil
                end
            end
        end
    end
end

local function EnsureBackdropEventFrame()
    if UtilityIconViewers.__backdropEventFrame then return end
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("PLAYER_REGEN_ENABLED")
    ef:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_ENABLED" then
            ProcessPendingBackdrops()
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
    end)
    UtilityIconViewers.__backdropEventFrame = ef
end

local function SafeSetBackdrop(frame, backdropInfo, color)
    if not frame or not frame.SetBackdrop then return false end

    if InCombatLockdown() then
        BackdropPendingState[frame] = true
        UtilityIconViewers.__pendingBackdrops = UtilityIconViewers.__pendingBackdrops or {}
        UtilityIconViewers.__pendingBackdrops[frame] = { backdrop = backdropInfo, color = color }
        EnsureBackdropEventFrame()
        UtilityIconViewers.__backdropEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
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
        UtilityIconViewers.__pendingBackdrops = UtilityIconViewers.__pendingBackdrops or {}
        UtilityIconViewers.__pendingBackdrops[frame] = { backdrop = backdropInfo, color = color }
        EnsureBackdropEventFrame()
        UtilityIconViewers.__backdropEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
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
    for i = 1, select("#", container:GetChildren()) do
        local child = select(i, container:GetChildren())
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
function UtilityIconViewers:SkinIcon(icon, settings)
    if not icon then return false end

    local iconTexture = icon.Icon or icon.icon
    if not iconTexture then return false end

    settings = settings or MyUtilityBuffTracker:GetSettings()
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
        local ist = GetIconState(icon)
        if ist._cachedPandemic ~= nil then
            picon = ist._cachedPandemic
        elseif icon.GetChildren then
            for i2 = 1, select("#", icon:GetChildren()) do
                local child = select(i2, icon:GetChildren())
                local n = child.GetName and child:GetName()
                if n and n:find("Pandemic") then
                    picon = child
                    break
                end
            end
            ist._cachedPandemic = picon or false
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
            iconState.chargeTextRef = chargeText
            iconState.chargeAnchor = position.point
            iconState.chargeOffX = position.x + offsetX
            iconState.chargeOffY = position.y + offsetY
            -- Set charge/stack text color from ChargeTextColorOptions
            local color = (_G.CooldownChargeDB and _G.CooldownChargeDB["TextColor_ChargeText_Utility"]) or {1,1,1,1}
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

        if not cdText then
            local ist2 = GetIconState(icon)
            if ist2._cachedCdText ~= nil then
                cdText = ist2._cachedCdText
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
                ist2._cachedCdText = cdText or false
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
            local color = (_G.CooldownChargeDB and _G.CooldownChargeDB["TextColor_CooldownText_Utility"]) or {1,1,1,1}
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
    local iconTexture = icon.Icon or icon.icon
    if iconTexture then
        iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    -- Add 1-pixel black border using four overlay textures
    if not iconState.pixelBorders then
        iconState.pixelBorders = {}
        -- Top
        local top = icon:CreateTexture(nil, "OVERLAY")
        top:SetColorTexture(0, 0, 0, 1)
        top:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        top:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 0, 0)
        top:SetHeight(1)
        iconState.pixelBorders.top = top
        -- Bottom
        local bottom = icon:CreateTexture(nil, "OVERLAY")
        bottom:SetColorTexture(0, 0, 0, 1)
        bottom:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)
        bottom:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
        bottom:SetHeight(1)
        iconState.pixelBorders.bottom = bottom
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


    iconState.skinned = true
    iconState.skinPending = nil
    return true
end

-- ---------------------------
-- Process pending icons (called after combat)
-- ---------------------------
function UtilityIconViewers:ProcessPendingIcons()
    for icon, data in pairs(self.__pendingIcons) do
        if icon and icon:IsShown() and not GetIconState(icon).skinned then
            pcall(self.SkinIcon, self, icon, data.settings)
        end
        self.__pendingIcons[icon] = nil
    end
end

local function EnsurePendingEventFrame()
    if UtilityIconViewers.__iconSkinEventFrame then return end
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("PLAYER_REGEN_ENABLED")
    ef:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_ENABLED" then
            self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            UtilityIconViewers:ProcessPendingIcons()
            ProcessPendingBackdrops()
        end
    end)
    UtilityIconViewers.__iconSkinEventFrame = ef
end

-- ============================================================
-- UTILITY CLUSTER MODE — helpers (mirrors EssentialBuffTracker)
-- ============================================================
local MAX_UBT_CLUSTER_GROUPS = 20

local DEFAULT_UBT_CLUSTER_POSITIONS = {
    [1] = { point = "CENTER", x = -300, y = 200 },
    [2] = { point = "CENTER", x = -150, y = 200 },
    [3] = { point = "CENTER", x = 0,    y = 200 },
    [4] = { point = "CENTER", x = 150,  y = 200 },
    [5] = { point = "CENTER", x = 300,  y = 200 },
}

local function GetUBTDefaultClusterPosition(index)
    if DEFAULT_UBT_CLUSTER_POSITIONS[index] then
        return DEFAULT_UBT_CLUSTER_POSITIONS[index]
    end
    local col = ((index - 1) % 5) - 2
    local row = math.floor((index - 1) / 5)
    return { point = "CENTER", x = col * 150, y = 200 + row * 150 }
end

local function GetUBTClusterManualOrder(settings, clusterIndex)
    settings.clusterManualOrders = settings.clusterManualOrders or {}
    if not settings.clusterManualOrders[clusterIndex] then
        settings.clusterManualOrders[clusterIndex] = {}
    end
    return settings.clusterManualOrders[clusterIndex]
end

local function BuildUBTOrderedKeysForCluster(settings, clusterIndex, availableKeys)
    local ordered = {}
    local added = {}
    settings.clusterAssignments = settings.clusterAssignments or {}
    local orderList = GetUBTClusterManualOrder(settings, clusterIndex)

    local function CanUseKey(key)
        local nk = tostring(key)
        local assigned = tonumber(settings.clusterAssignments[nk]) or 1
        if assigned ~= clusterIndex then return nil end
        if availableKeys and not availableKeys[nk] then return nil end
        return nk
    end

    for _, key in ipairs(orderList) do
        local usable = CanUseKey(key)
        if usable and not added[usable] then
            table.insert(ordered, usable); added[usable] = true
        end
    end
    local leftovers = {}
    for key, assigned in pairs(settings.clusterAssignments) do
        if (tonumber(assigned) or 1) == clusterIndex then
            local usable = CanUseKey(key)
            if usable and not added[usable] then
                table.insert(leftovers, usable); added[usable] = true
            end
        end
    end
    table.sort(leftovers, function(a, b)
        local an, bn = tonumber(a), tonumber(b)
        if an and bn then return an < bn end
        return tostring(a) < tostring(b)
    end)
    for _, k in ipairs(leftovers) do table.insert(ordered, k) end
    return ordered
end

local function BuildUBTAvailableKeySet(viewer)
    local keys = {}
    local pool = viewer and viewer.itemFramePool
    if pool then
        for icon in pool:EnumerateActive() do
            if icon and icon:IsShown() then
                local key = GetUtilityIconKey(icon)
                if key then keys[tostring(key)] = true end
            end
        end
    end
    return keys
end

local _ubt_clusterViewerMeta = setmetatable({}, {__mode="k"})
local function GetUBTViewerMeta(viewer)
    if not _ubt_clusterViewerMeta[viewer] then _ubt_clusterViewerMeta[viewer] = {} end
    return _ubt_clusterViewerMeta[viewer]
end

local function EnsureUBTClusterAnchorForIndex(viewer, settings, index)
    local vm = GetUBTViewerMeta(viewer)
    vm.clusterAnchors = vm.clusterAnchors or {}
    local anchors = vm.clusterAnchors
    if anchors[index] then return anchors[index] end

    local anchor = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    anchor:SetSize(120, 120)
    anchor:SetMovable(true)
    anchor:EnableMouse(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetClampedToScreen(true)
    anchor:SetFrameStrata("MEDIUM")
    anchor:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left=1, right=1, top=1, bottom=1 },
    })
    anchor:SetBackdropColor(0, 0, 0, 0.12)
    anchor:SetBackdropBorderColor(0.2, 0.6, 1.0, 0.9)  -- blue tint for Utility
    anchor._clusterIndex = index

    anchor:SetScript("OnDragStart", function(self)
        local s = MyUtilityBuffTracker:GetSettings()
        if not s or not s.clusterUnlocked then return end
        if InCombatLockdown() then return end
        self:StartMoving()
    end)
    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local s = MyUtilityBuffTracker:GetSettings()
        if not s then return end
        s.clusterPositions = s.clusterPositions or {}
        local point, _, relPoint, x, y = self:GetPoint(1)
        s.clusterPositions[self._clusterIndex] = {
            point = point or "CENTER", relPoint = relPoint or "CENTER",
            x = x or 0, y = y or 0,
        }
    end)

    anchors[index] = anchor
    local saved = settings.clusterPositions and settings.clusterPositions[index]
    local fallback = GetUBTDefaultClusterPosition(index)
    local pt   = (saved and saved.point)    or fallback.point
    local rpt  = (saved and saved.relPoint) or pt
    local px   = (saved and saved.x)        or fallback.x
    local py   = (saved and saved.y)        or fallback.y
    anchor:ClearAllPoints()
    anchor:SetPoint(pt, UIParent, rpt, px, py)
    anchor:Hide()
    return anchor
end

-- Cluster drag/free-position state
local _ubt_dragState = { draggingIcon = nil, sourceCluster = nil }
local _ubt_freePosSelected = nil
local _ubt_freePosViewer   = nil
local _ubt_freePosKeyFrame = nil

local function UBTFreePosDeselect()
    if _ubt_freePosSelected then
        local icon = _ubt_freePosSelected
        if icon._ubtSelectHighlight then icon._ubtSelectHighlight:Hide() end
        _ubt_freePosSelected = nil
        _ubt_freePosViewer   = nil
    end
    if _ubt_freePosKeyFrame then _ubt_freePosKeyFrame:EnableKeyboard(false) end
end

local function UBTFreePosNudge(dx, dy)
    local icon = _ubt_freePosSelected
    if not icon then return end
    local ci = icon._ubtDragCluster
    local iconKey = GetUtilityIconKey(icon)
    if not ci or not iconKey then return end
    local keyStr = tostring(iconKey)
    local s = MyUtilityBuffTracker:GetSettings()
    if not s then return end
    s.clusterIconFreePositions = s.clusterIconFreePositions or {}
    s.clusterIconFreePositions[ci] = s.clusterIconFreePositions[ci] or {}
    local pos = s.clusterIconFreePositions[ci][keyStr] or {x=0,y=0}
    local newX = (pos.x or 0) + dx
    local newY = (pos.y or 0) + dy
    s.clusterIconFreePositions[ci][keyStr] = {x=newX, y=newY}
    if _ubt_freePosViewer then
        local vm = GetUBTViewerMeta(_ubt_freePosViewer)
        local anchor = vm.clusterAnchors and vm.clusterAnchors[ci]
        if anchor then
            icon:ClearAllPoints()
            icon:SetPoint("CENTER", anchor, "CENTER", newX, newY)
        end
    end
end

local function UBTFreePosSelect(icon, viewer)
    UBTFreePosDeselect()
    _ubt_freePosSelected = icon
    _ubt_freePosViewer   = viewer
    if not icon._ubtSelectHighlight then
        local hl = icon:CreateTexture(nil, "OVERLAY", nil, 7)
        hl:SetAllPoints()
        hl:SetColorTexture(1, 0.9, 0, 0.4)
        icon._ubtSelectHighlight = hl
    end
    icon._ubtSelectHighlight:Show()
    if not _ubt_freePosKeyFrame then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetAllPoints(UIParent)
        f:SetFrameStrata("TOOLTIP")
        f:EnableMouse(false)
        f:EnableKeyboard(false)
        f:SetScript("OnKeyDown", function(self, key)
            if not _ubt_freePosSelected then self:EnableKeyboard(false); return end
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                UBTFreePosDeselect(); return
            end
            local step = IsShiftKeyDown() and 10 or 1
            if     key == "UP"    then self:SetPropagateKeyboardInput(false); UBTFreePosNudge(0,  step)
            elseif key == "DOWN"  then self:SetPropagateKeyboardInput(false); UBTFreePosNudge(0, -step)
            elseif key == "LEFT"  then self:SetPropagateKeyboardInput(false); UBTFreePosNudge(-step, 0)
            elseif key == "RIGHT" then self:SetPropagateKeyboardInput(false); UBTFreePosNudge( step, 0)
            else   self:SetPropagateKeyboardInput(true)
            end
        end)
        _ubt_freePosKeyFrame = f
    end
    _ubt_freePosKeyFrame:EnableKeyboard(true)
end

local function FindUBTClusterForCursor(vm, clusterCount, mx, my)
    if not vm or not vm.clusterAnchors then return nil end
    for ci = 1, clusterCount do
        local anchor = vm.clusterAnchors[ci]
        if anchor and anchor:IsShown() then
            local l, r = anchor:GetLeft(), anchor:GetRight()
            local b, t = anchor:GetBottom(), anchor:GetTop()
            if l and r and b and t and mx >= l and mx <= r and my >= b and my <= t then
                return ci, anchor
            end
        end
    end
    local closest, closestAnchor, dist = nil, nil, 1e9
    for ci = 1, clusterCount do
        local anchor = vm.clusterAnchors[ci]
        if anchor and anchor:IsShown() then
            local cx, cy = anchor:GetCenter()
            if cx and cy then
                local d = (mx-cx)^2 + (my-cy)^2
                if d < dist then dist=d; closest=ci; closestAnchor=anchor end
            end
        end
    end
    return closest, closestAnchor
end

local function FindUBTNearestKeyInCluster(vm, clusterIndex, draggedIcon, mx, my)
    if not vm or not vm.clusterIconsByIndex then return nil end
    local iconList = vm.clusterIconsByIndex[clusterIndex]
    if type(iconList) ~= "table" then return nil end
    local nearestKey, nearestDist = nil, 1e9
    for _, child in ipairs(iconList) do
        if child and child ~= draggedIcon and (child.Icon or child.icon) then
            local cx, cy = child:GetCenter()
            local key = GetUtilityIconKey(child)
            if cx and cy and key then
                local d = (mx-cx)^2 + (my-cy)^2
                if d < nearestDist then nearestDist=d; nearestKey=tostring(key) end
            end
        end
    end
    return nearestKey
end

local function RemoveKeyFromAllUBTClusterOrders(settings, key)
    settings.clusterManualOrders = settings.clusterManualOrders or {}
    local normalized = tostring(key)
    for _, orderList in pairs(settings.clusterManualOrders) do
        if type(orderList) == "table" then
            for i = #orderList, 1, -1 do
                if tostring(orderList[i]) == normalized then table.remove(orderList, i) end
            end
        end
    end
end

local function SetupUBTClusterIconDrag(icon, viewer, clusterIndex)
    if not icon or InCombatLockdown() then return end
    icon._ubtDragCluster = clusterIndex
    icon:SetMovable(true)
    icon:RegisterForDrag("LeftButton")
    icon:EnableMouse(true)

    icon:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        local s = MyUtilityBuffTracker:GetSettings()
        if not s or not s.clusterUnlocked then return end
        local ci = self._ubtDragCluster or clusterIndex
        _ubt_dragState.draggingIcon = self
        _ubt_dragState.sourceCluster = ci
        self:StartMoving()
        self:SetAlpha(0.6)
    end)

    icon:SetScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" then return end
        if InCombatLockdown() then return end
        local s = MyUtilityBuffTracker:GetSettings()
        if not s or not s.clusterUnlocked then return end
        local ci = self._ubtDragCluster or clusterIndex
        if not (s.clusterFreePositionModes and s.clusterFreePositionModes[ci]) then return end
        if _ubt_freePosSelected == self then UBTFreePosDeselect()
        else UBTFreePosSelect(self, viewer) end
    end)

    icon:SetScript("OnDragStop", function(self)
        if InCombatLockdown() then return end
        self:StopMovingOrSizing()
        self:SetAlpha(1.0)
        if _ubt_dragState.draggingIcon ~= self then return end

        local s = MyUtilityBuffTracker:GetSettings()
        local iconKey = GetUtilityIconKey(self)
        if not s or not iconKey then
            _ubt_dragState.draggingIcon = nil
            _ubt_dragState.sourceCluster = nil
            pcall(UtilityIconViewers.ApplyViewerLayout, UtilityIconViewers, viewer)
            return
        end

        local keyStr = tostring(iconKey)
        local sourceCluster = tonumber(_ubt_dragState.sourceCluster) or 1
        local clusterCount = math.max(1, math.min(MAX_UBT_CLUSTER_GROUPS, SafeNumber(s.clusterCount, DEFAULTS.clusterCount) or DEFAULTS.clusterCount))

        -- Free position mode: save offset from anchor and re-anchor directly
        if s.clusterFreePositionModes and s.clusterFreePositionModes[sourceCluster] then
            local vm = GetUBTViewerMeta(viewer)
            local anchor = vm.clusterAnchors and vm.clusterAnchors[sourceCluster]
            if anchor then
                local ix, iy = self:GetCenter()
                local ax, ay = anchor:GetCenter()
                if ix and iy and ax and ay then
                    local offsetX = ix - ax
                    local offsetY = iy - ay
                    s.clusterIconFreePositions = s.clusterIconFreePositions or {}
                    s.clusterIconFreePositions[sourceCluster] = s.clusterIconFreePositions[sourceCluster] or {}
                    s.clusterIconFreePositions[sourceCluster][keyStr] = {x=offsetX, y=offsetY}
                    self:ClearAllPoints()
                    self:SetPoint("CENTER", anchor, "CENTER", offsetX, offsetY)
                end
            end
            _ubt_dragState.draggingIcon = nil
            _ubt_dragState.sourceCluster = nil
            return
        end

        -- Normal mode: re-assign icon to cluster under cursor
        local uiScale = UIParent and UIParent:GetEffectiveScale() or 1
        local mx, my = GetCursorPosition()
        mx = mx / uiScale; my = my / uiScale

        local vm = GetUBTViewerMeta(viewer)
        local targetCluster = FindUBTClusterForCursor(vm, clusterCount, mx, my)
        targetCluster = tonumber(targetCluster) or sourceCluster

        s.clusterAssignments = s.clusterAssignments or {}
        s.clusterAssignments[keyStr] = targetCluster

        RemoveKeyFromAllUBTClusterOrders(s, keyStr)
        local targetOrderList = GetUBTClusterManualOrder(s, targetCluster)
        local targetKey = FindUBTNearestKeyInCluster(vm, targetCluster, self, mx, my)
        if targetKey then
            local inserted = false
            for idx, existing in ipairs(targetOrderList) do
                if tostring(existing) == targetKey then
                    table.insert(targetOrderList, idx, keyStr); inserted = true; break
                end
            end
            if not inserted then table.insert(targetOrderList, keyStr) end
        else
            table.insert(targetOrderList, keyStr)
        end

        _ubt_dragState.draggingIcon = nil
        _ubt_dragState.sourceCluster = nil
        pcall(UtilityIconViewers.ApplyViewerLayout, UtilityIconViewers, viewer)
    end)
end

local function ApplyUBTClusterIconDragHandlers(viewer, settings, clusterCount, groupedIcons)
    if not viewer or not settings.clusterUnlocked then return end
    if InCombatLockdown() then return end
    for ci = 1, clusterCount do
        local icons = groupedIcons and groupedIcons[ci]
        if type(icons) == "table" then
            for _, child in ipairs(icons) do
                if child and (child.Icon or child.icon) then
                    if child._ubtDragCluster ~= ci then
                        child._ubtDragCluster = ci
                        pcall(SetupUBTClusterIconDrag, child, viewer, ci)
                    end
                end
            end
        end
    end
end

local function ApplyUBTClusterDragState(viewer, settings, forceNow)
    if not viewer then return end
    if InCombatLockdown() and not forceNow then return end
    local vm = GetUBTViewerMeta(viewer)
    if not vm.clusterAnchors then return end
    local clusterCount = math.max(1, math.min(MAX_UBT_CLUSTER_GROUPS, SafeNumber(settings.clusterCount, DEFAULTS.clusterCount)))
    for i = 1, MAX_UBT_CLUSTER_GROUPS do
        local anchor = vm.clusterAnchors[i]
        if anchor then
            local inRange = (i <= clusterCount)
            local enabled = settings.clusterUnlocked and inRange
            local sampleMode = string.lower(tostring((settings.clusterSampleDisplayModes and settings.clusterSampleDisplayModes[i]) or "off"))
            local showForSamples = inRange and (sampleMode == "always")
            if enabled then
                anchor:Show()
                anchor:EnableMouse(true)
                anchor:SetBackdropColor(0, 0.1, 0.3, 0.25)
                anchor:SetBackdropBorderColor(0.2, 0.6, 1.0, 0.9)
            elseif showForSamples then
                anchor:Show()
                anchor:EnableMouse(false)
                anchor:SetBackdropColor(0, 0, 0, 0.05)
                anchor:SetBackdropBorderColor(0.2, 0.6, 1.0, 0.3)
            else
                anchor:Hide()
            end
        end
    end
end

-- Hide all UBT cluster anchors
local function HideAllUBTClusterAnchors(viewer)
    local vm = GetUBTViewerMeta(viewer)
    if vm.clusterAnchors then
        for i = 1, MAX_UBT_CLUSTER_GROUPS do
            local a = vm.clusterAnchors[i]
            if a then a:Hide() end
        end
    end
end


function UtilityIconViewers:ApplyViewerLayout(viewer)
    if not viewer or not viewer.GetName then return end
    if not viewer:IsShown() then return end
    if IsEditModeActive() then return end

    local settings = MyUtilityBuffTracker:GetSettings()
    local viewerFrame = viewer.viewerFrame
    if type(viewerFrame) == "string" then
        viewerFrame = _G[viewerFrame]
    end
    local container = viewerFrame or viewer

    -- Use Blizzard's itemFramePool when available (zero-allocation iterator)
    local icons = {}
    local pool = viewer.itemFramePool
    if pool then
        for child in pool:EnumerateActive() do
            if child and (child.Icon or child.icon) then
                table.insert(icons, child)
            end
        end
    else
        for i = 1, select("#", container:GetChildren()) do
            local child = select(i, container:GetChildren())
            if child and (child.Icon or child.icon) then
                table.insert(icons, child)
            end
        end
    end

    if #icons == 0 then
        SetViewerMetric(viewer, "lastNumRows", 0)
        return
    end

    for i, icon in ipairs(icons) do
        local state = GetIconState(icon)
        if state.creationOrder == nil then
            state.creationOrder = i
        end
    end
    table.sort(icons, _ubt_iconSortComparator)

    local inCombat = InCombatLockdown()
    for _, icon in ipairs(icons) do
        local iconState = GetIconState(icon)
        if not iconState.skinned and not iconState.skinPending then
            iconState.skinPending = true
            if inCombat then
                EnsurePendingEventFrame()
                UtilityIconViewers.__pendingIcons[icon] = { icon=icon, settings=settings, viewer=viewer }
                UtilityIconViewers.__iconSkinEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            else
                pcall(UtilityIconViewers.SkinIcon, UtilityIconViewers, icon, settings)
                iconState.skinPending = nil
            end
        end
    end

    local shownIcons = {}
    for _, icon in ipairs(icons) do
        if icon:IsShown() then table.insert(shownIcons, icon) end
    end

    -- Merge external icons from the registry
    if MyUtilityBuffTracker._externalIcons then
        for extFrame in pairs(MyUtilityBuffTracker._externalIcons) do
            if extFrame and extFrame:IsShown() and (extFrame.Icon or extFrame.icon) then
                local es = GetIconState(extFrame)
                es.lastX = nil
                es.lastY = nil
                es.lastSizeW = nil
                es.lastSizeH = nil
                es.creationOrder = es.creationOrder or 99999
                es.isExternal = true
                shownIcons[#shownIcons + 1] = extFrame
            end
        end
        table.sort(shownIcons, _ubt_iconSortComparator)
    end

    if #shownIcons == 0 then
        SetViewerMetric(viewer, "lastNumRows", 0)
        return
    end

    local iconSize = SafeNumber(settings.iconSize, DEFAULTS.iconSize)

    -- Default base size
    for _, icon in ipairs(shownIcons) do
        icon:SetSize(iconSize, iconSize)
    end

    local iconWidth, iconHeight = iconSize, iconSize
    local spacing = settings.spacing or DEFAULTS.spacing

    -- ===========================
    -- CLUSTER MODE
    -- ===========================
    if settings.multiClusterMode then
        local clusterCount = math.max(1, math.min(MAX_UBT_CLUSTER_GROUPS, SafeNumber(settings.clusterCount, DEFAULTS.clusterCount) or DEFAULTS.clusterCount))
        settings.clusterCount = clusterCount
        settings.clusterFlows = settings.clusterFlows or {}
        settings.clusterVerticalGrows = settings.clusterVerticalGrows or {}
        settings.clusterVerticalPins = settings.clusterVerticalPins or {}
        settings.clusterIconSizes = settings.clusterIconSizes or {}
        settings.clusterAssignments = settings.clusterAssignments or {}
        settings.clusterManualOrders = settings.clusterManualOrders or {}
        if settings.clusterCenterIcons == nil then settings.clusterCenterIcons = true end
        local centerClusterIcons = settings.clusterCenterIcons ~= false

        local vm = GetUBTViewerMeta(viewer)

        local groupedIcons = {}
        for i = 1, clusterCount do
            groupedIcons[i] = {}
            EnsureUBTClusterAnchorForIndex(viewer, settings, i)
        end

        -- Hide excess anchors
        if vm.clusterAnchors then
            for i = clusterCount + 1, MAX_UBT_CLUSTER_GROUPS do
                local anchor = vm.clusterAnchors[i]
                if anchor then anchor:Hide() end
            end
        end

        -- Show active anchors only when unlocked
        for i = 1, clusterCount do
            local anchor = vm.clusterAnchors and vm.clusterAnchors[i]
            if anchor then
                if settings.clusterUnlocked then anchor:Show() else anchor:Hide() end
            end
        end

        -- Assign icons to clusters
        for _, icon in ipairs(shownIcons) do
            local key = GetUtilityIconKey(icon)
            local assignedGroup = tonumber(key and settings.clusterAssignments[tostring(key)]) or 1
            if assignedGroup < 1 or assignedGroup > clusterCount then assignedGroup = 1 end
            table.insert(groupedIcons[assignedGroup], icon)
        end

        local rowLimit = SafeNumber(settings.rowLimit or settings.columns, DEFAULTS.rowLimit)
        local availableKeys = BuildUBTAvailableKeySet(viewer)

        -- Sort each group by manual order
        local orderIndexByCluster = {}
        for i = 1, clusterCount do
            orderIndexByCluster[i] = {}
            local orderedKeys = BuildUBTOrderedKeysForCluster(settings, i, availableKeys)
            for idx, key in ipairs(orderedKeys) do
                orderIndexByCluster[i][tostring(key)] = idx
            end
            table.sort(groupedIcons[i], function(a, b)
                local keyA = GetUtilityIconKey(a)
                local keyB = GetUtilityIconKey(b)
                local posA = keyA and orderIndexByCluster[i][tostring(keyA)]
                local posB = keyB and orderIndexByCluster[i][tostring(keyB)]
                if posA and posB and posA ~= posB then return posA < posB end
                if posA and not posB then return true end
                if posB and not posA then return false end
                local aOrder = (IconRuntimeState[a] and IconRuntimeState[a].creationOrder) or 0
                local bOrder = (IconRuntimeState[b] and IconRuntimeState[b].creationOrder) or 0
                return aOrder < bOrder
            end)
        end

        local totalVisibleIcons = 0
        for groupIndex = 1, clusterCount do
            local anchor = vm.clusterAnchors and vm.clusterAnchors[groupIndex]
            local groupIcons = groupedIcons[groupIndex]
            if anchor and groupIcons then
                local clusterFlow = string.lower(tostring(settings.clusterFlows[groupIndex] or settings.clusterFlow or DEFAULTS.clusterFlow or "horizontal"))
                local verticalGrow = string.lower(tostring(settings.clusterVerticalGrows[groupIndex] or "down"))
                local verticalPin  = string.lower(tostring(settings.clusterVerticalPins[groupIndex]  or "center"))
                local clusterIconSize = SafeNumber(settings.clusterIconSizes[groupIndex], iconSize)
                if clusterFlow ~= "vertical" then clusterFlow = "horizontal" end
                if verticalGrow ~= "up"      then verticalGrow = "down" end
                if verticalPin ~= "top" and verticalPin ~= "bottom" then verticalPin = "center" end

                local groupCount = #groupIcons
                totalVisibleIcons = totalVisibleIcons + groupCount
                local anchorWidth  = anchor:GetWidth()  or 120
                local anchorHeight = anchor:GetHeight() or 120

                if groupCount > 0 then
                    local freeMode = settings.clusterFreePositionModes and settings.clusterFreePositionModes[groupIndex]
                    if freeMode then
                        local savedPos = (settings.clusterIconFreePositions and settings.clusterIconFreePositions[groupIndex]) or {}
                        for idx, icon in ipairs(groupIcons) do
                            icon:SetSize(clusterIconSize, clusterIconSize)
                            icon:ClearAllPoints()
                            local iconKey = GetUtilityIconKey(icon)
                            local keyStr = iconKey and tostring(iconKey) or ("_idx_"..idx)
                            local pos = savedPos[keyStr]
                            if pos then
                                icon:SetPoint("CENTER", anchor, "CENTER", pos.x or 0, pos.y or 0)
                            else
                                local col   = (idx-1) % 3
                                local row_i = math.floor((idx-1) / 3)
                                icon:SetPoint("CENTER", anchor, "CENTER",
                                    (col-1) * (clusterIconSize + spacing),
                                    -row_i  * (clusterIconSize + spacing))
                            end
                        end
                    else
                        -- Normal grid/flow layout
                        local layoutCount = groupCount
                        local lineSize = layoutCount
                        local lineCount = 1
                        if rowLimit and rowLimit > 0 then
                            lineSize = math.max(1, rowLimit)
                            lineCount = math.ceil(layoutCount / lineSize)
                        end

                        local columns, rows
                        if clusterFlow == "vertical" then
                            rows = math.min(layoutCount, lineSize); columns = lineCount
                        else
                            columns = math.min(layoutCount, lineSize); rows = lineCount
                        end

                        local yBase = -15 - (clusterIconSize / 2)
                        if clusterFlow == "vertical" then
                            if verticalPin == "top"    then yBase = anchorHeight - 5 - (clusterIconSize / 2)
                            elseif verticalPin == "bottom" then yBase = 5 + (clusterIconSize / 2)
                            else yBase = anchorHeight / 2 end
                        end

                        local iconsPerRow = {}
                        for idx2 = 1, groupCount do
                            local ri = math.floor((idx2-1) / lineSize)
                            iconsPerRow[ri] = (iconsPerRow[ri] or 0) + 1
                        end

                        local rowColCounter = {}
                        for idx, icon in ipairs(groupIcons) do
                            local rowIndex, colIndex
                            if clusterFlow == "vertical" then
                                rowIndex = (idx-1) % lineSize
                                colIndex = math.floor((idx-1) / lineSize)
                            else
                                rowIndex = math.floor((idx-1) / lineSize)
                                rowColCounter[rowIndex] = (rowColCounter[rowIndex] or 0)
                                colIndex = rowColCounter[rowIndex]
                                rowColCounter[rowIndex] = rowColCounter[rowIndex] + 1
                            end

                            icon:SetSize(clusterIconSize, clusterIconSize)
                            icon:ClearAllPoints()

                            if clusterFlow == "vertical" then
                                local x = 5 + (clusterIconSize/2) + colIndex * (clusterIconSize+spacing)
                                local y
                                if verticalPin == "center" then y = yBase + rowIndex*(clusterIconSize+spacing)
                                elseif verticalGrow == "up" then y = yBase + rowIndex*(clusterIconSize+spacing)
                                else y = yBase - rowIndex*(clusterIconSize+spacing) end
                                icon:SetPoint("CENTER", anchor, "BOTTOMLEFT", x, y)
                            else
                                if centerClusterIcons then
                                    local rowCols = iconsPerRow[rowIndex] or columns
                                    local rowWidth   = rowCols * clusterIconSize + (rowCols-1) * spacing
                                    local groupHeight = rows  * clusterIconSize + (rows-1)  * spacing
                                    local x = -rowWidth/2 + clusterIconSize/2 + colIndex*(clusterIconSize+spacing)
                                    local y =  groupHeight/2 - clusterIconSize/2 - rowIndex*(clusterIconSize+spacing)
                                    icon:SetPoint("CENTER", anchor, "CENTER", x, y)
                                else
                                    local x = 5 + (clusterIconSize/2) + colIndex*(clusterIconSize+spacing)
                                    local y = (anchorHeight-5) - (clusterIconSize/2) - rowIndex*(clusterIconSize+spacing)
                                    icon:SetPoint("CENTER", anchor, "BOTTOMLEFT", x, y)
                                end
                            end
                        end
                    end -- freeMode else
                end -- groupCount > 0
            end
        end

        vm.clusterIconsByIndex = groupedIcons
        ApplyUBTClusterDragState(viewer, settings)
        ApplyUBTClusterIconDragHandlers(viewer, settings, clusterCount, groupedIcons)
        SetViewerMetric(viewer, "lastNumRows", 1)
        SetViewerMetric(viewer, "iconCount", totalVisibleIcons)
        if not InCombatLockdown() then viewer:SetSize(2, 2) end
        return
    else
        -- Non-cluster mode: hide all cluster anchors
        HideAllUBTClusterAnchors(viewer)
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

        if not InCombatLockdown() then viewer:SetSize(totalWidth, totalHeight) end
        return
    end

    -- Dynamic mode
    local rowLimit = SafeNumber(settings.rowLimit or settings.columns, DEFAULTS.rowLimit)

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
        if not InCombatLockdown() then
            viewer:SetSize(totalWidth, rowSize)
        end
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

        for r = 1, numRows do
            local row = rows[r]

            local rowSize = (settings.rowSizes and settings.rowSizes[r]) or iconSize
            local w = rowSize
            local h = rowSize

            local rowWidth = #row * w + (#row - 1) * spacing
            if rowWidth > maxRowWidth then maxRowWidth = rowWidth end

            local startX = -rowWidth/2 + w/2

            local y = 0
            if r > 1 then
                local rowSpacing = iconHeight + spacing
                if growDir == "up" then
                    y = (r-1) * rowSpacing
                else
                    y = -(r-1) * rowSpacing
                end
            end

            for i, icon in ipairs(row) do
                local x = startX + (i-1)*(w+spacing)
                icon:SetSize(w, h)
                icon:ClearAllPoints()
                icon:SetPoint("CENTER", container, "CENTER", x, y)
            end
        end

        local rowSpacing = iconHeight + spacing
        local totalHeight = (numRows-1)*rowSpacing + iconHeight

        SetViewerMetric(viewer, "lastNumRows", numRows)

        if not InCombatLockdown() then
            viewer:SetSize(maxRowWidth, totalHeight)
        end
    end
    SetViewerMetric(viewer, "iconCount", #shownIcons)
end

function UtilityIconViewers:RescanViewer(viewer)
    if not viewer or not viewer.GetName then return end
    UtilityIconViewers:ApplyViewerLayout(viewer)
end

MyUtilityBuffTracker = MyUtilityBuffTracker or {}
MyUtilityBuffTracker.IconViewers = UtilityIconViewers
-- ---------------------------
-- HookViewer
-- ---------------------------
local function HookViewer()
    local viewer = _G["UtilityCooldownViewer"]
    if not viewer then return end

    viewer:SetMovable(not MyUtilityBuffTrackerDB.locked)
    viewer:EnableMouse(not MyUtilityBuffTrackerDB.locked)

    viewer:HookScript("OnShow", function(self) pcall(UtilityIconViewers.RescanViewer, UtilityIconViewers, self) end)
    viewer:HookScript("OnSizeChanged", function(self) pcall(UtilityIconViewers.ApplyViewerLayout, UtilityIconViewers, self) end)

    local viewerState = ViewerRuntimeState[viewer]
    if not viewerState then
        viewerState = {}
        ViewerRuntimeState[viewer] = viewerState
    end
    -- Hook Blizzard layout for instant response
    if not viewerState._refreshLayoutHooked and viewer.RefreshLayout then
        hooksecurefunc(viewer, "RefreshLayout", function(self)
            if IsEditModeActive() then return end
            if not self:IsShown() then return end
            -- Invalidate count so the throttled dispatch re-runs layout
            if viewerState.eventFrame then
                viewerState.eventFrame._lastActiveCount = -1
                viewerState.eventFrame:Show()
            end
        end)
        viewerState._refreshLayoutHooked = true
    end

    -- Event-driven refresh + glow system (show/hide dispatch â€” zero CPU when idle)
    if not viewerState.eventFrame then
        local ef = CreateFrame("Frame")
        ef:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        ef:RegisterUnitEvent("UNIT_AURA", "player")
        ef:RegisterEvent("PLAYER_REGEN_ENABLED")
        ef:Hide() -- starts hidden; zero CPU until an event fires
        ef._lastActiveCount = -1
        ef._lastRun = 0

        ef:SetScript("OnEvent", function(self, event, arg1)
            if event == "UNIT_AURA" and arg1 ~= "player" then return end
            if event == "SPELL_UPDATE_COOLDOWN" then
                if not InCombatLockdown() then return end
                local settings = MyUtilityBuffTracker:GetSettings()
                if not HasCooldownOrReadyModeGlow_UBT(settings) and not HasReadyOrCooldownModeSound_UBT(settings) then
                    return
                end
            end
            self:Show()
        end)

        -- Show/hide dispatch with timestamp throttle (max ~4/sec, zero ticking)
        -- Layout only runs when active icon count changes.
        ef:SetScript("OnUpdate", function(self)
            self:Hide()
            local now = GetTime()
            if now - self._lastRun < 0.25 then return end
            self._lastRun = now
            if IsEditModeActive() then return end
            if not viewer or not viewer:IsShown() then return end

            -- Layout on icon count change only
            local pool = viewer.itemFramePool
            local layoutRan = false
            if pool and not InCombatLockdown() then
                local count = pool:GetNumActive()
                if count ~= self._lastActiveCount then
                    self._lastActiveCount = count
                    UtilityIconViewers:RescanViewer(viewer)
                    layoutRan = true
                end
            end

            -- Enforce charge/cooldown text positions (only after layout ran)
            if layoutRan and pool and pool:GetNumActive() > 0 then
                for icon in pool:EnumerateActive() do
                    local is = GetIconState(icon)
                    if is.chargeTextRef then
                        is.chargeTextRef:ClearAllPoints()
                        is.chargeTextRef:SetPoint(is.chargeAnchor, icon, is.chargeAnchor, is.chargeOffX, is.chargeOffY)
                    end
                    if is.cdTextRef then
                        is.cdTextRef:ClearAllPoints()
                        is.cdTextRef:SetPoint(is.cdAnchor, icon, is.cdAnchor, is.cdOffX, is.cdOffY)
                    end
                end
            end

            -- Hook cooldown tracking on all active icons (needed for CD override
            -- even when no per-spell glows are configured)
            local pool = viewer.itemFramePool
            if pool and pool:GetNumActive() > 0 then
                for icon in pool:EnumerateActive() do
                    if icon and (icon.Icon or icon.icon) then
                        HookCooldownTracking(icon)
                    end
                end
            end

            -- Glow + sound update
            local settings = MyUtilityBuffTracker:GetSettings()
            local spellGlows = settings and settings.spellGlows or {}
            local spellSounds = settings and settings.spellSounds or {}
            local soundRevision = GetSpellSoundsRevision_UBT(settings)
            if spellSounds ~= ubtSoundCfgSource or soundRevision ~= ubtSoundCfgRevision then
                RebuildEnabledSoundLookup_UBT(spellSounds)
                ubtSoundCfgRevision = soundRevision
            end
            local hasSounds = InCombatLockdown() and next(ubtEnabledSoundLookup) ~= nil
            if hasSounds then
                for k in pairs(_ubt_activeSoundCfgByKey) do _ubt_activeSoundCfgByKey[k] = nil end
                for k in pairs(_ubt_activeSoundModeByKey) do _ubt_activeSoundModeByKey[k] = nil end
                for k in pairs(_ubt_activeSoundReadyByKey) do _ubt_activeSoundReadyByKey[k] = nil end
            end
            local activeSoundCfgByKey = hasSounds and _ubt_activeSoundCfgByKey or nil
            local activeSoundModeByKey = hasSounds and _ubt_activeSoundModeByKey or nil
            local activeSoundReadyByKey = hasSounds and _ubt_activeSoundReadyByKey or nil
            local canGlow = (LCG ~= nil)
            -- Use Blizzard's itemFramePool (zero-allocation iterator)
            local pool = viewer.itemFramePool
            local hasGlowConfig = next(spellGlows) ~= nil

            if canGlow and hasGlowConfig then
                table_wipe(ubtEnabledGlowLookup)
                for skey, cfg in pairs(spellGlows) do
                    if type(cfg) == "table" and cfg.enabled then
                        ubtEnabledGlowLookup[tostring(skey)] = cfg
                    end
                end
            else
                table_wipe(ubtEnabledGlowLookup)
            end

            if pool and pool:GetNumActive() > 0 then
                if not next(ubtEnabledGlowLookup) then
                    for icon in pool:EnumerateActive() do
                        if icon._ubtGlowing then
                            StopGlow_UBT(icon)
                            icon._ubtGlowing = false
                            icon._ubtGlowType = nil
                        end
                    end
                end

                local inCombat = InCombatLockdown()
                for icon in pool:EnumerateActive() do
                    if icon and (icon.Icon or icon.icon) then
                        if (not inCombat) or not icon._ubtCachedKey then
                            local freshKey = GetUtilityIconKey(icon)
                            if freshKey then
                                icon._ubtCachedKey = freshKey
                                icon._ubtCachedKeyStr = tostring(freshKey)
                            end
                        end
                        local key = icon._ubtCachedKey
                        if key then
                            local glowCfg = ubtEnabledGlowLookup[icon._ubtCachedKeyStr]
                            local shouldGlow = false
                            if glowCfg and icon:IsShown() then
                                if glowCfg.mode == "ready" then
                                    shouldGlow = IsIconReady(icon)
                                    if not shouldGlow then
                                        local sid = tonumber(key)
                                        if sid and C_Spell and C_Spell.GetSpellCooldown then
                                            local info = C_Spell.GetSpellCooldown(sid)
                                            if info and info.isOnGCD then
                                                shouldGlow = true
                                            end
                                        end
                                    end
                                elseif glowCfg.mode == "cooldown" then
                                    shouldGlow = IsIconOnCooldown(icon)
                                    if shouldGlow then
                                        local sid = tonumber(key)
                                        if sid and C_Spell and C_Spell.GetSpellCooldown then
                                            local info = C_Spell.GetSpellCooldown(sid)
                                            if info and info.isOnGCD then
                                                shouldGlow = false
                                            end
                                        end
                                    end
                                end
                            end

                            -- Use per-spell config
                            local glowType = glowCfg and glowCfg.glowType or "pixel"
                            local glowColor = glowCfg and glowCfg.color or _ubt_defaultGlowColor

                            if shouldGlow then
                                if not icon._ubtGlowing or icon._ubtGlowType ~= glowType then
                                    if icon._ubtGlowing then
                                        StopGlow_UBT(icon)
                                    end
                                    ubtGlowColor[1] = glowColor.r or 1
                                    ubtGlowColor[2] = glowColor.g or 1
                                    ubtGlowColor[3] = glowColor.b or 0
                                    ubtGlowColor[4] = glowColor.a or 1
                                    if glowType == "autocast" then
                                        LCG.AutoCastGlow_Start(icon, ubtGlowColor, 4, 0.6, nil, 0, 0, "ubtGlow")
                                    elseif glowType == "button" then
                                        LCG.ButtonGlow_Start(icon, ubtGlowColor, 0.5)
                                    elseif glowType == "proc" then
                                        LCG.ProcGlow_Start(icon, ubtProcOpts)
                                    else
                                        LCG.PixelGlow_Start(icon, ubtGlowColor, 8, 0.25, nil, nil, 0, 0, false, "ubtGlow")
                                    end
                                    icon._ubtGlowing = true
                                    icon._ubtGlowType = glowType
                                end
                            else
                                if icon._ubtGlowing then
                                    StopGlow_UBT(icon)
                                    icon._ubtGlowing = false
                                    icon._ubtGlowType = nil
                                end
                            end

                            if hasSounds and icon:IsShown() then
                                local keyStr = icon._ubtCachedKeyStr or tostring(key)
                                local soundCfg = ubtEnabledSoundLookup[keyStr]
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
                                    local isReady = IsReadyForSound_UBT(icon, key)
                                    if activeSoundReadyByKey[keyStr] == nil then
                                        activeSoundReadyByKey[keyStr] = isReady
                                    end
                                end
                            end
                        elseif icon._ubtGlowing then
                            StopGlow_UBT(icon)
                            icon._ubtGlowing = false
                            icon._ubtGlowType = nil
                        end
                    end
                end
            else
                if canGlow then
                    -- No active icons: clear any stale glows and still process sound expire transitions.
                    local viewerState = ViewerRuntimeState[viewer]
                    if viewerState and viewerState._ubtLastPool then
                        for icon in pairs(viewerState._ubtLastPool) do
                            if icon and icon._ubtGlowing then
                                StopGlow_UBT(icon)
                                icon._ubtGlowing = false
                                icon._ubtGlowType = nil
                            end
                        end
                    end
                end
            end

            if hasSounds then
                for keyStr, cfg in pairs(activeSoundCfgByKey) do
                    local mode = activeSoundModeByKey[keyStr] or "ready"
                    local prevReady = ubtSoundReadyPrevByKey[keyStr]
                    local curReady = activeSoundReadyByKey[keyStr] and true or false
                    if prevReady ~= nil then
                        local playOnReady = (mode == "ready" or mode == "both")
                        local playOnCooldown = (mode == "cooldown" or mode == "both")
                        if playOnReady and curReady and not prevReady then
                            PlaySpellSound_UBT(keyStr, cfg)
                        elseif playOnCooldown and (not curReady) and prevReady then
                            PlaySpellSound_UBT(keyStr, cfg)
                        end
                    end
                end

                ResetSoundState_UBT(false)
                for keyStr, cfg in pairs(activeSoundCfgByKey) do
                    ubtSoundActivePrevByKey[keyStr] = true
                    ubtSoundPrevCfgByKey[keyStr] = cfg
                    ubtSoundPrevModeByKey[keyStr] = activeSoundModeByKey[keyStr] or "ready"
                    ubtSoundReadyPrevByKey[keyStr] = activeSoundReadyByKey[keyStr] and true or false
                end
            else
                ResetSoundState_UBT(false)
            end
        end)

        viewerState.eventFrame = ef

        -- ===========================
        -- Assisted Combat Highlight (blue rotation helper glow)
        -- Polls C_AssistedCombat.GetNextCastSpell() via C_Timer.NewTicker
        -- (zero CPU when viewer hidden, ~5 calls/sec when visible).
        -- ===========================
        local ubtAssistedTicker = nil
        local ubtAssistedLastSpellID = nil
        local UBT_ASSISTED_COLOR = { 0.3, 0.6, 1.0, 1.0 }

        local function UBTAssistedTick()
            local settings = MyUtilityBuffTracker:GetSettings()
            if not settings or not settings.assistedCombatHighlight then
                if ubtAssistedLastSpellID ~= nil then
                    ubtAssistedLastSpellID = nil
                    local pool = viewer.itemFramePool
                    if pool and LCG then
                        for icon in pool:EnumerateActive() do
                            if icon._ubtAssistedGlowing then
                                LCG.PixelGlow_Stop(icon, "ubtAssisted")
                                icon._ubtAssistedGlowing = false
                            end
                        end
                    end
                end
                return
            end
            if not C_AssistedCombat or not C_AssistedCombat.GetNextCastSpell then return end
            if not LCG then return end

            local nextSpellID = C_AssistedCombat.GetNextCastSpell(false)
            if nextSpellID == ubtAssistedLastSpellID then return end
            ubtAssistedLastSpellID = nextSpellID

            local pool = viewer.itemFramePool
            if not pool then return end

            for icon in pool:EnumerateActive() do
                if icon and (icon.Icon or icon.icon) and icon:IsShown() then
                    local key = icon._ubtCachedKey
                    if not key then
                        key = GetUtilityIconKey(icon)
                        if key then
                            icon._ubtCachedKey = key
                            icon._ubtCachedKeyStr = tostring(key)
                        end
                    end

                    local shouldHighlight = (nextSpellID ~= nil and key == nextSpellID)
                    if shouldHighlight and not icon._ubtAssistedGlowing then
                        LCG.PixelGlow_Start(icon, UBT_ASSISTED_COLOR, 12, 0.25, 8, 2, 0, 0, false, "ubtAssisted")
                        icon._ubtAssistedGlowing = true
                    elseif not shouldHighlight and icon._ubtAssistedGlowing then
                        LCG.PixelGlow_Stop(icon, "ubtAssisted")
                        icon._ubtAssistedGlowing = false
                    end
                end
            end
        end

        local function StartUBTAssistedTicker()
            if ubtAssistedTicker then return end
            local rate = AssistedCombatManager and AssistedCombatManager:GetUpdateRate() or 0.2
            if rate < 0.1 then rate = 0.1 end
            ubtAssistedTicker = C_Timer.NewTicker(rate, UBTAssistedTick)
        end

        local function StopUBTAssistedTicker()
            if ubtAssistedTicker then
                ubtAssistedTicker:Cancel()
                ubtAssistedTicker = nil
            end
            if ubtAssistedLastSpellID ~= nil then
                ubtAssistedLastSpellID = nil
                local pool = viewer.itemFramePool
                if pool and LCG then
                    for icon in pool:EnumerateActive() do
                        if icon._ubtAssistedGlowing then
                            LCG.PixelGlow_Stop(icon, "ubtAssisted")
                            icon._ubtAssistedGlowing = false
                        end
                    end
                end
            end
        end

        -- Only tick when viewer is visible AND in combat (zero CPU otherwise)
        viewer:HookScript("OnShow", function()
            if InCombatLockdown() then StartUBTAssistedTicker() end
        end)
        viewer:HookScript("OnHide", function() StopUBTAssistedTicker() end)
        -- Combat enter/leave hooks for assisted ticker lifecycle
        local ubtAssistedCombatFrame = CreateFrame("Frame")
        ubtAssistedCombatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        ubtAssistedCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        ubtAssistedCombatFrame:SetScript("OnEvent", function(_, event)
            if event == "PLAYER_REGEN_DISABLED" then
                if viewer:IsShown() then StartUBTAssistedTicker() end
            else
                StopUBTAssistedTicker()
            end
        end)
    end
end

-- Ensure DB and try to hook immediately if the frame exists now
EnsureDB()
-- HookViewer() and event registration deferred to PLAYER_LOGIN, gated by enabled state

-- If the Utility viewer is created later by another addon, ensure we hook when it's available
local hookFrame = CreateFrame("Frame")
hookFrame:SetScript("OnEvent", function(self, event, name)
    if _G["UtilityCooldownViewer"] then
        HookViewer()
        self:UnregisterEvent("ADDON_LOADED")
    end
end)

-- ---------------------------
-- Config Panel (Interface Options) with safe deferred registration
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
                    local viewer = _G["UtilityCooldownViewer"]
                    if viewer then
                        ForceReskinViewer(viewer)
                        pcall(UtilityIconViewers.ApplyViewerLayout, UtilityIconViewers, viewer)
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

    -- Use default thumb from OptionsSliderTemplate

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
        local viewer = _G["UtilityCooldownViewer"]
        if viewer then
            ForceReskinViewer(viewer)
            pcall(UtilityIconViewers.ApplyViewerLayout, UtilityIconViewers, viewer)
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
local function CreateCheck(parent, labelText, initial, onChanged)
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
        local viewer = _G["UtilityCooldownViewer"]
        if viewer then
            ForceReskinViewer(viewer)
            pcall(UtilityIconViewers.ApplyViewerLayout, UtilityIconViewers, viewer)
        end
    end)

    return container
end

function MyUtilityBuffTracker:OnProfileChanged()
    -- Refresh the viewer after a short delay
    C_Timer.After(0.5, function()
        local viewer = _G["UtilityCooldownViewer"]
        if viewer then
            -- Force complete refresh
            ForceReskinViewer(viewer)
            pcall(UtilityIconViewers.ApplyViewerLayout, UtilityIconViewers, viewer)

            -- Trigger buff update if available
            if UtilityIconViewers and UtilityIconViewers.UpdateAllBuffs then
                pcall(UtilityIconViewers.UpdateAllBuffs, UtilityIconViewers)
            end
        end
        UpdateCooldownManagerVisibility()
    end)

    -- Refresh options panel after a short delay to ensure profile change is complete
    C_Timer.After(0.5, function()
        if _G.MyUtilityBuffTrackerPanel and _G.MyUtilityBuffTrackerPanel._rebuildConfigUI then
            _G.MyUtilityBuffTrackerPanel:_rebuildConfigUI()
        end
    end)
end

-- Scrollable, full-featured options panel for Interface Options
local optionsPanel

-- Old CreateOptionsPanel removed; options are now handled by Ace3 AceConfig (ui/options/UtilityBuffsOptions.lua)
function MyUtilityBuffTracker:CreateOptionsPanel() return nil end

-- Gate all background processing behind enabled state at login
local utilityEnableGate = CreateFrame("Frame")
utilityEnableGate:RegisterEvent("PLAYER_LOGIN")
utilityEnableGate:SetScript("OnEvent", function()
    local settings = MyUtilityBuffTracker:GetSettings()
    if settings and settings.enabled ~= false then
        -- Register mount visibility events while enabled.
        mountEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        mountEventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
        -- Hook the viewer (ticker + layout hooks)
        HookViewer()
        -- If viewer isn't created yet, hook when it appears
        hookFrame:RegisterEvent("ADDON_LOADED")
    end
end)
