-- ============================================================
-- CkraigCooldownManager :: UI :: Minimap :: MinimapButton
-- ============================================================
-- Draggable minimap button with tooltip.
-- Uses the CK_logo texture.  Position is persisted in
-- CCM_Settings.minimapAngle.
-- ============================================================

local optionsInit = CreateFrame("Frame")
optionsInit:RegisterEvent("PLAYER_LOGIN")
optionsInit:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()

    local AceConfigDialog = LibStub and LibStub("AceConfigDialog-3.0", true)

    local minimapBtn = CreateFrame("Button", "CkraigCDM_MinimapButton", Minimap)
    minimapBtn:SetSize(32, 32)
    minimapBtn:SetFrameStrata("LOW")
    minimapBtn:SetFrameLevel(5)
    minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    minimapBtn:SetMovable(true)
    minimapBtn:RegisterForDrag("LeftButton")

    -- Icon artwork
    local icon = minimapBtn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture("Interface\\AddOns\\CkraigCooldownManager\\CK_logo")

    -- Border ring
    local border = minimapBtn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", 0, 0)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Positioning helpers
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
            local half = Minimap:GetWidth() / 2 + 5
            local scale = math.max(math.abs(cos), math.abs(sin))
            x = cos / scale * half
            y = sin / scale * half
        else
            -- For circular minimap, position on outer edge using minimap radius
            local radius = Minimap:GetWidth() / 2 + 5
            x = cos * radius
            y = sin * radius
        end
        minimapBtn:ClearAllPoints()
        minimapBtn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    -- Apply saved visibility
    if CCM_Settings.showMinimapButton == false then
        minimapBtn:Hide()
    else
        minimapBtn:Show()
    end

    -- Expose reference so AceOptions can toggle it
    _G.CkraigCDM_MinimapButtonRef = minimapBtn

    UpdateMinimapPosition(savedAngle)

    -- Drag-to-reposition around the minimap edge
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

    -- Click to open Ace3 options dialog
    minimapBtn:SetScript("OnClick", function()
        if InCombatLockdown() then
            print("|cffff6600Ckraig Cooldown Manager:|r Cannot open settings during combat.")
            return
        end
        if AceConfigDialog then
            if AceConfigDialog.OpenFrames and AceConfigDialog.OpenFrames["CkraigCooldownManager"] then
                AceConfigDialog:Close("CkraigCooldownManager")
            else
                AceConfigDialog:Open("CkraigCooldownManager")
            end
        end
    end)

    -- Tooltip
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
