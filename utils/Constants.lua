-- ============================================================
-- CkraigCooldownManager :: Utils :: Constants
-- ============================================================
-- Addon-wide constants and default values.
-- Keeps magic numbers out of logic files.
-- ============================================================

local CCM = _G.CkraigCooldownManager
CCM.Constants = CCM.Constants or {}

-- General layout defaults
CCM.Constants.DEFAULT_ICON_SIZE      = 36
CCM.Constants.DEFAULT_ICON_SPACING   = 50
CCM.Constants.DEFAULT_ICON_ROW_SPACING = 10
CCM.Constants.DEFAULT_ICONS_PER_ROW  = 6

-- Bar defaults
CCM.Constants.DEFAULT_BAR_HEIGHT     = 24
CCM.Constants.DEFAULT_BAR_WIDTH      = 200
CCM.Constants.DEFAULT_BAR_SPACING    = 2
CCM.Constants.DEFAULT_FONT_SIZE      = 11
CCM.Constants.DEFAULT_FONT           = "Friz Quadrata TT"
CCM.Constants.DEFAULT_TEXTURE        = "Blizzard Raid Bar"

-- Fade threshold for smooth bar transitions
CCM.Constants.FADE_THRESHOLD         = 0.3

-- Maximum number of bar clusters
CCM.Constants.MAX_BAR_CLUSTERS       = 10

-- Frame strata options
CCM.Constants.FRAME_STRATA_OPTIONS = {
    "BACKGROUND",
    "LOW",
    "MEDIUM",
    "HIGH",
    "DIALOG",
    "TOOLTIP",
}

-- Aspect ratio options used by icon trackers
CCM.Constants.ASPECT_RATIO_OPTIONS = {
    "1:1",
    "4:3",
    "16:9",
    "3:2",
}
