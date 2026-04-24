-- Store references to dynamically created UI elements for cleanup
local spellRowWidgets = {}

local function ClearSpellRows()
    for _, row in ipairs(spellRowWidgets) do
        if row.iconTex then row.iconTex:Hide() end
        if row.nameFont then row.nameFont:Hide() end
        if row.chargeFont then row.chargeFont:Hide() end
        if row.colorBtn then row.colorBtn:Hide() end
    end
    wipe(spellRowWidgets)
end

local function CreateSpellRows()
    ClearSpellRows()
    local spellList = _G.CCM_GetDynamicIconsSpellList and _G.CCM_GetDynamicIconsSpellList() or {}
    local yOffset = -120
    local xIcon, xName, xCharge, xColor = 32, 72, 220, 340
    local rowHeight = 36
    for i, spell in ipairs(spellList) do
        local spellID = tonumber(spell.key)
        local name = spell.name or ("SpellID " .. tostring(spellID))
        local icon = spell.icon or "Interface\\ICONS\\INV_Misc_QuestionMark"

        -- Icon
        local iconTex = _G.ChargeTextColorOptionsPanel:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(28, 28)
        iconTex:SetPoint("TOPLEFT", xIcon, yOffset - (i-1)*rowHeight)
        iconTex:SetTexture(icon)

        -- Name
        local nameFont = _G.ChargeTextColorOptionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameFont:SetPoint("TOPLEFT", xName, yOffset - (i-1)*rowHeight + -2)
        nameFont:SetText(name)

        -- Charge info
        local chargeFont = _G.ChargeTextColorOptionsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        chargeFont:SetPoint("TOPLEFT", xCharge, yOffset - (i-1)*rowHeight + -2)
        local charges, maxCharges
        if C_Spell and C_Spell.GetSpellCharges and spellID then
            charges, maxCharges = C_Spell.GetSpellCharges(spellID)
        end
        if maxCharges and maxCharges > 1 then
            chargeFont:SetText("Charges: " .. (charges or "?") .. "/" .. maxCharges)
        else
            chargeFont:SetText("")
        end

        -- Color picker button
        local colorBtn = CreateFrame("Button", nil, _G.ChargeTextColorOptionsPanel, "UIPanelButtonTemplate")
        colorBtn:SetSize(120, 28)
        colorBtn:SetPoint("TOPLEFT", xColor, yOffset - (i-1)*rowHeight)
        colorBtn:SetText("Pick Color")
        colorBtn.spellID = spellID
        colorBtn:SetScript("OnClick", function(self)
            local db = ChargeTextColorOptions:GetSettings()
            local key = "Spell_" .. tostring(self.spellID)
            local current = db[key] or {1,1,1,1}
            local r, g, b, a = unpack(current)
            if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
                ColorPickerFrame:SetupColorPickerAndShow({
                    r = r, g = g, b = b, opacity = a, hasOpacity = true,
                    swatchFunc = function()
                        local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                        local newA = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or 1
                        db[key] = {newR, newG, newB, newA}
                        _G.CooldownChargeDB = db
                        ThrottledReskinAllViewers()
                    end,
                    opacityFunc = function()
                        local newR, newG, newB = ColorPickerFrame:GetColorRGB()
                        local newA = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or 1
                        db[key] = {newR, newG, newB, newA}
                        _G.CooldownChargeDB = db
                        ThrottledReskinAllViewers()
                    end,
                })
            end
        end)

        table.insert(spellRowWidgets, {
            iconTex = iconTex,
            nameFont = nameFont,
            chargeFont = chargeFont,
            colorBtn = colorBtn,
        })
    end
end

local colorPickersUIBuilt = false
local function BuildColorPickersUI()
    if colorPickersUIBuilt then return end
    colorPickersUIBuilt = true
    local parentPanel = _G.ChargeTextColorOptionsPanel or UIParent
    local spellLabel = parentPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    spellLabel:SetPoint("TOPLEFT", 32, -48)
    spellLabel:SetText("Per-Spell Charge/Stack Colors")

    local refreshBtn = CreateFrame("Button", nil, parentPanel, "UIPanelButtonTemplate")
    refreshBtn:SetSize(100, 24)
    refreshBtn:SetPoint("TOPLEFT", spellLabel, "BOTTOMLEFT", 0, -8)
    refreshBtn:SetText("Refresh List")
    refreshBtn:SetScript("OnClick", function()
        CreateSpellRows()
    end)

    CreateSpellRows()
end
_G.CCM_CreateColorPickersUI = BuildColorPickersUI
