-- File: Skin.lua
local addonName, addon = ...
_G.EHTweaks = _G.EHTweaks or addon
EHTweaks.Skin = EHTweaks.Skin or {}
local Skin = EHTweaks.Skin

-- Standard Window Frame (Backdrop + Title Stripe)
function Skin.ApplyWindow(f, titleText)
    if not f then return end

    -- Dark Backdrop (BACKGROUND Layer)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = {left = 0, right = 0, top = 0, bottom = 0},
    })
    f:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    f:SetBackdropBorderColor(0, 0, 0, 1)

    -- Title Stripe (ARTWORK Layer - Fixes Z-Fighting)
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
    if titleText then f.title:SetText(titleText) end
    
    -- Close Button
    if not f.closeBtn then
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 0, 0)
        close:SetScript("OnClick", function() f:Hide() end)
        f.closeBtn = close
    end
end

-- Thin Inset Frame (For lists, content areas)
function Skin.ApplyInset(f)
    if not f then return end
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    -- Slightly darker than main window, lighter border
    f:SetBackdropColor(0, 0, 0, 0.3) 
    f:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8) 
end
