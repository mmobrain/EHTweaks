-- Author: Skulltrail
-- EHtweaks: Project Ebonhold Extensions
-- Features: Skill Tree Filter, Echoes Filter, Visual Highlights, Focus Zoom, Chat Links

local addonName, addon = ...

-- --- Configuration ---
local FILTER_MATCH_ALPHA = 1.0
local FILTER_NOMATCH_ALPHA = 0.15
local SEARCH_THROTTLE = 0.2

-- --- State ---
local searchTimer = 0
local currentSearchText = ""
local currentEchoSearchText = ""
local filterBox = nil
local echoFilterBox = nil
local matchedNodes = {} 

-- --- Visuals Helper ---

local function CreateGlow(btn)
    if btn.searchGlow then return end

    local glow = btn:CreateTexture(nil, "OVERLAY")
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(0, 1, 0, 1) -- Green glow
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

-- --- Linking Helper ---

local function HandleLinkClick(spellId)
    if IsControlKeyDown() and IsAltKeyDown() then
        if spellId then
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
        return true
    end
    return false
end

-- =========================================================
-- SECTION 1: SKILL TREE
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
                    if utils and utils.GetSpellDescription then
                        local desc = utils.GetSpellDescription(spellId, 999, 1)
                        if desc and string.find(string.lower(desc), text, 1, true) then
                            isMatch = true
                            break
                        end
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

    local f = CreateFrame("Frame", "EHtweaks_FilterFrame", parent)
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

    local eb = CreateFrame("EditBox", "EHtweaks_FilterBox", f, "InputBoxTemplate")
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
-- SECTION 2: ECHOES
-- =========================================================

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
                    if utils and utils.GetSpellDescription then
                        local desc = utils.GetSpellDescription(data.spellId, 999, 1)
                        if desc and string.find(string.lower(desc), searchText, 1, true) then
                            isMatch = true
                        end
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

    local f = CreateFrame("Frame", "EHtweaks_EchoFilterFrame", parent)
    f:SetSize(200, 30)
    f:SetPoint("BOTTOM", parent, "BOTTOM", 0, 15)
    f:SetFrameLevel(parent:GetFrameLevel() + 5)

    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.label:SetPoint("LEFT", f, "LEFT", 0, 0)
    f.label:SetText("Filter:")
    f.label:SetTextColor(1, 0.82, 0)

    local eb = CreateFrame("EditBox", "EHtweaks_EchoFilterBox", f, "InputBoxTemplate")
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
        if HandleLinkClick(spellId) then
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
                        -- For ranked nodes, link max rank to show potential
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
                    HandleLinkClick(self.ehSpellId)
                end)
                iconBtn.hasLinkWrapper = true
            end
        end
    end
end

-- =========================================================
-- INITIALIZATION
-- =========================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        
        -- 1. Setup Skill Tree
        if _G.skillTreeFrame then
            _G.skillTreeFrame:HookScript("OnShow", function()
                if not filterBox then CreateSkillFilterFrame() end
                HookSkillTreeButtons()
            end)
        else
            C_Timer.After(1, function()
                if _G.skillTreeFrame then
                    _G.skillTreeFrame:HookScript("OnShow", function()
                        if not filterBox then CreateSkillFilterFrame() end
                        HookSkillTreeButtons()
                    end)
                end
            end)
        end
        
        -- 2. Setup Echoes
        if ProjectEbonhold and ProjectEbonhold.PlayerRunUI and ProjectEbonhold.PlayerRunUI.UpdateGrantedPerks then
            hooksecurefunc(ProjectEbonhold.PlayerRunUI, "UpdateGrantedPerks", function()
                if not echoFilterBox then CreateEchoFilterFrame() end
                
                if currentEchoSearchText ~= "" then
                    ApplyEchoFilter(currentEchoSearchText)
                else
                    ApplyEchoFilter("") 
                end
                
                HookEchoButtons()
            end)
        end
        
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end)