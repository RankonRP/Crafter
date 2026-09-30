-- Crafter: kde se surovina sežene – zóny, značka na mapě, tečky na mapě světa
-- Data jsou v Zdroje.lua (světové souřadnice spawnů z CMaNGOS). Na zónu a souřadnice
-- mapy je převádí hra (C_Map). Pořadí os se jednou ověří podle polohy hráče.
local C = Crafter

local CONTINENT_NAMES = { [0] = "Eastern Kingdoms", [1] = "Kalimdor" }

-------------------------------------------------------------------------------
-- Převod světových souřadnic na zónu
-------------------------------------------------------------------------------
local function vec(map, x, y)
    if CrafterDB and CrafterDB.axis == "ba" then return CreateVector2D(y, x) end
    return CreateVector2D(x, y)
end

C.Vec = function(map, x, y) return vec(map, x, y) end
-- body z databáze: kdyby osy databáze byly v jiném pořadí než ve hře, /crafter osy je prohodí
C.DbXY = function(x, y) if CrafterDB and CrafterDB.dbSwap then return y, x end return x, y end
local zoneCache = {}

-- jednou: zjistit, v jakém pořadí C_Map chce souřadnice (podle polohy hráče)
local function calibrate()
    if CrafterDB.axis then return end
    local ok = pcall(function()
        local a, b, _, inst = UnitPosition("player")
        local zone = C_Map.GetBestMapForUnit("player")
        local pp = zone and C_Map.GetPlayerMapPosition(zone, "player")
        if not a or not pp then return end
        local best, bestD
        for _, order in ipairs({ "ab", "ba" }) do
            local v = order == "ab" and CreateVector2D(a, b) or CreateVector2D(b, a)
            local _, pos = C_Map.GetMapPosFromWorldPos(inst, v, zone)
            if pos then
                local d = (pos.x - pp.x) ^ 2 + (pos.y - pp.y) ^ 2
                if not bestD or d < bestD then best, bestD = order, d end
            end
        end
        if best and bestD < 0.01 then CrafterDB.axis = best; wipe(zoneCache) end
    end)
    return ok
end
C.Calibrate = function() return calibrate() end

-- vrací název zóny, uiMapID zóny a souřadnice 0..1 v ní (nebo nil)
function C.ZoneOf(map, x, y)
    calibrate()
    local key = map .. ":" .. math.floor(x / 50) .. ":" .. math.floor(y / 50)
    local hit = zoneCache[key]
    if hit ~= nil then
        if hit == false then return nil end
        local _, pos = C_Map.GetMapPosFromWorldPos(map, vec(map, x, y), hit.id)
        return hit.name, hit.id, pos and pos.x, pos and pos.y
    end
    local ok, name, id, zx, zy = pcall(function()
        local mapID, pos = C_Map.GetMapPosFromWorldPos(map, vec(map, x, y))
        if not mapID or not pos then return nil end
        local info = C_Map.GetMapInfo(mapID)
        -- když dostaneme kontinent, zjistit zónu na té pozici
        if info and info.mapType and info.mapType < 3 then
            local child = C_Map.GetMapInfoAtPosition(mapID, pos.x, pos.y)
            if child and child.mapID ~= mapID then
                local _, cpos = C_Map.GetMapPosFromWorldPos(map, vec(map, x, y), child.mapID)
                return child.name, child.mapID, cpos and cpos.x, cpos and cpos.y
            end
        end
        return info and info.name, mapID, pos.x, pos.y
    end)
    if not ok or not name then zoneCache[key] = false return nil end
    zoneCache[key] = { name = name, id = id }
    return name, id, zx, zy
end

-- body zdroje -> seznam unikátních zón (nejčastější první)
local function zonesOf(pts, max)
    local count, order = {}, {}
    for i = 1, #pts, 3 do
        local name = C.ZoneOf(pts[i], C.DbXY(pts[i + 1], pts[i + 2]))
        if name then
            if not count[name] then count[name] = 0; order[#order + 1] = name end
            count[name] = count[name] + 1
        end
    end
    table.sort(order, function(a, b) return count[a] > count[b] end)
    local out = {}
    for i = 1, math.min(max or 3, #order) do out[i] = order[i] end
    if #order == 0 and pts[1] then out[1] = CONTINENT_NAMES[pts[1]] or "?" end
    return out, #order
end

-------------------------------------------------------------------------------
-- Popis zdrojů suroviny (pro popisky)
-------------------------------------------------------------------------------
local function levels(n)
    if not n.l1 or n.l1 == 0 then return "" end
    return n.l1 == n.l2 and (" lvl " .. n.l1) or (" lvl " .. n.l1 .. "-" .. n.l2)
end

-- vrací { { druh, text, barva } } – druh: "v" prodejce, "d" kořist, "s" stahování, "g" sběr, "c" výroba
function C.SourceLines(itemID, maxPer)
    local z = Crafter_Zdroje and Crafter_Zdroje[itemID]
    if not z then return nil end
    maxPer = maxPer or 3
    local out = {}
    local function zoneText(pts)
        local zs, total = zonesOf(pts, 3)
        local s = table.concat(zs, ", ")
        if total > 3 then s = s .. " …" end
        return s
    end
    if z.v then
        for i = 1, math.min(maxPer, #z.v) do
            local n = Crafter_NPC[z.v[i]]
            if n then out[#out + 1] = { "v", ("Prodává: %s (%s)%s"):format(n.n, zoneText(n.p), z.price and ("  " .. C.Money(z.price)) or "") } end
        end
        if #z.v > maxPer then out[#out + 1] = { "v", ("  … a dalších %d prodejců"):format(#z.v - maxPer) } end
    end
    if z.g then
        for i = 1, math.min(maxPer, #z.g) do
            local o = Crafter_OBJ[z.g[i][1]]
            if o then out[#out + 1] = { "g", ("Sbírá se z: %s (%s)"):format(o.n, zoneText(o.p)) } end
        end
    end
    if z.s then
        local lo, hi, names = 99, 0, {}
        for i, id in ipairs(z.s) do
            local n = Crafter_NPC[id]
            if n then
                lo, hi = math.min(lo, n.l1 or 99), math.max(hi, n.l2 or 0)
                if i <= maxPer then names[#names + 1] = n.n .. levels(n) .. " (" .. zoneText(n.p) .. ")" end
            end
        end
        for _, s in ipairs(names) do out[#out + 1] = { "s", "Stahuje se z: " .. s } end
        if #z.s > maxPer then out[#out + 1] = { "s", ("  … a z dalších %d zvířat (lvl %d-%d)"):format(#z.s - maxPer, lo, hi) } end
    end
    if z.d then
        for i = 1, math.min(maxPer, #z.d) do
            local n = Crafter_NPC[z.d[i][1]]
            if n then out[#out + 1] = { "d", ("Padá z: %s%s %d %% (%s)"):format(n.n, levels(n), z.d[i][2], zoneText(n.p)) } end
        end
    end
    if z.c then out[#out + 1] = { "c", "Vyrábí se: " .. table.concat(z.c, ", ") } end
    return out
end

C.SOURCE_COLOR = {
    v = { 1, 0.82, 0.2 },    -- prodejce: zlatá
    g = { 0.3, 1, 0.3 },     -- sběr: zelená
    s = { 0.85, 0.55, 0.25 },-- stahování: hnědá
    d = { 1, 0.35, 0.35 },   -- kořist: červená
    c = { 0.6, 0.8, 1 },     -- výroba: modrá
}

-------------------------------------------------------------------------------
-- Všechny body suroviny: { druh, mapa, x, y, jméno }
-------------------------------------------------------------------------------
local function allPoints(itemID, limit)
    local z = Crafter_Zdroje and Crafter_Zdroje[itemID]
    local out = {}
    if not z then return out end
    local function add(kind, pts, name)
        for i = 1, #pts, 3 do
            if #out >= (limit or 800) then return end
            local x, y = C.DbXY(pts[i + 1], pts[i + 2])
            out[#out + 1] = { kind, pts[i], x, y, name }
        end
    end
    for _, id in ipairs(z.v or {}) do local n = Crafter_NPC[id]; if n then add("v", n.p, n.n) end end
    for _, g in ipairs(z.g or {}) do local o = Crafter_OBJ[g[1]]; if o then add("g", o.p, o.n) end end
    for _, id in ipairs(z.s or {}) do local n = Crafter_NPC[id]; if n then add("s", n.p, n.n) end end
    for _, d in ipairs(z.d or {}) do local n = Crafter_NPC[d[1]]; if n then add("d", n.p, n.n) end end
    return out
end

-------------------------------------------------------------------------------
-- Značka na mapě k nejbližšímu místu + tečky na mapě světa
-------------------------------------------------------------------------------
function C.ShowOnMap(itemID, name)
    CrafterDB.mapItem = itemID
    CrafterDB.mapItemName = name
    local pts = allPoints(itemID)
    if #pts == 0 then C.Msg("pro tuhle surovinu nemam zadne misto na mape.") return end
    local a, b, _, inst
    pcall(function() a, b, _, inst = UnitPosition("player") end)
    local best, bestD
    for _, p in ipairs(pts) do
        if a and p[2] == inst then
            local d = (p[3] - a) ^ 2 + (p[4] - b) ^ 2
            if not bestD or d < bestD then best, bestD = p, d end
        end
    end
    best = best or pts[1]
    local zoneName, zoneID, zx, zy = C.ZoneOf(best[2], best[3], best[4])
    if zoneID and zx and C_Map.SetUserWaypoint and UiMapPoint then
        local ok = pcall(function()
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(zoneID, zx, zy))
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
        end)
        if ok then
            C.Msg(("znacka na mape: %s - %s (%s %.0f, %.0f). Na mape sveta uvidis vsechna mista."):format(
                name or "?", best[5] or "?", zoneName or "?", zx * 100, zy * 100))
        end
    else
        C.Msg(("nejblizsi misto: %s (%s)"):format(best[5] or "?", zoneName or CONTINENT_NAMES[best[2]] or "?"))
    end
    if C.RefreshMapPins then C.RefreshMapPins() end
end

function C.ClearMap()
    CrafterDB.mapItem = nil
    if C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
    if C.RefreshMapPins then C.RefreshMapPins() end
end

-- tečky na mapě světa pro vybranou surovinu
local pins, pinFrame, legend = {}, nil, nil
function C.RefreshMapPins()
    if not WorldMapFrame or not WorldMapFrame.GetCanvas then return end
    local canvas = WorldMapFrame:GetCanvas()
    if not pinFrame then
        pinFrame = CreateFrame("Frame", nil, canvas)
        pinFrame:SetAllPoints()
        pinFrame:SetFrameLevel(canvas:GetFrameLevel() + 20)
        legend = CreateFrame("Button", nil, WorldMapFrame, "BackdropTemplate")
        legend:SetSize(260, 22)
        legend:SetPoint("TOP", WorldMapFrame.ScrollContainer or WorldMapFrame, "TOP", 0, -6)
        legend:SetFrameStrata("HIGH")
        legend:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        legend:SetBackdropColor(0, 0, 0, 0.75)
        legend:SetBackdropBorderColor(0.9, 0.7, 0.3, 1)
        legend.text = legend:CreateFontString(nil, "OVERLAY")
        legend.text:SetFont("Interface\\AddOns\\Crafter\\Fonts\\cz.ttf", 11, "")
        legend.text:SetPoint("CENTER")
        legend:SetScript("OnClick", C.ClearMap)
    end
    for _, t in ipairs(pins) do t:Hide() end
    local itemID = CrafterDB and CrafterDB.mapItem
    legend:SetShown(itemID ~= nil)
    if not itemID then return end
    legend.text:SetText(("Crafter: %s  (klik = skrýt)"):format(CrafterDB.mapItemName or itemID))
    local mapID = WorldMapFrame:GetMapID()
    if not mapID then return end
    local w, h = canvas:GetSize()
    local scale = (WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.GetCanvasScale and WorldMapFrame.ScrollContainer:GetCanvasScale()) or 1
    local size = math.max(6, 14 / scale)
    local n = 0
    for _, p in ipairs(allPoints(itemID)) do
        local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, p[2], vec(p[2], p[3], p[4]), mapID)
        if ok and pos and pos.x >= 0 and pos.x <= 1 and pos.y >= 0 and pos.y <= 1 then
            n = n + 1
            local t = pins[n]
            if not t then
                t = pinFrame:CreateTexture(nil, "OVERLAY")
                t:SetTexture("Interface\\Buttons\\WHITE8x8")
                local mask = pinFrame:CreateMaskTexture()
                mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                mask:SetAllPoints(t)
                t:AddMaskTexture(mask)
                pins[n] = t
            end
            local col = C.SOURCE_COLOR[p[1]]
            t:SetVertexColor(col[1], col[2], col[3], 0.9)
            t:SetSize(size, size)
            t:ClearAllPoints()
            t:SetPoint("CENTER", pinFrame, "TOPLEFT", pos.x * w, -pos.y * h)
            t:Show()
        end
    end
end

-- mapa světa: překreslit při otevření a změně mapy
local hooked
local function hookMap()
    if hooked or not WorldMapFrame then return end
    hooked = true
    WorldMapFrame:HookScript("OnShow", function() C_Timer.After(0, C.RefreshMapPins) end)
    if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", function() C.RefreshMapPins() end) end
    if EventRegistry and EventRegistry.RegisterCallback then
        pcall(EventRegistry.RegisterCallback, EventRegistry, "MapCanvas.MapSet", function() C.RefreshMapPins() end, C)
    end
end

-------------------------------------------------------------------------------
-- Popisek předmětu kdekoli ve hře (taška, okno profese…): krátce, kde sehnat
-- (herní popisek neumí č/ř/ů – texty bez háčků)
-------------------------------------------------------------------------------
local ASCII = { ["á"]="a",["č"]="c",["ď"]="d",["é"]="e",["ě"]="e",["í"]="i",["ň"]="n",["ó"]="o",["ř"]="r",["š"]="s",["ť"]="t",["ú"]="u",["ů"]="u",["ý"]="y",["ž"]="z",
                ["Á"]="A",["Č"]="C",["Ď"]="D",["É"]="E",["Ě"]="E",["Í"]="I",["Ň"]="N",["Ó"]="O",["Ř"]="R",["Š"]="S",["Ť"]="T",["Ú"]="U",["Ů"]="U",["Ý"]="Y",["Ž"]="Z",
                ["…"]="..." }
local function ascii(s) return (s:gsub("[%z\1-\127\194-\244][\128-\191]*", function(ch) return ASCII[ch] or ch end)) end

local function addItemLines(tip, itemID)
    if not CrafterDB or CrafterDB.tooltip == false then return end
    local lines = C.SourceLines(itemID, 2)
    if not lines or #lines == 0 then return end
    tip:AddLine(" ")
    tip:AddLine("Crafter - kde sehnat:", 0.9, 0.7, 0.3)
    for i, l in ipairs(lines) do
        if i > 6 then tip:AddLine("  ... vice v nakupnim seznamu Crafteru", 0.6, 0.6, 0.6) break end
        local col = C.SOURCE_COLOR[l[1]]
        tip:AddLine(ascii(l[2]), col[1], col[2], col[3], true)
    end
    tip:Show()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if TooltipDataProcessor and Enum and Enum.TooltipDataType then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
                if tip ~= GameTooltip and tip ~= ItemRefTooltip then return end
                pcall(addItemLines, tip, data and data.id)
            end)
        end
        if WorldMapFrame then hookMap() end
    end
    C_Timer.After(2, function() pcall(calibrate) end)
end)
