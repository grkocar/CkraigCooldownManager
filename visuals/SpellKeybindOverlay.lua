-- ============================================================
-- CkraigCooldownManager :: Visuals :: SpellKeybindOverlay
-- ============================================================
-- Displays keybind text on Essential and Utility Buff Tracker
-- cooldown icons. Reads from action bars via
-- C_ActionBar.FindSpellActionButtons and falls back to direct
-- spell-name bindings.
-- ============================================================

local CCM = _G.CkraigCooldownManager
if not CCM then return end

local LSM          = LibStub and LibStub("LibSharedMedia-3.0", true)
local AceRegistry  = LibStub and LibStub("AceConfigRegistry-3.0", true)

-- ============================================================
-- Saved-variable defaults
-- ============================================================
local DEFAULTS = {
    essentialsEnabled = false,
    utilityEnabled    = false,
    fontSize          = 10,
    font              = "Friz Quadrata TT",
    fontFlags         = "OUTLINE",
    position          = "BOTTOMLEFT",
    offsetX           = 2,
    offsetY           = 2,
    color             = { r = 1, g = 1, b = 1, a = 1 },
}

local function GetDB()
    if not MySpellKeybindOverlayDB then
        MySpellKeybindOverlayDB = {}
    end
    local db = MySpellKeybindOverlayDB
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then
            if type(v) == "table" then
                db[k] = {}
                for k2, v2 in pairs(v) do db[k][k2] = v2 end
            else
                db[k] = v
            end
        end
    end
    -- Ensure color sub-table is fully populated
    if type(db.color) ~= "table" then db.color = {} end
    for k, v in pairs(DEFAULTS.color) do
        if db.color[k] == nil then db.color[k] = v end
    end
    return db
end

-- ============================================================
-- Keybind resolution
-- ============================================================

-- Maps action-bar slot number → binding name string.
-- Formula: slot = (actionpage - 1) * 12 + buttonIndex
-- Verified against Blizzard's MultiActionBars.xml (actionpage attributes).
--
--   Main bar       actionpage 1  → slots   1– 12  → ACTIONBUTTON1-12
--   MultiBarRight  actionpage 3  → slots  25– 36  → MULTIACTIONBAR3BUTTON1-12
--   MultiBarLeft   actionpage 4  → slots  37– 48  → MULTIACTIONBAR4BUTTON1-12
--   MultiBarBotR   actionpage 5  → slots  49– 60  → MULTIACTIONBAR2BUTTON1-12
--   MultiBarBotL   actionpage 6  → slots  61– 72  → MULTIACTIONBAR1BUTTON1-12
--   MultiBar5      actionpage 13 → slots 145–156  → MULTIACTIONBAR5BUTTON1-12
--   MultiBar6      actionpage 14 → slots 157–168  → MULTIACTIONBAR6BUTTON1-12
--   MultiBar7      actionpage 15 → slots 169–180  → MULTIACTIONBAR7BUTTON1-12
-- Pages 2,7-12 are paged main-bar variants (DH meta, shapeshifts, etc.) and
-- share ACTIONBUTTON bindings since they use the same physical buttons.
local function GetActionBarBindingForSlot(slot)
    if slot >= 1   and slot <= 12  then return "ACTIONBUTTON"          .. slot          end
    if slot >= 25  and slot <= 36  then return "MULTIACTIONBAR3BUTTON" .. (slot - 24)   end
    if slot >= 37  and slot <= 48  then return "MULTIACTIONBAR4BUTTON" .. (slot - 36)   end
    if slot >= 49  and slot <= 60  then return "MULTIACTIONBAR2BUTTON" .. (slot - 48)   end
    if slot >= 61  and slot <= 72  then return "MULTIACTIONBAR1BUTTON" .. (slot - 60)   end
    if slot >= 145 and slot <= 156 then return "MULTIACTIONBAR5BUTTON" .. (slot - 144)  end
    if slot >= 157 and slot <= 168 then return "MULTIACTIONBAR6BUTTON" .. (slot - 156)  end
    if slot >= 169 and slot <= 180 then return "MULTIACTIONBAR7BUTTON" .. (slot - 168)  end
    -- Paged main-bar variants (actionpages 2, 7–12): same physical buttons → same bindings
    if slot >= 13 and slot <= 144 then
        return "ACTIONBUTTON" .. (((slot - 1) % 12) + 1)
    end
    return nil
end

local function FormatKeybindText(key)
    if not key or key == "" then return nil end
    key = key:upper()
    key = key:gsub("ALT%-",          "A-")
    key = key:gsub("CTRL%-",         "C-")
    key = key:gsub("SHIFT%-",        "S-")
    key = key:gsub("NUMPAD",         "NP")
    key = key:gsub("BUTTON(%d+)",    "M%1")
    key = key:gsub("SPACE",          "SPC")
    key = key:gsub("MOUSEWHEELUP",   "WU")
    key = key:gsub("MOUSEWHEELDOWN", "WD")
    key = key:gsub("BACKSPACE",      "BS")
    key = key:gsub("DELETE",         "DEL")
    key = key:gsub("INSERT",         "INS")
    key = key:gsub("HOME",           "HM")
    key = key:gsub("PAGEUP",         "PU")
    key = key:gsub("PAGEDOWN",       "PD")
    return key
end

-- [spellID] = formatted string  or  false (cache miss)
local _keybindCache = {}

local function ClearKeybindCache()
    for k in pairs(_keybindCache) do _keybindCache[k] = nil end
end

local function GetSpellKeybind(spellID)
    if not spellID then return nil end
    local sid = tonumber(spellID)
    if not sid then return nil end

    local cached = _keybindCache[sid]
    if cached ~= nil then
        return cached ~= false and cached or nil
    end

    local result = nil

    -- ── Method 1: C_ActionBar.FindSpellActionButtons (most reliable) ──
    if C_ActionBar and C_ActionBar.FindSpellActionButtons then
        local ok, slots = pcall(C_ActionBar.FindSpellActionButtons, sid)
        if ok and slots then
            for _, slot in ipairs(slots) do
                local bindName = GetActionBarBindingForSlot(slot)
                if bindName then
                    local key = GetBindingKey(bindName)
                    if key and key ~= "" then
                        result = FormatKeybindText(key)
                        break
                    end
                end
            end
        end
    end

    -- ── Method 2: Try talent override (e.g. Berserk → Incarnation) ──
    if not result and FindSpellOverrideByID then
        local ok2, override = pcall(FindSpellOverrideByID, sid)
        if ok2 and override and override ~= sid and C_ActionBar and C_ActionBar.FindSpellActionButtons then
            local ok3, slots2 = pcall(C_ActionBar.FindSpellActionButtons, override)
            if ok3 and slots2 then
                for _, slot in ipairs(slots2) do
                    local bindName = GetActionBarBindingForSlot(slot)
                    if bindName then
                        local key = GetBindingKey(bindName)
                        if key and key ~= "" then
                            result = FormatKeybindText(key)
                            break
                        end
                    end
                end
            end
        end
    end

    -- ── Method 3: Direct spell-name binding ──
    if not result then
        local spellName = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(sid)
        if spellName then
            local key = GetBindingKey("SPELL " .. spellName)
            if key and key ~= "" then
                result = FormatKeybindText(key)
            end
        end
    end

    _keybindCache[sid] = result or false
    return result
end

-- ============================================================
-- Icon spell-ID extraction (mirrors GetUtilityIconKey logic)
-- ============================================================
local function GetIconSpellID(icon)
    if not icon then return nil end

    -- Primary: cooldownID → C_CooldownViewer lookup
    local cdID = icon.cooldownID
    if cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
        local ok, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
        if ok and info then
            local sid = info.spellID
            if sid then return tonumber(sid) end
        end
    end

    -- Fallback: direct .spellID field
    if icon.spellID then return tonumber(icon.spellID) end

    return nil
end

-- ============================================================
-- Per-icon overlay FontString
-- ============================================================
local function GetOrCreateKeybindLabel(icon)
    if not icon then return nil end
    if not icon._ccmKeybindLabel then
        local fs = icon:CreateFontString(nil, "OVERLAY", nil, 7)
        fs:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        fs:SetTextColor(1, 1, 1, 1)
        fs:Hide()
        icon._ccmKeybindLabel = fs
    end
    return icon._ccmKeybindLabel
end

local function ApplyKeybindToIcon(icon, db)
    local fs = GetOrCreateKeybindLabel(icon)
    if not fs then return end

    local spellID = GetIconSpellID(icon)
    local keybind = spellID and GetSpellKeybind(spellID)
    if not keybind then
        fs:Hide()
        return
    end

    -- Resolve font path via SharedMedia
    local fontPath = "Fonts\\FRIZQT__.TTF"
    local dbFont   = db.font or DEFAULTS.font
    if LSM and dbFont and dbFont ~= "" then
        local resolved = LSM:Fetch("font", dbFont, true)
        if resolved and resolved ~= "" then fontPath = resolved end
    end

    local fontSize  = tonumber(db.fontSize)  or DEFAULTS.fontSize
    local fontFlags = db.fontFlags            or DEFAULTS.fontFlags

    -- Per-FontString font cache so every icon gets its own SetFont call
    if fs._ccmFontPath ~= fontPath or fs._ccmFontSize ~= fontSize or fs._ccmFontFlags ~= fontFlags then
        fs:SetFont(fontPath, fontSize, fontFlags)
        fs._ccmFontPath  = fontPath
        fs._ccmFontSize  = fontSize
        fs._ccmFontFlags = fontFlags
    end

    local c = db.color or DEFAULTS.color
    local cr, cg, cb, ca = c.r or 1, c.g or 1, c.b or 1, c.a or 1
    if fs._ccmColorR ~= cr or fs._ccmColorG ~= cg or fs._ccmColorB ~= cb or fs._ccmColorA ~= ca then
        fs:SetTextColor(cr, cg, cb, ca)
        fs._ccmColorR, fs._ccmColorG, fs._ccmColorB, fs._ccmColorA = cr, cg, cb, ca
    end

    -- Position: re-anchor every time (icon size may have changed)
    local pos = db.position or DEFAULTS.position
    local ox  = tonumber(db.offsetX) or DEFAULTS.offsetX
    local oy  = tonumber(db.offsetY) or DEFAULTS.offsetY
    fs:ClearAllPoints()
    fs:SetPoint(pos, icon, pos, ox, oy)

    fs:SetText(keybind)
    fs:Show()
end

local function HideKeybindOnIcon(icon)
    if icon and icon._ccmKeybindLabel then
        icon._ccmKeybindLabel:Hide()
    end
end

-- ============================================================
-- Update all visible icons for a single viewer
-- ============================================================
local function UpdateViewerKeybinds(viewerName, enabled, db)
    local viewer = _G[viewerName]
    if not viewer then return end
    local pool = viewer.itemFramePool
    if not pool then return end
    for icon in pool:EnumerateActive() do
        if icon then
            if enabled and icon:IsShown() then
                ApplyKeybindToIcon(icon, db)
            else
                HideKeybindOnIcon(icon)
            end
        end
    end
end

-- ============================================================
-- Top-level refresh — called by ticker and hooks
-- ============================================================
local function UpdateAllKeybindOverlays()
    local db = GetDB()
    -- Force font re-apply on next pass by clearing per-FontString caches
    -- (done implicitly — changing db values will mismatch stored fs._ccmFontSize etc.)
    UpdateViewerKeybinds("EssentialCooldownViewer", db.essentialsEnabled, db)
    UpdateViewerKeybinds("UtilityCooldownViewer",   db.utilityEnabled,    db)
end

CCM.RefreshKeybindOverlays = function()
    ClearKeybindCache()
    UpdateAllKeybindOverlays()
end

-- ============================================================
-- Hooks on the layout methods so overlays update immediately
-- after any layout pass, without waiting for the ticker.
-- Both MyEssentialIconViewers and UtilityIconViewers are globals.
-- ============================================================
local function HookViewerLayouts()
    if MyEssentialIconViewers and MyEssentialIconViewers.ApplyViewerLayout then
        local orig = MyEssentialIconViewers.ApplyViewerLayout
        MyEssentialIconViewers.ApplyViewerLayout = function(self, viewer, ...)
            local r = orig(self, viewer, ...)
            C_Timer.After(0, UpdateAllKeybindOverlays)
            return r
        end
    end

    if UtilityIconViewers and UtilityIconViewers.ApplyViewerLayout then
        local orig = UtilityIconViewers.ApplyViewerLayout
        UtilityIconViewers.ApplyViewerLayout = function(self, viewer, ...)
            local r = orig(self, viewer, ...)
            C_Timer.After(0, UpdateAllKeybindOverlays)
            return r
        end
    end
end

-- ============================================================
-- Init frame: events + periodic ticker
-- ============================================================
local _ticker = nil

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("UPDATE_BINDINGS")
initFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
initFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        GetDB()
        HookViewerLayouts()
        -- Slight delay so all other addon PLAYER_LOGIN handlers finish first
        C_Timer.After(1, function()
            -- Build and register options tab
            if CCM.BuildSpellKeybindOptions then
                CCM.BuildSpellKeybindOptions()
                if AceRegistry then
                    AceRegistry:NotifyChange("CkraigCooldownManager")
                end
            end
            ClearKeybindCache()
            UpdateAllKeybindOverlays()
        end)
        -- 0.25s ticker keeps overlays correct during combat icon changes
        if not _ticker then
            _ticker = C_Timer.NewTicker(0.25, UpdateAllKeybindOverlays)
        end
    elseif event == "UPDATE_BINDINGS" or event == "ACTIONBAR_SLOT_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
        ClearKeybindCache()
        UpdateAllKeybindOverlays()
    end
end)
