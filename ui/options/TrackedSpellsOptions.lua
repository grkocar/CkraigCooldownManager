-- ============================================================
-- CkraigCooldownManager :: UI :: Options :: Tracked Spells
-- ============================================================
local CCM = _G.CkraigCooldownManager
local AceRegistry = LibStub("AceConfigRegistry-3.0")
local opts = CCM.AceOpts

local function GetDB()
    return _G.CCM_TrackedSpellsSettings
end

local function SaveSettings()
    if _G.CCM_TrackedSpells and _G.CCM_TrackedSpells.SaveSettings then
        _G.CCM_TrackedSpells.SaveSettings()
    end
end

local function Refresh()
    if _G.CCM_TrackedSpells and _G.CCM_TrackedSpells.UpdateCustomSpellIcons then
        _G.CCM_TrackedSpells.UpdateCustomSpellIcons()
    end
    SaveSettings()
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

local _spellTab  -- forward-declared so all closures can reach it

-- Rebuild the spell list args dynamically
local function RebuildSpellListArgs()
    local spellTab = _spellTab
    if not spellTab or not spellTab.args then return end
    for k in pairs(spellTab.args) do
        if k:find("^spell_") or k:find("^groupHeader_") or k:find("^groupViewer") or k == "empty" then
            spellTab.args[k] = nil
        end
    end

    local db = GetDB()
    if not db or not db.groups then
        spellTab.args.empty = {
            type = "description",
            name = "|cff888888No spells tracked. Add spells using the input above.|r",
            order = 100,
            fontSize = "medium",
        }
        return
    end

    local order = 100
    for gi, group in ipairs(db.groups) do
        if group.spellIDs then
            if #db.groups > 1 then
                spellTab.args["groupHeader_" .. gi] = {
                    type = "header",
                    name = group.name or ("Group " .. gi),
                    order = order,
                }
                order = order + 1
            end

            -- Per-group viewer integration dropdown
            local capturedGroupIdx = gi
            spellTab.args["groupViewerMode_" .. gi] = {
                type = "select",
                name = "Show With",
                desc = "Standalone: icons shown at group anchor. Essential/Utility: icons merged into that viewer's layout.",
                order = order,
                width = 1.2,
                values = {
                    standalone = "Standalone",
                    essential = "Essential Viewer",
                    utility = "Utility Viewer",
                    cursor = "Cursor Anchored",
                },
                get = function()
                    local d = GetDB()
                    local g = d and d.groups and d.groups[capturedGroupIdx]
                    return g and g.viewerMode or "standalone"
                end,
                set = function(_, val)
                    local d = GetDB()
                    local g = d and d.groups and d.groups[capturedGroupIdx]
                    if not g then return end
                    g.viewerMode = val
                    Refresh()
                end,
            }
            order = order + 1
            spellTab.args["groupViewerSortOrder_" .. gi] = {
                type = "range",
                name = "Sort Position",
                desc = "Controls where these icons appear among viewer icons. 0 = append at end. Lower numbers appear first (e.g. 1 = first icon).",
                order = order,
                min = 0, max = 30, step = 1,
                width = 1.0,
                hidden = function()
                    local d = GetDB()
                    local g = d and d.groups and d.groups[capturedGroupIdx]
                    local mode = g and (g.viewerMode or "standalone") or "standalone"
                    return not g or mode == "standalone" or mode == "cursor"
                end,
                get = function()
                    local d = GetDB()
                    local g = d and d.groups and d.groups[capturedGroupIdx]
                    return g and tonumber(g.viewerSortOrder) or 0
                end,
                set = function(_, val)
                    local d = GetDB()
                    local g = d and d.groups and d.groups[capturedGroupIdx]
                    if not g then return end
                    g.viewerSortOrder = val
                    Refresh()
                end,
            }
            order = order + 1

            -- Cursor-mode per-group options (visible only when cursor mode is selected)
            spellTab.args["groupCursorOffsetX_" .. gi] = {
                type = "range",
                name = "Cursor X Offset",
                desc = "Horizontal offset of icons from the cursor.",
                order = order,
                min = -500, max = 500, step = 1,
                width = 1.0,
                hidden = function()
                    local d = GetDB()
                    local g = d and d.groups and d.groups[capturedGroupIdx]
                    return not g or (g.viewerMode or "standalone") ~= "cursor"
                end,
                get = function()
                    local d = GetDB()
                    local g = d and d.groups and d.groups[capturedGroupIdx]
                    return g and tonumber(g.cursorOffsetX) or 0
                end,
                set = function(_, val)
                    local d = GetDB()
                    local g = d and d.groups and d.groups[capturedGroupIdx]
                    if not g then return end
                    g.cursorOffsetX = val
                    Refresh()
                end,
            }
            order = order + 1

            spellTab.args["groupCursorOffsetY_" .. gi] = {
                type = "range",
                name = "Cursor Y Offset",
                desc = "Vertical offset of icons from the cursor.",
                order = order,
                min = -500, max = 500, step = 1,
                width = 1.0,
                hidden = function()
                    local d = GetDB()
                    local g = d and d.groups and d.groups[capturedGroupIdx]
                    return not g or (g.viewerMode or "standalone") ~= "cursor"
                end,
                get = function()
                    local d = GetDB()
                    local g = d and d.groups and d.groups[capturedGroupIdx]
                    return g and tonumber(g.cursorOffsetY) or 0
                end,
                set = function(_, val)
                    local d = GetDB()
                    local g = d and d.groups and d.groups[capturedGroupIdx]
                    if not g then return end
                    g.cursorOffsetY = val
                    Refresh()
                end,
            }
            order = order + 1

            spellTab.args["groupCursorDirection_" .. gi] = {
                type = "select",
                name = "Growth Direction",
                desc = "Direction icons grow from the cursor anchor point.",
                order = order,
                width = 1.0,
                values = opts.DIRECTION_VALUES,
                hidden = function()
                    local d = GetDB()
                    local g = d and d.groups and d.groups[capturedGroupIdx]
                    return not g or (g.viewerMode or "standalone") ~= "cursor"
                end,
                get = function()
                    local d = GetDB()
                    local g = d and d.groups and d.groups[capturedGroupIdx]
                    return (g and g.placement and g.placement.direction) or "RIGHT"
                end,
                set = function(_, val)
                    local d = GetDB()
                    local g = d and d.groups and d.groups[capturedGroupIdx]
                    if not g then return end
                    g.placement = g.placement or {}
                    g.placement.direction = val
                    Refresh()
                end,
            }
            order = order + 1

            for i, spellID in ipairs(group.spellIDs) do
                local sid = tonumber(spellID) or 0
                local key = "spell_" .. gi .. "_" .. i
                local capturedGI, capturedI = gi, i

                spellTab.args[key] = {
                    type = "group",
                    name = function()
                        if sid > 0 then return GetSpellName(sid) end
                        return tostring(spellID)
                    end,
                    inline = true,
                    order = order,
                    args = {
                        icon = {
                            type = "description",
                            name = "",
                            order = 1,
                            image = function()
                                if sid > 0 then return GetSpellIcon(sid), 24, 24 end
                                return 134400, 24, 24
                            end,
                            width = 0.15,
                        },
                        label = {
                            type = "description",
                            name = function()
                                if sid > 0 then
                                    return "  " .. GetSpellName(sid) .. "  |cff888888(ID: " .. sid .. ")|r"
                                end
                                return "  " .. tostring(spellID)
                            end,
                            order = 2,
                            fontSize = "medium",
                            width = 1.2,
                        },
                        showCount = {
                            type = "toggle",
                            name = "Show Count",
                            order = 3,
                            width = 0.7,
                            get = function()
                                local d = GetDB()
                                local g = d and d.groups and d.groups[capturedGI]
                                if not g then return true end
                                local skey = tostring(sid)
                                if g.spellCountSettings and g.spellCountSettings[skey] and g.spellCountSettings[skey].show ~= nil then
                                    return g.spellCountSettings[skey].show
                                end
                                if g.spellShowCount and g.spellShowCount[skey] ~= nil then
                                    return g.spellShowCount[skey]
                                end
                                return true
                            end,
                            set = function(_, val)
                                local d = GetDB()
                                local g = d and d.groups and d.groups[capturedGI]
                                if not g then return end
                                local skey = tostring(sid)
                                g.spellCountSettings = g.spellCountSettings or {}
                                g.spellCountSettings[skey] = g.spellCountSettings[skey] or {}
                                g.spellCountSettings[skey].show = val and true or false
                                Refresh()
                            end,
                        },
                        onlyOnCooldown = {
                            type = "toggle",
                            name = "Only On Cooldown",
                            desc = "Hide this icon when the spell is ready. Show it only while it is cooling down.",
                            order = 3.5,
                            width = 0.9,
                            get = function()
                                local d = GetDB()
                                local g = d and d.groups and d.groups[capturedGI]
                                if not g then return false end
                                local skey = tostring(sid)
                                return g.spellOnlyOnCooldown and g.spellOnlyOnCooldown[skey] == true
                            end,
                            set = function(_, val)
                                local d = GetDB()
                                local g = d and d.groups and d.groups[capturedGI]
                                if not g then return end
                                local skey = tostring(sid)
                                g.spellOnlyOnCooldown = g.spellOnlyOnCooldown or {}
                                g.spellOnlyOnCooldown[skey] = val and true or nil
                                Refresh()
                            end,
                        },
                        countPos = {
                            type = "select",
                            name = "Stack Pos",
                            order = 4,
                            width = 0.8,
                            values = opts.POSITION_VALUES,
                            get = function()
                                local d = GetDB()
                                local g = d and d.groups and d.groups[capturedGI]
                                local skey = tostring(sid)
                                if g and g.spellCountSettings and g.spellCountSettings[skey] and g.spellCountSettings[skey].position then
                                    return g.spellCountSettings[skey].position
                                end
                                return (g and g.placement and g.placement.chargePosition) or (d and d.chargePosition) or "BOTTOMRIGHT"
                            end,
                            set = function(_, val)
                                local d = GetDB()
                                local g = d and d.groups and d.groups[capturedGI]
                                if not g then return end
                                local skey = tostring(sid)
                                g.spellCountSettings = g.spellCountSettings or {}
                                g.spellCountSettings[skey] = g.spellCountSettings[skey] or {}
                                g.spellCountSettings[skey].position = val
                                Refresh()
                            end,
                        },
                        countSize = {
                            type = "range",
                            name = "Stack Size",
                            order = 5,
                            min = 8,
                            max = 32,
                            step = 1,
                            width = 0.8,
                            get = function()
                                local d = GetDB()
                                local g = d and d.groups and d.groups[capturedGI]
                                local skey = tostring(sid)
                                if g and g.spellCountSettings and g.spellCountSettings[skey] and g.spellCountSettings[skey].size then
                                    return g.spellCountSettings[skey].size
                                end
                                return (g and g.placement and g.placement.chargeTextSize) or (d and d.chargeTextSize) or 14
                            end,
                            set = function(_, val)
                                local d = GetDB()
                                local g = d and d.groups and d.groups[capturedGI]
                                if not g then return end
                                local skey = tostring(sid)
                                g.spellCountSettings = g.spellCountSettings or {}
                                g.spellCountSettings[skey] = g.spellCountSettings[skey] or {}
                                g.spellCountSettings[skey].size = val
                                Refresh()
                            end,
                        },
                        countX = {
                            type = "range",
                            name = "Stack X",
                            order = 6,
                            min = -200,
                            max = 200,
                            step = 1,
                            width = 0.7,
                            get = function()
                                local d = GetDB()
                                local g = d and d.groups and d.groups[capturedGI]
                                local skey = tostring(sid)
                                if g and g.spellCountSettings and g.spellCountSettings[skey] and g.spellCountSettings[skey].x then
                                    return g.spellCountSettings[skey].x
                                end
                                return (g and g.placement and g.placement.chargeTextX) or (d and d.chargeTextX) or 0
                            end,
                            set = function(_, val)
                                local d = GetDB()
                                local g = d and d.groups and d.groups[capturedGI]
                                if not g then return end
                                local skey = tostring(sid)
                                g.spellCountSettings = g.spellCountSettings or {}
                                g.spellCountSettings[skey] = g.spellCountSettings[skey] or {}
                                g.spellCountSettings[skey].x = val
                                Refresh()
                            end,
                        },
                        countY = {
                            type = "range",
                            name = "Stack Y",
                            order = 7,
                            min = -200,
                            max = 200,
                            step = 1,
                            width = 0.7,
                            get = function()
                                local d = GetDB()
                                local g = d and d.groups and d.groups[capturedGI]
                                local skey = tostring(sid)
                                if g and g.spellCountSettings and g.spellCountSettings[skey] and g.spellCountSettings[skey].y then
                                    return g.spellCountSettings[skey].y
                                end
                                return (g and g.placement and g.placement.chargeTextY) or (d and d.chargeTextY) or 0
                            end,
                            set = function(_, val)
                                local d = GetDB()
                                local g = d and d.groups and d.groups[capturedGI]
                                if not g then return end
                                local skey = tostring(sid)
                                g.spellCountSettings = g.spellCountSettings or {}
                                g.spellCountSettings[skey] = g.spellCountSettings[skey] or {}
                                g.spellCountSettings[skey].y = val
                                Refresh()
                            end,
                        },
                        iconSize = {
                            type = "range",
                            name = "Icon Size",
                            order = 8,
                            min = 8,
                            max = 200,
                            step = 1,
                            width = 0.8,
                            get = function()
                                local d = GetDB()
                                local g = d and d.groups and d.groups[capturedGI]
                                if not g then return d and d.iconSize or 36 end
                                local skey = tostring(sid)
                                if g.spellSizes and g.spellSizes[skey] then
                                    return g.spellSizes[skey]
                                end
                                return (g.placement and g.placement.iconSize) or (d and d.iconSize) or 36
                            end,
                            set = function(_, val)
                                local d = GetDB()
                                local g = d and d.groups and d.groups[capturedGI]
                                if not g then return end
                                local skey = tostring(sid)
                                g.spellSizes = g.spellSizes or {}
                                g.spellSizes[skey] = val
                                Refresh()
                            end,
                        },
                        iconXOffset = {
                            type = "range",
                            name = "Icon X",
                            order = 8,
                            min = -200,
                            max = 200,
                            step = 1,
                            width = 0.8,
                            get = function()
                                local d = GetDB()
                                local g = d and d.groups and d.groups[capturedGI]
                                if not g then return 0 end
                                local skey = tostring(sid)
                                return (g.spellXOffsets and g.spellXOffsets[skey]) or 0
                            end,
                            set = function(_, val)
                                local d = GetDB()
                                local g = d and d.groups and d.groups[capturedGI]
                                if not g then return end
                                local skey = tostring(sid)
                                g.spellXOffsets = g.spellXOffsets or {}
                                g.spellXOffsets[skey] = val
                                Refresh()
                            end,
                        },
                        iconYOffset = {
                            type = "range",
                            name = "Icon Y",
                            order = 9,
                            min = -200,
                            max = 200,
                            step = 1,
                            width = 0.8,
                            get = function()
                                local d = GetDB()
                                local g = d and d.groups and d.groups[capturedGI]
                                if not g then return 0 end
                                local skey = tostring(sid)
                                return (g.spellOffsets and g.spellOffsets[skey]) or 0
                            end,
                            set = function(_, val)
                                local d = GetDB()
                                local g = d and d.groups and d.groups[capturedGI]
                                if not g then return end
                                local skey = tostring(sid)
                                g.spellOffsets = g.spellOffsets or {}
                                g.spellOffsets[skey] = val
                                Refresh()
                            end,
                        },
                        remove = {
                            type = "execute",
                            name = "Remove",
                            order = 10,
                            width = 0.5,
                            confirm = true,
                            confirmText = "Remove this spell from tracking?",
                            func = function()
                                local curDB = GetDB()
                                if curDB and curDB.groups and curDB.groups[capturedGI] then
                                    local g = curDB.groups[capturedGI]
                                    if g.spellIDs and g.spellIDs[capturedI] then
                                        local spellID = g.spellIDs[capturedI]
                                        table.remove(g.spellIDs, capturedI)
                                        -- Remove from Blizzard cooldown viewer
                                        if _G.CCM_TrackedSpells and _G.CCM_TrackedSpells.RemoveSpellFromCooldownViewer then
                                            _G.CCM_TrackedSpells.RemoveSpellFromCooldownViewer(spellID)
                                        end
                                    end
                                end
                                Refresh()
                                RebuildSpellListArgs()
                                AceRegistry:NotifyChange("CkraigCooldownManager")
                            end,
                        },
                    },
                }
                order = order + 1
            end
        end
    end

    local totalSpells = 0
    for _, g in ipairs(db.groups) do
        totalSpells = totalSpells + (g.spellIDs and #g.spellIDs or 0)
    end
    if totalSpells == 0 then
        spellTab.args.empty = {
            type = "description",
            name = "|cff888888No spells tracked. Add spells using the input above.|r",
            order = 100,
            fontSize = "medium",
        }
    end
end

-- Pending scan state: which scanned spells are selected and target group
local _pendingSelected = {}   -- [spellID] = true/false
local _pendingTargetGroup = 1 -- group index to add into

local function RebuildPendingPickerArgs()
    local spellTab = _spellTab
    if not spellTab or not spellTab.args then return end
    -- Clear old picker entries
    for k in pairs(spellTab.args) do
        if k:find("^pending_") or k == "pendingHeader" or k == "pendingGroupSelect"
            or k == "pendingAddSelected" or k == "pendingSelectAll" or k == "pendingSelectNone"
            or k == "pendingDismiss" then
            spellTab.args[k] = nil
        end
    end

    local pending = _G.CCM_PendingScannedSpells
    if not pending or #pending == 0 then return end

    local order = 50 -- between addSpell (1) and listHeader (10)... use 50-99 range

    spellTab.args.pendingHeader = {
        type = "header",
        name = "Scanned Spells — Select Which to Add",
        order = order,
    }
    order = order + 1

    -- Group selector
    local function GetGroupValues()
        local db = GetDB()
        local vals = {}
        if db and db.groups then
            for i, g in ipairs(db.groups) do
                vals[i] = g.name or ("Group " .. i)
            end
        end
        local nextIdx = (db and db.groups and #db.groups or 0) + 1
        vals[nextIdx] = "|cff00ff00+ New Group|r"
        return vals
    end

    spellTab.args.pendingGroupSelect = {
        type = "select",
        name = "Add to Group",
        desc = "Which group to add the selected spells into",
        order = order,
        width = 1.0,
        values = GetGroupValues,
        get = function() return _pendingTargetGroup end,
        set = function(_, val) _pendingTargetGroup = val end,
    }
    order = order + 1

    spellTab.args.pendingSelectAll = {
        type = "execute",
        name = "Select All",
        order = order,
        width = 0.5,
        func = function()
            for _, id in ipairs(pending) do _pendingSelected[id] = true end
            AceRegistry:NotifyChange("CkraigCooldownManager")
        end,
    }
    order = order + 1

    spellTab.args.pendingSelectNone = {
        type = "execute",
        name = "Select None",
        order = order,
        width = 0.5,
        func = function()
            wipe(_pendingSelected)
            AceRegistry:NotifyChange("CkraigCooldownManager")
        end,
    }
    order = order + 1

    spellTab.args.pendingAddSelected = {
        type = "execute",
        name = "Add Selected",
        order = order,
        width = 0.6,
        func = function()
            local db = GetDB()
            if not db then return end
            db.groups = db.groups or {}
            local targetIdx = _pendingTargetGroup
            -- Create new group if they picked the "+ New Group" option
            if not db.groups[targetIdx] then
                db.groups[targetIdx] = { name = "Group " .. targetIdx, spellIDs = {} }
            end
            local group = db.groups[targetIdx]
            group.spellIDs = group.spellIDs or {}
            local existing = {}
            for _, id in ipairs(group.spellIDs) do existing[id] = true end
            local added = 0
            for _, id in ipairs(pending) do
                if _pendingSelected[id] and not existing[id] then
                    table.insert(group.spellIDs, id)
                    if _G.CCM_TrackedSpells and _G.CCM_TrackedSpells.AddSpellToCooldownViewer then
                        _G.CCM_TrackedSpells.AddSpellToCooldownViewer(id)
                    end
                    added = added + 1
                end
            end
            print("[CCM] Added", added, "spells to", group.name or ("Group " .. targetIdx))
            -- Clear pending
            _G.CCM_PendingScannedSpells = nil
            wipe(_pendingSelected)
            Refresh()
            RebuildPendingPickerArgs()
            RebuildSpellListArgs()
            AceRegistry:NotifyChange("CkraigCooldownManager")
        end,
    }
    order = order + 1

    spellTab.args.pendingDismiss = {
        type = "execute",
        name = "Dismiss",
        desc = "Clear the scanned spell list without adding anything",
        order = order,
        width = 0.5,
        func = function()
            _G.CCM_PendingScannedSpells = nil
            wipe(_pendingSelected)
            RebuildPendingPickerArgs()
            AceRegistry:NotifyChange("CkraigCooldownManager")
        end,
    }
    order = order + 1

    -- One toggle per scanned spell with icon
    for idx, spellID in ipairs(pending) do
        local sid = spellID
        local key = "pending_" .. sid
        spellTab.args[key] = {
            type = "toggle",
            name = function()
                local name = GetSpellName(sid)
                return "|T" .. GetSpellIcon(sid) .. ":16:16:0:0|t  " .. name .. "  |cff888888(" .. sid .. ")|r"
            end,
            desc = function()
                return "Spell ID: " .. sid
            end,
            order = order,
            width = "full",
            get = function() return _pendingSelected[sid] == true end,
            set = function(_, val) _pendingSelected[sid] = val end,
        }
        order = order + 1
    end
end

function CCM.BuildTrackedSpellsOptions()
    local opts = CCM.AceOpts

    _spellTab = {
        type = "group",
        name = "Spell List",
        order = 2,
        args = {
            refreshList = {
                type = "execute",
                name = "Scan Spellbook",
                desc = "Scan your spellbook for current-spec spells. Choose which to add.",
                order = 0,
                func = function()
                    if _G.AutoPopulateTrackedSpells then
                        _G.AutoPopulateTrackedSpells()
                    end
                    wipe(_pendingSelected)
                    RebuildPendingPickerArgs()
                    RebuildSpellListArgs()
                    AceRegistry:NotifyChange("CkraigCooldownManager")
                end,
            },
            addSpell = {
                type = "input",
                name = "Add Spell ID",
                desc = "Enter a numeric spell ID to track",
                order = 1,
                width = "double",
                get = function() return "" end,
                set = function(_, val)
                    local db = GetDB()
                    if not db then return end
                    local id = tonumber(val)
                    if not id then return end
                    db.groups = db.groups or {}
                    if #db.groups == 0 then
                        db.groups[1] = { name = "Group 1", spellIDs = {} }
                    end
                    local group = db.groups[1]
                    group.spellIDs = group.spellIDs or {}
                    table.insert(group.spellIDs, id)
                    -- Add to Blizzard cooldown viewer so it appears on bars
                    if _G.CCM_TrackedSpells and _G.CCM_TrackedSpells.AddSpellToCooldownViewer then
                        _G.CCM_TrackedSpells.AddSpellToCooldownViewer(id)
                    end
                    Refresh()
                    RebuildSpellListArgs()
                    AceRegistry:NotifyChange("CkraigCooldownManager")
                end,
            },
            listHeader = {
                type = "header",
                name = "Current Tracked Spells",
                order = 10,
            },
        },
    }

    RebuildPendingPickerArgs()
    RebuildSpellListArgs()

    CCM.AceOptionsTable.args.trackedSpells = {
        type = "group",
        name = "Tracked Spells",
        order = 55,
        childGroups = "tab",
        args = {
            general = {
                type = "group",
                name = "General",
                order = 1,
                args = {
                    enabled = {
                        type = "toggle",
                        name = "Enable Custom Spell Tracking",
                        order = 1,
                        width = "full",
                        get = function() local db = GetDB(); return db and db.enabled end,
                        set = function(_, val) local db = GetDB(); if db then db.enabled = val; Refresh() end end,
                    },
                    showInCombatOnly = {
                        type = "toggle",
                        name = "Show Icons In Combat Only",
                        order = 2,
                        get = function() local db = GetDB(); return db and db.showInCombatOnly end,
                        set = function(_, val) local db = GetDB(); if db then db.showInCombatOnly = val; Refresh() end end,
                    },
                    unlockAnchors = {
                        type = "execute",
                        name = function()
                            local db = GetDB()
                            if db and db.groupsMoving then
                                return "Lock Group Anchors"
                            end
                            return "Unlock Group Anchors"
                        end,
                        desc = "Unlock tracked spell group anchor boxes so you can drag them on screen.",
                        order = 3,
                        width = "double",
                        func = function()
                            local db = GetDB()
                            if not db then return end
                            db.groupsMoving = not db.groupsMoving
                            Refresh()
                            AceRegistry:NotifyChange("CkraigCooldownManager")
                        end,
                    },
                    resetAnchorPositions = {
                        type = "execute",
                        name = "Reset Group Anchor Positions",
                        order = 4,
                        confirm = true,
                        confirmText = "Reset all tracked spell group anchor positions?",
                        func = function()
                            local db = GetDB()
                            if not db or not db.groups then return end
                            for gi, group in ipairs(db.groups) do
                                group.placement = group.placement or {}
                                group.placement.x = 0
                                group.placement.y = -80 * (gi - 1)
                            end
                            Refresh()
                        end,
                    },
                    headerSize = { type = "header", name = "Size & Layout", order = 10 },
                    iconSize = {
                        type = "range", name = "Icon Size", order = 11,
                        min = 20, max = 100, step = 1,
                        get = function() local db = GetDB(); return db and db.iconSize or 36 end,
                        set = function(_, val) local db = GetDB(); if db then db.iconSize = val; Refresh() end end,
                    },
                    spacing = {
                        type = "range", name = "Icon Spacing", order = 12,
                        min = 0, max = 50, step = 1,
                        get = function() local db = GetDB(); return db and db.spacing or 4 end,
                        set = function(_, val) local db = GetDB(); if db then db.spacing = val; Refresh() end end,
                    },
                    direction = {
                        type = "select", name = "Growth Direction", order = 13,
                        values = opts.DIRECTION_VALUES,
                        get = function() local db = GetDB(); return db and db.direction or "RIGHT" end,
                        set = function(_, val) local db = GetDB(); if db then db.direction = val; Refresh() end end,
                    },
                    headerText = { type = "header", name = "Text Settings", order = 20 },
                    chargePosition = {
                        type = "select", name = "Charge/Stack Position", order = 21,
                        values = opts.POSITION_VALUES,
                        get = function() local db = GetDB(); return db and db.chargePosition or "BOTTOMRIGHT" end,
                        set = function(_, val) local db = GetDB(); if db then db.chargePosition = val; Refresh() end end,
                    },
                    chargeTextSize = {
                        type = "range", name = "Charge Text Size", order = 22,
                        min = 8, max = 32, step = 1,
                        get = function() local db = GetDB(); return db and db.chargeTextSize or 14 end,
                        set = function(_, val) local db = GetDB(); if db then db.chargeTextSize = val; Refresh() end end,
                    },
                    chargeTextX = {
                        type = "range", name = "Charge Text X Offset", order = 23,
                        min = -200, max = 200, step = 1,
                        get = function() local db = GetDB(); return db and db.chargeTextX or 0 end,
                        set = function(_, val) local db = GetDB(); if db then db.chargeTextX = val; Refresh() end end,
                    },
                    chargeTextY = {
                        type = "range", name = "Charge Text Y Offset", order = 24,
                        min = -200, max = 200, step = 1,
                        get = function() local db = GetDB(); return db and db.chargeTextY or 0 end,
                        set = function(_, val) local db = GetDB(); if db then db.chargeTextY = val; Refresh() end end,
                    },
                },
            },
            spells = _spellTab,
        },
    }
end
