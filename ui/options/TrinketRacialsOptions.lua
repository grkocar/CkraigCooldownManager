-- ============================================================
-- CkraigCooldownManager :: UI :: Options :: Trinket & Racials
-- ============================================================
-- AceConfig options table for TrinketRacials module.
-- Replaces the hand-built TRINKETRACIALS.CreateOptionsPanel.
-- ============================================================

local CCM = _G.CkraigCooldownManager
local AceRegistry = LibStub("AceConfigRegistry-3.0")
local LSM = LibStub("LibSharedMedia-3.0", true)

local trSoundKeyCache        = nil
local trSoundSearchText      = ""
local trSoundLsmCallbackReg  = false
local trSoundShowAll         = true
local trSoundPage            = 1
local trSoundPageSize        = 150

local function TRTrimString(s)
    if type(s) ~= "string" then return "" end
    return s:match("^%s*(.-)%s*$") or ""
end

local function TRBuildSoundKeyCache()
    if trSoundKeyCache then return trSoundKeyCache end
    local keys = {}
    if LSM and LSM.HashTable then
        local tbl = LSM:HashTable("sound")
        if type(tbl) == "table" then
            for key in pairs(tbl) do keys[#keys + 1] = tostring(key) end
        end
    end
    table.sort(keys, function(a, b) return a:lower() < b:lower() end)
    trSoundKeyCache = keys
    return trSoundKeyCache
end

local function TRGetSoundValues(currentValue)
    local values = {}
    local keys = TRBuildSoundKeyCache()
    local query = TRTrimString(trSoundSearchText):lower()
    local hasSearch = (query ~= "")

    if hasSearch then
        for _, key in ipairs(keys) do
            if key:lower():find(query, 1, true) then values[key] = key end
        end
    elseif trSoundShowAll then
        local totalKeys = #keys
        local totalPages = math.max(1, math.ceil(totalKeys / trSoundPageSize))
        if trSoundPage > totalPages then trSoundPage = totalPages end
        if trSoundPage < 1 then trSoundPage = 1 end
        local startIdx = (trSoundPage - 1) * trSoundPageSize + 1
        local endIdx   = math.min(startIdx + trSoundPageSize - 1, totalKeys)
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

local function TRRegisterSoundCallback()
    if trSoundLsmCallbackReg or not (LSM and LSM.RegisterCallback) then return end
    trSoundLsmCallbackReg = true
    LSM:RegisterCallback("LibSharedMedia_Registered", function(_, mediaType)
        if mediaType == "sound" then
            trSoundKeyCache = nil
            AceRegistry:NotifyChange("CkraigCooldownManager")
        end
    end)
end

local function GetDB()
    -- Read settings from the module's own profile data store
    if _G.TRINKETRACIALS and _G.TRINKETRACIALS.GetProfileData then
        local data = _G.TRINKETRACIALS.GetProfileData()
        if data then return data end
    end
    return {}
end

local function SetAndRefresh(key, val)
    if _G.TRINKETRACIALS and _G.TRINKETRACIALS.SetProfileData then
        _G.TRINKETRACIALS.SetProfileData(key, val)
    end
    if _G.TRINKETRACIALS and _G.TRINKETRACIALS.LoadSettings then
        _G.TRINKETRACIALS.LoadSettings()
    end
    if _G.TRINKETRACIALS and _G.TRINKETRACIALS.UpdateAllIcons then
        _G.TRINKETRACIALS.UpdateAllIcons()
    end
end

local function NormalizeCoord(v, fallback)
    local n = tonumber(v)
    if not n then n = fallback or 0 end
    return math.floor(n)
end

local function GetDirectPosition(group)
    local frame = (group == 2) and _G.CCM_AnchorFrame2 or _G.CCM_AnchorFrame
    if frame and frame.GetCenter then
        local cx, cy = frame:GetCenter()
        if cx and cy and UIParent and UIParent.GetCenter then
            local ux, uy = UIParent:GetCenter()
            if ux and uy then
                return NormalizeCoord(cx - ux, 0), NormalizeCoord(cy - uy, (group == 2) and -80 or 0)
            end
        end
    end

    local key = (group == 2) and "trinketIcons2" or "trinketIcons"
    if CkraigProfileManager and CkraigProfileManager.GetProfileData then
        local data = CkraigProfileManager:GetProfileData(key)
        if type(data) == "table" then
            return NormalizeCoord(data.x, 0), NormalizeCoord(data.y, (group == 2) and -80 or 0)
        end
    end

    return 0, (group == 2) and -80 or 0
end

local function SetDirectPosition(group, x, y)
    x = NormalizeCoord(x, 0)
    y = NormalizeCoord(y, (group == 2) and -80 or 0)

    local key = (group == 2) and "trinketIcons2" or "trinketIcons"
    if CkraigProfileManager and CkraigProfileManager.GetProfileData and CkraigProfileManager.SetProfileData then
        local data = CkraigProfileManager:GetProfileData(key)
        if type(data) ~= "table" then data = {} end
        data.x = x
        data.y = y
        CkraigProfileManager:SetProfileData(key, data)

        local tracked = CkraigProfileManager:GetProfileData("trackedItems")
        if type(tracked) ~= "table" then tracked = {} end
        tracked.layoutPositions = tracked.layoutPositions or {}
        if type(tracked.layoutPositions) ~= "table" then tracked.layoutPositions = {} end
        local groupKey = (group == 2) and "group2" or "group1"
        tracked.layoutPositions[groupKey] = tracked.layoutPositions[groupKey] or {}
        if type(tracked.layoutPositions[groupKey]) ~= "table" then
            tracked.layoutPositions[groupKey] = {}
        end

        local layoutName
        local LibEditMode = LibStub and LibStub("LibEditMode", true)
        if LibEditMode and LibEditMode.GetActiveLayoutName then
            layoutName = LibEditMode:GetActiveLayoutName()
        end
        if layoutName then
            tracked.layoutPositions[groupKey][layoutName] = { x = x, y = y }
        end
        CkraigProfileManager:SetProfileData("trackedItems", tracked)
    end

    local frame = (group == 2) and _G.CCM_AnchorFrame2 or _G.CCM_AnchorFrame
    if frame then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    end
end

local function SetPositionSafe(group, x, y)
    local ok = false
    if _G.TRINKETRACIALS then
        if group == 2 and _G.TRINKETRACIALS.SetPosition2 then
            ok = pcall(_G.TRINKETRACIALS.SetPosition2, x, y)
        elseif group ~= 2 and _G.TRINKETRACIALS.SetPosition then
            ok = pcall(_G.TRINKETRACIALS.SetPosition, x, y)
        end
    end
    if not ok then
        SetDirectPosition(group, x, y)
        if _G.TRINKETRACIALS and _G.TRINKETRACIALS.UpdateAllIcons then
            pcall(_G.TRINKETRACIALS.UpdateAllIcons)
        end
    end
end

local function SetMoveModeSafe(group, enabled)
    local ok = false
    if _G.TRINKETRACIALS and _G.TRINKETRACIALS.SetMoveMode then
        ok = pcall(_G.TRINKETRACIALS.SetMoveMode, group, enabled)
    end
    if ok then return end

    local frame = (group == 2) and _G.CCM_AnchorFrame2 or _G.CCM_AnchorFrame
    if not frame then return end
    enabled = enabled and true or false
    frame.moving = enabled
    frame:SetFrameStrata(enabled and "TOOLTIP" or "MEDIUM")
    frame:SetMovable(enabled)
    frame:EnableMouse(enabled)
    if enabled then
        frame:Show()
        frame:SetAlpha(1)
    else
        frame:EnableKeyboard(false)
        frame._arrowKeyActive = false
        if frame._anchorLabel then
            frame._anchorLabel:SetText((group == 2) and "Group 2" or "Group 1")
        end
        if not frame.isDragging then
            frame:Hide()
        end
    end
end

function CCM.BuildTrinketRacialsOptions()
    TRRegisterSoundCallback()

    CCM.AceOptionsTable.args.trinketRacials = {
        type = "group",
        name = "Tracked Items",
        order = 50,
        childGroups = "tab",
        args = {
            general = {
                type = "group",
                name = "General",
                order = 1,
                args = {
                    enableNote = {
                        type = "description",
                        name = "|cffff6600Enabling/disabling requires a UI reload.|r",
                        order = 0,
                        fontSize = "medium",
                    },
                    enable = {
                        type = "execute",
                        name = "Enable & Reload",
                        order = 1,
                        func = function()
                            SetAndRefresh("enabled", true)
                            ReloadUI()
                        end,
                        confirm = true,
                        confirmText = "This will reload your UI. Continue?",
                    },
                    disable = {
                        type = "execute",
                        name = "Disable & Reload",
                        order = 2,
                        func = function()
                            SetAndRefresh("enabled", false)
                            ReloadUI()
                        end,
                        confirm = true,
                        confirmText = "This will reload your UI. Continue?",
                    },
                    showPassiveTrinkets = {
                        type = "toggle",
                        name = "Show Passive Trinkets",
                        order = 3,
                        get = function() local db = GetDB(); return db.showPassiveTrinkets ~= false end,
                        set = function(_, val) SetAndRefresh("showPassiveTrinkets", val) end,
                    },
                    groupMode = {
                        type = "select",
                        name = "Group Mode",
                        order = 4,
                        values = { single = "Single Group", split = "Split (2 Groups)" },
                        get = function() local db = GetDB(); return db.groupMode or "single" end,
                        set = function(_, val) SetAndRefresh("groupMode", val) end,
                    },
                    group2ClusterMode = {
                        type = "toggle",
                        name = "Show Group 2 in Essential Cooldowns",
                        order = 5,
                        hidden = function() local db = GetDB(); return (db.groupMode or "single") ~= "split" end,
                        get = function() local db = GetDB(); return db.group2ClusterMode end,
                        set = function(_, val) SetAndRefresh("group2ClusterMode", val) end,
                    },
                    group2SortOrder = {
                        type = "range",
                        name = "Sort Position in Viewer",
                        desc = "Controls where Group 2 icons appear among Essential viewer icons. 0 = append at end. Lower numbers appear first (e.g. 1 = first icon).",
                        order = 6,
                        min = 0, max = 30, step = 1,
                        hidden = function()
                            local db = GetDB()
                            return (db.groupMode or "single") ~= "split" or not db.group2ClusterMode
                        end,
                        get = function() local db = GetDB(); return db.group2SortOrder or 0 end,
                        set = function(_, val) SetAndRefresh("group2SortOrder", val) end,
                    },
                },
            },
            sizes = {
                type = "group",
                name = "Size & Spacing",
                order = 2,
                args = {
                    iconSize = {
                        type = "range",
                        name = "Icon Size (All)",
                        order = 1,
                        min = 20, max = 80, step = 1,
                        get = function() local db = GetDB(); return db.iconSize or 36 end,
                        set = function(_, val)
                            SetAndRefresh("iconSize", val)
                            SetAndRefresh("iconSize1", val)
                            SetAndRefresh("iconSize2", val)
                        end,
                    },
                    headerGroup1 = {
                        type = "header",
                        name = "Group 1",
                        order = 10,
                    },
                    iconSize1 = {
                        type = "range",
                        name = "Group 1 Icon Size",
                        order = 11,
                        min = 20, max = 80, step = 1,
                        get = function() local db = GetDB(); return db.iconSize1 or db.iconSize or 36 end,
                        set = function(_, val) SetAndRefresh("iconSize1", val) end,
                    },
                    iconSpacing1 = {
                        type = "range",
                        name = "Group 1 Icon Spacing",
                        order = 12,
                        min = 0, max = 100, step = 1,
                        get = function() local db = GetDB(); return db.iconSpacing1 or 4 end,
                        set = function(_, val) SetAndRefresh("iconSpacing1", val) end,
                    },
                    iconsPerRow1 = {
                        type = "range",
                        name = "Group 1 Icons Per Row",
                        order = 13,
                        min = 1, max = 12, step = 1,
                        get = function() local db = GetDB(); return db.iconsPerRow1 or 6 end,
                        set = function(_, val) SetAndRefresh("iconsPerRow1", val) end,
                    },
                    headerGroup2 = {
                        type = "header",
                        name = "Group 2",
                        order = 20,
                        hidden = function() local db = GetDB(); return (db.groupMode or "single") ~= "split" end,
                    },
                    iconSize2 = {
                        type = "range",
                        name = "Group 2 Icon Size",
                        order = 21,
                        min = 20, max = 80, step = 1,
                        hidden = function() local db = GetDB(); return (db.groupMode or "single") ~= "split" end,
                        get = function() local db = GetDB(); return db.iconSize2 or db.iconSize or 36 end,
                        set = function(_, val) SetAndRefresh("iconSize2", val) end,
                    },
                    iconSpacing2 = {
                        type = "range",
                        name = "Group 2 Icon Spacing",
                        order = 22,
                        min = 0, max = 100, step = 1,
                        hidden = function() local db = GetDB(); return (db.groupMode or "single") ~= "split" end,
                        get = function() local db = GetDB(); return db.iconSpacing2 or 4 end,
                        set = function(_, val) SetAndRefresh("iconSpacing2", val) end,
                    },
                    iconsPerRow2 = {
                        type = "range",
                        name = "Group 2 Icons Per Row",
                        order = 23,
                        min = 1, max = 12, step = 1,
                        hidden = function() local db = GetDB(); return (db.groupMode or "single") ~= "split" end,
                        get = function() local db = GetDB(); return db.iconsPerRow2 or 6 end,
                        set = function(_, val) SetAndRefresh("iconsPerRow2", val) end,
                    },
                    rowSpacing = {
                        type = "range",
                        name = "Row Spacing",
                        order = 30,
                        min = 0, max = 50, step = 1,
                        get = function() local db = GetDB(); return db.iconRowSpacing or 4 end,
                        set = function(_, val) SetAndRefresh("iconRowSpacing", val) end,
                    },
                },
            },
            positions = {
                type = "group",
                name = "Positions",
                order = 3,
                args = {
                    moveHint = {
                        type = "description",
                        name = "Unlock anchors here to drag them, or use the X/Y sliders for exact placement.",
                        order = 0,
                        fontSize = "medium",
                    },
                    unlockGroup1 = {
                        type = "execute",
                        name = "Unlock Group 1 Anchor",
                        order = 1,
                        width = 1.2,
                        func = function()
                            SetMoveModeSafe(1, true)
                        end,
                    },
                    unlockGroup2 = {
                        type = "execute",
                        name = "Unlock Group 2 Anchor",
                        order = 2,
                        width = 1.2,
                        hidden = function() local db = GetDB(); return (db.groupMode or "single") ~= "split" end,
                        func = function()
                            SetMoveModeSafe(2, true)
                        end,
                    },
                    lockAnchors = {
                        type = "execute",
                        name = "Lock Anchors",
                        order = 3,
                        width = 1.0,
                        func = function()
                            if _G.TRINKETRACIALS and _G.TRINKETRACIALS.LockAllAnchors then
                                local ok = pcall(_G.TRINKETRACIALS.LockAllAnchors)
                                if ok then return end
                            end
                            SetMoveModeSafe(1, false)
                            SetMoveModeSafe(2, false)
                        end,
                    },
                    resetAnchors = {
                        type = "execute",
                        name = "Reset Anchor Positions",
                        order = 4,
                        width = 1.2,
                        confirm = true,
                        confirmText = "Reset Group 1/2 positions and layout overrides?",
                        func = function()
                            if _G.TRINKETRACIALS and _G.TRINKETRACIALS.ResetPositions then
                                _G.TRINKETRACIALS.ResetPositions()
                            end
                        end,
                    },
                    group1X = {
                        type = "range",
                        name = "Group 1 X",
                        order = 10,
                        min = -1000, max = 1000, step = 1,
                        get = function()
                            if _G.TRINKETRACIALS and _G.TRINKETRACIALS.GetPosition then
                                local ok, pos = pcall(_G.TRINKETRACIALS.GetPosition)
                                if ok and type(pos) == "table" and type(pos.x) == "number" then
                                    return pos.x
                                end
                            end
                            local x = GetDirectPosition(1)
                            return x
                        end,
                        set = function(_, val)
                            local _, y = GetDirectPosition(1)
                            SetPositionSafe(1, val, y)
                        end,
                    },
                    group1Y = {
                        type = "range",
                        name = "Group 1 Y",
                        order = 11,
                        min = -1000, max = 1000, step = 1,
                        get = function()
                            if _G.TRINKETRACIALS and _G.TRINKETRACIALS.GetPosition then
                                local ok, pos = pcall(_G.TRINKETRACIALS.GetPosition)
                                if ok and type(pos) == "table" and type(pos.y) == "number" then
                                    return pos.y
                                end
                            end
                            local _, y = GetDirectPosition(1)
                            return y
                        end,
                        set = function(_, val)
                            local x = GetDirectPosition(1)
                            SetPositionSafe(1, x, val)
                        end,
                    },
                    group2X = {
                        type = "range",
                        name = "Group 2 X",
                        order = 12,
                        min = -1000, max = 1000, step = 1,
                        hidden = function() local db = GetDB(); return (db.groupMode or "single") ~= "split" end,
                        get = function()
                            if _G.TRINKETRACIALS and _G.TRINKETRACIALS.GetPosition2 then
                                local ok, pos = pcall(_G.TRINKETRACIALS.GetPosition2)
                                if ok and type(pos) == "table" and type(pos.x) == "number" then
                                    return pos.x
                                end
                            end
                            local x = GetDirectPosition(2)
                            return x
                        end,
                        set = function(_, val)
                            local _, y = GetDirectPosition(2)
                            SetPositionSafe(2, val, y)
                        end,
                    },
                    group2Y = {
                        type = "range",
                        name = "Group 2 Y",
                        order = 13,
                        min = -1000, max = 1000, step = 1,
                        hidden = function() local db = GetDB(); return (db.groupMode or "single") ~= "split" end,
                        get = function()
                            if _G.TRINKETRACIALS and _G.TRINKETRACIALS.GetPosition2 then
                                local ok, pos = pcall(_G.TRINKETRACIALS.GetPosition2)
                                if ok and type(pos) == "table" and type(pos.y) == "number" then
                                    return pos.y
                                end
                            end
                            local _, y = GetDirectPosition(2)
                            return y
                        end,
                        set = function(_, val)
                            local x = GetDirectPosition(2)
                            SetPositionSafe(2, x, val)
                        end,
                    },
                },
            },
            -- ============================
            -- Count Text tab
            -- ============================
            countText = {
                type = "group",
                name = "Count Text",
                order = 5,
                args = {
                    desc = {
                        type = "description",
                        name = "Configure the anchor point and X/Y offset of the count number on each icon.",
                        order = 0,
                        fontSize = "medium",
                    },
                    headerGroup1 = {
                        type = "header",
                        name = "Group 1",
                        order = 10,
                    },
                    countAnchor1 = {
                        type = "select",
                        name = "Anchor Point",
                        desc = "Which corner/edge of the icon the count number is anchored to.",
                        order = 11,
                        values = {
                            TOPLEFT = "Top Left", TOP = "Top", TOPRIGHT = "Top Right",
                            LEFT = "Left", CENTER = "Center", RIGHT = "Right",
                            BOTTOMLEFT = "Bottom Left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom Right",
                        },
                        sorting = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" },
                        get = function() local db = GetDB(); return db.countAnchor1 or "BOTTOMRIGHT" end,
                        set = function(_, val) SetAndRefresh("countAnchor1", val) end,
                    },
                    countOffsetX1 = {
                        type = "range",
                        name = "X Offset",
                        order = 12,
                        min = -50, max = 50, step = 1,
                        get = function() local db = GetDB(); return db.countOffsetX1 or -2 end,
                        set = function(_, val) SetAndRefresh("countOffsetX1", val) end,
                    },
                    countOffsetY1 = {
                        type = "range",
                        name = "Y Offset",
                        order = 13,
                        min = -50, max = 50, step = 1,
                        get = function() local db = GetDB(); return db.countOffsetY1 or 2 end,
                        set = function(_, val) SetAndRefresh("countOffsetY1", val) end,
                    },
                    countFontSize1 = {
                        type = "range",
                        name = "Font Size",
                        order = 14,
                        min = 6, max = 32, step = 1,
                        get = function() local db = GetDB(); return db.countFontSize1 or 14 end,
                        set = function(_, val) SetAndRefresh("countFontSize1", val) end,
                    },
                    countColor1 = {
                        type = "color",
                        name = "Color",
                        order = 15,
                        hasAlpha = true,
                        get = function()
                            local db = GetDB()
                            local c = type(db.countColor1) == "table" and db.countColor1 or {}
                            return c.r or 1, c.g or 1, c.b or 1, c.a or 1
                        end,
                        set = function(_, r, g, b, a)
                            local c = { r = r, g = g, b = b, a = a }
                            SetAndRefresh("countColor1", c)
                        end,
                    },
                    headerGroup2 = {
                        type = "header",
                        name = "Group 2",
                        order = 20,
                        hidden = function() local db = GetDB(); return (db.groupMode or "single") ~= "split" end,
                    },
                    countAnchor2 = {
                        type = "select",
                        name = "Anchor Point",
                        desc = "Which corner/edge of the icon the count number is anchored to (Group 2).",
                        order = 21,
                        hidden = function() local db = GetDB(); return (db.groupMode or "single") ~= "split" end,
                        values = {
                            TOPLEFT = "Top Left", TOP = "Top", TOPRIGHT = "Top Right",
                            LEFT = "Left", CENTER = "Center", RIGHT = "Right",
                            BOTTOMLEFT = "Bottom Left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom Right",
                        },
                        sorting = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" },
                        get = function() local db = GetDB(); return db.countAnchor2 or "BOTTOMRIGHT" end,
                        set = function(_, val) SetAndRefresh("countAnchor2", val) end,
                    },
                    countOffsetX2 = {
                        type = "range",
                        name = "X Offset",
                        order = 22,
                        min = -50, max = 50, step = 1,
                        hidden = function() local db = GetDB(); return (db.groupMode or "single") ~= "split" end,
                        get = function() local db = GetDB(); return db.countOffsetX2 or -2 end,
                        set = function(_, val) SetAndRefresh("countOffsetX2", val) end,
                    },
                    countOffsetY2 = {
                        type = "range",
                        name = "Y Offset",
                        order = 23,
                        min = -50, max = 50, step = 1,
                        hidden = function() local db = GetDB(); return (db.groupMode or "single") ~= "split" end,
                        get = function() local db = GetDB(); return db.countOffsetY2 or 2 end,
                        set = function(_, val) SetAndRefresh("countOffsetY2", val) end,
                    },
                    countFontSize2 = {
                        type = "range",
                        name = "Font Size",
                        order = 24,
                        min = 6, max = 32, step = 1,
                        hidden = function() local db = GetDB(); return (db.groupMode or "single") ~= "split" end,
                        get = function() local db = GetDB(); return db.countFontSize2 or 14 end,
                        set = function(_, val) SetAndRefresh("countFontSize2", val) end,
                    },
                    countColor2 = {
                        type = "color",
                        name = "Color",
                        order = 25,
                        hasAlpha = true,
                        hidden = function() local db = GetDB(); return (db.groupMode or "single") ~= "split" end,
                        get = function()
                            local db = GetDB()
                            local c = type(db.countColor2) == "table" and db.countColor2 or {}
                            return c.r or 1, c.g or 1, c.b or 1, c.a or 1
                        end,
                        set = function(_, r, g, b, a)
                            local c = { r = r, g = g, b = b, a = a }
                            SetAndRefresh("countColor2", c)
                        end,
                    },
                },
            },
            -- ============================
            -- Sounds tab
            -- ============================
            sounds = {
                type = "group",
                name = "Sounds",
                order = 5,
                args = {
                    desc = {
                        type = "description",
                        name = "Play a sound or TTS when an item becomes ready or goes on cooldown. Configure per category below.",
                        order = 0,
                        fontSize = "medium",
                        width = "full",
                    },
                    trSoundShowAllToggle = {
                        type = "toggle",
                        name = "Show Full Sound List",
                        desc = "Toggle between a quick list (first 80 sounds) and the full paginated SharedMedia list.",
                        order = 1,
                        width = 1.0,
                        get = function() return trSoundShowAll end,
                        set = function(_, val)
                            trSoundShowAll = val and true or false
                            trSoundPage = 1
                            AceRegistry:NotifyChange("CkraigCooldownManager")
                        end,
                    },
                    trSoundPrevPage = {
                        type = "execute",
                        name = "< Prev Page",
                        order = 2,
                        width = 0.5,
                        hidden = function() return not trSoundShowAll or TRTrimString(trSoundSearchText) ~= "" end,
                        disabled = function() return trSoundPage <= 1 end,
                        func = function()
                            trSoundPage = math.max(1, trSoundPage - 1)
                            AceRegistry:NotifyChange("CkraigCooldownManager")
                        end,
                    },
                    trSoundPageInfo = {
                        type = "description",
                        name = function()
                            local totalKeys = #(TRBuildSoundKeyCache())
                            local totalPages = math.max(1, math.ceil(totalKeys / trSoundPageSize))
                            return "  Page " .. trSoundPage .. " / " .. totalPages .. "  (" .. totalKeys .. " sounds)  "
                        end,
                        order = 3,
                        width = 1.0,
                        hidden = function() return not trSoundShowAll or TRTrimString(trSoundSearchText) ~= "" end,
                    },
                    trSoundNextPage = {
                        type = "execute",
                        name = "Next Page >",
                        order = 4,
                        width = 0.5,
                        hidden = function() return not trSoundShowAll or TRTrimString(trSoundSearchText) ~= "" end,
                        disabled = function()
                            local totalKeys = #(TRBuildSoundKeyCache())
                            local totalPages = math.max(1, math.ceil(totalKeys / trSoundPageSize))
                            return trSoundPage >= totalPages
                        end,
                        func = function()
                            local totalKeys = #(TRBuildSoundKeyCache())
                            local totalPages = math.max(1, math.ceil(totalKeys / trSoundPageSize))
                            trSoundPage = math.min(totalPages, trSoundPage + 1)
                            AceRegistry:NotifyChange("CkraigCooldownManager")
                        end,
                    },
                    trSoundSearch = {
                        type = "input",
                        name = "Search SharedMedia Sounds",
                        desc = "Type part of a sound name to filter the dropdown.",
                        order = 5,
                        width = "full",
                        get = function() return trSoundSearchText end,
                        set = function(_, val)
                            trSoundSearchText = TRTrimString(val)
                            AceRegistry:NotifyChange("CkraigCooldownManager")
                        end,
                    },
                    trSoundSearchHelp = {
                        type = "description",
                        name = "Tip: Use Search to find sounds instantly. Enable 'Show Full Sound List' to browse all sounds with page controls.",
                        order = 6,
                        width = "full",
                    },
                },
            },
            -- ============================
            -- Tracked Items tab
            -- ============================
            trackedItems = {
                type = "group",
                name = "Tracked Items",
                order = 4,
                args = {
                    desc = {
                        type = "description",
                        name = "Shows all tracked item categories and their group assignments. Items with icons are those currently usable.",
                        order = 0,
                    },
                },
            },
        },
    }

    -- Build tracked items display
    local itemTab = CCM.AceOptionsTable.args.trinketRacials.args.trackedItems
    local groupValues = { [1] = "Group 1", [2] = "Group 2" }

    local function GetItemName(itemID)
        if C_Item and C_Item.GetItemNameByID then
            local name = C_Item.GetItemNameByID(itemID)
            if name then return name end
        end
        return "Item " .. itemID
    end

    local function GetItemIcon(itemID)
        if C_Item and C_Item.GetItemIconByID then
            local icon = C_Item.GetItemIconByID(itemID)
            if icon then return icon end
        end
        return "Interface\\ICONS\\INV_Misc_QuestionMark"
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
        return "Interface\\ICONS\\INV_Misc_QuestionMark"
    end

    local order = 10

    -- Trinket slots
    for _, info in ipairs({
        { key = "trinket13", name = "Trinket (Slot 13)", icon = function() return GetInventoryItemTexture("player", 13) or "Interface\\ICONS\\INV_Misc_QuestionMark" end },
        { key = "trinket14", name = "Trinket (Slot 14)", icon = function() return GetInventoryItemTexture("player", 14) or "Interface\\ICONS\\INV_Misc_QuestionMark" end },
    }) do
        itemTab.args["item_" .. info.key] = {
            type = "group", name = "", order = order, inline = true,
            args = {
                icon = {
                    type = "description", name = info.name, order = 1,
                    image = info.icon, imageWidth = 24, imageHeight = 24, width = 1.5,
                },
                group = {
                    type = "select", name = "Group", order = 2, values = groupValues, width = 0.7,
                    get = function()
                        if _G.TRINKETRACIALS and _G.TRINKETRACIALS.GetIconGroupAssignments then
                            local a = _G.TRINKETRACIALS.GetIconGroupAssignments()
                            return a and a[info.key] or 2
                        end
                        return 2
                    end,
                    set = function(_, val)
                        if _G.TRINKETRACIALS and _G.TRINKETRACIALS.SetIconGroupAssignment then
                            _G.TRINKETRACIALS.SetIconGroupAssignment(info.key, val)
                        end
                    end,
                },
            },
        }
        order = order + 1
    end

    -- Healthstone
    itemTab.args.item_healthstone = {
        type = "group", name = "", order = order, inline = true,
        args = {
            icon = {
                type = "description", name = "Healthstone", order = 1,
                image = function() return GetItemIcon(5512) end, imageWidth = 24, imageHeight = 24, width = 1.5,
            },
            group = {
                type = "select", name = "Group", order = 2, values = groupValues, width = 0.7,
                get = function()
                    if _G.TRINKETRACIALS and _G.TRINKETRACIALS.GetIconGroupAssignments then
                        local a = _G.TRINKETRACIALS.GetIconGroupAssignments()
                        return a and a.healthstone or 2
                    end
                    return 2
                end,
                set = function(_, val)
                    if _G.TRINKETRACIALS and _G.TRINKETRACIALS.SetIconGroupAssignment then
                        _G.TRINKETRACIALS.SetIconGroupAssignment("healthstone", val)
                    end
                end,
            },
        },
    }
    order = order + 1

    -- Category headers + group assignments for Racials, Power Potions, Healing Potions
    for _, cat in ipairs({
        { key = "racials", label = "Racials", getList = function() return _G.TRINKETRACIALS and _G.TRINKETRACIALS.GetRacials and _G.TRINKETRACIALS.GetRacials() or {} end, isSpell = true },
        { key = "power", label = "Power Potions", getList = function() return _G.TRINKETRACIALS and _G.TRINKETRACIALS.GetPowerPotions and _G.TRINKETRACIALS.GetPowerPotions() or {} end, isSpell = false },
        { key = "healing", label = "Healing Potions", getList = function() return _G.TRINKETRACIALS and _G.TRINKETRACIALS.GetHealingPotions and _G.TRINKETRACIALS.GetHealingPotions() or {} end, isSpell = false },
    }) do
        itemTab.args["header_" .. cat.key] = {
            type = "header", name = cat.label, order = order,
        }
        order = order + 1

        -- Group assignment for the whole category
        itemTab.args["group_" .. cat.key] = {
            type = "select", name = cat.label .. " → Group", order = order,
            values = groupValues, width = 1,
            get = function()
                if _G.TRINKETRACIALS and _G.TRINKETRACIALS.GetIconGroupAssignments then
                    local a = _G.TRINKETRACIALS.GetIconGroupAssignments()
                    return a and a[cat.key] or 1
                end
                return 1
            end,
            set = function(_, val)
                if _G.TRINKETRACIALS and _G.TRINKETRACIALS.SetIconGroupAssignment then
                    _G.TRINKETRACIALS.SetIconGroupAssignment(cat.key, val)
                end
            end,
        }
        order = order + 1

        -- Show items/spells in the category with icons
        local list = cat.getList()
        for idx, id in ipairs(list) do
            local capturedId = id
            itemTab.args["catitem_" .. cat.key .. "_" .. idx] = {
                type = "description",
                name = function()
                    if cat.isSpell then return GetSpellName(capturedId) .. "  (ID: " .. capturedId .. ")" end
                    return GetItemName(capturedId) .. "  (ID: " .. capturedId .. ")"
                end,
                order = order,
                image = function()
                    if cat.isSpell then return GetSpellIcon(capturedId) end
                    return GetItemIcon(capturedId)
                end,
                imageWidth = 20, imageHeight = 20,
                width = "full",
            }
            order = order + 1
        end
    end

    -- ============================
    -- Build Sounds tab content
    -- ============================
    local soundTab = CCM.AceOptionsTable.args.trinketRacials.args.sounds

    local SOUND_CATEGORIES = {
        { key = "racials",     label = "Racials",         icon = function() return GetSpellIcon(RACIALS and RACIALS[1] or 0) end },
        { key = "trinket13",   label = "Trinket Slot 13", icon = function() return GetInventoryItemTexture("player", 13) or 134400 end },
        { key = "trinket14",   label = "Trinket Slot 14", icon = function() return GetInventoryItemTexture("player", 14) or 134400 end },
        { key = "power",       label = "Power Potion",    icon = function() return GetItemIcon(POWER_POTIONS and POWER_POTIONS[1] or 0) end },
        { key = "healing",     label = "Healing Potion",  icon = function() return GetItemIcon(HEALING_POTIONS and HEALING_POTIONS[1] or 0) end },
        { key = "healthstone", label = "Healthstone",     icon = function() return GetItemIcon(5512) end },
    }

    local function RACIALS_ref()
        return _G.TRINKETRACIALS and _G.TRINKETRACIALS.GetRacials and _G.TRINKETRACIALS.GetRacials() or {}
    end
    local function POWER_ref()
        return _G.TRINKETRACIALS and _G.TRINKETRACIALS.GetPowerPotions and _G.TRINKETRACIALS.GetPowerPotions() or {}
    end
    local function HEALING_ref()
        return _G.TRINKETRACIALS and _G.TRINKETRACIALS.GetHealingPotions and _G.TRINKETRACIALS.GetHealingPotions() or {}
    end

    SOUND_CATEGORIES[1].icon = function()
        local r = RACIALS_ref(); return (r[1] and GetSpellIcon(r[1])) or 134400
    end
    SOUND_CATEGORIES[4].icon = function()
        local p = POWER_ref(); return (p[1] and GetItemIcon(p[1])) or 134400
    end
    SOUND_CATEGORIES[5].icon = function()
        local h = HEALING_ref(); return (h[1] and GetItemIcon(h[1])) or 134400
    end

    local sOrder = 10
    for _, cat in ipairs(SOUND_CATEGORIES) do
        local capturedKey   = cat.key
        local capturedLabel = cat.label
        local capturedIcon  = cat.icon

        soundTab.args["sound_" .. capturedKey] = {
            type = "group",
            name = capturedLabel,
            inline = true,
            order = sOrder,
            args = {
                icon = {
                    type = "description", name = "", order = 1,
                    image = function()
                        local ok, tex = pcall(capturedIcon)
                        return (ok and tex) and tex or 134400, 24, 24
                    end,
                    width = 0.15,
                },
                enabled = {
                    type = "toggle", name = "Enabled", order = 2, width = 0.4,
                    get = function()
                        local db = GetDB(); db.itemSounds = db.itemSounds or {}
                        local cfg = db.itemSounds[capturedKey]
                        return type(cfg) == "table" and cfg.enabled == true
                    end,
                    set = function(_, v)
                        local db = GetDB(); db.itemSounds = db.itemSounds or {}
                        db.itemSounds[capturedKey] = db.itemSounds[capturedKey] or {}
                        db.itemSounds[capturedKey].enabled = v and true or false
                        SetAndRefresh("itemSounds", db.itemSounds)
                    end,
                },
                mode = {
                    type = "select", name = "Trigger", order = 3, width = 0.75,
                    values = { ready = "On Ready", cooldown = "On Cooldown", both = "Both" },
                    get = function()
                        local db = GetDB(); db.itemSounds = db.itemSounds or {}
                        local cfg = db.itemSounds[capturedKey]
                        return (type(cfg) == "table" and cfg.mode) or "ready"
                    end,
                    set = function(_, v)
                        local db = GetDB(); db.itemSounds = db.itemSounds or {}
                        db.itemSounds[capturedKey] = db.itemSounds[capturedKey] or {}
                        db.itemSounds[capturedKey].mode = v
                        SetAndRefresh("itemSounds", db.itemSounds)
                    end,
                },
                output = {
                    type = "select", name = "Output", order = 4, width = 0.7,
                    values = { sound = "Sound", tts = "TTS", both = "Sound + TTS" },
                    get = function()
                        local db = GetDB(); db.itemSounds = db.itemSounds or {}
                        local cfg = db.itemSounds[capturedKey]
                        return (type(cfg) == "table" and cfg.output) or "sound"
                    end,
                    set = function(_, v)
                        local db = GetDB(); db.itemSounds = db.itemSounds or {}
                        db.itemSounds[capturedKey] = db.itemSounds[capturedKey] or {}
                        db.itemSounds[capturedKey].output = v
                        SetAndRefresh("itemSounds", db.itemSounds)
                    end,
                },
                sound = {
                    type = "select", name = "Sound", order = 5, width = 1.2,
                    hidden = function()
                        local db = GetDB(); db.itemSounds = db.itemSounds or {}
                        local cfg = db.itemSounds[capturedKey]
                        return (type(cfg) == "table" and cfg.output) == "tts"
                    end,
                    values = function()
                        local db = GetDB(); db.itemSounds = db.itemSounds or {}
                        local cfg = db.itemSounds[capturedKey]
                        return TRGetSoundValues(type(cfg) == "table" and cfg.sound or "")
                    end,
                    get = function()
                        local db = GetDB(); db.itemSounds = db.itemSounds or {}
                        local cfg = db.itemSounds[capturedKey]
                        return (type(cfg) == "table" and cfg.sound) or ""
                    end,
                    set = function(_, v)
                        local db = GetDB(); db.itemSounds = db.itemSounds or {}
                        db.itemSounds[capturedKey] = db.itemSounds[capturedKey] or {}
                        db.itemSounds[capturedKey].sound = v
                        SetAndRefresh("itemSounds", db.itemSounds)
                    end,
                },
                ttsText = {
                    type = "input", name = "TTS Text", order = 6, width = 1.2,
                    desc = "Text to speak. Leave blank to use '" .. capturedLabel .. "'.",
                    hidden = function()
                        local db = GetDB(); db.itemSounds = db.itemSounds or {}
                        local cfg = db.itemSounds[capturedKey]
                        return (type(cfg) == "table" and cfg.output) == "sound"
                    end,
                    get = function()
                        local db = GetDB(); db.itemSounds = db.itemSounds or {}
                        local cfg = db.itemSounds[capturedKey]
                        return (type(cfg) == "table" and cfg.ttsText) or ""
                    end,
                    set = function(_, v)
                        local db = GetDB(); db.itemSounds = db.itemSounds or {}
                        db.itemSounds[capturedKey] = db.itemSounds[capturedKey] or {}
                        db.itemSounds[capturedKey].ttsText = tostring(v or "")
                        SetAndRefresh("itemSounds", db.itemSounds)
                    end,
                },
                test = {
                    type = "execute", name = "Test", order = 7, width = 0.4,
                    func = function()
                        local db = GetDB(); db.itemSounds = db.itemSounds or {}
                        local cfg = db.itemSounds[capturedKey]
                        if type(cfg) == "table" then
                            if _G.TRINKETRACIALS and _G.TRINKETRACIALS.TestSound then
                                _G.TRINKETRACIALS.TestSound(capturedKey, cfg, capturedLabel)
                            end
                        end
                    end,
                },
            },
        }
        sOrder = sOrder + 1
    end
end
