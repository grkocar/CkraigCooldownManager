-- ============================================================
-- CkraigCooldownManager :: Core :: Events
-- ============================================================
-- Centralized event helper utilities.
-- Thin wrappers used by multiple modules for combat checks
-- and spec/profile switching.
-- ============================================================

local CCM = _G.CkraigCooldownManager

-- Combat lockdown helper (safe one-liner used everywhere)
function CCM.IsInCombat()
    return InCombatLockdown()
end

-- Class + Spec profile name  e.g. "WARRIOR_Arms"
function CCM.GetClassSpecProfileName()
    local _, class = UnitClass("player")
    local specIndex = GetSpecialization and GetSpecialization()
    local specName = specIndex and select(2, GetSpecializationInfo(specIndex)) or "Default"
    return class .. "_" .. (specName or "Default")
end

-- Hero Talent Spec detection (e.g. "Aldrachi Reaver", "Frostfire", etc.)
-- Returns the hero spec ID or nil if unavailable
function CCM.GetActiveHeroTalentSpec()
    if C_ClassTalents and C_ClassTalents.GetActiveHeroTalentSpec then
        local ok, specID = pcall(C_ClassTalents.GetActiveHeroTalentSpec)
        if ok and specID then return specID end
    end
    return nil
end

-- Extended profile name including hero spec: "WARRIOR_Arms_HeroSpecName"
-- Falls back to GetClassSpecProfileName if hero talent API is unavailable
function CCM.GetFullSpecProfileName()
    local base = CCM.GetClassSpecProfileName()
    local heroSpecID = CCM.GetActiveHeroTalentSpec()
    if heroSpecID then
        -- Try to get hero spec name
        if C_ClassTalents and C_ClassTalents.GetHeroTalentSpecInfo then
            local ok, info = pcall(C_ClassTalents.GetHeroTalentSpecInfo, heroSpecID)
            if ok and info and info.name then
                return base .. "_" .. info.name
            end
        end
        return base .. "_Hero" .. heroSpecID
    end
    return base
end

-- Switch to the matching class/spec profile if one exists in the given AceDB
function CCM.SwitchProfileForClassSpec(db)
    if not db or not db.GetCurrentProfile then return end
    local profileName = CCM.GetClassSpecProfileName()
    if db:GetCurrentProfile() ~= profileName then
        local profiles = {}
        db:GetProfiles(profiles)
        for _, name in ipairs(profiles) do
            if name == profileName then
                db:SetProfile(profileName)
                return
            end
        end
    end
end

-- Spec-change listener — switches profile automatically on respec
local specProfileFrame = CreateFrame("Frame")
specProfileFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
specProfileFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
specProfileFrame:SetScript("OnEvent", function()
    if _G.CkraigCooldownManager and _G.CkraigCooldownManager.db then
        CCM.SwitchProfileForClassSpec(_G.CkraigCooldownManager.db)
    end
end)
