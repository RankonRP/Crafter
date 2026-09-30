// Vytáhne z CMaNGOS classic-db, kde se sehnají suroviny profesí, a zapíše Crafter/Zdroje.lua.
//   node tools/zdroje.js <cesta k ClassicDB.sql>
// Zdroje: prodejci (npc_vendor), kořist z mobů (creature_loot), stahování (skinning_loot),
// sběr z bylin/rud/truhel (gameobject_loot), výroba (spell_template). Poloha = vzorek spawnů
// (světové souřadnice), na zónu a mapu je ve hře převede addon sám (C_Map).
const fs = require("fs");
const path = require("path");

const sqlPath = process.argv[2];
if (!sqlPath) { console.error("použití: node tools/zdroje.js <ClassicDB.sql>"); process.exit(1); }
const sql = fs.readFileSync(sqlPath, "utf8");

// --- čtení SQL dumpu -------------------------------------------------------
function columns(table) {
  const m = sql.match(new RegExp("CREATE TABLE `" + table + "` \\(([\\s\\S]*?)\\n\\)"));
  if (!m) throw new Error("tabulka " + table + " nenalezena");
  const cols = {};
  let i = 0;
  for (const line of m[1].split("\n")) {
    const c = line.match(/^\s*`([^`]+)`/);
    if (c) { if (!(c[1] in cols)) cols[c[1]] = i; i++; }
  }
  return cols;
}

function parseTuples(s, out) {
  let i = s.indexOf("VALUES") + 6, row = null, val = "", inStr = false, isStr = false;
  for (; i < s.length; i++) {
    const c = s[i];
    if (inStr) {
      if (c === "\\") { const n = s[++i]; val += n === "n" ? "\n" : n === "r" ? "\r" : n === "t" ? "\t" : n; }
      else if (c === "'") { if (s[i + 1] === "'") { val += "'"; i++; } else inStr = false; }
      else val += c;
    } else if (c === "(" && !row) { row = []; val = ""; isStr = false; }
    else if (c === "'") { inStr = true; isStr = true; }
    else if (row && (c === "," || c === ")")) {
      row.push(isStr ? val : (val.trim() === "NULL" ? "" : val.trim())); val = ""; isStr = false;
      if (c === ")") { out.push(row); row = null; }
    } else if (row) val += c;
  }
}

function rows(table) {
  const out = [];
  const prefix = "INSERT INTO `" + table + "` VALUES";
  let pos = 0;
  while ((pos = sql.indexOf(prefix, pos)) !== -1) {
    const end = sql.indexOf(";\n", pos);
    parseTuples(sql.slice(pos, end + 1), out);
    pos = end;
  }
  const cols = columns(table);
  return out.map((r) => new Proxy(r, { get: (t, k) => (k in cols ? t[cols[k]] : t[k]) }));
}
const num = (v) => Number(v) || 0;

// --- položky: suroviny z receptů + obchodní zboží ---------------------------
console.log("čtu item_template…");
const items = {};
for (const r of rows("item_template")) items[r.entry] = { name: r.name, cls: num(r.class), sub: num(r.subclass), buy: num(r.BuyPrice), buyCount: Math.max(1, num(r.BuyCount)) };

console.log("čtu spell_template…");
const crafted = {};     // itemID -> [názvy receptů]
const craftFrom = {};   // itemID -> [[surovina, počet], …] z prvního receptu (Copper Bar <- Copper Ore ×1)
const wanted = new Set();
for (const s of rows("spell_template")) {
  for (let e = 1; e <= 3; e++) {
    if (num(s["Effect" + e]) !== 24) continue;          // SPELL_EFFECT_CREATE_ITEM
    const made = s["EffectItemType" + e];
    if (!made || !items[made]) continue;
    let hasReagent = false;
    const list = [];
    for (let k = 1; k <= 8; k++) {
      const rg = s["Reagent" + k];
      if (rg && rg !== "0" && items[rg]) { wanted.add(rg); hasReagent = true; list.push([Number(rg), Math.max(1, num(s["ReagentCount" + k]))]); }
    }
    if (hasReagent) {
      (crafted[made] = crafted[made] || []).push(s.SpellName);
      // nejjednodušší recept (nejméně druhů surovin) – pro řetězec „bar z rudy“
      if (!craftFrom[made] || list.length < craftFrom[made].length) craftFrom[made] = list;
    }
  }
}
for (const [id, it] of Object.entries(items)) if (it.cls === 7) wanted.add(id);   // Trade Goods
console.log("surovin:", wanted.size);

// --- tvorové a jejich spawny ------------------------------------------------
console.log("čtu creature_template…");
const ct = {};
const byLoot = {}, bySkin = {}, byVendorTpl = {};
for (const r of rows("creature_template")) {
  ct[r.Entry] = { name: r.Name, sub: r.SubName, min: num(r.MinLevel), max: num(r.MaxLevel) };
  if (num(r.LootId)) (byLoot[r.LootId] = byLoot[r.LootId] || []).push(r.Entry);
  if (num(r.SkinningLootId)) (bySkin[r.SkinningLootId] = bySkin[r.SkinningLootId] || []).push(r.Entry);
  if (num(r.VendorTemplateId)) (byVendorTpl[r.VendorTemplateId] = byVendorTpl[r.VendorTemplateId] || []).push(r.Entry);
}

// vzorek bodů: jeden na čtverec 150 yardů, nejvýš 40 – aby šla vidět celá oblast výskytu
// body jako trojice {mapa, x, y, mapa, x, y…} – oba kontinenty (rudy a byliny rostou na obou)
function sample(points) {
  if (!points.length) return null;
  const byMap = {};
  for (const p of points) (byMap[p.map] = byMap[p.map] || []).push(p);
  const cut = [];
  for (const [map, list] of Object.entries(byMap)) {
    const seen = new Set(), pts = [];
    for (const p of list) {
      const key = Math.round(p.x / 150) + ":" + Math.round(p.y / 150);
      if (seen.has(key)) continue;
      seen.add(key);
      pts.push([Math.round(p.x), Math.round(p.y)]);
    }
    const step = Math.max(1, Math.ceil(pts.length / 40));
    for (let i = 0; i < pts.length; i += step) cut.push(Number(map), pts[i][0], pts[i][1]);
  }
  return { pts: cut, count: points.length };
}

console.log("čtu spawny…");
const cSpawns = {};
for (const r of rows("creature")) {
  const map = num(r.map);
  if (map !== 0 && map !== 1) continue;   // jen venkovní svět (Eastern Kingdoms, Kalimdor)
  (cSpawns[r.id] = cSpawns[r.id] || []).push({ map, x: num(r.position_x), y: num(r.position_y) });
}
const gSpawns = {};
for (const r of rows("gameobject")) {
  const map = num(r.map);
  if (map !== 0 && map !== 1) continue;
  (gSpawns[r.id] = gSpawns[r.id] || []).push({ map, x: num(r.position_x), y: num(r.position_y) });
}

// --- kořist (i přes reference_loot_template) --------------------------------
console.log("čtu kořist…");
const refItems = {};   // referenceId -> { itemID: šance }
for (const r of rows("reference_loot_template")) {
  if (num(r.mincountOrRef) < 0) continue;
  (refItems[r.entry] = refItems[r.entry] || {})[r.item] = Math.abs(num(r.ChanceOrQuestChance));
}
function lootIndex(table) {
  const idx = {};   // itemID -> [{ entry, chance }]
  for (const r of rows(table)) {
    const chance = num(r.ChanceOrQuestChance);
    if (chance < 0) continue;   // questové předměty
    if (num(r.mincountOrRef) < 0) {
      const ref = refItems[-num(r.mincountOrRef)] || {};
      for (const [item, c] of Object.entries(ref)) {
        if (!wanted.has(item)) continue;
        (idx[item] = idx[item] || []).push({ entry: r.entry, chance: (chance || 100) * (c || 100) / 100 });
      }
    } else if (wanted.has(r.item)) {
      (idx[r.item] = idx[r.item] || []).push({ entry: r.entry, chance: chance || 100 });
    }
  }
  return idx;
}
const dropIdx = lootIndex("creature_loot_template");
const skinIdx = lootIndex("skinning_loot_template");
const goIdx = lootIndex("gameobject_loot_template");

const goByLoot = {};
for (const r of rows("gameobject_template")) {
  if (num(r.type) === 3 && num(r.data1)) (goByLoot[r.data1] = goByLoot[r.data1] || []).push({ id: r.entry, name: r.name });
}

// --- prodejci ---------------------------------------------------------------
const vendorIdx = {};
for (const r of rows("npc_vendor")) if (wanted.has(r.item)) (vendorIdx[r.item] = vendorIdx[r.item] || new Set()).add(r.entry);
for (const r of rows("npc_vendor_template")) {
  if (!wanted.has(r.item)) continue;
  for (const c of byVendorTpl[r.entry] || []) (vendorIdx[r.item] = vendorIdx[r.item] || new Set()).add(c);
}

// --- sestavení -------------------------------------------------------------
const npcOut = {}, objOut = {};
function useNpc(id) {
  if (npcOut[id]) return true;
  const c = ct[id], sp = cSpawns[id] && sample(cSpawns[id]);
  if (!c || !sp) return false;
  npcOut[id] = { n: c.name, s: c.sub, l1: c.min, l2: c.max, p: sp.pts };
  return true;
}
function useObj(id, name) {
  if (objOut[id]) return true;
  const sp = gSpawns[id] && sample(gSpawns[id]);
  if (!sp) return false;
  objOut[id] = { n: name, p: sp.pts, c: sp.count };
  return true;
}

const out = {};
for (const id of wanted) {
  const it = items[id];
  if (!it) continue;
  const e = { n: it.name };   // jméno předmětu (záloha, když ho hra ještě nezná)
  const vendors = [...(vendorIdx[id] || [])].filter(useNpc);   // všichni – nejbližšího vybírá addon podle polohy
  if (vendors.length) { e.v = vendors.map(Number); e.price = Math.round(it.buy / it.buyCount); }

  const mobs = (list, max) => {
    const best = {};
    for (const { entry, chance } of list || []) for (const c of byLoot[entry] || []) best[c] = Math.max(best[c] || 0, chance);
    return Object.entries(best).filter(([c]) => useNpc(c)).sort((a, b) => b[1] - a[1]).slice(0, max)
      .map(([c, ch]) => [Number(c), Math.round(ch * 10) / 10]);
  };
  const drops = mobs(dropIdx[id], 16).filter(([, ch]) => ch >= 2);
  if (drops.length) e.d = drops;

  const skinBest = {};
  for (const { entry, chance } of skinIdx[id] || []) for (const c of bySkin[entry] || []) skinBest[c] = Math.max(skinBest[c] || 0, chance);
  const skins = Object.keys(skinBest).filter(useNpc).sort((a, b) => ct[a].min - ct[b].min).slice(0, 30);
  if (skins.length) e.s = skins.map(Number);

  const nodes = {};
  // truhly, bedny a sudy mají náhodnou kořist – nejsou to místa, kde se surovina sbírá
  const CONTAINER = /chest|crate|box|barrel|footlocker|trunk|cache|coffer|strongbox|stash|sack|basket|locker|bag\b|pile|supplies|package/i;
  for (const { entry, chance } of goIdx[id] || []) for (const g of goByLoot[entry] || []) {
    if (CONTAINER.test(g.name)) continue;
    if (!nodes[g.id] || nodes[g.id].chance < chance) nodes[g.id] = { name: g.name, chance };
  }
  const g = Object.entries(nodes).filter(([gid, v]) => useObj(gid, v.name))
    .sort((a, b) => b[1].chance - a[1].chance).slice(0, 6).map(([gid, v]) => [Number(gid), Math.round(v.chance)]);
  if (g.length) e.g = g;

  if (crafted[id]) { e.c = [...new Set(crafted[id])].slice(0, 3); e.r = craftFrom[id]; }
  if (Object.keys(e).length > 1) out[id] = e;
}

// --- ložiska rud a byliny: VŠECHNA místa (pro mapu a minimapu jako Gatherer) -----
// ruda = ložisko s „Vein“/„Deposit“ v názvu, bylina = kořist obsahuje bylinu (třída 7, podtřída 9)
const goLoot = {};   // loot entry -> [itemID]
for (const r of rows("gameobject_loot_template")) {
  const list = (goLoot[r.entry] = goLoot[r.entry] || []);
  if (num(r.mincountOrRef) < 0) for (const it of Object.keys(refItems[-num(r.mincountOrRef)] || {})) list.push(it);
  else list.push(r.item);
}
const nodeOut = {};
let nodePoints = 0;
for (const r of rows("gameobject_template")) {
  if (num(r.type) !== 3 || !num(r.data1)) continue;
  const loot = goLoot[r.data1] || [];
  let kind = null, main = null;
  if (/vein|deposit/i.test(r.name)) {
    kind = "m";
    main = loot.find((i) => items[i] && /ore$/i.test(items[i].name)) || loot.find((i) => items[i] && items[i].cls === 7);
  } else {
    const herb = loot.find((i) => items[i] && items[i].cls === 7 && items[i].sub === 9);
    if (herb && !/chest|crate|box|barrel|sack|basket|stash|cache/i.test(r.name)) { kind = "h"; main = herb; }
  }
  if (!kind || !gSpawns[r.entry]) continue;
  const pts = [];
  for (const p of gSpawns[r.entry]) pts.push(p.map, Math.round(p.x), Math.round(p.y));
  nodeOut[r.entry] = { n: r.name, t: kind, i: Number(main) || 0, p: pts };
  nodePoints += pts.length / 3;
}

// --- zápis do Lua ------------------------------------------------------------
const q = (s) => '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n") + '"';
function lua(v) {
  if (Array.isArray(v)) return "{" + v.map(lua).join(",") + "}";
  if (v && typeof v === "object") return "{" + Object.entries(v).filter(([, x]) => x !== "" && x != null).map(([k, x]) => k + "=" + lua(x)).join(",") + "}";
  if (typeof v === "number") return String(v);
  return q(v);
}
let s = "-- Generuje tools/zdroje.js z CMaNGOS classic-db. Neupravuj ručně.\n";
s += "-- Crafter_Zdroje[itemID] = { v = prodejci, price = cena/ks, d = {{mob, šance}}, s = stahování, g = {{uzel, šance}}, c = recepty }\n";
s += "Crafter_Zdroje = {\n";
for (const [id, e] of Object.entries(out)) s += "[" + id + "]=" + lua(e) + ",\n";
s += "}\n-- Crafter_NPC[id] = { n = jméno, s = podtitul, l1/l2 = úroveň, p = {mapa,x,y, mapa,x,y…} (mapa 0 = Eastern Kingdoms, 1 = Kalimdor) }\nCrafter_NPC = {\n";
for (const [id, e] of Object.entries(npcOut)) s += "[" + id + "]=" + lua(e) + ",\n";
s += "}\n-- Crafter_OBJ[id] = { n = jméno (bylina, žíla), p = {mapa,x,y…}, c = počet spawnů }\nCrafter_OBJ = {\n";
for (const [id, e] of Object.entries(objOut)) s += "[" + id + "]=" + lua(e) + ",\n";
s += "}\n";
// místa rud a bylin z databáze (nodeOut) se nepřibalují – mapa Crafteru ukazuje jen vlastní nálezy hráče
const target = path.join(__dirname, "..", "Crafter", "Zdroje.lua");
fs.writeFileSync(target, s);
console.log(`hotovo: surovin se zdrojem ${Object.keys(out).length}, NPC ${Object.keys(npcOut).length}, objektů ${Object.keys(objOut).length}, ${Math.round(s.length / 1024)} kB`);
for (const probe of ["2318", "2589", "2770", "2447", "2320"]) console.log(probe, items[probe] && items[probe].name, JSON.stringify(out[probe]).slice(0, 300));
