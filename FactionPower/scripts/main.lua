--[[
  Faction Power - your deeds shift the balance of SpaceBourne 2's factions.
  UE4SS Lua mod. On by default (config.lua Enabled); Shift+F9 switches it off/on.
  Tested in game: missions, Faction Power, relations, the dominance line, the key.
  Not yet seen in game: shop sales and dungeon ends (DESIGN.md section 14).

  Layout (same pattern as Hardcore Tactical Realism):
    config.lua        user settings
    fp/gamedefs.lua   every game-internal name (the only file to fix after a game patch)
    fp/model.lua      the power model: pure math (caps, fading, daily budgets)
    fp/ledger.lua     the mod's own per-character file (never the game's save)
    fp/world.lua      reads/changes the game's faction data through the game's own functions
    fp/sources.lua    hook callbacks: dungeons, sales, missions -> deeds
    fp/hooks.lua      safe lazy hook registration (copy of HTR's)
]]

local VERSION = "0.1.2"

local U = require("fp.util")

-- Settings -------------------------------------------------------------------
local DEFAULTS = {
    Enabled = true,
    ToggleKey = "F9", ToggleModifiers = { "SHIFT" }, StatusKey = "", StatusModifiers = { "SHIFT" },
    Channels = { FactionPower = true, Influence = true, Relations = true },
    Sources = { Dungeons = true, Sales = true, Commodities = false, Missions = true },
    Dungeon = { FactionPower = 600, Influence = 2.0, BossBonus = 1.0, OwnerHostile = -1.5, Relation = 1, LevelScale = true },
    Sales = { Strategic = {}, FactionPowerPerTenThousand = 150, InfluencePerTenThousand = 0.8, MaxPowerPerSale = 600,
        MaxInfluencePerSale = 1.5, PirateFactor = 0.5 },
    Commodities = { InfluencePerTenThousand = 0.2 },
    Missions = { FactionPower = 300, HelpInfluence = 1.5, StrikeInfluence = 1.5, HostileInfluence = -1.5, Relation = 2 },
    Limits = { GameTimePerDay = 600, FactionPowerPerDay = 2000, CapFraction = 0.25, CapMin = 3, CapMax = 20,
        CapDefault = 8, HalfLifeDays = 30, DailyPerSystem = 3, DailyPerFaction = 5, FatigueScale = 5, RepeatDays = 7,
        RelationPerDay = 4, JournalSize = 400 },
    Hud = { Notify = true, MinShown = 0.1 },
    Cleanup = false,
    Debug = { Log = false, SlowHookMs = 8 },
}

local function fill(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = v
        elseif type(v) == "table" and type(dst[k]) == "table" and next(v) ~= nil then
            fill(dst[k], v)
        end
    end
    return dst
end

local okCfg, cfg = pcall(require, "config")
if not okCfg or type(cfg) ~= "table" then
    U.warn("config.lua could not be read (" .. tostring(cfg) .. "); using defaults")
    cfg = {}
end
fill(cfg, DEFAULTS)
U.Verbose = cfg.Debug.Log

FP = { version = VERSION, cfg = cfg, on = false }

-- On/off, remembered in state.txt ---------------------------------------------
local STATE = U.Dir .. "state.txt"
do
    local f = io.open(STATE, "r")
    local s = f and f:read("a") or ""
    if f then f:close() end
    local v = s:match("on=(%a+)")
    if v then FP.on = (v == "true") else FP.on = cfg.Enabled == true end
    if cfg.Cleanup then FP.on = true end -- cleanup needs the mod running once
end

local function saveState()
    local f = io.open(STATE, "w")
    if f then f:write("on=" .. tostring(FP.on) .. "\n"); f:close() end
end

local H = require("fp.hooks")
-- Timed work on the game thread (gametick.lua, the set's shared file). No LoopAsync (UE4SS crash).
local GT = require("fp.gametick")
GT.log = function(msg) U.warn(msg) end
H.SLOW = cfg.Debug.SlowHookMs / 1000
local G = require("fp.gamedefs")
local M = require("fp.model")
local L = require("fp.ledger")
local W = require("fp.world")
local S = require("fp.sources")

U.warn(string.format("Faction Power %s loaded, %s", VERSION, FP.on and "ON" or "off"))

-- Ledger per character ---------------------------------------------------------
local openChar = nil
local pendingQuests = {} -- before a ledger is open

local function ensureLedger()
    local id = W.characterID()
    if not id then return L.state end
    if id ~= openChar then
        L.flush(0)
        L.open(id)
        openChar = id
        L.state.quests = L.state.quests or {}
        for tag, info in pairs(pendingQuests) do L.state.quests[tag] = info end
        pendingQuests = {}
        U.log("ledger open for " .. id)
    end
    return L.state
end

-- An older save of the same character was loaded: the game clock went back.
-- From the loop (`live` false) the earlier clock must be seen on 3 ticks in a row and not
-- be 0, so a clock read mid-load never rolls anything back. A deed (`live`) is in play.
local behind = 0
local function checkRollback(today, live)
    local St = L.state
    if not (St and today) or today <= 0.05 or today + 0.01 >= St.lastDay then behind = 0; return end
    if not live then
        behind = behind + 1
        if behind < 3 then return end
    end
    behind = 0
    local changed = M.rollback(St, today)
    for sys in pairs(changed) do FP.reapply(sys) end
    L.touch()
    U.log(string.format("older save loaded (day %.1f < %.1f): mod bookkeeping rolled back", today, St.lastDay))
end

function FP.rememberQuest(tag, info)
    local St = ensureLedger()
    local t = St and St.quests or pendingQuests
    t[tag] = info
    if St then L.touch() end
end

function FP.takeQuest(tag)
    local St = ensureLedger()
    local t = St and St.quests or pendingQuests
    local info = t[tag]
    t[tag] = nil
    if info and St then L.touch() end
    return info
end

-- Bring the mod's line for `system` up to date in the game (with fading). The ledger is the
-- source of truth: the game drops the line whenever it recalculates a system.
-- fromRecalc: called right after the game rebuilt the list (just add the line once).
function FP.reapply(system, fromRecalc)
    local St = L.state
    if not (St and system and St.systems[system]) then return end
    local today = W.today(cfg) or St.systems[system].day
    local s = M.touch(St, cfg.Limits, system, W.systemOwner(system), today)
    if fromRecalc then W.addLine(system, s.p) else W.setInfluence(system, s.p) end
end

-- HUD -----------------------------------------------------------------------
local function announce(d, r)
    if not cfg.Hud.Notify then return end
    local parts = {}
    if r.power > 0 then parts[#parts + 1] = string.format("+%d Faction Power", r.power) end
    local who = d.parent or d.owner or "?"
    if math.abs(r.influence) >= cfg.Hud.MinShown then
        parts[#parts + 1] = string.format("%s local support %+.1f", who, r.influence)
    end
    if r.relation ~= 0 then parts[#parts + 1] = string.format("relation with %s %+d", who, r.relation) end
    if #parts == 0 then return end
    pcall(U.notify, table.concat(parts, ", ") .. " (" .. (d.label or "deed") .. ")", W.gameBuilder())
end

-- One deed from a source: decide (model), apply (world), remember (ledger), show (HUD).
function FP.deed(d)
    if cfg.Cleanup then return end
    local today = W.today(cfg, true) -- a deed is rare: a lookup scan is allowed here
    local St = ensureLedger()
    if not (St and today) then U.log("deed skipped: no character or clock yet"); return end
    checkRollback(today, true)
    if d.system and not d.start then d.start = W.startDominance(d.system) end
    local r = M.apply(St, cfg, d, today, d.parent or d.owner)
    if r.influence ~= 0 then W.setInfluence(d.system, St.systems[d.system].p) end
    if r.power > 0 then W.addPower(r.power) end
    if r.relation ~= 0 then W.addRelation(d.family, r.relation) end
    L.touch()
    U.log(string.format("deed %s in %s (%s): influence %+.2f power %d relation %+d", d.label or "?", tostring(d.system),
        tostring(d.parent or d.owner), r.influence, r.power, r.relation))
    announce(d, r)
end

-- Removal helper (config Cleanup = true): for each character you load, zero every line the
-- mod wrote. No new deeds count while Cleanup is set.
local cleaned = {}
local function cleanup()
    local St = ensureLedger()
    if not (St and openChar and not cleaned[openChar] and W.familyManager(true)) then return end
    for sys, s in pairs(St.systems) do s.p = 0; W.setInfluence(sys, 0) end
    L.touch(); L.flush(0)
    cleaned[openChar] = true
    U.warn("cleanup done for " .. tostring(openChar))
    pcall(U.notify, "Faction Power: influence removed for this character. Set Cleanup = false or delete the mod.",
        W.gameBuilder())
end

-- Hooks (registered only while the mod is on) --------------------------------------
H.add(G.Fn.CalculateDominance, S.onCalculateDominance, "dominance recalculation")
H.add(G.Fn.AddNewQuest, S.onAddNewQuest, "quest accepted")
H.add(G.Fn.CompleteQuest, S.onCompleteQuest, "quest completed")
H.add(G.Fn.ShopToast, S.onShopToast, "shop sale")
if cfg.Sources.Dungeons then
    H.add(G.Fn.DungeonDoor, S.onDungeonDoor, "dungeon floor cleared")
    H.add(G.Fn.NpcDead, S.onNpcDead, "boss death")
    H.add(G.Fn.CreatureDead, S.onCreatureDead, "creature boss death")
end
-- Commodities (phase 3): G.Fn.SectorStock, not wired yet.

-- Boss deaths happen in combat: their hooks only queue; the loop handles them 5 s later
-- (a possible ~50 ms lookup then falls after the fight, not during it).
local queue = {}
function FP.queue(info)
    if #queue < 4 then info.t = os.clock(); queue[#queue + 1] = info end
end

-- Debug commands (only with Debug.Log = true): write one word into <mod>\debug_cmd.txt:
--   test   apply a small test deed in the current system (Power, influence, relation)
--   on|off switch the mod      status  show the status line
local DEBUG_CMD = U.Dir .. "debug_cmd.txt"
local function debugCommand()
    if not cfg.Debug.Log then return end
    local f = io.open(DEBUG_CMD, "r")
    if not f then return end
    local cmd = (f:read("a") or ""):match("%a+") or ""
    f:close(); os.remove(DEBUG_CMD)
    U.log("debug command: " .. cmd)
    if FP.debug then pcall(FP.debug, cmd) end
end

-- Once a second on the game thread, pumped by the HUD's drawing (gametick.lua);
-- started after each load or possession (ClientRestart). Until 0.1.1 this was LoopAsync +
-- ExecuteInGameThread: from UE4SS's async thread that writes a map all mods share without a
-- lock, and two mods at once crashed the game (UE4SS.dll+0x87c104).
GT.drive(GT.HUD_TICK, "hud") -- the player's HUD drawing: once per frame, on foot and in ships
GT.drive(GT.FOOT_TICK, "foot") -- fallback when the HUD is hidden (the pump runs once per frame anyway)
GT.boot()
GT.every(1.0, function()
    pcall(debugCommand)
    if not FP.on then return end
    local ok, err = pcall(function()
        H.poll(os.clock())
        if cfg.Cleanup then cleanup() end
        if #queue > 0 and os.clock() - queue[1].t > 5 then
            local q = queue; queue = {}
            for _, info in ipairs(q) do S.onDungeonCleared(info) end
        end
        if L.state then
            ensureLedger() -- another character loaded? (the game instance is cached by now: cheap)
            checkRollback(W.today(cfg))
            L.flush(30)
        end
    end)
    if not ok then U.warn("loop: " .. tostring(err)) end
end)

-- Keys ----------------------------------------------------------------------
local function statusText()
    local sys = W.currentSystem(true)
    local owner = W.systemOwner(sys)
    local St = ensureLedger()
    local s = St and sys and St.systems[sys]
    local cap = M.cap(cfg.Limits, sys and W.startDominance(sys))
    local gb = W.gameBuilder()
    local power = gb and U.get(gb, G.P.FactionPower) or "?"
    return string.format("Faction Power %s | %s held by %s (%s), local support %+.1f of +-%.0f",
        tostring(power), tostring(sys), tostring(owner), tostring(owner and W.familyParent(owner)), s and s.p or 0, cap)
end

local function status()
    pcall(U.notify, statusText(), W.gameBuilder())
end

local function toggle()
    FP.on = not FP.on
    saveState()
    if FP.on then H.wake() else L.flush(0) end
    U.warn("Faction Power " .. (FP.on and "ON" or "OFF"))
    local text = "Faction Power mod OFF"
    if FP.on then
        local ok, s = pcall(statusText)
        text = "Faction Power mod ON" .. (ok and (" | " .. s) or "")
    end
    pcall(U.notify, text, W.gameBuilder())
end

-- Keys with optional modifiers (shared laptop-safe key plan: DESIGN.md section 8).
-- Refused: the game's F1/F2/F5 (squad orders), F6 (quick save), F8 (quick load), F10 (bug
-- report), F12 (Steam screenshot), and the Ctrl/Alt modifiers (map / crouch on foot).
local GAME_KEYS = { F1 = true, F2 = true, F5 = true, F6 = true, F8 = true, F10 = true, F12 = true }
local function bindKey(name, mods, fn)
    if not name or name == "" or not (Key and Key[name]) then return end
    if GAME_KEYS[name] then U.warn(name .. " is a game key; not bound (see DESIGN.md section 8)"); return end
    local list = {}
    for _, m in ipairs(type(mods) == "table" and mods or {}) do
        if m ~= "SHIFT" then
            U.warn("modifier " .. tostring(m) .. " ignored: only SHIFT (Ctrl opens the map, Alt crouches)")
        elseif ModifierKey and ModifierKey[m] then
            list[#list + 1] = ModifierKey[m]
        end
    end
    local cb = function() ExecuteInGameThread(fn) end
    if #list > 0 then RegisterKeyBind(Key[name], list, cb) else RegisterKeyBind(Key[name], cb) end
end
bindKey(cfg.ToggleKey, cfg.ToggleModifiers, toggle)
bindKey(cfg.StatusKey, cfg.StatusModifiers, status)

function FP.debug(cmd)
    if cmd == "on" and not FP.on or cmd == "off" and FP.on then toggle()
    elseif cmd == "status" then status()
    elseif cmd == "test" and FP.on then
        local sys = W.currentSystem(true)
        local owner = W.systemOwner(sys)
        FP.deed({ system = sys, owner = owner, parent = owner and W.familyParent(owner), power = 100, influence = 1,
            family = owner, relation = 1, label = "debug test" })
    end
end
