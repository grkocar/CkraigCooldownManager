-- ============================================================
-- CkraigCooldownManager :: UI :: Options :: ResourceBarsOptions
-- ============================================================
-- AceConfig options table for the Resource Bars system.
-- Health Bar, Power Bar, Alt Power Bar, Class Resource tabs.
-- ============================================================

local CCM = _G.CkraigCooldownManager
local RB = CCM_ResourceBars
local LSM = LibStub("LibSharedMedia-3.0", true)

-- ============================================================
-- Helpers
-- ============================================================
local function GetRBSettings(moduleName)
    if not RB then return nil end
    return RB:GetModuleSettings(moduleName)
end

local function RefreshModule(moduleName)
    if not RB then return end
    local mod = RB.modules[moduleName]
    if mod and mod.Refresh then
        local class = RB:GetPlayerClass()
        local specID = RB:GetPlayerSpec()
        mod:Refresh(class, specID)
    end
end

local function GetTextureValues()
    local values = {}
    if LSM then
        local list = LSM:HashTable("statusbar")
        for k in pairs(list) do
            values[k] = k
        end
    end
    return values
end

local TEXT_FORMAT_VALUES = {
    percent = "Percent (75%)",
    current = "Current (15.2K)",
    both    = "Current / Max (15.2K / 20.0K)",
    deficit = "Deficit (-4.8K)",
}

local STAGGER_TEXT_FORMAT_VALUES = {
    percent = "Percent (75%)",
    current = "Current (15.2K)",
    both    = "Current (Percent)",
    deficit = "Deficit (-4.8K)",
}

-- Helper: get active resource def for the current class/spec
local function GetActiveClassResourceDef()
    local RB = CCM_ResourceBars
    if not RB or not RB.RESOURCE_DEFS then return nil, 0 end
    local class = RB:GetPlayerClass()
    local specID = RB:GetPlayerSpec()
    local defs = RB.RESOURCE_DEFS[class]
    if not defs then return nil, 0 end
    for _, def in ipairs(defs) do
        if def.segmented and def.specs then
            for _, sid in ipairs(def.specs) do
                if sid == specID then
                    local maxPts = def.maxPoints or (def.maxFunc and def.maxFunc()) or 5
                    return def, maxPts
                end
            end
        end
    end
    return nil, 0
end

-- Resource point label names per type
local SEGMENT_LABELS = {
    comboPoints    = "Combo Point",
    holyPower      = "Holy Power",
    chi            = "Chi",
    soulShards     = "Soul Shard",
    arcaneCharges  = "Arcane Charge",
    essence        = "Essence",
    runes          = "Rune",
}

-- ============================================================
-- Status bar options builder (health, power, altpower)
-- ============================================================
local function BuildStatusBarOptions(moduleName, displayName, order, extraArgs)
    local args = {
        enabled = {
            type = "toggle",
            name = "Enable " .. displayName,
            order = 1,
            width = "full",
            get = function() local db = GetRBSettings(moduleName); return db and db.enabled end,
            set = function(_, val)
                local db = GetRBSettings(moduleName)
                if db then db.enabled = val; RefreshModule(moduleName) end
            end,
        },
        spacer1 = { type = "description", name = "", order = 1.5, width = "full" },
        -- Dimensions
        width = {
            type = "range",
            name = "Width",
            order = 2,
            min = 50, max = 500, step = 1,
            get = function() local db = GetRBSettings(moduleName); return db and db.width or 200 end,
            set = function(_, val)
                local db = GetRBSettings(moduleName)
                if db then db.width = val; RefreshModule(moduleName) end
            end,
            hidden = function() local db = GetRBSettings(moduleName); return db and db.widthMatchAnchor and db.anchor == "viewer" end,
        },
        height = {
            type = "range",
            name = "Height",
            order = 3,
            min = 4, max = 60, step = 1,
            get = function() local db = GetRBSettings(moduleName); return db and db.height or 20 end,
            set = function(_, val)
                local db = GetRBSettings(moduleName)
                if db then db.height = val; RefreshModule(moduleName) end
            end,
        },
        -- Texture
        texture = {
            type = "select",
            name = "Bar Texture",
            order = 5,
            dialogControl = "LSM30_Statusbar",
            values = function() return GetTextureValues() end,
            get = function() local db = GetRBSettings(moduleName); return db and db.texture or "Blizzard Raid Bar" end,
            set = function(_, val)
                local db = GetRBSettings(moduleName)
                if db then db.texture = val; RefreshModule(moduleName) end
            end,
        },
        -- Border
        borderSize = {
            type = "range",
            name = "Border Size",
            order = 6,
            min = 0, max = 4, step = 1,
            get = function() local db = GetRBSettings(moduleName); return db and db.borderSize or 1 end,
            set = function(_, val)
                local db = GetRBSettings(moduleName)
                if db then db.borderSize = val; RefreshModule(moduleName) end
            end,
        },
        borderColor = {
            type = "color",
            name = "Border Color",
            order = 7,
            hasAlpha = true,
            get = function()
                local db = GetRBSettings(moduleName)
                local c = db and db.borderColor or { r = 0, g = 0, b = 0, a = 1 }
                return c.r, c.g, c.b, c.a
            end,
            set = function(_, r, g, b, a)
                local db = GetRBSettings(moduleName)
                if db then db.borderColor = { r = r, g = g, b = b, a = a }; RefreshModule(moduleName) end
            end,
        },
        bgColor = {
            type = "color",
            name = "Background Color",
            order = 8,
            hasAlpha = true,
            get = function()
                local db = GetRBSettings(moduleName)
                local c = db and db.bgColor or { r = 0.15, g = 0.15, b = 0.15, a = 0.8 }
                return c.r, c.g, c.b, c.a
            end,
            set = function(_, r, g, b, a)
                local db = GetRBSettings(moduleName)
                if db then db.bgColor = { r = r, g = g, b = b, a = a }; RefreshModule(moduleName) end
            end,
        },
        -- Text
        spacer2 = { type = "description", name = "", order = 9.5, width = "full" },
        showText = {
            type = "toggle",
            name = "Show Text",
            order = 10,
            get = function() local db = GetRBSettings(moduleName); return db and db.showText end,
            set = function(_, val)
                local db = GetRBSettings(moduleName)
                if db then db.showText = val; RefreshModule(moduleName) end
            end,
        },
        textFormat = {
            type = "select",
            name = "Text Format",
            order = 11,
            values = TEXT_FORMAT_VALUES,
            get = function() local db = GetRBSettings(moduleName); return db and db.textFormat or "percent" end,
            set = function(_, val)
                local db = GetRBSettings(moduleName)
                if db then db.textFormat = val; RefreshModule(moduleName) end
            end,
        },
        textSize = {
            type = "range",
            name = "Text Size",
            order = 12,
            min = 6, max = 24, step = 1,
            get = function() local db = GetRBSettings(moduleName); return db and db.textSize or 12 end,
            set = function(_, val)
                local db = GetRBSettings(moduleName)
                if db then db.textSize = val; RefreshModule(moduleName) end
            end,
        },
        -- Visibility
        spacer3 = { type = "description", name = "", order = 19.5, width = "full" },
        visibilityHeader = {
            type = "header",
            name = "Visibility",
            order = 20,
        },
        hideWhenMounted = {
            type = "toggle",
            name = "Hide When Mounted",
            order = 21,
            get = function() local db = GetRBSettings(moduleName); return db and db.hideWhenMounted end,
            set = function(_, val)
                local db = GetRBSettings(moduleName)
                if db then db.hideWhenMounted = val; RefreshModule(moduleName) end
            end,
        },
        hideOutOfCombat = {
            type = "toggle",
            name = "Hide Out of Combat",
            order = 22,
            get = function() local db = GetRBSettings(moduleName); return db and db.hideOutOfCombat end,
            set = function(_, val)
                local db = GetRBSettings(moduleName)
                if db then db.hideOutOfCombat = val; RefreshModule(moduleName) end
            end,
        },
        -- Positioning & Anchoring
        spacer4 = { type = "description", name = "", order = 29.5, width = "full" },
        positionHeader = {
            type = "header",
            name = "Position & Anchor",
            order = 30,
        },
        anchorMode = {
            type = "select",
            name = "Anchor To",
            order = 30.1,
            values = { free = "Free (Drag)", viewer = "Cooldown Viewer" },
            get = function() local db = GetRBSettings(moduleName); return db and db.anchor or "free" end,
            set = function(_, val)
                local db = GetRBSettings(moduleName)
                if db then db.anchor = val; RefreshModule(moduleName) end
            end,
        },
        anchorStackDesc = {
            type = "description",
            name = "Bars anchored to the same viewer stack automatically with no gaps. Disabled or hidden bars are skipped.",
            order = 30.15,
            width = "full",
            hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
        },
        anchorTarget = {
            type = "select",
            name = "Viewer",
            order = 30.2,
            values = function()
                return RB and RB.ANCHOR_TARGET_LABELS or { essential = "Essential" }
            end,
            get = function() local db = GetRBSettings(moduleName); return db and db.anchorTarget or "essential" end,
            set = function(_, val)
                local db = GetRBSettings(moduleName)
                if db then
                    db.anchorTarget = val
                    if RB then RB:HookAnchorResize(val) end
                    RefreshModule(moduleName)
                end
            end,
            hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
        },
        anchorPosition = {
            type = "select",
            name = "Position",
            order = 30.3,
            values = { BELOW = "Below", ABOVE = "Above", LEFT = "Left", RIGHT = "Right" },
            get = function() local db = GetRBSettings(moduleName); return db and db.anchorPosition or "BELOW" end,
            set = function(_, val)
                local db = GetRBSettings(moduleName)
                if db then db.anchorPosition = val; RefreshModule(moduleName) end
            end,
            hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
        },
        anchorOffset = {
            type = "range",
            name = "Offset from Viewer",
            desc = "Gap between the viewer and the first visible bar in the stack.",
            order = 30.4,
            min = -50, max = 50, step = 1,
            get = function() local db = GetRBSettings(moduleName); return db and db.anchorOffset or 2 end,
            set = function(_, val)
                local db = GetRBSettings(moduleName)
                if db then db.anchorOffset = val; RefreshModule(moduleName) end
            end,
            hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
        },
        widthMatchAnchor = {
            type = "toggle",
            name = "Match Anchor Width",
            desc = "Automatically resize bar width to match the viewer width.",
            order = 30.5,
            get = function() local db = GetRBSettings(moduleName); return db and db.widthMatchAnchor end,
            set = function(_, val)
                local db = GetRBSettings(moduleName)
                if db then
                    db.widthMatchAnchor = val
                    if val and RB then RB:HookAnchorResize(db.anchorTarget or "essential") end
                    RefreshModule(moduleName)
                end
            end,
            hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
        },
        lockBar = {
            type = "toggle",
            name = "Lock Bar (Drag to Reposition)",
            desc = "Uncheck to unlock and drag the bar to a new position.",
            order = 31,
            width = "full",
            get = function()
                local bar = RB and RB.bars[moduleName]
                return bar and bar._locked
            end,
            set = function(_, val)
                local bar = RB and RB.bars[moduleName]
                if bar then bar._locked = val end
            end,
            hidden = function() local db = GetRBSettings(moduleName); return db and db.anchor == "viewer" end,
        },
        resetPosition = {
            type = "execute",
            name = "Reset Position",
            order = 32,
            func = function()
                local db = GetRBSettings(moduleName)
                if db then
                    local defaults = RB.MODULE_DEFAULTS[moduleName]
                    if defaults and defaults.position then
                        db.position = { point = defaults.position.point, x = defaults.position.x, y = defaults.position.y }
                    else
                        db.position = { point = "CENTER", x = 0, y = 0 }
                    end
                    RefreshModule(moduleName)
                end
            end,
            hidden = function() local db = GetRBSettings(moduleName); return db and db.anchor == "viewer" end,
        },
    }

    -- Merge extra args
    if extraArgs then
        for k, v in pairs(extraArgs) do
            args[k] = v
        end
    end

    return {
        type = "group",
        name = displayName,
        order = order,
        args = args,
    }
end

-- ============================================================
-- Health bar extra options
-- ============================================================
local function HealthBarExtras()
    return {
        colorHeader = {
            type = "header",
            name = "Color",
            order = 14,
        },
        useClassColor = {
            type = "toggle",
            name = "Use Class Color",
            order = 15,
            get = function() local db = GetRBSettings("healthBar"); return db and db.useClassColor end,
            set = function(_, val)
                local db = GetRBSettings("healthBar")
                if db then db.useClassColor = val; RefreshModule("healthBar") end
            end,
        },
        customColor = {
            type = "color",
            name = "Custom Bar Color",
            order = 16,
            hasAlpha = true,
            disabled = function() local db = GetRBSettings("healthBar"); return db and (db.useClassColor or db.useGradient) end,
            get = function()
                local db = GetRBSettings("healthBar")
                local c = db and db.customColor or { r = 0.2, g = 0.8, b = 0.2, a = 1 }
                return c.r, c.g, c.b, c.a
            end,
            set = function(_, r, g, b, a)
                local db = GetRBSettings("healthBar")
                if db then db.customColor = { r = r, g = g, b = b, a = a }; RefreshModule("healthBar") end
            end,
        },
        useGradient = {
            type = "toggle",
            name = "Enable Gradient",
            desc = "Use a horizontal gradient instead of a solid or class color.",
            order = 16.1,
            width = "full",
            get = function() local db = GetRBSettings("healthBar"); return db and db.useGradient end,
            set = function(_, val)
                local db = GetRBSettings("healthBar")
                if db then db.useGradient = val; RefreshModule("healthBar") end
            end,
        },
        gradientStart = {
            type = "color",
            name = "Gradient Start",
            desc = "Left side color of the gradient.",
            order = 16.2,
            hasAlpha = true,
            hidden = function() local db = GetRBSettings("healthBar"); return not db or not db.useGradient end,
            get = function()
                local db = GetRBSettings("healthBar")
                local c = db and db.gradientStart or { r = 0.2, g = 0.8, b = 0.2, a = 1 }
                return c.r, c.g, c.b, c.a
            end,
            set = function(_, r, g, b, a)
                local db = GetRBSettings("healthBar")
                if db then db.gradientStart = { r = r, g = g, b = b, a = a }; RefreshModule("healthBar") end
            end,
        },
        gradientEnd = {
            type = "color",
            name = "Gradient End",
            desc = "Right side color of the gradient.",
            order = 16.3,
            hasAlpha = true,
            hidden = function() local db = GetRBSettings("healthBar"); return not db or not db.useGradient end,
            get = function()
                local db = GetRBSettings("healthBar")
                local c = db and db.gradientEnd or { r = 0.0, g = 0.5, b = 0.0, a = 1 }
                return c.r, c.g, c.b, c.a
            end,
            set = function(_, r, g, b, a)
                local db = GetRBSettings("healthBar")
                if db then db.gradientEnd = { r = r, g = g, b = b, a = a }; RefreshModule("healthBar") end
            end,
        },
        absorbHeader = {
            type = "header",
            name = "Absorb Shield",
            order = 17,
        },
        showAbsorb = {
            type = "toggle",
            name = "Show Absorb Overlay",
            order = 17.5,
            get = function() local db = GetRBSettings("healthBar"); return db and db.showAbsorb end,
            set = function(_, val)
                local db = GetRBSettings("healthBar")
                if db then db.showAbsorb = val; RefreshModule("healthBar") end
            end,
        },
        absorbTexture = {
            type = "select",
            name = "Absorb Bar Texture",
            order = 17.6,
            dialogControl = "LSM30_Statusbar",
            values = function() return GetTextureValues() end,
            get = function()
                local db = GetRBSettings("healthBar")
                return db and db.absorbTexture or "Blizzard Raid Bar"
            end,
            set = function(_, val)
                local db = GetRBSettings("healthBar")
                if db then db.absorbTexture = val; RefreshModule("healthBar") end
            end,
        },
        absorbSide = {
            type = "select",
            name = "Absorb Fill Side",
            desc = "Which side the absorb bar fills from",
            order = 17.7,
            values = { right = "Right (reverse fill)", left = "Left (normal fill)" },
            get = function()
                local db = GetRBSettings("healthBar")
                return db and db.absorbSide or "right"
            end,
            set = function(_, val)
                local db = GetRBSettings("healthBar")
                if db then db.absorbSide = val; RefreshModule("healthBar") end
            end,
        },
        absorbColor = {
            type = "color",
            name = "Absorb Color",
            order = 18,
            hasAlpha = true,
            get = function()
                local db = GetRBSettings("healthBar")
                local c = db and db.absorbColor or { r = 0.8, g = 0.8, b = 0.2, a = 0.5 }
                return c.r, c.g, c.b, c.a
            end,
            set = function(_, r, g, b, a)
                local db = GetRBSettings("healthBar")
                if db then db.absorbColor = { r = r, g = g, b = b, a = a }; RefreshModule("healthBar") end
            end,
        },
        menuHeader = {
            type = "header",
            name = "Right-Click Menu",
            order = 19,
        },
        showRightClickMenu = {
            type = "toggle",
            name = "Enable Right-Click Menu",
            desc = "Overlay a secure button so right-clicking the health bar opens the player unit menu",
            order = 19.5,
            get = function() local db = GetRBSettings("healthBar"); return db and db.showRightClickMenu end,
            set = function(_, val)
                local db = GetRBSettings("healthBar")
                if db then db.showRightClickMenu = val; RefreshModule("healthBar") end
            end,
        },
    }
end

-- ============================================================
-- Power bar extra options
-- ============================================================
local function PowerBarExtras()
    return {
        colorHeader = {
            type = "header",
            name = "Color",
            order = 14,
        },
        usePowerColor = {
            type = "toggle",
            name = "Use Power Type Color",
            order = 15,
            get = function() local db = GetRBSettings("powerBar"); return db and db.usePowerColor end,
            set = function(_, val)
                local db = GetRBSettings("powerBar")
                if db then db.usePowerColor = val; RefreshModule("powerBar") end
            end,
        },
        customColor = {
            type = "color",
            name = "Custom Bar Color",
            order = 16,
            hasAlpha = true,
            disabled = function() local db = GetRBSettings("powerBar"); return db and (db.usePowerColor or db.useGradient) end,
            get = function()
                local db = GetRBSettings("powerBar")
                local c = db and db.customColor or { r = 0.2, g = 0.2, b = 0.8, a = 1 }
                return c.r, c.g, c.b, c.a
            end,
            set = function(_, r, g, b, a)
                local db = GetRBSettings("powerBar")
                if db then db.customColor = { r = r, g = g, b = b, a = a }; RefreshModule("powerBar") end
            end,
        },
        useGradient = {
            type = "toggle",
            name = "Enable Gradient",
            desc = "Use a horizontal gradient instead of a solid or power type color.",
            order = 16.1,
            width = "full",
            get = function() local db = GetRBSettings("powerBar"); return db and db.useGradient end,
            set = function(_, val)
                local db = GetRBSettings("powerBar")
                if db then db.useGradient = val; RefreshModule("powerBar") end
            end,
        },
        gradientStart = {
            type = "color",
            name = "Gradient Start",
            desc = "Left side color of the gradient.",
            order = 16.2,
            hasAlpha = true,
            hidden = function() local db = GetRBSettings("powerBar"); return not db or not db.useGradient end,
            get = function()
                local db = GetRBSettings("powerBar")
                local c = db and db.gradientStart or { r = 0.2, g = 0.2, b = 0.8, a = 1 }
                return c.r, c.g, c.b, c.a
            end,
            set = function(_, r, g, b, a)
                local db = GetRBSettings("powerBar")
                if db then db.gradientStart = { r = r, g = g, b = b, a = a }; RefreshModule("powerBar") end
            end,
        },
        gradientEnd = {
            type = "color",
            name = "Gradient End",
            desc = "Right side color of the gradient.",
            order = 16.3,
            hasAlpha = true,
            hidden = function() local db = GetRBSettings("powerBar"); return not db or not db.useGradient end,
            get = function()
                local db = GetRBSettings("powerBar")
                local c = db and db.gradientEnd or { r = 0.0, g = 0.0, b = 0.5, a = 1 }
                return c.r, c.g, c.b, c.a
            end,
            set = function(_, r, g, b, a)
                local db = GetRBSettings("powerBar")
                if db then db.gradientEnd = { r = r, g = g, b = b, a = a }; RefreshModule("powerBar") end
            end,
        },
    }
end

-- ============================================================
-- Alt power bar extra options
-- ============================================================
local function AltPowerBarExtras()
    return {
        colorHeader = {
            type = "header",
            name = "Color",
            order = 14,
        },
        customColor = {
            type = "color",
            name = "Bar Color",
            desc = "Solid bar color (used when gradient is off).",
            order = 15,
            hasAlpha = true,
            get = function()
                local db = GetRBSettings("altPowerBar")
                local c = db and db.customColor or { r = 0.9, g = 0.6, b = 0.1, a = 1 }
                return c.r, c.g, c.b, c.a
            end,
            set = function(_, r, g, b, a)
                local db = GetRBSettings("altPowerBar")
                if db then db.customColor = { r = r, g = g, b = b, a = a }; RefreshModule("altPowerBar") end
            end,
        },
        useGradient = {
            type = "toggle",
            name = "Enable Gradient",
            desc = "Use a horizontal gradient instead of a solid color.",
            order = 16,
            width = "full",
            get = function() local db = GetRBSettings("altPowerBar"); return db and db.useGradient end,
            set = function(_, val)
                local db = GetRBSettings("altPowerBar")
                if db then db.useGradient = val; RefreshModule("altPowerBar") end
            end,
        },
        gradientStart = {
            type = "color",
            name = "Gradient Start",
            desc = "Left side color of the gradient.",
            order = 17,
            hasAlpha = true,
            get = function()
                local db = GetRBSettings("altPowerBar")
                local c = db and db.gradientStart or { r = 0.9, g = 0.6, b = 0.1, a = 1 }
                return c.r, c.g, c.b, c.a
            end,
            set = function(_, r, g, b, a)
                local db = GetRBSettings("altPowerBar")
                if db then db.gradientStart = { r = r, g = g, b = b, a = a }; RefreshModule("altPowerBar") end
            end,
        },
        gradientEnd = {
            type = "color",
            name = "Gradient End",
            desc = "Right side color of the gradient.",
            order = 18,
            hasAlpha = true,
            get = function()
                local db = GetRBSettings("altPowerBar")
                local c = db and db.gradientEnd or { r = 1.0, g = 0.3, b = 0.0, a = 1 }
                return c.r, c.g, c.b, c.a
            end,
            set = function(_, r, g, b, a)
                local db = GetRBSettings("altPowerBar")
                if db then db.gradientEnd = { r = r, g = g, b = b, a = a }; RefreshModule("altPowerBar") end
            end,
        },
    }
end

-- ============================================================
-- Class Resource options tab
-- ============================================================
local function BuildClassResourceTab()
    local result = {
        type = "group",
        name = "Class Resource",
        order = 4,
        args = {
            enabled = {
                type = "toggle",
                name = "Enable Class Resource",
                order = 1,
                width = "full",
                get = function() local db = GetRBSettings("classResource"); return db and db.enabled end,
                set = function(_, val)
                    local db = GetRBSettings("classResource")
                    if db then db.enabled = val; RefreshModule("classResource") end
                end,
            },
            desc = {
                type = "description",
                name = "Displays class-specific resources: Combo Points (Rogue/Druid), Holy Power (Paladin), Soul Shards (Warlock), Chi (Monk), Essence (Evoker), Arcane Charges (Mage), Runes (Death Knight), and Stagger (Brewmaster Monk).\n\nClasses without a secondary resource (Warrior, Hunter, Priest, Shaman, Demon Hunter) use only the Power Bar above.",
                order = 1.5,
                width = "full",
            },
            spacer1 = { type = "description", name = "", order = 1.9, width = "full" },
            -- Segmented bar dimensions
            segHeader = {
                type = "header",
                name = "Point Segments",
                order = 2,
            },
            segmentWidth = {
                type = "range",
                name = "Segment Width",
                order = 3,
                min = 8, max = 60, step = 1,
                get = function() local db = GetRBSettings("classResource"); return db and db.segmentWidth or 22 end,
                set = function(_, val)
                    local db = GetRBSettings("classResource")
                    if db then db.segmentWidth = val; RefreshModule("classResource") end
                end,
                hidden = function() local db = GetRBSettings("classResource"); return db and db.widthMatchAnchor and db.anchor == "viewer" end,
            },
            segmentHeight = {
                type = "range",
                name = "Segment Height",
                order = 4,
                min = 4, max = 40, step = 1,
                get = function() local db = GetRBSettings("classResource"); return db and db.segmentHeight or 14 end,
                set = function(_, val)
                    local db = GetRBSettings("classResource")
                    if db then db.segmentHeight = val; RefreshModule("classResource") end
                end,
            },
            segmentSpacing = {
                type = "range",
                name = "Segment Spacing",
                order = 5,
                min = 0, max = 10, step = 1,
                get = function() local db = GetRBSettings("classResource"); return db and db.segmentSpacing or 3 end,
                set = function(_, val)
                    local db = GetRBSettings("classResource")
                    if db then db.segmentSpacing = val; RefreshModule("classResource") end
                end,
            },
            -- Color
            spacer2 = { type = "description", name = "", order = 5.5, width = "full" },
            colorHeader = {
                type = "header",
                name = "Color",
                order = 6,
            },
            usePerPointColor = {
                type = "toggle",
                name = "Gradient Per-Point Color",
                desc = "Use a slightly different shade for each point to show progress at a glance.",
                order = 7,
                get = function() local db = GetRBSettings("classResource"); return db and db.usePerPointColor end,
                set = function(_, val)
                    local db = GetRBSettings("classResource")
                    if db then db.usePerPointColor = val; RefreshModule("classResource") end
                end,
            },
            -- Per-segment color pickers (dynamic based on class)
            segColorHeader = {
                type = "header",
                name = "Segment Colors",
                order = 7.1,
                hidden = function()
                    local db = GetRBSettings("classResource")
                    if not db or not db.usePerPointColor then return true end
                    local RB = CCM_ResourceBars
                    if not RB or not RB.RESOURCE_DEFS then return true end
                    local class = RB:GetPlayerClass()
                    local defs = RB.RESOURCE_DEFS[class]
                    return not defs or #defs == 0
                end,
            },
            segColorResetBtn = {
                type = "execute",
                name = "Reset to Default Colors",
                order = 7.19,
                width = "normal",
                func = function()
                    local db = GetRBSettings("classResource")
                    if db then db.segmentColors = {}; RefreshModule("classResource") end
                end,
                hidden = function()
                    local db = GetRBSettings("classResource")
                    if not db or not db.usePerPointColor then return true end
                    local def = GetActiveClassResourceDef()
                    return not def
                end,
            },
            -- Charged combo point colors (Rogue/Druid)
            -- Resource count text
            resourceTextHeader = {
                type = "header",
                name = "Resource Text",
                order = 7.1,
            },
            showResourceText = {
                type = "toggle",
                name = "Show Resource Count",
                desc = "Display a count (e.g. 3.5/5) centered on the bar.",
                order = 7.11,
                width = "full",
                get = function()
                    local db = GetRBSettings("classResource")
                    return db and db.showResourceText
                end,
                set = function(_, val)
                    local db = GetRBSettings("classResource")
                    if db then db.showResourceText = val; RefreshModule("classResource") end
                end,
            },
            resourceTextSize = {
                type = "range",
                name = "Text Size",
                order = 7.12,
                min = 6, max = 32, step = 1,
                get = function()
                    local db = GetRBSettings("classResource")
                    return db and db.resourceTextSize or 12
                end,
                set = function(_, val)
                    local db = GetRBSettings("classResource")
                    if db then db.resourceTextSize = val; RefreshModule("classResource") end
                end,
                hidden = function()
                    local db = GetRBSettings("classResource")
                    return not db or not db.showResourceText
                end,
            },
            -- Rune options (Death Knight)
            runeHeader = {
                type = "header",
                name = "Rune Options (Death Knight)",
                order = 7.2,
                hidden = function()
                    local def = GetActiveClassResourceDef()
                    return not def or not def.isRunes
                end,
            },
            showRuneTimers = {
                type = "toggle",
                name = "Show Rune Cooldown Timers",
                desc = "Display remaining cooldown text on each rune segment.",
                order = 7.21,
                width = "full",
                get = function()
                    local db = GetRBSettings("classResource")
                    return db and db.showRuneTimers ~= false
                end,
                set = function(_, val)
                    local db = GetRBSettings("classResource")
                    if db then db.showRuneTimers = val; RefreshModule("classResource") end
                end,
                hidden = function()
                    local def = GetActiveClassResourceDef()
                    return not def or not def.isRunes
                end,
            },
            chargedHeader = {
                type = "header",
                name = "Charged Combo Points",
                order = 7.3,
                hidden = function()
                    local def = GetActiveClassResourceDef()
                    return not def or not def.hasCharged
                end,
            },
            chargedColor = {
                type = "color",
                name = "Charged Fill Color",
                order = 7.31,
                hasAlpha = false,
                get = function()
                    local db = GetRBSettings("classResource")
                    if not db then return 0.2, 0.6, 1.0 end
                    local c = db.chargedColor or { r = 0.2, g = 0.6, b = 1.0 }
                    return c.r, c.g, c.b
                end,
                set = function(_, r, g, b)
                    local db = GetRBSettings("classResource")
                    if db then db.chargedColor = { r = r, g = g, b = b }; RefreshModule("classResource") end
                end,
                hidden = function()
                    local def = GetActiveClassResourceDef()
                    return not def or not def.hasCharged
                end,
            },
            chargedBgColor = {
                type = "color",
                name = "Charged Background Color",
                order = 7.32,
                hasAlpha = true,
                get = function()
                    local db = GetRBSettings("classResource")
                    if not db then return 0.1, 0.3, 0.5, 0.7 end
                    local c = db.chargedBgColor or { r = 0.1, g = 0.3, b = 0.5, a = 0.7 }
                    return c.r, c.g, c.b, c.a
                end,
                set = function(_, r, g, b, a)
                    local db = GetRBSettings("classResource")
                    if db then db.chargedBgColor = { r = r, g = g, b = b, a = a }; RefreshModule("classResource") end
                end,
                hidden = function()
                    local def = GetActiveClassResourceDef()
                    return not def or not def.hasCharged
                end,
            },
            -- Border
            spacer3 = { type = "description", name = "", order = 7.5, width = "full" },
            borderHeader = {
                type = "header",
                name = "Border",
                order = 8,
            },
            borderSize = {
                type = "range",
                name = "Border Size",
                order = 9,
                min = 0, max = 4, step = 1,
                get = function() local db = GetRBSettings("classResource"); return db and db.borderSize or 1 end,
                set = function(_, val)
                    local db = GetRBSettings("classResource")
                    if db then db.borderSize = val; RefreshModule("classResource") end
                end,
            },
            borderColor = {
                type = "color",
                name = "Border Color",
                order = 10,
                hasAlpha = true,
                get = function()
                    local db = GetRBSettings("classResource")
                    local c = db and db.borderColor or { r = 0, g = 0, b = 0, a = 1 }
                    return c.r, c.g, c.b, c.a
                end,
                set = function(_, r, g, b, a)
                    local db = GetRBSettings("classResource")
                    if db then db.borderColor = { r = r, g = g, b = b, a = a }; RefreshModule("classResource") end
                end,
            },
            -- Stagger bar settings (only relevant for Brewmaster)
            spacer4 = { type = "description", name = "", order = 14.5, width = "full" },
            staggerHeader = {
                type = "header",
                name = "Stagger Bar (Brewmaster)",
                order = 15,
            },
            staggerWidth = {
                type = "range",
                name = "Stagger Bar Width",
                order = 16,
                min = 50, max = 500, step = 1,
                get = function() local db = GetRBSettings("classResource"); return db and db.staggerWidth or 200 end,
                set = function(_, val)
                    local db = GetRBSettings("classResource")
                    if db then db.staggerWidth = val; RefreshModule("classResource") end
                end,
            },
            staggerHeight = {
                type = "range",
                name = "Stagger Bar Height",
                order = 17,
                min = 4, max = 40, step = 1,
                get = function() local db = GetRBSettings("classResource"); return db and db.staggerHeight or 14 end,
                set = function(_, val)
                    local db = GetRBSettings("classResource")
                    if db then db.staggerHeight = val; RefreshModule("classResource") end
                end,
            },
            staggerShowText = {
                type = "toggle",
                name = "Show Stagger Text",
                order = 18,
                get = function() local db = GetRBSettings("classResource"); return db and db.staggerShowText end,
                set = function(_, val)
                    local db = GetRBSettings("classResource")
                    if db then db.staggerShowText = val; RefreshModule("classResource") end
                end,
            },
            staggerTextFormat = {
                type = "select",
                name = "Stagger Text Format",
                order = 18.5,
                values = STAGGER_TEXT_FORMAT_VALUES,
                get = function() local db = GetRBSettings("classResource"); return db and db.staggerTextFormat or "both" end,
                set = function(_, val)
                    local db = GetRBSettings("classResource")
                    if db then db.staggerTextFormat = val; RefreshModule("classResource") end
                end,
                hidden = function()
                    local db = GetRBSettings("classResource")
                    return not db or not db.staggerShowText
                end,
            },
            staggerTextSize = {
                type = "range",
                name = "Stagger Text Size",
                order = 18.6,
                min = 6, max = 24, step = 1,
                get = function() local db = GetRBSettings("classResource"); return db and db.staggerTextSize or 11 end,
                set = function(_, val)
                    local db = GetRBSettings("classResource")
                    if db then db.staggerTextSize = val; RefreshModule("classResource") end
                end,
                hidden = function()
                    local db = GetRBSettings("classResource")
                    return not db or not db.staggerShowText
                end,
            },
            staggerTexture = {
                type = "select",
                name = "Stagger Texture",
                order = 19,
                dialogControl = "LSM30_Statusbar",
                values = function() return GetTextureValues() end,
                get = function() local db = GetRBSettings("classResource"); return db and db.staggerTexture or "Blizzard Raid Bar" end,
                set = function(_, val)
                    local db = GetRBSettings("classResource")
                    if db then db.staggerTexture = val; RefreshModule("classResource") end
                end,
            },
            -- Visibility
            spacer5 = { type = "description", name = "", order = 19.5, width = "full" },
            visibilityHeader = {
                type = "header",
                name = "Visibility",
                order = 20,
            },
            hideWhenMounted = {
                type = "toggle",
                name = "Hide When Mounted",
                order = 21,
                get = function() local db = GetRBSettings("classResource"); return db and db.hideWhenMounted end,
                set = function(_, val)
                    local db = GetRBSettings("classResource")
                    if db then db.hideWhenMounted = val; RefreshModule("classResource") end
                end,
            },
            hideOutOfCombat = {
                type = "toggle",
                name = "Hide Out of Combat",
                order = 22,
                get = function() local db = GetRBSettings("classResource"); return db and db.hideOutOfCombat end,
                set = function(_, val)
                    local db = GetRBSettings("classResource")
                    if db then db.hideOutOfCombat = val; RefreshModule("classResource") end
                end,
            },
            -- Positioning & Anchoring
            spacer6 = { type = "description", name = "", order = 29.5, width = "full" },
            positionHeader = {
                type = "header",
                name = "Position & Anchor",
                order = 30,
            },
            anchorMode = {
                type = "select",
                name = "Anchor To",
                order = 30.1,
                values = { free = "Free (Drag)", viewer = "Cooldown Viewer" },
                get = function() local db = GetRBSettings("classResource"); return db and db.anchor or "free" end,
                set = function(_, val)
                    local db = GetRBSettings("classResource")
                    if db then db.anchor = val; RefreshModule("classResource") end
                end,
            },
            anchorStackDesc = {
                type = "description",
                name = "Bars anchored to the same viewer stack automatically with no gaps. Disabled or hidden bars are skipped.",
                order = 30.15,
                width = "full",
                hidden = function() local db = GetRBSettings("classResource"); return not db or db.anchor ~= "viewer" end,
            },
            anchorTarget = {
                type = "select",
                name = "Viewer",
                order = 30.2,
                values = function()
                    return RB and RB.ANCHOR_TARGET_LABELS or { essential = "Essential" }
                end,
                get = function() local db = GetRBSettings("classResource"); return db and db.anchorTarget or "essential" end,
                set = function(_, val)
                    local db = GetRBSettings("classResource")
                    if db then
                        db.anchorTarget = val
                        if RB then RB:HookAnchorResize(val) end
                        RefreshModule("classResource")
                    end
                end,
                hidden = function() local db = GetRBSettings("classResource"); return not db or db.anchor ~= "viewer" end,
            },
            anchorPosition = {
                type = "select",
                name = "Position",
                order = 30.3,
                values = { BELOW = "Below", ABOVE = "Above", LEFT = "Left", RIGHT = "Right" },
                get = function() local db = GetRBSettings("classResource"); return db and db.anchorPosition or "BELOW" end,
                set = function(_, val)
                    local db = GetRBSettings("classResource")
                    if db then db.anchorPosition = val; RefreshModule("classResource") end
                end,
                hidden = function() local db = GetRBSettings("classResource"); return not db or db.anchor ~= "viewer" end,
            },
            anchorOffset = {
                type = "range",
                name = "Offset from Viewer",
                desc = "Gap between the viewer and the first visible bar in the stack.",
                order = 30.4,
                min = -50, max = 50, step = 1,
                get = function() local db = GetRBSettings("classResource"); return db and db.anchorOffset or 2 end,
                set = function(_, val)
                    local db = GetRBSettings("classResource")
                    if db then db.anchorOffset = val; RefreshModule("classResource") end
                end,
                hidden = function() local db = GetRBSettings("classResource"); return not db or db.anchor ~= "viewer" end,
            },
            widthMatchAnchor = {
                type = "toggle",
                name = "Match Anchor Width",
                desc = "Automatically resize bar width to match the viewer width.",
                order = 30.5,
                get = function() local db = GetRBSettings("classResource"); return db and db.widthMatchAnchor end,
                set = function(_, val)
                    local db = GetRBSettings("classResource")
                    if db then
                        db.widthMatchAnchor = val
                        if val and RB then RB:HookAnchorResize(db.anchorTarget or "essential") end
                        RefreshModule("classResource")
                    end
                end,
                hidden = function() local db = GetRBSettings("classResource"); return not db or db.anchor ~= "viewer" end,
            },
            lockBar = {
                type = "toggle",
                name = "Lock Bar (Drag to Reposition)",
                desc = "Uncheck to unlock and drag the bar to a new position.",
                order = 31,
                width = "full",
                get = function()
                    local bar = RB and (RB.bars["classResource"] or RB.bars["classResource_stagger"])
                    return bar and bar._locked
                end,
                set = function(_, val)
                    if RB then
                        local bar = RB.bars["classResource"]
                        if bar then bar._locked = val end
                        bar = RB.bars["classResource_stagger"]
                        if bar then bar._locked = val end
                    end
                end,
                hidden = function() local db = GetRBSettings("classResource"); return db and db.anchor == "viewer" end,
            },
            resetPosition = {
                type = "execute",
                name = "Reset Position",
                order = 32,
                func = function()
                    local db = GetRBSettings("classResource")
                    if db then
                        db.position = { point = "CENTER", x = 0, y = -60 }
                        RefreshModule("classResource")
                    end
                end,
                hidden = function() local db = GetRBSettings("classResource"); return db and db.anchor == "viewer" end,
            },
        },
    }

    -- Dynamically inject per-segment color pickers (up to 10)
    for idx = 1, 10 do
        result.args["segColor" .. idx] = {
            type = "color",
            name = function()
                local def = GetActiveClassResourceDef()
                local label = def and SEGMENT_LABELS[def.resource] or "Segment"
                return label .. " " .. idx
            end,
            order = 7.1 + idx * 0.008,
            hasAlpha = false,
            get = function()
                local db = GetRBSettings("classResource")
                if not db then return 1, 1, 1 end
                local saved = db.segmentColors and db.segmentColors[idx]
                if saved then return saved.r, saved.g, saved.b end
                -- Fall back to def.colors default
                local def = GetActiveClassResourceDef()
                if def and def.colors and def.colors[idx] then
                    local c = def.colors[idx]
                    return c.r, c.g, c.b
                end
                local c = def and def.color or { r = 1, g = 1, b = 1 }
                return c.r, c.g, c.b
            end,
            set = function(_, r, g, b)
                local db = GetRBSettings("classResource")
                if not db then return end
                if not db.segmentColors then db.segmentColors = {} end
                db.segmentColors[idx] = { r = r, g = g, b = b }
                RefreshModule("classResource")
            end,
            hidden = function()
                local db = GetRBSettings("classResource")
                if not db or not db.usePerPointColor then return true end
                local def, maxPts = GetActiveClassResourceDef()
                if not def then return true end
                return idx > maxPts
            end,
        }
    end

    return result
end

-- ============================================================
-- Ironfur Tracker tab (Guardian Druid)
-- ============================================================
local function BuildIronfurTrackerTab()
    local moduleName = "ironfurTracker"
    return {
        type = "group",
        name = "Ironfur Tracker",
        order = 5,
        args = {
            desc = {
                type = "description",
                name = "Tracks active Ironfur stacks for Guardian Druid. Each cast creates a draining segment.",
                order = 0,
                width = "full",
            },
            enabled = {
                type = "toggle",
                name = "Enable Ironfur Tracker",
                order = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.enabled end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.enabled = val; RefreshModule(moduleName) end
                end,
            },
            spacer1 = { type = "description", name = "", order = 1.5, width = "full" },
            -- Dimensions
            width = {
                type = "range",
                name = "Width",
                order = 2,
                min = 60, max = 500, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.width or 180 end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.width = val; RefreshModule(moduleName) end
                end,
                hidden = function() local db = GetRBSettings(moduleName); return db and db.widthMatchAnchor and db.anchor == "viewer" end,
            },
            height = {
                type = "range",
                name = "Height",
                order = 3,
                min = 8, max = 80, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.height or 24 end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.height = val; RefreshModule(moduleName) end
                end,
            },
            maxSegments = {
                type = "range",
                name = "Max Segments",
                order = 4,
                min = 1, max = 30, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.maxSegments or 6 end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.maxSegments = val; RefreshModule(moduleName) end
                end,
            },
            -- Texture
            texture = {
                type = "select",
                name = "Segment Texture",
                order = 5,
                dialogControl = "LSM30_Statusbar",
                values = function() return GetTextureValues() end,
                get = function() local db = GetRBSettings(moduleName); return db and db.texture or "Blizzard Raid Bar" end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.texture = val; RefreshModule(moduleName) end
                end,
            },
            -- Colors
            spacer2 = { type = "description", name = "", order = 5.5, width = "full" },
            segmentColor = {
                type = "color",
                name = "Segment Color",
                order = 6,
                hasAlpha = true,
                get = function()
                    local db = GetRBSettings(moduleName)
                    local c = db and db.segmentColor or { r = 0.5, g = 0.8, b = 1.0, a = 1 }
                    return c.r, c.g, c.b, c.a
                end,
                set = function(_, r, g, b, a)
                    local db = GetRBSettings(moduleName)
                    if db then db.segmentColor = { r = r, g = g, b = b, a = a }; RefreshModule(moduleName) end
                end,
            },
            tickColor = {
                type = "color",
                name = "Tick Color",
                order = 7,
                hasAlpha = true,
                get = function()
                    local db = GetRBSettings(moduleName)
                    local c = db and db.tickColor or { r = 0, g = 0, b = 0, a = 1 }
                    return c.r, c.g, c.b, c.a
                end,
                set = function(_, r, g, b, a)
                    local db = GetRBSettings(moduleName)
                    if db then db.tickColor = { r = r, g = g, b = b, a = a }; RefreshModule(moduleName) end
                end,
            },
            bgColor = {
                type = "color",
                name = "Background Color",
                order = 8,
                hasAlpha = true,
                get = function()
                    local db = GetRBSettings(moduleName)
                    local c = db and db.bgColor or { r = 0.08, g = 0.08, b = 0.08, a = 0.85 }
                    return c.r, c.g, c.b, c.a
                end,
                set = function(_, r, g, b, a)
                    local db = GetRBSettings(moduleName)
                    if db then db.bgColor = { r = r, g = g, b = b, a = a }; RefreshModule(moduleName) end
                end,
            },
            -- Border
            borderSize = {
                type = "range",
                name = "Border Size",
                order = 9,
                min = 0, max = 4, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.borderSize or 1 end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.borderSize = val; RefreshModule(moduleName) end
                end,
            },
            borderColor = {
                type = "color",
                name = "Border Color",
                order = 10,
                hasAlpha = true,
                get = function()
                    local db = GetRBSettings(moduleName)
                    local c = db and db.borderColor or { r = 0, g = 0, b = 0, a = 1 }
                    return c.r, c.g, c.b, c.a
                end,
                set = function(_, r, g, b, a)
                    local db = GetRBSettings(moduleName)
                    if db then db.borderColor = { r = r, g = g, b = b, a = a }; RefreshModule(moduleName) end
                end,
            },
            -- Text
            spacer3 = { type = "description", name = "", order = 10.5, width = "full" },
            showText = {
                type = "toggle",
                name = "Show Stack Count",
                order = 11,
                get = function() local db = GetRBSettings(moduleName); return db and db.showText end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.showText = val; RefreshModule(moduleName) end
                end,
            },
            textSize = {
                type = "range",
                name = "Text Size",
                order = 12,
                min = 8, max = 48, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.textSize or 20 end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.textSize = val; RefreshModule(moduleName) end
                end,
            },
            textPosition = {
                type = "select",
                name = "Text Position",
                order = 13,
                values = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" },
                get = function() local db = GetRBSettings(moduleName); return db and db.textPosition or "CENTER" end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.textPosition = val; RefreshModule(moduleName) end
                end,
            },
            -- Visibility
            spacer4 = { type = "description", name = "", order = 19.5, width = "full" },
            visibilityHeader = {
                type = "header",
                name = "Visibility",
                order = 20,
            },
            hideWhenMounted = {
                type = "toggle",
                name = "Hide When Mounted",
                order = 21,
                get = function() local db = GetRBSettings(moduleName); return db and db.hideWhenMounted end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.hideWhenMounted = val; RefreshModule(moduleName) end
                end,
            },
            hideOutOfCombat = {
                type = "toggle",
                name = "Hide Out of Combat",
                order = 22,
                get = function() local db = GetRBSettings(moduleName); return db and db.hideOutOfCombat end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.hideOutOfCombat = val; RefreshModule(moduleName) end
                end,
            },
            -- Position & Anchor
            spacer5 = { type = "description", name = "", order = 29.5, width = "full" },
            positionHeader = {
                type = "header",
                name = "Position & Anchor",
                order = 30,
            },
            anchorMode = {
                type = "select",
                name = "Anchor To",
                order = 30.1,
                values = { free = "Free (Drag)", viewer = "Cooldown Viewer" },
                get = function() local db = GetRBSettings(moduleName); return db and db.anchor or "free" end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.anchor = val; RefreshModule(moduleName) end
                end,
            },
            anchorStackDesc = {
                type = "description",
                name = "Bars anchored to the same viewer stack automatically with no gaps. Disabled or hidden bars are skipped.",
                order = 30.15,
                width = "full",
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
            },
            anchorTarget = {
                type = "select",
                name = "Viewer",
                order = 30.2,
                values = function()
                    return RB and RB.ANCHOR_TARGET_LABELS or { essential = "Essential" }
                end,
                get = function() local db = GetRBSettings(moduleName); return db and db.anchorTarget or "essential" end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then
                        db.anchorTarget = val
                        if RB then RB:HookAnchorResize(val) end
                        RefreshModule(moduleName)
                    end
                end,
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
            },
            anchorPosition = {
                type = "select",
                name = "Position",
                order = 30.3,
                values = { BELOW = "Below", ABOVE = "Above", LEFT = "Left", RIGHT = "Right" },
                get = function() local db = GetRBSettings(moduleName); return db and db.anchorPosition or "BELOW" end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.anchorPosition = val; RefreshModule(moduleName) end
                end,
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
            },
            anchorOffset = {
                type = "range",
                name = "Offset from Viewer",
                desc = "Gap between the viewer and the first visible bar in the stack.",
                order = 30.4,
                min = -50, max = 50, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.anchorOffset or 2 end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.anchorOffset = val; RefreshModule(moduleName) end
                end,
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
            },
            widthMatchAnchor = {
                type = "toggle",
                name = "Match Anchor Width",
                desc = "Automatically resize bar width to match the viewer width.",
                order = 30.5,
                get = function() local db = GetRBSettings(moduleName); return db and db.widthMatchAnchor end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then
                        db.widthMatchAnchor = val
                        if val and RB then RB:HookAnchorResize(db.anchorTarget or "essential") end
                        RefreshModule(moduleName)
                    end
                end,
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
            },
            lockBar = {
                type = "toggle",
                name = "Lock Bar (Drag to Reposition)",
                desc = "Uncheck to unlock and drag the bar to a new position.",
                order = 31,
                width = "full",
                get = function()
                    local bar = RB and RB.bars[moduleName]
                    return bar and bar._locked
                end,
                set = function(_, val)
                    local bar = RB and RB.bars[moduleName]
                    if bar then bar._locked = val end
                end,
                hidden = function() local db = GetRBSettings(moduleName); return db and db.anchor == "viewer" end,
            },
            resetPosition = {
                type = "execute",
                name = "Reset Position",
                order = 32,
                func = function()
                    local db = GetRBSettings(moduleName)
                    if db then
                        local defaults = RB.MODULE_DEFAULTS[moduleName]
                        if defaults and defaults.position then
                            db.position = { point = defaults.position.point, x = defaults.position.x, y = defaults.position.y }
                        else
                            db.position = { point = "CENTER", x = 0, y = -200 }
                        end
                        RefreshModule(moduleName)
                    end
                end,
                hidden = function() local db = GetRBSettings(moduleName); return db and db.anchor == "viewer" end,
            },
        },
    }
end

-- ============================================================
-- Monk Orb Tracker tab (Brewmaster Monk)
-- ============================================================
local function BuildMonkOrbTrackerTab()
    local moduleName = "monkOrbTracker"
    return {
        type = "group",
        name = "Monk Orb Tracker",
        order = 6,
        args = {
            desc = {
                type = "description",
                name = "Tracks stagger orb count for Brewmaster Monk as a filled status bar with divider ticks.",
                order = 0,
                width = "full",
            },
            enabled = {
                type = "toggle",
                name = "Enable Orb Tracker",
                order = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.enabled end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.enabled = val; RefreshModule(moduleName) end
                end,
            },
            spacer1 = { type = "description", name = "", order = 1.5, width = "full" },
            -- Dimensions
            width = {
                type = "range",
                name = "Width",
                order = 2,
                min = 60, max = 500, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.width or 120 end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.width = val; RefreshModule(moduleName) end
                end,
                hidden = function() local db = GetRBSettings(moduleName); return db and db.widthMatchAnchor and db.anchor == "viewer" end,
            },
            height = {
                type = "range",
                name = "Height",
                order = 3,
                min = 8, max = 80, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.height or 24 end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.height = val; RefreshModule(moduleName) end
                end,
            },
            numOrbs = {
                type = "range",
                name = "Max Orbs",
                order = 4,
                min = 1, max = 20, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.numOrbs or 5 end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.numOrbs = val; RefreshModule(moduleName) end
                end,
            },
            -- Texture
            texture = {
                type = "select",
                name = "Bar Texture",
                order = 5,
                dialogControl = "LSM30_Statusbar",
                values = function() return GetTextureValues() end,
                get = function() local db = GetRBSettings(moduleName); return db and db.texture or "Blizzard Raid Bar" end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.texture = val; RefreshModule(moduleName) end
                end,
            },
            bgTexture = {
                type = "select",
                name = "Background Texture",
                desc = "Select a background texture. Leave default for flat color.",
                order = 5.5,
                dialogControl = "LSM30_Statusbar",
                values = function()
                    local vals = GetTextureValues()
                    vals[""] = "(None - Flat Color)"
                    return vals
                end,
                get = function() local db = GetRBSettings(moduleName); return db and db.bgTexture or "" end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.bgTexture = val; RefreshModule(moduleName) end
                end,
            },
            -- Colors
            spacer2 = { type = "description", name = "", order = 5.9, width = "full" },
            gradientStart = {
                type = "color",
                name = "Gradient Start",
                order = 6,
                hasAlpha = true,
                get = function()
                    local db = GetRBSettings(moduleName)
                    local c = db and db.gradientStart or { r = 0.46, g = 0.98, b = 1.00, a = 1 }
                    return c.r, c.g, c.b, c.a
                end,
                set = function(_, r, g, b, a)
                    local db = GetRBSettings(moduleName)
                    if db then db.gradientStart = { r = r, g = g, b = b, a = a }; RefreshModule(moduleName) end
                end,
            },
            gradientEnd = {
                type = "color",
                name = "Gradient End",
                order = 7,
                hasAlpha = true,
                get = function()
                    local db = GetRBSettings(moduleName)
                    local c = db and db.gradientEnd or { r = 0.00, g = 0.50, b = 1.00, a = 1 }
                    return c.r, c.g, c.b, c.a
                end,
                set = function(_, r, g, b, a)
                    local db = GetRBSettings(moduleName)
                    if db then db.gradientEnd = { r = r, g = g, b = b, a = a }; RefreshModule(moduleName) end
                end,
            },
            bgColor = {
                type = "color",
                name = "Background Color",
                order = 8,
                hasAlpha = true,
                get = function()
                    local db = GetRBSettings(moduleName)
                    local c = db and db.bgColor or { r = 0.08, g = 0.08, b = 0.08, a = 0.75 }
                    return c.r, c.g, c.b, c.a
                end,
                set = function(_, r, g, b, a)
                    local db = GetRBSettings(moduleName)
                    if db then db.bgColor = { r = r, g = g, b = b, a = a }; RefreshModule(moduleName) end
                end,
            },
            -- Border
            borderSize = {
                type = "range",
                name = "Border Size",
                order = 9,
                min = 0, max = 4, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.borderSize or 1 end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.borderSize = val; RefreshModule(moduleName) end
                end,
            },
            borderColor = {
                type = "color",
                name = "Border Color",
                order = 10,
                hasAlpha = true,
                get = function()
                    local db = GetRBSettings(moduleName)
                    local c = db and db.borderColor or { r = 0, g = 0, b = 0, a = 1 }
                    return c.r, c.g, c.b, c.a
                end,
                set = function(_, r, g, b, a)
                    local db = GetRBSettings(moduleName)
                    if db then db.borderColor = { r = r, g = g, b = b, a = a }; RefreshModule(moduleName) end
                end,
            },
            -- Visibility
            spacer3 = { type = "description", name = "", order = 19.5, width = "full" },
            visibilityHeader = {
                type = "header",
                name = "Visibility",
                order = 20,
            },
            hideWhenMounted = {
                type = "toggle",
                name = "Hide When Mounted",
                order = 21,
                get = function() local db = GetRBSettings(moduleName); return db and db.hideWhenMounted end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.hideWhenMounted = val; RefreshModule(moduleName) end
                end,
            },
            hideOutOfCombat = {
                type = "toggle",
                name = "Hide Out of Combat",
                order = 22,
                get = function() local db = GetRBSettings(moduleName); return db and db.hideOutOfCombat end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.hideOutOfCombat = val; RefreshModule(moduleName) end
                end,
            },
            -- Position & Anchor
            spacer4 = { type = "description", name = "", order = 29.5, width = "full" },
            positionHeader = {
                type = "header",
                name = "Position & Anchor",
                order = 30,
            },
            anchorMode = {
                type = "select",
                name = "Anchor To",
                order = 30.1,
                values = { free = "Free (Drag)", viewer = "Cooldown Viewer" },
                get = function() local db = GetRBSettings(moduleName); return db and db.anchor or "free" end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.anchor = val; RefreshModule(moduleName) end
                end,
            },
            anchorStackDesc = {
                type = "description",
                name = "Bars anchored to the same viewer stack automatically with no gaps. Disabled or hidden bars are skipped.",
                order = 30.15,
                width = "full",
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
            },
            anchorTarget = {
                type = "select",
                name = "Viewer",
                order = 30.2,
                values = function()
                    return RB and RB.ANCHOR_TARGET_LABELS or { essential = "Essential" }
                end,
                get = function() local db = GetRBSettings(moduleName); return db and db.anchorTarget or "essential" end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then
                        db.anchorTarget = val
                        if RB then RB:HookAnchorResize(val) end
                        RefreshModule(moduleName)
                    end
                end,
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
            },
            anchorPosition = {
                type = "select",
                name = "Position",
                order = 30.3,
                values = { BELOW = "Below", ABOVE = "Above", LEFT = "Left", RIGHT = "Right" },
                get = function() local db = GetRBSettings(moduleName); return db and db.anchorPosition or "BELOW" end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.anchorPosition = val; RefreshModule(moduleName) end
                end,
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
            },
            anchorOffset = {
                type = "range",
                name = "Offset from Viewer",
                desc = "Gap between the viewer and the first visible bar in the stack.",
                order = 30.4,
                min = -50, max = 50, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.anchorOffset or 2 end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.anchorOffset = val; RefreshModule(moduleName) end
                end,
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
            },
            widthMatchAnchor = {
                type = "toggle",
                name = "Match Anchor Width",
                desc = "Automatically resize bar width to match the viewer width.",
                order = 30.5,
                get = function() local db = GetRBSettings(moduleName); return db and db.widthMatchAnchor end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then
                        db.widthMatchAnchor = val
                        if val and RB then RB:HookAnchorResize(db.anchorTarget or "essential") end
                        RefreshModule(moduleName)
                    end
                end,
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
            },
            lockBar = {
                type = "toggle",
                name = "Lock Bar (Drag to Reposition)",
                desc = "Uncheck to unlock and drag the bar to a new position.",
                order = 31,
                width = "full",
                get = function()
                    local b = RB and RB.bars[moduleName]
                    return b and b._locked
                end,
                set = function(_, val)
                    local b = RB and RB.bars[moduleName]
                    if b then b._locked = val end
                end,
                hidden = function() local db = GetRBSettings(moduleName); return db and db.anchor == "viewer" end,
            },
            resetPosition = {
                type = "execute",
                name = "Reset Position",
                order = 32,
                func = function()
                    local db = GetRBSettings(moduleName)
                    if db then
                        local defaults = RB.MODULE_DEFAULTS[moduleName]
                        if defaults and defaults.position then
                            db.position = { point = defaults.position.point, x = defaults.position.x, y = defaults.position.y }
                        else
                            db.position = { point = "CENTER", x = 0, y = -200 }
                        end
                        RefreshModule(moduleName)
                    end
                end,
                hidden = function() local db = GetRBSettings(moduleName); return db and db.anchor == "viewer" end,
            },
        },
    }
end

-- ============================================================
-- Vengeance Soul Tracker options tab
-- ============================================================
local function BuildVengeanceSoulTrackerTab()
    local moduleName = "vengeanceSoulTracker"
    return {
        type = "group",
        name = "Vengeance Soul Tracker",
        order = 7,
        args = {
            desc = {
                type = "description",
                name = "Tracks Soul Fragment count for Vengeance Demon Hunter as a filled status bar with divider ticks.",
                order = 0,
                width = "full",
            },
            enabled = {
                type = "toggle",
                name = "Enable Soul Tracker",
                order = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.enabled end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.enabled = val; RefreshModule(moduleName) end
                end,
            },
            spacer1 = { type = "description", name = "", order = 1.5, width = "full" },
            width = {
                type = "range", name = "Width", order = 2, min = 60, max = 500, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.width or 120 end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.width = val; RefreshModule(moduleName) end end,
                hidden = function() local db = GetRBSettings(moduleName); return db and db.widthMatchAnchor and db.anchor == "viewer" end,
            },
            height = {
                type = "range", name = "Height", order = 3, min = 8, max = 80, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.height or 24 end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.height = val; RefreshModule(moduleName) end end,
            },
            numSouls = {
                type = "range", name = "Max Souls", order = 4, min = 1, max = 20, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.numSouls or 6 end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.numSouls = val; RefreshModule(moduleName) end end,
            },
            texture = {
                type = "select", name = "Bar Texture", order = 5, dialogControl = "LSM30_Statusbar",
                values = function() return GetTextureValues() end,
                get = function() local db = GetRBSettings(moduleName); return db and db.texture or "Blizzard Raid Bar" end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.texture = val; RefreshModule(moduleName) end end,
            },
            bgTexture = {
                type = "select", name = "Background Texture", order = 5.5, dialogControl = "LSM30_Statusbar",
                values = function() local vals = GetTextureValues(); vals[""] = "(None - Flat Color)"; return vals end,
                get = function() local db = GetRBSettings(moduleName); return db and db.bgTexture or "" end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.bgTexture = val; RefreshModule(moduleName) end end,
            },
            spacer2 = { type = "description", name = "", order = 5.9, width = "full" },
            gradientStart = {
                type = "color", name = "Gradient Start", order = 6, hasAlpha = true,
                get = function() local db = GetRBSettings(moduleName); local c = db and db.gradientStart or { r = 0.46, g = 0.98, b = 1.00, a = 1 }; return c.r, c.g, c.b, c.a end,
                set = function(_, r, g, b, a) local db = GetRBSettings(moduleName); if db then db.gradientStart = { r = r, g = g, b = b, a = a }; RefreshModule(moduleName) end end,
            },
            gradientEnd = {
                type = "color", name = "Gradient End", order = 7, hasAlpha = true,
                get = function() local db = GetRBSettings(moduleName); local c = db and db.gradientEnd or { r = 0.00, g = 0.50, b = 1.00, a = 1 }; return c.r, c.g, c.b, c.a end,
                set = function(_, r, g, b, a) local db = GetRBSettings(moduleName); if db then db.gradientEnd = { r = r, g = g, b = b, a = a }; RefreshModule(moduleName) end end,
            },
            bgColor = {
                type = "color", name = "Background Color", order = 8, hasAlpha = true,
                get = function() local db = GetRBSettings(moduleName); local c = db and db.bgColor or { r = 0.08, g = 0.08, b = 0.08, a = 0.75 }; return c.r, c.g, c.b, c.a end,
                set = function(_, r, g, b, a) local db = GetRBSettings(moduleName); if db then db.bgColor = { r = r, g = g, b = b, a = a }; RefreshModule(moduleName) end end,
            },
            borderSize = {
                type = "range", name = "Border Size", order = 9, min = 0, max = 4, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.borderSize or 1 end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.borderSize = val; RefreshModule(moduleName) end end,
            },
            borderColor = {
                type = "color", name = "Border Color", order = 10, hasAlpha = true,
                get = function() local db = GetRBSettings(moduleName); local c = db and db.borderColor or { r = 0, g = 0, b = 0, a = 1 }; return c.r, c.g, c.b, c.a end,
                set = function(_, r, g, b, a) local db = GetRBSettings(moduleName); if db then db.borderColor = { r = r, g = g, b = b, a = a }; RefreshModule(moduleName) end end,
            },
            spacer3 = { type = "description", name = "", order = 19.5, width = "full" },
            visibilityHeader = { type = "header", name = "Visibility", order = 20 },
            hideWhenMounted = {
                type = "toggle", name = "Hide When Mounted", order = 21,
                get = function() local db = GetRBSettings(moduleName); return db and db.hideWhenMounted end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.hideWhenMounted = val; RefreshModule(moduleName) end end,
            },
            hideOutOfCombat = {
                type = "toggle", name = "Hide Out of Combat", order = 22,
                get = function() local db = GetRBSettings(moduleName); return db and db.hideOutOfCombat end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.hideOutOfCombat = val; RefreshModule(moduleName) end end,
            },
            spacer4 = { type = "description", name = "", order = 29.5, width = "full" },
            positionHeader = { type = "header", name = "Position & Anchor", order = 30 },
            anchorMode = {
                type = "select", name = "Anchor To", order = 30.1,
                values = { free = "Free (Drag)", viewer = "Cooldown Viewer" },
                get = function() local db = GetRBSettings(moduleName); return db and db.anchor or "free" end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.anchor = val; RefreshModule(moduleName) end end,
            },
            anchorStackDesc = {
                type = "description", name = "Bars anchored to the same viewer stack automatically with no gaps. Disabled or hidden bars are skipped.", order = 30.15, width = "full",
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
            },
            anchorTarget = {
                type = "select", name = "Viewer", order = 30.2,
                values = function() return RB and RB.ANCHOR_TARGET_LABELS or { essential = "Essential" } end,
                get = function() local db = GetRBSettings(moduleName); return db and db.anchorTarget or "essential" end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.anchorTarget = val; if RB then RB:HookAnchorResize(val) end; RefreshModule(moduleName) end end,
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
            },
            anchorPosition = {
                type = "select", name = "Position", order = 30.3,
                values = { BELOW = "Below", ABOVE = "Above", LEFT = "Left", RIGHT = "Right" },
                get = function() local db = GetRBSettings(moduleName); return db and db.anchorPosition or "BELOW" end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.anchorPosition = val; RefreshModule(moduleName) end end,
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
            },
            anchorOffset = {
                type = "range", name = "Offset from Viewer", order = 30.4, min = -50, max = 50, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.anchorOffset or 2 end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.anchorOffset = val; RefreshModule(moduleName) end end,
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
            },
            widthMatchAnchor = {
                type = "toggle", name = "Match Anchor Width", order = 30.5,
                get = function() local db = GetRBSettings(moduleName); return db and db.widthMatchAnchor end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.widthMatchAnchor = val; if val and RB then RB:HookAnchorResize(db.anchorTarget or "essential") end; RefreshModule(moduleName) end end,
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
            },
            lockBar = {
                type = "toggle", name = "Lock Bar (Drag to Reposition)", order = 31, width = "full",
                get = function() local b = RB and RB.bars[moduleName]; return b and b._locked end,
                set = function(_, val) local b = RB and RB.bars[moduleName]; if b then b._locked = val end end,
                hidden = function() local db = GetRBSettings(moduleName); return db and db.anchor == "viewer" end,
            },
            resetPosition = {
                type = "execute", name = "Reset Position", order = 32,
                func = function() local db = GetRBSettings(moduleName); if db then local d = RB.MODULE_DEFAULTS[moduleName]; if d and d.position then db.position = { point = d.position.point, x = d.position.x, y = d.position.y } else db.position = { point = "CENTER", x = 0, y = -200 } end; RefreshModule(moduleName) end end,
                hidden = function() local db = GetRBSettings(moduleName); return db and db.anchor == "viewer" end,
            },
        },
    }
end

-- ============================================================
-- Warrior Whirlwind Tracker options tab
-- ============================================================
local function BuildWarriorWhirlwindTrackerTab()
    local moduleName = "warriorWhirlwindTracker"
    return {
        type = "group",
        name = "Warrior Whirlwind Tracker",
        order = 8,
        args = {
            desc = {
                type = "description",
                name = "Tracks Improved Whirlwind stacks for Fury Warrior as a filled status bar with divider ticks.",
                order = 0,
                width = "full",
            },
            enabled = {
                type = "toggle",
                name = "Enable Whirlwind Tracker",
                order = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.enabled end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.enabled = val; RefreshModule(moduleName) end
                end,
            },
            spacer1 = { type = "description", name = "", order = 1.5, width = "full" },
            width = {
                type = "range", name = "Width", order = 2, min = 60, max = 500, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.width or 120 end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.width = val; RefreshModule(moduleName) end end,
                hidden = function() local db = GetRBSettings(moduleName); return db and db.widthMatchAnchor and db.anchor == "viewer" end,
            },
            height = {
                type = "range", name = "Height", order = 3, min = 8, max = 80, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.height or 24 end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.height = val; RefreshModule(moduleName) end end,
            },
            numSegments = {
                type = "range", name = "Number of Segments", order = 4, min = 1, max = 10, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.numSegments or 4 end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.numSegments = val; RefreshModule(moduleName) end end,
            },
            texture = {
                type = "select", name = "Bar Texture", order = 5, dialogControl = "LSM30_Statusbar",
                values = function() return GetTextureValues() end,
                get = function() local db = GetRBSettings(moduleName); return db and db.texture or "Blizzard Raid Bar" end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.texture = val; RefreshModule(moduleName) end end,
            },
            bgTexture = {
                type = "select", name = "Background Texture", order = 5.5, dialogControl = "LSM30_Statusbar",
                values = function() local vals = GetTextureValues(); vals[""] = "(None - Flat Color)"; return vals end,
                get = function() local db = GetRBSettings(moduleName); return db and db.bgTexture or "" end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.bgTexture = val; RefreshModule(moduleName) end end,
            },
            spacer2 = { type = "description", name = "", order = 5.9, width = "full" },
            gradientStart = {
                type = "color", name = "Gradient Start", order = 6, hasAlpha = true,
                get = function() local db = GetRBSettings(moduleName); local c = db and db.gradientStart or { r = 0.78, g = 0.61, b = 0.43, a = 1 }; return c.r, c.g, c.b, c.a end,
                set = function(_, r, g, b, a) local db = GetRBSettings(moduleName); if db then db.gradientStart = { r = r, g = g, b = b, a = a }; RefreshModule(moduleName) end end,
            },
            gradientEnd = {
                type = "color", name = "Gradient End", order = 7, hasAlpha = true,
                get = function() local db = GetRBSettings(moduleName); local c = db and db.gradientEnd or { r = 0.50, g = 0.30, b = 0.15, a = 1 }; return c.r, c.g, c.b, c.a end,
                set = function(_, r, g, b, a) local db = GetRBSettings(moduleName); if db then db.gradientEnd = { r = r, g = g, b = b, a = a }; RefreshModule(moduleName) end end,
            },
            bgColor = {
                type = "color", name = "Background Color", order = 8, hasAlpha = true,
                get = function() local db = GetRBSettings(moduleName); local c = db and db.bgColor or { r = 0.08, g = 0.08, b = 0.08, a = 0.75 }; return c.r, c.g, c.b, c.a end,
                set = function(_, r, g, b, a) local db = GetRBSettings(moduleName); if db then db.bgColor = { r = r, g = g, b = b, a = a }; RefreshModule(moduleName) end end,
            },
            borderSize = {
                type = "range", name = "Border Size", order = 9, min = 0, max = 4, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.borderSize or 1 end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.borderSize = val; RefreshModule(moduleName) end end,
            },
            borderColor = {
                type = "color", name = "Border Color", order = 10, hasAlpha = true,
                get = function() local db = GetRBSettings(moduleName); local c = db and db.borderColor or { r = 0, g = 0, b = 0, a = 1 }; return c.r, c.g, c.b, c.a end,
                set = function(_, r, g, b, a) local db = GetRBSettings(moduleName); if db then db.borderColor = { r = r, g = g, b = b, a = a }; RefreshModule(moduleName) end end,
            },
            spacer3 = { type = "description", name = "", order = 19.5, width = "full" },
            visibilityHeader = { type = "header", name = "Visibility", order = 20 },
            hideWhenMounted = {
                type = "toggle", name = "Hide When Mounted", order = 21,
                get = function() local db = GetRBSettings(moduleName); return db and db.hideWhenMounted end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.hideWhenMounted = val; RefreshModule(moduleName) end end,
            },
            hideOutOfCombat = {
                type = "toggle", name = "Hide Out of Combat", order = 22,
                get = function() local db = GetRBSettings(moduleName); return db and db.hideOutOfCombat end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.hideOutOfCombat = val; RefreshModule(moduleName) end end,
            },
            spacer4 = { type = "description", name = "", order = 29.5, width = "full" },
            positionHeader = { type = "header", name = "Position & Anchor", order = 30 },
            anchorMode = {
                type = "select", name = "Anchor To", order = 30.1,
                values = { free = "Free (Drag)", viewer = "Cooldown Viewer" },
                get = function() local db = GetRBSettings(moduleName); return db and db.anchor or "free" end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.anchor = val; RefreshModule(moduleName) end end,
            },
            anchorStackDesc = {
                type = "description", name = "Bars anchored to the same viewer stack automatically with no gaps. Disabled or hidden bars are skipped.", order = 30.15, width = "full",
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
            },
            anchorTarget = {
                type = "select", name = "Viewer", order = 30.2,
                values = function() return RB and RB.ANCHOR_TARGET_LABELS or { essential = "Essential" } end,
                get = function() local db = GetRBSettings(moduleName); return db and db.anchorTarget or "essential" end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.anchorTarget = val; if RB then RB:HookAnchorResize(val) end; RefreshModule(moduleName) end end,
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
            },
            anchorPosition = {
                type = "select", name = "Position", order = 30.3,
                values = { BELOW = "Below", ABOVE = "Above", LEFT = "Left", RIGHT = "Right" },
                get = function() local db = GetRBSettings(moduleName); return db and db.anchorPosition or "BELOW" end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.anchorPosition = val; RefreshModule(moduleName) end end,
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
            },
            anchorOffset = {
                type = "range", name = "Offset from Viewer", order = 30.4, min = -50, max = 50, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.anchorOffset or 2 end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.anchorOffset = val; RefreshModule(moduleName) end end,
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
            },
            widthMatchAnchor = {
                type = "toggle", name = "Match Anchor Width", order = 30.5,
                get = function() local db = GetRBSettings(moduleName); return db and db.widthMatchAnchor end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.widthMatchAnchor = val; if val and RB then RB:HookAnchorResize(db.anchorTarget or "essential") end; RefreshModule(moduleName) end end,
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
            },
            lockBar = {
                type = "toggle", name = "Lock Bar (Drag to Reposition)", order = 31, width = "full",
                get = function() local b = RB and RB.bars[moduleName]; return b and b._locked end,
                set = function(_, val) local b = RB and RB.bars[moduleName]; if b then b._locked = val end end,
                hidden = function() local db = GetRBSettings(moduleName); return db and db.anchor == "viewer" end,
            },
            resetPosition = {
                type = "execute", name = "Reset Position", order = 32,
                func = function() local db = GetRBSettings(moduleName); if db then local d = RB.MODULE_DEFAULTS[moduleName]; if d and d.position then db.position = { point = d.position.point, x = d.position.x, y = d.position.y } else db.position = { point = "CENTER", x = 0, y = -200 } end; RefreshModule(moduleName) end end,
                hidden = function() local db = GetRBSettings(moduleName); return db and db.anchor == "viewer" end,
            },
        },
    }
end

-- ============================================================
-- Maelstrom Tracker options tab
-- ============================================================
local function BuildMaelstromTrackerTab()
    local moduleName = "maelstromTracker"
    return {
        type = "group",
        name = "Maelstrom Tracker",
        order = 9,
        args = {
            desc = {
                type = "description",
                name = "Tracks Maelstrom Weapon stacks for Enhancement Shaman as a filled status bar with divider ticks.",
                order = 0,
                width = "full",
            },
            enabled = {
                type = "toggle",
                name = "Enable Maelstrom Tracker",
                order = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.enabled end,
                set = function(_, val)
                    local db = GetRBSettings(moduleName)
                    if db then db.enabled = val; RefreshModule(moduleName) end
                end,
            },
            spacer1 = { type = "description", name = "", order = 1.5, width = "full" },
            width = {
                type = "range", name = "Width", order = 2, min = 60, max = 500, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.width or 120 end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.width = val; RefreshModule(moduleName) end end,
                hidden = function() local db = GetRBSettings(moduleName); return db and db.widthMatchAnchor and db.anchor == "viewer" end,
            },
            height = {
                type = "range", name = "Height", order = 3, min = 8, max = 80, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.height or 24 end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.height = val; RefreshModule(moduleName) end end,
            },
            numStacks = {
                type = "range", name = "Max Stacks", order = 4, min = 1, max = 20, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.numStacks or 10 end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.numStacks = val; RefreshModule(moduleName) end end,
            },
            texture = {
                type = "select", name = "Bar Texture", order = 5, dialogControl = "LSM30_Statusbar",
                values = function() return GetTextureValues() end,
                get = function() local db = GetRBSettings(moduleName); return db and db.texture or "Blizzard Raid Bar" end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.texture = val; RefreshModule(moduleName) end end,
            },
            bgTexture = {
                type = "select", name = "Background Texture", order = 5.5, dialogControl = "LSM30_Statusbar",
                values = function() local vals = GetTextureValues(); vals[""] = "(None - Flat Color)"; return vals end,
                get = function() local db = GetRBSettings(moduleName); return db and db.bgTexture or "" end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.bgTexture = val; RefreshModule(moduleName) end end,
            },
            spacer2 = { type = "description", name = "", order = 5.9, width = "full" },
            colorMode = {
                type = "select", name = "Color Mode", order = 5.95,
                values = { gradient = "Gradient", threshold = "Per-Stack Threshold" },
                get = function() local db = GetRBSettings(moduleName); return db and db.colorMode or "gradient" end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.colorMode = val; RefreshModule(moduleName) end end,
            },
            gradientStart = {
                type = "color", name = "Gradient Start", order = 6, hasAlpha = true,
                get = function() local db = GetRBSettings(moduleName); local c = db and db.gradientStart or { r = 0.00, g = 0.50, b = 1.00, a = 1 }; return c.r, c.g, c.b, c.a end,
                set = function(_, r, g, b, a) local db = GetRBSettings(moduleName); if db then db.gradientStart = { r = r, g = g, b = b, a = a }; RefreshModule(moduleName) end end,
                hidden = function() local db = GetRBSettings(moduleName); return db and db.colorMode == "threshold" end,
            },
            gradientEnd = {
                type = "color", name = "Gradient End", order = 7, hasAlpha = true,
                get = function() local db = GetRBSettings(moduleName); local c = db and db.gradientEnd or { r = 0.00, g = 0.25, b = 0.60, a = 1 }; return c.r, c.g, c.b, c.a end,
                set = function(_, r, g, b, a) local db = GetRBSettings(moduleName); if db then db.gradientEnd = { r = r, g = g, b = b, a = a }; RefreshModule(moduleName) end end,
                hidden = function() local db = GetRBSettings(moduleName); return db and db.colorMode == "threshold" end,
            },
            thresholdColor1 = {
                type = "color", name = "Low Stacks Color (0-5)", order = 6.1, hasAlpha = true,
                desc = "Color when stacks are below the first threshold.",
                get = function() local db = GetRBSettings(moduleName); local c = db and db.thresholdColor1 or { r = 0.00, g = 0.50, b = 1.00, a = 1 }; return c.r, c.g, c.b, c.a end,
                set = function(_, r, g, b, a) local db = GetRBSettings(moduleName); if db then db.thresholdColor1 = { r = r, g = g, b = b, a = a }; RefreshModule(moduleName) end end,
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.colorMode ~= "threshold" end,
            },
            threshold1 = {
                type = "range", name = "Mid Threshold (stacks >=)", order = 6.2, min = 1, max = 20, step = 1,
                desc = "Stacks at or above this value use the mid color.",
                get = function() local db = GetRBSettings(moduleName); return db and db.threshold1 or 6 end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.threshold1 = val; RefreshModule(moduleName) end end,
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.colorMode ~= "threshold" end,
            },
            thresholdColor2 = {
                type = "color", name = "Mid Stacks Color (6-9)", order = 6.3, hasAlpha = true,
                desc = "Color when stacks are at or above the first threshold but below the second.",
                get = function() local db = GetRBSettings(moduleName); local c = db and db.thresholdColor2 or { r = 1.00, g = 0.80, b = 0.00, a = 1 }; return c.r, c.g, c.b, c.a end,
                set = function(_, r, g, b, a) local db = GetRBSettings(moduleName); if db then db.thresholdColor2 = { r = r, g = g, b = b, a = a }; RefreshModule(moduleName) end end,
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.colorMode ~= "threshold" end,
            },
            threshold2 = {
                type = "range", name = "Max Threshold (stacks >=)", order = 6.4, min = 1, max = 20, step = 1,
                desc = "Stacks at or above this value use the max color.",
                get = function() local db = GetRBSettings(moduleName); return db and db.threshold2 or 10 end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.threshold2 = val; RefreshModule(moduleName) end end,
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.colorMode ~= "threshold" end,
            },
            thresholdColor3 = {
                type = "color", name = "Max Stacks Color (10)", order = 6.5, hasAlpha = true,
                desc = "Color when stacks are at or above the second threshold.",
                get = function() local db = GetRBSettings(moduleName); local c = db and db.thresholdColor3 or { r = 1.00, g = 0.30, b = 0.00, a = 1 }; return c.r, c.g, c.b, c.a end,
                set = function(_, r, g, b, a) local db = GetRBSettings(moduleName); if db then db.thresholdColor3 = { r = r, g = g, b = b, a = a }; RefreshModule(moduleName) end end,
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.colorMode ~= "threshold" end,
            },
            bgColor = {
                type = "color", name = "Background Color", order = 8, hasAlpha = true,
                get = function() local db = GetRBSettings(moduleName); local c = db and db.bgColor or { r = 0.08, g = 0.08, b = 0.08, a = 0.75 }; return c.r, c.g, c.b, c.a end,
                set = function(_, r, g, b, a) local db = GetRBSettings(moduleName); if db then db.bgColor = { r = r, g = g, b = b, a = a }; RefreshModule(moduleName) end end,
            },
            borderSize = {
                type = "range", name = "Border Size", order = 9, min = 0, max = 4, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.borderSize or 1 end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.borderSize = val; RefreshModule(moduleName) end end,
            },
            borderColor = {
                type = "color", name = "Border Color", order = 10, hasAlpha = true,
                get = function() local db = GetRBSettings(moduleName); local c = db and db.borderColor or { r = 0, g = 0, b = 0, a = 1 }; return c.r, c.g, c.b, c.a end,
                set = function(_, r, g, b, a) local db = GetRBSettings(moduleName); if db then db.borderColor = { r = r, g = g, b = b, a = a }; RefreshModule(moduleName) end end,
            },
            spacer3 = { type = "description", name = "", order = 19.5, width = "full" },
            visibilityHeader = { type = "header", name = "Visibility", order = 20 },
            hideWhenMounted = {
                type = "toggle", name = "Hide When Mounted", order = 21,
                get = function() local db = GetRBSettings(moduleName); return db and db.hideWhenMounted end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.hideWhenMounted = val; RefreshModule(moduleName) end end,
            },
            hideOutOfCombat = {
                type = "toggle", name = "Hide Out of Combat", order = 22,
                get = function() local db = GetRBSettings(moduleName); return db and db.hideOutOfCombat end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.hideOutOfCombat = val; RefreshModule(moduleName) end end,
            },
            spacer4 = { type = "description", name = "", order = 29.5, width = "full" },
            positionHeader = { type = "header", name = "Position & Anchor", order = 30 },
            anchorMode = {
                type = "select", name = "Anchor To", order = 30.1,
                values = { free = "Free (Drag)", viewer = "Cooldown Viewer" },
                get = function() local db = GetRBSettings(moduleName); return db and db.anchor or "free" end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.anchor = val; RefreshModule(moduleName) end end,
            },
            anchorStackDesc = {
                type = "description", name = "Bars anchored to the same viewer stack automatically with no gaps. Disabled or hidden bars are skipped.", order = 30.15, width = "full",
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
            },
            anchorTarget = {
                type = "select", name = "Viewer", order = 30.2,
                values = function() return RB and RB.ANCHOR_TARGET_LABELS or { essential = "Essential" } end,
                get = function() local db = GetRBSettings(moduleName); return db and db.anchorTarget or "essential" end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.anchorTarget = val; if RB then RB:HookAnchorResize(val) end; RefreshModule(moduleName) end end,
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
            },
            anchorPosition = {
                type = "select", name = "Position", order = 30.3,
                values = { BELOW = "Below", ABOVE = "Above", LEFT = "Left", RIGHT = "Right" },
                get = function() local db = GetRBSettings(moduleName); return db and db.anchorPosition or "BELOW" end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.anchorPosition = val; RefreshModule(moduleName) end end,
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
            },
            anchorOffset = {
                type = "range", name = "Offset from Viewer", order = 30.4, min = -50, max = 50, step = 1,
                get = function() local db = GetRBSettings(moduleName); return db and db.anchorOffset or 2 end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.anchorOffset = val; RefreshModule(moduleName) end end,
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
            },
            widthMatchAnchor = {
                type = "toggle", name = "Match Anchor Width", order = 30.5,
                get = function() local db = GetRBSettings(moduleName); return db and db.widthMatchAnchor end,
                set = function(_, val) local db = GetRBSettings(moduleName); if db then db.widthMatchAnchor = val; if val and RB then RB:HookAnchorResize(db.anchorTarget or "essential") end; RefreshModule(moduleName) end end,
                hidden = function() local db = GetRBSettings(moduleName); return not db or db.anchor ~= "viewer" end,
            },
            lockBar = {
                type = "toggle", name = "Lock Bar (Drag to Reposition)", order = 31, width = "full",
                get = function() local b = RB and RB.bars[moduleName]; return b and b._locked end,
                set = function(_, val) local b = RB and RB.bars[moduleName]; if b then b._locked = val end end,
                hidden = function() local db = GetRBSettings(moduleName); return db and db.anchor == "viewer" end,
            },
            resetPosition = {
                type = "execute", name = "Reset Position", order = 32,
                func = function() local db = GetRBSettings(moduleName); if db then local d = RB.MODULE_DEFAULTS[moduleName]; if d and d.position then db.position = { point = d.position.point, x = d.position.x, y = d.position.y } else db.position = { point = "CENTER", x = 0, y = -200 } end; RefreshModule(moduleName) end end,
                hidden = function() local db = GetRBSettings(moduleName); return db and db.anchor == "viewer" end,
            },
        },
    }
end

-- ============================================================
-- Main builder - called from AceOptions.lua
-- ============================================================
function CCM.BuildResourceBarsOptions()
    CCM.AceOptionsTable.args.resourceBars = {
        type = "group",
        name = "Resource Bars",
        order = 15,
        childGroups = "tab",
        args = {
            healthBar   = BuildStatusBarOptions("healthBar", "Health Bar", 1, HealthBarExtras()),
            powerBar    = BuildStatusBarOptions("powerBar", "Power Bar", 2, PowerBarExtras()),
            altPowerBar = BuildStatusBarOptions("altPowerBar", "Alt Power Bar", 3, AltPowerBarExtras()),
            classResource = BuildClassResourceTab(),
            ironfurTracker = BuildIronfurTrackerTab(),
            monkOrbTracker = BuildMonkOrbTrackerTab(),
            vengeanceSoulTracker = BuildVengeanceSoulTrackerTab(),
            warriorWhirlwindTracker = BuildWarriorWhirlwindTrackerTab(),
            maelstromTracker = BuildMaelstromTrackerTab(),
        },
    }
end
