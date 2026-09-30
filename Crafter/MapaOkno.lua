-- Crafter: vlastní mapa – mapa zóny jen s tvými nálezy (kůže, rudy, byliny, ryby) a šipkou hráče
-- Obrázek mapy skládáme z dlaždic, které hra dává (C_Map.GetMapArtLayerTextures).
local C = Crafter
local FONT = "Interface\\AddOns\\Crafter\\Fonts\\cz.ttf"
local W = 640   -- šířka mapy v okně (mění se táhlem, pamatuje se v CrafterDB.mapW)

local win, canvas, tiles, pins, arrow = nil, nil, {}, {}, nil
local overlays = {}   -- objevené části mapy
local mapID, onlyItem, target, star

local function fs(parent, size, r, g, b)
    local t = parent:CreateFontString(nil, "OVERLAY")
    t:SetFont(FONT, size, "")
    t:SetTextColor(r or 1, g or 1, b or 1)
    return t
end

-- dlaždice obrázku mapy
local function drawArt()
    for _, t in ipairs(tiles) do t:Hide() end
    local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(mapID)
    local layer = layers and layers[1]
    local textures = C_Map.GetMapArtLayerTextures and C_Map.GetMapArtLayerTextures(mapID, 1)
    local H = W * 2 / 3
    if layer and layer.layerWidth and layer.layerWidth > 0 then H = W * layer.layerHeight / layer.layerWidth end
    canvas:SetSize(W, H)
    win.sizing = true
    win:SetSize(W + 20, H + 96)
    win.sizing = false
    for _, t in ipairs(overlays) do t:Hide() end
    if not layer or not textures then return end
    local cols = math.ceil(layer.layerWidth / layer.tileWidth)
    local k = W / layer.layerWidth
    for i, fileID in ipairs(textures) do
        local t = tiles[i]
        if not t then t = canvas:CreateTexture(nil, "BACKGROUND"); tiles[i] = t end
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        t:SetTexture(fileID)
        t:SetSize(layer.tileWidth * k, layer.tileHeight * k)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", canvas, "TOPLEFT", col * layer.tileWidth * k, -row * layer.tileHeight * k)
        t:Show()
    end

    -- objevené části zóny (vesnice, údolí…) – stejně jako je kreslí mapa hry
    local explored = C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures and C_MapExplorationInfo.GetExploredMapTextures(mapID)
    local n = 0
    for _, info in ipairs(explored or {}) do
        if not info.isShownByMouseOver then
            local wide = math.ceil(info.textureWidth / 256)
            local tall = math.ceil(info.textureHeight / 256)
            local idx = 0
            for j = 1, tall do
                local ph, fh = 256, 256
                if j == tall then
                    ph = info.textureHeight % 256
                    if ph == 0 then ph = 256 end
                    fh = 16
                    while fh < ph do fh = fh * 2 end
                end
                for i = 1, wide do
                    idx = idx + 1
                    local pw, fw = 256, 256
                    if i == wide then
                        pw = info.textureWidth % 256
                        if pw == 0 then pw = 256 end
                        fw = 16
                        while fw < pw do fw = fw * 2 end
                    end
                    local fileID = info.fileDataIDs and info.fileDataIDs[idx]
                    if fileID then
                        n = n + 1
                        local t = overlays[n]
                        if not t then t = canvas:CreateTexture(nil, "BORDER"); overlays[n] = t end
                        t:SetTexture(fileID)
                        t:SetTexCoord(0, pw / fw, 0, ph / fh)
                        t:SetSize(pw * k, ph * k)
                        t:ClearAllPoints()
                        t:SetPoint("TOPLEFT", canvas, "TOPLEFT", (info.offsetX + 256 * (i - 1)) * k, -(info.offsetY + 256 * (j - 1)) * k)
                        t:Show()
                    end
                end
            end
        end
    end
end

local function pinEnter(self)
    local f = CrafterDB.found[self.itemID]
    local srcs = {}
    for name in pairs(f and f.src or {}) do srcs[#srcs + 1] = name end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(C.Sber.ItemName(self.itemID))
    local kind = ({ s = "Skinning", m = "Mining", h = "Herbalism", f = "Fishing" })[self.kind] or ""
    GameTooltip:AddLine(kind .. (#srcs > 0 and (": " .. table.concat(srcs, ", ")) or ""), 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end

local function drawPins()
    for _, p in ipairs(pins) do p:Hide() end
    local w, h = canvas:GetSize()
    local n = 0
    for _, pt in ipairs(C.Sber.OnMap(mapID, onlyItem)) do
        if CrafterDB.sber[pt[4]] then
            n = n + 1
            local p = pins[n]
            if not p then
                p = CreateFrame("Frame", nil, canvas)
                p:SetSize(18, 18)
                p.tex = p:CreateTexture(nil, "OVERLAY")
                p.tex:SetAllPoints()
                p.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                p:EnableMouse(true)
                p:SetScript("OnEnter", pinEnter)
                p:SetScript("OnLeave", GameTooltip_Hide)
                pins[n] = p
            end
            p.itemID, p.kind = pt[3], pt[4]
            p.tex:SetTexture(C.Sber.IconOf(pt[3]))
            p:ClearAllPoints()
            p:SetPoint("CENTER", canvas, "TOPLEFT", pt[1] * w, -pt[2] * h)
            p:SetFrameLevel(canvas:GetFrameLevel() + 2)
            p:Show()
        end
    end
    local info = C_Map.GetMapInfo(mapID)
    win.zone:SetText((info and info.name or "?") .. (onlyItem and ("  –  jen " .. C.Sber.ItemName(onlyItem)) or ""))
    -- hvězdička: kam jít pro surovinu, kterou ještě nemáš nalezenou
    if not star then
        star = CreateFrame("Frame", nil, canvas)
        star:SetSize(24, 24)
        star.tex = star:CreateTexture(nil, "OVERLAY")
        star.tex:SetAllPoints()
        star.tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_1")
        star:EnableMouse(true)
        star:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.label or "?")
            GameTooltip:AddLine("Crafter - sem pro " .. (self.item or "surovinu"), 0.9, 0.7, 0.3)
            GameTooltip:Show()
        end)
        star:SetScript("OnLeave", GameTooltip_Hide)
    end
    if target and target.zoneID == mapID and target.x then
        star.label, star.item = target.label, target.item
        star:ClearAllPoints()
        star:SetPoint("CENTER", canvas, "TOPLEFT", target.x * w, -target.y * h)
        star:SetFrameLevel(canvas:GetFrameLevel() + 3)
        star:Show()
    else
        star:Hide()
    end
    if n == 0 and target and target.zoneID == mapID then
        win.count:SetText(("Zatím nenalezeno – hvězdička = nejbližší místo: %s. Na mapě hry máš značku."):format(target.label or "?"))
    else
        win.count:SetText(n == 0 and "Tady zatím nemáš žádné nálezy. Stahuj, těž, trhej – Crafter si místa zapamatuje." or ("Nálezů na mapě: %d"):format(n))
    end
end

local function updateArrow()
    if not win or not win:IsShown() then return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos or pos.x < 0 or pos.x > 1 or pos.y < 0 or pos.y > 1 then arrow:Hide() return end
    local w, h = canvas:GetSize()
    arrow:ClearAllPoints()
    arrow:SetPoint("CENTER", canvas, "TOPLEFT", pos.x * w, -pos.y * h)
    local ok, facing = pcall(GetPlayerFacing)
    if ok and facing then arrow:SetRotation(facing) end
    arrow:Show()
end

local function show(id)
    mapID = id
    drawArt()
    drawPins()
    updateArrow()
end

-- přepínání mezi zónami s nálezy (a tvou zónou)
local function cycle(step)
    local zones = C.Sber.ZonesWithFinds()
    local here = C_Map.GetBestMapForUnit("player")
    local list, seen = {}, {}
    if here then list[1] = here; seen[here] = true end
    for _, z in ipairs(zones) do if not seen[z[1]] then list[#list + 1] = z[1]; seen[z[1]] = true end end
    if #list == 0 then return end
    local idx = 1
    for i, id in ipairs(list) do if id == mapID then idx = i end end
    idx = ((idx - 1 + step) % #list) + 1
    show(list[idx])
end

local function create()
    win = CreateFrame("Frame", "CrafterMapa", UIParent, "BackdropTemplate")
    win:SetPoint("CENTER")
    win:SetFrameStrata("HIGH")
    win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    win:SetBackdropColor(0.03, 0.03, 0.03, 0.96)
    win:SetBackdropBorderColor(0.9, 0.7, 0.3, 1)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    tinsert(UISpecialFrames, "CrafterMapa")
    local title = fs(win, 14, 0.9, 0.7, 0.3)
    title:SetPoint("TOPLEFT", 10, -9)
    title:SetText("Crafter – moje nálezy")
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    -- zóna a přepínání
    local prev = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    prev:SetSize(26, 22)
    prev:SetPoint("TOPLEFT", 190, -6)
    prev:SetText("<")
    prev:SetScript("OnClick", function() cycle(-1) end)
    local nextB = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    nextB:SetSize(26, 22)
    nextB:SetPoint("TOPRIGHT", -34, -6)
    win.zone = fs(win, 13)
    win.zone:SetPoint("LEFT", prev, "RIGHT", 8, 0)
    win.zone:SetPoint("RIGHT", nextB, "LEFT", -8, 0)
    win.zone:SetJustifyH("CENTER")
    win.zone:SetWordWrap(false)
    nextB:SetText(">")
    nextB:SetScript("OnClick", function() cycle(1) end)

    -- filtr
    local FILTER = { { "s", "Kůže" }, { "m", "Rudy" }, { "h", "Byliny" }, { "f", "Ryby" } }
    win.checks = {}
    for i, o in ipairs(FILTER) do
        local cb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", 10 + (i - 1) * 92, -32)
        cb:SetHitRectInsets(0, -70, 0, 0)
        if cb.Text then cb.Text:SetText("") end
        local l = fs(win, 12)
        l:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        l:SetText(o[2])
        cb:SetScript("OnClick", function(self)
            CrafterDB.sber[o[1]] = self:GetChecked() and true or false
            C.Sber.Rebuild()
            drawPins()
        end)
        win.checks[o[1]] = cb
    end
    local all = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    all:SetSize(110, 22)
    all:SetPoint("TOPRIGHT", -10, -32)
    all:SetNormalFontObject(CrafterFontButton)
    all:SetHighlightFontObject(CrafterFontButtonHl)
    all:SetText("Ukázat vše")
    all:SetScript("OnClick", function() onlyItem = nil; target = nil; drawPins() end)

    canvas = CreateFrame("Frame", nil, win)
    canvas:SetPoint("TOPLEFT", 10, -60)
    arrow = canvas:CreateTexture(nil, "OVERLAY", nil, 7)
    arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    arrow:SetSize(28, 28)

    win.count = fs(win, 11, 0.75, 0.75, 0.75)
    win.count:SetPoint("BOTTOMLEFT", 10, 12)
    win.count:SetPoint("RIGHT", win, "RIGHT", -170, 0)
    win.count:SetJustifyH("LEFT")
    win.count:SetWordWrap(false)

    -- táhlo pro změnu velikosti (vpravo dole)
    win:SetResizable(true)
    if win.SetResizeBounds then win:SetResizeBounds(560, 420, 1600, 1150) end
    local grip = CreateFrame("Button", nil, win)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function() win:StopMovingOrSizing() end)
    -- mapu přizpůsobit šířce okna (i během tažení; výška se dopočítá podle poměru mapy)
    local pendingResize
    win:SetScript("OnSizeChanged", function(self, w)
        if self.sizing or pendingResize then return end
        pendingResize = true
        C_Timer.After(0.15, function()
            pendingResize = nil
            local newW = math.floor(math.max(540, math.min(1580, win:GetWidth() - 20)))
            if newW ~= W or math.abs(win:GetHeight() - (canvas:GetHeight() + 96)) > 2 then
                W = newW
                CrafterDB.mapW = W
                if mapID then drawArt(); drawPins() end
            end
        end)
    end)
    local mm = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    mm:SetSize(22, 22)
    mm:SetPoint("BOTTOMRIGHT", -140, 8)
    mm:SetHitRectInsets(0, -130, 0, 0)
    if mm.Text then mm.Text:SetText("") end
    local mml = fs(win, 12)
    mml:SetPoint("LEFT", mm, "RIGHT", 2, 0)
    mml:SetText("I na minimapě")
    mm:SetScript("OnClick", function(self) CrafterDB.sber.minimap = self:GetChecked() and true or false end)
    win.mm = mm

    win:SetScript("OnShow", function()
        for k, cb in pairs(win.checks) do cb:SetChecked(CrafterDB.sber[k]) end
        win.mm:SetChecked(CrafterDB.sber.minimap)
    end)
    C_Timer.NewTicker(0.2, function() pcall(updateArrow) end)
end

-- otevřít mapu: zone = mapa (nebo tvoje zóna), item = zvýraznit jen jeden předmět
function C.OpenMap(zone, item, tg)
    if CrafterDB.mapW then W = math.max(540, CrafterDB.mapW) end
    if not win then create() end
    onlyItem = item
    target = tg
    local id = zone or C_Map.GetBestMapForUnit("player")
    if not id then C.Msg("nevim, kde jsi - zkus to venku.") return end
    win:Show()
    show(id)
end

function C.ToggleMap()
    if win and win:IsShown() then win:Hide() else C.OpenMap() end
end

-- tlačítko Mapa u suroviny: tvoje nálezy -> vlastní mapa zóny s tou surovinou; jinak značka k nejbližšímu zdroji
function C.MapFor(itemID, name)
    local pts = itemID and C.Sber.Points(itemID)
    if pts and #pts > 0 then
        local a, b, inst = C.PlayerWorld()
        local best, bestD
        for i = 1, #pts, 3 do
            local d = (a and pts[i] == inst) and ((pts[i + 1] - a) ^ 2 + (pts[i + 2] - b) ^ 2) or 1e12
            if not bestD or d < bestD then best, bestD = i, d end
        end
        local _, zoneID = C.ZoneOf(pts[best], pts[best + 1], pts[best + 2])
        if zoneID then C.OpenMap(zoneID, itemID) return end
    end
    -- ještě nenalezeno: značka + mapa Crafteru s hvězdičkou u nejbližšího obchodníka / místa
    C.lastTarget = nil
    C.ShowOnMap(itemID, name)
    local tg = C.lastTarget
    if tg and tg.zoneID then C.OpenMap(tg.zoneID, itemID, tg) end
end

-- nový nález -> překreslit, když je mapa otevřená
function C.MapChanged()
    if win and win:IsShown() then drawPins() end
end
