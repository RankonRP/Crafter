-- Crafter: jedno okno se třemi záložkami
--   1. Na skill  – co teď vyrobit, aby rostla dovednost (a kolik kusů)
--   2. Co chybí  – suroviny, které chybí (i přepočet bar -> ruda) a kde je sehnat; nákup u obchodníka
--   3. Mapa      – tvoje nálezy (kůže, rudy, byliny, ryby); mapa je z MapaOkno.lua vložená sem
local C = Crafter
local FONT = "Interface\\AddOns\\Crafter\\Fonts\\cz.ttf"

local fontNormal = CreateFont("CrafterFontNormal")
fontNormal:SetFont(FONT, 12, "")
local fontSmall = CreateFont("CrafterFontSmall")
fontSmall:SetFont(FONT, 10, "")
local fontTitle = CreateFont("CrafterFontTitle")
fontTitle:SetFont(FONT, 14, "")
local fontBig = CreateFont("CrafterFontBig")
fontBig:SetFont(FONT, 15, "")
local fontButton = CreateFont("CrafterFontButton")
fontButton:SetFont(FONT, 12, "")
fontButton:SetTextColor(1, 0.82, 0)
local fontButtonHl = CreateFont("CrafterFontButtonHl")
fontButtonHl:SetFont(FONT, 12, "")
fontButtonHl:SetTextColor(1, 1, 1)

local BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }
local ACCENT = { 0.9, 0.7, 0.3 }
local W, H = 400, 570   -- velikost okna

local function text(parent, font, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(font)
    fs:SetTextColor(r or 1, g or 1, b or 1)
    fs:SetJustifyH("LEFT")
    return fs
end

local function button(parent, w, label)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 24)
    b:SetNormalFontObject(fontButton)
    b:SetHighlightFontObject(fontButtonHl)
    b:SetDisabledFontObject(fontButton)
    b:SetText(label)
    return b
end

local function colorText(r, g, b, s) return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, s) end

-- vlastní popisek s českým písmem
local tip = CreateFrame("GameTooltip", "CrafterTooltip", UIParent, "GameTooltipTemplate")
local function showTip(owner, lines)
    tip:SetOwner(owner, "ANCHOR_RIGHT")
    tip:ClearLines()
    for i, l in ipairs(lines) do tip:AddLine(l[1], l[2] or 1, l[3] or 1, l[4] or 1, i > 1) end
    for i = 1, tip:NumLines() do
        local fs = _G["CrafterTooltipTextLeft" .. i]
        if fs then fs:SetFont(FONT, i == 1 and 13 or 11, "") end
    end
    tip:Show()
end
local function hideTip() tip:Hide() end

-- posuvný seznam uvnitř stránky
local function scrollArea(parent, top, bottom)
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 0, top)
    sf:SetPoint("BOTTOMRIGHT", -22, bottom)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(W - 40, 10)
    sf:SetScrollChild(content)
    return sf, content
end

local main, pages, tabs, current = nil, {}, {}, 1
local provider
local refreshSkill, refreshNeed

-------------------------------------------------------------------------------
-- Hlavní okno
-------------------------------------------------------------------------------
local function savePos()
    main:StopMovingOrSizing()
    local p, _, _, x, y = main:GetPoint()
    CrafterDB.mainPos = { p, math.floor(x + 0.5), math.floor(y + 0.5) }
end

function C.ShowMainTab(n)
    if not main then return end
    current = n
    for i, p in ipairs(pages) do p:SetShown(i == n) end
    for i, t in ipairs(tabs) do
        local on = i == n
        t.line:SetShown(on)
        t.label:SetTextColor(on and 1 or 0.65, on and 0.85 or 0.65, on and 0.3 or 0.65)
    end
    main:Show()
    main:Raise()
    if n == 1 then refreshSkill() elseif n == 2 then refreshNeed() else C.MapTabShown() end
end

local function createMain()
    main = CreateFrame("Frame", "CrafterMain", UIParent, "BackdropTemplate")
    main:SetSize(W, H)
    main:SetBackdrop(BACKDROP)
    main:SetBackdropColor(0.03, 0.03, 0.03, 0.96)
    main:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    main:SetFrameStrata("HIGH")
    main:SetToplevel(true)
    main:EnableMouse(true)
    main:SetMovable(true)
    main:SetClampedToScreen(true)
    main:RegisterForDrag("LeftButton")
    main:SetScript("OnDragStart", main.StartMoving)
    main:SetScript("OnDragStop", savePos)
    main:Hide()
    tinsert(UISpecialFrames, "CrafterMain")
    local pos = CrafterDB.mainPos
    if pos then main:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else main:SetPoint("CENTER", 200, 0) end

    main.title = text(main, fontTitle, ACCENT[1], ACCENT[2], ACCENT[3])
    main.title:SetPoint("TOPLEFT", 12, -10)
    main.skill = text(main, fontNormal, 0.8, 0.8, 0.8)
    main.skill:SetPoint("TOPRIGHT", -34, -11)
    main.skill:SetJustifyH("RIGHT")
    local close = CreateFrame("Button", nil, main, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    -- záložky
    local LABELS = { "Na skill", "Co chybí", "Mapa" }
    local tw = (W - 16) / 3
    for i, label in ipairs(LABELS) do
        local t = CreateFrame("Button", nil, main)
        t:SetSize(tw, 26)
        t:SetPoint("TOPLEFT", 8 + (i - 1) * tw, -32)
        t.label = text(t, fontBig)
        t.label:SetPoint("CENTER")
        t.label:SetText(label)
        t.line = t:CreateTexture(nil, "ARTWORK")
        t.line:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
        t.line:SetPoint("BOTTOMLEFT", 6, 0)
        t.line:SetPoint("BOTTOMRIGHT", -6, 0)
        t.line:SetHeight(2)
        local hl = t:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.05)
        t:SetScript("OnClick", function() C.ShowMainTab(i) end)
        tabs[i] = t
    end
    local sep = main:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(1, 1, 1, 0.12)
    sep:SetPoint("TOPLEFT", 8, -58)
    sep:SetPoint("TOPRIGHT", -8, -58)
    sep:SetHeight(1)

    for i = 1, 3 do
        local p = CreateFrame("Frame", nil, main)
        p:SetPoint("TOPLEFT", 10, -64)
        p:SetPoint("BOTTOMRIGHT", -10, 10)
        p:Hide()
        pages[i] = p
    end
end

local function updateHeader()
    provider = C.Provider()
    if provider then
        local name, rank, max = provider.line()
        main.title:SetText("Crafter – " .. (name or "?"))
        rank, max = tonumber(rank), tonumber(max)
        if rank and max then
            main.skill:SetText(max > rank and ("%d / %d · zbývá %d"):format(rank, max, max - rank) or ("%d / %d · max"):format(rank, max))
        else
            main.skill:SetText("")
        end
        main.rank, main.max = rank, max
    else
        main.title:SetText("Crafter")
        main.skill:SetText("")
        main.rank, main.max = nil, nil
    end
end

-------------------------------------------------------------------------------
-- 1. Na skill
-------------------------------------------------------------------------------
local skill = {}       -- prvky stránky
local focus            -- recept v kartě doporučení

-- kolik kusů je potřeba na zbývající body (oranžový = bod za kus)
local function piecesToMax(r)
    if not main.rank or not main.max then return 1 end
    local left = main.max - main.rank
    if left <= 0 then return 1 end
    if r.diff == "medium" then left = math.ceil(left * 1.5) elseif r.diff == "easy" then left = left * 3 end
    return math.max(1, math.min(999, left))
end

-- recepty, které zvednou skill, seřazené: jistota bodu, pak co hned vyrobíš, pak cena
local function skillRecipes()
    local out = {}
    if not provider then return out end
    for _, r in ipairs(provider.recipes()) do
        if r.diff ~= "trivial" then out[#out + 1] = r end
    end
    table.sort(out, function(a, b)
        local da, db = (C.DIFF[a.diff] or C.DIFF.easy).order, (C.DIFF[b.diff] or C.DIFF.easy).order
        if da ~= db then return da < db end
        if (a.numAvailable > 0) ~= (b.numAvailable > 0) then return a.numAvailable > 0 end
        local ca = C.RecipeCost(a)
        local cb = C.RecipeCost(b)
        if ca ~= cb then return ca < cb end
        return a.name < b.name
    end)
    return out
end

local function setPlan(r, qty)
    for i = #CrafterDB.list, 1, -1 do
        if CrafterDB.list[i].name == r.name then table.remove(CrafterDB.list, i) end
    end
    C.AddToList(r, qty)
end

local function createSkillPage(p)
    skill.empty = text(p, fontNormal, 0.75, 0.75, 0.75)
    skill.empty:SetPoint("TOPLEFT", 4, -10)
    skill.empty:SetWidth(W - 40)
    skill.empty:SetText("Otevři okno profese (třeba Leatherworking) a Crafter ti poradí, co vyrobit, aby ti rostla dovednost.")

    local lbl = text(p, fontSmall, 0.7, 0.7, 0.7)
    lbl:SetPoint("TOPLEFT", 2, -4)
    lbl:SetText("Doporučuju teď vyrobit")
    skill.lbl = lbl

    local card = CreateFrame("Frame", nil, p, "BackdropTemplate")
    card:SetPoint("TOPLEFT", 0, -20)
    card:SetPoint("TOPRIGHT", 0, -20)
    card:SetHeight(112)
    card:SetBackdrop(BACKDROP)
    card:SetBackdropColor(1, 1, 1, 0.04)
    card:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.7)
    skill.card = card
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(36, 36)
    card.icon:SetPoint("TOPLEFT", 10, -10)
    card.name = text(card, fontBig)
    card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -1)
    card.name:SetPoint("RIGHT", -10, 0)
    card.name:SetWordWrap(false)
    card.chance = text(card, fontNormal)
    card.chance:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
    card.info = text(card, fontSmall, 0.8, 0.8, 0.8)
    card.info:SetPoint("TOPLEFT", card.icon, "BOTTOMLEFT", 0, -8)
    card.info:SetPoint("RIGHT", -10, 0)
    card.pick = button(card, (W - 60) / 2, "Vybrat v profesi")
    card.pick:SetPoint("BOTTOMLEFT", 10, 10)
    card.pick:SetScript("OnClick", function() if focus and provider then provider.select(focus) end end)
    card.fill = button(card, (W - 60) / 2, "Doplnit suroviny")
    card.fill:SetPoint("BOTTOMRIGHT", -10, 10)
    card.fill:SetScript("OnClick", function()
        if not focus then return end
        setPlan(focus, piecesToMax(focus))
        C.ShowMainTab(2)
    end)
    card.fill:SetScript("OnEnter", function(self)
        showTip(self, { { "Doplnit suroviny" }, { "Naplánuje tolik kusů, kolik je potřeba do maxima dovednosti, a v záložce Co chybí ukáže, co ti chybí a kde to sehnat.", 0.8, 0.8, 0.8 } })
    end)
    card.fill:SetScript("OnLeave", hideTip)

    local more = text(p, fontSmall, 0.7, 0.7, 0.7)
    more:SetPoint("TOPLEFT", 2, -142)
    more:SetText("Další recepty, které zvednou skill (klik = doporučit a vybrat)")
    skill.more = more
    skill.sf, skill.content = scrollArea(p, -160, 0)
    skill.rows = {}
end

function refreshSkill()
    if not main or current ~= 1 then return end
    updateHeader()
    local list = skillRecipes()
    local has = provider ~= nil and #list > 0
    skill.empty:SetShown(not has)
    skill.card:SetShown(has)
    skill.lbl:SetShown(has)
    skill.more:SetShown(has)
    skill.sf:SetShown(has)
    if provider and #list == 0 then
        skill.empty:SetText(main.rank and main.max and main.rank >= main.max
            and "Máš maximum dovednosti. U trenéra se nauč další úroveň profese."
            or "Žádný recept, který znáš, ti teď dovednost nezvedne. U trenéra se nauč nové recepty.")
    elseif not provider then
        skill.empty:SetText("Otevři okno profese (třeba Leatherworking) a Crafter ti poradí, co vyrobit, aby ti rostla dovednost.")
    end
    if not has then return end

    -- doporučení: vybraný, jinak první v pořadí
    local found
    if focus then for _, r in ipairs(list) do if r.name == focus.name then found = r end end end
    focus = found or list[1]
    local d = C.DIFF[focus.diff] or C.DIFF.easy
    local card = skill.card
    card.icon:SetTexture(focus.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    card.name:SetText(focus.name)
    card.name:SetTextColor(d.color[1], d.color[2], d.color[3])
    card.chance:SetText(d.label)
    card.chance:SetTextColor(d.color[1], d.color[2], d.color[3])
    local need = piecesToMax(focus)
    local left = (main.rank and main.max) and (main.max - main.rank) or 0
    card.info:SetText((focus.numAvailable > 0 and ("Máš suroviny na %d ks"):format(focus.numAvailable) or "Suroviny ti chybí")
        .. (left > 0 and ("  ·  na +%d bodů potřebuješ asi %d ks"):format(left, need) or ""))
    card.fill:SetText(("Doplnit suroviny (%d×)"):format(need))

    local n = 0
    for _, r in ipairs(list) do
        if r ~= focus then
            n = n + 1
            local row = skill.rows[n]
            if not row then
                row = CreateFrame("Button", nil, skill.content)
                row:SetHeight(24)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(20, 20)
                row.icon:SetPoint("LEFT", 2, 0)
                row.name = text(row, fontNormal)
                row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.name:SetPoint("RIGHT", -110, 0)
                row.name:SetWordWrap(false)
                row.right = text(row, fontSmall, 0.75, 0.75, 0.75)
                row.right:SetPoint("RIGHT", -4, 0)
                row.right:SetJustifyH("RIGHT")
                local hl = row:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.06)
                row:SetScript("OnClick", function(self)
                    focus = self.recipe
                    if provider then provider.select(self.recipe) end
                    refreshSkill()
                end)
                skill.rows[n] = row
            end
            local rd = C.DIFF[r.diff] or C.DIFF.easy
            row.recipe = r
            row.icon:SetTexture(r.icon)
            row.name:SetText(r.name)
            row.name:SetTextColor(rd.color[1], rd.color[2], rd.color[3])
            row.right:SetText(rd.label .. (r.numAvailable > 0 and ("  ·  %d×"):format(r.numAvailable) or ""))
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(n - 1) * 26)
            row:SetPoint("RIGHT", skill.content, "RIGHT", 0, 0)
            row:Show()
        end
    end
    for i = n + 1, #skill.rows do skill.rows[i]:Hide() end
    skill.content:SetHeight(math.max(1, n * 26))
end
C.RefreshPanel = function() refreshSkill() end

-------------------------------------------------------------------------------
-- 2. Co chybí
-------------------------------------------------------------------------------
local need = {}

local function createNeedPage(p)
    need.sf, need.content = scrollArea(p, 0, 70)
    need.rows = {}
    need.status = text(p, fontNormal)
    need.status:SetPoint("BOTTOMLEFT", 2, 42)
    need.status:SetPoint("RIGHT", 0, 0)
    need.status:SetWordWrap(false)
    need.buy = button(p, W - 20, "Koupit, co chybí")
    need.buy:SetPoint("BOTTOMLEFT", 0, 12)
    need.buy:SetScript("OnClick", function() C.BuyFromList(); C_Timer.After(0.6, refreshNeed) end)
    need.clear = button(p, 110, "Vyčistit")
    need.clear:SetPoint("BOTTOMRIGHT", 0, 12)
    need.clear:SetScript("OnClick", function() wipe(CrafterDB.list); refreshNeed() end)
end

local function needRow(i)
    local row = need.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, need.content)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(24, 24)
    row.icon:SetPoint("TOPLEFT", 2, -3)
    row.name = text(row, fontNormal)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
    row.name:SetPoint("RIGHT", -110, 0)
    row.name:SetWordWrap(false)
    row.right = text(row, fontNormal)
    row.right:SetPoint("TOPRIGHT", -4, -3)
    row.right:SetJustifyH("RIGHT")
    row.sub = text(row, fontSmall, 0.7, 0.7, 0.7)
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -3)
    row.sub:SetPoint("RIGHT", -4, 0)
    row.sub:SetWordWrap(false)
    row.del = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.del:SetSize(22, 18)
    row.del:SetPoint("RIGHT", -2, 0)
    row.del:SetText("X")
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
    need.rows[i] = row
    return row
end

function refreshNeed()
    if not main or current ~= 2 then return end
    updateHeader()
    local n, y = 0, 0
    local function add(h, fill)
        n = n + 1
        local row = needRow(n)
        row:SetHeight(h)
        row.del:Hide()
        row.sub:SetText("")
        row.right:SetText("")
        row:SetScript("OnClick", nil)
        row:SetScript("OnEnter", nil)
        row:SetScript("OnLeave", nil)
        row.icon:SetTexture(nil)
        fill(row)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", need.content, "RIGHT", 0, 0)
        row:Show()
        y = y + h + 2
    end
    local function header(label)
        add(20, function(row)
            row.name:SetText(label)
            row.name:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
        end)
    end

    if #CrafterDB.list == 0 then
        header("Zatím nic neplánuješ")
        add(44, function(row)
            row.name:SetText("V záložce Na skill dej „Doplnit suroviny“.")
            row.name:SetTextColor(0.8, 0.8, 0.8)
            row.sub:SetText("Tady pak uvidíš, co ti chybí a kde to sehnat.")
        end)
    else
        header("Plánuješ vyrobit")
        for i, e in ipairs(CrafterDB.list) do
            add(24, function(row)
                row.icon:SetTexture(e.icon)
                row.name:SetText(("%s  ×%d"):format(e.name, e.qty))
                row.name:SetTextColor(1, 1, 1)
                row.del:Show()
                row.del:SetScript("OnClick", function() table.remove(CrafterDB.list, i); refreshNeed() end)
                row:SetScript("OnClick", function() C.SelectRecipeByName(e.name) end)
                row:SetScript("OnEnter", function(self) showTip(self, { { e.name }, { "Klik = vybrat v okně profese. X = odebrat z plánu.", 0.8, 0.8, 0.8 } }) end)
                row:SetScript("OnLeave", hideTip)
            end)
        end

        -- co chybí: suroviny receptů + přepočet (bar -> ruda)
        local totals, raw = C.ListTotals()
        local missing = {}
        for _, t in ipairs(totals) do if t.missing > 0 then missing[#missing + 1] = t end end
        for _, x in ipairs(raw or {}) do if x.missing > 0 then missing[#missing + 1] = x end end
        if #missing == 0 then
            header("Máš všechno – můžeš vyrábět")
        else
            header("Chybí ti (klik = ukázat na mapě)")
            for _, t in ipairs(missing) do
                add(40, function(row)
                    row.icon:SetTexture(t.icon)
                    row.name:SetText(t.name)
                    row.name:SetTextColor(1, 1, 1)
                    row.right:SetText(("chybí %d"):format(t.missing))
                    row.right:SetTextColor(1, 0.45, 0.45)
                    local how = C.HowToGet(t.id)
                    local best = how and how[1] and how[1][2] or ""
                    if t["for"] then best = "na " .. t["for"] .. " – " .. best end
                    row.sub:SetText(best)
                    row:SetScript("OnClick", function() C.MapFor(t.id, t.name) end)
                    row:SetScript("OnEnter", function(self)
                        local lines = { { t.name }, { ("Máš %d, potřeba %d, chybí %d."):format(t.have, t.need, t.missing), 0.8, 0.8, 0.8 } }
                        if t["for"] then lines[#lines + 1] = { "Na výrobu: " .. t["for"], 0.6, 0.8, 1 } end
                        for _, l in ipairs(how or {}) do
                            local col = C.HOW_COLOR[l[1]] or { 0.8, 0.8, 0.8 }
                            lines[#lines + 1] = { "• " .. l[2], col[1], col[2], col[3] }
                        end
                        lines[#lines + 1] = { "Klik = ukázat na mapě", 0.6, 0.6, 0.6 }
                        showTip(self, lines)
                    end)
                    row:SetScript("OnLeave", hideTip)
                end)
            end
        end
    end
    for i = n + 1, #need.rows do need.rows[i]:Hide() end
    need.content:SetHeight(math.max(1, y))

    -- dole: stav a nákup u obchodníka
    need.clear:SetShown(#CrafterDB.list > 0)
    local merchant = MerchantFrame and MerchantFrame:IsShown()
    if merchant and #CrafterDB.list > 0 then
        local plan, total = C.MerchantPlan()
        need.buy:Show()
        need.buy:SetWidth(W - 140)
        need.buy:SetEnabled(#plan > 0)
        need.buy:SetText(#plan > 0 and ("Koupit, co chybí (" .. C.Money(total) .. ")") or "Tady nic z toho neprodávají")
        need.status:SetText("")
    else
        need.buy:Hide()
        need.status:SetText(#CrafterDB.list > 0 and colorText(0.7, 0.7, 0.7, "U obchodníka tu bude tlačítko Koupit, co chybí.") or "")
    end
end
C.RefreshList = function() refreshNeed() end

-------------------------------------------------------------------------------
-- Otevírání
-------------------------------------------------------------------------------
local function ensure()
    if main then return end
    createMain()
    createSkillPage(pages[1])
    createNeedPage(pages[2])
    C.EmbedMap(pages[3])
end

C.EnsureMain = ensure

-- tab = 1/2/3; bez čísla: Na skill u otevřené profese, jinak Co chybí
function C.ToggleMain(tab)
    ensure()
    if main:IsShown() and (not tab or tab == current) then main:Hide() return end
    C.ShowMainTab(tab or (C.Provider() and 1 or 2))
end
C.ToggleList = function() C.ToggleMain(2) end
C.ShowDetail = function() end   -- staré okno Suroviny už není (vše je v záložkách)

-- vybrat recept podle jména v otevřeném okně profese
function C.SelectRecipeByName(name)
    provider = C.Provider()
    if not provider then C.Msg("otevri okno profese - pak recept vyberu.") return end
    for _, r in ipairs(provider.recipes()) do
        if r.name == name then
            provider.select(r)
            focus = r
            return
        end
    end
    C.Msg("tenhle recept v otevrene profesi neni.")
end

-- u okna profese: Crafter vedle něj (když ho hráč sám nepřesunul)
local function attachToProfession()
    ensure()
    local p = C.Provider()
    if not p then return end
    if not CrafterDB.mainPos then
        local host = (p.kind == "craft" and CraftFrame) or (p.kind == "retail" and ProfessionsFrame) or TradeSkillFrame
        if host then
            main:ClearAllPoints()
            main:SetPoint("TOPLEFT", host, "TOPRIGHT", 70, 0)
        end
    end
    main.autoOpened = not main:IsShown()
    C.ShowMainTab(1)
end

-------------------------------------------------------------------------------
-- Ikona u minimapy: levý klik = Crafter, pravý = mapa
-------------------------------------------------------------------------------
local mm
local function placeMinimap()
    local a = math.rad(CrafterDB.minimapAngle or 120)
    local r = (Minimap:GetWidth() / 2) + 10
    mm:ClearAllPoints()
    mm:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end
local function createMinimap()
    if mm or not Minimap then return end
    mm = CreateFrame("Button", "CrafterMinimapButton", Minimap)
    mm:SetSize(31, 31)
    mm:SetFrameStrata("MEDIUM")
    mm:SetFrameLevel(8)
    local icon = mm:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\Trade_BlackSmithing")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 1)
    local border = mm:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    mm:RegisterForDrag("LeftButton")
    mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mm:SetScript("OnClick", function(_, b) if b == "RightButton" then C.ToggleMain(3) else C.ToggleMain() end end)
    mm:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = Minimap:GetEffectiveScale()
            CrafterDB.minimapAngle = math.deg(math.atan2(cy / s - my, cx / s - mx))
            placeMinimap()
        end)
    end)
    mm:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mm:SetScript("OnEnter", function(self)
        showTip(self, { { "Crafter" }, { "Levý klik: Crafter (Na skill / Co chybí)", 0.9, 0.9, 0.9 },
                        { "Pravý klik: mapa tvých nálezů", 0.9, 0.9, 0.9 }, { "Tažením posuneš ikonu.", 0.7, 0.7, 0.7 } })
    end)
    mm:SetScript("OnLeave", hideTip)
    placeMinimap()
end

-------------------------------------------------------------------------------
-- Události a příkazy
-------------------------------------------------------------------------------
local pending
local function later(fn)
    if pending then return end
    pending = true
    C_Timer.After(0.3, function() pending = nil; fn() end)
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE",
                     "CRAFT_SHOW", "CRAFT_CLOSE", "CRAFT_UPDATE", "BAG_UPDATE", "MERCHANT_SHOW", "MERCHANT_CLOSED",
                     "MERCHANT_UPDATE", "SKILL_LINES_CHANGED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then createMinimap() return end
    if event == "TRADE_SKILL_SHOW" or event == "CRAFT_SHOW" then
        C_Timer.After(0.1, attachToProfession)
        return
    end
    if event == "TRADE_SKILL_CLOSE" or event == "CRAFT_CLOSE" then
        C_Timer.After(0.1, function()
            -- sám otevřený u profese a pořád na záložce Na skill -> zavřít s profesí
            if main and main.autoOpened and current == 1 and not C.Provider() then main:Hide() end
            if main and main:IsShown() then refreshSkill() end
        end)
        return
    end
    if event == "MERCHANT_SHOW" then
        C.ScanMerchant()
        -- něco z plánu tu prodávají -> ukázat Co chybí s tlačítkem Koupit
        if #CrafterDB.list > 0 then
            local plan = C.MerchantPlan()
            if #plan > 0 then ensure(); C.ShowMainTab(2) end
        end
        return
    end
    if event == "MERCHANT_UPDATE" then C.ScanMerchant() end
    later(function()
        if not main or not main:IsShown() then return end
        if current == 1 then refreshSkill() elseif current == 2 then refreshNeed() end
    end)
end)

SLASH_CRAFTER1 = "/crafter"
SlashCmdList.CRAFTER = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" then C.ToggleMain() return end
    if msg == "mapa" then C.ToggleMain(3) return end
    if msg == "seznam" or msg == "chybi" then C.ToggleMain(2) return end
    if msg == "ladit" then C.Sber.Debug() return end
    if msg == "sber" then C.Sber.Toggle() return end
    if msg == "znacka" then C.ClearMap(); C.Msg("znacka na mape zrusena.") return end
    if msg == "vycistit" then wipe(CrafterDB.list); if main then refreshNeed() end; C.Msg("plan vycisten.") return end
    if msg == "ceny" then
        local n = 0
        for _ in pairs(CrafterDB.prices) do n = n + 1 end
        C.Msg(("znam ceny %d surovin od obchodniku."):format(n))
        return
    end
    if msg == "popisky" then
        CrafterDB.tooltip = CrafterDB.tooltip == false
        C.Msg("kde sehnat v popiscich predmetu: " .. (CrafterDB.tooltip == false and "vypnuto" or "zapnuto"))
        return
    end
    C.Msg("/crafter = okno Crafteru, /crafter mapa, /crafter chybi, /crafter vycistit, /crafter ladit, /crafter popisky")
end
