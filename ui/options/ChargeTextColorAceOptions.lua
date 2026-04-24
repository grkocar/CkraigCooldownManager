-- ============================================================
-- CkraigCooldownManager :: UI :: Options :: Charge Text Colors
-- ============================================================
-- AceConfig options table for charge/cooldown text color pickers.
-- Replaces both ChargeTextColorOptions and colorpickers panels.
-- ============================================================

local CCM = _G.CkraigCooldownManager
ChargeTextColorOptions = ChargeTextColorOptions or {}

local COLOR_KEYS = {
    "TextColor_CooldownText_Buff",
    "TextColor_CooldownText_Essential",
    "TextColor_CooldownText_Utility",
    "TextColor_ChargeText_Buff",
    "TextColor_ChargeText_Essential",
    "TextColor_ChargeText_Utility",
}

local function NormalizeColor(value)
    local r = (type(value) == "table" and (value.r or value[1])) or 1
    local g = (type(value) == "table" and (value.g or value[2])) or 1
    local b = (type(value) == "table" and (value.b or value[3])) or 1
    local a = (type(value) == "table" and (value.a or value[4])) or 1
    return r, g, b, a
end

local function EnsureProfileColorDB()
    if _G.CkraigProfileManager and _G.CkraigProfileManager.db and _G.CkraigProfileManager.db.profile then
        _G.CkraigProfileManager.db.profile.chargeTextColors = _G.CkraigProfileManager.db.profile.chargeTextColors or {}
        return _G.CkraigProfileManager.db.profile.chargeTextColors
    end
    return nil
end

local function EnsureGlobalColorDB()
    if type(_G.CooldownChargeDB) ~= "table" then
        _G.CooldownChargeDB = {}
    end
    return _G.CooldownChargeDB
end

local function SyncChargeColorDB()
    local profileDB = EnsureProfileColorDB()
    local globalDB = EnsureGlobalColorDB()

    if profileDB then
        for _, key in ipairs(COLOR_KEYS) do
            local r, g, b, a = NormalizeColor(profileDB[key])
            profileDB[key] = { r = r, g = g, b = b, a = a }
            globalDB[key] = { r, g, b, a }
        end
    else
        for _, key in ipairs(COLOR_KEYS) do
            local r, g, b, a = NormalizeColor(globalDB[key])
            globalDB[key] = { r, g, b, a }
        end
    end
end

_G.CCM_SyncChargeTextColorDB = SyncChargeColorDB

local function GetDB()
    local db = EnsureProfileColorDB()
    if db then
        return db
    end
    return EnsureGlobalColorDB()
end

local function GetColorRGBA(key)
    local db = EnsureGlobalColorDB()
    local c = db and db[key]
    local r, g, b, a = NormalizeColor(c)
    return r, g, b, a
end

local function FindChargeText(icon)
    if not icon then return nil end

    if icon.GetApplicationsFontString then
        local ok, fs = pcall(icon.GetApplicationsFontString, icon)
        if ok and fs and fs.SetTextColor then
            return fs
        end
    end

    if icon.ChargeCount and icon.ChargeCount.Current and icon.ChargeCount.Current.SetTextColor then
        return icon.ChargeCount.Current
    end

    local direct = icon._chargeText or icon._customCountText or icon.Count or icon.count or icon.Charges or icon.charges or icon.StackCount
    if direct and direct.SetTextColor then
        return direct
    end

    if icon.GetRegions then
        local ok, regions = pcall(function() return { icon:GetRegions() } end)
        if ok and regions then
            for _, region in ipairs(regions) do
                if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                    local text = region.GetText and region:GetText()
                    if text and tonumber(text) and tonumber(text) > 0 then
                        return region
                    end
                end
            end
        end
    end

    return nil
end

local function FindCooldownText(icon)
    if not icon then return nil end
    local cd = icon.Cooldown or icon.cooldown
    if not cd then return nil end

    if cd.Text and cd.Text.SetTextColor then return cd.Text end
    if cd.text and cd.text.SetTextColor then return cd.text end

    if cd.GetChildren then
        local ok, children = pcall(function() return { cd:GetChildren() } end)
        if ok and children then
            for _, child in ipairs(children) do
                if child and child.GetObjectType and child:GetObjectType() == "FontString" then
                    return child
                end
            end
        end
    end

    if cd.GetRegions then
        local ok, regions = pcall(function() return { cd:GetRegions() } end)
        if ok and regions then
            for _, region in ipairs(regions) do
                if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                    return region
                end
            end
        end
    end

    return nil
end

local function ApplyLiveTextColors(viewer, chargeKey, cooldownKey)
    if not viewer or not viewer:IsShown() then return end

    local cr, cg, cb, ca = GetColorRGBA(chargeKey)
    local dr, dg, db, da = GetColorRGBA(cooldownKey)

    local function ApplyIcon(icon)
        if not icon then return end
        local chargeText = FindChargeText(icon)
        if chargeText and chargeText.SetTextColor then
            pcall(chargeText.SetTextColor, chargeText, cr, cg, cb, ca)
        end
        local cooldownText = FindCooldownText(icon)
        if cooldownText and cooldownText.SetTextColor then
            pcall(cooldownText.SetTextColor, cooldownText, dr, dg, db, da)
        end
    end

    local pool = viewer.itemFramePool
    if pool and pool.EnumerateActive then
        for icon in pool:EnumerateActive() do
            ApplyIcon(icon)
        end
        return
    end

    local container = viewer.viewerFrame or viewer
    if type(container) == "string" then
        container = _G[container]
    end
    if container and container.GetChildren then
        for _, child in ipairs({ container:GetChildren() }) do
            if child and (child.Icon or child.icon or child.Cooldown or child.cooldown) then
                ApplyIcon(child)
            end
        end
    end
end

local function Refresh()
    -- Refresh all modules that display charge/cooldown text
    local function ForceReskinPool(viewer, skinOwner, skinMethod, settings)
        if not viewer or not viewer:IsShown() or not skinOwner or type(skinOwner[skinMethod]) ~= "function" then
            return
        end

        local pool = viewer.itemFramePool
        if pool and pool.EnumerateActive then
            for icon in pool:EnumerateActive() do
                if icon then
                    pcall(skinOwner[skinMethod], skinOwner, icon, settings)
                end
            end
            return
        end

        local container = viewer.viewerFrame or viewer
        if type(container) == "string" then
            container = _G[container]
        end
        if container and container.GetChildren then
            for _, child in ipairs({ container:GetChildren() }) do
                if child and (child.Icon or child.icon or child.Cooldown or child.cooldown) then
                    pcall(skinOwner[skinMethod], skinOwner, child, settings)
                end
            end
        end
    end

    local buffViewer = _G["BuffIconCooldownViewer"]
    local buffSettings = DYNAMICICONS and DYNAMICICONS.GetSettings and DYNAMICICONS:GetSettings()
    ForceReskinPool(buffViewer, _G.BuffIconViewers, "SkinIcon", buffSettings)
    ApplyLiveTextColors(buffViewer, "TextColor_ChargeText_Buff", "TextColor_CooldownText_Buff")
    if buffViewer and buffViewer:IsShown() and _G.BuffIconViewers and _G.BuffIconViewers.ApplyViewerLayout then
        pcall(_G.BuffIconViewers.ApplyViewerLayout, _G.BuffIconViewers, buffViewer)
    end

    if DYNAMICICONS and DYNAMICICONS.RefreshLayout then
        DYNAMICICONS:RefreshLayout()
    end

    local essentialViewer = _G["EssentialCooldownViewer"]
    local essentialSettings = MyEssentialBuffTracker and MyEssentialBuffTracker.GetSettings and MyEssentialBuffTracker:GetSettings()
    ForceReskinPool(essentialViewer, _G.MyEssentialIconViewers, "SkinIcon", essentialSettings)
    ApplyLiveTextColors(essentialViewer, "TextColor_ChargeText_Essential", "TextColor_CooldownText_Essential")
    if essentialViewer and essentialViewer:IsShown() and _G.MyEssentialIconViewers and _G.MyEssentialIconViewers.ApplyViewerLayout then
        pcall(_G.MyEssentialIconViewers.ApplyViewerLayout, _G.MyEssentialIconViewers, essentialViewer)
    end

    if MyEssentialBuffTracker and MyEssentialBuffTracker.RefreshEssentialLayout then
        MyEssentialBuffTracker:RefreshEssentialLayout()
    end

    local utilityViewer = _G["UtilityCooldownViewer"]
    local utilitySettings = MyUtilityBuffTracker and MyUtilityBuffTracker.GetSettings and MyUtilityBuffTracker:GetSettings()
    ForceReskinPool(utilityViewer, _G.UtilityIconViewers, "SkinIcon", utilitySettings)
    ApplyLiveTextColors(utilityViewer, "TextColor_ChargeText_Utility", "TextColor_CooldownText_Utility")
    if utilityViewer and utilityViewer:IsShown() and _G.UtilityIconViewers and _G.UtilityIconViewers.ApplyViewerLayout then
        pcall(_G.UtilityIconViewers.ApplyViewerLayout, _G.UtilityIconViewers, utilityViewer)
    end

    if MyUtilityBuffTracker and MyUtilityBuffTracker.RefreshUtilityLayout then
        MyUtilityBuffTracker:RefreshUtilityLayout()
    end

    local aceRegistry = LibStub and LibStub("AceConfigRegistry-3.0", true)
    if aceRegistry then
        pcall(aceRegistry.NotifyChange, aceRegistry, "CkraigCooldownManager")
    end
end

local function ColorGet(key)
    return function()
        local db = GetDB()
        local c = db and db[key]
        if c then
            return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 1, c.a or c[4] or 1
        end
        return 1, 1, 1, 1
    end
end

local function ColorSet(key)
    return function(_, r, g, b, a)
        local db = GetDB()
        if db then
            db[key] = {r = r, g = g, b = b, a = a}
            -- Sync to _G.CooldownChargeDB (array format) so tracker
            -- SkinIcon functions read the updated color immediately
            if type(_G.CooldownChargeDB) ~= "table" then _G.CooldownChargeDB = {} end
            _G.CooldownChargeDB[key] = {r, g, b, a}
            Refresh()
        end
    end
end

function ChargeTextColorOptions:OnProfileChanged()
    SyncChargeColorDB()
    Refresh()
end

-- Initialize sync once on file load so reloads start with consistent values.
SyncChargeColorDB()

function CCM.BuildChargeTextColorOptions()
    CCM.AceOptionsTable.args.chargeTextColors = {
        type = "group",
        name = "Charge Text Colors",
        order = 85,
        args = {
            headerCooldown = {
                type = "header",
                name = "Cooldown Text Colors",
                order = 1,
            },
            buffCooldownColor = {
                type = "color",
                name = "Buff Cooldown Color",
                order = 2,
                hasAlpha = true,
                get = ColorGet("TextColor_CooldownText_Buff"),
                set = ColorSet("TextColor_CooldownText_Buff"),
            },
            essentialCooldownColor = {
                type = "color",
                name = "Essential Cooldown Color",
                order = 3,
                hasAlpha = true,
                get = ColorGet("TextColor_CooldownText_Essential"),
                set = ColorSet("TextColor_CooldownText_Essential"),
            },
            utilityCooldownColor = {
                type = "color",
                name = "Utility Cooldown Color",
                order = 4,
                hasAlpha = true,
                get = ColorGet("TextColor_CooldownText_Utility"),
                set = ColorSet("TextColor_CooldownText_Utility"),
            },
            headerCharge = {
                type = "header",
                name = "Charge/Stack Text Colors",
                order = 10,
            },
            buffChargeColor = {
                type = "color",
                name = "Buff Charge/Stack Color",
                order = 11,
                hasAlpha = true,
                get = ColorGet("TextColor_ChargeText_Buff"),
                set = ColorSet("TextColor_ChargeText_Buff"),
            },
            essentialChargeColor = {
                type = "color",
                name = "Essential Charge/Stack Color",
                order = 12,
                hasAlpha = true,
                get = ColorGet("TextColor_ChargeText_Essential"),
                set = ColorSet("TextColor_ChargeText_Essential"),
            },
            utilityChargeColor = {
                type = "color",
                name = "Utility Charge/Stack Color",
                order = 13,
                hasAlpha = true,
                get = ColorGet("TextColor_ChargeText_Utility"),
                set = ColorSet("TextColor_ChargeText_Utility"),
            },
            headerReset = {
                type = "header",
                name = "",
                order = 20,
            },
            resetAll = {
                type = "execute",
                name = "Reset All Colors to Default",
                order = 21,
                func = function()
                    local db = GetDB()
                    if db then
                        for _, key in ipairs(COLOR_KEYS) do
                            db[key] = { r = 1, g = 1, b = 1, a = 1 }
                        end
                        SyncChargeColorDB()
                        Refresh()
                    end
                end,
                confirm = true,
                confirmText = "Reset all charge/cooldown text colors to white?",
            },
        },
    }
end
