


-- IMPORTANT: To persist color settings, add this line to your .toc file:
-- SavedVariables: CooldownChargeDB

_G.ChargeTextColorOptionsPanel = CreateFrame("Frame", "ChargeTextColorOptionsPanel", UIParent)
_G.ChargeTextColorOptionsPanel.name = "Charge Text Colors"

_G.CooldownChargeDB = _G.CooldownChargeDB or {}

-- Define ChargeTextColorOptions as a table
ChargeTextColorOptions = ChargeTextColorOptions or {}

-- Profile system integration
local function InitializeDB()
    -- No registration needed - ProfileManager calls OnProfileChanged directly
end

function ChargeTextColorOptions:GetSettings()
    if CkraigProfileManager and CkraigProfileManager.db and CkraigProfileManager.db.profile then
        return CkraigProfileManager.db.profile.chargeTextColors
    end
    -- Fallback to global DB
    return _G.CooldownChargeDB
end



local function GetCooldownChargeDB()
    if type(_G.CooldownChargeDB) ~= "table" then _G.CooldownChargeDB = {} end
    return _G.CooldownChargeDB
end

local function ClearIconSkinCache(viewer)
    return
end

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
    -- Buffs
    if _G.BuffIconViewers and _G.BuffIconCooldownViewer then
        ClearIconSkinCache(_G.BuffIconCooldownViewer)
        if _G.BuffIconViewers.ForceReskinViewer then
            _G.BuffIconViewers:ForceReskinViewer(_G.BuffIconCooldownViewer)
        end
        if _G.BuffIconViewers.ApplyViewerLayout then
            pcall(function() _G.BuffIconViewers:ApplyViewerLayout(_G.BuffIconCooldownViewer) end)
        end
    end
    -- Essentials
    if _G.MyEssentialIconViewers and _G.EssentialCooldownViewer then
        ClearIconSkinCache(_G.EssentialCooldownViewer)
        if _G.MyEssentialIconViewers.ForceReskinViewer then
            _G.MyEssentialIconViewers:ForceReskinViewer(_G.EssentialCooldownViewer)
        end
        if _G.MyEssentialIconViewers.ApplyViewerLayout then
            pcall(function() _G.MyEssentialIconViewers:ApplyViewerLayout(_G.EssentialCooldownViewer) end)
        end
    end
    -- Utility
    if _G.UtilityIconViewers and _G.UtilityCooldownViewer then
        ClearIconSkinCache(_G.UtilityCooldownViewer)
        if _G.UtilityIconViewers.ForceReskinViewer then
            _G.UtilityIconViewers:ForceReskinViewer(_G.UtilityCooldownViewer)
        end
        if _G.UtilityIconViewers.ApplyViewerLayout then
            pcall(function() _G.UtilityIconViewers:ApplyViewerLayout(_G.UtilityCooldownViewer) end)
        end
    end

end

function ChargeTextColorOptions:OnProfileChanged()
    -- Use throttled reskin to avoid redundant calls
    ThrottledReskinAllViewers()
end

local function ShowColorPicker(groupName)
    local settings = ChargeTextColorOptions:GetSettings()
    local current = settings["TextColor_" .. groupName] or {1,1,1,1}
    local r, g, b, a = unpack(current)
    local function openOptionsPanel()
        if _G.Settings and _G.Settings.GetCategory and _G.Settings.OpenToCategory and _G.ChargeTextColorOptionsPanel then
            local cat = _G.Settings.GetCategory(_G.ChargeTextColorOptionsPanel)
            if cat and cat.ID then
                _G.Settings.OpenToCategory(cat.ID)
            end
        elseif _G.InterfaceOptionsFrame_OpenToCategory and _G.ChargeTextColorOptionsPanel then
            _G.InterfaceOptionsFrame_OpenToCategory(_G.ChargeTextColorOptionsPanel)
        end
    end
    local function setColor(newR, newG, newB, newA)
        local db = ChargeTextColorOptions:GetSettings()
        db["TextColor_" .. groupName] = {newR, newG, newB, newA}
        _G.CooldownChargeDB = db -- ensure global is updated for backward compatibility
    end
    local function onCancel()
        openOptionsPanel()
    end
    if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            swatchFunc = function()
                local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                local newA = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or 1
                setColor(newR, newG, newB, newA)
                ThrottledReskinAllViewers()
            end,
            opacityFunc = function()
                local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                local newA = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or 1
                setColor(newR, newG, newB, newA)
                ThrottledReskinAllViewers()
            end,
            hasOpacity = true,
            opacity = a,
            r = r,
            g = g,
            b = b,
        })
    end
end

local function CreateChargeTextColorOptionsUI()
    -- Add a background for visibility
    local bg = _G.ChargeTextColorOptionsPanel:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0.1, 0.1, 0.1, 0.7)
    bg:SetAllPoints(_G.ChargeTextColorOptionsPanel)

    local title = _G.ChargeTextColorOptionsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Charge Text Color Options")

    -- Profile selector
    if CkraigProfileManager and CkraigProfileManager.db then
        local profileLabel = _G.ChargeTextColorOptionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        profileLabel:SetPoint("TOPRIGHT", _G.ChargeTextColorOptionsPanel, "TOPRIGHT", -16, -16)
        profileLabel:SetText("Profile:")
        local profileDropdown = CreateFrame("DropdownButton", nil, _G.ChargeTextColorOptionsPanel, "WowStyle1DropdownTemplate")
        profileDropdown:SetPoint("TOPRIGHT", profileLabel, "BOTTOMRIGHT", 0, -2)
        profileDropdown:SetWidth(170)
        profileDropdown:SetupMenu(function(dd, rootDescription)
            if not CkraigProfileManager or not CkraigProfileManager.db then return end
            local profiles = CkraigProfileManager.db:GetProfiles()
            local current = CkraigProfileManager.db:GetCurrentProfile()
            for _, name in ipairs(profiles) do
                rootDescription:CreateRadio(
                    name,
                    function() return name == CkraigProfileManager.db:GetCurrentProfile() end,
                    function() CkraigProfileManager.db:SetProfile(name) end,
                    name
                )
            end
        end)
    end

    -- Add section labels for clarity
    local cooldownLabel = _G.ChargeTextColorOptionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    cooldownLabel:SetPoint("TOPLEFT", 32, -48)
    cooldownLabel:SetText("Cooldown Text Colors")

    local chargeLabel = _G.ChargeTextColorOptionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    chargeLabel:SetPoint("TOPLEFT", 240, -48)
    chargeLabel:SetText("Charge/Stack Text Colors")

    local groups = {"Buff", "Essential", "Utility"}
    for i, group in ipairs(groups) do
        -- Cooldown text color picker
        local cdBtn = CreateFrame("Button", nil, _G.ChargeTextColorOptionsPanel, "UIPanelButtonTemplate")
        cdBtn:SetSize(180, 30)
        cdBtn:SetPoint("TOPLEFT", 32, -80 - (i-1)*40)
        cdBtn:SetText("Pick " .. group .. " Cooldown Color")
        cdBtn:SetScript("OnClick", function()
            ShowColorPicker("CooldownText_" .. group)
        end)

        -- Charge/stack text color picker
        local stackBtn = CreateFrame("Button", nil, _G.ChargeTextColorOptionsPanel, "UIPanelButtonTemplate")
        stackBtn:SetSize(180, 30)
        stackBtn:SetPoint("TOPLEFT", 240, -80 - (i-1)*40)
        stackBtn:SetText("Pick " .. group .. " Charge/Stack Color")
        stackBtn:SetScript("OnClick", function()
            ShowColorPicker("ChargeText_" .. group)
        end)
    end
end

_G.CCM_CreateChargeTextColorOptionsUI = CreateChargeTextColorOptionsUI

