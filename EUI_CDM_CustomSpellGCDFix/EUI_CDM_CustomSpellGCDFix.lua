local addonName = ...

local moduleNS = EllesmereUI
    and EllesmereUI._ModuleNS
    and EllesmereUI._ModuleNS["EllesmereUICooldownManager"]

if not (moduleNS
    and type(moduleNS._presetFrames) == "table"
    and type(moduleNS._MarkPresetCdDirty) == "function") then
    print("|cffff5555" .. addonName .. ": EllesmereUI CDM internals were not found; fix disabled.|r")
    return
end

if not (C_Spell and type(C_Spell.GetSpellCooldownDuration) == "function") then
    print("|cffff5555" .. addonName .. ": C_Spell.GetSpellCooldownDuration is unavailable; fix disabled.|r")
    return
end

local getSpellCooldownDuration = C_Spell.GetSpellCooldownDuration

local function GetFrameSpellID(frame)
    local sid = frame._cachedPresetSID
    if sid then
        return sid
    end

    local key = frame._pfKey
    local idText = type(key) == "string" and key:match(":(%d+)$")
    sid = idText and tonumber(idText) or nil
    if sid then
        frame._cachedPresetSID = sid
    end
    return sid
end

local function IsVisibleCustomSpellFrame(frame)
    return frame
        and frame._isCustomSpellFrame
        and not frame._isCustomBuffFrame
        and frame.IsShown
        and frame:IsShown()
        and frame._cooldown
end

local function RefreshFrame(frame)
    local sid = GetFrameSpellID(frame)
    if not sid then
        return false
    end

    -- Pass the complete DurationObject directly to the native Cooldown widget.
    -- Do not inspect its state: those values may be secret in combat.
    -- The no-argument form includes the GCD.
    local ok, durationObject = pcall(getSpellCooldownDuration, sid)
    if not ok then
        return false
    end

    local cooldown = frame._cooldown
    if durationObject then
        local pushOK = pcall(
            cooldown.SetCooldownFromDurationObject,
            cooldown,
            durationObject,
            true
        )
        if not pushOK then
            return false
        end
    else
        local clearOK = pcall(cooldown.Clear, cooldown)
        if not clearOK then
            return false
        end
    end

    -- Keep Ellesmere's own processor synchronized for related frame state.
    frame._cdPushArm = true
    return true
end

local function OnSpellCooldownUpdate()
    local anyRefreshed = false

    -- Any spell can start or end the player's GCD, so do not filter by spell ID.
    for _, frame in pairs(moduleNS._presetFrames) do
        if IsVisibleCustomSpellFrame(frame) and RefreshFrame(frame) then
            anyRefreshed = true
        end
    end

    if anyRefreshed then
        moduleNS._MarkPresetCdDirty()
    end
end

local listener = CreateFrame("Frame")
listener:RegisterEvent("SPELL_UPDATE_COOLDOWN")
listener:SetScript("OnEvent", OnSpellCooldownUpdate)
