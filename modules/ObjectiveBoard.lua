-- =========================================================
-- EHTweaks: Remote Objectives Board Module (Viewer)
-- =========================================================
local EHTweaks_RemoteBoardFrame = nil

-- =========================================================
-- MINIBAR "B" BUTTON INJECTION
-- =========================================================
local function InjectBoardButtonToMiniBar()
    local bar = _G["EHTweaks_MiniRunBar"]
    if not bar or bar.boardBtn then return end

    local eBtn = bar.ehtEchoBtn

    local b = CreateFrame("Button", nil, bar)
    b:SetSize(10, 10)
    b:SetFrameLevel((eBtn and eBtn:GetFrameLevel() or bar:GetFrameLevel()) + 5)
    b:EnableMouse(true)
    b:RegisterForClicks("LeftButtonUp")

    if eBtn then
        b:SetPoint("TOPLEFT", eBtn, "TOPRIGHT", 3, 0)
    else
        b:SetPoint("TOPLEFT", bar.maxBtn, "BOTTOMLEFT", 16, 2)
    end
   

    local label = b:CreateFontString(nil, "OVERLAY", "SystemFont_Outline_Small")
    label:SetPoint("CENTER", -3, 0)
    label:SetText("B")
    label:SetTextColor(1, 0.82, 0, 1)
    b.label = label

    b:SetScript("OnClick", function()
        EHTweaks_ToggleRemoteObjectivesBoard()
    end)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Objectives Board", 0.3, 1.0, 0.3)
        GameTooltip:AddLine("View available objectives.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    bar.boardBtn = b
end

-- =========================================================
-- REMOTE BOARD REFRESH
-- =========================================================
local function RefreshRemoteBoard()
    if not EHTweaks_RemoteBoardFrame then return end

    local proposals = nil
    local activeObj = nil
    
    if ProjectEbonhold and ProjectEbonhold.ObjectivesService then
        if ProjectEbonhold.ObjectivesService.GetCurrentObjectives then
            proposals = ProjectEbonhold.ObjectivesService.GetCurrentObjectives()
        end
        if ProjectEbonhold.ObjectivesService.GetActiveObjective then
            activeObj = ProjectEbonhold.ObjectivesService.GetActiveObjective()
        end
    end

    if not proposals or #proposals == 0 then
        EHTweaks_RemoteBoardFrame.emptyText:Show()
        for i = 1, 3 do
            EHTweaks_RemoteBoardFrame.rows[i]:Hide()
        end
        return
    end

    EHTweaks_RemoteBoardFrame.emptyText:Hide()

    for i = 1, 3 do
        local row = EHTweaks_RemoteBoardFrame.rows[i]
        local obj = proposals[i]

        if obj then
            -- Golden Outline for Active Objective
            local isActive = activeObj and (activeObj.title == obj.title) and (activeObj.difficulty == obj.difficulty)
            if isActive then
                row:SetBackdropBorderColor(1, 0.82, 0, 1) -- Golden
            else
                row:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8) -- Default dark gray
            end

            -- Title color by difficulty
            if obj.difficulty == 0 then
                row.title:SetTextColor(0.3, 1.0, 0.3)
            elseif obj.difficulty == 1 then
                row.title:SetTextColor(1.0, 0.82, 0.0)
            else
                row.title:SetTextColor(1.0, 0.3, 0.3)
            end

            row.title:SetText(obj.title or "Unknown")
            row.desc:SetText(obj.objectiveText or "")
            row.ashes:SetText("|cffA020F0" .. (obj.soulAshes or 0) .. " Soul Ashes|r")

            -- Buff icon, text (word-wrapped), and full hover tooltip
            if obj.bonusSpellId and obj.bonusSpellId > 0 then
                local name, _, icon = GetSpellInfo(obj.bonusSpellId)
                
                local desc = ""
                if utils and utils.GetSpellDescription then
                    desc = utils.GetSpellDescription(obj.bonusSpellId, 500, 1) or ""
                end
                if desc == "Click for details" then desc = "" end

                row.buffIcon:SetNormalTexture(icon)
                
                local descText = desc ~= "" and (" - |cffcccccc" .. desc .. "|r") or ""
                row.buffText:SetText("|cff44ff44Buff:|r " .. (name or "Unknown") .. descText)
                
                row.buffIcon:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink("spell:" .. obj.bonusSpellId)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cff00FF00Reward|r", 1, 1, 1)
                    GameTooltip:AddLine("Earned upon completing this objective.", 1, 0.82, 0, true)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(obj.title or "Objective", 1, 0.82, 0)
                    if obj.objectiveText and obj.objectiveText ~= "" then
                        GameTooltip:AddLine(obj.objectiveText, 0.9, 0.9, 0.9, true)
                    end
                    GameTooltip:Show()
                end)
                row.buffIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)
                row.buffIcon:Show()
            else
                row.buffIcon:SetNormalTexture(nil)
                row.buffIcon:Hide()
                row.buffText:SetText("")
            end

            -- Curse icon, text (word-wrapped), and full hover tooltip
            if obj.malusSpellId and obj.malusSpellId > 0 then
                local name, _, icon = GetSpellInfo(obj.malusSpellId)
                
                local desc = ""
                if utils and utils.GetSpellDescription then
                    desc = utils.GetSpellDescription(obj.malusSpellId, 500, 1) or ""
                end
                if desc == "Click for details" then desc = "" end

                row.curseIcon:SetNormalTexture(icon)
                
                local descText = desc ~= "" and (" - |cffcccccc" .. desc .. "|r") or ""
                row.curseText:SetText("|cffff4444Curse:|r " .. (name or "Unknown") .. descText)
                
                row.curseIcon:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink("spell:" .. obj.malusSpellId)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cffFF0000Curse|r", 1, 1, 1)
                    GameTooltip:AddLine("Active while pursuing this objective.", 1, 0.3, 0.3, true)
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(obj.title or "Objective", 1, 0.82, 0)
                    if obj.objectiveText and obj.objectiveText ~= "" then
                        GameTooltip:AddLine(obj.objectiveText, 0.9, 0.9, 0.9, true)
                    end
                    GameTooltip:Show()
                end)
                row.curseIcon:SetScript("OnLeave", function() GameTooltip:Hide() end)
                row.curseIcon:Show()
            else
                row.curseIcon:SetNormalTexture(nil)
                row.curseIcon:Hide()
                row.curseText:SetText("")
            end

            row:Show()
        else
            row:Hide()
        end
    end
end

-- =========================================================
-- TOGGLE BOARD
-- =========================================================
-- Helper: scale an existing FontString while keeping the same font file + flags.
local function EHTweaks_ScaleFontString(fs, scale, forceFlags)
    if not fs or not scale then return end
    local fontPath, fontSize, fontFlags = fs:GetFont()
    if not fontPath or not fontSize then return end
    fs:SetFont(fontPath, fontSize * scale, forceFlags or fontFlags)
end

function EHTweaks_ToggleRemoteObjectivesBoard()
    local isNewFrame = false

    if not EHTweaks_RemoteBoardFrame then
        local f = CreateFrame("Frame", "EHTweaks_RemoteBoardFrame", UIParent)
        f:SetSize(440, 520)
        f:SetPoint("CENTER", 0, 50)
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        f:Hide()

        if EHTweaks and EHTweaks.Skin and EHTweaks.Skin.ApplyWindow then
            EHTweaks.Skin.ApplyWindow(f, "Remote Objectives Board")
        else
            f:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                edgeSize = 1,
                insets = {left = 0, right = 0, top = 0, bottom = 0}
            })
            f:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
            f:SetBackdropBorderColor(0, 0, 0, 1)
            local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
            closeBtn:SetPoint("TOPRIGHT", -5, -5)
        end

        local emptyText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        emptyText:SetPoint("CENTER", 0, 0)
        emptyText:SetText("No Objectives available.")
        emptyText:Hide()
        f.emptyText = emptyText

        f.rows = {}

        -- Font scaling settings (tweak these freely)
        local titleScale = 1.30
        local ashesScale = 1.20
        local descScale  = 1.15
        local detailScale = 1.15

        for i = 1, 3 do
            local row = CreateFrame("Frame", nil, f)
            row:SetSize(400, 145)
            row:SetPoint("TOP", 0, -45 - ((i - 1) * 155))

            if EHTweaks and EHTweaks.Skin and EHTweaks.Skin.ApplyInset then
                EHTweaks.Skin.ApplyInset(row)
            else
                row:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8X8",
                    edgeFile = "Interface\\Buttons\\WHITE8X8",
                    edgeSize = 1,
                    insets = {left = 0, right = 0, top = 0, bottom = 0}
                })
                row:SetBackdropColor(0, 0, 0, 0.3)
                row:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
            end

            -- Title
            row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.title:SetPoint("TOPLEFT", 10, -10)
            EHTweaks_ScaleFontString(row.title, titleScale)

            -- Ashes (top-right)
            row.ashes = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.ashes:SetPoint("TOPRIGHT", -12, -10)
            EHTweaks_ScaleFontString(row.ashes, ashesScale)

            -- Objective text (“what to do”)
            row.desc = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            row.desc:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -6)
            row.desc:SetWidth(380)
            row.desc:SetJustifyH("LEFT")
            EHTweaks_ScaleFontString(row.desc, descScale)

            -- Buff
            local buffIcon = CreateFrame("Button", nil, row)
            buffIcon:SetSize(24, 24)
            buffIcon:SetPoint("TOPLEFT", row.desc, "BOTTOMLEFT", 0, -10)
            row.buffIcon = buffIcon

            row.buffText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.buffText:SetPoint("TOPLEFT", buffIcon, "TOPRIGHT", 6, -2)
            row.buffText:SetWidth(350)
            row.buffText:SetJustifyH("LEFT")
            row.buffText:SetJustifyV("TOP")
            row.buffText:SetWordWrap(true)
            EHTweaks_ScaleFontString(row.buffText, detailScale)

            -- Curse (anchored under buffText so it naturally moves down when buff wraps)
            local curseIcon = CreateFrame("Button", nil, row)
            curseIcon:SetSize(24, 24)
            curseIcon:SetPoint("TOPLEFT", row.buffText, "BOTTOMLEFT", -30, -10)
            row.curseIcon = curseIcon

            row.curseText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.curseText:SetPoint("TOPLEFT", curseIcon, "TOPRIGHT", 6, -2)
            row.curseText:SetWidth(350)
            row.curseText:SetJustifyH("LEFT")
            row.curseText:SetJustifyV("TOP")
            row.curseText:SetWordWrap(true)
            EHTweaks_ScaleFontString(row.curseText, detailScale)

            f.rows[i] = row
        end

        EHTweaks_RemoteBoardFrame = f
        isNewFrame = true
    end

    if not isNewFrame and EHTweaks_RemoteBoardFrame:IsShown() then
        EHTweaks_RemoteBoardFrame:Hide()
    else
        RefreshRemoteBoard()
        EHTweaks_RemoteBoardFrame:Show()
    end
end


-- =========================================================
-- INIT: Inject B button into MiniBar after world loads
-- =========================================================
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(1.0, function()
            InjectBoardButtonToMiniBar()
        end)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end)

-- =========================================================
-- SLASH COMMANDS
-- =========================================================
SLASH_EHTWEAKSBOARD1 = "/ehtb"
SlashCmdList["EHTWEAKSBOARD"] = function()
    EHTweaks_ToggleRemoteObjectivesBoard()
end
