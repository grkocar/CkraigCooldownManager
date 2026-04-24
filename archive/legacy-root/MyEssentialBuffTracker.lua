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
local _ebt_batchFrame = CreateFrame("Frame")
_ebt_batchFrame:Hide()
local _ebt_lastUpdate = 0
local _ebt_throttle = 0.15 -- seconds

local function IsInCombat() return InCombatLockdown() end

local function MarkEssentialDirty(reason)
    _ebt_dirty = true
    if IsInCombat() then
        _ebt_batchFrame:Show()
    end
end

local _ebt_lastActiveCount_batch = -1

local function UpdateEssentialBatch()
    if not _ebt_dirty then _ebt_batchFrame:Hide(); return end
    _ebt_dirty = false
    _ebt_batchFrame:Hide()
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

_ebt_batchFrame:SetScript("OnUpdate", function(self, elapsed)
    _ebt_lastUpdate = _ebt_lastUpdate + elapsed
    if _ebt_lastUpdate >= _ebt_throttle then
        _ebt_lastUpdate = 0
        UpdateEssentialBatch()
    end
end)

-- Hook combat state events to manage batch frame lifecycle
local function SetupEssentialEventHooks()
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("PLAYER_REGEN_DISABLED")
    ef:RegisterEvent("PLAYER_REGEN_ENABLED")
    ef:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_REGEN_DISABLED" then
            if _ebt_dirty then _ebt_batchFrame:Show() end
        elseif event == "PLAYER_REGEN_ENABLED" then
            _ebt_batchFrame:Hide()
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
    self:InitializeDB()
    local settings = self:GetSettings()
    if settings and type(settings.spellGlows) ~= "table" then
        settings.spellGlows = {}
    end

    if self.StopAllGlowsNow then
        self:StopAllGlowsNow()
    end

    C_Timer.After(0.1, function()
        if MyEssentialBuffTracker and MyEssentialBuffTracker.StopAllGlowsNow then
            MyEssentialBuffTracker:StopAllGlowsNow()
        end
        if _G.CkraigGlowManager and _G.CkraigGlowManager.DisableCustomGlowsNow then
            _G.CkraigGlowManager.DisableCustomGlowsNow()
        end
        if MyEssentialBuffTracker and MyEssentialBuffTracker.RefreshEssentialLayout then
            MyEssentialBuffTracker:RefreshEssentialLayout()
        end
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
}
    local settings = MyEssentialBuffTracker:GetSettings()
    if settings.borderSize == nil then settings.borderSize = DEFAULTS.borderSize end
    settings.borderColor = settings.borderColor or DEFAULTS.borderColor

local LCG = LibStub("LibCustomGlow-1.0", true)
local LibEditMode = LibStub("LibEditMode", true)

-- Reusable glow color array (avoids table allocation per icon per dispatch)
local ebtGlowColor = { 1, 1, 1, 1 }
local ebtProcOpts = { color = ebtGlowColor, key = "ebtGlow" }
local ebtEnabledGlowLookup = {}

-- Pooled tables for ApplyViewerLayout (avoids GC churn on every cooldown/aura event)
local _ebt_icons = {}
local _ebt_shownIcons = {}
local _ebt_rows = {}
-- _ebt_iconSortComparator defined below (after ebtIconMeta)

-- Skin version system: skip re-skinning when settings haven't changed
local _ebt_skinVersion = 1
local _ebt_lastSkinFingerprint = ""

local function GetEBTSkinFingerprint(settings)
    return table.concat({
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
        settings.borderSize or 0,
    }, "|")
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

local function SuppressEssentialAlertVisual(icon)
    if not icon then return end
    local alert = icon.SpellActivationAlert
    if alert then
        if not alert._ebtSuppressed then
            alert._ebtSuppressed = true
            alert:HookScript("OnShow", function(self)
                self:Hide()
            end)
        end
        alert:Hide()
    end

    -- Some frames expose proc visuals via children instead of icon.SpellActivationAlert.
    if icon.GetChildren then
        for _, child in ipairs({ icon:GetChildren() }) do
            if child and child.GetName then
                local childName = child:GetName()
                if childName and childName:find("SpellActivationAlert", 1, true) then
                    if not child._ebtSuppressed then
                        child._ebtSuppressed = true
                        child:HookScript("OnShow", function(self)
                            self:Hide()
                        end)
                    end
                    child:Hide()
                end
            end
        end
    end
end

local function StopGlow_EBT(icon)
    if not LCG or not icon then return end
    -- Clear both Essential and global glow channels to avoid stale cross-system glows.
    LCG.AutoCastGlow_Stop(icon, "ebtGlow")
    LCG.AutoCastGlow_Stop(icon, "ccmGlow")
    LCG.ButtonGlow_Stop(icon)
    LCG.ProcGlow_Stop(icon, "ebtGlow")
    LCG.ProcGlow_Stop(icon, "ccmGlow")
    LCG.PixelGlow_Stop(icon, "ebtGlow")
    LCG.PixelGlow_Stop(icon, "ccmGlow")
    LCG.PixelGlow_Stop(icon, "ubtGlow")
    LCG.PixelGlow_Stop(icon, "diGlow")
    -- Also stop default-key glows when another path started glow without an explicit key.
    LCG.AutoCastGlow_Stop(icon)
    LCG.ProcGlow_Stop(icon)
    LCG.PixelGlow_Stop(icon)
    SuppressEssentialAlertVisual(icon)

    local m = ebtIconMeta[icon]
    if m then
        m.glowing = false
        m.glowType = nil
    end
end

local function StopGlow_EBT_Recursive(frame, depth)
    if not frame then return end
    depth = depth or 0
    if depth > 4 then return end

    StopGlow_EBT(frame)

    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do
            StopGlow_EBT_Recursive(child, depth + 1)
        end
    end
end

local function StopAllEssentialGlows(viewer, pool)
    if pool then
        for icon in pool:EnumerateActive() do
            StopGlow_EBT(icon)
        end
    end

    for _, frame in pairs(_ebt_persistentIcons or {}) do
        StopGlow_EBT(frame)
    end
    for _, frame in pairs(_ebt_duplicateIcons or {}) do
        StopGlow_EBT(frame)
    end
    for frame in pairs(MyEssentialBuffTracker._externalIcons or {}) do
        StopGlow_EBT(frame)
    end

    if viewer and viewer.GetChildren then
        for _, child in ipairs({ viewer:GetChildren() }) do
            if child and (child.Icon or child.icon) then
                StopGlow_EBT(child)
            end
        end
    end

    -- Last-resort sweep: stop any glow left on nested Essential viewer children.
    if viewer then
        StopGlow_EBT_Recursive(viewer, 0)
    end
end

function MyEssentialBuffTracker:StopAllGlowsNow()
    local viewer = _G["EssentialCooldownViewer"]
    local pool = viewer and viewer.itemFramePool or nil
    StopAllEssentialGlows(viewer, pool)
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

    if settings.staticGridMode == nil then settings.staticGridMode = DEFAULTS.staticGridMode end
    if settings.gridRows == nil then settings.gridRows = DEFAULTS.gridRows end
    if settings.gridColumns == nil then settings.gridColumns = DEFAULTS.gridColumns end
    if settings.gridSlotMap == nil then settings.gridSlotMap = {} end

    -- Per-row sizes
    if settings.rowSizes == nil then settings.rowSizes = {} end
    if settings.rowOffsets == nil then settings.rowOffsets = {} end

    -- Per-spell glows
    if settings.spellGlows == nil then settings.spellGlows = {} end

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
end

-- ---------------------------
-- Icon key identification for glow system
-- Uses ONLY direct frame fields (clean, never tainted) to avoid "table index is secret".
-- Resolves cooldownID → spellID through Blizzard's C_CooldownViewer API.
-- ---------------------------
local function GetEssentialIconKey(icon)
    if not icon then return nil end

    -- 1. Try direct .cooldownID field → resolve to spellID via C_CooldownViewer
    local cdID = icon.cooldownID
    if cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
        if ok and info and info.spellID then
            return info.spellID
        end
    end

    -- 2. Direct .spellID field (some frames set this directly)
    if icon.spellID then return icon.spellID end

    -- 3. Direct .auraInstanceID → resolve to spellId via C_UnitAuras
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

-- Hook icon's Cooldown widget to track cooldown state without reading tainted values.
-- SetCooldown = on cooldown (Blizzard only calls this for real CDs via CooldownFrame_Set)
-- Clear = cooldown cleared (CooldownFrame_Set calls Clear for 0-duration)
-- OnCooldownDone = cooldown animation finished
local function HookCooldownTracking(icon)
    local m = GetIconMeta(icon)
    if m.cdHooked then return end
    local cd = icon.Cooldown
    if not cd then return end
    m.cdHooked = true
    m.isOnCD = false
    hooksecurefunc(cd, "SetCooldown", function()
        local im = ebtIconMeta[icon]
        if im then im.isOnCD = true end
    end)
    hooksecurefunc(cd, "Clear", function()
        local im = ebtIconMeta[icon]
        if im then im.isOnCD = false end
    end)
    cd:HookScript("OnCooldownDone", function()
        local im = ebtIconMeta[icon]
        if im then im.isOnCD = false end
    end)
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
    if not picon and icon.GetChildren then
        for _, child in ipairs({ icon:GetChildren() }) do
            local n = child.GetName and child:GetName()
            if n and n:find("Pandemic") then
                picon = child
                break
            end
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

    local label = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOP", 0, -4)
    label:SetText("EBT Cluster " .. index)
    anchor._clusterLabel = label
    anchor._clusterIndex = index
    label:Hide()

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
    anchor:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            ShowEBTClusterContextMenu(self, MyEssentialBuffTracker:GetSettings(), index)
        end
    end)

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
-- Event registration deferred until persistent icons are created (avoids idle CPU)
_ebt_persistentUpdateFrame:SetScript("OnEvent", function(self)
    self:Show()
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

-- Update persistent + duplicate icons on SPELL_UPDATE_COOLDOWN
_ebt_persistentUpdateFrame._lastRun = 0
_ebt_persistentUpdateFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    local now = GetTime()
    if now - self._lastRun < 0.1 then return end
    self._lastRun = now
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
                    if not pcall(frame.Cooldown.SetCooldown, frame.Cooldown, cdStart, cdDur) then
                        frame.Cooldown:Clear()
                    end
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
        self:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
    end
end)

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
                if anchor._clusterLabel then anchor._clusterLabel:Show() end
                anchor:SetBackdropColor(0, 0, 0, 0.3)
                anchor:SetBackdropBorderColor(0.2, 0.8, 0.4, 0.9)
            elseif showForSamples then
                anchor:Show()
                anchor:EnableMouse(false)
                if anchor._clusterLabel then anchor._clusterLabel:Hide() end
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
        for _, child in ipairs({container:GetChildren()}) do
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
            local anchor = EnsureEBTClusterAnchorForIndex(viewer, settings, i)
            if anchor and anchor._clusterLabel then
                anchor._clusterLabel:SetText("EBT Cluster " .. i)
            end
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
            _ebt_persistentUpdateFrame:Show()
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
            _ebt_persistentUpdateFrame:Show()
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

        -- Unlock preview: show sample icons, enable dragging, return early
        if settings.clusterUnlocked then
            RenderEBTClusterSampleIcons(viewer, settings, clusterCount, rowLimit, iconSize, spacing, {
                unlockPreview = true,
                availableKeys = availableKeys,
            })
            ApplyEBTClusterDragState(viewer, settings)
            GetViewerMeta(viewer).lastNumRows = 1
            GetViewerMeta(viewer).iconCount = 0
            return
        else
            RenderEBTClusterSampleIcons(viewer, settings, clusterCount, rowLimit, iconSize, spacing, {
                unlockPreview = false,
                availableKeys = availableKeys,
            })
        end

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
                    end
                end
            end
        end

        ApplyEBTClusterDragState(viewer, settings)
        GetViewerMeta(viewer).lastNumRows = 1
        GetViewerMeta(viewer).iconCount = totalVisibleIcons
        -- Shrink viewer itself — icons live on cluster anchors now
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
            ebtDispatch:Hide() -- starts hidden; zero CPU until an event fires
            ebtDispatch._lastActiveCount = -1
            ebtDispatch._lastRun = 0

            ebtDispatch:SetScript("OnEvent", function(self, event, arg1)
                -- During combat, keep batch layout updates but still allow glow events to dispatch.
                if event ~= "PLAYER_REGEN_ENABLED" and InCombatLockdown() and event ~= "SPELL_UPDATE_COOLDOWN" and event ~= "UNIT_AURA" then
                    MarkEssentialDirty(event)
                    return
                end
                self:Show()
            end)

            -- Hook Blizzard layout for instant response
            if viewer.RefreshLayout then
                hooksecurefunc(viewer, "RefreshLayout", function()
                    ebtDispatch._lastActiveCount = -1 -- force layout on next dispatch
                    ebtDispatch:Show()
                end)
            end

            -- Show/hide dispatch with timestamp throttle (max ~10/sec, zero ticking)
            ebtDispatch:SetScript("OnUpdate", function(self)
                self:Hide()
                local now = GetTime()
                if now - self._lastRun < 0.15 then return end
                self._lastRun = now

                -- Layout on icon count change only (or always in cluster mode)
                local pool = viewer.itemFramePool
                local layoutRan = false
                if pool and not InCombatLockdown() then
                    local count = pool:GetNumActive()
                    local settings_now = MyEssentialBuffTracker:GetSettings()
                    local forceLayout = settings_now and settings_now.multiClusterMode
                    if count ~= self._lastActiveCount or forceLayout then
                        self._lastActiveCount = count
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

                -- Glow update
                if not LCG then return end
                local settings = MyEssentialBuffTracker:GetSettings()
                local spellGlows = settings and settings.spellGlows or {}

                -- Use Blizzard's itemFramePool (zero-allocation iterator)
                local pool = viewer.itemFramePool
                if not pool or pool:GetNumActive() == 0 then return end

                if not next(spellGlows) then
                    StopAllEssentialGlows(viewer, pool)
                    return
                end

                table_wipe(ebtEnabledGlowLookup)
                for skey, cfg in pairs(spellGlows) do
                    if type(cfg) == "table" and cfg.enabled then
                        ebtEnabledGlowLookup[tostring(skey)] = cfg
                    end
                end
                if not next(ebtEnabledGlowLookup) then
                    StopAllEssentialGlows(viewer, pool)
                    return
                end

                local getSpellCooldown = C_Spell and C_Spell.GetSpellCooldown
                local gcdStateCache = {}
                for icon in pool:EnumerateActive() do
                    if icon and (icon.Icon or icon.icon) then
                        SuppressEssentialAlertVisual(icon)
                        local im = GetIconMeta(icon)
                        if not im.cdHooked then
                            HookCooldownTracking(icon)
                        end
                        -- Only re-resolve key when the underlying ID changes
                        local curCdID = icon.cooldownID
                        local curAuraID = icon.auraInstanceID
                        local curSpellID = icon.spellID
                        local hasStableIdentity = (curCdID ~= nil) or (curAuraID ~= nil) or (curSpellID ~= nil)

                        -- Frame-pool reuse can leave stale cached keys; if this icon has no stable identity,
                        -- force-clear cache and any active glow for this frame.
                        if not hasStableIdentity then
                            im._lastCdID = nil
                            im._lastAuraID = nil
                            im._lastSpellID = nil
                            im.cachedKey = nil
                            im.cachedKeyStr = nil
                            im.cachedKeyNum = nil
                            if im.glowing then
                                StopGlow_EBT(icon)
                                im.glowing = false
                                im.glowType = nil
                            end
                        elseif curCdID ~= im._lastCdID or curAuraID ~= im._lastAuraID or curSpellID ~= im._lastSpellID then
                            im._lastCdID = curCdID
                            im._lastAuraID = curAuraID
                            im._lastSpellID = curSpellID
                            local freshKey = GetEssentialIconKey(icon)
                            im.cachedKey = freshKey
                            if freshKey then
                                im.cachedKeyStr = tostring(freshKey)
                                im.cachedKeyNum = tonumber(freshKey)
                            else
                                im.cachedKeyStr = nil
                                im.cachedKeyNum = nil
                            end
                        end
                        local key = im.cachedKey
                        if key then
                            local glowCfg = ebtEnabledGlowLookup[im.cachedKeyStr]
                            if not glowCfg and im.cachedKeyNum then
                                glowCfg = ebtEnabledGlowLookup[tostring(im.cachedKeyNum)]
                            end
                            if glowCfg then
                                local shouldGlow = false
                                if icon:IsShown() then
                                    local cfgModeRaw = glowCfg.mode
                                    if cfgModeRaw == "ready" then
                                        shouldGlow = IsIconReady(icon)
                                    elseif cfgModeRaw == "cooldown" then
                                        shouldGlow = IsIconOnCooldown(icon)
                                        if shouldGlow and getSpellCooldown and im.cachedKeyNum then
                                            local gcdOnly = gcdStateCache[im.cachedKeyNum]
                                            if gcdOnly == nil then
                                                local info = getSpellCooldown(im.cachedKeyNum)
                                                gcdOnly = (info and info.isOnGCD) and true or false
                                                gcdStateCache[im.cachedKeyNum] = gcdOnly
                                            end
                                            if gcdOnly then shouldGlow = false end
                                        end
                                    end
                                end
                                local glowType = "pixel"
                                local cfgGlowTypeRaw = glowCfg.glowType
                                if glowCfg.__ccmGlowTypeRaw ~= cfgGlowTypeRaw then
                                    glowCfg.__ccmGlowTypeRaw = cfgGlowTypeRaw
                                    glowCfg.__ccmGlowType = cfgGlowTypeRaw or "pixel"
                                end
                                glowType = glowCfg.__ccmGlowType or "pixel"
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
                                    StopGlow_EBT(icon)
                                    im.glowing = false
                                    im.glowType = nil
                                end
                            else
                                StopGlow_EBT(icon)
                                im.glowing = false
                                im.glowType = nil
                            end
                        elseif im.glowing then
                            StopGlow_EBT(icon)
                            im.glowing = false
                            im.glowType = nil
                        end
                    end
                end
            end)

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
                StopAllEssentialGlows(viewer, viewer.itemFramePool)
                C_Timer.After(0.25, function()
                    local v = _G["EssentialCooldownViewer"]
                    if v then
                        StopAllEssentialGlows(v, v.itemFramePool)
                    end
                end)
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

    -- Register the ANCHOR (our own frame) with LibEditMode — not the Blizzard viewer
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
        -- Anchor stays attached to viewer — Blizzard manages viewer position per layout
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


function MyEssentialBuffTracker:CreateOptionsPanel()
    EnsureDB()
    if optionsPanel then return optionsPanel end
    optionsPanel = CreateFrame("Frame", "MyEssentialBuffTrackerOptionsPanel", InterfaceOptionsFramePanelContainer or UIParent)
        -- Always refresh UI when panel is shown
        optionsPanel:SetScript("OnShow", function()
            if MyEssentialBuffTracker and MyEssentialBuffTracker.UpdateSettings then
                MyEssentialBuffTracker:UpdateSettings()
            end
        end)
    optionsPanel.name = "MyEssentialBuffTracker"
    optionsPanel:SetSize(550, 1100)
    -- Add green note to top-right (after optionsPanel is created)
    local note = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    note:SetPoint("TOPRIGHT", optionsPanel, "TOPRIGHT", -24, -26)
    note:SetText("Drag all spells in essential cooldown manager!")
    note:SetTextColor(0.2, 1, 0.2, 1)
    note:SetJustifyH("LEFT")

    -- ScrollFrame setup
    local scrollFrame = CreateFrame("ScrollFrame", nil, optionsPanel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", 0, 0)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(530, 2000)
    scrollFrame:SetScrollChild(content)

    optionsPanel._content = content


    -- Inline per-row slider builder, returns new y offset
    local function AddPerRowSliders(content, x1, y)
        -- Remove old widgets
        if content._rowSizeWidgets then
            for _, w in ipairs(content._rowSizeWidgets) do if w then w:Hide() end end
        end
        content._rowSizeWidgets = {}

        local viewer = _G["EssentialCooldownViewer"]
        local numRows = 1
        local vm = viewer and ebtViewerMeta[viewer]
        if vm and vm.lastNumRows and vm.lastNumRows > 0 then
            numRows = vm.lastNumRows
        end

        local rowSizeTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        rowSizeTitle:SetPoint("TOPLEFT", x1, y)
        rowSizeTitle:SetText("Row Icon Sizes")
        rowSizeTitle:SetTextColor(0.9, 0.9, 0.9, 1)
        y = y - 24
        table.insert(content._rowSizeWidgets, rowSizeTitle)

        for r = 1, numRows do
            local settings = MyEssentialBuffTracker:GetSettings()
            local current = (settings.rowSizes and settings.rowSizes[r]) or settings.iconSize
            local rowSlider = CreateSlider(content, "Row "..r.." Size", 1, 200, 1, current,
                function(v)
                    local settings = MyEssentialBuffTracker:GetSettings()
                    settings.rowSizes = settings.rowSizes or {}
                    settings.rowSizes[r] = v
                    local viewer = _G["EssentialCooldownViewer"]
                    if viewer then
                        ForceReskinViewer(viewer)
                        pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
                        if optionsPanel and optionsPanel._rebuildConfigUI then optionsPanel:_rebuildConfigUI() end
                    end
                end)
            rowSlider:SetPoint("TOPLEFT", x1, y)
            y = y - 46
            table.insert(content._rowSizeWidgets, rowSlider)

            local currentOffset = (settings.rowOffsets and settings.rowOffsets[r]) or 0
            local offsetSlider = CreateSlider(content, "Row "..r.." Y Offset", -300, 300, 1, currentOffset,
                function(v)
                    local settings = MyEssentialBuffTracker:GetSettings()
                    settings.rowOffsets = settings.rowOffsets or {}
                    settings.rowOffsets[r] = v
                    local viewer = _G["EssentialCooldownViewer"]
                    if viewer then
                        pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
                    end
                end)
            offsetSlider:SetPoint("TOPLEFT", x1, y)
            y = y - 46
            table.insert(content._rowSizeWidgets, offsetSlider)
        end
        return y
    end


    -- Rebuilds the entire config UI, including per-row sliders, with correct y-offsets
    function optionsPanel:_rebuildConfigUI()
        -- Remove all child frames
        for i, child in ipairs({content:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end
        -- Properly neutralize old regions (FontStrings can't be reparented;
        -- hide + clear points/text/alpha to prevent ghosting on rebuild)
        for _, region in ipairs({content:GetRegions()}) do
            if region then
                if region.Hide then region:Hide() end
                if region.ClearAllPoints then region:ClearAllPoints() end
                if region.SetText then region:SetText("") end
                if region.SetAlpha then region:SetAlpha(0) end
            end
        end

        local title = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -12)
        title:SetText("MyEssentialBuffTracker")
        title:SetTextColor(1, 1, 1, 1)

        -- After all controls are created, force OnShow for all children to update input/valueText
        C_Timer.After(0, function()
            for _, child in ipairs({content:GetChildren()}) do
                if child.Show then child:Show() end
            end
        end)

        local x1, x2 = 20, 290
        local y = -48


        -- ICON SETTINGS
        local iconTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        iconTitle:SetPoint("TOPLEFT", x1, y)
        iconTitle:SetText("Icon Settings")
        iconTitle:SetTextColor(0.9, 0.9, 0.9, 1)
        y = y - 24

        local iconSizeSlider = CreateSlider(content, "Icon Size", -200, 300, 1, MyEssentialBuffTracker:GetSettings().iconSize,
            function(v)
                MyEssentialBuffTracker:GetSettings().iconSize = v
                local viewer = _G["EssentialCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
                    if optionsPanel and optionsPanel._rebuildConfigUI then optionsPanel:_rebuildConfigUI() end
                end
            end)
        iconSizeSlider:SetPoint("TOPLEFT", x1, y)

        local aspectRatioSlider = CreateSlider(content, "Aspect Ratio", 0.1, 5.0, 0.01, MyEssentialBuffTracker:GetSettings().aspectRatioCrop or 1.0,
            function(v)
                MyEssentialBuffTracker:GetSettings().aspectRatioCrop = v
                local viewer = _G["EssentialCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
                    if optionsPanel and optionsPanel._rebuildConfigUI then optionsPanel:_rebuildConfigUI() end
                end
            end)
        aspectRatioSlider:SetPoint("TOPLEFT", x2, y)
        y = y - 46

        local cornerRadius = CreateSlider(content, "Corner Radius", -50, 100, 1, MyEssentialBuffTracker:GetSettings().iconCornerRadius or 0,
            function(v)
                MyEssentialBuffTracker:GetSettings().iconCornerRadius = v
                local viewer = _G["EssentialCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
                end
            end)
        cornerRadius:SetPoint("TOPLEFT", x1, y)
        y = y - 52

        -- ENABLE VIEWER OPTION
        local enableCheck = CreateCheckbox(content, "Enable Essential Tracker", MyEssentialBuffTracker:GetSettings().enabled ~= false,
            function(v)
                MyEssentialBuffTracker:GetSettings().enabled = v
                UpdateCooldownManagerVisibility()
            end)
        enableCheck:SetPoint("TOPLEFT", x1, y)
        y = y - 28

        -- HIDE WHEN MOUNTED OPTION (now visible in UI)
        local hideMount = CreateCheckbox(content, "Hide when mounted", MyEssentialBuffTracker:GetSettings().hideWhenMounted,
            function(v)
                MyEssentialBuffTracker:GetSettings().hideWhenMounted = v
                if v then
                    mountEventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
                else
                    mountEventFrame:UnregisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
                end
                UpdateCooldownManagerVisibility()
            end)
        hideMount:SetPoint("TOPLEFT", x1, y)
        y = y - 28

        -- SPACING & LAYOUT
        local spaceTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        spaceTitle:SetPoint("TOPLEFT", x1, y)
        spaceTitle:SetText("Spacing & Layout")
        spaceTitle:SetTextColor(0.9, 0.9, 0.9, 1)
        y = y - 24

        local hSpace = CreateSlider(content, "Horizontal Spacing", -200, 200, 1, MyEssentialBuffTracker:GetSettings().spacing,
            function(v)
                MyEssentialBuffTracker:GetSettings().spacing = v
                local viewer = _G["EssentialCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
                    if optionsPanel and optionsPanel._rebuildConfigUI then optionsPanel:_rebuildConfigUI() end
                end
            end)
        hSpace:SetPoint("TOPLEFT", x1, y)

        local vSpace = CreateSlider(content, "Vertical Spacing", -200, 200, 1, MyEssentialBuffTracker:GetSettings().spacing,
            function(v)
                MyEssentialBuffTracker:GetSettings().spacing = v
                local viewer = _G["EssentialCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
                    if optionsPanel and optionsPanel._rebuildConfigUI then optionsPanel:_rebuildConfigUI() end
                end
            end)
        vSpace:SetPoint("TOPLEFT", x2, y)
        y = y - 46

        local perRow = CreateSlider(content, "Icons Per Row", 1, 50, 1, MyEssentialBuffTracker:GetSettings().columns,
            function(v)
                local settings = MyEssentialBuffTracker:GetSettings()
                settings.columns = v; settings.rowLimit = v
                local viewer = _G["EssentialCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
                    if optionsPanel and optionsPanel._rebuildConfigUI then optionsPanel:_rebuildConfigUI() end
                end
            end)
        perRow:SetPoint("TOPLEFT", x1, y)
        y = y - 52

        y = y - 46

        -- =============================
        -- CLUSTER MODE
        -- =============================
        local clusterTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        clusterTitle:SetPoint("TOPLEFT", x1, y)
        clusterTitle:SetText("Cluster Mode")
        clusterTitle:SetTextColor(0.2, 0.8, 0.4, 1)
        y = y - 24

        local clusterEnable = CreateCheckbox(content, "Enable Multi-Cluster Mode", MyEssentialBuffTracker:GetSettings().multiClusterMode,
            function(v)
                MyEssentialBuffTracker:GetSettings().multiClusterMode = v
                local viewer = _G["EssentialCooldownViewer"]
                if viewer then
                    pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
                end
                if optionsPanel and optionsPanel._rebuildConfigUI then optionsPanel:_rebuildConfigUI() end
            end)
        clusterEnable:SetPoint("TOPLEFT", x1, y)
        y = y - 28

        if MyEssentialBuffTracker:GetSettings().multiClusterMode then
        local clusterUnlock = CreateCheckbox(content, "Unlock Clusters (drag to reposition)", MyEssentialBuffTracker:GetSettings().clusterUnlocked,
            function(v)
                MyEssentialBuffTracker:GetSettings().clusterUnlocked = v
                local viewer = _G["EssentialCooldownViewer"]
                if viewer then
                    pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
                end
            end)
        clusterUnlock:SetPoint("TOPLEFT", x1, y)
        y = y - 28

        local clusterCenter = CreateCheckbox(content, "Center icons in cluster", MyEssentialBuffTracker:GetSettings().clusterCenterIcons ~= false,
            function(v)
                MyEssentialBuffTracker:GetSettings().clusterCenterIcons = v
                local viewer = _G["EssentialCooldownViewer"]
                if viewer then
                    pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
                end
            end)
        clusterCenter:SetPoint("TOPLEFT", x1, y)
        y = y - 28

        local clusterCountSlider = CreateSlider(content, "Number of Clusters", 1, 20, 1, MyEssentialBuffTracker:GetSettings().clusterCount or 5,
            function(v)
                MyEssentialBuffTracker:GetSettings().clusterCount = v
                local viewer = _G["EssentialCooldownViewer"]
                if viewer then
                    pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
                    if optionsPanel and optionsPanel._rebuildConfigUI then optionsPanel:_rebuildConfigUI() end
                end
            end)
        clusterCountSlider:SetPoint("TOPLEFT", x1, y)
        y = y - 52

        -- Per-cluster settings
        local curSettings = MyEssentialBuffTracker:GetSettings()
        local cCount = SafeNumber(curSettings.clusterCount, 5)
        local flowOptions = {"horizontal", "vertical"}

        for ci = 1, cCount do
            local ciLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            ciLabel:SetPoint("TOPLEFT", x1, y)
            ciLabel:SetText("Cluster " .. ci)
            ciLabel:SetTextColor(0.2, 0.8, 0.4, 1)
            y = y - 20

            local ciFlow = CreateDropdown(content, "Flow", flowOptions, curSettings.clusterFlows[ci] or curSettings.clusterFlow or "horizontal",
                function(v)
                    MyEssentialBuffTracker:GetSettings().clusterFlows[ci] = v
                    local viewer = _G["EssentialCooldownViewer"]
                    if viewer then pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer) end
                end)
            ciFlow:SetPoint("TOPLEFT", x1, y)

            local ciSize = CreateSlider(content, "Icon Size", 1, 200, 1, curSettings.clusterIconSizes[ci] or curSettings.iconSize,
                function(v)
                    MyEssentialBuffTracker:GetSettings().clusterIconSizes[ci] = v
                    local viewer = _G["EssentialCooldownViewer"]
                    if viewer then pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer) end
                end)
            ciSize:SetPoint("TOPLEFT", x2, y)
            y = y - 52
        end

        -- Spell-to-cluster assignment list
        local assignTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        assignTitle:SetPoint("TOPLEFT", x1, y)
        assignTitle:SetText("Spell Cluster Assignments")
        assignTitle:SetTextColor(0.2, 0.8, 0.4, 1)
        y = y - 20

        local assignNote = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        assignNote:SetPoint("TOPLEFT", x1, y)
        assignNote:SetText("Assign spells to clusters. Unassigned spells go to Cluster 1.")
        assignNote:SetTextColor(0.6, 0.6, 0.6, 1)
        y = y - 16

        local viewer = _G["EssentialCooldownViewer"]
        local assignItems = {}
        if viewer then
            local ok, result = pcall(CollectEssentialDisplayedItems, viewer)
            if ok and result then assignItems = result end
        end
        -- Also include previously-assigned spells
        local addedAssignKeys = {}
        for _, item in ipairs(assignItems) do addedAssignKeys[tostring(item.key)] = true end
        for spellKey in pairs(curSettings.clusterAssignments or {}) do
            if not addedAssignKeys[tostring(spellKey)] then
                local id = tonumber(spellKey)
                local name = id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) or nil
                local iconTex = id and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id) or nil
                if name then
                    table.insert(assignItems, { key = id or spellKey, name = name, icon = iconTex })
                    addedAssignKeys[tostring(spellKey)] = true
                end
            end
        end
        table.sort(assignItems, function(a, b) return (a.name or "") < (b.name or "") end)

        local clusterLabels = {}
        for ci = 1, cCount do clusterLabels[ci] = "Cluster " .. ci end

        for _, item in ipairs(assignItems) do
            local row = CreateFrame("Frame", nil, content)
            row:SetSize(500, 28)
            row:SetPoint("TOPLEFT", x1, y)

            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(20, 20)
            icon:SetPoint("LEFT", 0, 0)
            icon:SetTexture(item.icon or "Interface\\ICONS\\INV_Misc_QuestionMark")

            local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameLabel:SetPoint("LEFT", icon, "RIGHT", 6, 0)
            nameLabel:SetText(item.name or tostring(item.key))
            nameLabel:SetTextColor(1, 1, 1, 1)
            nameLabel:SetWidth(140)
            nameLabel:SetJustifyH("LEFT")

            local keyStr = tostring(item.key)
            local currentCI = tonumber(curSettings.clusterAssignments[keyStr]) or 1

            local ciDropdown = CreateDropdown(row, "", clusterLabels, clusterLabels[currentCI] or "Cluster 1",
                function(v)
                    for ci = 1, cCount do
                        if v == clusterLabels[ci] then
                            MyEssentialBuffTracker:GetSettings().clusterAssignments[keyStr] = ci
                            break
                        end
                    end
                    local viewer = _G["EssentialCooldownViewer"]
                    if viewer then pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer) end
                    if optionsPanel and optionsPanel._rebuildConfigUI then optionsPanel:_rebuildConfigUI() end
                end)
            ciDropdown:SetPoint("LEFT", nameLabel, "RIGHT", 4, 0)

            -- Order position label
            local orderLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            orderLabel:SetPoint("LEFT", ciDropdown, "RIGHT", 6, 0)
            orderLabel:SetWidth(28)
            orderLabel:SetJustifyH("CENTER")

            -- Up button
            local upButton = CreateFrame("Button", nil, row, "UIPanelScrollUpButtonTemplate")
            upButton:SetSize(20, 20)
            upButton:SetPoint("LEFT", orderLabel, "RIGHT", 2, 0)

            -- Down button
            local downButton = CreateFrame("Button", nil, row, "UIPanelScrollDownButtonTemplate")
            downButton:SetSize(20, 20)
            downButton:SetPoint("LEFT", upButton, "RIGHT", 2, 0)

            local function RefreshOrderLabel()
                local curCluster = tonumber(MyEssentialBuffTracker:GetSettings().clusterAssignments[keyStr]) or 1
                local orderedKeys = BuildEBTOrderedKeysForCluster(MyEssentialBuffTracker:GetSettings(), curCluster, nil)
                local position = "-"
                for idx, key in ipairs(orderedKeys) do
                    if tostring(key) == keyStr then
                        position = tostring(idx)
                        break
                    end
                end
                orderLabel:SetText(position)
            end
            RefreshOrderLabel()

            upButton:SetScript("OnClick", function()
                local curCluster = tonumber(MyEssentialBuffTracker:GetSettings().clusterAssignments[keyStr]) or 1
                MoveKeyInEBTClusterOrder(MyEssentialBuffTracker:GetSettings(), curCluster, keyStr, -1)
                local activeViewer = _G["EssentialCooldownViewer"]
                if activeViewer then
                    pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, activeViewer)
                end
                if optionsPanel and optionsPanel._rebuildConfigUI then
                    optionsPanel:_rebuildConfigUI()
                else
                    RefreshOrderLabel()
                end
            end)

            downButton:SetScript("OnClick", function()
                local curCluster = tonumber(MyEssentialBuffTracker:GetSettings().clusterAssignments[keyStr]) or 1
                MoveKeyInEBTClusterOrder(MyEssentialBuffTracker:GetSettings(), curCluster, keyStr, 1)
                local activeViewer = _G["EssentialCooldownViewer"]
                if activeViewer then
                    pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, activeViewer)
                end
                if optionsPanel and optionsPanel._rebuildConfigUI then
                    optionsPanel:_rebuildConfigUI()
                else
                    RefreshOrderLabel()
                end
            end)

            y = y - 32
        end

        y = y - 16
        end -- multiClusterMode controls

        -- Insert per-row sliders inline, update y
        y = AddPerRowSliders(content, x1, y)

        -- COOLDOWN TEXT
        -- Only add Cooldown Text section label if not already present
        if not content._cdTitle then
            content._cdTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            content._cdTitle:SetPoint("TOPLEFT", x1, y)
            content._cdTitle:SetText("Cooldown Text")
            content._cdTitle:SetTextColor(0.9, 0.9, 0.9, 1)
        else
            content._cdTitle:ClearAllPoints()
            content._cdTitle:SetPoint("TOPLEFT", x1, y)
            content._cdTitle:Show()
        end
        y = y - 24

        local showCD = CreateCheckbox(content, "Show Cooldown Text", MyEssentialBuffTracker:GetSettings().showCooldownText,
            function(v)
                MyEssentialBuffTracker:GetSettings().showCooldownText = v
                local viewer = _G["EssentialCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
                end
            end)
        showCD:SetPoint("TOPLEFT", x1, y)
        y = y - 28

        local cdSize = CreateSlider(content, "Text Size", 1, 100, 1, MyEssentialBuffTracker:GetSettings().cooldownTextSize,
            function(v)
                MyEssentialBuffTracker:GetSettings().cooldownTextSize = v
                local viewer = _G["EssentialCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
                end
            end)
        cdSize:SetPoint("TOPLEFT", x1, y)

        local cdX = CreateSlider(content, "X Offset", -100, 100, 1, MyEssentialBuffTracker:GetSettings().cooldownTextX or 0,
            function(v)
                MyEssentialBuffTracker:GetSettings().cooldownTextX = v
                local viewer = _G["EssentialCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
                end
            end)
        cdX:SetPoint("TOPLEFT", x2, y)
        y = y - 46

        local cdY = CreateSlider(content, "Y Offset", -100, 100, 1, MyEssentialBuffTracker:GetSettings().cooldownTextY or 0,
            function(v)
                MyEssentialBuffTracker:GetSettings().cooldownTextY = v
                local viewer = _G["EssentialCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
                end
            end)
        cdY:SetPoint("TOPLEFT", x1, y)
        y = y - 30

        local positionOptions = {"CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}
        local cdPosition = CreateDropdown(content, "Position", positionOptions, MyEssentialBuffTracker:GetSettings().cooldownTextPosition or "CENTER",
            function(v)
                MyEssentialBuffTracker:GetSettings().cooldownTextPosition = v
                local viewer = _G["EssentialCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
                end
            end)
        cdPosition:SetPoint("TOPLEFT", x1, y)
        y = y - 40



        -- Charge/Count Text Size
        local chargeSize = CreateSlider(content, "Charge/Count Text Size", 1, 100, 1, MyEssentialBuffTracker:GetSettings().chargeTextSize or 14,
            function(v)
                MyEssentialBuffTracker:GetSettings().chargeTextSize = v
                local viewer = _G["EssentialCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
                end
            end)
        chargeSize:SetPoint("TOPLEFT", x2, y)
        y = y - 46


        local chargeX = CreateSlider(content, "X Offset", -100, 100, 1, MyEssentialBuffTracker:GetSettings().chargeTextX or 0,
            function(v)
                MyEssentialBuffTracker:GetSettings().chargeTextX = v
                local viewer = _G["EssentialCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
                end
            end)
        chargeX:SetPoint("TOPLEFT", x2, y)
        y = y - 46

        local chargeY = CreateSlider(content, "Y Offset", -100, 100, 1, MyEssentialBuffTracker:GetSettings().chargeTextY or 0,
            function(v)
                MyEssentialBuffTracker:GetSettings().chargeTextY = v
                local viewer = _G["EssentialCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
                end
            end)
        chargeY:SetPoint("TOPLEFT", x1, y)
        y = y - 46


        -- Add label above charge position dropdown only once
        if not content._chargePosLabel then
            content._chargePosLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            content._chargePosLabel:SetPoint("TOPLEFT", x1, y)
            content._chargePosLabel:SetText("Charge/Count Text Position")
            content._chargePosLabel:SetTextColor(0.9, 0.9, 0.9, 1)
            content._chargePosLabel:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
        else
            content._chargePosLabel:ClearAllPoints()
            content._chargePosLabel:SetPoint("TOPLEFT", x1, y)
            content._chargePosLabel:Show()
        end
        y = y - 20

        local chargePosition = CreateDropdown(content, "Position", positionOptions, MyEssentialBuffTracker:GetSettings().chargeTextPosition or "BOTTOMRIGHT",
            function(v)
                MyEssentialBuffTracker:GetSettings().chargeTextPosition = v
                local viewer = _G["EssentialCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(MyEssentialIconViewers.ApplyViewerLayout, MyEssentialIconViewers, viewer)
                end
            end)
        chargePosition:SetPoint("TOPLEFT", x1, y)
        y = y - 82

        -- =============================
        -- SPELL LIST WITH GLOW CONTROLS
        -- =============================
        local spellTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        spellTitle:SetPoint("TOPLEFT", x1, y)
        spellTitle:SetText("Spell Glow Settings")
        spellTitle:SetTextColor(0.9, 0.9, 0.9, 1)
        y = y - 24

        local spellNote = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        spellNote:SetPoint("TOPLEFT", x1, y)
        spellNote:SetText("Spells appear after they show in the viewer.")
        spellNote:SetTextColor(0.6, 0.6, 0.6, 1)
        y = y - 14

        local channelWarn = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        channelWarn:SetPoint("TOPLEFT", x1, y)
        channelWarn:SetText("WARNING: Do not assign glow to channeled spells!")
        channelWarn:SetTextColor(1, 0.2, 0.2, 1)

        local refreshBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        refreshBtn:SetSize(100, 20)
        refreshBtn:SetPoint("LEFT", spellNote, "RIGHT", 8, 0)
        refreshBtn:SetText("Refresh List")
        refreshBtn:SetScript("OnClick", function()
            if optionsPanel and optionsPanel._rebuildConfigUI then
                optionsPanel:_rebuildConfigUI()
            end
        end)
        y = y - 22

        local viewer = _G["EssentialCooldownViewer"]
        local spellItems = {}
        if viewer then
            local ok, result = pcall(CollectEssentialDisplayedItems, viewer)
            if ok and result then spellItems = result end
        end
        -- Also include any previously-glowed spells that are still shown
        local settings = MyEssentialBuffTracker:GetSettings()
        settings.spellGlows = settings.spellGlows or {}
        local addedKeys = {}
        for _, item in ipairs(spellItems) do addedKeys[item.key] = true end

        -- Sort by name
        table.sort(spellItems, function(a, b) return (a.name or "") < (b.name or "") end)

        for _, item in ipairs(spellItems) do
            local row = CreateFrame("Frame", nil, content)
            row:SetSize(500, 48)
            row:SetPoint("TOPLEFT", x1, y)

            -- Spell icon
            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(24, 24)
            icon:SetPoint("TOPLEFT", 0, 0)
            if item.icon then
                icon:SetTexture(item.icon)
            else
                icon:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")
            end

            -- Spell name
            local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameLabel:SetPoint("LEFT", icon, "RIGHT", 6, 0)
            nameLabel:SetText(item.name or item.key)
            nameLabel:SetTextColor(1, 1, 1, 1)
            nameLabel:SetWidth(200)
            nameLabel:SetJustifyH("LEFT")

            -- Glow controls (second line below icon)
            local glowCfg = settings.spellGlows[item.key] or { enabled = false, mode = "ready", glowType = "pixel", color = {r=1, g=1, b=0, a=1} }
            if not glowCfg.glowType then glowCfg.glowType = "pixel" end
            settings.spellGlows[item.key] = glowCfg

            -- Toggle button: Glow:ON / Glow:OFF
            local glowBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            glowBtn:SetSize(50, 18)
            glowBtn:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -2)
            glowBtn:SetText(glowCfg.enabled and "Glow:ON" or "Glow:OFF")
            glowBtn._spellKey = item.key
            glowBtn:SetScript("OnClick", function(self)
                local cfg = settings.spellGlows[self._spellKey]
                cfg.enabled = not cfg.enabled
                self:SetText(cfg.enabled and "Glow:ON" or "Glow:OFF")
            end)

            -- Glow type toggle: Pixel -> AutoCast -> Button -> Proc
            local glowTypeLabels = { pixel = "Pixel", autocast = "AutoCast", button = "Button", proc = "Proc" }
            local glowTypeOrder = { "pixel", "autocast", "button", "proc" }
            local typeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            typeBtn:SetSize(70, 18)
            typeBtn:SetPoint("LEFT", glowBtn, "RIGHT", 4, 0)
            typeBtn:SetText(glowTypeLabels[glowCfg.glowType] or "Pixel")
            typeBtn._spellKey = item.key
            typeBtn:SetScript("OnClick", function(self)
                local cfg = settings.spellGlows[self._spellKey]
                local cur = cfg.glowType or "pixel"
                local nextIdx = 1
                for i, v in ipairs(glowTypeOrder) do
                    if v == cur then nextIdx = i + 1; break end
                end
                if nextIdx > #glowTypeOrder then nextIdx = 1 end
                cfg.glowType = glowTypeOrder[nextIdx]
                self:SetText(glowTypeLabels[cfg.glowType] or "Pixel")
            end)

            -- Color swatch (plain textures, no BackdropTemplate)
            local colorSwatch = CreateFrame("Button", nil, row)
            colorSwatch:SetSize(18, 18)
            colorSwatch:SetPoint("LEFT", typeBtn, "RIGHT", 4, 0)
            local gc = glowCfg.color or {r=1, g=1, b=0, a=1}
            local swatchBorder = colorSwatch:CreateTexture(nil, "BACKGROUND")
            swatchBorder:SetAllPoints()
            swatchBorder:SetColorTexture(0.3, 0.3, 0.3, 1)
            local swatchBg = colorSwatch:CreateTexture(nil, "OVERLAY")
            swatchBg:SetPoint("TOPLEFT", 1, -1)
            swatchBg:SetPoint("BOTTOMRIGHT", -1, 1)
            swatchBg:SetColorTexture(gc.r, gc.g, gc.b, gc.a or 1)
            colorSwatch._swatchBg = swatchBg
            colorSwatch._spellKey = item.key
            colorSwatch:SetScript("OnClick", function(self)
                local cfg = settings.spellGlows[self._spellKey]
                local c = cfg.color or {r=1, g=1, b=0, a=1}
                local info = {}
                info.r, info.g, info.b = c.r, c.g, c.b
                info.opacity = c.a or 1
                info.hasOpacity = true
                info.swatchFunc = function()
                    local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                    local na = ColorPickerFrame:GetColorAlpha()
                    cfg.color = {r=nr, g=ng, b=nb, a=na}
                    self._swatchBg:SetColorTexture(nr, ng, nb, na)
                end
                info.opacityFunc = info.swatchFunc
                info.cancelFunc = function(prev)
                    cfg.color = {r=prev.r, g=prev.g, b=prev.b, a=prev.opacity or 1}
                    self._swatchBg:SetColorTexture(prev.r, prev.g, prev.b, prev.opacity or 1)
                end
                ColorPickerFrame:SetupColorPickerAndShow(info)
            end)

            y = y - 48
        end

        local finalHeight = math.max(2000, math.abs(y) + 100)
        C_Timer.After(0, function()
            pcall(content.SetSize, content, 530, finalHeight)
        end)

        -- OTHER (Lock Frame checkbox removed)
    end

    optionsPanel:_rebuildConfigUI()

    optionsPanel:HookScript("OnShow", function()
        if optionsPanel and optionsPanel._rebuildConfigUI then optionsPanel:_rebuildConfigUI() end
    end)

    -- Do not self-register; assign to global for parent registration
    _G.MyEssentialBuffTrackerPanel = optionsPanel
    return optionsPanel
end

-- Register the options panel on login

-- No direct registration here; handled by CkraigsOptions.lua



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
