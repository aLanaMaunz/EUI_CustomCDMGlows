EUI CDM Custom Spell GCD Fix 1.8.0
==================================

Installation:
1. Remove the previous EUI_CDM_CustomSpellGCDFix folder from Interface/AddOns.
2. Extract this folder into Interface/AddOns.
3. Reload the UI with /reload.

This is a minimal version of the tested 1.7.0 implementation. Runtime behavior
is unchanged. Diagnostic counters, the /eui-gcdfix command, status summaries,
and the successful-load message have been removed.

The addon listens only for SPELL_UPDATE_COOLDOWN. It refreshes visible
EllesmereUI Custom Spell frames by passing the full
C_Spell.GetSpellCooldownDuration(spellID) DurationObject directly to the native
Cooldown widget. It does not inspect secret values and does not use timers,
polling, or cast-stop events.

The addon does not modify EllesmereUI files.
