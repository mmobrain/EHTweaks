-- Author: Skulltrail
-- EHTweaks: Skill & Perk Browser
-- Features: Tabs (Skills/My Echoes/Echoes DB/Settings/Import), Merged Rank Descriptions, Search, Jump to Node, Chat Links

local addonName, addon = ...
local LibDeflate = LibStub:GetLibrary("LibDeflate")

-- Ensure global Skin table exists to prevent errors if loading order varies
if not EHTweaks.Skin then EHTweaks.Skin = {} end
local Skin = EHTweaks.Skin

-- If Skin module isn't loaded yet (fallback for testing)
if not Skin.ApplyWindow then
    Skin.ApplyWindow = function(f, title)
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = {left = 0, right = 0, top = 0, bottom = 0},
        })
        f:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
        f:SetBackdropBorderColor(0, 0, 0, 1)
        if not f.titleBg then
            local t = f:CreateTexture(nil, "ARTWORK")
            t:SetTexture("Interface\\Buttons\\WHITE8X8")
            t:SetVertexColor(0.2, 0.2, 0.2, 1)
            t:SetHeight(24)
            t:SetPoint("TOPLEFT", 1, -1)
            t:SetPoint("TOPRIGHT", -1, -1)
            f.titleBg = t
        end
        if not f.title then
            f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            f.title:SetPoint("TOP", 0, -6)
        end
        f.title:SetText(title or "")
        if not f.closeBtn then
            local c = CreateFrame("Button", nil, f, "UIPanelCloseButton")
            c:SetPoint("TOPRIGHT", 0, 0)
            c:SetScript("OnClick", function() f:Hide() end)
            f.closeBtn = c
        end
    end
end
if not Skin.ApplyInset then
    Skin.ApplyInset = function(f)
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = {left = 0, right = 0, top = 0, bottom = 0},
        })
        f:SetBackdropColor(0, 0, 0, 0.3)
        f:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    end
end

-- --- Configuration ---
local ROW_HEIGHT = 44
local MIN_ROWS = 8
local BROWSER_TITLE = "Ebonhold Compendium"
local EXPORT_HEADER = "!EHT1!"

-- Quality Colors
local QUALITY_COLORS = {
    [0] = { r=1, g=1, b=1, name="Common" },
    [1] = { r=0.1, g=1, b=0.1, name="Uncommon" },
    [2] = { r=0.0, g=0.4, b=1.0, name="Rare" },
    [3] = { r=0.6, g=0.2, b=1.0, name="Epic" },
    [4] = { r=1.0, g=0.5, b=0.0, name="Legendary" }
}

-- --- Data State ---
local activeTab = 1 -- 1: Skills, 2: My Echoes, 3: Echoes DB, 4: Settings, 5: Import/Export
local browserData = {}
local filteredData = {}
local browserFrame = nil
local isDataDirty = true

function EHTweaks_RefreshBrowser()
    -- Mark data as dirty so it rebuilds the list (re-checking favorites)
    isDataDirty = true
    
    -- If the browser frame is visible, refresh the scroll view immediately
    if browserFrame and browserFrame:IsShown() then
        -- This function (RefreshData/UpdateScroll) handles rebuilding if isDataDirty is true
        if UpdateScroll then UpdateScroll() end 
    end
end

-- --- ECHO DELETION LOGIC ---
local RefreshData
local function EHTweaks_DeleteEcho(spellId, deleteAll)
    if not EHTweaksDB or not EHTweaksDB.seenEchoes or not spellId then return end
    
    local targetEntry = EHTweaksDB.seenEchoes[spellId]
    if not targetEntry then return end

    if deleteAll then
        local name = targetEntry.name
        local count = 0
        for id, data in pairs(EHTweaksDB.seenEchoes) do
            if data.name == name then
                EHTweaksDB.seenEchoes[id] = nil
                count = count + 1
            end
        end
        print("|cffff0000EHTweaks:|r Deleted all " .. count .. " entries for '" .. name .. "'.")
    else
        EHTweaksDB.seenEchoes[spellId] = nil
        print("|cffff0000EHTweaks:|r Deleted echo '" .. targetEntry.name .. "' (ID: " .. spellId .. ").")
    end

    
    if RefreshData then
        RefreshData()  -- Rebuild the list immediately
    end
    
    -- Update UI
    if browserFrame and browserFrame.UpdateLayout then
        browserFrame:UpdateLayout() -- Ensure scroll/rows are redrawn
    end
end

StaticPopupDialogs["EHTWEAKS_DELETE_ECHO"] = {
    text = "Delete Echo from Database?\n\n|cffffd100%s|r",
    button1 = "Delete This",
    button2 = "Cancel",
    OnAccept = function(self)
        EHTweaks_DeleteEcho(self.data, false)
    end,
    OnAlt = function(self)
        EHTweaks_DeleteEcho(self.data, true)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
}

local function EHTweaks_PromptDeleteEcho(spellId)
    if not EHTweaksDB.seenEchoes[spellId] then return end
    
    local entry = EHTweaksDB.seenEchoes[spellId]
    local name = entry.name
    
    -- Count duplicates
    local count = 0
    for _, data in pairs(EHTweaksDB.seenEchoes) do
        if data.name == name then count = count + 1 end
    end

    local dialog = StaticPopupDialogs["EHTWEAKS_DELETE_ECHO"]
    
    if count > 1 then
        dialog.button3 = "Delete All (" .. count .. ")"
        dialog.OnAlt = function(self) EHTweaks_DeleteEcho(spellId, true) end
    else
        dialog.button3 = nil
        dialog.OnAlt = nil
    end

    local popup = StaticPopup_Show("EHTWEAKS_DELETE_ECHO", name)
    if popup then
        popup.data = spellId
    end
end


-- --- Helper: Text Merging ---
local function GetRichDescription(data)
    if not data then return "" end

    if data.isPerk then
        if utils and utils.GetSpellDescription then
            return utils.GetSpellDescription(data.spellId, 999, data.stack or 1)
        end
        return "No description available."
    end

    local spellIds = data.ranks
    if not spellIds or #spellIds == 0 then return "" end
    
    local desc1 = utils.GetSpellDescription(spellIds[1], 999, 1)
    if #spellIds == 1 then return desc1 end

    local template = desc1:gsub("%d+%.?%d*", "%%s") 
    local values = {} 
    
    local vIndex = 1
    for num in desc1:gmatch("%d+%.?%d*") do
        if not values[vIndex] then values[vIndex] = {} end
        table.insert(values[vIndex], num)
        vIndex = vIndex + 1
    end
    
    for i = 2, #spellIds do
        local descN = utils.GetSpellDescription(spellIds[i], 999, 1)
        local templateN = descN:gsub("%d+%.?%d*", "%%s")
        if template ~= templateN then return nil end 
        
        vIndex = 1
        for num in descN:gmatch("%d+%.?%d*") do
            if values[vIndex] then table.insert(values[vIndex], num) end
            vIndex = vIndex + 1
        end
    end
    
    local finalStr = ""
    local lastPos = 1
    local vIndex = 1
    
    while true do
        local startP, endP = string.find(desc1, "%d+%.?%d*", lastPos)
        if not startP then break end
        
        finalStr = finalStr .. string.sub(desc1, lastPos, startP - 1)
        
        if values[vIndex] then
            local rankVals = values[vIndex]
            local allSame = true
            for k=2, #rankVals do if rankVals[k] ~= rankVals[1] then allSame = false break end end
            
            if allSame then
                finalStr = finalStr .. rankVals[1]
            else
                local merged = ""
                for k, v in ipairs(rankVals) do
                    if k > 1 then merged = merged .. "/" end
                    merged = merged .. v
                end
                finalStr = finalStr .. "|cff00ff00" .. merged .. "|r"
            end
        else
            finalStr = finalStr .. string.sub(desc1, startP, endP)
        end
        vIndex = vIndex + 1
        lastPos = endP + 1
    end
    finalStr = finalStr .. string.sub(desc1, lastPos)
    return finalStr
end

-- --- Data Building ---
local function BuildTreeData()
    local data = {}
    if TalentDatabase and TalentDatabase[0] then
        for _, node in ipairs(TalentDatabase[0].nodes) do
            if node.spells and #node.spells > 0 then
                if node.isMultipleChoice then
                    for i, spellId in ipairs(node.spells) do
                        local name, _, icon = GetSpellInfo(spellId)
                        if name then
                            table.insert(data, {
                                nodeId = node.id,
                                spellId = spellId,
                                isChoice = true,
                                name = name,
                                icon = icon,
                                ranks = { spellId },
                                cost = node.soulPointsCosts and node.soulPointsCosts[1] or 0
                            })
                        end
                    end
                else
                    local maxRankSpellId = node.spells[#node.spells]
                    local name, _, icon = GetSpellInfo(maxRankSpellId)
                    if name then
                        table.insert(data, {
                            nodeId = node.id,
                            spellId = maxRankSpellId,
                            isChoice = false,
                            name = name,
                            icon = icon,
                            ranks = node.spells,
                            cost = node.soulPointsCosts and node.soulPointsCosts[1] or 0,
                            maxCost = node.soulPointsCosts and node.soulPointsCosts[#node.soulPointsCosts] or 0
                        })
                    end
                end
            end
        end
    end
    table.sort(data, function(a, b) return a.name < b.name end)
    return data
end

local function BuildPerkData()
    local data = {}
    if ProjectEbonhold and ProjectEbonhold.PerkService then
        local granted = ProjectEbonhold.PerkService.GetGrantedPerks()
        if granted then
            for spellName, instances in pairs(granted) do
                if instances and #instances > 0 then
                    -- Group by SpellID to separate different qualities/IDs of the same spell name
                    local idGroups = {}
                    
                    for _, info in ipairs(instances) do
                        local sID = info.spellId
                        if sID then
                            if not idGroups[sID] then
                                idGroups[sID] = {
                                    spellId = sID,
                                    quality = info.quality or 0,
                                    stack = 0,
                                    name = spellName
                                }
                            end
                            -- Accumulate stacks for this specific ID
                            idGroups[sID].stack = idGroups[sID].stack + (info.stack or 1)
                        end
                    end
                    
                    -- Convert groups to list rows
                    for sID, group in pairs(idGroups) do
                        local _, _, iconTex = GetSpellInfo(sID)
                        table.insert(data, {
                            isPerk = true,
                            name = group.name,
                            icon = iconTex,
                            spellId = sID,
                            stack = group.stack,
                            quality = group.quality
                        })
                    end
                end
            end
        end
    end
    
    -- Sort: Quality DESC -> Name ASC -> Stack DESC
    table.sort(data, function(a, b) 
        if a.quality ~= b.quality then return a.quality > b.quality end
        if a.name ~= b.name then return a.name < b.name end
        return a.stack > b.stack
    end)
    
    return data
end

local function BuildHistoryData()
    local data = {}
    local groups = {} -- name => { highestQ, qualities = { q => id }, icon, name }
    
    if EHTweaksDB and EHTweaksDB.seenEchoes then
        for spellId, info in pairs(EHTweaksDB.seenEchoes) do
            local name = info.name
            if name then
                if not groups[name] then
                    groups[name] = { highestQ = -1, qualities = {}, icon = info.icon, name = name }
                end
                
                local q = math.abs(tonumber(info.quality) or 0)
                groups[name].qualities[q] = spellId
                
                if q > groups[name].highestQ then
                    groups[name].highestQ = q
                    groups[name].icon = info.icon
                end
            end
        end
    end
    
    for name, group in pairs(groups) do
        local mainID = group.qualities[group.highestQ]
        
        -- Check ALL IDs with this name, not just the highest quality (just to be sure)
        local fav = false
        if EHTweaksDB.favorites then
            -- Check if ANY ID with this name is favorited
            for quality, spellId in pairs(group.qualities) do
                if EHTweaksDB.favorites[spellId] then
                    fav = true
                    break
                end
            end
        end
        
        table.insert(data, {
            isPerk = true,
            isHistory = true,
            name = name,
            icon = group.icon,
            spellId = mainID,
            quality = group.highestQ,
            qualityMap = group.qualities,
            isFavorite = fav
        })
    end
    
    table.sort(data, function(a, b)
        if a.isFavorite ~= b.isFavorite then return a.isFavorite end
        if a.quality ~= b.quality then return a.quality > b.quality end
        return a.name < b.name
    end)
    
    return data
end


local function ApplyFilter()
    local text = (browserFrame and browserFrame.searchBox and browserFrame.searchBox:GetText()) or ""
    
    -- Recycle the table instead of creating a new one
    wipe(filteredData)

    if text == "" then
        -- Fast path: just copy references
        for _, v in ipairs(browserData) do table.insert(filteredData, v) end
    else
        text = string.lower(text)
        for _, entry in ipairs(browserData) do
            -- Name match
            if string.find(string.lower(entry.name), text, 1, true) then
                table.insert(filteredData, entry)
            else               
                local desc = nil
                               
                if desc and string.find(string.lower(desc), text, 1, true) then
                    table.insert(filteredData, entry)
                end
            end
        end
    end
end

RefreshData = function()
    if activeTab == 1 then
        browserData = BuildTreeData() 
    elseif activeTab == 2 then
        browserData = BuildPerkData() 
    else
        wipe(browserData)
    end
    
    ApplyFilter()
    
    -- Update Count Labels
    if browserFrame and browserFrame.countLabel then
        local count = #filteredData
        local total = #browserData
        local color = "|cffffffff"
        if activeTab == 1 then color = "|cffFFD700" end
        if activeTab == 2 then color = "|cff00FF00" end
        
        browserFrame.countLabel:SetText(string.format("%sItems: %d / %d|r", color, count, total))
    end
    
    isDataDirty = false
end

-- --- IMPORT / EXPORT LOGIC (LibDeflate) ---
-- Format: { [1]={id=123,q=1}, [2]={id=456,q=0}, ... } -> Serialized -> Compressed -> Encoded
function EHTweaks_ExportEchoes()
    if not EHTweaksDB.seenEchoes then 
        EHTweaks_Log("Export: No seenEchoes DB found.")
        return "" 
    end
    if not LibDeflate then return "Error: LibDeflate missing" end
    
    local exportTable = {}
    local count = 0
    
    -- Gather data into a simple array
    EHTweaks_Log("--- Exporting Echoes ---")
    for spellId, info in pairs(EHTweaksDB.seenEchoes) do        
        local quality = math.abs(info.quality or 0)
        table.insert(exportTable, { spellId, quality }) 
        count = count + 1
    end
    EHTweaks_Log("Total items to export: " .. count)
    
    -- Manual Serialization: id:q,id:q
    local parts = {}
    for _, entry in ipairs(exportTable) do
        table.insert(parts, entry[1] .. ":" .. entry[2])
    end
    local rawString = table.concat(parts, ",")
    
    -- Compress + Encode
    local compressed = LibDeflate:CompressDeflate(rawString)    
    local encoded = LibDeflate:EncodeForPrint(compressed)
    
    return EXPORT_HEADER .. encoded
end

function EHTweaks_ImportEchoes(code)
    if not LibDeflate then return 0, "LibDeflate Missing" end
    
    EHTweaks_Log("--- Importing Echoes ---")
    
    -- Strip header
    if string.sub(code, 1, string.len(EXPORT_HEADER)) == EXPORT_HEADER then
        code = string.sub(code, string.len(EXPORT_HEADER) + 1)
    end
    
    -- Decode
    local compressed = LibDeflate:DecodeForPrint(code)
    if not compressed then 
        EHTweaks_Log("Import Error: Invalid Encoding (DecodeForPrint failed)")
        return 0, "Invalid Encoding" 
    end
    
    -- Decompress
    local rawString = LibDeflate:DecompressDeflate(compressed)
    if not rawString then 
        EHTweaks_Log("Import Error: Decompression Failed")
        return 0, "Decompression Failed" 
    end
    
    -- DEBUG: Inspect the raw string format
    local safeLog = rawString:sub(1, 100) 
    EHTweaks_Log("DEBUG Raw String Sample: " .. safeLog) 
    EHTweaks_Log("DEBUG Raw String Length: " .. string.len(rawString))
    
    -- Deserialize
    local imported = 0   -- Count of NEW or UPGRADED items
    local totalSeen = 0  -- Count of VALID items parsed
    if not EHTweaksDB.seenEchoes then EHTweaksDB.seenEchoes = {} end
    
    local loopCount = 0
    for entryStr in string.gmatch(rawString, "([^,]+)") do
        loopCount = loopCount + 1
        
        local idStr, qStr = string.match(entryStr, "^(%d+):(-?%d+)$")
        
        if idStr and qStr then
            totalSeen = totalSeen + 1
            local spellId = tonumber(idStr)
            local quality = tonumber(qStr)
            quality = math.abs(quality) 
            
            -- Validate Spell Exists
            local name, _, icon = GetSpellInfo(spellId)
            if name then
                if not EHTweaksDB.seenEchoes[spellId] then
                    EHTweaksDB.seenEchoes[spellId] = {
                        name = name,
                        icon = icon,
                        quality = quality
                    }
                    imported = imported + 1
                else
                    -- Merge strategy: Keep highest quality
                    local oldQ = math.abs(EHTweaksDB.seenEchoes[spellId].quality or 0)
                    if quality > oldQ then
                        EHTweaksDB.seenEchoes[spellId].quality = quality
                        imported = imported + 1 
                    end
                end
            end
        else
            -- Debug failed parse only
             if loopCount <= 3 then EHTweaks_Log("DEBUG Failed Parse: '" .. tostring(entryStr) .. "'") end
        end
    end
    
    EHTweaks_Log("Loop Iterations: " .. loopCount)
    EHTweaks_Log("Valid Items Parsed: " .. totalSeen)
    EHTweaks_Log("New/Upgraded Items: " .. imported)
    
    -- Logic Fix: If we saw valid items but imported 0, it means everything was duplicate/lower quality.
    -- This is a SUCCESSFUL merge, not a failure.
    if imported == 0 and totalSeen > 0 then
        return 0, "No new data (Database already up-to-date)"
    elseif totalSeen == 0 then
         return 0, "Format Error (Parsed 0 valid items)"
    end
    
    return imported
end

-- --- UI Logic ---
local function UpdateScroll()
    if not browserFrame then return end
    
    if activeTab >= 3 then 
        if browserFrame.scroll then browserFrame.scroll:Hide() end
        if browserFrame.searchBox then browserFrame.searchBox:Hide() end
        if browserFrame.searchLabel then browserFrame.searchLabel:Hide() end
        if browserFrame.listContainer then browserFrame.listContainer:Hide() end
        if browserFrame.rows then for _, r in ipairs(browserFrame.rows) do r:Hide() end end
        if browserFrame.settingsFrame then if activeTab == 3 then browserFrame.settingsFrame:Show() else browserFrame.settingsFrame:Hide() end end
        return
    else
        if browserFrame.scroll then browserFrame.scroll:Show() end
        if browserFrame.searchBox then browserFrame.searchBox:Show() end
        if browserFrame.searchLabel then browserFrame.searchLabel:Show() end
        if browserFrame.listContainer then browserFrame.listContainer:Show() end
        if browserFrame.settingsFrame then browserFrame.settingsFrame:Hide() end
    end

    if isDataDirty then RefreshData() end
    
    local FauxScrollFrame_Update = FauxScrollFrame_Update
    local offset = FauxScrollFrame_GetOffset(browserFrame.scroll)
    local numItems = #filteredData
    local maxRows = browserFrame.maxRows or MIN_ROWS
    
    for i = 1, #browserFrame.rows do
        local row = browserFrame.rows[i]
        if i > maxRows then
            row:Hide()
        else
            local index = offset + i
            if index <= numItems then
                local data = filteredData[index]
                row.data = data
                
                row.icon:SetTexture(data.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                
                -- Favorites Styling
                if data.isFavorite then
                    -- Show Gem Icon
                    row.favMark:Show()
                    
                    -- Anchor cost text to the LEFT of the Gem to prevent overlap
                    row.cost:SetPoint("RIGHT", row.favMark, "LEFT", -5, 0)
                    
                    -- Goldish/Greenish Background                    
                    row.bg:SetVertexColor(0.1, 0.4, 0.0, 0.4)
                else
                    row.favMark:Hide()
                    -- Reset anchor if no gem
                    row.cost:SetPoint("RIGHT", -10, 0)
                    -- Transparent background
                    row.bg:SetVertexColor(0, 0, 0, 0)
                end
                
                if data.isPerk then
                    local color = QUALITY_COLORS[data.quality] or QUALITY_COLORS[0]
                    row.name:SetText(data.name)
                    row.name:SetTextColor(color.r, color.g, color.b)
                    
                    row.cost:SetText("Stack: " .. (data.stack or 1))
                    row.typeText:SetText(color.name)
                    row.typeText:SetTextColor(color.r, color.g, color.b)
                else
                    row.name:SetText(data.name)
                    row.name:SetTextColor(1, 1, 1)
                    if data.isChoice then
                        row.cost:SetText("|cffFFD700" .. data.cost .. "|r SP")
                        row.typeText:SetText("Choice")
                        row.typeText:SetTextColor(1, 0.5, 0)
                    else
                        local rankCount = #data.ranks
                        if rankCount > 1 then
                            row.cost:SetText("|cffFFD700" .. data.cost .. "-" .. data.maxCost .. "|r SP")
                            row.typeText:SetText("Rank 1-" .. rankCount)
                            row.typeText:SetTextColor(0, 1, 0)
                        else
                            row.cost:SetText("|cffFFD700" .. data.cost .. "|r SP")
                            row.typeText:SetText("Passive")
                            row.typeText:SetTextColor(0.8, 0.8, 0.8)
                        end
                    end
                end
                row:Show()
            else
                row:Hide()
            end
        end
    end
    FauxScrollFrame_Update(browserFrame.scroll, numItems, maxRows, ROW_HEIGHT)
end


local function SetTab(id)
    activeTab = id
    isDataDirty = true
    if browserFrame then
        for k, t in ipairs(browserFrame.tabs) do
            if k == id then
                 t.bg:SetVertexColor(0.3, 0.3, 0.3, 1)
            else
                 t.bg:SetVertexColor(0.15, 0.15, 0.15, 1)
            end
        end
        if browserFrame.searchBox then browserFrame.searchBox:SetText("") end
    end
    UpdateScroll()
end

local function CreateBrowserFrame()
    if browserFrame then return browserFrame end

    local f = CreateFrame("Frame", "EHTweaks_BrowserFrame", UIParent)
    f:SetSize(600, 520)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetResizable(true)
    f:SetMinResize(600, 400)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    
    Skin.ApplyWindow(f, BROWSER_TITLE)
    browserFrame = f
    
    local countLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countLbl:SetPoint("TOPLEFT", 10, -7)
    f.countLabel = countLbl

    local sb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    sb:SetSize(200, 20)
    sb:SetPoint("TOPRIGHT", -30, -32)
    sb:SetAutoFocus(false)
    sb:SetScript("OnTextChanged", function(self) self.updateDelay = 0.3 end)
    sb:SetScript("OnUpdate", function(self, elapsed)
        elapsed = math.min(elapsed or 0, 0.1)

        if self.updateDelay then
          self.updateDelay = self.updateDelay - elapsed
          if self.updateDelay <= 0 then
            self.updateDelay = nil
            ApplyFilter()
            UpdateScroll()
          end
        end
    end)

    f.searchBox = sb
    
    local sbLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sbLabel:SetPoint("RIGHT", sb, "LEFT", -5, 0)
    sbLabel:SetText("Filter:")
    f.searchLabel = sbLabel
    
    local clearBtn = CreateFrame("Button", nil, sb)
    clearBtn:SetSize(14, 14)
    clearBtn:SetPoint("RIGHT", sb, "RIGHT", -4, 0)
    clearBtn:SetNormalTexture("Interface\\FriendsFrame\\ClearBroadcastIcon")
    clearBtn:SetAlpha(0.5)
    clearBtn:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    clearBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
    clearBtn:SetScript("OnClick", function()
        sb:SetText("")
        sb:ClearFocus()
        ApplyFilter()
        UpdateScroll()
    end)

    local listContainer = CreateFrame("Frame", nil, f)
    listContainer:SetPoint("TOPLEFT", 10, -60)
    listContainer:SetPoint("BOTTOMRIGHT", -10, 40)
    Skin.ApplyInset(listContainer)
    f.listContainer = listContainer

    local sf = CreateFrame("ScrollFrame", "EHTweaks_BrowserScroll", listContainer, "FauxScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 0, -2)
    sf:SetPoint("BOTTOMRIGHT", -26, 2)
    sf:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, UpdateScroll)
    end)
    f.scroll = sf
    
    local resize = CreateFrame("Button", nil, f)
    resize:SetSize(16, 16)
    resize:SetPoint("BOTTOMRIGHT")
    resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resize:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    resize:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)
    f.resizeBtn = resize

    f.tabs = {}
    local function CreateNavTab(id, text)
        local tab = CreateFrame("Button", "$parentTab"..id, f)
        tab:SetID(id)
        tab:SetText(text)
        tab:SetSize(110, 26)
        tab:SetNormalFontObject("GameFontNormalSmall")
        tab:SetHighlightFontObject("GameFontHighlightSmall")
        local bg = tab:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        bg:SetVertexColor(0.15, 0.15, 0.15, 1)
        tab.bg = bg
        tab:SetScript("OnEnter", function(self) self.bg:SetVertexColor(0.25, 0.25, 0.25, 1) end)
        tab:SetScript("OnLeave", function(self) 
             if activeTab ~= self:GetID() then self.bg:SetVertexColor(0.15, 0.15, 0.15, 1) 
             else self.bg:SetVertexColor(0.3, 0.3, 0.3, 1) end
        end)
        tab:SetScript("OnClick", function() SetTab(id) end)
        return tab
    end
    
    local tabNames = {"Skills", "My Echoes", "Settings"}
    local prevTab
    for i, name in ipairs(tabNames) do
        local t = CreateNavTab(i, name)
        if i == 1 then
            t:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 5)
        else
            t:SetPoint("LEFT", prevTab, "RIGHT", 2, 0)
        end
        f.tabs[i] = t
        prevTab = t
    end

    f.CreateRows = function(self)
        local h = self:GetHeight()
        local availableH = h - 90 
        local count = math.floor(availableH / ROW_HEIGHT)
        if count < MIN_ROWS then count = MIN_ROWS end
        self.maxRows = count
        
        if not self.rows then self.rows = {} end
        
        for i = 1, count do
            if not self.rows[i] then
                local row = CreateFrame("Button", nil, listContainer)
                row:SetSize(424, ROW_HEIGHT)
                row:RegisterForClicks("AnyUp") 
                
                local bg = row:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetTexture("Interface\\Buttons\\WHITE8X8")
                bg:SetVertexColor(0, 0, 0, 0)
                row.bg = bg

                local hl = row:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                hl:SetAlpha(0.3)
                
                local icon = row:CreateTexture(nil, "ARTWORK")
                icon:SetSize(36, 36)
                icon:SetPoint("LEFT", 5, 0)
                row.icon = icon
                
                local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
                name:SetJustifyH("LEFT")
                row.name = name
                
                local typeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                typeText:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, 0)
                typeText:SetJustifyH("LEFT")
                row.typeText = typeText
                
                local favMark = row:CreateTexture(nil, "OVERLAY")
                favMark:SetSize(14, 14)                
                favMark:SetPoint("RIGHT", -10, 0) 
                favMark:SetTexture("Interface\\Icons\\inv_misc_gem_02")
                favMark:Hide()
                row.favMark = favMark

                local cost = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                cost:SetPoint("RIGHT", favMark, "LEFT", -5, 0)
                row.cost = cost
                               
                row:SetScript("OnEnter", function(self)
                    if not self.data then return end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:ClearLines()
                    
                    if self.data.isPerk then
                        local c = QUALITY_COLORS[self.data.quality] or QUALITY_COLORS[0]
                        GameTooltip:AddLine(self.data.name, c.r, c.g, c.b)
                        local desc = GetRichDescription and GetRichDescription(self.data)
                        if desc then GameTooltip:AddLine(desc, 1, 0.82, 0, true) end
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("Current Stack: " .. (self.data.stack or 1), 1, 1, 1)
                    else
                        GameTooltip:AddLine(self.data.name, 1, 1, 1)
                        for i, spellId in ipairs(self.data.ranks or {}) do
                            local d = utils and utils.GetSpellDescription(spellId, 999, 1) or ""
                            GameTooltip:AddLine("Rank " .. i .. ": " .. d, 0.8, 0.8, 0.8, true)
                        end
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("Click to view in Skill Tree", 0, 1, 0)
                    end
                    GameTooltip:AddLine("Ctrl+Alt+Click to Link", 0.6, 0.6, 0.6)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function() GameTooltip:Hide() end)
                
                row:SetScript("OnClick", function(self, button)
                    if not self.data then return end
                                        
                    if button == "LeftButton" and IsControlKeyDown() and IsShiftKeyDown() then
                        if f.cardIndex then
                            MD.BanishOption(f.cardIndex)
                        end
                    end
                    
                    if EHTweaks_HandleLinkClick and EHTweaks_HandleLinkClick(self.data.spellId) then return end
                    
                    if self.data.isPerk then return end
                    
                    if _G.skillTreeFrame then _G.skillTreeFrame:Show() end
                    
                    local btn = _G["skillTreeNode" .. self.data.nodeId]
                    if btn and _G.skillTreeScroll then
                        local scroll = _G.skillTreeScroll
                        local _, _, _, xOfs, yOfs = btn:GetPoint(1)
                        if xOfs then
                            local h = xOfs - (scroll:GetWidth()/2)
                            local v = math.abs(yOfs) - (scroll:GetHeight()/2)
                            scroll:SetHorizontalScroll(math.max(0, h))
                            scroll:SetVerticalScroll(math.max(0, v))
                            
                            if not btn.browserGlow then
                                local glow = btn:CreateTexture(nil, "OVERLAY")
                                glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
                                glow:SetBlendMode("ADD")
                                glow:SetVertexColor(1, 0.5, 0, 1)
                                glow:SetPoint("CENTER", btn, "CENTER", 0, 0)
                                glow:SetSize(btn:GetWidth() * 2, btn:GetHeight() * 2)
                                
                                local ag = glow:CreateAnimationGroup()
                                local a1 = ag:CreateAnimation("Alpha")
                                a1:SetChange(-1)
                                a1:SetDuration(1)
                                a1:SetOrder(1)
                                ag:SetLooping("REPEAT")
                                
                                btn.browserGlow = glow
                                btn.browserGlowAnim = ag
                            end
                            btn.browserGlow:Show()
                            btn.browserGlowAnim:Play()
                            C_Timer.After(5, function() 
                                if btn.browserGlow then 
                                    btn.browserGlow:Hide() 
                                    btn.browserGlowAnim:Stop() 
                                end 
                            end)
                        end
                    end
                end)

                self.rows[i] = row
            end
        end
        UpdateScroll()
    end
    
    f.UpdateLayout = function(self)
        self:CreateRows()
        local w = self:GetWidth()
        local contentW = w - 40
        self.searchBox:SetWidth(w - 260)
        for i, row in ipairs(self.rows) do
             row:SetWidth(contentW)
             row:SetPoint("TOPLEFT", 10, -5 - (i-1)*ROW_HEIGHT)
        end
        UpdateScroll()
    end
    
    f:SetScript("OnSizeChanged", function(self) self:UpdateLayout() end)

    -- --- SETTINGS FRAME ---
    local settings = CreateFrame("Frame", nil, f)
    settings:SetPoint("TOPLEFT", 10, -60)
    settings:SetPoint("BOTTOMRIGHT", -10, 40)
    Skin.ApplyInset(settings)
    settings:Hide()
    f.settingsFrame = settings
    
    local sTitle = settings:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sTitle:SetPoint("TOPLEFT", 20, -20)
    sTitle:SetText("EHTweaks Settings")
    
    -- Two-Column Layout Variables
    local col1X = 20
    local col2X = 300
    local startY = -50
    local itemSpacing = 26
    local itemsPerCol = 8

    local settingIndex = 0
    local lastSettingButton = nil

    local function AddCheck(varName, label, onClick)
        settingIndex = settingIndex + 1
        local cb = CreateFrame("CheckButton", nil, settings, "UICheckButtonTemplate")
        
        local col = (settingIndex <= itemsPerCol) and 1 or 2
        local row = (settingIndex <= itemsPerCol) and (settingIndex - 1) or (settingIndex - itemsPerCol - 1)
        
        local x = (col == 1) and col1X or col2X
        local y = startY - (row * itemSpacing)
        
        cb:SetPoint("TOPLEFT", settings, "TOPLEFT", x, y)
        
        local text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", cb, "RIGHT", 5, 1)
        text:SetText(label)
        
        cb:SetScript("OnClick", function(self)
             local isChecked = (self:GetChecked() == 1)
             EHTweaksDB[varName] = isChecked
             if onClick then onClick(self, isChecked) end
        end)
        
        cb:SetChecked(EHTweaksDB[varName])
        
        if not lastSettingButton then
            lastSettingButton = cb
        else
            local _, _, _, _, lastY = lastSettingButton:GetPoint()
            if y < lastY then
                lastSettingButton = cb
            end
        end
        
        return cb
    end

    AddCheck("enableFilters", "Enhance Project Ebonhold with Filters")
    AddCheck("enableChatLinks", "Enhance Project Ebonhold with Chat Links")
    AddCheck("enableTracker", "Enhance Project Ebonhold with Objective Tracker")
    AddCheck("minimapButtonHidden", "Hide Minimap Button", function(self, isChecked)
        if isChecked then
            if EHTweaks_HideMinimapButton then EHTweaks_HideMinimapButton() end
        else
            if EHTweaks_ShowMinimapButton then EHTweaks_ShowMinimapButton() end
        end
    end)
    AddCheck("enableLockedEchoWarning", "Warn on Death if Echo Locked")
    AddCheck("showDraftFavorites", "Show 'FAVOURED' on Draft Cards")
    AddCheck("showEmpowermentFavorites", "Show markers in 'My Echoes'", function(self, isChecked) 
        if HookEchoButtons then HookEchoButtons() end
    end)
    AddCheck("enableIntensityWarning", "Warn on Intensity level change") 
    AddCheck("enableShadowFissureWarning", "Warn when Shadow Fissure (red circle) is spawned")
    AddCheck("chatWarnings", "Show Chat Warnings")
    AddCheck("chatInfo", "Show Chat Info (Intensity/Stats)")
    AddCheck("enableModernDraft", "Enable Modern Draft UI |cffff5555(Exp!)|r")

    local reloadBtn = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
    reloadBtn:SetSize(160, 30)
    reloadBtn:SetPoint("TOPLEFT", lastSettingButton, "BOTTOMLEFT", 0, -20)
    reloadBtn:SetText("Apply and Reload UI")
    reloadBtn:SetScript("OnClick", ReloadUI)

    local warn = settings:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    warn:SetPoint("TOPLEFT", reloadBtn, "BOTTOMLEFT", 0, -9)
    warn:SetText("Note: Browser features (this window) will remain active regardless of these settings.")
    warn:SetTextColor(0.6, 0.6, 0.6)

    f:UpdateLayout()
    return f
end

SLASH_EHTBROWSER1 = "/eht"
SlashCmdList["EHTBROWSER"] = function(msg)
    if msg == "reset" then
        isDataDirty = true
        print("|cff00ff00EHTweaks:|r Browser data cache cleared.")
        return
    end
    local f = CreateBrowserFrame()
    f:Show()
    UpdateScroll()
end