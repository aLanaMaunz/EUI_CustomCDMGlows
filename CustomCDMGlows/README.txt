Custom CDM Glows 1.3.0
=====================

Standalone EllesmereUI plugin for custom Frostbolt and Ice Lance Cooldown
Manager icons. It uses EllesmereUI's public CDM icon lookup and native glow
renderer. It does not modify EllesmereUI files.

Aura detection
--------------
WoW Forever can mark the Frost Nova, Frostbite and Fingers of Frost aura
queries as secret. The addon therefore does not query C_UnitAuras for these
conditions. It reads the active-state flag from Blizzard's own Cooldown
Manager tracked-aura item frames instead.

For proc detection, add these auras to Blizzard Cooldown Manager under
Tracked Buffs or Tracked Bars:

- Frost Nova
- Frostbite
- Fingers of Frost

Keep the Blizzard BuffIconCooldownViewer and/or BuffBarCooldownViewer enabled
so their native state continues to update. The viewer can be visually faded,
but must remain enabled and shown.

Spell ID options
----------------
All IDs are editable in the EllesmereUI plugin options and saved in the
CustomCDMGlowsDB SavedVariables table.

Custom CDM spell IDs:
- Frostbolt: one positive numeric spell ID.
- Ice Lance: one positive numeric spell ID.

Aura spell IDs:
- Frost Nova: comma-separated IDs for all ranks that should trigger the glow.
- Frostbite: one or more comma-separated aura IDs.
- Fingers of Frost: comma-separated IDs for the proc variants.

Press Enter or move focus away from an input field to save the value. Invalid
entries are rejected and the last saved value is restored. Clearing an aura
ID field removes that ID match from the corresponding condition.

Defaults:
- Frostbolt: 8408
- Ice Lance: 1240044
- Frost Nova: 122, 865, 6131, 10230
- Frostbite: 12494
- Fingers of Frost: 400669, 400670

Options
-------
- Enable/disable the addon and each custom CDM spell independently.
- Enable/disable Frost Nova, Frostbite and Fingers of Frost conditions.
- Selected conditions are combined with OR.
- Optional Glow When Usable behavior.
- Current class color by default, or a custom RGB glow color.

Use /cdmglows to open the plugin options. Diagnostic and test slash commands
have been removed.

Install
-------
1. Remove the previous CustomCDMGlows folder.
2. Extract the new CustomCDMGlows folder into Interface/AddOns/.
3. Run /reload.
