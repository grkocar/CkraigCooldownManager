-- ============================================================
-- CkraigCooldownManager :: UI :: MainOptionsPanel
-- ============================================================
-- Registers the top-level Blizzard Settings category and
-- lazily builds all subcategories the first time the user
-- opens the panel.
-- ============================================================

local optionsRegistered = false
local panelsBuilt = false
local parentCategory

local function SafeCall(fn, obj)
    if type(fn) ~= "function" then return false end
    if obj then return pcall(fn, obj) end
    return pcall(fn)
end

-- ============================================================
-- Subcategory builder (runs once on first panel open)
-- ============================================================
local function BuildAndRegisterSubcategories()
    if panelsBuilt or not parentCategory then return end
    panelsBuilt = true

    -- Create module panels
    if MyEssentialBuffTracker and MyEssentialBuffTracker.CreateOptionsPanel then
        SafeCall(MyEssentialBuffTracker.CreateOptionsPanel, MyEssentialBuffTracker)
    end
    if MyUtilityBuffTracker and MyUtilityBuffTracker.CreateOptionsPanel then
        SafeCall(MyUtilityBuffTracker.CreateOptionsPanel, MyUtilityBuffTracker)
    end
    if DYNAMICICONS and DYNAMICICONS.CreateOptionsPanel then
        SafeCall(DYNAMICICONS.CreateOptionsPanel, DYNAMICICONS)
    end
    if _G.TRINKETRACIALS and _G.TRINKETRACIALS.CreateOptionsPanel then
        SafeCall(_G.TRINKETRACIALS.CreateOptionsPanel)
    elseif _G.PROCS and _G.PROCS.CreateOptionsPanel then
        SafeCall(_G.PROCS.CreateOptionsPanel)
    end
    if PowerPotionSuccessIcon and PowerPotionSuccessIcon.CreateOptionsPanel then
        SafeCall(PowerPotionSuccessIcon.CreateOptionsPanel, PowerPotionSuccessIcon)
    end
    if _G.CCM_TrackedSpells and _G.CCM_TrackedSpells.CreateTrackedSpellsOptionsPanel then
        SafeCall(_G.CCM_TrackedSpells.CreateTrackedSpellsOptionsPanel)
    end
    if not _G.CkraigGlowOptionsPanel and _G.CCM_CreateGlowOptionsPanel then
        SafeCall(_G.CCM_CreateGlowOptionsPanel)
    end
    if _G.CCM_SegmentBars and _G.CCM_SegmentBars.CreateOptionsPanel then
        SafeCall(_G.CCM_SegmentBars.CreateOptionsPanel, _G.CCM_SegmentBars)
    end
    if _G.CCM_CreateChargeTextColorOptionsUI then
        SafeCall(_G.CCM_CreateChargeTextColorOptionsUI)
    end
    if _G.CCM_CreateColorPickersUI then
        SafeCall(_G.CCM_CreateColorPickersUI)
    end

    -- Register subcategories with the Blizzard Settings API
    local parent = parentCategory

    if _G.MyEssentialBuffTrackerPanel then
        local sub = Settings.RegisterCanvasLayoutSubcategory(parent, _G.MyEssentialBuffTrackerPanel, "Essential Buffs")
        Settings.RegisterAddOnCategory(sub)
        _G.MyEssentialBuffTracker_CategoryID = sub:GetID()
    end
    if _G.MyUtilityBuffTrackerPanel then
        local sub = Settings.RegisterCanvasLayoutSubcategory(parent, _G.MyUtilityBuffTrackerPanel, "Utility Buffs")
        Settings.RegisterAddOnCategory(sub)
    end
    if _G.CkraigBarOptionsPanel then
        local sub = Settings.RegisterCanvasLayoutSubcategory(parent, _G.CkraigBarOptionsPanel, "Cooldown Bars")
        Settings.RegisterAddOnCategory(sub)
    end
    if _G.DYNAMICICONSPanel then
        local sub = Settings.RegisterCanvasLayoutSubcategory(parent, _G.DYNAMICICONSPanel, "Dynamic Icons")
        Settings.RegisterAddOnCategory(sub)
    end
    if _G.CCM_ItemConfigPanel then
        local sub = Settings.RegisterCanvasLayoutSubcategory(parent, _G.CCM_ItemConfigPanel, "Tracked Items")
        Settings.RegisterAddOnCategory(sub)
    end
    if _G.CCM_TrackedSpellsPanel then
        local sub = Settings.RegisterCanvasLayoutSubcategory(parent, _G.CCM_TrackedSpellsPanel, "Tracked Custom Spells")
        Settings.RegisterAddOnCategory(sub)
    end
    if _G.ChargeTextColorOptionsPanel then
        local sub = Settings.RegisterCanvasLayoutSubcategory(parent, _G.ChargeTextColorOptionsPanel, "Charge Text Colors")
        Settings.RegisterAddOnCategory(sub)
    end
    if _G.PowerPotionSuccessIconPanel then
        local sub = Settings.RegisterCanvasLayoutSubcategory(parent, _G.PowerPotionSuccessIconPanel, "Power Potion Success")
        Settings.RegisterAddOnCategory(sub)
        PowerPotionSuccessIconCategoryID = sub.ID
    end
    if _G.CkraigGlowOptionsPanel then
        local sub = Settings.RegisterCanvasLayoutSubcategory(parent, _G.CkraigGlowOptionsPanel, "Glow Style (All Viewers)")
        Settings.RegisterAddOnCategory(sub)
    end
    if _G.CCM_SegmentBarsPanel then
        local sub = Settings.RegisterCanvasLayoutSubcategory(parent, _G.CCM_SegmentBarsPanel, "Segment Bars")
        Settings.RegisterAddOnCategory(sub)
    end
end

-- ============================================================
-- Register on PLAYER_LOGIN
-- ============================================================
local optionsInit = CreateFrame("Frame")
optionsInit:RegisterEvent("PLAYER_LOGIN")
optionsInit:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if optionsRegistered then return end
    if not Settings or not Settings.RegisterCanvasLayoutCategory then return end

    local parentPanel = CreateFrame("Frame")
    parentPanel:SetSize(600, 200)
    parentPanel:SetScript("OnShow", function(self)
        self:SetScript("OnShow", nil)
        BuildAndRegisterSubcategories()
    end)

    parentCategory = Settings.RegisterCanvasLayoutCategory(parentPanel, "Ckraig Cooldown Manager")
    Settings.RegisterAddOnCategory(parentCategory)
    optionsRegistered = true

    -- Slash command
    SLASH_CKCDM1 = "/ckcdm"
    SlashCmdList["CKCDM"] = function()
        Settings.OpenToCategory(parentCategory:GetID())
    end
end)
