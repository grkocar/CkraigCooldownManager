

-- Hide Cooldown Manager when mounted

-- Mount hide/show option
local function IsPlayerMounted()
    return IsMounted and IsMounted()
end

local function SafeGetChildren(container) return { container:GetChildren() } end


local function UpdateCooldownManagerVisibility()
    local viewer = _G["BuffIconCooldownViewer"]
    if viewer then
        if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
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
mountEventFrame:SetScript("OnEvent", function(self, event)
    UpdateCooldownManagerVisibility()
    -- On initial login, only listen for mount changes when hideWhenMounted is on
    if event == "PLAYER_ENTERING_WORLD" then
        local s = DYNAMICICONS and DYNAMICICONS.GetSettings and DYNAMICICONS:GetSettings()
        if s and s.hideWhenMounted then
            self:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
        end
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
    clusterSampleDisplayModes = {},
    clusterAlwaysShowSpells = {},
    clusterAssignments = {},
    clusterPositions = {},
    clusterManualOrders = {},
    clusterCenterIcons = true,
    -- Duplicate spells across clusters: clusterDuplicates[key] = { [clusterIndex] = true, ... }
    clusterDuplicates = {},
    -- Per-spell glows: spellGlows[key] = { enabled, mode, glowType, color }
    spellGlows = {},
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

-- Reusable glow color array (avoids table allocation per icon per dispatch)
local diGlowColor = { 1, 1, 1, 1 }

-- Forward declarations for glow functions (bodies defined after all dependencies)
local StopGlow_DI, StartGlow_DI, IsSpellOnCooldown_DI, DispatchGlows_DI, EnsureGlowDispatchRunning

-- Periodic glow re-evaluation frame (calls forward-declared DispatchGlows_DI)
local _di_glowDispatchFrame = CreateFrame("Frame")
_di_glowDispatchFrame:Hide()
local _di_glowLastUpdate = 0
_di_glowDispatchFrame:SetScript("OnUpdate", function(self, elapsed)
    _di_glowLastUpdate = _di_glowLastUpdate + elapsed
    if _di_glowLastUpdate < 0.5 then return end
    _di_glowLastUpdate = 0
    local viewer = _G["BuffIconCooldownViewer"]
    if not viewer or not viewer:IsShown() then return end
    local settings = DYNAMICICONS:GetSettings()
    if not settings then return end
    DispatchGlows_DI(viewer, settings)
end)

local _di_pcall_unit, _di_pcall_auraID
local function _di_checkAuraDuration()
    local d = C_UnitAuras.GetAuraDataByAuraInstanceID(_di_pcall_unit, _di_pcall_auraID)
    return d and d.duration and d.duration > 0
end

-- Hoisted ProcGlow options table (reused every dispatch, avoids allocation)
local _di_procGlowOpts = { color = diGlowColor, key = "diGlow" }

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
    if settings.clusterSampleDisplayModes == nil then settings.clusterSampleDisplayModes = {} end
    if settings.clusterAlwaysShowSpells == nil then settings.clusterAlwaysShowSpells = {} end
    if settings.clusterAssignments == nil then settings.clusterAssignments = {} end
    if settings.clusterPositions == nil then settings.clusterPositions = {} end
    if settings.clusterManualOrders == nil then settings.clusterManualOrders = {} end
    if settings.clusterCenterIcons == nil then settings.clusterCenterIcons = DEFAULTS.clusterCenterIcons end
    if settings.clusterDuplicates == nil then settings.clusterDuplicates = {} end
    if settings.spellGlows == nil then settings.spellGlows = {} end
    -- Sanitize corrupted spellGlows entries (boolean instead of table)
    for k, v in pairs(settings.spellGlows) do
        if type(v) ~= "table" then
            settings.spellGlows[k] = { enabled = (v == true), mode = "ready", glowType = "pixel", color = {r=1, g=1, b=0, a=1} }
        end
    end
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

local function GetIconCooldownKey(icon)
    if not icon then return nil end

    local cooldownID = nil
    if icon.GetCooldownID then
        local ok, value = pcall(icon.GetCooldownID, icon)
        if ok then cooldownID = value end
    end

    if cooldownID == nil and icon.GetSpellID then
        local ok, value = pcall(icon.GetSpellID, icon)
        if ok then cooldownID = value end
    end

    if cooldownID == nil and icon.GetCooldownInfo then
        local okInfo, cooldownInfo = pcall(icon.GetCooldownInfo, icon)
        if okInfo and cooldownInfo then
            cooldownID = cooldownInfo.cooldownID or cooldownInfo.spellID
        end
    end

    if cooldownID == nil and icon.GetAuraSpellID then
        local ok, value = pcall(icon.GetAuraSpellID, icon)
        if ok then cooldownID = value end
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
            local candidateSpellIDs = GetCandidateSpellIDsFromCooldownInfo(cooldownInfo)

            for _, spellID in ipairs(candidateSpellIDs) do
                if C_Spell and C_Spell.GetSpellName and not name then
                    name = C_Spell.GetSpellName(spellID)
                end
                if C_Spell and C_Spell.GetSpellTexture and not iconTexture then
                    iconTexture = C_Spell.GetSpellTexture(spellID)
                end
                if name and iconTexture then
                    break
                end
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
            if child and (child.Icon or child.icon) then
                local iconTexture = nil
                local childIcon = child.Icon or child.icon
                if childIcon and childIcon.GetTexture then
                    iconTexture = childIcon:GetTexture()
                end
                local key = child.GetCooldownID and child:GetCooldownID()
                AddItemByKey(key or GetIconCooldownKey(child), nil, iconTexture)
            end
        end
    else
        local container = viewer.viewerFrame or viewer
        local okChildren, children = pcall(SafeGetChildren, container)
        if okChildren and children then
            for _, child in ipairs(children) do
                if child and (child.Icon or child.icon) then
                    local iconTexture = nil
                    local childIcon = child.Icon or child.icon
                    if childIcon and childIcon.GetTexture then
                        local okTex, tex = pcall(childIcon.GetTexture, childIcon)
                        if okTex then iconTexture = tex end
                    end

                    AddItemByKey(GetIconCooldownKey(child), nil, iconTexture)
                end
            end
        end
    end

    if viewer.GetCooldownIDs then
        local okIDs, cooldownIDs = pcall(viewer.GetCooldownIDs, viewer)
        if okIDs and cooldownIDs then
            for _, cooldownID in ipairs(cooldownIDs) do
                AddItemByKey(cooldownID)
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
    if cooldownInfo then
        local candidates = GetCandidateSpellIDsFromCooldownInfo(cooldownInfo)
        if #candidates > 0 then
            return candidates[1]
        end
    end

    return numericKey
end

local function IsSpellKnownForPlayer(spellID)
    if not spellID then
        return false
    end

    if IsSpellKnownOrOverridesKnown then
        local okKnown, isKnown = pcall(IsSpellKnownOrOverridesKnown, spellID)
        if okKnown and isKnown then
            return true
        end
    end

    if IsPlayerSpell then
        local okPlayerSpell, isPlayerSpell = pcall(IsPlayerSpell, spellID)
        if okPlayerSpell and isPlayerSpell then
            return true
        end
    end

    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local okBookKnown, isBookKnown = pcall(C_SpellBook.IsSpellKnown, spellID)
        if okBookKnown and isBookKnown then
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

local function BuildAvailableCooldownKeySet(viewer)
    local available = {}
    if not viewer then
        return available
    end

    local function AddIfUsable(rawKey)
        local normalizedKey = NormalizeCooldownKey(rawKey)
        if not normalizedKey then
            return
        end

        if tonumber(normalizedKey) and not IsCooldownKeyKnownForPlayer(normalizedKey) then
            return
        end

        available[tostring(normalizedKey)] = true
    end

    if viewer.GetCooldownIDs then
        local okIDs, cooldownIDs = pcall(viewer.GetCooldownIDs, viewer)
        if okIDs and cooldownIDs then
            for _, cooldownID in ipairs(cooldownIDs) do
                AddIfUsable(cooldownID)
            end
        end
    end

    local container = viewer.viewerFrame or viewer
    local okChildren, children = pcall(SafeGetChildren, container)
    if okChildren and children then
        for _, child in ipairs(children) do
            if child and (child.Icon or child.icon) then
                local key = GetIconCooldownKey(child)
                AddIfUsable(key)
            end
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

local function BuildDisplayedItemsForOptions(viewer, settings)
    UpsertKnownDisplayedItems(viewer)
    local availableKeys = BuildAvailableCooldownKeySet(viewer)

    local items = {}
    local added = {}

    for key, item in pairs(KnownDisplayedItemsByKey) do
        if key and item and availableKeys[tostring(key)] then
            table.insert(items, {
                key = key,
                name = item.name or ("CDID " .. tostring(key)),
                icon = item.icon,
            })
            added[key] = true
        end
    end

    settings = settings or DYNAMICICONS:GetSettings()
    settings.clusterAssignments = settings.clusterAssignments or {}
    for key in pairs(settings.clusterAssignments) do
        key = tostring(key)
        if availableKeys[key] and not added[key] then
            local spellID = tonumber(key)
            local name = nil
            local icon = nil
            if spellID and C_Spell and C_Spell.GetSpellName then
                name = C_Spell.GetSpellName(spellID)
            end
            if spellID and C_Spell and C_Spell.GetSpellTexture then
                icon = C_Spell.GetSpellTexture(spellID)
            end
            table.insert(items, {
                key = key,
                name = name or ("CDID " .. key),
                icon = icon,
            })
            if icon then
                SampleIconTextureCache[key] = icon
            end
            added[key] = true
        end
    end

    SortCooldownItems(items)
    return items
end

DYNAMICICONS = DYNAMICICONS or {}

-- ===============================
-- CPU Optimization: Event-driven batching, dirty flags, strict throttling, combat-only updates
-- ===============================
local _di_dirty = false
local _di_batchFrame = CreateFrame("Frame")
_di_batchFrame:Hide()
local _di_lastUpdate = 0
local _di_throttle = 0.03 -- seconds

local function IsInCombat() return InCombatLockdown() end

local function MarkDynamicIconsDirty(reason)
    _di_dirty = true
    _di_batchFrame:Show()
end

local function UpdateDynamicIconsBatch()
    if not _di_dirty then _di_batchFrame:Hide(); return end
    _di_dirty = false
    _di_batchFrame:Hide()
    local viewer = _G["BuffIconCooldownViewer"]
    if not viewer or not viewer:IsShown() then return end
    if BuffIconViewers and BuffIconViewers.ApplyViewerLayout then
        pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, viewer)
    end
end

_di_batchFrame:SetScript("OnUpdate", function(self, elapsed)
    _di_lastUpdate = _di_lastUpdate + elapsed
    if _di_lastUpdate >= _di_throttle then
        _di_lastUpdate = 0
        UpdateDynamicIconsBatch()
    end
end)

-- Hook combat state events to manage batch frame lifecycle
local function SetupDynamicIconsEventHooks()
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("PLAYER_REGEN_DISABLED")
    ef:RegisterEvent("PLAYER_REGEN_ENABLED")
    ef:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_REGEN_DISABLED" then
            -- Entering combat: flush any pending dirty state
            if _di_dirty then _di_batchFrame:Show() end
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- Leaving combat: flush pending updates instead of discarding
            if _di_dirty then _di_batchFrame:Show() end
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

function DYNAMICICONS:GetDisplayedItemsForOptions()
    local viewer = _G["BuffIconCooldownViewer"]
    local settings = self:GetSettings()
    local ok, items = pcall(BuildDisplayedItemsForOptions, viewer, settings)
    if ok and type(items) == "table" then
        return items
    end
    return {}
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

local function GetSampleTextureForKey(key)
    if not key then
        return "Interface\\ICONS\\INV_Misc_QuestionMark"
    end

    local cached = SampleIconTextureCache[key]
    if cached and cached ~= "" then
        return cached
    end

    local spellID = tonumber(key)
    if spellID and C_Spell and C_Spell.GetSpellTexture then
        local texture = C_Spell.GetSpellTexture(spellID)
        if texture and texture ~= "" then
            SampleIconTextureCache[key] = texture
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
            local mode = string.lower(tostring((settings.clusterSampleDisplayModes and settings.clusterSampleDisplayModes[groupIndex]) or "off"))
            local showSamples = unlockPreview or mode == "always"

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

                local groupWidth = columns * clusterIconSize + (columns - 1) * spacing
                local groupHeight = rows * clusterIconSize + (rows - 1) * spacing

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
                        local x = 5 + (clusterIconSize / 2) + colIndex * (clusterIconSize + spacing)
                        local y
                        if verticalPin == "center" or verticalGrow == "up" then
                            y = yBase + rowIndex * (clusterIconSize + spacing)
                        else
                            y = yBase - rowIndex * (clusterIconSize + spacing)
                        end
                        texture:SetPoint("CENTER", anchor, "BOTTOMLEFT", x, y)
                    else
                        if centerClusterIcons then
                            local x = -groupWidth / 2 + clusterIconSize / 2 + colIndex * (clusterIconSize + spacing)
                            local y = groupHeight / 2 - clusterIconSize / 2 - rowIndex * (clusterIconSize + spacing)
                            texture:SetPoint("CENTER", anchor, "CENTER", x, y)
                        else
                            local x = 5 + (clusterIconSize / 2) + colIndex * (clusterIconSize + spacing)
                            local y = (anchorHeight - 5) - (clusterIconSize / 2) - rowIndex * (clusterIconSize + spacing)
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

local function EnsureClusterAnchorForIndex(viewer, settings, index)
    local viewerState = GetViewerState(viewer)
    viewerState.clusterAnchors = viewerState.clusterAnchors or {}
    local anchors = viewerState.clusterAnchors

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

    local saved = settings.clusterPositions and settings.clusterPositions[index]
    local fallback = GetDefaultClusterPosition(index)
    local point = (saved and saved.point) or fallback.point
    local relPoint = (saved and saved.relPoint) or point
    local x = (saved and saved.x) or fallback.x
    local y = (saved and saved.y) or fallback.y
    anchor:ClearAllPoints()
    anchor:SetPoint(point, UIParent, relPoint, x, y)
    anchor:Hide()

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
    local spellID = tonumber(frame._spellKey)
    if not spellID then
        frame.Cooldown:Clear(); frame:SetAlpha(0.5); return
    end
    -- Hook Cooldown to capture values for duplicates
    HookSourceIconForDuplicates(frame)
    -- Use durationObject API (secret-safe, no pcall needed)
    local durObj = C_Spell and C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(spellID)
    local cdInfo = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
    if durObj and cdInfo and cdInfo.isOnGCD ~= true then
        frame.Cooldown:SetCooldownFromDurationObject(durObj)
        frame:SetAlpha(1.0)
    else
        frame.Cooldown:Clear()
        frame:SetAlpha(0.5)
    end
end

-- Persistent + duplicate icon update (event-driven, zero CPU when idle)
_di_persistentUpdateFrame = CreateFrame("Frame")
_di_persistentUpdateFrame:Hide()
_di_persistentUpdateFrame._lastRun = 0
-- Event registration deferred until persistent icons are created (avoids idle CPU)
_di_persistentUpdateFrame:SetScript("OnEvent", function(self)
    self:Show()
end)
_di_persistentUpdateFrame:SetScript("OnUpdate", function(self)
    self:Hide()
    local now = GetTime()
    if now - self._lastRun < 0.3 then return end
    self._lastRun = now
    for _, frame in pairs(_di_persistentIcons) do
        if frame:IsShown() then
            UpdatePersistentIconCooldown(frame)
        end
    end
    for _, frame in pairs(_di_duplicateIcons) do
        if frame:IsShown() then
            local src = frame._sourceIcon
            if src and frame.Cooldown then
                local cdStart = src._ccm_cdStart
                local cdDur   = src._ccm_cdDur
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
                -- Mirror texture captured by our hook
                local hookedTex = src._ccm_iconTexture
                if hookedTex and frame.Icon then
                    frame.Icon:SetTexture(hookedTex)
                end
            else
                UpdatePersistentIconCooldown(frame)
            end
        end
    end
end)

local function HideAllPersistentIcons()
    for _, frame in pairs(_di_persistentIcons) do
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
    -- Hook the Cooldown widget's SetCooldown
    local cd = sourceIcon.Cooldown
    if cd and not _ccm_hookedCooldowns[cd] then
        _ccm_hookedCooldowns[cd] = true
        hooksecurefunc(cd, "SetCooldown", function(_self, start, duration)
            sourceIcon._ccm_cdStart = start
            sourceIcon._ccm_cdDur   = duration
        end)
        if cd.SetCooldownFromDurationObject then
            hooksecurefunc(cd, "SetCooldownFromDurationObject", function(_self, durObj)
                sourceIcon._ccm_cdDurObj = durObj
            end)
        end
        hooksecurefunc(cd, "Clear", function()
            sourceIcon._ccm_cdStart = 0
            sourceIcon._ccm_cdDur   = 0
            sourceIcon._ccm_cdDurObj = nil
        end)
    end
    -- Hook the Icon texture's SetTexture
    local iconTex = sourceIcon.Icon or sourceIcon.icon
    if iconTex and iconTex.SetTexture and not sourceIcon._ccm_hookedTexture then
        sourceIcon._ccm_hookedTexture = true
        hooksecurefunc(iconTex, "SetTexture", function(_self, tex)
            sourceIcon._ccm_iconTexture = tex
        end)
        -- Capture current texture right away
        pcall(function()
            local t = iconTex:GetTexture()
            if t then sourceIcon._ccm_iconTexture = t end
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

-- ===========================
-- Glow function bodies (all dependencies now in scope)
-- ===========================
StopGlow_DI = function(icon)
    if not LCG then return end
    local state = IconRuntimeState[icon]
    if not state or not state.glowActive then return end
    local gt = state.glowType
    if gt == "autocast" then LCG.AutoCastGlow_Stop(icon, "diGlow")
    elseif gt == "button" then LCG.ButtonGlow_Stop(icon)
    elseif gt == "proc" then LCG.ProcGlow_Stop(icon, "diGlow")
    else LCG.PixelGlow_Stop(icon, "diGlow") end
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
    state.glowType = glowType
    state.glowActive = true
    local c = color or {r=1, g=1, b=0, a=1}
    local thisColor = {c.r or 1, c.g or 1, c.b or 0, c.a or 1}
    if glowType == "autocast" then
        LCG.AutoCastGlow_Start(icon, thisColor, 10, 0.25, 1, -1, -1, "diGlow")
    elseif glowType == "button" then
        LCG.ButtonGlow_Start(icon, thisColor, 0.125)
    elseif glowType == "proc" then
        local opts = { color = thisColor, key = "diGlow" }
        LCG.ProcGlow_Start(icon, opts)
    else
        LCG.PixelGlow_Start(icon, thisColor, 5, 0.25, 2, 1, -1, -1, false, "diGlow")
    end
end

IsSpellOnCooldown_DI = function(icon)
    -- tostring() then tonumber() strips WoW secret-number taint
    local dur = icon and icon._ccm_cdDur
    dur = dur and tonumber(tostring(dur))
    return dur and dur > 1.5
end

DispatchGlows_DI = function(viewer, settings)
    if not LCG or not viewer or not settings then return end
    local spellGlows = settings.spellGlows
    if not spellGlows then return end

    local pool = viewer.itemFramePool
    local icons
    if pool then
        icons = {}
        for child in pool:EnumerateActive() do
            if child and (child.Icon or child.icon) then
                icons[#icons + 1] = child
            end
        end
    end

    -- Also check persistent and duplicate icons
    local allIcons = icons or {}
    for _, frame in pairs(_di_persistentIcons) do
        if frame:IsShown() then allIcons[#allIcons + 1] = frame end
    end
    for _, frame in pairs(_di_duplicateIcons) do
        if frame:IsShown() then allIcons[#allIcons + 1] = frame end
    end

    for _, icon in ipairs(allIcons) do
        HookSourceIconForDuplicates(icon)
        local key = GetIconCooldownKey(icon)
        if key then
            local cfg = spellGlows[key]
            if cfg and type(cfg) == "table" and cfg.enabled then
                local onCooldown = IsSpellOnCooldown_DI(icon)
                local shouldGlow = false
                if cfg.mode == "cooldown" then
                    shouldGlow = onCooldown == true
                else
                    shouldGlow = not onCooldown
                end
                if shouldGlow then
                    -- Always fetch the latest color from config
                    local color = cfg.color or {r=1, g=1, b=0, a=1}
                    StartGlow_DI(icon, cfg.glowType or "pixel", color)
                else
                    local state = IconRuntimeState[icon]
                    if state and state.glowActive then
                        StopGlow_DI(icon)
                        state.glowActive = nil
                    end
                end
            else
                local state = IconRuntimeState[icon]
                if state and state.glowActive then
                    StopGlow_DI(icon)
                    state.glowActive = nil
                end
            end
        end
    end
end

EnsureGlowDispatchRunning = function(settings)
    if not settings or not settings.spellGlows then return end
    for _, cfg in pairs(settings.spellGlows) do
        if type(cfg) == "table" and cfg.enabled then
            _di_glowDispatchFrame:Show()
            return
        end
    end
    _di_glowDispatchFrame:Hide()
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
    table.insert(menuList, { text = "Always Show Spells:", isTitle = true, notCheckable = true })

    settings.clusterAlwaysShowSpells = settings.clusterAlwaysShowSpells or {}
    local viewer = _G["BuffIconCooldownViewer"]
    -- Use the same displayed-items list the options panel uses (filters out stale/unknown spells)
    local displayedItems = BuildDisplayedItemsForOptions(viewer, settings)
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
                isNotRadio = true,
                keepShownOnClick = true,
                checked = function() return settings.clusterAlwaysShowSpells[spell.key] end,
                func = function()
                    if settings.clusterAlwaysShowSpells[spell.key] then
                        settings.clusterAlwaysShowSpells[spell.key] = nil
                    else
                        settings.clusterAlwaysShowSpells[spell.key] = true
                    end
                    local viewer = _G["BuffIconCooldownViewer"]
                    if viewer then
                        pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, viewer)
                    end
                end,
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
    local viewerState = ViewerRuntimeState[viewer]
    if not viewerState or not viewerState.clusterAnchors then return end
    for i = 1, MAX_CLUSTER_GROUPS do
        local anchor = viewerState.clusterAnchors[i]
        if anchor then
            local inRange = settings.multiClusterMode and i <= settings.clusterCount
            local enabled = settings.clusterUnlocked and inRange
            local sampleMode = string.lower(tostring((settings.clusterSampleDisplayModes and settings.clusterSampleDisplayModes[i]) or "off"))
            local showForSamples = inRange and sampleMode == "always"
            local shouldShowAnchor = enabled or showForSamples
            anchor:EnableMouse(enabled)
            if enabled then
                anchor:SetBackdropColor(0.25, 0.18, 0.02, 0.45)
                anchor:SetBackdropBorderColor(1.0, 0.82, 0.0, 1)
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

local function HideClusterAnchors(viewer)
    if not viewer then return end
    local viewerState = ViewerRuntimeState[viewer]
    if viewerState and viewerState.clusterAnchors then
        for i = 1, MAX_CLUSTER_GROUPS do
            local anchor = viewerState.clusterAnchors[i]
            if anchor then
                anchor:Hide()
                if anchor._editModeOverlay then anchor._editModeOverlay:Hide() end
            end
        end
    end
end

-- Edit Mode overlay for cluster anchors (blue selection box)
local EDITMODE_OVERLAY_COLOR = { 64/255, 128/255, 1, 0.85 }
local EDITMODE_BG_COLOR      = { 64/255, 128/255, 1, 0.12 }

local function EnsureEditModeOverlay(anchor)
    if anchor._editModeOverlay then return anchor._editModeOverlay end
    local overlay = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
    overlay:SetAllPoints(anchor)
    overlay:SetFrameLevel(anchor:GetFrameLevel() + 2)
    overlay:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    overlay:SetBackdropColor(EDITMODE_BG_COLOR[1], EDITMODE_BG_COLOR[2], EDITMODE_BG_COLOR[3], EDITMODE_BG_COLOR[4])
    overlay:SetBackdropBorderColor(EDITMODE_OVERLAY_COLOR[1], EDITMODE_OVERLAY_COLOR[2], EDITMODE_OVERLAY_COLOR[3], EDITMODE_OVERLAY_COLOR[4])
    local lbl = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOP", 0, -4)
    lbl:SetTextColor(1, 1, 1, 1)
    overlay._label = lbl
    overlay:Hide()
    anchor._editModeOverlay = overlay
    return overlay
end

local function ShowClusterAnchorsEditMode(viewer)
    if not viewer then return end
    local settings = DYNAMICICONS:GetSettings()
    if not settings or not settings.multiClusterMode then return end
    local viewerState = ViewerRuntimeState[viewer]
    if not viewerState or not viewerState.clusterAnchors then return end
    for i = 1, math.min(settings.clusterCount or 0, MAX_CLUSTER_GROUPS) do
        local anchor = viewerState.clusterAnchors[i]
        if anchor then
            anchor:Show()
            anchor:EnableMouse(true)
            anchor:SetMovable(true)
            -- Blue edit-mode style
            anchor:SetBackdropColor(EDITMODE_BG_COLOR[1], EDITMODE_BG_COLOR[2], EDITMODE_BG_COLOR[3], EDITMODE_BG_COLOR[4])
            anchor:SetBackdropBorderColor(EDITMODE_OVERLAY_COLOR[1], EDITMODE_OVERLAY_COLOR[2], EDITMODE_OVERLAY_COLOR[3], EDITMODE_OVERLAY_COLOR[4])
            if anchor._clusterLabel then
                anchor._clusterLabel:SetText("Cluster " .. i)
                anchor._clusterLabel:SetTextColor(1, 1, 1, 1)
                anchor._clusterLabel:Show()
            end
            local ov = EnsureEditModeOverlay(anchor)
            ov._label:SetText("Cluster " .. i)
            ov:Show()
        end
    end
    -- Hide excess
    for i = (settings.clusterCount or 0) + 1, MAX_CLUSTER_GROUPS do
        local anchor = viewerState.clusterAnchors[i]
        if anchor then
            anchor:Hide()
            if anchor._editModeOverlay then anchor._editModeOverlay:Hide() end
        end
    end
end

local function HideClusterAnchorsEditMode(viewer)
    if not viewer then return end
    local viewerState = ViewerRuntimeState[viewer]
    if not viewerState or not viewerState.clusterAnchors then return end
    for i = 1, MAX_CLUSTER_GROUPS do
        local anchor = viewerState.clusterAnchors[i]
        if anchor and anchor._editModeOverlay then
            anchor._editModeOverlay:Hide()
        end
    end
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
-- ApplyViewerLayout (layout + skinning)
-- ---------------------------
function BuffIconViewers:ApplyViewerLayout(viewer)
    if not viewer or not viewer.GetName then return end
    if not viewer:IsShown() then return end

    if IsEditModeActive() then
        HideClusterAnchors(viewer)
        return
    end

    local settings = DYNAMICICONS:GetSettings()
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
        local okChildren, children = pcall(SafeGetChildren, container)
        if okChildren and children then
            for _, child in ipairs(children) do
                if child and (child.Icon or child.icon) then
                    iconCount = iconCount + 1
                    icons[iconCount] = child
                end
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
                pcall(BuffIconViewers.SkinIcon, BuffIconViewers, icon, settings)
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
                frame:Hide()
            end
        end
        if anyPersistentIcon then
            _di_persistentUpdateFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
            _di_persistentUpdateFrame:Show()
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
            _di_persistentUpdateFrame:Show()
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
                                local groupWidth = columns * clusterIconSize + (columns - 1) * spacing
                                local groupHeight = rows * clusterIconSize + (rows - 1) * spacing
                                local x = -groupWidth / 2 + clusterIconSize / 2 + colIndex * (clusterIconSize + spacing)
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
    -- Batch refreshes after a short delay (single timer)
    C_Timer.After(0.5, function()
        local viewer = _G["BuffIconCooldownViewer"]
        if viewer then
            ForceReskinViewer(viewer)
            pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, viewer)
            if BuffIconViewers and BuffIconViewers.UpdateAllBuffs then
                pcall(BuffIconViewers.UpdateAllBuffs, BuffIconViewers)
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
        C_Timer.After(0.1, ThrottledInit)
    else
        -- Stop retrying after a while and continue on fallback DB.
        didInit = true
        PrimeDisplayedItemsOnLogin()
    end
end
initFrame:SetScript("OnEvent", function()
    C_Timer.After(0.1, ThrottledInit)
end)

-- Initialize on load
DYNAMICICONS:InitializeDB()
-- ---------------------------
-- HookViewer
-- ---------------------------
local function HookViewer()
    local viewer = _G["BuffIconCooldownViewer"]
    if not viewer then return end

    ApplyViewerInteractionState(viewer, DYNAMICICONS:GetSettings())

    if EditModeManagerFrame and not BuffIconViewers.__editModeHooksInstalled then
        EditModeManagerFrame:HookScript("OnShow", function()
            local v = _G["BuffIconCooldownViewer"]
            if v then
                if InCombatLockdown() then
                    QueueInteractionRefresh(v)
                    return
                end
                v:Show()
                -- Show cluster anchors as blue edit-mode boxes instead of hiding
                local s = DYNAMICICONS:GetSettings()
                if s and s.multiClusterMode then
                    -- Ensure anchors exist for all clusters
                    for ci = 1, math.min(s.clusterCount or 0, MAX_CLUSTER_GROUPS) do
                        EnsureClusterAnchorForIndex(v, s, ci)
                    end
                    ShowClusterAnchorsEditMode(v)
                else
                    HideClusterAnchors(v)
                end
            end
        end)
        EditModeManagerFrame:HookScript("OnHide", function()
            local v = _G["BuffIconCooldownViewer"]
            if v and InCombatLockdown() then
                QueueInteractionRefresh(v)
                return
            end
            -- Hide edit-mode overlays
            if v then HideClusterAnchorsEditMode(v) end
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
function DYNAMICICONS:CreateOptionsPanel()
        -- Ensure config UI is rebuilt after login so color pickers and spell list are correct
        local function DelayedRebuildConfigUI()
            if optionsPanel and optionsPanel._rebuildConfigUI then
                optionsPanel:_rebuildConfigUI()
            end
        end
        local loginFrame = CreateFrame("Frame")
        loginFrame:RegisterEvent("PLAYER_LOGIN")
        loginFrame:SetScript("OnEvent", function()
            C_Timer.After(1, DelayedRebuildConfigUI)
        end)
    EnsureDB()
    if optionsPanel then return optionsPanel end
    optionsPanel = CreateFrame("Frame", "DYNAMICICONSOptionsPanel", UIParent)

    optionsPanel.name = "DYNAMICICONS"
    optionsPanel:SetSize(550, 1100)

    interactionNote:SetPoint("TOPRIGHT", optionsPanel, "TOPRIGHT", -24, -44)
    interactionNote:SetWidth(360)
    interactionNote:SetJustifyH("RIGHT")
    interactionNote:SetText("")
    optionsPanel._interactionNote = interactionNote

    RefreshOptionsInteractionStatus = function()
        if not optionsPanel or not optionsPanel._interactionNote then return end
        local viewer = _G["BuffIconCooldownViewer"]
        local pending = viewer and PendingInteractionRefresh[viewer]

        if pending then
            optionsPanel._interactionNote:SetText("Lock/unlock/Edit Mode interaction changes will apply after combat.")
            optionsPanel._interactionNote:SetTextColor(1.0, 0.82, 0.0, 1)
        elseif InCombatLockdown() then
            optionsPanel._interactionNote:SetText("In combat: lock/unlock/Edit Mode interaction changes are deferred.")
            optionsPanel._interactionNote:SetTextColor(1.0, 0.65, 0.2, 1)
        else
            optionsPanel._interactionNote:SetText("")
        end
    end

    local scrollFrame = CreateFrame("ScrollFrame", nil, optionsPanel)
    scrollFrame:SetPoint("TOPLEFT", 0, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", 0, 0)
    scrollFrame:SetClipsChildren(true)
    scrollFrame:EnableMouseWheel(true)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(530, 2000)
    scrollFrame:SetScrollChild(content)
    optionsPanel._content = content

    local function UpdateScrollRange()
        local child = scrollFrame:GetScrollChild()
        if not child then
            scrollFrame:SetVerticalScroll(0)
            return
        end

        local childHeight = child:GetHeight() or 0
        local frameHeight = scrollFrame:GetHeight() or 0
        local maxOffset = math.max(0, childHeight - frameHeight)
        local current = scrollFrame:GetVerticalScroll() or 0

        if current < 0 then
            current = 0
        elseif current > maxOffset then
            current = maxOffset
        end

        scrollFrame:SetVerticalScroll(current)
    end

    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local child = self:GetScrollChild()
        if not child then return end

        local childHeight = child:GetHeight() or 0
        local frameHeight = self:GetHeight() or 0
        local maxOffset = math.max(0, childHeight - frameHeight)
        local current = self:GetVerticalScroll() or 0
        local nextOffset = current - (delta * 36)

        if nextOffset < 0 then
            nextOffset = 0
        elseif nextOffset > maxOffset then
            nextOffset = maxOffset
        end

        self:SetVerticalScroll(nextOffset)
    end)
--HERE IS WHAT MAKES ICONS SHOW PERFECT NOT REALLY 
    scrollFrame:SetScript("OnSizeChanged", function()
        -- Throttle UpdateScrollRange to avoid excessive calls
        if not scrollFrame._updateScrollPending then
            scrollFrame._updateScrollPending = true
            C_Timer.After(0.3, function()
                scrollFrame._updateScrollPending = false
                UpdateScrollRange()
            end)
        end
    end)
--where it moves maybe

    content:SetScript("OnSizeChanged", function()
        if not content._updateScrollPending then
            content._updateScrollPending = true
            C_Timer.After(0.5, function()
                content._updateScrollPending = false
                UpdateScrollRange()
            end)
        end
    end)

    local function AddPerRowSliders(content, x1, y)
        if content._rowSizeWidgets then
            for _, w in ipairs(content._rowSizeWidgets) do if w then w:Hide() end end
        end
        content._rowSizeWidgets = {}
        local viewer = _G["BuffIconCooldownViewer"]
        local numRows = 1
        if viewer then
            local lastNumRows = GetViewerMetric(viewer, "lastNumRows", 0)
            if lastNumRows and lastNumRows > 0 then
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
            local settings = DYNAMICICONS:GetSettings()
            local current = (settings.rowSizes and settings.rowSizes[r]) or settings.iconSize
            local rowSlider = CreateSlider(content, "Row "..r.." Size", 1, 200, 1, current,
                function(v)
                    local settings = DYNAMICICONS:GetSettings()
                    settings.rowSizes = settings.rowSizes or {}
                    settings.rowSizes[r] = v
                    local viewer = _G["BuffIconCooldownViewer"]
                    if viewer then
                        ForceReskinViewer(viewer)
                        pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, viewer)
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
        -- Hide and detach all child frames
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
        title:SetText("DYNAMICICONS")
        title:SetTextColor(1, 1, 1, 1)

        -- After all controls are created, force OnShow for all children to update input/valueText
        -- Directly call Show on all children (no timer needed)
        for _, child in ipairs({content:GetChildren()}) do
            if child.Show then child:Show() end
        end

        -- Profile selector
        if CkraigProfileManager and CkraigProfileManager.db then
            local profileLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            profileLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -30)
            profileLabel:SetText("Profile:")
            profileLabel:SetTextColor(0.85, 0.85, 0.85, 1)
            local profileDropdown = CreateFrame("DropdownButton", "DYNAMICICONSProfileDropdown", content, "WowStyle1DropdownTemplate")
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
        local iconSizeSlider = CreateSlider(content, "Icon Size", 8, 128, 1, DYNAMICICONS:GetSettings().iconSize,
            function(v)
                DYNAMICICONS:GetSettings().iconSize = v
                local viewer = _G["BuffIconCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, viewer)
                    if optionsPanel and optionsPanel._rebuildConfigUI then optionsPanel:_rebuildConfigUI() end
                end
            end)
        iconSizeSlider:SetPoint("TOPLEFT", x1, y)

        -- Cooldown Text Size Slider
        y = y - 46
        local cooldownTextSizeSlider = CreateSlider(content, "Cooldown Text Size", 8, 36, 1, DYNAMICICONS:GetSettings().cooldownTextSize or 16,
            function(v)
                DYNAMICICONS:GetSettings().cooldownTextSize = v
                -- Live update: re-apply layout to update all cooldown text sizes
                local viewer = _G["BuffIconCooldownViewer"]
                if viewer then
                    pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, viewer)
                end
            end)
        cooldownTextSizeSlider:SetPoint("TOPLEFT", x1, y)            y = y - 46
       
        local spaceTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        spaceTitle:SetPoint("TOPLEFT", x1, y)
        spaceTitle:SetText("Spacing & Layout")
        spaceTitle:SetTextColor(0.9, 0.9, 0.9, 1)
        y = y - 24
        local hSpace = CreateSlider(content, "Horizontal Spacing", 0, 40, 1, DYNAMICICONS:GetSettings().spacing,
            function(v)
                DYNAMICICONS:GetSettings().spacing = v
                local viewer = _G["BuffIconCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, viewer)
                    if optionsPanel and optionsPanel._rebuildConfigUI then optionsPanel:_rebuildConfigUI() end
                end
            end)
        hSpace:SetPoint("TOPLEFT", x1, y)
        local vSpace = CreateSlider(content, "Vertical Spacing", 0, 40, 1, DYNAMICICONS:GetSettings().spacing,
            function(v)
                DYNAMICICONS:GetSettings().spacing = v
                local viewer = _G["BuffIconCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, viewer)
                    if optionsPanel and optionsPanel._rebuildConfigUI then optionsPanel:_rebuildConfigUI() end
                end
            end)
        vSpace:SetPoint("TOPLEFT", x2, y)
        y = y - 46
        local perRow = CreateSlider(content, "Icons Per Row", 1, 50, 1, DYNAMICICONS:GetSettings().columns,
            function(v)
                local settings = DYNAMICICONS:GetSettings()
                settings.columns = v; settings.rowLimit = v
                local viewer = _G["BuffIconCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, viewer)
                    if optionsPanel and optionsPanel._rebuildConfigUI then optionsPanel:_rebuildConfigUI() end
                end
            end)
        perRow:SetPoint("TOPLEFT", x1, y)
        y = y - 52

        -- Charge/Stack Font Position Options
        local chargeTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        chargeTitle:SetPoint("TOPLEFT", x1, y)
        chargeTitle:SetText("Charge/Stack Font Position")
        chargeTitle:SetTextColor(0.9, 0.9, 0.9, 1)
        y = y - 24

        -- Dropdown for position
        local positionOptions = {"CENTER", "TOP", "BOTTOM", "LEFT", "RIGHT", "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}
        local function UpdateChargeFontPosition()
            local viewer = _G["BuffIconCooldownViewer"]
            if viewer then
                ForceReskinViewer(viewer)
                pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, viewer)
            end
        end
        local chargePosDropdown = CreateDropdown(content, "Position",
            positionOptions,
            function() return DYNAMICICONS:GetSettings().chargeTextPosition or "BOTTOMRIGHT" end,
            function(v)
                DYNAMICICONS:GetSettings().chargeTextPosition = v
                UpdateChargeFontPosition()
            end)
        chargePosDropdown:SetPoint("TOPLEFT", x1, y)
        y = y - 52

        -- X Offset Slider
        local chargeXSlider = CreateSlider(content, "Charge X Offset", -100, 100, 1, DYNAMICICONS:GetSettings().chargeTextX or 0,
            function(v)
                DYNAMICICONS:GetSettings().chargeTextX = v
                UpdateChargeFontPosition()
            end)
        chargeXSlider:SetPoint("TOPLEFT", x1, y)
        y = y - 46

        -- Y Offset Slider
        local chargeYSlider = CreateSlider(content, "Charge Y Offset", -100, 100, 1, DYNAMICICONS:GetSettings().chargeTextY or 0,
            function(v)
                DYNAMICICONS:GetSettings().chargeTextY = v
                UpdateChargeFontPosition()
            end)
        chargeYSlider:SetPoint("TOPLEFT", x1, y)
        y = y - 46

        y = AddPerRowSliders(content, x1, y)
        -- ENABLE VIEWER OPTION (Atlas-based checkbox)
        local enableCheck = CreateCheck(content, "Enable Dynamic Icons", DYNAMICICONS:GetSettings().enabled ~= false,
            function(v)
                DYNAMICICONS:GetSettings().enabled = v
                UpdateCooldownManagerVisibility()
                local viewer = _G["BuffIconCooldownViewer"]
                if viewer and v then
                    pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, viewer)
                end
            end, true)
        enableCheck:SetPoint("TOPLEFT", x1, y)
        y = y - 28

        -- HIDE WHEN MOUNTED OPTION (Atlas-based checkbox)
        local hideMount = CreateCheck(content, "Hide when mounted", DYNAMICICONS:GetSettings().hideWhenMounted,
            function(v)
                DYNAMICICONS:GetSettings().hideWhenMounted = v
                if v then
                    mountEventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
                else
                    mountEventFrame:UnregisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
                end
                UpdateCooldownManagerVisibility()
            end, true)
        hideMount:SetPoint("TOPLEFT", x1, y)
        y = y - 28

        -- SHOW SWIPE OPTION (Atlas-based checkbox)
        local showSwipeCheck = CreateCheck(content, "Show Cooldown Swipe", DYNAMICICONS:GetSettings().showSwipe,
            function(v)
                DYNAMICICONS:GetSettings().showSwipe = v
                local viewer = _G["BuffIconCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, viewer)
                end
            end, true)
        showSwipeCheck:SetPoint("TOPLEFT", x1, y)
        y = y - 28

        -- (Lock Frame checkbox removed)
        y = y - 12
        -- Add a single, always-visible Stack/Charge Font Size slider under the Lock Frame checkbox
        local extraFontSizeSlider = CreateSlider(content, "Stack/Charge Font Size", 6, 72, 1, DYNAMICICONS:GetSettings().chargeTextSize or 14,
            function(v)
                DYNAMICICONS:GetSettings().chargeTextSize = v
                local viewer = _G["BuffIconCooldownViewer"]
                if viewer then
                    ForceReskinViewer(viewer)
                    pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, viewer)
                end
            end)
        extraFontSizeSlider:SetPoint("TOPLEFT", x1, y)
        y = y - 46

        local clusterTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        clusterTitle:SetPoint("TOPLEFT", x1, y)
        clusterTitle:SetText("Dynamic Multi-Cluster")
        clusterTitle:SetTextColor(0.9, 0.9, 0.9, 1)
        y = y - 24

        local multiClusterCheck = CreateCheck(content, "Enable multi-cluster dynamic mode", DYNAMICICONS:GetSettings().multiClusterMode,
            function(v)
                local settings = DYNAMICICONS:GetSettings()
                settings.multiClusterMode = v
                local viewer = _G["BuffIconCooldownViewer"]
                if viewer then
                    pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, viewer)
                end
                if optionsPanel and optionsPanel._rebuildConfigUI then optionsPanel:_rebuildConfigUI() end
            end, true)
        multiClusterCheck:SetPoint("TOPLEFT", x1, y)
        y = y - 28

        if DYNAMICICONS:GetSettings().multiClusterMode then
            local centerClusterCheck = CreateCheck(content, "Center icons in cluster", DYNAMICICONS:GetSettings().clusterCenterIcons ~= false,
                function(v)
                    local settings = DYNAMICICONS:GetSettings()
                    settings.clusterCenterIcons = v
                    local viewer = _G["BuffIconCooldownViewer"]
                    if viewer then
                        pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, viewer)
                    end
                end, true)
            centerClusterCheck:SetPoint("TOPLEFT", x1, y)
            y = y - 28
        end

        if DYNAMICICONS:GetSettings().multiClusterMode then
        local clusterUnlockedCheck = CreateCheck(content, "Unlock cluster boxes for dragging", DYNAMICICONS:GetSettings().clusterUnlocked,
            function(v)
                local settings = DYNAMICICONS:GetSettings()
                settings.clusterUnlocked = v
                local viewer = _G["BuffIconCooldownViewer"]
                if viewer then
                    ApplyViewerInteractionState(viewer, settings)
                    pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, viewer)
                end
            end, true)
        clusterUnlockedCheck:SetPoint("TOPLEFT", x1, y)
        y = y - 28

        local clusterCountSlider = CreateSlider(content, "Cluster Count", 1, MAX_CLUSTER_GROUPS, 1, DYNAMICICONS:GetSettings().clusterCount or DEFAULTS.clusterCount,
            function(v)
                local settings = DYNAMICICONS:GetSettings()
                settings.clusterCount = v
                local viewer = _G["BuffIconCooldownViewer"]
                if viewer then
                    pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, viewer)
                end
                if optionsPanel and optionsPanel._rebuildConfigUI then optionsPanel:_rebuildConfigUI() end
            end)
        clusterCountSlider:SetPoint("TOPLEFT", x1, y)
        y = y - 50

        local clusterFlowLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        clusterFlowLabel:SetPoint("TOPLEFT", x1, y)
        clusterFlowLabel:SetText("Cluster Flow (per cluster)")
        clusterFlowLabel:SetTextColor(0.9, 0.9, 0.9, 1)
        y = y - 20

        local settings = DYNAMICICONS:GetSettings()
        settings.clusterFlows = settings.clusterFlows or {}
        settings.clusterVerticalGrows = settings.clusterVerticalGrows or {}
        settings.clusterVerticalPins = settings.clusterVerticalPins or {}
        settings.clusterIconSizes = settings.clusterIconSizes or {}
        settings.clusterSampleDisplayModes = settings.clusterSampleDisplayModes or {}
        local flowClusterCount = math.max(1, math.min(MAX_CLUSTER_GROUPS, settings.clusterCount or DEFAULTS.clusterCount))

        for clusterIndex = 1, flowClusterCount do
            local flowRow = CreateFrame("Frame", nil, content)
            flowRow:SetSize(520, 34)
            flowRow:SetPoint("TOPLEFT", x1, y)

            local flowName = flowRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            flowName:SetPoint("LEFT", 0, 0)
            flowName:SetWidth(80)
            flowName:SetJustifyH("LEFT")
            flowName:SetText("Cluster " .. clusterIndex)

            local function ApplyAndRefresh()
                local viewer = _G["BuffIconCooldownViewer"]
                if viewer then
                    pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, viewer)
                end
            end

            local flowDropdown = CreateFrame("DropdownButton", nil, flowRow, "WowStyle1DropdownTemplate")
            flowDropdown:SetPoint("LEFT", flowName, "RIGHT", 4, 0)
            flowDropdown:SetSize(110, 22)
            flowDropdown:SetupMenu(function(dd, rootDescription)
                rootDescription:CreateRadio("Horizontal",
                    function() return string.lower(tostring(settings.clusterFlows[clusterIndex] or settings.clusterFlow or DEFAULTS.clusterFlow)) ~= "vertical" end,
                    function() settings.clusterFlows[clusterIndex] = "horizontal"; ApplyAndRefresh() end)
                rootDescription:CreateRadio("Vertical",
                    function() return string.lower(tostring(settings.clusterFlows[clusterIndex] or settings.clusterFlow or DEFAULTS.clusterFlow)) == "vertical" end,
                    function() settings.clusterFlows[clusterIndex] = "vertical"; ApplyAndRefresh() end)
            end)

            local growDropdown = CreateFrame("DropdownButton", nil, flowRow, "WowStyle1DropdownTemplate")
            growDropdown:SetPoint("LEFT", flowDropdown, "RIGHT", 4, 0)
            growDropdown:SetSize(110, 22)
            growDropdown:SetupMenu(function(dd, rootDescription)
                rootDescription:CreateRadio("Grow Down",
                    function() return string.lower(tostring(settings.clusterVerticalGrows[clusterIndex] or "down")) ~= "up" end,
                    function() settings.clusterVerticalGrows[clusterIndex] = "down"; ApplyAndRefresh() end)
                rootDescription:CreateRadio("Grow Up",
                    function() return string.lower(tostring(settings.clusterVerticalGrows[clusterIndex] or "down")) == "up" end,
                    function() settings.clusterVerticalGrows[clusterIndex] = "up"; ApplyAndRefresh() end)
            end)

            local pinDropdown = CreateFrame("DropdownButton", nil, flowRow, "WowStyle1DropdownTemplate")
            pinDropdown:SetPoint("LEFT", growDropdown, "RIGHT", 4, 0)
            pinDropdown:SetSize(110, 22)
            pinDropdown:SetupMenu(function(dd, rootDescription)
                rootDescription:CreateRadio("Pin Top",
                    function() return string.lower(tostring(settings.clusterVerticalPins[clusterIndex] or "center")) == "top" end,
                    function() settings.clusterVerticalPins[clusterIndex] = "top"; ApplyAndRefresh() end)
                rootDescription:CreateRadio("Pin Center",
                    function() return string.lower(tostring(settings.clusterVerticalPins[clusterIndex] or "center")) == "center" end,
                    function() settings.clusterVerticalPins[clusterIndex] = "center"; ApplyAndRefresh() end)
                rootDescription:CreateRadio("Pin Bottom",
                    function() return string.lower(tostring(settings.clusterVerticalPins[clusterIndex] or "center")) == "bottom" end,
                    function() settings.clusterVerticalPins[clusterIndex] = "bottom"; ApplyAndRefresh() end)
            end)

            local sampleDropdown = CreateFrame("DropdownButton", nil, flowRow, "WowStyle1DropdownTemplate")
            sampleDropdown:SetPoint("LEFT", pinDropdown, "RIGHT", 4, 0)
            sampleDropdown:SetSize(120, 22)
            sampleDropdown:SetupMenu(function(dd, rootDescription)
                rootDescription:CreateRadio("HIDE INACTIVE",
                    function() return string.lower(tostring(settings.clusterSampleDisplayModes[clusterIndex] or "off")) ~= "always" end,
                    function() settings.clusterSampleDisplayModes[clusterIndex] = "off"; ApplyAndRefresh() end)
                rootDescription:CreateRadio("SHOW INACTIVE",
                    function() return string.lower(tostring(settings.clusterSampleDisplayModes[clusterIndex] or "off")) == "always" end,
                    function() settings.clusterSampleDisplayModes[clusterIndex] = "always"; ApplyAndRefresh() end)
            end)

            y = y - 34
        end

        y = y - 10

        local clusterSizeTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        clusterSizeTitle:SetPoint("TOPLEFT", x1, y)
        clusterSizeTitle:SetText("Cluster Icon Size (per cluster)")
        clusterSizeTitle:SetTextColor(0.9, 0.9, 0.9, 1)
        y = y - 24

        for clusterIndex = 1, flowClusterCount do
            local sliderX = ((clusterIndex % 2) == 1) and x1 or x2
            local initialSize = SafeNumber(settings.clusterIconSizes[clusterIndex], settings.iconSize)
            local clusterSizeSlider = CreateSlider(content, "Cluster " .. clusterIndex .. " Icon Size", 8, 128, 1, initialSize,
                function(v)
                    settings.clusterIconSizes[clusterIndex] = v
                    local viewer = _G["BuffIconCooldownViewer"]
                    if viewer then
                        pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, viewer)
                    end
                end)
            clusterSizeSlider:SetPoint("TOPLEFT", sliderX, y)

            if (clusterIndex % 2) == 0 then
                y = y - 46
            end
        end
        if (flowClusterCount % 2) == 1 then
            y = y - 46
        end

        y = y - 8

        local assignTitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        assignTitle:SetPoint("TOPLEFT", x1, y)
        assignTitle:SetText("Assign displayed CDIDs to clusters")
        assignTitle:SetTextColor(0.9, 0.9, 0.9, 1)
        y = y - 20

        local refreshButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
        refreshButton:SetSize(150, 22)
        refreshButton:SetPoint("TOPLEFT", x1, y)
        refreshButton:SetText("Refresh Displayed List")
        refreshButton:SetScript("OnClick", function()
            local activeViewer = _G["BuffIconCooldownViewer"]
            if activeViewer then
                pcall(UpsertKnownDisplayedItems, activeViewer)
            end
            if optionsPanel and optionsPanel._rebuildConfigUI then
                optionsPanel:_rebuildConfigUI()
            end
        end)
        y = y - 28

        local viewer = _G["BuffIconCooldownViewer"]
        local displayedItems = BuildDisplayedItemsForOptions(viewer, DYNAMICICONS:GetSettings())
        if #displayedItems == 0 then
            local noItems = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            noItems:SetPoint("TOPLEFT", x1, y)
            noItems:SetText("No displayed tracked buffs found yet. Open the Blizzard Cooldown Viewer and click Refresh.")
            noItems:SetTextColor(0.9, 0.6, 0.4, 1)
            noItems:SetWidth(480)
            noItems:SetJustifyH("LEFT")
            y = y - 36
        else
            local settings = DYNAMICICONS:GetSettings()
            settings.clusterAssignments = settings.clusterAssignments or {}
            local clusterCount = math.max(1, math.min(MAX_CLUSTER_GROUPS, settings.clusterCount or DEFAULTS.clusterCount))

            for _, item in ipairs(displayedItems) do
                local row = CreateFrame("Frame", nil, content)
                row:SetSize(500, 48)
                row:SetPoint("TOPLEFT", x1, y)

                local icon = row:CreateTexture(nil, "ARTWORK")
                icon:SetSize(20, 20)
                icon:SetPoint("LEFT", 0, 0)
                if item.icon and item.icon ~= "" then
                    icon:SetTexture(item.icon)
                else
                    icon:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")
                end

                local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
                label:SetWidth(220)
                label:SetJustifyH("LEFT")
                label:SetText(string.format("%s (%s)", item.name, item.key))

                local clusterButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                clusterButton:SetSize(100, 22)
                clusterButton:SetPoint("LEFT", label, "RIGHT", 0, 0)

                local orderLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                orderLabel:SetPoint("LEFT", clusterButton, "RIGHT", 6, 0)
                orderLabel:SetWidth(28)
                orderLabel:SetJustifyH("CENTER")

                local upButton = CreateFrame("Button", nil, row, "UIPanelScrollUpButtonTemplate")
                upButton:SetSize(20, 20)
                upButton:SetPoint("LEFT", orderLabel, "RIGHT", 2, 0)
                upButton:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
                upButton:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down")
                upButton:SetDisabledTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Disabled")
                upButton:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight")

                local downButton = CreateFrame("Button", nil, row, "UIPanelScrollDownButtonTemplate")
                downButton:SetSize(20, 20)
                downButton:SetPoint("LEFT", upButton, "RIGHT", 2, 0)
                downButton:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
                downButton:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
                downButton:SetDisabledTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Disabled")
                downButton:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight")

                -- Duplicate to other clusters button
                settings.clusterDuplicates = settings.clusterDuplicates or {}
                local dupBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
                dupBtn:SetSize(36, 20)
                dupBtn:SetPoint("LEFT", downButton, "RIGHT", 6, 0)
                dupBtn:SetText("Dup")
                dupBtn:SetScript("OnEnter", function(self)
                    if GameTooltip then
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        local dups = settings.clusterDuplicates[item.key]
                        local dupList = {}
                        if dups then
                            for ci, en in pairs(dups) do
                                if en then table.insert(dupList, tostring(ci)) end
                            end
                        end
                        local dupText = #dupList > 0 and table.concat(dupList, ", ") or "none"
                        GameTooltip:SetText("Duplicate this spell into other clusters.\nCurrent duplicates: " .. dupText, 1, 1, 1, 1, true)
                        GameTooltip:Show()
                    end
                end)
                dupBtn:SetScript("OnLeave", function()
                    if GameTooltip then GameTooltip:Hide() end
                end)
                dupBtn:SetScript("OnClick", function(self)
                    local menuList = {}
                    local primaryCluster = tonumber(settings.clusterAssignments[item.key]) or 1
                    table.insert(menuList, { text = item.name .. " — Duplicate to:", isTitle = true, notCheckable = true })
                    for ci = 1, clusterCount do
                        if ci ~= primaryCluster then
                            local dups = settings.clusterDuplicates[item.key] or {}
                            local isEnabled = dups[ci] and true or false
                            table.insert(menuList, {
                                text = "Cluster " .. ci,
                                checked = isEnabled,
                                isNotRadio = true,
                                func = function()
                                    settings.clusterDuplicates[item.key] = settings.clusterDuplicates[item.key] or {}
                                    if settings.clusterDuplicates[item.key][ci] then
                                        settings.clusterDuplicates[item.key][ci] = nil
                                    else
                                        settings.clusterDuplicates[item.key][ci] = true
                                    end
                                    -- Clean up empty tables
                                    local anyLeft = false
                                    for _ in pairs(settings.clusterDuplicates[item.key]) do anyLeft = true; break end
                                    if not anyLeft then settings.clusterDuplicates[item.key] = nil end
                                    local activeViewer = _G["BuffIconCooldownViewer"]
                                    if activeViewer then
                                        pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, activeViewer)
                                    end
                                    if optionsPanel and optionsPanel._rebuildConfigUI then
                                        optionsPanel:_rebuildConfigUI()
                                    end
                                end,
                            })
                        end
                    end
                    table.insert(menuList, { text = "", isTitle = true, notCheckable = true })
                    table.insert(menuList, { text = "Close", notCheckable = true, func = function() CloseDropDownMenus() end })
                    _EasyMenu(menuList, iconClusterContextMenu, "cursor", 0, 0, "MENU")
                end)

                -- Show which clusters this spell is duplicated into
                local dupInfo = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                dupInfo:SetPoint("LEFT", dupBtn, "RIGHT", 4, 0)
                dupInfo:SetWidth(80)
                dupInfo:SetJustifyH("LEFT")
                local dupClusters = settings.clusterDuplicates[item.key]
                if dupClusters then
                    local dupList = {}
                    for ci, en in pairs(dupClusters) do
                        if en then table.insert(dupList, tostring(ci)) end
                    end
                    if #dupList > 0 then
                        table.sort(dupList)
                        dupInfo:SetText("+C" .. table.concat(dupList, ","))
                        dupInfo:SetTextColor(0.4, 0.9, 0.4, 1)
                    else
                        dupInfo:SetText("")
                    end
                else
                    dupInfo:SetText("")
                end

                local function SetClusterSelection(groupIndex)
                    RemoveKeyFromAllClusterOrders(settings, item.key)
                    settings.clusterAssignments[item.key] = groupIndex
                    AddKeyToClusterOrderEnd(settings, groupIndex, item.key)
                    clusterButton:SetText("Cluster " .. groupIndex)
                    -- Remove duplicate entry for the new primary cluster
                    if settings.clusterDuplicates[item.key] then
                        settings.clusterDuplicates[item.key][groupIndex] = nil
                        local anyLeft = false
                        for _ in pairs(settings.clusterDuplicates[item.key]) do anyLeft = true; break end
                        if not anyLeft then settings.clusterDuplicates[item.key] = nil end
                    end
                    local activeViewer = _G["BuffIconCooldownViewer"]
                    if activeViewer then
                        pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, activeViewer)
                    end
                end

                local function RefreshOrderLabel()
                    local currentCluster = tonumber(settings.clusterAssignments[item.key]) or 1
                    local orderedKeys = BuildOrderedKeysForCluster(settings, currentCluster, nil)
                    local position = "-"
                    for idx, key in ipairs(orderedKeys) do
                        if tostring(key) == tostring(item.key) then
                            position = tostring(idx)
                            break
                        end
                    end
                    orderLabel:SetText(position)
                end

                clusterButton:SetScript("OnClick", function(_, mouseButton)
                    local current = tonumber(settings.clusterAssignments[item.key]) or 1
                    local nextGroup
                    if mouseButton == "RightButton" then
                        nextGroup = current - 1
                        if nextGroup < 1 then
                            nextGroup = clusterCount
                        end
                    else
                        nextGroup = current + 1
                        if nextGroup > clusterCount then
                            nextGroup = 1
                        end
                    end
                    SetClusterSelection(nextGroup)
                end)

                clusterButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                clusterButton:SetText("Cluster " .. (tonumber(settings.clusterAssignments[item.key]) or 1))
                clusterButton:SetScript("OnEnter", function(self)
                    if GameTooltip then
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText("Left-click: next cluster\nRight-click: previous cluster", 1, 1, 1, 1, true)
                        GameTooltip:Show()
                    end
                end)
                clusterButton:SetScript("OnLeave", function()
                    if GameTooltip then GameTooltip:Hide() end
                end)

                upButton:SetScript("OnClick", function()
                    local currentCluster = tonumber(settings.clusterAssignments[item.key]) or 1
                    MoveKeyInClusterOrder(settings, currentCluster, item.key, -1)
                    local activeViewer = _G["BuffIconCooldownViewer"]
                    if activeViewer then
                        pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, activeViewer)
                    end
                    if optionsPanel and optionsPanel._rebuildConfigUI then
                        optionsPanel:_rebuildConfigUI()
                    else
                        RefreshOrderLabel()
                    end
                end)

                downButton:SetScript("OnClick", function()
                    local currentCluster = tonumber(settings.clusterAssignments[item.key]) or 1
                    MoveKeyInClusterOrder(settings, currentCluster, item.key, 1)
                    local activeViewer = _G["BuffIconCooldownViewer"]
                    if activeViewer then
                        pcall(BuffIconViewers.ApplyViewerLayout, BuffIconViewers, activeViewer)
                    end
                    if optionsPanel and optionsPanel._rebuildConfigUI then
                        optionsPanel:_rebuildConfigUI()
                    else
                        RefreshOrderLabel()
                    end
                end)

                -- Per-spell glow controls (matches Essential glow system)
                settings.spellGlows = settings.spellGlows or {}
                local glowCfg = settings.spellGlows[item.key]
                if type(glowCfg) ~= "table" then
                    glowCfg = { enabled = (glowCfg == true), mode = "ready", glowType = "pixel", color = {r=1, g=1, b=0, a=1} }
                end
                if not glowCfg.glowType then glowCfg.glowType = "pixel" end
                if not glowCfg.mode then glowCfg.mode = "ready" end
                if not glowCfg.color then glowCfg.color = {r=1, g=1, b=0, a=1} end
                settings.spellGlows[item.key] = glowCfg

                -- Glow ON/OFF button
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

                -- Mode toggle: "On Ready" <-> "On Cooldown"
                local modeLabels = { ready = "On Ready", cooldown = "On Cooldown" }
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

                -- Glow type toggle: Pixel -> AutoCast -> Button -> Proc
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

                -- Color swatch with WoW color picker
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

                RefreshOrderLabel()
                y = y - 48
            end
        end
        end -- multiClusterMode controls

        content:SetSize(530, math.max(3200, math.abs(y) + 220))
        -- Directly call UpdateScrollRange (no timer needed)
        UpdateScrollRange()
    end
    optionsPanel:_rebuildConfigUI()
    optionsPanel:HookScript("OnShow", function()
        if optionsPanel and optionsPanel._rebuildConfigUI then optionsPanel:_rebuildConfigUI() end
        if RefreshOptionsInteractionStatus then RefreshOptionsInteractionStatus() end
    end)
    -- Do not self-register; assign to global for parent registration
    _G.DYNAMICICONSPanel = optionsPanel
    return optionsPanel
end


-- No direct registration here; handled by CkraigsOptions.lua

