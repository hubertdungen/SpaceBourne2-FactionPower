--[[
  gametick.lua 1.0 - timed work on the game thread, without LoopAsync / ExecuteWithDelay.
  One source for every SB2 Realism mod (side-session-notes\...\gametick.lua); copy it unchanged.

  Why: UE4SS 3.0.1 runs LoopAsync / ExecuteWithDelay / ExecuteAsync callbacks on each mod's own
  thread WITHOUT its lock. ExecuteInGameThread (also RegisterHook, NotifyOnNewObject) called from
  there adds a Lua thread to one map that every mod shares, unlocked; two mods doing it at once
  break the map and the game crashes (UE4SS.dll+0x87c104 / +0x87ac32, seen 7 times). Hook
  callbacks on Blueprint functions, key binds and ExecuteInGameThread actions run under UE4SS's
  lock. So: no LoopAsync / ExecuteWithDelay / ExecuteAsync at all; timed work runs here,
  pumped from game-thread hooks.

  Use:
    local GT = require("<mod>.gametick")
    GT.every(1.0, fn)       -- fn(now) every second, first at the next pump; return true to stop
    GT.after(2.1, fn)       -- fn(now) once, 2.1 s from now
    GT.pump()               -- call from game-thread hooks (a Blueprint ReceiveTick is best)
    GT.drive(path)          -- a Blueprint function that pumps (e.g. a ReceiveTick); hooked from
                            -- the game thread as soon as its class is loaded (see GT.boot)
    GT.boot(fn)             -- hooks PlayerController:ClientRestart (every load / possession) to
                            -- run fn(now), hook pending drivers and pump. Call once, at load.
  Where it pumps (SB2, measured 2026-11-06 with HTR):
    on foot   GT.FOOT_TICK (ALS characters, ~80 calls/s)
    in space  GT.SHIP_TICK only: no ALS character ticks in a ship (~117 calls/s)
    main menu nothing: no ClientRestart, no map tick. Work for the main menu (or for paused
              screens, if the game pauses ticks there) needs one of the mod's own hooks on a
              widget function: call GT.pump() at the top of any hook callback, it costs nothing.
    a load    ClientRestart fires after each load and possession (ship <-> foot): drivers are
              hooked again if their class was reloaded, then the pump goes on.
  Cost: GT.pump is one os.clock() and one compare until a job is due, and runs jobs at most once
  every GT.MIN_GAP seconds (several ReceiveTicks per frame cost nothing extra).
  Key binds may keep calling ExecuteInGameThread: they run under UE4SS's lock.
]]

local GT = { jobs = {}, drivers = {}, due = math.huge, last = -1e9, running = false, MIN_GAP = 0.005,
    -- SB2 game-thread ticks for GT.drive (every frame, for every such actor):
    FOOT_TICK = "/Game/Locomotion/Blueprints/CharacterLogic/ALS_Base.ALS_Base_C:ReceiveTick", -- every ALS character
    SHIP_TICK = "/Game/1Data/SB2Ships/Q1_Master_Ship.Q1_Master_Ship_C:ReceiveTick",           -- every ship
    MAX_ERRORS = 25, log = function(msg) print("[gametick] " .. tostring(msg) .. "\n") end,
    stats = { pumps = 0, runs = 0, time = 0, worst = 0, by = {} } }

local function nextDue()
    local d = math.huge
    for _, j in ipairs(GT.jobs) do if j.at < d then d = j.at end end
    GT.due = d
end

local function add(job)
    GT.jobs[#GT.jobs + 1] = job
    if job.at < GT.due then GT.due = job.at end
    return job
end

-- fn(now) every `seconds`; first run at the next pump (or `first` seconds from now).
function GT.every(seconds, fn, first)
    return add({ fn = fn, every = seconds, at = os.clock() + (first or 0), errors = 0 })
end

-- fn(now) once, `seconds` from now.
function GT.after(seconds, fn)
    return add({ fn = fn, at = os.clock() + seconds, errors = 0 })
end

function GT.cancel(job)
    if job then job.dead = true end
end

-- src: optional tag counted in GT.report ("foot", "ship", ...).
function GT.pump(src)
    if src then local by = GT.stats.by; by[src] = (by[src] or 0) + 1 end
    local now = os.clock()
    if now < GT.due or GT.running or now - GT.last < GT.MIN_GAP then return end
    GT.running, GT.last = true, now
    local s = GT.stats
    s.pumps = s.pumps + 1
    local list = GT.jobs
    GT.jobs = {} -- jobs added by a job land here and run from the next pump
    for _, j in ipairs(list) do
        if not j.dead and now >= j.at then
            local t0 = os.clock()
            local ok, res = pcall(j.fn, now)
            local dt = os.clock() - t0
            s.runs, s.time = s.runs + 1, s.time + dt
            if dt > s.worst then s.worst = dt end
            if not ok then
                j.errors = j.errors + 1
                if j.errors <= 3 then GT.log("job error: " .. tostring(res)) end
                if j.errors >= GT.MAX_ERRORS then j.dead = true; GT.log("job stopped after repeated errors") end
            end
            if j.every and not j.dead and not (ok and res == true) then
                j.at = math.max(j.at + j.every, now + j.every * 0.5) -- no catch-up burst after a pause
                GT.jobs[#GT.jobs + 1] = j
            end
        elseif not j.dead then
            GT.jobs[#GT.jobs + 1] = j
        end
    end
    nextDue()
    GT.running = false
end

local function hookDrivers()
    for _, d in ipairs(GT.drivers) do
        local fn = StaticFindObject(d.path)
        local a = (fn and fn:IsValid()) and fn:GetAddress() or nil
        if a and a ~= d.addr then -- not hooked yet, or its class was loaded again
            local ok, err = pcall(RegisterHook, d.path, function() GT.pump(d.tag) end)
            if ok then d.addr = a; GT.log("pumped by " .. d.path) else GT.log("could not hook " .. d.path .. ": " .. tostring(err)) end
        end
    end
end

-- path: a Blueprint function that runs often on the game thread (a ReceiveTick). Hooked from
-- GT.boot's ClientRestart (a missing class costs one ~37 ms lookup there, once per load).
function GT.drive(path, tag)
    GT.drivers[#GT.drivers + 1] = { path = path, tag = tag or path:match("([%w_]+):") }
end

-- fn(now): the mod's own start-up work after each load / possession (game thread).
function GT.boot(fn)
    local ok, err = pcall(RegisterHook, "/Script/Engine.PlayerController:ClientRestart", function()
        local now = os.clock()
        if fn then local ok2, e2 = pcall(fn, now); if not ok2 then GT.log("boot error: " .. tostring(e2)) end end
        pcall(hookDrivers)
        GT.pump("boot")
    end)
    if not ok then GT.log("could not hook ClientRestart: " .. tostring(err)) end
    return ok
end

-- "pumps N, jobs N, x ms, worst y ms; calls: boot N, foot N, ..." since the last call.
function GT.report()
    local s = GT.stats
    local by = {}
    for k, v in pairs(s.by) do by[#by + 1] = k .. " " .. v end
    table.sort(by)
    local r = string.format("pumps %d, jobs %d, %.1f ms, worst %.1f ms; calls: %s", s.pumps, s.runs, s.time * 1000,
        s.worst * 1000, #by > 0 and table.concat(by, ", ") or "none")
    s.pumps, s.runs, s.time, s.worst, s.by = 0, 0, 0, 0, {}
    return r
end

return GT
