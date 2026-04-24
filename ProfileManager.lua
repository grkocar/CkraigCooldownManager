-- luacheck: globals CkraigCooldownManager DYNAMICICONS MyEssentialBuffTracker MyUtilityBuffTracker ChargeTextColorOptions PowerPotionSuccessIcon CCM_SegmentBars

local addonName, addon = ...
local ProfileManager = LibStub("AceAddon-3.0"):NewAddon(addonName.."ProfileManager", "AceEvent-3.0")
local AceDBOptions
local LibDualSpec = LibStub("LibDualSpec-1.0", true) -- true = silent fail if not found

-- Default settings for all modules
local defaults = {
    profile = {
        -- Cooldown Bars settings (from CCM_CooldownBars.lua)
        buffBars = {
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
            hideBarName = false,
            hideIcons = false,
            timerTextAlign = "RIGHT",
            timerTextFontSize = 11,
        },
        -- Dynamic Icons settings (from DYNAMICICONS.lua)
        dynamicIcons = {
            enabled = true,
            columns = 3,
            hSpacing = 2,
            vSpacing = 2,
            growUp = true,
            locked = true,
            iconSize = 36,
            aspectRatio = "1:1",
            aspectRatioCrop = nil,
            spacing = 0,
            rowLimit = 0,
            rowGrowDirection = "up",
            iconCornerRadius = 1,
            cooldownTextSize = 16,
            cooldownTextPosition = "CENTER",
            cooldownTextX = 0,
            cooldownTextY = 0,
            chargeTextSize = 18,
            chargeTextPosition = "TOP",
            chargeTextX = 0,
            chargeTextY = 13,
            cooldownTextFont = "Friz Quadrata TT",
            showCooldownText = true,
            showChargeText = true,
            hideWhenMounted = false,
            cooldownTextColor = {r = 1, g = 1, b = 1, a = 1},
            borderSize = 1,
            borderColor = {r = 0, g = 0, b = 0, a = 1},
            backgroundColor = {r = 0, g = 0, b = 0, a = 0.5},
            staticGridMode = false,
            gridRows = 4,
            gridColumns = 4,
            gridSlotMap = {},
            rowSizes = {},
        },
        -- Essential Buffs settings (from MyEssentialBuffTracker.lua)
        essentialBuffs = {
            enabled = true,
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

            -- Border
            borderSize = 1,
            borderColor = {0, 0, 0, 1},
        },
        -- Utility Buffs settings (from MyUtilityBuffTracker.lua)
        utilityBuffs = {
            enabled = true,
            columns = 3,
            hSpacing = 2,
            vSpacing = 2,
            growUp = true,
            locked = true,
            iconSize = 36,
            aspectRatio = "1:1",
            aspectRatioCrop = nil,
            spacing = 0,
            rowLimit = 0,
            rowGrowDirection = "down",
            iconCornerRadius = 1,
            cooldownTextSize = 16,
            cooldownTextPosition = "CENTER",
            cooldownTextX = 0,
            cooldownTextY = 0,
            chargeTextSize = 14,
            chargeTextPosition = "BOTTOMRIGHT",
            chargeTextX = 0,
            chargeTextY = 0,
            showCooldownText = true,
            showChargeText = true,
            hideWhenMounted = false,
            staticGridMode = false,
            gridRows = 4,
            gridColumns = 4,
            gridSlotMap = {},
            rowSizes = {},
        },
        -- Charge Text Colors settings (from ChargeTextColorOptions.lua)
        chargeTextColors = {
            -- Add charge text color settings here
        },
        -- Power Potion Success Icon settings (from PowerPotionSuccessIcon.lua)
        powerPotionSuccessIcon = {
            enabled = true,
            iconSize = 36,
            positionX = 200,
            positionY = 0,
            locked = true,
            clusterIndex = 1,
            frameStrata = "BACKGROUND",
            showInDynamic = false,
            showTimer = true,
            powerPotionsList = {431932, 370816, 1236616, 1238443, 1236652, 1236994, 1236998, 1236551},
            timerDurations = {
                [431932] = 30,
                [370816] = 30,
                [1236616] = 30,
                [1238443] = 30,
                [1236652] = 30,
                [1236994] = 30,
                [1236998] = 30,
                [1236551] = 30,
            },
        },
        -- Segment Bars settings (from SegmentBars.lua)
        segmentBars = {
            enabled = true,
            hideWhenMounted = false,
            barWidth = 140,
            barHeight = 20,
            barSpacing = 4,
            anchorX = 0,
            anchorY = -180,
            locked = true,
            fillingTexture = "Blizzard Raid Bar",
            tickTexture = "Blizzard Raid Bar",
            tickWidth = 2,
            tickColor = { 0, 0, 0, 1 },
            bgColor = { 0.08, 0.08, 0.08, 0.75 },
            frameStrata = "LOW",
            showLabel = true,
            labelFontSize = 11,
            labelFont = "Friz Quadrata TT",
            spells = {},
        },
    },
}

function ProfileManager:OnInitialize()
    -- Load AceDBOptions here to ensure libraries are loaded
    AceDBOptions = LibStub("AceDBOptions-3.0")
    if not AceDBOptions then
        error("AceDBOptions-3.0 not found. Please ensure the library is properly loaded.")
        return
    end
    
    -- Initialize the main database
    self.db = LibStub("AceDB-3.0"):New("CkraigCooldownManagerDB", defaults, true)

    -- Enable per-spec profiles with LibDualSpec
    if LibDualSpec then
        LibDualSpec:EnhanceDatabase(self.db, "CkraigCooldownManager")
    end

    -- Fix corrupted profile name
    local currentProfile = self.db:GetCurrentProfile()
    if string.find(currentProfile, "CKRAIG") or string.find(currentProfile, "ckraig") then
        self.db:SetProfile("Default")
    end

    -- Ensure defaults are applied to current profile
    self:EnsureDefaults()

    if _G.CCM_SyncChargeTextColorDB then
        _G.CCM_SyncChargeTextColorDB()
    end

    -- Register for profile changes
    self.db.RegisterCallback(self, "OnProfileChanged", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileCopied", "OnProfileChanged")
    self.db.RegisterCallback(self, "OnProfileReset", "OnProfileChanged")
    
    -- Create profile options immediately
    self:CreateProfileOptions()
end

local function DeepCopy(orig)
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = (type(v) == "table") and DeepCopy(v) or v
    end
    return copy
end

function ProfileManager:EnsureDefaults()
    -- Ensure all default values are present in the current profile
    -- Use rawget so we don't mistake AceDB's __index default passthrough for a real saved value
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

function ProfileManager:CreateProfileOptions()
    -- Try to load libraries with error checking
    local AceConfig = LibStub("AceConfig-3.0")
    local AceConfigDialog = LibStub("AceConfigDialog-3.0")
    local AceSerializer = LibStub("AceSerializer-3.0")
    
    if not AceConfig or not AceConfigDialog then
        print("ProfileManager: AceConfig libraries not available, profile management disabled")
        return
    end
    
    local options = AceDBOptions:GetOptionsTable(self.db)
    AceConfig:RegisterOptionsTable("CkraigCooldownManager Profiles", options)
    
    -- Add per-spec profile options from LibDualSpec
    if LibDualSpec then
        LibDualSpec:EnhanceOptions(options, self.db)
    end

    -- Add import/export functionality
    if AceSerializer then
        -- Define export popup dialog

        local function GetEditBox(self)
            return self.editBox or self.EditBox
        end

        StaticPopupDialogs["CKRAIG_PROFILE_EXPORT"] = {
            text = "Copy this profile export string:",
            button1 = "Close",
            hasEditBox = true,
            editBoxWidth = 400,
            OnShow = function(self, data)
                -- Fallback: if data is nil, try to get the export string again
                if not data or data == "" then
                    if ProfileManager and ProfileManager.db and ProfileManager.db.profile then
                        data = LibStub("AceSerializer-3.0"):Serialize(ProfileManager.db.profile)
                        self.data = data
                    end
                end
                local box = GetEditBox(self)
                if box then
                    box:SetText(data or "")
                    box:HighlightText()
                    box:SetFocus()
                end
            end,
            OnAccept = function() end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }

        StaticPopupDialogs["CKRAIG_PROFILE_IMPORT"] = {
            text = "Paste the profile import string:",
            button1 = "Import",
            button2 = "Cancel",
            hasEditBox = true,
            editBoxWidth = 400,
            OnShow = function(self)
                local box = GetEditBox(self)
                if box then
                    box:SetText("")
                    box:SetFocus()
                end
            end,
            OnAccept = function(self)
                local box = GetEditBox(self)
                local value = box and box:GetText() or ""
                local success, data = AceSerializer:Deserialize(value)
                if success and type(data) == "table" then
                    -- Overwrite all keys in the current profile with the imported data
                    for k in pairs(ProfileManager.db.profile) do
                        ProfileManager.db.profile[k] = nil
                    end
                    for k, v in pairs(data) do
                        ProfileManager.db.profile[k] = v
                    end
                    ProfileManager:EnsureDefaults()
                    ProfileManager:OnProfileChanged()
                    print("Profile imported and applied successfully.")
                else
                    print("Invalid import string")
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }

        options.args.currentprofile = {
            type = "description",
            name = function() return "Profile: " .. ProfileManager.db:GetCurrentProfile() end,
            order = 50,
        }

        options.args.importexport = {
            type = "group",
            name = "Import/Export",
            order = 100,
            args = {
                export = {
                    type = "execute",
                    name = "Export Profile",
                    desc = "Opens a popup with the export string to copy",
                    func = function()
                        local serialized = AceSerializer:Serialize(ProfileManager.db.profile)
                        StaticPopup_Show("CKRAIG_PROFILE_EXPORT", serialized)
                    end,
                },
                import = {
                    type = "execute",
                    name = "Import Profile",
                    desc = "Opens a popup to paste an import string",
                    func = function()
                        StaticPopup_Show("CKRAIG_PROFILE_IMPORT")
                    end,
                },
            },
        }
    end

    -- Register as standalone panel (can't use subcategory because parent uses Settings API, not AceConfigDialog)
    if not _G.CkraigProfileManagerPanel or not _G.CkraigProfileManagerPanel._addedToOptions then
        local panel = AceConfigDialog:AddToBlizOptions("CkraigCooldownManager Profiles", "Ckraig Profiles")
        _G.CkraigProfileManagerPanel = panel
        self.profilePanel = panel
        panel._addedToOptions = true
    else
        self.profilePanel = _G.CkraigProfileManagerPanel
    end
end

function ProfileManager:OnProfileChanged()
    -- Ensure defaults are applied to the new profile
    self:EnsureDefaults()

    if _G.CCM_SyncChargeTextColorDB then
        _G.CCM_SyncChargeTextColorDB()
    end
    
    -- Notify other modules of profile change
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

-- Provide access to profile data for other modules
function ProfileManager:GetProfileData(moduleName)
    if not self.db or not self.db.profile then
        -- Not initialized yet, return empty table to avoid error
        return {}
    end
    return self.db.profile[moduleName]
end

function ProfileManager:SetProfileData(moduleName, data)
    if not self.db or not self.db.profile then
        -- Not initialized yet, do nothing
        return
    end
    self.db.profile[moduleName] = data
end

-- Global access function
_G.CkraigProfileManager = ProfileManager