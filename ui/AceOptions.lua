-- ============================================================
-- CkraigCooldownManager :: UI :: AceOptions
-- ============================================================
-- Central Ace3 AceConfig registration hub.
-- Replaces ALL hand-built Blizzard Settings API panels with
-- declarative AceConfig options tables rendered by AceConfigDialog.
-- ============================================================

local addonName, addon = ...
local CCM = _G.CkraigCooldownManager
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceDBOptions = LibStub("AceDBOptions-3.0")
local LSM = LibStub("LibSharedMedia-3.0")

-- ============================================================
-- Shared position anchor values
-- ============================================================
local POSITION_VALUES = {
    CENTER      = "Center",
    TOP         = "Top",
    BOTTOM      = "Bottom",
    LEFT        = "Left",
    RIGHT       = "Right",
    TOPLEFT     = "Top Left",
    TOPRIGHT    = "Top Right",
    BOTTOMLEFT  = "Bottom Left",
    BOTTOMRIGHT = "Bottom Right",
}

local GLOW_TYPE_VALUES = {
    pixel    = "Pixel",
    autocast = "Autocast",
    button   = "Button Glow",
    proc     = "Proc Glow",
}

local FRAME_STRATA_VALUES = {
    BACKGROUND = "BACKGROUND",
    LOW        = "LOW",
    MEDIUM     = "MEDIUM",
    HIGH       = "HIGH",
    DIALOG     = "DIALOG",
}

local DIRECTION_VALUES = {
    RIGHT = "Right",
    LEFT  = "Left",
    UP    = "Up",
    DOWN  = "Down",
}

local FLOW_VALUES = {
    horizontal = "Horizontal",
    vertical   = "Vertical",
}

local GROW_VALUES = {
    up   = "Grow Up",
    down = "Grow Down",
}

local TIMER_ALIGN_VALUES = {
    LEFT   = "Left",
    CENTER = "Center",
    RIGHT  = "Right",
}

-- ============================================================
-- Shared helpers
-- ============================================================
local function GetProfileDB()
    if _G.CkraigProfileManager and _G.CkraigProfileManager.db then
        return _G.CkraigProfileManager.db
    end
    return nil
end

local function GetProfileData(section)
    local db = GetProfileDB()
    if db and db.profile and db.profile[section] then
        return db.profile[section]
    end
    return nil
end

-- Helper to build a getter/setter pair for profile-based settings
local function ProfileGetSet(section, callbacks)
    callbacks = callbacks or {}
    return {
        get = function(info)
            local s = GetProfileData(section)
            if not s then return nil end
            local key = info[#info]
            local val = s[key]
            -- For color type, AceConfig expects r,g,b,a returns
            if info.type == "color" then
                if type(val) == "table" then
                    return val.r or val[1] or 1, val.g or val[2] or 1, val.b or val[3] or 1, val.a or val[4] or 1
                end
                return 1, 1, 1, 1
            end
            return val
        end,
        set = function(info, ...)
            local s = GetProfileData(section)
            if not s then return end
            local key = info[#info]
            if info.type == "color" then
                local r, g, b, a = ...
                s[key] = {r = r, g = g, b = b, a = a}
            else
                s[key] = ...
            end
            if callbacks.refresh then callbacks.refresh() end
        end,
    }
end

-- Helper to get LSM font names as a values table
local function GetFontValues()
    local fonts = {}
    for _, name in ipairs(LSM:List("font")) do
        fonts[name] = name
    end
    return fonts
end

-- Helper to get LSM statusbar texture names
local function GetTextureValues()
    local textures = {}
    for _, name in ipairs(LSM:List("statusbar")) do
        textures[name] = name
    end
    return textures
end

-- ============================================================
-- Expose shared values/helpers for per-module options files
-- ============================================================
CCM.AceOpts = {
    POSITION_VALUES      = POSITION_VALUES,
    GLOW_TYPE_VALUES     = GLOW_TYPE_VALUES,
    FRAME_STRATA_VALUES  = FRAME_STRATA_VALUES,
    DIRECTION_VALUES     = DIRECTION_VALUES,
    FLOW_VALUES          = FLOW_VALUES,
    GROW_VALUES          = GROW_VALUES,
    TIMER_ALIGN_VALUES   = TIMER_ALIGN_VALUES,
    GetProfileDB         = GetProfileDB,
    GetProfileData       = GetProfileData,
    ProfileGetSet        = ProfileGetSet,
    GetFontValues        = GetFontValues,
    GetTextureValues     = GetTextureValues,
    LSM                  = LSM,
}

-- ============================================================
-- Master options table — sub-modules inject their groups
-- ============================================================
CCM.AceOptionsTable = {
    type = "group",
    name = "Ckraig Cooldown Manager",
    childGroups = "tab",
    args = {},
}

-- ============================================================
-- Registration (called after all option sub-tables are built)
-- ============================================================
local registeredOnce = false

local function TrimInput(input)
    if type(input) ~= "string" then return "" end
    if strtrim then
        return strtrim(input)
    end
    return input:match("^%s*(.-)%s*$")
end

local function RegisterAllOptions()
    if registeredOnce then return end
    registeredOnce = true

    -- ---- Minimap tab (minimap toggle etc.) ----
    CCM.AceOptionsTable.args.minimap = {
        type  = "group",
        name  = "Minimap",
        order = 901,
        args  = {
            showMinimapButton = {
                type    = "toggle",
                name    = "Show Minimap Button",
                desc    = "Show or hide the CkraigCooldownManager minimap button.",
                order   = 1,
                get     = function() return CCM_Settings.showMinimapButton ~= false end,
                set     = function(_, val)
                    CCM_Settings.showMinimapButton = val
                    local btn = _G.CkraigCDM_MinimapButtonRef
                    if btn then
                        if val then btn:Show() else btn:Hide() end
                    end
                end,
            },
            socialHeader = {
                type = "header",
                name = "Socials",
                order = 10,
            },
            discordIcon = {
                type = "description",
                name = " ",
                order = 10.5,
                width = 0.25,
                image = "Interface\\AddOns\\CkraigCooldownManager\\discord",
                imageWidth = 64,
                imageHeight = 64,
            },
            discordLink = {
                type = "input",
                name = "Discord",
                desc = "Join the Discord community! Select and copy this link.",
                order = 11,
                width = 1.85,
                get = function() return "https://discord.gg/rZm7stP8gn" end,
                set = function() end,
            },
            twitchIcon = {
                type = "description",
                name = " ",
                order = 11.5,
                width = 0.25,
                image = "Interface\\AddOns\\CkraigCooldownManager\\twitch",
                imageWidth = 64,
                imageHeight = 64,
            },
            twitchLink = {
                type = "input",
                name = "Twitch",
                desc = "Follow on Twitch! Select and copy this link.",
                order = 12,
                width = 1.85,
                get = function() return "https://www.twitch.tv/ckraigfriend" end,
                set = function() end,
            },
        },
    }

    -- Let each module inject its options
    if CCM.BuildCooldownBarsOptions    then CCM.BuildCooldownBarsOptions() end
    if CCM.BuildDynamicIconsOptions    then CCM.BuildDynamicIconsOptions() end
    if CCM.BuildEssentialBuffsOptions  then CCM.BuildEssentialBuffsOptions() end
    if CCM.BuildUtilityBuffsOptions    then CCM.BuildUtilityBuffsOptions() end
    if CCM.BuildGlowOptions            then CCM.BuildGlowOptions() end
    if CCM.BuildTrinketRacialsOptions  then CCM.BuildTrinketRacialsOptions() end
    if CCM.BuildPowerPotionOptions     then CCM.BuildPowerPotionOptions() end
    if CCM.BuildTrackedSpellsOptions   then CCM.BuildTrackedSpellsOptions() end
    if CCM.BuildSegmentBarsOptions     then CCM.BuildSegmentBarsOptions() end
    if CCM.BuildChargeTextColorOptions then CCM.BuildChargeTextColorOptions() end
    if CCM.BuildDefensiveAuraOptions   then CCM.BuildDefensiveAuraOptions() end
    if CCM.BuildResourceBarsOptions      then CCM.BuildResourceBarsOptions() end

    -- Profile management tab
    local db = GetProfileDB()
    if db then
        CCM.AceOptionsTable.args.profiles = AceDBOptions:GetOptionsTable(db)
        CCM.AceOptionsTable.args.profiles.order = 900
    end

    -- Register with AceConfig
    AceConfig:RegisterOptionsTable("CkraigCooldownManager", CCM.AceOptionsTable)

    -- Add to Blizzard Interface Options and standalone dialog
    AceConfigDialog:AddToBlizOptions("CkraigCooldownManager", "Ckraig Cooldown Manager")
end

-- ============================================================
-- Slash command + PLAYER_LOGIN bootstrap
-- ============================================================
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()

    -- Delay slightly so all modules have time to load
    C_Timer.After(0.5, function()
        RegisterAllOptions()
    end)

    -- Slash commands
    SLASH_CKCDM1 = "/ckcdm"
    SLASH_CKCDM2 = "/ccm"
    SlashCmdList["CKCDM"] = function(input)
        if InCombatLockdown and InCombatLockdown() then
            print("|cffff6600Ckraig Cooldown Manager:|r Cannot open settings during combat.")
            return
        end

        local trimmed = TrimInput(input)
        if trimmed ~= "" then
            -- Allow /ckcdm <tabname> to open a specific tab
            AceConfigDialog:Open("CkraigCooldownManager")
            AceConfigDialog:SelectGroup("CkraigCooldownManager", trimmed:lower())
        else
            -- Toggle standalone dialog
            if AceConfigDialog.OpenFrames["CkraigCooldownManager"] then
                AceConfigDialog:Close("CkraigCooldownManager")
            else
                AceConfigDialog:Open("CkraigCooldownManager")
            end
        end
    end
end)
