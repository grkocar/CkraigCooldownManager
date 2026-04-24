-- ============================================================
-- CkraigCooldownManager :: Core :: Init
-- ============================================================
-- Handles ADDON_LOADED bootstrapping.
-- Ensures ProfileManager is initialized when the addon loads.
-- ============================================================

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, arg1)
    if arg1 == "CkraigCooldownManager" then
        -- Bootstrap the ProfileManager if it exists
        if _G.CkraigProfileManager and _G.CkraigProfileManager.OnInitialize then
            if not _G.CkraigProfileManager.db then
                _G.CkraigProfileManager:OnInitialize()
            end
        end
    end
end)
