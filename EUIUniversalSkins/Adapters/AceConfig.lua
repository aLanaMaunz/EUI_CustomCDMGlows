local ADDON, ns = ...

local function GetLibrary(name)
    if not LibStub then return nil end
    local ok, lib = pcall(LibStub, name, true)
    return ok and lib or nil
end

local function Install()
    local dialog = GetLibrary("AceConfigDialog-3.0")
    if not dialog then
        if ns.debug then ns.Print("AceConfigDialog-3.0 was not found yet.") end
        return false
    end

    local function ScanOpenFrames()
        local openFrames = dialog.OpenFrames
        if type(openFrames) ~= "table" then return end
        for appName, frame in pairs(openFrames) do
            if ns.IsSkinTarget(frame) then
                ns.TrackRoot(frame, "AceConfig: " .. tostring(appName))
                ns.QueueScan(frame)
            end
        end
    end

    -- Config apps often build or recycle their controls during FeedGroup.
    -- Hooking the library's public methods catches those rebuilds without
    -- replacing AceGUI/AceConfig functions or changing their return values.
    ns.Hook(dialog, "Open", ScanOpenFrames)
    ns.Hook(dialog, "FeedGroup", ScanOpenFrames)
    ns.Hook(dialog, "Close", ScanOpenFrames)
    ScanOpenFrames()

    ns.Print("AceConfigDialog adapter installed.")
    return true
end

local adapter = ns.RegisterAdapter("AceConfig", "AceConfig / AceGUI windows", {}, Install)
ns.OnLibraryRegistered(function()
    ns.TryAdapter(adapter)
end)
