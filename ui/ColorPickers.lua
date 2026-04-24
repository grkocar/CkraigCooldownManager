-- ============================================================
-- CkraigCooldownManager :: UI :: ColorPickers
-- ============================================================
-- Per-spell colour-picker rows for the Charge Text Colors
-- options panel.  Lists every tracked spell with a swatch.
-- ============================================================

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

        local iconTex = _G.ChargeTextColorOptionsPanel:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(28, 28)
        iconTex:SetPoint("TOPLEFT", xIcon, yOffset - (i - 1) * rowHeight)
        iconTex:SetTexture(icon)

        local nameFont = _G.ChargeTextColorOptionsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameFont:SetPoint("TOPLEFT", xName, yOffset - (i - 1) * rowHeight + 4)
        nameFont:SetText(name)

        table.insert(spellRowWidgets, {
            iconTex = iconTex,
            nameFont = nameFont,
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
    refreshBtn:SetScript("OnClick", function() CreateSpellRows() end)

    CreateSpellRows()
end

_G.CCM_CreateColorPickersUI = BuildColorPickersUI
