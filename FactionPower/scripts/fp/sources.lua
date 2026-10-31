--[[
  Sources: hook callbacks that turn game events into "deeds" for the model.
  Verified in game: quest completion (contracts, side quests; mail quests skipped) and the
  dominance recalculation. Written from the Blueprints, not yet seen firing: shop sales,
  dungeon door, boss deaths (DESIGN.md section 14).

  Callbacks only read game data and call FP.deed(); FP.deed() decides and applies.
  Every deed earns Faction Power (the main effect) and moves the local influence of the
  family that rules the system, and your relation with it.
]]

local U = require("fp.util")
local G = require("fp.gamedefs")
local W = require("fp.world")

local S = {}

local function param(p)
    if p == nil then return nil end
    local ok, v = pcall(function() return p:get() end)
    if ok then return v end
    return p
end

-- Owner (FamilyID) of a system and its parent faction (Falron, Xeghan, Morthra, Pirates, ...).
local function ownerOf(system)
    local owner = W.systemOwner(system)
    return owner, owner and W.familyParent(owner) or nil
end

local function arrayLen(a)
    local n = 0
    if not pcall(function() n = a:GetArrayNum() end) then pcall(function() n = #a end) end
    return n
end

---------------------------------------------------------------------------------
-- Sales: post-hook Bought_Slot_C:UpdateItem(Texture, InText, Sell?, Price).
-- The shop calls it once per sale (Sell? = true) or purchase (false), right after it
-- paid you; Shop_Widget.SoldItem and .Amount still hold the sale. The toast widget sits
-- in the shop's widget tree: Bought_Slot -> WidgetTree -> Shop_Widget (UNTESTED path).
local function outerShop(slot)
    local o = slot
    for _ = 1, 3 do
        local ok, parent = pcall(function() return o:GetOuter() end)
        if not (ok and U.valid(parent)) then return nil end
        local okN, cls = pcall(function() return parent:GetClass():GetFName():ToString() end)
        if okN and cls == "Shop_Widget_C" then return parent end
        o = parent
    end
    return nil
end

function S.onShopToast(self, _texture, _text, sell)
    local cfg = FP.cfg
    if not cfg.Sources.Sales or param(sell) ~= true then return end
    local slot = param(self)
    W.fromContext(slot)
    local shop = outerShop(slot)
    if not shop then U.log("sale: shop widget not found"); return end
    local item = U.get(shop, G.P.SoldItem)
    if not item then return end
    local kind = G.ItemType[U.get(item, G.Item.Type, -1)]
    local weight = kind and cfg.Sales.Strategic[kind] or 0
    if weight <= 0 then return end
    local amount = math.max(1, U.get(shop, G.P.Amount, 1))
    local units = amount * U.get(item, G.Item.Value, 0) / 1.4 / 10000 -- the shop pays Value / 1.4 (CalculateCut)
    local system = W.currentSystem(true)
    local owner, parent = ownerOf(system)
    if not owner then return end
    local f = parent == "Pirates" and cfg.Sales.PirateFactor or 1 -- black market: the pirates gain only slightly
    FP.deed({
        system = system, owner = owner, parent = parent,
        power = math.min(weight * units * cfg.Sales.FactionPowerPerTenThousand, cfg.Sales.MaxPowerPerSale) * f,
        influence = math.min(weight * units * cfg.Sales.InfluencePerTenThousand, cfg.Sales.MaxInfluencePerSale) * f,
        fatigueKey = system .. ":" .. kind, fatigueUnits = units,
        label = "sold " .. kind,
    })
end

---------------------------------------------------------------------------------
-- Missions. The quest data has no usable giver or target (GiverFaction is never set
-- by the contract generator), so the mod reasons from WHERE the mission happens
-- (SubGoals[0].Location) and WHAT kind it is:
--   help    (guard, escort, rescue)        -> the ruler of that system gains;
--   strike  (kill, clear, destroy, raid)   -> the enemies are pirates/raiders: the ruler
--                                             gains (its space is cleaner), unless the ruler
--                                             IS the target: a pirate-held system, or a bounty
--                                             on the ruler's faction -> the ruler loses;
--   your faction's operation (tag "Operation") -> the ruler of the target system loses.

local HELP = { GuardAsteroid = 0.75, GuardSalvage = 0.75, GuardConvoy = 1.0, GuardTrade = 1.0, GuardBase = 1.0,
    Escord = 1.0, SavePerson = 1.0, JoinGuard = 1.0, Foot_SavePerson = 1.0, DLC_HelpVillage = 1.0,
    DLC_HelpStation = 1.0, DLC_SaveSomeone = 1.0 }
local STRIKE = { KillOne = 0.75, KillMulti = 1.0, ClearArea = 1.25, DestroyBase = 1.5, Capture_Person = 1.0,
    JoinRaid = 1.5, Foot_KillOne = 0.75, Foot_Hack = 0.5, Foot_DestroyCrates = 0.5, Foot_Planet_SkinVilliage = 1.0,
    Foot_Planet_Kill_Outpost = 1.25, Foot_Planet_ClearCity = 1.5, DLC_DestroyHive = 1.25, DLC_DestroyShips = 1.25,
    DLC_GetItem = 0.5 }

local function questLocation(q)
    local goals = U.get(q, G.Quest.SubGoals)
    local first = goals and U.get(goals, 1)
    local loc = first and U.str(U.get(first, G.Quest.GoalLocation)) or ""
    if loc == "" or loc == "None" then return nil end
    return loc
end

-- Post-hook Game_Builder_C:AddNewQuest(QuestToAdd, ForceToAdd?, NoCContractSpawner?, out QuestTtOAdd)
-- Remembers what completion will no longer be able to read (bounty faction, location).
function S.onAddNewQuest(self, _quest, _force, _noSpawner, out)
    W.seen(param(self))
    local q = param(out)
    local tag = q and U.str(U.get(q, G.Quest.Tag)) or ""
    if tag == "" then return end
    local info = { system = questLocation(q), kind = G.QuestKind[U.get(q, G.Quest.Kind, -1)] }
    if info.kind == "Bounty" then
        -- BountyList[FindBountyIndex(ClintID)].Faction_24 (byte, G.FactionByte); TODO Phase 2
        info.bountyFaction = nil
    end
    FP.rememberQuest(tag, info)
end

-- Your faction's operation: the system it targets, from Game_Builder.OperationData.
local function operationSystem(gb)
    local op = U.get(gb, G.P.OperationData)
    local loc = op and U.get(op, G.Operation.Location)
    local s = loc and U.str(U.get(loc, G.Operation.SystemID)) or ""
    if s == "" or s == "None" then return nil end
    return s
end

-- Post-hook Game_Builder_C:CompleteQuest(Tag, Fail?, out Completed?)
function S.onCompleteQuest(self, tag, fail, completed)
    local cfg = FP.cfg
    local gb = param(self)
    W.seen(gb)
    U.log(string.format("CompleteQuest hook: tag=%s fail=%s completed=%s", U.str(param(tag)), tostring(param(fail)),
        tostring(param(completed))))
    -- Verified in game: the Completed? out param reads false in the post-hook even on success,
    -- so success = not Fail? and the quest is now in CompletedQuests (checked below).
    if not cfg.Sources.Missions or param(fail) == true then return end
    tag = U.str(param(tag))
    local info = FP.takeQuest(tag) or {}
    local M = cfg.Missions

    if tag == G.Operation.Tag then
        local system = operationSystem(gb)
        local owner, parent = ownerOf(system)
        if not owner or owner == G.PlayerFamilyID then return end
        -- vanilla already pays the operation (battle summaries, castles): influence and relation only
        FP.deed({ system = system, owner = owner, parent = parent, influence = M.HostileInfluence,
            family = owner, relation = -M.Relation, label = "operation" })
        return
    end

    -- the quest has just moved to CompletedQuests: search from the end
    local list = U.get(gb, G.P.CompletedQuests)
    local q
    if list then
        local n = arrayLen(list)
        for i = n, math.max(1, n - 20), -1 do
            local e = U.get(list, i)
            if e and U.str(U.get(e, G.Quest.Tag)) == tag then q = e; break end
        end
    end
    if not q then U.log("quest " .. tag .. ": not found in CompletedQuests"); return end
    local kind = G.QuestKind[U.get(q, G.Quest.Kind, -1)]
    local mail = U.get(q, G.Quest.Mail, false)
    U.log(string.format("quest %s: kind=%s mail=%s type=%s", tag, tostring(kind), tostring(mail),
        tostring(G.ContractType[U.get(q, G.Quest.Type, -1)])))
    if kind == "MainQuest" or mail then return end -- story / mail: vanilla pays Power
    local system = info.system or questLocation(q)
    local owner, parent = ownerOf(system)
    U.log(string.format("quest %s: system=%s owner=%s parent=%s", tag, tostring(system), tostring(owner), tostring(parent)))
    if not owner then return end

    local ctype = G.ContractType[U.get(q, G.Quest.Type, -1)] or ""
    local help, strike = HELP[ctype], STRIKE[ctype]
    local w = help or strike or 1.0
    local tier = U.clamp(U.get(q, G.Quest.Tier, 1), 1, 4)
    local power = M.FactionPower * w * (0.75 + 0.25 * tier)
    local hostile = (strike or kind == "Bounty") and
        (parent == "Pirates" or (info.bountyFaction ~= nil and info.bountyFaction == parent))
    local influence, relation
    if hostile then
        influence, relation = M.HostileInfluence * w, -M.Relation
    elseif help and parent == "Pirates" then
        influence, relation = 0, 0 -- guarding traders in pirate space does not help the pirates
    else
        influence, relation = (help and M.HelpInfluence or M.StrikeInfluence) * w, M.Relation
    end
    FP.deed({
        key = "quest:" .. tag .. ":" .. tostring(U.get(q, G.Quest.Accepted, 0)),
        system = system, owner = owner, parent = parent,
        power = power, influence = influence, family = owner, relation = relation,
        label = kind == "Bounty" and "bounty" or "mission",
    })
end

---------------------------------------------------------------------------------
-- Dungeons (galaxy dungeons: camps, scrapper colonies, caves, space). Post-hook
-- Q1_DungeonManager_C:InteractedWithDoor(DoorRole, DoorRef): role 2 is the door that marks
-- the current floor cleared (the manager then calls the native CurrentFloorCleared()).
-- The boss floor cleared = the dungeon is cleared. Not combat code: the fight is over.
function S.onDungeonDoor(self, role, _door)
    if not FP.cfg.Sources.Dungeons or param(role) ~= G.Dungeon.FloorClearedRole then return end
    local dm = param(self)
    W.fromContext(dm)
    local okD, d = pcall(function() return dm:GetCurrentDungeon() end)
    local okF, cur = pcall(function() return dm:GetCurrentFloor() end)
    if not (okD and d) then U.log("dungeon door: no current dungeon"); return end
    local floors = U.get(d, G.Dungeon.Floors)
    local n, boss = arrayLen(floors), false
    for i = 1, n do
        local f = U.get(floors, i)
        if f and okF and U.get(f, G.Dungeon.FloorIndex, -1) == cur then boss = U.get(f, G.Dungeon.Boss, false) == true end
    end
    if not okF and n > 0 then boss = true end -- unknown floor index: count once anyway (dedup by system)
    U.log(string.format("dungeon door: floor %s of %d cleared, boss=%s", tostring(cur), n, tostring(boss)))
    if not boss then return end
    local kind = G.DungeonType[U.get(d, G.Dungeon.Type, -1)]
    local system = U.str(U.get(d, G.Dungeon.System))
    S.onDungeonCleared({ final = true, system = system ~= "" and system ~= "None" and system or nil,
        level = U.get(d, G.Dungeon.Level, 0), raider = kind == "camp", creature = kind == "cave",
        name = U.str(U.get(d, G.Dungeon.Name)) })
end

-- Fallback for dungeons outside the dungeon manager (contract dungeons, surface dungeons):
-- "its boss died". Post-hooks on Q1_Shooter_AI_C:OnDeadEvent (HTR hooks it too) and
-- Q1_BP_Creature_C:OnDead (cave creatures). These run in combat, so they only read one
-- flag and queue; the 1 s loop calls S.onDungeonCleared 5 s later. Both paths share the
-- dedup key (one dungeon per system per RepeatDays), so a dungeon never counts twice.

function S.onNpcDead(self)
    if not FP.cfg.Sources.Dungeons then return end
    local npc = param(self)
    if U.get(npc, G.P.IsBoss, false) ~= true then return end -- every non-boss death stops here
    W.fromContext(npc)
    FP.queue({
        final = U.get(npc, G.P.FinalBoss, false) == true or U.get(npc, G.P.LegendBoss, false) == true,
        level = U.get(npc, G.P.Level, 0), raider = U.get(npc, G.P.Raider, false) == true,
    })
end

function S.onCreatureDead(self)
    if not FP.cfg.Sources.Dungeons then return end
    local c = param(self)
    if U.get(c, G.P.CreatureBoss, false) ~= true then return end
    W.fromContext(c)
    FP.queue({ final = true, level = U.get(c, G.P.Level, 0), creature = true })
end

function S.onDungeonCleared(info)
    local cfg = FP.cfg
    local gb = W.gameBuilder(true)
    if not gb then return end
    local where = G.WhereIsPlayer[U.get(gb, G.P.PlayerIsAt, -1)]
    -- a boss in a dungeon or a surface dungeon; elsewhere only a boss flagged final/legendary
    if not (where == "Dungeon" or where == "PlanetSurface" or info.final) then return end
    local system = info.system or W.currentSystem(true)
    local owner, parent = ownerOf(system)
    if not owner then return end
    local D = cfg.Dungeon
    local hostile = info.raider and parent == "Pirates" -- a pirate base in a pirate-held system
    local factor = 1
    if D.LevelScale then
        local sysData = U.get(gb, G.P.CurrentSystemData)
        local sysLevel = sysData and U.get(sysData, G.System.Level, 0) or 0
        local lvl = info.level or 0
        if sysLevel > 0 and lvl > sysLevel then factor = math.min(1.5, 1 + (lvl - sysLevel) / 20) end
    end
    FP.deed({
        -- one dungeon per system per RepeatDays (the dungeon's own ID is native; Phase 0)
        key = "dungeon:" .. system, system = system, owner = owner, parent = parent,
        power = D.FactionPower * factor,
        influence = (hostile and D.OwnerHostile or (D.Influence + D.BossBonus)) * factor,
        family = owner, relation = hostile and 0 or D.Relation,
        label = info.creature and "cave cleared" or "dungeon cleared",
    })
end

---------------------------------------------------------------------------------
-- Dominance recalculation: post-hook Game_Builder_C:CalculateDominance(System, ...).
-- The game rebuilds a system's dominance list when a system window opens; put the mod's
-- line back right after it (if the game had dropped it).
function S.onCalculateDominance(self, system)
    W.seen(param(self))
    if W.recalculating then return end -- our own recalculation: W.setInfluence adds the line
    FP.reapply(U.str(param(system)), true)
end

return S
