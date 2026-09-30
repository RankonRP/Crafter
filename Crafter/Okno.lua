-- Crafter: okna – panel „Co vyrobit“ u okna profese, nákupní seznam, ikona u minimapy
local C = Crafter
local FONT = "Interface\\AddOns\\Crafter\\Fonts\\cz.ttf"

local fontNormal = CreateFont("CrafterFontNormal")
fontNormal:SetFont(FONT, 12, "")
local fontSmall = CreateFont("CrafterFontSmall")
fontSmall:SetFont(FONT, 10, "")
local fontTitle = CreateFont("CrafterFontTitle")
fontTitle:SetFont(FONT, 14, "")
local fontButton = CreateFont("CrafterFontButton")
fontButton:SetFont(FONT, 12, "")
fontButton:SetTextColor(1, 0.82, 0)
local fontButtonHl = CreateFont("CrafterFontButtonHl")
fontButtonHl:SetFont(FONT, 12, "")
fontButtonHl:SetTextColor(1, 1, 1)

local BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }
local ACCENT = { 0.9, 0.7, 0.3 }

local function text(parent, font, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(font)
    fs:SetTextColor(r or 1, g or 1, b or 1)
    return fs
end

local function czechButton(parent, w, label)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetNormalFontObject(fontButton)
    b:SetHighlightFontObject(fontButtonHl)
    b:SetDisabledFontObject(fontButton)
    b:SetText(label)
    return b
end

local function window(name, w, h)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(0.03, 0.03, 0.03, 0.95)
    f:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:Hide()
    f.title = text(f, fontTitle, ACCENT[1], ACCENT[2], ACCENT[3])
    f.title:SetPoint("TOPLEFT", 10, -9)
    f.title:SetPoint("RIGHT", -30, 0)
    f.title:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    return f
end

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

-- vytvoří posuvný seznam: vrací scroll a obsah (child), do kterého se kreslí řádky
local function scrollArea(parent, top, bottom)
    local sf = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 8, top)
    sf:SetPoint("BOTTOMRIGHT", -28, bottom)
    local content = CreateFrame("Frame", nil, sf)
    content:SetSize(parent:GetWidth() - 36, 10)
    sf:SetScrollChild(content)
    sf:SetScript("OnSizeChanged", function(self, w) content:SetWidth(w) end)
    return sf, content
end

local refreshList   -- nákupní seznam (níž)

-------------------------------------------------------------------------------
-- Panel „Co vyrobit“ vedle okna profese
-------------------------------------------------------------------------------
local panel, rows, recipes, selected, qty = nil, {}, {}, nil, 1
local provider

local function sortRecipes(list)
    table.sort(list, function(a, b)
        local da, db = (C.DIFF[a.diff] or C.DIFF.easy).order, (C.DIFF[b.diff] or C.DIFF.easy).order
        if da ~= db then return da < db end
        local ca, ua = C.RecipeCost(a)
        local cb, ub = C.RecipeCost(b)
        if ua ~= ub then return not ua end
        if ca ~= cb then return ca < cb end
        return a.name < b.name
    end)
end

local function reagentLines(r, times)
    times = times or 1
    local lines = {}
    for _, rg in ipairs(r.reagents) do
        local need = rg.need * times
        local ok = rg.have >= need
        local price = C.PriceOf(rg.id)
        lines[#lines + 1] = { ("%d× %s  (máš %d)%s"):format(need, rg.name or "?", rg.have, price and ("  " .. C.Money(price) .. "/ks") or ""),
                              ok and 0.6 or 1, ok and 1 or 0.4, ok and 0.6 or 0.4 }
    end
    return lines
end

local function updateRow(row, r)
    local d = C.DIFF[r.diff] or C.DIFF.easy
    row.icon:SetTexture(r.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.name:SetText(r.name)
    row.name:SetTextColor(d.color[1], d.color[2], d.color[3])
    local cost, unknown, farm = C.RecipeCost(r)
    local parts = { d.label }
    parts[#parts + 1] = r.numAvailable > 0 and ("vyrobíš %d×"):format(r.numAvailable) or "chybí suroviny"
    parts[#parts + 1] = C.CostText(cost, unknown, farm)
    row.info:SetText(table.concat(parts, "  ·  "))
    row.sel:SetShown(selected and selected.name == r.name or false)
end

local function refreshPanel()
    if not panel or not panel:IsShown() or not provider then return end
    local name, rank, max = provider.line()
    panel.rank, panel.max = tonumber(rank), tonumber(max)
    local left = (panel.rank and panel.max) and (panel.max - panel.rank) or nil
    panel.title:SetText(("Crafter – %s %s/%s%s"):format(name or "?", tostring(rank or "?"), tostring(max or "?"),
        left and (left > 0 and ("  (zbývá %d)"):format(left) or "  (max – u trenéra se nauč další úroveň)") or ""))
    local all = provider.recipes()
    recipes = {}
    for _, r in ipairs(all) do
        local show = true
        if CrafterDB.hideTrivial and r.diff == "trivial" then show = false end
        if CrafterDB.onlyCraftable and r.numAvailable <= 0 then show = false end
        if show then recipes[#recipes + 1] = r end
    end
    sortRecipes(recipes)
    if selected then
        local found
        for _, r in ipairs(recipes) do if r.name == selected.name then found = r end end
        selected = found
    end
    for i, r in ipairs(recipes) do
        local row = rows[i]
        if not row then
            row = CreateFrame("Button", nil, panel.content)
            row:SetHeight(34)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * 36)
            row:SetPoint("RIGHT", panel.content, "RIGHT", 0, 0)
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.07)
            row.sel = row:CreateTexture(nil, "BACKGROUND")
            row.sel:SetAllPoints()
            row.sel:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.18)
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(28, 28)
            row.icon:SetPoint("LEFT", 2, 0)
            row.name = text(row, fontNormal)
            row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
            row.name:SetPoint("RIGHT", -4, 0)
            row.name:SetJustifyH("LEFT")
            row.name:SetWordWrap(false)
            row.info = text(row, fontSmall, 0.75, 0.75, 0.75)
            row.info:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
            row.info:SetPoint("RIGHT", -4, 0)
            row.info:SetJustifyH("LEFT")
            row.info:SetWordWrap(false)
            row:SetScript("OnClick", function(self)
                selected = self.recipe
                provider.select(self.recipe)
                refreshPanel()
                C.ShowDetail(self.recipe)
            end)
            row:SetScript("OnEnter", function(self)
                local lines = { { self.recipe.name } }
                for _, l in ipairs(reagentLines(self.recipe)) do lines[#lines + 1] = l end
                lines[#lines + 1] = { " " }
                lines[#lines + 1] = { "Klik = vedle se ukáže, jak suroviny sehnat. Dole nastav počet a přidej na nákupní seznam.", 0.7, 0.7, 0.7 }
                showTip(self, lines)
            end)
            row:SetScript("OnLeave", hideTip)
            rows[i] = row
        end
        row.recipe = r
        updateRow(row, r)
        row:Show()
    end
    for i = #recipes + 1, #rows do rows[i]:Hide() end
    panel.content:SetHeight(math.max(1, #recipes * 36))
    panel.empty:SetShown(#recipes == 0)

    -- spodní část: vybraný recept
    if selected then
        panel.selName:SetText(selected.name)
        local cost, unknown, farm = C.RecipeCost(selected)
        panel.selCost:SetText(("%d× = %s"):format(qty, C.CostText(cost * qty, unknown, farm)))
        panel.add:Enable()
    else
        panel.selName:SetText("Vyber recept v seznamu nahoře")
        panel.selCost:SetText("")
        panel.add:Disable()
    end
    panel.qtyText:SetText(qty)
    panel.listBtn:SetText(("Nákupní seznam (%d)"):format(#CrafterDB.list))
end
C.RefreshPanel = refreshPanel

local function createPanel()
    panel = window("CrafterPanel", 340, 460)
    panel:SetFrameStrata("HIGH")

    local hideGray = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    hideGray:SetSize(22, 22)
    hideGray:SetPoint("TOPLEFT", 8, -30)
    hideGray:SetHitRectInsets(0, -130, 0, 0)
    if hideGray.Text then hideGray.Text:SetText("") end
    local l1 = text(panel, fontSmall)
    l1:SetPoint("LEFT", hideGray, "RIGHT", 2, 0)
    l1:SetText("Schovat šedé (nic nedají)")
    hideGray:SetScript("OnClick", function(self) CrafterDB.hideTrivial = self:GetChecked() and true or false; refreshPanel() end)

    local onlyCan = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    onlyCan:SetSize(22, 22)
    onlyCan:SetPoint("TOPLEFT", 178, -30)
    onlyCan:SetHitRectInsets(0, -130, 0, 0)
    if onlyCan.Text then onlyCan.Text:SetText("") end
    local l2 = text(panel, fontSmall)
    l2:SetPoint("LEFT", onlyCan, "RIGHT", 2, 0)
    l2:SetText("Jen co hned vyrobím")
    onlyCan:SetScript("OnClick", function(self) CrafterDB.onlyCraftable = self:GetChecked() and true or false; refreshPanel() end)
    panel:HookScript("OnShow", function()
        hideGray:SetChecked(CrafterDB.hideTrivial)
        onlyCan:SetChecked(CrafterDB.onlyCraftable)
    end)

    panel.sf, panel.content = scrollArea(panel, -56, 104)
    panel.empty = text(panel.content, fontNormal, 0.6, 0.6, 0.6)
    panel.empty:SetPoint("TOPLEFT", 6, -6)
    panel.empty:SetWidth(280)
    panel.empty:SetJustifyH("LEFT")
    panel.empty:SetText("Žádný recept tu teď nezvedne dovednost. Zkus vypnout „Schovat šedé“, nebo se u trenéra nauč nové recepty.")

    local sep = panel:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.4)
    sep:SetPoint("BOTTOMLEFT", 8, 98)
    sep:SetPoint("BOTTOMRIGHT", -8, 98)
    sep:SetHeight(1)

    panel.selName = text(panel, fontNormal, 1, 1, 1)
    panel.selName:SetPoint("BOTTOMLEFT", 10, 76)
    panel.selName:SetPoint("RIGHT", -10, 0)
    panel.selName:SetJustifyH("LEFT")
    panel.selName:SetWordWrap(false)

    local ql = text(panel, fontNormal)
    ql:SetPoint("BOTTOMLEFT", 10, 45)
    ql:SetText("Kolik:")
    local minus = czechButton(panel, 24, "-")
    minus:SetPoint("BOTTOMLEFT", 56, 40)
    panel.qtyText = text(panel, fontNormal, 1, 1, 1)
    panel.qtyText:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    panel.qtyText:SetWidth(34)
    local plus = czechButton(panel, 24, "+")
    plus:SetPoint("LEFT", panel.qtyText, "RIGHT", 4, 0)
    local function step(d)
        local big = IsShiftKeyDown() and 10 or 1
        qty = math.max(1, math.min(999, qty + d * big))
        refreshPanel()
    end
    minus:SetScript("OnClick", function() step(-1) end)
    plus:SetScript("OnClick", function() step(1) end)
    -- „Na skill“: tolik kusů, kolik bodů chybí do maxima (oranžový recept = bod za každý kus)
    local toMax = czechButton(panel, 64, "Na skill")
    toMax:SetPoint("LEFT", plus, "RIGHT", 6, 0)
    toMax:SetScript("OnClick", function()
        if not panel.rank or not panel.max then return end
        local need = panel.max - panel.rank
        if selected and selected.diff == "medium" then need = math.ceil(need * 1.5) end
        if selected and selected.diff == "easy" then need = need * 3 end
        qty = math.max(1, math.min(999, need))
        refreshPanel()
    end)
    toMax:SetScript("OnEnter", function(self)
        showTip(self, { { "Na skill" }, { "Nastaví počet kusů, kolik bodů chybí do maxima dovednosti. Oranžový recept dá bod za každý kus, u žlutého a zeleného Crafter počítá víc kusů (body padají jen občas).", 0.8, 0.8, 0.8 } })
    end)
    toMax:SetScript("OnLeave", hideTip)
    panel.selCost = text(panel, fontSmall, 0.8, 0.8, 0.8)
    panel.selCost:SetPoint("LEFT", toMax, "RIGHT", 6, 0)
    panel.selCost:SetPoint("RIGHT", -10, 0)
    panel.selCost:SetJustifyH("LEFT")

    panel.add = czechButton(panel, 150, "Přidat na seznam")
    panel.add:SetPoint("BOTTOMLEFT", 10, 10)
    panel.add:SetScript("OnClick", function()
        if not selected then return end
        C.AddToList(selected, qty)
        C.Msg(("na seznamu: %s x%d"):format(selected.name, qty))
        refreshPanel()
        if refreshList then refreshList() end
    end)
    panel.listBtn = czechButton(panel, 160, "Nákupní seznam")
    panel.listBtn:SetPoint("BOTTOMRIGHT", -10, 10)
    panel.listBtn:SetScript("OnClick", function() C.ToggleList() end)
    minus:HookScript("OnEnter", function(self) showTip(self, { { "Počet" }, { "Shift + klik = po deseti.", 0.8, 0.8, 0.8 } }) end)
    minus:HookScript("OnLeave", hideTip)
    plus:HookScript("OnEnter", function(self) showTip(self, { { "Počet" }, { "Shift + klik = po deseti.", 0.8, 0.8, 0.8 } }) end)
    plus:HookScript("OnLeave", hideTip)
end

local function attachPanel()
    provider = C.Provider()
    if not provider then return end
    if not panel then createPanel() end
    local host = (provider.kind == "craft" and CraftFrame) or (provider.kind == "retail" and ProfessionsFrame) or TradeSkillFrame
    panel:ClearAllPoints()
    -- vedle okna jsou záložky pro přepínání profesí (asi 65 bodů) -> panel až za ně
    panel:SetPoint("TOPLEFT", host, "TOPRIGHT", 70, 0)
    panel:Show()
    refreshPanel()
end

-------------------------------------------------------------------------------
-- Okno „Suroviny“: po kliknutí na recept – co máš a jak zbytek sehnat
-------------------------------------------------------------------------------
local detail, detailRecipe, blocks = nil, nil, {}

local function block(i)
    local b = blocks[i]
    if b then return b end
    b = CreateFrame("Frame", nil, detail.content)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(30, 30)
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.name = text(b, fontNormal, 1, 1, 1)
    b.name:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 8, -1)
    b.name:SetPoint("RIGHT", -70, 0)
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    b.count = text(b, fontSmall)
    b.count:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -2)
    b.how = text(b, fontSmall)
    b.how:SetPoint("TOPLEFT", b.icon, "BOTTOMLEFT", 4, -4)
    b.how:SetPoint("RIGHT", -6, 0)
    b.how:SetJustifyH("LEFT")
    b.how:SetSpacing(2)
    b.map = czechButton(b, 62, "Mapa")
    b.map:SetPoint("TOPRIGHT", -2, -4)
    b.map:SetScript("OnClick", function(self) C.MapFor(self:GetParent().itemID, self:GetParent().itemName) end)
    b.map:SetScript("OnEnter", function(self) showTip(self, { { "Mapa" }, { "Máš-li tuhle surovinu už nalezenou, otevře mapu Crafteru s tvými místy. Jinak dá značku k nejbližšímu obchodníkovi nebo místu, kde se sežene.", 0.8, 0.8, 0.8 } }) end)
    b.map:SetScript("OnLeave", hideTip)
    blocks[i] = b
    return b
end

local function colorText(r, g, bl, s)
    return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, bl * 255, s)
end

local function refreshDetail()
    if not detail or not detail:IsShown() or not detailRecipe then return end
    -- čerstvé počty (taška se mohla změnit)
    if provider then
        for _, r in ipairs(recipes) do if r.name == detailRecipe.name then detailRecipe = r end end
    end
    detail.title:SetText(detailRecipe.name)
    local y = 0
    for i, rg in ipairs(detailRecipe.reagents) do
        local b = block(i)
        b.itemID, b.itemName = rg.id, rg.name
        b.icon:SetTexture(rg.icon)
        b.name:SetText(rg.name or "?")
        local ok = rg.have >= rg.need
        b.count:SetText(ok and colorText(0.5, 1, 0.5, ("máš %d – stačí (potřeba %d)"):format(rg.have, rg.need))
                            or colorText(1, 0.45, 0.45, ("máš %d, potřeba %d – chybí %d"):format(rg.have, rg.need, rg.need - rg.have)))
        local lines = {}
        for _, l in ipairs(rg.id and C.HowToGet(rg.id) or {}) do
            local col = C.HOW_COLOR[l[1]] or { 0.8, 0.8, 0.8 }
            lines[#lines + 1] = colorText(col[1], col[2], col[3], "• " .. l[2])
        end
        b.how:SetText(table.concat(lines, "\n"))
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 0, -y)
        b:SetPoint("RIGHT", detail.content, "RIGHT", 0, 0)
        local h = 40 + (b.how:GetStringHeight() or 0) + 10
        b:SetHeight(h)
        b:Show()
        y = y + h
    end
    for i = #detailRecipe.reagents + 1, #blocks do blocks[i]:Hide() end
    detail.content:SetHeight(math.max(1, y))
end
C.RefreshDetail = refreshDetail

function C.ShowDetail(r)
    if not detail then
        detail = window("CrafterDetail", 380, 460)
        detail:SetFrameStrata("HIGH")
        detail.sf, detail.content = scrollArea(detail, -34, 44)
        local legend = text(detail, fontSmall, 0.65, 0.65, 0.65)
        legend:SetPoint("BOTTOMLEFT", 10, 14)
        legend:SetPoint("RIGHT", -10, 0)
        legend:SetJustifyH("LEFT")
        legend:SetText("Kde co stáhneš, vytěžíš nebo natrháš, si Crafter pamatuje sám – uvidíš to na jeho mapě (pravý klik na ikonu u minimapy).")
    end
    detailRecipe = r
    detail:ClearAllPoints()
    if panel and panel:IsShown() then detail:SetPoint("TOPLEFT", panel, "TOPRIGHT", 4, 0) else detail:SetPoint("CENTER") end
    detail:Show()
    refreshDetail()
end

-------------------------------------------------------------------------------
-- Nákupní seznam
-------------------------------------------------------------------------------
local list, listRows = nil, {}

local function listRow(i)
    local row = listRows[i]
    if row then return row end
    row = CreateFrame("Button", nil, list.content)
    row:SetHeight(22)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * 24)
    row:SetPoint("RIGHT", list.content, "RIGHT", 0, 0)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20)
    row.icon:SetPoint("LEFT", 2, 0)
    row.name = text(row, fontNormal)
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetPoint("RIGHT", -110, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.count = text(row, fontNormal)
    row.count:SetPoint("RIGHT", -4, 0)
    row.count:SetJustifyH("RIGHT")
    row.del = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.del:SetSize(22, 18)
    row.del:SetPoint("RIGHT", -2, 0)
    row.del:SetText("X")
    listRows[i] = row
    return row
end

function refreshList()
    if not list or not list:IsShown() then return end
    local n = 0
    local function add(fill)
        n = n + 1
        local row = listRow(n)
        row.del:Hide()
        row:SetScript("OnEnter", nil)
        row:SetScript("OnLeave", nil)
        row:SetScript("OnClick", nil)
        fill(row)
        row:Show()
    end
    -- recepty
    local header = function(label)
        add(function(row)
            row.icon:SetTexture(nil)
            row.name:SetText(label)
            row.name:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
            row.count:SetText("")
        end)
    end
    if #CrafterDB.list == 0 then
        header("Seznam je prázdný")
        add(function(row)
            row.icon:SetTexture(nil)
            row.name:SetText("Otevři profesi, vyber recept a dej „Přidat na seznam“.")
            row.name:SetTextColor(0.6, 0.6, 0.6)
            row.count:SetText("")
        end)
    else
        header("Chci vyrobit")
        for i, e in ipairs(CrafterDB.list) do
            add(function(row)
                row.icon:SetTexture(e.icon)
                row.name:SetText(e.name)
                row.name:SetTextColor(1, 1, 1)
                row.count:SetText("")
                row.del:Show()
                row.del:SetScript("OnClick", function() C.RemoveFromList(i); refreshList(); if C.RefreshPanel then C.RefreshPanel() end end)
                row.name:SetText(("%s  ×%d"):format(e.name, e.qty))
            end)
        end
        header("Suroviny (máš / potřeba)")
        local missingCost, unknown, farm = 0, false, false
        for _, t in ipairs(C.ListTotals()) do
            add(function(row)
                row.icon:SetTexture(t.icon)
                row.name:SetText(t.name)
                local done = t.missing == 0
                row.name:SetTextColor(done and 0.6 or 1, done and 1 or 1, done and 0.6 or 1)
                row.count:SetText(("%d / %d"):format(t.have, t.need))
                row.count:SetTextColor(done and 0.6 or 1, done and 1 or 0.4, done and 0.6 or 0.4)
                row:SetScript("OnEnter", function(self)
                    local lines = { { t.name }, { ("Máš %d (i v bance), potřeba %d, chybí %d."):format(t.have, t.need, t.missing), 0.8, 0.8, 0.8 } }
                    if t.price then
                        lines[#lines + 1] = { ("Viděno u %s: %s za kus"):format(CrafterDB.vendorName[t.id] or "?", C.Money(t.price)), 0.6, 1, 0.6 }
                    end
                    local src = C.SourceLines and C.SourceLines(t.id, 3)
                    if src and #src > 0 then
                        lines[#lines + 1] = { " " }
                        lines[#lines + 1] = { "Kde sehnat:", ACCENT[1], ACCENT[2], ACCENT[3] }
                        for _, l in ipairs(src) do
                            local col = C.SOURCE_COLOR[l[1]]
                            lines[#lines + 1] = { l[2], col[1], col[2], col[3] }
                        end
                        lines[#lines + 1] = { " " }
                        lines[#lines + 1] = { "Klik = ukázat na mapě (značka k nejbližšímu místu, tečky na mapě světa)", 0.7, 0.7, 0.7 }
                    else
                        lines[#lines + 1] = { "Kde ji sehnat, nevím (nová věc ve Forever, nebo jen z aukce).", 0.7, 0.7, 0.7 }
                    end
                    showTip(self, lines)
                end)
                row:SetScript("OnLeave", hideTip)
                row:SetScript("OnClick", function() if C.ShowOnMap then C.ShowOnMap(t.id, t.name) end end)
            end)
            if t.missing > 0 then
                if t.price then missingCost = missingCost + t.price * t.missing elseif C.Farmable(t.id) then farm = true else unknown = true end
            end
        end
        local anyMissing = false
        for _, t in ipairs(C.ListTotals()) do if t.missing > 0 then anyMissing = true end end
        if not anyMissing then
            list.total:SetText("|cff80ff80Máš všechny suroviny – můžeš vyrábět.|r")
        else
            list.total:SetText("Chybějící za " .. C.CostText(missingCost, unknown, farm))
        end
    end
    if #CrafterDB.list == 0 then list.total:SetText("") end
    for i = n + 1, #listRows do listRows[i]:Hide() end
    list.content:SetHeight(math.max(1, n * 24))

    -- nákup u obchodníka
    if MerchantFrame and MerchantFrame:IsShown() then
        local plan, total = C.MerchantPlan()
        list.buy:SetShown(true)
        list.buy:SetEnabled(#plan > 0)
        local missingAny = false
        for _, t in ipairs(C.ListTotals()) do if t.missing > 0 then missingAny = true end end
        if #plan > 0 then list.buy:SetText("Koupit, co chybí (" .. C.Money(total) .. ")")
        elseif not missingAny then list.buy:SetText("Nic nechybí")
        else list.buy:SetText("To, co chybí, tu neprodávají") end
    else
        list.buy:Hide()
    end
end
C.RefreshList = refreshList

local function createList()
    list = window("CrafterList", 340, 400)
    list:SetPoint("CENTER", 250, 0)
    list:SetFrameStrata("HIGH")
    list:SetMovable(true)
    list:RegisterForDrag("LeftButton")
    list:SetScript("OnDragStart", list.StartMoving)
    list:SetScript("OnDragStop", list.StopMovingOrSizing)
    tinsert(UISpecialFrames, "CrafterList")
    list.title:SetText("Crafter – nákupní seznam")
    list.sf, list.content = scrollArea(list, -32, 76)
    list.total = text(list, fontSmall, 0.9, 0.9, 0.9)
    list.total:SetPoint("BOTTOMLEFT", 10, 58)
    list.total:SetPoint("RIGHT", -10, 0)
    list.total:SetJustifyH("LEFT")
    list.buy = czechButton(list, 320, "Koupit tady")
    list.buy:SetPoint("BOTTOM", 0, 32)
    list.buy:SetScript("OnClick", function() C.BuyFromList(); C_Timer.After(0.6, refreshList) end)
    local clear = czechButton(list, 150, "Vyčistit seznam")
    clear:SetPoint("BOTTOMLEFT", 10, 8)
    clear:SetScript("OnClick", function()
        wipe(CrafterDB.list)
        refreshList()
        if C.RefreshPanel then C.RefreshPanel() end
    end)
    local close = czechButton(list, 110, "Zavřít")
    close:SetPoint("BOTTOMRIGHT", -10, 8)
    close:SetScript("OnClick", function() list:Hide() end)
    list:SetScript("OnShow", refreshList)
end

function C.ToggleList(show)
    if not list then createList() end
    if show == nil then show = not list:IsShown() end
    list:SetShown(show)
    if show then refreshList() end
end

-------------------------------------------------------------------------------
-- Ikona u minimapy: klik = nákupní seznam
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
    mm:SetScript("OnClick", function(_, button)
        if button == "RightButton" then C.ToggleMap() else C.ToggleList() end
    end)
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
        showTip(self, { { "Crafter" }, { "Klik: nákupní seznam", 0.9, 0.9, 0.9 }, { "Pravý klik: mapa tvých nálezů", 0.9, 0.9, 0.9 },
                        { "Panel „Co vyrobit“ se ukáže sám u okna profese.", 0.7, 0.7, 0.7 }, { "Tažením posuneš ikonu.", 0.7, 0.7, 0.7 } })
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
    pcall(ev.RegisterEvent, ev, e)   -- některé události nemusí ve Forever existovat
end
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        createMinimap()
        return
    end
    if event == "TRADE_SKILL_SHOW" or event == "CRAFT_SHOW" then
        C_Timer.After(0.1, attachPanel)
        return
    end
    if event == "TRADE_SKILL_CLOSE" or event == "CRAFT_CLOSE" then
        C_Timer.After(0.1, function()
            -- druhé okno (Enchanting / ostatní) může být pořád otevřené
            if C.Provider() then attachPanel() else if panel then panel:Hide() end; if detail then detail:Hide() end end
        end)
        return
    end
    if event == "MERCHANT_SHOW" then
        C.ScanMerchant()
        if #CrafterDB.list > 0 then C.ToggleList(true) end
        refreshList()
        return
    end
    if event == "MERCHANT_UPDATE" then C.ScanMerchant() end
    later(function()
        refreshPanel()
        refreshList()
        refreshDetail()
    end)
end)

SLASH_CRAFTER1 = "/crafter"
SlashCmdList.CRAFTER = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" or msg == "seznam" then C.ToggleList() return end
    if msg == "vycistit" then wipe(CrafterDB.list); refreshList(); C.Msg("seznam vycisten.") return end
    if msg == "mapa" then C.ToggleMap() return end
    if msg == "sber" then C.Sber.Toggle() return end
    if msg == "ladit" then C.Sber.Debug() return end
    if msg == "osy" then
        CrafterDB.dbSwap = not CrafterDB.dbSwap
        C.Sber.Rebuild()
        C.Msg("mista z databaze: osy " .. (CrafterDB.dbSwap and "PROHOZENY" or "puvodni") .. ". Kdyz jsou tecky na mape mimo, prepni zpatky.")
        return
    end
    if msg == "popisky" then CrafterDB.tooltip = CrafterDB.tooltip == false; C.Msg("kde sehnat v popiscich predmetu: " .. (CrafterDB.tooltip == false and "vypnuto" or "zapnuto")) return end
    if msg == "ceny" then
        local n = 0
        for _ in pairs(CrafterDB.prices) do n = n + 1 end
        C.Msg(("znam ceny %d surovin od obchodniku."):format(n))
        return
    end
    C.Msg("/crafter = nakupni seznam, /crafter mapa = mapa tvych nalezu, /crafter znacka = zrusit znacku, /crafter vycistit, /crafter ceny, /crafter popisky. Panel Co vyrobit se ukaze sam u okna profese.")
end
