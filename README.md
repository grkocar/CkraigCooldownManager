# CkraigCooldownManager

**Version:** 3.0  
**Author:** Ckraigfriend  
**Category:** Unit Frames  

A professional World of Warcraft addon for tracking cooldowns, buffs, trinkets, racials, potions, and custom spells — all with fully customisable bar colours, icon layouts, cluster modes, glow effects, and per-spec profile management.

---

## Folder Structure

```
CkraigCooldownManager/
│
├── core/                          # Core bootstrap & lifecycle
│   ├── Namespace.lua              #   Global addon table
│   ├── SavedVariables.lua         #   All SavedVariables declarations
│   ├── Events.lua                 #   Combat helpers, spec-change listener
│   └── Init.lua                   #   ADDON_LOADED bootstrap
│
├── utils/                         # Shared utilities
│   ├── Constants.lua              #   Addon-wide constants & defaults
│   ├── Helpers.lua                #   DeepCopy, SafeCall, icon helpers, etc.
│   └── Profiling.lua              #   CPU profiling stubs
│
├── data/                          # Static data tables
│   └── SpellLists.lua             #   Racial, potion, healing spell IDs
│
├── profiles/                      # AceDB profile system
│   ├── Defaults.lua               #   Default values for every module
│   ├── ProfileManager.lua         #   AceDB init, change notifications
│   └── ProfileOptions.lua         #   Import/Export, Blizzard settings panel
│
├── trackers/                      # Feature modules that track things
│   ├── buffs/
│   │   ├── EssentialBuffTracker.lua   # Essential buff icon grid
│   │   └── UtilityBuffTracker.lua     # Utility buff icon grid
│   ├── cooldowns/
│   │   ├── DynamicIcons.lua           # Main cooldown icon tracker
│   │   ├── TrackedSpells.lua          # Custom spellbook spell tracker
│   │   └── SegmentBars.lua            # Segmented charge/stack bars
│   └── items/
│       ├── TrinketRacials.lua         # Trinkets, racials, potions
│       └── PowerPotionSuccess.lua     # Power potion success icon
│
├── cooldownbars/                  # Cooldown bar rendering (split from CCM_CooldownBars)
│   ├── BarCore.lua                #   AceAddon registration, viewer frame
│   ├── BarStyle.lua               #   StyleBar() — textures, backdrop, fonts
│   ├── BarLayout.lua              #   RepositionAllBars() — stacking & cluster
│   ├── ClusterAnchors.lua         #   Movable cluster anchor frames
│   ├── SpellIdentity.lua          #   Spell resolution & known-spell checks
│   └── BarOptions.lua             #   Blizzard settings panel for bars
│
├── visuals/                       # Visual effects
│   ├── GlowManager.lua            #   LibCustomGlow wrapper & batching
│   └── GlowOptions.lua            #   Glow settings panel
│
├── ui/                            # User interface panels
│   ├── MainOptionsPanel.lua       #   Top-level Blizzard Settings category
│   ├── ChargeTextColorOptions.lua #   Charge/stack text colour panel
│   ├── ColorPickers.lua           #   Per-spell colour swatches
│   └── minimap/
│       └── MinimapButton.lua      #   Draggable minimap button
│
├── icons/                         # Custom icon assets
├── Libs/                          # Third-party libraries (Ace3, LSM, etc.)
├── CkraigCooldownManager.toc      #   Addon manifest (load order)
└── README.md                      #   This file
```

---

## How the Load Order Works

The `.toc` file controls the load order.  WoW loads files top-to-bottom:

1. **Libraries** — Ace3, LibSharedMedia, LibCustomGlow, etc.
2. **Core** — Namespace → SavedVariables → Events → Init
3. **Utils** — Constants, Helpers, Profiling
4. **Data** — Spell/item ID tables
5. **Profiles** — Defaults → ProfileManager → ProfileOptions
6. **Trackers** — Buff, cooldown, and item trackers
7. **Visuals** — Glow system
8. **UI** — Options panels and minimap button (loaded last so all modules exist)

---

## Migration Guide

The original single-file modules (e.g. `CCM_CooldownBars.lua`) still work.  
The new folder structure loads **alongside** them during migration.  
To complete migration for any module:

1. Move the code from the original `.lua` into the matching new file(s).
2. Update the `.toc` to point to the new path.
3. Delete the original file.

---

## Slash Commands

| Command    | Action                     |
|------------|----------------------------|
| `/ckcdm`   | Open the settings panel    |

---

## SavedVariables

| Variable                    | Module                      |
|-----------------------------|-----------------------------|
| `CkraigCooldownManagerDB`  | Profile database (AceDB)    |
| `MyEssentialBuffTrackerDB`  | Essential Buffs settings     |
| `MyUtilityBuffTrackerDB`    | Utility Buffs settings       |
| `DYNAMICICONSDB`            | Dynamic Icons settings       |
| `DYNAMICBARSDB`             | Dynamic Bars settings        |
| `CooldownChargeDB`          | Charge text colour overrides |
| `CCM_Settings`              | Minimap button angle, etc.   |
| `TrinketTrackerDB`          | Trinket/Racial settings      |
| `PowerPotionSuccessIconDB`  | Potion success icon settings |
| `CCM_TrackedSpellsDB`       | Custom tracked spells        |
| `CCM_SegmentBarsDB`         | Segment bar settings         |
