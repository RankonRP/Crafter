-- Crafter: vlastní mapa – mapa zóny jen s tvými nálezy (kůže, rudy, byliny, ryby) a šipkou hráče
-- Obrázek mapy skládáme z dlaždic, které hra dává (C_Map.GetMapArtLayerTextures).
local C = Crafter
local FONT = "Interface\\AddOns\\Crafter\\Fonts\\cz.ttf"
local W = 640   -- šířka mapy v okně (mění se táhlem, pamatuje se v CrafterDB.mapW)

local win, canvas, tiles, pins, arrow = nil, nil, {}, {}, nil
local overlays = {}   -- objevené části mapy
local mapID, onlyItem, target, star
local view, zoom = nil, 1   -- výřez mapy (ScrollFrame) a přiblížení 1–6×
local host             -- rámeček záložky Mapa v hlavním okně (mapa je vložená do něj)

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
    local ratio = 2 / 3
    if layer and layer.layerWidth and layer.layerWidth > 0 then ratio = layer.layerHeight / layer.layerWidth end
    if host then
        -- vložená mapa: co nejširší, ale aby se vešla na výšku mezi horní a dolní ovládání
        W = math.floor(math.min(host:GetWidth() - 20, (host:GetHeight() - 122) / ratio))
    end
    local H = W * ratio
    view:SetSize(W, H)
    canvas:SetSize(W * zoom, H * zoom)
    if not host then
        win.sizing = true
        win:SetSize(W + 20, H + 122)
        win.sizing = false
    end
    for _, t in ipairs(overlays) do t:Hide() end
    if not layer or not textures then return end
    local cols = math.ceil(layer.layerWidth / layer.tileWidth)
    local k = W * zoom / layer.layerWidth
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
                p.tex = p:CreateTexture(nil, "OVERLAY")
                p.tex:SetAllPoints()
                p.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                p:EnableMouse(true)
                p:SetScript("OnEnter", pinEnter)
                p:SetScript("OnLeave", GameTooltip_Hide)
                pins[n] = p
            end
            p.itemID, p.kind = pt[3], pt[4]
            p:SetSize(CrafterDB.mapIcon or 18, CrafterDB.mapIcon or 18)
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
        -- značka cíle: pulzující zlatý kruh, uvnitř ikonka suroviny, pod ní jméno místa
        star = CreateFrame("Frame", nil, canvas)
        star:SetSize(34, 34)
        local mask = star:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints()
        star.glow = star:CreateTexture(nil, "ARTWORK")
        star.glow:SetPoint("CENTER")
        star.glow:SetSize(54, 54)
        star.glow:SetTexture("Interface\\Buttons\\WHITE8x8")
        star.glow:SetVertexColor(1, 0.8, 0.1, 0.5)
        local gmask = star:CreateMaskTexture()
        gmask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        gmask:SetAllPoints(star.glow)
        star.glow:AddMaskTexture(gmask)
        local pulse = star.glow:CreateAnimationGroup()
        pulse:SetLooping("BOUNCE")
        local a = pulse:CreateAnimation("Alpha")
        a:SetFromAlpha(1)
        a:SetToAlpha(0.15)
        a:SetDuration(0.6)
        pulse:Play()
        star.ring = star:CreateTexture(nil, "OVERLAY", nil, 1)
        star.ring:SetAllPoints()
        star.ring:SetTexture("Interface\\Buttons\\WHITE8x8")
        star.ring:SetVertexColor(1, 0.82, 0.1, 1)
        star.ring:AddMaskTexture(mask)
        star.tex = star:CreateTexture(nil, "OVERLAY", nil, 2)
        star.tex:SetPoint("CENTER")
        star.tex:SetSize(26, 26)
        local imask = star:CreateMaskTexture()
        imask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        imask:SetAllPoints(star.tex)
        star.tex:AddMaskTexture(imask)
        star.name = star:CreateFontString(nil, "OVERLAY")
        star.name:SetFont(FONT, 12, "OUTLINE")
        star.name:SetTextColor(1, 0.85, 0.2)
        star.name:SetPoint("TOP", star, "BOTTOM", 0, -4)
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
        star.tex:SetTexture(onlyItem and C.Sber.IconOf(onlyItem) or "Interface\\Icons\\INV_Misc_Bag_10")
        star.name:SetText(target.label or "")
        star:ClearAllPoints()
        star:SetPoint("CENTER", canvas, "TOPLEFT", target.x * w, -target.y * h)
        star:SetFrameLevel(canvas:GetFrameLevel() + 3)
        star:Show()
    else
        star:Hide()
    end
    if n == 0 and target and target.zoneID == mapID then
        win.count:SetText(("Zatím nenalezeno – zlatý kruh = nejbližší místo: %s"):format(target.label or "?"))
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
    if id ~= mapID then zoom = 1; if win and win.zoomText then win.zoomText:SetText("1.0×") end end
    mapID = id
    drawArt()
    drawPins()
    updateArrow()
end

-- Seznam všech zón (podle kontinentů) – klik přepne mapu
local picker
local CONTINENTS = { 1414, 1415 }   -- Kalimdor, Eastern Kingdoms (+ kontinent, kde právě jsi)
function C.ToggleZonePicker()
    if picker and picker:IsShown() then picker:Hide() return end
    if not picker then
        picker = CreateFrame("Frame", nil, win, "BackdropTemplate")
        picker:SetSize(260, 380)
        picker:SetPoint("TOP", win, "TOP", 0, -30)
        picker:SetFrameStrata("FULLSCREEN_DIALOG")
        picker:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        picker:SetBackdropColor(0.02, 0.02, 0.02, 0.97)
        picker:SetBackdropBorderColor(0.9, 0.7, 0.3, 1)
        picker:EnableMouse(true)
        local sf = CreateFrame("ScrollFrame", nil, picker, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 6, -6)
        sf:SetPoint("BOTTOMRIGHT", -26, 6)
        picker.content = CreateFrame("Frame", nil, sf)
        picker.content:SetSize(220, 10)
        sf:SetScrollChild(picker.content)
        picker.rows = {}
    end
    -- kontinenty: Kalimdor, Eastern Kingdoms a ten, kde právě jsi (Forever může mít nové)
    local conts, seen = {}, {}
    local here = C_Map.GetBestMapForUnit("player")
    local id = here
    for _ = 1, 5 do
        local info = id and C_Map.GetMapInfo(id)
        if not info then break end
        if info.mapType == 2 then if not seen[info.mapID] then conts[#conts + 1] = info.mapID; seen[info.mapID] = true end break end
        id = info.parentMapID
    end
    for _, c in ipairs(CONTINENTS) do if not seen[c] and C_Map.GetMapInfo(c) then conts[#conts + 1] = c; seen[c] = true end end
    local finds = {}
    for _, z in ipairs(C.Sber.ZonesWithFinds()) do finds[z[1]] = z[3] end

    local n, y = 0, 0
    local function row(text, r, g, b, onClick)
        n = n + 1
        local btn = picker.rows[n]
        if not btn then
            btn = CreateFrame("Button", nil, picker.content)
            btn:SetSize(220, 18)
            btn.text = fs(btn, 12)
            btn.text:SetPoint("LEFT", 4, 0)
            btn.text:SetJustifyH("LEFT")
            local hl = btn:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 0.8, 0.3, 0.15)
            picker.rows[n] = btn
        end
        btn.text:SetText(text)
        btn.text:SetTextColor(r, g, b)
        btn:SetScript("OnClick", onClick)
        btn:EnableMouse(onClick ~= nil)
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", 0, -y)
        btn:Show()
        y = y + 19
    end
    for _, cont in ipairs(conts) do
        local cinfo = C_Map.GetMapInfo(cont)
        row(cinfo and cinfo.name or ("#" .. cont), 0.9, 0.7, 0.3, nil)
        local zones = C_Map.GetMapChildrenInfo and C_Map.GetMapChildrenInfo(cont, 3) or {}
        table.sort(zones, function(a, b) return a.name < b.name end)
        for _, z in ipairs(zones) do
            local cnt = finds[z.mapID]
            local mid = z.mapID
            row("   " .. z.name .. (cnt and ("  (" .. cnt .. ")") or ""), cnt and 0.5 or 0.85, cnt and 1 or 0.85, cnt and 0.6 or 0.85, function()
                picker:Hide()
                show(mid)
            end)
        end
    end
    for i = n + 1, #picker.rows do picker.rows[i]:Hide() end
    picker.content:SetHeight(math.max(1, y))
    picker:Show()
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

local function create(parent)
    if parent then
        -- mapa vložená do záložky hlavního okna (bez vlastního rámu, zavírání a přesouvání)
        win = CreateFrame("Frame", nil, parent)
        win:SetAllPoints(parent)
        win.savePos = function() end
    else
    win = CreateFrame("Frame", "CrafterMapa", UIParent, "BackdropTemplate")
    win:Hide()
    -- poloha: uložená, jinak vpravo (mimo okna profese a Crafteru)
    local pos = CrafterDB.mapPos
    if pos then win:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else win:SetPoint("RIGHT", UIParent, "RIGHT", -30, -40) end
    win:SetFrameStrata("DIALOG")   -- vždy nad panelem Crafteru
    win:SetToplevel(true)          -- kliknutím dopředu
    win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    win:SetBackdropColor(0.03, 0.03, 0.03, 0.96)
    win:SetBackdropBorderColor(0.9, 0.7, 0.3, 1)
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    local function savePos()
        win:StopMovingOrSizing()
        local point, _, _, x, y = win:GetPoint()
        CrafterDB.mapPos = { point, math.floor(x + 0.5), math.floor(y + 0.5) }
    end
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", savePos)
    win.savePos = savePos
    tinsert(UISpecialFrames, "CrafterMapa")
    local title = fs(win, 14, 0.9, 0.7, 0.3)
    title:SetPoint("TOPLEFT", 10, -9)
    title:SetText("Crafter")
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    end

    -- zóna a přepínání
    local prev = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    prev:SetSize(26, 22)
    prev:SetPoint("TOPLEFT", parent and 8 or 80, -6)
    prev:SetText("<")
    prev:SetScript("OnClick", function() cycle(-1) end)
    local nextB = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    nextB:SetSize(26, 22)
    nextB:SetPoint("TOPRIGHT", parent and -8 or -34, -6)
    win.zone = fs(win, 13)
    win.zone:SetPoint("LEFT", prev, "RIGHT", 8, 0)
    win.zone:SetPoint("RIGHT", nextB, "LEFT", -8, 0)
    win.zone:SetJustifyH("CENTER")
    win.zone:SetWordWrap(false)
    -- klik na název zóny = seznam všech zón
    local zoneBtn = CreateFrame("Button", nil, win)
    zoneBtn:SetPoint("TOPLEFT", win.zone, "TOPLEFT", 0, 4)
    zoneBtn:SetPoint("BOTTOMRIGHT", win.zone, "BOTTOMRIGHT", 0, -4)
    local zhl = zoneBtn:CreateTexture(nil, "HIGHLIGHT")
    zhl:SetAllPoints()
    zhl:SetColorTexture(1, 0.8, 0.3, 0.15)
    zoneBtn:SetScript("OnClick", function() C.ToggleZonePicker() end)
    zoneBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Klik = vybrat zonu")
        GameTooltip:Show()
    end)
    zoneBtn:SetScript("OnLeave", GameTooltip_Hide)
    nextB:SetText(">")
    nextB:SetScript("OnClick", function() cycle(1) end)

    -- filtr
    local FILTER = { { "s", "Kůže" }, { "m", "Rudy" }, { "h", "Byliny" }, { "f", "Ryby" } }
    win.checks = {}
    for i, o in ipairs(FILTER) do
        local cb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetPoint("TOPLEFT", 8 + (i - 1) * 72, -32)
        cb:SetHitRectInsets(0, -44, 0, 0)
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
    all:SetSize(90, 22)
    all:SetPoint("TOPRIGHT", -10, -32)
    all:SetNormalFontObject(CrafterFontButton)
    all:SetHighlightFontObject(CrafterFontButtonHl)
    all:SetText("Vše")
    all:SetScript("OnClick", function() onlyItem = nil; target = nil; drawPins() end)

    view = CreateFrame("ScrollFrame", nil, win)
    view:SetPoint("TOPLEFT", 10, -60)
    view:SetClipsChildren(true)
    canvas = CreateFrame("Frame", nil, view)
    canvas:SetSize(W, W * 2 / 3)
    view:SetScrollChild(canvas)

    -- posun výřezu (hlídá okraje)
    local function scrollTo(x, y)
        local maxX = math.max(0, canvas:GetWidth() - view:GetWidth())
        local maxY = math.max(0, canvas:GetHeight() - view:GetHeight())
        view:SetHorizontalScroll(math.max(0, math.min(maxX, x)))
        view:SetVerticalScroll(math.max(0, math.min(maxY, y)))
    end
    -- přiblížit kolem bodu (fx, fy = 0..1 ve výřezu)
    local function setZoom(z, fx, fy)
        z = math.max(1, math.min(6, z))
        if z == zoom then return end
        fx, fy = fx or 0.5, fy or 0.5
        local cx = (view:GetHorizontalScroll() + fx * view:GetWidth()) / canvas:GetWidth()
        local cy = (view:GetVerticalScroll() + fy * view:GetHeight()) / canvas:GetHeight()
        zoom = z
        drawArt()
        drawPins()
        scrollTo(cx * canvas:GetWidth() - fx * view:GetWidth(), cy * canvas:GetHeight() - fy * view:GetHeight())
        win.zoomText:SetText(("%.1f×"):format(zoom))
    end
    win.setZoom = setZoom
    win.scrollTo = scrollTo

    view:EnableMouseWheel(true)
    view:SetScript("OnMouseWheel", function(self, delta)
        local x, y = GetCursorPosition()
        local s = self:GetEffectiveScale()
        local fx = (x / s - self:GetLeft()) / self:GetWidth()
        local fy = (self:GetTop() - y / s) / self:GetHeight()
        setZoom(zoom * (delta > 0 and 1.25 or 0.8), fx, fy)
    end)

    -- tažení: přiblížená mapa se posouvá, oddálená posouvá celé okno
    canvas:EnableMouse(true)
    canvas:RegisterForDrag("LeftButton")
    canvas:SetScript("OnDragStart", function(self)
        if zoom <= 1 then if not parent then win:StartMoving() end return end
        local x, y = GetCursorPosition()
        self.drag = { x = x, y = y, sx = view:GetHorizontalScroll(), sy = view:GetVerticalScroll() }
        self:SetScript("OnUpdate", function(me)
            local cx, cy = GetCursorPosition()
            local s = me:GetEffectiveScale()
            scrollTo(me.drag.sx - (cx - me.drag.x) / s, me.drag.sy + (cy - me.drag.y) / s)
        end)
    end)
    canvas:SetScript("OnDragStop", function(self)
        if self.drag then self.drag = nil; self:SetScript("OnUpdate", nil) else win.savePos() end
    end)
    arrow = canvas:CreateTexture(nil, "OVERLAY", nil, 7)
    arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
    arrow:SetSize(28, 28)

    local zOut = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    zOut:SetSize(24, 22)
    zOut:SetPoint("BOTTOMLEFT", 8, 34)
    zOut:SetText("-")
    zOut:SetScript("OnClick", function() win.setZoom(zoom * 0.8) end)
    win.zoomText = fs(win, 11)
    win.zoomText:SetPoint("LEFT", zOut, "RIGHT", 4, 0)
    win.zoomText:SetWidth(34)
    win.zoomText:SetText("1.0×")
    local zIn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    zIn:SetSize(24, 22)
    zIn:SetPoint("LEFT", win.zoomText, "RIGHT", 4, 0)
    zIn:SetText("+")
    zIn:SetScript("OnClick", function() win.setZoom(zoom * 1.25) end)
    local me = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    me:SetSize(60, 22)
    me:SetPoint("LEFT", zIn, "RIGHT", 6, 0)
    me:SetNormalFontObject(CrafterFontButton)
    me:SetHighlightFontObject(CrafterFontButtonHl)
    me:SetText("Na mě")
    me:SetScript("OnClick", function()
        local pos = C_Map.GetPlayerMapPosition(mapID, "player")
        if not pos then C.Msg("nejsi na teto mape.") return end
        if zoom < 2 then win.setZoom(2.5) end
        win.scrollTo(pos.x * canvas:GetWidth() - view:GetWidth() / 2, pos.y * canvas:GetHeight() - view:GetHeight() / 2)
    end)

    -- velikost ikonek (mapa, minimapa)
    local function sizeStepper(x, label, key, default, apply)
        local l = fs(win, 11)
        l:SetPoint("BOTTOMLEFT", x, 13)
        l:SetText(label)
        local minus = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        minus:SetSize(22, 20)
        minus:SetPoint("LEFT", l, "RIGHT", 6, 0)
        minus:SetText("-")
        local val = fs(win, 11)
        val:SetPoint("LEFT", minus, "RIGHT", 3, 0)
        val:SetWidth(22)
        local plus = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        plus:SetSize(22, 20)
        plus:SetPoint("LEFT", val, "RIGHT", 3, 0)
        plus:SetText("+")
        local function set(v)
            CrafterDB[key] = math.max(8, math.min(40, v))
            val:SetText(CrafterDB[key])
            apply()
        end
        minus:SetScript("OnClick", function() set((CrafterDB[key] or default) - 2) end)
        plus:SetScript("OnClick", function() set((CrafterDB[key] or default) + 2) end)
        val:SetText(CrafterDB[key] or default)
    end
    sizeStepper(10, "Mapa", "mapIcon", 18, function() drawPins() end)
    sizeStepper(170, "Minimapa", "miniIcon", 14, function() end)

    -- sdílení nálezů s kamarády
    local share = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    share:SetSize(64, 20)
    share:SetPoint("BOTTOMRIGHT", parent and -8 or -22, 8)
    share:SetNormalFontObject(CrafterFontButton)
    share:SetHighlightFontObject(CrafterFontButtonHl)
    share:SetText("Sdílet")
    share:SetScript("OnClick", function() C.OpenShare() end)

    win.count = fs(win, 11, 0.75, 0.75, 0.75)
    win.count:SetPoint("BOTTOMLEFT", 168, 38)
    win.count:SetPoint("RIGHT", win, "RIGHT", -24, 0)
    win.count:SetJustifyH("LEFT")
    win.count:SetWordWrap(false)

    -- táhlo pro změnu velikosti (vpravo dole) – jen samostatné okno
    if not parent then
    win:SetResizable(true)
    if win.SetResizeBounds then win:SetResizeBounds(400, 320, 1600, 1150) end
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
            local newW = math.floor(math.max(380, math.min(1580, win:GetWidth() - 20)))
            if newW ~= W or math.abs(win:GetHeight() - (view:GetHeight() + 122)) > 2 then
                W = newW
                CrafterDB.mapW = W
                if mapID then drawArt(); drawPins() end
            end
        end)
    end)
    end
    local mm = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    mm:SetSize(22, 22)
    mm:SetPoint("BOTTOMLEFT", 146, 7)
    mm:SetHitRectInsets(0, 0, 0, 0)
    mm:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Ukazovat nalezy i na minimape")
        GameTooltip:Show()
    end)
    mm:SetScript("OnLeave", GameTooltip_Hide)
    if mm.Text then mm.Text:SetText("") end
    local mml = fs(win, 12)
    mml:SetPoint("LEFT", mm, "RIGHT", 2, 0)
    mml:SetText("")
    mm:SetScript("OnClick", function(self) CrafterDB.sber.minimap = self:GetChecked() and true or false end)
    win.mm = mm

    win.sync = function()
        for k, cb in pairs(win.checks) do cb:SetChecked(CrafterDB.sber[k] and true or false) end
        win.mm:SetChecked(CrafterDB.sber.minimap and true or false)
    end
    win:SetScript("OnShow", win.sync)
    C_Timer.NewTicker(0.2, function() pcall(updateArrow) end)
end

-- otevřít mapu: zone = mapa (nebo tvoje zóna), item = zvýraznit jen jeden předmět
-- vložit mapu do záložky hlavního okna (volá Okno.lua)
function C.EmbedMap(parent)
    host = parent
    if not win then create(parent) end
end

function C.OpenMap(zone, item, tg)
    if C.EnsureMain then C.EnsureMain() end   -- mapa žije v záložce hlavního okna
    if host and C.ShowMainTab then C.ShowMainTab(3) end
    if CrafterDB.mapW and not host then W = math.max(380, CrafterDB.mapW) end
    if not win then create() end
    onlyItem = item
    target = tg
    local id = zone or C_Map.GetBestMapForUnit("player")
    if not id then C.Msg("nevim, kde jsi - zkus to venku.") return end
    win:Show()
    win:Raise()
    win.sync()
    show(id)
end

function C.ToggleMap()
    if host and C.ToggleMain then C.ToggleMain(3) return end
    if win and win:IsShown() then win:Hide() else C.OpenMap() end
end

-- záložka Mapa se ukázala -> překreslit (velikost záložky mohla být jiná)
function C.MapTabShown()
    if not win then return end
    win.sync()
    show(mapID or C_Map.GetBestMapForUnit("player"))
end

-- tlačítko Mapa u suroviny: tvoje nálezy -> vlastní mapa zóny s tou surovinou; jinak značka k nejbližšímu zdroji
function C.MapFor(itemID, name)
    -- vyrábí se to z něčeho (bar z rudy)? když ten předmět sám nemáš nalezený, hledej jeho suroviny
    local z = itemID and Crafter_Zdroje and Crafter_Zdroje[itemID]
    local own = itemID and C.Sber.Points(itemID)
    if (not own or #own == 0) and z and z.r then
        for _, rg in ipairs(z.r) do
            local p = C.Sber.Points(rg[1])
            if p and #p > 0 then
                C.Msg(("%s se vyrabi z %s - ukazuju, kde ho mas nalezeny."):format(name or "?", C.Sber.ItemName(rg[1])))
                return C.MapFor(rg[1], C.Sber.ItemName(rg[1]))
            end
        end
        -- bar nikdo neprodává a rudu nemáš nalezenou -> nejbližší místo pro rudu
        if not z.v then
            local rg = z.r[1]
            C.Msg(("%s se vyrabi z %s - ukazuju, kde ho sezenes."):format(name or "?", C.Sber.ItemName(rg[1])))
            return C.MapFor(rg[1], C.Sber.ItemName(rg[1]))
        end
    end
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

-- Okno sdílení: nahoře tvoje nálezy jako text (Ctrl+C), dole vložit text od kamaráda (Ctrl+V)
local shareWin
function C.OpenShare()
    if not shareWin then
        shareWin = CreateFrame("Frame", "CrafterShare", UIParent, "BackdropTemplate")
        shareWin:SetSize(460, 330)
        shareWin:SetPoint("CENTER")
        shareWin:SetFrameStrata("FULLSCREEN_DIALOG")
        shareWin:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        shareWin:SetBackdropColor(0.03, 0.03, 0.03, 0.97)
        shareWin:SetBackdropBorderColor(0.9, 0.7, 0.3, 1)
        shareWin:EnableMouse(true)
        shareWin:SetMovable(true)
        shareWin:RegisterForDrag("LeftButton")
        shareWin:SetScript("OnDragStart", shareWin.StartMoving)
        shareWin:SetScript("OnDragStop", shareWin.StopMovingOrSizing)
        tinsert(UISpecialFrames, "CrafterShare")
        local title = fs(shareWin, 14, 0.9, 0.7, 0.3)
        title:SetPoint("TOPLEFT", 10, -9)
        title:SetText("Crafter – sdílet nálezy")
        local close = CreateFrame("Button", nil, shareWin, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        local function box(y, h, label)
            local l = fs(shareWin, 11, 0.8, 0.8, 0.8)
            l:SetPoint("TOPLEFT", 12, y)
            l:SetWidth(436)
            l:SetJustifyH("LEFT")
            l:SetText(label)
            local sf = CreateFrame("ScrollFrame", nil, shareWin, "UIPanelScrollFrameTemplate")
            sf:SetPoint("TOPLEFT", 12, y - 30)
            sf:SetSize(410, h)
            local bg = shareWin:CreateTexture(nil, "BACKGROUND", nil, 1)
            bg:SetPoint("TOPLEFT", sf, -2, 2)
            bg:SetPoint("BOTTOMRIGHT", sf, 2, -2)
            bg:SetColorTexture(1, 1, 1, 0.05)
            local eb = CreateFrame("EditBox", nil, sf)
            eb:SetMultiLine(true)
            eb:SetAutoFocus(false)
            eb:SetFontObject(ChatFontSmall or ChatFontNormal)
            eb:SetWidth(400)
            eb:SetScript("OnEscapePressed", function() shareWin:Hide() end)
            sf:SetScrollChild(eb)
            return eb
        end
        shareWin.out = box(-32, 70, "Tvoje nálezy – klikni do pole, Ctrl+A a Ctrl+C, a pošli kamarádovi:")
        shareWin.inp = box(-150, 70, "Nálezy od kamaráda – vlož text (Ctrl+V) a klikni Načíst. Tvoje místa zůstanou, jen přibudou nová.")
        local load = CreateFrame("Button", nil, shareWin, "UIPanelButtonTemplate")
        load:SetSize(120, 22)
        load:SetPoint("BOTTOMLEFT", 12, 10)
        load:SetNormalFontObject(CrafterFontButton)
        load:SetHighlightFontObject(CrafterFontButtonHl)
        load:SetText("Načíst")
        load:SetScript("OnClick", function()
            local n, err = C.Sber.Import(shareWin.inp:GetText())
            if not n then C.Msg("nacteni se nepovedlo: " .. err) return end
            C.Msg(("nacteno - pribylo %d novych mist."):format(n))
            shareWin.inp:SetText("")
            shareWin.out:SetText(C.Sber.Export())
            if C.MapChanged then C.MapChanged() end
        end)
    end
    shareWin.out:SetText(C.Sber.Export())
    shareWin:Show()
    shareWin.out:SetFocus()
    shareWin.out:HighlightText()
end

-- nový nález -> překreslit, když je mapa otevřená
function C.MapChanged()
    if win and win:IsShown() then drawPins() end
end
