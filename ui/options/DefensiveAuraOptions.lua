-- ============================================================
-- CkraigCooldownManager :: UI :: Options :: Defensive Aura
-- ============================================================
-- AceConfig options table for the Defensive Aura Tracker.
-- Adds a "Defensive Aura" tab to the CCM Ace3 config dialog.
-- ============================================================

local CCM = _G.CkraigCooldownManager
local AceRegistry = LibStub("AceConfigRegistry-3.0")

-- ============================================================
-- DB access
-- ============================================================
local function GetDB()
    if DefensiveAuraTracker and DefensiveAuraTracker.GetSettings then
        return DefensiveAuraTracker:GetSettings()
    end
    return CCM.AceOpts.GetProfileData("defensiveAura")
end

local function Refresh()
    -- No layout to refresh; just notify AceConfig that values changed
    AceRegistry:NotifyChange("CkraigCooldownManager")
end

-- ============================================================
-- Sound values for the dropdown
-- ============================================================
local function GetSoundValues()
    local values = {}
    -- SOUNDKIT built-in options
    values["RAID_WARNING"]        = "Raid Warning Horn"
    values["READY_CHECK"]         = "Ready Check Ping"
    values["ALARM_CLOCK_WARNING_3"] = "Alarm Clock Tone"
    values["LEVEL_UP"]            = "Level Up"
    values["IG_PLAYER_INVITE"]    = "Player Invite"

    -- LibSharedMedia sounds
    local LSM = CCM.AceOpts.LSM
    if LSM then
        for _, name in ipairs(LSM:List("sound")) do
            values[name] = name .. " (SharedMedia)"
        end
    end

    return values
end

-- ============================================================
-- Build options table
-- ============================================================
function CCM.BuildDefensiveAuraOptions()
    CCM.AceOptionsTable.args.defensiveAura = {
        type = "group",
        name = "Defensive Aura",
        order = 45,
        args = {
            description = {
                type = "description",
                name = "Plays an alert sound (and optional screen flash) when an external defensive cooldown is applied to you via Blizzard's ExternalDefensivesFrame.",
                order = 0,
                fontSize = "medium",
            },
            headerGeneral = {
                type = "header",
                name = "General",
                order = 1,
            },
            enabled = {
                type = "toggle",
                name = "Enable Defensive Alerts",
                desc = "Toggle sound alerts when an external defensive is detected.",
                order = 2,
                width = "full",
                get = function() local db = GetDB(); return db and db.enabled end,
                set = function(_, val)
                    local db = GetDB()
                    if db then db.enabled = val; Refresh() end
                end,
            },
            headerSound = {
                type = "header",
                name = "Sound",
                order = 10,
            },
            alertSound = {
                type = "select",
                name = "Alert Sound",
                desc = "Choose which sound to play when a defensive is detected.",
                order = 11,
                values = GetSoundValues,
                get = function()
                    local db = GetDB()
                    return db and db.alertSound or "RAID_WARNING"
                end,
                set = function(_, val)
                    local db = GetDB()
                    if db then
                        db.alertSound = val
                        Refresh()
                    end
                end,
            },
            previewSound = {
                type = "execute",
                name = "Preview Sound",
                desc = "Play the currently selected alert sound.",
                order = 12,
                func = function()
                    if DefensiveAuraTracker and DefensiveAuraTracker.PreviewSound then
                        DefensiveAuraTracker:PreviewSound()
                    end
                end,
            },
            headerVisual = {
                type = "header",
                name = "Visual",
                order = 20,
            },
            flashScreen = {
                type = "toggle",
                name = "Flash Screen",
                desc = "Briefly flash the screen with a gold tint when an external defensive is detected.",
                order = 21,
                get = function() local db = GetDB(); return db and db.flashScreen end,
                set = function(_, val)
                    local db = GetDB()
                    if db then db.flashScreen = val; Refresh() end
                end,
            },
            printMessage = {
                type = "toggle",
                name = "Print Chat Message",
                desc = "Print a message to chat when an external defensive is detected.",
                order = 22,
                get = function() local db = GetDB(); return db and db.printMessage end,
                set = function(_, val)
                    local db = GetDB()
                    if db then db.printMessage = val; Refresh() end
                end,
            },
            headerTest = {
                type = "header",
                name = "Test",
                order = 30,
            },
            testAlert = {
                type = "execute",
                name = "Test Alert",
                desc = "Simulate a defensive detection to test your current settings (sound + flash + chat).",
                order = 31,
                func = function()
                    if DefensiveAuraTracker then
                        local settings = DefensiveAuraTracker:GetSettings()
                        if not settings.enabled then
                            print("|cff00ff00[CCM]|r Defensive alerts are disabled. Enable them first.")
                            return
                        end
                        -- Temporarily fire the combined alert
                        if DefensiveAuraTracker.PreviewSound then
                            DefensiveAuraTracker:PreviewSound()
                        end
                        print("|cff00ff00[CCM]|r Defensive alert test fired.")
                    end
                end,
            },
            headerSlash = {
                type = "header",
                name = "Slash Commands",
                order = 90,
            },
            slashHelp = {
                type = "description",
                name = "|cffffd200/ccmdef on|r — Enable alerts\n|cffffd200/ccmdef off|r — Disable alerts\n|cffffd200/ccmdef test|r — Fire a test alert",
                order = 91,
                fontSize = "medium",
            },
        },
    }
end
