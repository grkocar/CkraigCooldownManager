-- CPU Optimization: All event handling consolidated into ScheduleTrinketBatch system below
-- Get profile data for tracked items
local function GetProfileData()
	if CkraigProfileManager and CkraigProfileManager.GetProfileData then
		local data = CkraigProfileManager:GetProfileData("trackedItems")
		if data then
			return data
		end
	end
	return {}
end

-- Set profile data for tracked items
local function SetProfileData(key, value)
	local data = GetProfileData()
	data[key] = value
	if CkraigProfileManager and CkraigProfileManager.SetProfileData then
		CkraigProfileManager:SetProfileData("trackedItems", data)
	end
end
-- Helper to check for safe, non-tainted numbers



-- List of all relevant racial spell IDs
local RACIALS = {
	212971,212970,212969,7744, 20549, 20572, 33697, 33702, 20589, 20594, 26297, 28880, 59542, 59543, 59544, 59545, 59547, 59548, 121093, 370626, 416250, 58984, 59752, 68992, 69041, 69070, 107079, 25046, 28730, 50613, 69179, 80483, 202719, 129597, 155145, 232633, 255647, 255654,256948, 260364, 265221, 274738, 287712, 291944, 312411, 312924, 357214, 368970, 436344, 1237885
}
if not RACIALS then
	RACIALS = {}
end


-- List of all relevant power potion item IDs
local POWER_POTIONS = { 241308, 241309, 212264, 212265, 212263,}
if not POWER_POTIONS then
	POWER_POTIONS = {}
end

-- List of all relevant healing potion item IDs (add more as needed)
local HEALING_POTIONS = {
	241304, -- New potionID healingPotionID midnight
	244839, -- New potionID healingPotionID
	258138, --potent healing potion that give50%health
	244835, -- healwarwithin
	244838, -- healing warwithin
	211880, -- WARWITHIN HEALING POTION
	211879, -- New healing potion warwithin
	211878, -- New healing potion warwithin
	191380, -- Refreshing Healing Potion (Dragonflight)
	187802, -- Cosmic Healing Potion (Shadowlands)
	169451, -- Abyssal Healing Potion (BFA)
	152615, -- Coastal Healing Potion (BFA)
	127834, -- Ancient Healing Potion (Legion)
	109223, -- Healing Tonic (WoD)
	76097,  -- Master Healing Potion (MoP)
	57191,  -- Mythical Healing Potion (Cata)
	33447,  -- Runic Healing Potion (WotLK)
	22829,  -- Super Healing Potion (TBC)
	13446,  -- Major Healing Potion (Classic)
	3928,   -- Superior Healing Potion (Classic)
	1710,   -- Greater Healing Potion (Classic)
	929,    -- Healing Potion (Classic)
	118     -- Minor Healing Potion (Classic)
}
local function FindFirstUsableHealingPotion()
	for _, potionID in ipairs(HEALING_POTIONS) do
		local count = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(potionID, false, true) or 0
		if count > 0 then
			return potionID, count
		end
	end
	return nil, 0
end

-- New function to find Healthstone
local function FindHealthstone()
	local itemIDs = {224464, 5512} -- Demonic Healthstone first, then regular Healthstone
	for _, itemID in ipairs(itemIDs) do
		local count = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemID, false, true) or 0
		if count > 0 then
			return itemID, count
		end
	end
	return nil, 0
end


local LibEditMode = LibStub("LibEditMode", true)

local ICON_SIZE = 40
local ICON_SIZE_1 = 40
local ICON_SIZE_2 = 40
local ICON_PADDING = 5
local ICON_SPACING = 0
local ICON_SPACING_1 = 0
local ICON_SPACING_2 = 0
local ICON_ROW_SPACING = 10
local ICONS_PER_ROW_1 = 6 -- Blue box (group 1)
local ICONS_PER_ROW_2 = 6 -- Yellow box (group 2)
local ICON_START_X = 0
local ICON_START_Y = 0
local SAMPLE_HEALING_ICON_ID = 7548909
local SAMPLE_POWER_ICON_ID = 7548911
-- Per-icon group assignment: maps icon key -> group number (1 or 2)
local IconGroupAssignments = {}
local DEFAULT_ASSIGNMENTS = {
	racials = 1, power = 1, healing = 1,
	healthstone = 2, trinket13 = 2, trinket14 = 2,
}

-- Legacy (kept for migration only)
local Group1IconCount = 3
local Group2IconCount = 3

-- Group mode: "single" (all icons in one group) or "split" (evenly split into 2 groups)
local GroupMode = "single"

-- Configurable enabled state
local TrackedItemsEnabled = true
local ShowPassiveTrinkets = true

-- Group 2 cluster integration
local Group2ClusterMode = false
local Group2ClusterIndex = 1


local function GetProfileData()
	if CkraigProfileManager and CkraigProfileManager.GetProfileData then
		local data = CkraigProfileManager:GetProfileData("trackedItems")
		if data then
			return data
		end
	end
	return {}
end

-- Get or initialize icon order
local function GetIconOrder()
	local data = GetProfileData()
	if not data.iconOrder then
		-- Default order: racials, power, healing, healthstone, trinket13, trinket14
		data.iconOrder = {"racials", "power", "healing", "healthstone", "trinket13", "trinket14"}
		SetProfileData("iconOrder", data.iconOrder)
	end
	return data.iconOrder
end

local function SetIconOrder(order)
	SetProfileData("iconOrder", order)
end

-- Per-icon group assignment helpers
local function GetIconGroupAssignments()
	local data = GetProfileData()
	if data.iconGroupAssignments then
		return data.iconGroupAssignments
	end
	return nil -- nil means not yet migrated
end

local function SetIconGroupAssignments(assignments)
	IconGroupAssignments = assignments
	SetProfileData("iconGroupAssignments", assignments)
end

local function EnsureIconGroupAssignments()
	-- If assignments already exist in saved data, use them
	local saved = GetIconGroupAssignments()
	if saved then
		IconGroupAssignments = saved
		return
	end
	-- Migrate from old count-based split
	local data = GetProfileData()
	local oldG1 = data.group1IconCount or 3
	local oldG2 = data.group2IconCount or 3
	local order = GetIconOrder()
	local assignments = {}
	for i, key in ipairs(order) do
		if i <= oldG1 then
			assignments[key] = 1
		elseif i <= oldG1 + oldG2 then
			assignments[key] = 2
		else
			assignments[key] = 1 -- overflow goes to group 1
		end
	end
	-- Fill any missing keys with defaults
	for key, grp in pairs(DEFAULT_ASSIGNMENTS) do
		if not assignments[key] then
			assignments[key] = grp
		end
	end
	SetIconGroupAssignments(assignments)
end

-- Load settings from profile
local function LoadSettings()
	local data = GetProfileData()
	TrackedItemsEnabled = data.enabled ~= false -- default true
	ShowPassiveTrinkets = data.showPassiveTrinkets ~= false -- default true
	ICON_SIZE = data.iconSize or 40
	ICON_SIZE_1 = data.iconSize1 or ICON_SIZE
	ICON_SIZE_2 = data.iconSize2 or ICON_SIZE
	ICON_SPACING = data.iconSpacing or 0
	ICON_SPACING_1 = data.iconSpacing1 or 0
	ICON_SPACING_2 = data.iconSpacing2 or 0
	ICON_ROW_SPACING = data.iconRowSpacing or 10
	ICONS_PER_ROW_1 = data.iconsPerRow1 or 6
	ICONS_PER_ROW_2 = data.iconsPerRow2 or 6
	GroupMode = data.groupMode or "single"
	Group1IconCount = data.group1IconCount or 3
	Group2IconCount = data.group2IconCount or 3
	Group2ClusterMode = data.group2ClusterMode or false
	Group2ClusterIndex = data.group2ClusterIndex or 1
	EnsureIconGroupAssignments()
end

-- Load enabled state early so event registration can be gated
LoadSettings()

-- Save settings to profile
local function SaveSettings()
	SetProfileData("enabled", TrackedItemsEnabled)
	SetProfileData("iconSize", ICON_SIZE)
	SetProfileData("iconSize1", ICON_SIZE_1)
	SetProfileData("iconSize2", ICON_SIZE_2)
	SetProfileData("iconSpacing", ICON_SPACING)
	SetProfileData("iconSpacing1", ICON_SPACING_1)
	SetProfileData("iconSpacing2", ICON_SPACING_2)
	SetProfileData("iconRowSpacing", ICON_ROW_SPACING)
	SetProfileData("iconsPerRow1", ICONS_PER_ROW_1)
	SetProfileData("iconsPerRow2", ICONS_PER_ROW_2)
	SetProfileData("groupMode", GroupMode)
	SetProfileData("showPassiveTrinkets", ShowPassiveTrinkets)
	SetProfileData("group2ClusterMode", Group2ClusterMode)
	SetProfileData("group2ClusterIndex", Group2ClusterIndex)
end



-- Profile-aware saved position for group 1
local function GetProfilePosition()
	if CkraigProfileManager and CkraigProfileManager.GetProfileData then
		local data = CkraigProfileManager:GetProfileData("trinketIcons")
		if data and data.x and data.y then
			return {x = data.x, y = data.y}
		end
	end
	return {x = 0, y = 0}
end

local function SetProfilePosition(x, y)
	if CkraigProfileManager and CkraigProfileManager.SetProfileData then
		local data = CkraigProfileManager:GetProfileData("trinketIcons") or {}
		data.x = x
		data.y = y
		CkraigProfileManager:SetProfileData("trinketIcons", data)
	end
end

-- Profile-aware saved position for group 2
local function GetProfilePosition2()
	if CkraigProfileManager and CkraigProfileManager.GetProfileData then
		local data = CkraigProfileManager:GetProfileData("trinketIcons2")
		if data and data.x and data.y then
			return {x = data.x, y = data.y}
		end
	end
	return {x = 0, y = -80}
end


local CCM_SavedPosition = {x = 0, y = 0} -- Only updated after PLAYER_LOGIN
local CCM_SavedPosition2 = {x = 0, y = 0}

-- Forward declarations for cross-referencing in OnMouseUp handlers
local anchorFrame2

-- Anchor frame for group 1
local anchorFrame = CreateFrame("Frame", "CCM_AnchorFrame", UIParent)
anchorFrame:SetSize(240, 60)
anchorFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
anchorFrame:EnableMouse(false)
anchorFrame:SetMovable(true)
anchorFrame:SetFrameStrata("MEDIUM")
anchorFrame:RegisterForDrag("LeftButton")
anchorFrame:SetScript("OnDragStart", function(self)
	if InCombatLockdown() then return end
	self.isDragging = true
	self:SetMovable(true)
	self:EnableMouse(true)
	self:StartMoving()
	self:Show()
end)
anchorFrame:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local x, y = self:GetCenter()
	local ux, uy = UIParent:GetCenter()
	CCM_SavedPosition.x = math.floor(x - ux)
	CCM_SavedPosition.y = math.floor(y - uy)
	SetProfilePosition(CCM_SavedPosition.x, CCM_SavedPosition.y)
	-- Re-anchor to CENTER so arrow key nudging works from correct position
	self:ClearAllPoints()
	self:SetPoint("CENTER", UIParent, "CENTER", CCM_SavedPosition.x, CCM_SavedPosition.y)
	self.isDragging = false
end)

local anchorTex = anchorFrame:CreateTexture(nil, "BACKGROUND")
anchorTex:SetAllPoints(anchorFrame)
anchorTex:SetColorTexture(0, 1, 1, 0.15)

local anchorLabel = anchorFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
anchorLabel:SetPoint("TOP", 0, -4)
anchorLabel:SetText("Group 1")
anchorLabel:SetTextColor(0, 1, 1, 1)
anchorFrame._anchorLabel = anchorLabel

-- Arrow key nudging for pixel-perfect positioning
anchorFrame:EnableKeyboard(false)
anchorFrame:SetScript("OnKeyDown", function(self, key)
	if InCombatLockdown() then return end
	local step = IsShiftKeyDown() and 10 or 1
	if key == "UP" then
		CCM_SavedPosition.y = CCM_SavedPosition.y + step
	elseif key == "DOWN" then
		CCM_SavedPosition.y = CCM_SavedPosition.y - step
	elseif key == "LEFT" then
		CCM_SavedPosition.x = CCM_SavedPosition.x - step
	elseif key == "RIGHT" then
		CCM_SavedPosition.x = CCM_SavedPosition.x + step
	elseif key == "ESCAPE" then
		self:EnableKeyboard(false)
		self._arrowKeyActive = false
		self._anchorLabel:SetText("Group 1")
		self:SetPropagateKeyboardInput(true)
		return
	else
		self:SetPropagateKeyboardInput(true)
		return
	end
	self:SetPropagateKeyboardInput(false)
	self:ClearAllPoints()
	self:SetPoint("CENTER", UIParent, "CENTER", CCM_SavedPosition.x, CCM_SavedPosition.y)
	SetProfilePosition(CCM_SavedPosition.x, CCM_SavedPosition.y)
	UpdateAllIcons()
end)
anchorFrame:SetScript("OnMouseUp", function(self, button)
	if button == "RightButton" and self.moving then
		local wasActive = self._arrowKeyActive
		-- Deselect both anchors first
		anchorFrame:EnableKeyboard(false)
		anchorFrame._arrowKeyActive = false
		anchorFrame._anchorLabel:SetText("Group 1")
		anchorFrame2:EnableKeyboard(false)
		anchorFrame2._arrowKeyActive = false
		anchorFrame2._anchorLabel:SetText("Group 2")
		if not wasActive then
			self:EnableKeyboard(true)
			self._arrowKeyActive = true
			self._anchorLabel:SetText("Group 1 [ARROWS]")
		end
	end
end)

anchorFrame:Hide()

-- Helper to save group 2 position to profile
local function SetProfilePosition2(x, y)
	CCM_SavedPosition2.x = x
	CCM_SavedPosition2.y = y
	if CkraigProfileManager and CkraigProfileManager.SetProfileData then
		local data = CkraigProfileManager:GetProfileData("trinketIcons2") or {}
		data.x = x
		data.y = y
		CkraigProfileManager:SetProfileData("trinketIcons2", data)
	end
end

-- Anchor frame for group 2
anchorFrame2 = CreateFrame("Frame", "CCM_AnchorFrame2", UIParent)
anchorFrame2:SetSize(240, 60)
anchorFrame2:SetPoint("CENTER", UIParent, "CENTER", 0, -80)
anchorFrame2:EnableMouse(false)
anchorFrame2:SetMovable(true)
anchorFrame2:SetFrameStrata("MEDIUM")
anchorFrame2:RegisterForDrag("LeftButton")
anchorFrame2:SetScript("OnDragStart", function(self)
	if InCombatLockdown() then return end
	self.isDragging = true
	self:SetMovable(true)
	self:EnableMouse(true)
	self:StartMoving()
	self:Show()
end)
anchorFrame2:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing()
	local x, y = self:GetCenter()
	local ux, uy = UIParent:GetCenter()
	CCM_SavedPosition2.x = math.floor(x - ux)
	CCM_SavedPosition2.y = math.floor(y - uy)
	SetProfilePosition2(CCM_SavedPosition2.x, CCM_SavedPosition2.y)
	-- Re-anchor to CENTER so arrow key nudging works from correct position
	self:ClearAllPoints()
	self:SetPoint("CENTER", UIParent, "CENTER", CCM_SavedPosition2.x, CCM_SavedPosition2.y)
	self.isDragging = false
end)

local anchorTex2 = anchorFrame2:CreateTexture(nil, "BACKGROUND")
anchorTex2:SetAllPoints(anchorFrame2)
anchorTex2:SetColorTexture(1, 1, 0, 0.15)

local anchorLabel2 = anchorFrame2:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
anchorLabel2:SetPoint("TOP", 0, -4)
anchorLabel2:SetText("Group 2")
anchorLabel2:SetTextColor(1, 1, 0, 1)
anchorFrame2._anchorLabel = anchorLabel2

-- Arrow key nudging for pixel-perfect positioning
anchorFrame2:EnableKeyboard(false)
anchorFrame2:SetScript("OnKeyDown", function(self, key)
	if InCombatLockdown() then return end
	local step = IsShiftKeyDown() and 10 or 1
	if key == "UP" then
		CCM_SavedPosition2.y = CCM_SavedPosition2.y + step
	elseif key == "DOWN" then
		CCM_SavedPosition2.y = CCM_SavedPosition2.y - step
	elseif key == "LEFT" then
		CCM_SavedPosition2.x = CCM_SavedPosition2.x - step
	elseif key == "RIGHT" then
		CCM_SavedPosition2.x = CCM_SavedPosition2.x + step
	elseif key == "ESCAPE" then
		self:EnableKeyboard(false)
		self._arrowKeyActive = false
		self._anchorLabel:SetText("Group 2")
		self:SetPropagateKeyboardInput(true)
		return
	else
		self:SetPropagateKeyboardInput(true)
		return
	end
	self:SetPropagateKeyboardInput(false)
	self:ClearAllPoints()
	self:SetPoint("CENTER", UIParent, "CENTER", CCM_SavedPosition2.x, CCM_SavedPosition2.y)
	SetProfilePosition2(CCM_SavedPosition2.x, CCM_SavedPosition2.y)
	UpdateAllIcons()
end)
anchorFrame2:SetScript("OnMouseUp", function(self, button)
	if button == "RightButton" and self.moving then
		local wasActive = self._arrowKeyActive
		-- Deselect both anchors first
		anchorFrame:EnableKeyboard(false)
		anchorFrame._arrowKeyActive = false
		anchorFrame._anchorLabel:SetText("Group 1")
		anchorFrame2:EnableKeyboard(false)
		anchorFrame2._arrowKeyActive = false
		anchorFrame2._anchorLabel:SetText("Group 2")
		if not wasActive then
			self:EnableKeyboard(true)
			self._arrowKeyActive = true
			self._anchorLabel:SetText("Group 2 [ARROWS]")
		end
	end
end)

anchorFrame2:Hide()

-- -----------------------------------------------
-- LibEditMode integration for Group 1 & Group 2
-- -----------------------------------------------

-- Per-layout position helpers
local function GetLayoutPositions(profileKey)
	local data = GetProfileData()
	data.layoutPositions = data.layoutPositions or {}
	data.layoutPositions[profileKey] = data.layoutPositions[profileKey] or {}
	return data.layoutPositions[profileKey]
end

local function SetLayoutPosition(profileKey, layoutName, x, y)
	local data = GetProfileData()
	data.layoutPositions = data.layoutPositions or {}
	data.layoutPositions[profileKey] = data.layoutPositions[profileKey] or {}
	data.layoutPositions[profileKey][layoutName] = { x = x, y = y }
	SetProfileData("layoutPositions", data.layoutPositions)
end

local function GetBestPosition(profileKey, getProfilePosFn, defaultPos)
	local layoutName = LibEditMode and LibEditMode:GetActiveLayoutName()
	if layoutName then
		local lp = GetLayoutPositions(profileKey)
		if lp[layoutName] then
			return lp[layoutName]
		end
	end
	local saved = getProfilePosFn()
	if saved and saved.x and saved.y then return saved end
	return defaultPos
end

-- Register both anchors with LibEditMode
local function RegisterTrinketEditMode()
	if not LibEditMode then return end

	-- Group 1
	local default1 = { point = "CENTER", x = 0, y = 0 }
	LibEditMode:AddFrame(anchorFrame, function(frame, lName, pt, fx, fy)
		if not lName then return end
		SetLayoutPosition("group1", lName, fx, fy)
		-- Also save to legacy position
		CCM_SavedPosition.x = math.floor(fx)
		CCM_SavedPosition.y = math.floor(fy)
		SetProfilePosition(CCM_SavedPosition.x, CCM_SavedPosition.y)
	end, default1, "Trinket/Racial Group 1")

	LibEditMode:AddFrameSettings(anchorFrame, {
		{
			kind = LibEditMode.SettingType.Slider,
			name = "Icon Size",
			default = 40,
			get = function() return ICON_SIZE_1 end,
			set = function(_, newValue)
				ICON_SIZE_1 = newValue
				SaveSettings()
				UpdateAllIcons()
			end,
			minValue = 20,
			maxValue = 80,
			valueStep = 1,
		},
		{
			kind = LibEditMode.SettingType.Slider,
			name = "Icon Spacing",
			default = 0,
			get = function() return ICON_SPACING_1 end,
			set = function(_, newValue)
				ICON_SPACING_1 = newValue
				SaveSettings()
				UpdateAllIcons()
			end,
			minValue = 0,
			maxValue = 100,
			valueStep = 1,
		},
		{
			kind = LibEditMode.SettingType.Slider,
			name = "Row Spacing",
			default = 10,
			get = function() return ICON_ROW_SPACING end,
			set = function(_, newValue)
				ICON_ROW_SPACING = newValue
				SaveSettings()
				UpdateAllIcons()
			end,
			minValue = 0,
			maxValue = 50,
			valueStep = 1,
		},
		{
			kind = LibEditMode.SettingType.Slider,
			name = "Icons Per Row",
			default = 6,
			get = function() return ICONS_PER_ROW_1 end,
			set = function(_, newValue)
				ICONS_PER_ROW_1 = newValue
				SaveSettings()
				UpdateAllIcons()
			end,
			minValue = 1,
			maxValue = 12,
			valueStep = 1,
		},
	})

	-- Group 2
	local default2 = { point = "CENTER", x = 0, y = -80 }
	LibEditMode:AddFrame(anchorFrame2, function(frame, lName, pt, fx, fy)
		if not lName then return end
		SetLayoutPosition("group2", lName, fx, fy)
		CCM_SavedPosition2.x = math.floor(fx)
		CCM_SavedPosition2.y = math.floor(fy)
		SetProfilePosition2(CCM_SavedPosition2.x, CCM_SavedPosition2.y)
	end, default2, "Trinket/Racial Group 2")

	LibEditMode:AddFrameSettings(anchorFrame2, {
		{
			kind = LibEditMode.SettingType.Slider,
			name = "Icon Size",
			default = 40,
			get = function() return ICON_SIZE_2 end,
			set = function(_, newValue)
				ICON_SIZE_2 = newValue
				SaveSettings()
				UpdateAllIcons()
			end,
			minValue = 20,
			maxValue = 80,
			valueStep = 1,
		},
		{
			kind = LibEditMode.SettingType.Slider,
			name = "Icon Spacing",
			default = 0,
			get = function() return ICON_SPACING_2 end,
			set = function(_, newValue)
				ICON_SPACING_2 = newValue
				SaveSettings()
				UpdateAllIcons()
			end,
			minValue = 0,
			maxValue = 100,
			valueStep = 1,
		},
		{
			kind = LibEditMode.SettingType.Slider,
			name = "Row Spacing",
			default = 10,
			get = function() return ICON_ROW_SPACING end,
			set = function(_, newValue)
				ICON_ROW_SPACING = newValue
				SaveSettings()
				UpdateAllIcons()
			end,
			minValue = 0,
			maxValue = 50,
			valueStep = 1,
		},
		{
			kind = LibEditMode.SettingType.Slider,
			name = "Icons Per Row",
			default = 6,
			get = function() return ICONS_PER_ROW_2 end,
			set = function(_, newValue)
				ICONS_PER_ROW_2 = newValue
				SaveSettings()
				UpdateAllIcons()
			end,
			minValue = 1,
			maxValue = 12,
			valueStep = 1,
		},
	})
end

-- Restore positions when layout changes
local function RestoreTrinketPositionsForLayout(layoutName)
	if not layoutName then return end
	local lp1 = GetLayoutPositions("group1")
	if lp1[layoutName] then
		CCM_SavedPosition.x = lp1[layoutName].x
		CCM_SavedPosition.y = lp1[layoutName].y
		anchorFrame:ClearAllPoints()
		anchorFrame:SetPoint("CENTER", UIParent, "CENTER", CCM_SavedPosition.x, CCM_SavedPosition.y)
	end
	local lp2 = GetLayoutPositions("group2")
	if lp2[layoutName] then
		CCM_SavedPosition2.x = lp2[layoutName].x
		CCM_SavedPosition2.y = lp2[layoutName].y
		anchorFrame2:ClearAllPoints()
		anchorFrame2:SetPoint("CENTER", UIParent, "CENTER", CCM_SavedPosition2.x, CCM_SavedPosition2.y)
	end
	UpdateAllIcons()
end

-- Wire LibEditMode callbacks
local function SetupTrinketEditModeCallbacks()
	if not LibEditMode then return end

	LibEditMode:RegisterCallback("layout", function(layoutName)
		RestoreTrinketPositionsForLayout(layoutName)
	end)

	LibEditMode:RegisterCallback("enter", function()
		if not TrackedItemsEnabled then return end
		-- Show anchor frames so LibEditMode's selection overlays are visible and clickable
		anchorFrame:Show()
		anchorFrame._anchorLabel:Show()
		if GroupMode == "split" then
			anchorFrame2:Show()
			anchorFrame2._anchorLabel:Show()
		end
	end)

	LibEditMode:RegisterCallback("exit", function()
		anchorFrame:EnableMouse(false)
		anchorFrame:EnableKeyboard(false)
		anchorFrame._arrowKeyActive = false
		anchorFrame._anchorLabel:SetText("Group 1")
		anchorFrame:Hide()
		anchorFrame.moving = false
		anchorFrame2:EnableMouse(false)
		anchorFrame2:EnableKeyboard(false)
		anchorFrame2._arrowKeyActive = false
		anchorFrame2._anchorLabel:SetText("Group 2")
		anchorFrame2:Hide()
		anchorFrame2.moving = false
		UpdateAllIcons()
	end)
end

-- Slash command to enable moving group 1
SLASH_TRINKETMOVE1 = "/trinketmove"
SlashCmdList["TRINKETMOVE"] = function()
    if not anchorFrame.moving then
        anchorFrame:SetFrameStrata("TOOLTIP")
        anchorFrame:EnableMouse(true)
        anchorFrame:Show()
        anchorFrame:SetAlpha(1)
        anchorFrame.moving = true
    else
        if not anchorFrame.isDragging then
            anchorFrame:SetFrameStrata("MEDIUM")
            anchorFrame:EnableMouse(false)
            anchorFrame:EnableKeyboard(false)
            anchorFrame._arrowKeyActive = false
            anchorFrame._anchorLabel:SetText("Group 1")
            anchorFrame:Hide()
            anchorFrame.moving = false
        end
    end
end

-- Slash command to enable moving group 2
SLASH_TRINKETMOVE2 = "/trinketmove2"
SlashCmdList["TRINKETMOVE2"] = function()
    if not anchorFrame2.moving then
        anchorFrame2:SetFrameStrata("TOOLTIP")
        anchorFrame2:EnableMouse(true)
        anchorFrame2:Show()
        anchorFrame2:SetAlpha(1)
        anchorFrame2.moving = true
    else
        if not anchorFrame2.isDragging then
            anchorFrame2:SetFrameStrata("MEDIUM")
            anchorFrame2:EnableMouse(false)
            anchorFrame2:EnableKeyboard(false)
            anchorFrame2._arrowKeyActive = false
            anchorFrame2._anchorLabel:SetText("Group 2")
            anchorFrame2:Hide()
            anchorFrame2.moving = false
        end
    end
end

local iconFrames = {}

local function CreateOrGetIconFrame(index)
	if not iconFrames[index] then
		local frame = CreateFrame("Frame", nil, UIParent)
		frame:SetSize(ICON_SIZE, ICON_SIZE)
		frame:SetFrameStrata("MEDIUM")
		frame.texture = frame:CreateTexture(nil, "ARTWORK")
		frame.texture:SetAllPoints()
		-- ElvUI-style icon crop
		frame.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
		frame.cooldown:SetAllPoints(frame)
		frame.cooldown:SetDrawSwipe(true)
		frame.cooldown:SetDrawBling(true)
		frame.cooldown:SetHideCountdownNumbers(false)
		frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		frame.count:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
		frame.count:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")

		-- Add 1-pixel black border using four overlay textures
		if not frame.pixelBorders then
			frame.pixelBorders = {}
			-- Top
			local top = frame:CreateTexture(nil, "OVERLAY")
			top:SetColorTexture(0, 0, 0, 1)
			top:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
			top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
			top:SetHeight(1)
			frame.pixelBorders.top = top
			-- Bottom
			local bottom = frame:CreateTexture(nil, "OVERLAY")
			bottom:SetColorTexture(0, 0, 0, 1)
			bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
			bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
			bottom:SetHeight(1)
			frame.pixelBorders.bottom = bottom
			-- Left
			local leftB = frame:CreateTexture(nil, "OVERLAY")
			leftB:SetColorTexture(0, 0, 0, 1)
			leftB:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
			leftB:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
			leftB:SetWidth(1)
			frame.pixelBorders.left = leftB
			-- Right
			local rightB = frame:CreateTexture(nil, "OVERLAY")
			rightB:SetColorTexture(0, 0, 0, 1)
			rightB:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
			rightB:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
			rightB:SetWidth(1)
			frame.pixelBorders.right = rightB
		end
		for _, border in pairs(frame.pixelBorders) do border:Show() end

		-- Add shadow texture if not present
		if not frame.shadow then
			local shadow = frame:CreateTexture(nil, "BACKGROUND")
			shadow:SetTexture("Interface\\BUTTONS\\UI-Quickslot-Depress")
			shadow:SetAllPoints(frame)
			shadow:SetVertexColor(0, 0, 0, 0.6)
			frame.shadow = shadow
		end

		frame:Hide()
		iconFrames[index] = frame
	end
	return iconFrames[index]
end

local function ShowIconAt(frame, x, y)
	frame:ClearAllPoints()
	frame:SetPoint("CENTER", anchorFrame, "CENTER", x, y)
	frame:Show()
end

local function FindFirstUsablePotion()
	for _, potionID in ipairs(POWER_POTIONS) do
		local count = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(potionID, false, true) or 0
		if count > 0 then
			return potionID, count
		end
	end
	return nil, 0
end

local function GetSafeItemCooldown(itemID)
	if not itemID then
		return 0, 0, 0
	end
	local ok, start, duration, enable = pcall(GetItemCooldown, itemID)
	if ok then
		return start or 0, duration or 0, enable or 0
	end
	return 0, 0, 0
end

-- New API helper: safely set cooldown using duration objects or isActive field
-- Per Blizzard 12.0.1 hotfix: SetCooldown no longer accepts secret values.
-- Use GetSpellCooldownDuration/GetSpellChargeDuration + SetCooldownFromDurationObject.
local function SafeSetSpellCooldown(cooldownFrame, spellID)
	if not cooldownFrame then return end
	-- Try charges first
	local chargesInfo = C_Spell and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(spellID)
	if chargesInfo then
		if chargesInfo.currentCharges and chargesInfo.maxCharges and chargesInfo.currentCharges < chargesInfo.maxCharges then
			local chargeDurObj = C_Spell and C_Spell.GetSpellChargeDuration and C_Spell.GetSpellChargeDuration(spellID)
			if chargeDurObj then
				cooldownFrame:SetCooldownFromDurationObject(chargeDurObj)
			else
				cooldownFrame:Clear()
			end
		else
			cooldownFrame:Clear()
		end
		return chargesInfo
	end
	-- No charges, use regular cooldown durationObject
	local durObj = C_Spell and C_Spell.GetSpellCooldownDuration and C_Spell.GetSpellCooldownDuration(spellID)
	local cdInfo = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(spellID)
	if durObj and cdInfo and cdInfo.isOnGCD ~= true then
		cooldownFrame:SetCooldownFromDurationObject(durObj)
	else
		cooldownFrame:Clear()
	end
	return nil -- no charges info
end

-- Safe item cooldown setter using pcall
local function SafeSetItemCooldown(cooldownFrame, itemID)
	if not cooldownFrame or not itemID then
		if cooldownFrame then cooldownFrame:Clear() end
		return false
	end
	local start, duration, enable = GetSafeItemCooldown(itemID)
	if enable and enable ~= 0 then
		local ok = pcall(cooldownFrame.SetCooldown, cooldownFrame, start, duration)
		if not ok then cooldownFrame:Clear() end
		return true
	else
		cooldownFrame:Clear()
		return false
	end
end

-- Safe trinket cooldown setter using pcall
local function SafeSetTrinketCooldown(cooldownFrame, slot)
	if not cooldownFrame or not slot then
		if cooldownFrame then cooldownFrame:Clear() end
		return false
	end
	local start, duration, enable = GetInventoryItemCooldown("player", slot)
	if enable and type(start) == "number" and type(duration) == "number" then
		local ok = pcall(cooldownFrame.SetCooldown, cooldownFrame, start, duration)
		if not ok then cooldownFrame:Clear() end
		return true
	else
		cooldownFrame:Clear()
		return false
	end
end

local function FindPlayerRacials()
	local found = {}
	for _, spellID in ipairs(RACIALS) do
		if IsPlayerSpell(spellID) then
			table.insert(found, spellID)
		end
	end
	return found
end



function UpdateAllIcons()
	if anchorFrame.isDragging or anchorFrame2.isDragging then return end
	if not TrackedItemsEnabled then
		for i = 1, #iconFrames do
			if MyEssentialBuffTracker and MyEssentialBuffTracker.UnregisterExternalIcon then
				MyEssentialBuffTracker:UnregisterExternalIcon(iconFrames[i])
			end
			iconFrames[i]:Hide()
		end
		return
	end
	-- Move anchors to saved positions
	local pos = GetProfilePosition()
	CCM_SavedPosition.x = pos.x
	CCM_SavedPosition.y = pos.y
	anchorFrame:ClearAllPoints()
	anchorFrame:SetPoint("CENTER", UIParent, "CENTER", CCM_SavedPosition.x, CCM_SavedPosition.y)
	local pos2 = GetProfilePosition2()
	CCM_SavedPosition2.x = pos2.x
	CCM_SavedPosition2.y = pos2.y
	anchorFrame2:ClearAllPoints()
	anchorFrame2:SetPoint("CENTER", UIParent, "CENTER", CCM_SavedPosition2.x, CCM_SavedPosition2.y)
	local iconOrder = GetIconOrder()
	local iconDataList = {}
	for _, key in ipairs(iconOrder) do
		if key == "racials" then
			for _, spellID in ipairs(FindPlayerRacials()) do
				table.insert(iconDataList, {type="racial", spellID=spellID, groupKey="racials"})
			end
		elseif key == "power" then
			local potionID, potionCount = FindFirstUsablePotion()
			if potionID then
				table.insert(iconDataList, {type="power", itemID=potionID, count=potionCount, groupKey="power"})
			else
				-- Show sample icon if no power potions
				table.insert(iconDataList, {type="power", itemID=nil, iconID=SAMPLE_POWER_ICON_ID, count=0, desaturate=true, sample=true, groupKey="power"})
			end
		elseif key == "healing" then
			local healingPotionID, healingPotionCount = FindFirstUsableHealingPotion()
			if healingPotionID then
				table.insert(iconDataList, {type="healing", itemID=healingPotionID, count=healingPotionCount, groupKey="healing"})
			else
				-- Show sample icon if no healing potions
				table.insert(iconDataList, {type="healing", itemID=nil, iconID=SAMPLE_HEALING_ICON_ID, count=0, desaturate=true, sample=true, groupKey="healing"})
			end
		elseif key == "healthstone" then
			-- Always show healthstone icon, desaturated if not in bags
			local itemIDs = {224464, 5512}
			local foundID, foundCount = nil, 0
			for _, itemID in ipairs(itemIDs) do
				local count = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemID, false, true) or 0
				if count > 0 then
					foundID = itemID
					foundCount = count
					break
				end
			end
			local showID = foundID or itemIDs[1]
			table.insert(iconDataList, {type="healthstone", itemID=showID, count=foundCount, desaturate=(foundCount == 0), groupKey="healthstone"})
		elseif key == "trinket13" then
			local itemID = GetInventoryItemID("player", 13)
			if itemID then
				local isPassive = false
				local spellName = GetItemSpell(itemID)
				if not spellName then isPassive = true end
				if ShowPassiveTrinkets or not isPassive then
					table.insert(iconDataList, {type="trinket", slot=13, isPassive=isPassive, groupKey="trinket13"})
				end
			end
		elseif key == "trinket14" then
			local itemID = GetInventoryItemID("player", 14)
			if itemID then
				local isPassive = false
				local spellName = GetItemSpell(itemID)
				if not spellName then isPassive = true end
				if ShowPassiveTrinkets or not isPassive then
					table.insert(iconDataList, {type="trinket", slot=14, isPassive=isPassive, groupKey="trinket14"})
				end
			end
		end
	end

	local function PositionIcon(frame, idx, iconsInRow, row, col, rowOffsetX, anchor)
		local x = ICON_START_X + rowOffsetX + col * (ICON_SIZE_1 + ICON_SPACING_1)
		local y = ICON_START_Y - row * (ICON_SIZE_1 + ICON_ROW_SPACING)
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y)
		frame:Show()
	end

	local totalIcons = #iconDataList
	local usedFrames = 0

	if GroupMode == "split" and totalIcons > 1 then
		-- Split into 2 groups using per-icon assignments
		local group1 = {}
		local group2 = {}
		for i = 1, totalIcons do
			local data = iconDataList[i]
			local grp = IconGroupAssignments[data.groupKey] or 1
			if grp == 2 then
				table.insert(group2, data)
			else
				table.insert(group1, data)
			end
		end
		local numRows1 = math.ceil(#group1 / ICONS_PER_ROW_1)
		for row = 0, numRows1 - 1 do
			local startIdx = row * ICONS_PER_ROW_1 + 1
			local endIdx = math.min((row + 1) * ICONS_PER_ROW_1, #group1)
			local iconsInRow = endIdx - startIdx + 1
			local rowOffsetX = 0
			if iconsInRow < ICONS_PER_ROW_1 then
				local rowWidth = iconsInRow * ICON_SIZE_1 + (iconsInRow - 1) * ICON_SPACING_1
				local fullWidth = ICONS_PER_ROW_1 * ICON_SIZE_1 + (ICONS_PER_ROW_1 - 1) * ICON_SPACING_1
				rowOffsetX = math.floor((fullWidth - rowWidth) / 2)
			end
			for col = 0, iconsInRow - 1 do
				local i = startIdx + col
				local data = group1[i]
				local frame = CreateOrGetIconFrame(i)
				frame:SetSize(ICON_SIZE_1, ICON_SIZE_1)
				frame._trinketData = data
				frame.texture:SetDesaturated(false)
				if frame.grayOverlay then frame.grayOverlay:Hide() end
				if frame.cooldown then
					if frame.cooldown.SetDrawSwipe then frame.cooldown:SetDrawSwipe(true) end
					if frame.cooldown.SetSwipeColor then frame.cooldown:SetSwipeColor(0, 0, 0, 0.8) end
				end
				-- Set icon visuals (same as before)
				   if data.type == "racial" then
					   if frame.cooldown then
						   if frame.cooldown.SetDrawSwipe then frame.cooldown:SetDrawSwipe(false) end
						   if frame.cooldown.SetSwipeColor then frame.cooldown:SetSwipeColor(0, 0, 0, 0) end
					   end
					   local icon = C_Spell and C_Spell.GetSpellInfo and (C_Spell.GetSpellInfo(data.spellID) and C_Spell.GetSpellInfo(data.spellID).iconID) or select(3, GetSpellInfo(data.spellID))
					   frame.texture:SetTexture(icon)
					   local chargesInfo = SafeSetSpellCooldown(frame.cooldown, data.spellID)
					   if chargesInfo then
						   frame.count:SetText(chargesInfo.currentCharges > 1 and chargesInfo.currentCharges or "")
					   else
						   frame.count:SetText("")
					   end
				   elseif data.type == "power" then
					   local icon = data.iconID or ((C_Item and C_Item.GetItemIconByID and data.itemID and C_Item.GetItemIconByID(data.itemID)) or GetItemIcon(data.itemID))
					   frame.texture:SetTexture(icon)
					   local start, duration, enable = GetSafeItemCooldown(data.itemID)
					   local ok = pcall(frame.cooldown.SetCooldown, frame.cooldown, start, duration)
					   if not ok then frame.cooldown:Clear() end
					   frame.count:SetText(data.count and data.count > 1 and data.count or "")
					   -- Desaturate if on cooldown or if not in bags
					   if (duration and duration > 1 and start and (start + duration - GetTime() > 0)) or (data.desaturate) then
						   frame.texture:SetDesaturated(true)
						   -- Add gray overlay for sample icon
						   if data.sample then
							   if not frame.grayOverlay then
								   frame.grayOverlay = frame:CreateTexture(nil, "OVERLAY")
								   frame.grayOverlay:SetAllPoints(frame)
								   frame.grayOverlay:SetColorTexture(0.5, 0.5, 0.5, 0.5) -- semi-transparent gray
							   end
							   frame.grayOverlay:Show()
						   else
							   if frame.grayOverlay then frame.grayOverlay:Hide() end
						   end
					   else
						   frame.texture:SetDesaturated(false)
						   if frame.grayOverlay then frame.grayOverlay:Hide() end
					   end
				   end
				   if data.type == "healing" then
					   local iconPath = data.iconID or GetItemIcon(data.itemID) or "Interface\\Icons\\inv_misc_questionmark"
					   frame.texture:SetTexture(iconPath)
					   local start, duration, enable = GetSafeItemCooldown(data.itemID)
					   local ok = pcall(frame.cooldown.SetCooldown, frame.cooldown, start or 0, duration or 0)
					   if not ok then frame.cooldown:Clear() end
					   frame.count:SetText(data.count and data.count > 1 and data.count or "")
					   -- Desaturate if on cooldown or if not in bags
					   if (duration and duration > 1 and start and (start + duration - GetTime() > 0)) or (data.desaturate) then
						   frame.texture:SetDesaturated(true)
						   -- Add gray overlay for sample icon
						   if data.sample then
							   if not frame.grayOverlay then
								   frame.grayOverlay = frame:CreateTexture(nil, "OVERLAY")
								   frame.grayOverlay:SetAllPoints(frame)
								   frame.grayOverlay:SetColorTexture(0.5, 0.5, 0.5, 0.5) -- semi-transparent gray
							   end
							   frame.grayOverlay:Show()
						   else
							   if frame.grayOverlay then frame.grayOverlay:Hide() end
						   end
					   else
						   frame.texture:SetDesaturated(false)
						   if frame.grayOverlay then frame.grayOverlay:Hide() end
					   end
				   elseif data.type == "healthstone" then
					   local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(data.itemID) or GetItemIcon(data.itemID)
					   frame.texture:SetTexture(icon)
					   frame.cooldown:Clear() -- Remove cooldown overlay so it never blinks
					   frame.count:SetText(data.count and data.count > 1 and data.count or "")
					   frame.texture:SetDesaturated(data.desaturate and true or false)
				   elseif data.type == "trinket" then
					   local itemID = GetInventoryItemID("player", data.slot)
					   local iconPath = itemID and GetInventoryItemTexture("player", data.slot) or "Interface\\Icons\\inv_misc_questionmark"
					   frame.texture:SetTexture(iconPath)
					   local start, duration, enable = GetInventoryItemCooldown("player", data.slot)
					   if enable and duration > 0 then
						   local ok = pcall(frame.cooldown.SetCooldown, frame.cooldown, start, duration)
						   if not ok then frame.cooldown:Clear() end
						   -- Desaturate if on cooldown
						   if duration > 1 and start and (start + duration - GetTime() > 0) then
							   frame.texture:SetDesaturated(true)
						   else
							   frame.texture:SetDesaturated(false)
						   end
					   else
						   frame.cooldown:Clear()
						   frame.texture:SetDesaturated(false)
					   end
					   frame.count:SetText("")
				end
				PositionIcon(frame, i, iconsInRow, row, col, rowOffsetX, anchorFrame)
				usedFrames = math.max(usedFrames, i)
			end
		end
		   -- Layout group 2 (anchorFrame2, yellow box)
		local numRows2 = math.ceil(#group2 / ICONS_PER_ROW_2)
		for row = 0, numRows2 - 1 do
			local startIdx = row * ICONS_PER_ROW_2 + 1
			local endIdx = math.min((row + 1) * ICONS_PER_ROW_2, #group2)
			local iconsInRow = endIdx - startIdx + 1
			local rowWidth = iconsInRow * ICON_SIZE_2 + (iconsInRow - 1) * ICON_SPACING_2
			local fullWidth = ICONS_PER_ROW_2 * ICON_SIZE_2 + (ICONS_PER_ROW_2 - 1) * ICON_SPACING_2
			local rowOffsetX = math.floor((fullWidth - rowWidth) / 2)
			   for col = 0, iconsInRow - 1 do
				   local i = startIdx + col
				   local data = group2[i]
				   local frame = CreateOrGetIconFrame(#group1 + i)
				   frame:SetSize(ICON_SIZE_2, ICON_SIZE_2)
				   frame._trinketData = data
				   frame.texture:SetDesaturated(false)
				   if frame.grayOverlay then frame.grayOverlay:Hide() end
				   if frame.cooldown then
					   if frame.cooldown.SetDrawSwipe then frame.cooldown:SetDrawSwipe(true) end
					   if frame.cooldown.SetSwipeColor then frame.cooldown:SetSwipeColor(0, 0, 0, 0.8) end
				   end
				   -- Set icon visuals (same as before)
				   if data.type == "racial" then
					   if frame.cooldown then
						   if frame.cooldown.SetDrawSwipe then frame.cooldown:SetDrawSwipe(false) end
						   if frame.cooldown.SetSwipeColor then frame.cooldown:SetSwipeColor(0, 0, 0, 0) end
					   end
					   local icon = C_Spell and C_Spell.GetSpellInfo and (C_Spell.GetSpellInfo(data.spellID) and C_Spell.GetSpellInfo(data.spellID).iconID) or select(3, GetSpellInfo(data.spellID))
					   frame.texture:SetTexture(icon)
					   local chargesInfo = SafeSetSpellCooldown(frame.cooldown, data.spellID)
					   if chargesInfo then
						   frame.count:SetText(chargesInfo.currentCharges > 1 and chargesInfo.currentCharges or "")
					   else
						   frame.count:SetText("")
					   end
				   elseif data.type == "power" or data.type == "healing" then
					   local icon = data.iconID or ((C_Item and C_Item.GetItemIconByID and data.itemID and C_Item.GetItemIconByID(data.itemID)) or GetItemIcon(data.itemID))
					   frame.texture:SetTexture(icon)
					   local start, duration, enable = GetSafeItemCooldown(data.itemID)
					   local ok = pcall(frame.cooldown.SetCooldown, frame.cooldown, start or 0, duration or 0)
					   if not ok then frame.cooldown:Clear() end
					   frame.count:SetText(data.count and data.count > 1 and data.count or "")
					   if (duration and duration > 1 and start and (start + duration - GetTime() > 0)) or (data.desaturate) then
						   frame.texture:SetDesaturated(true)
					   else
						   frame.texture:SetDesaturated(false)
					   end
				   elseif data.type == "healthstone" then
					   local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(data.itemID) or GetItemIcon(data.itemID)
					   frame.texture:SetTexture(icon)
					   frame.cooldown:Clear() -- Remove cooldown overlay so it never blinks
					   frame.count:SetText(data.count and data.count > 1 and data.count or "")
					   frame.texture:SetDesaturated(data.desaturate and true or false)
				   elseif data.type == "trinket" then
					   local itemID = GetInventoryItemID("player", data.slot)
					   local iconPath = itemID and GetInventoryItemTexture("player", data.slot) or "Interface\\Icons\\inv_misc_questionmark"
					   frame.texture:SetTexture(iconPath)
					   local start, duration, enable = GetInventoryItemCooldown("player", data.slot)
					   if enable and duration > 0 then
						   local ok = pcall(frame.cooldown.SetCooldown, frame.cooldown, start, duration)
						   if not ok then frame.cooldown:Clear() end
						   -- Desaturate if on cooldown
						   if duration > 1 and start and (start + duration - GetTime() > 0) then
							   frame.texture:SetDesaturated(true)
						   else
							   frame.texture:SetDesaturated(false)
						   end
					   else
						   frame.cooldown:Clear()
						   frame.texture:SetDesaturated(false)
					   end
					   frame.count:SetText("")
				   end
				   -- Essential mode: register with MyEssentialBuffTracker instead of standalone positioning
				   if Group2ClusterMode and MyEssentialBuffTracker and MyEssentialBuffTracker.RegisterExternalIcon then
				       frame.Icon = frame.Icon or frame.texture
				       frame.Cooldown = frame.Cooldown or frame.cooldown
				       frame:Show()
				       MyEssentialBuffTracker:RegisterExternalIcon(frame)
				   else
				       -- Always right-to-left: icons are placed from the right edge, so col=0 is rightmost
				       local rtl_col = iconsInRow - 1 - col
				       local x = ICON_START_X + rowOffsetX + rtl_col * (ICON_SIZE_2 + ICON_SPACING_2)
				       local y = ICON_START_Y - row * (ICON_SIZE_2 + ICON_ROW_SPACING)
				       frame:ClearAllPoints()
				       frame:SetPoint("TOPLEFT", anchorFrame2, "TOPLEFT", x, y)
				       frame:Show()
				   end
				   usedFrames = math.max(usedFrames, #group1 + i)
			   end
		   end
	else
		-- Single group (default/original)
		local numRows = math.ceil(totalIcons / ICONS_PER_ROW_1)
		for row = 0, numRows - 1 do
			local startIdx = row * ICONS_PER_ROW_1 + 1
			local endIdx = math.min((row + 1) * ICONS_PER_ROW_1, totalIcons)
			local iconsInRow = endIdx - startIdx + 1
			local rowOffsetX = 0
			if row > 0 and iconsInRow < ICONS_PER_ROW_1 then
				local rowWidth = iconsInRow * ICON_SIZE + (iconsInRow - 1) * ICON_SPACING
				local fullWidth = ICONS_PER_ROW_1 * ICON_SIZE + (ICONS_PER_ROW_1 - 1) * ICON_SPACING
				rowOffsetX = math.floor((fullWidth - rowWidth) / 2)
			end
			for col = 0, iconsInRow - 1 do
				local i = startIdx + col
				local data = iconDataList[i]
				local frame = CreateOrGetIconFrame(i)
				frame:SetSize(ICON_SIZE_1, ICON_SIZE)
				frame._trinketData = data
				frame.texture:SetDesaturated(false)
				if frame.grayOverlay then frame.grayOverlay:Hide() end
				if frame.cooldown then
					if frame.cooldown.SetDrawSwipe then frame.cooldown:SetDrawSwipe(true) end
					if frame.cooldown.SetSwipeColor then frame.cooldown:SetSwipeColor(0, 0, 0, 0.8) end
				end
				if data.type == "racial" then
					if frame.cooldown then
						if frame.cooldown.SetDrawSwipe then frame.cooldown:SetDrawSwipe(false) end
						if frame.cooldown.SetSwipeColor then frame.cooldown:SetSwipeColor(0, 0, 0, 0) end
					end
					local icon = C_Spell and C_Spell.GetSpellInfo and (C_Spell.GetSpellInfo(data.spellID) and C_Spell.GetSpellInfo(data.spellID).iconID) or select(3, GetSpellInfo(data.spellID))
					frame.texture:SetTexture(icon)
					local chargesInfo = SafeSetSpellCooldown(frame.cooldown, data.spellID)
					if chargesInfo then
						frame.count:SetText(chargesInfo.currentCharges > 1 and chargesInfo.currentCharges or "")
					else
						frame.count:SetText("")
					end
				elseif data.type == "power" or data.type == "healing" then
					local icon = data.iconID or ((C_Item and C_Item.GetItemIconByID and data.itemID and C_Item.GetItemIconByID(data.itemID)) or GetItemIcon(data.itemID))
					frame.texture:SetTexture(icon)
					local start, duration, enable = GetSafeItemCooldown(data.itemID)
					local ok = pcall(frame.cooldown.SetCooldown, frame.cooldown, start or 0, duration or 0)
					if not ok then frame.cooldown:Clear() end
					frame.count:SetText(data.count and data.count > 1 and data.count or "")
					if (duration and duration > 1 and start and (start + duration - GetTime() > 0)) or (data.desaturate) then
						frame.texture:SetDesaturated(true)
					else
						frame.texture:SetDesaturated(false)
					end
				   elseif data.type == "healthstone" then
					   local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(data.itemID) or GetItemIcon(data.itemID)
					   frame.texture:SetTexture(icon)
					   frame.cooldown:Clear() -- Remove cooldown overlay so it never blinks
					   frame.count:SetText(data.count and data.count > 1 and data.count or "")
				elseif data.type == "trinket" then
					local itemID = GetInventoryItemID("player", data.slot)
					local iconPath = itemID and GetInventoryItemTexture("player", data.slot) or "Interface\\Icons\\inv_misc_questionmark"
					frame.texture:SetTexture(iconPath)
					local start, duration, enable = GetInventoryItemCooldown("player", data.slot)
					if enable and duration > 0 then
						local ok = pcall(frame.cooldown.SetCooldown, frame.cooldown, start, duration)
						if not ok then frame.cooldown:Clear() end
					else
						frame.cooldown:Clear()
					end
					frame.count:SetText("")
				end
				PositionIcon(frame, i, iconsInRow, row, col, rowOffsetX, anchorFrame)
				usedFrames = usedFrames + 1
			end
		end
	end
	-- Unregister unused frames from cluster if they were previously registered
	for i = usedFrames + 1, #iconFrames do
		if MyEssentialBuffTracker and MyEssentialBuffTracker.UnregisterExternalIcon then
			MyEssentialBuffTracker:UnregisterExternalIcon(iconFrames[i])
		end
		iconFrames[i]._trinketData = nil
		iconFrames[i]:Hide()
	end
end

-- Lightweight cooldown-only update: no data rebuild, no repositioning
local function UpdateCooldownsOnly()
	for i = 1, #iconFrames do
		local frame = iconFrames[i]
		local data = frame._trinketData
		if not data or not frame:IsShown() then break end
		   if data.type == "racial" then
			   SafeSetSpellCooldown(frame.cooldown, data.spellID)
			   local chargesInfo = C_Spell and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(data.spellID)
			   if chargesInfo then
				   frame.count:SetText(chargesInfo.currentCharges > 1 and chargesInfo.currentCharges or "")
			   end
		   elseif data.type == "power" or data.type == "healing" then
			   if not data.sample then
				   local start, duration = GetSafeItemCooldown(data.itemID)
				   local ok = pcall(frame.cooldown.SetCooldown, frame.cooldown, start, duration)
				   if not ok then frame.cooldown:Clear() end
			   end
		   elseif data.type == "trinket" then
			   local start, duration, enable = GetInventoryItemCooldown("player", data.slot)
			   if enable then
				   local ok = pcall(frame.cooldown.SetCooldown, frame.cooldown, start, duration)
				   if not ok then frame.cooldown:Clear() end
			   else
				   frame.cooldown:Clear()
			   end
		end
		-- healthstone: no cooldown to update
	end
end


-- Event-driven batching and dirty flag system
local trinketDirty = false
local trinketCDDirty = false
local trinketBatchScheduled = false
local trinketBatchInterval = 0.3

local function RunTrinketBatch()
	trinketBatchScheduled = false
	if trinketDirty then
		trinketDirty = false
		trinketCDDirty = false
		UpdateAllIcons()
	elseif trinketCDDirty then
		trinketCDDirty = false
		UpdateCooldownsOnly()
	end
end

local function ScheduleTrinketBatch()
	if not trinketBatchScheduled then
		trinketBatchScheduled = true
		C_Timer.After(trinketBatchInterval, RunTrinketBatch)
	end
end

local eventFrame = CreateFrame("Frame")
if TrackedItemsEnabled then
	-- Full rebuild events (rare)
	eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
	eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
	eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
	eventFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
	-- Cooldown-only events (frequent)
	eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	eventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")
	eventFrame:RegisterEvent("BAG_UPDATE_COOLDOWN")
	-- World event
	eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
end
eventFrame:SetScript("OnEvent", function(self, event, ...)
	if event == "PLAYER_ENTERING_WORLD" then
		trinketDirty = true
		ScheduleTrinketBatch()
		return
	end
	-- Cooldown-only events
	if event == "SPELL_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_CHARGES" or event == "BAG_UPDATE_COOLDOWN" then
		trinketCDDirty = true
		ScheduleTrinketBatch()
		return
	end
	-- Full rebuild events
	trinketDirty = true
	ScheduleTrinketBatch()
end)


-- Wait for PLAYER_LOGIN to initialize anchor and icons
local function InitializeTrinketIcons()
	LoadSettings()
	local pos = GetProfilePosition()
	CCM_SavedPosition.x = pos.x
	CCM_SavedPosition.y = pos.y
	anchorFrame:ClearAllPoints()
	anchorFrame:SetPoint("CENTER", UIParent, "CENTER", CCM_SavedPosition.x, CCM_SavedPosition.y)
	UpdateAllIcons()
	-- Listen for profile changes to reload position
	if CkraigProfileManager and CkraigProfileManager.RegisterCallback and not anchorFrame._profileCB then
		anchorFrame._profileCB = true
		CkraigProfileManager:RegisterCallback("OnProfileChanged", function()
			LoadSettings()
			local pos = GetProfilePosition()
			CCM_SavedPosition.x = pos.x
			CCM_SavedPosition.y = pos.y
			anchorFrame:ClearAllPoints()
			anchorFrame:SetPoint("CENTER", UIParent, "CENTER", CCM_SavedPosition.x, CCM_SavedPosition.y)
			UpdateAllIcons()
		end)
	end
end

-- Create options panel function (similar to other modules)
local function CreateOptionsPanel()
	local panel = CreateFrame("Frame", "CCM_ItemConfigPanel", UIParent)
	panel:SetSize(520, 700)

	-- Scroll frame so content doesn't clip
	local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	scrollFrame:SetPoint("TOPLEFT", 0, 0)
	scrollFrame:SetPoint("BOTTOMRIGHT", -26, 0)

	local content = CreateFrame("Frame", nil, scrollFrame)
	content:SetWidth(490)
	content:SetHeight(1) -- will be updated dynamically
	scrollFrame:SetScrollChild(content)

	-- Consistent vertical gap between sections
	local SECTION_GAP = -16
	local SLIDER_GAP = -30
	local BUTTON_GAP = -10

	-- Title
	local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Tracked Items Configuration")

	-- Description
	local desc = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	desc:SetWidth(460)
	desc:SetText("Configure which racial abilities, potions, and trinkets are tracked.")
	desc:SetJustifyH("LEFT")

	-- Enable / Disable buttons
	local enableBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	enableBtn:SetSize(120, 24)
	enableBtn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, BUTTON_GAP)
	enableBtn:SetText("Enable & Reload")
	enableBtn:SetScript("OnClick", function()
		TrackedItemsEnabled = true
		SaveSettings()
		C_UI.Reload()
	end)

	local disableBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	disableBtn:SetSize(120, 24)
	disableBtn:SetPoint("LEFT", enableBtn, "RIGHT", 8, 0)
	disableBtn:SetText("Disable & Reload")
	disableBtn:SetScript("OnClick", function()
		TrackedItemsEnabled = false
		SaveSettings()
		C_UI.Reload()
	end)

	local statusLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	statusLabel:SetPoint("LEFT", disableBtn, "RIGHT", 10, 0)
	if TrackedItemsEnabled then
		statusLabel:SetText("|cFF00FF00Enabled|r")
	else
		statusLabel:SetText("|cFFFF0000Disabled|r")
	end

	-- Passive trinket toggle
	local passiveTrinketCheck = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
	passiveTrinketCheck:SetPoint("TOPLEFT", enableBtn, "BOTTOMLEFT", 0, BUTTON_GAP)
	passiveTrinketCheck.Text:SetText("Show Passive Trinkets")
	passiveTrinketCheck:SetChecked(ShowPassiveTrinkets)
	passiveTrinketCheck:SetScript("OnClick", function(self)
		ShowPassiveTrinkets = self:GetChecked()
		SaveSettings()
		UpdateAllIcons()
	end)

	-- ===== Icon Group Assignment UI =====
	local function getRealIconForKey(key)
		if key == "racials" then
			local racials = FindPlayerRacials()
			if #racials > 0 then
				local spellID = racials[1]
				return (C_Spell and C_Spell.GetSpellInfo and (C_Spell.GetSpellInfo(spellID) and C_Spell.GetSpellInfo(spellID).iconID)) or select(3, GetSpellInfo(spellID))
			end
		elseif key == "power" then
			local potionID = select(1, FindFirstUsablePotion())
			if potionID then
				return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(potionID)) or GetItemIcon(potionID)
			end
		elseif key == "healing" then
			local healingPotionID = select(1, FindFirstUsableHealingPotion())
			if healingPotionID then
				return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(healingPotionID)) or GetItemIcon(healingPotionID)
			end
		elseif key == "healthstone" then
			local healthstoneID = select(1, FindHealthstone())
			if healthstoneID then
				return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(healthstoneID)) or GetItemIcon(healthstoneID)
			end
		elseif key == "trinket13" then
			local itemID = GetInventoryItemID("player", 13)
			if itemID then
				return GetInventoryItemTexture("player", 13)
			end
		elseif key == "trinket14" then
			local itemID = GetInventoryItemID("player", 14)
			if itemID then
				return GetInventoryItemTexture("player", 14)
			end
		end
		return "Interface\\Icons\\inv_misc_questionmark"
	end

	local iconTypeLabels = {
		racials = "Racials",
		power = "Power Potion",
		healing = "Healing Potion",
		healthstone = "Healthstone",
		trinket13 = "Trinket 1",
		trinket14 = "Trinket 2",
	}

	-- Container for the two-tray assignment system
	local assignLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	assignLabel:SetPoint("TOPLEFT", passiveTrinketCheck, "BOTTOMLEFT", 0, SECTION_GAP)
	assignLabel:SetText("|cFFFFD100Icon Assignment|r  (click icon to swap groups, drag to reorder)")
	assignLabel:SetTextColor(1, 1, 1, 1)

	-- Group 1 tray (blue border)
	local tray1Label = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	tray1Label:SetPoint("TOPLEFT", assignLabel, "BOTTOMLEFT", 0, -8)
	tray1Label:SetText("|cFF4488FFGroup 1 (Blue Box)|r")

	local tray1Frame = CreateFrame("Frame", nil, content, "BackdropTemplate")
	tray1Frame:SetPoint("TOPLEFT", tray1Label, "BOTTOMLEFT", 0, -4)
	tray1Frame:SetSize(460, 52)
	tray1Frame:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = {left = 2, right = 2, top = 2, bottom = 2}})
	tray1Frame:SetBackdropColor(0.1, 0.2, 0.4, 0.6)
	tray1Frame:SetBackdropBorderColor(0.3, 0.5, 1.0, 0.8)

	-- Group 2 tray (yellow border)
	local tray2Label = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	tray2Label:SetPoint("TOPLEFT", tray1Frame, "BOTTOMLEFT", 0, -8)
	tray2Label:SetText("|cFFFFCC00Group 2 (Yellow Box)|r")

	local tray2Frame = CreateFrame("Frame", nil, content, "BackdropTemplate")
	tray2Frame:SetPoint("TOPLEFT", tray2Label, "BOTTOMLEFT", 0, -4)
	tray2Frame:SetSize(460, 52)
	tray2Frame:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = {left = 2, right = 2, top = 2, bottom = 2}})
	tray2Frame:SetBackdropColor(0.3, 0.25, 0.05, 0.6)
	tray2Frame:SetBackdropBorderColor(1.0, 0.8, 0.0, 0.8)

	local trayButtons = {} -- pool of all icon buttons
	local orderFrame = tray2Frame -- used as anchor for sections below

	local function GetGroupKeysForTray(groupNum)
		local iconOrder = GetIconOrder()
		local result = {}
		for _, key in ipairs(iconOrder) do
			if (IconGroupAssignments[key] or 1) == groupNum then
				table.insert(result, key)
			end
		end
		return result
	end

	local RefreshTrays -- forward declare

	local function CreateTrayButton(parent, key, groupNum)
		local btn = CreateFrame("Button", nil, parent)
		btn:SetSize(40, 40)
		btn.icon = btn:CreateTexture(nil, "ARTWORK")
		btn.icon:SetAllPoints()
		btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- slight trim
		btn.border = btn:CreateTexture(nil, "OVERLAY")
		btn.border:SetPoint("TOPLEFT", -2, 2)
		btn.border:SetPoint("BOTTOMRIGHT", 2, -2)
		btn.border:SetColorTexture(groupNum == 1 and 0.3 or 1.0, groupNum == 1 and 0.5 or 0.8, groupNum == 1 and 1.0 or 0.0, 0.6)
		btn.border:SetDrawLayer("OVERLAY", -1)
		btn.iconFill = btn:CreateTexture(nil, "BACKGROUND")
		btn.iconFill:SetAllPoints()
		btn.iconFill:SetColorTexture(0, 0, 0, 0.4)
		btn.key = key
		btn.groupNum = groupNum

		btn:SetMovable(true)
		btn:RegisterForDrag("LeftButton")
		btn:RegisterForClicks("RightButtonUp")

		-- Right-click → swap to the other group (only in split mode)
		btn:SetScript("OnClick", function(self, button)
			if button == "RightButton" and GroupMode == "split" then
				local newGroup = (self.groupNum == 1) and 2 or 1
				IconGroupAssignments[self.key] = newGroup
				SetIconGroupAssignments(IconGroupAssignments)
				UpdateAllIcons()
				RefreshTrays()
			end
		end)

		-- Drag to reorder within group
		btn:SetScript("OnDragStart", function(self)
			self._origParent = self:GetParent()
			self:SetFrameStrata("TOOLTIP")
			self:StartMoving()
		end)
		btn:SetScript("OnDragStop", function(self)
			self:StopMovingOrSizing()
			self:SetFrameStrata("MEDIUM")

			-- Detect if dropped over the other group's tray (cross-group drag)
			if GroupMode == "split" then
				local cx, cy = self:GetCenter()
				local otherGroup = (self.groupNum == 1) and 2 or 1
				local otherTray = (otherGroup == 1) and tray1Frame or tray2Frame
				if otherTray and otherTray:IsShown() then
					local left = otherTray:GetLeft()
					local right = otherTray:GetRight()
					local bottom = otherTray:GetBottom()
					local top = otherTray:GetTop()
					if left and right and bottom and top and cx >= left and cx <= right and cy >= bottom and cy <= top then
						-- Reassign to the other group
						IconGroupAssignments[self.key] = otherGroup
						SetIconGroupAssignments(IconGroupAssignments)
						self.groupNum = otherGroup
					end
				end
			end

			-- Figure out new position by comparing X with siblings
			local myX = self:GetCenter()
			local myGroup = self.groupNum
			local keys = GetGroupKeysForTray(myGroup)
			local bestIdx = #keys
			for idx, otherKey in ipairs(keys) do
				if otherKey ~= self.key then
					for _, ob in ipairs(trayButtons) do
						if ob.key == otherKey and ob.groupNum == myGroup and ob:IsShown() then
							local ox = ob:GetCenter()
							if myX < ox then
								bestIdx = idx
								break
							end
						end
					end
				end
				if bestIdx < #keys then break end
			end
			-- Reorder in the master iconOrder: remove self.key, reinsert at right spot
			local iconOrder = GetIconOrder()
			-- Remove old position
			for i = #iconOrder, 1, -1 do
				if iconOrder[i] == self.key then
					table.remove(iconOrder, i)
					break
				end
			end
			-- Find the key at bestIdx in the group and insert before it
			local targetKey = keys[bestIdx]
			local insertPos = #iconOrder + 1
			if targetKey and targetKey ~= self.key then
				for i, k in ipairs(iconOrder) do
					if k == targetKey then
						insertPos = i
						break
					end
				end
			end
			table.insert(iconOrder, insertPos, self.key)
			SetIconOrder(iconOrder)
			UpdateAllIcons()
			RefreshTrays()
		end)

		btn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			local tip = iconTypeLabels[self.key] or self.key
			if GroupMode == "split" then
				tip = tip .. "\n|cFF888888Right-click to swap group|r"
			end
			tip = tip .. "\n|cFF888888Drag to reorder|r"
			GameTooltip:SetText(tip)
			GameTooltip:Show()
		end)
		btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return btn
	end

	RefreshTrays = function()
		-- Hide all existing buttons
		for _, btn in ipairs(trayButtons) do btn:Hide() end
		local btnIdx = 0

		if GroupMode ~= "split" then
			-- Single mode: show all icons in tray1 as a flat reorder
			local iconOrder = GetIconOrder()
			for pos, key in ipairs(iconOrder) do
				btnIdx = btnIdx + 1
				local btn = trayButtons[btnIdx]
				if not btn then
					btn = CreateTrayButton(tray1Frame, key, 1)
					trayButtons[btnIdx] = btn
				end
				btn.key = key
				btn.groupNum = 1
				btn:SetParent(tray1Frame)
				btn.icon:SetTexture(getRealIconForKey(key))
				btn.border:SetColorTexture(0.3, 0.5, 1.0, 0.6)
				btn:ClearAllPoints()
				btn:SetPoint("LEFT", tray1Frame, "LEFT", 6 + (pos - 1) * 50, 0)
				btn:Show()
			end
		else
			-- Split mode: show icons in their assigned trays
			for _, groupNum in ipairs({1, 2}) do
				local parentTray = groupNum == 1 and tray1Frame or tray2Frame
				local keys = GetGroupKeysForTray(groupNum)
				for pos, key in ipairs(keys) do
					btnIdx = btnIdx + 1
					local btn = trayButtons[btnIdx]
					if not btn then
						btn = CreateTrayButton(parentTray, key, groupNum)
						trayButtons[btnIdx] = btn
					end
					btn.key = key
					btn.groupNum = groupNum
					btn:SetParent(parentTray)
					btn.icon:SetTexture(getRealIconForKey(key))
					btn.border:SetColorTexture(groupNum == 1 and 0.3 or 1.0, groupNum == 1 and 0.5 or 0.8, groupNum == 1 and 1.0 or 0.0, 0.6)
					btn:ClearAllPoints()
					btn:SetPoint("LEFT", parentTray, "LEFT", 6 + (pos - 1) * 50, 0)
					btn:Show()
				end
			end
		end
	end
	RefreshTrays()

	-- Anchor container that's always visible (tray2 may be hidden in single mode)
	local trayBottomAnchor = CreateFrame("Frame", nil, content)
	trayBottomAnchor:SetSize(1, 1)
	trayBottomAnchor:SetPoint("TOPLEFT", tray2Frame, "BOTTOMLEFT", 0, 0)

	-- ===== Buttons row: Unlock + Reset =====
	local anchorLockBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	anchorLockBtn:SetSize(160, 24)
	anchorLockBtn:SetPoint("TOPLEFT", trayBottomAnchor, "TOPLEFT", 0, BUTTON_GAP)
	anchorLockBtn:SetText("Unlock Icon Positions")
	anchorLockBtn.locked = true
	anchorLockBtn:SetScript("OnClick", function(self)
		if self.locked then
			anchorFrame:SetFrameStrata("TOOLTIP")
			anchorFrame:EnableMouse(true)
			anchorFrame:Show()
			anchorFrame:SetAlpha(1)
			anchorFrame.moving = true
			anchorFrame2:SetFrameStrata("TOOLTIP")
			anchorFrame2:EnableMouse(true)
			anchorFrame2:Show()
			anchorFrame2:SetAlpha(1)
			anchorFrame2.moving = true
			self:SetText("Lock Icon Positions")
			self.locked = false
			print("[CCM] Left-drag to move. Right-click a box to enable Arrow Key mode. Shift+Arrow = 10px.")
		else
			anchorFrame:SetFrameStrata("MEDIUM")
			anchorFrame:EnableMouse(false)
			anchorFrame:EnableKeyboard(false)
			anchorFrame._arrowKeyActive = false
			anchorFrame._anchorLabel:SetText("Group 1")
			anchorFrame:Hide()
			anchorFrame:SetAlpha(1)
			anchorFrame.moving = false
			anchorFrame2:SetFrameStrata("MEDIUM")
			anchorFrame2:EnableMouse(false)
			anchorFrame2:EnableKeyboard(false)
			anchorFrame2._arrowKeyActive = false
			anchorFrame2._anchorLabel:SetText("Group 2")
			anchorFrame2:Hide()
			anchorFrame2:SetAlpha(1)
			anchorFrame2.moving = false
			self:SetText("Unlock Icon Positions")
			self.locked = true
			print("[CCM] Both groups locked.")
		end
	end)

	local resetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	resetBtn:SetSize(130, 24)
	resetBtn:SetPoint("LEFT", anchorLockBtn, "RIGHT", 8, 0)
	resetBtn:SetText("Reset Positions")
	resetBtn:SetScript("OnClick", function()
		local default1 = {x = 0, y = 0}
		local default2 = {x = 0, y = -80}
		anchorFrame:ClearAllPoints()
		anchorFrame:SetPoint("CENTER", UIParent, "CENTER", default1.x, default1.y)
		CCM_SavedPosition.x = default1.x
		CCM_SavedPosition.y = default1.y
		SetProfilePosition(default1.x, default1.y)
		anchorFrame2:ClearAllPoints()
		anchorFrame2:SetPoint("CENTER", UIParent, "CENTER", default2.x, default2.y)
		CCM_SavedPosition2.x = default2.x
		CCM_SavedPosition2.y = default2.y
		if CkraigProfileManager and CkraigProfileManager.SetProfileData then
			local data = CkraigProfileManager:GetProfileData("trinketIcons2") or {}
			data.x = default2.x
			data.y = default2.y
			CkraigProfileManager:SetProfileData("trinketIcons2", data)
		end
		print("[CCM] Icon positions reset to default.")
	end)

	-- ===== Group Mode Dropdown =====
	local UpdateClusterControlsVisibility  -- forward declaration
	local groupModeLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	groupModeLabel:SetPoint("TOPLEFT", anchorLockBtn, "BOTTOMLEFT", 0, SECTION_GAP)
	groupModeLabel:SetText("Group Mode:")
	groupModeLabel:SetTextColor(1, 1, 1, 1)

	local groupModeDropdown = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate")
	groupModeDropdown:SetPoint("TOPLEFT", groupModeLabel, "BOTTOMLEFT", 0, -4)
	groupModeDropdown:SetWidth(200)
	if LoadSettings then LoadSettings() end

	local groupModeOptions = {
		{ text = "1 Group (All Icons)", value = "single" },
		{ text = "2 Groups (Even Split)", value = "split" },
	}

	groupModeDropdown:SetupMenu(function(dd, rootDescription)
		for _, opt in ipairs(groupModeOptions) do
			rootDescription:CreateRadio(
				opt.text,
				function() return GroupMode == opt.value end,
				function()
					GroupMode = opt.value
					SaveSettings()
					if opt.value == "single" and MyEssentialBuffTracker and MyEssentialBuffTracker.UnregisterExternalIcon then
						for _, frame in ipairs(iconFrames) do
							MyEssentialBuffTracker:UnregisterExternalIcon(frame)
						end
					end
					UpdateAllIcons()
					UpdateClusterControlsVisibility()
				end,
				opt.value
			)
		end
	end)

	-- Group 2 → Essential Cooldowns checkbox
	local g2ClusterCheck = CreateFrame("CheckButton", nil, content, "InterfaceOptionsCheckButtonTemplate")
	g2ClusterCheck:SetPoint("TOPLEFT", groupModeDropdown, "BOTTOMLEFT", 0, -4)
	g2ClusterCheck.Text:SetText("Show Group 2 in Essential Cooldowns")
	g2ClusterCheck:SetChecked(Group2ClusterMode)

	UpdateClusterControlsVisibility = function()
		g2ClusterCheck:SetShown(GroupMode == "split")
	end

	g2ClusterCheck:SetScript("OnClick", function(self)
		Group2ClusterMode = self:GetChecked()
		SaveSettings()
		UpdateClusterControlsVisibility()
		if not Group2ClusterMode and MyEssentialBuffTracker and MyEssentialBuffTracker.UnregisterExternalIcon then
			for _, frame in ipairs(iconFrames) do
				MyEssentialBuffTracker:UnregisterExternalIcon(frame)
			end
		end
		UpdateAllIcons()
	end)

	UpdateClusterControlsVisibility()

	-- Hook group mode dropdown text changes to update all visibility
	local groupModeText = groupModeDropdown.Text or _G[groupModeDropdown:GetName() and (groupModeDropdown:GetName() .. "Text")]
	if groupModeText and groupModeText.SetText then
		hooksecurefunc(groupModeText, "SetText", function()
			C_Timer.After(0, function()
				if UpdateClusterControlsVisibility then UpdateClusterControlsVisibility() end
				if UpdateIconSizeSliderVisibility then UpdateIconSizeSliderVisibility() end
				if UpdateIconSpacingSliderVisibility then UpdateIconSpacingSliderVisibility() end
				if UpdateTrayVisibility then UpdateTrayVisibility() end
			end)
		end)
	end

	-- ===== Sliders =====
	local function CreateSlider(parent, label, minVal, maxVal, step, value, onValueChanged)
		local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
		slider:SetMinMaxValues(minVal, maxVal)
		slider:SetValueStep(step)
		slider:SetValue(value)
		slider:SetObeyStepOnDrag(true)
		slider:SetWidth(200)
		slider:SetHeight(16)
		slider.Text = slider:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		slider.Text:SetPoint("TOP", slider, "BOTTOM", 0, -2)
		slider.Text:SetText(label .. ": " .. value)

		local input = CreateFrame("EditBox", nil, slider, "InputBoxTemplate")
		input:SetSize(40, 18)
		input:SetPoint("LEFT", slider, "RIGHT", 10, 0)
		input:SetAutoFocus(false)
		input:SetTextColor(1, 1, 1, 1)
		input:SetMaxLetters(6)

		local displayVal = string.format("%.0f", value)
		input:SetText(displayVal)

		local function UpdateValue(v)
			v = tonumber(v) or 0
			local displayVal = string.format("%.0f", v)
			slider:SetValue(v)
			slider.Text:SetText(label .. ": " .. displayVal)
			input:SetText(displayVal)
			onValueChanged(v)
		end

		slider:SetScript("OnValueChanged", function(self, v)
			UpdateValue(v)
		end)

		input:SetScript("OnEnterPressed", function(self)
			local val = tonumber(self:GetText())
			if val and val >= minVal and val <= maxVal then
				UpdateValue(val)
			else
				self:SetText(string.format("%.0f", slider:GetValue()))
			end
			self:ClearFocus()
		end)
		input:SetScript("OnEscapePressed", function(self)
			self:SetText(string.format("%.0f", slider:GetValue()))
			self:ClearFocus()
		end)
		input:SetScript("OnEditFocusLost", function(self)
			self:SetText(string.format("%.0f", slider:GetValue()))
		end)

		slider.input = input
		return slider
	end

	-- Use g2ClusterCheck as the anchor point for sliders section
	local prevAnchor = g2ClusterCheck

	-- ---- Icon Size ----
	local sizeSectionLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	sizeSectionLabel:SetPoint("TOPLEFT", prevAnchor, "BOTTOMLEFT", 0, SECTION_GAP)
	sizeSectionLabel:SetText("|cFFFFD100Icon Size|r")

	local iconSizeSlider = CreateSlider(content, "Icon Size (all)", 20, 80, 1, ICON_SIZE, function(v)
		ICON_SIZE = v
		ICON_SIZE_1 = v
		ICON_SIZE_2 = v
		SaveSettings()
		UpdateAllIcons()
	end)
	iconSizeSlider:SetPoint("TOPLEFT", sizeSectionLabel, "BOTTOMLEFT", 0, -8)

	local iconSizeSlider1 = CreateSlider(content, "Group 1 Icon Size", 20, 80, 1, ICON_SIZE_1, function(v)
		ICON_SIZE_1 = v
		SaveSettings()
		UpdateAllIcons()
	end)
	iconSizeSlider1:SetPoint("TOPLEFT", sizeSectionLabel, "BOTTOMLEFT", 0, -8)

	local iconSizeSlider2 = CreateSlider(content, "Group 2 Icon Size", 20, 80, 1, ICON_SIZE_2, function(v)
		ICON_SIZE_2 = v
		SaveSettings()
		UpdateAllIcons()
	end)
	iconSizeSlider2:SetPoint("TOPLEFT", iconSizeSlider1, "BOTTOMLEFT", 0, SLIDER_GAP)

	local function UpdateIconSizeSliderVisibility()
		if GroupMode == "split" then
			iconSizeSlider:Hide()
			iconSizeSlider1:Show()
			iconSizeSlider2:Show()
		else
			iconSizeSlider:Show()
			iconSizeSlider1:Hide()
			iconSizeSlider2:Hide()
		end
	end
	UpdateIconSizeSliderVisibility()

	-- ---- Spacing ----
	local spacingSectionLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	spacingSectionLabel:SetPoint("TOPLEFT", iconSizeSlider2, "BOTTOMLEFT", 0, SECTION_GAP)
	spacingSectionLabel:SetText("|cFFFFD100Spacing|r")

	local iconSpacingSlider1 = CreateSlider(content, "Icon Spacing (Group 1)", 0, 100, 1, ICON_SPACING_1, function(v)
		ICON_SPACING_1 = v
		SaveSettings()
		UpdateAllIcons()
	end)
	iconSpacingSlider1:SetPoint("TOPLEFT", spacingSectionLabel, "BOTTOMLEFT", 0, -8)

	local iconSpacingSlider2 = CreateSlider(content, "Icon Spacing (Group 2)", 0, 100, 1, ICON_SPACING_2, function(v)
		ICON_SPACING_2 = v
		SaveSettings()
		UpdateAllIcons()
	end)
	iconSpacingSlider2:SetPoint("TOPLEFT", iconSpacingSlider1, "BOTTOMLEFT", 0, SLIDER_GAP)

	local rowSpacingSlider = CreateSlider(content, "Row Spacing", 0, 50, 1, ICON_ROW_SPACING, function(v)
		ICON_ROW_SPACING = v
		SaveSettings()
		UpdateAllIcons()
	end)
	rowSpacingSlider:SetPoint("TOPLEFT", iconSpacingSlider2, "BOTTOMLEFT", 0, SLIDER_GAP)

	local function UpdateIconSpacingSliderVisibility()
		if GroupMode == "split" then
			iconSpacingSlider1:Show()
			iconSpacingSlider2:Show()
		else
			iconSpacingSlider1:Hide()
			iconSpacingSlider2:Hide()
		end
	end
	UpdateIconSpacingSliderVisibility()

	-- ---- Icons Per Row ----
	local perRowSectionLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	perRowSectionLabel:SetPoint("TOPLEFT", rowSpacingSlider, "BOTTOMLEFT", 0, SECTION_GAP)
	perRowSectionLabel:SetText("|cFFFFD100Icons Per Row|r")

	local iconsPerRowSlider1 = CreateSlider(content, "Icons Per Row (Group 1)", 1, 12, 1, ICONS_PER_ROW_1, function(v)
		ICONS_PER_ROW_1 = v
		SaveSettings()
		UpdateAllIcons()
	end)
	iconsPerRowSlider1:SetPoint("TOPLEFT", perRowSectionLabel, "BOTTOMLEFT", 0, -8)

	local iconsPerRowSlider2 = CreateSlider(content, "Icons Per Row (Group 2)", 1, 12, 1, ICONS_PER_ROW_2, function(v)
		ICONS_PER_ROW_2 = v
		SaveSettings()
		UpdateAllIcons()
	end)
	iconsPerRowSlider2:SetPoint("TOPLEFT", iconsPerRowSlider1, "BOTTOMLEFT", 0, SLIDER_GAP)

	-- ---- Position (X/Y) ----
	local posSectionLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	posSectionLabel:SetPoint("TOPLEFT", iconsPerRowSlider2, "BOTTOMLEFT", 0, SECTION_GAP)
	posSectionLabel:SetText("|cFFFFD100Position|r")

	local function SetAnchor1Pos(x, y)
		anchorFrame:ClearAllPoints()
		anchorFrame:SetPoint("CENTER", UIParent, "CENTER", x, y)
		CCM_SavedPosition.x = x
		CCM_SavedPosition.y = y
		SetProfilePosition(x, y)
	end

	local anchor1XSlider = CreateSlider(content, "Group 1 X", -1000, 1000, 1, CCM_SavedPosition and CCM_SavedPosition.x or 0, function(v)
		SetAnchor1Pos(v, CCM_SavedPosition.y or 0)
	end)
	anchor1XSlider:SetPoint("TOPLEFT", posSectionLabel, "BOTTOMLEFT", 0, -8)

	local anchor1YSlider = CreateSlider(content, "Group 1 Y", -1000, 1000, 1, CCM_SavedPosition and CCM_SavedPosition.y or 0, function(v)
		SetAnchor1Pos(CCM_SavedPosition.x or 0, v)
	end)
	anchor1YSlider:SetPoint("TOPLEFT", anchor1XSlider, "BOTTOMLEFT", 0, SLIDER_GAP)

	local function SetAnchor2Pos(x, y)
		anchorFrame2:ClearAllPoints()
		anchorFrame2:SetPoint("CENTER", UIParent, "CENTER", x, y)
		CCM_SavedPosition2.x = x
		CCM_SavedPosition2.y = y
		if CkraigProfileManager and CkraigProfileManager.SetProfileData then
			local data = CkraigProfileManager:GetProfileData("trinketIcons2") or {}
			data.x = x
			data.y = y
			CkraigProfileManager:SetProfileData("trinketIcons2", data)
		end
	end

	local anchor2XSlider = CreateSlider(content, "Group 2 X", -1000, 1000, 1, CCM_SavedPosition2 and CCM_SavedPosition2.x or 0, function(v)
		SetAnchor2Pos(v, CCM_SavedPosition2.y or -80)
	end)
	anchor2XSlider:SetPoint("TOPLEFT", anchor1YSlider, "BOTTOMLEFT", 0, SLIDER_GAP)

	local anchor2YSlider = CreateSlider(content, "Group 2 Y", -1000, 1000, 1, CCM_SavedPosition2 and CCM_SavedPosition2.y or -80, function(v)
		SetAnchor2Pos(CCM_SavedPosition2.x or 0, v)
	end)
	anchor2YSlider:SetPoint("TOPLEFT", anchor2XSlider, "BOTTOMLEFT", 0, SLIDER_GAP)

	-- ---- Tray visibility based on group mode ----
	local function UpdateTrayVisibility()
		local isSplit = (GroupMode == "split")
		tray2Label:SetShown(isSplit)
		tray2Frame:SetShown(isSplit)
		if isSplit then
			assignLabel:SetText("|cFFFFD100Icon Assignment|r  (right-click icon to swap groups, drag to reorder)")
			tray1Label:SetText("|cFF4488FFGroup 1 (Blue Box)|r")
			-- Reanchor lock button below tray2
			trayBottomAnchor:ClearAllPoints()
			trayBottomAnchor:SetPoint("TOPLEFT", tray2Frame, "BOTTOMLEFT", 0, 0)
		else
			assignLabel:SetText("|cFFFFD100Icon Order|r  (drag to reorder)")
			tray1Label:SetText("|cFF4488FFAll Icons|r")
			-- Reanchor lock button below tray1 (tray2 is hidden)
			trayBottomAnchor:ClearAllPoints()
			trayBottomAnchor:SetPoint("TOPLEFT", tray1Frame, "BOTTOMLEFT", 0, 0)
		end
		tray1Label:Show()
		tray1Frame:Show()
		RefreshTrays()
	end
	UpdateTrayVisibility()

	-- Set content height so scroll works
	content:SetHeight(1400)

	_G.CCM_ItemConfigPanel = panel
	if InterfaceOptions_AddCategory and not panel._addedToOptions then
		InterfaceOptions_AddCategory(panel)
		panel._addedToOptions = true
	end
end

-- Make it global for CkraigsOptions.lua
_G.TRINKETRACIALS = _G.TRINKETRACIALS or {}
_G.TRINKETRACIALS.CreateOptionsPanel = CreateOptionsPanel
-- Backward compatibility alias
_G.PROCS = _G.PROCS or _G.TRINKETRACIALS
_G.PROCS.CreateOptionsPanel = CreateOptionsPanel

local loginInitFrame = CreateFrame("Frame")
loginInitFrame:RegisterEvent("PLAYER_LOGIN")
loginInitFrame:SetScript("OnEvent", function()
	InitializeTrinketIcons()
	RegisterTrinketEditMode()
	SetupTrinketEditModeCallbacks()
end)

