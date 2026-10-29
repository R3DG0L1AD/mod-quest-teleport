--[[ 26_quest_teleport.lua  (FamilyLAN, WoWbot 2026-10-21, GO-LIVE\quest-teleport-20261021)
  "Teleport Near" for the FamQuestPort client addon.
  Client -> server: addon message prefix "FQP", whisper to self, text "TP:<questId>".
  The server checks the player really has the quest, picks a destination and, after a short
  "cast" (stand still, no combat), teleports the player ~25 yd away from it on open ground.
  Destination order:
    1. all objectives done      -> the quest ender (creature, else game object) spawn
    2. quest_poi objective area -> centroid of the POI polygon (nearest one if several)
    3. required NPC/GO spawn, or a creature/GO that drops a required item -> nearest spawn
    4. nothing found            -> friendly message
  Only to the four continents (0 Eastern Kingdoms, 1 Kalimdor, 530 Outland, 571 Northrend);
  crossing continents is allowed (CONFIG.ALLOW_CROSS_CONTINENT).
  UNDO: delete this file + reload ale (GO-LIVE\quest-teleport-20261021\UNDO-quest-teleport.ps1).
]]
local CONFIG = {
  PREFIX = "FQP",
  COOLDOWN = 60,              -- seconds between successful teleports (per character)
  MIN_GM_RANK = 0,            -- 0 = everyone; 1+ = GMs only
  CAST_SECONDS = 3,           -- "cast time": stand still, no combat
  OFFSET = 25,                -- yards away from the target point (stay out of the pack)
  ALLOW_CROSS_CONTINENT = true,
  CONTINENTS = { [0] = true, [1] = true, [530] = true, [571] = true },
  SELF_TEST = {},             -- quest ids to resolve + log once at load (debug), e.g. {871, 844}
}
local TAG = "[QuestPort]"
local lastUse, pending = {}, {}

local function msg(p, text) p:SendBroadcastMessage("|cff66ccff[Teleport Near]|r " .. text) end
local function safeCall(o, m, ...) local f = o and o[m]; if type(f) ~= "function" then return nil end
  local ok, r = pcall(f, o, ...); if ok then return r end; return nil end
local function IsBot(p)
  if safeCall(p, "IsBot") == true or safeCall(p, "IsPlayerbot") == true then return true end
  if safeCall(p, "GetPlayerIP") == "headless" then return true end
  local acc = safeCall(p, "GetAccountName")
  if type(acc) == "string" then local u = acc:upper()
    if u:find("^RNDBOT") or u:find("PLAYERBOT") or u:find("^AHBOT") or u:find("^RAIDBOT") then return true end end
  return false
end
local function q1(sql) local ok, r = pcall(WorldDBQuery, sql); if ok then return r end; return nil end
local function d2(ax, ay, bx, by) return math.sqrt((ax - bx)^2 + (ay - by)^2) end

-- nearest spawn of a list of creature (c) / game object (g) entries; prefers the player's map
local function nearestSpawn(cIds, gIds, pmap, px, py)
  local best
  local function scan(tbl, ids)
    if #ids == 0 then return end
    local q = q1(string.format("SELECT map, position_x, position_y, position_z FROM %s WHERE id IN (%s) AND map IN (0,1,530,571) LIMIT 400",
      tbl, table.concat(ids, ",")))
    if not q then return end
    repeat
      local m, x, y, z = q:GetUInt32(0), q:GetFloat(1), q:GetFloat(2), q:GetFloat(3)
      local score = (m == pmap) and d2(x, y, px, py) or (1e7 + d2(x, y, 0, 0) * 0)
      if not best or score < best.score then best = { map = m, x = x, y = y, z = z, score = score } end
    until not q:NextRow()
  end
  scan("creature", cIds); scan("gameobject", gIds)
  return best
end

local function resolve(questId, complete, pmap, px, py)
  -- 1. quest ender
  if complete then
    local c = {}; local q = q1("SELECT id FROM creature_questender WHERE quest=" .. questId)
    if q then repeat c[#c + 1] = q:GetUInt32(0) until not q:NextRow() end
    local g = {}; q = q1("SELECT id FROM gameobject_questender WHERE quest=" .. questId)
    if q then repeat g[#g + 1] = q:GetUInt32(0) until not q:NextRow() end
    local s = nearestSpawn(c, g, pmap, px, py)
    if s then s.why = "the quest turn-in"; return s end
  end
  -- 2. quest_poi objective areas (ObjectiveIndex >= 0), centroid of each polygon
  local q = q1("SELECT p.id, p.MapID, CAST(AVG(pt.X) AS FLOAT), CAST(AVG(pt.Y) AS FLOAT) FROM quest_poi p JOIN quest_poi_points pt ON pt.QuestID=p.QuestID AND pt.Idx1=p.id " ..
               "WHERE p.QuestID=" .. questId .. " AND p.ObjectiveIndex >= 0 AND p.MapID IN (0,1,530,571) GROUP BY p.id, p.MapID")
  if q then
    local best
    repeat
      local m, x, y = q:GetUInt32(1), q:GetFloat(2), q:GetFloat(3)
      local score = (m == pmap) and d2(x, y, px, py) or 1e7
      if not best or score < best.score then best = { map = m, x = x, y = y, score = score, why = "the quest area" } end
    until not q:NextRow()
    if best then return best end
  end
  -- 3. required NPC/GO, or whoever drops the required items
  local t = q1("SELECT RequiredNpcOrGo1,RequiredNpcOrGo2,RequiredNpcOrGo3,RequiredNpcOrGo4," ..
               "RequiredItemId1,RequiredItemId2,RequiredItemId3,RequiredItemId4,RequiredItemId5,RequiredItemId6 FROM quest_template WHERE ID=" .. questId)
  if t then
    local c, g, items = {}, {}, {}
    for i = 0, 3 do local v = t:GetInt32(i); if v > 0 then c[#c + 1] = v elseif v < 0 then g[#g + 1] = -v end end
    for i = 4, 9 do local v = t:GetUInt32(i); if v > 0 then items[#items + 1] = v end end
    local s = nearestSpawn(c, g, pmap, px, py)
    if s then s.why = "the quest target"; return s end
    if #items > 0 then
      local il = table.concat(items, ",")
      local lc, lg = {}, {}
      local r = q1("SELECT DISTINCT ct.entry FROM creature_template ct JOIN creature_loot_template l ON l.Entry=ct.lootid WHERE ct.lootid>0 AND l.Item IN (" .. il .. ") LIMIT 60")
      if r then repeat lc[#lc + 1] = r:GetUInt32(0) until not r:NextRow() end
      r = q1("SELECT DISTINCT gt.entry FROM gameobject_template gt JOIN gameobject_loot_template l ON l.Entry=gt.Data1 WHERE gt.type=3 AND l.Item IN (" .. il .. ") LIMIT 60")
      if r then repeat lg[#lg + 1] = r:GetUInt32(0) until not r:NextRow() end
      s = nearestSpawn(lc, lg, pmap, px, py)
      if s then s.why = "where the quest items can be found"; return s end
    end
  end
  return nil
end

-- pick an open spot ~OFFSET yd from the target: ground height known, few spawns nearby, not a cliff
local function landing(dest)
  local m = GetMapById(dest.map)
  local refZ = dest.z
  if not refZ then
    -- area point (POI centroid): anchor on the nearest real creature spawn (they stand on walkable ground),
    -- because terrain height alone can be a seabed or a cave ceiling
    local q = q1(string.format("SELECT position_x, position_y, position_z FROM creature WHERE map=%d AND position_x BETWEEN %f AND %f AND position_y BETWEEN %f AND %f " ..
      "ORDER BY (position_x-(%f))*(position_x-(%f))+(position_y-(%f))*(position_y-(%f)) LIMIT 1",
      dest.map, dest.x - 80, dest.x + 80, dest.y - 80, dest.y + 80, dest.x, dest.x, dest.y, dest.y))
    if q then
      dest = { map = dest.map, x = q:GetFloat(0), y = q:GetFloat(1), z = q:GetFloat(2), why = dest.why }
      refZ = dest.z
    else
      refZ = m and m:GetHeight(dest.x, dest.y) or nil
    end
  end
  if not refZ then return nil end
  local spawns = {}
  local q = q1(string.format("SELECT position_x, position_y FROM creature WHERE map=%d AND position_x BETWEEN %f AND %f AND position_y BETWEEN %f AND %f LIMIT 300",
    dest.map, dest.x - 45, dest.x + 45, dest.y - 45, dest.y + 45))
  if q then repeat spawns[#spawns + 1] = { q:GetFloat(0), q:GetFloat(1) } until not q:NextRow() end
  local best
  for i = 0, 7 do
    local a = i * math.pi / 4
    local x, y = dest.x + CONFIG.OFFSET * math.cos(a), dest.y + CONFIG.OFFSET * math.sin(a)
    local h = m and m:GetHeight(x, y)
    local score = 0
    for _, s in ipairs(spawns) do if d2(x, y, s[1], s[2]) < 12 then score = score + 1 end end
    if not h then score = score + 50 elseif math.abs(h - refZ) > 10 then score = score + 30 end
    if not best or score < best.score then best = { x = x, y = y, z = (h or refZ), score = score, o = a + math.pi } end
  end
  if best.score >= 30 then   -- every ring point is a cliff/unknown: stand right next to the target instead
    return { x = dest.x + 3, y = dest.y, z = refZ + 1.0, o = 0 }
  end
  best.z = best.z + 0.5
  return best
end

local function blocked(p)
  if p:IsDead() then return "You can't do that while you're a ghost." end
  if p:IsInCombat() then return "Not while you're in a fight!" end
  local map = p:GetMap()
  if not CONFIG.CONTINENTS[p:GetMapId()] or (map and (map:IsDungeon() or map:IsBattleground() or map:IsArena())) then
    return "That only works out in the open world, not in dungeons or battlegrounds." end
  return nil
end

local function request(p, questId)
  if IsBot(p) then return end
  if p:GetGMRank() < CONFIG.MIN_GM_RANK then msg(p, "Teleport Near isn't turned on for you yet."); return end
  local guid = p:GetGUIDLow()
  if pending[guid] then msg(p, "Already getting ready to teleport!"); return end
  local left = (lastUse[guid] or 0) + CONFIG.COOLDOWN - os.time()
  if left > 0 then msg(p, "Teleport Near is resting. Try again in " .. left .. " seconds."); return end
  local why = blocked(p); if why then msg(p, why); return end
  if not questId or questId <= 0 or not p:HasQuest(questId) then msg(p, "That quest isn't in your quest log."); return end
  local complete = (p:GetQuestStatus(questId) == 1)
  local dest = resolve(questId, complete, p:GetMapId(), p:GetX(), p:GetY())
  if not dest then msg(p, "Sorry, I couldn't find a good spot for that quest. Check the quest text for hints!"); return end
  if not CONFIG.CONTINENTS[dest.map] then msg(p, "Sorry, that quest's spot is somewhere I can't send you."); return end
  if dest.map ~= p:GetMapId() and not CONFIG.ALLOW_CROSS_CONTINENT then msg(p, "That quest is on another continent."); return end
  local spot = landing(dest)
  if not spot then msg(p, "Sorry, I couldn't find safe ground near that quest."); return end
  local sx, sy, sz = p:GetX(), p:GetY(), p:GetZ()
  pending[guid] = true
  msg(p, string.format("Teleporting near %s in %d seconds. Hold still!", dest.why, CONFIG.CAST_SECONDS))
  p:RegisterEvent(function(_, _, _, pl)
    pending[guid] = nil
    local w = blocked(pl)
    if w then msg(pl, "Teleport cancelled. " .. w); return end
    if d2(pl:GetX(), pl:GetY(), sx, sy) > 1.5 or math.abs(pl:GetZ() - sz) > 3 then msg(pl, "Teleport cancelled because you moved."); return end
    lastUse[guid] = os.time()
    pl:Teleport(dest.map, spot.x, spot.y, spot.z, spot.o)
    print(string.format("%s %s quest %d -> map %d %.1f %.1f %.1f (%s)", TAG, pl:GetName(), questId, dest.map, spot.x, spot.y, spot.z, dest.why))
  end, CONFIG.CAST_SECONDS * 1000, 1)
end

RegisterServerEvent(30, function(_, sender, mtype, prefix, text, target)
  if prefix ~= CONFIG.PREFIX or mtype ~= 7 or not sender or not text then return end
  if target and target.GetGUIDLow and target:GetGUIDLow() ~= sender:GetGUIDLow() then return end
  local id = tonumber((text:match("^TP:(%d+)$")))
  local ok, err = pcall(request, sender, id); if not ok then print(TAG .. " error: " .. tostring(err)) end
  return false
end)
RegisterPlayerEvent(4, function(_, p) pending[p:GetGUIDLow()] = nil end)   -- logout

for _, qid in ipairs(CONFIG.SELF_TEST) do
  for _, complete in ipairs({ false, true }) do
    local ok, dest = pcall(resolve, qid, complete, 1, -500, -2600)   -- pretend the player stands in the Barrens
    if ok and dest then
      local spot = landing(dest)
      print(string.format("%s TEST quest %d complete=%s -> %s map %d target %.1f %.1f -> land %s", TAG, qid, tostring(complete), dest.why, dest.map, dest.x, dest.y,
        spot and string.format("%.1f %.1f %.1f", spot.x, spot.y, spot.z) or "none"))
    else
      print(string.format("%s TEST quest %d complete=%s -> nothing found%s", TAG, qid, tostring(complete), ok and "" or (" ERR " .. tostring(dest))))
    end
  end
end
print(string.format("%s loaded (cooldown %ds, min GM rank %d, cast %ds, cross-continent %s)", TAG,
  CONFIG.COOLDOWN, CONFIG.MIN_GM_RANK, CONFIG.CAST_SECONDS, tostring(CONFIG.ALLOW_CROSS_CONTINENT)))
