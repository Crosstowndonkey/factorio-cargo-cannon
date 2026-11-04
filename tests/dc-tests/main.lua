-- Suite "main": the basic shots, crashes, robots, inserters, a circuit condition and the readouts.
local C = require("common")
local DC, check, count, CHEST, RED, GREEN = C.DC, C.check, C.count, C.CHEST, C.RED, C.GREEN
local S = {}

function S.setup(T)
  local W = C.world()
  local n, p, v, f = W.n, W.p, W.v, W.f
  local rp = n.create_entity{name = "roboport", position = {0, 0}, force = f}
  rp.insert{name = "logistic-robot", count = 100}
  rp.energy = 1e8
  local store = n.create_entity{name = "storage-chest", position = {4, 0}, force = f}
  store.insert{name = "cargo-cannon-capsule", count = 50}
  local build, load = C.build, C.load

  -- 1. an orbit shot up to the platform
  T.up = build(n, "cargo-cannon", {-20, -20})
  T.up_rx = build(p, "cargo-cannon-receiver", {-20, -20})
  load(T.up, 10, "iron-plate", 100)
  DC("set_target", T.up, T.up_rx)
  -- 2. half a stack: waits (full-stack setting on)
  T.half = C.cannon(n, {-10, -20}, T.up_rx, "copper-plate", 50)
  -- 3. no capsules
  T.nocaps = build(n, "cargo-cannon", {0, -20})
  load(T.nocaps, 0, "copper-plate", 100)
  DC("set_target", T.nocaps, T.up_rx)
  -- 4. interplanetary to a full receiver: crashes, cargo lost, receiver damaged
  T.full_rx = build(v, "cargo-cannon-receiver", {-20, -20})
  for i = 1, 40 do T.full_rx.get_inventory(CHEST)[i].set_stack{name = "stone", count = 50} end
  T.tofull = C.cannon(n, {10, -20}, T.full_rx, "coal", 50)
  -- 5. interplanetary to an empty receiver: arrives, 3 capsules used
  T.inter_rx = build(v, "cargo-cannon-receiver", {0, -20})
  T.inter = C.cannon(n, {20, -20}, T.inter_rx, "steel-plate", 100)
  -- 6. down from the platform to Nauvis (a passive provider: robots take some to a requester chest)
  T.down_rx = build(n, "cargo-cannon-receiver", {10, 6})
  T.down = C.cannon(p, {0, 0}, T.down_rx, "iron-gear-wheel", 100)
  T.wants = n.create_entity{name = "requester-chest", position = {-6, 4}, force = f}
  T.wants.get_logistic_sections().add_section().set_slot(1, {value = {name = "iron-gear-wheel", quality = "normal"}, min = 20})
  -- 7. circuit enable: signal A > 0, no signal at first
  T.circ = C.cannon(n, {30, -20}, T.up_rx, "stone-brick", 100, {circuit_enable = true,
     condition = {signal = C.sig("signal-A"), comparator = ">", constant = 0}})
  -- 8. target by signal: signal-C = the receiver's channel
  T.sig_rx = build(p, "cargo-cannon-receiver", {10, -20})
  T.bysig = C.cannon(n, {40, -20}, nil, "plastic-bar", 100, {circuit_target = true, target_signal = C.sig("signal-C")})
  C.combinator(n, {40, -16}, {["signal-C"] = DC("receiver", T.sig_rx).channel}, T.bysig)
  -- 9. the receiver is removed while the capsule flies: it crashes on the platform
  T.gone_rx = build(p, "cargo-cannon-receiver", {20, 10})
  T.gone = C.cannon(n, {-30, -20}, T.gone_rx, "sulfur", 50)
  -- 10. robots bring requested capsules
  T.bots = build(n, "cargo-cannon", {-10, 6})
  T.bots.get_logistic_sections().add_section().set_slot(1, {value = {name = "cargo-cannon-capsule", quality = "normal"}, min = 5})
  -- 11. an inserter loads capsules; another empties a receiver
  T.ins_cannon = build(n, "cargo-cannon", {-30, 10})
  local src = n.create_entity{name = "iron-chest", position = {-30.5, 13.5}, force = f}
  src.insert{name = "cargo-cannon-capsule", count = 60}
  DC("configure", T.ins_cannon, {cargo = {name = "iron-plate", quality = "normal"}})
  -- 14. no cargo picked: slot 2 is locked, an inserter with capsules can only fill slot 1
  T.locked_slot = build(n, "cargo-cannon", {-40, 10})
  local src2 = n.create_entity{name = "iron-chest", position = {-40.5, 13.5}, force = f}
  src2.insert{name = "cargo-cannon-capsule", count = 60}
  n.create_entity{name = "fast-inserter", position = {-40.5, 12.5}, direction = defines.direction.south, force = f}
  n.create_entity{name = "fast-inserter", position = {-30.5, 12.5}, direction = defines.direction.south, force = f}
  n.create_entity{name = "fast-inserter", position = {10.5, 9.5}, direction = defines.direction.north, force = f}
  T.out_chest = n.create_entity{name = "iron-chest", position = {10.5, 10.5}, force = f}
  -- 12. wired safely: "fire while Receiver space > 0" at a full receiver - holds fire, nothing crashes
  T.safe = C.cannon(n, {50, -20}, T.full_rx, "wood", 100, {circuit_enable = true,
     condition = {signal = C.sig(C.SPACE), comparator = ">", constant = 0}})
  -- 13. a force without the interplanetary research can't fire to another planet
  local beta = game.create_force("beta")
  beta.research_all_technologies()
  beta.technologies["cargo-cannon-interplanetary"].researched = false
  T.locked = build(n, "cargo-cannon", {50, 20}, beta)
  T.locked_rx = build(v, "cargo-cannon-receiver", {20, 20}, beta)
  load(T.locked, 10, "wood", 100)
  DC("set_target", T.locked, T.locked_rx)
end

local function readout(cannon, name) return cannon.get_signal(C.sig(name), RED) end

function S.tick(T, tick)
  if tick == 100 then
    check("readout: receiver space = 39 (40 empty, 1 capsule on its way)", readout(T.up, C.SPACE) == 39, readout(T.up, C.SPACE))
  end
  if not T.removed and count(T.gone, "sulfur") == 0 then
    T.removed = true
    T.gone_rx.destroy()
  end
  if tick == 700 then
    C.combinator(T.circ.surface, {30, -16}, {["signal-A"] = 1}, T.circ, {GREEN})
    check("circuit: held fire while A = 0", count(T.circ, "stone-brick") == 100 and C.status(T.circ) == "disabled", C.status(T.circ))
  end
  if tick == 1500 then
    check("orbit shot: 100 iron plates reached the platform", count(T.up_rx, "iron-plate") == 100, count(T.up_rx, "iron-plate"))
    check("orbit shot: used 1 capsule", count(T.up, "cargo-cannon-capsule") == 9)
    check("orbit shot: cannon emptied", count(T.up, "iron-plate") == 0)
    check("half stack: waits for a full stack", count(T.half, "copper-plate") == 50 and C.status(T.half) == "waiting-full", C.status(T.half))
    check("no capsules: waits", count(T.nocaps, "copper-plate") == 100 and C.status(T.nocaps) == "no-capsules", C.status(T.nocaps))
    check("full receiver: cargo lost", count(T.full_rx, "coal") == 0 and count(T.tofull, "coal") == 0)
    check("full receiver: damaged by the crash", T.full_rx.health < T.full_rx.max_health, T.full_rx.health .. "/" .. T.full_rx.max_health)
    check("interplanetary: 100 steel reached Vulcanus", count(T.inter_rx, "steel-plate") == 100, count(T.inter_rx, "steel-plate"))
    check("interplanetary: used 3 capsules", count(T.inter, "cargo-cannon-capsule") == 7, count(T.inter, "cargo-cannon-capsule"))
    local gears_rx, gears_req, gears_out = count(T.down_rx, "iron-gear-wheel"), count(T.wants, "iron-gear-wheel"), count(T.out_chest, "iron-gear-wheel")
    check("platform -> planet: 100 gears arrived (receiver + robots + inserter)", gears_rx + gears_req + gears_out == 100,
          gears_rx .. " + " .. gears_req .. " + " .. gears_out)
    check("passive provider: robots took gears to the requester chest", gears_req == 20, gears_req)
    check("inserter: emptied the receiver", gears_out > 0, gears_out)
    check("circuit: fired once A = 1", count(T.circ, "stone-brick") == 0 and count(T.up_rx, "stone-brick") == 100,
          count(T.circ, "stone-brick") .. " / " .. count(T.up_rx, "stone-brick"))
    check("target by signal: plastic reached the channel's receiver", count(T.sig_rx, "plastic-bar") == 100, count(T.sig_rx, "plastic-bar"))
    check("receiver removed mid-flight: sulfur lost, nothing left in the air", T.removed and DC("flights") == 0, "flights " .. DC("flights"))
    check("robots: brought the requested capsules", count(T.bots, "cargo-cannon-capsule") >= 5, count(T.bots, "cargo-cannon-capsule"))
    local inv = T.ins_cannon.get_inventory(CHEST)
    check("inserter: capsules only fill slot 1 (cargo slot keeps for iron)",
          inv[1].valid_for_read and inv[1].count == 50 and not inv[2].valid_for_read,
          tostring(inv[1].valid_for_read and inv[1].count) .. ", slot 2 " .. tostring(inv[2].valid_for_read and inv[2].name))
    local inv2 = T.locked_slot.get_inventory(CHEST)
    check("no cargo picked: slot 2 locked, capsules stay in slot 1",
          inv2[1].count == 50 and not inv2[2].valid_for_read and C.status(T.locked_slot) ~= "fired",
          inv2[1].count .. ", " .. C.status(T.locked_slot))
    check("readout: receiver space counts arrivals (38 after iron + bricks)", readout(T.up, C.SPACE) == 38, readout(T.up, C.SPACE))
    check("safe wiring: held fire at a full receiver", count(T.safe, "wood") == 100 and C.status(T.safe) == "disabled", C.status(T.safe))
    check("research: no interplanetary shots before Interplanetary cargo",
          count(T.locked, "wood") == 100 and C.status(T.locked) == "needs-research", C.status(T.locked))
    check("readout: cannon charge reported", readout(T.up, C.CHARGE) > 0, readout(T.up, C.CHARGE))
    return true
  end
end

return S
