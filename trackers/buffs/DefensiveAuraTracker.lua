-- ============================================================
-- CkraigCooldownManager :: Trackers :: Buffs :: DefensiveAuraTracker
-- ============================================================
-- Monitors Blizzard's ExternalDefensivesFrame for incoming external
-- defensive cooldowns and plays a configurable alert sound.
-- Integrates with CkraigProfileManager for profile-aware settings.
-- ============================================================

local addonName, CCM_Private = ...
local CCM = _G.CkraigCooldownManager

-- Saved-variable fallback table (used when ProfileManager is unavailable)
CCM_DefensiveAuraDB = CCM_DefensiveAuraDB or {}

-- ============================================================
-- Module table
-- ============================================================
local DefensiveAuraTracker = {}
_G.DefensiveAuraTracker = DefensiveAuraTracker

-- ============================================================
-- Settings helpers
-- ============================================================
local fallbackSettings = {
    enabled = true,
    alertSound = "RAID_WARNING",
    flashScreen = false,
    printMessage = false,
}

local function ApplyDefaults(settings)
    if settings.enabled == nil then settings.enabled = true end
    if settings.alertSound == nil then settings.alertSound = "RAID_WARNING" end
    if settings.flashScreen == nil then settings.flashScreen = false end
    if settings.printMessage == nil then settings.printMessage = false end
end

local function EnsureSettings()
    local settings

    if CkraigProfileManager and CkraigProfileManager.db and CkraigProfileManager.db.profile then
        local profile = CkraigProfileManager.db.profile
        if rawget(profile, "defensiveAura") == nil then
            profile.defensiveAura = {}
        end
        settings = profile.defensiveAura
    else
        CCM_DefensiveAuraDB.settings = CCM_DefensiveAuraDB.settings or {}
        settings = CCM_DefensiveAuraDB.settings
    end

    ApplyDefaults(settings)
    return settings
end

function DefensiveAuraTracker:GetSettings()
    return EnsureSettings() or fallbackSettings
end

-- ============================================================
-- Sound playback
-- ============================================================
-- SOUNDKIT fallback options (no LSM dependency required, but we
-- try LSM first when available for wider sound selection).
local SOUNDKIT_OPTIONS = {
    RAID_WARNING        = "Raid Warning Horn",
    READY_CHECK         = "Ready Check Ping",
    ALARM_CLOCK_WARNING_3 = "Alarm Clock Tone",
    LEVEL_UP            = "Level Up",
    IG_PLAYER_INVITE    = "Player Invite",
}

-- Track last played sound handle to prevent overlapping alerts
local _lastAlertSoundHandle = nil

local function PlayAlertSound()
    local settings = DefensiveAuraTracker:GetSettings()
    if not settings.enabled then return end

    local chosen = settings.alertSound
    if type(chosen) ~= "string" or chosen == "" then return end

    -- Prevent overlapping: check if previous alert is still playing
    if _lastAlertSoundHandle and C_Sound and C_Sound.IsPlaying then
        local ok, stillPlaying = pcall(C_Sound.IsPlaying, _lastAlertSoundHandle)
        if ok and stillPlaying then return end
    end

    -- Try LibSharedMedia first
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    if LSM then
        local path = LSM:Fetch("sound", chosen)
        if path then
            local ok, _, handle = pcall(PlaySoundFile, path, "Master")
            if ok and handle then _lastAlertSoundHandle = handle end
            return
        end
    end

    -- Fall back to SOUNDKIT
    if SOUNDKIT and SOUNDKIT[chosen] then
        local ok, _, handle = pcall(PlaySound, SOUNDKIT[chosen], "Master")
        if ok and handle then _lastAlertSoundHandle = handle end
    end
end

-- Expose for options panel preview button
function DefensiveAuraTracker:PreviewSound()
    PlayAlertSound()
end

-- ============================================================
-- Screen flash (optional visual cue)
-- ============================================================
local flashFrame

local function FlashScreen()
    local settings = DefensiveAuraTracker:GetSettings()
    if not settings.flashScreen then return end

    if not flashFrame then
        flashFrame = CreateFrame("Frame", nil, UIParent)
        flashFrame:SetAllPoints(UIParent)
        flashFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        flashFrame:SetAlpha(0)
        local tex = flashFrame:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints()
        tex:SetColorTexture(1, 0.84, 0, 0.25) -- gold tint
        flashFrame.tex = tex
    end

    flashFrame:SetAlpha(0.6)
    flashFrame:Show()

    local elapsed = 0
    flashFrame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local alpha = 0.6 * math.max(0, 1 - elapsed / 0.5)
        self:SetAlpha(alpha)
        if alpha <= 0 then
            self:Hide()
            self:SetScript("OnUpdate", nil)
        end
    end)
end

-- ============================================================
-- Chat message (optional)
-- ============================================================
local function PrintDefensiveMessage()
    local settings = DefensiveAuraTracker:GetSettings()
    if settings.printMessage then
        print("|cff00ff00[CCM]|r External defensive detected!")
    end
end

-- ============================================================
-- Combined alert handler
-- ============================================================
local function OnDefensiveDetected()
    local settings = DefensiveAuraTracker:GetSettings()
    if not settings.enabled then return end

    PlayAlertSound()
    FlashScreen()
    PrintDefensiveMessage()
end

-- ============================================================
-- Hook Blizzard ExternalDefensivesFrame
-- ============================================================
local hookedAuras = setmetatable({}, { __mode = "k" })

-- Utility: check if a spellID is an external defensive using modern API
-- Falls back to true if the API is unavailable (we trust Blizzard's frame)
function DefensiveAuraTracker:IsExternalDefensive(spellID)
    if not spellID then return false end
    if C_Spell and C_Spell.IsExternalDefensive then
        local ok, result = pcall(C_Spell.IsExternalDefensive, spellID)
        if ok then return result end
    end
    -- Fallback: trust the ExternalDefensivesFrame (it only shows real defensives)
    return true
end

-- Resolve spellID from an aura child frame (if available)
local function GetAuraSpellID(aura)
    if not aura then return nil end
    -- Blizzard aura frames often have .auraInstanceID or .spellID
    if aura.spellID then return aura.spellID end
    if aura.auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
        local ok, data = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, "player", aura.auraInstanceID)
        if ok and data and data.spellId then return data.spellId end
    end
    return nil
end

local function HookAuraFrame(aura)
    if hookedAuras[aura] then return end
    hookedAuras[aura] = true
    aura:HookScript("OnShow", function(self)
        OnDefensiveDetected()
    end)
    -- Fire immediately if already visible at hook time
    if aura:IsShown() then
        OnDefensiveDetected()
    end
end

local function HookAllAuraChildren()
    if not ExternalDefensivesFrame or not ExternalDefensivesFrame.AuraContainer then return end
    for i = 1, select("#", ExternalDefensivesFrame.AuraContainer:GetChildren()) do
        local child = select(i, ExternalDefensivesFrame.AuraContainer:GetChildren())
        if child then HookAuraFrame(child) end
    end
end

local function InitHooks()
    if not ExternalDefensivesFrame then return false end

    HookAllAuraChildren()

    if ExternalDefensivesFrame.AuraContainer and not ExternalDefensivesFrame.AuraContainer.__CCM_DA_Hooked then
        ExternalDefensivesFrame.AuraContainer.__CCM_DA_Hooked = true

        hooksecurefunc(ExternalDefensivesFrame.AuraContainer, "SetShown", function()
            HookAllAuraChildren()
        end)

        ExternalDefensivesFrame.AuraContainer:HookScript("OnShow", HookAllAuraChildren)
    end

    return true
end

-- ============================================================
-- Initialization
-- ============================================================
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:RegisterEvent("PLAYER_LOGIN")

local initDone = false
local initTicker = nil

local function TryInit()
    if initDone then
        if initTicker then initTicker:Cancel(); initTicker = nil end
        return
    end
    if InitHooks() then
        initDone = true
        if initTicker then initTicker:Cancel(); initTicker = nil end
        return
    end
end

-- Uses C_Timer.NewTicker for retry loop (cleaner than recursive C_Timer.After)
local function StartInitRetry()
    if initTicker or initDone then return end
    initTicker = C_Timer.NewTicker(1, function(self)
        TryInit()
        if initDone or self._remainingIterations == 0 then
            self:Cancel()
            initTicker = nil
        end
    end, 30)
end

initFrame:SetScript("OnEvent", function(self, event)
    EnsureSettings()
    TryInit()
    if not initDone then StartInitRetry() end
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

-- ============================================================
-- Slash command
-- ============================================================
SLASH_CCMDEFAURA1 = "/ccmdef"
SlashCmdList["CCMDEFAURA"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "on" then
        local s = DefensiveAuraTracker:GetSettings()
        s.enabled = true
        print("|cff00ff00[CCM]|r Defensive Aura alerts enabled.")
    elseif msg == "off" then
        local s = DefensiveAuraTracker:GetSettings()
        s.enabled = false
        print("|cff00ff00[CCM]|r Defensive Aura alerts disabled.")
    elseif msg == "test" then
        OnDefensiveDetected()
        print("|cff00ff00[CCM]|r Defensive alert test fired.")
    else
        print("|cff00ff00[CCM]|r Usage: /ccmdef on | off | test")
    end
end
