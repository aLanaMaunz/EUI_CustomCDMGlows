local ADDON, ns = ...

ns.name = ADDON
ns.version = "0.1.1"
ns.adapters = {}
ns.adapterByID = {}
ns.libraryCallbacks = {}
ns.roots = setmetatable({}, { __mode = "k" })
ns.skin = nil
ns.activated = false
ns.debug = false
ns.captureCreateFrame = false
ns.stats = {
    roots = 0,
    framesVisited = 0,
    buttons = 0,
    checkboxes = 0,
    editBoxes = 0,
    statusBars = 0,
    scrollBars = 0,
    dropdowns = 0,
    fontStrings = 0,
    panels = 0,
    aceWidgets = 0,
    autoDiscoveredRoots = 0,
    questieDialogs = 0,
}

local adapterFailures = {}
local registeredWithEUI = false
local eventFrame = CreateFrame("Frame")

local function Print(message)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffd6a85aEUI Universal Skins:|r " .. tostring(message))
    end
end
ns.Print = Print

function ns.IsEnabled()
    EUIUniversalSkinsDB = EUIUniversalSkinsDB or {}
    return EUIUniversalSkinsDB.disabled ~= true
end

function ns.IsAutoDiscoverEnabled()
    EUIUniversalSkinsDB = EUIUniversalSkinsDB or {}
    return EUIUniversalSkinsDB.autoDiscover ~= false
end

function ns.After(delay, callback)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay or 0, callback)
    else
        callback()
    end
end

function ns.IsObject(value)
    local valueType = type(value)
    return (valueType == "table" or valueType == "userdata")
        and type(value.GetObjectType) == "function"
        and not (value.IsForbidden and value:IsForbidden())
end

function ns.IsSkinTarget(value)
    return ns.IsObject(value) and not (value.IsProtected and value:IsProtected())
end

function ns.Safe(label, callback, ...)
    local ok, result = pcall(callback, ...)
    if not ok then
        local key = tostring(label) .. ": " .. tostring(result)
        if not adapterFailures[key] then
            adapterFailures[key] = true
            if geterrorhandler then
                geterrorhandler()(ADDON .. " / " .. key)
            else
                Print(key)
            end
        end
        return false
    end
    return true, result
end

local hooked = setmetatable({}, { __mode = "k" })
function ns.Hook(object, method, callback)
    if not object or type(object[method]) ~= "function" or type(hooksecurefunc) ~= "function" then
        return false
    end
    local objectHooks = hooked[object]
    if not objectHooks then
        objectHooks = {}
        hooked[object] = objectHooks
    end
    if objectHooks[method] then return true end
    objectHooks[method] = true
    local ok = pcall(hooksecurefunc, object, method, function(...)
        if ns.IsEnabled() and ns.activated then
            ns.Safe("hook " .. tostring(method), callback, ...)
        end
    end)
    if not ok then
        objectHooks[method] = nil
        return false
    end
    return true
end

local function IsAddonLoaded(addonName)
    local api = C_AddOns and C_AddOns.IsAddOnLoaded
    if api then
        local ok, result = pcall(api, addonName)
        return ok and result == true
    end
    if IsAddOnLoaded then
        local ok, result = pcall(IsAddOnLoaded, addonName)
        return ok and result == true
    end
    return false
end
ns.IsAddonLoaded = IsAddonLoaded

function ns.RegisterAdapter(id, label, addonNames, installer)
    if ns.adapterByID[id] then
        error("Duplicate adapter registration: " .. tostring(id))
    end
    if type(addonNames) == "string" then addonNames = { addonNames } end
    local adapter = {
        id = id,
        label = label or id,
        addonNames = addonNames or {},
        install = installer,
        attempted = false,
        active = false,
    }
    ns.adapterByID[id] = adapter
    ns.adapters[#ns.adapters + 1] = adapter
    if ns.activated then ns.TryAdapter(adapter) end
    return adapter
end

function ns.TryAdapter(adapter)
    if not adapter or adapter.attempted or not ns.activated or not ns.IsEnabled() then return end
    local targetLoaded = #adapter.addonNames == 0
    for _, addonName in ipairs(adapter.addonNames) do
        if IsAddonLoaded(addonName) then
            targetLoaded = true
            break
        end
    end
    if not targetLoaded then return end

    local ok, result = pcall(adapter.install, ns.skin, adapter)
    if not ok then
        adapter.attempted = true
        adapter.active = false
        adapterFailures[adapter.id] = true
        if geterrorhandler then geterrorhandler()(ADDON .. " / " .. adapter.label .. ": " .. tostring(result)) end
    elseif result == false then
        -- A dependency/library may be embedded in an addon that loads later.
        -- Leave the adapter retryable for the next ADDON_LOADED event.
        adapter.attempted = false
        adapter.active = false
    else
        adapter.attempted = true
        adapter.active = true
        if ns.debug then Print("adapter active: " .. adapter.label) end
    end
end

function ns.OnLibraryRegistered(callback)
    if type(callback) ~= "function" then return end
    ns.libraryCallbacks[#ns.libraryCallbacks + 1] = callback
    callback()
end

function ns.TryAdapters(addonName)
    for _, adapter in ipairs(ns.adapters) do
        if not addonName then
            ns.TryAdapter(adapter)
        elseif #adapter.addonNames == 0 then
            ns.TryAdapter(adapter)
        else
            for _, target in ipairs(adapter.addonNames) do
                if target == addonName then
                    ns.TryAdapter(adapter)
                    break
                end
            end
        end
    end
end

local function RegisterWithEUI()
    if registeredWithEUI then return true end
    local EUI = _G.EllesmereUI
    if not EUI or type(EUI.RegisterSkin) ~= "function" then return false end

    registeredWithEUI = true
    EUI.RegisterSkin(ADDON, function(S)
        ns.skin = S
        ns.activated = true
        ns.InstallCoreHooks()
        ns.TryAdapters()
        -- Defer discovery by one frame so every file in this addon's TOC has
        -- loaded, even when RegisterSkin invokes us immediately.
        ns.After(0, function()
            if ns.AutoDiscoverNamedRoots and ns.IsAutoDiscoverEnabled() then
                ns.AutoDiscoverNamedRoots()
            end
        end)
        Print("v" .. ns.version .. " active (EUI skin API v" .. tostring(S.apiVersion or "?") .. ").")
    end)
    return true
end

function ns.InstallCoreHooks()
    if ns.coreHooksInstalled then return end
    ns.coreHooksInstalled = true
    ns.TryAdapters()
    -- Libraries such as AceGUI may be embedded in, and registered by, addons
    -- that load after this compatibility addon.
    if LibStub and type(LibStub.NewLibrary) == "function" then
        ns.Hook(LibStub, "NewLibrary", function(...)
            ns.TryAdapters()
            for _, callback in ipairs(ns.libraryCallbacks) do
                ns.Safe("library registration callback", callback, ...)
            end
        end)
    end
end

-- Adapters are attempted both when their target addon loads and at login. This
-- mirrors the load-callback model used by mature addon skin collections.
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event, addonName)
    EUIUniversalSkinsDB = EUIUniversalSkinsDB or {}
    if event == "ADDON_LOADED" then
        RegisterWithEUI()
        if addonName then
            ns.TryAdapters(addonName)
            if ns.AutoDiscoverNamedRoots and ns.IsAutoDiscoverEnabled() then
                ns.AutoDiscoverNamedRoots(addonName)
            end
        end
    elseif event == "PLAYER_LOGIN" then
        if not RegisterWithEUI() then
            Print("EllesmereUI skin API not found. Install/update EllesmereUI and enable this skin in its third-party skin settings.")
        end
        ns.TryAdapters()
        if ns.AutoDiscoverNamedRoots and ns.IsAutoDiscoverEnabled() then
            ns.AutoDiscoverNamedRoots()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if ns.FlushPendingScans then ns.FlushPendingScans() end
    end
end)

RegisterWithEUI()

SLASH_EUIUNIVERSALSKINS1 = "/euis"
SLASH_EUIUNIVERSALSKINS2 = "/euius"
SlashCmdList.EUIUNIVERSALSKINS = function(message)
    local command, argument = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = (command or ""):lower()
    argument = (argument or ""):lower()

    if command == "on" then
        EUIUniversalSkinsDB.disabled = false
        Print("enabled. Re-enable the skin in EllesmereUI if its third-party skin toggle is off; reload recommended.")
        return
    elseif command == "off" then
        EUIUniversalSkinsDB.disabled = true
        Print("disabled for this session. Reload to fully remove installed hooks.")
        return
    elseif command == "debug" then
        ns.debug = argument ~= "off"
        Print("debug " .. (ns.debug and "enabled" or "disabled") .. ".")
        return
    elseif command == "status" then
        if ns.ShowStatus then ns.ShowStatus() else Print("v" .. ns.version .. ", active=" .. tostring(ns.activated)) end
        return
    elseif command == "scan" then
        if ns.ScanTrackedRoots then ns.ScanTrackedRoots() else Print("scanner not ready") end
        return
    elseif command == "inspect" then
        if ns.InspectMouseFocus then ns.InspectMouseFocus() else Print("diagnostics not ready") end
        return
    elseif command == "discover" then
        if ns.DiscoverTopLevelFrames then ns.DiscoverTopLevelFrames() else Print("diagnostics not ready") end
        return
    elseif command == "questie" then
        if ns.ScanQuestieDialogs then
            local matched, newlySkinned = ns.ScanQuestieDialogs()
            Print("Questie AddonDialog scan: " .. tostring(matched) .. " matching frame(s), "
                .. tostring(newlySkinned) .. " newly skinned.")
        else
            Print("Questie adapter is not ready.")
        end
        return
    elseif command == "autoscan" then
        local enabled = argument ~= "off"
        EUIUniversalSkinsDB.autoDiscover = enabled
        Print("named-root auto-discovery " .. (enabled and "enabled" or "disabled") .. ".")
        if enabled and ns.AutoDiscoverNamedRoots then
            ns.AutoDiscoverNamedRoots()
        end
        return
    elseif command == "watch" then
        if ns.SetCreateFrameWatch then ns.SetCreateFrameWatch(argument ~= "off") else Print("diagnostics not ready") end
        return
    end

    Print("v" .. ns.version .. " | commands: status, scan, inspect, discover, questie, autoscan on/off, debug on/off, watch on/off, on, off")
end
