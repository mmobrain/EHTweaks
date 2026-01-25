-- Author: Skulltrail
-- EHTweaks: Project Ebonhold Extensions
-- Features: Skill Tree Filter, Echoes Filter, Visual Highlights, Focus Zoom

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

-- --- Visuals Helper (Shared) ---

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
-- SECTION 2: ECHOES (EMPOWERMENT) FILTER
-- =========================================================

-- Reconstructs the sorted list of perks exactly how Project Ebonhold does
-- so we can map visual buttons back to data.
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
            local isMatch = false
            if searchText == "" then
                isMatch = true
            else
                -- 1. Name
                if string.find(string.lower(data.spellName), searchText, 1, true) then
                    isMatch = true
                else
                    -- 2. Description
                    if utils and utils.GetSpellDescription then
                        local desc = utils.GetSpellDescription(data.spellId, 999, 1)
                        if desc and string.find(string.lower(desc), searchText, 1, true) then
                            isMatch = true
                        end
                    end
                end
            end

            -- Reuse the glow/fade logic
            if searchText == "" then
                -- Reset to normal
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

    -- Container
    local f = CreateFrame("Frame", "EHTweaks_EchoFilterFrame", parent)
    f:SetSize(200, 30)
    -- Place at bottom of the frame
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

    -- Clear Button
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

    eb:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    eb:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        -- Direct update for Echoes is fast enough usually, 
        -- but reusing throttling variable style is safer
        if text ~= currentEchoSearchText then
            currentEchoSearchText = text
            ApplyEchoFilter(text)
        end
    end)

    echoFilterBox = eb
end

-- =========================================================
-- INITIALIZATION
-- =========================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        
        -- 1. Setup Skill Tree Filter
        if _G.skillTreeFrame then
            _G.skillTreeFrame:HookScript("OnShow", function()
                if not filterBox then CreateSkillFilterFrame() end
            end)
        else
            C_Timer.After(1, function()
                if _G.skillTreeFrame and not filterBox then
                    _G.skillTreeFrame:HookScript("OnShow", function()
                        if not filterBox then CreateSkillFilterFrame() end
                    end)
                end
            end)
        end
        
        -- 2. Setup Echoes Filter
        -- Hook UpdateGrantedPerks to ensure we inject the UI when it's populated/refreshed
        -- and to re-apply filters if the list changes while filtering.
        if ProjectEbonhold and ProjectEbonhold.PlayerRunUI and ProjectEbonhold.PlayerRunUI.UpdateGrantedPerks then
            hooksecurefunc(ProjectEbonhold.PlayerRunUI, "UpdateGrantedPerks", function()
                if not echoFilterBox then
                    CreateEchoFilterFrame()
                end
                
                -- If there is active text, re-apply it after the UI rebuild
                if currentEchoSearchText ~= "" then
                    ApplyEchoFilter(currentEchoSearchText)
                end
            end)
        end
        
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end)