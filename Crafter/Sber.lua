-- Crafter: sběr – Crafter si pamatuje, kde jsi co získal (jako Gatherer, ale jen tvoje nálezy)
--  * stahování (Skinning), těžba (Mining), bylinky (Herbalism), rybaření (Fishing)
--  * po sběru se uloží místo pod předmět, který jsi dostal (Light Leather, Copper Ore…)
--  * ikonka toho předmětu pak svítí na mapě zóny a na minimapě
local C = Crafter

local SBER_DEFAULTS = { worldmap = false, minimap = true, s = true, m = true, h = true, f = true }   -- mapa hry bez ikonek (je vlastní mapa Crafteru)
local GATHER_SPELLS = { ["Skinning"] = "s", ["Mining"] = "m", ["Herb Gathering"] = "h", ["Herbalism"] = "h", ["Fishing"] = "f" }
C.KIND_NAME = { s = "stahování", m = "těžba", h = "bylinky", f = "rybaření" }
local GRID = 250

local S = {}
C.Sber = S

-------------------------------------------------------------------------------
-- Uložené nálezy: CrafterDB.found[itemID] = { t = druh, p = {mapa,x,y…}, src = { [jméno zdroje] = true } }
-------------------------------------------------------------------------------
local grid, byMap, iconCache = {}, {}, {}

local function iconOf(itemID)
    if iconCache[itemID] then return iconCache[itemID] end
    local tex = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(itemID)
    iconCache[itemID] = tex or "Interface\\Icons\\INV_Misc_QuestionMark"
    return iconCache[itemID]
end

local function addPoint(map, x, y, itemID, kind)
    if not CrafterDB.sber[kind] then return end
    local p = { x, y, itemID, kind }
    grid[map] = grid[map] or {}
    local key = math.floor(x / GRID) .. ":" .. math.floor(y / GRID)
    grid[map][key] = grid[map][key] or {}
    table.insert(grid[map][key], p)
    byMap[map] = byMap[map] or {}
    table.insert(byMap[map], p)
end

function S.Rebuild()
    wipe(grid)
    wipe(byMap)
    for itemID, f in pairs(CrafterDB.found) do
        if type(itemID) == "number" then
            for i = 1, #f.p, 3 do addPoint(f.p[i], f.p[i + 1], f.p[i + 2], itemID, f.t) end
        end
    end
    S.RefreshWorld()
end

function S.FoundCount()
    local n = 0
    for id, f in pairs(CrafterDB.found) do if type(id) == "number" then n = n + #f.p / 3 end end
    return n
end

-- body nálezu předmětu: { mapa, x, y, … } nebo nil
function S.Points(itemID)
    local f = CrafterDB.found[itemID]
    return f and f.p, f
end

-------------------------------------------------------------------------------
-- Záznam: kouzlo sběru -> kořist -> uložit místo pod každý získaný předmět
-------------------------------------------------------------------------------
local pendingTarget, gather

local function spellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    return GetSpellInfo and GetSpellInfo(id)
end

local function store(itemID, kind, sourceName, map, x, y)
    local f = CrafterDB.found[itemID] or { t = kind, p = {}, src = {} }
    CrafterDB.found[itemID] = f
    if sourceName and sourceName ~= "" then f.src[sourceName] = true end
    for i = 1, #f.p, 3 do
        if f.p[i] == map and (f.p[i + 1] - x) ^ 2 + (f.p[i + 2] - y) ^ 2 < 625 then return end   -- do 25 yardů = stejné místo
    end
    table.insert(f.p, map)
    table.insert(f.p, x)
    table.insert(f.p, y)
    addPoint(map, x, y, itemID, kind)
end

local function onLoot()
    if not gather or GetTime() - gather.time > (gather.kind == "f" and 40 or 6) then gather = nil return end
    for i = 1, (GetNumLootItems and GetNumLootItems() or 0) do
        local link = GetLootSlotLink(i)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then store(id, gather.kind, gather.target, gather.map, gather.x, gather.y) end
    end
    gather = nil
    S.RefreshWorld()
    if C.MapChanged then C.MapChanged() end
end

-------------------------------------------------------------------------------
-- Převod na mapu přes rohy mapy zóny (bez volání API pro každý bod)
-------------------------------------------------------------------------------
local frameCache = {}
local function mapFrame(mapID)
    if frameCache[mapID] ~= nil then return frameCache[mapID] or nil end
    local ok, res = pcall(function()
        local cont, w00 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 0))
        local _, w10 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(1, 0))
        local _, w01 = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(0, 1))
        if not cont or not w00 or not w10 or not w01 then return nil end
        local ux, uy, vx, vy = w10.x - w00.x, w10.y - w00.y, w01.x - w00.x, w01.y - w00.y
        return { cont = cont, ox = w00.x, oy = w00.y, ux = ux, uy = uy, vx = vx, vy = vy,
                 uu = ux * ux + uy * uy, vv = vx * vx + vy * vy,
                 width = math.sqrt(ux * ux + uy * uy), height = math.sqrt(vx * vx + vy * vy) }
    end)
    frameCache[mapID] = (ok and res) or false
    return frameCache[mapID] or nil
end

local function toMap(f, map, x, y)
    local v = C.Vec(map, x, y)
    local dx, dy = v.x - f.ox, v.y - f.oy
    return (dx * f.ux + dy * f.uy) / f.uu, (dx * f.vx + dy * f.vy) / f.vv
end

-- nálezy na dané mapě zóny: { { u, v, itemID, druh } } (u, v = 0..1); onlyItem = jen jeden předmět
function S.OnMap(mapID, onlyItem)
    local out = {}
    local f = mapFrame(mapID)
    if not f or not byMap[f.cont] then return out end
    for _, pt in ipairs(byMap[f.cont]) do
        if not onlyItem or pt[3] == onlyItem then
            local u, v = toMap(f, f.cont, pt[1], pt[2])
            if u >= 0 and u <= 1 and v >= 0 and v <= 1 then out[#out + 1] = { u, v, pt[3], pt[4] } end
        end
    end
    return out
end

-- zóny, kde máš nějaké nálezy: { { mapID, jméno, počet } }
function S.ZonesWithFinds()
    local count, names = {}, {}
    for itemID, f in pairs(CrafterDB.found) do
        if type(itemID) == "number" then
            for i = 1, #f.p, 3 do
                local name, id = C.ZoneOf(f.p[i], f.p[i + 1], f.p[i + 2])
                if id then count[id] = (count[id] or 0) + 1; names[id] = name end
            end
        end
    end
    local out = {}
    for id, n in pairs(count) do out[#out + 1] = { id, names[id], n } end
    table.sort(out, function(a, b) return a[2] < b[2] end)
    return out
end

S.ItemName = function(id) return (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (CrafterDB.itemNames and CrafterDB.itemNames[id]) or ("#" .. id) end
S.IconOf = function(id) return iconOf(id) end

local function itemName(id)
    local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
    return n or (CrafterDB.itemNames and CrafterDB.itemNames[id]) or ("#" .. id)
end

local function pinTooltip(self)
    local f = CrafterDB.found[self.itemID]
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(itemName(self.itemID))
    local srcs = {}
    for name in pairs(f and f.src or {}) do srcs[#srcs + 1] = name end
    local kind = ({ s = "Skinning", m = "Mining", h = "Herbalism", f = "Fishing" })[self.kind] or ""
    GameTooltip:AddLine(kind .. (#srcs > 0 and (": " .. table.concat(srcs, ", ")) or ""), 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine("Crafter - tvuj nalez", 0.9, 0.7, 0.3)
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

-------------------------------------------------------------------------------
-- Mapa světa (mapa zóny)
-------------------------------------------------------------------------------
local worldPins, worldLayer = {}, nil
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
    if not info or (info.mapType or 0) < 3 then return end
    local f = mapFrame(mapID)
    if not f or not byMap[f.cont] then return end
    local w, h = canvas:GetSize()
    local scale = (WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.GetCanvasScale and WorldMapFrame.ScrollContainer:GetCanvasScale()) or 1
    local size = math.max(10, 18 / scale)
    local n = 0
    for _, pt in ipairs(byMap[f.cont]) do
        local u, v = toMap(f, f.cont, pt[1], pt[2])
        if u >= 0 and u <= 1 and v >= 0 and v <= 1 then
            n = n + 1
            local p = getPin(worldPins, n, worldLayer)
            p:SetSize(size, size)
            p.tex:SetTexture(iconOf(pt[3]))
            p.itemID, p.kind = pt[3], pt[4]
            p:ClearAllPoints()
            p:SetPoint("CENTER", worldLayer, "TOPLEFT", u * w, -v * h)
            p:Show()
        end
    end
end

-------------------------------------------------------------------------------
-- Minimapa
-------------------------------------------------------------------------------
local miniPins = {}
local OUTDOOR = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 }
local INDOOR = { [0] = 300, 240, 180, 120, 80, 50 }

local function updateMinimap()
    for _, p in ipairs(miniPins) do p:Hide() end
    if not CrafterDB or not CrafterDB.sber or not CrafterDB.sber.minimap or not Minimap:IsVisible() then return end
    local a, b, inst = C.PlayerWorld()
    if not a or not grid[inst] then return end
    local zone = C_Map.GetBestMapForUnit("player")
    local f = zone and mapFrame(zone)
    local pp = zone and C_Map.GetPlayerMapPosition(zone, "player")
    if not f or not pp or f.cont ~= inst then return end
    local zoom = Minimap:GetZoom() or 0
    local diameter = ((IsIndoors and IsIndoors()) and INDOOR or OUTDOOR)[zoom] or 466
    local radius = diameter / 2
    local px = Minimap:GetWidth() / diameter
    local rotate = GetCVar and GetCVar("rotateMinimap") == "1"
    local facing = 0
    if rotate then pcall(function() facing = GetPlayerFacing() or 0 end) end
    local cosF, sinF = math.cos(facing), math.sin(facing)
    local n = 0
    local cx, cy = math.floor(a / GRID), math.floor(b / GRID)
    local reach = math.ceil(radius / GRID) + 1
    for gx = cx - reach, cx + reach do
        for gy = cy - reach, cy + reach do
            for _, pt in ipairs(grid[inst][gx .. ":" .. gy] or {}) do
                local u, v = toMap(f, inst, pt[1], pt[2])
                local east, north = (u - pp.x) * f.width, -(v - pp.y) * f.height
                if east * east + north * north < (radius * 0.92) ^ 2 then
                    local sx, sy = east, north
                    if rotate then sx, sy = east * cosF + north * sinF, -east * sinF + north * cosF end
                    n = n + 1
                    local p = getPin(miniPins, n, Minimap)
                    p:SetSize(14, 14)
                    p:SetFrameLevel(Minimap:GetFrameLevel() + 5)
                    p.tex:SetTexture(iconOf(pt[3]))
                    p.itemID, p.kind = pt[3], pt[4]
                    p:ClearAllPoints()
                    p:SetPoint("CENTER", Minimap, "CENTER", sx * px, sy * px)
                    p:Show()
                    if n >= 60 then return end
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
-- Nastavení
-------------------------------------------------------------------------------
local win
function S.Toggle()
    if not win then
        local FONT = "Interface\\AddOns\\Crafter\\Fonts\\cz.ttf"
        win = CreateFrame("Frame", "CrafterSber", UIParent, "BackdropTemplate")
        win:SetSize(300, 260)
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
        title:SetText("Crafter – moje nálezy na mapě")
        local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", 2, 2)
        local checks = {}
        local OPTS = {
            { "worldmap", "Na mapě zóny" }, { "minimap", "Na minimapě" },
            { "s", "Kůže (stahování)" }, { "m", "Rudy a kameny (těžba)" }, { "h", "Bylinky" }, { "f", "Ryby (rybaření)" },
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
        win.info:SetWidth(276)
        win.info:SetJustifyH("LEFT")
        win:SetScript("OnShow", function()
            for k, cb in pairs(checks) do cb:SetChecked(CrafterDB.sber[k]) end
            win.info:SetText(("Uložených míst: %d. Ukládají se sama, když něco stáhneš, vytěžíš, natrháš nebo chytíš."):format(S.FoundCount()))
        end)
    end
    win:SetShown(not win:IsShown())
end

-------------------------------------------------------------------------------
-- Události
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED", "LOOT_OPENED", "LOOT_READY" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, event, unit, a2, a3)
    if event == "PLAYER_LOGIN" then
        CrafterDB.sber = CrafterDB.sber or {}
        for k, v in pairs(SBER_DEFAULTS) do if CrafterDB.sber[k] == nil then CrafterDB.sber[k] = v end end
        if not CrafterDB.sber.v2 then CrafterDB.sber.worldmap = false; CrafterDB.sber.v2 = true end
        CrafterDB.found = CrafterDB.found or {}
        for k in pairs(CrafterDB.found) do if type(k) ~= "number" then CrafterDB.found[k] = nil end end   -- starý formát (0.3.x)
        pcall(S.Rebuild)
        C_Timer.NewTicker(0.1, function() pcall(updateMinimap) end)
        if WorldMapFrame then
            WorldMapFrame:HookScript("OnShow", function() C_Timer.After(0, S.RefreshWorld) end)
            if WorldMapFrame.OnMapChanged then hooksecurefunc(WorldMapFrame, "OnMapChanged", function() S.RefreshWorld() end) end
        end
        return
    end
    if event == "UNIT_SPELLCAST_SENT" then
        if unit == "player" then pendingTarget = a2 end   -- cíl: jméno zvířete / ložiska / byliny
        return
    end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit ~= "player" then return end
        local kind = GATHER_SPELLS[spellName(a3) or ""]
        if kind then
            local x, y, map = C.PlayerWorld()
            if x then gather = { kind = kind, target = pendingTarget, time = GetTime(), map = map, x = math.floor(x + 0.5), y = math.floor(y + 0.5) } end
        end
        pendingTarget = nil
        return
    end
    if event == "LOOT_OPENED" or event == "LOOT_READY" then pcall(onLoot) end
end)
