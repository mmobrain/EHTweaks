-- Author: Skulltrail
-- EHTweaks: Modern Draft UI
-- Features: Vertical List Layout, Saved Positions, Stat Summary Parser, Synced Favorites, Right-Click "FAV" Support.

local addonName, addon = ...
_G.EHTweaks = _G.EHTweaks or addon
EHTweaks.ModernDraft = {}
local MD = EHTweaks.ModernDraft

-- --- Configuration ---
local CARD_WIDTH = 340
local CARD_MIN_HEIGHT = 70
local CARD_SPACING = 8
local STAT_PANEL_WIDTH = 180

local QUALITY_INFO = {
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

-- --- State ---
local mainFrame = nil
local restoreBtn = nil
local cardPool = {}
local currentChoices = {}
local isSelecting = false
local currentOwnedStats = {}

-- Reroll priming
local rerollPollSeq = 0
local lastChoiceRequestAt = 0

-- --- Helper: Tooltip Scanner & Description ---
local scanner = _G["EHT_DraftScanner"] or CreateFrame("GameTooltip", "EHT_DraftScanner", nil, "GameTooltipTemplate")
scanner:SetOwner(WorldFrame, "ANCHOR_NONE")

local function GetCardDescription(spellId, stack)
    -- 1. Try ebonholdproject's utils first
    -- Using 500 char limit as requested to prevent early truncation
    if utils and utils.GetSpellDescription then
        local desc = utils.GetSpellDescription(spellId, 500, stack or 1)
        if desc and desc ~= "" and desc ~= "Click for details" then 
            return desc 
        end
    end

    -- 2. Fallback: Standard Tooltip Scan (if utils fails for any reason)
    scanner:ClearLines()
    scanner:SetHyperlink("spell:" .. spellId)
    local lines = scanner:NumLines()
    if lines < 1 then return "" end
    
    local desc = ""
    -- For spells, description usually starts at line 2
    for i = 2, lines do
        local lineObj = _G["EHT_DraftScannerTextLeft" .. i]
        if lineObj then
            local text = lineObj:GetText()
            if text then
                 -- Filter out "Rank" or "Next Rank" lines
                 if not text:find("^Rank %d") and not text:find("^Next Rank:") then
                     if desc ~= "" then desc = desc .. "\n" end
                     desc = desc .. text
                end
            end
        end
    end
    return desc
end

-- --- Helper: Stat Parser ---
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

-- --- Helper: UI Update Stat Panel ---
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

-- --- Helper: Favorite Sync Logic ---
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
    
    -- INSTANT UI UPDATE: Loop through visible cards and update them
	
	-- 1. Refresh Original UI Markers (if active)
    if EHTweaks_RefreshFavouredMarkers then 
        EHTweaks_RefreshFavouredMarkers() 
    end
    
    -- 2. Refresh Modern UI (Instant Update)
    if cardPool then
        for _, card in ipairs(cardPool) do
            if card:IsShown() and card.data then
                local isFav = EHTweaksDB.favorites and EHTweaksDB.favorites[card.data.spellId]
                
                -- Update Star
                if card.star then
                     card.star:SetAlpha(isFav and 1 or 0.2)
                end
                
                -- Update Button Text
                if card.btn then
                     card.btn:SetText(isFav and "Select (F)" or "Select")
                end
            end
        end
    end
    
    -- 3. Broadcast to Browser
    if EHTweaks_RefreshBrowser then EHTweaks_RefreshBrowser() end
    -- MD.Refresh() DISABLED here anymore to avoid full redraw flickering, 
    -- since we manually updated the active cards above...
end


-- --- Helper: Count Owned Echoes ---
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

-- --- Helper: Reroll Info ---
local function GetRerollInfo()
    -- Strategy 1: PerkUI state
    if ProjectEbonhold and ProjectEbonhold.PerkUI then
        local perkUI = ProjectEbonhold.PerkUI
        if perkUI.totalRerolls ~= nil and perkUI.usedRerolls ~= nil then
            local total = tonumber(perkUI.totalRerolls) or 0
            local used = tonumber(perkUI.usedRerolls) or 0
            return math.max(0, total - used), total
        end
    end
    
    -- Strategy 2: Global run data
    local runData = _G.EbonholdPlayerRunData
    if runData then
        local used = tonumber(runData.usedRerolls) or 0
        local total = tonumber(runData.totalRerolls) or 0
        return math.max(0, total - used), total
    end
    
    -- Strategy 3: Service getter
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

-- --- Reroll Priming & Polling ---
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

local function UpdateRerollButton()
    if not mainFrame or not mainFrame.rerollBtn then return end
    local avail, total = GetRerollInfo()
    mainFrame.rerollBtn:SetText("Reroll (" .. avail .. "/" .. total .. ")")
    if avail <= 0 then mainFrame.rerollBtn:Disable() else mainFrame.rerollBtn:Enable() end
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

-- --- Helper: Dynamic Height Calculator ---
local function CalculateCardHeight(descText)
    if not descText or descText == "" then
        return CARD_MIN_HEIGHT
    end
    
    -- CONFIG: Scale Factor (1.15 = 15% larger than standard)
    local descScale = 1.15
    
    -- Create the measuring fontstring if it doesn't exist yet
    if not _G.EHT_MeasureFont then
        local f = CreateFrame("Frame", nil, UIParent)
        f:Hide()
        _G.EHT_MeasureFont = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        _G.EHT_MeasureFont:SetJustifyH("LEFT")
        _G.EHT_MeasureFont:SetJustifyV("TOP")
    end
    
    -- 1. Reset to base object to get the correct font face/style
    _G.EHT_MeasureFont:SetFontObject("GameFontHighlight") 
    
    -- 2. Get current settings and apply SCALING
    local fontPath, fontSize, fontFlags = _G.EHT_MeasureFont:GetFont()
    _G.EHT_MeasureFont:SetFont(fontPath, fontSize * descScale, fontFlags)
    
    -- 3. Set Width and Wrap
    _G.EHT_MeasureFont:SetWidth(270)
    _G.EHT_MeasureFont:SetWordWrap(true)
    
    _G.EHT_MeasureFont:SetText(descText)
    local textHeight = _G.EHT_MeasureFont:GetStringHeight()
    
    -- Height: Top Area(38) + TextHeight + Bottom Padding(12)
    local neededHeight = 38 + textHeight + 12
    
    return math.max(CARD_MIN_HEIGHT, math.ceil(neededHeight))
end

-- --- Backdrop Definitions ---
local BACKDROP_THIN = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
    insets = {left = 0, right = 0, top = 0, bottom = 0}
}

local BACKDROP_THICK = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 2, -- Thicker border on hover
    insets = {left = 0, right = 0, top = 0, bottom = 0}
}

-- --- Frame Factory: Card ---
local function CreateCard(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(CARD_WIDTH, CARD_MIN_HEIGHT)
    
    -- Initial Backdrop (Thin)
    f:SetBackdrop(BACKDROP_THIN)
    f:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    f:SetBackdropBorderColor(0, 0, 0, 1) 
    
    -- 1. Icon
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
    
    -- 2. Select Button
    local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btn:SetSize(70, 30)
    btn:SetPoint("TOPRIGHT", -5, -5)
    btn:SetText("Select")
    btn:SetFrameLevel(240)
    f.btn = btn
    
    -- 3. Name
    local name = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", iconBg, "TOPRIGHT", 10, -2)
    name:SetPoint("RIGHT", btn, "LEFT", -5, 0)
    name:SetJustifyH("LEFT")
    f.name = name
    
    -- 4. Description (Scaled)
    local desc = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    
    -- Apply Scale
    local descScale = 1.15
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
    
    -- Hover Area
    local hover = CreateFrame("Button", nil, f)
    hover:SetAllPoints(f)
    hover:SetFrameLevel(230)
    hover:RegisterForClicks("RightButtonUp")
    f.hover = hover
    
    -- --- HOVER SCRIPTS ---
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
            -- Pass the frame 'f' to SyncFavorite so it can update the text immediately
            SyncFavorite(f.data.spellId, f.data.name, not currentIsFav, f)
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

-- --- Logic: Selection ---
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

-- --- UI: Restore Button ---
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

-- --- UI: Main Frame ---
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
    
    -- Stat Panel
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
        StaticPopupDialogs["PERK_REROLL_CONFIRM"] = {
            text = "Are you sure you want to reroll these Echoes?", button1 = "Yes", button2 = "No",
            OnAccept = function() 
                if ProjectEbonhold and ProjectEbonhold.PerkService and ProjectEbonhold.PerkService.RequestReroll then
                    ProjectEbonhold.PerkService.RequestReroll() 
                end
            end,
            timeout = 0, whileDead = true, hideOnEscape = true
        }
        StaticPopup_Show("PERK_REROLL_CONFIRM")
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

-- --- Pending stock-button flow ---
MD.pendingChoices = nil
MD._chooseBtnHooked = false
MD._origChooseOnClick = nil

local function HookChooseButton()
    local btn = _G.PerkChooseButton
    if not btn or MD._chooseBtnHooked then return btn ~= nil end

    MD._origChooseOnClick = btn:GetScript("OnClick")

    btn:SetScript("OnClick", function(self, ...)
        -- If ModernDraft is enabled and we have a pending choice, open MD instead
        if EHTweaksDB and EHTweaksDB.enableModernDraft and MD.pendingChoices and #MD.pendingChoices > 0 then
            if _G.ProjectEbonholdPerkFrame then _G.ProjectEbonholdPerkFrame:Hide() end
            MD.Show(MD.pendingChoices)
            return
        end

        -- Fallback: run original behavior
        if MD._origChooseOnClick then
            return MD._origChooseOnClick(self, ...)
        end
    end)

    MD._chooseBtnHooked = true
    return true
end


-- --- Logic: Dynamic Favorite Sync ---
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
    
    -- Calculate stats for the summary panel
    currentOwnedStats = CalculateAllOwnedStats()
    UpdateStatSummary(nil)
    
    currentChoices = choices
    isSelecting = false
    
    local num = #choices
    local cardHeights = {}
    local totalContainerHeight = 0
    
    -- PASS 1: Calculate Heights
    for i, data in ipairs(choices) do
        local descText = GetCardDescription(data.spellId, data.stack or 1)
        local h = CalculateCardHeight(descText)
        cardHeights[i] = h
        
        totalContainerHeight = totalContainerHeight + h
        if i < num then
            totalContainerHeight = totalContainerHeight + CARD_SPACING
        end
    end
    
    -- --- DYNAMIC WIDTH LOGIC ---
    local hasStats = false
    if currentOwnedStats then
        for k, v in pairs(currentOwnedStats) do
            if v ~= 0 then 
                hasStats = true 
                break 
            end
        end
    end
    
    -- Resize Main Frame
    local frameHeight = math.max(totalContainerHeight + 90, 200) 
    mainFrame:SetHeight(frameHeight)
    
    if hasStats then
        mainFrame:SetWidth(680) -- Full width (Cards + Stats)
        mainFrame.statPanel:Show()
    else
        mainFrame:SetWidth(360) -- Narrow width (Cards only)
        mainFrame.statPanel:Hide()
    end
    
    mainFrame.cardContainer:SetHeight(totalContainerHeight)
    mainFrame.statPanel:SetHeight(totalContainerHeight)

    -- PASS 2: Render Cards
    local currentY = 0
    
    for i, data in ipairs(choices) do
        local card = GetCard(i)
        local h = cardHeights[i]
        
        card:SetSize(CARD_WIDTH, h)
        card:SetFrameLevel(220)
        card:Show()
        
        card:SetPoint("TOPLEFT", mainFrame.cardContainer, "TOPLEFT", 0, -currentY)
        currentY = currentY + h + CARD_SPACING
        
        local name, _, icon = GetSpellInfo(data.spellId)
        
        -- Quality Color Logic
        local qInfo = QUALITY_INFO[data.quality] or QUALITY_INFO[0]
        
        -- Store info for Hover Script
        card.qInfo = qInfo
        card.data = data
        data.name = name
        card.cardStats = GetSpellStats(data.spellId, 1)
        
        -- Apply Colors & Text
        card.name:SetText(name or "Unknown Echo")
        card.name:SetTextColor(qInfo.r, qInfo.g, qInfo.b)
        
        -- Set Initial Thin Border & Background
        card:SetBackdrop(BACKDROP_THIN)
        card:SetBackdropColor(0.1, 0.1, 0.1, 0.9) -- Re-apply background color
        card:SetBackdropBorderColor(qInfo.r, qInfo.g, qInfo.b, 1)
        
        local descText = GetCardDescription(data.spellId, data.stack or 1)
        card.desc:SetText(descText)
        
        card.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        
        local count = GetOwnedCount(name)
        card.ownedText:SetText(count > 0 and "x"..count or "")
        
        -- --- FAVORITE LOGIC ---
        card.star:Show() -- Ensure visible
        local isFav = EHTweaksDB.favorites and EHTweaksDB.favorites[data.spellId]
        
        if isFav then
            card.star:SetAlpha(1)
            card.btn:SetText("Select (F)")
        else
            card.star:SetAlpha(0.2)
            card.btn:SetText("Select")
        end
        
        -- Star Click
        card.star:SetScript("OnClick", function()
            local currentIsFav = EHTweaksDB.favorites and EHTweaksDB.favorites[data.spellId]
            SyncFavorite(data.spellId, name, not currentIsFav)
        end)
        
        -- Keyboard Bind
        local key1 = GetBindingKey("EHTWEAKS_DRAFT_"..i)
        card.kbText:SetText(key1 and "["..key1.."]" or "")
        
        -- Select Action
        card.btn:SetScript("OnClick", function() MD.SelectOption(i) end)
    end
    
    for i = num + 1, #cardPool do
        cardPool[i]:Hide()
    end
    
    -- MD.Refresh() -- DISABLED to prevent redundancy/recursion if triggered by SyncFavorite
    
    UpdateRerollButton()
    PrimeRerollDataIfNeeded()
    StartRerollPolling()
    
    mainFrame:Show()
end


function MD.Hide()
    rerollPollSeq = rerollPollSeq + 1
    if mainFrame then mainFrame:Hide() end
    if restoreBtn then restoreBtn:Hide() end
end

function MD.Minimize()
    rerollPollSeq = rerollPollSeq + 1
    if mainFrame then mainFrame:Hide() end
    if restoreBtn then restoreBtn:Show() end
end

function MD.IsVisible()
    return mainFrame and mainFrame:IsVisible()
end

-- --- Hooking ---
local function HookInit()
    if not ProjectEbonhold or not ProjectEbonhold.PerkUI then return end
    
    hooksecurefunc(ProjectEbonhold.PerkUI, "Show", function(choices)
        if not (EHTweaksDB and EHTweaksDB.enableModernDraft) then return end
        if not choices or #choices == 0 then return end
        
        MD.pendingChoices = choices
    
        -- Ensure the button is hooked (it may not exist on the first tick)
        if not HookChooseButton() then
            After(0.10, HookChooseButton)
            After(0.30, HookChooseButton)
        end
    end)
    
    hooksecurefunc(ProjectEbonhold.PerkUI, "Hide", function()
        MD.Hide()
    end)
    
    -- Sync with external Favorite changes (Browser or original Echoes frame)
    if EHTweaks_RefreshFavouredMarkers then
        hooksecurefunc("EHTweaks_RefreshFavouredMarkers", function()
            if MD.IsVisible() then MD.Refresh() end
        end)
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", HookInit)

-- Export keybind functions
_G.EHTweaks_SelectDraftOption = function(i) MD.SelectOption(i) end
_G.EHTweaksSelectDraftOption1 = function() MD.SelectOption(1) end
_G.EHTweaksSelectDraftOption2 = function() MD.SelectOption(2) end
_G.EHTweaksSelectDraftOption3 = function() MD.SelectOption(3) end
