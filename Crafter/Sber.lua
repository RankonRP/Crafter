-- Crafter: sběr – kde rostou byliny a kde jsou ložiska rud (jako Gatherer / GatherMate)
--  * místa z databáze (Crafter_Uzly v Zdroje.lua, celý klasický svět)
--  * vlastní nálezy: po vytěžení / natrhání se místo uloží (i nové oblasti Forever)
--  * ikonky na mapě světa (mapa zóny) a na minimapě
-- Poloha na mapě se počítá přes souřadnice zóny (C_Map) – funguje bez ohledu na pořadí os.
local C = Crafter

local SBER_DEFAULTS = { mining = true, herbs = true, worldmap = true, minimap = true, db = true, mine = true }
local GATHER_SPELLS = { ["Mining"] = "m", ["Herb Gathering"] = "h", ["Herbalism"] = "h" }
local DEFAULT_ICON = { m = "Interface\\Icons\\Trade_Mining", h = "Interface\\Icons\\Trade_Herbalism" }
local GRID = 250   -- velikost čtverce mřížky v yardech (rychlé hledání bodů kolem hráče)

local S = {}
C.Sber = S

-------------------------------------------------------------------------------
-- Body: z databáze + vlastní nálezy, v mřížce podle kontinentu
-------------------------------------------------------------------------------
local grid = {}   -- grid[mapa][klíč] = { {x, y, druh, ikona, jméno}, … }
local byMap = {}  -- byMap[mapa] = { body } (pro mapu světa)
local iconCache = {}

local function iconOf(itemID, kind)
    if not itemID or itemID == 0 then return DEFAULT_ICON[kind] end
    if iconCache[itemID] then return iconCache[itemID] end
    local tex = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
    iconCache[itemID] = tex or DEFAULT_ICON[kind]
    return iconCache[itemID]
end

local function addPoint(map, x, y, kind, itemID, name)
    local cfg = CrafterDB.sber
    if (kind == "m" and not cfg.mining) or (kind == "h" and not cfg.herbs) then return end
    local p = { x, y, kind, itemID, name }
    local g = grid[map] or {}
    grid[map] = g
    local key = math.floor(x / GRID) .. ":" .. math.floor(y / GRID)
    g[key] = g[key] or {}
    table.insert(g[key], p)
    byMap[map] = byMap[map] or {}
    table.insert(byMap[map], p)
end

function S.Rebuild()
    wipe(grid)
    wipe(byMap)
    local cfg = CrafterDB.sber
    if cfg.db and Crafter_Uzly then
        for _, u in pairs(Crafter_Uzly) do
            for i = 1, #u.p, 3 do
                local x, y = C.DbXY(u.p[i + 1], u.p[i + 2])
                addPoint(u.p[i], x, y, u.t, u.i, u.n)
            end
        end
    end
    if cfg.mine then
        for name, f in pairs(CrafterDB.found) do
            for i = 1, #f.p, 3 do addPoint(f.p[i], f.p[i + 1], f.p[i + 2], f.t, f.i, name) end
        end
    end
    S.RefreshWorld()
end

function S.FoundCount()
    local n = 0
    for _, f in pairs(CrafterDB.found) do n = n + #f.p / 3 end
    return n
end

-------------------------------------------------------------------------------
-- Záznam vlastních nálezů
-------------------------------------------------------------------------------
local pendingTarget, lastFound

local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and GetSpellInfo(id)
end

local function record(kind, name)
    local a, b, inst = C.PlayerWorld()
    if not a or not name or name == "" then return end

    local f = CrafterDB.found[name] or { t = kind, i = 0, p = {} }
    CrafterDB.found[name] = f
    -- stejné místo (do 20 yardů) neukládat dvakrát
    for i = 1, #f.p, 3 do
        if f.p[i] == inst and (f.p[i + 1] - a) ^ 2 + (f.p[i + 2] - b) ^ 2 < 400 then lastFound = f return end
    end
    table.insert(f.p, inst)
    table.insert(f.p, math.floor(a + 0.5))
    table.insert(f.p, math.floor(b + 0.5))
    lastFound = f
    if CrafterDB.sber.mine then addPoint(inst, math.floor(a + 0.5), math.floor(b + 0.5), kind, f.i, name) end
end

-------------------------------------------------------------------------------
-- Převod na mapu: rohy mapy ve světových souřadnicích -> poloha 0..1 bez volání API pro každý bod
-------------------------------------------------------------------------------
local frameCache = {}
local function mapFrame(mapID)
    if frameCache[mapID] ~= nil then return frameCache[mapID] or nil end
    local ok, res = pcall(function()
        local cont, w00 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
        local _, w10 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 0))
        local _, w01 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 1))
        if not cont or not w00 or not w10 or not w01 then return nil end
        local ux, uy = w10.x - w00.x, w10.y - w00.y
        local vx, vy = w01.x - w00.x, w01.y - w00.y
        return { cont = cont, ox = w00.x, oy = w00.y, ux = ux, uy = uy, vx = vx, vy = vy,
                 uu = ux * ux + uy * uy, vv = vx * vx + vy * vy,
                 width = math.sqrt(ux * ux + uy * uy), height = math.sqrt(vx * vx + vy * vy) }
    end)
    frameCache[mapID] = (ok and res) or false
    return frameCache[mapID] or nil
end

-- světový bod (naše pořadí x, y) -> poloha na mapě 0..1
local function toMap(f, map, x, y)
    local v = C.Vec(map, x, y)
    local dx, dy = v.x - f.ox, v.y - f.oy
    return (dx * f.ux + dy * f.uy) / f.uu, (dx * f.vx + dy * f.vy) / f.vv
end

-------------------------------------------------------------------------------
-- Mapa světa: ikonky na mapě zóny
-------------------------------------------------------------------------------
local worldPins, worldLayer = {}, nil

local function pinTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.name or "?")
    GameTooltip:AddLine(self.kind == "m" and "Loziste rudy" or "Bylina", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end

local function getPin(pool, i, parent)
    local p = pool[i]
    if p then return p end
    p = CreateFrame("Frame", nil, parent)
    p.tex = p:CreateTexture(nil, "OVERLAY")
    p.tex:SetAllPoints()
    p.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    p:EnableMouse(true)
    p:SetScript("OnEnter", pinTooltip)
    p:SetScript("OnLeave", GameTooltip_Hide)
    pool[i] = p
    return p
end

function S.RefreshWorld()
    if not WorldMapFrame or not WorldMapFrame:IsShown() or not WorldMapFrame.GetCanvas then return end
    local canvas = WorldMapFrame:GetCanvas()
    if not worldLayer then
        worldLayer = CreateFrame("Frame", nil, canvas)
        worldLayer:SetAllPoints()
        worldLayer:SetFrameLevel(canvas:GetFrameLevel() + 15)
    end
    for _, p in ipairs(worldPins) do p:Hide() end
    if not CrafterDB.sber.worldmap then return end
    local mapID = WorldMapFrame:GetMapID()
    local info = mapID and C_Map.GetMapInfo(mapID)
    if not info or (info.mapType or 0) < 3 then return end   -- jen mapa zóny (na kontinentu by to byla změť)
    local f = mapFrame(mapID)
    if not f or not byMap[f.cont] then return end
    local w, h = canvas:GetSize()
    local scale = (WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.GetCanvasScale and WorldMapFrame.ScrollContainer:GetCanvasScale()) or 1
    local size = math.max(8, 16 / scale)
    local n = 0
    for _, pt in ipairs(byMap[f.cont]) do
        local u, v = toMap(f, f.cont, pt[1], pt[2])
        if u >= 0 and u <= 1 and v >= 0 and v <= 1 then
            n = n + 1
            local p = getPin(worldPins, n, worldLayer)
            p:SetSize(size, size)
            p.tex:SetTexture(iconOf(pt[4], pt[3]))
            p.name, p.kind = pt[5], pt[3]
            p:ClearAllPoints()
            p:SetPoint("CENTER", worldLayer, "TOPLEFT", u * w, -v * h)
            p:Show()
            if n >= 1500 then break end
        end
    end
end

-------------------------------------------------------------------------------
-- Minimapa: ikonky v okolí hráče
-------------------------------------------------------------------------------
local miniPins = {}
-- průměr minimapy v yardech podle přiblížení (venku / uvnitř), jako v HereBeDragons
local OUTDOOR = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }

local function updateMinimap()
    for _, p in ipairs(miniPins) do p:Hide() end
    if not CrafterDB or not CrafterDB.sber.minimap or not Minimap:IsVisible() then return end
    local a, b, inst = C.PlayerWorld()
    if not a or not grid[inst] then return end
    local zone = C_Map.GetBestMapForUnit("player")
    local f = zone and mapFrame(zone)
    local pp = zone and C_Map.GetPlayerMapPosition(zone, "player")
    if not f or not pp or f.cont ~= inst then return end

    local zoom = Minimap:GetZoom() or 0
    local diameter = ((IsIndoors and IsIndoors()) and INDOOR or OUTDOOR)[zoom] or 466
    local radius = diameter / 2
    local px = Minimap:GetWidth() / diameter   -- bodů obrazovky na yard
    local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
    local facing = 0
    if rotate then pcall(function() facing = GetPlayerFacing() or 0 end) end
    local cosF, sinF = math.cos(facing), math.sin(facing)

    local n = 0
    local cx, cy = math.floor(a / GRID), math.floor(b / GRID)
    local reach = math.ceil(radius / GRID) + 1
    for gx = cx - reach, cx + reach do
        for gy = cy - reach, cy + reach do
            local cell = grid[inst][gx .. ":" .. gy]
            if cell then
                for _, pt in ipairs(cell) do
                    local u, v = toMap(f, inst, pt[1], pt[2])
                    local east = (u - pp.x) * f.width
                    local north = -(v - pp.y) * f.height
                    if east * east + north * north < (radius * 0.92) ^ 2 then
                        local sx, sy = east, north
                        if rotate then
                            sx = east * cosF + north * sinF
                            sy = -east * sinF + north * cosF
                        end
                        n = n + 1
                        local p = getPin(miniPins, n, Minimap)
                        p:SetSize(12, 12)
                        p:SetFrameLevel(Minimap:GetFrameLevel() + 5)
                        p.tex:SetTexture(iconOf(pt[4], pt[3]))
                        p.name, p.kind = pt[5], pt[3]
                        p:ClearAllPoints()
                        p:SetPoint("CENTER", Minimap, "CENTER", sx * px, sy * px)
                        p:Show()
                        if n >= 60 then return end
                    end
                end
            end
        end
    end
end

-- /crafter ladit: co addon vidí (pro hledání chyb v mapě a minimapě)
function S.Debug()
    local ok, ua, ub, _, uinst = pcall(UnitPosition, "player")
    C.Msg(("UnitPosition: %s %s %s %s"):format(tostring(ok), tostring(ua), tostring(ub), tostring(uinst)))
    local a, b, inst, src = C.PlayerWorld()
    C.Msg(("poloha hrace: %s, %s kontinent %s (zdroj %s), osy %s"):format(tostring(a), tostring(b), tostring(inst), tostring(src), tostring(CrafterDB.axis)))
    local zone = C_Map.GetBestMapForUnit("player")
    local info = zone and C_Map.GetMapInfo(zone)
    local f = zone and mapFrame(zone)
    C.Msg(("zona: %s %s typ %s | ramec mapy: %s"):format(tostring(zone), info and info.name or "?", info and tostring(info.mapType) or "?",
        f and ("kontinent " .. tostring(f.cont) .. ", " .. math.floor(f.width) .. "x" .. math.floor(f.height) .. " yd") or "NENI"))
    local keys = {}
    for k, list in pairs(byMap) do keys[#keys + 1] = k .. "=" .. #list end
    C.Msg("body podle kontinentu: " .. (#keys > 0 and table.concat(keys, ", ") or "zadne"))
    if f and byMap[f.cont] then
        local inZone, best, bestD = 0, nil, nil
        local pp = C_Map.GetPlayerMapPosition(zone, "player")
        for _, pt in ipairs(byMap[f.cont]) do
            local u, v = toMap(f, f.cont, pt[1], pt[2])
            if u >= 0 and u <= 1 and v >= 0 and v <= 1 then
                inZone = inZone + 1
                if pp then
                    local d = (u - pp.x) ^ 2 + (v - pp.y) ^ 2
                    if not bestD or d < bestD then best, bestD = { pt[5], u, v }, d end
                end
            end
        end
        C.Msg(("v teto zone bodu: %d%s"):format(inZone, best and ("; nejblizsi " .. best[1] .. (" (%.0f, %.0f)"):format(best[2] * 100, best[3] * 100)) or ""))
    end
end

-------------------------------------------------------------------------------
-- Okno nastavení sběru
-------------------------------------------------------------------------------
local win
function S.Toggle()
    if not win then
        local FONT = "Interface\\AddOns\\Crafter\\Fonts\\cz.ttf"
        win = CreateFrame("Frame", "CrafterSber", UIParent, "BackdropTemplate")
        win:SetSize(290, 270)
        win:SetPoint("CENTER", -200, 0)
        win:SetFrameStrata("HIGH")
        win:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        win:SetBackdropColor(0.03, 0.03, 0.03, 0.95)
        win:SetBackdropBorderColor(0.9, 0.7, 0.3, 1)
        win:EnableMouse(true)
        win:SetMovable(true)
        win:RegisterForDrag("LeftButton")
        win:SetScript("OnDragStart", win.StartMoving)
        win:SetScript("OnDragStop", win.StopMovingOrSizing)
        tinsert(UISpecialFrames, "CrafterSber")
        local title = win:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT, 14, "")
        title:SetTextColor(0.9, 0.7, 0.3)
        title:SetPoint("TOPLEFT", 10, -9)
        title:SetText("Crafter – sběr (rudy a byliny)")
        local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        local checks = {}
        local OPTS = {
            { "mining", "Ukazovat rudy" }, { "herbs", "Ukazovat byliny" },
            { "worldmap", "Na mapě světa (mapa zóny)" }, { "minimap", "Na minimapě" },
            { "db", "Místa z databáze (celý svět)" }, { "mine", "Moje nálezy" },
        }
        for i, o in ipairs(OPTS) do
            local cb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
            cb:SetSize(24, 24)
            cb:SetPoint("TOPLEFT", 10, -30 - (i - 1) * 26)
            cb:SetHitRectInsets(0, -220, 0, 0)
            if cb.Text then cb.Text:SetText("") end
            local fs = win:CreateFontString(nil, "OVERLAY")
            fs:SetFont(FONT, 12, "")
            fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
            fs:SetText(o[2])
            cb:SetScript("OnClick", function(self)
                CrafterDB.sber[o[1]] = self:GetChecked() and true or false
                S.Rebuild()
                updateMinimap()
            end)
            checks[o[1]] = cb
        end
        win.info = win:CreateFontString(nil, "OVERLAY")
        win.info:SetFont(FONT, 11, "")
        win.info:SetTextColor(0.75, 0.75, 0.75)
        win.info:SetPoint("BOTTOMLEFT", 12, 12)
        win.info:SetWidth(266)
        win.info:SetJustifyH("LEFT")
        win:SetScript("OnShow", function()
            for k, cb in pairs(checks) do cb:SetChecked(CrafterDB.sber[k]) end
            win.info:SetText(("Tvých nálezů: %d. Ukládají se samy, když něco vytěžíš nebo natrháš – i v nových oblastech Forever."):format(S.FoundCount()))
        end)
    end
    win:SetShown(not win:IsShown())
end

-------------------------------------------------------------------------------
-- Události
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "LOOT_OPENED" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event, unit, a2, a3, a4)
    if event == "PLAYER_LOGIN" then
        CrafterDB.sber = CrafterDB.sber or {}
        for k, v in pairs(SBER_DEFAULTS) do if CrafterDB.sber[k] == nil then CrafterDB.sber[k] = v end end
        CrafterDB.found = CrafterDB.found or {}
        S.Rebuild()
        C_Timer.NewTicker(0.1, function() pcall(updateMinimap) end)
        if WorldMapFrame then
            WorldMapFrame:HookScript("OnShow", function() C_Timer.After(0, S.RefreshWorld) end)
            if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", function() S.RefreshWorld() end) end
        end
        return
    end
    if event == "UNIT_SPELLCAST_SENT" then
        -- (unit, cíl – jméno ložiska / byliny, castGUID, spellID)
        if unit == "player" then pendingTarget = a2 end
        return
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit ~= "player" then return end
        local kind = GATHER_SPELLS[spellName(a3) or ""]
        if kind and pendingTarget then record(kind, pendingTarget) end
        pendingTarget = nil
        return
    end
    if event == "LOOT_OPENED" and lastFound and (lastFound.i or 0) == 0 then
        -- ikonka nálezu = první předmět z kořisti
        local link = GetLootSlotLink and GetLootSlotLink(1)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then lastFound.i = id end
        lastFound = nil
    end
end)
