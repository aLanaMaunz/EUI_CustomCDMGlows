EUI Second Chat Wake
====================

A small standalone companion plugin for EllesmereUI on WoW Forever.

What it does
------------
EllesmereUI's Idle Fade currently has a mouseover wake overlay for ChatFrame1.
This addon adds mouseover wake-up detection to the additional permanent chat
windows (ChatFrame2 through ChatFrame10).

It uses IsMouseOver() as a geometric hit test on the chat frame and EUI's
separate panel frame, so it can still detect the pointer when EllesmereUI has
disabled mouse input on a fully faded chat window. The panel check also covers
parts of the skin that extend beyond the original Blizzard chat frame.
When a secondary window is hovered while faded, the addon calls EllesmereUI's
own ResetIdleTimer() function. Fade timing, fade strength, and the fade-in
animation therefore remain controlled by EllesmereUI.

Installation
------------
1. Extract the EUISecondChatWake folder into:
   World of Warcraft\_forever_\Interface\AddOns\
   (Use your actual WoW Forever installation folder.)
2. Make sure EllesmereUI and EllesmereUI Chat are enabled.
3. Restart the game or type /reload.

Options
-------
Open EllesmereUI and look for:
   Chat Fade Fix -> Second Chat Fade -> Settings

The feature is enabled by default. You can also use:
   /eui2chat

Compatibility
-------------
WoW Forever interface: 16001
Dependencies: EllesmereUI, EllesmereUIChat

Implementation note
-------------------
EllesmereUI exposes RegisterPlugin for third-party settings pages, but its
current plugin API does not expose a public chat idle-fade wake function.
This addon therefore resolves the existing EllesmereUIChat module namespace
through EllesmereUI's module registry, uses its existing chat-frame side-table
helper for the panel hit test, and calls ECHAT.ResetIdleTimer(). These internal
accesses are guarded. If EllesmereUI changes the registry, helper, or reset
function, the addon safely stops doing the extra wake-up instead of raising
an error.
