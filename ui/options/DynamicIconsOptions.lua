-- ============================================================
-- CkraigCooldownManager :: UI :: Options :: Dynamic Icons
-- ============================================================
-- AceConfig options table for the Dynamic Icons module.
-- Replaces the hand-built DYNAMICICONS.CreateOptionsPanel.
-- ============================================================

local CCM = _G.CkraigCooldownManager
local AceRegistry = LibStub("AceConfigRegistry-3.0")
local LSM = LibStub("LibSharedMedia-3.0", true)

local soundKeyCache = nil
local soundSearchText = ""
local soundLsmCallbackRegistered = false
local soundShowAll = true     -- true = paginated full list by default
local soundPage = 1
local soundPageSize = 150

local function TrimString(s)
    if type(s) ~= "string" then return "" end
    return s:match("^%s*(.-)%s*$") or ""
end

local function BuildSoundKeyCache()
    if soundKeyCache then return soundKeyCache end
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
    soundKeyCache = keys
    return soundKeyCache
end

local function GetFilteredSoundValues(currentValue)
    local values = {}
    local keys = BuildSoundKeyCache()
    local query = TrimString(soundSearchText):lower()
    local hasSearch = (query ~= "")

    -- When searching, show all matches (no cap, no pagination)
    -- When lazy mode (soundShowAll == false), cap at 80
    -- When full mode (soundShowAll == true), paginate
    if hasSearch then
        for _, key in ipairs(keys) do
            if key:lower():find(query, 1, true) then
                values[key] = key
            end
        end
    elseif soundShowAll then
        -- Paginated full list
        local totalKeys = #keys
        local totalPages = math.max(1, math.ceil(totalKeys / soundPageSize))
        if soundPage > totalPages then soundPage = totalPages end
        if soundPage < 1 then soundPage = 1 end
        local startIdx = (soundPage - 1) * soundPageSize + 1
        local endIdx = math.min(startIdx + soundPageSize - 1, totalKeys)
        for i = startIdx, endIdx do
            local key = keys[i]
            if key then
                values[key] = key
            end
        end
    else
        -- Lazy mode: first 80
        local count = 0
        for _, key in ipairs(keys) do
            values[key] = key
            count = count + 1
            if count >= 80 then
                break
            end
        end
    end

    if currentValue and currentValue ~= "" and not values[currentValue] then
        values[currentValue] = currentValue .. " (selected)"
    end

    return values
end

local function RegisterSoundMediaCallback()
    if soundLsmCallbackRegistered or not (LSM and LSM.RegisterCallback) then
        return
    end
    soundLsmCallbackRegistered = true
    LSM:RegisterCallback("LibSharedMedia_Registered", function(_, mediaType)
        if mediaType == "sound" then
            soundKeyCache = nil
            AceRegistry:NotifyChange("CkraigCooldownManager")
        end
    end)
end

local function GetDB()
    if DYNAMICICONS and DYNAMICICONS.GetSettings then
        return DYNAMICICONS:GetSettings()
    end
    return CCM.AceOpts.GetProfileData("dynamicIcons")
end

local function TouchSpellSoundConfig(db)
    db = db or GetDB()
    if not db then return end
    db.spellSoundsRevision = (tonumber(db.spellSoundsRevision) or 0) + 1
end

local function Refresh()
    if DYNAMICICONS and DYNAMICICONS.RefreshLayout then
        DYNAMICICONS:RefreshLayout()
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

function CCM.BuildDynamicIconsOptions()
    local opts = CCM.AceOpts
    local MAX_CLUSTERS = 20

    RegisterSoundMediaCallback()

    CCM.AceOptionsTable.args.dynamicIcons = {
        type = "group",
        name = "Dynamic Icons",
        order = 20,
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
                    enabled = {
                        type = "toggle",
                        name = "Enable Dynamic Icons",
                        order = 1,
                        width = "full",
                        get = function() local db = GetDB(); return db and db.enabled end,
                        set = function(_, val) local db = GetDB(); if db then db.enabled = val; Refresh() end end,
                    },
                    previewViewer = {
                        type = "execute",
                        name = "Toggle Blizzard Cooldown Settings",
                        desc = "Opens the real Blizzard Cooldown Settings window and also shows the desaturated Dynamic Icon cluster samples while that window is open.",
                        order = 1.5,
                        width = "full",
                        func = function()
                            ToggleCooldownSettingsPanel()
                        end,
                    },
                    startupSamplePreview = {
                        type = "toggle",
                        name = "Show Sample Clusters For 3 Seconds On Login",
                        desc = "Shows the desaturated Dynamic Icon cluster samples briefly when you first load into the game.",
                        order = 1.6,
                        width = "full",
                        get = function()
                            local db = GetDB()
                            return db and db.startupSamplePreview
                        end,
                        set = function(_, val)
                            local db = GetDB()
                            if db then
                                db.startupSamplePreview = val and true or false
                            end
                        end,
                    },
                    hideWhenMounted = {
                        type = "toggle",
                        name = "Hide When Mounted",
                        order = 2,
                        get = function() local db = GetDB(); return db and db.hideWhenMounted end,
                        set = function(_, val)
                            local db = GetDB()
                            if db then
                                db.hideWhenMounted = val
                                Refresh()
                                if DYNAMICICONS and DYNAMICICONS.RefreshVisibility then
                                    DYNAMICICONS:RefreshVisibility()
                                end
                            end
                        end,
                    },
                    showSwipe = {
                        type = "toggle",
                        name = "Show Cooldown Swipe",
                        order = 3,
                        get = function() local db = GetDB(); return db and db.showSwipe end,
                        set = function(_, val) local db = GetDB(); if db then db.showSwipe = val; Refresh() end end,
                    },
                    headerSize = {
                        type = "header",
                        name = "Size & Layout",
                        order = 10,
                    },
                    iconSize = {
                        type = "range",
                        name = "Icon Size",
                        order = 11,
                        min = 8, max = 128, step = 1,
                        get = function() local db = GetDB(); return db and db.iconSize end,
                        set = function(_, val) local db = GetDB(); if db then db.iconSize = val; Refresh() end end,
                    },
                    spacing = {
                        type = "range",
                        name = "Horizontal Spacing",
                        order = 12,
                        min = 0, max = 40, step = 1,
                        get = function() local db = GetDB(); return db and db.spacing end,
                        set = function(_, val) local db = GetDB(); if db then db.spacing = val; Refresh() end end,
                    },
                    columns = {
                        type = "range",
                        name = "Icons Per Row",
                        order = 13,
                        min = 1, max = 50, step = 1,
                        get = function() local db = GetDB(); return db and (db.columns or db.rowLimit) end,
                        set = function(_, val)
                            local db = GetDB()
                            if db then db.columns = val; db.rowLimit = val; Refresh() end
                        end,
                    },
                    headerText = {
                        type = "header",
                        name = "Text Settings",
                        order = 20,
                    },
                    cooldownTextSize = {
                        type = "range",
                        name = "Cooldown Text Size",
                        order = 21,
                        min = 8, max = 36, step = 1,
                        get = function() local db = GetDB(); return db and db.cooldownTextSize end,
                        set = function(_, val) local db = GetDB(); if db then db.cooldownTextSize = val; Refresh() end end,
                    },
                    chargeTextSize = {
                        type = "range",
                        name = "Charge/Stack Font Size",
                        order = 22,
                        min = 6, max = 72, step = 1,
                        get = function() local db = GetDB(); return db and db.chargeTextSize end,
                        set = function(_, val) local db = GetDB(); if db then db.chargeTextSize = val; Refresh() end end,
                    },
                    chargeTextPosition = {
                        type = "select",
                        name = "Charge/Stack Position",
                        order = 23,
                        values = opts.POSITION_VALUES,
                        get = function() local db = GetDB(); return db and db.chargeTextPosition end,
                        set = function(_, val) local db = GetDB(); if db then db.chargeTextPosition = val; Refresh() end end,
                    },
                    chargeTextX = {
                        type = "range",
                        name = "Charge X Offset",
                        order = 24,
                        min = -100, max = 100, step = 1,
                        get = function() local db = GetDB(); return db and db.chargeTextX end,
                        set = function(_, val) local db = GetDB(); if db then db.chargeTextX = val; Refresh() end end,
                    },
                    chargeTextY = {
                        type = "range",
                        name = "Charge Y Offset",
                        order = 25,
                        min = -100, max = 100, step = 1,
                        get = function() local db = GetDB(); return db and db.chargeTextY end,
                        set = function(_, val) local db = GetDB(); if db then db.chargeTextY = val; Refresh() end end,
                    },
                },
            },
            -- ============================
            -- Row Sizes tab
            -- ============================
            rowSizes = {
                type = "group",
                name = "Row Sizes",
                order = 2,
                args = {},
            },
            -- ============================
            -- Clusters tab
            -- ============================
            clusters = {
                type = "group",
                name = "Clusters",
                order = 3,
                args = {
                    multiClusterMode = {
                        type = "toggle",
                        name = "Enable Multi-Cluster Mode",
                        order = 1,
                        width = "full",
                        get = function() local db = GetDB(); return db and db.multiClusterMode end,
                        set = function(_, val) local db = GetDB(); if db then db.multiClusterMode = val; Refresh() end end,
                    },
                    clusterCenterIcons = {
                        type = "toggle",
                        name = "Center Icons in Cluster",
                        order = 2,
                        hidden = function() local db = GetDB(); return not db or not db.multiClusterMode end,
                        get = function() local db = GetDB(); return db and db.clusterCenterIcons end,
                        set = function(_, val) local db = GetDB(); if db then db.clusterCenterIcons = val; Refresh() end end,
                    },
                    clusterUnlocked = {
                        type = "toggle",
                        name = "Unlock Cluster Boxes",
                        order = 3,
                        hidden = function() local db = GetDB(); return not db or not db.multiClusterMode end,
                        get = function() local db = GetDB(); return db and db.clusterUnlocked end,
                        set = function(_, val) local db = GetDB(); if db then db.clusterUnlocked = val; Refresh() end end,
                    },
                    clusterCount = {
                        type = "range",
                        name = "Number of Clusters",
                        order = 4,
                        min = 1, max = MAX_CLUSTERS, step = 1,
                        hidden = function() local db = GetDB(); return not db or not db.multiClusterMode end,
                        get = function() local db = GetDB(); return db and db.clusterCount or 1 end,
                        set = function(_, val) local db = GetDB(); if db then db.clusterCount = val; Refresh() end end,
                    },
                },
            },
            -- ============================
            -- Spell Assignments tab
            -- ============================
            spellAssignments = {
                type = "group",
                name = "Spell Assignments",
                order = 4,
                args = {
                    desc = {
                        type = "description",
                        name = "Assign spells to clusters. Click 'Refresh List' when you want to scan currently displayed cooldown viewer spells.",
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
                order = 5,
                args = {
                    refreshGlowList = {
                        type = "execute",
                        name = "Refresh Glow List",
                        desc = "Scan active Dynamic Icons for spells and add them to the glow list",
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
            -- ============================
            -- Spell Sounds tab
            -- ============================
            spellSounds = {
                type = "group",
                name = "Spell Sounds",
                order = 6,
                args = {
                    soundShowAll = {
                        type = "toggle",
                        name = "Show Full Sound List",
                        desc = "Toggle between a quick list (first 80 sounds) and the full paginated SharedMedia list.",
                        order = -3,
                        width = 1.0,
                        get = function() return soundShowAll end,
                        set = function(_, val)
                            soundShowAll = val and true or false
                            soundPage = 1
                            AceRegistry:NotifyChange("CkraigCooldownManager")
                        end,
                    },
                    soundPrevPage = {
                        type = "execute",
                        name = "< Prev Page",
                        desc = "Go to the previous page of sounds.",
                        order = -2.5,
                        width = 0.5,
                        hidden = function() return not soundShowAll or TrimString(soundSearchText) ~= "" end,
                        disabled = function() return soundPage <= 1 end,
                        func = function()
                            soundPage = math.max(1, soundPage - 1)
                            AceRegistry:NotifyChange("CkraigCooldownManager")
                        end,
                    },
                    soundPageInfo = {
                        type = "description",
                        name = function()
                            local totalKeys = #(BuildSoundKeyCache())
                            local totalPages = math.max(1, math.ceil(totalKeys / soundPageSize))
                            return "  Page " .. soundPage .. " / " .. totalPages .. "  (" .. totalKeys .. " sounds)  "
                        end,
                        order = -2.4,
                        width = 1.0,
                        hidden = function() return not soundShowAll or TrimString(soundSearchText) ~= "" end,
                    },
                    soundNextPage = {
                        type = "execute",
                        name = "Next Page >",
                        desc = "Go to the next page of sounds.",
                        order = -2.3,
                        width = 0.5,
                        hidden = function() return not soundShowAll or TrimString(soundSearchText) ~= "" end,
                        disabled = function()
                            local totalKeys = #(BuildSoundKeyCache())
                            local totalPages = math.max(1, math.ceil(totalKeys / soundPageSize))
                            return soundPage >= totalPages
                        end,
                        func = function()
                            local totalKeys = #(BuildSoundKeyCache())
                            local totalPages = math.max(1, math.ceil(totalKeys / soundPageSize))
                            soundPage = math.min(totalPages, soundPage + 1)
                            AceRegistry:NotifyChange("CkraigCooldownManager")
                        end,
                    },
                    soundSearch = {
                        type = "input",
                        name = "Search SharedMedia Sounds",
                        desc = "Type part of a sound name to filter the dropdown and reduce lag.",
                        order = -1,
                        width = "full",
                        get = function() return soundSearchText end,
                        set = function(_, val)
                            soundSearchText = TrimString(val)
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
                        desc = "Scan active Dynamic Icons for spells and add them to the sound list",
                        order = 0,
                        func = function() end, -- replaced below
                    },
                    addSound = {
                        type = "input",
                        name = "Add Spell ID for Sound",
                        order = 1,
                        width = "double",
                        set = function(_, val) end, -- replaced below
                        get = function() return "" end,
                    },
                },
            },
        },
    }

    -- ============================
    -- Spell Assignments: rebuild logic
    -- ============================
    local assignTab = CCM.AceOptionsTable.args.dynamicIcons.args.spellAssignments
    local RebuildAssignmentArgs

    local function GetConfiguredSpellList(db, forAssignments)
        db = db or GetDB()
        if db and db.showAllCooldownSettingsInOptions and _G.CCM_GetDynamicIconsAllSettingsSpellList then
            local items = _G.CCM_GetDynamicIconsAllSettingsSpellList()
            if type(items) == "table" then return items end
            return {}
        end

        if forAssignments then
            local getAssignmentList = _G.CCM_GetDynamicIconsAssignmentSpellList or _G.CCM_GetDynamicIconsSpellList
            if getAssignmentList then
                local items = getAssignmentList()
                if type(items) == "table" then return items end
            end
            return {}
        end

        local items = _G.CCM_GetDynamicIconsSpellList and _G.CCM_GetDynamicIconsSpellList() or {}
        if type(items) == "table" then return items end
        return {}
    end

    assignTab.args.showAllCooldownSettingsInOptions = {
        type = "toggle",
        name = "Show All Cooldowns From Settings",
        desc = "Include configured cooldown settings entries even when they are not currently visible as active icons.",
        order = 2,
        width = "full",
        get = function()
            local db = GetDB()
            return db and db.showAllCooldownSettingsInOptions or false
        end,
        set = function(_, val)
            local db = GetDB()
            if not db then return end
            db.showAllCooldownSettingsInOptions = val and true or false
            RebuildAssignmentArgs()
            AceRegistry:NotifyChange("CkraigCooldownManager")
        end,
    }
    assignTab.args.refreshList.order = 3
    assignTab.args.addSpell.order = 4

    RebuildAssignmentArgs = function()
        for k in pairs(assignTab.args) do
            if k:match("^spell_") then assignTab.args[k] = nil end
        end
        local db = GetDB()
        if not db then return end
        db.clusterAssignments = db.clusterAssignments or {}
        db.clusterSampleIconsByKey = db.clusterSampleIconsByKey or {}

        local items = {}
        local available = {}
        local live = GetConfiguredSpellList(db, true)
        if type(live) == "table" then
            for _, item in ipairs(live) do
                local skey = tostring(item.key)
                if skey and skey ~= "" and not available[skey] then
                    available[skey] = true
                    table.insert(items, item)
                    if item.icon and item.icon ~= "" then
                        db.clusterSampleIconsByKey[skey] = item.icon
                    end
                end
            end
        end

        table.sort(items, function(a, b) return (a.name or "") < (b.name or "") end)

        local clusterValues = {}
        for c = 1, MAX_CLUSTERS do clusterValues[c] = "Cluster " .. c end

        for idx, item in ipairs(items) do
            local skey = tostring(item.key)
            assignTab.args["spell_" .. skey] = {
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
                    cluster = {
                        type = "select",
                        name = "Cluster",
                        order = 2,
                        values = clusterValues,
                        width = 0.8,
                        get = function()
                            local d = GetDB()
                            return d and d.clusterAssignments and tonumber(d.clusterAssignments[skey]) or 1
                        end,
                        set = function(_, val)
                            local d = GetDB()
                            if d then
                                d.clusterAssignments = d.clusterAssignments or {}
                                d.clusterAssignments[skey] = val
                                if d.clusterDuplicates and d.clusterDuplicates[skey] then
                                    d.clusterDuplicates[skey][val] = nil
                                    local anyLeft = false
                                    for _ in pairs(d.clusterDuplicates[skey]) do
                                        anyLeft = true
                                        break
                                    end
                                    if not anyLeft then
                                        d.clusterDuplicates[skey] = nil
                                    end
                                end
                                Refresh()
                                RebuildAssignmentArgs()
                                AceRegistry:NotifyChange("CkraigCooldownManager")
                            end
                        end,
                    },
                    duplicates = {
                        type = "multiselect",
                        name = "Duplicate To",
                        order = 3,
                        width = 1.2,
                        values = function()
                            local d = GetDB()
                            local maxCount = d and tonumber(d.clusterCount) or 1
                            if maxCount < 1 then maxCount = 1 end
                            local primary = d and d.clusterAssignments and tonumber(d.clusterAssignments[skey]) or 1
                            local values = {}
                            for ci = 1, maxCount do
                                if ci ~= primary then
                                    values[ci] = "Cluster " .. ci
                                end
                            end
                            return values
                        end,
                        get = function(_, key)
                            local d = GetDB()
                            if not d then return false end
                            d.clusterDuplicates = d.clusterDuplicates or {}
                            local dup = d.clusterDuplicates[skey]
                            return dup and dup[key] and true or false
                        end,
                        set = function(_, key, val)
                            local d = GetDB()
                            if not d then return end
                            d.clusterDuplicates = d.clusterDuplicates or {}
                            d.clusterAssignments = d.clusterAssignments or {}
                            local primary = tonumber(d.clusterAssignments[skey]) or 1
                            key = tonumber(key)
                            if not key or key == primary then return end

                            d.clusterDuplicates[skey] = d.clusterDuplicates[skey] or {}
                            if val then
                                d.clusterDuplicates[skey][key] = true
                            else
                                d.clusterDuplicates[skey][key] = nil
                                local anyLeft = false
                                for _ in pairs(d.clusterDuplicates[skey]) do
                                    anyLeft = true
                                    break
                                end
                                if not anyLeft then
                                    d.clusterDuplicates[skey] = nil
                                end
                            end
                            Refresh()
                        end,
                    },
                    remove = {
                        type = "execute",
                        name = "Remove",
                        order = 4,
                        width = 0.5,
                        confirm = true,
                        func = function()
                            local d = GetDB()
                            if d then
                                if d.clusterAssignments then d.clusterAssignments[skey] = nil end
                                if d.clusterAlwaysShowSpells then d.clusterAlwaysShowSpells[skey] = nil end
                                if d.clusterDuplicates then d.clusterDuplicates[skey] = nil end
                                Refresh()
                                RebuildAssignmentArgs()
                                AceRegistry:NotifyChange("CkraigCooldownManager")
                            end
                        end,
                    },
                },
            }
        end
    end

    assignTab.args.refreshList.func = function()
        RebuildAssignmentArgs()
        AceRegistry:NotifyChange("CkraigCooldownManager")
    end

    assignTab.args.addSpell.set = function(_, val)
        local id = tonumber(val)
        if not id or id <= 0 then return end
        local db = GetDB()
        if not db then return end

        db.clusterAssignments = db.clusterAssignments or {}
        db.clusterSampleIconsByKey = db.clusterSampleIconsByKey or {}
        db.clusterAssignments[tostring(id)] = db.clusterAssignments[tostring(id)] or 1
        if C_Spell and C_Spell.GetSpellTexture then
            local icon = C_Spell.GetSpellTexture(id)
            if icon and icon ~= "" then
                db.clusterSampleIconsByKey[tostring(id)] = icon
            end
        end
        Refresh()
        RebuildAssignmentArgs()
        AceRegistry:NotifyChange("CkraigCooldownManager")
    end

    RebuildAssignmentArgs()

    -- ============================
    -- Spell Glows: rebuild logic
    -- ============================
    local glowTab = CCM.AceOptionsTable.args.dynamicIcons.args.spellGlows

    local function RebuildGlowArgs(useLiveScan)
        for k in pairs(glowTab.args) do
            if k:match("^glow_") then glowTab.args[k] = nil end
        end
        local db = GetDB()
        if not db or not db.spellGlows then return end

        local liveByKey = {}
        if useLiveScan then
            local live = GetConfiguredSpellList(db, false)
            if type(live) == "table" then
                for _, item in ipairs(live) do
                    local skey = tostring(item.key)
                    if skey and skey ~= "" then
                        liveByKey[skey] = item
                    end
                end
            end
        end

        local sorted = {}
        for key, cfg in pairs(db.spellGlows) do
            if type(cfg) == "table" and (not useLiveScan or liveByKey[tostring(key)]) then
                table.insert(sorted, key)
            end
        end
        table.sort(sorted, function(a, b)
            local na = tonumber(a)
            local nb = tonumber(b)
            if na and nb then return na < nb end
            return tostring(a) < tostring(b)
        end)

        for idx, skey in ipairs(sorted) do
            local liveItem = liveByKey[tostring(skey)]
            local spellName = (liveItem and liveItem.name) or ("Cooldown " .. skey)
            local spellIcon = liveItem and liveItem.icon or nil
            local numericID = tonumber(skey)
            if not spellIcon and numericID and C_Spell and C_Spell.GetSpellTexture then
                spellIcon = C_Spell.GetSpellTexture(numericID)
            end

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
                                d.spellGlows[skey].enabled = val
                                Refresh()
                            end
                        end,
                    },
                    readyOnlyText = {
                        type = "description",
                        name = "Enable Glow Ready",
                        order = 3,
                        width = "full",
                        fontSize = "medium",
                    },
                    glowType = {
                        type = "select",
                        name = "Glow Type",
                        order = 4,
                        values = { pixel = "Pixel", autocast = "Autocast", button = "Button", proc = "Proc" },
                        width = 0.7,
                        get = function()
                            local d = GetDB()
                            local g = d and d.spellGlows and d.spellGlows[skey]
                            return g and g.glowType or "pixel"
                        end,
                        set = function(_, val)
                            local d = GetDB()
                            if d and d.spellGlows and d.spellGlows[skey] then
                                d.spellGlows[skey].glowType = val
                                Refresh()
                            end
                        end,
                    },
                    color = {
                        type = "color",
                        name = "Color",
                        order = 5,
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
                                d.spellGlows[skey].color = { r = r, g = g, b = b, a = a }
                                Refresh()
                            end
                        end,
                    },
                    remove = {
                        type = "execute",
                        name = "Remove",
                        order = 6,
                        width = 0.5,
                        confirm = true,
                        func = function()
                            local d = GetDB()
                            if d and d.spellGlows then
                                d.spellGlows[skey] = nil
                                Refresh()
                                RebuildGlowArgs()
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
        local items = GetConfiguredSpellList(db, false)
        local available = {}
        for _, item in ipairs(items) do
            local skey = tostring(item.key)
            available[skey] = true
            if not db.spellGlows[skey] then
                db.spellGlows[skey] = { enabled = false, mode = "ready", glowType = "pixel", color = { r = 1, g = 1, b = 0, a = 1 } }
            end
        end
        for skey in pairs(db.spellGlows) do
            if not available[tostring(skey)] then
                db.spellGlows[skey] = nil
            end
        end
        RebuildGlowArgs(true)
        AceRegistry:NotifyChange("CkraigCooldownManager")
    end

    glowTab.args.addGlow.set = function(_, val)
        local id = tonumber(val)
        if not id or id <= 0 then return end
        local db = GetDB()
        if not db then return end

        local allowed = false
        local items = GetConfiguredSpellList(db, false)
        for _, item in ipairs(items) do
            if tostring(item.key) == tostring(id) then
                allowed = true
                break
            end
        end
        if not allowed then return end

        db.spellGlows = db.spellGlows or {}
        if not db.spellGlows[tostring(id)] then
            db.spellGlows[tostring(id)] = { enabled = true, mode = "ready", glowType = "pixel", color = { r = 1, g = 1, b = 0, a = 1 } }
        end
        Refresh()
        RebuildGlowArgs(true)
        AceRegistry:NotifyChange("CkraigCooldownManager")
    end

    RebuildGlowArgs(true)

    -- ============================
    -- Spell Sounds: rebuild logic
    -- ============================
    local soundTab = CCM.AceOptionsTable.args.dynamicIcons.args.spellSounds

    local function ResolveSoundPath(soundKey)
        if not soundKey or soundKey == "" then return nil end
        if LSM and LSM.Fetch then
            local ok, path = pcall(LSM.Fetch, LSM, "sound", soundKey, true)
            if ok and path and path ~= "" then
                return path
            end
        end
        return soundKey
    end

    local function RebuildSoundArgs(useLiveScan)
        for k in pairs(soundTab.args) do
            if k:match("^sound_") then soundTab.args[k] = nil end
        end
        local db = GetDB()
        if not db then return end
        db.spellSounds = db.spellSounds or {}

        local liveByKey = {}
        if useLiveScan then
            local live = GetConfiguredSpellList(db, false)
            if type(live) == "table" then
                for _, item in ipairs(live) do
                    local skey = tostring(item.key)
                    if skey and skey ~= "" then
                        liveByKey[skey] = item
                    end
                end
            end
        end

        local sorted = {}
        for key, cfg in pairs(db.spellSounds) do
            if type(cfg) == "table" and (not useLiveScan or liveByKey[tostring(key)]) then
                table.insert(sorted, key)
            end
        end
        table.sort(sorted, function(a, b)
            local na = tonumber(a)
            local nb = tonumber(b)
            if na and nb then return na < nb end
            return tostring(a) < tostring(b)
        end)

        for idx, skey in ipairs(sorted) do
            local liveItem = liveByKey[tostring(skey)]
            local spellName = (liveItem and liveItem.name) or ("Cooldown " .. skey)
            local spellIcon = liveItem and liveItem.icon or nil
            local numericID = tonumber(skey)
            if not spellIcon and numericID and C_Spell and C_Spell.GetSpellTexture then
                spellIcon = C_Spell.GetSpellTexture(numericID)
            end

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
                                TouchSpellSoundConfig(d)
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
                                TouchSpellSoundConfig(d)
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
                                TouchSpellSoundConfig(d)
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
                            return GetFilteredSoundValues(current)
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
                                TouchSpellSoundConfig(d)
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
                                TouchSpellSoundConfig(d)
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
                                local soundPath = ResolveSoundPath(s.sound)
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
                                TouchSpellSoundConfig(d)
                                Refresh()
                                RebuildSoundArgs()
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
        soundKeyCache = nil
        db.spellSounds = db.spellSounds or {}

        local items = GetConfiguredSpellList(db, false)
        local available = {}
        for _, item in ipairs(items) do
            local skey = tostring(item.key)
            available[skey] = true
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
            if not available[tostring(skey)] then
                db.spellSounds[skey] = nil
            end
        end

        TouchSpellSoundConfig(db)
        RebuildSoundArgs(true)
        AceRegistry:NotifyChange("CkraigCooldownManager")
    end

    soundTab.args.addSound.set = function(_, val)
        local id = tonumber(val)
        if not id or id <= 0 then return end
        local db = GetDB()
        if not db then return end

        local allowed = false
        local items = GetConfiguredSpellList(db, false)
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
        TouchSpellSoundConfig(db)
        Refresh()
        RebuildSoundArgs(true)
        AceRegistry:NotifyChange("CkraigCooldownManager")
    end

    RebuildSoundArgs(true)

    -- Generate row-size sliders (up to 10 rows)
    local rowArgs = CCM.AceOptionsTable.args.dynamicIcons.args.rowSizes.args
    for i = 1, 10 do
        rowArgs["row" .. i] = {
            type = "range",
            name = "Row " .. i .. " Size",
            order = i,
            min = 1, max = 200, step = 1,
            get = function()
                local db = GetDB()
                return db and db.rowSizes and db.rowSizes[i] or db.iconSize or 36
            end,
            set = function(_, val)
                local db = GetDB()
                if db then
                    db.rowSizes = db.rowSizes or {}
                    db.rowSizes[i] = val
                    Refresh()
                end
            end,
        }
    end

    -- Generate per-cluster controls
    local clusterArgs = CCM.AceOptionsTable.args.dynamicIcons.args.clusters.args
    for i = 1, MAX_CLUSTERS do
        clusterArgs["cluster" .. i] = {
            type = "group",
            name = "Cluster " .. i,
            order = 10 + i,
            inline = true,
            hidden = function()
                local db = GetDB()
                return not db or not db.multiClusterMode or (db.clusterCount or 1) < i
            end,
            args = {
                iconSize = {
                    type = "range",
                    name = "Icon Size",
                    order = 1,
                    min = 8, max = 128, step = 1,
                    get = function()
                        local db = GetDB()
                        return db and db.clusterIconSizes and db.clusterIconSizes[i] or db.iconSize or 36
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterIconSizes = db.clusterIconSizes or {}
                            db.clusterIconSizes[i] = val
                            Refresh()
                        end
                    end,
                },
                flow = {
                    type = "select",
                    name = "Flow Direction",
                    order = 2,
                    values = opts.FLOW_VALUES,
                    get = function()
                        local db = GetDB()
                        return db and db.clusterFlows and db.clusterFlows[i] or "horizontal"
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
                horizontalSpacing = {
                    type = "range",
                    name = "Horizontal Spacing",
                    order = 3,
                    min = 0, max = 100, step = 1,
                    get = function()
                        local db = GetDB()
                        if not db then return 0 end
                        return db.clusterHorizontalSpacings and db.clusterHorizontalSpacings[i] or db.spacing or 0
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterHorizontalSpacings = db.clusterHorizontalSpacings or {}
                            db.clusterHorizontalSpacings[i] = val
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
                        return db and db.clusterVerticalGrows and db.clusterVerticalGrows[i] or "down"
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterVerticalGrows = db.clusterVerticalGrows or {}
                            db.clusterVerticalGrows[i] = val
                            Refresh()
                        end
                    end,
                },
                pin = {
                    type = "select",
                    name = "Vertical Pin",
                    order = 5,
                    values = { top = "Pin Top", center = "Pin Center", bottom = "Pin Bottom" },
                    get = function()
                        local db = GetDB()
                        return db and db.clusterVerticalPins and db.clusterVerticalPins[i] or "top"
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterVerticalPins = db.clusterVerticalPins or {}
                            db.clusterVerticalPins[i] = val
                            Refresh()
                        end
                    end,
                },
                displayMode = {
                    type = "select",
                    name = "Display Mode",
                    order = 6,
                    values = { off = "Hide Inactive", always = "Show Inactive" },
                    get = function()
                        local db = GetDB()
                        return db and db.clusterSampleDisplayModes and db.clusterSampleDisplayModes[i] or "off"
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterSampleDisplayModes = db.clusterSampleDisplayModes or {}
                            db.clusterSampleDisplayModes[i] = val
                            Refresh()
                        end
                    end,
                },
                headerClusterText = {
                    type = "header",
                    name = "Text Overrides",
                    order = 10,
                },
                cooldownTextSize = {
                    type = "range",
                    name = "Cooldown Text Size",
                    desc = "Per-cluster override. Set to 0 to use the global value.",
                    order = 11,
                    min = 0, max = 36, step = 1,
                    get = function()
                        local db = GetDB()
                        return db and db.clusterCooldownTextSizes and db.clusterCooldownTextSizes[i] or 0
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterCooldownTextSizes = db.clusterCooldownTextSizes or {}
                            db.clusterCooldownTextSizes[i] = val > 0 and val or nil
                            Refresh()
                        end
                    end,
                },
                cooldownTextColor = {
                    type = "color",
                    name = "Cooldown Text Color",
                    desc = "Per-cluster override for cooldown number color. Reset removes the override.",
                    order = 12,
                    hasAlpha = true,
                    get = function()
                        local db = GetDB()
                        local c = db and db.clusterCooldownTextColors and db.clusterCooldownTextColors[i]
                        if c then return c.r or 1, c.g or 1, c.b or 1, c.a or 1 end
                        return 1, 1, 1, 1
                    end,
                    set = function(_, r, g, b, a)
                        local db = GetDB()
                        if db then
                            db.clusterCooldownTextColors = db.clusterCooldownTextColors or {}
                            db.clusterCooldownTextColors[i] = { r = r, g = g, b = b, a = a }
                            Refresh()
                        end
                    end,
                },
                chargeTextSize = {
                    type = "range",
                    name = "Charge Text Size",
                    desc = "Per-cluster override. Set to 0 to use the global value.",
                    order = 13,
                    min = 0, max = 72, step = 1,
                    get = function()
                        local db = GetDB()
                        return db and db.clusterChargeTextSizes and db.clusterChargeTextSizes[i] or 0
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterChargeTextSizes = db.clusterChargeTextSizes or {}
                            db.clusterChargeTextSizes[i] = val > 0 and val or nil
                            Refresh()
                        end
                    end,
                },
                chargeTextColor = {
                    type = "color",
                    name = "Charge Text Color",
                    desc = "Per-cluster override for charge/stack number color. Reset removes the override.",
                    order = 14,
                    hasAlpha = true,
                    get = function()
                        local db = GetDB()
                        local c = db and db.clusterChargeTextColors and db.clusterChargeTextColors[i]
                        if c then return c.r or 1, c.g or 1, c.b or 1, c.a or 1 end
                        return 1, 1, 1, 1
                    end,
                    set = function(_, r, g, b, a)
                        local db = GetDB()
                        if db then
                            db.clusterChargeTextColors = db.clusterChargeTextColors or {}
                            db.clusterChargeTextColors[i] = { r = r, g = g, b = b, a = a }
                            Refresh()
                        end
                    end,
                },
            },
        }
    end
end
