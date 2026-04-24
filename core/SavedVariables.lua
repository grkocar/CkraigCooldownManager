-- ============================================================
-- CkraigCooldownManager :: Core :: SavedVariables
-- ============================================================
-- Declares all SavedVariables tables up-front with safe defaults.
-- This file loads very early so every module can safely reference
-- its DB table even before ADDON_LOADED fires.
-- ============================================================

-- Profile database (managed by AceDB via ProfileManager)
CkraigCooldownManagerDB    = CkraigCooldownManagerDB    or {}

-- Per-module saved variables
MyEssentialBuffTrackerDB   = MyEssentialBuffTrackerDB   or {}
MyUtilityBuffTrackerDB     = MyUtilityBuffTrackerDB     or {}
UtilityIconDuplicatorDB    = UtilityIconDuplicatorDB    or {}
DYNAMICICONSDB             = DYNAMICICONSDB             or {}
DYNAMICBARSDB              = DYNAMICBARSDB              or {}
CooldownChargeDB           = CooldownChargeDB           or {}
CCM_Settings               = CCM_Settings               or {}
CCM_Settings.showMinimapButton = (CCM_Settings.showMinimapButton ~= false) -- default true
TrinketTrackerDB           = TrinketTrackerDB           or {}
PowerPotionSuccessIconDB   = PowerPotionSuccessIconDB   or {}
CCM_TrackedSpellsDB        = CCM_TrackedSpellsDB        or {}
CCM_SegmentBarsDB          = CCM_SegmentBarsDB          or {}
CCM_TrackedSpellsSettings  = CCM_TrackedSpellsSettings  or {}
CCM_DefensiveAuraDB        = CCM_DefensiveAuraDB        or {}
CCM_EditModeTogglePanelDB  = CCM_EditModeTogglePanelDB  or {}
CCM_ResourceBarsDB         = CCM_ResourceBarsDB         or {}
