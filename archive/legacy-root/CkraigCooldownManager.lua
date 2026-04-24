
_G.CkraigCooldownManager = _G.CkraigCooldownManager or {}

-- Ensure ProfileManager is initialized on ADDON_LOADED
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, arg1)
	if arg1 == "CkraigCooldownManager" and _G.CkraigProfileManager and _G.CkraigProfileManager.OnInitialize then
		if not _G.CkraigProfileManager.db then
			_G.CkraigProfileManager:OnInitialize()
		end
	end
end)
