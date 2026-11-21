EUI Roboto Font - WoW Forever
============================

This addon registers the static Roboto Regular TrueType font with
LibSharedMedia-3.0. EllesmereUI reads external SharedMedia fonts and includes
them in its global and per-module font pickers.

Installation
------------
1. Extract the EUIRobotoFont folder into:
   _forever_/Interface/AddOns/
2. Make sure EllesmereUI is enabled.
3. Restart the game or run /reload.
4. Open EllesmereUI's font settings and select "Roboto".

If another addon already registered a font under the exact key "Roboto",
this addon registers its copy as "Roboto (EUI)" instead of overwriting it.

Font attribution
----------------
Roboto Regular, Copyright 2011 Google Inc.
Source: googlefonts/roboto-2, src/hinted/Roboto-Regular.ttf
License: Apache License, Version 2.0 (see LICENSE-Apache-2.0.txt).

This addon bundles the static Regular face only. EUI applies its own font
outline/shadow settings independently.
