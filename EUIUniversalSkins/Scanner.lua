local ADDON, ns = ...

local styled = setmetatable({}, { __mode = "k" })
local panelStyled = setmetatable({}, { __mode = "k" })
local hooked = setmetatable({}, { __mode = "k" })
local rootOptions = setmetatable({}, { __mode = "k" })
local pending = setmetatable({}, { __mode = "k" })
local queued = setmetatable({}, { __mode = "k" })
local aceCheckboxBorders = setmetatable({}, { __mode = "k" })
local statusBarHooks = setmetatable({}, { __mode = "k" })
local iconStyles = setmetatable({}, { __mode = "k" })
local aceWidgetsSeen = setmetatable({}, { __mode = "k" })

local function Count(key)
    ns.stats[key] = (ns.stats[key] or 0) + 1
end

local function IsExcluded(frame, kind)
    return kind == "GameTooltip"
        or kind == "PlayerModel"
        or kind == "Model"
        or kind == "ModelScene"
        or kind == "WorldFrame"
end

local function HookScript(frame, scriptName, callback)
    if not frame or type(frame.HookScript) ~= "function" then return end
    local scripts = hooked[frame]
    if not scripts then
        scripts = {}
        hooked[frame] = scripts
    end
    if scripts[scriptName] then return end
    if frame.HasScript and not frame:HasScript(scriptName) then return end
    local ok = pcall(frame.HookScript, frame, scriptName, callback)
    if ok then scripts[scriptName] = true end
end

local function FadeTexture(texture)
    if not texture or type(texture.SetAlpha) ~= "function" then return end
    if not texture.GetAlpha or texture:GetAlpha() ~= 0 then texture:SetAlpha(0) end
    local scripts = hooked[texture]
    if not scripts then
        scripts = {}
        hooked[texture] = scripts
    end
    if scripts.SetAlpha then return end
    scripts.SetAlpha = true
    if hooksecurefunc then
        pcall(hooksecurefunc, texture, "SetAlpha", function(self, alpha)
            if alpha ~= 0 then self:SetAlpha(0) end
        end)
    end
end
ns.FadeTexture = FadeTexture

local function GetTexture(value)
    if ns.IsObject(value) and value.GetObjectType and value:GetObjectType() == "Texture" then
        return value
    end
end

local function GetButtonLabel(frame)
    local label = frame.GetFontString and frame:GetFontString()
    if ns.IsObject(label) and label:GetObjectType() == "FontString" then return label end
    for _, key in ipairs({ "Text", "text", "Label", "label" }) do
        local candidate = frame[key]
        if ns.IsObject(candidate) and candidate.GetObjectType and candidate:GetObjectType() == "FontString" then
            return candidate
        end
    end
end

local function StyleButton(frame, S)
    local widget = frame.obj
    local isAceButton = widget and widget.frame == frame and widget.type == "Button"
    local label = GetButtonLabel(frame)
    local icon = GetTexture(frame.Icon) or GetTexture(frame.icon)

    if isAceButton and label and S.Button then
        S.Button(frame, { "Text", "text" })
        if S.StateButtonLabel then S.StateButtonLabel(frame) end
        Count("buttons")
        return
    end

    -- Item, spell and icon buttons need their artwork preserved. SquareIcon is
    -- a deliberately narrow treatment: it only changes the supplied icon.
    if icon then
        if S.SquareIcon and iconStyles[frame] ~= icon then
            local square = frame.GetWidth and frame.GetHeight and frame:GetWidth() == frame:GetHeight()
            ns.Safe("square icon", S.SquareIcon, icon, square and frame or nil)
            iconStyles[frame] = icon
        end
        return
    end
    if frame.ItemIcon or frame.IconTexture or frame.itemId or frame.itemID
        or frame.itemGUID or frame.spellId or frame.spellID then
        return
    end

    if label and S.Button then
        S.Button(frame)
        if S.StateButtonLabel then S.StateButtonLabel(frame) end
        Count("buttons")
        return
    end

    local name = frame.GetName and frame:GetName()
    local lowerName = type(name) == "string" and name:lower() or ""
    if lowerName:find("closebutton", 1, true) and S.CloseButton then
        S.CloseButton(frame)
        Count("buttons")
        return
    end

    local normal = frame.GetNormalTexture and frame:GetNormalTexture()
    local path = normal and normal.GetTexture and normal:GetTexture()
    if type(path) == "string" then
        if path:find("UI%-Panel%-MinimizeButton") or path:find("UI%-Panel%-CloseButton") then
            if S.CloseButton then S.CloseButton(frame); Count("buttons") end
        elseif S.PageButton then
            local direction
            if lowerName:find("prev", 1, true) or lowerName:find("previous", 1, true) then direction = "<"
            elseif lowerName:find("next", 1, true) then direction = ">" end
            if direction then S.PageButton(frame, direction); Count("buttons") end
        end
    end
end

local function StyleAceCheckbox(frame, widget, S)
    local bg, check = widget.checkbg, widget.check
    if not ns.IsSkinTarget(bg) or not ns.IsSkinTarget(check)
        or bg:GetObjectType() ~= "Texture" or check:GetObjectType() ~= "Texture" then return end
    if bg.SetColorTexture then bg:SetColorTexture(0.02, 0.02, 0.02, 1) end

    if not aceCheckboxBorders[frame] and frame.CreateTexture then
        aceCheckboxBorders[frame] = true
        for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
            local edge = frame:CreateTexture(nil, "ARTWORK")
            edge:SetColorTexture(0.25, 0.25, 0.25, 1)
            if side == "TOP" or side == "BOTTOM" then
                edge:SetPoint(side .. "LEFT", bg, side .. "LEFT")
                edge:SetPoint(side .. "RIGHT", bg, side .. "RIGHT")
                edge:SetHeight(1)
            else
                edge:SetPoint("TOP" .. side, bg, "TOP" .. side)
                edge:SetPoint("BOTTOM" .. side, bg, "BOTTOM" .. side)
                edge:SetWidth(1)
            end
        end
    end

    local function UpdateCheckColor()
        if not check or not check.SetVertexColor then return end
        if widget.disabled then
            check:SetVertexColor(0.5, 0.5, 0.5, 1)
        elseif S.GetAccentColor then
            local r, g, b = S.GetAccentColor()
            check:SetVertexColor(r, g, b, 1)
        end
    end
    UpdateCheckColor()
    ns.Hook(widget, "SetType", UpdateCheckColor)
    ns.Hook(widget, "SetDisabled", UpdateCheckColor)
end

local function StyleAceWidget(frame, S)
    local widget = frame.obj
    if not widget or widget.frame ~= frame then return end

    if widget.type == "Dropdown" then
        if ns.IsSkinTarget(widget.dropdown) and S.Dropdown then
            S.Dropdown(widget.dropdown)
            if widget.button and widget.button.GetRegions then
                local regions = { widget.button:GetRegions() }
                for i = 1, #regions do
                    local region = regions[i]
                    if region and region.GetObjectType and region:GetObjectType() == "Texture" then
                        FadeTexture(region)
                    end
                end
            end
        end
    elseif widget.type == "CheckBox" then
        StyleAceCheckbox(frame, widget, S)
        if ns.IsObject(widget.text) and widget.text:GetObjectType() == "FontString" and S.Font then
            ns.Safe("AceGUI checkbox label", S.Font, widget.text)
        end
    elseif widget.type == "TabGroup" and S.Tab then
        for _, tab in pairs(widget.tabs or {}) do
            if ns.IsSkinTarget(tab) then
                S.Tab(tab)
                if S.SetTabSelection then S.SetTabSelection(tab, tab.selected and true or false) end
            end
        end
        ns.Hook(widget, "SelectTab", function()
            for _, tab in pairs(widget.tabs or {}) do
                if ns.IsSkinTarget(tab) and S.SetTabSelection then
                    S.SetTabSelection(tab, tab.selected and true or false)
                end
            end
        end)
    end

    if ns.IsSkinTarget(widget.closebtn) then
        if S.Button then S.Button(widget.closebtn) end
        if S.StateButtonLabel then S.StateButtonLabel(widget.closebtn) end
    end
end

local function StyleGenericPanel(frame, S)
    if panelStyled[frame] or not frame.GetBackdrop or not frame.SetBackdrop or not S.Panel then return end
    local backdrop = frame:GetBackdrop()
    if type(backdrop) ~= "table" or not backdrop.bgFile then return end
    if type(backdrop.bgFile) == "string" and backdrop.bgFile:lower():find("icons", 1, true) then return end
    if frame.icon or frame.Icon or frame.Portrait or frame.portrait then return end

    panelStyled[frame] = true
    local keep = {}
    if frame.GetRegions then
        local regions = { frame:GetRegions() }
        for i = 1, #regions do
            local region = regions[i]
            if region and region.GetTexture and region.GetDrawLayer then
                local layer = region:GetDrawLayer()
                if layer ~= "BACKGROUND" and layer ~= "BORDER" then
                    keep[region] = region:GetAlpha()
                end
            end
        end
    end

    local ok = ns.Safe("generic panel", S.Panel, frame)
    if not ok then
        panelStyled[frame] = nil
        return
    end
    for region, alpha in pairs(keep) do
        if region.SetAlpha then region:SetAlpha(alpha) end
    end
    ns.Safe("clear generic backdrop", frame.SetBackdrop, frame, nil)
    ns.Hook(frame, "SetBackdrop", function(owner, value)
        if value then ns.Safe("clear refreshed backdrop", owner.SetBackdrop, owner, nil) end
    end)
    Count("panels")
end

local function StyleStatusBar(frame, S)
    if not S.ApplyBarFill then return end
    local ok = ns.Safe("status bar", S.ApplyBarFill, frame)
    if not ok or statusBarHooks[frame] then return end
    statusBarHooks[frame] = true
    local painting = false
    ns.Hook(frame, "SetStatusBarColor", function()
        if painting then return end
        painting = true
        ns.Safe("status bar refresh", S.ApplyBarFill, frame)
        painting = false
    end)
end

local function StyleFrame(frame, kind, options)
    local S = ns.skin
    if not S or not ns.IsSkinTarget(frame) then return end

    local firstTime = not styled[frame]
    if firstTime then
        styled[frame] = true
        Count("framesVisited")
    end

    -- EUI's primitives are idempotent, so apply them on each root refresh.
    -- This also catches controls and widget references attached after first show.
    if kind == "CheckButton" and S.Checkbox then
        ns.Safe("checkbox", S.Checkbox, frame)
        if firstTime then Count("checkboxes") end
    elseif kind == "EditBox" and S.EditBox then
        ns.Safe("edit box", S.EditBox, frame)
        if firstTime then Count("editBoxes") end
    elseif kind == "DropdownButton" and S.Dropdown then
        ns.Safe("dropdown", S.Dropdown, frame)
        if firstTime then Count("dropdowns") end
    elseif kind == "StatusBar" and S.ApplyBarFill then
        StyleStatusBar(frame, S)
        if firstTime then Count("statusBars") end
    elseif kind == "Button" then
        ns.Safe("button", StyleButton, frame, S)
    elseif kind == "Slider" and S.ScrollBar and frame.GetThumbTexture
        and frame.GetOrientation and frame:GetOrientation() == "VERTICAL" then
        local name = frame.GetName and frame:GetName() or ""
        local parent = frame.GetParent and frame:GetParent()
        local isScrollBar = name:lower():find("scroll", 1, true) ~= nil
            or (parent and (parent.ScrollBar == frame or parent.scrollbar == frame))
        if isScrollBar then
            ns.Safe("vertical scrollbar", S.ScrollBar, frame)
            if firstTime then Count("scrollBars") end
        end
    end

    if S.FadeNineSlice and frame.NineSlice then ns.Safe("nine slice", S.FadeNineSlice, frame.NineSlice) end
    if S.Inset and frame.Inset and ns.IsSkinTarget(frame.Inset) then ns.Safe("inset", S.Inset, frame.Inset) end

    if S.ScrollBar then
        local scrollBar = frame.ScrollBar or frame.scrollbar
        if ns.IsSkinTarget(scrollBar) then
            ns.Safe("child scrollbar", S.ScrollBar, scrollBar)
            if not styled[scrollBar] then
                styled[scrollBar] = true
                if firstTime then Count("scrollBars") end
            end
        end
    end

    if frame.CloseButton and S.CloseButton and ns.IsSkinTarget(frame.CloseButton) then
        ns.Safe("close button", S.CloseButton, frame.CloseButton)
    elseif frame.closeButton and S.CloseButton and ns.IsSkinTarget(frame.closeButton) then
        ns.Safe("close button", S.CloseButton, frame.closeButton)
    end

    if kind == "Frame" then
        StyleGenericPanel(frame, S)
    end
    if frame.obj and frame.obj.frame == frame then
        ns.Safe("AceGUI widget", StyleAceWidget, frame, S)
        if not aceWidgetsSeen[frame.obj] then
            aceWidgetsSeen[frame.obj] = true
            Count("aceWidgets")
        end
    end

    -- FontStrings are safe to re-check; S.Font is itself idempotent and keeps
    -- the current size and text color.
    if frame.GetRegions and S.Font then
        local regions = { frame:GetRegions() }
        for i = 1, #regions do
            local region = regions[i]
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                ns.Safe("font string", S.Font, region)
                if firstTime then Count("fontStrings") end
            end
        end
    end

    if S.SortHeaderBar and frame.HeaderContainer then ns.Safe("sort header bar", S.SortHeaderBar, frame) end

    -- Re-scan on container show to catch pooled/lazy controls. Scroll frames
    -- also get a refresh after scrolling, when virtualized rows are recycled.
    if firstTime and frame.GetNumChildren and (kind == "Frame" or kind == "ScrollFrame") then
        HookScript(frame, "OnShow", function()
            ns.QueueScan(frame, rootOptions[frame])
        end)
        if kind == "ScrollFrame" then
            HookScript(frame, "OnVerticalScroll", function()
                ns.QueueScan(frame, rootOptions[frame])
            end)
        end
    end
end

local function Walk(frame, depth, options)
    if depth > ((options and options.maxDepth) or 14) then return end
    if not ns.IsSkinTarget(frame) then return end

    local kind = frame:GetObjectType()
    if IsExcluded(frame, kind) then return end

    StyleFrame(frame, kind, options)

    if frame.GetChildren and frame.GetNumChildren and frame:GetNumChildren() > 0 then
        local children = { frame:GetChildren() }
        for i = 1, #children do
            Walk(children[i], depth + 1, options)
        end
    end
end


local function NormalizeAddonName(value)
    return type(value) == "string" and value:lower():gsub("[^%w]", "") or ""
end

local ignoredAddonPrefixes = {
    "blizzard",
    "ellesmereui",
    "euiaddonskins",
    "euiuniversalskins",
}

local function IsIgnoredAddonName(addonName)
    local normalized = NormalizeAddonName(addonName)
    for _, prefix in ipairs(ignoredAddonPrefixes) do
        if normalized:sub(1, #prefix) == prefix then return true end
    end
    return normalized == ""
end

local function GetLoadedAddonNames(onlyAddon)
    if onlyAddon then
        if ns.IsAddonLoaded(onlyAddon) and not IsIgnoredAddonName(onlyAddon) then
            return { onlyAddon }
        end
        return {}
    end

    local names = {}
    local countFn = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
    local infoFn = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
    if type(countFn) ~= "function" or type(infoFn) ~= "function" then return names end

    local okCount, count = pcall(countFn)
    if not okCount or type(count) ~= "number" then return names end
    for index = 1, count do
        local okInfo, addonName = pcall(infoFn, index)
        if okInfo and type(addonName) == "string"
            and ns.IsAddonLoaded(addonName) and not IsIgnoredAddonName(addonName) then
            names[#names + 1] = addonName
        end
    end
    table.sort(names, function(a, b) return #NormalizeAddonName(a) > #NormalizeAddonName(b) end)
    return names
end

function ns.AutoDiscoverNamedRoots(onlyAddon)
    if not ns.IsAutoDiscoverEnabled() or type(EnumerateFrames) ~= "function" or not UIParent then return 0 end
    local addonNames = GetLoadedAddonNames(onlyAddon)
    if #addonNames == 0 then return 0 end

    local discovered = 0
    local frame = EnumerateFrames()
    while frame do
        if ns.IsSkinTarget(frame) and frame.GetParent and frame:GetParent() == UIParent
            and frame.GetName and frame.GetObjectType then
            local frameName = NormalizeAddonName(frame:GetName())
            local kind = frame:GetObjectType()
            if frameName ~= "" and (kind == "Frame" or kind == "ScrollFrame") then
                local matchedAddon
                for _, addonName in ipairs(addonNames) do
                    local prefix = NormalizeAddonName(addonName)
                    if frameName:sub(1, #prefix) == prefix then
                        matchedAddon = addonName
                        break
                    end
                end
                if matchedAddon and not ns.roots[frame] then
                    ns.TrackRoot(frame, "Auto: " .. matchedAddon)
                    ns.stats.autoDiscoveredRoots = ns.stats.autoDiscoveredRoots + 1
                    discovered = discovered + 1
                    if ns.debug then
                        ns.Print("auto-discovered " .. tostring(frame:GetName()) .. " (" .. matchedAddon .. ")")
                    end
                elseif matchedAddon then
                    ns.TrackRoot(frame)
                end
            end
        end
        frame = EnumerateFrames(frame)
    end
    if discovered > 0 and ns.debug then
        ns.Print("auto-discovery added " .. discovered .. " named addon root(s).")
    end
    return discovered
end

function ns.TrackRoot(frame, label, options)
    if not ns.IsSkinTarget(frame) then return end
    local existing = ns.roots[frame]
    if not existing then
        ns.roots[frame] = { label = label or "unknown", options = options }
        ns.stats.roots = ns.stats.roots + 1
    else
        if label then existing.label = label end
        if options then existing.options = options end
    end
    ns.QueueScan(frame, options)
end

function ns.ScanTree(root, options)
    if not ns.IsSkinTarget(root) or not ns.skin or not ns.IsEnabled() then return false end
    if InCombatLockdown and InCombatLockdown() then
        pending[root] = options or rootOptions[root]
        return false
    end

    if options then rootOptions[root] = options end
    options = options or rootOptions[root] or {}

    if options.rootStyle and not styled[root] then
        local S = ns.skin
        if options.rootStyle == "shell" and S.Shell then
            ns.Safe("root shell", S.Shell, root, options.shellOptions)
            Count("panels")
        elseif options.rootStyle == "panel" and S.Panel then
            ns.Safe("root panel", S.Panel, root, options.panelOptions)
            Count("panels")
        end
        styled[root] = true
        if root.SetBackdrop then ns.Safe("clear root backdrop", root.SetBackdrop, root, nil) end
    end

    Walk(root, 0, options)
    return true
end

function ns.QueueScan(root, options)
    if not ns.IsSkinTarget(root) then return end
    if options then rootOptions[root] = options end
    if InCombatLockdown and InCombatLockdown() then
        pending[root] = options or rootOptions[root]
        return
    end
    if queued[root] then return end
    queued[root] = true
    ns.After(0, function()
        queued[root] = nil
        if ns.IsEnabled() then ns.ScanTree(root, rootOptions[root]) end
    end)
end

function ns.FlushPendingScans()
    if InCombatLockdown and InCombatLockdown() then return end
    local batch = pending
    pending = setmetatable({}, { __mode = "k" })
    for root, options in pairs(batch) do
        ns.QueueScan(root, options)
    end
end

function ns.ScanTrackedRoots()
    local count = 0
    for root, record in pairs(ns.roots) do
        if ns.IsSkinTarget(root) then
            ns.ScanTree(root, record.options)
            count = count + 1
        end
    end
    ns.Print("rescanned " .. count .. " known roots; visited " .. ns.stats.framesVisited .. " frames overall.")
end

function ns.FadeDialogArt(frame)
    if not frame then return end
    if frame.Background then FadeTexture(frame.Background) end
    if frame.Border then FadeTexture(frame.Border) end
end
