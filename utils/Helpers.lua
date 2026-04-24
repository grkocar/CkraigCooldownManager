-- ============================================================
-- CkraigCooldownManager :: Utils :: Helpers
-- ============================================================
-- Shared utility functions used by multiple modules.
-- Centralised here to avoid duplication across files.
-- ============================================================

local CCM = _G.CkraigCooldownManager
CCM.Utils = CCM.Utils or {}

-- Round a value to the nearest pixel
function CCM.Utils.RoundPixel(value)
    return math.floor((value or 0) + 0.5)
end

-- Deep-copy a table (recursive)
function CCM.Utils.DeepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = CCM.Utils.DeepCopy(v)
    end
    return copy
end

-- Safe pcall wrapper with optional self argument
function CCM.Utils.SafeCall(fn, obj)
    if type(fn) ~= "function" then return false end
    local ok
    if obj then
        ok = pcall(fn, obj)
    else
        ok = pcall(fn)
    end
    return ok
end

-- ============================================================
-- Patch version detection
-- ============================================================
-- select(4, GetBuildInfo()) returns numeric TOC version:
--   12.0.0 = 120000, 12.0.5 = 120005
-- This flag is evaluated once at file load and never changes.
local tocVersion = select(4, GetBuildInfo()) or 0
CCM.Is1205 = (tocVersion >= 120005)

-- Check if the player is currently mounted
function CCM.Utils.IsPlayerMounted()
    return IsMounted and IsMounted()
end

-- Safely collect children from a container frame
function CCM.Utils.SafeGetChildren(container)
    if not container or not container.GetChildren then return {} end
    return { container:GetChildren() }
end

-- Hide all border textures on an icon frame
function CCM.Utils.HideAllIconBorders(child)
    if not child then return end
    if child.DebuffBorder then child.DebuffBorder:SetAlpha(0) end
    if child.IconBorder then child.IconBorder:SetAlpha(0) end
    if child.Border then child.Border:SetAlpha(0) end
    if child.GetRegions then
        for i = 1, select('#', child:GetRegions()) do
            local region = select(i, child:GetRegions())
            if region and region.IsObjectType and region:IsObjectType("Texture") then
                region:SetAlpha(0)
            end
        end
    end
end

-- Cache for FindIconTexture (avoids repeated frame tree walks)
-- Keys are frames (permanent objects, never GC'd in WoW), values held strongly.
local _iconTextureCache = {}

-- Find the icon texture inside a container frame (walks children)
-- Results are cached per container; cache auto-clears when frames are collected.
function CCM.Utils.FindIconTexture(container)
    if not container then return nil end
    local cached = _iconTextureCache[container]
    if cached then return cached end
    if container.IsObjectType and container:IsObjectType("Texture") then
        _iconTextureCache[container] = container
        return container
    end
    local direct = container.icon or container.Icon or container.IconTexture or container.Texture
    if direct and direct.IsObjectType and direct:IsObjectType("Texture") then
        _iconTextureCache[container] = direct
        return direct
    end
    if container.GetRegions then
        for i = 1, select("#", container:GetRegions()) do
            local region = select(i, container:GetRegions())
            if region and region.IsObjectType and region:IsObjectType("Texture") then
                _iconTextureCache[container] = region
                return region
            end
        end
    end
    if container.GetChildren then
        for _, child in ipairs({ container:GetChildren() }) do
            for i = 1, select("#", child:GetRegions()) do
                local region = select(i, child:GetRegions())
                if region and region.IsObjectType and region:IsObjectType("Texture") then
                    _iconTextureCache[container] = region
                    return region
                end
            end
        end
    end
    return nil
end

-- Invalidate FindIconTexture cache for a specific container (call after frame recycling)
function CCM.Utils.InvalidateIconTextureCache(container)
    if container then _iconTextureCache[container] = nil end
end

-- Normalize a spell key to a canonical string form
function CCM.Utils.NormalizeSpellKey(value)
    if value == nil then return nil end
    local valueType = type(value)
    if valueType == "number" then
        if value <= 0 then return nil end
        return tostring(math.floor(value + 0.5))
    end
    if valueType == "string" then
        local trimmed = value:match("^%s*(.-)%s*$")
        if trimmed == "" then return nil end
        return trimmed
    end
    return nil
end

-- Safe spell/item info lookup (shared by TrackedSpells, DynamicIcons, etc.)
-- Returns: name, icon, "spell"/"item" — or nil,nil,nil
function CCM.Utils.SafeGetSpellOrItemInfo(id)
    if not id then return nil, nil, nil end
    local numericID = tonumber(id)
    if not numericID then return nil, nil, nil end

    -- Try spell info first (single API call)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(numericID)
        if info and info.name then
            return info.name, info.iconID, "spell"
        end
    end

    -- Fallback to item info
    local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfo(numericID)
    if itemName then
        return itemName, itemIcon, "item"
    end

    return nil, nil, nil
end

-- ============================================================
-- Modern C_Spell classification helpers (11.x+)
-- ============================================================

-- Check if a spell is a self-buff (e.g. for auto-classifying essential buffs)
function CCM.Utils.IsSelfBuff(spellID)
    if not spellID then return false end
    if C_Spell and C_Spell.IsSelfBuff then
        local ok, result = pcall(C_Spell.IsSelfBuff, spellID)
        if ok then return result end
    end
    return false
end

-- Check if a spell is a priority aura (Blizzard marks high-importance buffs)
function CCM.Utils.IsPriorityAura(spellID)
    if not spellID then return false end
    if C_Spell and C_Spell.IsPriorityAura then
        local ok, result = pcall(C_Spell.IsPriorityAura, spellID)
        if ok then return result end
    end
    return false
end

-- Check if a spell is usable right now (mana, range, etc.)
function CCM.Utils.IsSpellUsable(spellID)
    if not spellID then return false end
    if C_Spell and C_Spell.IsSpellUsable then
        local ok, result = pcall(C_Spell.IsSpellUsable, spellID)
        if ok then return result end
    end
    return false
end

-- Get the maximum cumulative aura stacks for a spell (useful for segment bars)
function CCM.Utils.GetMaxAuraStacks(spellID)
    if not spellID then return nil end
    if C_Spell and C_Spell.GetSpellMaxCumulativeAuraApplications then
        local ok, result = pcall(C_Spell.GetSpellMaxCumulativeAuraApplications, spellID)
        if ok and result and result > 0 then return result end
    end
    return nil
end

-- Request spell data load from server (cold cache guard)
function CCM.Utils.RequestSpellDataLoad(spellID)
    if not spellID then return end
    if C_Spell and C_Spell.RequestLoadSpellData then
        pcall(C_Spell.RequestLoadSpellData, spellID)
    end
end

-- Check if a spell is an external defensive cooldown
function CCM.Utils.IsExternalDefensive(spellID)
    if not spellID then return false end
    if C_Spell and C_Spell.IsExternalDefensive then
        local ok, result = pcall(C_Spell.IsExternalDefensive, spellID)
        if ok then return result end
    end
    return false
end

-- Get the override spell for a given spellID (talent morphing)
function CCM.Utils.GetOverrideSpell(spellID)
    if not spellID then return spellID end
    if C_Spell and C_Spell.GetOverrideSpell then
        local ok, overrideID = pcall(C_Spell.GetOverrideSpell, spellID)
        if ok and overrideID and overrideID ~= spellID then
            return overrideID
        end
    end
    return spellID
end
