-- ============================================================
-- CkraigCooldownManager :: CooldownBars :: BarCore
-- ============================================================
-- Master module for cooldown bar display (BuffBarCooldownViewer).
-- Handles AceAddon registration, bar styling, layout/reposition,
-- cluster mode, glow/fade, and event-driven updates.
--
-- Section map (search for "[SECTION]" to jump):
--   [SECTION: UTILITIES]       - HideAllIconBorders, FindIconTexture
--   [SECTION: PROFILE]         - Class/spec profile switching
--   [SECTION: LIBRARIES]       - Library references
--   [SECTION: SETTINGS DETECT] - Zero-alloc settings change detection
--   [SECTION: BAR STATE]       - Per-bar state (weak-keyed metatables)
--   [SECTION: FRAME SETUP]     - BuffBarCooldownViewer frame creation
--   [SECTION: ADDON INIT]      - AceAddon NewAddon, OnInitialize, OnProfileChanged
--   [SECTION: SPELL IDENTITY]  - Spell resolution helpers
--   [SECTION: CLUSTER ANCHORS] - Multi-anchor cluster system
--   [SECTION: BAR VISIBILITY]  - Icon show/hide, bar icon refresh
--   [SECTION: STYLE]           - StyleBar and colour helpers
--   [SECTION: LAYOUT]          - RepositionAllBars (standard/cluster/grid)
--   [SECTION: COOLDOWN PASS]   - Fade + glow merged update pass
--   [SECTION: ON ENABLE]       - Event registration, hooks, timers
--   [SECTION: EXPORTS]         - _barInternals table
-- ============================================================

-- [SECTION: UTILITIES]
-- Delegate to the cached CCM.Utils versions (loaded from Helpers.lua)
local CCM = _G.CkraigCooldownManager
local HideAllIconBorders = CCM.Utils.HideAllIconBorders
local FindIconTexture = CCM.Utils.FindIconTexture

-- [SECTION: PROFILE]
local function GetClassSpecProfileName()
    local _, class = UnitClass("player")
    local specIndex = GetSpecialization and GetSpecialization()
    local specName = specIndex and select(2, GetSpecializationInfo(specIndex)) or "Default"
    return class .. "_" .. (specName or "Default")
end
-- Switch to the correct profile for current class/spec if it exists
local function SwitchProfileForClassSpec(db)
    if not db or not db.GetCurrentProfile then return end
    local profileName = GetClassSpecProfileName()
    if db:GetCurrentProfile() ~= profileName then
        local profiles = {}
        db:GetProfiles(profiles)
        for _, name in ipairs(profiles) do
            if name == profileName then
                db:SetProfile(profileName)
                return
            end
        end
    end
end

-- Event frame to handle spec/profile switching

local function IsInCombat() return InCombatLockdown() end

function CkraigCooldownManager:HideUnusedBars()
    for _, bar in ipairs(self.activeBars or {}) do
        if not bar:IsNeededForSpec() then
            bar:Hide()
            bar:UnregisterAllEvents()
        end
    end
end

local specProfileFrame = CreateFrame("Frame")
specProfileFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
specProfileFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
specProfileFrame:SetScript("OnEvent", function()
    if _G.CkraigCooldownManager and _G.CkraigCooldownManager.db then
        SwitchProfileForClassSpec(_G.CkraigCooldownManager.db)
    end
end)

-- [SECTION: LIBRARIES]
local LibEditModeOverride = LibStub("LibEditModeOverride-1.0", true)
local LibEditMode = LibStub("LibEditMode", true)
local LCG = LibStub("LibCustomGlow-1.0", true)
-- Removed unused locals: AceDB, AceDBOptions, LibDualSpec, AceConfig, AceConfigDialog
local bbGlowColor = {1, 1, 1, 1} -- reusable color array for PixelGlow

-- [SECTION: SETTINGS DETECT]
-- Style version: bumps when bar settings change; StyleBar skips redundant work
local _bb_styleVersion = 0
local _bb_spellColorVersion = 0

-- Zero-allocation settings change detection (replaces per-callback version bumps)
local _bb_fp = {}
local function BarSettingsChanged(settings)
    local changed = false
    local v
    v = settings.font or ""; if _bb_fp[1] ~= v then _bb_fp[1] = v; changed = true end
    v = settings.texture or ""; if _bb_fp[2] ~= v then _bb_fp[2] = v; changed = true end
    v = settings.barHeight or 24; if _bb_fp[3] ~= v then _bb_fp[3] = v; changed = true end
    v = settings.barTextFontSize or 11; if _bb_fp[4] ~= v then _bb_fp[4] = v; changed = true end
    v = settings.timerTextFontSize or 11; if _bb_fp[5] ~= v then _bb_fp[5] = v; changed = true end
    v = settings.borderSize or 0; if _bb_fp[6] ~= v then _bb_fp[6] = v; changed = true end
    v = settings.backdropBorderSize or 0; if _bb_fp[7] ~= v then _bb_fp[7] = v; changed = true end
    v = settings.barWidth or 200; if _bb_fp[8] ~= v then _bb_fp[8] = v; changed = true end
    v = settings.useClassColor and true or false; if _bb_fp[9] ~= v then _bb_fp[9] = v; changed = true end
    v = settings.hideIcons and true or false; if _bb_fp[10] ~= v then _bb_fp[10] = v; changed = true end
    v = settings.hideBarName and true or false; if _bb_fp[11] ~= v then _bb_fp[11] = v; changed = true end
    v = settings.timerTextAlign or "RIGHT"; if _bb_fp[12] ~= v then _bb_fp[12] = v; changed = true end
    v = settings.stackFontSize or 14; if _bb_fp[13] ~= v then _bb_fp[13] = v; changed = true end
    v = settings.stackFontOffsetX or 0; if _bb_fp[14] ~= v then _bb_fp[14] = v; changed = true end
    v = settings.stackFontOffsetY or 0; if _bb_fp[15] ~= v then _bb_fp[15] = v; changed = true end
    v = settings.iconWidth or 24; if _bb_fp[16] ~= v then _bb_fp[16] = v; changed = true end
    v = settings.iconHeight or 24; if _bb_fp[17] ~= v then _bb_fp[17] = v; changed = true end
    v = _bb_spellColorVersion; if _bb_fp[18] ~= v then _bb_fp[18] = v; changed = true end
    v = settings.showIconCooldownSweep and true or false; if _bb_fp[19] ~= v then _bb_fp[19] = v; changed = true end
    return changed
end

local function InvalidateBarStyle()
    _bb_styleVersion = _bb_styleVersion + 1
    wipe(_bb_fp)
end

-- [SECTION: BAR STATE]
-- Pooled tables (avoids GC churn on every cooldown event)
local _bb_poolFrames = {}
local _bb_poolActive = {}

-- Per-bar state (weak-keyed to avoid leaking pool frames)
local _bb_barState = setmetatable({}, { __mode = "k" })
local function GetBarState(bar)
    local s = _bb_barState[bar]
    if not s then s = {} _bb_barState[bar] = s end
    return s
end

local function SetBarStateValue(bar, key, value)
    if not bar then return end
    local s = GetBarState(bar)
    s[key] = value
end

local function GetBarStateValue(bar, key)
    if not bar then return nil end
    local s = _bb_barState[bar]
    return s and s[key] or nil
end

-- (Moved below CkraigCooldownManager definition)


-- When custom slider changes, update Edit Mode width
local function SetEditModeWidth(newWidth)
    if not LibEditModeOverride or not BuffBarCooldownViewer then return end
    local frame = BuffBarCooldownViewer
    local setting = (Enum and Enum.EditModeSystem and Enum.EditModeSystem.BuffBarCooldownViewer and Enum.EditModeSetting and Enum.EditModeSetting.Width) or "Width"
    pcall(function()
        LibEditModeOverride:SetFrameSetting(frame, setting, newWidth)
        LibEditModeOverride:ApplyChanges()
    end)
end

-- [SECTION: FRAME SETUP]
-- Ensure BuffBarCooldownViewer exists for this addon
if not _G.BuffBarCooldownViewer then
    local f = CreateFrame("Frame", "BuffBarCooldownViewer", UIParent, "BackdropTemplate")
    f:SetSize(220, 300)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if _G.CkraigCooldownManager and _G.CkraigCooldownManager.SaveBuffBarPosition then
            _G.CkraigCooldownManager:SaveBuffBarPosition()
        end
    end)
    f:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 8})
    f:SetBackdropColor(0,0,0,0.3)
    f:SetBackdropBorderColor(0.2,0.2,0.2,0.8)
    _G.BuffBarCooldownViewer = f

    -- Add a second blue box for Group 2
    local group2Box = CreateFrame("Frame", "BuffBarCooldownViewerGroup2", UIParent, "BackdropTemplate")
    group2Box:SetSize(220, 300)
    group2Box:SetPoint("CENTER", UIParent, "CENTER", 240, 0) -- Offset to the right of Group 1
    group2Box:SetMovable(true)
    group2Box:EnableMouse(true)
    group2Box:RegisterForDrag("LeftButton")
    group2Box:SetScript("OnDragStart", group2Box.StartMoving)
    group2Box:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position logic for Group 2 can be added later
    end)
    group2Box:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 8})
    group2Box:SetBackdropColor(0,0.3,0.8,0.3) -- Blue tint for Group 2
    group2Box:SetBackdropBorderColor(0.2,0.2,0.8,0.8)
    group2Box:Hide() -- Only show when unlocking icons
    _G.BuffBarCooldownViewerGroup2 = group2Box
end
-- [SECTION: ADDON INIT]
local AddonName = "CkraigCooldownManager"
local CkraigCooldownManager = LibStub("AceAddon-3.0"):NewAddon(AddonName, "AceEvent-3.0")

local LSM = LibStub("LibSharedMedia-3.0")
local FADE_THRESHOLD = 0.3
local BAR_FADE_ENABLED = false
local bbEnabledSoundLookup = {}
local bbSoundCfgSource = nil
local bbSoundCfgRevision = -1
local bbSoundActivePrevByKey = {}
local bbSoundPrevCfgByKey = {}
local bbSoundPrevModeByKey = {}
local bbSoundLastPlayByKey = {}
local bbSoundMinInterval = 0.15
-- Pre-allocated sound dispatch tables (avoid per-tick GC)
local _bb_activeSoundCfgByKey = {}
local _bb_activeSoundModeByKey = {}

local function GetSpellSoundsRevision_BB(settings)
    return tonumber(settings and settings.spellSoundsRevision) or 0
end

-- Local defaults for buffBars (used as fallback if ProfileManager not ready)
local buffBarsDefaults = {
    anchorPoint = "CENTER",
    relativePoint = "CENTER",
    anchorX = 0,
    anchorY = 0,
    enabled = true,
    font = "Friz Quadrata TT",
    fontSize = 11,
    barTextFontSize = 11,
    stackFontSize = 14,
    stackFontOffsetX = 0,
    stackFontOffsetY = 0,
    stackFontScale = 1.6,
    texture = "Blizzard Raid Bar",
    borderSize = 1.0,
    backdropBorderSize = 1.0,
    borderColor = {r = 0, g = 0, b = 0, a = 1},
    barHeight = 24,
    iconWidth = 24,
    iconHeight = 24,
    barWidth = 200,
    barSpacing = 2,
    showIcon = true,
    useClassColor = true,
    customColor = {r = 0.5, g = 0.5, b = 0.5, a = 1},
    backdropColor = {r = 0, g = 0, b = 0, a = 0.5},
    truncateText = false,
    maxTextWidth = 0,
    frameStrata = "LOW",
    barAlpha = 1.0,
    aspectRatio = "1:1",
    cornerRadius = 1,
    hideBarName = false,
    hideIcons = false,
    timerTextAlign = "RIGHT",
    timerTextFontSize = 11, -- separate font size for timer/duration text
    stackingMode = 1, -- 1 = Dynamic, 2 = ?, 3 = Static Random Up
    regularGrowDirection = "up", -- standard mode stack direction: "up" or "down"
    spellColors = {},
    -- Cluster mode settings
    clusterMode = false,
    clusterCount = 3,
    clusterUnlocked = false,
    clusterFlow = "horizontal",
    clusterFlows = {},
    clusterCenterBars = true,
    clusterAssignments = {},
    clusterPositions = {},
    clusterManualOrders = {},
    clusterBarWidths = {},
    clusterBarHeights = {},
    clusterIconPositions = {},  -- per-cluster icon position: "bottom"/"top" for vertical, "left"/"right" for horizontal
    clusterGrowDirections = {}, -- per-cluster horizontal stack direction: "up" (bottom->top) or "down" (top->bottom)
    clusterStratas = {},          -- per-cluster frame strata: "BACKGROUND"/"LOW"/"MEDIUM"/"HIGH"/"DIALOG"
    clusterNameFontSizes = {},    -- per-cluster name font size override
    clusterTimerFontSizes = {},   -- per-cluster timer font size override
    clusterStackFontSizes = {},   -- per-cluster stack/count font size override
    clusterNameOffsets = {},      -- per-cluster name {x, y} offset
    clusterTimerOffsets = {},     -- per-cluster timer {x, y} offset
    clusterStackOffsets = {},     -- per-cluster stack {x, y} offset
    clusterBarTextures = {},        -- per-cluster bar texture (LSM key); nil = use global
    clusterHideBarNames = {},       -- per-cluster hide bar name: nil = follow global, true = hide, false = show
    clusterHideIcons = {},          -- per-cluster hide icons: nil = follow global, true = hide, false = show
    clusterShowAlways = {},         -- per-cluster show always: true = anchor stays visible outside edit/unlock mode
    clusterLayoutPositions = {},
    -- Per-spell glow settings: spellGlows[spellKey] = { enabled=bool, mode="show"|"inactive", color={r,g,b,a} }
    spellGlows = {},
    -- Per-spell sounds: spellSounds[spellKey] = { enabled=bool, sound=LSM key, output="sound"|"tts"|"both", ttsText=string, mode="show"|"expire"|"both" }
    spellSounds = {},
    spellSoundsRevision = 0,
    -- Circular cooldown sweep overlay on bar icons
    showIconCooldownSweep = false,
}

local function NormalizeBarSpellSounds(settings)
    if not settings then return end
    if settings.spellSoundsRevision == nil then
        settings.spellSoundsRevision = 0
    end
    if type(settings.spellSounds) ~= "table" then
        settings.spellSounds = {}
        return
    end

    for k, v in pairs(settings.spellSounds) do
        if type(v) ~= "table" then
            settings.spellSounds[k] = { enabled = (v == true), sound = "", output = "sound", ttsText = "", mode = "expire" }
        else
            if v.mode == nil or v.mode == "" then
                v.mode = "expire"
            elseif v.mode == "ready" then
                v.mode = "expire"
            end
            if v.mode ~= "show" and v.mode ~= "expire" and v.mode ~= "both" then
                v.mode = "expire"
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
end

local function RebuildEnabledSoundLookup_BB(spellSounds)
    for k in pairs(bbEnabledSoundLookup) do bbEnabledSoundLookup[k] = nil end
    bbSoundCfgSource = spellSounds
    bbSoundCfgRevision = tonumber((_G.CkraigCooldownManager and _G.CkraigCooldownManager.db and _G.CkraigCooldownManager.db.profile and GetSpellSoundsRevision_BB(_G.CkraigCooldownManager.db.profile.buffBars)) or 0) or 0

    if type(spellSounds) ~= "table" then
        return false
    end

    local hasEnabled = false
    for skey, cfg in pairs(spellSounds) do
        if type(cfg) == "table" and cfg.enabled then
            bbEnabledSoundLookup[tostring(skey)] = cfg
            hasEnabled = true
        end
    end
    return hasEnabled
end

local function ResolveSoundPath_BB(soundKey)
    if not soundKey or soundKey == "" then return nil end
    if LSM and LSM.Fetch then
        local ok, path = pcall(LSM.Fetch, LSM, "sound", soundKey, true)
        if ok and path and path ~= "" then
            return path
        end
    end
    return soundKey
end

local function TrimString_BB(s)
    if type(s) ~= "string" then return "" end
    return s:match("^%s*(.-)%s*$") or ""
end

local function ResolveSpellName_BB(spellKey)
    local spellID = tonumber(spellKey)
    if spellID and C_Spell and C_Spell.GetSpellName then
        local name = C_Spell.GetSpellName(spellID)
        if name and name ~= "" then
            return name
        end
    end
    return tostring(spellKey or "Spell")
end

local function ResolveTtsText_BB(spellKey, cfg)
    local text = TrimString_BB(cfg and cfg.ttsText)
    if text ~= "" then
        return text
    end
    return ResolveSpellName_BB(spellKey)
end

local function SpeakText_BB(text)
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

local function PlaySpellSound_BB(spellKey, cfg)
    if not cfg then return end
    local keyStr = tostring(spellKey or "")
    if keyStr == "" then return end

    local now = GetTime and GetTime() or 0
    local last = bbSoundLastPlayByKey[keyStr]
    if last and (now - last) < bbSoundMinInterval then
        return
    end
    bbSoundLastPlayByKey[keyStr] = now

    local output = tostring(cfg.output or "sound")
    local playSound = (output == "sound" or output == "both")
    local playTts = (output == "tts" or output == "both")
    local didPlay = false

    if playSound then
        local soundPath = ResolveSoundPath_BB(cfg.sound)
        if soundPath then
            local ok = pcall(PlaySoundFile, soundPath, "Master")
            didPlay = didPlay or (ok and true or false)
        end
    end

    if playTts then
        local ttsText = ResolveTtsText_BB(keyStr, cfg)
        didPlay = SpeakText_BB(ttsText) or didPlay
    elseif playSound and not didPlay then
        -- Fallback for missing/invalid SharedMedia sounds.
        didPlay = SpeakText_BB(ResolveTtsText_BB(keyStr, cfg)) or didPlay
    end

    if not didPlay then
        bbSoundLastPlayByKey[keyStr] = nil
    end
end

local function ResetSoundState_BB(resetLastPlayed)
    for k in pairs(bbSoundActivePrevByKey) do bbSoundActivePrevByKey[k] = nil end
    for k in pairs(bbSoundPrevCfgByKey) do bbSoundPrevCfgByKey[k] = nil end
    for k in pairs(bbSoundPrevModeByKey) do bbSoundPrevModeByKey[k] = nil end
    if resetLastPlayed then
        for k in pairs(bbSoundLastPlayByKey) do bbSoundLastPlayByKey[k] = nil end
    end
end

local function EnsureSharedProfileDB(addon)
    if _G.CkraigProfileManager and _G.CkraigProfileManager.db then
        addon.db = _G.CkraigProfileManager.db
        return true
    end
    return addon.db ~= nil
end

-- OnInitialize: Use ProfileManager's shared database
local oldOnInitialize = CkraigCooldownManager.OnInitialize
CkraigCooldownManager.OnInitialize = function(self, ...)
    if oldOnInitialize then oldOnInitialize(self, ...) end

    -- Use ProfileManager's shared database instead of creating our own
    EnsureSharedProfileDB(self)
    
    -- Ensure buffBars exists in profile
    if self.db and self.db.profile then
        if not self.db.profile.buffBars then
            self.db.profile.buffBars = CopyTable(buffBarsDefaults)
        else
            -- Merge in any missing default values (for new settings added later)
            for key, value in pairs(buffBarsDefaults) do
                if self.db.profile.buffBars[key] == nil then
                    self.db.profile.buffBars[key] = value
                end
            end
        end
        NormalizeBarSpellSounds(self.db.profile.buffBars)
    end
end

-- Handle profile changes from ProfileManager
function CkraigCooldownManager:OnProfileChanged()
    EnsureSharedProfileDB(self)

    -- Ensure buffBars exists after profile change
    if self.db and self.db.profile then
        if not self.db.profile.buffBars then
            self.db.profile.buffBars = CopyTable(buffBarsDefaults)
        else
            -- Merge in any missing default values
            for key, value in pairs(buffBarsDefaults) do
                if self.db.profile.buffBars[key] == nil then
                    self.db.profile.buffBars[key] = value
                end
            end
        end
        NormalizeBarSpellSounds(self.db.profile.buffBars)
    end
    -- Refresh bars with new profile settings
    InvalidateBarStyle()
    -- Stop stale glows from the old profile so they don't bleed into the new one
    if self.StopAllBarGlows then self:StopAllBarGlows() end
    ResetSoundState_BB(true)
    if self.RepositionAllBars then
        self:RepositionAllBars()
    end
end

-- Helpers
local function roundPixel(value) return math.floor((value or 0) + 0.5) end

local function SetClusterPendingBarHidden(barFrame, hidden)
    if not barFrame then return end
    local state = GetBarState(barFrame)

    if hidden then
        state.clusterPendingHidden = true
        return
    end

    if not state.clusterPendingHidden then return end
    state.clusterPendingHidden = nil
    -- Restore alpha that was zeroed in OnAcquireItemFrame
    if barFrame.SetAlpha then barFrame:SetAlpha(1) end
end

-- Generation counter: incremented at the start of each update pass so
-- calls within the same synchronous tick reuse the cached result.
local _bb_poolGen = 0
local _bb_poolCachedGen = -1

local function InvalidateBarPool()
    _bb_poolGen = _bb_poolGen + 1
end

local function GetBuffBarFrames()
    if not BuffBarCooldownViewer then return _bb_poolActive end
    -- Return cached result if still within the same update generation
    if _bb_poolCachedGen == _bb_poolGen then return _bb_poolActive end
    _bb_poolCachedGen = _bb_poolGen

    wipe(_bb_poolFrames)
    wipe(_bb_poolActive)

    if type(BuffBarCooldownViewer.GetItemFrames) == "function" then
        local ok, items = pcall(BuffBarCooldownViewer.GetItemFrames, BuffBarCooldownViewer)
        if ok and items and type(items) == "table" then
            for _, f in ipairs(items) do
                if f and f:IsObjectType("Frame") then _bb_poolFrames[#_bb_poolFrames + 1] = f end
            end
        end
    end

    if #_bb_poolFrames == 0 and type(BuffBarCooldownViewer.GetChildren) == "function" then
        for i = 1, select("#", BuffBarCooldownViewer:GetChildren()) do
            local child = select(i, BuffBarCooldownViewer:GetChildren())
            if child and child:IsObjectType("Frame") then _bb_poolFrames[#_bb_poolFrames + 1] = child end
        end
    end

    for _, frame in ipairs(_bb_poolFrames) do
        if frame and frame:IsShown() and frame:IsVisible() then _bb_poolActive[#_bb_poolActive + 1] = frame end
    end
    return _bb_poolActive
end

-- [SECTION: SPELL IDENTITY]
local function NormalizeBarSpellKey(value)
    if value == nil then return nil end
    local valueType = type(value)
    if valueType == "number" then
        if value <= 0 then return nil end
        return tostring(math.floor(value + 0.5))
    end
    if valueType == "string" then
        local trimmed = value:match("^%s*(.-)%s*$")
        if trimmed == "" then return nil end
        return trimmed
    end
    return nil
end

local _bb_spellCandidates = {}  -- reusable table for GetSpellCandidatesFromCooldownInfo

local function GetSpellCandidatesFromCooldownInfo(cooldownInfo)
    wipe(_bb_spellCandidates)
    if not cooldownInfo then return _bb_spellCandidates end

    local function AddSpell(spellID)
        if type(spellID) == "number" and spellID > 0 then
            _bb_spellCandidates[#_bb_spellCandidates + 1] = spellID
        end
    end

    AddSpell(cooldownInfo.overrideTooltipSpellID)
    AddSpell(cooldownInfo.overrideSpellID)
    AddSpell(cooldownInfo.spellID)

    -- C_Spell.GetOverrideSpell: resolve talent/talent-morphed overrides
    if cooldownInfo.spellID and C_Spell and C_Spell.GetOverrideSpell then
        local overrideID = C_Spell.GetOverrideSpell(cooldownInfo.spellID)
        if overrideID and overrideID ~= cooldownInfo.spellID then
            AddSpell(overrideID)
        end
    end

    if type(cooldownInfo.linkedSpellIDs) == "table" then
        for _, linkedSpellID in ipairs(cooldownInfo.linkedSpellIDs) do
            AddSpell(linkedSpellID)
        end
    end

    return _bb_spellCandidates
end

local function IsSpellKnownForPlayer(spellID)
    if not spellID then return false end

    if IsSpellKnownOrOverridesKnown then
        if IsSpellKnownOrOverridesKnown(spellID) then return true end
    end

    if IsPlayerSpell then
        if IsPlayerSpell(spellID) then return true end
    end

    if C_SpellBook and C_SpellBook.IsSpellKnown then
        if C_SpellBook.IsSpellKnown(spellID) then return true end
    end

    return false
end

local function IsCooldownKeyKnownForPlayer(key)
    local numericKey = tonumber(key)
    if not numericKey then return false end

    if C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local cooldownInfo = C_CooldownViewer.GetCooldownViewerCooldownInfo(numericKey)
        if cooldownInfo then
            if cooldownInfo.isKnown then
                return true
            end

            local candidates = GetSpellCandidatesFromCooldownInfo(cooldownInfo)
            for _, spellID in ipairs(candidates) do
                if IsSpellKnownForPlayer(spellID) then
                    return true
                end
            end
        end
    end

    return IsSpellKnownForPlayer(numericKey)
end

local function ResolveBarSpellIdentity(barFrame, fallbackIndex)
    if not barFrame then
        return nil, nil, nil
    end

    local key = nil
    local label = nil
    local icon = nil

    -- Inline source iteration to avoid table allocation
    local barBar = barFrame.Bar
    local src1 = barFrame
    local src2 = barBar
    local src3 = barFrame.cooldownInfo
    local src4 = barBar and barBar.cooldownInfo

    for si = 1, 4 do
        local src = (si == 1 and src1) or (si == 2 and src2) or (si == 3 and src3) or src4
        if type(src) == "table" then
            if not key and src.GetCooldownID then
                key = src:GetCooldownID()
            end
            if not key and src.GetSpellID then
                key = src:GetSpellID()
            end
            if not key and src.GetCooldownInfo then
                local info = src:GetCooldownInfo()
                if info then
                    key = info.cooldownID or info.spellID or info.overrideSpellID or info.overrideTooltipSpellID
                end
            end
            if not key then
                key = src.cooldownID or src.spellID or src.overrideSpellID or src.overrideTooltipSpellID or src.auraSpellID
            end

            if not label then label = src.spellName or src.name end
            if not icon then icon = src.icon or src.texture end
            if key and label and icon then break end
        end
    end

    key = NormalizeBarSpellKey(key)

    -- Try C_Spell.GetOverrideSpell to resolve talent-morphed spells
    if key and C_Spell and C_Spell.GetOverrideSpell then
        local numKey = tonumber(key)
        if numKey then
            local overrideID = C_Spell.GetOverrideSpell(numKey)
            if overrideID and overrideID ~= numKey then
                -- Use the override as the canonical key if the player knows it
                if IsSpellKnownForPlayer(overrideID) then
                    key = NormalizeBarSpellKey(overrideID)
                end
            end
        end
    end
    if not key then
        return nil, nil, nil
    end

    if not IsCooldownKeyKnownForPlayer(key) then
        return nil, nil, nil
    end

    local numericKey = tonumber(key)

    if numericKey and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local cooldownInfo = C_CooldownViewer.GetCooldownViewerCooldownInfo(numericKey)
        if cooldownInfo then
            local candidates = GetSpellCandidatesFromCooldownInfo(cooldownInfo)
            for _, spellID in ipairs(candidates) do
                if not label and C_Spell and C_Spell.GetSpellName then
                    label = C_Spell.GetSpellName(spellID)
                end
                if not icon and C_Spell and C_Spell.GetSpellTexture then
                    icon = C_Spell.GetSpellTexture(spellID)
                end
                if label and icon then
                    break
                end
            end
        end
    end

    if not label and numericKey and C_Spell and C_Spell.GetSpellName then
        label = C_Spell.GetSpellName(numericKey)
    end
    if not icon and numericKey and C_Spell and C_Spell.GetSpellTexture then
        icon = C_Spell.GetSpellTexture(numericKey)
    end

    -- Cold cache guard: if spell name/icon is still missing, request server data load
    if (not label or not icon) and numericKey and C_Spell and C_Spell.RequestLoadSpellData then
        pcall(C_Spell.RequestLoadSpellData, numericKey)
    end

    if not label then
        label = "Spell " .. key
    end

    return key, label, icon
end

local function BuildBarSpellItemsForOptions(settings)
    settings = settings or (_G.CkraigCooldownManager and _G.CkraigCooldownManager.db and _G.CkraigCooldownManager.db.profile and _G.CkraigCooldownManager.db.profile.buffBars) or {}
    settings.spellColors = settings.spellColors or {}

    local items = {}
    local seen = {}

    -- Strict source: currently visible bar frames only.
    -- Using category sets/GetCooldownIDs can include stale or off-class keys.
    local bars = GetBuffBarFrames()
    for i, bar in ipairs(bars) do
        local key, label, icon = ResolveBarSpellIdentity(bar, i)
        if key and IsCooldownKeyKnownForPlayer(key) and not seen[key] then
            seen[key] = true
            table.insert(items, { key = key, label = label, icon = icon })
        end
    end

    table.sort(items, function(a, b)
        local aNum = tonumber(a.key)
        local bNum = tonumber(b.key)
        if aNum and bNum then return aNum < bNum end
        return tostring(a.key) < tostring(b.key)
    end)

    return items
end

-- Expose spell list to options panel
function CkraigCooldownManager:GetBarSpellItems()
    return BuildBarSpellItemsForOptions(self.db and self.db.profile and self.db.profile.buffBars)
end

-- [SECTION: CLUSTER ANCHORS]
-- =========================
-- Cluster mode helpers
-- =========================
local MAX_BAR_CLUSTERS = 10
local barClusterAnchors = {}
local MIN_CLUSTER_ANCHOR_WIDTH = 220
local MIN_CLUSTER_ANCHOR_HEIGHT = 140

local function GetDefaultBarClusterPosition(index)
    local spacingX = 220
    local col = (index - 1) % 3
    local row = math.floor((index - 1) / 3)
    return { point = "CENTER", x = -spacingX + col * spacingX, y = 120 - row * 200 }
end

local function EnsureBarClusterAnchor(settings, index)
    if barClusterAnchors[index] then
        return barClusterAnchors[index]
    end

    local anchor = CreateFrame("Frame", "CkraigBarClusterAnchor" .. index, UIParent, "BackdropTemplate")
    anchor:SetSize(220, 200)
    anchor:SetMovable(true)
    anchor:EnableMouse(true)
    anchor:RegisterForDrag("LeftButton")
    anchor:SetClampedToScreen(true)
    anchor:SetFrameStrata(settings.clusterStratas and settings.clusterStratas[index] or "MEDIUM")

    anchor:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    anchor:SetBackdropColor(0, 0, 0, 0)
    anchor:SetBackdropBorderColor(0, 0, 0, 0)

    local label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    label:SetPoint("CENTER", anchor, "TOP", 0, 0)
    label:SetText("Bar Cluster " .. index)
    label:SetTextColor(1, 1, 1, 1)
    label:SetFont(label:GetFont(), 16, "OUTLINE")
    label:Hide()
    anchor._clusterLabel = label
    anchor._clusterIndex = index

    -- Manual drag (for "Unlock Clusters" toggle, outside Edit Mode)
    anchor:SetScript("OnDragStart", function(self)
        if not settings.clusterUnlocked then return end
        if InCombatLockdown() then return end
        self:SetMovable(true)
        self:StartMoving()
    end)
    anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        settings.clusterPositions = settings.clusterPositions or {}
        settings.clusterPositions[index] = { point = point, relPoint = relPoint, x = x, y = y }
    end)

    -- Arrow key nudging for pixel-perfect positioning
    anchor:EnableKeyboard(false)
    anchor:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        if not settings.clusterUnlocked then
            self:SetPropagateKeyboardInput(true)
            return
        end
        local step = IsShiftKeyDown() and 10 or 1
        local point, rel, relPoint, x, y = self:GetPoint()
        if key == "UP" then
            y = y + step
        elseif key == "DOWN" then
            y = y - step
        elseif key == "LEFT" then
            x = x - step
        elseif key == "RIGHT" then
            x = x + step
        elseif key == "ESCAPE" then
            self:EnableKeyboard(false)
            self._arrowKeyActive = false
            self._clusterLabel:SetText("Bar Cluster " .. self._clusterIndex)
            self:SetPropagateKeyboardInput(true)
            return
        else
            self:SetPropagateKeyboardInput(true)
            return
        end
        self:SetPropagateKeyboardInput(false)
        self:ClearAllPoints()
        self:SetPoint(point, UIParent, relPoint, x, y)
        settings.clusterPositions = settings.clusterPositions or {}
        settings.clusterPositions[index] = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    anchor:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and settings.clusterUnlocked then
            local wasActive = self._arrowKeyActive
            for i = 1, MAX_BAR_CLUSTERS do
                local other = barClusterAnchors[i]
                if other then
                    other:EnableKeyboard(false)
                    other._arrowKeyActive = false
                    if other._clusterLabel then
                        other._clusterLabel:SetText("Bar Cluster " .. i)
                    end
                end
            end
            if not wasActive then
                self:EnableKeyboard(true)
                self._arrowKeyActive = true
                self._clusterLabel:SetText("Bar Cluster " .. index .. " [ARROWS]")
            end
        end
    end)

    barClusterAnchors[index] = anchor

    -- Restore position: prefer per-layout positions, fall back to legacy positions
    local saved
    local layoutName = LibEditMode and LibEditMode:GetActiveLayoutName()
    if layoutName then
        settings.clusterLayoutPositions = settings.clusterLayoutPositions or {}
        local layoutPos = settings.clusterLayoutPositions[layoutName]
        saved = layoutPos and layoutPos[index]
    end
    if not saved then
        saved = settings.clusterPositions and settings.clusterPositions[index]
    end
    local fallback = GetDefaultBarClusterPosition(index)
    local point = (saved and saved.point) or fallback.point
    local x = (saved and saved.x) or fallback.x
    local y = (saved and saved.y) or fallback.y
    anchor:ClearAllPoints()
    anchor:SetPoint(point, UIParent, point, x, y)
    anchor:Hide()

    -- Register with LibEditMode for Edit Mode integration
    if LibEditMode then
        LibEditMode:AddFrame(anchor, function(frame, lName, pt, fx, fy)
            if not lName then return end
            settings.clusterLayoutPositions = settings.clusterLayoutPositions or {}
            settings.clusterLayoutPositions[lName] = settings.clusterLayoutPositions[lName] or {}
            settings.clusterLayoutPositions[lName][index] = { point = pt, x = fx, y = fy }
        end, fallback, "Bar Cluster " .. index)

        -- Per-cluster settings in Edit Mode dialog
        LibEditMode:AddFrameSettings(anchor, {
            {
                kind = LibEditMode.SettingType.Slider,
                name = "Bar Width",
                default = 200,
                get = function()
                    return settings.clusterBarWidths[index] or settings.barWidth or 200
                end,
                set = function(_, newValue)
                    settings.clusterBarWidths[index] = newValue
                    if CkraigCooldownManager.RepositionAllBars then
                        CkraigCooldownManager:RepositionAllBars()
                    end
                end,
                minValue = 50,
                maxValue = 600,
                valueStep = 1,
            },
            {
                kind = LibEditMode.SettingType.Slider,
                name = "Bar Height",
                default = 24,
                get = function()
                    return settings.clusterBarHeights[index] or settings.barHeight or 24
                end,
                set = function(_, newValue)
                    settings.clusterBarHeights[index] = newValue
                    if CkraigCooldownManager.RepositionAllBars then
                        CkraigCooldownManager:RepositionAllBars()
                    end
                end,
                minValue = 8,
                maxValue = 80,
                valueStep = 1,
            },
            {
                kind = LibEditMode.SettingType.Dropdown,
                name = "Frame Strata",
                get = function()
                    return (settings.clusterStratas and settings.clusterStratas[index]) or "MEDIUM"
                end,
                set = function(_, newValue)
                    if not settings.clusterStratas then settings.clusterStratas = {} end
                    settings.clusterStratas[index] = newValue
                    anchor:SetFrameStrata(newValue)
                    if CkraigCooldownManager.RepositionAllBars then
                        CkraigCooldownManager:RepositionAllBars()
                    end
                end,
                values = {
                    { text = "Background", value = "BACKGROUND" },
                    { text = "Low",        value = "LOW" },
                    { text = "Medium",     value = "MEDIUM" },
                    { text = "High",       value = "HIGH" },
                    { text = "Dialog",     value = "DIALOG" },
                },
            },
            {
                kind = LibEditMode.SettingType.Dropdown,
                name = "Bar Texture",
                height = 300,
                get = function()
                    return settings.clusterBarTextures and settings.clusterBarTextures[index] or ""
                end,
                set = function(_, newValue)
                    settings.clusterBarTextures = settings.clusterBarTextures or {}
                    settings.clusterBarTextures[index] = (newValue ~= "") and newValue or nil
                    InvalidateBarStyle()
                    if CkraigCooldownManager.RepositionAllBars then
                        CkraigCooldownManager:RepositionAllBars()
                    end
                end,
                values = (function()
                    local vals = { { text = "(Global)", value = "" } }
                    for _, name in ipairs(LSM:List("statusbar")) do
                        vals[#vals + 1] = { text = name, value = name }
                    end
                    return vals
                end)(),
            },
            {
                kind = LibEditMode.SettingType.Slider,
                name = "Name Font Size",
                default = 0,
                get = function()
                    return settings.clusterNameFontSizes[index] or 0
                end,
                set = function(_, newValue)
                    settings.clusterNameFontSizes[index] = newValue > 0 and newValue or nil
                    InvalidateBarStyle()
                    if CkraigCooldownManager.RepositionAllBars then
                        CkraigCooldownManager:RepositionAllBars()
                    end
                end,
                minValue = 0,
                maxValue = 40,
                valueStep = 1,
                formatter = function(v) return v == 0 and "Global" or tostring(v) end,
            },
            {
                kind = LibEditMode.SettingType.Slider,
                name = "Name X Offset",
                default = 0,
                get = function()
                    local o = settings.clusterNameOffsets[index]
                    return o and o.x or 0
                end,
                set = function(_, newValue)
                    settings.clusterNameOffsets[index] = settings.clusterNameOffsets[index] or { x = 0, y = 0 }
                    settings.clusterNameOffsets[index].x = newValue
                    InvalidateBarStyle()
                    if CkraigCooldownManager.RepositionAllBars then
                        CkraigCooldownManager:RepositionAllBars()
                    end
                end,
                minValue = -50,
                maxValue = 50,
                valueStep = 1,
            },
            {
                kind = LibEditMode.SettingType.Slider,
                name = "Name Y Offset",
                default = 0,
                get = function()
                    local o = settings.clusterNameOffsets[index]
                    return o and o.y or 0
                end,
                set = function(_, newValue)
                    settings.clusterNameOffsets[index] = settings.clusterNameOffsets[index] or { x = 0, y = 0 }
                    settings.clusterNameOffsets[index].y = newValue
                    InvalidateBarStyle()
                    if CkraigCooldownManager.RepositionAllBars then
                        CkraigCooldownManager:RepositionAllBars()
                    end
                end,
                minValue = -50,
                maxValue = 50,
                valueStep = 1,
            },
            {
                kind = LibEditMode.SettingType.Slider,
                name = "Timer Font Size",
                default = 0,
                get = function()
                    return settings.clusterTimerFontSizes[index] or 0
                end,
                set = function(_, newValue)
                    settings.clusterTimerFontSizes[index] = newValue > 0 and newValue or nil
                    InvalidateBarStyle()
                    if CkraigCooldownManager.RepositionAllBars then
                        CkraigCooldownManager:RepositionAllBars()
                    end
                end,
                minValue = 0,
                maxValue = 40,
                valueStep = 1,
                formatter = function(v) return v == 0 and "Global" or tostring(v) end,
            },
            {
                kind = LibEditMode.SettingType.Slider,
                name = "Timer X Offset",
                default = 0,
                get = function()
                    local o = settings.clusterTimerOffsets[index]
                    return o and o.x or 0
                end,
                set = function(_, newValue)
                    settings.clusterTimerOffsets[index] = settings.clusterTimerOffsets[index] or { x = 0, y = 0 }
                    settings.clusterTimerOffsets[index].x = newValue
                    InvalidateBarStyle()
                    if CkraigCooldownManager.RepositionAllBars then
                        CkraigCooldownManager:RepositionAllBars()
                    end
                end,
                minValue = -50,
                maxValue = 50,
                valueStep = 1,
            },
            {
                kind = LibEditMode.SettingType.Slider,
                name = "Timer Y Offset",
                default = 0,
                get = function()
                    local o = settings.clusterTimerOffsets[index]
                    return o and o.y or 0
                end,
                set = function(_, newValue)
                    settings.clusterTimerOffsets[index] = settings.clusterTimerOffsets[index] or { x = 0, y = 0 }
                    settings.clusterTimerOffsets[index].y = newValue
                    InvalidateBarStyle()
                    if CkraigCooldownManager.RepositionAllBars then
                        CkraigCooldownManager:RepositionAllBars()
                    end
                end,
                minValue = -50,
                maxValue = 50,
                valueStep = 1,
            },
            {
                kind = LibEditMode.SettingType.Slider,
                name = "Stack Font Size",
                default = 0,
                get = function()
                    return settings.clusterStackFontSizes[index] or 0
                end,
                set = function(_, newValue)
                    settings.clusterStackFontSizes[index] = newValue > 0 and newValue or nil
                    InvalidateBarStyle()
                    if CkraigCooldownManager.RepositionAllBars then
                        CkraigCooldownManager:RepositionAllBars()
                    end
                end,
                minValue = 0,
                maxValue = 40,
                valueStep = 1,
                formatter = function(v) return v == 0 and "Global" or tostring(v) end,
            },
            {
                kind = LibEditMode.SettingType.Slider,
                name = "Stack X Offset",
                default = 0,
                get = function()
                    local o = settings.clusterStackOffsets[index]
                    return o and o.x or 0
                end,
                set = function(_, newValue)
                    settings.clusterStackOffsets[index] = settings.clusterStackOffsets[index] or { x = 0, y = 0 }
                    settings.clusterStackOffsets[index].x = newValue
                    InvalidateBarStyle()
                    if CkraigCooldownManager.RepositionAllBars then
                        CkraigCooldownManager:RepositionAllBars()
                    end
                end,
                minValue = -300,
                maxValue = 300,
                valueStep = 1,
            },
            {
                kind = LibEditMode.SettingType.Slider,
                name = "Stack Y Offset",
                default = 0,
                get = function()
                    local o = settings.clusterStackOffsets[index]
                    return o and o.y or 0
                end,
                set = function(_, newValue)
                    settings.clusterStackOffsets[index] = settings.clusterStackOffsets[index] or { x = 0, y = 0 }
                    settings.clusterStackOffsets[index].y = newValue
                    InvalidateBarStyle()
                    if CkraigCooldownManager.RepositionAllBars then
                        CkraigCooldownManager:RepositionAllBars()
                    end
                end,
                minValue = -300,
                maxValue = 300,
                valueStep = 1,
            },
            {
                kind = LibEditMode.SettingType.Checkbox,
                name = "Hide Bar Name",
                default = false,
                get = function()
                    local v = settings.clusterHideBarNames and settings.clusterHideBarNames[index]
                    if v == nil then return settings.hideBarName and true or false end
                    return v
                end,
                set = function(_, newValue)
                    settings.clusterHideBarNames = settings.clusterHideBarNames or {}
                    -- Store explicit override; nil would fall back to global
                    settings.clusterHideBarNames[index] = newValue and true or false
                    InvalidateBarStyle()
                    if CkraigCooldownManager.RepositionAllBars then
                        CkraigCooldownManager:RepositionAllBars()
                    end
                end,
            },
            {
                kind = LibEditMode.SettingType.Checkbox,
                name = "Hide Icons",
                default = false,
                get = function()
                    local v = settings.clusterHideIcons and settings.clusterHideIcons[index]
                    if v == nil then return settings.hideIcons and true or false end
                    return v
                end,
                set = function(_, newValue)
                    settings.clusterHideIcons = settings.clusterHideIcons or {}
                    settings.clusterHideIcons[index] = newValue and true or false
                    InvalidateBarStyle()
                    if CkraigCooldownManager.RepositionAllBars then
                        CkraigCooldownManager:RepositionAllBars()
                    end
                end,
            },
            {
                kind = LibEditMode.SettingType.Checkbox,
                name = "Show Always",
                default = false,
                get = function()
                    return settings.clusterShowAlways and settings.clusterShowAlways[index] or false
                end,
                set = function(_, newValue)
                    settings.clusterShowAlways = settings.clusterShowAlways or {}
                    settings.clusterShowAlways[index] = newValue and true or false
                    if CkraigCooldownManager.RepositionAllBars then
                        CkraigCooldownManager:RepositionAllBars()
                    end
                end,
            },
        })
    end

    return anchor
end

local ccm_inEditMode = false

local function ApplyBarClusterDragState(settings)
    local clusterCount = settings.clusterCount or 3
    local unlocked = settings.clusterUnlocked and settings.clusterMode
    for i = 1, MAX_BAR_CLUSTERS do
        local anchor = barClusterAnchors[i]
        if anchor then
            local inUse = settings.clusterMode and i <= clusterCount
            if unlocked and not ccm_inEditMode and inUse then
                -- Manual unlock mode: show gold backdrop for drag/arrow-key positioning
                anchor:SetBackdropColor(0.25, 0.18, 0.02, 0.5)
                anchor:SetBackdropBorderColor(1.0, 0.82, 0.0, 0.9)
                anchor:EnableMouse(true)
                anchor._clusterLabel:Show()
            elseif inUse then
                -- Normal or Edit Mode: transparent backdrop (LibEditMode handles Edit Mode overlay)
                anchor:SetBackdropColor(0, 0, 0, 0)
                anchor:SetBackdropBorderColor(0, 0, 0, 0)
                if not ccm_inEditMode then
                    anchor:EnableMouse(false)
                    anchor:EnableKeyboard(false)
                    anchor._clusterLabel:Hide()
                end
            end
            if not inUse then
                anchor:Hide()
            end
        end
    end
end

local function HideAllBarClusterAnchors()
    for i = 1, MAX_BAR_CLUSTERS do
        if barClusterAnchors[i] then
            barClusterAnchors[i]:Hide()
        end
    end
end

-- LibEditMode: restore cluster positions when Edit Mode layout changes
local function RestoreClusterPositionsForLayout(layoutName)
    local settings = CkraigCooldownManager.db and CkraigCooldownManager.db.profile and CkraigCooldownManager.db.profile.buffBars
    if not settings then return end
    settings.clusterLayoutPositions = settings.clusterLayoutPositions or {}
    local layoutPos = settings.clusterLayoutPositions[layoutName]
    for i = 1, MAX_BAR_CLUSTERS do
        local anchor = barClusterAnchors[i]
        if anchor then
            local saved = layoutPos and layoutPos[i]
            if not saved then
                saved = settings.clusterPositions and settings.clusterPositions[i]
            end
            if saved then
                anchor:ClearAllPoints()
                anchor:SetPoint(saved.point, UIParent, saved.point, saved.x, saved.y)
            end
        end
    end
end

local function RequestImmediateBarsRefresh()
    local addon = CkraigCooldownManager
    if not addon then return end
    if addon._bb_updateFrame then
        addon._bb_updateFrame._layoutDirty = true
    end
    if addon._bb_scheduleUpdate then
        addon._bb_scheduleUpdate(true)
        return
    end
    if addon.RepositionAllBars then
        C_Timer.After(0, function()
            addon:RepositionAllBars()
        end)
    end
end

-- Wire LibEditMode callbacks (called once from OnEnable)
local function SetupEditModeCallbacks()
    if not LibEditMode then return end

    -- Layout change: restore per-layout cluster positions
    LibEditMode:RegisterCallback("layout", function(layoutName)
        RestoreClusterPositionsForLayout(layoutName)
        RequestImmediateBarsRefresh()
    end)

    -- Enter Edit Mode: ensure cluster anchors exist so LibEditMode can show them
    LibEditMode:RegisterCallback("enter", function()
        ccm_inEditMode = true
        local settings = CkraigCooldownManager.db and CkraigCooldownManager.db.profile and CkraigCooldownManager.db.profile.buffBars
        if not settings then return end
        if not settings.clusterMode then
            RequestImmediateBarsRefresh()
            return
        end
        local clusterCount = settings.clusterCount or 3
        for i = 1, clusterCount do
            local anchor = barClusterAnchors[i]
            if not anchor then
                anchor = EnsureBarClusterAnchor(settings, i)
            end
            if anchor then
                -- Make backdrop invisible — LibEditMode provides the selection overlay
                anchor:SetBackdropColor(0, 0, 0, 0)
                anchor:SetBackdropBorderColor(0, 0, 0, 0)
                anchor._clusterLabel:Hide()
            end
        end
        -- Hide anchors beyond cluster count in Edit Mode
        for ci = 1, MAX_BAR_CLUSTERS do
            local anchor = barClusterAnchors[ci]
            if anchor then
                LibEditMode:SetFrameEditModeHidden("Bar Cluster " .. ci, ci > clusterCount)
            end
        end
        RequestImmediateBarsRefresh()
    end)

    -- Exit Edit Mode: restore normal visibility and movable state
    LibEditMode:RegisterCallback("exit", function()
        ccm_inEditMode = false
        local settings = CkraigCooldownManager.db and CkraigCooldownManager.db.profile and CkraigCooldownManager.db.profile.buffBars
        if not settings then return end
        -- Restore movable for manual unlock mode
        for i = 1, MAX_BAR_CLUSTERS do
            local anchor = barClusterAnchors[i]
            if anchor then anchor:SetMovable(true) end
        end
        ApplyBarClusterDragState(settings)
        RequestImmediateBarsRefresh()
    end)
end

local function GetBarClusterAssignment(settings, key)
    if not key or not settings.clusterAssignments then return 1 end
    local assigned = tonumber(settings.clusterAssignments[tostring(key)])
    if assigned and assigned >= 1 and assigned <= (settings.clusterCount or 3) then
        return assigned
    end
    return 1
end

local function GetBarClusterManualOrder(settings, clusterIndex)
    settings.clusterManualOrders = settings.clusterManualOrders or {}
    settings.clusterManualOrders[clusterIndex] = settings.clusterManualOrders[clusterIndex] or {}
    return settings.clusterManualOrders[clusterIndex]
end

local function RemoveBarKeyFromAllClusterOrders(settings, key)
    local normalizedKey = tostring(NormalizeBarSpellKey(key))
    if not normalizedKey then return end
    settings.clusterManualOrders = settings.clusterManualOrders or {}
    for _, orderList in pairs(settings.clusterManualOrders) do
        for i = #orderList, 1, -1 do
            if tostring(orderList[i]) == normalizedKey then
                table.remove(orderList, i)
            end
        end
    end
end

local function AddBarKeyToClusterOrderEnd(settings, clusterIndex, key)
    local normalizedKey = tostring(NormalizeBarSpellKey(key))
    if not normalizedKey then return end
    local orderList = GetBarClusterManualOrder(settings, clusterIndex)
    for _, existing in ipairs(orderList) do
        if tostring(existing) == normalizedKey then return end
    end
    table.insert(orderList, normalizedKey)
end

local function BuildOrderedBarsForCluster(settings, clusterIndex, barsByCluster)
    local ordered = {}
    local added = {}
    local orderList = GetBarClusterManualOrder(settings, clusterIndex)
    local barsInCluster = barsByCluster[clusterIndex] or {}

    local barByKey = {}
    for _, entry in ipairs(barsInCluster) do
        if entry.key then barByKey[tostring(entry.key)] = entry end
    end

    for _, key in ipairs(orderList) do
        local keyStr = tostring(key)
        if barByKey[keyStr] and not added[keyStr] then
            table.insert(ordered, barByKey[keyStr])
            added[keyStr] = true
        end
    end

    for _, entry in ipairs(barsInCluster) do
        local keyStr = tostring(entry.key)
        if not added[keyStr] then
            table.insert(ordered, entry)
            added[keyStr] = true
        end
    end

    return ordered
end

-- [SECTION: BAR VISIBILITY]
-- =========================
-- RefreshAllBarIconVisibility
-- =========================
local function RefreshAllBarIconVisibility()
    if not CkraigCooldownManager or not CkraigCooldownManager.db then return end
    local cfg = CkraigCooldownManager.db.profile and CkraigCooldownManager.db.profile.buffBars
    if not cfg then return end

    local showIcons = not cfg.hideIcons
    local bars = GetBuffBarFrames()
    for _, bar in ipairs(bars) do
        local barObj = bar.Bar or bar
        local parent = barObj and barObj.GetParent and barObj:GetParent() or nil
        local iconContainer = parent and (parent.Icon or parent.icon or parent.IconTexture)
        if iconContainer then
            if showIcons then
                if iconContainer.IsObjectType and iconContainer:IsObjectType("Texture") then
                    if iconContainer.Show then iconContainer:Show() end
                    if iconContainer.SetAlpha then iconContainer:SetAlpha(1) end
                else
                    if iconContainer.Show then iconContainer:Show() end
                    if iconContainer.SetAlpha then iconContainer:SetAlpha(1) end
                    local childTex = iconContainer.icon or iconContainer.Icon or iconContainer.IconTexture or iconContainer.Texture or FindIconTexture(iconContainer)
                    if childTex and childTex.Show then
                        childTex:Show()
                        if childTex.SetAlpha then childTex:SetAlpha(1) end
                    end
                end
                if iconContainer.IconBorder then iconContainer.IconBorder:SetAlpha(1) end
                if iconContainer.Border then iconContainer.Border:SetAlpha(1) end
            else
                if iconContainer.IsObjectType and iconContainer:IsObjectType("Texture") then
                    if iconContainer.Hide then iconContainer:Hide() end
                else
                    local childTex = iconContainer.icon or iconContainer.Icon or iconContainer.IconTexture or iconContainer.Texture or FindIconTexture(iconContainer)
                    if childTex and childTex.Hide then childTex:Hide() end
                end
                HideAllIconBorders(iconContainer)
            end
        end

        if parent and parent.Icon then
            if showIcons then
                if parent.Icon.Show then parent.Icon:Show() end
                if parent.Icon.SetAlpha then parent.Icon:SetAlpha(1) end
                if parent.Icon.IconBorder then parent.Icon.IconBorder:SetAlpha(1) end
                if parent.Icon.Border then parent.Icon.Border:SetAlpha(1) end
            else
                if parent.Icon.Hide then parent.Icon:Hide() end
                HideAllIconBorders(parent.Icon)
            end
        end

        if iconContainer and iconContainer.Applications then
            iconContainer.Applications:Show()
        end
        if parent and parent.Icon and parent.Icon.Applications then
            parent.Icon.Applications:Show()
        end

        if not showIcons and parent then HideAllIconBorders(parent) end

        if CkraigCooldownManager.StyleBar and barObj then
            CkraigCooldownManager:StyleBar(barObj)
        end
    end

    if CkraigCooldownManager.RepositionAllBars then
        CkraigCooldownManager:RepositionAllBars()
    end
end

-- (rest of the code continues as before)

-- Color helpers
function CkraigCooldownManager:GetClassColor()
    local _, class = UnitClass("player")
    if class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then
        local c = RAID_CLASS_COLORS[class]
        return c.r, c.g, c.b, 1
    end
    return 0.5, 0.5, 0.5, 1
end

function CkraigCooldownManager:GetBarColor()
    local cfg = self.db.profile.buffBars
    if cfg.useClassColor then return self:GetClassColor() end
    local c = cfg.customColor or {r=1,g=1,b=1,a=1}
    return c.r or 1, c.g or 1, c.b or 1, c.a or 1
end

-- =========================
-- Stack-count text helpers
-- =========================

local function FindStackFontString(barFrame)
    if not barFrame then return nil end

    local candidates = {
        barFrame.Count, barFrame.CountText, barFrame.StackCount, barFrame.Stack,
        barFrame.CountFontString, barFrame.StackFontString, barFrame.Number
    }

    for _, c in ipairs(candidates) do
        if c and type(c) == "table" and c.IsObjectType and c:IsObjectType("FontString") then
            return c
        end
    end

    if barFrame.GetRegions then
        for i = 1, select("#", barFrame:GetRegions()) do
            local region = select(i, barFrame:GetRegions())
            if region and region.IsObjectType and region:IsObjectType("FontString") then
                local ok, len = pcall(string.len, region:GetText() or "")
                if ok and len and len <= 6 then return region end
            end
        end
    end

    if barFrame.GetChildren then
        for i = 1, select("#", barFrame:GetChildren()) do
            local child = select(i, barFrame:GetChildren())
            if child and child.GetRegions then
                for j = 1, select("#", child:GetRegions()) do
                    local region = select(j, child:GetRegions())
                    if region and region.IsObjectType and region:IsObjectType("FontString") then
                        local ok, len = pcall(string.len, region:GetText() or "")
                        if ok and len and len <= 6 then return region end
                    end
                end
            end
        end
    end

    return nil
end

local function ApplyStackFontToBar(self, barFrame)
    if not barFrame then return end
    local cfg = self.db and self.db.profile and self.db.profile.buffBars
    if not cfg then return end

    local stackFS = FindStackFontString(barFrame)
    if not stackFS then return end


    local fontPath = LSM:Fetch("font", cfg.font) or STANDARD_TEXT_FONT
    local barHeight = cfg.barHeight or 24
    local stackFontSize = math.min(cfg.stackFontSize or 14, barHeight)

    -- Only apply stackFontSize if the FontString is attached to the icon (not the duration/cooldown number)
    local parent = stackFS:GetParent() or barFrame
    local isIconFont = false
    if parent and (parent:GetName() or ""):find("Icon") then
        isIconFont = true
    end
    if isIconFont then
        stackFS:SetFont(fontPath, stackFontSize, "OUTLINE")
    else
        -- fallback: use bar text font size for non-icon fontstrings
        local barTextFontSize = math.min(cfg.barTextFontSize or cfg.fontSize or 11, barHeight)
        stackFS:SetFont(fontPath, barTextFontSize, "OUTLINE")
    end
    stackFS:SetTextColor(1, 1, 1, 1)
end

local function UpdateAllStackFonts(self)
    if not BuffBarCooldownViewer or not self.db or not self.db.profile or not self.db.profile.buffBars.enabled then return end
    local bars = GetBuffBarFrames()
    for _, bar in ipairs(bars) do
        local bf = bar.Bar or bar
        ApplyStackFontToBar(self, bf)
    end
end



-- [SECTION: STYLE]
-- =========================
-- Styling and layout
-- =========================

function CkraigCooldownManager:StyleBar(barFrame)
    if not barFrame then return end
    local bs = GetBarState(barFrame)
    local styleLayoutSig = string.format("%s:%s:%s:%s:%s",
        bs.displayMode or "horizontal",
        bs.verticalBar and 1 or 0,
        bs.iconPosition or "",
        bs.clusterBarHeight or 0,
        bs.clusterIndex or 0)
    if bs.styleVer == _bb_styleVersion and bs.styleLayoutSig == styleLayoutSig then return end
    bs.styleVer = _bb_styleVersion
    bs.styleLayoutSig = styleLayoutSig

    local settings = self.db.profile.buffBars
    local barHeight = settings.barHeight or 24
    local borderSize = settings.borderSize or 0
    local backdropBorderSize = settings.backdropBorderSize or 0
    local borderColor = settings.borderColor or {r=0,g=0,b=0,a=1}
    local backdropColor = settings.backdropColor or {r=0,g=0,b=0,a=0.5}
    local fontPath = LSM:Fetch("font", settings.font) or STANDARD_TEXT_FONT
    local fontSize = settings.barTextFontSize or settings.fontSize or 11
    local textureKey = settings.texture
    if bs.clusterIndex and settings.clusterBarTextures and settings.clusterBarTextures[bs.clusterIndex] then
        textureKey = settings.clusterBarTextures[bs.clusterIndex]
    end
    local texturePath = LSM:Fetch("statusbar", textureKey) or "Interface\\RaidFrame\\Raid-Bar-Hp-Fill"

    local parent = barFrame:GetParent()
    local bs = GetBarState(barFrame)
    local ps = parent and GetBarState(parent) or nil
    local isVerticalBar = bs.verticalBar

    -- Smart StatusBar anchor: tracks layout mode to avoid ClearAllPoints spam
    if not isVerticalBar then
        -- Horizontal: anchor StatusBar after the icon so it doesn't cover it
        local ic = parent and (parent.Icon or parent.icon or parent.IconTexture)
        local layoutKey = "H:" .. (settings.hideIcons and "noicon" or "icon")
        if bs.barLayoutKey ~= layoutKey and barFrame.ClearAllPoints then
            barFrame:ClearAllPoints()
            if ic and not settings.hideIcons then
                barFrame:SetPoint("LEFT", ic, "RIGHT", 2, 0)
            else
                barFrame:SetPoint("LEFT", parent, "LEFT", 0, 0)
            end
            bs.barLayoutKey = layoutKey
        end
        if barFrame.SetHeight then barFrame:SetHeight(barHeight) end
        if barFrame.SetWidth and settings.barWidth then barFrame:SetWidth(settings.barWidth) end
        if parent and parent.SetWidth and settings.barWidth then parent:SetWidth(settings.barWidth) end
    else
        -- Vertical: StatusBar fills the full parent frame
        if bs.barLayoutKey ~= "V" and barFrame.ClearAllPoints then
            barFrame:ClearAllPoints()
            barFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
            barFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
            bs.barLayoutKey = "V"
        end
    end
    -- Do NOT set parent (BuffBarCooldownViewer) height/width here; keep it fixed
    -- This prevents the Edit Mode box from stretching to fit all bars
    -- Only the bars themselves should be sized

    if barFrame.SetStatusBarTexture then
        pcall(barFrame.SetStatusBarTexture, barFrame, texturePath)
        local r, g, b, a
        if settings.useClassColor then
            r, g, b, a = self:GetClassColor()
        else
            settings.spellColors = settings.spellColors or {}
            local spellKey = bs.spellKey or (ps and ps.spellKey)
            local spellColor = spellKey and settings.spellColors[tostring(spellKey)] or nil
            local color = spellColor or { r = 1, g = 1, b = 1, a = 1 }
            r = tonumber(color.r) or 1
            g = tonumber(color.g) or 1
            b = tonumber(color.b) or 1
            a = tonumber(color.a) or 1
        end
        if barFrame.SetStatusBarColor then pcall(barFrame.SetStatusBarColor, barFrame, r, g, b, a) end
    end
    local statusbarTexture = barFrame.GetStatusBarTexture and barFrame:GetStatusBarTexture() or nil
    if statusbarTexture and statusbarTexture.SetAlpha then
        statusbarTexture:SetAlpha(1)
    end

    if not bs.backdrop then
        bs.backdrop = CreateFrame("Frame", nil, barFrame, "BackdropTemplate")
    end
    local bg = bs.backdrop
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", barFrame, -backdropBorderSize, backdropBorderSize)
    bg:SetPoint("BOTTOMRIGHT", barFrame, backdropBorderSize, -backdropBorderSize)
    bg:SetFrameLevel(math.max(0, (barFrame:GetFrameLevel() or 0) - 1))
    bg:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8x8", edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=backdropBorderSize})
    bg:SetBackdropColor(backdropColor.r, backdropColor.g, backdropColor.b, backdropColor.a)
    bg:SetBackdropBorderColor(borderColor.r, borderColor.g, borderColor.b, borderColor.a)
    bg:Show()

    if parent then
        if borderSize > 0 then
            if not (ps and ps.outerBorder) then
                ps.outerBorder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
            end
            local outer = ps.outerBorder
            outer:ClearAllPoints()
            outer:SetPoint("TOPLEFT", parent, -borderSize, borderSize)
            outer:SetPoint("BOTTOMRIGHT", parent, borderSize, -borderSize)
            outer:SetFrameLevel(math.max(0, (parent:GetFrameLevel() or 0) - 1))
            outer:SetBackdrop({edgeFile="Interface\\Buttons\\WHITE8x8", edgeSize=borderSize})
            outer:SetBackdropColor(0,0,0,0)
            -- Make the border fully transparent
            outer:SetBackdropBorderColor(borderColor.r, borderColor.g, borderColor.b, 0)
            outer:Show()
        elseif ps and ps.outerBorder then
            ps.outerBorder:Hide()
        end
    end

    -- Icon handling (LazarUI-style dynamic cropping)
    local iconContainer = parent and (parent.Icon or parent.icon or parent.IconTexture)
    if iconContainer then
        local iconW, iconH
        if bs.clusterBarHeight then
            iconW = bs.clusterBarHeight
            iconH = bs.clusterBarHeight
        elseif isVerticalBar then
            -- For vertical bars, make icon square matching the bar's narrow width
            local parentW = bs.verticalBarWidth or parent:GetWidth() or barHeight
            iconW = parentW
            iconH = parentW
        else
            iconW = math.min(settings.iconWidth or settings.barHeight or 24, barHeight)
            iconH = math.min(settings.iconHeight or settings.barHeight or 24, barHeight)
        end
        -- Per-cluster hideIcons: nil = follow global, true = force hide, false = force show
        local effectiveHideIcons
        if bs.clusterIndex and settings.clusterHideIcons and settings.clusterHideIcons[bs.clusterIndex] ~= nil then
            effectiveHideIcons = settings.clusterHideIcons[bs.clusterIndex]
        else
            effectiveHideIcons = settings.hideIcons
        end
        local showIcon = not effectiveHideIcons

        -- Reposition the icon based on per-bar icon position (smart anchor to avoid spam)
        local iconPos = bs.iconPosition or (isVerticalBar and "bottom" or "left")
        local iconAnchorKey = (isVerticalBar and "V:" or "H:") .. iconPos
        if bs.iconAnchorKey ~= iconAnchorKey and iconContainer.ClearAllPoints then
            iconContainer:ClearAllPoints()
            if isVerticalBar then
                if iconPos == "top" then
                    iconContainer:SetPoint("BOTTOM", parent, "TOP", 0, 1)
                elseif iconPos == "left" then
                    iconContainer:SetPoint("RIGHT", parent, "LEFT", -1, 0)
                else
                    iconContainer:SetPoint("TOP", parent, "BOTTOM", 0, -1)
                end
            else
                iconContainer:SetPoint("LEFT", parent, "LEFT", 0, 0)
            end
            bs.iconAnchorKey = iconAnchorKey
        end

        -- Set the size of the icon container
        if iconContainer.SetSize then iconContainer:SetSize(iconW, iconH) end

        -- ElvUI-style icon crop
        local function applyIconCrop(tex)
            if not tex or not tex.IsObjectType or not tex:IsObjectType("Texture") then return end
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", iconContainer, "TOPLEFT", 0, 0)
            tex:SetPoint("BOTTOMRIGHT", iconContainer, "BOTTOMRIGHT", 0, 0)
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            if tex.SetSize then pcall(tex.SetSize, tex, iconW, iconH) end
        end

        if iconContainer:IsObjectType("Texture") then
            if showIcon then
                iconContainer:Show()
                applyIconCrop(iconContainer)
                -- Strip masks from the icon texture itself
                if iconContainer.GetMaskTexture then
                    local mi = 1
                    local mask = iconContainer:GetMaskTexture(mi)
                    while mask do
                        iconContainer:RemoveMaskTexture(mask)
                        mi = mi + 1
                        mask = iconContainer:GetMaskTexture(mi)
                    end
                end
            else
                iconContainer:Hide()
            end
        else
            local childTex = iconContainer.icon or iconContainer.Icon or iconContainer.IconTexture or iconContainer.Texture
            if not childTex or not (childTex.IsObjectType and childTex:IsObjectType("Texture")) then
                childTex = FindIconTexture(iconContainer)
            end
            if childTex and childTex.IsObjectType and childTex:IsObjectType("Texture") then
                if showIcon then
                    childTex:Show()
                    childTex:SetAlpha(1)
                    applyIconCrop(childTex)
                    -- Strip masks (Blizzard uses MaskTexture for shaped icons)
                    if childTex.GetMaskTexture then
                        local mi = 1
                        local mask = childTex:GetMaskTexture(mi)
                        while mask do
                            childTex:RemoveMaskTexture(mask)
                            mi = mi + 1
                            mask = childTex:GetMaskTexture(mi)
                        end
                    end
                else
                    childTex:Hide()
                end
            end
            -- ElvUI strip: hide overlays/borders on the icon container
            if showIcon and iconContainer.GetRegions then
                local kept = {}
                if childTex then kept[childTex] = true end
                if iconContainer.pixelBorders then
                    for _, pb in pairs(iconContainer.pixelBorders) do kept[pb] = true end
                end
                for _, region in ipairs({ iconContainer:GetRegions() }) do
                    if region and region.IsObjectType then
                        if region:IsObjectType("MaskTexture") then
                            region:Hide()
                        elseif region:IsObjectType("Texture") and not kept[region] then
                            region:SetAlpha(0)
                            region:Hide()
                        end
                    end
                end
            end
            -- Permanently neutralize DebuffBorder (lives on parent, not iconContainer).
            -- Blizzard's RefreshIconBorder() calls UpdateFromAuraData which re-shows it.
            -- Use hooksecurefunc (not method replacement) to avoid tainting Blizzard's
            -- secure execution path.
            if parent and parent.DebuffBorder and not parent.DebuffBorder._ccmNeutralized then
                parent.DebuffBorder._ccmNeutralized = true
                parent.DebuffBorder:Hide()
                if parent.DebuffBorder.Texture then
                    parent.DebuffBorder.Texture:SetTexture(nil)
                    parent.DebuffBorder.Texture:SetAlpha(0)
                end
                hooksecurefunc(parent.DebuffBorder, "UpdateFromAuraData", function(dbSelf)
                    dbSelf:Hide()
                end)
            end
        end

        -- Add 1-pixel black border using four overlay textures
        if not iconContainer.pixelBorders then
            iconContainer.pixelBorders = {}
            -- Top
            local top = iconContainer:CreateTexture(nil, "OVERLAY")
            top:SetColorTexture(0, 0, 0, 1)
            top:SetPoint("TOPLEFT", iconContainer, "TOPLEFT", 0, 0)
            top:SetPoint("TOPRIGHT", iconContainer, "TOPRIGHT", 0, 0)
            top:SetHeight(1)
            iconContainer.pixelBorders.top = top
            -- Bottom
            local bottom = iconContainer:CreateTexture(nil, "OVERLAY")
            bottom:SetColorTexture(0, 0, 0, 1)
            bottom:SetPoint("BOTTOMLEFT", iconContainer, "BOTTOMLEFT", 0, 0)
            bottom:SetPoint("BOTTOMRIGHT", iconContainer, "BOTTOMRIGHT", 0, 0)
            bottom:SetHeight(1)
            iconContainer.pixelBorders.bottom = bottom
            -- Left
            local leftB = iconContainer:CreateTexture(nil, "OVERLAY")
            leftB:SetColorTexture(0, 0, 0, 1)
            leftB:SetPoint("TOPLEFT", iconContainer, "TOPLEFT", 0, 0)
            leftB:SetPoint("BOTTOMLEFT", iconContainer, "BOTTOMLEFT", 0, 0)
            leftB:SetWidth(1)
            iconContainer.pixelBorders.left = leftB
            -- Right
            local rightB = iconContainer:CreateTexture(nil, "OVERLAY")
            rightB:SetColorTexture(0, 0, 0, 1)
            rightB:SetPoint("TOPRIGHT", iconContainer, "TOPRIGHT", 0, 0)
            rightB:SetPoint("BOTTOMRIGHT", iconContainer, "BOTTOMRIGHT", 0, 0)
            rightB:SetWidth(1)
            iconContainer.pixelBorders.right = rightB
        end
        for _, border in pairs(iconContainer.pixelBorders) do border:Show() end

        -- Add shadow texture if not present
        if not iconContainer.shadow then
            local shadow = iconContainer:CreateTexture(nil, "BACKGROUND")
            shadow:SetTexture("Interface\\BUTTONS\\UI-Quickslot-Depress")
            shadow:SetAllPoints(iconContainer)
            shadow:SetVertexColor(0, 0, 0, 0.6)
            iconContainer.shadow = shadow
        end
        if iconContainer.shadow then
            iconContainer.shadow:Hide()
        end

        -- Circular cooldown sweep on icon (Blizzard CooldownFrameTemplate, animated by C++ engine)
        if settings.showIconCooldownSweep and showIcon and parent then
            if not parent._ccmIconCooldown then
                local cd = CreateFrame("Cooldown", nil, parent, "CooldownFrameTemplate")
                cd:SetDrawEdge(true)
                cd:SetDrawSwipe(true)
                cd:SetHideCountdownNumbers(true)
                cd:SetSwipeColor(0, 0, 0, 0.6)
                parent._ccmIconCooldown = cd
            end
            local cd = parent._ccmIconCooldown
            cd:ClearAllPoints()
            cd:SetAllPoints(iconContainer)
            cd:SetFrameLevel((parent:GetFrameLevel() or 0) + 2)
            cd:Show()
            -- Set cooldown from parent's cooldownInfo
            local cooldownInfo = parent.cooldownInfo
            if cooldownInfo and cooldownInfo.startTime and cooldownInfo.duration and cooldownInfo.duration > 0 then
                cd:SetCooldown(cooldownInfo.startTime, cooldownInfo.duration)
            end
        elseif parent and parent._ccmIconCooldown then
            parent._ccmIconCooldown:Hide()
        end

        if iconContainer.Applications then iconContainer.Applications:Show() end
        if parent and parent.Icon and parent.Icon.Applications then parent.Icon.Applications:Show() end
        -- If there are multiple icons, ensure they are centered and do not exceed bar height
        if parent and parent.Icons and type(parent.Icons) == "table" then
            local totalWidth = 0
            for _, ic in ipairs(parent.Icons) do
                if ic.SetSize then ic:SetSize(iconW, iconH) end
                totalWidth = totalWidth + iconW
            end
            -- Center icons horizontally if needed
            if parent.SetWidth then
                local barWidth = CkraigCooldownManager and CkraigCooldownManager.db and CkraigCooldownManager.db.profile and CkraigCooldownManager.db.profile.buffBars and CkraigCooldownManager.db.profile.buffBars.barWidth or settings.barWidth or 200
                parent:SetWidth(barWidth)
            end
        end
        -- Only hide icon borders if icons are hidden
        if not showIcon then
            HideAllIconBorders(iconContainer)
            if parent and parent.Icon then HideAllIconBorders(parent.Icon) end
            if parent then HideAllIconBorders(parent) end
        end
    end

    if barFrame.GetRegions then
        for i = 1, select("#", barFrame:GetRegions()) do
            local region = select(i, barFrame:GetRegions())
            if region and region:IsObjectType("Texture") then
                local keep = false
                if barFrame.GetStatusBarTexture and region == barFrame:GetStatusBarTexture() then keep = true end
                if not keep then pcall(region.SetTexture, region, nil); pcall(region.Hide, region) end
            end
        end
    end

    -- Apply font to Name/Text (the buff name)
    local ci = bs.clusterIndex  -- per-cluster override index (nil if not in cluster mode)
    -- Per-cluster hideBarName: nil = follow global, true = force hide, false = force show
    local effectiveHideBarName
    if ci and settings.clusterHideBarNames and settings.clusterHideBarNames[ci] ~= nil then
        effectiveHideBarName = settings.clusterHideBarNames[ci]
    else
        effectiveHideBarName = settings.hideBarName
    end
    local nameFS = barFrame.Name or barFrame.Text
    if nameFS and nameFS.SetFont then
        if effectiveHideBarName or isVerticalBar then
            nameFS:Hide()
        else
            nameFS:Show()
            local nameFontSize = (ci and settings.clusterNameFontSizes and settings.clusterNameFontSizes[ci]) or fontSize
            pcall(nameFS.SetFont, nameFS, fontPath, nameFontSize, "OUTLINE")
            pcall(nameFS.SetTextColor, nameFS,1,1,1,1)
            -- Per-cluster name offset
            local nameOff = ci and settings.clusterNameOffsets and settings.clusterNameOffsets[ci]
            if nameOff and (nameOff.x ~= 0 or nameOff.y ~= 0) then
                nameFS:ClearAllPoints()
                nameFS:SetPoint("LEFT", barFrame, "LEFT", 5 + (nameOff.x or 0), nameOff.y or 0)
                nameFS:SetPoint("RIGHT", barFrame, "RIGHT", -25 + (nameOff.x or 0), nameOff.y or 0)
            end
        end
    end
    
    -- Apply font to timer/duration text
    -- The timer text uses timerTextFontSize setting
    local timerFontSize = settings.timerTextFontSize or settings.barTextFontSize or settings.fontSize or 11
    local timerAlign = settings.timerTextAlign or "RIGHT"
    
    -- Try direct properties on barFrame first
    local timeFS = barFrame.TimeLeft or barFrame.Duration or barFrame.Time or barFrame.Timer
    
    -- Also check the parent frame for timer FontString
    if not timeFS and parent then
        timeFS = parent.TimeLeft or parent.Duration or parent.Time or parent.Timer
    end
    
    -- Count FontStrings for debug
    local fontStringCount = 0
    
    -- If not found, scan barFrame regions for FontStrings that aren't the name
    if not timeFS and barFrame.GetRegions then
        for i = 1, select("#", barFrame:GetRegions()) do
            local region = select(i, barFrame:GetRegions())
            if region and region:IsObjectType("FontString") then
                fontStringCount = fontStringCount + 1
                if region ~= nameFS then
                    timeFS = region
                end
            end
        end
    end
    
    -- Also check parent frame regions for timer text
    if not timeFS and parent and parent.GetRegions then
        for i = 1, select("#", parent:GetRegions()) do
            local region = select(i, parent:GetRegions())
            if region and region:IsObjectType("FontString") then
                fontStringCount = fontStringCount + 1
                -- Skip nameFS and look for something that looks like time (numbers, colons, etc)
                if region ~= nameFS then
                    local text = region.GetText and region:GetText() or ""
                    -- Timer text usually contains numbers/colons like "1:30" or "45"
                    if text:match("%d") or text == "" then
                        timeFS = region
                    end
                end
            end
        end
    end
    
    -- Apply timer font settings
    if timeFS and timeFS.SetFont then
        local effectiveTimerSize = (ci and settings.clusterTimerFontSizes and settings.clusterTimerFontSizes[ci]) or timerFontSize
        pcall(timeFS.SetFont, timeFS, fontPath, effectiveTimerSize, "OUTLINE")
        local timerOff = ci and settings.clusterTimerOffsets and settings.clusterTimerOffsets[ci]
        local txOff = timerOff and timerOff.x or 0
        local tyOff = timerOff and timerOff.y or 0
        timeFS:ClearAllPoints()
        if isVerticalBar then
            -- For vertical bars, place timer text at bottom center
            timeFS:SetPoint("BOTTOM", barFrame, "BOTTOM", txOff, 2 + tyOff)
        elseif timerAlign == "LEFT" then
            timeFS:SetPoint("LEFT", barFrame, "LEFT", 4 + txOff, tyOff)
        elseif timerAlign == "CENTER" then
            timeFS:SetPoint("CENTER", barFrame, "CENTER", txOff, tyOff)
        else
            timeFS:SetPoint("RIGHT", barFrame, "RIGHT", -4 + txOff, tyOff)
        end
    end

    if self.ApplyBarFrameSettings then self:ApplyBarFrameSettings(barFrame) end

    -- Only modify the stack/count FontString (no other changes)
    ApplyStackFontToBar(self, barFrame)

    -- Always set stack/application font and position if Applications FontString exists
    if parent and parent.Icon and parent.Icon.Applications and parent.Icon.Applications.SetFont then
        local fontPath = LSM:Fetch("font", settings.font) or STANDARD_TEXT_FONT
        local baseSize = math.min(14, barHeight)
        local clusterStackSize = ci and settings.clusterStackFontSizes and settings.clusterStackFontSizes[ci]
        local mult = clusterStackSize and (clusterStackSize / 14) or (settings.stackFontSize and (settings.stackFontSize / 14) or 1.0)
        parent.Icon.Applications:SetFont(fontPath, baseSize * mult, "OUTLINE")
        parent.Icon.Applications:ClearAllPoints()
        local stackOff = ci and settings.clusterStackOffsets and settings.clusterStackOffsets[ci]
        local sxOff = (stackOff and stackOff.x or 0) + (settings.stackFontOffsetX or 0)
        local syOff = (stackOff and stackOff.y or 0) + (settings.stackFontOffsetY or 0)
        parent.Icon.Applications:SetPoint("CENTER", parent.Icon, "CENTER", sxOff, syOff)
        parent.Icon.Applications:SetWidth(0)
        parent.Icon.Applications:Show()
    end
    if iconContainer and iconContainer.Applications and iconContainer.Applications.SetFont then
        local fontPath = LSM:Fetch("font", settings.font) or STANDARD_TEXT_FONT
        local baseSize = math.min(14, barHeight)
        local clusterStackSize = ci and settings.clusterStackFontSizes and settings.clusterStackFontSizes[ci]
        local mult = clusterStackSize and (clusterStackSize / 14) or (settings.stackFontSize and (settings.stackFontSize / 14) or 1.0)
        iconContainer.Applications:SetFont(fontPath, baseSize * mult, "OUTLINE")
        iconContainer.Applications:ClearAllPoints()
        local stackOff = ci and settings.clusterStackOffsets and settings.clusterStackOffsets[ci]
        local sxOff = (stackOff and stackOff.x or 0) + (settings.stackFontOffsetX or 0)
        local syOff = (stackOff and stackOff.y or 0) + (settings.stackFontOffsetY or 0)
        iconContainer.Applications:SetPoint("CENTER", iconContainer, "CENTER", sxOff, syOff)
        iconContainer.Applications:SetWidth(0)
        iconContainer.Applications:Show()
    end
end

-- [SECTION: LAYOUT]
function CkraigCooldownManager:RepositionAllBars()
    if not BuffBarCooldownViewer or not self.db.profile.buffBars.enabled then return end
    local settings = self.db.profile.buffBars
    -- Only bump style version when tracked settings actually changed.
    if BarSettingsChanged(settings) then
        _bb_styleVersion = _bb_styleVersion + 1
    end
    local updateFrame = self._bb_updateFrame
    if updateFrame then updateFrame._repositioning = true end
    local bars = GetBuffBarFrames()
    local barHeight, spacing = settings.barHeight or 24, settings.barSpacing or 2

    -- Ensure cluster settings are initialized
    settings.clusterAssignments = settings.clusterAssignments or {}
    settings.clusterPositions = settings.clusterPositions or {}
    settings.clusterManualOrders = settings.clusterManualOrders or {}
    settings.clusterFlows = settings.clusterFlows or {}
    settings.clusterBarWidths = settings.clusterBarWidths or {}
    settings.clusterBarHeights = settings.clusterBarHeights or {}
    settings.clusterIconPositions = settings.clusterIconPositions or {}
    settings.clusterGrowDirections = settings.clusterGrowDirections or {}
    settings.clusterVerticalGrowDirections = settings.clusterVerticalGrowDirections or {}

    if settings.clusterMode then
        local clusterCount = settings.clusterCount or 3
        local barWidth = settings.barWidth or 200

        for i = 1, clusterCount do
            local anchor = EnsureBarClusterAnchor(settings, i)
            anchor:Show()
        end

        ApplyBarClusterDragState(settings)

        local barsByCluster = {}
        for i = 1, clusterCount do barsByCluster[i] = {} end

        for i, bar in ipairs(bars) do
            local barObj = bar.Bar or bar
            SetBarStateValue(barObj, "barIndex", i)
            local spellKey, spellLabel = ResolveBarSpellIdentity(bar, i)
            SetBarStateValue(barObj, "spellKey", spellKey)
            SetBarStateValue(barObj, "spellLabel", spellLabel)
            SetBarStateValue(bar, "spellKey", spellKey)
            SetBarStateValue(bar, "spellLabel", spellLabel)

            -- Skip blank/example bars that have no valid spell identity
            if not spellKey then
                if bar.SetAlpha then bar:SetAlpha(0) end
            else
                local clusterIdx = GetBarClusterAssignment(settings, spellKey)
                table.insert(barsByCluster[clusterIdx], { bar = bar, barObj = barObj, key = spellKey, label = spellLabel, index = i })
                AddBarKeyToClusterOrderEnd(settings, clusterIdx, spellKey)
            end
        end

        -- Show Always: include hidden (off-cooldown) pool bars for showAlways clusters
        local _sa_activeBars = {}
        for _, b in ipairs(bars) do _sa_activeBars[b] = true end
        for _, bar in ipairs(_bb_poolFrames) do
            if not _sa_activeBars[bar] then
                local barObj = bar.Bar or bar
                local spellKey, spellLabel = ResolveBarSpellIdentity(bar, 0)
                if spellKey then
                    local clusterIdx = GetBarClusterAssignment(settings, spellKey)
                    if settings.clusterShowAlways and settings.clusterShowAlways[clusterIdx] then
                        SetBarStateValue(barObj, "spellKey", spellKey)
                        SetBarStateValue(barObj, "spellLabel", spellLabel)
                        SetBarStateValue(bar, "spellKey", spellKey)
                        SetBarStateValue(bar, "spellLabel", spellLabel)
                        table.insert(barsByCluster[clusterIdx], { bar = bar, barObj = barObj, key = spellKey, label = spellLabel, index = 0 })
                        AddBarKeyToClusterOrderEnd(settings, clusterIdx, spellKey)
                        -- Force-show hidden off-cooldown bars
                        if bar.Show then bar:Show() end
                        if bar.SetAlpha then bar:SetAlpha(1) end
                    end
                end
            end
        end

        for ci = 1, clusterCount do
            local anchor = barClusterAnchors[ci]
            if anchor then
                local orderedBars = BuildOrderedBarsForCluster(settings, ci, barsByCluster)
                local clusterBarWidth = settings.clusterBarWidths[ci] or barWidth
                local clusterBarHeight = settings.clusterBarHeights[ci] or barHeight
                local flow = string.lower(tostring(settings.clusterFlows[ci] or settings.clusterFlow or "horizontal"))

                if flow == "vertical" then
                    -- Vertical bars: narrow/tall bars placed side by side
                    local vertBarWidth = clusterBarHeight   -- narrow dimension
                    local vertBarHeight = clusterBarWidth   -- tall dimension
                    local totalWidth = 0
                    local vGrowDir = string.lower(tostring(settings.clusterVerticalGrowDirections and settings.clusterVerticalGrowDirections[ci] or "right"))
                    local growRight = (vGrowDir ~= "left")

                    for bi, entry in ipairs(orderedBars) do
                        local bar = entry.bar
                        local barObj = entry.barObj
                        local x = roundPixel((bi - 1) * (vertBarWidth + spacing))

                        if bar and bar.ClearAllPoints then bar:ClearAllPoints() end
                        if bar.SetPoint then
                            if growRight then
                                bar:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", x + 4, 16)
                            else
                                bar:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -(x + 4), 16)
                            end
                        end
                        local clusterStrata = (settings.clusterStratas and settings.clusterStratas[ci]) or "MEDIUM"
                        if bar.SetFrameStrata then bar:SetFrameStrata(clusterStrata) end

                        SetBarStateValue(barObj, "clusterBarHeight", clusterBarHeight)
                        SetBarStateValue(barObj, "verticalBar", true)
                        SetBarStateValue(barObj, "verticalBarWidth", vertBarWidth)
                        SetBarStateValue(barObj, "iconPosition", settings.clusterIconPositions[ci] or "bottom")
                        SetBarStateValue(barObj, "displayMode", "vertical")
                        SetBarStateValue(barObj, "clusterIndex", ci)
                        -- Set parent size BEFORE StyleBar so icon reads correct parent width
                        if bar.SetSize then bar:SetSize(vertBarWidth, vertBarHeight) end

                        self:StyleBar(barObj)
                        if barObj.SetOrientation then barObj:SetOrientation("VERTICAL") end
                        SetClusterPendingBarHidden(bar, false)
                        bar:Show()
                        totalWidth = x + vertBarWidth
                    end

                    local anchorWidth = math.max(totalWidth + 8, MIN_CLUSTER_ANCHOR_WIDTH)
                    local anchorHeight = math.max(vertBarHeight + 32, MIN_CLUSTER_ANCHOR_HEIGHT)
                    anchor:SetSize(anchorWidth, anchorHeight)
                else
                    -- Horizontal bars (default): normal bars stacked vertically
                    local totalHeight = 0
                    local growDir = string.lower(tostring(settings.clusterGrowDirections[ci] or "down"))
                    local growDown = (growDir == "down")

                    for bi, entry in ipairs(orderedBars) do
                        local bar = entry.bar
                        local barObj = entry.barObj
                        if bar and bar.ClearAllPoints then bar:ClearAllPoints() end
                        local y = roundPixel((bi - 1) * (clusterBarHeight + spacing))

                        if bar.SetPoint then
                            if growDown then
                                bar:SetPoint("TOPLEFT", anchor, "TOPLEFT", 4, -(y + 16))
                            else
                                bar:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT", 4, y + 16)
                            end
                        end
                        local clusterStrata = (settings.clusterStratas and settings.clusterStratas[ci]) or "MEDIUM"
                        if bar.SetFrameStrata then bar:SetFrameStrata(clusterStrata) end

                        SetBarStateValue(barObj, "clusterBarHeight", clusterBarHeight)
                        SetBarStateValue(barObj, "verticalBar", false)
                        SetBarStateValue(barObj, "verticalBarWidth", nil)
                        SetBarStateValue(barObj, "iconPosition", nil)
                        SetBarStateValue(barObj, "displayMode", "horizontal")
                        SetBarStateValue(barObj, "clusterIndex", ci)

                        self:StyleBar(barObj)
                        if bar.SetWidth then bar:SetWidth(clusterBarWidth - 8) end
                        if bar.SetHeight then bar:SetHeight(clusterBarHeight) end
                        if barObj.SetWidth then barObj:SetWidth(clusterBarWidth - 8) end
                        if barObj.SetHeight then barObj:SetHeight(clusterBarHeight) end
                        if barObj.SetOrientation then barObj:SetOrientation("HORIZONTAL") end
                        SetClusterPendingBarHidden(bar, false)
                        bar:Show()
                        totalHeight = y + clusterBarHeight
                    end

                    -- Keep anchor moderately sized in Edit Mode so drag targets remain usable
                    -- and grow-up/grow-down orientation stays visually clear.
                    local barCount = #orderedBars
                    local contentHeight = barCount > 0 and (barCount * (clusterBarHeight + spacing) - spacing + 32) or 40
                    local anchorWidth = math.max(clusterBarWidth, MIN_CLUSTER_ANCHOR_WIDTH)
                    local anchorHeight = math.max(contentHeight, MIN_CLUSTER_ANCHOR_HEIGHT)
                    anchor:SetSize(anchorWidth, anchorHeight)
                end
                anchor:Show()
            end
        end

        for i = clusterCount + 1, MAX_BAR_CLUSTERS do
            if barClusterAnchors[i] then barClusterAnchors[i]:Hide() end
        end
    elseif settings.gridMode then
        HideAllBarClusterAnchors()
        local gridCols = settings.gridCols or 2
        local gridRows = settings.gridRows or 12
        local colWidth = settings.barWidth or 200
        local rowHeight = barHeight + spacing
        for i, bar in ipairs(bars) do
            if bar and bar.ClearAllPoints then bar:ClearAllPoints() end
            if i <= gridCols * gridRows then
                local col = ((i - 1) % gridCols)
                local row = math.floor((i - 1) / gridCols)
                local x = col * (colWidth + spacing)
                local y = roundPixel(row * rowHeight)
                if bar.SetPoint then bar:SetPoint("BOTTOMLEFT", BuffBarCooldownViewer, "BOTTOMLEFT", x, y) end
                local barObj = bar.Bar or bar
                SetBarStateValue(barObj, "barIndex", i)
                local spellKey, spellLabel = ResolveBarSpellIdentity(bar, i)
                SetBarStateValue(barObj, "spellKey", spellKey)
                SetBarStateValue(barObj, "spellLabel", spellLabel)
                SetBarStateValue(bar, "spellKey", spellKey)
                SetBarStateValue(bar, "spellLabel", spellLabel)

                -- Reset cluster-only sizing/layout flags in non-cluster modes.
                SetBarStateValue(barObj, "clusterBarHeight", nil)
                SetBarStateValue(barObj, "verticalBar", false)
                SetBarStateValue(barObj, "verticalBarWidth", nil)
                SetBarStateValue(barObj, "iconPosition", nil)
                SetBarStateValue(barObj, "displayMode", "horizontal")

                if bar.SetSize then bar:SetSize(colWidth, barHeight) end
                if barObj.SetWidth then barObj:SetWidth(colWidth) end
                if barObj.SetHeight then barObj:SetHeight(barHeight) end
                if barObj.SetOrientation then barObj:SetOrientation("HORIZONTAL") end

                self:StyleBar(barObj)
                SetClusterPendingBarHidden(bar, false)
                bar:Show()
            else
                bar:Hide()
            end
        end
    else
        -- Standard mode: vertical stack in BuffBarCooldownViewer.
        HideAllBarClusterAnchors()

        local parentHeight = BuffBarCooldownViewer:GetHeight() or 300
        local maxBars = math.floor((parentHeight + spacing) / (barHeight + spacing))
        local growDown = string.lower(tostring(settings.regularGrowDirection or "up")) == "down"

        local slotIndex = 0
        for i, bar in ipairs(bars) do
            local barObj = bar.Bar or bar
            SetBarStateValue(barObj, "barIndex", i)
            local spellKey, spellLabel = ResolveBarSpellIdentity(bar, i)
            SetBarStateValue(barObj, "spellKey", spellKey)
            SetBarStateValue(barObj, "spellLabel", spellLabel)
            SetBarStateValue(bar, "spellKey", spellKey)
            SetBarStateValue(bar, "spellLabel", spellLabel)

            -- Skip blank/example bars that have no valid spell identity
            if not spellKey then
                if bar.SetAlpha then bar:SetAlpha(0) end
            elseif slotIndex < maxBars then
                local y = roundPixel(slotIndex * (barHeight + spacing))
                local bw = settings.barWidth or 200
                -- Always re-anchor: Blizzard's RefreshLayout / container Layout()
                -- moves bars back to default positions before our hook fires.
                -- Skipping the SetPoint here causes bars to pile up or overlap.
                if bar and bar.ClearAllPoints then bar:ClearAllPoints() end
                if bar.SetPoint then
                    if growDown then
                        bar:SetPoint("TOPLEFT", BuffBarCooldownViewer, "TOPLEFT", 0, -y)
                    else
                        bar:SetPoint("BOTTOMLEFT", BuffBarCooldownViewer, "BOTTOMLEFT", 0, y)
                    end
                end

                -- Reset cluster-only sizing/layout flags in standard mode.
                SetBarStateValue(barObj, "clusterBarHeight", nil)
                SetBarStateValue(barObj, "verticalBar", false)
                SetBarStateValue(barObj, "verticalBarWidth", nil)
                SetBarStateValue(barObj, "iconPosition", nil)
                SetBarStateValue(barObj, "displayMode", "horizontal")

                if barObj.SetOrientation then barObj:SetOrientation("HORIZONTAL") end
                if bar.SetWidth then bar:SetWidth(bw) end
                if bar.SetHeight then bar:SetHeight(barHeight) end
                if barObj.SetWidth then barObj:SetWidth(bw) end
                if barObj.SetHeight then barObj:SetHeight(barHeight) end

                self:StyleBar(barObj)
                SetClusterPendingBarHidden(bar, false)
                bar:Show()
                slotIndex = slotIndex + 1
            else
                local _bs = GetBarState(bar)
                _bs._layoutSlot = nil
                _bs._layoutMode = nil
                bar:Hide()
            end
        end
    end

    if updateFrame then updateFrame._repositioning = false end
end

-- Fade-only check: returns true if any bar is fading or approaching fade
-- Uses Blizzard's itemFramePool:EnumerateActive() — zero-allocation iterator, no table/pcall
function CkraigCooldownManager:CheckFadingBars()
    if not BuffBarCooldownViewer then return false end
    local pool = BuffBarCooldownViewer.itemFramePool
    if not pool then return false end
    if not BAR_FADE_ENABLED then
        for frame in pool:EnumerateActive() do
            local fs = GetBarState(frame)
            if fs.fading then
                frame:SetAlpha(1)
                fs.fading = false
            end
        end
        return false
    end
    local anyActive = false
    local now = GetTime()
    for frame in pool:EnumerateActive() do
        local fs = GetBarState(frame)
        if frame:IsShown() and frame.cooldownInfo and frame.cooldownInfo.duration then
            local duration, startTime = frame.cooldownInfo.duration, frame.cooldownInfo.startTime
            if duration and startTime and duration > 0 then
                local remaining = (startTime + duration) - now
                if remaining <= FADE_THRESHOLD and remaining > 0 then
                    frame:SetAlpha(remaining / FADE_THRESHOLD)
                    fs.fading = true
                    anyActive = true
                elseif remaining <= 0 then
                    frame:SetAlpha(0)
                    frame:Hide()
                    fs.fading = false
                else
                    if fs.fading then
                        frame:SetAlpha(1)
                        fs.fading = false
                    end
                    if remaining <= 1.0 then anyActive = true end
                end
            end
        end
    end
    return anyActive
end

-- Helper: determine if a bar's spell is on cooldown (mirrors DynamicIcons approach)
-- CPU-optimised: no pcall (GetSpellCooldown returns nil for unknown spells)
local function IsBarSpellOnCooldown(frame, spellKey)
    -- Try C_Spell.GetSpellCooldown using the resolved spellKey (cleanest, no taint)
    local numericKey = tonumber(spellKey)
    if numericKey and C_Spell and C_Spell.GetSpellCooldown then
        local cdInfo = C_Spell.GetSpellCooldown(numericKey)
        if cdInfo and not cdInfo.isOnGCD then
            local dur = tonumber(tostring(cdInfo.duration or 0)) or 0
            return dur > 1.5
        end
    end
    -- Fallback: frame.cooldownStartTime / cooldownDuration (Blizzard sets these directly)
    local start = frame.cooldownStartTime
    local dur = frame.cooldownDuration
    if start and dur then
        start = tonumber(tostring(start)) or 0
        dur = tonumber(tostring(dur)) or 0
        if dur > 1.5 then
            return (start + dur) > GetTime()
        end
    end
    -- Last resort: bar is shown = cooldown is active
    return frame:IsShown()
end

-- Glow logic: only runs on event-driven dirty flag
-- Uses itemFramePool:EnumerateActive() and direct API calls (no pcall/table overhead)
-- Stop all active bar glows (used on profile/spec change to clear stale glows)
function CkraigCooldownManager:StopAllBarGlows()
    if not LCG or not BuffBarCooldownViewer then return end
    local pool = BuffBarCooldownViewer.itemFramePool
    if not pool then return end
    for frame in pool:EnumerateActive() do
        local glowTarget = frame.Bar or frame
        local glowState = GetBarState(glowTarget)
        if glowState and glowState.glowing then
            pcall(LCG.PixelGlow_Stop, glowTarget, "bbGlow")
            glowState.glowing = false
        end
    end
end

function CkraigCooldownManager:UpdateBarGlows()
    if not BuffBarCooldownViewer then return end
    if not LCG then return end
    local pool = BuffBarCooldownViewer.itemFramePool
    if not pool then return end
    local settings = self.db and self.db.profile and self.db.profile.buffBars
    local spellGlows = settings and settings.spellGlows or {}
    if not next(spellGlows) then
        -- No glows configured: stop any leftover glows from a previous profile
        self:StopAllBarGlows()
        return
    end

    for frame in pool:EnumerateActive() do
        local frameState = GetBarState(frame)
        local barState = frame.Bar and GetBarState(frame.Bar) or nil
        local spellKey = frameState.spellKey or (barState and barState.spellKey)
        local glowTarget = frame.Bar or frame
        local glowState = GetBarState(glowTarget)
        if spellKey then
            local glowCfg = spellGlows[tostring(spellKey)]
            if glowCfg and glowCfg.enabled then
                local active = IsBarSpellOnCooldown(frame, spellKey)
                local shouldGlow
                if glowCfg.mode == "inactive" then
                    shouldGlow = frame:IsShown() and not active
                else
                    shouldGlow = frame:IsShown() and active
                end

                if shouldGlow then
                    if not glowState.glowing then
                        local c = glowCfg.color or {r=1,g=1,b=0,a=1}
                        bbGlowColor[1] = c.r; bbGlowColor[2] = c.g; bbGlowColor[3] = c.b; bbGlowColor[4] = c.a
                        LCG.PixelGlow_Start(glowTarget, bbGlowColor, 8, 0.25, nil, nil, 0, 0, false, "bbGlow")
                        glowState.glowing = true
                    end
                else
                    if glowState.glowing then
                        LCG.PixelGlow_Stop(glowTarget, "bbGlow")
                        glowState.glowing = false
                    end
                end
            else
                if glowState.glowing then
                    LCG.PixelGlow_Stop(glowTarget, "bbGlow")
                    glowState.glowing = false
                end
            end
        end
    end
end

-- [SECTION: COOLDOWN PASS]
-- Merged single-pass: fade + glow + visible count + pendingHidden in one pool iteration
-- Returns: anyFading, visibleCount, pendingHidden
function CkraigCooldownManager:UpdateBarsCooldownPass()
    if not BuffBarCooldownViewer then return false, 0, false end
    local pool = BuffBarCooldownViewer.itemFramePool
    if not pool then return false, 0, false end

    local settings = self.db and self.db.profile and self.db.profile.buffBars
    local spellGlows = settings and settings.spellGlows or {}
    local hasGlows = LCG and next(spellGlows) ~= nil
    local spellSounds = settings and settings.spellSounds or {}
    local soundRevision = GetSpellSoundsRevision_BB(settings)
    if spellSounds ~= bbSoundCfgSource or soundRevision ~= bbSoundCfgRevision then
        RebuildEnabledSoundLookup_BB(spellSounds)
        bbSoundCfgRevision = soundRevision
    end
    local hasSounds = InCombatLockdown() and next(bbEnabledSoundLookup) ~= nil
    if hasSounds then
        for k in pairs(_bb_activeSoundCfgByKey) do _bb_activeSoundCfgByKey[k] = nil end
        for k in pairs(_bb_activeSoundModeByKey) do _bb_activeSoundModeByKey[k] = nil end
    end
    local activeSoundCfgByKey = hasSounds and _bb_activeSoundCfgByKey or nil
    local activeSoundModeByKey = hasSounds and _bb_activeSoundModeByKey or nil
    local anyFading = false
    local visibleCount = 0
    local pendingHidden = false
    local now = GetTime()

    for frame in pool:EnumerateActive() do
        local fs = GetBarState(frame)
        local barObj = frame.Bar or frame
        local shown = frame:IsShown()

        -- Fade logic (temporarily paused)
        if BAR_FADE_ENABLED and shown and frame.cooldownInfo and frame.cooldownInfo.duration then
            local duration, startTime = frame.cooldownInfo.duration, frame.cooldownInfo.startTime
            if duration and startTime and duration > 0 then
                local remaining = (startTime + duration) - now
                if remaining <= FADE_THRESHOLD and remaining > 0 then
                    frame:SetAlpha(remaining / FADE_THRESHOLD)
                    fs.fading = true
                    anyFading = true
                elseif remaining <= 0 then
                    frame:SetAlpha(0)
                    frame:Hide()
                    fs.fading = false
                else
                    if fs.fading then
                        frame:SetAlpha(1)
                        fs.fading = false
                    end
                    if remaining <= 1.0 then anyFading = true end
                end
            end
        elseif fs.fading then
            frame:SetAlpha(1)
            fs.fading = false
        end

        -- Glow logic (inlined, state-guarded)
        if hasGlows then
            local barState = frame.Bar and GetBarState(frame.Bar) or nil
            local spellKey = fs.spellKey or (barState and barState.spellKey)
            local glowTarget = frame.Bar or frame
            local gs = GetBarState(glowTarget)
            if spellKey then
                if fs.spellKeyCache ~= spellKey then
                    fs.spellKeyCache = spellKey
                    fs.spellKeyStr = tostring(spellKey)
                end
                local glowCfg = spellGlows[fs.spellKeyStr]
                if glowCfg and glowCfg.enabled then
                    local active = IsBarSpellOnCooldown(frame, spellKey)
                    local modeRaw = glowCfg.mode
                    if glowCfg.__ccmModeRaw ~= modeRaw then
                        glowCfg.__ccmModeRaw = modeRaw
                        glowCfg.__ccmModeInactive = (modeRaw == "inactive")
                    end
                    local shouldGlow = glowCfg.__ccmModeInactive and (shown and not active) or (shown and active)
                    if shouldGlow then
                        if not gs.glowing or gs.glowKey ~= spellKey then
                            local c = glowCfg.color
                            bbGlowColor[1] = c and c.r or 1
                            bbGlowColor[2] = c and c.g or 1
                            bbGlowColor[3] = c and c.b or 0
                            bbGlowColor[4] = c and c.a or 1
                            LCG.PixelGlow_Start(glowTarget, bbGlowColor, 8, 0.25, nil, nil, 0, 0, false, "bbGlow")
                            gs.glowing = true
                            gs.glowKey = spellKey
                        end
                    else
                        if gs.glowing then
                            LCG.PixelGlow_Stop(glowTarget, "bbGlow")
                            gs.glowing = false
                            gs.glowKey = nil
                        end
                    end
                else
                    if gs.glowing then
                        LCG.PixelGlow_Stop(glowTarget, "bbGlow")
                        gs.glowing = false
                        gs.glowKey = nil
                    end
                end
            end
        end

        if hasSounds and shown then
            local keyStr = fs.spellKeyStr
            if not keyStr then
                local barState = frame.Bar and GetBarState(frame.Bar) or nil
                local spellKey = fs.spellKey or (barState and barState.spellKey)
                if spellKey then
                    keyStr = tostring(spellKey)
                    fs.spellKeyStr = keyStr
                end
            end
            if keyStr then
                local cfg = bbEnabledSoundLookup[keyStr]
                if cfg then
                    local mode = tostring(cfg.mode or "expire")
                    if mode == "ready" then mode = "expire" end
                    activeSoundCfgByKey[keyStr] = cfg
                    activeSoundModeByKey[keyStr] = mode
                end
            end
        end

        -- Update circular cooldown sweep when cooldownInfo changes
        if frame._ccmIconCooldown and frame._ccmIconCooldown:IsShown() then
            local ci = frame.cooldownInfo
            if ci and ci.startTime and ci.duration and ci.duration > 0 then
                if fs._cdStart ~= ci.startTime or fs._cdDur ~= ci.duration then
                    frame._ccmIconCooldown:SetCooldown(ci.startTime, ci.duration)
                    fs._cdStart = ci.startTime
                    fs._cdDur = ci.duration
                end
            end
        end

        -- Track visible count + pending hidden (eliminates 2 extra pool iterations)
        if shown and frame:IsVisible() then
            visibleCount = visibleCount + 1
        end
        if fs.clusterPendingHidden then
            pendingHidden = true
        end
    end

    if hasSounds then
        for keyStr, cfg in pairs(activeSoundCfgByKey) do
            local mode = activeSoundModeByKey[keyStr] or "expire"
            local playOnShow = (mode == "show" or mode == "both")
            if playOnShow and not bbSoundActivePrevByKey[keyStr] then
                PlaySpellSound_BB(keyStr, cfg)
            end
        end

        for keyStr in pairs(bbSoundActivePrevByKey) do
            if not activeSoundCfgByKey[keyStr] then
                local mode = bbSoundPrevModeByKey[keyStr] or "expire"
                local playOnExpire = (mode == "expire" or mode == "both")
                if playOnExpire then
                    PlaySpellSound_BB(keyStr, bbSoundPrevCfgByKey[keyStr] or bbEnabledSoundLookup[keyStr])
                end
            end
        end

        ResetSoundState_BB(false)
        for keyStr, cfg in pairs(activeSoundCfgByKey) do
            bbSoundActivePrevByKey[keyStr] = true
            bbSoundPrevCfgByKey[keyStr] = cfg
            bbSoundPrevModeByKey[keyStr] = activeSoundModeByKey[keyStr] or "expire"
        end
    else
        ResetSoundState_BB(false)
    end

    return anyFading, visibleCount, pendingHidden
end


-- [SECTION: ON ENABLE]
function CkraigCooldownManager:OnEnable()
    -- OnEnable fires on PLAYER_LOGIN, so run login logic directly here
    -- Always lock cluster boxes on login/reload
    if self.db and self.db.profile and self.db.profile.buffBars then
        self.db.profile.buffBars.clusterUnlocked = false
        ApplyBarClusterDragState(self.db.profile.buffBars)
    end
    if BuffBarCooldownViewer then
        self:RepositionAllBars()
    end
    -- Wire up LibEditMode callbacks
    SetupEditModeCallbacks()

    local ScheduleBBUpdate = self._bb_scheduleUpdate

    if not self._bb_updateFrame then
        self._bb_updateFrame = CreateFrame("Frame")
        self._bb_updateFrame._dirty = true
        self._bb_updateFrame._timerPending = false
        self._bb_updateFrame._nextAllowed = 0
        self._bb_updateFrame._nextVisualOnlyAllowed = 0
        self._bb_updateFrame._visualOnlyPending = false

        -- Separate fade frame: only shown when bars are actually fading
        self._bb_fadeFrame = CreateFrame("Frame")
        self._bb_fadeFrame:Hide()
        self._bb_fadeFrame:SetScript("OnUpdate", function(fadeF, elapsed)
            fadeF._elapsed = (fadeF._elapsed or 0) + elapsed
            if fadeF._elapsed < 0.5 then return end
            fadeF._elapsed = 0
            local anyFading = self:CheckFadingBars()
            if not anyFading then
                fadeF:Hide() -- nothing fading → sleep (zero CPU)
            end
        end)

        -- Event-driven: flag dirty on cooldown/aura/combat changes
        self._bb_updateFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        self._bb_updateFrame:RegisterUnitEvent("UNIT_AURA", "player")
        self._bb_updateFrame:RegisterEvent("PLAYER_REGEN_DISABLED")  -- entering combat
        self._bb_updateFrame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- leaving combat
        self._bb_updateFrame:RegisterEvent("COOLDOWN_VIEWER_DATA_LOADED")  -- Blizzard finished populating bar data
        self._bb_updateFrame:RegisterEvent("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED")  -- spell overrides changed

        local lastBarCount = -1

        local function RunBBUpdatePass(frame, visualOnly)
            if not (self.db and self.db.profile and self.db.profile.buffBars and self.db.profile.buffBars.enabled) then return end
            if not BuffBarCooldownViewer then return end

            -- Bump pool generation so GetBuffBarFrames rebuilds on first call this tick
            InvalidateBarPool()

            -- Single merged pass: fade + glow + visible count + pending hidden
            local anyFading, visibleCount, pendingHidden = self:UpdateBarsCooldownPass()
            if anyFading and self._bb_fadeFrame then
                self._bb_fadeFrame:Show()
            end

            if visualOnly then
                return
            end

            if visibleCount == 0 and not pendingHidden then return end

            if visibleCount ~= lastBarCount or frame._layoutDirty or pendingHidden then
                lastBarCount = visibleCount
                frame._layoutDirty = false
                self:RepositionAllBars()
            end
        end

        -- Pre-baked callback to avoid closure allocation per C_Timer.After
        local function _bb_timerCallback()
            local frame = self._bb_updateFrame
            frame._timerPending = false
            local visualOnly = frame._visualOnlyPending and true or false
            frame._visualOnlyPending = false
            if visualOnly then
                frame._nextVisualOnlyAllowed = GetTime() + 0.10
            else
                frame._nextAllowed = GetTime() + 0.02
            end
            RunBBUpdatePass(frame, visualOnly)
        end

        ScheduleBBUpdate = function(immediate, visualOnly)
            if self._bb_updateFrame._timerPending then
                -- Escalate queued visual-only pass to full pass when needed.
                if not visualOnly then
                    self._bb_updateFrame._visualOnlyPending = false
                end
                return
            end

            local now = GetTime()
            local delay = 0
            if visualOnly then
                if not immediate and now < (self._bb_updateFrame._nextVisualOnlyAllowed or 0) then
                    delay = self._bb_updateFrame._nextVisualOnlyAllowed - now
                end
            elseif not immediate and now < (self._bb_updateFrame._nextAllowed or 0) then
                delay = self._bb_updateFrame._nextAllowed - now
            end

            self._bb_updateFrame._visualOnlyPending = visualOnly and true or false
            self._bb_updateFrame._timerPending = true
            C_Timer.After(delay, _bb_timerCallback)
        end
        self._bb_scheduleUpdate = ScheduleBBUpdate

        self._bb_updateFrame:SetScript("OnEvent", function(ef, event, arg1)
            if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
                ScheduleBBUpdate(true)
                return
            end
            -- CDM data loaded/world enter: force full restyle.
            -- Keep spell-override updates lightweight because they can fire from
            -- non-bar viewers (e.g. EssentialCooldownViewer) and cause bar blink.
            if event == "COOLDOWN_VIEWER_DATA_LOADED" or event == "PLAYER_ENTERING_WORLD" then
                InvalidateBarStyle()
                ef._layoutDirty = true
                ScheduleBBUpdate(true)
                return
            end
            if event == "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED" then
                ScheduleBBUpdate(false, true)
                return
            end
            if event == "SPELL_UPDATE_COOLDOWN" and not InCombatLockdown() then
                return  -- bar sounds/glows only need updates in combat
            end
            ScheduleBBUpdate(false, false) -- queue one batched dispatch
        end)

        -- Hook Blizzard bar layout — defer to next frame to avoid tainting
        -- Blizzard's secure execution path. Running RepositionAllBars synchronously
        -- inside hooksecurefunc taints values that EssentialCooldownViewer reads later.
        if BuffBarCooldownViewer and BuffBarCooldownViewer.RefreshLayout then
            hooksecurefunc(BuffBarCooldownViewer, "RefreshLayout", function()
                if self._bb_updateFrame and self._bb_updateFrame._repositioning then return end
                C_Timer.After(0, function()
                    if self._bb_updateFrame and self._bb_updateFrame._repositioning then return end
                    self:RepositionAllBars()
                end)
            end)
        end

        -- Hook the item container's Layout() — same deferred logic
        if BuffBarCooldownViewer and BuffBarCooldownViewer.GetItemContainerFrame then
            local container = BuffBarCooldownViewer:GetItemContainerFrame()
            if container and container.Layout then
                hooksecurefunc(container, "Layout", function()
                    if self._bb_updateFrame and self._bb_updateFrame._repositioning then return end
                    C_Timer.After(0, function()
                        if self._bb_updateFrame and self._bb_updateFrame._repositioning then return end
                        self:RepositionAllBars()
                    end)
                end)
            end
        end

        if BuffBarCooldownViewer and BuffBarCooldownViewer.OnAcquireItemFrame then
            hooksecurefunc(BuffBarCooldownViewer, "OnAcquireItemFrame", function(viewer, itemFrame)
                local profile = self.db and self.db.profile and self.db.profile.buffBars
                if profile and profile.clusterMode then
                    -- Immediately hide so the bar never flashes in BuffBarCooldownViewer
                    if itemFrame and itemFrame.SetAlpha then itemFrame:SetAlpha(0) end
                    SetClusterPendingBarHidden(itemFrame, true)
                    -- Defer reposition to avoid tainting secure execution
                    C_Timer.After(0, function()
                        self:RepositionAllBars()
                    end)
                else
                    SetClusterPendingBarHidden(itemFrame, false)
                    ScheduleBBUpdate(true)
                end

                -- Hook SetBarContent on each item frame (once) so Blizzard cannot
                -- re-show name/icon after we've hidden them via hideBarName / hideIcons.
                if itemFrame and not itemFrame._ccmSetBarContentHooked and itemFrame.SetBarContent then
                    hooksecurefunc(itemFrame, "SetBarContent", function(frame)
                        local cfg = self.db and self.db.profile and self.db.profile.buffBars
                        if not cfg then return end
                        -- Determine per-cluster override (if bar has a cluster assignment)
                        local ci = frame.Bar and GetBarState(frame.Bar).clusterIndex
                        local hideName = cfg.hideBarName
                        if ci and cfg.clusterHideBarNames and cfg.clusterHideBarNames[ci] ~= nil then
                            hideName = cfg.clusterHideBarNames[ci]
                        end
                        local hideIcon = cfg.hideIcons
                        if ci and cfg.clusterHideIcons and cfg.clusterHideIcons[ci] ~= nil then
                            hideIcon = cfg.clusterHideIcons[ci]
                        end
                        if hideName then
                            local nameFS = frame.GetNameFontString and frame:GetNameFontString()
                            if nameFS and nameFS.Hide then nameFS:Hide() end
                        end
                        if hideIcon then
                            local iconFrame = frame.GetIconFrame and frame:GetIconFrame()
                            if iconFrame and iconFrame.Hide then iconFrame:Hide() end
                        end
                    end)
                    itemFrame._ccmSetBarContentHooked = true
                end
            end)
        end

    end

    if not ScheduleBBUpdate then
        ScheduleBBUpdate = self._bb_scheduleUpdate
    end

    -- Also catch PLAYER_ENTERING_WORLD for UI reloads
    self._bb_updateFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

    -- Hook SetBarContent on any pre-existing item frames that were acquired before OnEnable
    if BuffBarCooldownViewer and BuffBarCooldownViewer.itemFramePool then
        for frame in BuffBarCooldownViewer.itemFramePool:EnumerateActive() do
            if frame and not frame._ccmSetBarContentHooked and frame.SetBarContent then
                hooksecurefunc(frame, "SetBarContent", function(f)
                    local cfg = self.db and self.db.profile and self.db.profile.buffBars
                    if not cfg then return end
                    local ci = f.Bar and GetBarState(f.Bar).clusterIndex
                    local hideName = cfg.hideBarName
                    if ci and cfg.clusterHideBarNames and cfg.clusterHideBarNames[ci] ~= nil then
                        hideName = cfg.clusterHideBarNames[ci]
                    end
                    local hideIcon = cfg.hideIcons
                    if ci and cfg.clusterHideIcons and cfg.clusterHideIcons[ci] ~= nil then
                        hideIcon = cfg.clusterHideIcons[ci]
                    end
                    if hideName then
                        local nameFS = f.GetNameFontString and f:GetNameFontString()
                        if nameFS and nameFS.Hide then nameFS:Hide() end
                    end
                    if hideIcon then
                        local iconFrame = f.GetIconFrame and f:GetIconFrame()
                        if iconFrame and iconFrame.Hide then iconFrame:Hide() end
                    end
                end)
                frame._ccmSetBarContentHooked = true
            end
        end
    end

    -- Delayed retries: Blizzard CDM populates bar data asynchronously after login.
    -- COOLDOWN_VIEWER_DATA_LOADED may have already fired before OnEnable, so force
    -- restyle at staggered intervals to catch late-populated bars.
    local ef = self._bb_updateFrame
    C_Timer.After(0.5, function()
        InvalidateBarStyle()
        ef._layoutDirty = true
        if ScheduleBBUpdate then ScheduleBBUpdate(true) end
    end)
    C_Timer.After(2.0, function()
        InvalidateBarStyle()
        ef._layoutDirty = true
        if ScheduleBBUpdate then ScheduleBBUpdate(true) end
    end)
    C_Timer.After(5.0, function()
        InvalidateBarStyle()
        ef._layoutDirty = true
        if ScheduleBBUpdate then ScheduleBBUpdate(true) end
    end)

end


-- Options panel for bar settings (CkraigCooldownManager)


-- Helper: Attach middle-click input box to a slider
local function AttachSliderInputBox(slider, minValue, maxValue, onValueSet)
    local editBox = CreateFrame("EditBox", nil, slider, "BackdropTemplate")
    editBox:SetAutoFocus(true)
    editBox:SetFontObject("GameFontHighlight")
    editBox:SetSize(60, 24)
    editBox:SetJustifyH("CENTER")
    editBox:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 }})
    editBox:SetBackdropColor(0,0,0,0.8)
    editBox:Hide()
    editBox:SetScript("OnEscapePressed", function(self) self:Hide() end)
    editBox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val then
            val = math.max(minValue, math.min(maxValue, val))
            slider:SetValue(val)
            if onValueSet then onValueSet(val) end
        end
        self:Hide()
    end)
    editBox:SetScript("OnEditFocusLost", function(self) self:Hide() end)
    slider:HookScript("OnMouseDown", function(_, btn)
        if btn == "MiddleButton" then
            editBox:SetText(tostring(math.floor(slider:GetValue())))
            editBox:SetPoint("CENTER", slider, "CENTER")
            editBox:Show()
            editBox:SetFocus()
        end
    end)
end


-- Old CreateCkraigBarOptionsPanel removed; options are now handled by Ace3 AceConfig (ui/options/CooldownBarsOptions.lua)
function _G.CreateCkraigBarOptionsPanel() return nil end
_G.EnsureCkraigBarOptionsPanel = _G.CreateCkraigBarOptionsPanel

-- [SECTION: EXPORTS]
-- ============================================================
-- Exported internals for external modules (SpellIdentity, etc.)
-- ============================================================
CkraigCooldownManager._barInternals = {
    GetBarState = GetBarState,
    SetBarStateValue = SetBarStateValue,
    GetBarStateValue = GetBarStateValue,
    GetBuffBarFrames = GetBuffBarFrames,
    NormalizeBarSpellKey = NormalizeBarSpellKey,
    GetSpellCandidatesFromCooldownInfo = GetSpellCandidatesFromCooldownInfo,
    IsSpellKnownForPlayer = IsSpellKnownForPlayer,
    IsCooldownKeyKnownForPlayer = IsCooldownKeyKnownForPlayer,
    ResolveBarSpellIdentity = ResolveBarSpellIdentity,
    BuildBarSpellItemsForOptions = BuildBarSpellItemsForOptions,
    InvalidateBarStyle = InvalidateBarStyle,
    barClusterAnchors = barClusterAnchors,
    MAX_BAR_CLUSTERS = MAX_BAR_CLUSTERS,
    EnsureBarClusterAnchor = EnsureBarClusterAnchor,
    ApplyBarClusterDragState = ApplyBarClusterDragState,
    HideAllBarClusterAnchors = HideAllBarClusterAnchors,
    HideAllIconBorders = HideAllIconBorders,
    FindIconTexture = FindIconTexture,
    roundPixel = roundPixel,
    RefreshAllBarIconVisibility = RefreshAllBarIconVisibility,
}
