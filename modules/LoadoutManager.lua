-- Author: Skulltrail
-- EHTweaks: Loadout Manager
-- Features: Newest First sorting loadouts, Auto-Backups, Macro-style Icon Selector

local addonName, addon = ...
local LibDeflate = LibStub:GetLibrary("LibDeflate")

-- Ensure EHTweaks.Skin exists
if not EHTweaks.Skin then EHTweaks.Skin = {} end
local Skin = EHTweaks.Skin

-- Define Fallback Skin functions if they don't exist
if not Skin.ApplyWindow then
    Skin.ApplyWindow = function(f, title)
        f:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8", 
            edgeFile = "Interface\\Buttons\\WHITE8X8",
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
            f.title:SetText(title or "")
        end
        
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
            bgFile = "Interface\\Buttons\\WHITE8X8", 
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, tileSize = 0, edgeSize = 1,
            insets = {left = 0, right = 0, top = 0, bottom = 0},
        })
        f:SetBackdropColor(0, 0, 0, 0.3)
        f:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    end
end

_G.EHTweaks = _G.EHTweaks or addon
EHTweaks.Loadout = EHTweaks.Loadout or {
    managerFrame = nil,
    saveFrame = nil,
    selectedIndex = 0,
    listData = {},
    iconPool = {},
    MAX_BACKUPS = 2,
    EXPORT_HEADER = "!EHTL!",
    showOnlyMyClass = false
}

local LM = EHTweaks.Loadout
local BACKUP_ICON = "Interface\\Icons\\ability_evoker_innatemagic5"

-- --- Localization Warning ---
if GetLocale() ~= "enUS" and GetLocale() ~= "enGB" then
    print("|cffff7f00EHTweaks Warning:|r Current locale is not English. Skill Tree scraping ('3/5' text) may be unreliable.")
end

-- --- Helper: UI Strata Fixer ---
local function EHT_FixStrata(frame)
    if frame then
        frame:SetFrameStrata("TOOLTIP")
        frame:SetToplevel(true)
    end
end

-- --- Helper: Skinning (Compendium Style) ---
local function ApplyCompendiumSkin(f, titleText)
    -- Sleek Backdrop
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = {left = 0, right = 0, top = 0, bottom = 0},
    })
    f:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    f:SetBackdropBorderColor(0, 0, 0, 1)

    -- Title Background Stripe (ARTWORK layer to fix Z-fighting)
    if not f.titleBg then
        local titleBg = f:CreateTexture(nil, "ARTWORK")
        titleBg:SetTexture("Interface\\Buttons\\WHITE8X8")
        titleBg:SetVertexColor(0.2, 0.2, 0.2, 1)
        titleBg:SetHeight(24)
        titleBg:SetPoint("TOPLEFT", 1, -1)
        titleBg:SetPoint("TOPRIGHT", -1, -1)
        f.titleBg = titleBg
    end

    -- Title Text
    if not f.title then
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", 0, -6)
        f.title = title
    end
    f.title:SetText(titleText)
    
    -- Close Button (Generic)
    if not f.closeBtn then
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 0, 0)
        close:SetScript("OnClick", function() f:Hide() end)
        f.closeBtn = close
    end
end

-- --- Helper: Skin Inset Frames (Thin Borders) ---
local function SkinInset(f)
    if not f then return end
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    f:SetBackdropColor(0, 0, 0, 0.3) -- Darker inner background
    f:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8) -- Subtle grey border
end

-- --- Helper: Icon Pool Management ---
local function GetIconButton(parent, index)
    if not LM.iconPool[index] then
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(38, 38)
        
        local tex = b:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        b.tex = tex
        
        local sel = b:CreateTexture(nil, "OVERLAY")
        sel:SetAllPoints()
        sel:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        sel:SetBlendMode("ADD")
        sel:Hide()
        b.sel = sel
        
        b:SetScript("OnClick", function(self)
            LM.saveFrameSelectedIcon = self.iconPath
            for _, other in ipairs(LM.iconPool) do other.sel:Hide() end
            self.sel:Show()
        end)
        
        LM.iconPool[index] = b
    end
    return LM.iconPool[index]
end

-- --- Logic: Data Scraping ---
local function GetTreeInfo()
    local nodes = {}
    local iconsFound = {}
    local iconMap = {} 
    local totalCost = 0
    local hasPoints = false
    
    if TalentDatabase and TalentDatabase[0] then
        for _, node in ipairs(TalentDatabase[0].nodes) do
            local btn = _G["skillTreeNode"..node.id]
            if btn then
                local rank = 0
                local costPerRank = node.soulPointsCosts and node.soulPointsCosts[1] or 0
                
                if btn.isMultipleChoice then
                    if btn.selectedSpell and btn.selectedSpell > 0 then
                        rank = btn.selectedSpell
                        totalCost = totalCost + costPerRank
                    end
                else
                    if btn.rankText then
                        local text = btn.rankText:GetText()
                        if text and text ~= "" then
                            local r = text:match("^(%d+)/")
                            if r then 
                                rank = tonumber(r) 
                                if rank > 0 then totalCost = totalCost + (costPerRank * rank) end
                            end
                        end
                    end
                end
                
                if rank > 0 then
                    nodes[node.id] = rank
                    hasPoints = true
                end

                if node.spells then
                    for _, spellId in ipairs(node.spells) do
                        local _, _, icon = GetSpellInfo(spellId)
                        if icon and not iconMap[icon] then
                            table.insert(iconsFound, icon)
                            iconMap[icon] = true
                        end
                    end
                end
            end
        end
    end
    return nodes, totalCost, hasPoints, iconsFound
end

-- --- Logic: Storage ---
local function GetAllLoadoutsDB()
    if not EHTweaksDB.loadouts then EHTweaksDB.loadouts = {} end
    return EHTweaksDB.loadouts
end

-- Get only current class loadouts (backwards compatible accessor)
local function GetClassLoadoutDB()
    local allDB = GetAllLoadoutsDB()
    local _, class = UnitClass("player")
    if not allDB[class] then allDB[class] = {} end
    return allDB[class]
end

local function GetBackupDB()
    if not EHTweaksDB.backups then EHTweaksDB.backups = {} end
    return EHTweaksDB.backups
end

-- --- UI: Refresh ---
function EHTweaks_RefreshLoadoutList()
    if not LM.managerFrame then return end
    
    local backups = GetBackupDB()
    local playerAsh = (EbonholdPlayerRunData and EbonholdPlayerRunData.soulPoints) or 0
    local _, playerClass = UnitClass("player")
    
    -- NEW: Build list with optional class filtering
    local sortedSaved = {}
    local sortedBackups = {}
    
    if LM.showOnlyMyClass then
        -- OLD BEHAVIOR: Only current class
        local saved = GetClassLoadoutDB()
        for _, v in ipairs(saved) do
            table.insert(sortedSaved, v)
        end
    else
        -- NEW BEHAVIOR: All classes
        local allDB = GetAllLoadoutsDB()
        for class, classLoadouts in pairs(allDB) do
            for _, v in ipairs(classLoadouts) do
                -- Tag with class for display
                v.savedForClass = class
                table.insert(sortedSaved, v)
            end
        end
    end
    
    for _, v in ipairs(backups) do
        table.insert(sortedBackups, v)
    end
    
    table.sort(sortedSaved, function(a, b) return (a.timestamp or 0) > (b.timestamp or 0) end)
    table.sort(sortedBackups, function(a, b) return (a.timestamp or 0) > (b.timestamp or 0) end)
    
    LM.listData = {}
    for _, s in ipairs(sortedSaved) do table.insert(LM.listData, s) end
    for _, b in ipairs(sortedBackups) do table.insert(LM.listData, b) end
    
    local offset = FauxScrollFrame_GetOffset(LM.managerFrame.scroll)
    for i = 1, #LM.managerFrame.rows do
        local row = LM.managerFrame.rows[i]
        local idx = offset + i
        if idx <= #LM.listData then
            local data = LM.listData[idx]
            row.data, row.idx = data, idx
            
            -- Display class tag if showing all classes
            local displayName = data.name
            if not LM.showOnlyMyClass and data.savedForClass then
                local classColor = RAID_CLASS_COLORS[data.savedForClass]
                if classColor then
                    displayName = string.format("|cff%02x%02x%02x[%s]|r %s",
                        classColor.r * 255, classColor.g * 255, classColor.b * 255,
                        data.savedForClass:sub(1,3):upper(), data.name)
                else
                    displayName = "[" .. data.savedForClass .. "] " .. data.name
                end
            end
            
            row.name:SetText(displayName)
            row.icon:SetTexture(data.icon)
            
            if data.isBackup then
                row.name:SetTextColor(0.6, 0.6, 0.6)
                row.cost:SetText("|cff888888Auto-Backup|r")
            else
                row.name:SetTextColor(1, 0.82, 0)
                local color = (playerAsh >= (data.cost or 0)) and "|cff00FF00" or "|cffFF0000"
                row.cost:SetText(color .. (data.cost or 0) .. " Ash|r")
            end
            
            if LM.selectedIndex == idx then
                row.bg:Show()
            else
                row.bg:Hide()
            end
            row:Show()
        else
            row:Hide()
        end
    end
    
    FauxScrollFrame_Update(LM.managerFrame.scroll, #LM.listData, 6, 40)
    
    if LM.selectedIndex > 0 and LM.listData[LM.selectedIndex] then
        local d = LM.listData[LM.selectedIndex]
        LM.managerFrame.detailName:SetText(d.name)
        LM.managerFrame.detailDesc:SetText(d.desc)
        LM.managerFrame.btnExport:Enable() 
	  if InCombatLockdown() then
            LM.managerFrame.btnApply:Disable()
        else
            LM.managerFrame.btnApply:Enable()
        end
	  LM.managerFrame.btnDelete:Enable()
    else
        LM.managerFrame.detailName:SetText("Select a Loadout") LM.managerFrame.detailDesc:SetText("")
        LM.managerFrame.btnExport:Disable() 
	  LM.managerFrame.btnApply:Disable() 
	  LM.managerFrame.btnDelete:Disable()
    end
end

-- --- UI: Save Dialog ---
local function ShowSaveDialog()
    local nodes, cost, hasPoints, icons = GetTreeInfo()
    if not hasPoints then print("|cffff0000EHTweaks:|r Cannot save an empty tree.") return end

    if not LM.saveFrame then
        local f = CreateFrame("Frame", "EHTweaks_SaveDialog", UIParent)
        f:SetSize(400, 480)
        f:SetPoint("CENTER")
        f:SetFrameStrata("TOOLTIP")
        f:SetToplevel(true)
        f:EnableMouse(true) f:SetMovable(true)
        
        -- Apply Compendium Skin & Add Close Button
        ApplyCompendiumSkin(f, "Save New Build")
        
        f:SetScript("OnMouseDown", function(self) self:StartMoving() end)
        f:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

        local nLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nLbl:SetPoint("TOPLEFT", 30, -50)
        nLbl:SetText("Build Name:")
        
        local nEdit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        nEdit:SetSize(330, 25)
        nEdit:SetPoint("TOPLEFT", 35, -65)
        LM.saveFrameNameBox = nEdit

        local dLbl = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dLbl:SetPoint("TOPLEFT", 30, -100)
        dLbl:SetText("Description:")

        local dBg = CreateFrame("Frame", nil, f)
        dBg:SetSize(340, 80)
        dBg:SetPoint("TOPLEFT", 30, -120)
        SkinInset(dBg) -- Apply new inset skin
        
        local dEdit = CreateFrame("EditBox", nil, dBg)
        dEdit:SetMultiLine(true)
        dEdit:SetMaxLetters(250)
        dEdit:SetFontObject("GameFontHighlight")
        dEdit:SetAllPoints(dBg)
        dEdit:SetTextInsets(5,5,5,5)
        dEdit:SetAutoFocus(false)
        dEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        LM.saveFrameDescBox = dEdit

        local iScroll = CreateFrame("ScrollFrame", "EHT_SaveIconScroll", f, "UIPanelScrollFrameTemplate")
        iScroll:SetSize(310, 160)
        iScroll:SetPoint("TOPLEFT", 30, -230)
        SkinInset(iScroll) -- Apply new inset skin
        
        local iGrid = CreateFrame("Frame", nil, iScroll)
        iGrid:SetSize(310, 1)
        iScroll:SetScrollChild(iGrid)
        LM.saveFrameIconGrid = iGrid

        local btnSave = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btnSave:SetSize(120, 30)
        btnSave:SetPoint("BOTTOMLEFT", 40, 25)
        btnSave:SetText("Save Build")
        btnSave:SetScript("OnClick", function()
            local name = LM.saveFrameNameBox:GetText()
            if name == "" then name = "Untitled Build" end
            
            -- Prepare comparison vars
            local searchName = string.lower(name)
            local allDB = GetAllLoadoutsDB()
            local _, playerClass = UnitClass("player")
            
            local conflictClass = nil
            local overwriteIndex = nil
            
            -- Check Global Uniqueness (Iterate ALL classes)
            for className, classLoadouts in pairs(allDB) do
                for i, loadout in ipairs(classLoadouts) do
                    if string.lower(loadout.name) == searchName then
                        if className == playerClass then
                            -- Same name on MY class = Update/Overwrite
                            overwriteIndex = i
                        else
                            -- Same name on OTHER class = Conflict
                            conflictClass = className
                        end
                        break
                    end
                end
                if conflictClass then break end
            end

            -- Block save if name exists on another class
            if conflictClass then
                print("|cffff0000EHTweaks:|r Save failed. The name '"..name.."' is already used by your ["..conflictClass.."] loadouts.")
                return
            end

            -- Prepare new entry
            local newEntry = { 
                name = name, 
                desc = LM.saveFrameDescBox:GetText(), 
                icon = LM.saveFrameSelectedIcon, 
                nodes = LM.saveFrameNodes, 
                cost = LM.saveFrameCost, 
                timestamp = time() 
            }
            
            local currentClassDB = GetClassLoadoutDB()

            if overwriteIndex then
                -- Overwrite existing entry for current player
                currentClassDB[overwriteIndex] = newEntry
                print("|cff00ff00EHTweaks:|r Loadout '"..name.."' updated.")
            else
                -- Insert new entry
                table.insert(currentClassDB, newEntry)
                print("|cff00ff00EHTweaks:|r Loadout '"..name.."' saved.")
            end
            
            LM.saveFrame:Hide()
            EHTweaks_RefreshLoadoutList()
        end)

        local btnCancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        btnCancel:SetSize(120, 30)
        btnCancel:SetPoint("BOTTOMRIGHT", -40, 25)
        btnCancel:SetText("Cancel")
        btnCancel:SetScript("OnClick", function() LM.saveFrame:Hide() end)

        LM.saveFrame = f
    end

    LM.saveFrameNameBox:SetText("")
    LM.saveFrameDescBox:SetText("")
    LM.saveFrameNodes, LM.saveFrameCost = nodes, cost
    LM.saveFrameSelectedIcon = icons[1]

    for _, b in ipairs(LM.iconPool) do b:Hide() end
    local cols = 7
    for i, iconPath in ipairs(icons) do
        local b = GetIconButton(LM.saveFrameIconGrid, i)
        b.iconPath = iconPath
        b.tex:SetTexture(iconPath)
        b:SetPoint("TOPLEFT", ((i-1)%cols)*42, -math.floor((i-1)/cols)*42)
        if i == 1 then b.sel:Show() else b.sel:Hide() end
        b:Show()
    end
    LM.saveFrameIconGrid:SetHeight(math.ceil(#icons/cols)*42)
    LM.saveFrame:Show()
end

-- --- Logic: Backup ---
function EHTweaks_CreateAutoBackup()
    local nodes, cost, hasPoints, icons = GetTreeInfo()
    if not hasPoints then return end 
    
    local db = GetBackupDB()
    table.insert(db, 1, {
        name = "Backup " .. date("%H:%M:%S"),
        desc = "Auto-backup before apply/reset",
        icon = BACKUP_ICON,
        cost = cost,
        nodes = nodes,
        timestamp = time(),
        isBackup = true
    })
    
    while #db > LM.MAX_BACKUPS do table.remove(db) end
    print("|cff888888EHTweaks: Auto-backup created.|r")
end

-- --- Logic: Override selected loadout with current build ---
local function OverrideSelectedLoadout()
    local nodes, cost, hasPoints, icons = GetTreeInfo()
    if not hasPoints then
        print("|cffff0000EHTweaks:|r Cannot save an empty tree.")
        return
    end

    if not LM.listData or not LM.selectedIndex or LM.selectedIndex == 0 then
        return
    end

    local entry = LM.listData[LM.selectedIndex]
    if not entry or entry.isBackup then
        return
    end

    -- Update the existing table in-place
    entry.nodes     = nodes
    entry.cost      = cost
    
    -- Safe check for icon (icons is a table from GetTreeInfo, entry.icon must be a string)
    if icons and icons[1] then
        entry.icon = icons[1]
    end
    
    entry.timestamp = time()

    local name = entry.name or "Unnamed"
    print("|cff00ff00EHTweaks:|r Loadout '" .. name .. "' overridden with current build.")

    -- Use the correct global function name
    EHTweaks_RefreshLoadoutList()
end

-- --- Logic: Apply ---
function EHTweaks_ApplyLoadout(entry)
    if InCombatLockdown() then
        print("|cffff0000EHTweaks:|r Cannot apply loadouts while in combat!")
        return
    end
    if not entry or not entry.nodes then return end
    EHTweaks_CreateAutoBackup()
    
    local nodeData = {}
    for id, rank in pairs(entry.nodes) do table.insert(nodeData, id .. ":" .. rank) end
    local nodesString = table.concat(nodeData, ",")
    
    local activeID, activeName
    if EHTweaks_GetActiveLoadoutInfo then activeID, activeName = EHTweaks_GetActiveLoadoutInfo() end
    activeID = activeID or 0
    activeName = activeName or "Default"
    
    local startNodeId = nil
    if TalentDatabase and TalentDatabase[0] then
        for _, node in ipairs(TalentDatabase[0].nodes) do if node.isStart then startNodeId = node.id break end end
    end
    
    if ProjectEbonhold and ProjectEbonhold.SendLoadoutToServer then
        if startNodeId then
            ProjectEbonhold.SendLoadoutToServer({ id = activeID, name = activeName, nodeRanks = { [startNodeId] = 1 } })
        end
        C_Timer.After(0.6, function()
            ProjectEbonhold.sendToServer(ProjectEbonhold.CS.REQUEST_LOADOUT_UPDATE, activeID .. "|" .. activeName .. "|" .. nodesString)
            C_Timer.After(0.5, function()
                if ProjectEbonhold.RequestLoadoutFromServer then ProjectEbonhold.RequestLoadoutFromServer() end
                print("|cff00ff00EHTweaks:|r Loadout '"..entry.name.."' applied.")
            end)
        end)
    end
end

-- --- Logic: Export/Import ---
local function ExportString(entry)
    if not LibDeflate then return "" end
    local nodeStr = ""
    for id, rank in pairs(entry.nodes) do nodeStr = nodeStr .. id .. ":" .. rank .. "," end
    local data = string.format("%s|%s|%s|%d|%s", entry.name, entry.desc, entry.icon, entry.cost, nodeStr)
    local compressed = LibDeflate:CompressDeflate(data)
    return LM.EXPORT_HEADER .. LibDeflate:EncodeForPrint(compressed)
end

local function ImportString(str)
    if not LibDeflate then return end
    if string.sub(str, 1, string.len(LM.EXPORT_HEADER)) == LM.EXPORT_HEADER then
        str = string.sub(str, string.len(LM.EXPORT_HEADER) + 1)
    end
    local compressed = LibDeflate:DecodeForPrint(str)
    if not compressed then return end
    local data = LibDeflate:DecompressDeflate(compressed)
    if not data then return end
    
    local name, desc, icon, costStr, nodesStr = data:match("^(.-)|(.-)|(.-)|(%d+)|(.*)$")
    if name and nodesStr then
        local nodes = {}
        for pair in string.gmatch(nodesStr, "([^,]+)") do
            local id, rank = pair:match("(%d+):(%d+)")
            if id and rank then nodes[tonumber(id)] = tonumber(rank) end
        end
        local db = GetClassLoadoutDB()
        table.insert(db, { name = name, desc = desc, icon = icon, cost = tonumber(costStr), nodes = nodes, timestamp = time() })
        return true
    end
end

-- --- UI: Main Manager ---
local function CreateLoadoutManagerFrame()
    local f = CreateFrame("Frame", "EHTweaks_LoadoutManager", UIParent)
    f:SetSize(600, 400)
    f:SetPoint("CENTER")
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetToplevel(true)
    f:EnableMouse(true) f:SetMovable(true)
    
    Skin.ApplyWindow(f, "Loadout Manager")
    
    f:SetScript("OnMouseDown", function(self) self:StartMoving() end)
    f:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

    local listFrame = CreateFrame("Frame", nil, f)
    listFrame:SetSize(280, 270)
    listFrame:SetPoint("TOPLEFT", 20, -50)
    Skin.ApplyInset(listFrame)
    
    f.scroll = CreateFrame("ScrollFrame", "EHT_LoadoutScroll", listFrame, "FauxScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT", 0, 0)
    f.scroll:SetPoint("BOTTOMRIGHT", -30, 0)
    f.scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 40, EHTweaks_RefreshLoadoutList)
    end)
    
    f.rows = {}
    for i=1, 6 do
        local row = CreateFrame("Button", nil, listFrame)
        row:SetSize(250, 40)
        row:SetPoint("TOPLEFT", 0, -(i-1)*40)
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints() bg:SetTexture("Interface\\Buttons\\WHITE8X8") bg:SetVertexColor(0.3, 0.3, 0.3, 0.5)
        row.bg = bg
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(32, 32) icon:SetPoint("LEFT", 4, 0)
        row.icon = icon
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 5, 0)
        row.cost = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.cost:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 5, 0)
        row:SetScript("OnClick", function(self) LM.selectedIndex = self.idx EHTweaks_RefreshLoadoutList() end)
        f.rows[i] = row
    end
    
    local detailFrame = CreateFrame("Frame", nil, f)
    detailFrame:SetSize(260, 270)
    detailFrame:SetPoint("TOPRIGHT", -20, -50)
    Skin.ApplyInset(detailFrame)
    
    f.detailName = detailFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.detailName:SetPoint("TOPLEFT", 10, -10)
    f.detailDesc = detailFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.detailDesc:SetPoint("TOPLEFT", f.detailName, "BOTTOMLEFT", 0, -10)
    f.detailDesc:SetWidth(240) f.detailDesc:SetJustifyH("LEFT")
    
    local spacing, bottomY = 10, 22
    
    local btnSaveNew = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnSaveNew:SetSize(100, 25)
    btnSaveNew:SetPoint("BOTTOMLEFT", 20, bottomY)
    btnSaveNew:SetText("Save Current")
    
    -- Quick Save Logic
    btnSaveNew:SetScript("OnClick", function()
        -- SHIFT CLICK: Quick Save
        if IsShiftKeyDown() then
            local nodes, cost, hasPoints, icons = GetTreeInfo()
            if not hasPoints then 
                 print("|cffff0000EHTweaks:|r Cannot save empty tree.") 
                 return 
            end
            
            local name = "QuickSave " .. date("%H:%M:%S")
            local db = GetClassLoadoutDB()
            
            table.insert(db, 1, { -- Insert at top
                name = name, 
                desc = "Quick Shift+Click Save", 
                icon = icons[1] or "Interface\\Icons\\INV_Misc_QuestionMark", 
                nodes = nodes, 
                cost = cost, 
                timestamp = time() 
            })
            
            print("|cff00ff00EHTweaks:|r Quick Save created: " .. name)
            EHTweaks_RefreshLoadoutList()
            return
        end

        -- Normal Click Logic
        local selectedIndex = LM.selectedIndex or 0
        local entry = (LM.listData and selectedIndex > 0) and LM.listData[selectedIndex] or nil
    
        if entry and not entry.isBackup then
            local name = entry.name or "Selected Loadout"
            local dialog = StaticPopup_Show("EHTWEAKS_SAVELOADOUTMODE", name)
            if dialog and EHT_FixStrata then
                EHT_FixStrata(dialog)
            end
        else
            ShowSaveDialog()
        end
    end)
    
    -- Tooltip
    btnSaveNew:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Save Loadout")
        GameTooltip:AddLine("Click to open Save Dialog.", 1, 1, 1)
        GameTooltip:AddLine("Shift+Click to Quick Save.", 0, 1, 0)
        GameTooltip:Show()
    end)
    btnSaveNew:SetScript("OnLeave", function() GameTooltip:Hide() end)
    
    local btnImport = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnImport:SetSize(80, 25)
    btnImport:SetPoint("LEFT", btnSaveNew, "RIGHT", spacing, 0)
    btnImport:SetText("Import")
    btnImport:SetScript("OnClick", function() LM.selectedIndex=0 EHT_FixStrata(StaticPopup_Show("EHT_IMPORT")) end)
    
    f.btnExport = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.btnExport:SetSize(80, 25)
    f.btnExport:SetPoint("LEFT", btnImport, "RIGHT", spacing, 0)
    f.btnExport:SetText("Export")
    f.btnExport:SetScript("OnClick", function()
        local str = LM.listData[LM.selectedIndex] and ExportString(LM.listData[LM.selectedIndex]) or ""
        local dialog = StaticPopup_Show("EHT_EXPORT")
        if dialog then
            dialog.editBox:SetText(str)
            dialog.editBox:HighlightText()
            EHT_FixStrata(dialog)
        end
    end)
    
    f.btnApply = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.btnApply:SetSize(110, 25)
    f.btnApply:SetPoint("LEFT", f.btnExport, "RIGHT", spacing, 0)
    f.btnApply:SetText("Apply Loadout")
    f.btnApply:SetScript("OnClick", function() if LM.selectedIndex > 0 then EHTweaks_ApplyLoadout(LM.listData[LM.selectedIndex]) f:Hide() end end)
    
    --Combat State Handling
    f:RegisterEvent("PLAYER_REGEN_DISABLED") -- Combat Start
    f:RegisterEvent("PLAYER_REGEN_ENABLED")  -- Combat End
    f:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_REGEN_DISABLED" then
            if self.btnApply then self.btnApply:Disable() end
            if self.btnImport then self.btnImport:Disable() end 
            -- Note: Export/Save usually OK in combat, but Apply is strictly NO.
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- Re-enable based on selection state
            if LM.selectedIndex > 0 then
                if self.btnApply then self.btnApply:Enable() end
            end
            if self.btnImport then self.btnImport:Enable() end
        end
    end)

    -- Initial Check when opening frame
    f:HookScript("OnShow", function(self)
        if InCombatLockdown() then
            if self.btnApply then self.btnApply:Disable() end
        end
    end)
    
    f.btnDelete = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.btnDelete:SetSize(80, 25)
    f.btnDelete:SetPoint("LEFT", f.btnApply, "RIGHT", spacing, 0)
    f.btnDelete:SetText("Delete")
    f.btnDelete:SetScript("OnClick", function()
        if LM.selectedIndex > 0 then 
            EHT_FixStrata(StaticPopup_Show("EHTWEAKS_DELETE_CONFIRM"))
        end
    end)
        
	--Class Filter Checkbox
	local filterCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	filterCheck:SetSize(24, 24)	
	filterCheck:SetPoint("BOTTOMLEFT", listFrame, 0, -25)
	
	filterCheck:SetChecked(LM.showOnlyMyClass)

	local filterLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	filterLabel:SetPoint("LEFT", filterCheck, "RIGHT", 0, 0)
	filterLabel:SetText("My Class Only")
	filterLabel:SetTextColor(1, 0.82, 0)

	filterCheck:SetScript("OnClick", function(self)
	    LM.showOnlyMyClass = self:GetChecked()
	    LM.selectedIndex = 0
	    EHTweaks_RefreshLoadoutList()
	end)

	f.filterCheck = filterCheck

    f:Hide()
    LM.managerFrame = f
end

-- --- Static Popups ---
StaticPopupDialogs["EHTWEAKS_SAVELOADOUTMODE"] = {
    text = "You currently have |cff00ff00%s|r selected.\n\n" ..
           "Do you want to overwrite this loadout with your current build,\n" ..
           "or create a new loadout?",
    button1 = "Override",
    button2 = "Create New",
    OnAccept = function(self, data)
        OverrideSelectedLoadout()
    end,
    OnCancel = function(self, data)
        ShowSaveDialog()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs["EHTWEAKS_DELETE_CONFIRM"] = {
    text = "Delete this loadout forever?", button1 = "Yes", button2 = "No",
    OnAccept = function()
        local item = LM.listData[LM.selectedIndex]
        
        -- Identify the correct DB based on item properties
        local db
        if item.isBackup then
            db = GetBackupDB()
        elseif item.savedForClass then
            -- Item belongs to specific class (possibly not current player class)
            if EHTweaksDB.loadouts and EHTweaksDB.loadouts[item.savedForClass] then
                db = EHTweaksDB.loadouts[item.savedForClass]
            else
                -- Fallback to current class if structure is invalid
                db = GetClassLoadoutDB()
            end
        else
            -- Legacy or current class default
            db = GetClassLoadoutDB()
        end

        for k,v in ipairs(db) do 
            if v.timestamp == item.timestamp then 
                table.remove(db, k) 
                LM.selectedIndex = 0 
                EHTweaks_RefreshLoadoutList() 
                break 
            end 
        end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true
}

StaticPopupDialogs["EHT_EXPORT"] = {
    text = "Copy String (Ctrl+C):", button1 = "Close", hasEditBox = true, editBoxWidth = 350,
    timeout = 0, whileDead = true, hideOnEscape = true
}

StaticPopupDialogs["EHT_IMPORT"] = {
    text = "Paste Loadout String:", button1 = "Import", button2 = "Cancel", hasEditBox = true,
    OnAccept = function(self) 
        local LibDeflate = LibStub:GetLibrary("LibDeflate")
        local str = self.editBox:GetText()
        if str:find("!EHTL!") then
            str = str:gsub("!EHTL!", "")
            local data = LibDeflate:DecompressDeflate(LibDeflate:DecodeForPrint(str))
            local name, desc, icon, cost, nodes = data:match("^(.-)|(.-)|(.-)|(%d+)|(.*)$")
            if name then
                local nTable = {}
                for p in nodes:gmatch("([^,]+)") do local id, r = p:match("(%d+):(%d+)") nTable[tonumber(id)] = tonumber(r) end
                table.insert(GetClassLoadoutDB(), { name = name, desc = desc, icon = icon, cost = tonumber(cost), nodes = nTable, timestamp = time() })
                EHTweaks_RefreshLoadoutList()
            end
        end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true
}

function EHTweaks_ToggleLoadoutManager()
    if not LM.managerFrame then CreateLoadoutManagerFrame() end
    if LM.managerFrame:IsShown() then LM.managerFrame:Hide()
    else LM.selectedIndex = 0 EHTweaks_RefreshLoadoutList() LM.managerFrame:Show() end
end


-- Global function to load a loadout by name (case-insensitive)
-- --- Macro Support ---

function EHTweaks_LoadLoadout(targetName)
    if InCombatLockdown() then
        print("|cffff0000EHTweaks:|r Cannot change loadouts while in combat!")
        return
    end
    
    if not targetName or targetName == "" then
        print("|cffff0000EHTweaks:|r Usage: /ehtload Loadout Name")
        return
    end

    local allDB = EHTweaksDB.loadouts or {}
    local matches = {}
    
    -- Search ALL classes for the loadout
    for class, loadoutList in pairs(allDB) do
        for _, entry in ipairs(loadoutList) do
            if string.lower(entry.name) == string.lower(targetName) then
                table.insert(matches, entry)
            end
        end
    end

    if #matches > 0 then
        -- Warn if multiple loadouts exist with this name (Legacy data)
        if #matches > 1 then
            print("|cffff7f00EHTweaks Warning:|r Found " .. #matches .. " loadouts named '" .. targetName .. "'. Loading the first one found.")
        end

        -- Apply the first match
        local foundEntry = matches[1]
        EHTweaks_ApplyLoadout(foundEntry)
        print("|cff00ff00EHTweaks:|r Loading: " .. foundEntry.name)
    else
        print("|cffff0000EHTweaks:|r Loadout '" .. targetName .. "' not found.")
    end
end

-- Slash Command Handler
SLASH_EHTLOAD1 = "/ehtload"
SlashCmdList["EHTLOAD"] = function(msg)
    EHTweaks_LoadLoadout(msg)
end