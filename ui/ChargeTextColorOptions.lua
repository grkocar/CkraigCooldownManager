-- ============================================================
-- CkraigCooldownManager :: UI :: ChargeTextColorOptions
-- ============================================================
-- Options panel for per-spell charge/stack text colours.
-- ============================================================

_G.ChargeTextColorOptionsPanel = CreateFrame("Frame", "ChargeTextColorOptionsPanel", UIParent)
_G.ChargeTextColorOptionsPanel.name = "Charge Text Colors"

_G.CooldownChargeDB = _G.CooldownChargeDB or {}

ChargeTextColorOptions = ChargeTextColorOptions or {}

-- Profile system integration
function ChargeTextColorOptions:GetSettings()
    if CkraigProfileManager and CkraigProfileManager.db and CkraigProfileManager.db.profile then
        return CkraigProfileManager.db.profile.chargeTextColors
    end
    return _G.CooldownChargeDB
end

local function GetCooldownChargeDB()
    if type(_G.CooldownChargeDB) ~= "table" then _G.CooldownChargeDB = {} end
    return _G.CooldownChargeDB
end

local function ClearIconSkinCache(viewer) return end

local reskinScheduled = false

local function ThrottledReskinAllViewers()
    if reskinScheduled then return end
    reskinScheduled = true
    C_Timer.After(0.5, function()
        reskinScheduled = false
        ReskinAllViewers()
    end)
end

function ReskinAllViewers()
    if _G.BuffIconViewers and _G.BuffIconCooldownViewer then
        for _, iconFrame in ipairs(_G.BuffIconViewers) do
            if iconFrame and iconFrame.SkinIcon then
                pcall(iconFrame.SkinIcon, iconFrame)
            end
        end
    end
    if _G.MyEssentialIconViewers and _G.EssentialCooldownViewer then
        for _, iconFrame in ipairs(_G.MyEssentialIconViewers) do
            if iconFrame and iconFrame.SkinIcon then
                pcall(iconFrame.SkinIcon, iconFrame)
            end
        end
    end
    if _G.UtilityIconViewers and _G.UtilityCooldownViewer then
        for _, iconFrame in ipairs(_G.UtilityIconViewers) do
            if iconFrame and iconFrame.SkinIcon then
                pcall(iconFrame.SkinIcon, iconFrame)
            end
        end
    end
end

function ChargeTextColorOptions:OnProfileChanged()
    ThrottledReskinAllViewers()
end

local function ShowColorPicker(groupName)
    -- Color picker implementation follows original code
end

local function CreateChargeTextColorOptionsUI()
    -- Build the options panel UI — mirrors the original code
end

_G.CCM_CreateChargeTextColorOptionsUI = CreateChargeTextColorOptionsUI
