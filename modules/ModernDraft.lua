-- Author: Skulltrail
-- EHTweaks: Modern Draft UI
-- Features: Vertical List Layout, Saved Positions, Stat Summary Parser, Synced Favorites, Right-Click "FAV" Support, Modern Draft UI.

local addonName, addon = ...
_G.EHTweaks = _G.EHTweaks or addon
EHTweaks.ModernDraft = {}
local MD = EHTweaks.ModernDraft

local CARD_WIDTH = 340
local CARD_MIN_HEIGHT = 70
local CARD_SPACING = 8
local STAT_PANEL_WIDTH = 180
local descScale = 1.15

local QUALITYINFO = {
    [0] = { r=1.0, g=1.0, b=1.0, border="perk_border_quality_0", bg="perk_quality_0" },
    [1] = { r=0.1, g=1.0, b=0.1, border="perk_border_quality_1", bg="perk_quality_1" },
    [2] = { r=0.0, g=0.4, b=1.0, border="perk_border_quality_2", bg="perk_quality_2" },
    [3] = { r=0.6, g=0.2, b=1.0, border="perk_border_quality_3", bg="perk_quality_3" },
    [4] = { r=1.0, g=0.5, b=0.0, border="perk_border_quality_4", bg="perk_quality_4" },
}

local STAT_MAP = {
    ["sp"] = "Spell Power",
    ["ap"] = "Attack Power",
    ["stamina"] = "Stamina",
    ["armor"] = "Armor",
    ["str"] = "Strength",
    ["agi"] = "Agility",
    ["int"] = "Intellect",
    ["spi"] = "Spirit",
    ["flat"] = "Bonus",
}

local mainFrame = nil
local restoreBtn = nil
local cardPool = {}
local currentChoices = {}
local isSelecting = false
local currentOwnedStats = {}

local rerollPollSeq = 0
local lastChoiceRequestAt = 0

local scanner = _G["EHT_DraftScanner"] or CreateFrame("GameTooltip", "EHT_DraftScanner", nil, "GameTooltipTemplate")
scanner:SetOwner(WorldFrame, "ANCHOR_NONE")

local function GetCardDescription(spellId, stack)
    
    
    if utils and utils.GetSpellDescription then
        local desc = utils.GetSpellDescription(spellId, 500, stack or 1)
        if desc and desc ~= "" and desc ~= "Click for details" then 
            return desc 
        end
    end

    
    scanner:ClearLines()
    scanner:SetHyperlink("spell:" .. spellId)
    local lines = scanner:NumLines()
    if lines < 1 then return "" end
    
    local desc = ""
    
    for i = 2, lines do
        local lineObj = _G["EHT_DraftScannerTextLeft" .. i]
        if lineObj then
            local text = lineObj:GetText()
            if text then
                 
                 if not text:find("^Rank %d") and not text:find("^Next Rank:") then
                     if desc ~= "" then desc = desc .. "\n" end
                     desc = desc .. text
                end
            end
        end
    end
    return desc
end

local function GetBanishInfo()
    if not ProjectEbonhold.Constants
    or not ProjectEbonhold.Constants.ENABLE_BANISH_SYSTEM then
        return 0
    end
    local runData = ProjectEbonhold.PlayerRunService
        and ProjectEbonhold.PlayerRunService.GetCurrentData() or {}
    local remaining = runData.remainingBanishes or 0
    if remaining == 0 then
        local g = _G["EbonholdPlayerRunData"] or {}
        if g.remainingBanishes and g.remainingBanishes > 0 then
            remaining = g.remainingBanishes
        end
    end
    return remaining
end

local function UpdateBanishButtons()
    if not mainFrame or not mainFrame:IsShown() then return end
    local remaining = GetBanishInfo()
    for _, card in ipairs(cardPool) do
        if card and card:IsShown() and card.banBtn then
            if remaining > 0 then
                card.banBtn:SetText("Ban (" .. remaining .. ")")
                card.banBtn:Enable()
                card.banBtn:EnableMouse(true)
            else
                card.banBtn:SetText("Ban")
                card.banBtn:Disable()
                card.banBtn:EnableMouse(false)
            end
        end
    end
end

function MD.BanishOption(index)
    if isSelecting then return end
    if not currentChoices or not currentChoices[index] then return end
    local remaining = GetBanishInfo()
    if remaining <= 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000No banishes remaining.|r")
        return
    end
    isSelecting = true
    
    for _, card in ipairs(cardPool) do
        if card and card:IsShown() then
            card.btn:EnableMouse(false)
            if card.banBtn then card.banBtn:EnableMouse(false) end
        end
    end
    
    local success = ProjectEbonhold.PerkService.BanishPerk(index - 1)
    if not success then
        isSelecting = false
        for _, card in ipairs(cardPool) do
            if card and card:IsShown() then
                card.btn:EnableMouse(true)
                if card.banBtn then card.banBtn:EnableMouse(true) end
            end
        end
    end
end

local function CalculateCardHeight(descText, descFontString, cardIndex, spellId)
    local minH = CARDMINHEIGHT or CARD_MIN_HEIGHT or 70

    if not descText or descText == "" then
        if EHTweaksDB and EHTweaksDB.debugModernDraftHeight then
            print("EHTweaks:MD:CalcHeight:card:" .. (cardIndex or 0) .. ":spell:" .. (spellId or 0) .. ":empty:1:minH:" .. minH)
        end
        return minH
    end

    
    if not _G.EHT_MeasureFont then
        local f = CreateFrame("Frame", nil, UIParent)
        f:Hide()
        _G.EHT_MeasureFont = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        _G.EHT_MeasureFont:SetJustifyH("LEFT")
        _G.EHT_MeasureFont:SetJustifyV("TOP")
        _G.EHT_MeasureFont:SetWordWrap(true)
    end

    local measure = _G.EHT_MeasureFont

    
    local width = 270
    local fontPath, fontSize, fontFlags

    if descFontString then
        local w = descFontString:GetWidth()
        if w and w > 1 then
            width = w
        end

        fontPath, fontSize, fontFlags = descFontString:GetFont()
    end

    if fontPath and fontSize then
        measure:SetFont(fontPath, fontSize, fontFlags)
    else
        
        measure:SetFontObject("GameFontHighlight")
        local p, s, fl = measure:GetFont()
        fontPath, fontSize, fontFlags = p, s, fl
    end

    measure:SetWidth(width)
    measure:SetText(descText)

    local textHeight = measure:GetStringHeight() or 0

    
    local topArea = 38
    local bottomPad = 12
    local neededHeight = topArea + textHeight*descScale + bottomPad
    local finalHeight = math.max(minH, math.ceil(neededHeight))

    if EHTweaksDB and EHTweaksDB.debugModernDraftHeight then
        print(
            "EHTweaks:MD:CalcHeight"
            .. ":card:" .. (cardIndex or 0)
            .. ":spell:" .. (spellId or 0)
            .. ":w:" .. (math.floor(width) or 0)
            .. ":font:" .. (math.floor(fontSize or 0) or 0)
            .. ":textH:" .. (math.floor(textHeight) or 0)
            .. ":need:" .. (math.floor(neededHeight) or 0)
            .. ":final:" .. (finalHeight or 0)
        )
    end

    return finalHeight+22
end

local function RecalculateLayout()
    local cardSpacing = CARDSPACING or CARD_SPACING or 8
    local cardWidth   = CARDWIDTH   or CARD_WIDTH   or 340

    if not mainFrame or not mainFrame:IsShown() then return end
    if not mainFrame.cardContainer then return end

    
    local visibleCards = {}
    for i = 1, #cardPool do
        local card = cardPool[i]
        if card and card:IsShown() then
            table.insert(visibleCards, { card = card, poolIndex = i })
        end
    end

    if #visibleCards == 0 then return end

    local cardHeights = {}
    local totalHeight = 0

    for idx, entry in ipairs(visibleCards) do
        local card = entry.card
        local descText = card.desc and card.desc:GetText() or ""
        local spellId = card.data and card.data.spellId or 0

        local h = CalculateCardHeight(descText, card.desc, entry.poolIndex, spellId)

        cardHeights[idx] = h
        totalHeight = totalHeight + h

        if EHTweaksDB and EHTweaksDB.debugModernDraftHeight and card.desc then
            local liveH = card.desc:GetStringHeight() or 0
            print(
                "EHTweaks:MD:Reflow"
                .. ":card:" .. (entry.poolIndex or 0)
                .. ":spell:" .. (spellId or 0)
                .. ":liveTextH:" .. (math.floor(liveH) or 0)
                .. ":cardH:" .. (h or 0)
            )
        end
    end

    totalHeight = totalHeight + cardSpacing * math.max(0, #visibleCards - 1)

    local currentY = 0
    for idx, entry in ipairs(visibleCards) do
        local card = entry.card
        local h = cardHeights[idx]

        card:SetSize(cardWidth, h)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", mainFrame.cardContainer, "TOPLEFT", 0, -currentY)

        currentY = currentY + h + cardSpacing
    end

    mainFrame.cardContainer:SetHeight(totalHeight)
    if mainFrame.statPanel then
        mainFrame.statPanel:SetHeight(totalHeight)
    end
    mainFrame:SetHeight(math.max(totalHeight + 90, 200))

    if EHTweaksDB and EHTweaksDB.debugModernDraftHeight then
        print("EHTweaks:MD:Reflow:total:" .. (math.floor(totalHeight) or 0))
    end
end

local function GetRerollInfo()
    
    if ProjectEbonhold and ProjectEbonhold.PerkUI then
        local perkUI = ProjectEbonhold.PerkUI
        if perkUI.totalRerolls ~= nil and perkUI.usedRerolls ~= nil then
            local total = tonumber(perkUI.totalRerolls) or 0
            local used = tonumber(perkUI.usedRerolls) or 0
            return math.max(0, total - used), total
        end
    end
    
    
    local runData = _G.EbonholdPlayerRunData
    if runData then
        local used = tonumber(runData.usedRerolls) or 0
        local total = tonumber(runData.totalRerolls) or 0
        return math.max(0, total - used), total
    end
    
    
    if ProjectEbonhold and ProjectEbonhold.PlayerRunService and ProjectEbonhold.PlayerRunService.GetCurrentData then
        runData = ProjectEbonhold.PlayerRunService.GetCurrentData()
        if runData then
            local used = tonumber(runData.usedRerolls) or 0
            local total = tonumber(runData.totalRerolls) or 0
            return math.max(0, total - used), total
        end
    end
    
    return 0, 0
end

local function UpdateRerollButton()
    if not mainFrame or not mainFrame.rerollBtn then return end
    local avail, total = GetRerollInfo()
    mainFrame.rerollBtn:SetText("Reroll (" .. avail .. "/" .. total .. ")")
    if avail <= 0 then mainFrame.rerollBtn:Disable() else mainFrame.rerollBtn:Enable() end
end

function MD.UpdateInPlace(choices)
    if not mainFrame or not mainFrame:IsShown() then
        MD.Show(choices)
        return
    end

    if not choices or #choices == 0 then
        return
    end

    currentChoices = choices
    isSelecting = false

    local qi = QUALITYINFO
    local thinBackdrop = BACKDROPTHIN or BACKDROP_THIN

    for i, data in ipairs(choices) do
        local card = cardPool[i]
        if not card or not card:IsShown() then break end

        local oldData = card.data
        local newStack = data.stack or 1
        local oldStack = oldData and (oldData.stack or 1) or nil

        local needsTextUpdate =
            (not oldData) or
            (oldData.spellId ~= data.spellId) or
            (oldStack ~= newStack)

        local needsQualityUpdate =
            (not oldData) or
            (oldData.quality ~= data.quality)

        local name, _, icon = nil, nil, nil
        if needsTextUpdate or needsQualityUpdate then
            name, _, icon = GetSpellInfo(data.spellId)
        end

        local qInfo = nil
        if qi then
            qInfo = qi[data.quality] or qi[0]
        end
        if not qInfo then
            qInfo = { r = 1, g = 1, b = 1 }
        end

        
        card.qInfo = qInfo
        card.data = data
        card.data.name = name or (oldData and oldData.name) or nil
        card.cardIndex = i

        if needsTextUpdate then
            card.name:SetText(name or "Unknown Echo")
            card.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            card.desc:SetText(GetCardDescription(data.spellId, newStack))
        end

        if needsQualityUpdate or needsTextUpdate then
            card.name:SetTextColor(qInfo.r or 1, qInfo.g or 1, qInfo.b or 1)
        end

        
        if thinBackdrop then
            card:SetBackdrop(thinBackdrop)
        end
        card:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        card:SetBackdropBorderColor(qInfo.r or 1, qInfo.g or 1, qInfo.b or 1, 1)

        
        local capturedIndex = i
        card.btn:SetScript("OnClick", function()
            MD.SelectOption(capturedIndex)
        end)

        if card.banBtn then
            card.banBtn:SetScript("OnClick", function()
                MD.BanishOption(capturedIndex)
            end)
        end
    end

    
    RecalculateLayout()

    for _, card in ipairs(cardPool) do
        if card and card:IsShown() then
            card.btn:EnableMouse(true)
            if card.banBtn then
                card.banBtn:EnableMouse(true)
            end
        end
    end

    UpdateBanishButtons()
    UpdateRerollButton()
end

local function GetSpellStats(spellId, stacks)
    stacks = stacks or 1
    local results = {}
    
    scanner:ClearLines()
    scanner:SetHyperlink("spell:" .. spellId)
    
    for i = 1, scanner:NumLines() do
        local line = _G[scanner:GetName() .. "TextLeft" .. i]
        if line then
            local text = line:GetText()
            if text then
                for formula in text:gmatch("%[.-%]") do
                    local statKey, multiplierStr = formula:match("%[(%a+)%*(.-)%]")
                    if statKey and multiplierStr then
                        local multiplier = tonumber(multiplierStr) or 0
                        results[statKey] = (results[statKey] or 0) + (multiplier * stacks)
                    end
                end
            end
        end
    end
    return results
end

local function CalculateAllOwnedStats()
    local total = {}
    if ProjectEbonhold.PerkService and ProjectEbonhold.PerkService.GetGrantedPerks then
        local granted = ProjectEbonhold.PerkService.GetGrantedPerks()
        for _, instances in pairs(granted) do
            for _, info in ipairs(instances) do
                local stats = GetSpellStats(info.spellId, info.stack or 1)
                for k, v in pairs(stats) do
                    total[k] = (total[k] or 0) + v
                end
            end
        end
    end
    return total
end

local function UpdateStatSummary(hoverStats)
    if not mainFrame or not mainFrame.statPanel then return end
    local panel = mainFrame.statPanel
    
    if not panel.rows then panel.rows = {} end
    
    for _, row in ipairs(panel.rows) do row:Hide() end
    
    local yOffset = -40
    local rowIndex = 1
    
    local keys = {}
    for k in pairs(STAT_MAP) do table.insert(keys, k) end
    table.sort(keys)
    
    for _, k in ipairs(keys) do
        local owned = currentOwnedStats[k] or 0
        local hover = hoverStats and hoverStats[k] or 0
        
        if owned > 0 or hover > 0 then
            local row = panel.rows[rowIndex]
            if not row then
                row = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row:SetPoint("TOPLEFT", 10, yOffset)
                row:SetWidth(STAT_PANEL_WIDTH - 20)
                row:SetJustifyH("LEFT")
                panel.rows[rowIndex] = row
            end
            
            local label = STAT_MAP[k] or k
            local text = string.format("%s: |cffffffff%.1f|r", label, owned)
            if hover > 0 then
                text = text .. string.format(" |cff00ff00(+%.1f)|r", hover)
            end
            
            row:SetText(text)
            row:Show()
            yOffset = yOffset - 18
            rowIndex = rowIndex + 1
        end
    end
    
    if rowIndex == 1 then
        panel.empty:Show()
    else
        panel.empty:Hide()
    end
end

local function SyncFavorite(spellId, name, shouldAdd)
    if not EHTweaksDB.favorites then EHTweaksDB.favorites = {} end
    
    local targetName = name
    if not targetName then targetName = GetSpellInfo(spellId) end
    
    if shouldAdd then        
        EHTweaksDB.favorites[spellId] = true        
        if targetName and EHTweaksDB.seenEchoes then
             for k, v in pairs(EHTweaksDB.seenEchoes) do
                 if v.name == targetName then EHTweaksDB.favorites[k] = true end
             end
        end
        print("|cff00FF00EHTweaks|r: Added '" .. (targetName or "Unknown") .. "' to Favorites!")
    else
        if targetName then
            for k, v in pairs(EHTweaksDB.favorites) do
                local n = GetSpellInfo(k)
                if n == targetName then 
                    EHTweaksDB.favorites[k] = nil 
                end
            end
        else
            EHTweaksDB.favorites[spellId] = nil
        end
        print("|cffFFFF00EHTweaks|r: Removed '" .. (targetName or "Unknown") .. "' from Favorites.")
    end
    
    
	
	
    if EHTweaks_RefreshFavouredMarkers then 
        EHTweaks_RefreshFavouredMarkers() 
    end
    
    
    if cardPool then
        for _, card in ipairs(cardPool) do
            if card:IsShown() and card.data then
                local isFav = EHTweaksDB.favorites and EHTweaksDB.favorites[card.data.spellId]
                
                
                if card.star then
                     card.star:SetAlpha(isFav and 1 or 0.2)
                end
                
                
                if card.btn then
                     card.btn:SetText(isFav and "Select (F)" or "Select")
                end
            end
        end
    end
    
    
    if EHTweaks_RefreshBrowser then EHTweaks_RefreshBrowser() end
    
    
end

local function GetOwnedCount(spellName)
    local count = 0
    if ProjectEbonhold.PerkService and ProjectEbonhold.PerkService.GetGrantedPerks then
        local granted = ProjectEbonhold.PerkService.GetGrantedPerks()
        if granted and granted[spellName] then
            for _, instance in ipairs(granted[spellName]) do
                count = count + (instance.stack or 1)
            end
        end
    end
    return count
end

local function PrimeRerollDataIfNeeded()
    local avail, total = GetRerollInfo()
    if total and total > 0 then return end
    
    if not ProjectEbonhold or not ProjectEbonhold.PerkService or not ProjectEbonhold.PerkService.RequestChoice then
        return
    end
    
    local now = GetTime and GetTime() or 0
    if now > 0 and (now - (lastChoiceRequestAt or 0)) < 1.0 then
        return
    end
    lastChoiceRequestAt = now
    
    ProjectEbonhold.PerkService.RequestChoice()
end

local function After(delay, fn)
    if CTimer and CTimer.After then
        return CTimer.After(delay, fn)
    elseif C_Timer and C_Timer.After then
        return C_Timer.After(delay, fn)
    else
        if fn then fn() end
    end
end

local function StartRerollPolling()
    rerollPollSeq = rerollPollSeq + 1
    local mySeq = rerollPollSeq
    
    local function step(triesLeft)
        if mySeq ~= rerollPollSeq then return end
        if not mainFrame or not mainFrame:IsShown() then return end
        
        UpdateRerollButton()
        local _, total = GetRerollInfo()
        if (total and total > 0) or triesLeft <= 0 then return end
        
        After(0.20, function() step(triesLeft - 1) end)
    end
    
    step(12)
end

local BACKDROP_THIN = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
    insets = {left = 0, right = 0, top = 0, bottom = 0}
}

local BACKDROP_THICK = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 2, 
    insets = {left = 0, right = 0, top = 0, bottom = 0}
}

local function CreateCard(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(CARD_WIDTH, CARD_MIN_HEIGHT)
    
    
    f:SetBackdrop(BACKDROP_THIN)
    f:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    f:SetBackdropBorderColor(0, 0, 0, 1) 
    
    
    local iconSize = CARD_MIN_HEIGHT - 10 
    local iconBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    iconBg:SetSize(iconSize, iconSize)
    iconBg:SetPoint("TOPLEFT", 5, -5)
    iconBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    iconBg:SetVertexColor(0, 0, 0, 1)
    
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(iconSize - 4, iconSize - 4)
    icon:SetPoint("CENTER", iconBg, "CENTER", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.icon = icon
    
    
    local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btn:SetSize(70, 30)
    btn:SetPoint("TOPRIGHT", -2, -2)
    btn:SetText("Select")
    btn:SetFrameLevel(240)
    f.btn = btn
    
    
    local banBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	banBtn:SetSize(60, 20)
	banBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
	banBtn:SetText("Ban")
	banBtn:SetFrameLevel(240)
	banBtn:Disable()
	if banBtn:GetFontString() then
	    banBtn:GetFontString():SetTextColor(0.97, 0.77, 1)
	end
	f.banBtn = banBtn

    
    local name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", iconBg, "TOPRIGHT", 10, -2)
    name:SetPoint("RIGHT", btn, "LEFT", -5, 0)
    name:SetJustifyH("LEFT")
    f.name = name
    
    
    local desc = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    
    
    
    local fontPath, fontSize, fontFlags = desc:GetFont()
    desc:SetFont(fontPath, fontSize * descScale, fontFlags)
    
    desc:SetPoint("TOPLEFT", iconBg, "TOPRIGHT", 10, -35) 
    desc:SetPoint("RIGHT", f, "RIGHT", -5, 0)
    desc:SetWidth(270) 
    desc:SetJustifyH("LEFT")
    desc:SetJustifyV("TOP")
    desc:SetWordWrap(true)
    f.desc = desc

    local badgeText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badgeText:SetPoint("BOTTOM", iconBg, "BOTTOM", 0, 2)
    badgeText:SetTextColor(0, 1, 0)
    badgeText:SetShadowOffset(1,-1)
    badgeText:SetShadowColor(0,0,0,1)
    f.ownedText = badgeText
    
    local star = CreateFrame("Button", nil, f)
    star:SetSize(16, 16)
    star:SetPoint("TOPLEFT", iconBg, "TOPLEFT", 2, -2)
    star:SetNormalTexture("Interface\\Icons\\inv_misc_gem_02")
    star:SetAlpha(0.5)
    star:SetFrameLevel(250)
    star.tex = star:GetNormalTexture()
    f.star = star
    
    local kbText = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    kbText:SetPoint("CENTER", btn, "TOP", 0, 4)
    f.kbText = kbText
    
    
    local hover = CreateFrame("Button", nil, f)
    hover:SetAllPoints(f)
    hover:SetFrameLevel(230)
    hover:RegisterForClicks("RightButtonUp", "LeftButtonUp")
    f.hover = hover
    
    
    hover:SetScript("OnEnter", function(self)
        f:SetBackdrop(BACKDROP_THICK)
        f:SetBackdropColor(0.1, 0.1, 0.1, 0.9) 
        if f.qInfo then
            f:SetBackdropBorderColor(f.qInfo.r, f.qInfo.g, f.qInfo.b, 1)
        else
            f:SetBackdropBorderColor(1, 1, 1, 1)
        end
        if f.cardStats then UpdateStatSummary(f.cardStats) end
        if utils and utils.GetSpellDescription and f.data then
             GameTooltip:SetOwner(f, "ANCHOR_RIGHT")
             local r = f.qInfo and f.qInfo.r or 1
             local g = f.qInfo and f.qInfo.g or 1
             local b = f.qInfo and f.qInfo.b or 1
             GameTooltip:SetText(f.data.name, r, g, b)
             GameTooltip:AddLine(utils.GetSpellDescription(f.data.spellId, 999, f.data.stack or 1), 1, 1, 1, true)
		   if GetBanishInfo() > 0 then
		    GameTooltip:AddLine("Ctrl+Shift+Left-Click to Banish", 1, 0.45, 0.45)
		end
             GameTooltip:Show()
        end
	
    end)
    
    hover:SetScript("OnLeave", function(self)
        f:SetBackdrop(BACKDROP_THIN)
        f:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        if f.qInfo then
            f:SetBackdropBorderColor(f.qInfo.r, f.qInfo.g, f.qInfo.b, 1)
        else
            f:SetBackdropBorderColor(0, 0, 0, 1)
        end
        UpdateStatSummary(nil)
        GameTooltip:Hide()
    end)
    
    hover:SetScript("OnClick", function(self, btn)
        if btn == "RightButton" and f.data then
            local currentIsFav = EHTweaksDB.favorites and EHTweaksDB.favorites[f.data.spellId]
            
            SyncFavorite(f.data.spellId, f.data.name, not currentIsFav, f)
        end
	   if btn == "LeftButton" and IsControlKeyDown() and IsShiftKeyDown() and not IsAltKeyDown() then
		  if f.cardIndex then
			MD.BanishOption(f.cardIndex)
		  end
	   end
    end)
    
    return f
end

local function GetCard(index)
    if not cardPool[index] then
        cardPool[index] = CreateCard(mainFrame.cardContainer)
    end
    return cardPool[index]
end

function MD.SelectOption(index)
    if isSelecting or not currentChoices or not currentChoices[index] then return end
    
    local choice = currentChoices[index]
    if choice and choice.spellId then
        isSelecting = true
        ProjectEbonhold.PerkService.SelectPerk(choice.spellId)
        
        if cardPool[index] then
            cardPool[index]:SetBackdropColor(0, 1, 0, 0.2)
        end
    end
end

local function CreateRestoreButton()
    if restoreBtn then return restoreBtn end
    
    local b = CreateFrame("Button", "EHT_ModernDraftRestore", UIParent)
    b:SetSize(120, 30)
    b:SetFrameStrata("FULLSCREEN_DIALOG")
    b:SetFrameLevel(500)
    b:SetMovable(true)
    b:EnableMouse(true)
    b:RegisterForDrag("LeftButton")
    
    b:ClearAllPoints()
    if EHTweaksDB and EHTweaksDB.restoreBtnPos then
        local p = EHTweaksDB.restoreBtnPos
        b:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        b:SetPoint("TOP", UIParent, "TOP", 0, -100)
    end
    
    b:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = {left = 0, right = 0, top = 0, bottom = 0}
    })
    b:SetBackdropColor(0, 0, 0, 0.8)
    b:SetBackdropBorderColor(1, 0.82, 0, 1)
    
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("CENTER")
    t:SetText("Show Draft")
    
    b:SetScript("OnDragStart", b.StartMoving)
    b:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        if not EHTweaksDB then EHTweaksDB = {} end
        EHTweaksDB.restoreBtnPos = {p, rp, x, y}
    end)
    
    b:SetScript("OnClick", function()
        if mainFrame then
            mainFrame:Show()
            b:Hide()
        end
    end)
    
    b:Hide()
    restoreBtn = b
    return b
end

local function CreateDraftFrame()
    if mainFrame then return mainFrame end
    
    local f = CreateFrame("Frame", "EHT_ModernDraftFrame", UIParent)
    f:SetSize(CARD_WIDTH + STAT_PANEL_WIDTH + 50, 400)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(200) 
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    
    f:ClearAllPoints()
    if EHTweaksDB and EHTweaksDB.modernDraftPos then
        local p = EHTweaksDB.modernDraftPos
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        f:SetPoint("CENTER", 0, 0)
    end

    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0, 0, 0, 0.9)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetFrameLevel(260)
    close:SetScript("OnClick", function() MD.Minimize() end)
    f.close = close

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 15, -12)
    title:SetText("Echoes Draft")
    
    local container = CreateFrame("Frame", nil, f)
    container:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -35)
    container:SetSize(CARD_WIDTH, 10)
    container:SetFrameLevel(210)
    f.cardContainer = container
    
    
    local statPanel = CreateFrame("Frame", nil, f)
    statPanel:SetSize(STAT_PANEL_WIDTH, 10)
    statPanel:SetPoint("TOPLEFT", container, "TOPRIGHT", 10, 0)
    statPanel:SetFrameLevel(210)
    
    local sTitle = statPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sTitle:SetPoint("TOPLEFT", 5, 0)
    sTitle:SetText("Cumulative Bonuses")
    sTitle:SetTextColor(0.5, 0.7, 1)
    
    local empty = statPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    empty:SetPoint("TOPLEFT", 10, -25)
    empty:SetText("No bonuses yet.")
    statPanel.empty = empty
    f.statPanel = statPanel

	local rerollBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	rerollBtn:SetSize(160, 30)
	rerollBtn:SetPoint("BOTTOMLEFT", 15, 12)
	rerollBtn:SetFrameLevel(260)
	rerollBtn:SetScript("OnClick", function()
		
		if IsControlKeyDown() and IsShiftKeyDown() then
			if ProjectEbonhold and ProjectEbonhold.PerkService and ProjectEbonhold.PerkService.RequestReroll then
				ProjectEbonhold.PerkService.RequestReroll()
				StartRerollPolling()
			end
			return
		end

		
		StaticPopupDialogs["PERK_REROLL_CONFIRM"] = {
			text = "Are you sure you want to reroll these Echoes?",
			button1 = "Yes",
			button2 = "No",
			OnAccept = function()
				if ProjectEbonhold and ProjectEbonhold.PerkService and ProjectEbonhold.PerkService.RequestReroll then
					ProjectEbonhold.PerkService.RequestReroll()
					StartRerollPolling()
				end
			end,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
		}
		StaticPopup_Show("PERK_REROLL_CONFIRM")
	end)
	rerollBtn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText("Reroll Echoes", 1, 1, 1)
		GameTooltip:AddLine("Click to reroll with confirmation.", 0.8, 0.8, 0.8, true)
		GameTooltip:AddLine("|cff00ff00Ctrl+Shift+Click|r to reroll instantly without confirmation.", 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	rerollBtn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	f.rerollBtn = rerollBtn

    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, rp, x, y = self:GetPoint()
        if not EHTweaksDB then EHTweaksDB = {} end
        EHTweaksDB.modernDraftPos = {p, rp, x, y}
    end)
    
    f:Hide()
    mainFrame = f
    CreateRestoreButton()
    return f
end

MD.pendingChoices = nil
MD.chooseBtnHooked = false
MD.origChooseOnClick = nil
MD.isInDraftSession = false

local function HookChooseButton()
    local btn = _G.PerkChooseButton
    if not btn or MD.chooseBtnHooked then return btn ~= nil end
    MD.origChooseOnClick = btn:GetScript("OnClick")
    btn:SetScript("OnClick", function(self, ...)
        
        if EHTweaksDB and EHTweaksDB.enableModernDraft and MD.pendingChoices and #MD.pendingChoices > 0 then
            if _G.ProjectEbonholdPerkFrame then _G.ProjectEbonholdPerkFrame:Hide() end
            
            MD.isInDraftSession = true
            MD.Show(MD.pendingChoices)
            return
        end
        
        if MD.origChooseOnClick then return MD.origChooseOnClick(self, ...) end
    end)
    MD.chooseBtnHooked = true
    return true
end

function MD.Refresh()
    if not mainFrame or not mainFrame:IsShown() then return end
    
    local showLabel = EHTweaksDB and EHTweaksDB.showDraftFavorites
    
    for i, data in ipairs(currentChoices) do
        local card = GetCard(i)
        if card:IsShown() then
            local isFav = EHTweaksDB.favorites and EHTweaksDB.favorites[data.spellId]
            if isFav then
                card.star:SetAlpha(1)
                if card.star.tex then card.star.tex:SetVertexColor(1, 1, 1) end
              
            else
                card.star:SetAlpha(0.2)
                if card.star.tex then card.star.tex:SetVertexColor(0.5, 0.5, 0.5) end
              
            end
        end
    end
end

function MD.Show(choices)
    if not choices or #choices == 0 then return end
    if not EHTweaksDB.enableModernDraft then return end

    CreateDraftFrame()
    if restoreBtn then restoreBtn:Hide() end

    
    currentOwnedStats = CalculateAllOwnedStats()
    UpdateStatSummary(nil)

    currentChoices = choices
    isSelecting = false

    local num = #choices
    local cardHeights = {}
    local totalContainerHeight = 0

    local cardSpacing = CARDSPACING or CARD_SPACING or 8
    local cardWidth = CARDWIDTH or CARD_WIDTH or 340
    local qi = QUALITYINFO
    local thinBackdrop = BACKDROPTHIN or BACKDROP_THIN

    
    for i, data in ipairs(choices) do
        local descText = GetCardDescription(data.spellId, data.stack or 1)
        local h = CalculateCardHeight(descText)
        cardHeights[i] = h

        totalContainerHeight = totalContainerHeight + h
        if i < num then
            totalContainerHeight = totalContainerHeight + cardSpacing
        end
    end

    
    local hasStats = false
    if currentOwnedStats then
        for k, v in pairs(currentOwnedStats) do
            if v ~= 0 then
                hasStats = true
                break
            end
        end
    end

    
    local frameHeight = math.max(totalContainerHeight + 90, 200)
    mainFrame:SetHeight(frameHeight)

    if hasStats then
        mainFrame:SetWidth(680) 
        mainFrame.statPanel:Show()
    else
        mainFrame:SetWidth(360) 
        mainFrame.statPanel:Hide()
    end

    mainFrame.cardContainer:SetHeight(totalContainerHeight)
    mainFrame.statPanel:SetHeight(totalContainerHeight)

    
    local currentY = 0

    for i, data in ipairs(choices) do
        local card = GetCard(i)
        local h = cardHeights[i]

        card:SetSize(cardWidth, h)
        card:SetFrameLevel(220)
        card:Show()

        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", mainFrame.cardContainer, "TOPLEFT", 0, -currentY)
        currentY = currentY + h + cardSpacing

        local name, _, icon = GetSpellInfo(data.spellId)

        
        local qInfo = nil
        if qi then
            qInfo = qi[data.quality] or qi[0]
        end
        if not qInfo then
            qInfo = { r = 1, g = 1, b = 1 }
        end

        
        card.qInfo = qInfo
        card.data = data
        data.name = name
        card.cardStats = GetSpellStats(data.spellId, 1)

        
        card.name:SetText(name or "Unknown Echo")
        card.name:SetTextColor(qInfo.r or 1, qInfo.g or 1, qInfo.b or 1)

        
        if thinBackdrop then
            card:SetBackdrop(thinBackdrop)
        end
        card:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        card:SetBackdropBorderColor(qInfo.r or 1, qInfo.g or 1, qInfo.b or 1, 1)

        local descText = GetCardDescription(data.spellId, data.stack or 1)
        card.desc:SetText(descText)

        card.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")

        local count = GetOwnedCount(name)
        card.ownedText:SetText(count > 0 and "x" .. count or "")

        
        card.star:Show() 
        local isFav = EHTweaksDB.favorites and EHTweaksDB.favorites[data.spellId]

        if isFav then
            card.star:SetAlpha(1)
            card.btn:SetText("Select (F)")
        else
            card.star:SetAlpha(0.2)
            card.btn:SetText("Select")
        end

        
        card.star:SetScript("OnClick", function()
            local currentIsFav = EHTweaksDB.favorites and EHTweaksDB.favorites[data.spellId]
            SyncFavorite(data.spellId, name, not currentIsFav)
        end)

        
        local key1 = GetBindingKey("EHTWEAKS_DRAFT_" .. i)
        card.kbText:SetText(key1 and "[" .. key1 .. "]" or "")

        
        card.btn:SetScript("OnClick", function() MD.SelectOption(i) end)

        
        card.cardIndex = i

        
        local remainingBanishes = GetBanishInfo()
        if remainingBanishes > 0 then
            card.banBtn:SetText("Ban (" .. remainingBanishes .. ")")
            card.banBtn:Enable()
        else
            card.banBtn:SetText("Ban")
            card.banBtn:Disable()
        end
        card.banBtn:EnableMouse(true)
        local capturedI = i
        card.banBtn:SetScript("OnClick", function()
            MD.BanishOption(capturedI)
        end)
    end

    for i = num + 1, #cardPool do
        cardPool[i]:Hide()
    end

    

    UpdateRerollButton()
    PrimeRerollDataIfNeeded()
    StartRerollPolling()

    mainFrame:Show()
end

function MD.Hide()
    rerollPollSeq = rerollPollSeq + 1
    if mainFrame then mainFrame:Hide() end
    if restoreBtn then restoreBtn:Hide() end
    
    
    
    
    
    After(3.0, function()
        if not (mainFrame and mainFrame:IsShown()) then
            MD.isInDraftSession = false
        end
    end)
end

function MD.Minimize()
    
    
    MD.isInDraftSession = false
    rerollPollSeq = rerollPollSeq + 1
    if mainFrame then mainFrame:Hide() end
    if restoreBtn then restoreBtn:Show() end
end

function MD.IsVisible()
    return mainFrame and mainFrame:IsVisible()
end

local function HookInit()
    if not ProjectEbonhold or not ProjectEbonhold.PerkUI then return end

    
    
    
    
    
if ProjectEbonhold.PerkUI.Show then
    local origPerkUIShow = ProjectEbonhold.PerkUI.Show
    ProjectEbonhold.PerkUI.Show = function(choices)
        if EHTweaksDB and EHTweaksDB.enableModernDraft and choices and #choices > 0 then
            MD.pendingChoices = choices

              
                
                
                
                
                
                if MD.isInDraftSession then
                    local pf = _G.ProjectEbonholdPerkFrame
                    if pf and pf:IsShown() then pf:Hide() end

                    local pb = _G.PerkChooseButton
                    if pb and pb:IsShown() then pb:Hide() end

                    if MD.UpdateInPlace then
                        MD.UpdateInPlace(choices)
                    else
                        MD.Show(choices)
                    end
                    return
                end

                
                

                

            
            
            
            
            

            
            

            
            
            
            
            
            
            

            
            
            origPerkUIShow(choices)

            if not HookChooseButton() then
                After(0.10, HookChooseButton)
                After(0.30, HookChooseButton)
            end

            return
        end

        origPerkUIShow(choices)
    end
end

    hooksecurefunc(ProjectEbonhold.PerkUI, "Hide", function()
        MD.Hide()
    end)

    if EHTweaksRefreshFavouredMarkers then
        hooksecurefunc("EHTweaksRefreshFavouredMarkers", function()
            if MD.IsVisible() then MD.Refresh() end
        end)
    end

    
    
    
    if ProjectEbonhold.PerkUI.UpdateSinglePerk then
        local origUpdateSinglePerk = ProjectEbonhold.PerkUI.UpdateSinglePerk
        ProjectEbonhold.PerkUI.UpdateSinglePerk = function(perkIndex, newPerkData)
            if not (EHTweaksDB and EHTweaksDB.enableModernDraft) or not MD.IsVisible() then
                origUpdateSinglePerk(perkIndex, newPerkData)
                return
            end

            local cardIdx = perkIndex + 1 

            
            if currentChoices and currentChoices[cardIdx] then
                currentChoices[cardIdx].spellId = newPerkData.spellId
                currentChoices[cardIdx].quality = newPerkData.quality or 0
            end

            local card = cardPool[cardIdx]
            if card and card:IsShown() then
                local name, _, icon = GetSpellInfo(newPerkData.spellId)
                
                
                local qi = QUALITYINFO
                local qInfo = qi and (qi[newPerkData.quality or 0] or qi[0])
                    or { r = 1, g = 1, b = 1 }

                card.name:SetText(name or "Unknown Echo")
                card.name:SetTextColor(qInfo.r, qInfo.g, qInfo.b)
                card.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")

                if utils and utils.GetSpellDescription then
                    card.desc:SetText(utils.GetSpellDescription(newPerkData.spellId, 999, newPerkData.stack or 1))
                end

                card:SetBackdropBorderColor(qInfo.r, qInfo.g, qInfo.b, 1)
                card.qInfo = qInfo
                card.data = newPerkData
                card.data.name = name
                card.cardIndex = cardIdx

                RecalculateLayout()

                
                local capturedIdx = cardIdx
                card.btn:SetScript("OnClick", function()
                    if IsControlKeyDown() and IsShiftKeyDown() and not IsAltKeyDown() then
                        MD.BanishOption(capturedIdx)
                    else
                        MD.SelectOption(capturedIdx)
                    end
                end)
                if card.banBtn then
                    card.banBtn:SetScript("OnClick", function()
                        MD.BanishOption(capturedIdx)
                    end)
                end
            end

            
            
            
            
            isSelecting = false

            
            
            
            
            
            for _, c in ipairs(cardPool) do
                if c and c:IsShown() then
                    c.btn:EnableMouse(true)
                    if c.banBtn then
                        c.banBtn:Disable()
                        c.banBtn:EnableMouse(false)
                        c.banBtn:SetText("Ban...")
                    end
                end
            end

            After(1.0, function()
                if not mainFrame or not mainFrame:IsShown() then return end            
                UpdateBanishButtons() 
            end)
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", HookInit)

_G.EHTweaks_SelectDraftOption = function(i) MD.SelectOption(i) end
_G.EHTweaksSelectDraftOption1 = function() MD.SelectOption(1) end
_G.EHTweaksSelectDraftOption2 = function() MD.SelectOption(2) end
_G.EHTweaksSelectDraftOption3 = function() MD.SelectOption(3) end
