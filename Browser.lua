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
    local groups = {} -- name -> { highestQ, qualities = {q -> id}, icon }

    if EHTweaksDB and EHTweaksDB.seenEchoes then
        for spellId, info in pairs(EHTweaksDB.seenEchoes) do
            local name = info.name
            if name then
                if not groups[name] then
                    groups[name] = {
                        highestQ = -1,
                        qualities = {}, -- [quality] = spellId
                        icon = info.icon,
                        name = name
                    }
                end
                
                -- Ensure absolute value for quality to prevent -0 or negative numbers
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
        local fav = false
        if EHTweaksDB.favorites and EHTweaksDB.favorites[mainID] then
            fav = true
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
                -- Description match (using existing GetRichDescription if available)
                local desc = nil
                -- if GetRichDescription then 
                    -- desc = GetRichDescription(entry) 
                -- end
                
                if desc and string.find(string.lower(desc), text, 1, true) then
                    table.insert(filteredData, entry)
                end
            end
        end
    end
end

local function RefreshData()
    if activeTab == 1 then
        browserData = BuildTreeData() 
    elseif activeTab == 2 then
        browserData = BuildPerkData() 
    elseif activeTab == 3 then
        browserData = BuildHistoryData() 
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
        if activeTab == 3 then color = "|cff0070DD" end
        
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
    
    if activeTab >= 4 then 
        if browserFrame.scroll then browserFrame.scroll:Hide() end
        if browserFrame.searchBox then browserFrame.searchBox:Hide() end
        if browserFrame.searchLabel then browserFrame.searchLabel:Hide() end
        if browserFrame.listContainer then browserFrame.listContainer:Hide() end
        if browserFrame.rows then for _, r in ipairs(browserFrame.rows) do r:Hide() end end
        if browserFrame.settingsFrame then if activeTab == 4 then browserFrame.settingsFrame:Show() else browserFrame.settingsFrame:Hide() end end
        if browserFrame.importFrame then if activeTab == 5 then browserFrame.importFrame:Show() else browserFrame.importFrame:Hide() end end
        return
    else
        if browserFrame.scroll then browserFrame.scroll:Show() end
        if browserFrame.searchBox then browserFrame.searchBox:Show() end
        if browserFrame.searchLabel then browserFrame.searchLabel:Show() end
        if browserFrame.listContainer then browserFrame.listContainer:Show() end
        if browserFrame.settingsFrame then browserFrame.settingsFrame:Hide() end
        if browserFrame.importFrame then browserFrame.importFrame:Hide() end
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
                    
                    if data.isHistory then
                        local pips = ""
                        local map = data.qualityMap or {}
                        -- Pips: Common, Uncommon, Rare, Epic, Legendary
                        local chars = {"C","U","R","E","L"}
                        local colors = {"ffffffff", "ff1eff00", "ff0070dd", "ffa335ee", "ffff8000"}
                        for q=0,4 do
                            if map[q] then pips = pips.."|c"..colors[q+1]..chars[q+1].."|r " 
                            else pips = pips.."|cff555555"..chars[q+1].."|r " end
                        end
                        row.cost:SetText(pips)
                        local hName = QUALITY_COLORS[data.quality] and QUALITY_COLORS[data.quality].name or "Unknown"
                        row.typeText:SetText(hName)
                        row.typeText:SetTextColor(color.r, color.g, color.b)
                    else
                        row.cost:SetText("Stack: " .. (data.stack or 1))
                        row.typeText:SetText(color.name)
                        row.typeText:SetTextColor(color.r, color.g, color.b)
                    end
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

-- --- UI: Browser Frame ---
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
    
    local tabNames = {"Skills", "My Echoes", "Echoes DB", "Settings", "Import/DB"}
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

    -- CreateRows with Favorites, Tooltips, and Click Logic
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
                
                -- Row Background (for highlighting favorites)
                local bg = row:CreateTexture(nil, "BACKGROUND")
                bg:SetAllPoints()
                bg:SetTexture("Interface\\Buttons\\WHITE8X8")
                bg:SetVertexColor(0, 0, 0, 0) -- Invisible by default
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
                
                -- Favorite Marker (Gem Icon)
                local favMark = row:CreateTexture(nil, "OVERLAY")
                favMark:SetSize(14, 14)                
                favMark:SetPoint("RIGHT", -10, 0) 
                favMark:SetTexture("Interface\\Icons\\inv_misc_gem_02")
                favMark:Hide()
                row.favMark = favMark

                -- Cost/Pips anchored to the left of the Gem
                local cost = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                cost:SetPoint("RIGHT", favMark, "LEFT", -5, 0)
                row.cost = cost
                               
                
                row:SetScript("OnEnter", function(self)
                    if not self.data then return end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:ClearLines()
                    
                    if self.data.isPerk then
                        if self.data.isHistory and self.data.qualityMap then
                            local color = QUALITY_COLORS[self.data.quality] or QUALITY_COLORS[0]
                            GameTooltip:AddLine(self.data.name, color.r, color.g, color.b)
                            GameTooltip:AddLine(" ")
                            for q = 0, 4 do
                                local sID = self.data.qualityMap[q]
                                if sID then
                                    local qColor = QUALITY_COLORS[q]
                                    local qName = qColor.name or "Unknown"
                                    local desc = utils and utils.GetSpellDescription(sID, 999, 1) or "No Description"
                                    GameTooltip:AddLine(qName, qColor.r, qColor.g, qColor.b)
                                    GameTooltip:AddLine(desc, 1, 0.82, 0, true)
                                    GameTooltip:AddLine(" ")
                                end
                            end
                            GameTooltip:AddLine("Right-Click to Toggle Favorite", 1, 0.82, 0)
                        else
                            local c = QUALITY_COLORS[self.data.quality] or QUALITY_COLORS[0]
                            GameTooltip:AddLine(self.data.name, c.r, c.g, c.b)
                            local desc = GetRichDescription and GetRichDescription(self.data)
                            if desc then GameTooltip:AddLine(desc, 1, 0.82, 0, true) end
                            GameTooltip:AddLine(" ")
                            GameTooltip:AddLine("Current Stack: " .. (self.data.stack or 1), 1, 1, 1)
                        end
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
                    
                    -- RIGHT CLICK: Toggle Favorite (Echoes DB)
                    if button == "RightButton" and self.data.isHistory then
                        if not EHTweaksDB.favorites then EHTweaksDB.favorites = {} end
                        
                        local id = self.data.spellId
                        local name = self.data.name
                        if not name then name = GetSpellInfo(id) end
                        
                        -- Check if this specific ID is favored
                        if EHTweaksDB.favorites[id] then
                            -- REMOVE: Clear ALL IDs that match this Name (Sync Fix)
                            if name then
                                for k, v in pairs(EHTweaksDB.favorites) do
                                    local n = GetSpellInfo(k)
                                    if n == name then 
                                        EHTweaksDB.favorites[k] = nil 
                                    end
                                end
                            else
                                -- Fallback: Just remove ID if name unavailable
                                EHTweaksDB.favorites[id] = nil
                            end
                            print("|cffFFFF00EHTweaks|r: Removed '" .. (name or "Unknown") .. "' from Favorites.")
                        else
                            -- ADD: Add this specific ID
                            EHTweaksDB.favorites[id] = true
                            print("|cff00FF00EHTweaks|r: Added '" .. (name or "Unknown") .. "' to Favorites!")
                            
                            -- SYNC ADD: Add all known IDs for this name found in History
                            if name and EHTweaksDB.seenEchoes then
                                 for k, v in pairs(EHTweaksDB.seenEchoes) do
                                     if v.name == name then EHTweaksDB.favorites[k] = true end
                                 end
                            end
                        end
                        
                        -- Refresh Browser List
                        isDataDirty = true
                        UpdateScroll()
                        
                        -- Refresh Draft UI (perkMainFrame) immediately
                        if EHTweaks_RefreshFavouredMarkers then 
                            EHTweaks_RefreshFavouredMarkers() 
                        end
                        return
                    end
                    
                    -- LEFT CLICK or LINK Logic
                    if EHTweaks_HandleLinkClick and EHTweaks_HandleLinkClick(self.data.spellId) then return end
                    
                    if self.data.isPerk then return end
                    
                    -- JUMP TO NODE (Skills Tab)
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
    
    local lastObj = sTitle
    local function AddCheck(varName, label, onClick)
        local cb = CreateFrame("CheckButton", nil, settings, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", lastObj, "BOTTOMLEFT", 0, -1)
        
        local text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", cb, "RIGHT", 5, 1)
        text:SetText(label)
        
        cb:SetScript("OnClick", function(self)
             -- 3.3.5 FIX: GetChecked returns 1 or nil. Force boolean true/false.
             local isChecked = (self:GetChecked() == 1)
             EHTweaksDB[varName] = isChecked
             
             if onClick then onClick(self, isChecked) end
        end)
        
        -- Load Initial State correctly using boolean comparison
        cb:SetChecked(EHTweaksDB[varName])
        
        lastObj = cb
        return cb
    end

    AddCheck("enableFilters", "Enhance Project Ebonhold with Filters")
    AddCheck("enableChatLinks", "Enhance Project Ebonhold with Chat Links")
    AddCheck("enableTracker", "Enhance Project Ebonhold with Objective Tracker")
    
    -- Special case for Minimap Button (custom behavior)
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

    local reloadBtn = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
    reloadBtn:SetSize(160, 30)
    reloadBtn:SetPoint("TOPLEFT", lastObj, "BOTTOMLEFT", 0, -30)
    reloadBtn:SetText("Apply and Reload UI")
    reloadBtn:SetScript("OnClick", ReloadUI)

    local warn = settings:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    warn:SetPoint("TOPLEFT", reloadBtn, "BOTTOMLEFT", 0, -10)
    warn:SetText("Note: Browser features (this window) will remain active regardless of these settings.")
    warn:SetTextColor(0.6, 0.6, 0.6)

    -- --- IMPORT/EXPORT FRAME ---
    local import = CreateFrame("Frame", nil, f)
    import:SetPoint("TOPLEFT", 10, -60)
    import:SetPoint("BOTTOMRIGHT", -10, 40)
    Skin.ApplyInset(import)
    import:Hide()
    f.importFrame = import
    
    local iTitle = import:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    iTitle:SetPoint("TOPLEFT", 20, -20)
    iTitle:SetText("Import / Export Echoes")
    
    local h1 = import:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h1:SetPoint("TOPLEFT", iTitle, "BOTTOMLEFT", 0, -20)
    h1:SetText("Share your Echoes DB with others.")   
    
    local exportBtn = CreateFrame("Button", nil, import, "UIPanelButtonTemplate")
    exportBtn:SetSize(160, 30)
    exportBtn:SetPoint("TOPLEFT", h1, "BOTTOMLEFT", 0, -10)
    exportBtn:SetText("Export Echoes")
    exportBtn:SetScript("OnClick", function()
        if ProjectEbonhold and ProjectEbonhold.PerkService then
            local granted = ProjectEbonhold.PerkService.GetGrantedPerks()
            if granted then
                for spellName, instances in pairs(granted) do
                    for _, info in ipairs(instances) do
                        if EHTweaks_RecordEchoInfo then
                            EHTweaks_RecordEchoInfo(info.spellId, info.quality)
                        end
                    end
                end
            end
        end
        local str = EHTweaks_ExportEchoes and EHTweaks_ExportEchoes() or ""
        StaticPopupDialogs["EHTWEAKS_EXPORT"] = {
            text = "Echoes DB Export String:\n(Ctrl+C to copy)", button1 = "Close", hasEditBox = true, editBoxWidth = 350,
            OnShow = function(self) self.editBox:SetText(str) self.editBox:HighlightText() end,
            timeout = 0, whileDead = true, hideOnEscape = true
        }
        StaticPopup_Show("EHTWEAKS_EXPORT")
    end)

    local h2 = import:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h2:SetPoint("TOPLEFT", exportBtn, "BOTTOMLEFT", 0, -30)
    h2:SetText("Import Echoes DB from another player.")
    h2:SetWidth(360)
    h2:SetJustifyH("LEFT")

    local importBtn = CreateFrame("Button", nil, import, "UIPanelButtonTemplate")
    importBtn:SetSize(160, 30)
    importBtn:SetPoint("TOPLEFT", h2, "BOTTOMLEFT", 0, -10)
    importBtn:SetText("Import Echoes")
    importBtn:SetScript("OnClick", function()
        StaticPopupDialogs["EHTWEAKS_IMPORT_ECHOES"] = {
            text = "Paste String:", button1 = "Import", button2 = "Cancel", hasEditBox = true,
            OnAccept = function(self) 
                if EHTweaks_ImportEchoes then EHTweaks_ImportEchoes(self.editBox:GetText()) end
            end,
            timeout = 0, whileDead = true, hideOnEscape = true
        }
        StaticPopup_Show("EHTWEAKS_IMPORT_ECHOES")
    end)
    
    local separator = import:CreateTexture(nil, "ARTWORK")
    separator:SetHeight(1)
    separator:SetPoint("TOPLEFT", importBtn, "BOTTOMLEFT", 0, -20)
    separator:SetPoint("RIGHT", -20, 0)
    separator:SetTexture("Interface\\Buttons\\WHITE8X8")
    separator:SetVertexColor(0.4, 0.4, 0.4, 0.5)

    if _G.ETHTweaks_OptionalDB_Data then
        local starterHeader = import:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        starterHeader:SetPoint("TOPLEFT", separator, "BOTTOMLEFT", 0, -10)
        starterHeader:SetText("Starter Database Controls")
        
        local mergeStarterBtn = CreateFrame("Button", nil, import, "UIPanelButtonTemplate")
        mergeStarterBtn:SetSize(160, 25)
        mergeStarterBtn:SetPoint("TOPLEFT", starterHeader, "BOTTOMLEFT", 0, -10)
        mergeStarterBtn:SetText("Merge Starter DB")
        mergeStarterBtn:SetScript("OnClick", function()
            local starter = _G.ETHTweaks_OptionalDB_Data
            if starter and starter.data then
                local count, err = EHTweaks_ImportEchoes(starter.data)
                if count > 0 then
                    print("|cff00ff00EHTweaks:|r Merged Starter DB (" .. count .. " unique echoes ID's added/updated).")
                    if starter.contributors then
                         print("|cff00ff00EHTweaks:|r This Echoes DB was created thanks to: " .. starter.contributors)
                    end
                    RefreshData()
                else
                    if err == "No new data (Database already up-to-date)" then
                        print("|cffFFFF00EHTweaks:|r Merge complete. No new echoes found.")
                    else
                        print("|cffff0000EHTweaks:|r Merge failed: " .. (err or "Unknown"))
                    end
                end
            end
        end)
        
        local overrideStarterBtn = CreateFrame("Button", nil, import, "UIPanelButtonTemplate")
        overrideStarterBtn:SetSize(220, 25)
        overrideStarterBtn:SetPoint("LEFT", mergeStarterBtn, "RIGHT", 10, 0)
        overrideStarterBtn:SetText("|cffff7f00Override with Starter DB|r")
        overrideStarterBtn:SetScript("OnClick", function()
            StaticPopupDialogs["EHTWEAKS_OVERRIDE"] = {
                text = "|cffff0000WARNING:|r This will DELETE your current history and replace it with the Starter Database.\nAre you sure?",
                button1 = "Yes, Override", button2 = "Cancel",
                OnAccept = function()
                    EHTweaksDB.seenEchoes = {} 
                    local starter = _G.ETHTweaks_OptionalDB_Data
                    if starter and starter.data then
                        local count, err = EHTweaks_ImportEchoes(starter.data)
                        if count > 0 then
                            print("|cff00ff00EHTweaks:|r Database overridden with Starter DB (" .. count .. " unique echoes ID's).")
                            if starter.contributors then
                                 print("|cff00ff00EHTweaks:|r This Echoes DB was created thanks to: " .. starter.contributors)
                            end
                            RefreshData()
                        else
                            print("|cffff0000EHTweaks:|r Override failed: " .. (err or "Unknown"))
                        end
                    end
                end,
                timeout = 0, whileDead = true, hideOnEscape = true
            }
            StaticPopup_Show("EHTWEAKS_OVERRIDE")
        end)
        
        local purgeBtn = CreateFrame("Button", nil, import, "UIPanelButtonTemplate")
        purgeBtn:SetSize(120, 25)
        purgeBtn:SetPoint("LEFT", overrideStarterBtn, "RIGHT", 10, 0)
        purgeBtn:SetText("Purge DB")
        purgeBtn:SetScript("OnClick", function()
            StaticPopupDialogs["EHTWEAKS_PURGE"] = {
                text = "Are you sure you want to clear your Echoes History?\nThis cannot be undone.",
                button1 = "Yes", button2 = "No",
                OnAccept = function()
                    EHTweaksDB.seenEchoes = {}
                    isDataDirty = true
                    print("|cff00ff00EHTweaks:|r Echoes DB cleared.")
                    if activeTab == 3 then RefreshData() UpdateScroll() end
                end,
                timeout = 0, whileDead = true, hideOnEscape = true
            }
            StaticPopup_Show("EHTWEAKS_PURGE")
        end)
    else
        local purgeBtn = CreateFrame("Button", nil, import, "UIPanelButtonTemplate")
        purgeBtn:SetSize(120, 25)
        purgeBtn:SetPoint("TOPLEFT", separator, "BOTTOMLEFT", 0, -20)
        purgeBtn:SetText("Purge DB")
        purgeBtn:SetScript("OnClick", function()
            StaticPopupDialogs["EHTWEAKS_PURGE"] = {
                text = "Are you sure you want to clear your Echoes History?\nThis cannot be undone.",
                button1 = "Yes", button2 = "No",
                OnAccept = function()
                    EHTweaksDB.seenEchoes = {}
                    isDataDirty = true
                    print("|cff00ff00EHTweaks:|r Echoes DB cleared.")
                    if activeTab == 3 then RefreshData() UpdateScroll() end
                end,
                timeout = 0, whileDead = true, hideOnEscape = true
            }
            StaticPopup_Show("EHTWEAKS_PURGE")
        end)
    end
    
    f:UpdateLayout()
    return f
end

function EHTweaks_RefreshBrowser()
    -- Mark data as dirty so it rebuilds the list (re-checking favorites)
    isDataDirty = true
    
    -- If the browser frame is visible, refresh the scroll view immediately
    if browserFrame and browserFrame:IsShown() then
        -- This function (RefreshData/UpdateScroll) handles rebuilding if isDataDirty is true
        if UpdateScroll then UpdateScroll() end 
    end
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