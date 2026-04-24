-- CkraigCooldownManager Global Glow System (Refactored)
-- Robust, modular, profile-based global glow manager for all viewers

local _, CCM = ...
CCM = CCM or {}
_G.CkraigGlowManager = CCM
local LibCustomGlow = LibStub and LibStub("LibCustomGlow-1.0", true)

local activeGlows = {}
local frameGlowTypeState = setmetatable({}, { __mode = "k" })
local frameGlowConfigState = setmetatable({}, { __mode = "k" })
local frameGlowRenderTargetState = setmetatable({}, { __mode = "k" })
local frameAlertActiveState = setmetatable({}, { __mode = "k" })
local frameAlertStartTimeState = setmetatable({}, { __mode = "k" })
local alertToGlowTargetState = setmetatable({}, { __mode = "k" })
local pendingGlowStartState = setmetatable({}, { __mode = "k" })
local pendingGlowStopState = setmetatable({}, { __mode = "k" })
local cachedGlowTargets = setmetatable({}, { __mode = "k" }) -- frame â†’ resolved glow target cache
local BuildGlowConfigSignature
local cachedGlowSignature = nil  -- cached signature string, nil = dirty
local cachedGlowType = nil       -- cached glow type at time of signature build
local ENABLE_COOLDOWNVIEWER_VISUAL_HOOKS = false  -- Blizzard CooldownViewer visual alerts are left alone
local MIN_ALERT_GLOW_DURATION = 0.35

-- ===============================
-- CPU Optimization: Event-driven batching, dirty flags, strict throttling
-- ===============================
local _glow_dirty = false
local _glow_batchFrame = CreateFrame("Frame")
_glow_batchFrame:Hide()
local _glow_lastUpdate = 0
local _glow_throttle = 0.15 -- seconds

local function MarkGlowDirty(reason)
    _glow_dirty = true
    _glow_batchFrame:Show()
end

local function UpdateGlowBatch()
    if not _glow_dirty then _glow_batchFrame:Hide(); return end
    _glow_dirty = false
    _glow_batchFrame:Hide()
    CCM.RefreshCustomGlows()
end

_glow_batchFrame:SetScript("OnUpdate", function(self, elapsed)
    _glow_lastUpdate = _glow_lastUpdate + elapsed
    if _glow_lastUpdate >= _glow_throttle then
        _glow_lastUpdate = 0
        UpdateGlowBatch()
    end
end)

-- Hook glow events â€” only listen for combat transitions and init events
-- SPELL_UPDATE_COOLDOWN/UNIT_AURA removed: glow system checks state on combat enter/leave
local function SetupGlowEventHooks()
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("PLAYER_LOGIN")
    ef:RegisterEvent("PLAYER_ENTERING_WORLD")
    ef:RegisterEvent("PLAYER_REGEN_DISABLED")
    ef:RegisterEvent("PLAYER_REGEN_ENABLED")
    ef:SetScript("OnEvent", function(self, event, ...)
        if event == "PLAYER_REGEN_ENABLED" then
            _glow_dirty = true
            UpdateGlowBatch()
            return
        elseif event == "PLAYER_REGEN_DISABLED" then
            MarkGlowDirty(event)
        else
            MarkGlowDirty(event)
        end
    end)
end

SetupGlowEventHooks()

-- Utility: Normalize value
local function NormalizeValue(value, defaultValue)
    if value == nil then return defaultValue end
    return value
end

-- Utility: Normalize color table (reuses output table to avoid allocation)
local _gm_colorOut = {1, 1, 1, 1}
local function NormalizeColor(color, fallback)
    if type(color) ~= "table" then color = fallback or _gm_colorOut end
    local fallbackColor = fallback or _gm_colorOut

    local c1 = color[1] ~= nil and color[1] or color.r
    local c2 = color[2] ~= nil and color[2] or color.g
    local c3 = color[3] ~= nil and color[3] or color.b
    local c4 = color[4] ~= nil and color[4] or color.a

    return {
        NormalizeValue(c1, fallbackColor[1]),
        NormalizeValue(c2, fallbackColor[2]),
        NormalizeValue(c3, fallbackColor[3]),
        NormalizeValue(c4, fallbackColor[4]),
    }
end

-- Utility: Normalize glow type string
local function NormalizeGlowType(glowType)
    if not glowType then return nil end
    local normalized = tostring(glowType):lower()
    if normalized:find("pixel") then return "Pixel" end
    if normalized:find("autocast") then return "Autocast" end
    if normalized:find("button") then return "Button" end
    return nil
end

local function GetGlowStorage()
    _G.CkraigCooldownManagerDB = _G.CkraigCooldownManagerDB or {}
    _G.CkraigCooldownManagerDB.globalGlow = _G.CkraigCooldownManagerDB.globalGlow or {}
    local storage = _G.CkraigCooldownManagerDB.globalGlow

    if _G.CkraigGlobalGlowSettings and _G.CkraigGlobalGlowSettings.Glow and not storage.Glow then
        storage.Glow = _G.CkraigGlobalGlowSettings.Glow
    end

    return storage
end

-- Normalize and migrate settings
function CCM.NormalizeGlowSettings()
    local db = GetGlowStorage()
    db.Glow = db.Glow or {}
    local glow = db.Glow

    local normalizedType = NormalizeGlowType(glow.Type)
    glow.Type = normalizedType or "Pixel"
    glow.Enabled = NormalizeValue(glow.Enabled, false)
    glow.CommonThickness = NormalizeValue(glow.CommonThickness, nil)

    local legacyColor = glow.Colour

    glow.Pixel = glow.Pixel or {}
    glow.Pixel.Color = NormalizeColor(glow.Pixel.Color or legacyColor, {1,1,1,1})
    glow.Pixel.Lines = NormalizeValue(glow.Pixel.Lines or glow.Lines, 5)
    glow.Pixel.Frequency = NormalizeValue(glow.Pixel.Frequency or glow.Frequency, 0.25)
    glow.Pixel.Length = NormalizeValue(glow.Pixel.Length, 2)
    glow.Pixel.Thickness = NormalizeValue(glow.Pixel.Thickness or glow.Thickness, 1)
    glow.Pixel.XOffset = NormalizeValue(glow.Pixel.XOffset or glow.XOffset, -1)
    glow.Pixel.YOffset = NormalizeValue(glow.Pixel.YOffset or glow.YOffset, -1)
    glow.Pixel.Border = NormalizeValue(glow.Pixel.Border, false)

    glow.Autocast = glow.Autocast or {}
    glow.Autocast.Color = NormalizeColor(glow.Autocast.Color or legacyColor, {1,1,1,1})
    glow.Autocast.Particles = NormalizeValue(glow.Autocast.Particles or glow.Particles, 10)
    glow.Autocast.Frequency = NormalizeValue(glow.Autocast.Frequency or glow.Frequency, 0.25)
    glow.Autocast.Scale = NormalizeValue(glow.Autocast.Scale or glow.Scale, 1)
    glow.Autocast.XOffset = NormalizeValue(glow.Autocast.XOffset or glow.XOffset, -1)
    glow.Autocast.YOffset = NormalizeValue(glow.Autocast.YOffset or glow.YOffset, -1)

    glow.Proc = glow.Proc or {}
    glow.Proc.Color = NormalizeColor(glow.Proc.Color or legacyColor, {1,1,1,1})
    glow.Proc.StartAnim = NormalizeValue(glow.Proc.StartAnim, true)
    glow.Proc.Duration = NormalizeValue(glow.Proc.Duration, 1)
    glow.Proc.XOffset = NormalizeValue(glow.Proc.XOffset, 0)
    glow.Proc.YOffset = NormalizeValue(glow.Proc.YOffset, 0)

    glow.Button = glow.Button or {}
    glow.Button.Color = NormalizeColor(glow.Button.Color or legacyColor, {1,1,1,1})
    glow.Button.Frequency = NormalizeValue(glow.Button.Frequency, 0.125)

    if glow.CommonThickness == nil then
        glow.CommonThickness = NormalizeValue(glow.Pixel.Thickness, 1)
    end
    glow.CommonThickness = math.max(1, math.min(8, glow.CommonThickness))
    glow.Pixel.Thickness = glow.CommonThickness

    _G.CkraigGlobalGlowSettings = db
    return glow
end

function CCM.GetCustomGlowSettings()
    return CCM.NormalizeGlowSettings()
end


function CCM.StartCustomGlow(frame)
    if not frame or not LibCustomGlow then return end
    local glow = CCM.GetCustomGlowSettings()
    if not glow or not glow.Enabled then return end

    local glowType = glow.Type or "Pixel"
    local thickness = glow.CommonThickness or 1

    -- Build config signature to avoid redundant stop/start when nothing changed
    local sig = BuildGlowConfigSignature(glowType, glow, thickness)
    if frameGlowTypeState[frame] == glowType and frameGlowConfigState[frame] == sig then
        return -- already showing the correct glow
    end

    -- Stop previous glow if type or config changed
    if activeGlows[frame] then
        CCM.StopCustomGlow(frame)
    end

    if glowType == "Pixel" then
        local s = glow.Pixel or {}
        local color = s.Color or {1,1,1,1}
        LibCustomGlow.PixelGlow_Start(frame, color,
            s.Lines or 5, s.Frequency or 0.25, s.Length or 2,
            thickness, s.XOffset or -1, s.YOffset or -1,
            s.Border or false, "ccmGlow")
    elseif glowType == "Autocast" then
        local s = glow.Autocast or {}
        local color = s.Color or {1,1,1,1}
        local scaledScale = (s.Scale or 1) * (0.75 + ((thickness - 1) * 0.18))
        LibCustomGlow.AutoCastGlow_Start(frame, color,
            s.Particles or 10, s.Frequency or 0.25,
            scaledScale, s.XOffset or -1, s.YOffset or -1, "ccmGlow")
    elseif glowType == "Button" then
        local s = glow.Button or {}
        local color = s.Color or {1,1,1,1}
        local boostedFrequency = math.max(0.03, (s.Frequency or 0.125) / (0.75 + ((thickness - 1) * 0.2)))
        LibCustomGlow.ButtonGlow_Start(frame, color, boostedFrequency)
    end

    activeGlows[frame] = true
    frameGlowTypeState[frame] = glowType
    frameGlowConfigState[frame] = sig
end

function CCM.StopCustomGlow(frame)
    if not frame or not LibCustomGlow then return end
    local prevType = frameGlowTypeState[frame]
    if prevType == "Autocast" then
        LibCustomGlow.AutoCastGlow_Stop(frame, "ccmGlow")
    elseif prevType == "Button" then
        LibCustomGlow.ButtonGlow_Stop(frame)
    else
        LibCustomGlow.PixelGlow_Stop(frame, "ccmGlow")
    end
    activeGlows[frame] = nil
    frameGlowTypeState[frame] = nil
    frameGlowConfigState[frame] = nil
end

function CCM.StopAllCustomGlows()
    for frame in pairs(activeGlows) do
        CCM.StopCustomGlow(frame)
    end
end

function CCM.DisableCustomGlowsNow()
    for frame in pairs(frameAlertActiveState) do
        frameAlertActiveState[frame] = nil
        frameAlertStartTimeState[frame] = nil
    end

    CCM.StopAllCustomGlows()
end

function CCM.RefreshCustomGlows()
    cachedGlowSignature = nil  -- invalidate signature cache on settings change
    local glow = CCM.GetCustomGlowSettings()
    if not glow or not glow.Enabled then
        CCM.DisableCustomGlowsNow()
        return
    end
    for frame in pairs(activeGlows) do
        CCM.StartCustomGlow(frame)
    end
end

-- Blizzard override: ActionButtonSpellAlertManager hooks
local function GetCooldownViewerChild(frame)
    if not frame or not frame.GetParent then return nil end

    local viewers = _G.CkraigCooldownManagerViewers or {
        "EssentialCooldownViewer",
        "UtilityCooldownViewer",
        "BuffIconCooldownViewer",
        "BuffBarCooldownViewer",
    }

    local current = frame
    while current and current.GetParent do
        local parent = current:GetParent()
        if not parent then return nil end

        for _, viewerName in ipairs(viewers) do
            if parent == _G[viewerName] then
                return current
            end
        end

        current = parent
    end

    return nil
end

local function IsGlowFrameSizeSafe(frame)
    if not frame or not frame.GetWidth or not frame.GetHeight then
        return false
    end

    local width = tonumber(frame:GetWidth()) or 0
    local height = tonumber(frame:GetHeight()) or 0
    if width <= 0 or height <= 0 then
        return false
    end

    if width > 500 or height > 220 then
        return false
    end

    return true
end

local function IsLikelyGlowAnchor(frame)
    if not frame then return false end
    if frame.Cooldown or frame.Icon or frame.icon or frame.Bar then
        return true
    end
    if frame.GetCooldownInfo or frame.GetSpellID or frame.GetCooldownID then
        return true
    end
    return false
end

local function ResolveSafeGlowTarget(frame)
    local candidate = GetCooldownViewerChild(frame) or frame
    local current = candidate

    for _ = 1, 6 do
        if not current then break end
        if IsLikelyGlowAnchor(current) and IsGlowFrameSizeSafe(current) then
            return current
        end
        current = current.GetParent and current:GetParent() or nil
    end

    if IsGlowFrameSizeSafe(candidate) then
        return candidate
    end

    return nil
end

local function GetGlowTarget(frame)
    if not frame then return nil end
    local cached = cachedGlowTargets[frame]
    if cached ~= nil then return cached end -- false = previously resolved to nil
    local target = ResolveSafeGlowTarget(frame)
    cachedGlowTargets[frame] = target or false
    return target
end

local function StopAlertGlowNow(frame)
    if not frame then return end
    pendingGlowStartState[frame] = nil
    pendingGlowStopState[frame] = nil
    frameAlertActiveState[frame] = nil
    frameAlertStartTimeState[frame] = nil
    CCM.StopCustomGlow(frame)
end

local function ResolveVisualAlertGlowTarget(target)
    if not target then return nil end
    local targetFrame = target
    if target.GetAlertTargetFrame then
        targetFrame = target:GetAlertTargetFrame()
    end
    return GetGlowTarget(targetFrame)
end

function CCM.SetupCustomGlows()
    if CCM.CustomGlowHooksSet then return end
    CCM.CustomGlowHooksSet = true

    if not CCM.ActionButtonHooksSet and ActionButtonSpellAlertManager then
        CCM.ActionButtonHooksSet = true
        hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", function(_, frame)
            local activeGlowTarget = GetGlowTarget(frame)
            if not activeGlowTarget then return end

            -- Glow system disabled: let Blizzard's proc animation show normally.
            local glow = CCM.GetCustomGlowSettings()
            if not glow or not glow.Enabled then return end

            if frameAlertActiveState[activeGlowTarget] then
                pendingGlowStopState[activeGlowTarget] = nil
                frameAlertStartTimeState[activeGlowTarget] = GetTime()
                if frame and frame.SpellActivationAlert then
                    frame.SpellActivationAlert:Hide()
                end
                if activeGlowTarget.SpellActivationAlert then
                    activeGlowTarget.SpellActivationAlert:Hide()
                end
                CCM.StartCustomGlow(activeGlowTarget)
                return
            end

            frameAlertActiveState[activeGlowTarget] = true
            pendingGlowStopState[activeGlowTarget] = nil
            frameAlertStartTimeState[activeGlowTarget] = GetTime()
            if frame and frame.SpellActivationAlert then
                frame.SpellActivationAlert:Hide()
            end
            if activeGlowTarget.SpellActivationAlert then
                activeGlowTarget.SpellActivationAlert:Hide()
            end
            if pendingGlowStartState[activeGlowTarget] then
                return
            end
            pendingGlowStartState[activeGlowTarget] = true

            C_Timer.After(0, function()
                pendingGlowStartState[activeGlowTarget] = nil
                if frameAlertActiveState[activeGlowTarget] then
                    CCM.StartCustomGlow(activeGlowTarget)
                end
            end)
        end)

        hooksecurefunc(ActionButtonSpellAlertManager, "HideAlert", function(_, frame)
            local activeGlowTarget = GetGlowTarget(frame)
            if not activeGlowTarget then return end

            -- Glow system disabled: let Blizzard handle the hide.
            local glow = CCM.GetCustomGlowSettings()
            if not glow or not glow.Enabled then return end

            frameAlertActiveState[activeGlowTarget] = nil
            frameAlertStartTimeState[activeGlowTarget] = nil
            StopAlertGlowNow(activeGlowTarget)
        end)
    end

    -- CooldownViewer visual alerts are Blizzard's built-in system — don't intercept them
    -- Custom icon glows for Essential/Utility are handled by their own per-spell glow dispatch
end

-- Initialize hooks after login
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(_, event, arg1)
    if CCM and CCM.SetupCustomGlows then
        if event == "PLAYER_LOGIN" or (event == "ADDON_LOADED" and arg1 == "Blizzard_CooldownViewer") then
            CCM.SetupCustomGlows()
        end
    end
end)

local GLOW_STYLES = {"Pixel", "Autocast", "Button"}
local GLOW_LABELS = {
    Pixel = "Pixel Glow",
    Autocast = "AutoCast Glow",
    Button = "Button Glow",
}

local function GetStyleColor(style)
    local glow = CCM.GetCustomGlowSettings()
    local cfg = glow and glow[style]
    local color = cfg and cfg.Color or {1, 1, 1, 1}
    return color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1
end

local function SetStyleColor(style, r, g, b, a)
    local glow = CCM.GetCustomGlowSettings()
    glow[style] = glow[style] or {}
    glow[style].Color = {r or 1, g or 1, b or 1, a or 1}
    CCM.RefreshCustomGlows()
end

local function ResetAllGlowColorsToDefault()
    local glow = CCM.GetCustomGlowSettings()
    glow.Pixel = glow.Pixel or {}
    glow.Autocast = glow.Autocast or {}
    glow.Proc = glow.Proc or {}
    glow.Button = glow.Button or {}

    glow.Pixel.Color = {1, 1, 1, 1}
    glow.Autocast.Color = {1, 1, 1, 1}
    glow.Proc.Color = {1, 1, 1, 1}
    glow.Button.Color = {1, 1, 1, 1}

    CCM.RefreshCustomGlows()
end

local function OpenStyleColorPicker(style, swatchTexture)
    local r, g, b, a = GetStyleColor(style)

    local function updateFromPicker()
        local newR, newG, newB = ColorPickerFrame:GetColorRGB()
        local newA = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or a
        SetStyleColor(style, newR, newG, newB, newA)
        if swatchTexture and swatchTexture.SetColorTexture then
            swatchTexture:SetColorTexture(newR, newG, newB, newA)
        end
    end

    if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            swatchFunc = updateFromPicker,
            opacityFunc = updateFromPicker,
            cancelFunc = function(previousValues)
                if previousValues then
                    local pr = previousValues.r or r
                    local pg = previousValues.g or g
                    local pb = previousValues.b or b
                    local pa = previousValues.a or previousValues.opacity or a
                    SetStyleColor(style, pr, pg, pb, pa)
                    if swatchTexture and swatchTexture.SetColorTexture then
                        swatchTexture:SetColorTexture(pr, pg, pb, pa)
                    end
                end
            end,
            hasOpacity = true,
            opacity = a,
            r = r,
            g = g,
            b = b,
        })
    end
end

-- Options panel

-- Old CreateGlowOptionsPanel removed; options are now handled by Ace3 AceConfig (ui/options/GlowOptions.lua)
local function CreateGlowOptionsPanel() return nil end

BuildGlowConfigSignature = function(glowType, glow, thickness)
    if glowType == "Pixel" then
        local s = glow.Pixel or {}
        local c = s.Color
        return string.format("%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s",
            thickness, s.Lines or "", s.Frequency or "", s.Length or "",
            s.XOffset or "", s.YOffset or "", s.Border or "",
            c and c[1] or "", c and c[2] or "", c and c[3] or "", c and c[4] or "")
    elseif glowType == "Autocast" then
        local s = glow.Autocast or {}
        local scaledScale = (s.Scale or 1) * (0.75 + ((thickness - 1) * 0.18))
        local c = s.Color
        return string.format("%s|%s|%s|%s|%s|%s|%s|%s|%s",
            s.Particles or "", s.Frequency or "", scaledScale,
            s.XOffset or "", s.YOffset or "",
            c and c[1] or "", c and c[2] or "", c and c[3] or "", c and c[4] or "")
    elseif glowType == "Button" then
        local s = glow.Button or {}
        local boostedFrequency = math.max(0.03, (s.Frequency or 0.125) / (0.75 + ((thickness - 1) * 0.2)))
        local c = s.Color
        return string.format("%s|%s|%s|%s|%s",
            boostedFrequency,
            c and c[1] or "", c and c[2] or "", c and c[3] or "", c and c[4] or "")
    end
    return ""
end
