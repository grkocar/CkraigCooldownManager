-- ============================================================
-- CkraigCooldownManager :: Data :: SpellLists
-- ============================================================
-- Centralised spell ID / item ID lists used by multiple modules.
-- Keeping them in one place makes it easy to maintain when
-- Blizzard adds or removes spells between patches.
-- ============================================================

local CCM = _G.CkraigCooldownManager
CCM.SpellData = CCM.SpellData or {}

-- Racial ability spell IDs
CCM.SpellData.RACIALS = {
    -- Every Man for Himself / Will of the Forsaken / similar
    7744,    -- Will of the Forsaken (Undead)
    20549,   -- War Stomp (Tauren)
    20572,   -- Blood Fury (Orc – AP)
    33697,   -- Blood Fury (Orc – AP+SP)
    33702,   -- Blood Fury (Orc – SP)
    20589,   -- Escape Artist (Gnome)
    20594,   -- Stoneform (Dwarf)
    26297,   -- Berserking (Troll)
    28880,   -- Gift of the Naaru (Draenei)
    59542,   -- Gift of the Naaru (Draenei – Hunter)
    59543,   -- Gift of the Naaru (Draenei – Paladin)
    59544,   -- Gift of the Naaru (Draenei – Priest)
    59545,   -- Gift of the Naaru (Draenei – Shaman)
    59547,   -- Gift of the Naaru (Draenei – Warrior)
    59548,   -- Gift of the Naaru (Draenei – Mage)
    121093,  -- Gift of the Naaru (Draenei – Monk)
    58984,   -- Shadowmeld (Night Elf)
    59752,   -- Every Man for Himself (Human)
    68992,   -- Darkflight (Worgen)
    69041,   -- Rocket Barrage (Goblin)
    69070,   -- Rocket Jump (Goblin)
    107079,  -- Quaking Palm (Pandaren)
    25046,   -- Arcane Torrent (Blood Elf – Rogue)
    28730,   -- Arcane Torrent (Blood Elf – Mage)
    50613,   -- Arcane Torrent (Blood Elf – DK)
    69179,   -- Arcane Torrent (Blood Elf – Warrior)
    80483,   -- Arcane Torrent (Blood Elf – Hunter)
    129597,  -- Arcane Torrent (Blood Elf – Monk)
    155145,  -- Arcane Torrent (Blood Elf – Paladin)
    202719,  -- Arcane Torrent (Blood Elf – DH)
    232633,  -- Arcane Torrent (Blood Elf – Priest)
    -- Allied Races
    255647,  -- Light's Judgment (Lightforged Draenei)
    255654,  -- Bull Rush (Highmountain Tauren)
    256948,  -- Spatial Rift (Void Elf)
    260364,  -- Arcane Pulse (Nightborne)
    265221,  -- Fireblood (Dark Iron Dwarf)
    274738,  -- Ancestral Call (Mag'har Orc)
    287712,  -- Haymaker (Kul Tiran)
    291944,  -- Regeneratin' (Zandalari Troll)
    312411,  -- Bag of Tricks (Vulpera)
    312924,  -- Bag of Tricks (Vulpera – alt)
    357214,  -- Adrenaline Rush (Mechagnome – overcharged)
    370626,  -- Visage (Dracthyr)
    368970,  -- Tail Swipe (Dracthyr)
    416250,  -- Soar (Dracthyr)
    436344,  -- Charge Forward (Earthen)
    -- TWW additions
    212969,  -- Racial TWW
    212970,  -- Racial TWW
    212971,  -- Racial TWW
    1237885, -- Racial TWW
}

-- Power potion item IDs
CCM.SpellData.POWER_POTIONS = {
    431932, 370816, 1236616, 1238443, 1236652, 1236994, 1236998, 1236551, 383781,
}

-- Additional power potion IDs used by TrinketRacials
CCM.SpellData.TRINKET_POWER_POTIONS = {
    241308, 241309, 212264, 212265, 212263,
}

-- Mana potion item IDs (shown for healer specs instead of power potions)
CCM.SpellData.MANA_POTIONS = {
    241300,  -- Algari Mana Potion (Midnight R1)
    241301,  -- Algari Mana Potion (Midnight R2)
}

-- Healing potion item IDs (extend as needed)
CCM.SpellData.HEALING_POTIONS = {
    241304,  -- Algari Healing Potion (Midnight R1)
    241305,  -- Algari Healing Potion (Midnight R2)
    244839,  -- Healing Potion (TWW)
    258138,  -- Potent Healing Potion (50% health)
    244835,  -- Healing Potion (War Within)
    244838,  -- Healing Potion (War Within)
    211880,  -- Algari Healing Potion (War Within)
    211879,  -- Algari Healing Potion (War Within R2)
    211878,  -- Algari Healing Potion (War Within R3)
    191380,  -- Refreshing Healing Potion (Dragonflight)
    187802,  -- Cosmic Healing Potion (Shadowlands)
    169451,  -- Abyssal Healing Potion (BFA)
    152615,  -- Coastal Healing Potion (BFA)
    127834,  -- Ancient Healing Potion (Legion)
    109223,  -- Healing Tonic (WoD)
    76097,   -- Master Healing Potion (MoP)
    57191,   -- Mythical Healing Potion (Cata)
    33447,   -- Runic Healing Potion (WotLK)
    22829,   -- Super Healing Potion (TBC)
    13446,   -- Major Healing Potion (Classic)
    3928,    -- Superior Healing Potion (Classic)
    1710,    -- Greater Healing Potion (Classic)
    929,     -- Healing Potion (Classic)
    118,     -- Minor Healing Potion (Classic)
}

-- Default power potion timer durations  (spellID → seconds)
CCM.SpellData.DEFAULT_POTION_DURATIONS = {
    [431932]  = 30,
    [370816]  = 30,
    [1236616] = 30,
    [1238443] = 30,
    [1236652] = 30,
    [1236994] = 30,
    [1236998] = 30,
    [1236551] = 30,
}

-- ============================================================
-- Shared CooldownViewerSettings category scanner
-- ============================================================
-- Reads from Blizzard's C_CooldownViewer.GetCooldownViewerCategorySet API
-- which returns ALL cooldownIDs in a CooldownViewerSettings category
-- (Essential, Utility, TrackedBuff, TrackedBar) — same lists shown in
-- the in-game Cooldown Settings panel.
--
-- Returns: array of { key = spellID, name = string, icon = texturePath }
-- ============================================================

function CCM.GetCooldownViewerCategoryItems(category)
    local items = {}
    if not C_CooldownViewer or not C_CooldownViewer.GetCooldownViewerCategorySet then
        return items
    end
    if not Enum or not Enum.CooldownViewerCategory then
        return items
    end

    local okSet, cooldownSet = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, category, true)
    if not okSet or not cooldownSet then return items end

    local seen = {}
    for cooldownID in pairs(cooldownSet) do
        if not seen[cooldownID] then
            seen[cooldownID] = true
            local spellID = cooldownID
            local name, iconTex

            -- Resolve cooldownID → spellID through CooldownViewer API
            if C_CooldownViewer.GetCooldownViewerCooldownInfo then
                local okInfo, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cooldownID)
                if okInfo and info then
                    if info.spellID then spellID = info.spellID end
                end
            end

            -- Get spell name and icon
            if C_Spell and C_Spell.GetSpellName then
                name = C_Spell.GetSpellName(spellID)
            end
            if C_Spell and C_Spell.GetSpellTexture then
                iconTex = C_Spell.GetSpellTexture(spellID)
            end

            if name then
                table.insert(items, { key = spellID, name = name, icon = iconTex })
            end
        end
    end

    table.sort(items, function(a, b) return (a.name or "") < (b.name or "") end)
    return items
end
