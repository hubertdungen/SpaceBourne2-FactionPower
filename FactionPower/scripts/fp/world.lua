--[[
  Everything that reads or changes the game's own faction data. Verified in game 2026-10-31;
  originally written from
  the decompiled Blueprints; every call below must be checked in game (DESIGN.md, Phase 0)
  before the mod is switched on for real. Every call is wrapped in pcall.

  The game is only changed through the game's own functions:
    Q1FamilyManager:AddDominanceVariableToSystem  (the mod's one influence line per system)
    Game_Builder:"Add Remove Faction Power"       (your faction's Power, positive only)
    Q1FamilyManager:UpdateDiplomaticRelations     (off by default)
]]

local U = require("fp.util")
local G = require("fp.gamedefs")

local W = {}

-- Game_Builder and the family manager live for the whole session in the persistent
-- level. They are cached and re-checked with IsValid() before each use. A lookup by
-- scan (FindFirstOf, ~50 ms) happens only when `scan` is true (rare player actions:
-- a sale, a finished mission, a key press), at most once per LOOKUP_GAP seconds, and
-- never in the 1 s loop or in combat code. Hooks that run on Game_Builder pass `self`
-- to W.seen(), which fills the cache for free.
local LOOKUP_GAP = 10
local gb, fm, gi
local nextGB, nextFM, nextGI = 0, 0, 0

-- A load can leave the previous world in memory (HTR crash findings 2026-10-31), so an old
-- Game_Builder may still pass IsValid(): the live one always replaces it, and the family
-- manager is looked up again when the Game_Builder changes.
function W.seen(gameBuilder)
    if not U.valid(gameBuilder) then return end
    if gb ~= nil and U.valid(gb) and gb:GetAddress() == gameBuilder:GetAddress() then return end
    gb, fm = gameBuilder, nil
end

-- Cheap path from any live object (a hook's `self`): the player controller holds the
-- Game_Builder (Q1Controller.GameBuilderRef). GetPlayerController(ctx, 0) is instant, so it
-- runs on every call: the cache then always follows the current world.
function W.fromContext(ctx)
    if ctx == nil then return end
    pcall(function()
        local pc = U.gameplayStatics():GetPlayerController(ctx, 0)
        if U.valid(pc) then W.seen(pc[G.P.GameBuilderRef]) end
    end)
end

function W.gameBuilder(scan)
    if U.valid(gb) then return gb end
    if not scan or os.clock() < nextGB then return nil end
    nextGB = os.clock() + LOOKUP_GAP
    local ok, o = pcall(FindFirstOf, G.GameBuilderShort)
    gb = (ok and U.valid(o)) and o or nil
    return gb
end

function W.familyManager(scan)
    if U.valid(fm) then return fm end
    local b = W.gameBuilder(scan)
    local ref = b and U.get(b, G.P.FamilyManagerRef)
    if U.valid(ref) then fm = ref; return fm end
    if not scan or os.clock() < nextFM then return nil end
    nextFM = os.clock() + LOOKUP_GAP
    local ok, o = pcall(FindFirstOf, G.FamilyManagerShort)
    fm = (ok and U.valid(o)) and o or nil
    return fm
end

-- Character the loaded save belongs to (Q1GameInstance.CharacterID); keys the ledger.
function W.characterID()
    if not U.valid(gi) then
        if os.clock() < nextGI then return nil end
        nextGI = os.clock() + LOOKUP_GAP
        local ok, o = pcall(FindFirstOf, G.GameInstanceShort)
        gi = (ok and U.valid(o)) and o or nil
    end
    if not gi then return nil end
    local id = U.str(U.get(gi, G.P.CharacterID))
    if id == "" or id == "None" then id = U.str(U.get(gi, G.P.CharacterName)) end
    -- some saves have neither (seen in game): fall back to the save slot's name
    if id == "" or id == "None" then
        local slot = U.str(U.get(gi, G.P.LoadSaveFile))
        if slot ~= "" and slot ~= "None" then id = "slot_" .. slot end
    end
    if id == "" or id == "None" then return nil end
    return id
end

-- Game clock in game days (Game_Builder.CurrentGameTime / 600: ~10 min of play per day).
function W.today(cfg, scan)
    local b = W.gameBuilder(scan)
    local t = b and U.get(b, G.P.GameTime)
    if type(t) ~= "number" then return nil end
    return t / (cfg.Limits.GameTimePerDay or 600)
end

function W.currentSystem(scan)
    local b = W.gameBuilder(scan)
    local s = b and U.str(U.get(b, G.P.CurrentSolarID)) or ""
    if s == "" or s == "None" then return nil end
    return s
end

-- FamilyID (string) that owns `system`, or nil. The calls below only use the cache:
-- a source calls W.gameBuilder(true) / W.currentSystem(true) first when it may scan.
function W.systemOwner(system)
    local m = W.familyManager()
    if not (m and system) then return nil end
    local ok, id = pcall(function() return m:FindSystemOwner(FName(system)) end)
    local s = ok and U.str(id) or ""
    if s == "" or s == "None" then return nil end
    return s
end

-- Out parameters of native calls (verified in game, UE4SS 3.0.1): the Lua table passed is
-- filled with the struct's FIELDS directly (out.StartDominance, out.FamilyParentType);
-- arrays come back as Lua tables of params (element:get()).
local function field(out, key, sub)
    local v = out[key]
    if v == nil and sub and type(out[sub]) == "table" then v = out[sub][key] end
    if v == nil and sub and out[sub] ~= nil then v = U.get(out[sub], key) end
    return v
end

function W.familyParent(familyID)
    if familyID == G.PlayerFamilyID then return G.PlayerFamilyID end
    local m = W.familyManager()
    if not (m and familyID) then return nil end
    local out = {}
    local ok, found = pcall(function() return m:GetFamilyByID(FName(familyID), out) end)
    if not (ok and found) then return nil end
    local p = U.str(field(out, G.P.FamilyParentType, "OutFamily"))
    return (p ~= "" and p ~= "None") and p or nil
end

-- Dominance data of a system: { start = StartDominance, raid = RaidRequiredDominance,
-- line = the mod's own line's Point or nil if the game has no such line }.
function W.dominance(system)
    local m = W.familyManager()
    if not (m and system) then return nil end
    local out = {}
    local ok, found = pcall(function() return m:GetDominanceDataOfSystem(FName(system), out) end)
    if not (ok and found) then return nil end
    local r = { start = field(out, G.P.StartDominance, "OutData"), raid = field(out, G.P.RaidRequiredDominance, "OutData") }
    local vars = field(out, G.P.DominanceVariables, "OutData")
    if type(vars) == "table" then
        for _, e in pairs(vars) do
            local okV, v = pcall(function() return e:get() end)
            if not okV then v = e end
            if v and U.str(U.get(v, "ID")) == G.Dom.ID then
                local pt = U.get(v, "Point")
                if type(pt) == "number" then r.line = pt end
            end
        end
    end
    if type(r.start) ~= "number" then r.start = nil end
    return r
end

function W.startDominance(system)
    local d = W.dominance(system)
    return d and d.start or nil
end

-- The mod's influence line. Verified in game: AddDominanceVariableToSystem APPENDS (a second
-- call with the same ID adds a second line), and Game_Builder:CalculateDominance rebuilds the
-- system's list from scratch, dropping foreign lines. So the line is (re)added exactly once
-- right after a recalculation, and a changed value is written by recalculating first.
-- This also makes removal safe: without the mod, the next recalculation drops the line.
W.recalculating = false

function W.addLine(system, points)
    local m = W.familyManager()
    if not (m and system) or math.abs(points) < 0.005 then return false end
    return pcall(function()
        m:AddDominanceVariableToSystem(FName(system), {
            ID = FName(G.Dom.ID), Name = FName(G.Dom.Name), Type = FName(G.Dom.Type), Point = points,
        })
    end)
end

function W.setInfluence(system, points)
    local b = W.gameBuilder()
    if not (b and system) then return false end
    W.recalculating = true
    local ok = pcall(function() b:CalculateDominance(FName(system), false, {}, {}, {}) end)
    W.recalculating = false
    if not ok then return false end
    return W.addLine(system, points)
end

-- Your faction's Power (the game's own function; positive amounts only).
function W.addPower(amount)
    local b = W.gameBuilder()
    if not b or amount <= 0 then return false end
    return pcall(function() b[G.Fn.AddFactionPower](b, math.floor(amount), {}, {}) end)
end

function W.addRelation(familyID, delta)
    local m = W.familyManager()
    if not (m and familyID) or delta == 0 then return false end
    return pcall(function() m:UpdateDiplomaticRelations(FName(G.PlayerFamilyID), FName(familyID), delta, true) end)
end

return W
