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
local auraOverrideHookedCooldowns = setmetatable({}, { __mode = "k" })
local auraOverrideBypassState = setmetatable({}, { __mode = "k" })
local cachedGlowTargets = setmetatable({}, { __mode = "k" }) -- frame → resolved glow target cache
local BuildGlowConfigSignature
local cachedGlowSignature = nil  -- cached signature string, nil = dirty
local cachedGlowType = nil       -- cached glow type at time of signature build
local ENABLE_COOLDOWNVIEWER_VISUAL_HOOKS = false  -- Blizzard CooldownViewer visual alerts are left alone

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

-- Hook glow events — only listen for combat transitions and init events
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

-- Utility: Normalize color table
local function NormalizeColor(color, fallback)
    if type(color) ~= "table" then color = fallback or {1,1,1,1} end
    local fallbackColor = fallback or {1,1,1,1}

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
    if glow.IgnoreAuraOverride == nil then
        if glow.AllowAuraOverrideGlow ~= nil then
            glow.IgnoreAuraOverride = not glow.AllowAuraOverrideGlow
        else
            glow.IgnoreAuraOverride = false
        end
    end
    glow.AllowAuraOverrideGlow = nil
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

local function IsEssentialOrUtilityViewerTarget(frame)
    if not frame or not frame.GetParent then return false end

    local current = frame
    while current and current.GetParent do
        local parent = current:GetParent()
        if not parent then return false end

        -- Essential uses per-spell assignment glows; block global alert glows there.
        if parent == _G.UtilityCooldownViewer then
            return true
        end

        if parent == _G.EssentialCooldownViewer then
            return false
        end

        current = parent
    end

    return false
end

local function IsAuraOverrideScopeTarget(target)
    if not target then return false end

    local targetFrame = target
    if target.GetAlertTargetFrame then
        targetFrame = target:GetAlertTargetFrame()
    end

    local viewerChild = GetGlowTarget(targetFrame)
    local frameToCheck = viewerChild or targetFrame
    return IsEssentialOrUtilityViewerTarget(frameToCheck)
end

local function StopAlertGlowNow(frame)
    if not frame then return end
    pendingGlowStartState[frame] = nil
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

local function HasActiveAuraOnTarget(target)
    if not target then return false end

    local auraInstanceID
    if target.GetAuraSpellInstanceID then
        auraInstanceID = target:GetAuraSpellInstanceID()
    else
        auraInstanceID = target.auraInstanceID
    end
    if type(auraInstanceID) == "number" and auraInstanceID > 0 then
        return true
    end

    local auraSpellID
    if target.GetAuraSpellID then
        auraSpellID = target:GetAuraSpellID()
    else
        auraSpellID = target.auraSpellID
    end

    return type(auraSpellID) == "number" and auraSpellID > 0
end

local function ShouldIgnoreAuraOverrideForTarget(target)
    local glow = CCM.GetCustomGlowSettings()
    if not glow or not glow.IgnoreAuraOverride then
        return false
    end

    if not IsAuraOverrideScopeTarget(target) then
        return false
    end

    if HasActiveAuraOnTarget(target) then
        return true
    end

    return false
end

local function GetAuraOverrideSpellID(iconFrame)
    if not iconFrame then return nil end

    local cooldownInfo
    if iconFrame.GetCooldownInfo then
        cooldownInfo = iconFrame:GetCooldownInfo()
    end

    if cooldownInfo then
        local spellID = cooldownInfo.overrideSpellID or cooldownInfo.spellID
        if type(spellID) == "number" and spellID > 0 then
            return spellID
        end
    end

    if iconFrame.GetSpellID then
        local spellID = iconFrame:GetSpellID()
        if type(spellID) == "number" and spellID > 0 then
            return spellID
        end
    end

    return nil
end

local function RunWithAuraOverrideBypass(iconFrame, func)
    if not iconFrame or not func then return false end
    if auraOverrideBypassState[iconFrame] then return false end

    auraOverrideBypassState[iconFrame] = true
    local ok = pcall(func)
    auraOverrideBypassState[iconFrame] = nil
    return ok
end

local function ApplyIgnoreAuraOverrideCooldownForFrame(iconFrame)
    if not iconFrame then return end
    local cooldown = iconFrame.Cooldown
    if not cooldown then return end

    if not ShouldIgnoreAuraOverrideForTarget(iconFrame) then
        return
    end

    local spellID = GetAuraOverrideSpellID(iconFrame)
    if not spellID then
        return
    end

    local appliedChargeDuration = false
    if C_Spell and C_Spell.GetSpellCharges and C_Spell.GetSpellChargeDuration and cooldown.SetCooldownFromDurationObject then
        local okCharges, chargeInfo = pcall(C_Spell.GetSpellCharges, spellID)
        local isChargeSpell = okCharges and chargeInfo ~= nil
        if isChargeSpell then
            local okDuration, chargeDurationObject = pcall(C_Spell.GetSpellChargeDuration, spellID)
            if okDuration and chargeDurationObject then
                appliedChargeDuration = RunWithAuraOverrideBypass(iconFrame, function()
                    cooldown:SetCooldownFromDurationObject(chargeDurationObject)
                end)
            end
        end
    end

    if not appliedChargeDuration and C_Spell and C_Spell.GetSpellCooldown then
        local okCooldown, spellCooldownInfo = pcall(C_Spell.GetSpellCooldown, spellID)
        if okCooldown and spellCooldownInfo then
            -- Use isActive (non-secret boolean) to check if cooldown is actually running
            if spellCooldownInfo.isActive then
                -- Prefer SetCooldownFromDurationObject (accepts secret values)
                if cooldown.SetCooldownFromDurationObject and spellCooldownInfo.durationObject then
                    RunWithAuraOverrideBypass(iconFrame, function()
                        cooldown:SetCooldownFromDurationObject(spellCooldownInfo.durationObject)
                    end)
                else
                    -- Fallback: pcall-wrapped SetCooldown
                    RunWithAuraOverrideBypass(iconFrame, function()
                        local ok = pcall(cooldown.SetCooldown, cooldown, spellCooldownInfo.startTime, spellCooldownInfo.duration)
                        if not ok then cooldown:Clear() end
                    end)
                end
            else
                RunWithAuraOverrideBypass(iconFrame, function()
                    cooldown:Clear()
                end)
            end
        end
    end

    if cooldown.SetSwipeColor then
        cooldown:SetSwipeColor(0, 0, 0, 0.8)
    end
end

local function HookAuraOverrideCooldownFrame(iconFrame)
    if not iconFrame or not iconFrame.Cooldown then return end
    local cooldown = iconFrame.Cooldown
    if auraOverrideHookedCooldowns[cooldown] then return end
    auraOverrideHookedCooldowns[cooldown] = true

    hooksecurefunc(cooldown, "SetCooldown", function(self)
        local parent = self and self.GetParent and self:GetParent()
        if parent and auraOverrideBypassState[parent] then return end
        ApplyIgnoreAuraOverrideCooldownForFrame(parent)
    end)

    if cooldown.SetCooldownFromDurationObject then
        hooksecurefunc(cooldown, "SetCooldownFromDurationObject", function(self)
            local parent = self and self.GetParent and self:GetParent()
            if parent and auraOverrideBypassState[parent] then return end
            ApplyIgnoreAuraOverrideCooldownForFrame(parent)
        end)
    end
end

local function ForEachViewerIconFrame(callback)
    if type(callback) ~= "function" then return end
    local viewers = {
        "EssentialCooldownViewer",
        "UtilityCooldownViewer",
    }

    for _, viewerName in ipairs(viewers) do
        local viewer = _G[viewerName]
        if viewer and viewer.GetChildren then
            for _, child in ipairs({ viewer:GetChildren() }) do
                if child and child.Cooldown then
                    callback(child)
                end
            end
        end
    end
end

local function EnsureAuraOverrideCooldownHooks()
    ForEachViewerIconFrame(function(iconFrame)
        HookAuraOverrideCooldownFrame(iconFrame)
    end)
end

local function RefreshAuraOverrideCooldownForAllViewers()
    return
end

local function ReevaluateAuraOverrideGlows()
    for frame in pairs(activeGlows) do
        if ShouldIgnoreAuraOverrideForTarget(frame) then
            frameAlertActiveState[frame] = nil
            frameAlertStartTimeState[frame] = nil
            StopAlertGlowNow(frame)
        end
    end

end

function CCM.SetupCustomGlows()
    if CCM.CustomGlowHooksSet then return end
    CCM.CustomGlowHooksSet = true

    if not CCM.ActionButtonHooksSet and ActionButtonSpellAlertManager then
        CCM.ActionButtonHooksSet = true
        hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", function(_, frame)
            -- Glow system disabled: let Blizzard's proc animation show normally.
            local glow = CCM.GetCustomGlowSettings()
            if not glow or not glow.Enabled then return end

            local activeGlowTarget = GetGlowTarget(frame)
            if not activeGlowTarget then return end

            -- Essential uses per-spell dispatch; suppress Blizzard proc animation there.
            if IsEssentialOrUtilityViewerTarget(activeGlowTarget) == false and IsEssentialOrUtilityViewerTarget(frame) == false then
                -- Not a CCM viewer and not Essential — apply custom glow to action bar buttons
            end

            if ShouldIgnoreAuraOverrideForTarget(activeGlowTarget) then
                if frame and frame.SpellActivationAlert then
                    frame.SpellActivationAlert:Hide()
                end
                if activeGlowTarget.SpellActivationAlert then
                    activeGlowTarget.SpellActivationAlert:Hide()
                end
                frameAlertActiveState[activeGlowTarget] = nil
                frameAlertStartTimeState[activeGlowTarget] = nil
                StopAlertGlowNow(activeGlowTarget)
                return
            end

            if frameAlertActiveState[activeGlowTarget] then
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
            -- Glow system disabled: let Blizzard handle the hide.
            local glow = CCM.GetCustomGlowSettings()
            if not glow or not glow.Enabled then return end

            local activeGlowTarget = GetGlowTarget(frame)
            if not activeGlowTarget then return end
            frameAlertActiveState[activeGlowTarget] = nil
            frameAlertStartTimeState[activeGlowTarget] = nil
            StopAlertGlowNow(activeGlowTarget)
        end)
    end

    if false and not CCM.AuraOverrideCooldownHooksSet then
        CCM.AuraOverrideCooldownHooksSet = true

        EnsureAuraOverrideCooldownHooks()

        local auraOverrideFrame = CreateFrame("Frame")
        auraOverrideFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        auraOverrideFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        auraOverrideFrame:RegisterUnitEvent("UNIT_AURA", "player")
        auraOverrideFrame:SetScript("OnEvent", function(_, event, unit)
            C_Timer.After(0, function()
                EnsureAuraOverrideCooldownHooks()
                RefreshAuraOverrideCooldownForAllViewers()
            end)
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
    -- Aura override at login — DISABLED
    if false and event == "PLAYER_LOGIN" then
        C_Timer.After(0.5, function()
            local glow = CCM.GetCustomGlowSettings()
            if glow and glow.IgnoreAuraOverride == true then
                EnsureAuraOverrideCooldownHooks()
                RefreshAuraOverrideCooldownForAllViewers()
                ReevaluateAuraOverrideGlows()
                CCM.RefreshCustomGlows()
            end
        end)
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
local function CreateGlowOptionsPanel()
    local panel = CreateFrame("Frame", "CkraigGlowOptionsPanel", UIParent)
    panel.name = "Glow Style (All Viewers)"
    panel:SetSize(460, 430)

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("Global Glow Style")

    local description = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    description:SetPoint("TOPLEFT", 24, -68)
    description:SetWidth(410)
    description:SetJustifyH("LEFT")
    description:SetText("When Blizzard proc glow appears on a tracked viewer icon, replace it with the selected glow type.")

    local glowSettings = CCM.GetCustomGlowSettings()

    local enableCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    enableCheck:SetPoint("TOPLEFT", 24, -18)
    enableCheck.text = enableCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    enableCheck.text:SetPoint("LEFT", enableCheck, "RIGHT", 2, 0)
    enableCheck.text:SetText("Enable Custom Overrides")
    enableCheck:SetChecked(glowSettings.Enabled ~= false)

    local auraOverrideCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    auraOverrideCheck:SetPoint("TOPLEFT", 24, -42)
    auraOverrideCheck.text = auraOverrideCheck:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    auraOverrideCheck.text:SetPoint("LEFT", auraOverrideCheck, "RIGHT", 2, 0)
    auraOverrideCheck.text:SetText("Ignore Aura Override Glow (Disabled)")
    auraOverrideCheck:SetChecked(false)
    auraOverrideCheck:Disable()
    auraOverrideCheck:SetAlpha(0.5)

    local dropdownLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dropdownLabel:SetPoint("TOPLEFT", 24, -104)
    dropdownLabel:SetText("Glow Type:")

    local dropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("TOPLEFT", dropdownLabel, "BOTTOMLEFT", 0, -4)
    dropdown:SetWidth(200)

    dropdown:SetupMenu(function(dd, rootDescription)
        local currentType = (CCM.GetCustomGlowSettings() and CCM.GetCustomGlowSettings().Type) or "Pixel"
        for _, style in ipairs(GLOW_STYLES) do
            rootDescription:CreateRadio(
                GLOW_LABELS[style] or style,
                function() return ((CCM.GetCustomGlowSettings() and CCM.GetCustomGlowSettings().Type) or "Pixel") == style end,
                function()
                    local glow = CCM.GetCustomGlowSettings()
                    glow.Type = style
                    CCM.RefreshCustomGlows()
                end,
                style
            )
        end
    end)

    local thicknessLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    thicknessLabel:SetPoint("TOPLEFT", 24, -168)
    thicknessLabel:SetText("Glow Thickness:")

    local thicknessSlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
    thicknessSlider:SetPoint("TOPLEFT", thicknessLabel, "BOTTOMLEFT", 0, -12)
    thicknessSlider:SetWidth(220)
    thicknessSlider:SetMinMaxValues(1, 8)
    thicknessSlider:SetValueStep(0.5)
    if thicknessSlider.SetObeyStepOnDrag then
        thicknessSlider:SetObeyStepOnDrag(true)
    end

    local currentThickness = (glowSettings and (glowSettings.CommonThickness or (glowSettings.Pixel and glowSettings.Pixel.Thickness))) or 1
    thicknessSlider:SetValue(currentThickness)

    local sliderName = thicknessSlider:GetName()
    if sliderName and _G[sliderName .. "Low"] and _G[sliderName .. "High"] and _G[sliderName .. "Text"] then
        _G[sliderName .. "Low"]:SetText("1")
        _G[sliderName .. "High"]:SetText("8")
        _G[sliderName .. "Text"]:SetText(string.format("%.1f", currentThickness))
    end

    thicknessSlider:SetScript("OnValueChanged", function(self, value)
        local rounded = math.floor((value * 2) + 0.5) / 2
        local glow = CCM.GetCustomGlowSettings()
        glow.CommonThickness = rounded
        glow.Pixel.Thickness = rounded

        local sName = self:GetName()
        if sName and _G[sName .. "Text"] then
            _G[sName .. "Text"]:SetText(string.format("%.1f", rounded))
        end

        CCM.RefreshCustomGlows()
    end)

    local thicknessHint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    thicknessHint:SetPoint("TOPLEFT", thicknessSlider, "BOTTOMLEFT", 0, -9)
    thicknessHint:SetWidth(300)
    thicknessHint:SetJustifyH("LEFT")
    thicknessHint:SetText("For Pixel this is true line thickness. For AutoCast/Proc/Button it scales glow intensity/size.")

    local colorsLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    colorsLabel:SetPoint("TOPLEFT", 24, -365)
    colorsLabel:SetText("Glow Colors:")

    local colorSwatches = {}
    panel.CkraigGlowColorSwatches = colorSwatches
    local colorButtons = {}

    local function RefreshColorSwatches()
        for style, swatch in pairs(colorSwatches) do
            if swatch and swatch.SetColorTexture then
                local rr, rg, rb, ra = GetStyleColor(style)
                swatch:SetColorTexture(rr, rg, rb, ra)
            end
        end
    end

    local function CreateColorButton(style, xOffset, yOffset)
        local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        button:SetSize(130, 22)
        button:SetPoint("TOPLEFT", 24 + xOffset, -365 + yOffset)
        button:SetText(GLOW_LABELS[style] or style)
        table.insert(colorButtons, button)

        local swatchHolder = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        swatchHolder:SetSize(16, 16)
        swatchHolder:SetPoint("LEFT", button, "RIGHT", 8, 0)
        swatchHolder:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8X8",
            edgeFile = "Interface/Buttons/WHITE8X8",
            edgeSize = 1,
        })
        swatchHolder:SetBackdropColor(0, 0, 0, 0)
        swatchHolder:SetBackdropBorderColor(0, 0, 0, 1)

        local swatch = swatchHolder:CreateTexture(nil, "ARTWORK")
        swatch:SetSize(12, 12)
        swatch:SetPoint("CENTER")

        local sr, sg, sb, sa = GetStyleColor(style)
        swatch:SetColorTexture(sr, sg, sb, sa)
        colorSwatches[style] = swatch

        button:SetScript("OnClick", function()
            OpenStyleColorPicker(style, swatch)
        end)
    end

    CreateColorButton("Pixel", 0, -28)
    CreateColorButton("Autocast", 150, -28)
    CreateColorButton("Button", 150, -56)

    local resetColorsBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetColorsBtn:SetSize(150, 22)
    resetColorsBtn:SetPoint("TOPLEFT", 320, -393)
    resetColorsBtn:SetText("Reset Glow Colors")
    resetColorsBtn:SetScript("OnClick", function()
        ResetAllGlowColorsToDefault()
        RefreshColorSwatches()
    end)


    local function ApplyControlsEnabledState(enabled)
        if enabled then
            UIDropDownMenu_EnableDropDown(dropdown)
            thicknessSlider:Enable()
            auraOverrideCheck:Enable()
            resetColorsBtn:Enable()
            for _, btn in ipairs(colorButtons) do
                btn:Enable()
                btn:SetAlpha(1)
            end
        else
            UIDropDownMenu_DisableDropDown(dropdown)
            thicknessSlider:Disable()
            auraOverrideCheck:Disable()
            resetColorsBtn:Disable()
            for _, btn in ipairs(colorButtons) do
                btn:Disable()
                btn:SetAlpha(0.5)
            end
        end

        local alpha = enabled and 1 or 0.55
        thicknessSlider:SetAlpha(alpha)
        auraOverrideCheck:SetAlpha(alpha)
        resetColorsBtn:SetAlpha(alpha)
    end

    -- Ensure aura override logic is applied on load if checked
    -- DISABLED
    --[[
    C_Timer.After(0, function()
        local glow = CCM.GetCustomGlowSettings()
        if glow.IgnoreAuraOverride == true then
            EnsureAuraOverrideCooldownHooks()
            RefreshAuraOverrideCooldownForAllViewers()
            ReevaluateAuraOverrideGlows()
            CCM.RefreshCustomGlows()
        end
    end)
    ]]

    auraOverrideCheck:SetScript("OnClick", function(self)
        self:SetChecked(false)
    end)

    enableCheck:SetScript("OnClick", function(self)
        local glow = CCM.GetCustomGlowSettings()
        local enabled = self:GetChecked() and true or false
        glow.Enabled = enabled

        ApplyControlsEnabledState(enabled)
        if enabled then
            CCM.RefreshCustomGlows()
        else
            CCM.DisableCustomGlowsNow()
        end
    end)

    panel:SetScript("OnShow", function()
        local glow = CCM.GetCustomGlowSettings()
        local enabled = glow.Enabled ~= false
        enableCheck:SetChecked(enabled)
        auraOverrideCheck:SetChecked(glow.IgnoreAuraOverride == true)
        ApplyControlsEnabledState(enabled)
        RefreshColorSwatches()
        C_Timer.After(0, RefreshColorSwatches)
        C_Timer.After(0.05, RefreshColorSwatches)
    end)

    local swatchRefreshFrame = CreateFrame("Frame")
    swatchRefreshFrame:RegisterEvent("PLAYER_LOGIN")
    swatchRefreshFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    swatchRefreshFrame:SetScript("OnEvent", function()
        if panel:IsShown() then
            RefreshColorSwatches()
            C_Timer.After(0, RefreshColorSwatches)
        end
    end)

    RefreshColorSwatches()
    ApplyControlsEnabledState(glowSettings.Enabled ~= false)

    _G.CkraigGlowOptionsPanel = panel
    return panel
end

_G.CCM_CreateGlowOptionsPanel = CreateGlowOptionsPanel

BuildGlowConfigSignature = function(glowType, glow, thickness)
    if glowType == "Pixel" then
        local s = glow.Pixel or {}
        return table.concat({
            tostring(thickness), tostring(s.Lines), tostring(s.Frequency), tostring(s.Length),
            tostring(s.XOffset), tostring(s.YOffset), tostring(s.Border),
            tostring((s.Color and s.Color[1]) or ""), tostring((s.Color and s.Color[2]) or ""),
            tostring((s.Color and s.Color[3]) or ""), tostring((s.Color and s.Color[4]) or ""),
        }, "|")
    elseif glowType == "Autocast" then
        local s = glow.Autocast or {}
        local scaledScale = (s.Scale or 1) * (0.75 + ((thickness - 1) * 0.18))
        return table.concat({
            tostring(s.Particles), tostring(s.Frequency), tostring(scaledScale),
            tostring(s.XOffset), tostring(s.YOffset),
            tostring((s.Color and s.Color[1]) or ""), tostring((s.Color and s.Color[2]) or ""),
            tostring((s.Color and s.Color[3]) or ""), tostring((s.Color and s.Color[4]) or ""),
        }, "|")
    elseif glowType == "Button" then
        local s = glow.Button or {}
        local boostedFrequency = math.max(0.03, (s.Frequency or 0.125) / (0.75 + ((thickness - 1) * 0.2)))
        return table.concat({
            tostring(boostedFrequency),
            tostring((s.Color and s.Color[1]) or ""), tostring((s.Color and s.Color[2]) or ""),
            tostring((s.Color and s.Color[3]) or ""), tostring((s.Color and s.Color[4]) or ""),
        }, "|")
    end
    return ""
end