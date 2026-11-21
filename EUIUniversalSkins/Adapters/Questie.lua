local ADDON, ns = ...

local styledDialogs = setmetatable({}, { __mode = "k" })
local watchedCreateFrame = false
local hookedPopupStacks = setmetatable({}, { __mode = "k" })
local scanQueued = false

local function IsType(object, expected)
    return ns.IsObject(object) and object.GetObjectType and object:GetObjectType() == expected
end

-- AddonDialog deliberately stores its API in the addon's private namespace:
--   local _, addon = ...; addon.Dialog = Dialogs
-- That table is not exported as _G.Questie.Dialog, so discovering the reusable
-- frame by its documented object shape is the safe external integration path.
local function IsQuestieAddonDialog(frame)
    return IsType(frame, "Frame")
        and frame.GetParent and frame:GetParent() == UIParent
        and IsType(frame.Text, "FontString")
        and IsType(frame.Button1, "Button")
        and IsType(frame.Button2, "Button")
        and IsType(frame.EditBox, "EditBox")
        and IsType(frame.Background, "Texture")
        and IsType(frame.Border, "Texture")
        and IsType(frame.AlertIcon, "Texture")
        and type(frame.Resize) == "function"
        and type(frame.Choose) == "function"
        and type(frame.GetEditBox) == "function"
end

local function SkinDialogFrame(frame)
    if not ns.IsSkinTarget(frame) or styledDialogs[frame] then return false end

    local S = ns.skin
    if not S then return false end

    -- These two named regions are the native dialog's background and border.
    -- Keep AlertIcon and all foreground controls intact.
    ns.FadeDialogArt(frame)

    if S.Panel then
        local keep = {}
        if frame.GetRegions then
            local regions = { frame:GetRegions() }
            for i = 1, #regions do
                local region = regions[i]
                if region and region.GetTexture and region.GetDrawLayer then
                    local layer = region:GetDrawLayer()
                    if layer ~= "BACKGROUND" and layer ~= "BORDER" then
                        keep[region] = region.GetAlpha and region:GetAlpha() or 1
                    end
                end
            end
        end

        local ok = ns.Safe("Questie dialog panel", S.Panel, frame)
        if not ok then return false end
        for region, alpha in pairs(keep) do
            if region.SetAlpha then
                ns.Safe("restore Questie foreground art", region.SetAlpha, region, alpha)
            end
        end
        if frame.SetBackdrop then
            ns.Safe("clear Questie backdrop", frame.SetBackdrop, frame, nil)
        end
    end

    styledDialogs[frame] = true
    ns.TrackRoot(frame, "Questie AddonDialog")
    ns.stats.questieDialogs = ns.stats.questieDialogs + 1

    -- The dialog object is reused for subsequent confirmations. Re-scan its
    -- owned controls on every show so state/layout changes and late regions are
    -- picked up without replacing Questie's own scripts.
    if frame.HookScript then
        pcall(frame.HookScript, frame, "OnShow", function(self)
            ns.QueueScan(self)
        end)
    end

    if ns.debug then
        ns.Print("skinned Questie AddonDialog: " .. tostring(frame))
    end
    return true
end

local function ScanForQuestieDialogs()
    scanQueued = false
    if not ns.IsEnabled() or not ns.activated then return 0 end

    local found, matched = 0, 0
    if type(EnumerateFrames) == "function" then
        local frame = EnumerateFrames()
        while frame do
            if IsQuestieAddonDialog(frame) then
                matched = matched + 1
                if SkinDialogFrame(frame) then found = found + 1 end
            end
            frame = EnumerateFrames(frame)
        end
    elseif UIParent and UIParent.GetChildren then
        -- Compatibility fallback for clients without EnumerateFrames().
        local function Walk(parent, depth)
            if depth > 20 or not parent or not parent.GetChildren then return end
            local children = { parent:GetChildren() }
            for i = 1, #children do
                local child = children[i]
                if IsQuestieAddonDialog(child) then
                    matched = matched + 1
                    if SkinDialogFrame(child) then found = found + 1 end
                end
                Walk(child, depth + 1)
            end
        end
        Walk(UIParent, 0)
    end

    ns.questieDialogMatches = matched
    return matched, found
end
ns.ScanQuestieDialogs = ScanForQuestieDialogs

local function QueueQuestieDialogScan()
    if scanQueued then return end
    scanQueued = true
    ns.After(0, ScanForQuestieDialogs)
end

local function InstallPopupStackHook()
    if not LibStub then return false end
    local ok, popupStack = pcall(LibStub, "LibPopupStack-1.0", true)
    if not ok or type(popupStack) ~= "table" or type(popupStack.Register) ~= "function" then
        return false
    end
    if hookedPopupStacks[popupStack] then return true end

    -- Questie's private AddonDialog calls PopupStack:Register(frame) from its
    -- own OnShow handler. The shared library is therefore the cleanest public
    -- interception point: it hands us the exact frame without exposing or
    -- replacing Questie's private namespace or any of its scripts.
    local hooked = ns.Hook(popupStack, "Register", function(_, frame)
        if IsQuestieAddonDialog(frame) then
            SkinDialogFrame(frame)
        end
    end)
    if hooked then hookedPopupStacks[popupStack] = true end
    return hooked
end

local function InstallCreateFrameDiscoveryHook()
    if watchedCreateFrame then return true end
    if type(CreateFrame) ~= "function" or type(hooksecurefunc) ~= "function" then return false end

    -- Fallback for Questie builds where LibPopupStack is not exposed through
    -- LibStub. The hook schedules a structural scan only for the same narrow
    -- anonymous top-level BackdropTemplate frame signature.
    local ok = pcall(hooksecurefunc, _G, "CreateFrame", function(frameType, frameName, parent, template)
        if frameType == "Frame" and parent == UIParent
            and type(template) == "string" and template:find("BackdropTemplate", 1, true) then
            QueueQuestieDialogScan()
        end
    end)

    watchedCreateFrame = ok
    return ok
end

local function Install()
    -- Prefer a public API if a Questie build happens to expose one. The Forever
    -- AddonDialog implementation currently uses a private addon namespace, so
    -- the structural discovery hook below is the normal path.
    local questie = _G.Questie
    local dialog = type(questie) == "table" and questie.Dialog or nil
    if type(dialog) == "table" and type(dialog.Show) == "function"
        and type(dialog.FindVisible) == "function" then
        ns.Hook(dialog, "Show", function(first, second)
            local key = type(first) == "string" and first or second
            if type(key) == "string" then
                local ok, frame = pcall(dialog.FindVisible, key)
                if ok and frame then SkinDialogFrame(frame) end
            end
        end)
    end

    -- The library callback runs immediately for an already-registered library
    -- and again when LibStub registers a later embedded copy.
    ns.OnLibraryRegistered(InstallPopupStackHook)
    local stackHooked = InstallPopupStackHook()
    local fallbackHooked = stackHooked or InstallCreateFrameDiscoveryHook()
    if not fallbackHooked then
        ns.Print("Questie AddonDialog discovery hooks could not be installed.")
        return false
    end

    -- Catch a dialog that was created before this adapter was installed.
    QueueQuestieDialogScan()
    ns.Print("Questie AddonDialog adapter installed (" .. (stackHooked and "LibPopupStack" or "frame-discovery") .. ").")
    return true
end

ns.RegisterAdapter("QuestieAddonDialog", "Questie AddonDialog", "Questie", Install)
