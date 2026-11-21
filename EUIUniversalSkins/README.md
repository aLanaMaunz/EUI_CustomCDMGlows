# EUI Universal Skins (WoW Forever)

Version: **0.1.1**

A first prototype of a compatibility-skin framework for generic addon UI elements, using the official EllesmereUI Skinning API.

## Goals

- Reuse EllesmereUI's own rendering primitives instead of creating a parallel theme.
- Discover and skin common controls inside known addon-owned windows.
- Auto-discover named top-level frames whose names begin with a loaded addon folder name, then scan only those matched roots. This is enabled by default and can be disabled with `/euis autoscan off`.
- Add library and addon adapters in the style of established skin collections, without depending on or overlapping the separate EUIAddonSkins package.
- Keep addon behaviour intact: no replacement of click handlers, no `SetScript` overwrites, no parent changes and no blanket `UIParent` reskin pass.
- Provide diagnostics to inspect UI that is not yet covered.

## Install

1. Extract the `EUIUniversalSkins` folder into `World of Warcraft/_classic_/Interface/AddOns/` (use the actual AddOns folder for your WoW Forever installation).
2. Make sure EllesmereUI is installed and enabled.
3. Enable **EUI Universal Skins** under EllesmereUI's third-party skin settings if it is not enabled by default.
4. Reload the UI.

This package targets WoW Forever / Camelot (interface 16001). The archive includes both the standard addon TOC and a `_Camelot.toc` variant, following the layout used by the EllesmereUI addon-skins package. It is not intended for Retail or other Classic flavors.

## Current adapters

- **Questie AddonDialog:** Questie's Forever dialog keeps its `Dialog` API in the addon's private namespace, so it is not assumed to exist as `_G.Questie.Dialog`. The adapter first hooks `LibPopupStack-1.0:Register`, which receives the actual dialog frame when Questie shows it. If that shared library is not exposed through LibStub, it falls back to watching the narrow top-level `BackdropTemplate` frame creation signature. Either way, it verifies the frame's distinctive owned members (`Text`, `Button1`, `Button2`, `EditBox`, `Background`, `Border`, `AlertIcon`, `Resize`, and `Choose`) before skinning it. It skins the panel, action buttons, optional edit box and fonts, and preserves the alert icon and Questie's scripts.
- **AceConfig / AceGUI windows:** rescans open AceConfig windows after `Open`, `FeedGroup` and `Close`, applying generic control skinning to their descendants. It also handles AceGUI dropdowns, texture-based checkboxes, tab groups and close buttons.
- **Blizzard / LibUIDropDownMenu lists:** detects common dropdown list globals after menu construction and skins their backdrop frames.

## Generic control coverage

Within roots supplied by an adapter, the scanner currently handles:

- ordinary text buttons (icon/item buttons are deliberately excluded)
- check buttons
- edit boxes
- status bars
- vertical scrollbars
- dropdown-button objects
- NineSlice and InsetFrame template artwork
- generic BackdropTemplate subpanels inside adapter-owned windows, while retaining foreground icon/art regions
- FontStrings
- AceGUI dropdowns, checkboxes and tab groups
- named close buttons, common minimize/close button textures and recognized page arrows
- square icon crops for safely identified icon buttons

It re-scans a container when it is shown and a ScrollFrame after vertical scrolling, so newly created or recycled child controls can be discovered.

## Slash commands

- `/euis status` - API, adapter and scan counters
- `/euis scan` - rescan all roots currently known to adapters
- `/euis inspect` - inspect the frame under the mouse, including its parent chain, textures, text and direct children. It tries `GetMouseFoci` / `GetMouseFocus` first, then falls back to an `EnumerateFrames()` + `IsMouseOver()` search.
- `/euis discover` - list likely top-level UI roots; diagnostic only, changes nothing
- `/euis questie` - manually search for and skin a Questie AddonDialog frame; reports how many matching frames were found
- `/euis autoscan on/off` - enable or disable conservative named-addon-root discovery
- `/euis watch on` - temporarily log unique `CreateFrame` signatures and their source addon when possible
- `/euis watch off` - stop logging (the secure hook remains inert until reload)
- `/euis debug on` / `/euis debug off` - enable or disable extra adapter messages
- `/euis off` - disable this addon's scanning until re-enabled or reload
- `/euis on` - enable scanning again

## Important limitations of v0.1.0

There is no safe, universal way to infer ownership and intent for every anonymous frame in WoW. This prototype does not recursively skin `UIParent`: its auto-discovery enumerates frame objects only to find named top-level `Frame` / `ScrollFrame` roots whose names match a loaded addon folder prefix, then scans inside those roots. Anonymous windows and frames without a matching addon-name prefix still need a targeted adapter. Generic styles are limited to high-confidence control types, and protected frames are skipped.

The `CreateFrame` watch is diagnostic only. It can miss calls made through a `CreateFrame` function reference cached before the hook was installed, and a source file is not always available in the stack. It does not change or skin newly-created frames.

The Lua files have been reviewed and the first mocked-runtime tests cover the Questie dialog shape, AceConfig roots, AceGUI checkboxes and tab groups. Version 0.1.1 corrects the Questie private-namespace assumption and adds a mouse-over fallback for the inspect command. The package has not yet been executed inside the actual WoW Forever client. The next in-game test should verify the Questie confirmation dialog and the updated `/euis inspect` fallback. Keep the addon disabled or remove its folder if any frame looks wrong.

## Next steps

1. Test the Questie confirmation prompt from the original screenshot.
2. Use `/euis inspect` and `/euis discover` on another missing element and capture the output.
3. Add narrowly-scoped adapters for the actual addons and UI libraries revealed by those diagnostics.
4. Expand generic widget support only where the EUI API has an appropriate primitive or a tested safe treatment.
