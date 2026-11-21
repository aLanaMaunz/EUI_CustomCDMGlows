local ADDON_NAME, ns = ...
local EUI = _G.EllesmereUI

if not EUI then
    return
end

if type(_G.EUISecondChatWakeDB) ~= "table" then
    _G.EUISecondChatWakeDB = {}
end

local db = _G.EUISecondChatWakeDB
if db.enabled == nil then
    db.enabled = true
end

local POLL_INTERVAL = 0.20
local ticker
local wasFaded = {}
local wasHovered = {}

-------------------------------------------------------------------------------
-- EllesmereUI Chat access
--
-- RegisterPlugin is the public options integration. EUI currently has no
-- public API for waking its chat idle-fade timer, so we resolve the existing
-- chat module namespace and call its own ResetIdleTimer function. All access
-- is guarded so an EUI internal change fails closed rather than throwing.
-------------------------------------------------------------------------------
local function GetChatAPI()
    local modules = EUI._ModuleNS
    local chatNS = modules and modules["EllesmereUIChat"]
    local chatAPI = chatNS and chatNS.ECHAT

    if type(chatAPI) ~= "table"
        or type(chatAPI.DB) ~= "function"
        or type(chatAPI.ResetIdleTimer) ~= "function"
    then
        return nil
    end

    return chatAPI
end

local function ClearHoverState()
    wipe(wasFaded)
    wipe(wasHovered)
end

local function GetChatPanelFrame(chatFrame)
    -- EUI keeps its detached panel frame in a weak side table so Blizzard's
    -- protected ChatFrame tables are not modified. Use that panel as an extra
    -- hit-test surface when the helper is available.
    local getFrameData = EUI._chatCFD
    if type(getFrameData) ~= "function" or not chatFrame then
        return nil
    end

    local ok, frameData = pcall(getFrameData, chatFrame)
    if ok and type(frameData) == "table" then
        return frameData.bg
    end

    return nil
end

local function IsFrameMouseOver(frame)
    if not frame or not frame.IsShown or not frame:IsShown() then
        return false
    end

    if not frame.IsMouseOver then
        return false
    end

    -- IsMouseOver is a geometric rectangle test. It still works while EUI has
    -- disabled mouse input on fully faded chat frames for passthrough.
    local ok, over = pcall(frame.IsMouseOver, frame)
    return ok and over == true
end

local function CheckSecondaryChatWindows()
    if db.enabled == false then
        ClearHoverState()
        return
    end

    local chatAPI = GetChatAPI()
    if not chatAPI then
        ClearHoverState()
        return
    end

    local ok, cfg = pcall(chatAPI.DB)
    if not ok or type(cfg) ~= "table"
        or cfg.idleFadeEnabled == false
        or cfg.visibility == "never"
    then
        ClearHoverState()
        return
    end

    -- Respect EUI's visibility rules (combat, mouseover, etc.). Do not wake
    -- chat when EUI itself currently considers the chat stack hidden.
    if type(EUI.EvalVisibility) == "function" then
        local visibleOK, visible = pcall(EUI.EvalVisibility, cfg)
        if visibleOK and visible == false then
            ClearHoverState()
            return
        end
    end

    local shouldWake = false

    -- ChatFrame1 has EUI's native hover overlay. Secondary permanent chat
    -- windows are frames 2-10 and need the additional geometric hover check.
    for index = 2, 10 do
        local chatFrame = _G["ChatFrame" .. index]
        local editBox = _G["ChatFrame" .. index .. "EditBox"]
        local tab = _G["ChatFrame" .. index .. "Tab"]
        local panel = GetChatPanelFrame(chatFrame)

        local frameShown = chatFrame and chatFrame.IsShown
            and chatFrame:IsShown()
        local panelShown = panel and panel.IsShown and panel:IsShown()
        local windowShown = frameShown or panelShown
        local alpha = 1

        if chatFrame and chatFrame.GetAlpha then
            alpha = chatFrame:GetAlpha() or 1
        elseif panel and panel.GetAlpha then
            alpha = panel:GetAlpha() or 1
        end

        -- EUI applies the same idle-fade alpha to the chat frame and its
        -- detached panel. The panel can extend beyond the Blizzard frame.
        local faded = windowShown and type(alpha) == "number" and alpha < 0.999

        local hovered = IsFrameMouseOver(chatFrame)
        if not hovered then
            hovered = IsFrameMouseOver(panel)
        end

        if not hovered then
            hovered = IsFrameMouseOver(editBox)
        end

        if not hovered then
            hovered = IsFrameMouseOver(tab)
        end

        -- Wake on either edge: the cursor enters an already-faded window, or
        -- the fade begins while the cursor is already resting over that window.
        if faded and hovered and (not wasFaded[index] or not wasHovered[index]) then
            shouldWake = true
        end

        wasFaded[index] = faded and true or false
        wasHovered[index] = hovered and true or false
    end

    if shouldWake then
        -- Use EUI's own state machine so its fade-in animation, idle delay,
        -- alpha settings and mouse-passthrough restoration remain authoritative.
        pcall(chatAPI.ResetIdleTimer)
    end
end

local function StopTicker()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
    ClearHoverState()
end

local function StartTicker()
    if db.enabled == false or ticker then
        return
    end

    if not (C_Timer and C_Timer.NewTicker) then
        return
    end

    ticker = C_Timer.NewTicker(POLL_INTERVAL, CheckSecondaryChatWindows)
end

local function ApplyEnabledState()
    if db.enabled == false then
        StopTicker()
    else
        StartTicker()
    end
end

-------------------------------------------------------------------------------
-- EllesmereUI plugin settings page
-------------------------------------------------------------------------------
if type(EUI.RegisterPlugin) == "function" then
    EUI.RegisterPlugin(ADDON_NAME, {
        label = "Chat Fade Fix",
        modules = {
            {
                key = "General",
                title = "Second Chat Fade",
                description = "Restore mouseover fade-in for additional chat windows.",
                pages = { "Settings" },
                buildPage = function(pageName, parent, yOffset)
                    local W = EUI.Widgets
                    if not W then
                        return 0
                    end

                    local y = yOffset
                    local _, height

                    _, height = W:SectionHeader(parent, "BEHAVIOR", y)
                    y = y - height

                    _, height = W:Toggle(
                        parent,
                        "Enable hover wake for secondary chat windows",
                        y,
                        function()
                            return db.enabled ~= false
                        end,
                        function(value)
                            db.enabled = value and true or false
                            ApplyEnabledState()
                        end
                    )
                    y = y - height

                    return math.abs(y)
                end,
            },
        },
    })
end

SLASH_EUISECONDCHATWAKE1 = "/eui2chat"
SlashCmdList.EUISECONDCHATWAKE = function()
    if type(EUI.OpenPlugin) == "function" then
        EUI.OpenPlugin(ADDON_NAME, "General", "Settings")
    end
end

-------------------------------------------------------------------------------
-- Start after EllesmereUIChat has completed its PLAYER_LOGIN setup.
-------------------------------------------------------------------------------
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
    end

    if db.enabled ~= false and C_Timer and C_Timer.After then
        C_Timer.After(0.5, StartTicker)
    end
end)
