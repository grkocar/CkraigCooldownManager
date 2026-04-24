-- ============================================================
-- CkraigCooldownManager :: Core :: Namespace
-- ============================================================
-- Single shared namespace table for all modules.
-- Every file receives (addonName, CCM) via the ... vararg;
-- this file makes sure the global table IS the addon table so
-- both _G.CkraigCooldownManager and the ... vararg reference
-- the same object.
-- ============================================================

local addonName, CCM = ...

-- Merge any pre-existing global keys into the addon private table
local existing = _G.CkraigCooldownManager
if existing and existing ~= CCM then
    for k, v in pairs(existing) do
        if CCM[k] == nil then CCM[k] = v end
    end
end

-- Make the global point at the addon table (same reference everywhere)
_G.CkraigCooldownManager = CCM

-- Expose the addon name
CCM.addonName = addonName

-- ============================================================
-- Self-profiling slash command: /ccmperf
-- Uses C_AddOnProfiler.GetAddOnMetric when available (11.x+)
-- ============================================================
SLASH_CCMPERF1 = "/ccmperf"
SlashCmdList["CCMPERF"] = function()
    if not C_AddOnProfiler or not C_AddOnProfiler.GetAddOnMetric then
        print("|cff00ff00[CCM]|r C_AddOnProfiler not available on this client.")
        return
    end
    local addonIdx = nil
    local numAddOns = C_AddOns and C_AddOns.GetNumAddOns and C_AddOns.GetNumAddOns() or GetNumAddOns()
    for i = 1, numAddOns do
        local name = C_AddOns and C_AddOns.GetAddOnInfo and C_AddOns.GetAddOnInfo(i) or GetAddOnInfo(i)
        if name == "CkraigCooldownManager" then
            addonIdx = i
            break
        end
    end
    if not addonIdx then
        print("|cff00ff00[CCM]|r Could not find addon index.")
        return
    end
    print("|cff00ff00[CCM]|r Performance Metrics:")
    local metrics = {
        "AvgTime", "PeakTime", "MemoryAvg", "MemoryPeak",
        "EncounterAvg", "EncounterPeak",
    }
    for _, metric in ipairs(metrics) do
        local ok, value = pcall(C_AddOnProfiler.GetAddOnMetric, addonIdx, metric)
        if ok and value then
            print(string.format("  %s: %s", metric, tostring(value)))
        end
    end
end
