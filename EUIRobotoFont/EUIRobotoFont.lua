-------------------------------------------------------------------------------
-- EUIRobotoFont
-- Registers a static Roboto Regular TTF with LibSharedMedia so EllesmereUI
-- can offer it in its global and per-module font dropdowns.
-------------------------------------------------------------------------------

local ADDON_NAME = ...
local FONT_KEY = "Roboto"
local FONT_PATH = "Interface\\AddOns\\EUIRobotoFont\\Fonts\\Roboto-Regular.ttf"

local function RegisterRoboto()
    local libStub = _G.LibStub
    local LSM = libStub and libStub("LibSharedMedia-3.0", true)

    if not LSM then
        print("|cffff5555EUI Roboto Font:|r LibSharedMedia-3.0 was not found. Is EllesmereUI loaded?")
        return
    end

    local mediaType = LSM.MediaType and LSM.MediaType.FONT or "font"
    local existingPath = LSM:Fetch(mediaType, FONT_KEY, true)

    if existingPath then
        if existingPath ~= FONT_PATH then
            -- Do not silently replace another addon's Roboto registration.
            -- Register under a distinct label so both fonts remain available.
            local alternateKey = "Roboto (EUI)"
            local alternatePath = LSM:Fetch(mediaType, alternateKey, true)
            if not alternatePath then
                LSM:Register(mediaType, alternateKey, FONT_PATH)
                print("|cff66ccffEUI Roboto Font:|r 'Roboto' was already registered by another addon. Added as 'Roboto (EUI)'.")
            end
        end
    else
        LSM:Register(mediaType, FONT_KEY, FONT_PATH)
    end

    -- EUI listens for LibSharedMedia_Registered and updates its path map/cache.
    -- This explicit invalidation is a harmless safety net for compatible builds.
    if _G.EllesmereUI and type(_G.EllesmereUI.InvalidateFontCache) == "function" then
        _G.EllesmereUI.InvalidateFontCache()
    end
end

RegisterRoboto()
