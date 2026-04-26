-- ============================================================
-- CkraigCooldownManager :: UI :: Options :: Utility Buffs
-- ============================================================
-- AceConfig options table for the Utility Buff Tracker.
-- Replaces MyUtilityBuffTracker.CreateOptionsPanel.
-- ============================================================

local CCM = _G.CkraigCooldownManager
local AceRegistry = LibStub("AceConfigRegistry-3.0")
local LSM = LibStub("LibSharedMedia-3.0", true)
local ubtSoundKeyCache = nil
local ubtSoundSearchText = ""
local ubtSoundLsmCallbackRegistered = false
local ubtSoundShowAll = true
local ubtSoundPage = 1
local ubtSoundPageSize = 150

local function TrimString_UBT_Opts(s)
    if type(s) ~= "string" then return "" end
    return s:match("^%s*(.-)%s*$") or ""
end

local function BuildSoundKeyCache_UBT_Opts()
    if ubtSoundKeyCache then return ubtSoundKeyCache end
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
    ubtSoundKeyCache = keys
    return ubtSoundKeyCache
end

local function GetFilteredSoundValues_UBT_Opts(currentValue)
    local values = {}
    local keys = BuildSoundKeyCache_UBT_Opts()
    local query = TrimString_UBT_Opts(ubtSoundSearchText):lower()
    local hasSearch = (query ~= "")

    if hasSearch then
        for _, key in ipairs(keys) do
            if key:lower():find(query, 1, true) then
                values[key] = key
            end
        end
    elseif ubtSoundShowAll then
        local totalKeys = #keys
        local totalPages = math.max(1, math.ceil(totalKeys / ubtSoundPageSize))
        if ubtSoundPage > totalPages then ubtSoundPage = totalPages end
        if ubtSoundPage < 1 then ubtSoundPage = 1 end
        local startIdx = (ubtSoundPage - 1) * ubtSoundPageSize + 1
        local endIdx = math.min(startIdx + ubtSoundPageSize - 1, totalKeys)
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

local function RegisterSoundMediaCallback_UBT_Opts()
    if ubtSoundLsmCallbackRegistered or not (LSM and LSM.RegisterCallback) then
        return
    end
    ubtSoundLsmCallbackRegistered = true
    LSM:RegisterCallback("LibSharedMedia_Registered", function(_, mediaType)
        if mediaType == "sound" then
            ubtSoundKeyCache = nil
            AceRegistry:NotifyChange("CkraigCooldownManager")
        end
    end)
end

local function GetDB()
    if MyUtilityBuffTracker and MyUtilityBuffTracker.GetSettings then
        return MyUtilityBuffTracker:GetSettings()
    end
    return CCM.AceOpts.GetProfileData("utilityBuffs")
end

local function TouchSpellSoundConfig_UBT_Opts(db)
    db = db or GetDB()
    if not db then return end
    db.spellSoundsRevision = (tonumber(db.spellSoundsRevision) or 0) + 1
end

local function Refresh()
    if MyUtilityBuffTracker and MyUtilityBuffTracker.RefreshUtilityLayout then
        MyUtilityBuffTracker:RefreshUtilityLayout()
    end
end

function CCM.BuildUtilityBuffsOptions()
    local opts = CCM.AceOpts

    RegisterSoundMediaCallback_UBT_Opts()

    CCM.AceOptionsTable.args.utilityBuffs = {
        type = "group",
        name = "Utility Buffs",
        order = 40,
        childGroups = "tab",
        args = {
            general = {
                type = "group",
                name = "General",
                order = 1,
                args = {
                    enabled = {
                        type = "toggle",
                        name = "Enable Utility Tracker",
                        order = 1,
                        width = "full",
                        get = function() local db = GetDB(); return db and db.enabled end,
                        set = function(_, val) local db = GetDB(); if db then db.enabled = val; Refresh() end end,
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
                                if MyUtilityBuffTracker and MyUtilityBuffTracker.RefreshVisibility then
                                    MyUtilityBuffTracker:RefreshVisibility()
                                end
                            end
                        end,
                    },
                    assistedCombatHighlight = {
                        type = "toggle",
                        name = "Show Assisted Combat Highlight",
                        desc = "Show the blue rotation helper glow on icons that match Blizzard's assisted combat recommendation.",
                        order = 3,
                        get = function() local db = GetDB(); return db and db.assistedCombatHighlight end,
                        set = function(_, val) local db = GetDB(); if db then db.assistedCombatHighlight = val end end,
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
                    aspectRatioCrop = {
                        type = "range",
                        name = "Aspect Ratio",
                        order = 12,
                        min = 0.1, max = 5.0, step = 0.01,
                        get = function() local db = GetDB(); return db and db.aspectRatioCrop or 1.0 end,
                        set = function(_, val) local db = GetDB(); if db then db.aspectRatioCrop = val; Refresh() end end,
                    },
                    iconCornerRadius = {
                        type = "range",
                        name = "Corner Radius",
                        order = 13,
                        min = 0, max = 20, step = 1,
                        get = function() local db = GetDB(); return db and db.iconCornerRadius end,
                        set = function(_, val) local db = GetDB(); if db then db.iconCornerRadius = val; Refresh() end end,
                    },
                    spacing = {
                        type = "range",
                        name = "Horizontal Spacing",
                        order = 14,
                        min = 0, max = 40, step = 1,
                        get = function() local db = GetDB(); return db and db.spacing end,
                        set = function(_, val) local db = GetDB(); if db then db.spacing = val; Refresh() end end,
                    },
                    columns = {
                        type = "range",
                        name = "Icons Per Row",
                        order = 15,
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
                        name = "Charge/Stack Text Size",
                        order = 22,
                        min = 1, max = 100, step = 1,
                        get = function() local db = GetDB(); return db and db.chargeTextSize end,
                        set = function(_, val) local db = GetDB(); if db then db.chargeTextSize = val; Refresh() end end,
                    },
                    chargeTextPosition = {
                        type = "select",
                        name = "Charge Position",
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
        },
    }

    -- Generate row-size sliders
    local rowArgs = CCM.AceOptionsTable.args.utilityBuffs.args.rowSizes.args
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

    -- ============================
    -- Spell Glows tab
    -- ============================
    local GLOW_MODES = { ready = "When Ready", cooldown = "On Cooldown" }
    local GLOW_TYPES = { pixel = "Pixel", autocast = "Autocast", button = "Button Glow", proc = "Proc Glow" }

    local glowTab = {
        type = "group",
        name = "Spell Glows",
        order = 3,
        args = {
            refreshList = {
                type = "execute",
                name = "Refresh Spell List from Viewer",
                desc = "Scan UtilityCooldownViewer for active spells and add them to the glow list",
                order = 0,
                func = function()
                    local db = GetDB()
                    if not db then return end
                    db.spellGlows = db.spellGlows or {}
                    local items = _G.CCM_GetUtilitySpellList and _G.CCM_GetUtilitySpellList() or {}
                    local available = {}
                    for _, item in ipairs(items) do
                        local skey = tonumber(item.key)
                        if skey then
                            available[tostring(skey)] = true
                            if not db.spellGlows[skey] then
                                db.spellGlows[skey] = { enabled = false, mode = "ready", glowType = "pixel", color = { r = 1, g = 1, b = 0, a = 1 } }
                            end
                        end
                    end
                    for skey in pairs(db.spellGlows) do
                        if not available[tostring(skey)] then
                            db.spellGlows[skey] = nil
                        end
                    end
                    CCM._RebuildUtilityGlowArgs(glowTab)
                    AceRegistry:NotifyChange("CkraigCooldownManager")
                end,
            },
            addGlow = {
                type = "input",
                name = "Add Spell ID for Glow",
                desc = "Enter a spell ID to configure a custom glow",
                order = 1,
                width = "double",
                get = function() return "" end,
                set = function(_, val)
                    local id = tonumber(val)
                    if not id then return end
                    local db = GetDB()
                    if db then
                        local allowed = false
                        local items = _G.CCM_GetUtilitySpellList and _G.CCM_GetUtilitySpellList() or {}
                        for _, item in ipairs(items) do
                            if tostring(item.key) == tostring(id) then
                                allowed = true
                                break
                            end
                        end
                        if not allowed then return end

                        db.spellGlows = db.spellGlows or {}
                        if not db.spellGlows[id] then
                            db.spellGlows[id] = { enabled = true, mode = "ready", glowType = "pixel", color = { r = 1, g = 1, b = 0, a = 1 } }
                        end
                        Refresh()
                        CCM._RebuildUtilityGlowArgs(glowTab)
                        AceRegistry:NotifyChange("CkraigCooldownManager")
                    end
                end,
            },
            glowHeader = {
                type = "header",
                name = "Per-Spell Glow Overrides",
                order = 10,
            },
        },
    }

    local function RebuildGlowArgs(tab)
        tab = tab or glowTab
        if not tab then return end
        for k in pairs(tab.args) do
            if k:find("^glow_") or k == "emptyGlow" then
                tab.args[k] = nil
            end
        end

        local db = GetDB()
        if not db or not db.spellGlows then
            tab.args.emptyGlow = {
                type = "description",
                name = "|cff888888No per-spell glows configured. Add a spell ID above.|r",
                order = 100, fontSize = "medium",
            }
            return
        end

        local available = {}
        local items = _G.CCM_GetUtilitySpellList and _G.CCM_GetUtilitySpellList() or {}
        for _, item in ipairs(items) do
            if item and item.key ~= nil then
                available[tostring(item.key)] = true
            end
        end

        local order = 100
        local hasEntries = false
        for spellID, cfg in pairs(db.spellGlows) do
            if available[tostring(spellID)] then
                hasEntries = true
            local sid = tonumber(spellID) or 0

            local function getGlowName()
                if C_Spell and C_Spell.GetSpellName and sid > 0 then
                    local n = C_Spell.GetSpellName(sid)
                    if n then return n end
                end
                return "Spell " .. sid
            end

            tab.args["glow_" .. sid] = {
                type = "group",
                name = getGlowName,
                inline = true,
                order = order,
                args = {
                    icon = {
                        type = "description", name = "", order = 1,
                        image = function()
                            if C_Spell and C_Spell.GetSpellTexture and sid > 0 then
                                local tex = C_Spell.GetSpellTexture(sid)
                                if tex then return tex, 24, 24 end
                            end
                            return 134400, 24, 24
                        end,
                        width = 0.15,
                    },
                    enabled = {
                        type = "toggle", name = "Enabled", order = 2, width = 0.4,
                        get = function() return cfg.enabled end,
                        set = function(_, v) cfg.enabled = v; Refresh() end,
                    },
                    mode = {
                        type = "select", name = "Mode", order = 3, width = 0.5,
                        values = GLOW_MODES,
                        get = function() return cfg.mode or "ready" end,
                        set = function(_, v) cfg.mode = v; Refresh() end,
                    },
                    glowType = {
                        type = "select", name = "Type", order = 4, width = 0.5,
                        values = GLOW_TYPES,
                        get = function() return cfg.glowType or "pixel" end,
                        set = function(_, v) cfg.glowType = v; Refresh() end,
                    },
                    color = {
                        type = "color", name = "Color", order = 5, hasAlpha = true, width = 0.4,
                        get = function()
                            local c = cfg.color
                            if c then return c.r or 1, c.g or 1, c.b or 0, c.a or 1 end
                            return 1, 1, 0, 1
                        end,
                        set = function(_, r, g, b, a) cfg.color = { r = r, g = g, b = b, a = a }; Refresh() end,
                    },
                    remove = {
                        type = "execute", name = "Remove", order = 6, width = 0.4,
                        confirm = true, confirmText = "Remove glow for this spell?",
                        func = function()
                            local curDB = GetDB()
                            if curDB and curDB.spellGlows then
                                curDB.spellGlows[spellID] = nil
                            end
                            Refresh()
                            RebuildGlowArgs(tab)
                            AceRegistry:NotifyChange("CkraigCooldownManager")
                        end,
                    },
                },
            }
            order = order + 1
            end
        end

        if not hasEntries then
            tab.args.emptyGlow = {
                type = "description",
                name = "|cff888888No per-spell glows configured. Add a spell ID above.|r",
                order = 100, fontSize = "medium",
            }
        end
    end

    CCM._RebuildUtilityGlowArgs = RebuildGlowArgs
    RebuildGlowArgs(glowTab)
    CCM.AceOptionsTable.args.utilityBuffs.args.spellGlows = glowTab

    -- ============================
    -- Spell Sounds tab
    -- ============================
    local soundTab = {
        type = "group",
        name = "Spell Sounds",
        order = 4,
        args = {
            ubtSoundShowAllToggle = {
                type = "toggle",
                name = "Show Full Sound List",
                desc = "Toggle between a quick list (first 80 sounds) and the full paginated SharedMedia list.",
                order = -3,
                width = 1.0,
                get = function() return ubtSoundShowAll end,
                set = function(_, val)
                    ubtSoundShowAll = val and true or false
                    ubtSoundPage = 1
                    AceRegistry:NotifyChange("CkraigCooldownManager")
                end,
            },
            ubtSoundPrevPage = {
                type = "execute",
                name = "< Prev Page",
                order = -2.5,
                width = 0.5,
                hidden = function() return not ubtSoundShowAll or TrimString_UBT_Opts(ubtSoundSearchText) ~= "" end,
                disabled = function() return ubtSoundPage <= 1 end,
                func = function()
                    ubtSoundPage = math.max(1, ubtSoundPage - 1)
                    AceRegistry:NotifyChange("CkraigCooldownManager")
                end,
            },
            ubtSoundPageInfo = {
                type = "description",
                name = function()
                    local totalKeys = #(BuildSoundKeyCache_UBT_Opts())
                    local totalPages = math.max(1, math.ceil(totalKeys / ubtSoundPageSize))
                    return "  Page " .. ubtSoundPage .. " / " .. totalPages .. "  (" .. totalKeys .. " sounds)  "
                end,
                order = -2.4,
                width = 1.0,
                hidden = function() return not ubtSoundShowAll or TrimString_UBT_Opts(ubtSoundSearchText) ~= "" end,
            },
            ubtSoundNextPage = {
                type = "execute",
                name = "Next Page >",
                order = -2.3,
                width = 0.5,
                hidden = function() return not ubtSoundShowAll or TrimString_UBT_Opts(ubtSoundSearchText) ~= "" end,
                disabled = function()
                    local totalKeys = #(BuildSoundKeyCache_UBT_Opts())
                    local totalPages = math.max(1, math.ceil(totalKeys / ubtSoundPageSize))
                    return ubtSoundPage >= totalPages
                end,
                func = function()
                    local totalKeys = #(BuildSoundKeyCache_UBT_Opts())
                    local totalPages = math.max(1, math.ceil(totalKeys / ubtSoundPageSize))
                    ubtSoundPage = math.min(totalPages, ubtSoundPage + 1)
                    AceRegistry:NotifyChange("CkraigCooldownManager")
                end,
            },
            soundSearch = {
                type = "input",
                name = "Search SharedMedia Sounds",
                desc = "Type part of a sound name to filter the dropdown and reduce lag.",
                order = -1,
                width = "full",
                get = function() return ubtSoundSearchText end,
                set = function(_, val)
                    ubtSoundSearchText = TrimString_UBT_Opts(val)
                    AceRegistry:NotifyChange("CkraigCooldownManager")
                end,
            },
            soundSearchHelp = {
                type = "description",
                name = "Tip: Use Search to find sounds instantly. Enable 'Show Full Sound List' to browse all sounds with page controls.",
                order = -0.5,
                width = "full",
            },
            refreshList = {
                type = "execute",
                name = "Refresh Spell List from Viewer",
                desc = "Scan UtilityCooldownViewer for active spells and add them to the sound list",
                order = 0,
                func = function() end,
            },
            addSound = {
                type = "input",
                name = "Add Spell ID for Sound",
                desc = "Enter a spell ID to configure a custom sound",
                order = 1,
                width = "double",
                get = function() return "" end,
                set = function(_, val) end,
            },
            soundHeader = {
                type = "header",
                name = "Per-Spell Sound Overrides",
                order = 10,
            },
        },
    }

    local function ResolveSoundPath_UBT_Opts(soundKey)
        if not soundKey or soundKey == "" then return nil end
        if LSM and LSM.Fetch then
            local ok, path = pcall(LSM.Fetch, LSM, "sound", soundKey, true)
            if ok and path and path ~= "" then
                return path
            end
        end
        return soundKey
    end

    local function RebuildSoundArgs(tab)
        tab = tab or soundTab
        if not tab then return end
        for k in pairs(tab.args) do
            if k:find("^sound_") or k == "emptySound" then
                tab.args[k] = nil
            end
        end

        local db = GetDB()
        if not db then return end
        db.spellSounds = db.spellSounds or {}

        local available = {}
        local items = _G.CCM_GetUtilitySpellList and _G.CCM_GetUtilitySpellList() or {}
        for _, item in ipairs(items) do
            if item and item.key ~= nil then
                available[tostring(item.key)] = item
            end
        end

        local sorted = {}
        for key, cfg in pairs(db.spellSounds) do
            if type(cfg) == "table" and available[tostring(key)] then
                table.insert(sorted, key)
            end
        end
        table.sort(sorted, function(a, b)
            local aItem = available[tostring(a)]
            local bItem = available[tostring(b)]
            local aName = (aItem and aItem.name) or tostring(a)
            local bName = (bItem and bItem.name) or tostring(b)
            return aName < bName
        end)

        local order = 100
        local hasEntries = false
        for _, spellID in ipairs(sorted) do
            hasEntries = true
            local sid = tonumber(spellID) or 0
            local item = available[tostring(spellID)]
            local spellName = (item and item.name) or ("Spell " .. sid)
            local spellIcon = item and item.icon
            local cfg = db.spellSounds[tostring(spellID)]

            tab.args["sound_" .. sid] = {
                type = "group",
                name = spellName,
                inline = true,
                order = order,
                args = {
                    icon = {
                        type = "description", name = "", order = 1,
                        image = function()
                            if spellIcon then return spellIcon, 24, 24 end
                            if C_Spell and C_Spell.GetSpellTexture and sid > 0 then
                                local tex = C_Spell.GetSpellTexture(sid)
                                if tex then return tex, 24, 24 end
                            end
                            return 134400, 24, 24
                        end,
                        width = 0.15,
                    },
                    enabled = {
                        type = "toggle", name = "Enabled", order = 2, width = 0.4,
                        get = function() return cfg.enabled == true end,
                        set = function(_, v) cfg.enabled = v and true or false; TouchSpellSoundConfig_UBT_Opts(); Refresh() end,
                    },
                    mode = {
                        type = "select", name = "Trigger", order = 3, width = 0.65,
                        values = {
                            ready = "On Ready",
                            cooldown = "On Cooldown Start",
                            both = "On Ready + Cooldown",
                        },
                        get = function()
                            local mode = cfg.mode or "ready"
                            if mode == "show" then
                                mode = "ready"
                            elseif mode == "expire" then
                                mode = "cooldown"
                            end
                            return mode
                        end,
                        set = function(_, v) cfg.mode = v or "ready"; TouchSpellSoundConfig_UBT_Opts(); Refresh() end,
                    },
                    output = {
                        type = "select", name = "Output", order = 4, width = 0.65,
                        values = {
                            sound = "SharedMedia Sound",
                            tts = "TTS",
                            both = "Sound + TTS",
                        },
                        get = function() return cfg.output or "sound" end,
                        set = function(_, v) cfg.output = v or "sound"; TouchSpellSoundConfig_UBT_Opts(); Refresh() end,
                    },
                    sound = {
                        type = "select", name = "Sound", order = 5, width = 1.1,
                        hidden = function()
                            local output = cfg.output or "sound"
                            return output == "tts"
                        end,
                        values = function()
                            return GetFilteredSoundValues_UBT_Opts(cfg.sound)
                        end,
                        get = function() return cfg.sound or "" end,
                        set = function(_, v) cfg.sound = v or ""; TouchSpellSoundConfig_UBT_Opts(); Refresh() end,
                    },
                    ttsText = {
                        type = "input", name = "TTS Text", order = 6, width = 1.1,
                        desc = "Text spoken when TTS output is enabled. Leave empty to use spell name.",
                        hidden = function()
                            local output = cfg.output or "sound"
                            return output == "sound"
                        end,
                        get = function() return cfg.ttsText or "" end,
                        set = function(_, v) cfg.ttsText = tostring(v or ""); TouchSpellSoundConfig_UBT_Opts(); Refresh() end,
                    },
                    test = {
                        type = "execute", name = "Play", order = 7, width = 0.35,
                        func = function()
                            local output = tostring(cfg.output or "sound")
                            if (output == "sound" or output == "both") then
                                local path = ResolveSoundPath_UBT_Opts(cfg.sound)
                                if path then pcall(PlaySoundFile, path, "Master") end
                            end
                            if (output == "tts" or output == "both") and C_VoiceChat and C_VoiceChat.SpeakText and C_TTSSettings and C_TTSSettings.GetVoiceOptionID and Enum and Enum.TtsVoiceType then
                                local text = tostring(cfg.ttsText or "")
                                if text == "" then text = spellName end
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
                        type = "execute", name = "Remove", order = 8, width = 0.4,
                        confirm = true,
                        func = function()
                            local curDB = GetDB()
                            if curDB and curDB.spellSounds then
                                curDB.spellSounds[tostring(spellID)] = nil
                                TouchSpellSoundConfig_UBT_Opts(curDB)
                            end
                            Refresh()
                            RebuildSoundArgs(tab)
                            AceRegistry:NotifyChange("CkraigCooldownManager")
                        end,
                    },
                },
            }
            order = order + 1
        end

        if not hasEntries then
            tab.args.emptySound = {
                type = "description",
                name = "|cff888888No per-spell sounds configured. Add a spell ID above.|r",
                order = 100,
                fontSize = "medium",
            }
        end
    end

    soundTab.args.refreshList.func = function()
        local db = GetDB()
        if not db then return end
        ubtSoundKeyCache = nil
        db.spellSounds = db.spellSounds or {}
        local items = _G.CCM_GetUtilitySpellList and _G.CCM_GetUtilitySpellList() or {}
        local available = {}
        for _, item in ipairs(items) do
            local skey = tonumber(item.key)
            if skey then
                local key = tostring(skey)
                available[key] = true
                if not db.spellSounds[key] then
                    db.spellSounds[key] = { enabled = false, sound = "", output = "sound", ttsText = "", mode = "ready" }
                elseif db.spellSounds[key].mode == nil or db.spellSounds[key].mode == "" then
                    db.spellSounds[key].mode = "ready"
                elseif db.spellSounds[key].mode == "show" then
                    db.spellSounds[key].mode = "ready"
                elseif db.spellSounds[key].mode == "expire" then
                    db.spellSounds[key].mode = "cooldown"
                end
                if db.spellSounds[key].output == nil or db.spellSounds[key].output == "" then
                    db.spellSounds[key].output = "sound"
                end
                if type(db.spellSounds[key].ttsText) ~= "string" then
                    db.spellSounds[key].ttsText = ""
                end
            end
        end
        for skey in pairs(db.spellSounds) do
            if not available[tostring(skey)] then
                db.spellSounds[skey] = nil
            end
        end
        TouchSpellSoundConfig_UBT_Opts(db)
        RebuildSoundArgs(soundTab)
        AceRegistry:NotifyChange("CkraigCooldownManager")
    end

    soundTab.args.addSound.set = function(_, val)
        local id = tonumber(val)
        if not id then return end
        local db = GetDB()
        if not db then return end
        local allowed = false
        local items = _G.CCM_GetUtilitySpellList and _G.CCM_GetUtilitySpellList() or {}
        for _, item in ipairs(items) do
            if tostring(item.key) == tostring(id) then
                allowed = true
                break
            end
        end
        if not allowed then return end

        db.spellSounds = db.spellSounds or {}
        local skey = tostring(id)
        if not db.spellSounds[skey] then
            db.spellSounds[skey] = { enabled = true, sound = "", output = "sound", ttsText = "", mode = "ready" }
        elseif db.spellSounds[skey].mode == nil or db.spellSounds[skey].mode == "" then
            db.spellSounds[skey].mode = "ready"
        elseif db.spellSounds[skey].mode == "show" then
            db.spellSounds[skey].mode = "ready"
        elseif db.spellSounds[skey].mode == "expire" then
            db.spellSounds[skey].mode = "cooldown"
        end
        if db.spellSounds[skey].output == nil or db.spellSounds[skey].output == "" then
            db.spellSounds[skey].output = "sound"
        end
        if type(db.spellSounds[skey].ttsText) ~= "string" then
            db.spellSounds[skey].ttsText = ""
        end
        TouchSpellSoundConfig_UBT_Opts(db)
        Refresh()
        RebuildSoundArgs(soundTab)
        AceRegistry:NotifyChange("CkraigCooldownManager")
    end

    CCM._RebuildUtilitySoundArgs = RebuildSoundArgs
    RebuildSoundArgs(soundTab)
    CCM.AceOptionsTable.args.utilityBuffs.args.spellSounds = soundTab

    -- ============================
    -- Cooldown Override tab (Utility)
    -- ============================
    local cdOverrideTab = {
        type = "group",
        name = "CD Override",
        order = 6,
        args = {
            desc = {
                type = "description",
                name = "For selected spells, replace Blizzard's buff/aura timer with the actual spell cooldown on the CooldownViewer icons.",
                order = 0,
                fontSize = "medium",
            },
            refreshList = {
                type = "execute",
                name = "Refresh Spell List from Viewer",
                desc = "Scan UtilityCooldownViewer for active spells",
                order = 1,
                func = function()
                    local db = GetDB()
                    if not db then return end
                    db.cooldownOverrideSpells = db.cooldownOverrideSpells or {}
                    local items = _G.CCM_GetUtilitySpellList and _G.CCM_GetUtilitySpellList() or {}
                    for _, item in ipairs(items) do
                        local skey = tonumber(item.key)
                        if skey then
                            local key = tostring(skey)
                            if db.cooldownOverrideSpells[key] == nil then
                                db.cooldownOverrideSpells[key] = false
                            end
                        end
                    end
                    -- Remove spells no longer in viewer
                    local available = {}
                    for _, item in ipairs(items) do
                        if item.key then available[tostring(item.key)] = true end
                    end
                    for skey in pairs(db.cooldownOverrideSpells) do
                        if not available[tostring(skey)] then
                            db.cooldownOverrideSpells[skey] = nil
                        end
                    end
                    Refresh()
                    CCM._RebuildUtilityCDOverrideArgs(cdOverrideTab)
                    AceRegistry:NotifyChange("CkraigCooldownManager")
                end,
            },
            overrideHeader = {
                type = "header",
                name = "Per-Spell Cooldown Overrides",
                order = 10,
            },
        },
    }

    local function RebuildCDOverrideArgs(tab)
        tab = tab or cdOverrideTab
        if not tab then return end
        for k in pairs(tab.args) do
            if k:find("^cdor_") or k == "emptyCDOverride" then
                tab.args[k] = nil
            end
        end

        local db = GetDB()
        if not db or not db.cooldownOverrideSpells then
            tab.args.emptyCDOverride = {
                type = "description",
                name = "|cff888888No spells found. Click Refresh to scan the viewer.|r",
                order = 100,
                fontSize = "medium",
            }
            return
        end

        local available = {}
        local items = _G.CCM_GetUtilitySpellList and _G.CCM_GetUtilitySpellList() or {}
        for _, item in ipairs(items) do
            if item and item.key ~= nil then
                available[tostring(item.key)] = true
            end
        end

        local order = 100
        local hasEntries = false
        for spellID, enabled in pairs(db.cooldownOverrideSpells) do
            if available[tostring(spellID)] then
                hasEntries = true
                local sid = tonumber(spellID) or 0
                local key = "cdor_" .. sid

                local function getSpellName()
                    if C_Spell and C_Spell.GetSpellName and sid > 0 then
                        local n = C_Spell.GetSpellName(sid)
                        if n then return n end
                    end
                    return "Spell " .. sid
                end

                tab.args[key] = {
                    type = "group",
                    name = getSpellName,
                    inline = true,
                    order = order,
                    args = {
                        icon = {
                            type = "description", name = "", order = 1,
                            image = function()
                                if C_Spell and C_Spell.GetSpellTexture and sid > 0 then
                                    local tex = C_Spell.GetSpellTexture(sid)
                                    if tex then return tex, 24, 24 end
                                end
                                return 134400, 24, 24
                            end,
                            width = 0.15,
                        },
                        enabled = {
                            type = "toggle",
                            name = "Show Actual Cooldown",
                            desc = "Replace aura/buff timer with the real spell cooldown.",
                            order = 2,
                            width = 1.2,
                            get = function() return db.cooldownOverrideSpells[tostring(sid)] == true end,
                            set = function(_, val)
                                db.cooldownOverrideSpells[tostring(sid)] = val
                                Refresh()
                            end,
                        },
                    },
                }
                order = order + 1
            end
        end

        if not hasEntries then
            tab.args.emptyCDOverride = {
                type = "description",
                name = "|cff888888No spells found. Click Refresh to scan the viewer.|r",
                order = 100,
                fontSize = "medium",
            }
        end
    end

    CCM._RebuildUtilityCDOverrideArgs = RebuildCDOverrideArgs
    RebuildCDOverrideArgs(cdOverrideTab)
    CCM.AceOptionsTable.args.utilityBuffs.args.cdOverride = cdOverrideTab

    -- ============================================================
    -- CLUSTERS tab
    -- ============================================================
    local MAX_CLUSTERS = 20

    CCM.AceOptionsTable.args.utilityBuffs.args.clusters = {
        type = "group",
        name = "Clusters",
        order = 5,
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
            clusterUnlockedNote = {
                type = "description",
                name = function()
                    local db = GetDB()
                    local anyFree = false
                    if db and db.clusterFreePositionModes then
                        for _, v in pairs(db.clusterFreePositionModes) do
                            if v then anyFree = true; break end
                        end
                    end
                    if anyFree then
                        return "|cFFFFD700Free Position Mode active:|r Unlock Cluster Boxes, then |cFFFFFFFFright-click|r an icon to select it (yellow glow). Use |cFFFFFFFFArrow Keys|r to nudge 1px, |cFFFFFFFFShift+Arrow|r for 10px. Right-click again or press Escape to deselect."
                    end
                    return ""
                end,
                order = 2.5,
                width = "full",
                hidden = function()
                    local db = GetDB()
                    if not db or not db.multiClusterMode then return true end
                    if db.clusterFreePositionModes then
                        for _, v in pairs(db.clusterFreePositionModes) do
                            if v then return false end
                        end
                    end
                    return true
                end,
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
    }

    -- Generate per-cluster controls
    local clusterArgs = CCM.AceOptionsTable.args.utilityBuffs.args.clusters.args
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
                    min = 1, max = 200, step = 1,
                    get = function()
                        local db = GetDB()
                        return db and db.clusterIconSizes and db.clusterIconSizes[i] or (db and db.iconSize) or 36
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
                freePositionMode = {
                    type = "toggle",
                    name = "Free Position Icons",
                    desc = "Right-click icons to select them, then nudge with Arrow Keys. Left-click drag also positions freely.",
                    order = 3,
                    get = function()
                        local db = GetDB()
                        return db and db.clusterFreePositionModes and db.clusterFreePositionModes[i] or false
                    end,
                    set = function(_, val)
                        local db = GetDB()
                        if db then
                            db.clusterFreePositionModes = db.clusterFreePositionModes or {}
                            db.clusterFreePositionModes[i] = val
                            Refresh()
                        end
                    end,
                },
                sampleDisplayMode = {
                    type = "select",
                    name = "Show Anchor When Locked",
                    desc = "Show this cluster's box even when Unlock Cluster Boxes is off, so you can see placement without editing.",
                    order = 4,
                    values = { off = "Off", always = "Always" },
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
            },
        }
    end

    -- ============================================================
    -- SPELL ASSIGNMENTS tab
    -- ============================================================
    CCM.AceOptionsTable.args.utilityBuffs.args.spellAssignments = {
        type = "group",
        name = "Spell Assignments",
        order = 7,
        hidden = function() local db = GetDB(); return not db or not db.multiClusterMode end,
        args = {
            desc = {
                type = "description",
                name = "Assign spells to clusters. Use 'Refresh List' to scan current spells from the cooldown viewer.",
                order = 1,
            },
            refreshList = {
                type = "execute",
                name = "Refresh List",
                order = 2,
                func = function() end,
            },
            addSpell = {
                type = "input",
                name = "Add Spell ID",
                order = 3,
                width = "double",
                set = function(_, val) end,
                get = function() return "" end,
            },
        },
    }

    local assignTab = CCM.AceOptionsTable.args.utilityBuffs.args.spellAssignments

    local function EnsureUBTClusterManualOrders(db)
        db.clusterManualOrders = db.clusterManualOrders or {}
        return db.clusterManualOrders
    end

    local function GetUBTClusterOrderList(db, clusterIndex)
        local orders = EnsureUBTClusterManualOrders(db)
        orders[clusterIndex] = orders[clusterIndex] or {}
        return orders[clusterIndex]
    end

    local function RemoveKeyFromAllUBTClusterOrders_Opts(db, key)
        local normalized = tostring(key)
        local orders = EnsureUBTClusterManualOrders(db)
        for _, orderList in pairs(orders) do
            if type(orderList) == "table" then
                for j = #orderList, 1, -1 do
                    if tostring(orderList[j]) == normalized then table.remove(orderList, j) end
                end
            end
        end
    end

    local function AddKeyToUBTClusterOrderEnd(db, clusterIndex, key)
        local normalized = tostring(key)
        local orderList = GetUBTClusterOrderList(db, clusterIndex)
        for _, existing in ipairs(orderList) do
            if tostring(existing) == normalized then return end
        end
        table.insert(orderList, normalized)
    end

    local function GetKeyPosInUBTClusterOrder(db, clusterIndex, key)
        local normalized = tostring(key)
        local orderList = GetUBTClusterOrderList(db, clusterIndex)
        for idx, existing in ipairs(orderList) do
            if tostring(existing) == normalized then return idx, #orderList end
        end
        return nil, #orderList
    end

    local function MoveKeyInUBTClusterOrder(db, clusterIndex, key, direction)
        local normalized = tostring(key)
        local orderList = GetUBTClusterOrderList(db, clusterIndex)
        local fromIndex
        for idx, existing in ipairs(orderList) do
            if tostring(existing) == normalized then fromIndex = idx; break end
        end
        if not fromIndex then
            table.insert(orderList, normalized)
            fromIndex = #orderList
        end
        local toIndex = fromIndex + (direction or 0)
        if toIndex < 1 or toIndex > #orderList then return false end
        orderList[fromIndex], orderList[toIndex] = orderList[toIndex], orderList[fromIndex]
        return true
    end

    local function RebuildUBTAssignmentArgs()
        for k in pairs(assignTab.args) do
            if k:match("^spell_") then assignTab.args[k] = nil end
        end

        local db = GetDB()
        if not db then return end
        db.clusterAssignments  = db.clusterAssignments  or {}
        db.clusterManualOrders = db.clusterManualOrders or {}

        local items = {}
        local available = {}
        local getList = _G.CCM_GetUtilitySpellList
        if getList then
            local live = getList()
            if type(live) == "table" then
                for _, item in ipairs(live) do
                    local skey = tostring(item.key)
                    if skey and skey ~= "" and not available[skey] then
                        available[skey] = true
                        table.insert(items, item)
                    end
                end
            end
        end

        -- Keep saved assignments visible even if not currently active in the viewer
        for key in pairs(db.clusterAssignments) do
            local skey = tostring(key)
            if skey ~= "" and not available[skey] then
                local id = tonumber(skey)
                local name = id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
                local icon = id and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
                table.insert(items, { key = skey, name = name or ("Saved Spell " .. skey), icon = icon })
                available[skey] = true
            end
        end

        for key, assigned in pairs(db.clusterAssignments) do
            AddKeyToUBTClusterOrderEnd(db, tonumber(assigned) or 1, key)
        end
        for _, item in ipairs(items) do
            local skey = tostring(item.key)
            local assigned = tonumber(db.clusterAssignments[skey]) or 1
            AddKeyToUBTClusterOrderEnd(db, assigned, skey)
        end

        local orderIndexByCluster = {}
        for c = 1, MAX_CLUSTERS do
            orderIndexByCluster[c] = {}
            local orderList = GetUBTClusterOrderList(db, c)
            for idx, key in ipairs(orderList) do
                orderIndexByCluster[c][tostring(key)] = idx
            end
        end

        table.sort(items, function(a, b)
            local aKey = tostring(a.key); local bKey = tostring(b.key)
            local aCluster = tonumber(db.clusterAssignments[aKey]) or 1
            local bCluster = tonumber(db.clusterAssignments[bKey]) or 1
            if aCluster ~= bCluster then return aCluster < bCluster end
            local aPos = orderIndexByCluster[aCluster] and orderIndexByCluster[aCluster][aKey]
            local bPos = orderIndexByCluster[bCluster] and orderIndexByCluster[bCluster][bKey]
            if aPos and bPos and aPos ~= bPos then return aPos < bPos end
            if aPos and not bPos then return true end
            if bPos and not aPos then return false end
            return (a.name or "") < (b.name or "")
        end)

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
                        imageWidth = 24, imageHeight = 24,
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
                                local oldCluster = tonumber(d.clusterAssignments[skey]) or 1
                                d.clusterAssignments[skey] = val
                                if oldCluster ~= val then
                                    RemoveKeyFromAllUBTClusterOrders_Opts(d, skey)
                                    AddKeyToUBTClusterOrderEnd(d, val, skey)
                                end
                                Refresh()
                                RebuildUBTAssignmentArgs()
                                AceRegistry:NotifyChange("CkraigCooldownManager")
                            end
                        end,
                    },
                    moveUp = {
                        type = "execute",
                        name = "Up",
                        order = 3,
                        width = 0.3,
                        disabled = function()
                            local d = GetDB(); if not d then return true end
                            local cluster = tonumber(d.clusterAssignments and d.clusterAssignments[skey]) or 1
                            local pos = GetKeyPosInUBTClusterOrder(d, cluster, skey)
                            return not pos or pos <= 1
                        end,
                        func = function()
                            local d = GetDB(); if not d then return end
                            local cluster = tonumber(d.clusterAssignments and d.clusterAssignments[skey]) or 1
                            if MoveKeyInUBTClusterOrder(d, cluster, skey, -1) then
                                Refresh(); RebuildUBTAssignmentArgs()
                                AceRegistry:NotifyChange("CkraigCooldownManager")
                            end
                        end,
                    },
                    moveDown = {
                        type = "execute",
                        name = "Down",
                        order = 4,
                        width = 0.35,
                        disabled = function()
                            local d = GetDB(); if not d then return true end
                            local cluster = tonumber(d.clusterAssignments and d.clusterAssignments[skey]) or 1
                            local pos, size = GetKeyPosInUBTClusterOrder(d, cluster, skey)
                            return not pos or not size or pos >= size
                        end,
                        func = function()
                            local d = GetDB(); if not d then return end
                            local cluster = tonumber(d.clusterAssignments and d.clusterAssignments[skey]) or 1
                            if MoveKeyInUBTClusterOrder(d, cluster, skey, 1) then
                                Refresh(); RebuildUBTAssignmentArgs()
                                AceRegistry:NotifyChange("CkraigCooldownManager")
                            end
                        end,
                    },
                    remove = {
                        type = "execute",
                        name = "Remove",
                        order = 5,
                        width = 0.35,
                        confirm = true,
                        func = function()
                            local d = GetDB()
                            if d then
                                if d.clusterAssignments then d.clusterAssignments[skey] = nil end
                                RemoveKeyFromAllUBTClusterOrders_Opts(d, skey)
                                Refresh()
                                RebuildUBTAssignmentArgs()
                                AceRegistry:NotifyChange("CkraigCooldownManager")
                            end
                        end,
                    },
                },
            }
        end
    end

    assignTab.args.refreshList.func = function()
        RebuildUBTAssignmentArgs()
        AceRegistry:NotifyChange("CkraigCooldownManager")
    end

    assignTab.args.addSpell.set = function(_, val)
        local id = tonumber(val)
        if not id or id <= 0 then return end
        local db = GetDB()
        if not db then return end
        db.clusterAssignments = db.clusterAssignments or {}
        db.clusterAssignments[tostring(id)] = db.clusterAssignments[tostring(id)] or 1
        AddKeyToUBTClusterOrderEnd(db, tonumber(db.clusterAssignments[tostring(id)]) or 1, tostring(id))
        Refresh()
        RebuildUBTAssignmentArgs()
        AceRegistry:NotifyChange("CkraigCooldownManager")
    end

    RebuildUBTAssignmentArgs()
end

