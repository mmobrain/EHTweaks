-- Author: Skulltrail
-- EHTweaks: Skill & Perk Browser
-- Features: Tabs (Skills/My Echoes/Echoes DB/Settings/Import), Merged Rank Descriptions, Search, Jump to Node, Chat Links

local addonName, addon = ...
local LibDeflate = LibStub:GetLibrary("LibDeflate")


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
                    -- Sum all stacks and find highest quality
                    local totalStack = 0
                    local highestQuality = 0
                    local primarySpellId = nil
                    local icon = nil
                    
                    for _, info in ipairs(instances) do
                        totalStack = totalStack + (info.stack or 1)
                        
                        if (info.quality or 0) > highestQuality then
                            highestQuality = info.quality or 0
                            primarySpellId = info.spellId
                        end
                        
                        if not primarySpellId then
                            primarySpellId = info.spellId
                        end
                    end
                    
                    if primarySpellId then
                        local _, _, iconTex = GetSpellInfo(primarySpellId)
                        table.insert(data, {
                            isPerk = true,
                            name = spellName,
                            icon = iconTex,
                            spellId = primarySpellId,
                            stack = totalStack,
                            quality = highestQuality
                        })
                    end
                end
            end
        end
    end
    table.sort(data, function(a, b) 
        if a.quality ~= b.quality then return a.quality > b.quality end
        return a.name < b.name 
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
                
                local q = math.abs(info.quality or 0)
                groups[name].qualities[q] = spellId
                
                if q > groups[name].highestQ then
                    groups[name].highestQ = q
                    groups[name].icon = info.icon
                end
            end
        end
    end
    
    for name, group in pairs(groups) do
        table.insert(data, {
            isPerk = true,
            isHistory = true,
            name = name,
            icon = group.icon,
            spellId = group.qualities[group.highestQ], -- Use highest quality ID for main display/tooltip
            quality = group.highestQ,
            qualityMap = group.qualities -- For pips
        })
    end

    table.sort(data, function(a, b) 
        if a.quality ~= b.quality then return a.quality > b.quality end
        return a.name < b.name 
    end)
    return data
end

local function RefreshData()
    if activeTab == 1 then
        browserData = BuildTreeData()
    elseif activeTab == 2 then
        browserData = BuildPerkData()
    elseif activeTab == 3 then
        browserData = BuildHistoryData()
    else
        browserData = {}
    end
    
    local text = (browserFrame and browserFrame.searchBox and browserFrame.searchBox:GetText()) or ""
    if text == "" then
        filteredData = browserData
    else
        text = string.lower(text)
        local res = {}
        for _, entry in ipairs(browserData) do
            if string.find(string.lower(entry.name), text, 1, true) then
                table.insert(res, entry)
            else
                local desc = GetRichDescription(entry)
                if desc and string.find(string.lower(desc), text, 1, true) then
                    table.insert(res, entry)
                end
            end
        end
        filteredData = res
    end
    
    -- --- Update Tab Counts ---
    if browserFrame and browserFrame.tabs then
        local treeC = #BuildTreeData()
        local myC = #BuildPerkData()
        local dbC = #BuildHistoryData()
        
        browserFrame.tabs[1]:SetText("Skill Tree (" .. treeC .. ")")
        browserFrame.tabs[2]:SetText("My Echoes (" .. myC .. ")")
        browserFrame.tabs[3]:SetText("Echoes DB (" .. dbC .. ")")
        
        PanelTemplates_TabResize(browserFrame.tabs[1], 0)
        PanelTemplates_TabResize(browserFrame.tabs[2], 0)
        PanelTemplates_TabResize(browserFrame.tabs[3], 0)
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
        EHTweaks_Log(string.format("Pack: ID=%d, Q=%d, Name=%s", spellId, quality, tostring(info.name)))
        count = count + 1
    end
    EHTweaks_Log("Total items to export: " .. count)
    
    -- Manual Serialization (simple string concat for 3.3.5 stability vs AceSerializer)
    -- Format: id:q,id:q,id:q
    local parts = {}
    for _, entry in ipairs(exportTable) do
        table.insert(parts, entry[1] .. ":" .. entry[2])
    end
    local rawString = table.concat(parts, ",")
    
    -- Compress
    local compressed = LibDeflate:CompressDeflate(rawString)
    -- Encode
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
    
    EHTweaks_Log("Raw String Length: " .. string.len(rawString))
    
    -- Deserialize (simple split)
    local imported = 0
    if not EHTweaksDB.seenEchoes then EHTweaksDB.seenEchoes = {} end
    
    for entryStr in string.gmatch(rawString, "([^,]+)") do
        -- FIX: Regex updated to accept optional negative sign (-?%d+) to handle legacy -0 imports
        local idStr, qStr = string.match(entryStr, "(%d+):(-?%d+)")
        if idStr and qStr then
            local spellId = tonumber(idStr)
            local quality = tonumber(qStr)
            quality = math.abs(quality) -- Normalize just in case
            
            -- Validate Spell Exists locally
            local name, _, icon = GetSpellInfo(spellId)
            if name then
                if not EHTweaksDB.seenEchoes[spellId] then
                    EHTweaksDB.seenEchoes[spellId] = {
                        name = name,
                        icon = icon,
                        quality = quality
                    }
                    imported = imported + 1
                    EHTweaks_Log("Imported NEW: " .. name .. " (" .. spellId .. ") Q=" .. quality)
                else
                    -- Merge strategy: Keep highest quality
                    local oldQ = math.abs(EHTweaksDB.seenEchoes[spellId].quality or 0)
                    if quality > oldQ then
                        EHTweaksDB.seenEchoes[spellId].quality = quality
                        imported = imported + 1 -- Count quality upgrade as import
                        EHTweaks_Log("Imported UPGRADE: " .. name .. " (" .. spellId .. ") Q=" .. oldQ .. "->" .. quality)
                    else
                        -- EHTweaks_Log("Skipped (Existing Better/Equal): " .. name .. " (" .. spellId .. ")")
                    end
                end
            else
                EHTweaks_Log("Skipped (Unknown SpellID): " .. spellId)
            end
        else
            EHTweaks_Log("Skipped (Malformed Entry): " .. tostring(entryStr))
        end
    end
    
    EHTweaks_Log("Import Finished. Total processed: " .. imported)
    return imported
end

-- --- UI Logic ---

local function UpdateScroll()
    if not browserFrame then return end 

    if activeTab >= 4 then -- Settings or Import/Export
        -- Hide List UI components
        if browserFrame.scroll then browserFrame.scroll:Hide() end
        if browserFrame.searchBox then browserFrame.searchBox:Hide() end
        if browserFrame.searchLabel then browserFrame.searchLabel:Hide() end
        
        -- HIDE ALL ROWS
        if browserFrame.rows then
            for _, row in ipairs(browserFrame.rows) do
                row:Hide()
            end
        end
        
        -- Toggle Frames
        if activeTab == 4 then
            if browserFrame.settingsFrame then browserFrame.settingsFrame:Show() end
            if browserFrame.importFrame then browserFrame.importFrame:Hide() end
        else
            if browserFrame.settingsFrame then browserFrame.settingsFrame:Hide() end
            if browserFrame.importFrame then browserFrame.importFrame:Show() end
        end
        return
    else
        -- Show List UI
        if browserFrame.scroll then browserFrame.scroll:Show() end
        if browserFrame.searchBox then browserFrame.searchBox:Show() end
        if browserFrame.searchLabel then browserFrame.searchLabel:Show() end
        
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
                
                if data.isPerk then
                    local color = QUALITY_COLORS[data.quality] or QUALITY_COLORS[0]
                    row.name:SetText(data.name)
                    row.name:SetTextColor(color.r, color.g, color.b)
                    
                    if data.isHistory then
                        -- Render C U R E L pips
                        local pips = ""
                        local map = data.qualityMap or {}
                        
                        if map[0] then pips = pips .. "|cffffffffC|r " else pips = pips .. "|cff555555C|r " end
                        if map[1] then pips = pips .. "|cff1eff00U|r " else pips = pips .. "|cff555555U|r " end
                        if map[2] then pips = pips .. "|cff0070ddR|r " else pips = pips .. "|cff555555R|r " end
                        if map[3] then pips = pips .. "|cffa335eeE|r " else pips = pips .. "|cff555555E|r " end
                        if map[4] then pips = pips .. "|cffff8000L|r"  else pips = pips .. "|cff555555L|r"  end
                        
                        row.cost:SetText(pips)
                        
                        -- Type text is Rarity Name (e.g. "Rare") based on highest discovered
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
        PanelTemplates_SetTab(browserFrame, id)
        PanelTemplates_UpdateTabs(browserFrame)
        if browserFrame.searchBox then browserFrame.searchBox:SetText("") end
    end
    UpdateScroll()
end

local function CreateBrowserFrame()
    if browserFrame then return browserFrame end

    local f = CreateFrame("Frame", "EHTweaks_BrowserFrame", UIParent)
    f:SetSize(480, 520)
    f:SetMinResize(480, 400)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:SetResizable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    
    -- Sleek Backdrop
    f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = {left = 0, right = 0, top = 0, bottom = 0},
    })
    f:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    f:SetBackdropBorderColor(0, 0, 0, 1)
    
    browserFrame = f
    
    -- Title Background Stripe
    local titleBg = f:CreateTexture(nil, "BACKGROUND")
    titleBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    titleBg:SetVertexColor(0.2, 0.2, 0.2, 1)
    titleBg:SetHeight(24)
    titleBg:SetPoint("TOPLEFT", 1, -1)
    titleBg:SetPoint("TOPRIGHT", -1, -1)
    
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -6)
    title:SetText(BROWSER_TITLE)
    
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetSize(24, 24)
    
    -- TABS (Top Navigation Style)
    f.numTabs = 5
    f.tabs = {}
    
    local function CreateNavTab(id, text, x)
        local tab = CreateFrame("Button", "$parentTab"..id, f)
        tab:SetID(id)
        tab:SetText(text)
        tab:SetSize(90, 24)
        
        -- Style
        tab:SetNormalFontObject("GameFontNormalSmall")
        tab:SetHighlightFontObject("GameFontHighlightSmall")
        
        local bg = tab:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        bg:SetVertexColor(0.15, 0.15, 0.15, 1)
        tab.bg = bg
        
        tab:SetScript("OnEnter", function(self) self.bg:SetVertexColor(0.25, 0.25, 0.25, 1) end)
        tab:SetScript("OnLeave", function(self) 
             if activeTab ~= self:GetID() then
                 self.bg:SetVertexColor(0.15, 0.15, 0.15, 1) 
             else
                 self.bg:SetVertexColor(0.3, 0.3, 0.3, 1)
             end
        end)
        tab:SetScript("OnClick", function() SetTab(id) end)
        
        return tab
    end
    
    local tab1 = CreateNavTab(1, "Skills", 0)
    tab1:SetPoint("TOPLEFT", f, "TOPLEFT", 5, -30)
    f.tabs[1] = tab1
    
    local tab2 = CreateNavTab(2, "My Echoes", 0)
    tab2:SetPoint("LEFT", tab1, "RIGHT", 2, 0)
    f.tabs[2] = tab2
    
    local tab3 = CreateNavTab(3, "Echoes DB", 0)
    tab3:SetPoint("LEFT", tab2, "RIGHT", 2, 0)
    f.tabs[3] = tab3
    
    local tab4 = CreateNavTab(4, "Settings", 0)
    tab4:SetPoint("LEFT", tab3, "RIGHT", 2, 0)
    f.tabs[4] = tab4
    
    local tab5 = CreateNavTab(5, "Import", 0)
    tab5:SetPoint("LEFT", tab4, "RIGHT", 2, 0)
    f.tabs[5] = tab5
    
    -- Hook SetTab to style nav buttons
    hooksecurefunc("PanelTemplates_SetTab", function(frame, id)
        if frame ~= f then return end
        for k, t in ipairs(f.tabs) do
             if k == id then
                 t.bg:SetVertexColor(0.3, 0.3, 0.3, 1)
             else
                 t.bg:SetVertexColor(0.15, 0.15, 0.15, 1)
             end
        end
    end)

    -- Search
    local sb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    sb:SetSize(200, 20)
    sb:SetPoint("TOPRIGHT", -30, -32)
    sb:SetAutoFocus(false)
    sb:SetScript("OnTextChanged", function(self)
        RefreshData()
        UpdateScroll()
    end)
    f.searchBox = sb
    
    local sbLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sbLabel:SetPoint("RIGHT", sb, "LEFT", -5, 0)
    sbLabel:SetText("Filter:")
    f.searchLabel = sbLabel
    
    -- Clear Button for Browser Search
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
        RefreshData()
        UpdateScroll()
    end)
    
    -- Scroll Frame
    local sf = CreateFrame("ScrollFrame", "EHTweaks_BrowserScroll", f, "FauxScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -70)
    sf:SetPoint("BOTTOMRIGHT", -30, 30)
    sf:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, UpdateScroll)
    end)
    f.scroll = sf
    
    -- Resize Handle
    local resize = CreateFrame("Button", nil, f)
    resize:SetSize(16, 16)
    resize:SetPoint("BOTTOMRIGHT")
    resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resize:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resize:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    resize:SetScript("OnMouseUp", function() f:StopMovingOrSizing() end)
    f.resizeBtn = resize

    -- Dynamic Row Creator
    f.CreateRows = function(self)
        local h = self:GetHeight()
        local availableH = h - 90 -- Top + Bottom padding
        local count = math.floor(availableH / ROW_HEIGHT)
        if count < MIN_ROWS then count = MIN_ROWS end
        self.maxRows = count
        
        if not self.rows then self.rows = {} end
        
        for i = 1, count do
            if not self.rows[i] then
                local row = CreateFrame("Button", nil, f)
                row:SetSize(424, ROW_HEIGHT)
                -- We set points dynamically in UpdateLayout
                
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
                
                local cost = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                cost:SetPoint("RIGHT", -10, 0)
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
                                    local desc = utils.GetSpellDescription(sID, 999, 1)
                                    GameTooltip:AddLine(qName, qColor.r, qColor.g, qColor.b)
                                    GameTooltip:AddLine(desc, 1, 0.82, 0, true)
                                    GameTooltip:AddLine(" ")
                                end
                            end
                        else
                            local c = QUALITY_COLORS[self.data.quality]
                            GameTooltip:AddLine(self.data.name, c.r, c.g, c.b)
                            local desc = GetRichDescription(self.data)
                            if desc then GameTooltip:AddLine(desc, 1, 0.82, 0, true) end
                            GameTooltip:AddLine(" ")
                            GameTooltip:AddLine("Current Stack: " .. self.data.stack, 1, 1, 1)
                        end
                    else
                        GameTooltip:AddLine(self.data.name, 1, 1, 1)
                        for i, spellId in ipairs(self.data.ranks or {}) do
                            local d = utils.GetSpellDescription(spellId, 999, 1)
                            GameTooltip:AddLine("Rank " .. i .. ": " .. d, 0.8, 0.8, 0.8, true)
                        end
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("Click to view in Skill Tree", 0, 1, 0)
                    end
                    GameTooltip:AddLine("Ctrl+Alt+Click to Link", 0.6, 0.6, 0.6)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function() GameTooltip:Hide() end)
                
                row:SetScript("OnClick", function(self)
                    if not self.data then return end
                    if EHTweaks_HandleLinkClick(self.data.spellId) then return end
                    if self.data.isPerk then return end
                    if _G.skillTreeFrame then _G.skillTreeFrame:Show() end
                    local btn = _G["skillTreeNode" .. self.data.nodeId]
                    if btn and _G.skillTreeScroll then
                        local scroll = _G.skillTreeScroll
                        local _, _, _, xOfs, yOfs = btn:GetPoint(1)
                        if xOfs then
                           scroll:SetHorizontalScroll(math.max(0, xOfs - (scroll:GetWidth()/2)))
                           scroll:SetVerticalScroll(math.max(0, math.abs(yOfs) - (scroll:GetHeight()/2)))
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
        local contentW = w - 40 -- margins
        
        self.scroll:SetPoint("BOTTOMRIGHT", -30, 30)
        self.searchBox:SetWidth(w - 260)
        
        for i, row in ipairs(self.rows) do
             row:SetWidth(contentW)
             row:SetPoint("TOPLEFT", 15, -70 - (i-1)*ROW_HEIGHT)
        end
        UpdateScroll()
    end
    
    f:SetScript("OnSizeChanged", function(self)
        self:UpdateLayout()
    end)
    
    -- Initial Layout
    f:UpdateLayout()

    
    -- SETTINGS FRAME
    local settings = CreateFrame("Frame", nil, f)
    settings:SetAllPoints(f)
    settings:Hide()
    f.settingsFrame = settings
    
    local sTitle = settings:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    sTitle:SetPoint("TOPLEFT", 20, -50)
    sTitle:SetText("EHTweaks Settings")
    
    local cb1 = CreateFrame("CheckButton", "EHTweaks_CB_Filters", settings, "UICheckButtonTemplate")
    cb1:SetPoint("TOPLEFT", sTitle, "BOTTOMLEFT", 0, -20)
    _G[cb1:GetName().."Text"]:SetText("Enhance Project Ebonhold with Filters")
    cb1:SetScript("OnClick", function(self)
        if EHTweaksDB then
            EHTweaksDB.enableFilters = self:GetChecked() and true or false
        end
    end)
    -- Init state
    if EHTweaksDB then cb1:SetChecked(EHTweaksDB.enableFilters) end
    
     local cb2 = CreateFrame("CheckButton", "EHTweaks_CB_Links", settings, "UICheckButtonTemplate")
    cb2:SetPoint("TOPLEFT", cb1, "BOTTOMLEFT", 0, -10)
    _G[cb2:GetName().."Text"]:SetText("Enhance Project Ebonhold with Chat Links")
    cb2:SetScript("OnClick", function(self)
        if EHTweaksDB then
            EHTweaksDB.enableChatLinks = self:GetChecked() and true or false
        end
    end)
    if EHTweaksDB then cb2:SetChecked(EHTweaksDB.enableChatLinks) end

    -- Objective Tracker Checkbox
    local cb3 = CreateFrame("CheckButton", "EHTweaks_CB_Tracker", settings, "UICheckButtonTemplate")
    cb3:SetPoint("TOPLEFT", cb2, "BOTTOMLEFT", 0, -10)
    _G[cb3:GetName().."Text"]:SetText("Enhance Project Ebonhold with Objective Tracker")
    cb3:SetScript("OnClick", function(self)
        if EHTweaksDB then
            EHTweaksDB.enableTracker = self:GetChecked() and true or false
            -- Immediately update visibility
            if _G.ProjectEbonhold and _G.ProjectEbonhold.ObjectivesService then
                 UpdateEHObjectiveDisplay(_G.ProjectEbonhold.ObjectivesService.GetActiveObjective())
            end
        end
    end)
    if EHTweaksDB then cb3:SetChecked(EHTweaksDB.enableTracker) end
    
    -- Apply & Reload Button
    local reloadBtn = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
    reloadBtn:SetSize(160, 30)
    reloadBtn:SetPoint("TOPLEFT", cb3, "BOTTOMLEFT", 0, -30)
    reloadBtn:SetText("Apply and Reload UI")
    reloadBtn:SetScript("OnClick", function()
        ReloadUI()
    end)
    
    local warn = settings:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    warn:SetPoint("TOPLEFT", reloadBtn, "BOTTOMLEFT", 0, -10)
    warn:SetText("Note: Browser features (this window) will remain active\nregardless of these settings.")
    warn:SetTextColor(0.6, 0.6, 0.6)
    
    -- IMPORT / EXPORT FRAME
    local import = CreateFrame("Frame", nil, f)
    import:SetAllPoints(f)
    import:Hide()
    f.importFrame = import
    
    local iTitle = import:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    iTitle:SetPoint("TOPLEFT", 20, -50)
    iTitle:SetText("Import / Export")
    
    local h1 = import:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h1:SetPoint("TOPLEFT", iTitle, "BOTTOMLEFT", 0, -20)
    h1:SetText("Share your Echoes DB with others.")    
    
    local exportBtn = CreateFrame("Button", nil, import, "UIPanelButtonTemplate")
    exportBtn:SetSize(160, 30)
    exportBtn:SetPoint("TOPLEFT", h1, "BOTTOMLEFT", 0, -10)
    exportBtn:SetText("Export Echoes")
    exportBtn:SetScript("OnClick", function()
    -- Ensure DB is current before export
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
    
    StaticPopupDialogs["EHTWEAKS_EXPORT"] = {
        text = "Echoes DB Export String:\\n(Ctrl+C to copy)",
        button1 = "Close",
        hasEditBox = true,
        maxLetters = 999999,
        editBoxWidth = 350,
        OnShow = function(self)
            local str = EHTweaks_ExportEchoes()
            self.editBox:SetText(str)
            self.editBox:HighlightText()
            self.editBox:SetFocus()
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true
    }
    StaticPopup_Show("EHTWEAKS_EXPORT")
end)

      
    
    -- Anchor to exportBtn instead of div to maintain left alignment
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
        StaticPopupDialogs["EHTWEAKS_IMPORT"] = {
            text = "Paste Export String here:\n(Ctrl+V. Imports are merged)",
            button1 = "Import",
            button2 = "Cancel",
            hasEditBox = true,
            maxLetters = 999999,
            editBoxWidth = 350,
            OnAccept = function(self)
                local code = self.editBox:GetText()
                local count, err = EHTweaks_ImportEchoes(code)
                if count > 0 then
                    print("|cff00ff00EHTweaks:|r Successfully imported " .. count .. " new/upgraded Echoes.")
                    RefreshData() -- Refresh list immediately if open
                else
                    print("|cffff0000EHTweaks:|r Import failed: " .. (err or "No new data found."))
                end
            end,
            EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
            timeout = 0, whileDead = true, hideOnEscape = true
        }
        StaticPopup_Show("EHTWEAKS_IMPORT")
    end)
    
    local separator = import:CreateTexture(nil, "ARTWORK")
    separator:SetHeight(1)
    separator:SetPoint("TOPLEFT", importBtn, "BOTTOMLEFT", 0, -20)
    separator:SetPoint("RIGHT", -20, 0)
    separator:SetTexture("Interface\\Buttons\\WHITE8X8")
    separator:SetVertexColor(0.3, 0.3, 0.3, 0.5)
    
    -- Starter DB Controls (Manual)
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
                    print("|cff00ff00EHTweaks:|r Merged Starter DB (" .. count .. " echoes added/updated).")
                    RefreshData()
                else
                    print("|cffff0000EHTweaks:|r Merge failed: " .. (err or "Unknown"))
                end
            end
        end)
        
        local overrideStarterBtn = CreateFrame("Button", nil, import, "UIPanelButtonTemplate")
        overrideStarterBtn:SetSize(180, 25)
        overrideStarterBtn:SetPoint("LEFT", mergeStarterBtn, "RIGHT", 10, 0)
        overrideStarterBtn:SetText("|cffff7f00Override with Starter DB|r")
        overrideStarterBtn:SetScript("OnClick", function()
            StaticPopupDialogs["EHTWEAKS_OVERRIDE"] = {
                text = "|cffff0000WARNING:|r This will DELETE your current history and replace it with the Starter Database.\nAre you sure?",
                button1 = "Yes, Override",
                button2 = "Cancel",
                OnAccept = function()
                    EHTweaksDB.seenEchoes = {} -- Wipe first
                    local starter = _G.ETHTweaks_OptionalDB_Data
                    if starter and starter.data then
                        local count, err = EHTweaks_ImportEchoes(starter.data)
                        if count > 0 then
                            print("|cff00ff00EHTweaks:|r Database overridden with Starter DB (" .. count .. " echoes).")
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
    end
    
    -- Purge Button (Bottom Right)
    local purgeBtn = CreateFrame("Button", nil, import, "UIPanelButtonTemplate")
    purgeBtn:SetSize(120, 25)
    purgeBtn:SetPoint("BOTTOMRIGHT", -20, 20)
    purgeBtn:SetText("Purge DB")
    purgeBtn:SetScript("OnClick", function()
        StaticPopupDialogs["EHTWEAKS_PURGE"] = {
            text = "Are you sure you want to clear your Echoes History?\nThis cannot be undone.",
            button1 = "Yes",
            button2 = "No",
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