-- ============================================================
-- CkraigCooldownManager :: UI :: Options :: Glow Style
-- ============================================================
-- AceConfig options table for the global glow system.
-- Replaces CCM_CreateGlowOptionsPanel.
-- ============================================================

local CCM = _G.CkraigCooldownManager

local function GetDB()
    if CCM.GetCustomGlowSettings then
        return CCM.GetCustomGlowSettings()
    end
    return nil
end

local function Refresh()
    if CCM.RefreshCustomGlows then CCM.RefreshCustomGlows() end
end

local function DisableGlows()
    if CCM.DisableCustomGlowsNow then CCM.DisableCustomGlowsNow() end
end

function CCM.BuildGlowOptions()
    local opts = CCM.AceOpts

    local GLOW_STYLES = {
        Pixel    = "Pixel",
        Autocast = "Autocast",
        Button   = "Button Glow",
        Proc     = "Proc Glow",
    }

    CCM.AceOptionsTable.args.glows = {
        type = "group",
        name = "Glow Style",
        order = 70,
        args = {
            enabled = {
                type = "toggle",
                name = "Enable Custom Overrides",
                desc = "Override glow effects globally across all viewers",
                order = 1,
                width = "full",
                get = function() local db = GetDB(); return db and db.Enabled end,
                set = function(_, val)
                    local db = GetDB()
                    if db then
                        db.Enabled = val
                        if val then Refresh() else DisableGlows() end
                    end
                end,
            },
            headerType = {
                type = "header",
                name = "Glow Settings",
                order = 10,
            },
            glowType = {
                type = "select",
                name = "Glow Type",
                order = 11,
                values = GLOW_STYLES,
                get = function() local db = GetDB(); return db and db.Type end,
                set = function(_, val)
                    local db = GetDB()
                    if db then db.Type = val; Refresh() end
                end,
            },
            thickness = {
                type = "range",
                name = "Glow Thickness",
                order = 12,
                min = 1, max = 8, step = 0.5,
                get = function()
                    local db = GetDB()
                    return db and (db.CommonThickness or (db.Pixel and db.Pixel.Thickness)) or 2
                end,
                set = function(_, val)
                    local db = GetDB()
                    if db then
                        db.CommonThickness = val
                        if db.Pixel then db.Pixel.Thickness = val end
                        Refresh()
                    end
                end,
            },
            headerColors = {
                type = "header",
                name = "Glow Colors",
                order = 20,
            },
            pixelColor = {
                type = "color",
                name = "Pixel Glow Color",
                order = 21,
                hasAlpha = true,
                get = function()
                    local db = GetDB()
                    if db and db.Pixel and db.Pixel.Color then
                        local c = db.Pixel.Color
                        return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 0, c.a or c[4] or 1
                    end
                    return 1, 1, 0, 1
                end,
                set = function(_, r, g, b, a)
                    local db = GetDB()
                    if db then
                        db.Pixel = db.Pixel or {}
                        db.Pixel.Color = {r = r, g = g, b = b, a = a}
                        Refresh()
                    end
                end,
            },
            autocastColor = {
                type = "color",
                name = "Autocast Glow Color",
                order = 22,
                hasAlpha = true,
                get = function()
                    local db = GetDB()
                    if db and db.Autocast and db.Autocast.Color then
                        local c = db.Autocast.Color
                        return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 0, c.a or c[4] or 1
                    end
                    return 1, 1, 0, 1
                end,
                set = function(_, r, g, b, a)
                    local db = GetDB()
                    if db then
                        db.Autocast = db.Autocast or {}
                        db.Autocast.Color = {r = r, g = g, b = b, a = a}
                        Refresh()
                    end
                end,
            },
            buttonColor = {
                type = "color",
                name = "Button Glow Color",
                order = 23,
                hasAlpha = true,
                get = function()
                    local db = GetDB()
                    if db and db.Button and db.Button.Color then
                        local c = db.Button.Color
                        return c.r or c[1] or 1, c.g or c[2] or 1, c.b or c[3] or 0, c.a or c[4] or 1
                    end
                    return 1, 1, 0, 1
                end,
                set = function(_, r, g, b, a)
                    local db = GetDB()
                    if db then
                        db.Button = db.Button or {}
                        db.Button.Color = {r = r, g = g, b = b, a = a}
                        Refresh()
                    end
                end,
            },
            resetColors = {
                type = "execute",
                name = "Reset All Glow Colors",
                order = 30,
                func = function()
                    local db = GetDB()
                    if db then
                        if db.Pixel then db.Pixel.Color = {r = 1, g = 1, b = 0, a = 1} end
                        if db.Autocast then db.Autocast.Color = {r = 1, g = 1, b = 0, a = 1} end
                        if db.Button then db.Button.Color = {r = 1, g = 1, b = 0, a = 1} end
                        Refresh()
                    end
                end,
            },
        },
    }
end
