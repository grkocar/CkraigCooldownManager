-- ============================================================
-- CkraigCooldownManager :: Profiles :: ProfileManager
-- ============================================================
-- AceDB profile management: initialisation, defaults merging,
-- and notifying every module when the active profile changes.
-- ============================================================

local addonName, addon = ...
local ProfileManager = LibStub("AceAddon-3.0"):NewAddon(addonName .. "ProfileManager", "AceEvent-3.0")
local AceDBOptions
local LibDualSpec = LibStub("LibDualSpec-1.0", true)

-- Pull the defaults table created in profiles/Defaults.lua
local CCM = _G.CkraigCooldownManager
local defaults = CCM.ProfileDefaults and CCM.ProfileDefaults.defaults or { profile = {} }

-- ============================================================
-- Helpers
-- ============================================================
local function DeepCopy(orig)
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = (type(v) == "table") and DeepCopy(v) or v
    end
    return copy
end

-- ============================================================
-- Lifecycle
-- ============================================================
function ProfileManager:OnInitialize()
    AceDBOptions = LibStub("AceDBOptions-3.0")
    if not AceDBOptions then
        error("AceDBOptions-3.0 not found. Please ensure the library is properly loaded.")
        return
    end

    self.db = LibStub("AceDB-3.0"):New("CkraigCooldownManagerDB", defaults, true)

    if LibDualSpec then
        LibDualSpec:EnhanceDatabase(self.db, "CkraigCooldownManager")
    end

    -- Fix corrupted profile name
    local currentProfile = self.db:GetCurrentProfile()
    if string.find(currentProfile, "CKRAIG") or string.find(currentProfile, "ckraig") then
        self.db:SetProfile("Default")
    end

    self:EnsureDefaults()

    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")

    self:CreateProfileOptions()
end

function ProfileManager:EnsureDefaults()
    for moduleName, moduleDefaults in pairs(defaults.profile) do
        if rawget(self.db.profile, moduleName) == nil then
            self.db.profile[moduleName] = DeepCopy(moduleDefaults)
        else
            for key, value in pairs(moduleDefaults) do
                if rawget(self.db.profile[moduleName], key) == nil then
                    self.db.profile[moduleName][key] = (type(value) == "table") and DeepCopy(value) or value
                end
            end
        end
    end
end

-- ============================================================
-- Profile change notification
-- ============================================================
function ProfileManager:OnProfileChanged()
    self:EnsureDefaults()

    if CkraigCooldownManager and CkraigCooldownManager.OnProfileChanged then
        CkraigCooldownManager:OnProfileChanged()
    end
    if DYNAMICICONS and DYNAMICICONS.OnProfileChanged then
        DYNAMICICONS:OnProfileChanged()
    end
    if MyEssentialBuffTracker and MyEssentialBuffTracker.OnProfileChanged then
        MyEssentialBuffTracker:OnProfileChanged()
    end
    if MyUtilityBuffTracker and MyUtilityBuffTracker.OnProfileChanged then
        MyUtilityBuffTracker:OnProfileChanged()
    end
    if ChargeTextColorOptions and ChargeTextColorOptions.OnProfileChanged then
        ChargeTextColorOptions:OnProfileChanged()
    end
    if PowerPotionSuccessIcon and PowerPotionSuccessIcon.OnProfileChanged then
        PowerPotionSuccessIcon:OnProfileChanged()
    end
    if _G.CCM_SegmentBars and _G.CCM_SegmentBars.OnProfileChanged then
        _G.CCM_SegmentBars:OnProfileChanged()
    end
end

-- ============================================================
-- Data accessors for other modules
-- ============================================================
function ProfileManager:GetProfileData(moduleName)
    if not self.db or not self.db.profile then return {} end
    return self.db.profile[moduleName]
end

function ProfileManager:SetProfileData(moduleName, data)
    if not self.db or not self.db.profile then return end
    self.db.profile[moduleName] = data
end

-- Global reference for cross-file access
_G.CkraigProfileManager = ProfileManager
