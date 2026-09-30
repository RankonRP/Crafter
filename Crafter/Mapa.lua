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

-- Poloha hráče ve světových souřadnicích (x, y, kontinent). Forever může UnitPosition
-- addonům nedávat -> náhradou poloha na mapě zóny převedená zpět na světovou.
function C.PlayerWorld()
    local ok, a, b, _, inst = pcall(UnitPosition, "player")
    if ok and a and b and not (issecretvalue and (issecretvalue(a) or issecretvalue(b))) then return a, b, inst, "unit" end
    local zone = C_Map.GetBestMapForUnit("player")
    local pp = zone and C_Map.GetPlayerMapPosition(zone, "player")
    if not pp then return nil end
    local cont, w = C_Map.GetWorldPosFromMapPos(zone, pp)
    if not cont or not w then return nil end
    if CrafterDB and CrafterDB.axis == "ba" then return w.y, w.x, cont, "map" end
    return w.x, w.y, cont, "map"
end

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
-- Jak surovinu získat – jednoduchá rada pro okno receptu
-- vrací { { druh, text, body } }: druh "mine" (tvůj nález), "v" koupit, "s" stahování,
-- "m" těžba, "h" bylinky, "d" padá z mobů, "c" výroba, "?" nevím
-------------------------------------------------------------------------------
local function nearestOf(ptsList)
    -- ptsList = { { jméno, body{mapa,x,y…} } } -> jméno, zóna nejbližšího místa (nebo prvního)
    local a, b, inst = C.PlayerWorld()
    local best, bestD, bestName
    for _, e in ipairs(ptsList) do
        local pts = e[2]
        for i = 1, #pts, 3 do
            local x, y = C.DbXY(pts[i + 1], pts[i + 2])
            local d = (a and pts[i] == inst) and ((x - a) ^ 2 + (y - b) ^ 2) or 1e12
            if not bestD or d < bestD then best, bestD, bestName = { pts[i], x, y }, d, e[1] end
        end
    end
    if not best then return nil end
    local zone = C.ZoneOf(best[1], best[2], best[3])
    return bestName, zone, best
end

function C.HowToGet(itemID)
    local out = {}
    local mine, f
    if C.Sber then mine, f = C.Sber.Points(itemID) end
    if mine and #mine > 0 then
        local zones, order = {}, {}
        for i = 1, #mine, 3 do
            local z = C.ZoneOf(mine[i], mine[i + 1], mine[i + 2]) or "?"
            if not zones[z] then zones[z] = 0; order[#order + 1] = z end
            zones[z] = zones[z] + 1
        end
        local parts = {}
        for i = 1, math.min(3, #order) do parts[i] = ("%s (%d×)"):format(order[i], zones[order[i]]) end
        out[#out + 1] = { "mine", ("Tvoje místa (%s): %s"):format(C.KIND_NAME[f.t] or "sběr", table.concat(parts, ", ")) }
    end
    local z = Crafter_Zdroje and Crafter_Zdroje[itemID]
    if z then
        if z.v then
            local list = {}
            for _, id in ipairs(z.v) do local n = Crafter_NPC[id]; if n then list[#list + 1] = { n.n, n.p } end end
            local name, zone = nearestOf(list)
            out[#out + 1] = { "v", ("Kup u obchodníka – nejblíž %s (%s)%s"):format(name or "?", zone or "?", z.price and (", " .. C.Money(z.price) .. "/ks") or "") }
        end
        if z.s then
            local list = {}
            for _, id in ipairs(z.s) do local n = Crafter_NPC[id]; if n then list[#list + 1] = { n.n, n.p } end end
            local name, zone = nearestOf(list)
            out[#out + 1] = { "s", ("Získáš stahováním (Skinning) – třeba %s (%s)"):format(name or "?", zone or "?") }
        end
        if z.g then
            local ore, herb = {}, {}
            for _, g in ipairs(z.g) do
                local o = Crafter_OBJ[g[1]]
                if o then
                    if o.n:find("Vein") or o.n:find("Deposit") then ore[#ore + 1] = { o.n, o.p } else herb[#herb + 1] = { o.n, o.p } end
                end
            end
            if #ore > 0 then
                local name, zone = nearestOf(ore)
                out[#out + 1] = { "m", ("Vytěžíš (Mining) z %s – třeba v %s"):format(name or "?", zone or "?") }
            end
            if #herb > 0 then
                local name, zone = nearestOf(herb)
                out[#out + 1] = { "h", ("Natrháš (Herbalism): %s – třeba v %s"):format(name or "?", zone or "?") }
            end
        end
        if z.d and #out == 0 then
            local list = {}
            for _, d in ipairs(z.d) do local n = Crafter_NPC[d[1]]; if n then list[#list + 1] = { n.n, n.p } end end
            local name, zone = nearestOf(list)
            out[#out + 1] = { "d", ("Padá z mobů – třeba %s (%s)"):format(name or "?", zone or "?") }
        end
        if z.c then out[#out + 1] = { "c", "Vyrobíš: " .. table.concat(z.c, ", ") } end
    end
    if #out == 0 then out[1] = { "?", "Nevím, kde se sežene (nová věc ve Forever?). Až ji získáš sběrem, Crafter si místo zapamatuje." } end
    return out
end

C.HOW_COLOR = { mine = { 0.4, 1, 0.8 }, v = { 1, 0.82, 0.2 }, s = { 0.85, 0.55, 0.25 }, m = { 0.75, 0.75, 0.85 },
                h = { 0.3, 1, 0.3 }, d = { 1, 0.4, 0.4 }, c = { 0.6, 0.8, 1 }, ["?"] = { 0.6, 0.6, 0.6 } }

-------------------------------------------------------------------------------
-- Značka na mapě: nejdřív k tvému nálezu, jinak k nejbližšímu obchodníkovi / místu z databáze
-------------------------------------------------------------------------------
function C.ShowOnMap(itemID, name)
    local candidates = {}
    local mine = C.Sber and C.Sber.Points(itemID)
    if mine and #mine > 0 then
        candidates[1] = { "tvuj nalez", mine, true }
    else
        for _, p in ipairs(allPoints(itemID)) do
            candidates[#candidates + 1] = { p[5], { p[2], p[3], p[4] }, true }
        end
    end
    if #candidates == 0 then C.Msg("pro tuhle surovinu nemam zadne misto.") return end
    local list = {}
    for _, c in ipairs(candidates) do list[#list + 1] = { c[1], c[2] } end
    -- nálezy jsou v souřadnicích hry, databáze po C.DbXY – nearestOf je volá přes DbXY, u nálezů to nevadí, dokud osy nejsou prohozené
    local who, zoneName, best = nearestOf(list)
    if not best then return end
    local _, zoneID, zx, zy = C.ZoneOf(best[1], best[2], best[3])
    C.lastTarget = { zoneID = zoneID, x = zx, y = zy, label = who, item = name }
    if zoneID and zx and C_Map.SetUserWaypoint and UiMapPoint then
        pcall(function()
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(zoneID, zx, zy))
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
        end)
        C.Msg(("znacka na mape: %s - %s (%s %.0f, %.0f)"):format(name or "?", who or "?", zoneName or "?", zx * 100, zy * 100))
    else
        C.Msg(("nejblizsi misto: %s (%s)"):format(who or "?", zoneName or "?"))
    end
end

function C.ClearMap()
    if C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
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
    end
    C_Timer.After(2, function() pcall(calibrate) end)
end)
