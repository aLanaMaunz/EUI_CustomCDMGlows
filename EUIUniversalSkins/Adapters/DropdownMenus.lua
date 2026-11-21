local ADDON, ns = ...

local function GetLibrary(name)
    if not LibStub then return nil end
    local ok, lib = pcall(LibStub, name, true)
    return ok and lib or nil
end

local function Install()
    local S = ns.skin
    if not S or not S.Panel then return end

    local styled = setmetatable({}, { __mode = "k" })
    local function StyleNamedDropDownLists()
        -- Match active list frames by their common global name rather than
        -- assuming one particular dropdown library's prefix.
        for globalName, list in pairs(_G) do
            if type(globalName) == "string"
                and globalName:match("DropDownList%d+$")
                and ns.IsSkinTarget(list)
                and list:GetObjectType() == "Frame" then
                local backdrop = _G[globalName .. "Backdrop"] or _G[globalName .. "MenuBackdrop"]
                    or list.Backdrop or list.MenuBackdrop
                if ns.IsSkinTarget(backdrop) and backdrop.GetObjectType and backdrop:GetObjectType() == "Frame" and not styled[backdrop] then
                    styled[backdrop] = true
                    ns.Safe("dropdown menu panel", S.Panel, backdrop)
                    if backdrop.SetBackdrop then ns.Safe("clear dropdown backdrop", backdrop.SetBackdrop, backdrop, nil) end
                elseif ns.IsSkinTarget(backdrop) and backdrop.GetObjectType and backdrop:GetObjectType() == "Texture" then
                    -- Some branches expose the backdrop as a texture region.
                    ns.FadeTexture(backdrop)
                    if not styled[list] then
                        styled[list] = true
                        ns.Safe("dropdown list panel", S.Panel, list)
                    end
                elseif not backdrop and not styled[list] then
                    -- Some library versions put the backdrop directly on the list.
                    styled[list] = true
                    ns.Safe("dropdown list panel", S.Panel, list)
                    if list.SetBackdrop then ns.Safe("clear dropdown list backdrop", list.SetBackdrop, list, nil) end
                end
                if list.NineSlice and S.FadeNineSlice then S.FadeNineSlice(list.NineSlice) end
            end
        end
    end

    local refreshQueued = false
    local function Refresh()
        if refreshQueued then return end
        refreshQueued = true
        ns.After(0, function()
            refreshQueued = false
            StyleNamedDropDownLists()
        end)
    end

    ns.Hook(_G, "ToggleDropDownMenu", Refresh)
    ns.Hook(_G, "UIDropDownMenu_AddButton", Refresh)
    ns.Hook(_G, "UIDropDownMenu_CreateFrames", Refresh)

    local function InstallLibraryHooks()
        for _, libraryName in ipairs({ "LibUIDropDownMenu-4.0", "LibUIDropDownMenuQuestie-4.0" }) do
            local lib = GetLibrary(libraryName)
            if lib then
                ns.Hook(lib, "ToggleDropDownMenu", Refresh)
                ns.Hook(lib, "UIDropDownMenu_AddButton", Refresh)
                ns.Hook(lib, "UIDropDownMenu_CreateFrames", Refresh)
            end
        end
    end
    InstallLibraryHooks()
    ns.OnLibraryRegistered(InstallLibraryHooks)

    StyleNamedDropDownLists()
    ns.Print("dropdown menu adapter installed.")
    return true
end

ns.RegisterAdapter("DropdownMenus", "Blizzard and LibUIDropDownMenu lists", {}, Install)
