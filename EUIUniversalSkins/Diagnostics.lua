local ADDON, ns = ...

local function ObjectName(frame)
    if not frame then return "<nil>" end
    local kind = frame.GetObjectType and frame:GetObjectType() or type(frame)
    local name = frame.GetName and frame:GetName() or nil
    return tostring(name or "<anonymous>") .. " [" .. tostring(kind) .. "]"
end

local function SafeCall(method, object, ...)
    if type(method) ~= "function" then return nil end
    local ok, result = pcall(method, object, ...)
    if ok then return result end
end

local function GetFrameDepth(frame)
    local depth, current = 0, frame
    while current and depth < 40 do
        depth = depth + 1
        current = current.GetParent and SafeCall(current.GetParent, current) or nil
    end
    return depth
end

local function GetFrameArea(frame)
    local width = frame.GetWidth and SafeCall(frame.GetWidth, frame) or 0
    local height = frame.GetHeight and SafeCall(frame.GetHeight, frame) or 0
    return math.max(0, width or 0) * math.max(0, height or 0)
end

local function EnumerateMouseOverFrame()
    if type(EnumerateFrames) ~= "function" then return nil end

    local best, bestDepth, bestArea
    local frame = EnumerateFrames()
    while frame do
        if ns.IsObject(frame) and frame.IsMouseOver and frame.IsVisible then
            local visible = SafeCall(frame.IsVisible, frame)
            local over = visible and SafeCall(frame.IsMouseOver, frame)
            if visible and over then
                local depth = GetFrameDepth(frame)
                local area = GetFrameArea(frame)
                if not best or depth > bestDepth or (depth == bestDepth and area < bestArea) then
                    best, bestDepth, bestArea = frame, depth, area
                end
            end
        end
        frame = EnumerateFrames(frame)
    end
    return best
end

local function GetMouseFocusFrame()
    if type(GetMouseFoci) == "function" then
        local results = { pcall(GetMouseFoci) }
        if results[1] then
            for i = 2, #results do
                if ns.IsObject(results[i]) then return results[i], "GetMouseFoci" end
            end
        end
    end
    if type(GetMouseFocus) == "function" then
        local ok, result = pcall(GetMouseFocus)
        if ok and ns.IsObject(result) then return result, "GetMouseFocus" end
    end

    local fallback = EnumerateMouseOverFrame()
    if fallback then return fallback, "EnumerateFrames()/IsMouseOver fallback" end
    return nil, "no supported mouse-focus API returned a frame"
end

function ns.ShowStatus()
    local S = ns.skin
    ns.Print("v" .. ns.version .. " | EUI active=" .. tostring(ns.activated)
        .. " | API=" .. tostring(S and S.apiVersion or "unavailable")
        .. " | enabled=" .. tostring(ns.IsEnabled()))
    ns.Print("roots=" .. tostring(ns.stats.roots)
        .. ", frames=" .. tostring(ns.stats.framesVisited)
        .. ", buttons=" .. tostring(ns.stats.buttons)
        .. ", checkboxes=" .. tostring(ns.stats.checkboxes)
        .. ", editBoxes=" .. tostring(ns.stats.editBoxes)
        .. ", statusBars=" .. tostring(ns.stats.statusBars)
        .. ", scrollBars=" .. tostring(ns.stats.scrollBars)
        .. ", fontStrings=" .. tostring(ns.stats.fontStrings)
        .. ", AceGUI widgets=" .. tostring(ns.stats.aceWidgets or 0)
        .. ", auto roots=" .. tostring(ns.stats.autoDiscoveredRoots or 0)
        .. ", Questie dialogs=" .. tostring(ns.stats.questieDialogs))
    ns.Print("named-root auto-discovery=" .. tostring(ns.IsAutoDiscoverEnabled()))
    for _, adapter in ipairs(ns.adapters) do
        local state = adapter.active and "active" or (adapter.attempted and "not available" or "waiting")
        ns.Print(adapter.label .. ": " .. state)
    end
end

function ns.InspectMouseFocus()
    local frame, source = GetMouseFocusFrame()
    if not frame then
        ns.Print("Could not resolve a mouse-focus frame (" .. tostring(source) .. ").")
        ns.Print("APIs: GetMouseFoci=" .. tostring(type(GetMouseFoci) == "function")
            .. ", GetMouseFocus=" .. tostring(type(GetMouseFocus) == "function")
            .. ", EnumerateFrames=" .. tostring(type(EnumerateFrames) == "function"))
        ns.Print("Try /fstack on the element, or use /euis discover while the window is open.")
        return
    end

    ns.Print("Mouse focus: " .. ObjectName(frame) .. " | source=" .. tostring(source))
    local current = frame
    for depth = 1, 6 do
        if not current then break end
        local width = current.GetWidth and math.floor(current:GetWidth() + 0.5) or 0
        local height = current.GetHeight and math.floor(current:GetHeight() + 0.5) or 0
        local strata = current.GetFrameStrata and current:GetFrameStrata() or "?"
        ns.Print(string.format("  parent %d: %s | %dx%d | strata=%s | shown=%s",
            depth, ObjectName(current), width, height, tostring(strata), tostring(current.IsShown and current:IsShown())))
        current = current.GetParent and current:GetParent() or nil
    end

    if frame.GetRegions then
        local regions = { frame:GetRegions() }
        local shown = 0
        for i = 1, #regions do
            local region = regions[i]
            if region and region.GetObjectType then
                local kind = region:GetObjectType()
                if kind == "Texture" then
                    local texture = region.GetTexture and region:GetTexture()
                    if texture then
                        ns.Print("  texture: " .. tostring(texture):sub(1, 110))
                        shown = shown + 1
                    end
                elseif kind == "FontString" then
                    local text = region.GetText and region:GetText()
                    if text and text ~= "" then
                        ns.Print("  text: " .. tostring(text):gsub("\n", " "):sub(1, 110))
                        shown = shown + 1
                    end
                end
                if shown >= 10 then break end
            end
        end
    end

    if frame.GetChildren then
        local children = { frame:GetChildren() }
        ns.Print("  direct children: " .. tostring(#children))
        for i = 1, math.min(#children, 12) do
            ns.Print("    " .. ObjectName(children[i]))
        end
    end
end

function ns.DiscoverTopLevelFrames()
    if type(EnumerateFrames) ~= "function" then
        ns.Print("EnumerateFrames() is not available on this client build.")
        return
    end

    local strataRank = {
        BACKGROUND = 1,
        LOW = 2,
        MEDIUM = 3,
        HIGH = 4,
        DIALOG = 5,
        FULLSCREEN = 6,
        FULLSCREEN_DIALOG = 7,
        TOOLTIP = 8,
    }
    local found = 0
    local frame = EnumerateFrames()
    while frame do
        if ns.IsObject(frame) and frame.GetParent and frame:GetParent() == UIParent
            and frame.IsShown and frame:IsShown() then
            local strata = frame.GetFrameStrata and frame:GetFrameStrata() or "MEDIUM"
            local children = frame.GetNumChildren and frame:GetNumChildren() or 0
            if (strataRank[strata] or 0) >= strataRank.DIALOG or children >= 3 then
                found = found + 1
                ns.Print("candidate " .. found .. ": " .. ObjectName(frame)
                    .. " | strata=" .. tostring(strata) .. " | children=" .. tostring(children))
                if found >= 60 then break end
            end
        end
        frame = EnumerateFrames(frame)
    end
    ns.Print("discovery complete; " .. found .. " candidate top-level frames listed. Nothing was changed.")
end

local watchInstalled = false
local watchSeen = {}
local watchCount = 0
function ns.SetCreateFrameWatch(enabled)
    if not enabled then
        ns.captureCreateFrame = false
        ns.Print("CreateFrame watch disabled. Its lightweight hook remains installed until reload.")
        return
    end
    if not watchInstalled then
        if type(hooksecurefunc) ~= "function" then
            ns.Print("hooksecurefunc is unavailable; CreateFrame watch cannot be installed.")
            return
        end
        local ok = pcall(hooksecurefunc, "CreateFrame", function(frameType, frameName, parent, template)
            if not ns.captureCreateFrame then return end
            if frameType ~= "Button" and frameType ~= "CheckButton" and frameType ~= "EditBox"
                and frameType ~= "Slider" and frameType ~= "ScrollFrame" and frameType ~= "Frame" then
                return
            end
            local stack = type(debugstack) == "function" and debugstack() or ""
            local owner = "unknown source"
            local sawOwnAddon = false
            for candidate in stack:gmatch("Interface[/\\]AddOns[/\\]([^/\\]+)") do
                if candidate:lower() == tostring(ADDON):lower() then
                    sawOwnAddon = true
                else
                    owner = candidate
                    break
                end
            end
            -- Do not report frames created by this addon's own scanner or
            -- diagnostics. They are not addon UI candidates.
            if owner == "unknown source" and sawOwnAddon then return end
            local key = tostring(owner) .. "|" .. tostring(frameType) .. "|" .. tostring(template)
            if watchSeen[key] then return end
            watchSeen[key] = true
            watchCount = watchCount + 1
            if watchCount <= 100 then
                ns.Print("CreateFrame: addon=" .. owner .. " type=" .. tostring(frameType)
                    .. " name=" .. tostring(frameName or "<anonymous>")
                    .. " template=" .. tostring(template or "<none>"))
                if ns.debug and owner == "unknown source" and stack ~= "" then
                    ns.Print("  stack: " .. tostring(stack):gsub("\n", " | "):sub(1, 220))
                end
            elseif watchCount == 101 then
                ns.Print("CreateFrame watch reached 100 unique entries; further entries are suppressed.")
            end
        end)
        watchInstalled = ok
        if not ok then
            ns.Print("CreateFrame hook could not be installed on this client.")
            return
        end
    end
    ns.captureCreateFrame = true
    ns.Print("CreateFrame watch enabled. Open the missing UI elements; unique creation signatures will be logged.")
end
