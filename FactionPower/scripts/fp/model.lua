--[[
  The power model: pure math on plain Lua tables, no game calls.
  (Not run yet: there is no Lua interpreter in the dev setup and nothing has been tested
  in game. See DESIGN.md, "Model".)

  Units
    power      Faction Power, the game's currency of your faction (Game_Builder.FactionPower).
               The main effect.
    influence  dominance points, the same unit the game uses for a solar system's
               dominance (a planet is worth 2-6, public order 2-20, a trade route 8-16;
               a system totals roughly 30-100). Positive = helps the system's owner.
    relation   the -100..100 relation between your faction ("WRA") and a family.
    day        a game day (world.lua converts the game clock; see Limits.GameTimePerDay).

  A "deed" is what a source reports:
    { key = dedup key or nil, system = SystemID, owner = FamilyID, start = StartDominance or nil,
      influence = raw points, power = raw Power, family = FamilyID or nil, relation = raw delta,
      fatigueKey = string or nil, fatigueUnits = size of the deed (10 000 credits = 1),
      label = text for the HUD }
]]

local M = {}

-- Largest |influence| the mod may hold in one system.
function M.cap(L, start)
    if not start or start <= 0 then return L.CapDefault end
    return math.max(L.CapMin, math.min(L.CapMax, start * L.CapFraction))
end

-- Exponential fade toward 0 (favors and grudges are forgotten).
function M.decay(points, dtDays, halfLife)
    if not halfLife or halfLife <= 0 or not dtDays or dtDays <= 0 then return points end
    return points * 0.5 ^ (dtDays / halfLife)
end

-- Saturating step: the closer the system already is to the cap in the same
-- direction, the less a new deed moves it. Returns the actual change.
function M.saturate(points, raw, cap)
    if raw == 0 or cap <= 0 then return 0 end
    local same = raw > 0 and math.max(0, points) or math.max(0, -points)
    local room = math.max(0, 1 - same / cap)
    local after = math.max(-cap, math.min(cap, points + raw * room))
    return after - points
end

-- Take up to |amount| from a daily budget; returns the signed part that fits.
function M.budget(book, key, amount, limit)
    if not limit or limit <= 0 then return amount end
    local used = book[key] or 0
    local mag = math.min(math.abs(amount), math.max(0, limit - used))
    book[key] = used + mag
    return amount >= 0 and mag or -mag
end

-- Market saturation: repeated sales of the same kind in the same place on the same
-- day count for less: factor 1, 1/2, 1/3 ... as the day's total grows by `scale` units.
function M.fatigue(book, key, units, scale)
    if not key or not scale or scale <= 0 then return 1 end
    local prior = book[key] or 0
    book[key] = prior + math.abs(units or 1)
    return 1 / (1 + prior / scale)
end

-- New, empty ledger state for one character.
function M.newState(character)
    return { version = 1, character = character, lastDay = 0, systems = {}, seen = {}, journal = {}, daily = { day = -1 } }
end

local function daily(S, day)
    local d = math.floor(day)
    if S.daily.day ~= d then S.daily = { day = d, sys = {}, fac = {}, power = {}, rel = {}, fat = {} } end
    return S.daily
end

-- Bring one system's stored influence up to `day` (decay) and reset it if the owner changed.
function M.touch(S, L, system, owner, day)
    local s = S.systems[system]
    if not s then
        s = { p = 0, owner = owner, day = day }
        S.systems[system] = s
    end
    if owner and s.owner ~= owner then
        -- local support for the old ruler does not transfer to a conqueror
        s.p, s.owner = 0, owner
    end
    s.p = M.decay(s.p, day - (s.day or day), L.HalfLifeDays)
    if math.abs(s.p) < 0.01 then s.p = 0 end
    s.day = day
    return s
end

--[[ Apply one deed at time `day`. Returns { influence, power, relation } actually granted.
  Order: dedup -> fatigue -> per-system and per-faction daily budgets -> saturation.
  `faction` is the owner's parent faction (Falron, Xeghan, Morthra, Pirates, Earthling, WRA...),
  used for the galaxy-wide daily budget. ]]
function M.apply(S, cfg, deed, day, faction)
    local L = cfg.Limits
    local out = { influence = 0, power = 0, relation = 0 }
    if deed.key then
        local seenDay = S.seen[deed.key]
        if seenDay and day - seenDay < L.RepeatDays then return out end
        S.seen[deed.key] = day
    end
    local D = daily(S, day)
    local fat = M.fatigue(D.fat, deed.fatigueKey, deed.fatigueUnits, L.FatigueScale)

    local pw = (deed.power or 0) * fat
    if pw > 0 and cfg.Channels.FactionPower then
        out.power = math.floor(M.budget(D.power, "all", pw, L.FactionPowerPerDay))
    end

    local raw = (deed.influence or 0) * fat
    if raw ~= 0 and deed.system and cfg.Channels.Influence then
        raw = M.budget(D.sys, deed.system, raw, L.DailyPerSystem)
        raw = M.budget(D.fac, faction or "?", raw, L.DailyPerFaction)
        local s = M.touch(S, L, deed.system, deed.owner, day)
        local d = M.saturate(s.p, raw, M.cap(L, deed.start))
        s.p = s.p + d
        out.influence = d
        if d ~= 0 then
            local j = S.journal
            j[#j + 1] = { day = day, system = deed.system, d = d }
            while #j > L.JournalSize do table.remove(j, 1) end
        end
    end

    local rel = deed.relation or 0
    if rel ~= 0 and deed.family and cfg.Channels.Relations then
        local r = M.budget(D.rel, deed.family, rel, L.RelationPerDay)
        out.relation = r >= 0 and math.floor(r + 0.5) or -math.floor(-r + 0.5)
    end

    if day > S.lastDay then S.lastDay = day end
    return out
end

-- The player loaded an older save of the same character: undo the mod's own
-- bookkeeping that happened "in the future". (Power and relations live in the game's
-- save, so the game already restored them.) Returns the list of systems changed.
function M.rollback(S, day)
    if day >= S.lastDay then return {} end
    local changed, keep = {}, {}
    for _, e in ipairs(S.journal) do
        if e.day > day then
            local s = S.systems[e.system]
            if s then s.p = s.p - e.d; changed[e.system] = true end
        else
            keep[#keep + 1] = e
        end
    end
    S.journal = keep
    for k, d in pairs(S.seen) do if d > day then S.seen[k] = nil end end
    S.daily = { day = -1 }
    S.lastDay = day
    return changed
end

return M
