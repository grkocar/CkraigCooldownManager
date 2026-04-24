-- ============================================================
-- CkraigCooldownManager :: Utils :: Profiler
-- ============================================================
-- Lightweight CPU profiler using debugprofilestop().
-- Wraps key OnUpdate/event-handler functions to measure per-
-- function CPU time. Activate with /ccmprofile.
--
-- Usage:
--   /ccmprofile start [seconds]  — start profiling (default 10s)
--   /ccmprofile stop             — stop early and print report
--   /ccmprofile report           — print last report again
--   /ccmprofile list             — show what can be hooked
--   /ccmprofile                  — toggle (start 10s / stop)
-- ============================================================

local CCM = _G.CkraigCooldownManager
if not CCM then return end

local Profiler = {}
CCM.Profiler = Profiler

-- ============================================================
-- State
-- ============================================================
local isRunning = false
local startTime = 0
local duration = 10
local timerHandle = nil

-- Per-function stats: [name] = { calls = N, totalMs = N }
local stats = {}
-- Installed frame script hooks: [name] = { frame, scriptType, origFunc }
local frameHooks = {}
-- Installed table function hooks: [name] = { tbl, key, origFunc }
local funcHooks = {}

-- ============================================================
-- Measurement core
-- ============================================================
local function WrapFunction(name, func)
    if not stats[name] then
        stats[name] = { calls = 0, totalMs = 0 }
    end
    local entry = stats[name]
    return function(...)
        local t0 = debugprofilestop()
        func(...)
        local elapsed = debugprofilestop() - t0
        entry.calls = entry.calls + 1
        entry.totalMs = entry.totalMs + elapsed
    end
end

-- ============================================================
-- Discovery: find all hookable CCM frames and functions
-- Returns { frames = { {name, frame, scriptType}, ... },
--           funcs  = { {name, tbl, key}, ... } }
-- ============================================================
local function DiscoverTargets()
    local frames = {}
    local funcs  = {}

    local function AddFrame(name, frame, scriptType)
        if frame and frame:GetScript(scriptType) then
            frames[#frames + 1] = { name = name, frame = frame, scriptType = scriptType }
        end
    end

    local function AddFunc(name, tbl, key)
        if tbl and type(tbl[key]) == "function" then
            funcs[#funcs + 1] = { name = name, tbl = tbl, key = key }
        end
    end

    -- ==========================================
    -- ResourceBars: named frames CCM_RB_*
    -- ==========================================
    local RB = _G.CCM_ResourceBars
    if RB and RB.bars then
        for barName, frame in pairs(RB.bars) do
            AddFrame("RB:" .. barName .. ":OnUpdate", frame, "OnUpdate")
            AddFrame("RB:" .. barName .. ":OnEvent", frame, "OnEvent")
            -- Inner StatusBar (HealthBar, PowerBar etc register events here)
            local inner = _G["CCM_RB_" .. barName .. "_Inner"]
            if inner and inner ~= frame then
                AddFrame("RB:" .. barName .. "_Inner:OnEvent", inner, "OnEvent")
            end
        end
    end

    -- ClassResources segmented container
    local classRes = _G["CCM_RB_classResource"]
    if classRes then
        AddFrame("ClassResources:OnUpdate", classRes, "OnUpdate")
        AddFrame("ClassResources:OnEvent", classRes, "OnEvent")
    end
    -- Stagger bar
    local stagger = _G["CCM_RB_classResource_stagger_Inner"]
    if stagger then
        AddFrame("Stagger:OnEvent", stagger, "OnEvent")
    end

    -- ==========================================
    -- CooldownBars (BarCore): _bb_updateFrame, _bb_fadeFrame
    -- ==========================================
    if CCM._bb_updateFrame then
        AddFrame("CooldownBars:EventDispatch", CCM._bb_updateFrame, "OnEvent")
    end
    if CCM._bb_fadeFrame then
        AddFrame("CooldownBars:FadeOnUpdate", CCM._bb_fadeFrame, "OnUpdate")
    end
    -- BarCore key functions
    if CCM._barInternals then
        AddFunc("CooldownBars:InvalidateBarStyle", CCM._barInternals, "InvalidateBarStyle")
    end

    -- ==========================================
    -- EssentialBuffTracker
    -- ==========================================
    local EBT = _G.MyEssentialBuffTracker
    if EBT then
        AddFunc("EBT:InitializeDB", EBT, "InitializeDB")
    end
    local EBTViewers = _G.MyEssentialIconViewers
    if EBTViewers then
        AddFunc("EBT:HookViewers", EBTViewers, "HookViewers")
        AddFunc("EBT:RescanViewer", EBTViewers, "RescanViewer")
    end
    -- EBT viewer frame itself (Blizzard frame with hooked scripts)
    local essViewer = _G["EssentialCooldownViewer"]
    if essViewer then
        AddFrame("EssentialViewer:OnEvent", essViewer, "OnEvent")
    end

    -- ==========================================
    -- UtilityBuffTracker
    -- ==========================================
    local UBT = _G.MyUtilityBuffTracker
    if UBT then
        AddFunc("UBT:InitializeDB", UBT, "InitializeDB")
    end
    local UBTViewers = _G.UtilityIconViewers
    if UBTViewers then
        AddFunc("UBT:RescanViewer", UBTViewers, "RescanViewer")
    end
    local utilViewer = _G["UtilityCooldownViewer"]
    if utilViewer then
        AddFrame("UtilityViewer:OnEvent", utilViewer, "OnEvent")
    end

    -- ==========================================
    -- DynamicIcons (BuffIcon viewer)
    -- ==========================================
    local DI = _G.DYNAMICICONS
    if DI then
        -- DI often has batch update functions
        AddFunc("DynamicIcons:FullRefresh", DI, "FullRefresh")
    end
    local DIViewers = _G.BuffIconViewers
    if DIViewers then
        AddFunc("DynamicIcons:RescanViewer", DIViewers, "RescanViewer")
    end
    local buffIconViewer = _G["BuffIconCooldownViewer"]
    if buffIconViewer then
        AddFrame("BuffIconViewer:OnEvent", buffIconViewer, "OnEvent")
    end

    -- ==========================================
    -- SegmentBars
    -- ==========================================
    local SB = _G.CCM_SegmentBars
    if SB then
        AddFunc("SegmentBars:FullRefresh", SB, "FullRefresh")
    end

    -- ==========================================
    -- TrackedSpells
    -- ==========================================
    local TS = _G.CCM_TrackedSpells
    if TS then
        AddFunc("TrackedSpells:FullRefresh", TS, "FullRefresh")
    end

    -- ==========================================
    -- GlowManager (RefreshCustomGlows is on CCM)
    -- ==========================================
    AddFunc("GlowManager:RefreshCustomGlows", CCM, "RefreshCustomGlows")

    -- ==========================================
    -- Externally registered targets
    -- ==========================================
    for _, t in ipairs(Profiler._extraFrames or {}) do
        AddFrame(t.name, t.frame, t.scriptType)
    end
    for _, t in ipairs(Profiler._extraFuncs or {}) do
        AddFunc(t.name, t.tbl, t.key)
    end

    return { frames = frames, funcs = funcs }
end

-- ============================================================
-- External registration API (for modules with local frames)
-- ============================================================
Profiler._extraFrames = {}
Profiler._extraFuncs = {}

function Profiler:RegisterFrame(name, frame, scriptType)
    self._extraFrames[#self._extraFrames + 1] = { name = name, frame = frame, scriptType = scriptType }
end

function Profiler:RegisterFunction(name, tbl, key)
    self._extraFuncs[#self._extraFuncs + 1] = { name = name, tbl = tbl, key = key }
end

-- ============================================================
-- Hook / unhook
-- ============================================================
local function InstallHooks()
    local targets = DiscoverTargets()

    for _, t in ipairs(targets.frames) do
        if not frameHooks[t.name] then
            local orig = t.frame:GetScript(t.scriptType)
            if orig then
                frameHooks[t.name] = { frame = t.frame, scriptType = t.scriptType, origFunc = orig }
                t.frame:SetScript(t.scriptType, WrapFunction(t.name, orig))
            end
        end
    end

    for _, t in ipairs(targets.funcs) do
        if not funcHooks[t.name] then
            local orig = t.tbl[t.key]
            if orig and type(orig) == "function" then
                funcHooks[t.name] = { tbl = t.tbl, key = t.key, origFunc = orig }
                t.tbl[t.key] = WrapFunction(t.name, orig)
            end
        end
    end
end

local function RemoveHooks()
    for _, info in pairs(frameHooks) do
        if info.frame and info.origFunc then
            info.frame:SetScript(info.scriptType, info.origFunc)
        end
    end
    wipe(frameHooks)

    for _, info in pairs(funcHooks) do
        if info.tbl and info.origFunc then
            info.tbl[info.key] = info.origFunc
        end
    end
    wipe(funcHooks)
end

-- ============================================================
-- Report
-- ============================================================
local lastReport = nil

local function PrintReport()
    if not lastReport then
        print("|cff00ccffCCM Profiler:|r No data. Run /ccmprofile start first.")
        return
    end

    local elapsed = lastReport.elapsed
    print("|cff00ccffCCM Profiler Report|r  (" .. string.format("%.1f", elapsed) .. "s sample)")
    print(string.format("  %-40s %10s %8s %10s", "Function", "Total(ms)", "Calls", "ms/call"))
    print("  " .. string.rep("-", 72))

    -- Sort by total time descending
    local sorted = {}
    for name, data in pairs(lastReport.stats) do
        if data.calls > 0 then
            sorted[#sorted + 1] = { name = name, totalMs = data.totalMs, calls = data.calls }
        end
    end
    table.sort(sorted, function(a, b) return a.totalMs > b.totalMs end)

    if #sorted == 0 then
        print("  |cff888888(no functions were called during the sample)|r")
    end

    for _, entry in ipairs(sorted) do
        local perCall = entry.calls > 0 and (entry.totalMs / entry.calls) or 0
        local color = entry.totalMs > 50 and "|cffff4444" or
                      entry.totalMs > 10 and "|cffffaa00" or "|cff44ff44"
        print(string.format("  %s%-40s %10.2f %8d %10.3f|r",
            color, entry.name, entry.totalMs, entry.calls, perCall))
    end

    -- Idle hooks (0 calls) — show count only
    local idleCount = 0
    for name, data in pairs(lastReport.stats) do
        if data.calls == 0 then idleCount = idleCount + 1 end
    end
    if idleCount > 0 then
        print("  |cff888888(" .. idleCount .. " hooks had 0 calls — idle during sample)|r")
    end

    -- Total
    local totalMs = 0
    for _, entry in ipairs(sorted) do totalMs = totalMs + entry.totalMs end
    print("  " .. string.rep("-", 72))
    print(string.format("  %-40s %10.2f ms total", "ALL PROFILED", totalMs))
end

-- ============================================================
-- Start / Stop
-- ============================================================
local function StopProfiling()
    if not isRunning then return end
    isRunning = false

    local elapsed = (debugprofilestop() - startTime) / 1000  -- ms → s

    -- Snapshot stats before unhooking
    lastReport = { elapsed = elapsed, stats = {} }
    for name, data in pairs(stats) do
        lastReport.stats[name] = { calls = data.calls, totalMs = data.totalMs }
    end

    RemoveHooks()

    if timerHandle then
        timerHandle:Cancel()
        timerHandle = nil
    end

    print("|cff00ccffCCM Profiler:|r Stopped.")
    PrintReport()
end

local function StartProfiling(seconds)
    if isRunning then
        StopProfiling()
    end

    duration = seconds or 10
    wipe(stats)
    wipe(frameHooks)
    wipe(funcHooks)

    InstallHooks()

    local hookCount = 0
    for _ in pairs(frameHooks) do hookCount = hookCount + 1 end
    for _ in pairs(funcHooks) do hookCount = hookCount + 1 end

    if hookCount == 0 then
        print("|cff00ccffCCM Profiler:|r No functions found to profile. Make sure the addon is fully loaded.")
        return
    end

    isRunning = true
    startTime = debugprofilestop()

    print("|cff00ccffCCM Profiler:|r Started — " .. hookCount .. " hooks for " .. duration .. "s.")
    print("|cff00ccffCCM Profiler:|r Play normally (enter combat, use abilities). /ccmprofile stop to end early.")

    timerHandle = C_Timer.NewTimer(duration, function()
        timerHandle = nil
        StopProfiling()
    end)
end

-- ============================================================
-- List: show discoverable targets without hooking
-- ============================================================
local function PrintDiscoverable()
    local targets = DiscoverTargets()
    print("|cff00ccffCCM Profiler:|r Discoverable targets:")
    local count = 0
    for _, t in ipairs(targets.frames) do
        print("  |cff44ff44[frame]|r " .. t.name .. "  (" .. t.scriptType .. ")")
        count = count + 1
    end
    for _, t in ipairs(targets.funcs) do
        print("  |cff44aaff[func]|r  " .. t.name)
        count = count + 1
    end
    if count == 0 then
        print("  |cff888888(none found — addon may not be fully initialized)|r")
    else
        print("  |cff888888" .. count .. " total targets|r")
    end
end

-- ============================================================
-- Slash command
-- ============================================================
SLASH_CCMPROFILE1 = "/ccmprofile"
SlashCmdList["CCMPROFILE"] = function(msg)
    local cmd, arg = strsplit(" ", (msg or ""):lower(), 2)
    cmd = strtrim(cmd or "")

    if cmd == "start" then
        local secs = tonumber(arg) or 10
        StartProfiling(secs)
    elseif cmd == "stop" then
        StopProfiling()
    elseif cmd == "report" then
        PrintReport()
    elseif cmd == "list" then
        PrintDiscoverable()
    elseif cmd == "" then
        -- Toggle
        if isRunning then
            StopProfiling()
        else
            StartProfiling(10)
        end
    else
        print("|cff00ccffCCM Profiler:|r Usage:")
        print("  /ccmprofile start [seconds]  — start profiling")
        print("  /ccmprofile stop             — stop and print report")
        print("  /ccmprofile report           — reprint last report")
        print("  /ccmprofile list             — show discoverable targets")
        print("  /ccmprofile                  — toggle (10s)")
    end
end
