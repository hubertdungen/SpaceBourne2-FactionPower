--[[
  Lazy, fault-isolated hook registration. Same design as HTR's htr/hooks.lua
  (Hardcore Tactical Realism), kept as a private copy so each mod of the set works alone.

  Game classes load only when first needed, so hooks are grouped by class: when a
  class appears, all its hooks register; if the class object is replaced (reloaded),
  they register again. A callback that keeps throwing Lua errors is switched off.

  Cost rule (measured in game for HTR): a StaticFindObject that finds its object costs
  ~0 ms, one that does NOT find it costs ~37 ms. Missing classes are looked up with a
  growing pause (1, 2, 4, 8, 16 s), at most one per poll, and again right away after
  H.wake().

  UE4SS 3.0 facts for Blueprint functions (verified in game for HTR):
    - the callback runs AFTER the Blueprint body (post-hook);
    - writing an OUT parameter with :set() changes what the caller receives.
  Only Blueprint UFunctions are hooked. Never native functions, never LoadMap.
]]

local U = require("fp.util")

local H = { list = {}, groups = {}, order = {}, SLOW = 0.008 }
local MAX_ERRORS = 25
local CHECK_LOADED = 5
local RETRY_MAX = 16

function H.add(path, fn, tag)
    local h = { path = path, fn = fn, tag = tag or path, errors = 0, disabled = false, on = false, slowAt = -1e9 }
    h.cb = function(...)
        if h.disabled or not FP.on then return end
        local t0 = os.clock()
        local ok, err = pcall(h.fn, ...)
        local dt = os.clock() - t0
        if dt > H.SLOW and t0 - h.slowAt > 30 then
            h.slowAt = t0
            U.warn(string.format("slow hook %s: %.0f ms", h.tag, dt * 1000))
        end
        if not ok then
            h.errors = h.errors + 1
            if h.errors <= 3 then U.warn("error in " .. h.tag .. ": " .. tostring(err)) end
            if h.errors >= MAX_ERRORS then
                h.disabled = true
                U.warn("hook " .. h.tag .. " disabled after repeated errors")
            end
        end
    end
    H.list[#H.list + 1] = h
    local cls = path:match("^(.-):") or path
    local g = H.groups[cls]
    if not g then
        g = { cls = cls, hooks = {}, addr = nil, retry = 1, nextTry = 0 }
        H.groups[cls] = g
        H.order[#H.order + 1] = g
    end
    g.hooks[#g.hooks + 1] = h
end

local function register(h)
    local ok, err = pcall(RegisterHook, h.path, h.cb)
    h.on = ok
    if ok then U.log("hooked " .. h.tag) else U.warn("could not hook " .. h.path .. ": " .. tostring(err)) end
end

function H.wake()
    for _, g in ipairs(H.order) do
        if not g.addr then g.retry, g.nextTry = 1, 0 end
    end
end

-- Call on the game thread about once a second. Returns how many hooks were registered.
function H.poll(now)
    local probed, registered = false, 0
    for _, g in ipairs(H.order) do
        if now >= g.nextTry and (g.addr or not probed) then
            if not g.addr then probed = true end
            local c = StaticFindObject(g.cls)
            local a = (c and c:IsValid()) and c:GetAddress() or nil
            if a then
                g.nextTry, g.retry = now + CHECK_LOADED, 1
                if a ~= g.addr then
                    g.addr = a
                    for _, h in ipairs(g.hooks) do register(h); registered = registered + 1 end
                end
            else
                if g.addr then
                    g.addr = nil
                    for _, h in ipairs(g.hooks) do h.on = false end
                end
                g.nextTry = now + g.retry
                g.retry = math.min(g.retry * 2, RETRY_MAX)
            end
        end
    end
    return registered
end

function H.status()
    local on, off = 0, 0
    for _, h in ipairs(H.list) do if h.on and not h.disabled then on = on + 1 else off = off + 1 end end
    return on, off
end

return H
