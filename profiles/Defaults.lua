-- ============================================================
-- CkraigCooldownManager :: Profiles :: Defaults
-- ============================================================
-- All default profile values for every module.
-- Separated from ProfileManager.lua for readability.
-- ============================================================

local CCM = _G.CkraigCooldownManager
CCM.ProfileDefaults = CCM.ProfileDefaults or {}

CCM.ProfileDefaults.defaults = {
    profile = {
        -- ------------------------------------------------
        -- Cooldown Bars  (CCM_CooldownBars)
        -- ------------------------------------------------
        buffBars = {
            anchorPoint = "CENTER",
            relativePoint = "CENTER",
            anchorX = 0,
            anchorY = 0,
            enabled = true,
            font = "Friz Quadrata TT",
            fontSize = 11,
            barTextFontSize = 11,
            stackFontSize = 14,
            stackFontOffsetX = 0,
            stackFontOffsetY = 0,
            stackFontScale = 1.6,
            texture = "Blizzard Raid Bar",
            borderSize = 1.0,
            backdropBorderSize = 1.0,
            borderColor = {r = 0, g = 0, b = 0, a = 1},
            barHeight = 24,
            barWidth = 200,
            barSpacing = 2,
            showIcon = true,
            useClassColor = true,
            customColor = {r = 0.5, g = 0.5, b = 0.5, a = 1},
            backdropColor = {r = 0, g = 0, b = 0, a = 0.5},
            truncateText = false,
            maxTextWidth = 0,
            frameStrata = "LOW",
            barAlpha = 1.0,
            hideBarName = false,
            hideIcons = false,
            timerTextAlign = "RIGHT",
            timerTextFontSize = 11,
        },

        -- ------------------------------------------------
        -- Dynamic Icons  (DYNAMICICONS)
        -- ------------------------------------------------
        dynamicIcons = {
            enabled = true,
            columns = 3,
            hSpacing = 2,
            vSpacing = 2,
            growUp = true,
            locked = true,
            iconSize = 36,
            aspectRatio = "1:1",
            aspectRatioCrop = nil,
            spacing = 0,
            rowLimit = 0,
            rowGrowDirection = "up",
            iconCornerRadius = 1,
            cooldownTextSize = 16,
            cooldownTextPosition = "CENTER",
            cooldownTextX = 0,
            cooldownTextY = 0,
            chargeTextSize = 18,
            chargeTextPosition = "TOP",
            chargeTextX = 0,
            chargeTextY = 13,
            cooldownTextFont = "Friz Quadrata TT",
            showCooldownText = true,
            showChargeText = true,
            hideWhenMounted = false,
            cooldownTextColor = {r = 1, g = 1, b = 1, a = 1},
            borderSize = 1,
            borderColor = {r = 0, g = 0, b = 0, a = 1},
            backgroundColor = {r = 0, g = 0, b = 0, a = 0.5},
            staticGridMode = false,
            gridRows = 4,
            gridColumns = 4,
            gridSlotMap = {},
            rowSizes = {},
            startupSamplePreview = true,
        },

        -- ------------------------------------------------
        -- Essential Buffs  (MyEssentialBuffTracker)
        -- ------------------------------------------------
        essentialBuffs = {
            enabled = true,
            columns         = 9,
            hSpacing        = 0,
            vSpacing        = 0,
            growUp          = true,
            locked          = true,
            iconSize        = 36,
            aspectRatio     = "1:1",
            aspectRatioCrop = nil,
            spacing         = 0,
            rowLimit        = 9,
            rowGrowDirection= "down",
            iconCornerRadius = 1,
            cooldownTextSize = 16,
            cooldownTextPosition = "CENTER",
            cooldownTextX = 0,
            cooldownTextY = 0,
            chargeTextSize = 14,
            chargeTextPosition = "BOTTOMRIGHT",
            chargeTextX = 0,
            chargeTextY = 0,
            showCooldownText = true,
            showChargeText = true,
            hideWhenMounted = false,
            staticGridMode = false,
            gridRows = 4,
            gridColumns = 4,
            gridSlotMap = {},
            rowSizes = {},
            borderSize = 1,
            borderColor = {0, 0, 0, 1},
        },

        -- ------------------------------------------------
        -- Utility Buffs  (MyUtilityBuffTracker)
        -- ------------------------------------------------
        utilityBuffs = {
            enabled = true,
            columns = 3,
            hSpacing = 2,
            vSpacing = 2,
            growUp = true,
            locked = true,
            iconSize = 36,
            aspectRatio = "1:1",
            aspectRatioCrop = nil,
            spacing = 0,
            rowLimit = 0,
            rowGrowDirection = "down",
            iconCornerRadius = 1,
            cooldownTextSize = 16,
            cooldownTextPosition = "CENTER",
            cooldownTextX = 0,
            cooldownTextY = 0,
            chargeTextSize = 14,
            chargeTextPosition = "BOTTOMRIGHT",
            chargeTextX = 0,
            chargeTextY = 0,
            showCooldownText = true,
            showChargeText = true,
            hideWhenMounted = false,
            staticGridMode = false,
            gridRows = 4,
            gridColumns = 4,
            gridSlotMap = {},
            rowSizes = {},
        },

        -- ------------------------------------------------
        -- Charge Text Colors  (ChargeTextColorOptions)
        -- ------------------------------------------------
        chargeTextColors = {},

        -- ------------------------------------------------
        -- Power Potion Success Icon
        -- ------------------------------------------------
        powerPotionSuccessIcon = {
            enabled = true,
            iconSize = 36,
            positionX = 200,
            positionY = 0,
            locked = true,
            clusterIndex = 1,
            frameStrata = "BACKGROUND",
            showInDynamic = false,
            showTimer = true,
            powerPotionsList = {431932, 370816, 1236616, 1238443, 1236652, 1236994, 1236998, 1236551},
            timerDurations = {
                [431932] = 30,
                [370816] = 30,
                [1236616] = 30,
                [1238443] = 30,
                [1236652] = 30,
                [1236994] = 30,
                [1236998] = 30,
                [1236551] = 30,
            },
        },

        -- ------------------------------------------------
        -- Defensive Aura Alerts
        -- ------------------------------------------------
        defensiveAura = {
            enabled = true,
            alertSound = "RAID_WARNING",
            flashScreen = false,
            printMessage = false,
        },

        -- ------------------------------------------------
        -- Segment Bars
        -- ------------------------------------------------
        segmentBars = {
            enabled = true,
            hideWhenMounted = false,
            barWidth = 140,
            barHeight = 20,
            barSpacing = 4,
            anchorX = 0,
            anchorY = -180,
            locked = true,
            fillingTexture = "Blizzard Raid Bar",
            tickTexture = "Blizzard Raid Bar",
            tickWidth = 2,
            tickColor = { 0, 0, 0, 1 },
            bgColor = { 0.08, 0.08, 0.08, 0.75 },
            frameStrata = "LOW",
            showLabel = true,
            labelFontSize = 11,
            labelFont = "Friz Quadrata TT",
            spells = {},
        },

        -- ------------------------------------------------
        -- Resource Bars  (health, power, class resource)
        -- ------------------------------------------------
        resourceBars = {
            healthBar = {
                enabled = true,
                width = 200,
                height = 20,
                texture = "Blizzard Raid Bar",
                bgColor = { r = 0.15, g = 0.15, b = 0.15, a = 0.8 },
                borderSize = 1,
                borderColor = { r = 0, g = 0, b = 0, a = 1 },
                useClassColor = true,
                customColor = { r = 0.2, g = 0.8, b = 0.2, a = 1 },
                showText = true,
                textFormat = "percent",
                textSize = 12,
                anchor = "free",
                position = { point = "CENTER", x = 0, y = -80 },
                hideWhenMounted = false,
                hideOutOfCombat = false,
                showAbsorb = true,
                absorbColor = { r = 0.8, g = 0.8, b = 0.2, a = 0.5 },
            },
            powerBar = {
                enabled = true,
                width = 200,
                height = 14,
                texture = "Blizzard Raid Bar",
                bgColor = { r = 0.15, g = 0.15, b = 0.15, a = 0.8 },
                borderSize = 1,
                borderColor = { r = 0, g = 0, b = 0, a = 1 },
                usePowerColor = true,
                customColor = { r = 0.2, g = 0.2, b = 0.8, a = 1 },
                showText = true,
                textFormat = "current",
                textSize = 11,
                anchor = "free",
                position = { point = "CENTER", x = 0, y = -100 },
                hideWhenMounted = false,
                hideOutOfCombat = false,
            },
            altPowerBar = {
                enabled = false,
                width = 200,
                height = 12,
                texture = "Blizzard Raid Bar",
                bgColor = { r = 0.15, g = 0.15, b = 0.15, a = 0.8 },
                borderSize = 1,
                borderColor = { r = 0, g = 0, b = 0, a = 1 },
                customColor = { r = 0.9, g = 0.6, b = 0.1, a = 1 },
                showText = true,
                textSize = 10,
                anchor = "free",
                position = { point = "CENTER", x = 0, y = -115 },
            },
            classResource = {
                enabled = true,
                segmentWidth = 22,
                segmentHeight = 14,
                segmentSpacing = 3,
                borderSize = 1,
                borderColor = { r = 0, g = 0, b = 0, a = 1 },
                anchor = "free",
                position = { point = "CENTER", x = 0, y = -60 },
                hideWhenMounted = false,
                hideOutOfCombat = false,
                usePerPointColor = true,
                staggerWidth = 200,
                staggerHeight = 14,
                staggerTexture = "Blizzard Raid Bar",
                staggerBgColor = { r = 0.15, g = 0.15, b = 0.15, a = 0.8 },
                staggerShowText = true,
                staggerTextSize = 11,
            },
        },
    },
}
