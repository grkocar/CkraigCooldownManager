-- CkraigsOptions.lua
-- Registers a single parent category with all module panels as subcategories in the Blizzard settings UI
-- Panels are created lazily on first open to avoid CPU cost at login

local optionsRegistered = false
local panelsBuilt = false

local function SafeCall(fn, obj)
    if type(fn) ~= "function" then
        return false
    end
    local ok
    if obj then
        ok = pcall(fn, obj)
    else
        ok = pcall(fn)
    end
    return ok
end

local parentCategory  -- stored so subcategories can be added lazily

local function BuildAndRegisterSubcategories()
    if panelsBuilt or not parentCategory then return end
    panelsBuilt = true

    -- Create all panels now (first time settings are opened)
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

    -- Register subcategories
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

-- Register on login — only the lightweight parent category
local optionsInit = CreateFrame("Frame")
optionsInit:RegisterEvent("PLAYER_LOGIN")
optionsInit:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()

    if optionsRegistered then return end
    if not Settings or not Settings.RegisterCanvasLayoutCategory or not Settings.RegisterAddOnCategory or not Settings.RegisterCanvasLayoutSubcategory then
        return
    end

    local parentPanel = CreateFrame("Frame")
    parentPanel:SetSize(600, 200)

    -- Build subcategories the first time the parent panel is shown
    parentPanel:SetScript("OnShow", function(self)
        self:SetScript("OnShow", nil)
        BuildAndRegisterSubcategories()
    end)

    parentCategory = Settings.RegisterCanvasLayoutCategory(parentPanel, "Ckraig Cooldown Manager")
    Settings.RegisterAddOnCategory(parentCategory)
    optionsRegistered = true

    -- Slash command to open options
    SLASH_CKCDM1 = "/ckcdm"
    SlashCmdList["CKCDM"] = function()
        Settings.OpenToCategory(parentCategory:GetID())
    end

    -- Minimap button
    local minimapBtn = CreateFrame("Button", "CkraigCDM_MinimapButton", Minimap)
    minimapBtn:SetSize(32, 32)
    minimapBtn:SetFrameStrata("MEDIUM")
    minimapBtn:SetFrameLevel(8)
    minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    minimapBtn:SetMovable(true)
    minimapBtn:RegisterForDrag("LeftButton")

    local icon = minimapBtn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture("Interface\\AddOns\\CkraigCooldownManager\\CK_logo")

    local border = minimapBtn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Position around the minimap edge (supports round and square minimaps)
    local savedAngle = CCM_Settings and CCM_Settings.minimapAngle or 220
    local function IsMinimapSquare()
        if GetMinimapShape and GetMinimapShape() == "SQUARE" then return true end
        local mask = Minimap.GetMaskTexture and Minimap:GetMaskTexture()
        if mask and (mask == "" or mask:lower():find("square")) then return true end
        return false
    end
    local function UpdateMinimapPosition(angle)
        local rad = math.rad(angle)
        local cos, sin = math.cos(rad), math.sin(rad)
        local x, y
        if IsMinimapSquare() then
            -- Clamp to square edge
            local half = Minimap:GetWidth() / 2 + 5
            local scale = math.max(math.abs(cos), math.abs(sin))
            x = cos / scale * half
            y = sin / scale * half
        else
            x = cos * 80
            y = sin * 80
        end
        minimapBtn:ClearAllPoints()
        minimapBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end
    UpdateMinimapPosition(savedAngle)

    -- Drag to reposition around minimap
    minimapBtn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local angle = math.deg(math.atan2(cy - my, cx - mx))
            UpdateMinimapPosition(angle)
            CCM_Settings = CCM_Settings or {}
            CCM_Settings.minimapAngle = angle
        end)
    end)
    minimapBtn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    minimapBtn:SetScript("OnClick", function()
        if InCombatLockdown() then
            print("|cffff6600Ckraig Cooldown Manager:|r Cannot open settings during combat.")
            return
        end
        Settings.OpenToCategory(parentCategory:GetID())
    end)
    minimapBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Ckraig Cooldown Manager")
        GameTooltip:AddLine("|cffffffffClick|r to open options", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cffffffffDrag|r to move", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    minimapBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end)
