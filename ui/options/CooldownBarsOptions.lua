-- ============================================================
-- CkraigCooldownManager :: UI :: Options :: Cooldown Bars
-- ============================================================
-- AceConfig options table for the Cooldown Bars module.
-- Replaces the hand-built CreateCkraigBarOptionsPanel.
-- ============================================================

local CCM = _G.CkraigCooldownManager
local AceRegistry = LibStub("AceConfigRegistry-3.0")
local LSM = LibStub("LibSharedMedia-3.0", true)
local bbSoundKeyCache = nil
local bbSoundSearchText = ""
local bbSoundLsmCallbackRegistered = false
local bbSoundShowAll = true
local bbSoundPage = 1
local bbSoundPageSize = 150

local function TrimString_BB_Opts(s)
    if type(s) ~= "string" then return "" end
    return s:match("^%s*(.-)%s*$") or ""
end

local function BuildSoundKeyCache_BB_Opts()
    if bbSoundKeyCache then return bbSoundKeyCache end
    local keys = {}
    if LSM and LSM.HashTable then
        local tbl = LSM:HashTable("sound")
        if type(tbl) == "table" then
            for key in pairs(tbl) do
                keys[#keys + 1] = tostring(key)
            end
        end
    end
    table.sort(keys, function(a, b)
        return a:lower() < b:lower()
    end)
    bbSoundKeyCache = keys
    return bbSoundKeyCache
end

local function GetFilteredSoundValues_BB_Opts(currentValue)
    local values = {}
    local keys = BuildSoundKeyCache_BB_Opts()
    local query = TrimString_BB_Opts(bbSoundSearchText):lower()
    local hasSearch = (query ~= "")

    if hasSearch then
        for _, key in ipairs(keys) do
            if key:lower():find(query, 1, true) then
                values[key] = key
            end
        end
    elseif bbSoundShowAll then
        local totalKeys = #keys
        local totalPages = math.max(1, math.ceil(totalKeys / bbSoundPageSize))
        if bbSoundPage > totalPages then bbSoundPage = totalPages end
        if bbSoundPage < 1 then bbSoundPage = 1 end
        local startIdx = (bbSoundPage - 1) * bbSoundPageSize + 1
        local endIdx = math.min(startIdx + bbSoundPageSize - 1, totalKeys)
        for i = startIdx, endIdx do
            local key = keys[i]
            if key then values[key] = key end
        end
    else
        local count = 0
        for _, key in ipairs(keys) do
            values[key] = key
            count = count + 1
            if count >= 80 then break end
        end
    end

    if currentValue and currentValue ~= "" and not values[currentValue] then
        values[currentValue] = currentValue .. " (selected)"
    end

    return values
end

local function RegisterSoundMediaCallback_BB_Opts()
    if bbSoundLsmCallbackRegistered or not (LSM and LSM.RegisterCallback) then
        return
    end
    bbSoundLsmCallbackRegistered = true
    LSM:RegisterCallback("LibSharedMedia_Registered", function(_, mediaType)
        if mediaType == "sound" then
            bbSoundKeyCache = nil
            AceRegistry:NotifyChange("CkraigCooldownManager")
        end
    end)
end

-- The CooldownBars AceAddon is created via NewAddon in BarCore.lua,
-- which is a DIFFERENT object from _G.CkraigCooldownManager (the shared
-- addon namespace).  We must use GetAddon to reach the real AceAddon
-- that owns .db and :RepositionAllBars().
local function GetBarAddon()
    return LibStub("AceAddon-3.0"):GetAddon("CkraigCooldownManager", true)
end

local function TouchSpellSoundConfig_BB_Opts(db)
    db = db or GetDB()
    if not db then return end
    db.spellSoundsRevision = (tonumber(db.spellSoundsRevision) or 0) + 1
end

local function Refresh()
    local addon = GetBarAddon()
    if addon then
        local internals = addon._barInternals
        if internals and internals.InvalidateBarStyle then
            internals.InvalidateBarStyle()
        end
        if addon.RepositionAllBars then
            addon:RepositionAllBars()
        end
    end
end

local function ToggleCooldownSettingsPanel()
    if DYNAMICICONS and DYNAMICICONS.EnsureCooldownSettingsHooks then
        DYNAMICICONS:EnsureCooldownSettingsHooks()
    end
    local settingsFrame = _G.CooldownViewerSettings
    if not settingsFrame and UIParentLoadAddOn then
        pcall(UIParentLoadAddOn, "Blizzard_CooldownViewer")
        settingsFrame = _G.CooldownViewerSettings
    end
    if settingsFrame and settingsFrame.TogglePanel then
        settingsFrame:TogglePanel()
    end
end

local function GetDB()
    local addon = GetBarAddon()
    if addon and addon.db and addon.db.profile and addon.db.profile.buffBars then
        return addon.db.profile.buffBars
    end
    local opts = CCM.AceOpts
    return opts.GetProfileData("buffBars")
end

function CCM.BuildCooldownBarsOptions()
    local opts = CCM.AceOpts
    local MAX_BAR_CLUSTERS = 10
    local RebuildColorArgs

    RegisterSoundMediaCallback_BB_Opts()

    CCM.AceOptionsTable.args.cooldownBars = {
        type = "group",
        name = "Cooldown Bars",
        order = 10,
        childGroups = "tab",
        args = {
            -- ============================
            -- General tab
            -- ============================
            general = {
                type = "group",
                name = "General",
                order = 1,
                args = {
                    previewViewer = {
                        type = "execute",
                        name = "Toggle Blizzard Cooldown Settings",
                        desc = "Opens the real Blizzard Cooldown Settings window. While it is open, Dynamic Icon cluster samples also stay visible in their desaturated preview state.",
                        order = 0,
                        width = "full",
                        func = function()
                            ToggleCooldownSettingsPanel()
                        end,
                    },
                    gridMode = {
                        type = "toggle",
                        name = "Enable Grid Mode",
                        order = 1,
                        get = function() local db = GetDB(); return db and db.gridMode end,
                        set = function(_, val) local db = GetDB(); if db then db.gridMode = val; Refresh() end end,
                    },
                    gridCols = {
                        type = "input",
                        name = "Grid Columns",
                        order = 2,
                        width = "half",
                        get = function() local db = GetDB(); return db and tostring(db.gridCols or 4) end,
                        set = function(_, val) local db = GetDB(); if db then db.gridCols = tonumber(val) or 4; Refresh() end end,
                    },
                    gridRows = {
                        type = "input",
                        name = "Grid Rows",
                        order = 3,
                        width = "half",
                        get = function() local db = GetDB(); return db and tostring(db.gridRows or 4) end,
                        set = function(_, val) local db = GetDB(); if db then db.gridRows = tonumber(val) or 4; Refresh() end end,
                    },
                    barTexture = {
                        type = "select",
                        name = "Bar Texture",
                        order = 10,
                        dialogControl = "LSM30_Statusbar",
                        values = function() return opts.GetTextureValues() end,
                        get = function() local db = GetDB(); return db and db.texture end,
                        set = function(_, val) local db = GetDB(); if db then db.texture = val; Refresh() end end,
                    },
                    barFont = {
                        type = "select",
                        name = "Bar Text Font",
                        order = 11,
                        dialogControl = "LSM30_Font",
                        values = function() return opts.GetFontValues() end,
                        get = function() local db = GetDB(); return db and db.font end,
                        set = function(_, val) local db = GetDB(); if db then db.font = val; Refresh() end end,
                    },
                    timerTextAlign = {
                        type = "select",
                        name = "Timer Text Alignment",
                        order = 12,
                        values = opts.TIMER_ALIGN_VALUES,
                        get = function() local db = GetDB(); return db and db.timerTextAlign end,
                        set = function(_, val) local db = GetDB(); if db then db.timerTextAlign = val; Refresh() end end,
                    },
                    headerSize = {
                        type = "header",
                        name = "Size & Spacing",
                        order = 20,
                    },
                    barHeight = {
                        type = "range",
                        name = "Bar Height",
                        order = 21,
                        min = 10, max = 54, step = 1,
                        get = function() local db = GetDB(); return db and db.barHeight end,
                        set = function(_, val)
                            local db = GetDB()
                            if db then
                                db.barHeight = val
                                db.iconHeight = val
                                db.iconWidth = val
                                Refresh()
                            end
                        end,
                    },
                    barWidth = {
                        type = "range",
                        name = "Bar Width",
                        order = 22,
                        min = 50, max = 400, step = 1,
                        get = function() local db = GetDB(); return db and db.barWidth end,
                        set = function(_, val) local db = GetDB(); if db then db.barWidth = val; Refresh() end end,
                    },
                    barSpacing = {
                        type = "range",
                        name = "Bar Spacing",
                        order = 23,
                        min = 0, max = 9, step = 1,
                        get = function() local db = GetDB(); return db and db.barSpacing end,
                        set = function(_, val) local db = GetDB(); if db then db.barSpacing = val; Refresh() end end,
                    },
                    regularGrowDirection = {
                        type = "select",
                        name = "Regular Mode Grow Direction",
                        desc = "Controls whether bars stack upward or downward when Cluster Mode is off.",
                        order = 24,
                        values = {
                            up = "Grow Up",
                            down = "Grow Down",
                        },
                        hidden = function()
                            local db = GetDB()
                            return db and db.clusterMode
                        end,
                        get = function()
                            local db = GetDB()
                            return db and db.regularGrowDirection or "up"
                        end,
                        set = function(_, val)
                            local db = GetDB()
                            if db then
                                db.regularGrowDirection = val
                                Refresh()
                            end
                        end,
                    },
                    headerFonts = {
                        type = "header",
                        name = "Font Sizes",
                        order = 30,
                    },
                    barTextFontSize = {
                        type = "range",
                        name = "Bar Text Font Size",
                        order = 31,
                        min = 6, max = 36, step = 1,
                        get = function() local db = GetDB(); return db and db.barTextFontSize end,
                        set = function(_, val) local db = GetDB(); if db then db.barTextFontSize = val; Refresh() end end,
                    },
                    timerTextFontSize = {
                        type = "range",
                        name = "Timer Text Font Size",
                        order = 32,
                        min = 6, max = 36, step = 1,
                        get = function() local db = GetDB(); return db and db.timerTextFontSize end,
                        set = function(_, val) local db = GetDB(); if db then db.timerTextFontSize = val; Refresh() end end,
                    },
                    stackFontSize = {
                        type = "range",
                        name = "Stack/Application Font Size",
                        order = 33,
                        min = 6, max = 120, step = 1,
                        get = function() local db = GetDB(); return db and db.stackFontSize end,
                        set = function(_, val) local db = GetDB(); if db then db.stackFontSize = val; Refresh() end end,
                    },
                    stackFontOffsetX = {
                        type = "range",
                        name = "Stack Number X Offset",
                        order = 34,
                        min = -300, max = 300, step = 1,
                        get = function() local db = GetDB(); return db and db.stackFontOffsetX end,
                        set = function(_, val) local db = GetDB(); if db then db.stackFontOffsetX = val; Refresh() end end,
                    },
                    stackFontOffsetY = {
                        type = "range",
                        name = "Stack Number Y Offset",
                        order = 35,
                        min = -300, max = 300, step = 1,
                        get = function() local db = GetDB(); return db and db.stackFontOffsetY end,
                        set = function(_, val) local db = GetDB(); if db then db.stackFontOffsetY = val; Refresh() end end,
                    },
                    headerDisplay = {
                        type = "header",
                        name = "Display",
                        order = 40,
                    },
                    useClassColor = {
                        type = "toggle",
                        name = "Use Class Color for Bars",
                        order = 41,
                        get = function() local db = GetDB(); return db and db.useClassColor end,
                        set = function(_, val) local db = GetDB(); if db then db.useClassColor = val; Refresh() end end,
                    },
                    hideIcons = {
                        type = "toggle",
                        name = "Hide Icons",
                        order = 42,
                        get = function() local db = GetDB(); return db and db.hideIcons end,
                        set = function(_, val) local db = GetDB(); if db then db.hideIcons = val; Refresh() end end,
                    },
                    hideBarName = {
                        type = "toggle",
                        name = "Hide Bar Name",
                        order = 43,
                        get = function() local db = GetDB(); return db and db.hideBarName end,
                        set = function(_, val) local db = GetDB(); if db then db.hideBarName = val; Refresh() end end,
                    },
                    aspectRatio = {
                        type = "range",
                        name = "Icon Aspect Ratio",
                        order = 44,
                        min = 0.5, max = 2.0, step = 0.01,
                        get = function()
                            local db = GetDB()
                            if not db or not db.aspectRatio then return 1.0 end
                            if type(db.aspectRatio) == "string" then
                                local w, h = db.aspectRatio:match("(%d+):(%d+)")
                                if w and h and tonumber(h) > 0 then return tonumber(w)/tonumber(h) end
                                return 1.0
                            end
                            return db.aspectRatio
                        end,
                        set = function(_, val)
                            local db = GetDB()
                            if db then db.aspectRatio = string.format("%.2f:1", val); Refresh() end
                        end,
                    },
                    cornerRadius = {
                        type = "range",
                        name = "Icon Corner Radius",
                        order = 45,
                        min = 0, max = 20, step = 1,
                        get = function() local db = GetDB(); return db and db.cornerRadius end,
                        set = function(_, val) local db = GetDB(); if db then db.cornerRadius = val; Refresh() end end,
                    },
                },
            },
            -- ============================
            -- Cluster tab
            -- ============================
            clusters = {
                type = "group",
                name = "Clusters",
                order = 2,
                args = {
                    clusterMode = {
                        type = "toggle",
                        name = "Enable Cluster Mode",
                        order = 1,
                        width = "full",
                        get = function() local db = GetDB(); return db and db.clusterMode end,
                        set = function(_, val) local db = GetDB(); if db then db.clusterMode = val; Refresh() end end,
                    },
                    clusterUnlocked = {
                        type = "toggle",
                        name = "Unlock Cluster Boxes",
                        order = 2,
                        get = function() local db = GetDB(); return db and db.clusterUnlocked end,
                        set = function(_, val) local db = GetDB(); if db then db.clusterUnlocked = val; Refresh() end end,
                    },
                    clusterCount = {
                        type = "range",
                        name = "Number of Clusters",
                        order = 3,
                        min = 1, max = MAX_BAR_CLUSTERS, step = 1,
                        get = function() local db = GetDB(); return db and db.clusterCount or 1 end,
                        set = function(_, val) local db = GetDB(); if db then db.clusterCount = val; Refresh() end end,
                    },
                    -- Per-cluster settings are generated dynamically below
                },
            },
            -- ============================
            -- Spell Colors tab
            -- ============================
            spellColors = {
                type = "group",
                name = "Spell Colors",
                order = 3,
                args = {
                    desc = {
                        type = "description",
                        name = "Assign custom bar colors per spell. Use 'Refresh List' to scan active cooldown bars.",
                        order = 1,
                    },
                    refreshList = {
                        type = "execute",
                        name = "Refresh List",
                        order = 2,
                        func = function() end, -- replaced below
                    },
                    addSpell = {
                        type = "input",
                        name = "Add Spell ID",
                        order = 3,
                        width = "double",
                        set = function(_, val) end, -- replaced below
                        get = function() return "" end,
                    },
                },
            },
            -- ============================
            -- Spell Glows tab
            -- ============================
            spellGlows = {
                type = "group",
                name = "Spell Glows",
                order = 4,
                args = {
                    refreshGlowList = {
                        type = "execute",
                        name = "Refresh Glow List",
                        desc = "Scan active cooldown bars and add them to the glow list",
                        order = 0,
                        func = function() end, -- replaced below
                    },
                    addGlow = {
                        type = "input",
                        name = "Add Spell ID for Glow",
                        order = 1,
                        width = "double",
                        set = function(_, val) end, -- replaced below
                        get = function() return "" end,
                    },
                },
            },
            spellSounds = {
                type = "group",
                name = "Spell Sounds",
                order = 5,
                args = {
                    bbSoundShowAllToggle = {
                        type = "toggle",
                        name = "Show Full Sound List",
                        desc = "Toggle between a quick list (first 80 sounds) and the full paginated SharedMedia list.",
                        order = -3,
                        width = 1.0,
                        get = function() return bbSoundShowAll end,
                        set = function(_, val)
                            bbSoundShowAll = val and true or false
                            bbSoundPage = 1
                            AceRegistry:NotifyChange("CkraigCooldownManager")
                        end,
                    },
                    bbSoundPrevPage = {
                        type = "execute",
                        name = "< Prev Page",
                        order = -2.5,
                        width = 0.5,
                        hidden = function() return not bbSoundShowAll or TrimString_BB_Opts(bbSoundSearchText) ~= "" end,
                        disabled = function() return bbSoundPage <= 1 end,
                        func = function()
                            bbSoundPage = math.max(1, bbSoundPage - 1)
                            AceRegistry:NotifyChange("CkraigCooldownManager")
                        end,
                    },
                    bbSoundPageInfo = {
                        type = "description",
                        name = function()
                            local totalKeys = #(BuildSoundKeyCache_BB_Opts())
                            local totalPages = math.max(1, math.ceil(totalKeys / bbSoundPageSize))
                            return "  Page " .. bbSoundPage .. " / " .. totalPages .. "  (" .. totalKeys .. " sounds)  "
                        end,
                        order = -2.4,
                        width = 1.0,
                        hidden = function() return not bbSoundShowAll or TrimString_BB_Opts(bbSoundSearchText) ~= "" end,
                    },
                    bbSoundNextPage = {
                        type = "execute",
                        name = "Next Page >",
                        order = -2.3,
                        width = 0.5,
                        hidden = function() return not bbSoundShowAll or TrimString_BB_Opts(bbSoundSearchText) ~= "" end,
                        disabled = function()
                            local totalKeys = #(BuildSoundKeyCache_BB_Opts())
                            local totalPages = math.max(1, math.ceil(totalKeys / bbSoundPageSize))
                            return bbSoundPage >= totalPages
                        end,
                        func = function()
                            local totalKeys = #(BuildSoundKeyCache_BB_Opts())
                            local totalPages = math.max(1, math.ceil(totalKeys / bbSoundPageSize))
                            bbSoundPage = math.min(totalPages, bbSoundPage + 1)
                            AceRegistry:NotifyChange("CkraigCooldownManager")
                        end,
                    },
                    soundSearch = {
                        type = "input",
                        name = "Search SharedMedia Sounds",
                        desc = "Type part of a sound name to filter the dropdown and reduce lag.",
                        order = -1,
                        width = "full",
                        get = function() return bbSoundSearchText end,
                        set = function(_, val)
                            bbSoundSearchText = TrimString_BB_Opts(val)
                            AceRegistry:NotifyChange("CkraigCooldownManager")
                        end,
                    },
                    soundSearchHelp = {
                        type = "description",
                        name = "Tip: Use Search to find sounds instantly. Enable 'Show Full Sound List' to browse all sounds with page controls.",
                        order = -0.5,
                        width = "full",
                    },
                    refreshSoundList = {
                        type = "execute",
                        name = "Refresh Sound List",
                        desc = "Scan active cooldown bars and add them to the sound list",
                        order = 0,
                        func = function() end,
                    },
                    addSound = {
                        type = "input",
                        name = "Add Spell ID for Sound",
                        order = 1,
                        width = "double",
                        set = function(_, val) end,
                        get = function() return "" end,
                    },
                },
            },
            -- ============================
            -- Cluster Assignments tab
            -- ============================
            clusterAssign = {
                type = "group",
                name = "Cluster Assign",
                order = 6,
                args = {
                    desc = {
                        type = "description",
                        name = "Assign each bar spell to a cluster group. Enable Cluster Mode in the Clusters tab first.",
                        order = 0,
                    },
                    refreshAssign = {
                        type = "execute",
                        name = "Refresh List",
                        desc = "Scan active cooldown bars to populate the assignment list",
                        order = 1,
                        func = function() end, -- replaced below
                    },
                },
            },
        },
    }

    -- ============================
    -- Spell Colors: rebuild logic
    -- ============================
    local colorTab = CCM.AceOptionsTable.args.cooldownBars.args.spellColors

    local function ScanBarSpells()
        local items = {}
        local seen = {}
        local db = GetDB()
        if not db then return items end

        -- Use BarCore's proper spell resolution list providers
        local addon = GetBarAddon()
        if addon and addon.GetBarSpellItems then
            local barItems = addon:GetBarSpellItems()
            if type(barItems) == "table" then
                for _, item in ipairs(barItems) do
                    if item.key and not seen[tostring(item.key)] then
                        seen[tostring(item.key)] = true
                        table.insert(items, { key = tostring(item.key), name = item.label or item.name or ("Spell " .. item.key), icon = item.icon })
                    end
                end
            end
        end
        table.sort(items, function(a, b) return (a.name or "") < (b.name or "") end)
        return items
    end

    RebuildColorArgs = function()
        for k in pairs(colorTab.args) do
            if k:match("^spell_") then colorTab.args[k] = nil end
        end
        local db = GetDB()
        if not db then return end
        db.spellColors = db.spellColors or {}
        local items = ScanBarSpells()
        for idx, item in ipairs(items) do
            local skey = tostring(item.key)
            colorTab.args["spell_" .. skey] = {
                type = "group",
                name = "",
                order = 100 + idx,
                inline = true,
                args = {
                    icon = {
                        type = "description",
                        name = (item.name or skey) .. "  (ID: " .. skey .. ")",
                        order = 1,
                        image = function() return item.icon or "Interface\\ICONS\\INV_Misc_QuestionMark" end,
                        imageWidth = 24,
                        imageHeight = 24,
                        width = 1.2,
                    },
                    color = {
                        type = "color",
                        name = "Bar Color",
                        order = 2,
                        hasAlpha = true,
                        width = 0.6,
                        get = function()
                            local d = GetDB()
                            local c = d and d.spellColors and d.spellColors[skey]
                            if c then return c.r or 0.5, c.g or 0.5, c.b or 0.5, c.a or 1 end
                            return 0.5, 0.5, 0.5, 1
                        end,
                        set = function(_, r, g, b, a)
                            local d = GetDB()
                            if d then
                                d.spellColors = d.spellColors or {}
                                d.spellColors[skey] = { r = r, g = g, b = b, a = a }
                                Refresh()
                            end
                        end,
                    },
                    remove = {
                        type = "execute",
                        name = "Remove",
                        order = 3,
                        width = 0.5,
                        confirm = true,
                        func = function()
                            local d = GetDB()
                            if d and d.spellColors then
                                d.spellColors[skey] = nil
                                Refresh()
                                RebuildColorArgs()
                                AceRegistry:NotifyChange("CkraigCooldownManager")
                            end
                        end,
                    },
                },
            }
        end
    end

    colorTab.args.refreshList.func = function()
        RebuildColorArgs()
        AceRegistry:NotifyChange("CkraigCooldownManager")
    end

    colorTab.args.addSpell.set = function(_, val)
        local id = tonumber(val)
        if not id or id <= 0 then return end
        local db = GetDB()
        if not db then return end
        db.spellColors = db.spellColors or {}
        if not db.spellColors[tostring(id)] then
            db.spellColors[tostring(id)] = { r = 0.5, g = 0.5, b = 0.5, a = 1 }
        end
        Refresh()
        RebuildColorArgs()
        AceRegistry:NotifyChange("CkraigCooldownManager")
    end

    RebuildColorArgs()

    -- ============================
    -- Spell Glows: rebuild logic
    -- ============================
    local glowTab = CCM.AceOptionsTable.args.cooldownBars.args.spellGlows

    local function RebuildBarGlowArgs()
        for k in pairs(glowTab.args) do
            if k:match("^glow_") then glowTab.args[k] = nil end
        end
        local db = GetDB()
        if not db or not db.spellGlows then return end

        local liveByKey = {}
        for _, item in ipairs(ScanBarSpells()) do
            if item and item.key ~= nil then
                liveByKey[tostring(item.key)] = item
            end
        end

        local sorted = {}
        for key, cfg in pairs(db.spellGlows) do
            if type(cfg) == "table" and liveByKey[tostring(key)] then
                table.insert(sorted, key)
            end
        end
        table.sort(sorted, function(a, b)
            local aItem = liveByKey[tostring(a)]
            local bItem = liveByKey[tostring(b)]
            local aName = (aItem and aItem.name) or tostring(a)
            local bName = (bItem and bItem.name) or tostring(b)
            return aName < bName
        end)

        for idx, skey in ipairs(sorted) do
            local liveItem = liveByKey[tostring(skey)]
            local spellName = (liveItem and liveItem.name) or ("Cooldown " .. skey)
            local spellIcon = liveItem and liveItem.icon or nil

            glowTab.args["glow_" .. skey] = {
                type = "group",
                name = "",
                order = 100 + idx,
                inline = true,
                args = {
                    icon = {
                        type = "description",
                        name = (spellName or skey) .. "  (ID: " .. skey .. ")",
                        order = 1,
                        image = function() return spellIcon or "Interface\\ICONS\\INV_Misc_QuestionMark" end,
                        imageWidth = 24,
                        imageHeight = 24,
                        width = 1.2,
                    },
                    enabled = {
                        type = "toggle",
                        name = "Enabled",
                        order = 2,
                        width = 0.5,
                        get = function()
                            local d = GetDB()
                            local g = d and d.spellGlows and d.spellGlows[skey]
                            return g and g.enabled
                        end,
                        set = function(_, val)
                            local d = GetDB()
                            if d and d.spellGlows and d.spellGlows[skey] then
                                d.spellGlows[skey].enabled = val; Refresh()
                            end
                        end,
                    },
                    mode = {
                        type = "select",
                        name = "Mode",
                        order = 3,
                        values = { show = "When Shown", inactive = "When Inactive" },
                        width = 0.7,
                        get = function()
                            local d = GetDB()
                            local g = d and d.spellGlows and d.spellGlows[skey]
                            return g and g.mode or "show"
                        end,
                        set = function(_, val)
                            local d = GetDB()
                            if d and d.spellGlows and d.spellGlows[skey] then
                                d.spellGlows[skey].mode = val; Refresh()
                            end
                        end,
                    },
                    color = {
                        type = "color",
                        name = "Color",
                        order = 4,
                        hasAlpha = true,
                        width = 0.5,
                        get = function()
                            local d = GetDB()
                            local g = d and d.spellGlows and d.spellGlows[skey]
                            if g and g.color then return g.color.r or 1, g.color.g or 1, g.color.b or 0, g.color.a or 1 end
                            return 1, 1, 0, 1
                        end,
                        set = function(_, r, g, b, a)
                            local d = GetDB()
                            if d and d.spellGlows and d.spellGlows[skey] then
                                d.spellGlows[skey].color = { r = r, g = g, b = b, a = a }; Refresh()
                            end
                        end,
                    },
                    remove = {
                        type = "execute",
                        name = "Remove",
                        order = 5,
                        width = 0.5,
                        confirm = true,
                        func = function()
                            local d = GetDB()
                            if d and d.spellGlows then
                                d.spellGlows[skey] = nil; Refresh()
                                RebuildBarGlowArgs()
                                AceRegistry:NotifyChange("CkraigCooldownManager")
                            end
                        end,
                    },
                },
            }
        end
    end

    glowTab.args.refreshGlowList.func = function()
        local db = GetDB()
        if not db then return end
        db.spellGlows = db.spellGlows or {}

        local validBarKeys = {}
        local items = ScanBarSpells()
        for _, item in ipairs(items) do
            local skey = tostring(item.key)
            validBarKeys[skey] = true
            if not db.spellGlows[skey] then
                db.spellGlows[skey] = { enabled = false, mode = "show", color = { r = 1, g = 1, b = 0, a = 1 } }
            end
        end
        -- Remove stale entries not present in currently scanned bars
        for skey in pairs(db.spellGlows) do
            if not validBarKeys[tostring(skey)] then
                db.spellGlows[skey] = nil
            end
        end
        RebuildBarGlowArgs()
        AceRegistry:NotifyChange("CkraigCooldownManager")
    end

    glowTab.args.addGlow.set = function(_, val)
        local id = tonumber(val)
        if not id or id <= 0 then return end
        local db = GetDB()
        if not db then return end
        db.spellGlows = db.spellGlows or {}
        if not db.spellGlows[tostring(id)] then
            db.spellGlows[tostring(id)] = { enabled = true, mode = "show", color = { r = 1, g = 1, b = 0, a = 1 } }
        end
        Refresh()
        RebuildBarGlowArgs()
        AceRegistry:NotifyChange("CkraigCooldownManager")
    end

    RebuildBarGlowArgs()

    -- ============================
    -- Spell Sounds: rebuild logic
    -- ============================
    local soundTab = CCM.AceOptionsTable.args.cooldownBars.args.spellSounds

    local function ResolveSoundPath_BB_Opts(soundKey)
        if not soundKey or soundKey == "" then return nil end
        if LSM and LSM.Fetch then
            local ok, path = pcall(LSM.Fetch, LSM, "sound", soundKey, true)
            if ok and path and path ~= "" then
                return path
            end
        end
        return soundKey
    end

    local function RebuildBarSoundArgs()
        for k in pairs(soundTab.args) do
            if k:match("^sound_") then soundTab.args[k] = nil end
        end
        local db = GetDB()
        if not db then return end
        db.spellSounds = db.spellSounds or {}

        local liveByKey = {}
        for _, item in ipairs(ScanBarSpells()) do
            if item and item.key ~= nil then
                liveByKey[tostring(item.key)] = item
            end
        end

        local sorted = {}
        for key, cfg in pairs(db.spellSounds) do
            if type(cfg) == "table" and liveByKey[tostring(key)] then
                table.insert(sorted, key)
            end
        end
        table.sort(sorted, function(a, b)
            local aItem = liveByKey[tostring(a)]
            local bItem = liveByKey[tostring(b)]
            local aName = (aItem and aItem.name) or tostring(a)
            local bName = (bItem and bItem.name) or tostring(b)
            return aName < bName
        end)

        for idx, skey in ipairs(sorted) do
            local liveItem = liveByKey[tostring(skey)]
            local spellName = (liveItem and liveItem.name) or ("Cooldown " .. skey)
            local spellIcon = liveItem and liveItem.icon or nil

            soundTab.args["sound_" .. skey] = {
                type = "group",
                name = "",
                order = 100 + idx,
                inline = true,
                args = {
                    icon = {
                        type = "description",
                        name = (spellName or skey) .. "  (ID: " .. skey .. ")",
                        order = 1,
                        image = function() return spellIcon or "Interface\\ICONS\\INV_Misc_QuestionMark" end,
                        imageWidth = 24,
                        imageHeight = 24,
                        width = 1.2,
                    },
                    enabled = {
                        type = "toggle",
                        name = "Enabled",
                        order = 2,
                        width = 0.5,
                        get = function()
                            local d = GetDB()
                            local s = d and d.spellSounds and d.spellSounds[skey]
                            return s and s.enabled
                        end,
                        set = function(_, val)
                            local d = GetDB()
                            if d and d.spellSounds and d.spellSounds[skey] then
                                d.spellSounds[skey].enabled = val and true or false
                                TouchSpellSoundConfig_BB_Opts(d)
                                Refresh()
                            end
                        end,
                    },
                    mode = {
                        type = "select",
                        name = "Trigger",
                        order = 2.5,
                        width = 0.8,
                        values = {
                            show = "On Start (Show)",
                            expire = "On Expire (Hide)",
                            both = "On Start + Expire",
                        },
                        get = function()
                            local d = GetDB()
                            local s = d and d.spellSounds and d.spellSounds[skey]
                            local mode = (s and s.mode) or "expire"
                            if mode == "ready" then mode = "expire" end
                            return mode
                        end,
                        set = function(_, val)
                            local d = GetDB()
                            if d and d.spellSounds and d.spellSounds[skey] then
                                d.spellSounds[skey].mode = val or "expire"
                                TouchSpellSoundConfig_BB_Opts(d)
                                Refresh()
                            end
                        end,
                    },
                    output = {
                        type = "select",
                        name = "Output",
                        order = 2.6,
                        width = 0.8,
                        values = {
                            sound = "SharedMedia Sound",
                            tts = "TTS",
                            both = "Sound + TTS",
                        },
                        get = function()
                            local d = GetDB()
                            local s = d and d.spellSounds and d.spellSounds[skey]
                            return (s and s.output) or "sound"
                        end,
                        set = function(_, val)
                            local d = GetDB()
                            if d and d.spellSounds and d.spellSounds[skey] then
                                d.spellSounds[skey].output = val or "sound"
                                TouchSpellSoundConfig_BB_Opts(d)
                                Refresh()
                            end
                        end,
                    },
                    sound = {
                        type = "select",
                        name = "Sound",
                        order = 3,
                        width = 1.1,
                        hidden = function()
                            local d = GetDB()
                            local s = d and d.spellSounds and d.spellSounds[skey]
                            local output = (s and s.output) or "sound"
                            return output == "tts"
                        end,
                        values = function()
                            local d = GetDB()
                            local s = d and d.spellSounds and d.spellSounds[skey]
                            local current = s and s.sound or nil
                            return GetFilteredSoundValues_BB_Opts(current)
                        end,
                        get = function()
                            local d = GetDB()
                            local s = d and d.spellSounds and d.spellSounds[skey]
                            return s and s.sound or ""
                        end,
                        set = function(_, val)
                            local d = GetDB()
                            if d and d.spellSounds and d.spellSounds[skey] then
                                d.spellSounds[skey].sound = val or ""
                                TouchSpellSoundConfig_BB_Opts(d)
                                Refresh()
                            end
                        end,
                    },
                    ttsText = {
                        type = "input",
                        name = "TTS Text",
                        desc = "Text spoken when TTS output is enabled. Leave empty to use spell name.",
                        order = 3.1,
                        width = 1.1,
                        hidden = function()
                            local d = GetDB()
                            local s = d and d.spellSounds and d.spellSounds[skey]
                            local output = (s and s.output) or "sound"
                            return output == "sound"
                        end,
                        get = function()
                            local d = GetDB()
                            local s = d and d.spellSounds and d.spellSounds[skey]
                            return (s and s.ttsText) or ""
                        end,
                        set = function(_, val)
                            local d = GetDB()
                            if d and d.spellSounds and d.spellSounds[skey] then
                                d.spellSounds[skey].ttsText = tostring(val or "")
                                TouchSpellSoundConfig_BB_Opts(d)
                                Refresh()
                            end
                        end,
                    },
                    test = {
                        type = "execute",
                        name = "Play",
                        order = 4,
                        width = 0.4,
                        func = function()
                            local d = GetDB()
                            local s = d and d.spellSounds and d.spellSounds[skey]
                            if not s then return end

                            local output = tostring(s.output or "sound")
                            if (output == "sound" or output == "both") then
                                local soundPath = ResolveSoundPath_BB_Opts(s.sound)
                                if soundPath then
                                    pcall(PlaySoundFile, soundPath, "Master")
                                end
                            end

                            if (output == "tts" or output == "both") and C_VoiceChat and C_VoiceChat.SpeakText and C_TTSSettings and C_TTSSettings.GetVoiceOptionID and Enum and Enum.TtsVoiceType then
                                local text = tostring(s.ttsText or "")
                                if text == "" then
                                    text = spellName or ("Spell " .. skey)
                                end
                                local voiceID = C_TTSSettings.GetVoiceOptionID(Enum.TtsVoiceType.Standard)
                                if voiceID then
                                    local rate = (C_TTSSettings.GetSpeechRate and C_TTSSettings.GetSpeechRate()) or 0
                                    local volume = (C_TTSSettings.GetSpeechVolume and C_TTSSettings.GetSpeechVolume()) or 100
                                    pcall(C_VoiceChat.SpeakText, voiceID, text, rate, volume, false)
                                end
                            end
                        end,
                    },
                    remove = {
                        type = "execute",
                        name = "Remove",
                        order = 5,
                        width = 0.5,
                        confirm = true,
                        func = function()
                            local d = GetDB()
                            if d and d.spellSounds then
                                d.spellSounds[skey] = nil
                                TouchSpellSoundConfig_BB_Opts(d)
                                Refresh()
                                RebuildBarSoundArgs()
                                AceRegistry:NotifyChange("CkraigCooldownManager")
                            end
                        end,
                    },
                },
            }
        end
    end

    soundTab.args.refreshSoundList.func = function()
        local db = GetDB()
        if not db then return end
        bbSoundKeyCache = nil
        db.spellSounds = db.spellSounds or {}

        local validBarKeys = {}
        local items = ScanBarSpells()
        for _, item in ipairs(items) do
            local skey = tostring(item.key)
            validBarKeys[skey] = true
            if not db.spellSounds[skey] then
                db.spellSounds[skey] = { enabled = false, sound = "", output = "sound", ttsText = "", mode = "expire" }
            elseif type(db.spellSounds[skey]) == "table" and (db.spellSounds[skey].mode == nil or db.spellSounds[skey].mode == "") then
                db.spellSounds[skey].mode = "expire"
            elseif type(db.spellSounds[skey]) == "table" and db.spellSounds[skey].mode == "ready" then
                db.spellSounds[skey].mode = "expire"
            end
            if type(db.spellSounds[skey]) == "table" and (db.spellSounds[skey].output == nil or db.spellSounds[skey].output == "") then
                db.spellSounds[skey].output = "sound"
            end
            if type(db.spellSounds[skey]) == "table" and type(db.spellSounds[skey].ttsText) ~= "string" then
                db.spellSounds[skey].ttsText = ""
            end
        end
        for skey in pairs(db.spellSounds) do
            if not validBarKeys[tostring(skey)] then
                db.spellSounds[skey] = nil
            end
        end

        TouchSpellSoundConfig_BB_Opts(db)
        RebuildBarSoundArgs()
        AceRegistry:NotifyChange("CkraigCooldownManager")
    end

    soundTab.args.addSound.set = function(_, val)
        local id = tonumber(val)
        if not id or id <= 0 then return end
        local db = GetDB()
        if not db then return end

        local allowed = false
        local items = ScanBarSpells()
        for _, item in ipairs(items) do
            if tostring(item.key) == tostring(id) then
                allowed = true
                break
            end
        end
        if not allowed then return end

        db.spellSounds = db.spellSounds or {}
        if not db.spellSounds[tostring(id)] then
            db.spellSounds[tostring(id)] = { enabled = true, sound = "", output = "sound", ttsText = "", mode = "expire" }
        elseif type(db.spellSounds[tostring(id)]) == "table" and (db.spellSounds[tostring(id)].mode == nil or db.spellSounds[tostring(id)].mode == "") then
            db.spellSounds[tostring(id)].mode = "expire"
        elseif type(db.spellSounds[tostring(id)]) == "table" and db.spellSounds[tostring(id)].mode == "ready" then
            db.spellSounds[tostring(id)].mode = "expire"
        end
        if type(db.spellSounds[tostring(id)]) == "table" and (db.spellSounds[tostring(id)].output == nil or db.spellSounds[tostring(id)].output == "") then
            db.spellSounds[tostring(id)].output = "sound"
        end
        if type(db.spellSounds[tostring(id)]) == "table" and type(db.spellSounds[tostring(id)].ttsText) ~= "string" then
            db.spellSounds[tostring(id)].ttsText = ""
        end
        TouchSpellSoundConfig_BB_Opts(db)
        Refresh()
        RebuildBarSoundArgs()
        AceRegistry:NotifyChange("CkraigCooldownManager")
    end

    RebuildBarSoundArgs()

    -- ============================
    -- Cluster Assignments: rebuild logic
    -- ============================
    local assignTab = CCM.AceOptionsTable.args.cooldownBars.args.clusterAssign

    local function RebuildClusterAssignArgs()
        for k in pairs(assignTab.args) do
            if k:match("^assign_") then assignTab.args[k] = nil end
        end
        local db = GetDB()
        if not db then return end
        db.clusterAssignments = db.clusterAssignments or {}

        local clusterCount = db.clusterCount or 1
        local clusterValues = {}
        for c = 1, clusterCount do
            clusterValues[c] = "Cluster " .. c
        end

        local items = ScanBarSpells()
        for idx, item in ipairs(items) do
            local skey = tostring(item.key)
            local spellName = item.label or item.name or ("Spell " .. skey)
            local spellIcon = item.icon

            assignTab.args["assign_" .. skey] = {
                type = "group",
                name = "",
                order = 100 + idx,
                inline = true,
                args = {
                    icon = {
                        type = "description",
                        name = spellName .. "  |cff888888(" .. skey .. ")|r",
                        order = 1,
                        image = function() return spellIcon or "Interface\\ICONS\\INV_Misc_QuestionMark" end,
                        imageWidth = 24,
                        imageHeight = 24,
                        width = 1.5,
                    },
                    cluster = {
                        type = "select",
                        name = "Cluster",
                        order = 2,
                        width = 0.8,
                        values = function()
                            local d = GetDB()
                            local cnt = d and d.clusterCount or 1
                            local v = {}
                            for c = 1, cnt do v[c] = "Cluster " .. c end
                            return v
                        end,
                        get = function()
                            local d = GetDB()
                            if d and d.clusterAssignments and d.clusterAssignments[skey] then
                                return tonumber(d.clusterAssignments[skey]) or 1
                            end
                            return 1
                        end,
                        set = function(_, val)
                            local d = GetDB()
                            if d then
                                d.clusterAssignments = d.clusterAssignments or {}
                                d.clusterAssignments[skey] = val
                                Refresh()
                            end
                        end,
                    },
                },
            }
        end

        if #items == 0 then
            assignTab.args.assign_empty = {
                type = "description",
                name = "|cff888888No bar spells detected. Make sure bars are visible, then click Refresh List.|r",
                order = 100,
                fontSize = "medium",
            }
        end
    end

    assignTab.args.refreshAssign.func = function()
        RebuildClusterAssignArgs()
        AceRegistry:NotifyChange("CkraigCooldownManager")
    end

    RebuildClusterAssignArgs()

    -- ============================
    -- Generate per-cluster controls
    -- ============================
    local clusterArgs = CCM.AceOptionsTable.args.cooldownBars.args.clusters.args
    for i = 1, MAX_BAR_CLUSTERS do
        local groupKey = "cluster" .. i
        clusterArgs[groupKey] = {
            type = "group",
            name = "Cluster " .. i,
            order = 10 + i,
            inline = true,
            hidden = function()
                local db = GetDB()
                return not db or not db.clusterMode or (db.clusterCount or 1) < i
            end,
            args = {
                width = {
                    type = "range",
                    name = "Width",
                    order = 1,
                    min = 50, max = 600, step = 1,
                    get = function()
                        local db = GetDB()
                        return db and db.clusterBarWidths and db.clusterBarWidths[i] or 200
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterBarWidths = db.clusterBarWidths or {}
                            db.clusterBarWidths[i] = val
                            Refresh()
                        end
                    end,
                },
                height = {
                    type = "range",
                    name = "Height",
                    order = 2,
                    min = 8, max = 100, step = 1,
                    get = function()
                        local db = GetDB()
                        return db and db.clusterBarHeights and db.clusterBarHeights[i] or 24
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterBarHeights = db.clusterBarHeights or {}
                            db.clusterBarHeights[i] = val
                            Refresh()
                        end
                    end,
                },
                flow = {
                    type = "select",
                    name = "Flow Direction",
                    order = 3,
                    values = opts.FLOW_VALUES,
                    get = function()
                        local db = GetDB()
                        return db and db.clusterFlows and db.clusterFlows[i] or "vertical"
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterFlows = db.clusterFlows or {}
                            db.clusterFlows[i] = val
                            Refresh()
                        end
                    end,
                },
                grow = {
                    type = "select",
                    name = "Grow Direction",
                    order = 4,
                    values = opts.GROW_VALUES,
                    get = function()
                        local db = GetDB()
                        return db and db.clusterGrowDirections and db.clusterGrowDirections[i] or "down"
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterGrowDirections = db.clusterGrowDirections or {}
                            db.clusterGrowDirections[i] = val
                            Refresh()
                        end
                    end,
                },
                verticalGrow = {
                    type = "select",
                    name = "Vertical Stack Direction",
                    desc = "When flow is Vertical, controls whether bars stack left-to-right or right-to-left.",
                    order = 4.5,
                    values = { right = "Left to Right", left = "Right to Left" },
                    hidden = function()
                        local db = GetDB()
                        local f = db and db.clusterFlows and db.clusterFlows[i] or "vertical"
                        return string.lower(tostring(f)) ~= "vertical"
                    end,
                    get = function()
                        local db = GetDB()
                        return db and db.clusterVerticalGrowDirections and db.clusterVerticalGrowDirections[i] or "right"
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterVerticalGrowDirections = db.clusterVerticalGrowDirections or {}
                            db.clusterVerticalGrowDirections[i] = val
                            Refresh()
                        end
                    end,
                },
                iconPos = {
                    type = "select",
                    name = "Icon Position",
                    order = 5,
                    values = { bottom = "Bottom", top = "Top", left = "Left" },
                    get = function()
                        local db = GetDB()
                        return db and db.clusterIconPositions and db.clusterIconPositions[i] or "left"
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterIconPositions = db.clusterIconPositions or {}
                            db.clusterIconPositions[i] = val
                            Refresh()
                        end
                    end,
                },
                strata = {
                    type = "select",
                    name = "Frame Strata",
                    order = 6,
                    values = { BACKGROUND = "Background", LOW = "Low", MEDIUM = "Medium", HIGH = "High", DIALOG = "Dialog" },
                    get = function()
                        local db = GetDB()
                        return db and db.clusterStratas and db.clusterStratas[i] or "MEDIUM"
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterStratas = db.clusterStratas or {}
                            db.clusterStratas[i] = val
                            Refresh()
                        end
                    end,
                },
                barTexture = {
                    type = "select",
                    name = "Bar Texture",
                    desc = "Override bar texture for this cluster. Leave as (Global) to use the shared texture.",
                    order = 7,
                    dialogControl = "LSM30_Statusbar",
                    values = function() return opts.GetTextureValues() end,
                    get = function()
                        local db = GetDB()
                        return db and db.clusterBarTextures and db.clusterBarTextures[i] or db.texture
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterBarTextures = db.clusterBarTextures or {}
                            if val == db.texture then
                                db.clusterBarTextures[i] = nil
                            else
                                db.clusterBarTextures[i] = val
                            end
                            Refresh()
                        end
                    end,
                },
                hideBarName = {
                    type = "toggle",
                    name = "Hide Bar Name",
                    desc = "Override the global Hide Bar Name setting for this cluster.",
                    order = 8,
                    get = function()
                        local db = GetDB()
                        if db and db.clusterHideBarNames and db.clusterHideBarNames[i] ~= nil then
                            return db.clusterHideBarNames[i]
                        end
                        return db and db.hideBarName or false
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterHideBarNames = db.clusterHideBarNames or {}
                            db.clusterHideBarNames[i] = val and true or false
                            Refresh()
                        end
                    end,
                },
                hideIcons = {
                    type = "toggle",
                    name = "Hide Icons",
                    desc = "Override the global Hide Icons setting for this cluster.",
                    order = 9,
                    get = function()
                        local db = GetDB()
                        if db and db.clusterHideIcons and db.clusterHideIcons[i] ~= nil then
                            return db.clusterHideIcons[i]
                        end
                        return db and db.hideIcons or false
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterHideIcons = db.clusterHideIcons or {}
                            db.clusterHideIcons[i] = val and true or false
                            Refresh()
                        end
                    end,
                },
                showAlways = {
                    type = "toggle",
                    name = "Show Always",
                    desc = "Keep this cluster anchor visible at all times (subtle blue outline).",
                    order = 10,
                    get = function()
                        local db = GetDB()
                        return db and db.clusterShowAlways and db.clusterShowAlways[i] or false
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterShowAlways = db.clusterShowAlways or {}
                            db.clusterShowAlways[i] = val and true or false
                            Refresh()
                        end
                    end,
                },
                nameFontHeader = {
                    type = "header",
                    name = "Name Font",
                    order = 11,
                },
                nameFontSize = {
                    type = "range",
                    name = "Name Font Size",
                    desc = "0 = use global setting",
                    order = 12,
                    min = 0, max = 40, step = 1,
                    get = function()
                        local db = GetDB()
                        return db and db.clusterNameFontSizes and db.clusterNameFontSizes[i] or 0
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterNameFontSizes = db.clusterNameFontSizes or {}
                            db.clusterNameFontSizes[i] = val > 0 and val or nil
                            Refresh()
                        end
                    end,
                },
                nameXOffset = {
                    type = "range",
                    name = "Name X Offset",
                    order = 13,
                    min = -50, max = 50, step = 1,
                    get = function()
                        local db = GetDB()
                        local o = db and db.clusterNameOffsets and db.clusterNameOffsets[i]
                        return o and o.x or 0
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterNameOffsets = db.clusterNameOffsets or {}
                            db.clusterNameOffsets[i] = db.clusterNameOffsets[i] or { x = 0, y = 0 }
                            db.clusterNameOffsets[i].x = val
                            Refresh()
                        end
                    end,
                },
                nameYOffset = {
                    type = "range",
                    name = "Name Y Offset",
                    order = 14,
                    min = -50, max = 50, step = 1,
                    get = function()
                        local db = GetDB()
                        local o = db and db.clusterNameOffsets and db.clusterNameOffsets[i]
                        return o and o.y or 0
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterNameOffsets = db.clusterNameOffsets or {}
                            db.clusterNameOffsets[i] = db.clusterNameOffsets[i] or { x = 0, y = 0 }
                            db.clusterNameOffsets[i].y = val
                            Refresh()
                        end
                    end,
                },
                timerFontHeader = {
                    type = "header",
                    name = "Timer Font",
                    order = 20,
                },
                timerFontSize = {
                    type = "range",
                    name = "Timer Font Size",
                    desc = "0 = use global setting",
                    order = 21,
                    min = 0, max = 40, step = 1,
                    get = function()
                        local db = GetDB()
                        return db and db.clusterTimerFontSizes and db.clusterTimerFontSizes[i] or 0
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterTimerFontSizes = db.clusterTimerFontSizes or {}
                            db.clusterTimerFontSizes[i] = val > 0 and val or nil
                            Refresh()
                        end
                    end,
                },
                timerXOffset = {
                    type = "range",
                    name = "Timer X Offset",
                    order = 22,
                    min = -50, max = 50, step = 1,
                    get = function()
                        local db = GetDB()
                        local o = db and db.clusterTimerOffsets and db.clusterTimerOffsets[i]
                        return o and o.x or 0
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterTimerOffsets = db.clusterTimerOffsets or {}
                            db.clusterTimerOffsets[i] = db.clusterTimerOffsets[i] or { x = 0, y = 0 }
                            db.clusterTimerOffsets[i].x = val
                            Refresh()
                        end
                    end,
                },
                timerYOffset = {
                    type = "range",
                    name = "Timer Y Offset",
                    order = 23,
                    min = -50, max = 50, step = 1,
                    get = function()
                        local db = GetDB()
                        local o = db and db.clusterTimerOffsets and db.clusterTimerOffsets[i]
                        return o and o.y or 0
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterTimerOffsets = db.clusterTimerOffsets or {}
                            db.clusterTimerOffsets[i] = db.clusterTimerOffsets[i] or { x = 0, y = 0 }
                            db.clusterTimerOffsets[i].y = val
                            Refresh()
                        end
                    end,
                },
                stackFontHeader = {
                    type = "header",
                    name = "Stack Font",
                    order = 30,
                },
                stackFontSize = {
                    type = "range",
                    name = "Stack Font Size",
                    desc = "0 = use global setting",
                    order = 31,
                    min = 0, max = 40, step = 1,
                    get = function()
                        local db = GetDB()
                        return db and db.clusterStackFontSizes and db.clusterStackFontSizes[i] or 0
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterStackFontSizes = db.clusterStackFontSizes or {}
                            db.clusterStackFontSizes[i] = val > 0 and val or nil
                            Refresh()
                        end
                    end,
                },
                stackXOffset = {
                    type = "range",
                    name = "Stack X Offset",
                    order = 32,
                    min = -300, max = 300, step = 1,
                    get = function()
                        local db = GetDB()
                        local o = db and db.clusterStackOffsets and db.clusterStackOffsets[i]
                        return o and o.x or 0
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterStackOffsets = db.clusterStackOffsets or {}
                            db.clusterStackOffsets[i] = db.clusterStackOffsets[i] or { x = 0, y = 0 }
                            db.clusterStackOffsets[i].x = val
                            Refresh()
                        end
                    end,
                },
                stackYOffset = {
                    type = "range",
                    name = "Stack Y Offset",
                    order = 33,
                    min = -300, max = 300, step = 1,
                    get = function()
                        local db = GetDB()
                        local o = db and db.clusterStackOffsets and db.clusterStackOffsets[i]
                        return o and o.y or 0
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterStackOffsets = db.clusterStackOffsets or {}
                            db.clusterStackOffsets[i] = db.clusterStackOffsets[i] or { x = 0, y = 0 }
                            db.clusterStackOffsets[i].y = val
                            Refresh()
                        end
                    end,
                },
            },
        }
    end
end
