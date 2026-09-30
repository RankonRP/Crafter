-- Crafter: data – recepty z okna profese, ceny u obchodníků, nákupní seznam
-- Hra má pro profese dvě okna: TradeSkill (většina profesí) a Craft (Enchanting).
-- Novější klient má místo nich C_TradeSkillUI – podporujeme všechny tři cesty.
-- Texty do chatu jsou bez háčků: písmo chatu neumí č/ř/ů.

local ADDON = ...
local C = {}
_G.Crafter = C

local DEFAULTS = {
    prices = {},       -- cena za kus u obchodníka: prices[itemID] = měďáky
    vendorName = {},   -- u kterého obchodníka jsme cenu viděli: vendorName[itemID] = "Jméno"
    list = {},         -- nákupní seznam: { { name = "Recept", qty = 5, reagents = { [itemID] = kusů na 1 výrobu } } }
    itemNames = {},    -- jména a ikonky surovin (aby seznam šel ukázat i bez otevřeného okna profese)
    itemIcons = {},
    hideTrivial = true,  -- schovat šedé recepty (nic nedají)
    onlyCraftable = false,
    minimapAngle = 120,
}

function C.Msg(text) print("|cffe6b34dCrafter:|r " .. text) end

-- Nový klient (Forever) má funkce pro předměty v C_Item, starý globálně – použít, co existuje
local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local function GetItemCount(id, bank)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id, bank) or 0 end
    if _G.GetItemCount then return _G.GetItemCount(id, bank) or 0 end
    return 0
end
local function itemName(id)
    local n = GetItemInfo and GetItemInfo(id)
    if not n and C_Item and C_Item.GetItemNameByID then n = C_Item.GetItemNameByID(id) end
    if not n and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return n
end
local function itemIcon(id)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    return GetItemInfo and select(10, GetItemInfo(id))
end
C.GetItemCount = GetItemCount

local function itemIDFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end
C.ItemIDFromLink = itemIDFromLink

-------------------------------------------------------------------------------
-- Obtížnost: jak jistě recept zvedne dovednost
-------------------------------------------------------------------------------
C.DIFF = {
    optimal = { order = 1, label = "jistý bod", color = { 1, 0.5, 0.25 } },
    medium  = { order = 2, label = "většinou bod", color = { 1, 1, 0 } },
    easy    = { order = 3, label = "občas bod", color = { 0.25, 0.75, 0.25 } },
    trivial = { order = 4, label = "žádný bod", color = { 0.5, 0.5, 0.5 } },
}
local RETAIL_DIFF = { [0] = "optimal", [1] = "medium", [2] = "easy", [3] = "trivial" }

-------------------------------------------------------------------------------
-- Poskytovatelé receptů
-- Každý vrací: kind, line() -> název, dovednost, max; recipes() -> seznam receptů;
-- select(recipe) -> označí recept v okně hry
-- recept = { index, name, diff, numAvailable, icon, link, reagents = { { id, name, icon, need, have } } }
-------------------------------------------------------------------------------
local function reagentInfo(id, name, icon, need)
    if id then
        CrafterDB.itemNames[id] = name or CrafterDB.itemNames[id]
        CrafterDB.itemIcons[id] = icon or CrafterDB.itemIcons[id]
    end
    return { id = id, name = name, icon = icon, need = need or 1, have = id and GetItemCount(id, true) or 0 }
end

-- kolik kusů jde vyrobit ze surovin v taškách (Forever tenhle počet nevrací) – bere se větší z obou
local function craftableCount(r)
    if #r.reagents == 0 then return r.numAvailable or 0 end
    local n = math.huge
    for _, rg in ipairs(r.reagents) do
        n = math.min(n, math.floor((rg.have or 0) / math.max(1, rg.need or 1)))
    end
    return math.max(r.numAvailable or 0, n == math.huge and 0 or n)
end

local TRADE = {
    kind = "trade",
    available = function() return GetNumTradeSkills ~= nil and TradeSkillFrame ~= nil and TradeSkillFrame:IsShown() end,
    line = function()
        local name, rank, max = GetTradeSkillLine()
        return name, rank, max
    end,
    recipes = function()
        if ExpandTradeSkillSubClass then pcall(ExpandTradeSkillSubClass, 0) end   -- rozbalit všechny skupiny
        local out = {}
        for i = 1, GetNumTradeSkills() do
            local name, kind, numAvailable = GetTradeSkillInfo(i)
            if name and kind and kind ~= "header" and kind ~= "subheader" then
                local r = { index = i, name = name, diff = kind, numAvailable = numAvailable or 0,
                            icon = GetTradeSkillIcon and GetTradeSkillIcon(i), link = GetTradeSkillItemLink and GetTradeSkillItemLink(i), reagents = {} }
                for k = 1, (GetTradeSkillNumReagents(i) or 0) do
                    local rName, rIcon, rCount = GetTradeSkillReagentInfo(i, k)
                    r.reagents[#r.reagents + 1] = reagentInfo(itemIDFromLink(GetTradeSkillReagentItemLink(i, k)), rName, rIcon, rCount)
                end
                r.numAvailable = craftableCount(r)
                out[#out + 1] = r
            end
        end
        return out
    end,
    select = function(r)
        if TradeSkillFrame_SetSelection then pcall(TradeSkillFrame_SetSelection, r.index) end
        if TradeSkillFrame_Update then pcall(TradeSkillFrame_Update) end
    end,
}

local CRAFT = {
    kind = "craft",
    available = function() return GetNumCrafts ~= nil and CraftFrame ~= nil and CraftFrame:IsShown() end,
    line = function()
        local name, rank, max = GetCraftDisplaySkillLine()
        return name, rank, max
    end,
    recipes = function()
        if ExpandCraftSkillLine then pcall(ExpandCraftSkillLine, 0) end
        local out = {}
        for i = 1, GetNumCrafts() do
            local name, _, kind, numAvailable = GetCraftInfo(i)
            if name and kind and kind ~= "header" then
                local r = { index = i, name = name, diff = kind, numAvailable = numAvailable or 0,
                            icon = GetCraftIcon and GetCraftIcon(i), link = GetCraftItemLink and GetCraftItemLink(i), reagents = {} }
                for k = 1, (GetCraftNumReagents(i) or 0) do
                    local rName, rIcon, rCount = GetCraftReagentInfo(i, k)
                    r.reagents[#r.reagents + 1] = reagentInfo(itemIDFromLink(GetCraftReagentItemLink(i, k)), rName, rIcon, rCount)
                end
                r.numAvailable = craftableCount(r)
                out[#out + 1] = r
            end
        end
        return out
    end,
    select = function(r)
        if CraftFrame_SetSelection then pcall(CraftFrame_SetSelection, r.index) end
        if CraftFrame_Update then pcall(CraftFrame_Update) end
    end,
}

local RETAIL = {
    kind = "retail",
    available = function()
        return C_TradeSkillUI ~= nil and C_TradeSkillUI.IsTradeSkillReady ~= nil and C_TradeSkillUI.IsTradeSkillReady()
            and ProfessionsFrame ~= nil and ProfessionsFrame:IsShown()
    end,
    line = function()
        -- stupeň profese (child) může být ve Forever prázdný (0/0) -> vzít ten, co má dovednost
        local child = C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo()
        local base = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
        local info = (child and (child.maxSkillLevel or 0) > 0) and child or base or child or {}
        local name = info.professionName or (base and base.professionName) or (child and child.professionName)
        return name, info.skillLevel, info.maxSkillLevel
    end,
    recipes = function()
        local out = {}
        for _, id in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
            local info = C_TradeSkillUI.GetRecipeInfo(id)
            if info and info.learned and not info.isDummyRecipe then
                local r = { index = id, recipeID = id, name = info.name, diff = RETAIL_DIFF[info.relativeDifficulty] or "easy",
                            numAvailable = info.numAvailable or 0, icon = info.icon, reagents = {} }
                local ok, schem = pcall(C_TradeSkillUI.GetRecipeSchematic, id, false)
                if ok and schem then
                    for _, slot in ipairs(schem.reagentSlotSchematics or {}) do
                        local reagent = slot.reagents and slot.reagents[1]
                        if reagent and reagent.itemID and slot.reagentType == 1 then
                            r.reagents[#r.reagents + 1] = reagentInfo(reagent.itemID, itemName(reagent.itemID), itemIcon(reagent.itemID), slot.quantityRequired)
                        end
                    end
                end
                r.numAvailable = craftableCount(r)
                out[#out + 1] = r
            end
        end
        return out
    end,
    select = function(r)
        if C_TradeSkillUI.OpenRecipe then pcall(C_TradeSkillUI.OpenRecipe, r.recipeID) end
    end,
}

function C.Provider()
    for _, p in ipairs({ CRAFT, TRADE, RETAIL }) do
        local ok, yes = pcall(p.available)
        if ok and yes then return p end
    end
end

-------------------------------------------------------------------------------
-- Ceny: cena za kus u obchodníka (zapisuje se při každé návštěvě)
-------------------------------------------------------------------------------
local function merchantItem(i)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(i)
        if info then return info.name, info.texture, info.price, info.stackCount, info.numAvailable end
    end
    local name, texture, price, quantity, numAvailable = GetMerchantItemInfo(i)
    return name, texture, price, quantity, numAvailable
end

function C.ScanMerchant()
    local vendor = UnitName("npc") or "?"
    local n = 0
    for i = 1, (GetMerchantNumItems() or 0) do
        local name, texture, price, quantity = merchantItem(i)
        local id = itemIDFromLink(GetMerchantItemLink(i))
        if id and price and price > 0 then
            CrafterDB.prices[id] = math.floor(price / math.max(1, quantity or 1) + 0.5)
            CrafterDB.vendorName[id] = vendor
            CrafterDB.itemNames[id] = name or CrafterDB.itemNames[id]
            CrafterDB.itemIcons[id] = texture or CrafterDB.itemIcons[id]
            n = n + 1
        end
    end
    return n
end

-- cena jedné výroby: součet známých cen; unknown = true, když některou cenu neznáme
function C.RecipeCost(r)
    local total, unknown = 0, false
    for _, rg in ipairs(r.reagents) do
        local p = rg.id and CrafterDB.prices[rg.id]
        if p then total = total + p * rg.need else unknown = true end
    end
    return total, unknown
end

-- cena k zobrazení: žádná známá = "cena ?", část neznámá = "12s + ?"
function C.CostText(cost, unknown)
    if unknown and (cost or 0) == 0 then return "cena ?" end
    return C.Money(cost) .. (unknown and " + ?" or "")
end

function C.Money(copper)
    if not copper then return "?" end
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return ("%dg %ds %dc"):format(math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

-------------------------------------------------------------------------------
-- Nákupní seznam
-------------------------------------------------------------------------------
function C.AddToList(r, qty)
    local reagents = {}
    for _, rg in ipairs(r.reagents) do
        if rg.id then reagents[rg.id] = (reagents[rg.id] or 0) + rg.need end
    end
    for _, e in ipairs(CrafterDB.list) do
        if e.name == r.name then e.qty = e.qty + qty; e.reagents = reagents return end
    end
    table.insert(CrafterDB.list, { name = r.name, qty = qty, reagents = reagents, icon = r.icon })
end

function C.RemoveFromList(i) table.remove(CrafterDB.list, i) end

-- sečtené suroviny: { { id, name, icon, need, have, missing, price } }, seřazené: chybějící první
function C.ListTotals()
    local need = {}
    for _, e in ipairs(CrafterDB.list) do
        for id, per in pairs(e.reagents) do need[id] = (need[id] or 0) + per * e.qty end
    end
    local out = {}
    for id, n in pairs(need) do
        local have = GetItemCount(id, true) or 0
        out[#out + 1] = { id = id, name = CrafterDB.itemNames[id] or itemName(id) or ("#" .. id), icon = CrafterDB.itemIcons[id] or itemIcon(id),
                          need = n, have = have, missing = math.max(0, n - have), price = CrafterDB.prices[id] }
    end
    table.sort(out, function(a, b)
        if (a.missing > 0) ~= (b.missing > 0) then return a.missing > 0 end
        return a.name < b.name
    end)
    return out
end

-- Koupit u otevřeného obchodníka všechno, co ze seznamu chybí a on to prodává.
-- Vrací počet koupených druhů a celkovou cenu.
function C.MerchantPlan()
    local plan, total = {}, 0
    local sells = {}
    for i = 1, (GetMerchantNumItems() or 0) do
        local id = itemIDFromLink(GetMerchantItemLink(i))
        if id then sells[id] = i end
    end
    for _, t in ipairs(C.ListTotals()) do
        local idx = sells[t.id]
        if t.missing > 0 and idx then
            local _, _, price, quantity, numAvailable = merchantItem(idx)
            local per = (price or 0) / math.max(1, quantity or 1)
            local want = t.missing
            if numAvailable and numAvailable >= 0 then want = math.min(want, numAvailable * math.max(1, quantity or 1)) end
            if want > 0 then
                plan[#plan + 1] = { index = idx, qty = want, name = t.name }
                total = total + math.ceil(per * want)
            end
        end
    end
    return plan, total
end

function C.BuyFromList()
    local plan, total = C.MerchantPlan()
    if #plan == 0 then C.Msg("u tohoto obchodnika nic ze seznamu neni.") return end
    if GetMoney() < total then C.Msg("nemas dost penez (potreba " .. C.Money(total) .. ").") return end
    for _, p in ipairs(plan) do
        local maxStack = GetMerchantItemMaxStack and GetMerchantItemMaxStack(p.index) or 20
        local left = p.qty
        while left > 0 do
            local n = math.min(left, math.max(1, maxStack))
            BuyMerchantItem(p.index, n)
            left = left - n
        end
    end
    C.Msg(("koupeno %d druhu surovin za %s."):format(#plan, C.Money(total)))
end

-------------------------------------------------------------------------------
-- Načtení uložených dat
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, _, name)
    if name ~= ADDON then return end
    CrafterDB = CrafterDB or {}
    for k, v in pairs(DEFAULTS) do
        if CrafterDB[k] == nil then CrafterDB[k] = type(v) == "table" and CopyTable(v) or v end
    end
end)
