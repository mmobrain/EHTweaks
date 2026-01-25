-- Author: Skulltrail
-- EHtweaks: Skill & Perk Browser
-- Features: Tabs (Skills/Echoes), Merged Rank Descriptions, Search, Jump to Node, Chat Links

local addonName, addon = ...

-- --- Configuration ---
local ROW_HEIGHT = 44
local MAX_ROWS = 10
local BROWSER_TITLE = "Ebonhold Compendium"

-- Quality Colors
local QUALITY_COLORS = {
    [0] = { r=1, g=1, b=1, name="Common" },
    [1] = { r=0.1, g=1, b=0.1, name="Uncommon" },
    [2] = { r=0.0, g=0.4, b=1.0, name="Rare" },
    [3] = { r=0.6, g=0.2, b=1.0, name="Epic" },
    [4] = { r=1.0, g=0.5, b=0.0, name="Legendary" }
}

-- --- Data State ---
local activeTab = 1 -- 1: Skills, 2: Echoes
local browserData = {}
local filteredData = {}
local browserFrame = nil
local isDataDirty = true

-- --- Helper: Chat Link ---
local function TryLinkToChat(spellId)
    if IsControlKeyDown() and IsAltKeyDown() and spellId then
        local link = GetSpellLink(spellId)
        
        -- Fallback if GetSpellLink returns nil (common for custom server spells)
        if not link then
            local name = GetSpellInfo(spellId)
            if name then
                link = "|cff71d5ff|Hspell:"..spellId.."|h["..name.."]|h|r"
            end
        end

        if link then
            local activeEditBox = ChatEdit_GetLastActiveWindow()
            if activeEditBox:IsVisible() then
                activeEditBox:Insert(link)
            else
                -- If no edit box is open, open one
                ChatFrame_OpenChat(link)
            end
            return true
        end
    end
    return false
end

-- --- Helper: Text Merging ---

local function GetRichDescription(data)
    if not data then return "" end

    if data.isPerk then
        if utils and utils.GetSpellDescription then
            return utils.GetSpellDescription(data.spellId, 999, data.stack)
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
                local info = instances[1]
                if info then
                    local _, _, icon = GetSpellInfo(info.spellId)
                    table.insert(data, {
                        isPerk = true,
                        name = spellName,
                        icon = icon,
                        spellId = info.spellId,
                        stack = info.stack,
                        quality = info.quality or 0
                    })
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

local function RefreshData()
    if activeTab == 1 then
        browserData = BuildTreeData()
    else
        browserData = BuildPerkData()
    end
    
    local text = browserFrame and browserFrame.searchBox:GetText() or ""
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
    isDataDirty = false
end

-- --- UI Logic ---

local function UpdateScroll()
    if isDataDirty then RefreshData() end
    
    local FauxScrollFrame_Update = FauxScrollFrame_Update
    local offset = FauxScrollFrame_GetOffset(browserFrame.scroll)
    local numItems = #filteredData
    
    for i = 1, MAX_ROWS do
        local row = browserFrame.rows[i]
        local index = offset + i
        
        if index <= numItems then
            local data = filteredData[index]
            row.data = data
            
            row.icon:SetTexture(data.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            
            if data.isPerk then
                local color = QUALITY_COLORS[data.quality] or QUALITY_COLORS[0]
                row.name:SetText(data.name)
                row.name:SetTextColor(color.r, color.g, color.b)
                row.cost:SetText("Stack: " .. data.stack)
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
    
    FauxScrollFrame_Update(browserFrame.scroll, numItems, MAX_ROWS, ROW_HEIGHT)
end

local function SetTab(id)
    activeTab = id
    isDataDirty = true
    PanelTemplates_SetTab(browserFrame, id)
    PanelTemplates_UpdateTabs(browserFrame)
    browserFrame.searchBox:SetText("") 
    UpdateScroll()
end

local function CreateBrowserFrame()
    if browserFrame then return browserFrame end
    
    local f = CreateFrame("Frame", "EHtweaks_BrowserFrame", UIParent)
    f:SetSize(400, 520)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -12)
    title:SetText(BROWSER_TITLE)
    
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)
    
    -- TABS
    f.numTabs = 2
    local tab1 = CreateFrame("Button", "$parentTab1", f, "CharacterFrameTabButtonTemplate")
    tab1:SetID(1)
    tab1:SetText("Skill Tree")
    tab1:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 20, -28)
    tab1:SetScript("OnClick", function() SetTab(1) end)
    PanelTemplates_TabResize(tab1, 0)
    
    local tab2 = CreateFrame("Button", "$parentTab2", f, "CharacterFrameTabButtonTemplate")
    tab2:SetID(2)
    tab2:SetText("My Echoes")
    tab2:SetPoint("LEFT", tab1, "RIGHT", -16, 0)
    tab2:SetScript("OnClick", function() SetTab(2) end)
    PanelTemplates_TabResize(tab2, 0)
    
    PanelTemplates_SetNumTabs(f, 2)
    PanelTemplates_SetTab(f, 1)
    PanelTemplates_UpdateTabs(f)
    
    -- Search
    local sb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    sb:SetSize(200, 20)
    sb:SetPoint("TOPLEFT", 20, -40)
    sb:SetAutoFocus(false)
    sb:SetScript("OnTextChanged", function(self)
        RefreshData()
        UpdateScroll()
    end)
    f.searchBox = sb
    
    local sbLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sbLabel:SetPoint("BOTTOMLEFT", sb, "TOPLEFT", -2, 0)
    sbLabel:SetText("Filter (Name/Desc):")
    
    -- Scroll Frame
    local sf = CreateFrame("ScrollFrame", "EHtweaks_BrowserScroll", f, "FauxScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 10, -70)
    sf:SetPoint("BOTTOMRIGHT", -30, 30)
    sf:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, UpdateScroll)
    end)
    f.scroll = sf
    
    -- Rows
    f.rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetSize(360, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 15, -70 - (i-1)*ROW_HEIGHT)
        
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
        
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        
        row:SetScript("OnEnter", function(self)
            if not self.data then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            
            if self.data.isPerk then
                local c = QUALITY_COLORS[self.data.quality]
                GameTooltip:AddLine(self.data.name, c.r, c.g, c.b)
            else
                GameTooltip:AddLine(self.data.name, 1, 1, 1)
            end
            
            local desc = GetRichDescription(self.data)
            if desc then
                GameTooltip:AddLine(desc, 1, 0.82, 0, true)
            else
                for i, spellId in ipairs(self.data.ranks or {}) do
                    local d = utils.GetSpellDescription(spellId, 999, 1)
                    GameTooltip:AddLine("Rank " .. i .. ": " .. d, 0.8, 0.8, 0.8, true)
                end
            end
            
            GameTooltip:AddLine(" ")
            
            if self.data.isPerk then
                GameTooltip:AddLine("Current Stack: " .. self.data.stack, 1, 1, 1)
            else
                GameTooltip:AddLine("Click to view in Skill Tree", 0, 1, 0)
            end
            
            GameTooltip:AddLine("Ctrl+Alt+Click to Link", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
        row:SetScript("OnClick", function(self)
            if not self.data then return end
            
            -- Chat Link Logic (Universal)
            if TryLinkToChat(self.data.spellId) then return end
            
            -- Normal Click Logic (Go To)
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
        
        f.rows[i] = row
    end
    
    browserFrame = f
    return f
end

SLASH_EHTBROWSER1 = "/eht"
SlashCmdList["EHTBROWSER"] = function(msg)
    if msg == "reset" then
        isDataDirty = true
        print("|cff00ff00EHtweaks:|r Browser data cache cleared.")
        return
    end
    local f = CreateBrowserFrame()
    f:Show()
    UpdateScroll()
end