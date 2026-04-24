-- ============================================================
-- CkraigCooldownManager :: UI :: Options :: Power Potion
-- ============================================================
local CCM = _G.CkraigCooldownManager
local AceRegistry = LibStub("AceConfigRegistry-3.0")

local function GetDB()
    if PowerPotionSuccessIcon and PowerPotionSuccessIcon.GetSettings then
        return PowerPotionSuccessIcon:GetSettings()
    end
    return CCM.AceOpts.GetProfileData("powerPotionSuccessIcon")
end

local function Refresh()
    if PowerPotionSuccessIcon and PowerPotionSuccessIcon.RepositionIcons then
        PowerPotionSuccessIcon:RepositionIcons()
    end
end

local function GetItemOrSpellName(id)
    if _G.SafeGetSpellOrItemInfo then
        local name = _G.SafeGetSpellOrItemInfo(id)
        if name then return name end
    end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    if name then return name end
    name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    if name then return name end
    local itemName = GetItemInfo and select(1, GetItemInfo(id))
    if itemName then return itemName end
    return "ID: " .. tostring(id)
end

local function GetItemOrSpellIcon(id)
    if _G.SafeGetSpellOrItemInfo then
        local _, icon = _G.SafeGetSpellOrItemInfo(id)
        if icon then return icon end
    end
    local icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
    if icon then return icon end
    icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
    if icon then return icon end
    local _, _, _, _, _, _, _, _, _, itemIcon = GetItemInfo and GetItemInfo(id)
    if itemIcon then return itemIcon end
    return 134400
end

local function RebuildPotionListArgs(potionTab)
    for k in pairs(potionTab.args) do
        if k:find("^potion_") or k == "empty" then
            potionTab.args[k] = nil
        end
    end

    local db = GetDB()
    if not db or not db.powerPotionsList or #db.powerPotionsList == 0 then
        potionTab.args.empty = {
            type = "description",
            name = "|cff888888No potions tracked. Add potions using the input above.|r",
            order = 100,
            fontSize = "medium",
        }
        return
    end

    local durations = db.timerDurations or {}

    for i, potionID in ipairs(db.powerPotionsList) do
        local pid = tonumber(potionID) or 0
        local key = "potion_" .. i
        local capturedI = i

        potionTab.args[key] = {
            type = "group",
            name = function()
                if pid > 0 then return GetItemOrSpellName(pid) end
                return tostring(potionID)
            end,
            inline = true,
            order = 100 + i,
            args = {
                icon = {
                    type = "description",
                    name = "",
                    order = 1,
                    image = function()
                        if pid > 0 then return GetItemOrSpellIcon(pid), 24, 24 end
                        return 134400, 24, 24
                    end,
                    width = 0.15,
                },
                label = {
                    type = "description",
                    name = function()
                        if pid > 0 then
                            return "  " .. GetItemOrSpellName(pid) .. "  |cff888888(ID: " .. pid .. ")|r"
                        end
                        return "  " .. tostring(potionID)
                    end,
                    order = 2,
                    fontSize = "medium",
                    width = 1.0,
                },
                duration = {
                    type = "range",
                    name = "Duration (s)",
                    order = 3,
                    min = 1, max = 300, step = 1,
                    width = 0.7,
                    get = function()
                        local curDB = GetDB()
                        return curDB and curDB.timerDurations and curDB.timerDurations[pid] or 30
                    end,
                    set = function(_, val)
                        local curDB = GetDB()
                        if curDB then
                            curDB.timerDurations = curDB.timerDurations or {}
                            curDB.timerDurations[pid] = val
                        end
                    end,
                },
                remove = {
                    type = "execute",
                    name = "Remove",
                    order = 4,
                    width = 0.5,
                    confirm = true,
                    confirmText = "Remove this potion?",
                    func = function()
                        local curDB = GetDB()
                        if curDB and curDB.powerPotionsList then
                            table.remove(curDB.powerPotionsList, capturedI)
                            if curDB.timerDurations then
                                curDB.timerDurations[pid] = nil
                            end
                        end
                        if PowerPotionSuccessIcon and PowerPotionSuccessIcon.RefreshTrackedPotions then
                            PowerPotionSuccessIcon:RefreshTrackedPotions()
                        end
                        Refresh()
                        RebuildPotionListArgs(potionTab)
                        AceRegistry:NotifyChange("CkraigCooldownManager")
                    end,
                },
            },
        }
    end
end

function CCM.BuildPowerPotionOptions()
    local opts = CCM.AceOpts

    local potionTab = {
        type = "group",
        name = "Tracked Potions",
        order = 2,
        args = {
            addPotion = {
                type = "input",
                name = "Add Spell/Item ID",
                desc = "Enter a numeric spell or item ID to track",
                order = 1,
                width = "double",
                get = function() return "" end,
                set = function(_, val)
                    local id = tonumber(val)
                    if not id then return end
                    local db = GetDB()
                    if db then
                        db.powerPotionsList = db.powerPotionsList or {}
                        table.insert(db.powerPotionsList, id)
                        db.timerDurations = db.timerDurations or {}
                        db.timerDurations[id] = 30
                        if PowerPotionSuccessIcon and PowerPotionSuccessIcon.RefreshTrackedPotions then
                            PowerPotionSuccessIcon:RefreshTrackedPotions()
                        end
                        Refresh()
                        RebuildPotionListArgs(potionTab)
                        AceRegistry:NotifyChange("CkraigCooldownManager")
                    end
                end,
            },
            listHeader = {
                type = "header",
                name = "Current Tracked Potions",
                order = 10,
            },
        },
    }

    RebuildPotionListArgs(potionTab)

    CCM.AceOptionsTable.args.powerPotion = {
        type = "group",
        name = "Power Potion",
        order = 60,
        childGroups = "tab",
        args = {
            general = {
                type = "group",
                name = "General",
                order = 1,
                args = {
                    enabled = {
                        type = "toggle", name = "Enable Power Potion Success Icon", order = 1, width = "full",
                        get = function() local db = GetDB(); return db and db.enabled end,
                        set = function(_, val) local db = GetDB(); if db then db.enabled = val; Refresh() end end,
                    },
                    locked = {
                        type = "toggle", name = "Lock Icon Position", order = 2,
                        get = function() local db = GetDB(); return db and db.locked end,
                        set = function(_, val) local db = GetDB(); if db then db.locked = val; Refresh() end end,
                    },
                    showInDynamic = {
                        type = "toggle", name = "Show in Dynamic Icons", order = 3,
                        get = function() local db = GetDB(); return db and db.showInDynamic end,
                        set = function(_, val) local db = GetDB(); if db then db.showInDynamic = val; Refresh() end end,
                    },
                    showTimer = {
                        type = "toggle", name = "Show Timer", order = 4,
                        get = function() local db = GetDB(); return db and db.showTimer end,
                        set = function(_, val) local db = GetDB(); if db then db.showTimer = val; Refresh() end end,
                    },
                    iconSize = {
                        type = "range", name = "Icon Size", order = 5,
                        min = 20, max = 100, step = 1,
                        get = function() local db = GetDB(); return db and db.iconSize end,
                        set = function(_, val) local db = GetDB(); if db then db.iconSize = val; Refresh() end end,
                    },
                    clusterIndex = {
                        type = "range", name = "Target Cluster", order = 6,
                        min = 1, max = 20, step = 1,
                        get = function() local db = GetDB(); return db and db.clusterIndex or 1 end,
                        set = function(_, val) local db = GetDB(); if db then db.clusterIndex = val; Refresh() end end,
                    },
                    frameStrata = {
                        type = "select", name = "Frame Strata", order = 7,
                        values = opts.FRAME_STRATA_VALUES,
                        get = function() local db = GetDB(); return db and db.frameStrata end,
                        set = function(_, val) local db = GetDB(); if db then db.frameStrata = val; Refresh() end end,
                    },
                },
            },
            potions = potionTab,
        },
    }
end
