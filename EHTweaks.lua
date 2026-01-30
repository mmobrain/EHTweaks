-- Author: Skulltrail
-- EHTweaks: Project Ebonhold Extensions
-- Features: Skill Tree Filter, Echoes Filter, Visual Highlights, Focus Zoom, Chat Links, Movable Echo Button, Echoes DB, Starter DB, Objective Tracker, PlayerRunFrame Saver, Minimap Button, Locked Echo Warning

local addonName, addon = ...

-- GLOBAL DEBUG TOGGLE
EHTweaks_DEBUG = false 

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
    enableLockedEchoWarning = true,
    seenEchoes = {},
    perkButtonPos = nil,
    runFramePos = nil,
    offeredOptionalDB = nil,
    minimapButtonAngle = 200, -- Default position in degrees
    minimapButtonHidden = false
}

-- --- State ---
local searchTimer = 0
local currentSearchText = ""
local currentEchoSearchText = ""
local filterBox = nil
local echoFilterBox = nil
local matchedNodes = {} 
local minimapButton = nil

-- --- Database Init ---
local function InitializeDB()
    if not EHTweaksDB then EHTweaksDB = {} end
    for k, v in pairs(DEFAULTS) do
        if EHTweaksDB[k] == nil then EHTweaksDB[k] = v end
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
-- SECTION 1: SKILL TREE FILTER
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
        if currentSearchText ~= "" then
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

local function RecordDraftEchoes(choices)
    if not choices then return end
    EHTweaks_Log("--- Recording Draft Echoes ---")
    for _, choice in ipairs(choices) do
        RecordEchoInfo(choice.spellId, choice.quality)
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

local function HookEchoButtons()
    local frame = _G.ProjectEbonholdEmpowermentFrame
    if not frame or not frame.perkIcons then return end
    
    local list = GetPerkListSorted()
    
    for i, iconBtn in ipairs(frame.perkIcons) do
        if list[i] then
            iconBtn.ehSpellId = list[i].spellId
            
            iconBtn:EnableMouse(true)
            
            if not iconBtn.hasLinkWrapper then
                iconBtn:SetScript("OnClick", function(self)
                    EHTweaks_HandleLinkClick(self.ehSpellId)
                end)
                iconBtn.hasLinkWrapper = true
            end
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
                SlashCmdList["EHTBROWSER"]("")
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

local function ShowMinimapButton()
    if not minimapButton then
        CreateMinimapButton()
    else
        minimapButton:Show()
    end
    
    if EHTweaksDB then
        EHTweaksDB.minimapButtonHidden = false
    end
end

local function HideMinimapButton()
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
    f:SetSize(600, 120)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    f:SetFrameStrata("HIGH")
    f:Hide()

    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = {left = 8, right = 8, top = 8, bottom = 8}
    })
    f:SetBackdropColor(0, 0, 0, 0.9)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cffFF4444Locked Echo Warning|r")
    f.title = title

    local message = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    message:SetPoint("TOP", title, "BOTTOM", 0, -10)
    message:SetWidth(550)
    message:SetJustifyH("CENTER")
    f.message = message

    warningFrame = f
    return f
end

local function CheckLockedEchoes()
    if not EHTweaksDB or not EHTweaksDB.enableLockedEchoWarning then return end
    if not ProjectEbonhold or not ProjectEbonhold.PerkService then return end

    local lockedPerks = ProjectEbonhold.PerkService.GetLockedPerks()

    local frame = CreateWarningFrame()

    if not lockedPerks or (type(lockedPerks) == "table" and next(lockedPerks) == nil) then
        -- No locked echo
        frame.message:SetText("|cffFFFF00You don't have a Locked Echo!|r\n\n|cffFFFFFFAssign a Permanent Echo before respawning\nor you will lose all your echoes.|r")
        frame:Show()
        EHTweaks_Log("Death Check: No locked echo found")
    else
        -- Has locked echo
        local echoCount = 0
        local echoNames = {}

        if type(lockedPerks) == "table" then
            for spellName, _ in pairs(lockedPerks) do
                echoCount = echoCount + 1
                table.insert(echoNames, spellName)
            end
        end

        if echoCount > 0 then
            local namesList = table.concat(echoNames, ", ")
            frame.message:SetText("|cff00FF00Locked Echo Detected|r\n\n|cffFFFFFFYou will keep: |cff00FF00" .. namesList .. "|r\n\nVerify this is the echo you want to keep.|r")
            frame:Show()
            EHTweaks_Log("Death Check: Found locked echo(s): " .. namesList)
        end
    end
end

local function HideWarningFrame()
    if warningFrame then
        warningFrame:Hide()
    end
end

-- =========================================================
-- INITIALIZATION
-- =========================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_DEAD")
eventFrame:RegisterEvent("PLAYER_ALIVE")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        InitializeDB()
        
        C_Timer.After(2, CheckStarterDatabase)
        
        if _G.skillTreeFrame then
            _G.skillTreeFrame:HookScript("OnShow", function()
                if EHTweaksDB.enableFilters and not filterBox then CreateSkillFilterFrame() end
                if EHTweaksDB.enableChatLinks then HookSkillTreeButtons() end
            end)
        else
            C_Timer.After(1, function()
                if _G.skillTreeFrame then
                    _G.skillTreeFrame:HookScript("OnShow", function()
                        if EHTweaksDB.enableFilters and not filterBox then CreateSkillFilterFrame() end
                        if EHTweaksDB.enableChatLinks then HookSkillTreeButtons() end
                    end)
                end
            end)
        end
        
        if ProjectEbonhold and ProjectEbonhold.PlayerRunUI and ProjectEbonhold.PlayerRunUI.UpdateGrantedPerks then
            hooksecurefunc(ProjectEbonhold.PlayerRunUI, "UpdateGrantedPerks", function()
                RecordOwnedEchoes()
                
                if EHTweaksDB.enableFilters then
                    if not echoFilterBox then CreateEchoFilterFrame() end
                    
                    if currentEchoSearchText ~= "" then
                        ApplyEchoFilter(currentEchoSearchText)
                    else
                        ApplyEchoFilter("") 
                    end
                end
                
                if EHTweaksDB.enableChatLinks then HookEchoButtons() end
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
        
        if PerkChooseButton or PerkHideButton then
            SetupPerkButtons()
        end
        
        C_Timer.After(2, function() 
             InitEHObjectiveTracker()
             AddEHTLabel()
             if ProjectEbonhold.ObjectivesService then
                 UpdateEHObjectiveDisplay(ProjectEbonhold.ObjectivesService.GetActiveObjective())
             end
        end)
        
       
        C_Timer.After(1, function()
            if EHTweaksDB and not EHTweaksDB.minimapButtonHidden then
                ShowMinimapButton()
            end
        end)

        self:UnregisterEvent("PLAYER_ENTERING_WORLD")

    elseif event == "PLAYER_DEAD" then
        -- Check for locked echoes when player dies
        C_Timer.After(1, CheckLockedEchoes)

    elseif event == "PLAYER_ALIVE" then
        -- Hide warning when player gets back alive
        C_Timer.After(0.5, function()
            HideWarningFrame()
            EHTweaks_Log("Player is alive, hiding warning")
        end)
    end
end)
