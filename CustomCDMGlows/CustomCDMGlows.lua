local ADDON_NAME = ...
local SPELL_INPUTS = {
    { key = "frostbolt", name = "Frostbolt" },
    { key = "iceLance", name = "Ice Lance" },
}

local DEFAULTS = {
    enabled = true,
    spells = {
        frostbolt = true,
        iceLance = true,
    },
    spellIDs = {
        frostbolt = "8408",
        iceLance = "1240044",
    },
    auraIDs = {
        frostNova = "122, 865, 6131, 10230",
        frostbite = "12494",
        fingersOfFrost = "400669, 400670",
    },
    conditions = {
        frostNova = true,
        frostbite = true,
        fingersOfFrost = true,
    },
    onlyUsable = true,
    useClassColor = true,
    glowColor = { r = 1.0, g = 0.82, b = 0.24 },
}

local function CopyDefaults(source, target)
    for key, value in pairs(source) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            CopyDefaults(value, target[key])
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

CustomCDMGlowsDB = type(CustomCDMGlowsDB) == "table" and CustomCDMGlowsDB or {}
CopyDefaults(DEFAULTS, CustomCDMGlowsDB)
local DB = CustomCDMGlowsDB

-- IDs are stored as editable strings so comma-separated rank/variant IDs can
-- be entered directly in the options page and survive reloads.
local function ParseIDList(value)
    local text = tostring(value or "")
    if text:match("[^%d,%s]") then return {}, false end
    if text:match("^%s*,") or text:match(",%s*,") or text:match(",%s*$") then
        return {}, false
    end

    local ids, seen = {}, {}
    for token in text:gmatch("[^,]+") do
        token = token:match("^%s*(.-)%s*$")
        if token ~= "" then
            local id = tonumber(token)
            if not id or id <= 0 or id > 2147483647 or id % 1 ~= 0 then
                return {}, false
            end
            if not seen[id] then
                seen[id] = true
                ids[#ids + 1] = id
            end
        end
    end
    return ids, true
end

local function ParseSingleID(value)
    local ids, valid = ParseIDList(value)
    if not valid or #ids ~= 1 then return nil end
    return ids[1]
end

local function FormatIDList(ids)
    local text = {}
    for i = 1, #ids do text[i] = tostring(ids[i]) end
    return table.concat(text, ", ")
end

local AURA_SPELLS = {
    frostNova = {},
    frostbite = {},
    fingersOfFrost = {},
}
local ALL_AURA_IDS = {}

local function AddSpellIDs(destination, source)
    for i = 1, #source do destination[source[i]] = true end
end

local function RebuildConfiguredAuraIDs()
    wipe(ALL_AURA_IDS)
    for key in pairs(AURA_SPELLS) do
        local ids = ParseIDList(DB.auraIDs[key])
        AURA_SPELLS[key] = ids
        AddSpellIDs(ALL_AURA_IDS, ids)
    end
end

local function GetConfiguredSpells()
    local spells = {}
    for i = 1, #SPELL_INPUTS do
        local input = SPELL_INPUTS[i]
        local spellID = ParseSingleID(DB.spellIDs[input.key])
        if spellID then
            spells[#spells + 1] = {
                key = input.key,
                name = input.name,
                spellID = spellID,
            }
        end
    end
    return spells
end

RebuildConfiguredAuraIDs()

local overlayByIcon = setmetatable({}, { __mode = "k" })
local hookedItems = setmetatable({}, { __mode = "k" })
local hookedViewers = setmetatable({}, { __mode = "k" })
local activeRecords = {}
local lookupScratch = {}

local trackedCooldownIDs = {
    frostNova = {},
    frostbite = {},
    fingersOfFrost = {},
}

local nativeScan = { available = false }
local refreshQueued = false
local scanQueued = false

local function IsSecret(value)
    if type(issecretvalue) ~= "function" then return false end
    local ok, result = pcall(issecretvalue, value)
    return ok and result == true
end

local function IsInCombat()
    return InCombatLockdown and InCombatLockdown() or false
end

local function InfoMatchesAnyAura(info, wanted)
    if not info or IsSecret(info) then return false end

    local fields = { "spellID", "overrideSpellID", "overrideTooltipSpellID" }
    for i = 1, #fields do
        local value
        local ok = pcall(function() value = info[fields[i]] end)
        if ok and not IsSecret(value) and type(value) == "number" and wanted[value] then
            return true
        end
    end

    local singleLinked
    local singleOK = pcall(function() singleLinked = info.linkedSpellID end)
    if singleOK and not IsSecret(singleLinked) and type(singleLinked) == "number" and wanted[singleLinked] then
        return true
    end

    local linked
    local ok = pcall(function() linked = info.linkedSpellIDs end)
    if not ok or IsSecret(linked) or type(linked) ~= "table" then return false end

    for i = 1, #linked do
        local value = linked[i]
        if not IsSecret(value) and type(value) == "number" and wanted[value] then
            return true
        end
    end
    return false
end

local function RebuildNativeAuraMap()
    if IsInCombat() then
        return false
    end

    wipe(trackedCooldownIDs.frostNova)
    wipe(trackedCooldownIDs.frostbite)
    wipe(trackedCooldownIDs.fingersOfFrost)

    local cv = C_CooldownViewer
    local categories = Enum and Enum.CooldownViewerCategory
    if not (cv and cv.GetCooldownViewerCategorySet and cv.GetCooldownViewerCooldownInfo
        and categories and categories.TrackedBuff ~= nil and categories.TrackedBar ~= nil) then
        nativeScan.available = false
        return false
    end

    local scanSucceeded = false
    local categoryList = { categories.TrackedBuff, categories.TrackedBar }
    local wantedByCondition = {}
    for conditionKey, spellIDs in pairs(AURA_SPELLS) do
        local wanted = {}
        AddSpellIDs(wanted, spellIDs)
        wantedByCondition[conditionKey] = wanted
    end

    for categoryIndex = 1, #categoryList do
        local category = categoryList[categoryIndex]
        local okIDs, cooldownIDs = pcall(cv.GetCooldownViewerCategorySet, category, true)
        if okIDs and type(cooldownIDs) == "table" and not IsSecret(cooldownIDs) then
            scanSucceeded = true
            for i = 1, #cooldownIDs do
                local cooldownID = cooldownIDs[i]
                if not IsSecret(cooldownID) and type(cooldownID) == "number" then
                    local okInfo, info = pcall(cv.GetCooldownViewerCooldownInfo, cooldownID)
                    if okInfo and info and InfoMatchesAnyAura(info, ALL_AURA_IDS) then
                        for conditionKey, wanted in pairs(wantedByCondition) do
                            if InfoMatchesAnyAura(info, wanted) then
                                trackedCooldownIDs[conditionKey][cooldownID] = true
                            end
                        end
                    end
                end
            end
        end
    end

    nativeScan.available = scanSucceeded
    return scanSucceeded
end

local function GetNativeViewerState(conditionKey)
    local wantedIDs = trackedCooldownIDs[conditionKey]
    if not nativeScan.available then return nil end
    if not wantedIDs or not next(wantedIDs) then return false end

    local viewerNames = { "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
    local foundItem = false
    local sawReadableFalse = false
    local sawUnknown = false

    for viewerIndex = 1, #viewerNames do
        local viewer = _G[viewerNames[viewerIndex]]
        local shown = viewer and viewer.IsShown and viewer:IsShown()
        local pool = shown and viewer.itemFramePool
        if pool and pool.EnumerateActive then
            local okPool, activeFound = pcall(function()
                for item in pool:EnumerateActive() do
                    local okID, cooldownID = pcall(item.GetCooldownID, item)
                    if okID and not IsSecret(cooldownID) and type(cooldownID) == "number"
                        and wantedIDs[cooldownID] then
                        foundItem = true
                        local active = item.isActive
                        if IsSecret(active) then
                            sawUnknown = true
                        elseif active == true then
                            return true
                        elseif active == false then
                            sawReadableFalse = true
                        else
                            sawUnknown = true
                        end
                    end
                end
                return false
            end)
            if activeFound == true then return true end
            if not okPool then sawUnknown = true end
        end
    end

    if not foundItem or sawUnknown then return nil end
    if sawReadableFalse then return false end
    return nil
end

local function GetSelectedConditionState()
    local selected = false
    local unknown = false

    for key in pairs(AURA_SPELLS) do
        if DB.conditions[key] then
            selected = true
            local state = GetNativeViewerState(key)
            if state == true then return true end
            if state == nil then unknown = true end
        end
    end

    if not selected then return false end
    if unknown then return nil end
    return false
end

local function SpellUsable(spellID)
    if not (C_Spell and C_Spell.GetSpellCooldown and C_Spell.IsSpellUsable) then
        return nil
    end

    local cdOK, cooldownInfo = pcall(C_Spell.GetSpellCooldown, spellID)
    if not cdOK or not cooldownInfo or IsSecret(cooldownInfo) then return nil end

    local readOK, isActive, isOnGCD = pcall(function()
        return cooldownInfo.isActive, cooldownInfo.isOnGCD
    end)
    if not readOK or IsSecret(isActive) or IsSecret(isOnGCD) then return nil end
    if isActive == true and isOnGCD ~= true then return false end

    local usableOK, usable, insufficientPower = pcall(C_Spell.IsSpellUsable, spellID)
    if not usableOK or IsSecret(usable) or IsSecret(insufficientPower) then return nil end
    return usable == true or insufficientPower == true
end

local function ShouldGlow(spellID)
    if not DB.enabled then return false end

    local conditionState = GetSelectedConditionState()
    if conditionState == false then return false end
    if conditionState == nil then return nil end

    if DB.onlyUsable then return SpellUsable(spellID) end
    return true
end

local function GetGlowAPI()
    local eui = EllesmereUI
    return eui and eui.Glows
end

local function GetGlowColor()
    if DB.useClassColor then
        local eui = EllesmereUI
        local class = (eui and eui._playerClass) or select(2, UnitClass("player"))
        if eui and type(eui.GetClassColor) == "function" then
            local ok, color = pcall(eui.GetClassColor, class)
            if ok and color then
                local r, g, b = color.r, color.g, color.b
                if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                    return r, g, b
                end
            end
        end
        local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if classColor then return classColor.r, classColor.g, classColor.b end
    end

    local color = DB.glowColor or DEFAULTS.glowColor
    return color.r or 1, color.g or 0.82, color.b or 0.24
end

local function StartAutocastGlow(overlay)
    local glows = GetGlowAPI()
    if not (glows and type(glows.StartGlow) == "function") then
        return false
    end

    local width, height = overlay:GetSize()
    if type(width) ~= "number" or width < 1 then width = 36 end
    if type(height) ~= "number" or height < 1 then height = width end
    local r, g, b = GetGlowColor()

    local ok = pcall(glows.StartGlow, overlay, 3, width, r, g, b, nil, height)
    if not ok then return false end
    return true
end

local function StopAutocastGlow(overlay)
    if not overlay then return end
    local glows = GetGlowAPI()
    if glows and type(glows.StopGlow) == "function" then
        pcall(glows.StopGlow, overlay)
    elseif glows and type(glows.StopAllGlows) == "function" then
        pcall(glows.StopAllGlows, overlay)
        overlay:SetAlpha(0)
    else
        overlay:SetAlpha(0)
    end
end

local function ApplyRecord(record)
    local state = ShouldGlow(record.spellID)
    if state == nil then return end -- preserve the last known state on unknown data

    if state and not record.glowing then
        if StartAutocastGlow(record.overlay) then record.glowing = true end
    elseif not state and record.glowing then
        StopAutocastGlow(record.overlay)
        record.glowing = false
    elseif not state then
        record.overlay:SetAlpha(0)
    end
end

local function RefreshAll()
    for i = 1, #activeRecords do ApplyRecord(activeRecords[i]) end
end

local function ScheduleRefresh()
    if refreshQueued then return end
    refreshQueued = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            refreshQueued = false
            RefreshAll()
        end)
    else
        refreshQueued = false
        RefreshAll()
    end
end

local function HookViewerItems()
    local viewerNames = { "BuffIconCooldownViewer", "BuffBarCooldownViewer" }
    for viewerIndex = 1, #viewerNames do
        local viewer = _G[viewerNames[viewerIndex]]
        if viewer then
            if not hookedViewers[viewer] and type(viewer.RefreshLayout) == "function" then
                local ok = pcall(hooksecurefunc, viewer, "RefreshLayout", function()
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0, function()
                            HookViewerItems()
                            ScheduleRefresh()
                        end)
                    else
                        HookViewerItems()
                        ScheduleRefresh()
                    end
                end)
                if ok then hookedViewers[viewer] = true end
            end

            local pool = viewer.itemFramePool
            if pool and pool.EnumerateActive then
                pcall(function()
                    for item in pool:EnumerateActive() do
                        if item and not hookedItems[item] and type(item.OnActiveStateChanged) == "function" then
                            local ok = pcall(hooksecurefunc, item, "OnActiveStateChanged", function()
                                ScheduleRefresh()
                            end)
                            if ok then hookedItems[item] = true end
                        end
                    end
                end)
            end
        end
    end
end

local function CreateOverlay(icon)
    local overlay = CreateFrame("Frame", nil, icon)
    overlay:SetAllPoints(icon)
    overlay:SetFrameLevel((icon:GetFrameLevel() or 0) + 20)
    overlay:EnableMouse(false)
    overlay:SetAlpha(0)
    overlay:Show()
    return overlay
end

local function GetIconsForSpell(api, spellID)
    wipe(lookupScratch)
    local ok, icons = pcall(api, spellID, lookupScratch)
    if not ok or type(icons) ~= "table" then return nil end
    return icons
end

local function RebindIcons()
    local eui = EllesmereUI
    local api = eui and eui.GetCDMIconsForSpell
    if type(api) ~= "function" then return false end

    local previousByIcon = {}
    for i = 1, #activeRecords do previousByIcon[activeRecords[i].icon] = activeRecords[i] end

    local nextRecords, seen = {}, {}
    local trackedSpells = GetConfiguredSpells()

    for i = 1, #trackedSpells do
        local entry = trackedSpells[i]
        if DB.spells[entry.key] then
            local icons = GetIconsForSpell(api, entry.spellID)
            if icons then
                for j = 1, #icons do
                    local icon = icons[j]
                    if icon and not seen[icon] then
                        seen[icon] = true
                        local overlay = overlayByIcon[icon]
                        if not overlay then
                            overlay = CreateOverlay(icon)
                            overlayByIcon[icon] = overlay
                        end
                        local previous = previousByIcon[icon]
                        nextRecords[#nextRecords + 1] = {
                            icon = icon,
                            overlay = overlay,
                            spellID = entry.spellID,
                            glowing = previous and previous.glowing or false,
                        }
                    end
                end
            end
        end
    end

    for i = 1, #activeRecords do
        local old = activeRecords[i]
        if not seen[old.icon] then
            StopAutocastGlow(old.overlay)
            old.glowing = false
            old.overlay:Hide()
        end
    end

    for i = 1, #nextRecords do nextRecords[i].overlay:Show() end
    activeRecords = nextRecords
    RefreshAll()
    return true
end

local function RefreshGlowColors()
    for i = 1, #activeRecords do
        local record = activeRecords[i]
        if record.glowing then
            StopAutocastGlow(record.overlay)
            record.glowing = false
        end
    end
    RefreshAll()
end

local function AddIDInputRow(parent, y, labelText, getValue, commitValue)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    row:SetHeight(34)

    local eui = EllesmereUI
    local fontPath = (eui and eui.EXPRESSWAY) or "Fonts\\FRIZQT__.TTF"
    local label = row:CreateFontString(nil, "OVERLAY")
    label:SetFont(fontPath, 12, "")
    label:SetTextColor(0.78, 0.78, 0.78, 1)
    label:SetJustifyH("LEFT")
    label:SetPoint("LEFT", row, "LEFT", 12, 0)

    local parentWidth = parent:GetWidth() or 520
    local labelWidth = math.max(150, math.floor(parentWidth * 0.46))
    label:SetWidth(labelWidth - 18)
    label:SetText(labelText)

    local edit = CreateFrame("EditBox", nil, row)
    edit:SetAutoFocus(false)
    edit:SetHeight(24)
    edit:SetPoint("LEFT", row, "LEFT", labelWidth, 0)
    edit:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    edit:SetFont(fontPath, 12, "")
    edit:SetTextColor(0.95, 0.95, 0.95, 1)
    edit:SetJustifyH("LEFT")
    edit:SetTextInsets(7, 7, 0, 0)
    edit:SetMaxLetters(96)

    local bg = edit:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.035, 0.035, 0.035, 0.95)

    local borderColor = { 0.28, 0.28, 0.28, 0.9 }
    local borders = {}
    for i = 1, 4 do
        borders[i] = edit:CreateTexture(nil, "BORDER")
        borders[i]:SetColorTexture(unpack(borderColor))
    end
    borders[1]:SetPoint("TOPLEFT"); borders[1]:SetPoint("TOPRIGHT"); borders[1]:SetHeight(1)
    borders[2]:SetPoint("BOTTOMLEFT"); borders[2]:SetPoint("BOTTOMRIGHT"); borders[2]:SetHeight(1)
    borders[3]:SetPoint("TOPLEFT"); borders[3]:SetPoint("BOTTOMLEFT"); borders[3]:SetWidth(1)
    borders[4]:SetPoint("TOPRIGHT"); borders[4]:SetPoint("BOTTOMRIGHT"); borders[4]:SetWidth(1)

    local function RestoreValue()
        edit:SetText(getValue() or "")
    end

    local function Commit()
        local current = edit:GetText() or ""
        if current ~= (getValue() or "") then
            commitValue(current)
            RestoreValue()
        end
    end

    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEditFocusLost", Commit)
    edit:SetScript("OnEscapePressed", function(self)
        RestoreValue()
        self:ClearFocus()
    end)
    edit:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
        for i = 1, #borders do borders[i]:SetColorTexture(0.25, 0.65, 1.0, 0.95) end
    end)
    edit:HookScript("OnEditFocusLost", function()
        for i = 1, #borders do borders[i]:SetColorTexture(unpack(borderColor)) end
    end)

    RestoreValue()
    row.editBox = edit
    return 34
end

local function BuildIDInputRow(parent, y, labelText, getValue, commitValue)
    if EllesmereUI and type(EllesmereUI.IsSearchPrebuild) == "function"
        and EllesmereUI.IsSearchPrebuild() then
        return 34
    end
    return AddIDInputRow(parent, y, labelText, getValue, commitValue)
end

local function SaveSpellID(key, text)
    local spellID = ParseSingleID(text)
    if not spellID then return false end
    DB.spellIDs[key] = tostring(spellID)
    RebindIcons()
    return true
end

local function SaveAuraIDs(key, text)
    local ids, valid = ParseIDList(text)
    if not valid then return false end
    DB.auraIDs[key] = FormatIDList(ids)
    RebuildConfiguredAuraIDs()

    if IsInCombat() then
        nativeScan.available = false
        wipe(trackedCooldownIDs.frostNova)
        wipe(trackedCooldownIDs.frostbite)
        wipe(trackedCooldownIDs.fingersOfFrost)
    else
        RebuildNativeAuraMap()
        HookViewerItems()
        ScheduleRefresh()
    end
    return true
end

local function BuildPage(pageName, parent, yOffset)
    local W = EllesmereUI and EllesmereUI.Widgets
    if not W then return 0 end
    local y = yOffset
    local _, h

    _, h = W:SectionHeader(parent, "GENERAL", y); y = y - h
    _, h = W:Toggle(parent, "Enable Custom CDM Glows", y,
        function() return DB.enabled end,
        function(value) DB.enabled = value; RefreshAll() end); y = y - h

    _, h = W:SectionHeader(parent, "CDM SPELLS", y); y = y - h
    _, h = W:Toggle(parent, "Frostbolt", y,
        function() return DB.spells.frostbolt end,
        function(value) DB.spells.frostbolt = value; RebindIcons() end); y = y - h
    _, h = W:Toggle(parent, "Ice Lance", y,
        function() return DB.spells.iceLance end,
        function(value) DB.spells.iceLance = value; RebindIcons() end); y = y - h

    _, h = W:SectionHeader(parent, "CUSTOM SPELL IDS", y); y = y - h
    h = BuildIDInputRow(parent, y, "Frostbolt Spell ID", function() return DB.spellIDs.frostbolt end,
        function(value) return SaveSpellID("frostbolt", value) end); y = y - h
    h = BuildIDInputRow(parent, y, "Ice Lance Spell ID", function() return DB.spellIDs.iceLance end,
        function(value) return SaveSpellID("iceLance", value) end); y = y - h

    _, h = W:SectionHeader(parent, "GLOW CONDITIONS (ANY SELECTED)", y); y = y - h
    _, h = W:Toggle(parent, "Target: Frost Nova", y,
        function() return DB.conditions.frostNova end,
        function(value) DB.conditions.frostNova = value; RefreshAll() end); y = y - h
    _, h = W:Toggle(parent, "Target: Frostbite", y,
        function() return DB.conditions.frostbite end,
        function(value) DB.conditions.frostbite = value; RefreshAll() end); y = y - h
    _, h = W:Toggle(parent, "Player: Fingers of Frost", y,
        function() return DB.conditions.fingersOfFrost end,
        function(value) DB.conditions.fingersOfFrost = value; RefreshAll() end); y = y - h

    _, h = W:SectionHeader(parent, "AURA SPELL IDS", y); y = y - h
    h = BuildIDInputRow(parent, y, "Frost Nova rank IDs", function() return DB.auraIDs.frostNova end,
        function(value) return SaveAuraIDs("frostNova", value) end); y = y - h
    h = BuildIDInputRow(parent, y, "Frostbite aura IDs", function() return DB.auraIDs.frostbite end,
        function(value) return SaveAuraIDs("frostbite", value) end); y = y - h
    h = BuildIDInputRow(parent, y, "Fingers of Frost aura IDs", function() return DB.auraIDs.fingersOfFrost end,
        function(value) return SaveAuraIDs("fingersOfFrost", value) end); y = y - h
    _, h = W:DualRow(parent, y,
        { type = "label", text = "Enter multiple aura IDs separated by commas" },
        { type = "label", text = "Changes save when you press Enter or leave a field" })
    y = y - h

    _, h = W:SectionHeader(parent, "USABILITY", y); y = y - h
    _, h = W:Toggle(parent, "Only glow while the spell is usable", y,
        function() return DB.onlyUsable end,
        function(value) DB.onlyUsable = value; RefreshAll() end); y = y - h

    _, h = W:SectionHeader(parent, "GLOW APPEARANCE", y); y = y - h
    _, h = W:DualRow(parent, y,
        {
            type = "toggle",
            text = "Use current class color",
            getValue = function() return DB.useClassColor end,
            setValue = function(value) DB.useClassColor = value; RefreshGlowColors() end,
        },
        {
            type = "colorpicker",
            text = "Custom Glow Color",
            hasAlpha = false,
            getValue = function()
                local c = DB.glowColor or DEFAULTS.glowColor
                return c.r or 1, c.g or 0.82, c.b or 0.24
            end,
            setValue = function(r, g, b)
                DB.glowColor = { r = r, g = g, b = b }
                DB.useClassColor = false
                RefreshGlowColors()
                if EllesmereUI and EllesmereUI.RefreshPage then EllesmereUI:RefreshPage() end
            end,
        })
    y = y - h

    return math.abs(y)
end

local function RegisterPlugin()
    local eui = EllesmereUI
    if not (eui and type(eui.RegisterPlugin) == "function") then return false end
    if eui.IsPluginRegistered and eui.IsPluginRegistered(ADDON_NAME) then return true end

    return eui.RegisterPlugin(ADDON_NAME, {
        label = "Custom CDM Glows",
        modules = {
            {
                key = "MageProcs",
                title = "Mage Proc Glows",
                description = "Secret-safe Auto-Cast Shine for custom Frost Mage CDM spells.",
                pages = { "Glow Conditions" },
                buildPage = BuildPage,
            },
        },
    })
end

SLASH_CUSTOMCDMGLOWS1 = "/cdmglows"
SlashCmdList.CUSTOMCDMGLOWS = function()
    local eui = EllesmereUI
    if eui and type(eui.OpenPlugin) == "function" then
        eui.OpenPlugin(ADDON_NAME, "MageProcs", "Glow Conditions")
    end
end

local function ScheduleNativeScan()
    if scanQueued then return end
    scanQueued = true
    local function run()
        scanQueued = false
        if IsInCombat() then
                return
        end
        RebuildNativeAuraMap()
        HookViewerItems()
        ScheduleRefresh()
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.15, run) else run() end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("SPELLS_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("SPELL_UPDATE_USABLE")
eventFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
eventFrame:RegisterEvent("SPELL_UPDATE_CHARGES")

local optionalEvents = {
    "COOLDOWN_VIEWER_DATA_LOADED",
    "COOLDOWN_VIEWER_TABLE_HOTFIXED",
    "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED",
    "EDIT_MODE_LAYOUTS_UPDATED",
}
for i = 1, #optionalEvents do
    pcall(eventFrame.RegisterEvent, eventFrame, optionalEvents[i])
end

eventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_AURA" then
        if unit == "player" or unit == "target" then ScheduleRefresh() end
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        for i = 1, #activeRecords do
            local record = activeRecords[i]
            if record.glowing then
                StopAutocastGlow(record.overlay)
                record.glowing = false
            end
        end
        ScheduleRefresh()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_SPECIALIZATION_CHANGED" or event == "SPELLS_CHANGED"
        or event == "COOLDOWN_VIEWER_DATA_LOADED" or event == "COOLDOWN_VIEWER_TABLE_HOTFIXED"
        or event == "COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED" or event == "EDIT_MODE_LAYOUTS_UPDATED" then
        ScheduleNativeScan()
        if event == "PLAYER_ENTERING_WORLD" and C_Timer and C_Timer.After then
            C_Timer.After(1, function()
                RebindIcons()
                ScheduleNativeScan()
            end)
        else
            RebindIcons()
        end
    else
        ScheduleRefresh()
    end
end)

RegisterPlugin()
RebindIcons()
ScheduleNativeScan()
