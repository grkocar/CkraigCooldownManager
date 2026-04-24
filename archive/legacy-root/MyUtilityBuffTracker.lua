-- ======================================================
-- MyUtilityBuffTracker (Deterministic ordering, Aspect Ratio,
-- Multi-row center layout, Combat-safe skinning, EditMode safe)
-- Target: _G["UtilityCooldownViewer"]
-- ======================================================

-- SavedVariables
MyUtilityBuffTrackerDB = MyUtilityBuffTrackerDB or {}

local function SafeGetChildren(container) return { container:GetChildren() } end


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
    if viewer then
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

    -- Static Grid Mode
    staticGridMode = false,
    gridRows = 4,
    gridColumns = 4,
    gridSlotMap = {},

    -- Per-row icon sizes (optional override, otherwise uses iconSize)
    rowSizes = {},

    -- Per-spell glow settings
    spellGlows = {},
}

local LCG = LibStub("LibCustomGlow-1.0", true)

-- Reusable glow color array (avoids table allocation per icon per dispatch)
local ubtGlowColor = { 1, 1, 1, 1 }
local ubtProcOpts = { color = ubtGlowColor, key = "ubtGlow" }
local ubtEnabledGlowLookup = {}

local function StopGlow_UBT(icon)
    local gt = icon._ubtGlowType
    if gt == "autocast" then LCG.AutoCastGlow_Stop(icon, "ubtGlow")
    elseif gt == "button" then LCG.ButtonGlow_Stop(icon)
    elseif gt == "proc" then LCG.ProcGlow_Stop(icon, "ubtGlow")
    else LCG.PixelGlow_Stop(icon, "ubtGlow") end
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

    if MyUtilityBuffTrackerDB.staticGridMode == nil then MyUtilityBuffTrackerDB.staticGridMode = DEFAULTS.staticGridMode end
    if MyUtilityBuffTrackerDB.gridRows == nil then MyUtilityBuffTrackerDB.gridRows = DEFAULTS.gridRows end
    if MyUtilityBuffTrackerDB.gridColumns == nil then MyUtilityBuffTrackerDB.gridColumns = DEFAULTS.gridColumns end
    if MyUtilityBuffTrackerDB.gridSlotMap == nil then MyUtilityBuffTrackerDB.gridSlotMap = {} end

    -- Per-row sizes
    if MyUtilityBuffTrackerDB.rowSizes == nil then MyUtilityBuffTrackerDB.rowSizes = {} end

    -- Per-spell glows
    if MyUtilityBuffTrackerDB.spellGlows == nil then MyUtilityBuffTrackerDB.spellGlows = {} end
end

-- ---------------------------
-- Icon key identification for glow system
-- Uses ONLY direct frame fields (clean, never tainted) to avoid "table index is secret".
-- Resolves cooldownID → spellID through Blizzard's C_CooldownViewer API.
-- ---------------------------
local function GetUtilityIconKey(icon)
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
    hooksecurefunc(cd, "SetCooldown", function()
        icon._isOnCD = true
    end)
    hooksecurefunc(cd, "Clear", function()
        icon._isOnCD = false
    end)
    cd:HookScript("OnCooldownDone", function()
        icon._isOnCD = false
    end)
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

-- ---------------------------
-- ApplyViewerLayout (layout + skinning)
-- ---------------------------
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
        local okChildren, children = pcall(SafeGetChildren, container)
        if okChildren and children then
            for _, child in ipairs(children) do
                if child and (child.Icon or child.icon) then
                    table.insert(icons, child)
                end
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
    table.sort(icons, function(a,b)
        local aOrder = GetIconState(a).creationOrder
        local bOrder = GetIconState(b).creationOrder
        return (a.layoutIndex or a:GetID() or aOrder) < (b.layoutIndex or b:GetID() or bOrder)
    end)

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

    -- Event-driven refresh + glow system (show/hide dispatch — zero CPU when idle)
    if not viewerState.eventFrame then
        local ef = CreateFrame("Frame")
        ef:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        ef:RegisterEvent("UNIT_AURA")
        ef:RegisterEvent("PLAYER_REGEN_ENABLED")
        ef:Hide() -- starts hidden; zero CPU until an event fires
        ef._lastActiveCount = -1
        ef._lastRun = 0

        ef:SetScript("OnEvent", function(self, event, arg1)
            if event == "UNIT_AURA" and arg1 ~= "player" then return end
            self:Show()
        end)

        -- Show/hide dispatch with timestamp throttle (max ~10/sec, zero ticking)
        -- Layout only runs when active icon count changes.
        ef:SetScript("OnUpdate", function(self)
            self:Hide()
            local now = GetTime()
            if now - self._lastRun < 0.1 then return end
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
                    pcall(UtilityIconViewers.RescanViewer, UtilityIconViewers, viewer)
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

            -- Glow update
            if not LCG then return end
            local settings = MyUtilityBuffTracker:GetSettings()
            local spellGlows = settings and settings.spellGlows or {}
            -- Use Blizzard's itemFramePool (zero-allocation iterator)
            local pool = viewer.itemFramePool
            if not pool or pool:GetNumActive() == 0 then return end

            if not next(spellGlows) then
                for icon in pool:EnumerateActive() do
                    if icon._ubtGlowing then
                        StopGlow_UBT(icon)
                        icon._ubtGlowing = false
                        icon._ubtGlowType = nil
                    end
                end
                return
            end

            table_wipe(ubtEnabledGlowLookup)
            for skey, cfg in pairs(spellGlows) do
                if type(cfg) == "table" and cfg.enabled then
                    ubtEnabledGlowLookup[tostring(skey)] = cfg
                end
            end
            if not next(ubtEnabledGlowLookup) then
                for icon in pool:EnumerateActive() do
                    if icon._ubtGlowing then
                        StopGlow_UBT(icon)
                        icon._ubtGlowing = false
                        icon._ubtGlowType = nil
                    end
                end
                return
            end

            local inCombat = InCombatLockdown()
            for icon in pool:EnumerateActive() do
                if icon and (icon.Icon or icon.icon) then
                    HookCooldownTracking(icon)
                    if not inCombat then
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
                        local glowType = glowCfg and glowCfg.glowType or "pixel"
                        if shouldGlow then
                            if not icon._ubtGlowing or icon._ubtGlowType ~= glowType then
                                if icon._ubtGlowing then
                                    StopGlow_UBT(icon)
                                end
                                local c = glowCfg.color
                                ubtGlowColor[1] = c and c.r or 1
                                ubtGlowColor[2] = c and c.g or 1
                                ubtGlowColor[3] = c and c.b or 0
                                ubtGlowColor[4] = c and c.a or 1
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
                    elseif icon._ubtGlowing then
                        StopGlow_UBT(icon)
                        icon._ubtGlowing = false
                        icon._ubtGlowType = nil
                    end
                end
            end
        end)

        viewerState.eventFrame = ef
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
function MyUtilityBuffTracker:CreateOptionsPanel()
    EnsureDB()
    if optionsPanel then return optionsPanel end
    optionsPanel = CreateFrame("Frame", "MyUtilityBuffTrackerOptionsPanel", UIParent)
        -- Always refresh UI when panel is shown
        optionsPanel:SetScript("OnShow", function()
            if MyUtilityBuffTracker and MyUtilityBuffTracker.UpdateSettings then
                MyUtilityBuffTracker:UpdateSettings()
            end
        end)
    optionsPanel.name = "MyUtilityBuffTracker"
    optionsPanel:SetSize(550, 1100)
    local note = optionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    note:SetPoint("TOPRIGHT", optionsPanel, "TOPRIGHT", -24, -26)
    note:SetText("Drag  a slider and numbers will show or click through pages!")
    note:SetTextColor(0.2, 1, 0.2, 1)
    note:SetJustifyH("LEFT")

    local scrollFrame = CreateFrame("ScrollFrame", nil, optionsPanel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", 0, 0)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(530, 2000)
    scrollFrame:SetScrollChild(content)
    optionsPanel._content = content

    local function AddPerRowSliders(content, x1, y)
        if content._rowSizeWidgets then
            for _, w in ipairs(content._rowSizeWidgets) do if w then w:Hide() end end
        end
        content._rowSizeWidgets = {}
        local viewer = _G["UtilityCooldownViewer"]
        local numRows = 1
        if viewer then
            local lastNumRows = GetViewerMetric(viewer, "lastNumRows", 0)
            if lastNumRows > 0 then
                numRows = lastNumRows
            end
        end
        local rowSizeTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        rowSizeTitle:SetPoint("TOPLEFT", x1, y)
        rowSizeTitle:SetText("Row Icon Sizes")
        rowSizeTitle:SetTextColor(0.9, 0.9, 0.9, 1)
        y = y - 24
        table.insert(content._rowSizeWidgets, rowSizeTitle)
        for r = 1, numRows do
            local settings = MyUtilityBuffTracker:GetSettings()
            local current = (settings.rowSizes and settings.rowSizes[r]) or settings.iconSize
            local rowSlider = CreateSlider(content, "Row "..r.." Size", 1, 200, 1, current,
                function(v)
                    local settings = MyUtilityBuffTracker:GetSettings()
                    settings.rowSizes[r] = v
                    local viewer = _G["UtilityCooldownViewer"]
                    if viewer then
                        ForceReskinViewer(viewer)
                        pcall(UtilityIconViewers.ApplyViewerLayout, UtilityIconViewers, viewer)
                        if optionsPanel and optionsPanel._rebuildConfigUI then optionsPanel:_rebuildConfigUI() end
                    end
                end)
            rowSlider:SetPoint("TOPLEFT", x1, y)
            y = y - 46
            table.insert(content._rowSizeWidgets, rowSlider)
        end
        return y
    end

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
        title:SetText("MyUtilityBuffTracker")
        title:SetTextColor(1, 1, 1, 1)

        -- After all controls are created, force OnShow for all children to update input/valueText
        C_Timer.After(0, function()
            for _, child in ipairs({content:GetChildren()}) do
                if child.Show then child:Show() end
            end
        end)

        -- Profile selector
        if CkraigProfileManager and CkraigProfileManager.db then
            local profileLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            profileLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -30)
            profileLabel:SetText("Profile:")
            profileLabel:SetTextColor(0.85, 0.85, 0.85, 1)
            local profileDropdown = CreateFrame("DropdownButton", "MyUtilityBuffTrackerProfileDropdown", content, "WowStyle1DropdownTemplate")
            profileDropdown:SetPoint("TOPLEFT", profileLabel, "BOTTOMLEFT", 0, -4)
            profileDropdown:SetSize(140, 26)
            profileDropdown:SetupMenu(function(dd, rootDescription)
                if not CkraigProfileManager or not CkraigProfileManager.db then return end
                local profiles = CkraigProfileManager.db:GetProfiles()
                for _, name in ipairs(profiles) do
                    rootDescription:CreateRadio(
                        name,
                        function(v) return v == CkraigProfileManager.db:GetCurrentProfile() end,
                        function(v) CkraigProfileManager.db:SetProfile(v) end,
                        name
                    )
                end
            end)
        end

        local x1, x2 = 20, 290
        local y = -80
        local iconTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        iconTitle:SetPoint("TOPLEFT", x1, y)
        iconTitle:SetText("Icon Settings")
        iconTitle:SetTextColor(0.9, 0.9, 0.9, 1)
        y = y - 24
        local settings = MyUtilityBuffTracker:GetSettings()
        local iconSizeSlider = CreateSlider(content, "Icon Size", 8, 128, 1, settings.iconSize,
            function(v)
                local settings = MyUtilityBuffTracker:GetSettings()
                settings.iconSize = v
                local viewer = _G["UtilityCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(UtilityIconViewers.ApplyViewerLayout, UtilityIconViewers, viewer)
                    if optionsPanel and optionsPanel._rebuildConfigUI then optionsPanel:_rebuildConfigUI() end
                end
            end)
        iconSizeSlider:SetPoint("TOPLEFT", x1, y)

        -- Cooldown Text Size Slider
        y = y - 46
        local cooldownTextSizeSlider = CreateSlider(content, "Cooldown Text Size", 8, 36, 1, settings.cooldownTextSize or 16,
            function(v)
                local settings = MyUtilityBuffTracker:GetSettings()
                settings.cooldownTextSize = v
                -- Live update: re-apply layout to update all cooldown text sizes
                local viewer = _G["UtilityCooldownViewer"]
                if viewer then
                    pcall(UtilityIconViewers.ApplyViewerLayout, UtilityIconViewers, viewer)
                end
            end)
        cooldownTextSizeSlider:SetPoint("TOPLEFT", x1, y)
        local aspectRatioSlider = CreateSlider(content, "Aspect Ratio", 0.1, 5.0, 0.01, settings.aspectRatioCrop or 1.0,
            function(v)
                local settings = MyUtilityBuffTracker:GetSettings()
                settings.aspectRatioCrop = v
                local viewer = _G["UtilityCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(UtilityIconViewers.ApplyViewerLayout, UtilityIconViewers, viewer)
                    if optionsPanel and optionsPanel._rebuildConfigUI then optionsPanel:_rebuildConfigUI() end
                end
            end)
        aspectRatioSlider:SetPoint("TOPLEFT", x2, y)
        y = y - 46
        local cornerRadius = CreateSlider(content, "Corner Radius", 0, 20, 1, settings.iconCornerRadius or 0,
            function(v)
                local settings = MyUtilityBuffTracker:GetSettings()
                settings.iconCornerRadius = v
                local viewer = _G["UtilityCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(UtilityIconViewers.ApplyViewerLayout, UtilityIconViewers, viewer)
                end
            end)
        cornerRadius:SetPoint("TOPLEFT", x1, y)
        y = y - 52
        local spaceTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        spaceTitle:SetPoint("TOPLEFT", x1, y)
        spaceTitle:SetText("Spacing & Layout")
        spaceTitle:SetTextColor(0.9, 0.9, 0.9, 1)
        y = y - 24
        local hSpace = CreateSlider(content, "Horizontal Spacing", 0, 40, 1, settings.spacing,
            function(v)
                local settings = MyUtilityBuffTracker:GetSettings()
                settings.spacing = v
                local viewer = _G["UtilityCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(UtilityIconViewers.ApplyViewerLayout, UtilityIconViewers, viewer)
                    if optionsPanel and optionsPanel._rebuildConfigUI then optionsPanel:_rebuildConfigUI() end
                end
            end)
        hSpace:SetPoint("TOPLEFT", x1, y)
        local vSpace = CreateSlider(content, "Vertical Spacing", 0, 40, 1, settings.spacing,
            function(v)
                local settings = MyUtilityBuffTracker:GetSettings()
                settings.spacing = v
                local viewer = _G["UtilityCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(UtilityIconViewers.ApplyViewerLayout, UtilityIconViewers, viewer)
                    if optionsPanel and optionsPanel._rebuildConfigUI then optionsPanel:_rebuildConfigUI() end
                end
            end)
        vSpace:SetPoint("TOPLEFT", x2, y)
        y = y - 46
        local perRow = CreateSlider(content, "Icons Per Row", 1, 50, 1, settings.columns,
            function(v)
                local settings = MyUtilityBuffTracker:GetSettings()
                settings.columns = v; settings.rowLimit = v
                local viewer = _G["UtilityCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(UtilityIconViewers.ApplyViewerLayout, UtilityIconViewers, viewer)
                    if optionsPanel and optionsPanel._rebuildConfigUI then optionsPanel:_rebuildConfigUI() end
                end
            end)
        perRow:SetPoint("TOPLEFT", x1, y)
        y = y - 52

        -- Charge/Stack Text Position Options
        local chargeTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        chargeTitle:SetPoint("TOPLEFT", x1, y)
        chargeTitle:SetText("Charge/Stack Text Position")
        chargeTitle:SetTextColor(0.9, 0.9, 0.9, 1)
        y = y - 24

        -- Charge/Stack Text Size Slider
        local chargeSize = CreateSlider(content, "Charge/Stack Text Size", 1, 100, 1, settings.chargeTextSize or 14,
            function(v)
                local settings = MyUtilityBuffTracker:GetSettings()
                settings.chargeTextSize = v
                local viewer = _G["UtilityCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(UtilityIconViewers.ApplyViewerLayout, UtilityIconViewers, viewer)
                end
            end)
        chargeSize:SetPoint("TOPLEFT", x2, y)
        y = y - 46

        local positionOptions = {"CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}
        local chargePosition = CreateDropdown(content, "Position", positionOptions, settings.chargeTextPosition or "BOTTOMRIGHT",
            function(v)
                local settings = MyUtilityBuffTracker:GetSettings()
                settings.chargeTextPosition = v
                local viewer = _G["UtilityCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(UtilityIconViewers.ApplyViewerLayout, UtilityIconViewers, viewer)
                end
            end)
        chargePosition:SetPoint("TOPLEFT", x1, y)
        y = y - 52

        local chargeX = CreateSlider(content, "X Offset", -100, 100, 1, settings.chargeTextX or 0,
            function(v)
                local settings = MyUtilityBuffTracker:GetSettings()
                settings.chargeTextX = v
                local viewer = _G["UtilityCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(UtilityIconViewers.ApplyViewerLayout, UtilityIconViewers, viewer)
                end
            end)
        chargeX:SetPoint("TOPLEFT", x2, y)
        y = y - 46

        local chargeY = CreateSlider(content, "Y Offset", -100, 100, 1, settings.chargeTextY or 0,
            function(v)
                local settings = MyUtilityBuffTracker:GetSettings()
                settings.chargeTextY = v
                local viewer = _G["UtilityCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(UtilityIconViewers.ApplyViewerLayout, UtilityIconViewers, viewer)
                end
            end)
        chargeY:SetPoint("TOPLEFT", x1, y)
        y = y - 46

        y = AddPerRowSliders(content, x1, y)
        -- ENABLE VIEWER OPTION
        local enableCheck = CreateCheck(content, "Enable Utility Tracker", settings.enabled ~= false,
            function(v)
                local settings = MyUtilityBuffTracker:GetSettings()
                settings.enabled = v
                ReloadUI()
            end)
        enableCheck:SetPoint("TOPLEFT", x1, y)
        y = y - 28

        -- HIDE WHEN MOUNTED OPTION
        local hideMount = CreateCheck(content, "Hide when mounted", settings.hideWhenMounted,
            function(v)
                local settings = MyUtilityBuffTracker:GetSettings()
                settings.hideWhenMounted = v
                if v then
                    mountEventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
                else
                    mountEventFrame:UnregisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
                end
                UpdateCooldownManagerVisibility()
            end)
        hideMount:SetPoint("TOPLEFT", x1, y)
        y = y - 28

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

        local viewer = _G["UtilityCooldownViewer"]
        local spellItems = {}
        if viewer then
            local ok, result = pcall(CollectUtilityDisplayedItems, viewer)
            if ok and result then spellItems = result end
        end
        local settings = MyUtilityBuffTracker:GetSettings()
        settings.spellGlows = settings.spellGlows or {}
        local addedKeys = {}
        for _, item in ipairs(spellItems) do addedKeys[item.key] = true end

        table.sort(spellItems, function(a, b) return (a.name or "") < (b.name or "") end)

        local modeLabels = { ready = "On Ready", cooldown = "On Cooldown" }

        for _, item in ipairs(spellItems) do
            local row = CreateFrame("Frame", nil, content)
            row:SetSize(500, 48)
            row:SetPoint("TOPLEFT", x1, y)

            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(24, 24)
            icon:SetPoint("TOPLEFT", 0, 0)
            if item.icon then
                icon:SetTexture(item.icon)
            else
                icon:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")
            end

            local nameLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameLabel:SetPoint("LEFT", icon, "RIGHT", 6, 0)
            nameLabel:SetText(item.name or item.key)
            nameLabel:SetTextColor(1, 1, 1, 1)
            nameLabel:SetWidth(200)
            nameLabel:SetJustifyH("LEFT")

            local glowCfg = settings.spellGlows[item.key] or { enabled = false, mode = "ready", glowType = "pixel", color = {r=1, g=1, b=0, a=1} }
            if not glowCfg.glowType then glowCfg.glowType = "pixel" end
            settings.spellGlows[item.key] = glowCfg

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

            local modeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            modeBtn:SetSize(90, 18)
            modeBtn:SetPoint("LEFT", glowBtn, "RIGHT", 4, 0)
            modeBtn:SetText(modeLabels[glowCfg.mode] or "On Ready")
            modeBtn._spellKey = item.key
            modeBtn:SetScript("OnClick", function(self)
                local cfg = settings.spellGlows[self._spellKey]
                if cfg.mode == "ready" then
                    cfg.mode = "cooldown"
                else
                    cfg.mode = "ready"
                end
                self:SetText(modeLabels[cfg.mode] or "On Ready")
            end)

            local glowTypeLabels = { pixel = "Pixel", autocast = "AutoCast", button = "Button", proc = "Proc" }
            local glowTypeOrder = { "pixel", "autocast", "button", "proc" }
            local typeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            typeBtn:SetSize(70, 18)
            typeBtn:SetPoint("LEFT", modeBtn, "RIGHT", 4, 0)
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

        -- Lock Frame checkbox removed
    end
    optionsPanel:_rebuildConfigUI()
    optionsPanel:HookScript("OnShow", function()
        if optionsPanel and optionsPanel._rebuildConfigUI then optionsPanel:_rebuildConfigUI() end
    end)
    -- Do not self-register; assign to global for parent registration
    _G.MyUtilityBuffTrackerPanel = optionsPanel
    return optionsPanel
end


-- No direct registration here; handled by CkraigsOptions.lua

-- Gate all background processing behind enabled state at login
local utilityEnableGate = CreateFrame("Frame")
utilityEnableGate:RegisterEvent("PLAYER_LOGIN")
utilityEnableGate:SetScript("OnEvent", function()
    local settings = MyUtilityBuffTracker:GetSettings()
    if settings and settings.enabled ~= false then
        -- Register mount visibility events (mount event only if hideWhenMounted is on)
        mountEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        if settings.hideWhenMounted then
            mountEventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
        end
        -- Hook the viewer (ticker + layout hooks)
        HookViewer()
        -- If viewer isn't created yet, hook when it appears
        hookFrame:RegisterEvent("ADDON_LOADED")
    end
end)
