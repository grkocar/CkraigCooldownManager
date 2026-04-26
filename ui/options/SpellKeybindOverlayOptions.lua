-- ============================================================
-- CkraigCooldownManager :: UI :: Options :: Spell Keybind Overlay
-- ============================================================
-- AceConfig options table for SpellKeybindOverlay.lua.
-- Registered as the "keybindOverlay" top-level tab in CCM's
-- options panel.
-- ============================================================

local CCM          = _G.CkraigCooldownManager
local AceRegistry  = LibStub("AceConfigRegistry-3.0")
local LSM          = LibStub("LibSharedMedia-3.0", true)

-- re-use the same GetDB helper (SpellKeybindOverlay.lua is loaded first)
local function GetDB()
    if not MySpellKeybindOverlayDB then MySpellKeybindOverlayDB = {} end
    return MySpellKeybindOverlayDB
end

local function Refresh()
    if CCM.RefreshKeybindOverlays then CCM.RefreshKeybindOverlays() end
end

-- ============================================================
-- Value tables
-- ============================================================
local FONT_FLAGS_VALUES = {
    [""]                    = "None",
    ["OUTLINE"]             = "Outline",
    ["THICKOUTLINE"]        = "Thick Outline",
    ["MONOCHROME"]          = "Monochrome",
    ["OUTLINE|MONOCHROME"]  = "Outline + Mono",
}

local POSITION_VALUES = {
    TOPLEFT     = "Top Left",
    TOP         = "Top Center",
    TOPRIGHT    = "Top Right",
    LEFT        = "Middle Left",
    CENTER      = "Center",
    RIGHT       = "Middle Right",
    BOTTOMLEFT  = "Bottom Left",
    BOTTOM      = "Bottom Center",
    BOTTOMRIGHT = "Bottom Right",
}

-- ============================================================
-- Build
-- ============================================================
function CCM.BuildSpellKeybindOptions()
    if not CCM.AceOptionsTable then return end

    CCM.AceOptionsTable.args.keybindOverlay = {
        type        = "group",
        name        = "Keybind Labels",
        order       = 60,
        childGroups = "tab",
        args        = {
            general = {
                type  = "group",
                name  = "General",
                order = 1,
                args  = {

                    -- ── Enable toggles ──────────────────────────────
                    essentialsEnabled = {
                        type    = "toggle",
                        name    = "Show on Essential Buffs",
                        desc    = "Display the keybind for each spell icon in the Essential Buff Tracker.",
                        order   = 1,
                        width   = "full",
                        get = function()
                            return GetDB().essentialsEnabled
                        end,
                        set = function(_, val)
                            GetDB().essentialsEnabled = val
                            Refresh()
                        end,
                    },
                    utilityEnabled = {
                        type    = "toggle",
                        name    = "Show on Utility Buffs",
                        desc    = "Display the keybind for each spell icon in the Utility Buff Tracker.",
                        order   = 2,
                        width   = "full",
                        get = function()
                            return GetDB().utilityEnabled
                        end,
                        set = function(_, val)
                            GetDB().utilityEnabled = val
                            Refresh()
                        end,
                    },

                    sep1 = { type = "description", name = " ", order = 3, width = "full" },

                    -- ── Font ────────────────────────────────────────
                    font = {
                        type          = "select",
                        name          = "Font",
                        desc          = "Keybind label font (uses SharedMedia library).",
                        order         = 4,
                        dialogControl = "LSM30_Font",
                        values        = LSM and AceGUIWidgetLSMlists and AceGUIWidgetLSMlists.font
                                        or (LSM and LSM:HashTable("font") or {}),
                        get = function()
                            return GetDB().font
                        end,
                        set = function(_, val)
                            GetDB().font = val
                            Refresh()
                        end,
                    },
                    fontSize = {
                        type  = "range",
                        name  = "Font Size",
                        order = 5,
                        min   = 4,
                        max   = 32,
                        step  = 1,
                        get = function()
                            return GetDB().fontSize
                        end,
                        set = function(_, val)
                            GetDB().fontSize = val
                            Refresh()
                        end,
                    },
                    fontFlags = {
                        type   = "select",
                        name   = "Font Style",
                        order  = 6,
                        values = FONT_FLAGS_VALUES,
                        get = function()
                            return GetDB().fontFlags
                        end,
                        set = function(_, val)
                            GetDB().fontFlags = val
                            Refresh()
                        end,
                    },

                    sep2 = { type = "description", name = " ", order = 7, width = "full" },

                    -- ── Position ────────────────────────────────────
                    position = {
                        type   = "select",
                        name   = "Anchor Corner",
                        desc   = "Which corner / edge of the icon the label is anchored to.",
                        order  = 8,
                        values = POSITION_VALUES,
                        get = function()
                            return GetDB().position
                        end,
                        set = function(_, val)
                            GetDB().position = val
                            Refresh()
                        end,
                    },
                    offsetX = {
                        type  = "range",
                        name  = "X Offset",
                        order = 9,
                        min   = -100,
                        max   = 100,
                        step  = 1,
                        get = function()
                            return GetDB().offsetX
                        end,
                        set = function(_, val)
                            GetDB().offsetX = val
                            Refresh()
                        end,
                    },
                    offsetY = {
                        type  = "range",
                        name  = "Y Offset",
                        order = 10,
                        min   = -100,
                        max   = 100,
                        step  = 1,
                        get = function()
                            return GetDB().offsetY
                        end,
                        set = function(_, val)
                            GetDB().offsetY = val
                            Refresh()
                        end,
                    },

                    sep3 = { type = "description", name = " ", order = 11, width = "full" },

                    -- ── Color ───────────────────────────────────────
                    color = {
                        type     = "color",
                        name     = "Text Color",
                        desc     = "Color and opacity of the keybind label.",
                        order    = 12,
                        hasAlpha = true,
                        get = function()
                            local c = GetDB().color or {}
                            return c.r or 1, c.g or 1, c.b or 1, c.a or 1
                        end,
                        set = function(_, r, g, b, a)
                            local db = GetDB()
                            db.color = db.color or {}
                            db.color.r, db.color.g, db.color.b, db.color.a = r, g, b, a
                            Refresh()
                        end,
                    },

                    sep4 = { type = "description", name = " ", order = 13, width = "full" },

                    -- ── Manual refresh ──────────────────────────────
                    refreshNow = {
                        type  = "execute",
                        name  = "Refresh Now",
                        desc  = "Manually clear the keybind cache and redraw all labels.",
                        order = 14,
                        func  = function()
                            Refresh()
                            if AceRegistry then
                                AceRegistry:NotifyChange("CkraigCooldownManager")
                            end
                        end,
                    },
                },
            },
        },
    }
end
