-- CPU Optimization: All event handling consolidated into ScheduleTrinketBatch system below
-- Get profile data for tracked items
local function GetProfileData()
	if CkraigProfileManager and CkraigProfileManager.GetProfileData then
		local data = CkraigProfileManager:GetProfileData("trackedItems")
		if type(data) == "table" then
			return data
		end
		if CkraigProfileManager.SetProfileData then
			CkraigProfileManager:SetProfileData("trackedItems", {})
		end
	end
	return {}
end

-- Set profile data for tracked items
local function SetProfileData(key, value)
	local data = GetProfileData()
	if type(data) ~= "table" then
		data = {}
	end
	data[key] = value
	if CkraigProfileManager and CkraigProfileManager.SetProfileData then
		CkraigProfileManager:SetProfileData("trackedItems", data)
	end
end
-- Helper to check for safe, non-tainted numbers

-- Use centralized spell/item data from SpellLists.lua (data/ loads before trackers/)
local CCM = _G.CkraigCooldownManager

-- Racial spell IDs (centralized in CCM.SpellData.RACIALS)
local RACIALS = CCM.SpellData.RACIALS or {}

-- Power potion item IDs (centralized in CCM.SpellData.TRINKET_POWER_POTIONS)
local POWER_POTIONS = CCM.SpellData.TRINKET_POWER_POTIONS or {}

-- Mana potion item IDs (centralized in CCM.SpellData.MANA_POTIONS)
local MANA_POTIONS = CCM.SpellData.MANA_POTIONS or {}

-- Healing potion item IDs (centralized in CCM.SpellData.HEALING_POTIONS)
local HEALING_POTIONS = CCM.SpellData.HEALING_POTIONS or {}

-- Healer spec detection
local HEALER_SPECS = {
	-- Priest: Holy=2, Disc=1
	["PRIEST"] = { [1] = true, [2] = true },
	-- Paladin: Holy=1
	["PALADIN"] = { [1] = true },
	-- Shaman: Resto=3
	["SHAMAN"] = { [3] = true },
	-- Druid: Resto=4
	["DRUID"] = { [4] = true },
	-- Monk: Mistweaver=2
	["MONK"] = { [2] = true },
	-- Evoker: Preservation=2
	["EVOKER"] = { [2] = true },
}

local function IsPlayerHealer()
	local _, class = UnitClass("player")
	local specIndex = GetSpecialization and GetSpecialization() or 0
	return HEALER_SPECS[class] and HEALER_SPECS[class][specIndex] or false
end

local function FindFirstUsableManaPotion()
	for _, potionID in ipairs(MANA_POTIONS) do
		local count = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(potionID, false, true) or 0
		if count > 0 then
			return potionID, count
		end
	end
	return nil, 0
end

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

local CCM_C = CCM.Constants or {}
local ICON_SIZE = CCM_C.DEFAULT_ICON_SIZE or 40
local ICON_SIZE_1 = CCM_C.DEFAULT_ICON_SIZE or 40
local ICON_SIZE_2 = CCM_C.DEFAULT_ICON_SIZE or 40
local ICON_PADDING = 5
local ICON_SPACING = 0
local ICON_SPACING_1 = 0
local ICON_SPACING_2 = 0
local ICON_ROW_SPACING = CCM_C.DEFAULT_ICON_ROW_SPACING or 10
local ICONS_PER_ROW_1 = CCM_C.DEFAULT_ICONS_PER_ROW or 6
local ICONS_PER_ROW_2 = CCM_C.DEFAULT_ICONS_PER_ROW or 6
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
local Group2SortOrder = 0

local function NormalizePosition(x, y, defaultX, defaultY)
	local nx = tonumber(x)
	local ny = tonumber(y)
	if not nx then nx = defaultX or 0 end
	if not ny then ny = defaultY or 0 end
	return math.floor(nx), math.floor(ny)
end

local function SanitizeProfilePosition(profileKey, defaultX, defaultY)
	if not (CkraigProfileManager and CkraigProfileManager.GetProfileData) then
		local x, y = NormalizePosition(nil, nil, defaultX, defaultY)
		return { x = x, y = y }
	end

	local data = CkraigProfileManager:GetProfileData(profileKey)
	if type(data) ~= "table" then
		data = {}
	end
	local x, y = NormalizePosition(data.x, data.y, defaultX, defaultY)
	if data.x ~= x or data.y ~= y then
		data.x = x
		data.y = y
		if CkraigProfileManager.SetProfileData then
			CkraigProfileManager:SetProfileData(profileKey, data)
		end
	end
	return { x = x, y = y }
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
	Group2SortOrder = data.group2SortOrder or 0
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
	SetProfileData("group2SortOrder", Group2SortOrder)
end



-- Forward declarations so early functions capture locals, not globals
local CCM_SavedPosition
local CCM_SavedPosition2

local function EnsureSavedPositions()
	if type(CCM_SavedPosition) ~= "table" then
		CCM_SavedPosition = { x = 0, y = 0 }
	end
	if type(CCM_SavedPosition2) ~= "table" then
		CCM_SavedPosition2 = { x = 0, y = 0 }
	end
	CCM_SavedPosition.x = tonumber(CCM_SavedPosition.x) or 0
	CCM_SavedPosition.y = tonumber(CCM_SavedPosition.y) or 0
	CCM_SavedPosition2.x = tonumber(CCM_SavedPosition2.x) or 0
	CCM_SavedPosition2.y = tonumber(CCM_SavedPosition2.y) or 0
end

-- Profile-aware saved position for group 1
local function GetProfilePosition()
	return SanitizeProfilePosition("trinketIcons", 0, 0)
end

local function SetProfilePosition(x, y)
	EnsureSavedPositions()
	x, y = NormalizePosition(x, y, 0, 0)
	CCM_SavedPosition.x = x
	CCM_SavedPosition.y = y
	if CkraigProfileManager and CkraigProfileManager.SetProfileData then
		local data = CkraigProfileManager:GetProfileData("trinketIcons") or {}
		data.x = x
		data.y = y
		CkraigProfileManager:SetProfileData("trinketIcons", data)

		-- Keep active LibEditMode layout position in sync to prevent snap-back.
		local layoutName = LibEditMode and LibEditMode.GetActiveLayoutName and LibEditMode:GetActiveLayoutName()
		if layoutName then
			local tracked = CkraigProfileManager:GetProfileData("trackedItems") or {}
			tracked.layoutPositions = tracked.layoutPositions or {}
			tracked.layoutPositions.group1 = tracked.layoutPositions.group1 or {}
			tracked.layoutPositions.group1[layoutName] = { x = x, y = y }
			CkraigProfileManager:SetProfileData("trackedItems", tracked)
		end
	end
end


CCM_SavedPosition = {x = 0, y = 0} -- runtime source of truth for group 1
CCM_SavedPosition2 = {x = 0, y = 0} -- runtime source of truth for group 2

-- Profile-aware saved position for group 2
local function GetProfilePosition2()
	return SanitizeProfilePosition("trinketIcons2", 0, -80)
end


CCM_SavedPosition.x = CCM_SavedPosition.x or 0
CCM_SavedPosition.y = CCM_SavedPosition.y or 0
CCM_SavedPosition2.x = CCM_SavedPosition2.x or 0
CCM_SavedPosition2.y = CCM_SavedPosition2.y or 0

-- Forward declarations for cross-referencing in OnMouseUp handlers
local anchorFrame2

-- Anchor frame for group 1
local anchorFrame = CreateFrame("Frame", "CCM_AnchorFrame", UIParent)
anchorFrame:SetSize(240, 60)
anchorFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
anchorFrame:EnableMouse(false)
anchorFrame:SetMovable(true)
anchorFrame:SetFrameStrata("MEDIUM")

local function BeginManualDrag1(self)
	if InCombatLockdown() then return end
	local scale = UIParent:GetEffectiveScale() or 1
	local cx, cy = GetCursorPosition()
	self._dragStartCursorX = (tonumber(cx) or 0) / scale
	self._dragStartCursorY = (tonumber(cy) or 0) / scale
	self._dragStartX = CCM_SavedPosition.x or 0
	self._dragStartY = CCM_SavedPosition.y or 0
	self.isDragging = true
	self:SetScript("OnUpdate", function(f)
		local s = UIParent:GetEffectiveScale() or 1
		local mx, my = GetCursorPosition()
		mx = (tonumber(mx) or 0) / s
		my = (tonumber(my) or 0) / s
		local dx = mx - (f._dragStartCursorX or mx)
		local dy = my - (f._dragStartCursorY or my)
		CCM_SavedPosition.x = math.floor((f._dragStartX or 0) + dx)
		CCM_SavedPosition.y = math.floor((f._dragStartY or 0) + dy)
		f:ClearAllPoints()
		f:SetPoint("CENTER", UIParent, "CENTER", CCM_SavedPosition.x, CCM_SavedPosition.y)
	end)
end

local function EndManualDrag1(self)
	if not self.isDragging then return end
	self:SetScript("OnUpdate", nil)
	SetProfilePosition(CCM_SavedPosition.x, CCM_SavedPosition.y)
	self:ClearAllPoints()
	self:SetPoint("CENTER", UIParent, "CENTER", CCM_SavedPosition.x, CCM_SavedPosition.y)
	self.isDragging = false
end

anchorFrame:SetScript("OnDragStart", nil)
anchorFrame:SetScript("OnDragStop", nil)
anchorFrame:RegisterForDrag("LeftButton")
anchorFrame:SetScript("OnDragStart", function(self)
	if self.moving and not self.isDragging then
		BeginManualDrag1(self)
	end
end)
anchorFrame:SetScript("OnDragStop", function(self)
	if self.isDragging then
		EndManualDrag1(self)
	end
end)
anchorFrame:SetScript("OnMouseDown", function(self, button)
	if button == "LeftButton" and self.moving and not self.isDragging then
		BeginManualDrag1(self)
		return
	end
end)
anchorFrame:SetScript("OnHide", function(self)
	if self.isDragging then
		EndManualDrag1(self)
	end
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
	if button == "LeftButton" and self.isDragging then
		EndManualDrag1(self)
		return
	end
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
	EnsureSavedPositions()
	x, y = NormalizePosition(x, y, 0, -80)
	CCM_SavedPosition2.x = x
	CCM_SavedPosition2.y = y
	if CkraigProfileManager and CkraigProfileManager.SetProfileData then
		local data = CkraigProfileManager:GetProfileData("trinketIcons2") or {}
		data.x = x
		data.y = y
		CkraigProfileManager:SetProfileData("trinketIcons2", data)

		-- Keep active LibEditMode layout position in sync to prevent snap-back.
		local layoutName = LibEditMode and LibEditMode.GetActiveLayoutName and LibEditMode:GetActiveLayoutName()
		if layoutName then
			local tracked = CkraigProfileManager:GetProfileData("trackedItems") or {}
			tracked.layoutPositions = tracked.layoutPositions or {}
			tracked.layoutPositions.group2 = tracked.layoutPositions.group2 or {}
			tracked.layoutPositions.group2[layoutName] = { x = x, y = y }
			CkraigProfileManager:SetProfileData("trackedItems", tracked)
		end
	end
end

-- Anchor frame for group 2
anchorFrame2 = CreateFrame("Frame", "CCM_AnchorFrame2", UIParent)
anchorFrame2:SetSize(240, 60)
anchorFrame2:SetPoint("CENTER", UIParent, "CENTER", 0, -80)
anchorFrame2:EnableMouse(false)
anchorFrame2:SetMovable(true)
anchorFrame2:SetFrameStrata("MEDIUM")

local function BeginManualDrag2(self)
	if InCombatLockdown() then return end
	local scale = UIParent:GetEffectiveScale() or 1
	local cx, cy = GetCursorPosition()
	self._dragStartCursorX = (tonumber(cx) or 0) / scale
	self._dragStartCursorY = (tonumber(cy) or 0) / scale
	self._dragStartX = CCM_SavedPosition2.x or 0
	self._dragStartY = CCM_SavedPosition2.y or 0
	self.isDragging = true
	self:SetScript("OnUpdate", function(f)
		local s = UIParent:GetEffectiveScale() or 1
		local mx, my = GetCursorPosition()
		mx = (tonumber(mx) or 0) / s
		my = (tonumber(my) or 0) / s
		local dx = mx - (f._dragStartCursorX or mx)
		local dy = my - (f._dragStartCursorY or my)
		CCM_SavedPosition2.x = math.floor((f._dragStartX or 0) + dx)
		CCM_SavedPosition2.y = math.floor((f._dragStartY or 0) + dy)
		f:ClearAllPoints()
		f:SetPoint("CENTER", UIParent, "CENTER", CCM_SavedPosition2.x, CCM_SavedPosition2.y)
	end)
end

local function EndManualDrag2(self)
	if not self.isDragging then return end
	self:SetScript("OnUpdate", nil)
	SetProfilePosition2(CCM_SavedPosition2.x, CCM_SavedPosition2.y)
	self:ClearAllPoints()
	self:SetPoint("CENTER", UIParent, "CENTER", CCM_SavedPosition2.x, CCM_SavedPosition2.y)
	self.isDragging = false
end

anchorFrame2:SetScript("OnDragStart", nil)
anchorFrame2:SetScript("OnDragStop", nil)
anchorFrame2:RegisterForDrag("LeftButton")
anchorFrame2:SetScript("OnDragStart", function(self)
	if self.moving and not self.isDragging then
		BeginManualDrag2(self)
	end
end)
anchorFrame2:SetScript("OnDragStop", function(self)
	if self.isDragging then
		EndManualDrag2(self)
	end
end)
anchorFrame2:SetScript("OnMouseDown", function(self, button)
	if button == "LeftButton" and self.moving and not self.isDragging then
		BeginManualDrag2(self)
		return
	end
end)
anchorFrame2:SetScript("OnHide", function(self)
	if self.isDragging then
		EndManualDrag2(self)
	end
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
	if button == "LeftButton" and self.isDragging then
		EndManualDrag2(self)
		return
	end
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
	if type(data) ~= "table" then data = {} end
	data.layoutPositions = data.layoutPositions or {}
	if type(data.layoutPositions) ~= "table" then
		data.layoutPositions = {}
	end
	data.layoutPositions[profileKey] = data.layoutPositions[profileKey] or {}
	if type(data.layoutPositions[profileKey]) ~= "table" then
		data.layoutPositions[profileKey] = {}
	end
	return data.layoutPositions[profileKey]
end

local function SetLayoutPosition(profileKey, layoutName, x, y)
	local data = GetProfileData()
	if type(data) ~= "table" then data = {} end
	x, y = NormalizePosition(x, y, 0, 0)
	data.layoutPositions = data.layoutPositions or {}
	if type(data.layoutPositions) ~= "table" then
		data.layoutPositions = {}
	end
	data.layoutPositions[profileKey] = data.layoutPositions[profileKey] or {}
	if type(data.layoutPositions[profileKey]) ~= "table" then
		data.layoutPositions[profileKey] = {}
	end
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
	if saved and type(saved.x) == "number" and type(saved.y) == "number" then return saved end
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
	if anchorFrame.moving or anchorFrame.isDragging or anchorFrame2.moving or anchorFrame2.isDragging then
		return
	end
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
local function SetAnchorMoveMode(frame, labelText, enabled)
	if not frame then return end
	enabled = enabled and true or false

	frame.moving = enabled
	frame:SetFrameStrata(enabled and "TOOLTIP" or "MEDIUM")
	frame:SetMovable(enabled)
	frame:EnableMouse(enabled)

	if enabled then
		frame:Show()
		frame:SetAlpha(1)
	else
		frame:EnableKeyboard(false)
		frame._arrowKeyActive = false
		if frame._anchorLabel then
			frame._anchorLabel:SetText(labelText)
		end
		if not frame.isDragging then
			frame:Hide()
		end
	end
end

SLASH_TRINKETMOVE1 = "/trinketmove"
SlashCmdList["TRINKETMOVE"] = function()
    SetAnchorMoveMode(anchorFrame, "Group 1", not anchorFrame.moving)
end

-- Slash command to enable moving group 2
SLASH_TRINKETMOVE2 = "/trinketmove2"
SlashCmdList["TRINKETMOVE2"] = function()
	SetAnchorMoveMode(anchorFrame2, "Group 2", not anchorFrame2.moving)
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

-- Safe trinket cooldown setter using C_Item.GetItemCooldown (modern API, item-ID based)
local function SafeSetTrinketCooldown(cooldownFrame, slot)
	if not cooldownFrame or not slot then
		if cooldownFrame then cooldownFrame:Clear() end
		return false
	end
	local itemID = GetInventoryItemID("player", slot)
	if not itemID then
		cooldownFrame:Clear()
		return false
	end
	local start, duration, enable
	if C_Item and C_Item.GetItemCooldown then
		start, duration, enable = C_Item.GetItemCooldown(itemID)
	else
		start, duration, enable = GetInventoryItemCooldown("player", slot)
	end
	if enable and enable ~= 0 and type(start) == "number" and type(duration) == "number" then
		local ok = pcall(cooldownFrame.SetCooldown, cooldownFrame, start, duration)
		if not ok then cooldownFrame:Clear() end
		return true
	else
		cooldownFrame:Clear()
		return false
	end
end

-- Helper: get trinket cooldown info for inline checks (start, duration, enable)
-- Uses C_Item.GetItemCooldown when available, falls back to GetInventoryItemCooldown
local function GetTrinketCooldownInfo(slot)
	local itemID = GetInventoryItemID("player", slot)
	if itemID and C_Item and C_Item.GetItemCooldown then
		return C_Item.GetItemCooldown(itemID)
	end
	-- Fallback
	return GetInventoryItemCooldown("player", slot)
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
	EnsureSavedPositions()
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
	if not anchorFrame.moving then
		local p1 = GetProfilePosition()
		CCM_SavedPosition.x = p1.x
		CCM_SavedPosition.y = p1.y
		anchorFrame:ClearAllPoints()
		anchorFrame:SetPoint("CENTER", UIParent, "CENTER", CCM_SavedPosition.x or 0, CCM_SavedPosition.y or 0)
	end
	if not anchorFrame2.moving then
		local p2 = GetProfilePosition2()
		CCM_SavedPosition2.x = p2.x
		CCM_SavedPosition2.y = p2.y
		anchorFrame2:ClearAllPoints()
		anchorFrame2:SetPoint("CENTER", UIParent, "CENTER", CCM_SavedPosition2.x or 0, CCM_SavedPosition2.y or -80)
	end
	local iconOrder = GetIconOrder()
	local iconDataList = {}
	for _, key in ipairs(iconOrder) do
		if key == "racials" then
			for _, spellID in ipairs(FindPlayerRacials()) do
				table.insert(iconDataList, {type="racial", spellID=spellID, groupKey="racials"})
			end
		elseif key == "power" then
			if IsPlayerHealer() then
				-- Healers see mana potions instead of power potions
				local manaID, manaCount = FindFirstUsableManaPotion()
				if manaID then
					table.insert(iconDataList, {type="power", itemID=manaID, count=manaCount, groupKey="power"})
				else
					table.insert(iconDataList, {type="power", itemID=nil, iconID=SAMPLE_POWER_ICON_ID, count=0, desaturate=true, sample=true, groupKey="power"})
				end
			else
				local potionID, potionCount = FindFirstUsablePotion()
				if potionID then
					table.insert(iconDataList, {type="power", itemID=potionID, count=potionCount, groupKey="power"})
				else
					-- Show sample icon if no power potions
					table.insert(iconDataList, {type="power", itemID=nil, iconID=SAMPLE_POWER_ICON_ID, count=0, desaturate=true, sample=true, groupKey="power"})
				end
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
					   local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(data.spellID)
					   local icon = (spInfo and spInfo.iconID) or select(3, GetSpellInfo(data.spellID))
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
					   local start, duration, enable = GetTrinketCooldownInfo(data.slot)
					   if enable and enable ~= 0 and duration > 0 then
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
					   local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(data.spellID)
					   local icon = (spInfo and spInfo.iconID) or select(3, GetSpellInfo(data.spellID))
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
					   local start, duration, enable = GetTrinketCooldownInfo(data.slot)
					   if enable and enable ~= 0 and duration > 0 then
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
				       if Group2SortOrder and Group2SortOrder > 0 then
				           frame.layoutIndex = Group2SortOrder
				       else
				           frame.layoutIndex = nil
				       end
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
					local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(data.spellID)
					local icon = (spInfo and spInfo.iconID) or select(3, GetSpellInfo(data.spellID))
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
					local start, duration, enable = GetTrinketCooldownInfo(data.slot)
					if enable and enable ~= 0 and duration > 0 then
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
			   local start, duration, enable = GetTrinketCooldownInfo(data.slot)
			   if enable and enable ~= 0 then
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
	eventFrame:RegisterEvent("BAG_UPDATE")
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
	EnsureSavedPositions()
	local pos = GetProfilePosition()
	CCM_SavedPosition.x = pos.x
	CCM_SavedPosition.y = pos.y
	local pos2 = GetProfilePosition2()
	CCM_SavedPosition2.x = pos2.x
	CCM_SavedPosition2.y = pos2.y
	anchorFrame:ClearAllPoints()
	anchorFrame:SetPoint("CENTER", UIParent, "CENTER", CCM_SavedPosition.x, CCM_SavedPosition.y)
	anchorFrame2:ClearAllPoints()
	anchorFrame2:SetPoint("CENTER", UIParent, "CENTER", CCM_SavedPosition2.x, CCM_SavedPosition2.y)
	UpdateAllIcons()
	-- Listen for profile changes to reload position
	if CkraigProfileManager and CkraigProfileManager.RegisterCallback and not anchorFrame._profileCB then
		anchorFrame._profileCB = true
		CkraigProfileManager:RegisterCallback("OnProfileChanged", function()
			LoadSettings()
			local pos = GetProfilePosition()
			CCM_SavedPosition.x = pos.x
			CCM_SavedPosition.y = pos.y
			local pos2 = GetProfilePosition2()
			CCM_SavedPosition2.x = pos2.x
			CCM_SavedPosition2.y = pos2.y
			anchorFrame:ClearAllPoints()
			anchorFrame:SetPoint("CENTER", UIParent, "CENTER", CCM_SavedPosition.x, CCM_SavedPosition.y)
			anchorFrame2:ClearAllPoints()
			anchorFrame2:SetPoint("CENTER", UIParent, "CENTER", CCM_SavedPosition2.x, CCM_SavedPosition2.y)
			UpdateAllIcons()
		end)
	end
end

-- Old CreateOptionsPanel removed; options are now handled by Ace3 AceConfig (ui/options/TrinketRacialsOptions.lua)
local function CreateOptionsPanel() return nil end

-- Expose module API for Ace3 options
_G.TRINKETRACIALS = _G.TRINKETRACIALS or {}
_G.TRINKETRACIALS.SaveSettings = function() SaveSettings() end
_G.TRINKETRACIALS.UpdateAllIcons = function() UpdateAllIcons() end
_G.TRINKETRACIALS.LoadSettings = function() LoadSettings() end
_G.TRINKETRACIALS.GetProfileData = function() return GetProfileData() end
_G.TRINKETRACIALS.SetProfileData = function(k, v) SetProfileData(k, v) end
_G.TRINKETRACIALS.GetPosition = function() return GetProfilePosition() end
_G.TRINKETRACIALS.SetPosition = function(x, y)
	x, y = NormalizePosition(x, y, 0, 0)
    SetProfilePosition(x, y)
    CCM_SavedPosition.x = x
    CCM_SavedPosition.y = y
    if anchorFrame then
        anchorFrame:ClearAllPoints()
        anchorFrame:SetPoint("CENTER", UIParent, "CENTER", x, y)
    end
    UpdateAllIcons()
end
_G.TRINKETRACIALS.GetPosition2 = function() return GetProfilePosition2() end
_G.TRINKETRACIALS.SetPosition2 = function(x, y)
	x, y = NormalizePosition(x, y, 0, -80)
    SetProfilePosition2(x, y)
    CCM_SavedPosition2.x = x
    CCM_SavedPosition2.y = y
    if anchorFrame2 then
        anchorFrame2:ClearAllPoints()
        anchorFrame2:SetPoint("CENTER", UIParent, "CENTER", x, y)
    end
    UpdateAllIcons()
end
_G.TRINKETRACIALS.SetMoveMode = function(group, enabled)
	if group == 2 then
		SetAnchorMoveMode(anchorFrame2, "Group 2", enabled)
	else
		SetAnchorMoveMode(anchorFrame, "Group 1", enabled)
	end
end
_G.TRINKETRACIALS.ToggleMoveMode = function(group)
	if group == 2 then
		SetAnchorMoveMode(anchorFrame2, "Group 2", not anchorFrame2.moving)
	else
		SetAnchorMoveMode(anchorFrame, "Group 1", not anchorFrame.moving)
	end
end
_G.TRINKETRACIALS.LockAllAnchors = function()
	SetAnchorMoveMode(anchorFrame, "Group 1", false)
	SetAnchorMoveMode(anchorFrame2, "Group 2", false)
end
_G.TRINKETRACIALS.ResetPositions = function()
	SetProfilePosition(0, 0)
	SetProfilePosition2(0, -80)
	local data = GetProfileData()
	if type(data) ~= "table" then data = {} end
	data.layoutPositions = nil
	SetProfileData("layoutPositions", nil)
	if anchorFrame then
		anchorFrame:ClearAllPoints()
		anchorFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	end
	if anchorFrame2 then
		anchorFrame2:ClearAllPoints()
		anchorFrame2:SetPoint("CENTER", UIParent, "CENTER", 0, -80)
	end
	UpdateAllIcons()
end

-- Expose item lists for Ace3 options UI
_G.TRINKETRACIALS.GetRacials = function() return RACIALS end
_G.TRINKETRACIALS.GetPowerPotions = function() return POWER_POTIONS end
_G.TRINKETRACIALS.GetHealingPotions = function() return HEALING_POTIONS end
_G.TRINKETRACIALS.GetIconGroupAssignments = function() return GetIconGroupAssignments() end
_G.TRINKETRACIALS.SetIconGroupAssignment = function(key, group)
    local assignments = GetIconGroupAssignments()
    assignments[key] = group
    SetIconGroupAssignments(assignments)
    UpdateAllIcons()
end

local loginInitFrame = CreateFrame("Frame")
loginInitFrame:RegisterEvent("PLAYER_LOGIN")
loginInitFrame:SetScript("OnEvent", function()
	InitializeTrinketIcons()
	RegisterTrinketEditMode()
	SetupTrinketEditModeCallbacks()
end)



