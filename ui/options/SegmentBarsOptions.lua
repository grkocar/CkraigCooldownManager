-- ============================================================
-- CkraigCooldownManager :: UI :: Options :: Segment Bars
-- ============================================================
-- AceConfig options table for the Segment Bars module.
-- Replaces CCM_SegmentBars.CreateOptionsPanel.
-- ============================================================

local CCM = _G.CkraigCooldownManager
local AceRegistry = LibStub("AceConfigRegistry-3.0")

local function GetDB()
    if _G.CCM_SegmentBars and _G.CCM_SegmentBars.GetSettings then
        return _G.CCM_SegmentBars:GetSettings()
    end
    return CCM.AceOpts.GetProfileData("segmentBars")
end

local function Refresh()
    if _G.CCM_SegmentBars then
        if _G.CCM_SegmentBars.FullRefresh then _G.CCM_SegmentBars:FullRefresh() end
    end
end

local function GetSpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local name = C_Spell.GetSpellName(id)
        if name then return name end
    end
    return "Spell " .. id
end

local function GetSpellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then
        local tex = C_Spell.GetSpellTexture(id)
        if tex then return tex end
    end
    return 134400
end

-- Shared anchor values for position dropdowns
local ANCHOR_VALUES = {
    LEFT   = "Left",
    RIGHT  = "Right",
    CENTER = "Center",
    TOP    = "Above",
    BOTTOM = "Below",
}

-- ============================================================
-- Build options
-- ============================================================
function CCM.BuildSegmentBarsOptions()
    local opts = CCM.AceOpts

    CCM.AceOptionsTable.args.segmentBars = {
        type = "group",
        name = "Segment Bars",
        order = 80,
        childGroups = "tab",
        args = {
            -- ============================
            -- General / Defaults tab
            -- ============================
            general = {
                type = "group",
                name = "Defaults",
                order = 1,
                args = {
                    enabled = {
                        type = "toggle",
                        name = "Enable Segment Bars",
                        order = 1,
                        width = "full",
                        get = function() local db = GetDB(); return db and db.enabled end,
                        set = function(_, val) local db = GetDB(); if db then db.enabled = val; Refresh() end end,
                    },
                    hideWhenMounted = {
                        type = "toggle",
                        name = "Hide When Mounted (Default)",
                        desc = "Default for all bars. Can be overridden per bar.",
                        order = 2,
                        get = function() local db = GetDB(); return db and db.hideWhenMounted end,
                        set = function(_, val) local db = GetDB(); if db then db.hideWhenMounted = val; Refresh() end end,
                    },
                    locked = {
                        type = "toggle",
                        name = "Lock All Positions",
                        order = 3,
                        get = function() local db = GetDB(); return db and db.locked end,
                        set = function(_, val)
                            local db = GetDB()
                            if db then
                                db.locked = val
                                if _G.CCM_SegmentBars and _G.CCM_SegmentBars.UpdateLocked then
                                    _G.CCM_SegmentBars:UpdateLocked()
                                end
                            end
                        end,
                    },
                    showLabel = {
                        type = "toggle",
                        name = "Show Spell Name (Default)",
                        order = 4,
                        get = function() local db = GetDB(); return db and db.showLabel end,
                        set = function(_, val) local db = GetDB(); if db then db.showLabel = val; Refresh() end end,
                    },
                    showCount = {
                        type = "toggle",
                        name = "Show Count Text (Default)",
                        order = 5,
                        get = function() local db = GetDB(); return db and db.showCount end,
                        set = function(_, val) local db = GetDB(); if db then db.showCount = val; Refresh() end end,
                    },
                    headerSize = {
                        type = "header",
                        name = "Default Size",
                        order = 10,
                    },
                    barWidth = {
                        type = "range",
                        name = "Bar Width",
                        order = 11,
                        min = 40, max = 400, step = 1,
                        get = function() local db = GetDB(); return db and db.barWidth end,
                        set = function(_, val) local db = GetDB(); if db then db.barWidth = val; Refresh() end end,
                    },
                    barHeight = {
                        type = "range",
                        name = "Bar Height",
                        order = 12,
                        min = 6, max = 60, step = 1,
                        get = function() local db = GetDB(); return db and db.barHeight end,
                        set = function(_, val) local db = GetDB(); if db then db.barHeight = val; Refresh() end end,
                    },
                    barSpacing = {
                        type = "range",
                        name = "Bar Spacing",
                        order = 13,
                        min = 0, max = 20, step = 1,
                        get = function() local db = GetDB(); return db and db.barSpacing end,
                        set = function(_, val) local db = GetDB(); if db then db.barSpacing = val; Refresh() end end,
                    },
                    headerTexture = {
                        type = "header",
                        name = "Default Textures & Fonts",
                        order = 20,
                    },
                    fillingTexture = {
                        type = "select",
                        name = "Filling Texture",
                        order = 21,
                        dialogControl = "LSM30_Statusbar",
                        values = function() return opts.GetTextureValues() end,
                        get = function() local db = GetDB(); return db and db.fillingTexture end,
                        set = function(_, val) local db = GetDB(); if db then db.fillingTexture = val; Refresh() end end,
                    },
                    tickTexture = {
                        type = "select",
                        name = "Tick Texture",
                        order = 22,
                        dialogControl = "LSM30_Statusbar",
                        values = function() return opts.GetTextureValues() end,
                        get = function() local db = GetDB(); return db and db.tickTexture end,
                        set = function(_, val) local db = GetDB(); if db then db.tickTexture = val; Refresh() end end,
                    },
                    labelFont = {
                        type = "select",
                        name = "Label Font",
                        order = 23,
                        dialogControl = "LSM30_Font",
                        values = function() return opts.GetFontValues() end,
                        get = function() local db = GetDB(); return db and db.labelFont end,
                        set = function(_, val) local db = GetDB(); if db then db.labelFont = val; Refresh() end end,
                    },
                    labelFontSize = {
                        type = "range",
                        name = "Label Font Size",
                        order = 24,
                        min = 6, max = 24, step = 1,
                        get = function() local db = GetDB(); return db and db.labelFontSize end,
                        set = function(_, val) local db = GetDB(); if db then db.labelFontSize = val; Refresh() end end,
                    },
                    headerColors = {
                        type = "header",
                        name = "Default Colors",
                        order = 30,
                    },
                    tickColor = {
                        type = "color",
                        name = "Tick Color",
                        order = 31,
                        hasAlpha = true,
                        get = function()
                            local db = GetDB()
                            if db and db.tickColor then
                                local c = db.tickColor
                                return c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1
                            end
                            return 0, 0, 0, 1
                        end,
                        set = function(_, r, g, b, a)
                            local db = GetDB()
                            if db then db.tickColor = {r, g, b, a}; Refresh() end
                        end,
                    },
                    bgColor = {
                        type = "color",
                        name = "Background Color",
                        order = 32,
                        hasAlpha = true,
                        get = function()
                            local db = GetDB()
                            if db and db.bgColor then
                                local c = db.bgColor
                                return c[1] or 0.08, c[2] or 0.08, c[3] or 0.08, c[4] or 0.75
                            end
                            return 0.08, 0.08, 0.08, 0.75
                        end,
                        set = function(_, r, g, b, a)
                            local db = GetDB()
                            if db then db.bgColor = {r, g, b, a}; Refresh() end
                        end,
                    },
                    frameStrata = {
                        type = "select",
                        name = "Frame Strata",
                        order = 33,
                        values = opts.FRAME_STRATA_VALUES,
                        get = function() local db = GetDB(); return db and db.frameStrata end,
                        set = function(_, val) local db = GetDB(); if db then db.frameStrata = val; Refresh() end end,
                    },
                },
            },
            -- ============================
            -- Groups tab
            -- ============================
            groups = {
                type = "group",
                name = "Groups",
                order = 1.5,
                args = {
                    desc = {
                        type = "description",
                        name = "Create named groups to stack multiple segment bars together. Bars assigned to a group share a single draggable anchor and optional per-group sizing.",
                        order = 0,
                    },
                    newGroupName = {
                        type = "input",
                        name = "New Group Name",
                        order = 1,
                        width = "double",
                        get = function() return "" end,
                        set = function() end, -- replaced below
                    },
                    -- group_* entries inserted by RebuildGroupArgs
                },
            },
            -- ============================
            -- Spells tab
            -- ============================
            spells = {
                type = "group",
                name = "Spells",
                order = 2,
                childGroups = "tab",
                args = {
                    -- Sub-tab: Add Spells (picker with its own scroll area)
                    addSpellsTab = {
                        type = "group",
                        name = "Add Spells",
                        order = 1,
                        args = {
                            refreshList = {
                                type = "execute",
                                name = "Refresh Spell List from Viewers",
                                desc = "Scan CooldownViewers and populate the picker below",
                                order = 0,
                                func = function() end, -- replaced below
                            },
                            addSelected = {
                                type = "execute",
                                name = "Add Selected Spells",
                                order = 1,
                                width = 0.8,
                                func = function() end, -- replaced below
                            },
                            addSpell = {
                                type = "input",
                                name = "Add Spell ID manually",
                                order = 2,
                                width = "double",
                                set = function(_, val) end, -- replaced below
                                get = function() return "" end,
                            },
                            pickerHeader = {
                                type = "header",
                                name = "Available Spells (select then click Add)",
                                order = 3,
                            },
                            -- pick_* toggles are inserted here by refreshList.func
                        },
                    },
                },
            },
        },
    }

    -- ============================
    -- Groups: rebuild logic
    -- ============================
    local groupsTab = CCM.AceOptionsTable.args.segmentBars.args.groups
    local RebuildSpellArgs -- forward declaration (defined in Spells section below)

    local function RebuildGroupArgs()
        for k in pairs(groupsTab.args) do
            if k:match("^group_") then groupsTab.args[k] = nil end
        end
        local db = GetDB()
        if not db or not db.groups then return end

        local sorted = {}
        for gname in pairs(db.groups) do
            table.insert(sorted, gname)
        end
        table.sort(sorted)

        for idx, gname in ipairs(sorted) do
            groupsTab.args["group_" .. gname] = {
                type = "group",
                name = gname,
                order = 10 + idx,
                inline = true,
                args = {
                    barWidth = {
                        type = "range", name = "Width", order = 1,
                        desc = "Per-group bar width. 0 = use global default.",
                        min = 0, max = 400, step = 1, width = 0.7,
                        get = function()
                            local d = GetDB()
                            local g = d and d.groups and d.groups[gname]
                            return g and g.barWidth or 0
                        end,
                        set = function(_, val)
                            local d = GetDB()
                            if d and d.groups and d.groups[gname] then
                                d.groups[gname].barWidth = val > 0 and val or nil
                                Refresh()
                            end
                        end,
                    },
                    barHeight = {
                        type = "range", name = "Height", order = 2,
                        desc = "Per-group bar height. 0 = use global default.",
                        min = 0, max = 60, step = 1, width = 0.7,
                        get = function()
                            local d = GetDB()
                            local g = d and d.groups and d.groups[gname]
                            return g and g.barHeight or 0
                        end,
                        set = function(_, val)
                            local d = GetDB()
                            if d and d.groups and d.groups[gname] then
                                d.groups[gname].barHeight = val > 0 and val or nil
                                Refresh()
                            end
                        end,
                    },
                    barSpacing = {
                        type = "range", name = "Spacing", order = 3,
                        desc = "Per-group bar spacing. 0 = use global default.",
                        min = 0, max = 20, step = 1, width = 0.7,
                        get = function()
                            local d = GetDB()
                            local g = d and d.groups and d.groups[gname]
                            return g and g.barSpacing or 0
                        end,
                        set = function(_, val)
                            local d = GetDB()
                            if d and d.groups and d.groups[gname] then
                                d.groups[gname].barSpacing = val > 0 and val or nil
                                Refresh()
                            end
                        end,
                    },
                    deleteGroup = {
                        type = "execute", name = "Delete Group", order = 10,
                        width = 0.6, confirm = true,
                        confirmText = "Delete group '" .. gname .. "'? Bars in this group will become standalone.",
                        func = function()
                            local d = GetDB()
                            if d and d.groups then
                                d.groups[gname] = nil
                                -- Unassign bars from deleted group
                                if d.spells then
                                    for _, entry in pairs(d.spells) do
                                        if entry.group == gname then
                                            entry.group = ""
                                        end
                                    end
                                end
                                Refresh()
                                RebuildGroupArgs()
                                RebuildSpellArgs()
                                AceRegistry:NotifyChange("CkraigCooldownManager")
                            end
                        end,
                    },
                },
            }
        end
    end

    -- Wire up new group creation
    groupsTab.args.newGroupName.set = function(_, val)
        if not val or val == "" then return end
        val = val:match("^%s*(.-)%s*$") -- trim whitespace
        if val == "" then return end
        local db = GetDB()
        if not db then return end
        db.groups = db.groups or {}
        if db.groups[val] then return end -- already exists
        db.groups[val] = {
            anchorX = 0,
            anchorY = -180,
        }
        Refresh()
        RebuildGroupArgs()
        RebuildSpellArgs() -- refresh group dropdown in spell entries
        AceRegistry:NotifyChange("CkraigCooldownManager")
    end

    -- ============================
    -- Spells: rebuild logic
    -- ============================
    local spellTab = CCM.AceOptionsTable.args.segmentBars.args.spells
    local pickerTab = spellTab.args.addSpellsTab

    -- Spell-specific helper: get/set with nil-means-inherit
    local function SpellGet(skey, field, default)
        local d = GetDB()
        local e = d and d.spells and d.spells[skey]
        if not e then return default end
        if e[field] ~= nil then return e[field] end
        return default
    end
    local function SpellSet(skey, field, val)
        local d = GetDB()
        if d and d.spells and d.spells[skey] then
            d.spells[skey][field] = val; Refresh()
        end
    end
    local function SpellColorGet(skey, field, dr, dg, db_, da)
        local d = GetDB()
        local e = d and d.spells and d.spells[skey]
        local c = e and e[field]
        if c then return c[1] or dr, c[2] or dg, c[3] or db_, c[4] or da end
        return dr, dg, db_, da
    end

    RebuildSpellArgs = function()
        for k in pairs(spellTab.args) do
            if k:match("^spell_") then spellTab.args[k] = nil end
        end
        local db = GetDB()
        if not db or not db.spells then return end

        local sorted = {}
        for key, entry in pairs(db.spells) do
            if type(entry) == "table" then
                table.insert(sorted, key)
            end
        end
        table.sort(sorted, function(a, b)
            local na, nb = tonumber(a), tonumber(b)
            if na and nb then return na < nb end
            return tostring(a) < tostring(b)
        end)

        -- Collect known group names for dropdown
        local groupValues = { [""] = "(Standalone)" }
        if db.groups then
            for gname in pairs(db.groups) do
                groupValues[gname] = gname
            end
        end

        for idx, skey in ipairs(sorted) do
            local id = tonumber(skey)
            local spellName = id and GetSpellName(id) or ("Spell " .. skey)
            local spellIcon = id and GetSpellIcon(id) or nil

            spellTab.args["spell_" .. skey] = {
                type = "group",
                name = function()
                    return "|T" .. (spellIcon or 134400) .. ":16:16:0:0|t  " .. spellName
                end,
                order = 100 + idx,
                args = {
                    -- Header row with icon + name
                    icon = {
                        type = "description",
                        name = spellName .. "  (ID: " .. skey .. ")",
                        order = 1,
                        image = function() return spellIcon or "Interface\\ICONS\\INV_Misc_QuestionMark" end,
                        imageWidth = 24,
                        imageHeight = 24,
                        width = "full",
                    },
                    -- ---- Core ----
                    coreHeader = { type = "header", name = "Core", order = 5 },
                    trackMode = {
                        type = "select", name = "Tracking Mode", order = 5.5,
                        desc = "Auto = try all sources. Charges = spell charges only. Buff = aura stacks only. Spell Count = GetSpellCastCount (e.g. Soul Fragments).",
                        values = { auto = "Auto (try all)", charges = "Charges", buff = "Buff Stacks", spellcount = "Spell Count" },
                        width = 0.8,
                        get = function() return SpellGet(skey, "trackMode", "auto") end,
                        set = function(_, val) SpellSet(skey, "trackMode", val) end,
                    },
                    maxSegments = {
                        type = "range", name = "Max Segments", order = 6,
                        min = 1, max = 100, step = 1, width = 0.7,
                        get = function() return SpellGet(skey, "maxSegments", 3) end,
                        set = function(_, val) SpellSet(skey, "maxSegments", val) end,
                    },
                    gradientStart = {
                        type = "color", name = "Gradient Start", order = 7,
                        hasAlpha = true, width = 0.5,
                        get = function() return SpellColorGet(skey, "gradientStart", 0.2, 0.8, 1, 1) end,
                        set = function(_, r, g, b, a) SpellSet(skey, "gradientStart", {r, g, b, a}) end,
                    },
                    gradientEnd = {
                        type = "color", name = "Gradient End", order = 8,
                        hasAlpha = true, width = 0.5,
                        get = function() return SpellColorGet(skey, "gradientEnd", 0, 0.4, 0.8, 1) end,
                        set = function(_, r, g, b, a) SpellSet(skey, "gradientEnd", {r, g, b, a}) end,
                    },
                    group = {
                        type = "select", name = "Group", order = 9,
                        values = groupValues, width = 0.7,
                        get = function() return SpellGet(skey, "group", "") end,
                        set = function(_, val) SpellSet(skey, "group", val) end,
                    },
                    newGroup = {
                        type = "input", name = "Or Create New Group", order = 9.5,
                        desc = "Type a name and press Enter to create a new group and assign this spell to it.",
                        width = 0.8,
                        get = function() return "" end,
                        set = function(_, val)
                            if not val or val == "" then return end
                            val = val:match("^%s*(.-)%s*$")
                            if val == "" then return end
                            local d = GetDB()
                            if not d then return end
                            d.groups = d.groups or {}
                            if not d.groups[val] then
                                d.groups[val] = { anchorX = 0, anchorY = -180 }
                            end
                            SpellSet(skey, "group", val)
                            RebuildGroupArgs()
                            RebuildSpellArgs()
                            AceRegistry:NotifyChange("CkraigCooldownManager")
                        end,
                    },
                    remove = {
                        type = "execute", name = "Remove", order = 10,
                        width = 0.5, confirm = true,
                        func = function()
                            local d = GetDB()
                            if d and d.spells then
                                d.spells[skey] = nil
                                if _G.CCM_SegmentBars and _G.CCM_SegmentBars.RemoveSpell then
                                    _G.CCM_SegmentBars:RemoveSpell(tonumber(skey))
                                end
                                RebuildSpellArgs()
                                AceRegistry:NotifyChange("CkraigCooldownManager")
                            end
                        end,
                    },
                    -- ---- Size & Appearance ----
                    sizeHeader = { type = "header", name = "Size & Appearance (per-bar)", order = 20 },
                    barWidth = {
                        type = "range", name = "Width", order = 21,
                        desc = "Per-bar width. Set to 0 to use default.",
                        min = 0, max = 400, step = 1, width = 0.7,
                        get = function() return SpellGet(skey, "barWidth", 0) or 0 end,
                        set = function(_, val) SpellSet(skey, "barWidth", val > 0 and val or nil) end,
                    },
                    barHeight = {
                        type = "range", name = "Height", order = 22,
                        desc = "Per-bar height. Set to 0 to use default.",
                        min = 0, max = 60, step = 1, width = 0.7,
                        get = function() return SpellGet(skey, "barHeight", 0) or 0 end,
                        set = function(_, val) SpellSet(skey, "barHeight", val > 0 and val or nil) end,
                    },
                    fillingTexture = {
                        type = "select", name = "Filling Texture", order = 23,
                        desc = "Per-bar texture. Leave empty to inherit default.",
                        dialogControl = "LSM30_Statusbar",
                        values = function()
                            local v = {}
                            for tk, tv in pairs(opts.GetTextureValues()) do v[tk] = tv end
                            v[""] = "(Use Default)"
                            return v
                        end,
                        get = function() return SpellGet(skey, "fillingTexture", "") or "" end,
                        set = function(_, val) SpellSet(skey, "fillingTexture", val ~= "" and val or nil) end,
                    },
                    frameStrata = {
                        type = "select", name = "Frame Strata", order = 24,
                        values = function()
                            local v = {}
                            for k2, v2 in pairs(opts.FRAME_STRATA_VALUES) do v[k2] = v2 end
                            v[""] = "(Use Default)"
                            return v
                        end,
                        get = function() return SpellGet(skey, "frameStrata", "") or "" end,
                        set = function(_, val) SpellSet(skey, "frameStrata", val ~= "" and val or nil) end,
                    },
                    -- ---- Display Toggles ----
                    toggleHeader = { type = "header", name = "Display Toggles", order = 30 },
                    hideWhenMounted = {
                        type = "toggle", name = "Hide When Mounted", order = 31,
                        tristate = true,
                        desc = "Nil (grey) = use default, checked = always hide, unchecked = always show",
                        get = function()
                            local v = SpellGet(skey, "hideWhenMounted", nil)
                            if v == nil then return nil end
                            return v
                        end,
                        set = function(_, val) SpellSet(skey, "hideWhenMounted", val) end,
                    },
                    showLabel = {
                        type = "toggle", name = "Show Spell Name", order = 33,
                        tristate = true,
                        get = function()
                            local v = SpellGet(skey, "showLabel", nil)
                            if v == nil then return nil end
                            return v
                        end,
                        set = function(_, val) SpellSet(skey, "showLabel", val) end,
                    },
                    -- ---- Spell Name Label ----
                    labelHeader = { type = "header", name = "Spell Name Label", order = 40 },
                    labelFont = {
                        type = "select", name = "Font", order = 41,
                        dialogControl = "LSM30_Font",
                        values = function() return opts.GetFontValues() end,
                        get = function() return SpellGet(skey, "labelFont", "") or "" end,
                        set = function(_, val) SpellSet(skey, "labelFont", val ~= "" and val or nil) end,
                    },
                    labelFontSize = {
                        type = "range", name = "Font Size", order = 42,
                        min = 0, max = 24, step = 1, width = 0.6,
                        desc = "0 = use default",
                        get = function() return SpellGet(skey, "labelFontSize", 0) or 0 end,
                        set = function(_, val) SpellSet(skey, "labelFontSize", val > 0 and val or nil) end,
                    },
                    labelAnchor = {
                        type = "select", name = "Position", order = 43,
                        values = ANCHOR_VALUES, width = 0.5,
                        get = function() return SpellGet(skey, "labelAnchor", "LEFT") end,
                        set = function(_, val) SpellSet(skey, "labelAnchor", val) end,
                    },
                    labelOffsetX = {
                        type = "range", name = "X Offset", order = 44,
                        min = -200, max = 200, step = 1, width = 0.5,
                        get = function() return SpellGet(skey, "labelOffsetX", 4) end,
                        set = function(_, val) SpellSet(skey, "labelOffsetX", val) end,
                    },
                    labelOffsetY = {
                        type = "range", name = "Y Offset", order = 45,
                        min = -200, max = 200, step = 1, width = 0.5,
                        get = function() return SpellGet(skey, "labelOffsetY", 0) end,
                        set = function(_, val) SpellSet(skey, "labelOffsetY", val) end,
                    },
                    -- ---- Count Text ----
                    countHeader = { type = "header", name = "Count Text", order = 50 },
                    showCount = {
                        type = "toggle", name = "Show Count", order = 51,
                        tristate = true,
                        get = function()
                            local v = SpellGet(skey, "showCount", nil)
                            if v == nil then return nil end
                            return v
                        end,
                        set = function(_, val) SpellSet(skey, "showCount", val) end,
                    },
                    countFont = {
                        type = "select", name = "Font", order = 52,
                        dialogControl = "LSM30_Font",
                        values = function() return opts.GetFontValues() end,
                        get = function() return SpellGet(skey, "countFont", "") or "" end,
                        set = function(_, val) SpellSet(skey, "countFont", val ~= "" and val or nil) end,
                    },
                    countFontSize = {
                        type = "range", name = "Font Size", order = 53,
                        min = 0, max = 24, step = 1, width = 0.6,
                        desc = "0 = use default",
                        get = function() return SpellGet(skey, "countFontSize", 0) or 0 end,
                        set = function(_, val) SpellSet(skey, "countFontSize", val > 0 and val or nil) end,
                    },
                    countAnchor = {
                        type = "select", name = "Position", order = 54,
                        values = ANCHOR_VALUES, width = 0.5,
                        get = function() return SpellGet(skey, "countAnchor", "RIGHT") end,
                        set = function(_, val) SpellSet(skey, "countAnchor", val) end,
                    },
                    countOffsetX = {
                        type = "range", name = "X Offset", order = 55,
                        min = -200, max = 200, step = 1, width = 0.5,
                        get = function() return SpellGet(skey, "countOffsetX", -4) end,
                        set = function(_, val) SpellSet(skey, "countOffsetX", val) end,
                    },
                    countOffsetY = {
                        type = "range", name = "Y Offset", order = 56,
                        min = -200, max = 200, step = 1, width = 0.5,
                        get = function() return SpellGet(skey, "countOffsetY", 0) end,
                        set = function(_, val) SpellSet(skey, "countOffsetY", val) end,
                    },
                    -- ---- Spell Icon ----
                    iconHeader = { type = "header", name = "Spell Icon on Bar", order = 70 },
                    showIcon = {
                        type = "toggle", name = "Show Icon", order = 71,
                        get = function() return SpellGet(skey, "showIcon", false) end,
                        set = function(_, val) SpellSet(skey, "showIcon", val) end,
                    },
                    iconSize = {
                        type = "range", name = "Icon Size", order = 72,
                        desc = "0 = match bar height",
                        min = 0, max = 64, step = 1, width = 0.6,
                        get = function() return SpellGet(skey, "iconSize", 0) or 0 end,
                        set = function(_, val) SpellSet(skey, "iconSize", val > 0 and val or nil) end,
                    },
                    iconAnchor = {
                        type = "select", name = "Icon Side", order = 73,
                        values = { LEFT = "Left of bar", RIGHT = "Right of bar" },
                        get = function() return SpellGet(skey, "iconAnchor", "LEFT") end,
                        set = function(_, val) SpellSet(skey, "iconAnchor", val) end,
                    },
                },
            }
        end
    end

    -- ============================
    -- Scanned spell picker (toggle-based with icons)
    -- ============================
    local _pendingSelected = {}
    local _scannedSpells = {}

    pickerTab.args.refreshList.func = function()
        wipe(_pendingSelected)
        wipe(_scannedSpells)
        -- Remove old picker entries
        for k in pairs(pickerTab.args) do
            if k:match("^pick_") then pickerTab.args[k] = nil end
        end

        local db = GetDB()
        if not db then return end
        db.spells = db.spells or {}

        local seen = {}

        -- Primary: ScanCDMCatalog (viewer frames)
        if _G.CCM_SegmentBars and _G.CCM_SegmentBars.ScanCDMCatalog then
            local catalog = _G.CCM_SegmentBars:ScanCDMCatalog()
            if type(catalog) == "table" then
                for _, item in ipairs(catalog) do
                    local skey = tostring(item.spellID or item.cooldownID)
                    if skey and skey ~= "" and not seen[skey] and not db.spells[skey] then
                        seen[skey] = true
                        table.insert(_scannedSpells, {
                            key = skey,
                            name = item.name or GetSpellName(tonumber(skey)),
                            icon = item.icon or GetSpellIcon(tonumber(skey)),
                        })
                    end
                end
            end
        end

        -- Fallback: exported spell list APIs
        local function AddFromList(items)
            if not items then return end
            for _, item in ipairs(items) do
                local skey = tostring(item.key or item.spellID or "")
                if skey ~= "" and not seen[skey] and not db.spells[skey] then
                    seen[skey] = true
                    local sid = tonumber(skey)
                    table.insert(_scannedSpells, {
                        key = skey,
                        name = sid and GetSpellName(sid) or ("Spell " .. skey),
                        icon = sid and GetSpellIcon(sid) or 134400,
                    })
                end
            end
        end
        AddFromList(_G.CCM_GetEssentialSpellList and _G.CCM_GetEssentialSpellList())
        AddFromList(_G.CCM_GetUtilitySpellList and _G.CCM_GetUtilitySpellList())
        AddFromList(_G.CCM_GetDynamicIconsSpellList and _G.CCM_GetDynamicIconsSpellList())

        -- Sort by name
        table.sort(_scannedSpells, function(a, b) return (a.name or "") < (b.name or "") end)

        -- Build toggle entries with spell icons
        for i, item in ipairs(_scannedSpells) do
            local sid = tonumber(item.key) or 0
            pickerTab.args["pick_" .. item.key] = {
                type = "toggle",
                name = function()
                    local iconTex = item.icon or GetSpellIcon(sid)
                    return "|T" .. iconTex .. ":16:16:0:0|t  " .. (item.name or "?") .. "  |cff888888(ID: " .. item.key .. ")|r"
                end,
                order = 10 + i,
                width = "full",
                get = function() return _pendingSelected[sid] == true end,
                set = function(_, val) _pendingSelected[sid] = val end,
            }
        end

        AceRegistry:NotifyChange("CkraigCooldownManager")
    end

    -- Add Selected button
    pickerTab.args.addSelected.func = function()
        local anyAdded = false
        for sid, selected in pairs(_pendingSelected) do
            if selected and sid > 0 then
                if _G.CCM_SegmentBars and _G.CCM_SegmentBars.AddSpell then
                    _G.CCM_SegmentBars:AddSpell(sid)
                else
                    local db = GetDB()
                    if db then
                        db.spells = db.spells or {}
                        local skey = tostring(sid)
                        if not db.spells[skey] then
                            db.spells[skey] = {
                                maxSegments = 3,
                                gradientStart = { 0.20, 0.80, 1.00, 1 },
                                gradientEnd = { 0.00, 0.40, 0.80, 1 },
                                order = 0,
                                group = "",
                            }
                        end
                    end
                end
                anyAdded = true
                pickerTab.args["pick_" .. tostring(sid)] = nil
            end
        end
        wipe(_pendingSelected)
        if anyAdded then
            Refresh()
            RebuildSpellArgs()
            AceRegistry:NotifyChange("CkraigCooldownManager")
        end
    end

    -- Manual add spell by ID
    pickerTab.args.addSpell.set = function(_, val)
        local id = tonumber(val)
        if not id or id <= 0 then return end
        if _G.CCM_SegmentBars and _G.CCM_SegmentBars.AddSpell then
            _G.CCM_SegmentBars:AddSpell(id)
        else
            local db = GetDB()
            if db then
                db.spells = db.spells or {}
                local skey = tostring(id)
                if not db.spells[skey] then
                    db.spells[skey] = {
                        maxSegments = 3,
                        gradientStart = { 0.20, 0.80, 1.00, 1 },
                        gradientEnd = { 0.00, 0.40, 0.80, 1 },
                        order = 0,
                        group = "",
                    }
                end
            end
        end
        Refresh()
        RebuildSpellArgs()
        AceRegistry:NotifyChange("CkraigCooldownManager")
    end

    RebuildGroupArgs()
    RebuildSpellArgs()
end