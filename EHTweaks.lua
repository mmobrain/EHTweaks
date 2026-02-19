-- Author: Skulltrail
-- EHTweaks: Project Ebonhold Extensions
-- Features: Skill Tree Filter, Echoes Filter, Visual Highlights, Focus Zoom, Chat Links, Movable Echo Button, Echoes DB, Starter DB, Objective Tracker, PlayerRunFrame Saver, Minimap Button, Skill Tree Reset Button, Loadout Manager

local addonName, addon = ...
_G.EHTweaks = _G.EHTweaks or addon

-- Ensure EHTweaks.Skin is accessible
EHTweaks.Skin = EHTweaks.Skin or {}
local Skin = EHTweaks.Skin

-- Safety check: If Skin functions are missing (load order issue), define fallbacks locally
if not Skin.ApplyWindow then
    Skin.ApplyWindow = function(f) f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"}) f:SetBackdropColor(0,0,0,0.8) end
    Skin.ApplyInset = function(f) f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"}) f:SetBackdropColor(0,0,0,0.5) end
end

-- GLOBAL DEBUG TOGGLE
EHTweaks_DEBUG = false 

-- Key Binding Strings
BINDING_HEADER_EHTWEAKS = "EHTweaks"
BINDING_NAME_EHTWEAKS_TOGGLETREE = "Toggle Skill Tree"
BINDING_NAME_EHTWEAKS_TOGGLEECHOES = "Toggle My Echoes"



function EHTweaks_Log(msg)
    if EHTweaks_DEBUG then
        print("|cffFF9900[EHT Debug]|r " .. tostring(msg))
    end
end

-- --- Configuration ---
local FILTER_MATCH_ALPHA = 1.0
local FILTER_NOMATCH_ALPHA = 0.15
local SEARCH_THROTTLE = 0.2

-- --- Defaults ---
local DEFAULTS = {
    enableFilters = true,
    enableChatLinks = true,
    enableTracker = true,
    showDraftFavorites = true, 
    showEmpowermentFavorites = true,
    seenEchoes = {},
    perkButtonPos = nil,
    runFramePos = nil,
    offeredOptionalDB = nil,
    minimapButtonAngle = 200,
    minimapButtonHidden = false,
    enableLockedEchoWarning = true,
    enableIntensityWarning = true,
    enableShadowFissureWarning = true,
    chatWarnings = false,
    chatInfo = false,
    enableModernDraft = false,
    collectEchoesFromChatLinks = false
}

-- --- State ---
local searchTimer = 0
local currentSearchText = ""
local currentEchoSearchText = ""
local filterBox = nil
local echoFilterBox = nil
local matchedNodes = {} 
local minimapButton = nil
-- Shared state for Intensity/Run data (Accessible by Hazard System and Minimizer)
local lastRunData = { soulPoints = 0, soulPointsMultiplier = 0 }
local lastIntData = { intensity = 0 }

-- LOADOUT TRACKING STATE
local activeLoadoutId = nil
local knownLoadouts = {} -- [Name] = ID

-- --- Database Init ---
local function InitializeDB()
    if not EHTweaksDB then EHTweaksDB = {} end
    for k, v in pairs(DEFAULTS) do        
        if EHTweaksDB[k] == nil then 
            EHTweaksDB[k] = v 
        end
    end
    -- Initialize Loadout Tables
    if not EHTweaksDB.loadouts then EHTweaksDB.loadouts = {} end
    if not EHTweaksDB.backups then EHTweaksDB.backups = {} end
end


-- =========================================================
-- SECTION: INTENSITY WARNING SYSTEM
-- =========================================================

local INTENSITY_THRESHOLDS = { 75, 200, 275, 375, 475 }
local lastIntensityCheck = nil
local intensityAlertFrame = nil

local function CreateIntensityAlertFrame()
    if intensityAlertFrame then return intensityAlertFrame end
    
    local f = CreateFrame("Frame", "EHTweaks_IntensityAlert", UIParent)
    f:SetSize(512, 100)
    f:SetPoint("CENTER", 0, 120) -- Positioned slightly above center
    f:SetFrameStrata("HIGH")
    f:Hide()
    
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    text:SetPoint("CENTER")
    text:SetFont("Fonts\\FRIZQT__.TTF", 32, "OUTLINE")
    f.text = text
    
    local ag = f:CreateAnimationGroup()
    
    -- Fade In
    local a1 = ag:CreateAnimation("Alpha")
    a1:SetChange(1) 
    a1:SetDuration(0.2)
    a1:SetOrder(1)
    
    -- Hold (simulated by delay on next anim)
    -- Fade Out
    local a2 = ag:CreateAnimation("Alpha")
    a2:SetChange(-1)
    a2:SetStartDelay(2.0)
    a2:SetDuration(1.0)
    a2:SetOrder(2)
    
    ag:SetScript("OnFinished", function() f:Hide() end)
    f.anim = ag
    
    intensityAlertFrame = f
    return f
end

local function TriggerIntensityAlert(level, isReached)
    -- Ensure frame exists (used for fallback or standard alerts)
    if not intensityAlertFrame then CreateIntensityAlertFrame() end
    
    local msg = ""
    local r, g, b = 1, 1, 1
    
    if isReached then
        msg = "Intensity Level " .. level .. " Reached!"
        r, g, b = 0.8, 0.5, 0.0 -- Orange/Gold
    else
        msg = "Intensity Level " .. level .. " Lost"
        r, g, b = 0.0, 0.6, 0.8 -- Blue/Teal
    end
    
    -- Logic: Chat Info (New Setting)
    if EHTweaksDB.chatInfo then
        print("|cff00FF00[EHT Info]|r " .. msg)
    end
    
    -- Logic: Use Raid Warning ONLY for Level 2+ GAINS
    if isReached and level >= 2 then
        if RaidWarningFrame and RaidNotice_AddMessage then
            local colorInfo = { r = r, g = g, b = b }
            RaidNotice_AddMessage(RaidWarningFrame, msg, colorInfo)
            PlaySound("RaidWarning") 
            return
        end
    end

    -- Logic: Use Custom Frame for Level 1 Gains AND All Losses
    local f = intensityAlertFrame
    f.anim:Stop()
    f:SetAlpha(0)
    f:Show()
    
    f.text:SetText(msg)
    f.text:SetTextColor(r, g, b)
    
    f.anim:Play()
end

local function CheckIntensityThresholds(newInt)
    if not EHTweaksDB.enableIntensityWarning then return end
    
    -- Initialize on first run without triggering
    if lastIntensityCheck == nil then 
        lastIntensityCheck = newInt 
        return 
    end
    
    if lastIntensityCheck == newInt then return end

    for i, thresh in ipairs(INTENSITY_THRESHOLDS) do
        -- Logic: Use +1 for reached (except last one) and -1 for lost
        local reachT = (i < #INTENSITY_THRESHOLDS) and (thresh + 1) or thresh
        local lostT = thresh - 1
        
        -- Check Reached (Crossed upwards past reach threshold)
        if lastIntensityCheck < reachT and newInt >= reachT then
             TriggerIntensityAlert(i, true)
        end
        
        -- Check Lost (Crossed downwards past lost threshold)
        if lastIntensityCheck > lostT and newInt <= lostT then
             TriggerIntensityAlert(i, false)
        end
    end
    
    lastIntensityCheck = newInt
end

-- =========================================================
-- SECTION: HAZARD WARNING SYSTEM (Custom Mechanics)
-- =========================================================

local hazardAlertFrame = nil

local function CreateHazardAlertFrame()
    if hazardAlertFrame then return hazardAlertFrame end
    
    local f = CreateFrame("Frame", "EHTweaks_HazardAlert", UIParent)
    f:SetSize(512, 120)
    f:SetPoint("CENTER", 0, 200) -- Positioned higher, prominent
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:Hide()
    
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    text:SetPoint("CENTER")
    -- Use a fixed large size (36) regardless of UI scale
    text:SetFont("Fonts\\FRIZQT__.TTF", 36, "OUTLINE") 
    f.text = text
    
    local ag = f:CreateAnimationGroup()
    
    -- Pop In (Scale Up)
    local aScale = ag:CreateAnimation("Scale")
    aScale:SetScale(1.5, 1.5)
    aScale:SetDuration(0.1)
    aScale:SetOrder(1)
    aScale:SetSmoothing("OUT")
    
    -- Scale Back to Normal
    local aScale2 = ag:CreateAnimation("Scale")
    aScale2:SetScale(0.66, 0.66) -- 1/1.5
    aScale2:SetDuration(0.15)
    aScale2:SetOrder(2)
    aScale2:SetSmoothing("IN")

    -- Fade In
    local aAlpha = ag:CreateAnimation("Alpha")
    aAlpha:SetChange(1) 
    aAlpha:SetDuration(0.1)
    aAlpha:SetOrder(1)

    -- Hold then Fade Out (Shortened for 5s spawn frequency)
    local aFade = ag:CreateAnimation("Alpha")
    aFade:SetChange(-1)
    aFade:SetStartDelay(1.5) 
    aFade:SetDuration(0.5)
    aFade:SetOrder(3)
    
    ag:SetScript("OnFinished", function() f:Hide() end)
    f.anim = ag
    
    hazardAlertFrame = f
    return f
end

local function TriggerHazardAlert(text)
    -- 1. Custom Huge Frame
    if not hazardAlertFrame then CreateHazardAlertFrame() end
    local f = hazardAlertFrame
    f.anim:Stop()
    f:SetAlpha(0)
    f:Show()
    
    f.text:SetText(text)
    f.text:SetTextColor(1, 0.2, 0.2) -- Bright Red
    
    f.anim:Play()

    -- 2. Audible Alert
	PlaySound("RaidWarning", "Master")    
    
    -- 3. Chat Backup (New Setting)
    if EHTweaksDB.chatWarnings then
        print("|cffff0000[EHT WARNING]|r " .. text)
    end
end

local hazardFrame = CreateFrame("Frame")
hazardFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
hazardFrame:SetScript("OnEvent", function(self, event, ...)
    local timestamp, eventType, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, spellId, spellName = ...

    -- [SHADOW FISSURE]
    -- ID: 95074 (Summon Event)
    -- Mechanic: At intensity >= 275* server forces player to summon the fissure at their feet so we hook this event to warn about it. We will use lower int lvl as threshold because when loosing intensity lvl SF can spawn up to 5 sec after.   
    if eventType == "SPELL_SUMMON" and spellId == 95074 then
        if EHTweaksDB.enableShadowFissureWarning then
            local intensity = lastIntData.intensity or 0
            if intensity >= 250 then
                if srcGUID == UnitGUID("player") then
                    TriggerHazardAlert("Shadow Fissure under YOU! MOVE!")
                end
            end
        end
    end
end)

-- --- Global Loadout Utilities ---

function EHTweaks_GetActiveLoadoutInfo()
    local name = "Default"
    local id = activeLoadoutId

    if (not id or id == 0) and knownLoadouts then
        local currentName = "Default"		
        if knownLoadouts[currentName] then	  
            id = knownLoadouts[currentName]
            name = currentName            
            activeLoadoutId = id		
        end
    end

    return id, name
end


-- Global functions for Keybind
function EHTweaks_ToggleSkillTree()
    if _G.skillTreeFrame then
        if _G.skillTreeFrame:IsShown() then
            _G.skillTreeFrame:Hide()
        else
            _G.skillTreeFrame:Show()
        end
    else
        print("|cffff0000EHTweaks:|r Skill Tree frame not found (is Project Ebonhold loaded?)")
    end
end

function EHTweaks_ToggleEchoes()
    local frame = _G.ProjectEbonholdEmpowermentFrame
    if frame then
        if frame:IsShown() then
            frame:Hide()
        else
            frame:Show()
        end
    else
        print("|cffff0000EHTweaks:|r Echoes frame not found.")
    end
end

-- =========================================================
-- HELPER: 3.3.5a Spell Description Scanner
-- =========================================================
local scannerTooltip = CreateFrame("GameTooltip", "EHTweaks_ScannerTooltip", nil, "GameTooltipTemplate")
scannerTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

local function GetSpellDescription_Local(spellId)
    if not spellId then return nil end
    
    scannerTooltip:ClearLines()
    scannerTooltip:SetHyperlink("spell:" .. spellId)
    
    local lines = scannerTooltip:NumLines()
    if lines < 1 then return nil end
    
    local desc = ""
    for i = 2, lines do
        local lineObj = _G["EHTweaks_ScannerTooltipTextLeft" .. i]
        if lineObj then
            local text = lineObj:GetText()
            if text then
                if not string.find(text, "^Rank %d+$") then
                    if desc ~= "" then desc = desc .. "\n" end
                    desc = desc .. text
                end
            end
        end
    end
    
    if desc == "" then return nil end
    return desc
end

-- --- Linking Helper ---

function EHTweaks_HandleLinkClick(spellId)
    if IsControlKeyDown() and IsAltKeyDown() and spellId then
        local link = GetSpellLink(spellId)
        
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
                ChatFrame_OpenChat(link)
            end
            return true
        end
    end
    return false
end

-- --- Visuals Helper ---

local function CreateGlow(btn)
    if btn.searchGlow then return end

    local glow = btn:CreateTexture(nil, "OVERLAY")
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(0, 1, 0, 1)
    glow:SetPoint("CENTER", btn, "CENTER", 0, 0)
    glow:SetSize(btn:GetWidth() * 1.8, btn:GetHeight() * 1.8)
    glow:Hide()

    local ag = glow:CreateAnimationGroup()
    local a1 = ag:CreateAnimation("Alpha")
    a1:SetChange(-0.6)
    a1:SetDuration(0.8)
    a1:SetOrder(1)
    local a2 = ag:CreateAnimation("Alpha")
    a2:SetChange(0.6)
    a2:SetDuration(0.8)
    a2:SetOrder(2)
    
    ag:SetLooping("REPEAT")
    
    btn.searchGlow = glow
    btn.searchGlowAnim = ag
end

local function SetHighlight(btn, isMatch)
    if not btn then return end

    if isMatch then
        btn:SetAlpha(FILTER_MATCH_ALPHA)
        if not btn.searchGlow then CreateGlow(btn) end
        
        btn.searchGlow:Show()
        if not btn.searchGlowAnim:IsPlaying() then
            btn.searchGlowAnim:Play()
        end
    else
        btn:SetAlpha(FILTER_NOMATCH_ALPHA)
        if btn.searchGlow then
            btn.searchGlow:Hide()
            btn.searchGlowAnim:Stop()
        end
    end
end

-- =========================================================
-- SECTION 1: SKILL TREE EXTENSIONS
-- =========================================================

local function FocusNode(nodeId)
    local btn = _G["skillTreeNode" .. nodeId]
    local scrollFrame = _G.skillTreeScroll
    local canvas = _G.skillTreeCanvas
    
    if not btn or not scrollFrame or not canvas then return end

    local scrollW = scrollFrame:GetWidth()
    local scrollH = scrollFrame:GetHeight()
    local point, relativeTo, relativePoint, xOfs, yOfs = btn:GetPoint(1)
    
    if not xOfs then return end

    local currentScale = canvas:GetScale() or 1
    
    local targetH = xOfs - (scrollW / 2) / currentScale
    local targetV = math.abs(yOfs) - (scrollH / 2) / currentScale

    local maxH = scrollFrame:GetHorizontalScrollRange()
    local maxV = scrollFrame:GetVerticalScrollRange()
    
    targetH = math.max(0, math.min(targetH, maxH))
    targetV = math.max(0, math.min(targetV, maxV))

    scrollFrame:SetHorizontalScroll(targetH)
    scrollFrame:SetVerticalScroll(targetV)
end

local function ApplySkillFilter(text)
    if text == "" then
        matchedNodes = {}
        if TalentDatabase and TalentDatabase[0] then
            for _, nodeData in ipairs(TalentDatabase[0].nodes) do
                local btn = _G["skillTreeNode" .. nodeData.id]
                if btn then
                    btn:SetAlpha(1)
                    if btn.searchGlow then btn.searchGlow:Hide() end
                end
            end
        end
        return
    end

    text = string.lower(text)
    matchedNodes = {} 
    
    if not TalentDatabase or not TalentDatabase[0] then return end

    for _, nodeData in ipairs(TalentDatabase[0].nodes) do
        local btn = _G["skillTreeNode" .. nodeData.id]
        
        if btn then
            local isMatch = false
            if nodeData.spells then
                for _, spellId in ipairs(nodeData.spells) do
                    local name = GetSpellInfo(spellId)
                    if name and string.find(string.lower(name), text, 1, true) then
                        isMatch = true
                        break
                    end
                    local desc = GetSpellDescription_Local(spellId)
                    if desc and string.find(string.lower(desc), text, 1, true) then
                        isMatch = true
                        break
                    end
                end
            end

            SetHighlight(btn, isMatch)
            
            if isMatch then
                table.insert(matchedNodes, nodeData.id)
            end
        end
    end
end

local function CreateSkillFilterFrame()
    local parent = _G.skillTreeBottomBar
    if not parent then return end

    local f = CreateFrame("Frame", "EHTweaks_FilterFrame", parent)
    f:SetSize(200, 30)
    
    if _G.skillTreeApplyButton then
        f:SetPoint("LEFT", _G.skillTreeApplyButton, "RIGHT", 10, 0)
    else
        f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -10, 5)
    end

    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.label:SetPoint("LEFT", f, "LEFT", 0, 0)
    f.label:SetText("Filter:")
    f.label:SetTextColor(1, 0.82, 0)

    local eb = CreateFrame("EditBox", "EHTweaks_FilterBox", f, "InputBoxTemplate")
    eb:SetSize(120, 20)
    eb:SetPoint("LEFT", f.label, "RIGHT", 8, 0)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(50)

    local clearBtn = CreateFrame("Button", nil, eb)
    clearBtn:SetSize(14, 14)
    clearBtn:SetPoint("RIGHT", eb, "RIGHT", -4, 0)
    clearBtn:SetNormalTexture("Interface\\FriendsFrame\\ClearBroadcastIcon")
    clearBtn:SetAlpha(0.5)
    clearBtn:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    clearBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
    clearBtn:SetScript("OnClick", function()
        eb:SetText("")
        eb:ClearFocus()
        ApplySkillFilter("")
    end)

    eb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if self:GetText() == "" then ApplySkillFilter("") end
    end)

    eb:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if matchedNodes and #matchedNodes > 0 then
            FocusNode(matchedNodes[1])
        end
    end)

    eb:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        if text ~= currentSearchText then
            currentSearchText = text
            searchTimer = 0
            if text == "" then ApplySkillFilter("") end
        end
    end)

    eb:SetScript("OnUpdate", function(self, elapsed)
        elapsed = math.min(elapsed or 0, 0.1)

        if currentSearchText then
             -- Safety Init
             if not searchTimer then searchTimer = 0 end
             if not SEARCH_THROTTLE then SEARCH_THROTTLE = 0.2 end
             
             searchTimer = searchTimer + elapsed
             if searchTimer >= SEARCH_THROTTLE then
                ApplySkillFilter(currentSearchText)
                searchTimer = -9999
             end
        end
    end)


    
    if ProjectEbonhold and ProjectEbonhold.SkillTree and ProjectEbonhold.SkillTree.UpdateTotalSoulPoints then
        hooksecurefunc(ProjectEbonhold.SkillTree, "UpdateTotalSoulPoints", function()
            if currentSearchText ~= "" then
                ApplySkillFilter(currentSearchText)
            end
        end)
    end

    filterBox = eb
end

-- =========================================================
-- SAVE & RESET BUTTONS
-- =========================================================

local function CreateExtraTreeButtons()
    if not _G.skillTreeBottomBar then return end
    if _G.EHTweaks_ResetTreeButton then return end

    -- --- RESET BUTTON ---
    local resetBtn = CreateFrame("Button", "EHTweaks_ResetTreeButton", _G.skillTreeBottomBar, "UIPanelButtonTemplate")
    resetBtn:SetSize(90, 22)
    
    -- Position: Bottom Right of the skill tree bar
    resetBtn:SetPoint("BOTTOMRIGHT", _G.skillTreeBottomBar, "BOTTOMRIGHT", -10, 5)
    resetBtn:SetText("Reset Tree")
    
    resetBtn:SetScript("OnClick", function()
        -- 1. Identify current active loadout for the reset target
        local currentName = "Default"
        if _G.skillTreeLoadoutDropdown then
            currentName = UIDropDownMenu_GetText(_G.skillTreeLoadoutDropdown) or "Default"
        end
        
        -- Resolve ID (using sniffed data from EHTweaks global state)
        local targetID = knownLoadouts[currentName]
        if not targetID and activeLoadoutId then targetID = activeLoadoutId end
        if not targetID then targetID = 0 end 
        
        -- 2. Find Start Node for Fail-Safe method
        local startNodeId = nil
        if TalentDatabase and TalentDatabase[0] then
            for _, node in ipairs(TalentDatabase[0].nodes) do
                if node.isStart then
                    startNodeId = node.id
                    break
                end
            end
        end
    
        -- 3. Show Confirmation
        StaticPopupDialogs["EHTWEAKS_RESET_TREE_CONFIRM"] = {
            text = "Are you sure you want to reset your entire Skill Tree?\n\n|cffFF0000This will unlearn all talents and refund Soul Ashes!|r\n\n(An automatic backup of your current build will be saved)",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                if ProjectEbonhold and ProjectEbonhold.SendLoadoutToServer and startNodeId then
                    
                    -- A. Trigger Auto-Backup (Call to LoadoutManager.lua function)
                    if EHTweaks_CreateAutoBackup then 
                        EHTweaks_CreateAutoBackup() 
                    end
                    
                    -- B. Send Reset Payload (Start Node = 1 point)
                    local loadoutPayload = {
                        id = targetID, 
                        name = currentName,
                        nodeRanks = { [startNodeId] = 1 } 
                    }
                    
                    ProjectEbonhold.SendLoadoutToServer(loadoutPayload)
                    print("|cff00ff00EHTweaks:|r Resetting tree...")
                    
                    -- C. Refresh UI after delay
                    C_Timer.After(0.5, function()
                         if ProjectEbonhold.RequestLoadoutFromServer then 
                             ProjectEbonhold.RequestLoadoutFromServer() 
                         end
                    end)
                else
                    print("|cffff0000EHTweaks:|r Reset failed. (Missing dependencies or Start Node ID)")
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        
        
        local dialog = StaticPopup_Show("EHTWEAKS_RESET_TREE_CONFIRM")
        if dialog then
            dialog:SetFrameStrata("FULLSCREEN_DIALOG")
            if _G.skillTreeFrame then
                dialog:SetFrameLevel(_G.skillTreeFrame:GetFrameLevel() + 50)
            else
                dialog:SetFrameLevel(200)
            end
        end
    end)
    
    resetBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Reset Skill Tree", 1, 1, 1)
        GameTooltip:AddLine("Refunds all spent Soul Ashes and resets talents.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- --- LOADOUTS BUTTON ---
    local loadoutsBtn = CreateFrame("Button", "EHTweaks_LoadoutsButton", _G.skillTreeBottomBar, "UIPanelButtonTemplate")
    loadoutsBtn:SetSize(90, 22)
    loadoutsBtn:SetPoint("RIGHT", resetBtn, "LEFT", -5, 0)
    loadoutsBtn:SetText("Loadouts")
    
    loadoutsBtn:SetScript("OnClick", function()
        if EHTweaks_ToggleLoadoutManager then
            EHTweaks_ToggleLoadoutManager()
        else
            print("|cffff0000EHTweaks:|r Loadout Manager module not loaded.")
        end
    end)
    
    loadoutsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Loadout Manager", 1, 1, 1)
        GameTooltip:AddLine("Save, Load, Import, and Export your talent builds locally.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    loadoutsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- =========================================================
-- SECTION 2: ECHOES RECORDING & FILTER
-- =========================================================

local function RecordEchoInfo(spellId, quality)
    if not spellId then return end
    
    local name, _, icon = GetSpellInfo(spellId)
    if not name then
        EHTweaks_Log("SKIPPED Echo Record: SpellID " .. tostring(spellId) .. " (GetSpellInfo failed)")
        return
    end

    if not EHTweaksDB then return end
    if not EHTweaksDB.seenEchoes then EHTweaksDB.seenEchoes = {} end
    
    if EHTweaksDB.seenEchoes[spellId] and (EHTweaksDB.seenEchoes[spellId].quality or 0) >= (quality or 0) then
        EHTweaks_Log("IGNORED Echo Record: " .. name .. " (" .. spellId .. ") - Existing Quality Higher or Equal")
        return
    end
    
    EHTweaksDB.seenEchoes[spellId] = {
        name = name,
        icon = icon,
        quality = math.abs(quality or 0)
    }
    EHTweaks_Log("SAVED Echo Record: " .. name .. " (" .. spellId .. ") Quality: " .. (quality or 0))
end

StaticPopupDialogs["EHTWEAKS_SAVE_ECHO_CONFIRM"] = {
    text = "Save Echo to Database?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function(self)
        -- Data is stored in self.data table
        if self.data and self.data.spellId then
            RecordEchoInfo(self.data.spellId, 0)
            print("|cff00FF00[EHTweaks]|r Echo saved: " .. (self.data.name or "Unknown"))
            
            -- Refresh Browser if it exists and is open
            if EHTweaks_RefreshBrowser then
                EHTweaks_RefreshBrowser()
            end
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local originalSetItemRef = SetItemRef

function SetItemRef(link, text, button, chatFrame)
    -- Always call original first to preserve default behavior
    if originalSetItemRef then
        originalSetItemRef(link, text, button, chatFrame)
    end
    
    -- Check if feature is enabled
    if not EHTweaksDB or not EHTweaksDB.collectEchoesFromChatLinks then
        return
    end
    
    -- Parse spell links: |Hspell:12345:0|h[Spell Name]|h or |Hspell:12345|h[Spell Name]|h
    local spellId = string.match(link, "spell:(%d+)")
    
    if not spellId then
        return
    end
    
    spellId = tonumber(spellId)
    
    -- Validate spell exists
    local spellName, _, spellIcon = GetSpellInfo(spellId)
    if not spellName then
        return
    end
    
    -- Check if already in database
    if EHTweaksDB.seenEchoes and EHTweaksDB.seenEchoes[spellId] then
        -- Already saved, show info message
        print("|cff00FF00[EHTweaks]|r Echo already in database: " .. spellName)
        return
    end
    
    -- Update the dialog text with spell info (icon + name)
    StaticPopupDialogs["EHTWEAKS_SAVE_ECHO_CONFIRM"].text = 
        "New Echo detected:|n|n|T" .. spellIcon .. ":24:24|t |cff71d5ff" .. spellName .. "|r|n|nSave to Echoes Database?"
    
    -- Show popup and pass data via the dialog object
    local dialog = StaticPopup_Show("EHTWEAKS_SAVE_ECHO_CONFIRM")
    if dialog then
        dialog.data = {
            spellId = spellId,
            name = spellName,
        }
    end
end

local function RecordOwnedEchoes()
    local granted = ProjectEbonhold.PerkService.GetGrantedPerks()
    if not granted then 
        EHTweaks_Log("RecordOwnedEchoes: No perks granted found.")
        return 
    end

    EHTweaks_Log("--- Recording Owned Echoes ---")
    for spellName, instances in pairs(granted) do
        for _, info in ipairs(instances) do
            RecordEchoInfo(info.spellId, info.quality)
        end
    end
end

local function GetPerkListSorted()
    local granted = ProjectEbonhold.PerkService.GetGrantedPerks()
    local perkList = {}
    if not granted then return perkList end

    for spellName, instances in pairs(granted) do
        local highestQuality = 0
        local primarySpellId = nil

        for _, instance in ipairs(instances) do
            if (instance.quality or 0) > highestQuality then
                highestQuality = instance.quality or 0
                primarySpellId = instance.spellId
            end
        end
        if not primarySpellId and instances[1] then primarySpellId = instances[1].spellId end

        table.insert(perkList, {
            spellName = spellName,
            spellId = primarySpellId,
            quality = highestQuality
        })
    end

    table.sort(perkList, function(a, b)
        if a.quality ~= b.quality then return a.quality > b.quality end
        return a.spellId < b.spellId
    end)
    
    return perkList
end

local function ApplyEchoFilter(text)
    local frame = _G.ProjectEbonholdEmpowermentFrame
    if not frame or not frame.perkIcons then return end
    
    local list = GetPerkListSorted()
    local searchText = string.lower(text)

    for i, iconBtn in ipairs(frame.perkIcons) do
        local data = list[i]
        
        if data then
            iconBtn.ehSpellId = data.spellId 
            
            local isMatch = false
            if searchText == "" then
                isMatch = true
            else
                if string.find(string.lower(data.spellName), searchText, 1, true) then
                    isMatch = true
                else
                    local desc = GetSpellDescription_Local(data.spellId)
                    if desc and string.find(string.lower(desc), searchText, 1, true) then
                        isMatch = true
                    end
                end
            end

            if searchText == "" then
                iconBtn:SetAlpha(1.0)
                if iconBtn.searchGlow then iconBtn.searchGlow:Hide() end
            else
                SetHighlight(iconBtn, isMatch)
            end
        end
    end
end

local function CreateEchoFilterFrame()
    local parent = _G.ProjectEbonholdEmpowermentFrame
    if not parent or echoFilterBox then return end

    local f = CreateFrame("Frame", "EHTweaks_EchoFilterFrame", parent)
    f:SetSize(200, 30)
    f:SetPoint("BOTTOM", parent, "BOTTOM", 0, 15)
    f:SetFrameLevel(parent:GetFrameLevel() + 5)

    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.label:SetPoint("LEFT", f, "LEFT", 0, 0)
    f.label:SetText("Filter:")
    f.label:SetTextColor(1, 0.82, 0)

    local eb = CreateFrame("EditBox", "EHTweaks_EchoFilterBox", f, "InputBoxTemplate")
    eb:SetSize(130, 20)
    eb:SetPoint("LEFT", f.label, "RIGHT", 8, 0)
    eb:SetAutoFocus(false)
    eb:SetMaxLetters(50)

    local clearBtn = CreateFrame("Button", nil, eb)
    clearBtn:SetSize(14, 14)
    clearBtn:SetPoint("RIGHT", eb, "RIGHT", -4, 0)
    clearBtn:SetNormalTexture("Interface\\FriendsFrame\\ClearBroadcastIcon")
    clearBtn:SetAlpha(0.5)
    clearBtn:SetScript("OnEnter", function(self) self:SetAlpha(1) end)
    clearBtn:SetScript("OnLeave", function(self) self:SetAlpha(0.5) end)
    clearBtn:SetScript("OnClick", function()
        eb:SetText("")
        eb:ClearFocus()
        ApplyEchoFilter("")
    end)

    eb:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        if self:GetText() == "" then ApplyEchoFilter("") end
    end)

    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    eb:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        if text ~= currentEchoSearchText then
            currentEchoSearchText = text
            ApplyEchoFilter(text)
        end
    end)
    
    echoFilterBox = eb
end

-- ==============================
-- EHT: EmpowermentFrame tweaks
-- Shift+Drag move + save position + Close (X) button
-- ==============================

local function EHT_RestoreEmpowermentFramePosition()
    if not EHTweaksDB or not EHTweaksDB.empowermentFramePos then return end

    local frame = _G.ProjectEbonholdEmpowermentFrame
    if not frame then return end

    local p = EHTweaksDB.empowermentFramePos
    -- p = { point, relativePoint, x, y }
    if not p[1] or not p[2] then return end

    frame:ClearAllPoints()
    frame:SetPoint(p[1], UIParent, p[2], p[3] or 0, p[4] or 0)
end

local function EHT_SaveEmpowermentFramePosition(frame)
    if not frame then return end
    if not EHTweaksDB then EHTweaksDB = {} end

    local point, _, relativePoint, xOfs, yOfs = frame:GetPoint(1)
    if not point or not relativePoint then return end

    EHTweaksDB.empowermentFramePos = { point, relativePoint, xOfs or 0, yOfs or 0 }
end

local function EHT_InstallEmpowermentCloseButton(frame)
    if not frame then return end

    -- Create ONCE
    if not frame.ehtCloseBtn then
        local close = CreateFrame("Button", "EHTEmpowermentCloseBtn", frame, "UIPanelCloseButton")
        close:SetSize(32, 32)
        close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
        close:SetFrameStrata("DIALOG")
        close:SetFrameLevel(frame:GetFrameLevel() + 10)

        close:SetScript("OnClick", function()
            frame:Hide() 
        end)

        close:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Close Echoes", 1, 1, 1)
            GameTooltip:Show()
        end)

        close:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        frame.ehtCloseBtn = close
    end


    frame.ehtCloseBtn:Show()
end


local function EHT_SetupEmpowermentFrameMoveAndSave()
    local frame = _G.ProjectEbonholdEmpowermentFrame
    if not frame or frame.EHT_MoverInstalled then return end

    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    -- ProjectEbonhold sets drag scripts directly to StartMoving/StopMovingOrSizing,
    -- so we override to enforce Shift-only movement.
    frame:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then
            self:StartMoving()
            self.ehtIsMoving = true
            if self.ehtCloseBtn and self.ehtCloseBtn.Raise then self.ehtCloseBtn:Raise() end
        end
    end)

    frame:SetScript("OnDragStop", function(self)
        if self.ehtIsMoving then
            self:StopMovingOrSizing()
            self.ehtIsMoving = false
            EHT_SaveEmpowermentFramePosition(self)
        end
    end)

    -- Ensure position + close button are applied every time it becomes visible.
    frame:HookScript("OnShow", function(self)
        EHT_RestoreEmpowermentFramePosition()
        EHT_InstallEmpowermentCloseButton(self) -- will show/anchor overlay
    end)

    frame:HookScript("OnHide", function(self)
        if self.ehtCloseBtn then self.ehtCloseBtn:Hide() end
    end)

    -- Install immediately (in case frame is already visible right now)
    EHT_InstallEmpowermentCloseButton(frame)
    EHT_RestoreEmpowermentFramePosition()

    frame.EHT_MoverInstalled = true
end


-- Delayed init with retry logic
function EHTweaks_InitEmpowermentFrameTweaks(tries)
    tries = tries or 0

    if _G.ProjectEbonholdEmpowermentFrame then
        EHT_SetupEmpowermentFrameMoveAndSave()
        return
    end

    if tries >= 20 then 
        print("|cffFF0000EHTweaks:|r Failed to find ProjectEbonholdEmpowermentFrame after 10 seconds")
        return 
    end
    
    if CTimer and CTimer.After then
        CTimer.After(0.5, function() EHTweaks_InitEmpowermentFrameTweaks(tries + 1) end)
    end
end

local function EHT_After(sec, fn)
    if CTimer and CTimer.After then return CTimer.After(sec, fn) end
    if C_Timer and C_Timer.After then return C_Timer.After(sec, fn) end
    if fn then fn() end
end

function EHTweaks_HookEmpowermentToggle(tries)
    tries = tries or 0

    if type(_G.ToggleEmpowermentPanel) == "function" then
        if not _G.ToggleEmpowermentPanel_EHTHooked then
            local orig = _G.ToggleEmpowermentPanel
            _G.ToggleEmpowermentPanel = function(...)
                local r = orig(...)                
                EHT_After(0, function() EHTweaks_InitEmpowermentFrameTweaks(0) end)
                return r
            end
            _G.ToggleEmpowermentPanel_EHTHooked = true
        end

        -- If frame already exists (created in ENTERING_WORLD), install immediately too. 
        if _G.ProjectEbonholdEmpowermentFrame then
            EHTweaks_InitEmpowermentFrameTweaks(0)
        end
        return
    end

    -- Toggle function not loaded yet; retry a bit.
    if tries < 60 then
        EHT_After(0.5, function() EHTweaks_HookEmpowermentToggle(tries + 1) end)
    end
end



-- ==============================
-- EHT: IntensityWarningFrame tweaks
-- Shift+Drag move + save position
-- ==============================

local function EHT_RestoreIntensityWarningPosition()
    if not EHTweaksDB or not EHTweaksDB.intensityWarningPos then return end

    local frame = _G.IntensityWarningFrame
    if not frame then return end

    local p = EHTweaksDB.intensityWarningPos
    -- p = { point, relativePoint, x, y }
    if not p[1] or not p[2] then return end

    frame:ClearAllPoints()
    frame:SetPoint(p[1], UIParent, p[2], p[3] or 0, p[4] or 0)
end

local function EHT_SaveIntensityWarningPosition(frame)
    if not frame then return end
    if not EHTweaksDB then EHTweaksDB = {} end

    local point, _, relativePoint, xOfs, yOfs = frame:GetPoint(1)
    if not point or not relativePoint then return end

    EHTweaksDB.intensityWarningPos = { point, relativePoint, xOfs or 0, yOfs or 0 }
end

local function EHT_SetupIntensityWarningMoveAndSave()
    local frame = _G.IntensityWarningFrame
    if not frame or frame.EHT_MoverInstalled then return end

    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    frame:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then
            self:StartMoving()
            self.ehtIsMoving = true
        end
    end)

    frame:SetScript("OnDragStop", function(self)
        if self.ehtIsMoving then
            self:StopMovingOrSizing()
            self.ehtIsMoving = false
            EHT_SaveIntensityWarningPosition(self)
        end
    end)

    -- Restore position when frame shows (it hides after unlock)
    frame:HookScript("OnShow", function()
        EHT_RestoreIntensityWarningPosition()
    end)

    -- Apply saved pos immediately if frame is already visible
    EHT_RestoreIntensityWarningPosition()

    frame.EHT_MoverInstalled = true
end

-- Delayed init with retry logic
function EHTweaks_InitIntensityWarningTweaks(tries)
    tries = tries or 0

    if _G.IntensityWarningFrame then
        EHT_SetupIntensityWarningMoveAndSave()
        return
    end

    if tries >= 20 then return end
    if CTimer and CTimer.After then
        CTimer.After(0.5, function() EHTweaks_InitIntensityWarningTweaks(tries + 1) end)
    end
end



-- =========================================================
-- SECTION 3: HOOKS & WRAPPERS
-- =========================================================

local function SecureWrapper(btn, getSpellIdFunc)
    if not btn or btn.hasLinkWrapper then return end
    
    local original = btn:GetScript("OnClick")
    
    btn:SetScript("OnClick", function(self, button)
        local spellId = getSpellIdFunc(self)
        if EHTweaks_HandleLinkClick(spellId) then
            return 
        end
        if original then
            original(self, button)
        end
    end)
    
    btn.hasLinkWrapper = true
end

local function HookSkillTreeButtons()
    if not TalentDatabase or not TalentDatabase[0] then return end
    
    for _, nodeData in ipairs(TalentDatabase[0].nodes) do
        local btn = _G["skillTreeNode" .. nodeData.id]
        if btn then
            SecureWrapper(btn, function(b) 
                if b.spells then
                    if b.isMultipleChoice and b.selectedSpell and b.selectedSpell > 0 then
                        return b.spells[b.selectedSpell]
                    elseif #b.spells > 0 then
                        return b.spells[#b.spells]
                    end
                end
                return nil
            end)
        end
    end
end

-- Helper to update the visual state of a grid button
local function UpdateEchoButtonVisual(btn)
    local spellId = btn.ehSpellId
    if not spellId then return end
    
    local isFav = EHTweaksDB.favorites and EHTweaksDB.favorites[spellId]
    local showMarker = EHTweaksDB.showEmpowermentFavorites
    
    if isFav and showMarker then
        if not btn.favMarker then
            local m = btn:CreateTexture(nil, "OVERLAY")
            m:SetSize(14, 14)
            m:SetPoint("TOPRIGHT", 2, 2)
            m:SetTexture("Interface\\Icons\\Inv_Misc_Gem_02")            
            m:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            btn.favMarker = m
        end
        btn.favMarker:Show()
    else
        if btn.favMarker then btn.favMarker:Hide() end
    end
end

local function HookEchoButtons()
    local frame = _G.ProjectEbonholdEmpowermentFrame
    if not frame or not frame.perkIcons then return end
    
    local list = GetPerkListSorted()
    
    for i, iconBtn in ipairs(frame.perkIcons) do
        if list[i] then
            iconBtn.ehSpellId = list[i].spellId
            iconBtn:EnableMouse(true)
            
            -- Register both buttons
            iconBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            
            -- Hook OnClick
            if not iconBtn.hasEHTHook then
                iconBtn:SetScript("OnClick", function(self, button)
                    if button == "RightButton" and IsShiftKeyDown() then
                        -- Toggle Favorite
                        if not EHTweaksDB.favorites then EHTweaksDB.favorites = {} end
                        
                        local id = self.ehSpellId
                        if EHTweaksDB.favorites[id] then
                            EHTweaksDB.favorites[id] = nil
                            print("|cffFFFF00EHTweaks|r: Removed from Favorites.")
                        else
                            EHTweaksDB.favorites[id] = true
                            print("|cff00FF00EHTweaks|r: Added to Favorites!")
                        end
                        
                        -- Update THIS button immediately
                        UpdateEchoButtonVisual(self)
                        
                        -- Refresh all other Empowerment buttons (in case of duplicates)
                        for _, otherBtn in ipairs(frame.perkIcons) do
                            if otherBtn.ehSpellId then
                                UpdateEchoButtonVisual(otherBtn)
                            end
                        end
                        
                        -- Refresh Draft UI if open
                        if EHTweaks_RefreshFavouredMarkers then 
                            EHTweaks_RefreshFavouredMarkers() 
                        end
				
				if EHTweaks_RefreshBrowser then
                            EHTweaks_RefreshBrowser()
                        end
                        
                        return -- Don't trigger chat link
                    else
                        -- Standard EHT Link Logic (Ctrl+Alt)
                        EHTweaks_HandleLinkClick(self.ehSpellId)
                    end
                end)
                
                -- Tooltip Hook
                iconBtn:HookScript("OnEnter", function(self)
                    local id = self.ehSpellId
                    if id and EHTweaksDB.favorites and EHTweaksDB.favorites[id] then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("|cffFFD700★ Favorited|r")
                        GameTooltip:AddLine("|cff888888Shift+Right-Click to Unfavorite|r")
                        GameTooltip:Show()
                    else
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("|cff888888Shift+Right-Click to Favorite|r")
                        GameTooltip:Show()
                    end
                end)
                
                iconBtn.hasEHTHook = true
            end
            
            -- Always update visual when list refreshes
            UpdateEchoButtonVisual(iconBtn)
        end
    end
end



-- =========================================================
-- SECTION 4: MOVABLE PERK BUTTONS
-- =========================================================

local function RestorePerkButtonPosition()
    if EHTweaksDB.perkButtonPos then
        local p = EHTweaksDB.perkButtonPos
        if PerkChooseButton then
            PerkChooseButton:ClearAllPoints()
            PerkChooseButton:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        end
        if PerkHideButton then
            PerkHideButton:ClearAllPoints()
            PerkHideButton:SetPoint(p[1], UIParent, p[2], p[3], p[4])
        end
    end
end

local function SetupMovable(frame)
    if not frame or frame.EHTweaksMovable then return end

    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)

    frame:HookScript("OnDragStart", function(self)
        if IsShiftKeyDown() then
            self:StartMoving()
            self.isMoving = true
        end
    end)

    frame:HookScript("OnDragStop", function(self)
        if self.isMoving then
            self:StopMovingOrSizing()
            self.isMoving = false
            local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()
            EHTweaksDB.perkButtonPos = { point, relativePoint, xOfs, yOfs }
            RestorePerkButtonPosition()
        end
    end)

    frame:HookScript("OnEnter", function(self)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00FF00Shift+Drag|r to move", 1, 1, 1)
        GameTooltip:Show()
    end)

    frame.EHTweaksMovable = true
end

local function SetupPerkButtons()
    if PerkChooseButton then SetupMovable(PerkChooseButton) end
    if PerkHideButton then 
        SetupMovable(PerkHideButton)
        PerkHideButton:HookScript("OnShow", RestorePerkButtonPosition)
    end
    RestorePerkButtonPosition()
end

-- =========================================================
-- SECTION 5: STARTER DATABASE HANDLING
-- =========================================================

local function IsDatabaseEmpty()
    return (not EHTweaksDB.seenEchoes) or (next(EHTweaksDB.seenEchoes) == nil)
end

local function ImportStarterDB()
    if not _G.ETHTweaks_OptionalDB_Data then return end
    
    local starter = _G.ETHTweaks_OptionalDB_Data
    local code = starter.data
    
    if EHTweaks_ImportEchoes then
        local count, err = EHTweaks_ImportEchoes(code)
        if count > 0 then
            print("|cff00ff00EHTweaks:|r Starter Database imported (" .. count .. " echoes).")
            if starter.contributors then
                print("|cff00ff00EHTweaks:|r This Echoes DB was created thanks to: " .. starter.contributors)
            end
        elseif err then
            print("|cffff0000EHTweaks:|r Starter DB Import failed: " .. err)
        end
    end
    
    EHTweaksDB.offeredOptionalDB = starter.version
end

local function CheckStarterDatabase()
    local starter = _G.ETHTweaks_OptionalDB_Data
    if not starter then return end
    
    if EHTweaksDB.offeredOptionalDB == starter.version then return end
    
    if IsDatabaseEmpty() then
        ImportStarterDB()
    else
        StaticPopupDialogs["EHTWEAKS_STARTER_DB"] = {
            text = "EHTweaks Starter Database Update Available:\n" .. (starter.version or "Unknown") .. "\n" .. (starter.changelog or "") .. "\n\nDo you want to merge this database with your existing Echoes?",
            button1 = "Merge",
            button2 = "Ignore",
            OnAccept = function()
                ImportStarterDB()
            end,
            OnCancel = function()
                EHTweaksDB.offeredOptionalDB = starter.version
            end,
            timeout = 0, whileDead = true, hideOnEscape = true
        }
        StaticPopup_Show("EHTWEAKS_STARTER_DB")
    end
end

-- =========================================================
-- SECTION 6: PLAYER RUN FRAME EXTENSIONS
-- =========================================================

local isRunFrameHooked = false

local function SetupRunFrameSaver()
    if isRunFrameHooked then return end
    
    local frame = _G["ProjectEbonholdPlayerRunFrame"]
    if frame then
        if EHTweaksDB and EHTweaksDB.runFramePos then
            local p = EHTweaksDB.runFramePos
            frame:ClearAllPoints()
            if p[1] and p[3] then
                frame:SetPoint(p[1], UIParent, p[3], p[4], p[5])
            end
        end
        
        if not frame:IsMovable() then
             frame:SetMovable(true)
             frame:RegisterForDrag("LeftButton")
             frame:SetScript("OnDragStart", frame.StartMoving)
             frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
        end
        
        frame:HookScript("OnDragStop", function(self)
             self:StopMovingOrSizing()
             
             local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()
             if EHTweaksDB then
                 EHTweaksDB.runFramePos = { point, "UIParent", relativePoint, xOfs, yOfs }
             end
        end)
        
        isRunFrameHooked = true
    end
end

local ehObjectiveFrame = nil

local function UpdateEHObjectiveDisplay(objective)
    if not ehObjectiveFrame then return end
    
    if not objective or not EHTweaksDB.enableTracker then
        ehObjectiveFrame:Hide()
        return
    end

    if objective.bonusSpellId and objective.bonusSpellId > 0 then
        local _, _, icon = GetSpellInfo(objective.bonusSpellId)
        ehObjectiveFrame.rewardIcon:SetTexture(icon)
        ehObjectiveFrame.rewardIcon:Show()
    else
        ehObjectiveFrame.rewardIcon:Hide()
    end

    if objective.malusSpellId and objective.malusSpellId > 0 then
        local _, _, icon = GetSpellInfo(objective.malusSpellId)
        ehObjectiveFrame.curseIcon:SetTexture(icon)
        ehObjectiveFrame.curseIcon:Show()
    else
        ehObjectiveFrame.curseIcon:Hide()
    end
    
    ehObjectiveFrame.objectiveData = objective
    ehObjectiveFrame:Show()
end

local function AddEHTLabel()
    local parent = _G.ProjectEbonholdPlayerRunFrame
    if not parent or parent.ehtLabel then return end
    
    
    local container = CreateFrame("Frame", nil, parent)
    container:SetFrameLevel(parent:GetFrameLevel() + 10)
    container:SetSize(50, 30)
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 24, -10)
    
    
    local label = container:CreateFontString(nil, "OVERLAY", "SystemFont_Outline_Small")
    label:SetPoint("LEFT", container, "LEFT", 0, 0)
    label:SetText("EHT")
    label:SetTextColor(1, 1, 1)
    label:SetAlpha(0.14)
    
    parent.ehtLabel = label
    parent.ehtLabelContainer = container
end

local function InitEHObjectiveTracker()
    local parent = _G.ProjectEbonholdPlayerRunFrame
    if not parent or ehObjectiveFrame then return end
    
    local f = CreateFrame("Frame", "EHTweaks_ObjectiveFrame", parent)
    f:SetSize(50, 24)
    
    if parent.hearthIcon then
        f:SetPoint("RIGHT", parent.hearthIcon, "LEFT", -5, 0)
    else
        f:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -50, -10)
    end
    
    local reward = f:CreateTexture(nil, "ARTWORK")
    reward:SetSize(22, 22)
    reward:SetPoint("RIGHT", 0, 0)
    f.rewardIcon = reward
    
    local rBorder = f:CreateTexture(nil, "OVERLAY")
    rBorder:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\roundborder")
    rBorder:SetVertexColor(0.3, 1, 0.3)
    rBorder:SetSize(24, 24)
    rBorder:SetPoint("CENTER", reward, "CENTER", 0, 0)
    f.rBorder = rBorder
    
    local curse = f:CreateTexture(nil, "ARTWORK")
    curse:SetSize(22, 22)
    curse:SetPoint("RIGHT", reward, "LEFT", -4, 0)
    f.curseIcon = curse
    
    local cBorder = f:CreateTexture(nil, "OVERLAY")
    cBorder:SetTexture("Interface\\AddOns\\ProjectEbonhold\\assets\\roundborder")
    cBorder:SetVertexColor(1, 0.3, 0.3)
    cBorder:SetSize(24, 24)
    cBorder:SetPoint("CENTER", curse, "CENTER", 0, 0)
    f.cBorder = cBorder
    
    local btn = CreateFrame("Button", nil, f)
    btn:SetAllPoints(f)
    btn:SetScript("OnEnter", function(self)
        local obj = f.objectiveData
        if not obj then return end
        
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(obj.title or "Active Objective", 1, 0.82, 0)
        
        if obj.objectiveText and obj.objectiveText ~= "" then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(obj.objectiveText, 0.9, 0.9, 0.9, true)
        end
        
        if obj.bonusSpellId then
            local name = GetSpellInfo(obj.bonusSpellId)
            local desc = GetSpellDescription_Local(obj.bonusSpellId)
            
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff44ff44Reward:|r " .. (name or "Unknown"), 1, 1, 1)
            
            if desc and desc ~= "" then
                GameTooltip:AddLine(desc, 1, 0.82, 0, true)
            end
        end
        
        if obj.malusSpellId then
            local name = GetSpellInfo(obj.malusSpellId)
            local desc = GetSpellDescription_Local(obj.malusSpellId)
            
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cffff4444Curse:|r " .. (name or "Unknown"), 1, 1, 1)
            
            if desc and desc ~= "" then
                GameTooltip:AddLine(desc, 1, 0.82, 0, true)
            end
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    ehObjectiveFrame = f
    
    if ProjectEbonhold.ObjectivesUI and ProjectEbonhold.ObjectivesUI.UpdateTracker then
        hooksecurefunc(ProjectEbonhold.ObjectivesUI, "UpdateTracker", function(objective)
            UpdateEHObjectiveDisplay(objective)
        end)
    end
end

-- =========================================================
-- SECTION 7: MINIMAP BUTTON
-- =========================================================

local function UpdateMinimapButtonPosition(angle)
    if not minimapButton then return end
    
    local x, y
    local q = math.rad(angle or 200)
    local radius = 80
    
    x = math.cos(q) * radius
    y = math.sin(q) * radius
    
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function CreateMinimapButton()
    if minimapButton then return minimapButton end
    
    minimapButton = CreateFrame("Button", "EHTweaks_MinimapButton", Minimap)
    minimapButton:SetFrameStrata("MEDIUM")
    minimapButton:SetFrameLevel(8)
    minimapButton:SetWidth(31)
    minimapButton:SetHeight(31)
    minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    
    local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
    icon:SetWidth(20)
    icon:SetHeight(20)
    icon:SetPoint("CENTER", minimapButton, "CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\ability_evoker_innatemagic5")
    minimapButton.icon = icon
    
    local overlay = minimapButton:CreateTexture(nil, "OVERLAY")
    overlay:SetWidth(53)
    overlay:SetHeight(53)
    overlay:SetPoint("TOPLEFT", minimapButton, "TOPLEFT", 0, 0)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    minimapButton.overlay = overlay
    
    minimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("|cffe5cc80Ebonhold Compendium|r", 1, 1, 1)
        GameTooltip:AddLine("Left-click to open", 0.7, 0.7, 1)
        GameTooltip:AddLine("Drag to move", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    
    minimapButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    minimapButton:RegisterForClicks("LeftButtonUp")
    minimapButton:SetScript("OnClick", function(self, btn)
        if btn == "LeftButton" then
            -- Open Browser (requires Browser.lua to be loaded)
            if _G.EHTweaks_BrowserFrame then
                if _G.EHTweaks_BrowserFrame:IsShown() then
                    _G.EHTweaks_BrowserFrame:Hide()
                else
                    _G.EHTweaks_BrowserFrame:Show()
                end
            else
                -- Trigger the slash command to create the frame if it doesn't exist
                if SlashCmdList["EHTBROWSER"] then
                    SlashCmdList["EHTBROWSER"]("")
                else
                    print("|cffff0000EHTweaks:|r Browser module not loaded.")
                end
            end
        end
    end)
    
    minimapButton:RegisterForDrag("LeftButton")
    minimapButton:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            
            local angle = math.deg(math.atan2(py - my, px - mx))
            if angle < 0 then
                angle = angle + 360
            end
            
            UpdateMinimapButtonPosition(angle)
            
            if EHTweaksDB then
                EHTweaksDB.minimapButtonAngle = angle
            end
        end)
    end)
    
    minimapButton:SetScript("OnDragStop", function(self)
        self:UnlockHighlight()
        self:SetScript("OnUpdate", nil)
    end)
    
    local savedAngle = EHTweaksDB and EHTweaksDB.minimapButtonAngle or 200
    UpdateMinimapButtonPosition(savedAngle)
    
    minimapButton:Show()
    
    return minimapButton
end

function EHTweaks_ShowMinimapButton()
    if not minimapButton then
        CreateMinimapButton()
    else
        minimapButton:Show()
    end
    
    if EHTweaksDB then
        EHTweaksDB.minimapButtonHidden = false
    end
end

function EHTweaks_HideMinimapButton()
    if minimapButton then
        minimapButton:Hide()
    end
    
    if EHTweaksDB then
        EHTweaksDB.minimapButtonHidden = true
    end
end

-- =========================================================
-- SECTION 8: LOCKED ECHO CHECKER ON DEATH
-- =========================================================

local warningFrame = nil

local function CreateWarningFrame()
    if warningFrame then return warningFrame end

    local f = CreateFrame("Frame", "EHTweaks_WarningFrame", UIParent)
    f:SetSize(460, 170)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 300)
    f:SetFrameStrata("HIGH")
    f:Hide()
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = {left = 0, right = 0, top = 0, bottom = 0},
    })
    f:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    f:SetBackdropBorderColor(0, 0, 0, 1)

    local titleBg = f:CreateTexture(nil, "ARTWORK")
    titleBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    titleBg:SetVertexColor(0.2, 0.2, 0.2, 1)
    titleBg:SetHeight(24)
    titleBg:SetPoint("TOPLEFT", 1, -1)
    titleBg:SetPoint("TOPRIGHT", -1, -1)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetSize(24, 24)
    close:SetScript("OnClick", function() f:Hide() end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -6)
    title:SetText("Locked Echo Warning")
    f.title = title

    local message = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    message:SetPoint("TOP", titleBg, "BOTTOM", 0, -15)
    message:SetWidth(440)
    message:SetJustifyH("CENTER")
    f.message = message

    warningFrame = f
    return f
end

local function CheckLockedEchoes()
    if not EHTweaksDB or not EHTweaksDB.enableLockedEchoWarning then return end
    if not ProjectEbonhold or not ProjectEbonhold.PerkService then return end

    local lockedPerks = ProjectEbonhold.PerkService.GetLockedPerks()
    local grantedPerks = ProjectEbonhold.PerkService.GetGrantedPerks()

    -- Calculate Locked Echoes
    local lockedCount = 0
    local echoNames = {}
    if lockedPerks and type(lockedPerks) == "table" then
        for _, val in pairs(lockedPerks) do
            lockedCount = lockedCount + 1
            
            local name = "Unknown Echo"
            if type(val) == "number" then
                local spellName = GetSpellInfo(val)
                if spellName then
                    name = spellName
                else
                    name = "ID: " .. val
                end
            elseif type(val) == "string" then
                name = val
            elseif type(val) == "table" then
                if val.name then
                    name = val.name
                elseif val.spellId then
                     local spellName = GetSpellInfo(val.spellId)
                     if spellName then name = spellName else name = "SpellID: " .. val.spellId end
                elseif val.id then
                     local spellName = GetSpellInfo(val.id)
                     if spellName then name = spellName else name = "ID: " .. val.id end
                else
                     name = "Unknown Echo (Data Error)" 
                end
            end
            
            table.insert(echoNames, name)
        end
    end
    local hasLocked = lockedCount > 0

    -- Calculate Granted Echoes (Active)
    local activeCount = 0
    if grantedPerks and type(grantedPerks) == "table" then
         for _, _ in pairs(grantedPerks) do
             activeCount = activeCount + 1
         end
    end
    local hasAnyEcho = activeCount > 0

    local frame = CreateWarningFrame()

    if hasLocked then
        -- Has locked echo
        local namesList = table.concat(echoNames, ", ")

        frame.message:SetText("|cff00FF00Locked Echo Detected|r\n\n|cffFFFFFFYou will keep: |cff00FF00" .. namesList .. "|r\n\nVerify this is the echo you want to keep.|r")
        frame:Show()
        EHTweaks_Log("Death Check: Found locked echo(s): " .. namesList)
        
    elseif hasAnyEcho then
        -- Has echoes but NONE are locked (Risk of losing them)
        frame.message:SetText("|cffFFFF00You don't have a Locked Echo!|r\n\n|cffFFFFFFAssign a Permanent Echo before respawning\nor you will lose all your echoes.|r")
        frame:Show()
        EHTweaks_Log("Death Check: No locked echo found (but has active echoes)")
        
    else
        -- Has NO echoes at all (Do nothing)
        EHTweaks_Log("Death Check: No echoes active")
    end
end

local function HideWarningFrame()
    if warningFrame then
        warningFrame:Hide()
    end
end

-- =========================================================
-- SECTION: DRAFT ECHO RECORDING & FAVORITES
-- =========================================================

-- 1. RECORDING
local function RecordDraftEchoes(choices)
    if not choices or not EHTweaksDB then return end
    if not EHTweaksDB.seenEchoes then EHTweaksDB.seenEchoes = {} end
    
    for _, choice in ipairs(choices) do
        local spellId = choice.spellId
        local quality = choice.quality
        
        if spellId and spellId > 0 then
            if not EHTweaksDB.seenEchoes[spellId] then
                 local name, _, icon = GetSpellInfo(spellId)
                 if name then
                     EHTweaksDB.seenEchoes[spellId] = {
                         name = name,
                         icon = icon,
                         quality = quality
                     }
                 end
            end
        end
    end
end

-- 2. LOOKUP UTILS
local function GetFavoritedEchoNames()
    local names = {}
    if not EHTweaksDB or not EHTweaksDB.favorites then return names end

    for spellId, isFav in pairs(EHTweaksDB.favorites) do
        if isFav then
            local name = GetSpellInfo(spellId)
            if name then names[name] = true end
        end
    end
    return names
end

local function GetActivePerkCards()
    local mainFrame = _G["ProjectEbonholdPerkFrame"]
    -- Strict check: Parent must be visible
    if not mainFrame or not mainFrame:IsShown() then return {} end

    local cards = {}
    local children = { mainFrame:GetChildren() }

    for _, child in ipairs(children) do
        -- Strict check: Child must be visible
        if child:IsShown() and child.icon and child.selectButton and child.nameText then
            table.insert(cards, child)
        end
    end
    return cards
end


-- Helper to clean color codes
local function StripColor(text)
    if not text then return nil end
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

-- New Helper: Sets up the click logic ONCE per card
local function SetupCardInteraction(card)
    if card.ehtInteractionSetup then return end
    
    card:EnableMouse(true)
    card:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and IsShiftKeyDown() then
            -- 1. Get Live Data
            local rawName = self.nameText and self.nameText:GetText()
            local cName = StripColor(rawName)
            if not cName then return end
            
            -- 2. Check Live State (Is it CURRENTLY favored?)
            local isCurrentlyFav = false
            
            -- Check logic: If ANY ID with this name is in DB, it's favored
            if EHTweaksDB.favorites then
                for k, v in pairs(EHTweaksDB.favorites) do
                    if v then
                        local n = GetSpellInfo(k)
                        if n == cName then
                            isCurrentlyFav = true
                            break -- Found one, so it IS favored
                        end
                    end
                end
            end
            
            -- 3. Perform Toggle
            if not EHTweaksDB.favorites then EHTweaksDB.favorites = {} end
            
            if isCurrentlyFav then
                -- REMOVE: Clear ALL entries matching this name (Clean cleanup)
                for k, v in pairs(EHTweaksDB.favorites) do
                    local n = GetSpellInfo(k)
                    if n == cName then EHTweaksDB.favorites[k] = nil end
                end
                print("|cffFFFF00EHTweaks|r: Removed '" .. cName .. "' from Favorites.")
            else
                -- ADD: Find the specific ID for this card to save
                local spellId = nil
                
                -- Strategy A: Match from choices (Best for Draft)
                local choices = ProjectEbonhold.PerkService and ProjectEbonhold.PerkService.GetCurrentChoice()
                if choices then
                     for _, choice in ipairs(choices) do
                         local sName = GetSpellInfo(choice.spellId)
                         if sName == cName then
                             spellId = choice.spellId
                             break
                         end
                     end
                end
                
                -- Strategy B: Fallback to DB History
                if not spellId and EHTweaksDB.seenEchoes then
                    for id, info in pairs(EHTweaksDB.seenEchoes) do
                        if info.name == cName then spellId = id break end
                    end
                end
                
                if spellId then
                    -- PRIMARY ADD
                    EHTweaksDB.favorites[spellId] = true
                    print("|cff00FF00EHTweaks|r: Added '" .. cName .. "' to Favorites!")
                    
                    -- SYNC FIX: Also add ALL other IDs with the same Name found in DB
                    -- This ensures Browser sees it as favorite even if it tracks a different ID (quality)
                    if EHTweaksDB.seenEchoes then
                        for id, info in pairs(EHTweaksDB.seenEchoes) do
                            if info.name == cName then
                                EHTweaksDB.favorites[id] = true
                            end
                        end
                    end
                else
                    print("|cffff0000EHTweaks|r: Could not resolve ID for '" .. cName .. "'")
                end
            end
            
            -- 4. Trigger Refresh
            -- This will call MarkFavouredEchoes again to update visuals
            EHTweaks_RefreshFavouredMarkers()
            
            -- Refresh Browser
            if EHTweaks and EHTweaks.RefreshBrowser then EHTweaks.RefreshBrowser() 
            elseif EHTweaks_RefreshBrowser then EHTweaks_RefreshBrowser() end
        end
    end)
    
    -- Tooltip Hook (Visual feedback on hover)
    card:HookScript("OnEnter", function(self)
        if IsShiftKeyDown() then
            GameTooltip:AddLine(" ")
            local cName = StripColor(self.nameText and self.nameText:GetText())
            
            -- Live Check for Tooltip
            local isF = false
            if cName and EHTweaksDB.favorites then
                for k, v in pairs(EHTweaksDB.favorites) do
                    if v and GetSpellInfo(k) == cName then isF = true break end
                end
            end
            
            if isF then
                GameTooltip:AddLine("|cffFF0000Shift+Right-Click to Unfavorite|r")
            else
                GameTooltip:AddLine("|cff00FF00Shift+Right-Click to Favorite|r")
            end
            GameTooltip:Show()
        end
    end)
    
    -- Safety: manage mouse enablement
    card:HookScript("OnHide", function(self) self:EnableMouse(false) end)
    card:HookScript("OnShow", function(self) self:EnableMouse(true) end)

    card.ehtInteractionSetup = true
end


-- Main Function: Refreshes Visuals (Called by EHTweaks_RefreshFavouredMarkers)
local function MarkFavouredEchoes()
    local cards = GetActivePerkCards()
    if #cards == 0 then return end

    -- 1. Build Lookup Table for Visuals (Optimization)
    -- Map Name -> True if favored
    local favNames = {}
    if EHTweaksDB.favorites then
        for spellId, isFav in pairs(EHTweaksDB.favorites) do
            if isFav then
                local name = GetSpellInfo(spellId)
                if name then favNames[name] = true end
            end
        end
    end

    for i, card in ipairs(cards) do
        -- Step A: Ensure Click Logic is Setup (Once per card lifetime)
        SetupCardInteraction(card)

        -- Step B: Update Visuals based on Name
        local rawName = card.nameText and card.nameText:GetText()
        local cardName = StripColor(rawName)
        local isFav = cardName and favNames[cardName]

        if EHTweaksDB.showDraftFavorites and isFav then
            if not card.ehtFavMarker then
                local parent = card.iconFrame or card
                local marker = CreateFrame("Frame", nil, parent)
                marker:SetSize(100, 24)
                marker:SetFrameStrata("DIALOG") 
                marker:SetFrameLevel(parent:GetFrameLevel() + 50)
                marker:SetPoint("BOTTOM", parent, "TOP", 0, 6)

                local glow = marker:CreateTexture(nil, "BACKGROUND")
                glow:SetTexture("Interface\\GLUES\\Models\\UI_Draenei\\GenericGlow64")
                glow:SetPoint("CENTER", marker, "CENTER", 0, 0)
                glow:SetSize(160, 50)
                glow:SetVertexColor(1.0, 0.9, 0.4)
                glow:SetBlendMode("ADD")
                glow:SetAlpha(0.6)

                local ag = glow:CreateAnimationGroup()
                local a1 = ag:CreateAnimation("Alpha")
                a1:SetChange(-0.3)
                a1:SetDuration(2.0)
                a1:SetOrder(1)
                local a2 = ag:CreateAnimation("Alpha")
                a2:SetChange(0.0)
                a2:SetDuration(2.0)
                a2:SetOrder(2)
                local a3 = ag:CreateAnimation("Alpha")
                a3:SetChange(0.3)
                a3:SetDuration(2.0)
                a3:SetOrder(3)
                local a4 = ag:CreateAnimation("Alpha")
                a4:SetChange(0.0)
                a4:SetDuration(2.0)
                a4:SetOrder(4)
                ag:SetLooping("REPEAT")
                marker.anim = ag
                
                local text = marker:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                text:SetPoint("CENTER", 0, 0)
                text:SetText("FAVOURED")
                text:SetTextColor(0, 1, 0)
                text:SetShadowColor(0, 0, 0, 1)
                text:SetShadowOffset(1, -1)
                marker.text = text

                card.ehtFavMarker = marker
            end
            
            card.ehtFavMarker:Show()
            if card.ehtFavMarker.anim then card.ehtFavMarker.anim:Play() end
        else
            if card.ehtFavMarker then
                card.ehtFavMarker:Hide()
                if card.ehtFavMarker.anim then card.ehtFavMarker.anim:Stop() end
            end
        end
    end
end



-- 4. GLOBAL REFRESH (Called by Browser)
function EHTweaks_RefreshFavouredMarkers()
    -- 1. Handle Original UI (ProjectEbonholdPerkFrame)
    if _G.ProjectEbonholdPerkFrame and _G.ProjectEbonholdPerkFrame:IsShown() then
        if EHTweaksDB.showDraftFavorites then
            MarkFavouredEchoes() -- Your existing function for old UI
        end
    end
    
    -- 2. Handle Modern Draft UI (MD.Show)
    -- We need to check if MD is loaded and visible
    if MD and MD.IsVisible and MD.IsVisible() then
        -- Refresh the Modern UI visuals directly
        -- We can just call the Refresh function we built into ModernDraft logic
        -- asking it to re-evaluate the button text/stars without a full redraw if possible,
        -- or just trigger a refresh.
        if MD.Refresh then
             MD.Refresh() 
        end
    end
end


-- 5. VISIBILITY BUTTON HOOKS (For Refresh)
local function HookPerkVisibilityButtons()
    local chooseButton = _G.PerkChooseButton
    local hideButton = _G.PerkHideButton
    
    if chooseButton and not chooseButton.ehtHooked then
        chooseButton:HookScript("OnClick", function()
            C_Timer.After(0.1, function()
                EHTweaks_RefreshFavouredMarkers()
            end)
        end)
        chooseButton.ehtHooked = true
    end
    
    if hideButton and not hideButton.ehtHooked then
        hideButton:HookScript("OnClick", function()
            C_Timer.After(0.1, function()
                EHTweaks_RefreshFavouredMarkers()
            end)
        end)
        hideButton.ehtHooked = true
    end
end

-- =========================================================
-- SECTION: EVENTS & INITIALIZATION
-- =========================================================

-- Ensure eventFrame exists
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_DEAD")
eventFrame:RegisterEvent("PLAYER_ALIVE")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        InitializeDB()
        
        if EHTweaksDB and not EHTweaksDB.minimapButtonHidden then
            EHTweaks_ShowMinimapButton()
        end
        
        C_Timer.After(2, CheckStarterDatabase)
	  
	
	  	
        
        -- HOOKS
        if ProjectEbonhold and ProjectEbonhold.PlayerRunUI and ProjectEbonhold.PlayerRunUI.UpdateGrantedPerks then
            hooksecurefunc(ProjectEbonhold.PlayerRunUI, "UpdateGrantedPerks", function()
                RecordOwnedEchoes()
                if EHTweaksDB.enableFilters then
                    if not echoFilterBox then CreateEchoFilterFrame() end
                    if currentEchoSearchText and currentEchoSearchText ~= "" then
                        ApplyEchoFilter(currentEchoSearchText)
                    else
                        ApplyEchoFilter("") 
                    end
                end
                if EHTweaksDB.enableChatLinks then HookEchoButtons() end
		    
		     if not _G.ProjectEbonholdEmpowermentFrame then return end
        if not _G.ProjectEbonholdEmpowermentFrame.EHT_MoverInstalled then
            EHT_SetupEmpowermentFrameMoveAndSave()
        end
            end)
        end
	  
	  -- Hook Intensity for Warning System
        if ProjectEbonhold and ProjectEbonhold.PlayerRunUI and ProjectEbonhold.PlayerRunUI.UpdateIntensity then
            hooksecurefunc(ProjectEbonhold.PlayerRunUI, "UpdateIntensity", function(data)
                if data and data.intensity then
                    CheckIntensityThresholds(data.intensity)
                end
            end)
        end

        if ProjectEbonhold and ProjectEbonhold.PlayerRunUI and ProjectEbonhold.PlayerRunUI.UpdateData then
             hooksecurefunc(ProjectEbonhold.PlayerRunUI, "UpdateData", function()
                 SetupRunFrameSaver()
                 AddEHTLabel()
             end)
             SetupRunFrameSaver()
        end
        
        if ProjectEbonhold and ProjectEbonhold.PerkUI and ProjectEbonhold.PerkUI.Show then
            hooksecurefunc(ProjectEbonhold.PerkUI, "Show", function(choices)
                RecordDraftEchoes(choices)
                SetupPerkButtons()
                        
            end)
        end
	  
	  if CTimer and CTimer.After and ProjectEbonhold then
	    CTimer.After(2, function()		
		EHTweaks_InitIntensityWarningTweaks(0)
	    end)
	  end
	  
	  
	  local function EHT_HookEmpowermentToggle()
	    if _G.ToggleEmpowermentPanel and not _G.ToggleEmpowermentPanel_EHTHooked then
		  local original = _G.ToggleEmpowermentPanel
		  _G.ToggleEmpowermentPanel = function()
			original()
			
			-- Refresh close button after toggle
			CTimer.After(0.1, function()
			    local frame = _G.ProjectEbonholdEmpowermentFrame
			    if frame and frame.ehtCloseBtn then
				  if frame:IsShown() then
					frame.ehtCloseBtn:ClearAllPoints()
					frame.ehtCloseBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
					frame.ehtCloseBtn:Show()
					if frame.ehtCloseBtn.Raise then frame.ehtCloseBtn:Raise() end
				  else
					frame.ehtCloseBtn:Hide()
				  end
			    end
			end)
		  end
		  _G.ToggleEmpowermentPanel_EHTHooked = true
	    end
	end

	-- Call this after successful init:
	if CTimer and CTimer.After and ProjectEbonhold then
	    CTimer.After(2, function()
		  EHTweaks_InitEmpowermentFrameTweaks(0)
		  EHTweaks_InitIntensityWarningTweaks(0)
		  
		  -- Hook the toggle function after frames exist
		  CTimer.After(1, EHT_HookEmpowermentToggle)
	    end)
	end

    elseif event == "PLAYER_ENTERING_WORLD" then
        if _G.skillTreeFrame and not _G.skillTreeFrame.EHTweaksHooked then
            _G.skillTreeFrame:HookScript("OnShow", function()
                if EHTweaksDB.enableFilters and not filterBox then CreateSkillFilterFrame() end
                if EHTweaksDB.enableChatLinks then HookSkillTreeButtons() end
                CreateExtraTreeButtons()
            end)
            _G.skillTreeFrame.EHTweaksHooked = true
        else
            C_Timer.After(1, function()
                if _G.skillTreeFrame and not _G.skillTreeFrame.EHTweaksHooked then
                    _G.skillTreeFrame:HookScript("OnShow", function()
                        if EHTweaksDB.enableFilters and not filterBox then CreateSkillFilterFrame() end
                        if EHTweaksDB.enableChatLinks then HookSkillTreeButtons() end
                        CreateExtraTreeButtons()
                    end)
                    _G.skillTreeFrame.EHTweaksHooked = true
                end
            end)
        end
        
        if PerkChooseButton or PerkHideButton then
            SetupPerkButtons()
        end
        
        -- Hook visibility buttons
        HookPerkVisibilityButtons()
        
        C_Timer.After(2, function() 
             InitEHObjectiveTracker()
             AddEHTLabel()
             if ProjectEbonhold.ObjectivesService then
                 UpdateEHObjectiveDisplay(ProjectEbonhold.ObjectivesService.GetActiveObjective())
             end
        end)
	  
	
	    -- --- SILENT SKILL TREE DATA REQUEST (PRELOAD CHARACTER ID) ---        
        C_Timer.After(3, function()
            -- 1. Check if we already have the ID (Success condition)
            local id = EHTweaks_GetActiveLoadoutInfo()
            if id and id ~= 0 then return end 

            -- 2. Attempt: Use the addon's exposed function (Clean Method)
            if ProjectEbonhold and ProjectEbonhold.RequestLoadoutFromServer then
                 ProjectEbonhold.RequestLoadoutFromServer()
                  --print("EHTweaks: RequestLoadoutFromServer called.") 
            end

            -- 3. Validation & Fallback: Wait 1 more second to see if it worked
            C_Timer.After(1, function()
                local checkId = EHTweaks_GetActiveLoadoutInfo()		    
                if checkId and checkId ~= 0 then return end -- Success!
			    -- FALLBACK: The "Blink" Method (Open & Close UI)
			    -- This forces the addon to run its own OnShow logic which requests data
			    if _G.skillTreeFrame and not _G.skillTreeFrame:IsShown() then
				  
				  _G.skillTreeFrame:Show()
				  _G.skillTreeFrame:Hide()
			    elseif _G.EHTweaks_ToggleSkillTree then
				  -- Use our own toggle if frame ref is missing. Probably will not work if above fails because we call same code.			  
				  _G.EHTweaksToggleSkillTree() -- Open
				  _G.EHTweaksToggleSkillTree() -- Close
			    end
            end)
        end)


	    

    elseif event == "PLAYER_DEAD" then
        C_Timer.After(1, CheckLockedEchoes)

    elseif event == "PLAYER_ALIVE" then
        C_Timer.After(0.5, function()
            HideWarningFrame()
            EHTweaks_Log("Player is alive, hiding warning")
        end)
        
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, payload, channel, sender = ...
        if prefix == "AAM0x9" then
            -- 3.3.5 FIX: Use \t instead of \\t to correctly match the literal tab character
            local opcodeStr, body = payload:match("^(%d+)\t(.*)$")
            local opcode = tonumber(opcodeStr)
            
            if opcode == 3 and body then
                local globalPart, loadoutsPart = body:match("([^_]+)_?(.*)")
                if globalPart then
                    local selID = globalPart:match("^(%d+),")
                    if selID then activeLoadoutId = tonumber(selID) end
                end
                if loadoutsPart then
                    for loadoutString in string.gmatch(loadoutsPart, "([^;]+)") do
                        local parts = {}
                        for part in string.gmatch(loadoutString, "([^,]+)") do table.insert(parts, part) end
                        if #parts >= 2 then
                            local id = tonumber(parts[1])
                            local name = parts[2]
                            if id and name then knownLoadouts[name] = id end
                        end
                    end
                end
            end
        end
    end
end)

SLASH_EHTWARNING1 = '/ehtwarning'
SlashCmdList['EHTWARNING'] = function()
    local f = CreateWarningFrame()
    f.message:SetText('|cff00FF00Locked Echo Detected|r\n\n|cffFFFFFFYou will keep: |cff00FF00Test Echo, Another Echo|r\n\nVerify this is the echo you want to keep.|r')
    f:Show()
end

-- =============================================================
-- EHTweaks: Player Run Frame Minimizer (Left Restore Button + Lines)
-- =============================================================

local miniBarFrame = nil
local MAX_INTENSITY = 475
--local INTENSITY_THRESHOLDS = { 75, 200, 275, 375, 475 }

local miniScanner = CreateFrame("GameTooltip", "EHTweaksMiniScanner", nil, "GameTooltipTemplate")
miniScanner:SetOwner(WorldFrame, "ANCHOR_NONE")

local function GetMiniSpellDesc(spellId)
    if not spellId then return nil end
    miniScanner:ClearLines()
    miniScanner:SetHyperlink("spell:" .. spellId)
    local lines = miniScanner:NumLines()
    if lines <= 1 then return nil end
    
    local desc = ""
    for i = 2, lines do
        local lineObj = _G["EHTweaksMiniScannerTextLeft" .. i]
        if lineObj then
            local text = lineObj:GetText()
            if text then
                if not string.find(text, "Rank %d") then
                    if desc ~= "" then desc = desc .. "\n" end
                    desc = desc .. text
                end
            end
        end
    end
    return desc
end

local function SaveMiniPosition(f)
    local point, _, relativePoint, x, y = f:GetPoint()
    EHTweaksDB.miniBarPos = { point, relativePoint, x, y }
end

local function RestoreMiniPosition(f)
    if EHTweaksDB.miniBarPos then
        local p = EHTweaksDB.miniBarPos
        f:ClearAllPoints()
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local function CreateMiniRunBar(mainFrame)
    if miniBarFrame then return miniBarFrame end

    local f = CreateFrame("Frame", "EHTweaks_MiniRunBar", UIParent)
    f:SetSize(280, 26) 
    RestoreMiniPosition(f)
    
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveMiniPosition(self)
    end)

    -- [1] Maximize Button (Moved to LEFT)
    local maxBtn = CreateFrame("Button", nil, f)
    maxBtn:SetSize(16, 16)
    maxBtn:SetPoint("LEFT", f, "LEFT", -1, 5) -- Inside Left
    maxBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Up")
    maxBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Down")
    maxBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    
    maxBtn:SetScript("OnClick", function()
        if mainFrame then
            EHTweaksDB.runFrameCollapsed = false
            f:Hide()
            mainFrame:Show()
            if ehObjectiveFrame then ehObjectiveFrame:Show() end
        end
    end)
    f.maxBtn = maxBtn -- Store for reference

    -- [2] Icons (To the right of Maximize Button)
    local reward = CreateFrame("Button", nil, f)
    reward:SetSize(20, 20)
    reward:SetPoint("LEFT", maxBtn, "RIGHT", 6, -5) 
    reward:EnableMouse(true)
    reward:Hide()
    f.rewardIcon = reward
    
    local curse = CreateFrame("Button", nil, f)
    curse:SetSize(20, 20)
    curse:SetPoint("LEFT", reward, "RIGHT", 2, 0) 
    curse:EnableMouse(true)
    curse:Hide()
    f.curseIcon = curse

    -- [3] Progress Bar (Remaining space to Right)
    local bar = CreateFrame("StatusBar", nil, f)
    bar:SetPoint("TOP", 0, -2)
    bar:SetPoint("BOTTOM", 0, 2)
    
    -- Anchor Left: 16(btn)+5(pad)+20(icon)+2+20(icon)+2 ~= 65px safe start
    bar:SetPoint("LEFT", f, "LEFT", 70, 0) 
    bar:SetPoint("RIGHT", f, "RIGHT", -5, 0) -- Stretch to right edge
    
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.6, 0.0, 0.8, 0.8)
    bar:SetMinMaxValues(0, MAX_INTENSITY)
    bar:SetValue(0)
    f.bar = bar

    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0, 0, 0, 0.2)

    f:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    -- "E" button (Toggle My Echoes)
	if not f.ehtEchoBtn then
	    local eb = CreateFrame("Button", nil, f)
	    eb:SetSize(10, 10)

	    
	    eb:SetPoint("TOPLEFT", maxBtn, "BOTTOMLEFT", 3, 2)

	    eb:SetFrameLevel(maxBtn:GetFrameLevel() + 5)
	    eb:EnableMouse(true)
	    eb:RegisterForClicks("LeftButtonUp")

	    -- Small background so it reads as a button
	    local bg = eb:CreateTexture(nil, "BACKGROUND")
	    bg:SetAllPoints()
	    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
	    bg:SetVertexColor(0, 0, 0, 0.35)
	    eb.bg = bg

	    -- Text "E" (don’t rely on Button:SetText unless using a template)
	    local txt = eb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	    txt:SetPoint("CENTER", 0, 0)
	    txt:SetText("E")
	    txt:SetTextColor(1, 1, 1)
	    eb.txt = txt

	    eb:SetScript("OnEnter", function(self)
		  self.bg:SetVertexColor(0.2, 0.2, 0.2, 0.75)
		  self.txt:SetTextColor(0.7, 1.0, 0.7)

		  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		  GameTooltip:SetText("Toggle My Echoes", 1, 1, 1)
		  GameTooltip:AddLine("Keybind: EHTweaks → Toggle My Echoes", 0.7, 0.7, 0.7, true)
		  GameTooltip:Show()
	    end)

	    eb:SetScript("OnLeave", function(self)
		  self.bg:SetVertexColor(0, 0, 0, 0.35)
		  self.txt:SetTextColor(1, 1, 1)
		  GameTooltip:Hide()
	    end)

	    eb:SetScript("OnClick", function()
		  if EHTweaks_ToggleEchoes then
			EHTweaks_ToggleEchoes()
		  end
	    end)

	    f.ehtEchoBtn = eb
	end

    
    -- Red Vertical Lines
    local function CreateMarkers()
        local w = bar:GetWidth()
        if w <= 0 then C_Timer.After(0.5, CreateMarkers) return end
        
        if f.markers then return end
        f.markers = {}
        
        for _, thresh in ipairs(INTENSITY_THRESHOLDS) do
            local ratio = thresh / MAX_INTENSITY
            local xPos = w * ratio
            
            local line = bar:CreateTexture(nil, "OVERLAY")
            line:SetSize(1, 6) 
            line:SetPoint("CENTER", bar, "LEFT", xPos, -8) -- Bottom edge area
            line:SetTexture("Interface\\Buttons\\WHITE8X8")
            line:SetVertexColor(1, 0, 0, 1) 
            
            table.insert(f.markers, line)
        end
    end
    
    bar:SetScript("OnSizeChanged", function() 
        if f.markers then 
             local w = bar:GetWidth()
             for i, line in ipairs(f.markers) do
                 local thresh = INTENSITY_THRESHOLDS[i]
                 if thresh then
                     local ratio = thresh / MAX_INTENSITY
                     line:SetPoint("CENTER", bar, "LEFT", w * ratio, -8)
                 end
             end
        else
            CreateMarkers()
        end
    end)

    -- Text (High)
    f.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.text:SetPoint("CENTER", 0, 4) 
    f.text:SetText("Loading...")
    f.text:SetShadowOffset(1, -1)
    
    -- Tooltip logic
    local function ShowTooltip(self)
        if self.spellId then
             GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
             local name = GetSpellInfo(self.spellId)
             local desc = GetMiniSpellDesc(self.spellId) 
             if name then
                 local color = self.isReward and "|cff44ff44" or "|cffff4444"
                 local label = self.isReward and "Reward" or "Curse"
                 GameTooltip:AddLine(color .. label .. "|r: " .. name, 1, 1, 1)
                 if desc and desc ~= "" then GameTooltip:AddLine(desc, 1, 0.82, 0, true) end
                 GameTooltip:Show()
             end
        end
    end
    local function HideTooltip(self) GameTooltip:Hide() end
    reward:SetScript("OnEnter", ShowTooltip) reward:SetScript("OnLeave", HideTooltip)
    curse:SetScript("OnEnter", ShowTooltip) curse:SetScript("OnLeave", HideTooltip)

    f:Hide()
    miniBarFrame = f
    return f
end

local function UpdateMiniBarText()
    if not miniBarFrame then return end
    
    local int = lastIntData.intensity or 0
    local ash = lastRunData.soulPoints or 0
    local mult = (lastRunData.soulPointsMultiplier or 0) * 100
    
    local text = string.format(
        "Int: |cffffffff%d|r  |  Ash: |cff29C0E6%s|r  |  |cff00ff00+%.0f%%|r",
        int,
        FormatLargeNumber and FormatLargeNumber(ash) or ash, 
        mult
    )
    miniBarFrame.text:SetText(text)
    
    if miniBarFrame.bar then
        miniBarFrame.bar:SetValue(int)
        if int >= 475 then miniBarFrame.bar:SetStatusBarColor(1, 0, 0)
        else miniBarFrame.bar:SetStatusBarColor(0.6, 0.0, 0.8) end
    end
end

local function SyncMiniTracker()
    if not miniBarFrame then return end
    
    if ehObjectiveFrame and ehObjectiveFrame.objectiveData then
         local obj = ehObjectiveFrame.objectiveData
         local hasReward = (obj.bonusSpellId and obj.bonusSpellId > 0)
         local hasCurse = (obj.malusSpellId and obj.malusSpellId > 0)

         if hasReward then
             local _, _, icon = GetSpellInfo(obj.bonusSpellId)
             miniBarFrame.rewardIcon:SetNormalTexture(icon) 
             miniBarFrame.rewardIcon.spellId = obj.bonusSpellId 
             miniBarFrame.rewardIcon.isReward = true 
             miniBarFrame.rewardIcon:Show()
         else
             miniBarFrame.rewardIcon:Hide()
         end
         
         if hasCurse then
             local _, _, icon = GetSpellInfo(obj.malusSpellId)
             miniBarFrame.curseIcon:SetNormalTexture(icon)
             miniBarFrame.curseIcon.spellId = obj.malusSpellId 
             miniBarFrame.curseIcon.isReward = false 
             miniBarFrame.curseIcon:Show()
             
             if not hasReward then
                 miniBarFrame.curseIcon:SetPoint("LEFT", miniBarFrame.maxBtn, "RIGHT", 4, 0)
             else
                 miniBarFrame.curseIcon:SetPoint("LEFT", miniBarFrame.rewardIcon, "RIGHT", 2, 0)
             end
         else
             miniBarFrame.curseIcon:Hide()
         end
    else
         miniBarFrame.rewardIcon:Hide()
         miniBarFrame.curseIcon:Hide()
    end
end

local function InitMinimizer(numTries)
    if numTries > 30 then return end 

    local mainFrame = _G.ProjectEbonholdPlayerRunFrame
    if not mainFrame then
        C_Timer.After(1, function() InitMinimizer(numTries + 1) end)
        return
    end

    local mini = CreateMiniRunBar(mainFrame)

    if not mainFrame.ehtMinimizeBtn then
        local minBtn = CreateFrame("Button", nil, mainFrame)
        minBtn:SetSize(20, 20)
        
       
        minBtn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 15, 0) 
        
        minBtn:SetFrameLevel(mainFrame:GetFrameLevel() + 20)
        
        minBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-SmallerButton-Up")
        minBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-SmallerButton-Down")
        minBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
        
        minBtn:SetScript("OnClick", function()
            EHTweaksDB.runFrameCollapsed = true
            RestoreMiniPosition(mini)
            
            mainFrame:Hide()
            if ehObjectiveFrame then ehObjectiveFrame:Hide() end
            
            mini:Show()
            UpdateMiniBarText()
            SyncMiniTracker()
        end)
        
        mainFrame.ehtMinimizeBtn = minBtn
    end

    if ProjectEbonhold and ProjectEbonhold.PlayerRunUI then
        hooksecurefunc(ProjectEbonhold.PlayerRunUI, "UpdateData", function(data)
            if data then for k,v in pairs(data) do lastRunData[k] = v end UpdateMiniBarText() end
        end)
        hooksecurefunc(ProjectEbonhold.PlayerRunUI, "UpdateIntensity", function(data)
            if data then for k,v in pairs(data) do lastIntData[k] = v end UpdateMiniBarText() end
        end)
    end
    
    C_Timer.NewTicker(1, SyncMiniTracker)

    if EHTweaksDB.runFrameCollapsed then
        mainFrame:Hide()
        if ehObjectiveFrame then ehObjectiveFrame:Hide() end
        mini:Show()
    end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function() 
    InitMinimizer(0) 
end)

