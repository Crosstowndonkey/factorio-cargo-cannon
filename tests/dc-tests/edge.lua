-- Suite "edge": awkward situations - rewiring, upgrades mid-flight, no power, things that have gone missing.
local C = require("common")
local DC, check, count, CHEST, RED, GREEN = C.DC, C.check, C.count, C.CHEST, C.RED, C.GREEN
local S = {}

local function readout_wires(cannon)
  local ro = DC("cannon", cannon).readout
  return ro.get_wire_connector(RED, true).connection_count, ro.get_wire_connector(GREEN, true).connection_count
end

function S.setup(T)
  local W = C.world()
  local n, p, f = W.n, W.p, W.f
  T.n, T.p = n, p

  -- 1. rewiring at runtime: none -> green -> green + red -> red -> none; the player's wires are never touched
  T.wire = C.build(n, "cargo-cannon", {-50, -50})
  T.wire_lamp_r = n.create_entity{name = "small-lamp", position = {-50, -46}, force = "player"}
  T.wire_lamp_g = n.create_entity{name = "small-lamp", position = {-48, -46}, force = "player"}

  -- 2. construction robots upgrade a cannon and a receiver to legendary, with a capsule on its way to the receiver
  local rp = n.create_entity{name = "roboport", position = {0, 0}, force = f}
  rp.insert{name = "construction-robot", count = 20}
  rp.energy = 1e8
  local store = n.create_entity{name = "storage-chest", position = {4, 4}, force = f}
  store.insert{name = "cargo-cannon", count = 2, quality = "legendary"}
  store.insert{name = "cargo-cannon-receiver", count = 2, quality = "legendary"}
  T.up_far = C.build(p, "cargo-cannon-receiver", {-30, -30})
  T.up_can = C.cannon(n, {-12, 0}, T.up_far, "iron-plate", 100)
  DC("configure", T.up_can, {full_stack = false})
  T.up_rx = C.build(n, "cargo-cannon-receiver", {12, 0})
  DC("configure_receiver", T.up_rx, {name = "Depot", channel = 4242})
  T.up_in = C.cannon(p, {-20, -30}, T.up_rx, "copper-plate", 100)
  T.up_aim = C.cannon(p, {-10, -30}, T.up_rx, "steel-plate", 0)

  -- 3. no power: nothing nearby
  T.dark_rx = C.build(p, "cargo-cannon-receiver", {0, -30})
  local tiles = {}
  for x = 90, 110 do for y = 90, 110 do table.insert(tiles, {name = "concrete", position = {x, y}}) end end
  n.request_to_generate_chunks({100, 100}, 2)
  n.force_generate_chunk_requests()
  n.set_tiles(tiles)
  for _, e in pairs(n.find_entities_filtered{area = {{90, 90}, {110, 110}}}) do if e.valid and e.type ~= "character" then e.destroy() end end
  T.dark = C.cannon(n, {100, 100}, T.dark_rx, "iron-plate", 100)

  -- 4. a capsule as the cargo
  T.cap_rx = C.build(p, "cargo-cannon-receiver", {10, -30})
  T.cap = C.build(n, "cargo-cannon", {-30, -30})
  C.load(T.cap, 10, "cargo-cannon-capsule", 50)
  DC("configure", T.cap, {full_stack = false})
  DC("set_target", T.cap, T.cap_rx)

  -- 5. a shot that costs more than the prototype's 1 GJ buffer
  T.big_rx = C.build(W.v, "cargo-cannon-receiver", {-20, -20})
  T.big = C.cannon(n, {-20, -30}, T.big_rx, "stone", 50)

  -- 6. things that disappear: cargo and signals from a mod that's been removed
  T.lost_rx = C.build(p, "cargo-cannon-receiver", {20, -30})
  T.lost_cargo = C.cannon(n, {-10, -30}, T.lost_rx, "wood", 100)
  T.lost_sig = C.cannon(n, {0, -30}, nil, "coal", 50)

  -- 7. a helper destroyed behind our back
  T.no_helpers_rx = C.build(p, "cargo-cannon-receiver", {30, -30})
  T.no_helpers = C.cannon(n, {10, -30}, T.no_helpers_rx, "stone-brick", 100)

  -- 7b. destroyed, then rebuilt from the ghost: it works as before
  T.kill_rx = C.build(n, "cargo-cannon-receiver", {30, 10})
  DC("configure_receiver", T.kill_rx, {name = "Rebuilt", channel = 5151})
  T.kill_aim = C.cannon(p, {20, -10}, T.kill_rx, "iron-stick", 0)
  T.kill = C.build(n, "cargo-cannon", {30, 0})
  DC("configure", T.kill, {cargo = {name = "pipe", quality = "normal"}, full_stack = false})
  DC("set_target", T.kill, T.lost_rx)

  -- 8. a receiver's channel set to 0: not reachable by signal, no error
  T.ch0 = C.build(p, "cargo-cannon-receiver", {-30, 0})
  DC("configure_receiver", T.ch0, {channel = 0})
  T.ch0_can = C.cannon(n, {20, -30}, nil, "iron-ore", 50, {circuit_target = true, target_signal = C.sig("signal-C")})
  C.combinator(n, {20, -26}, {["signal-C"] = 0}, T.ch0_can)
end

function S.tick(T, tick)
  local n = T.n
  if tick == 30 then
    local r, g = readout_wires(T.wire)
    check("rewire: no wires, the signals are on red", r == 1 and g == 0, r .. "/" .. g)
    T.wire_lamp_g.get_wire_connector(GREEN, true).connect_to(T.wire.get_wire_connector(GREEN, true))
    T.up_can.order_upgrade{target = {name = "cargo-cannon", quality = "legendary"}, force = "player"}
    T.up_rx.order_upgrade{target = {name = "cargo-cannon-receiver", quality = "legendary"}, force = "player"}
  end
  if tick == 100 then
    local r, g = readout_wires(T.wire)
    check("rewire: green only, the signals move to green", r == 0 and g == 1, r .. "/" .. g)
    T.wire_lamp_r.get_wire_connector(RED, true).connect_to(T.wire.get_wire_connector(RED, true))
  end
  if tick == 170 then
    local r, g = readout_wires(T.wire)
    check("rewire: both wires, the signals go to red", r == 1 and g == 0, r .. "/" .. g)
    check("rewire: the player's green wire is still there", T.wire.get_wire_connector(GREEN, true).is_connected_to(T.wire_lamp_g.get_wire_connector(GREEN, true)))
    T.wire.get_wire_connector(RED, true).disconnect_from(T.wire_lamp_r.get_wire_connector(RED, true))
    T.wire.get_wire_connector(GREEN, true).disconnect_from(T.wire_lamp_g.get_wire_connector(GREEN, true))
  end
  if tick == 240 then
    local r, g = readout_wires(T.wire)
    check("rewire: all wires gone, back on red", r == 1 and g == 0, r .. "/" .. g)
  end
  if tick == 120 then
    DC("configure", T.lost_cargo, {cargo = {name = "no-such-item", quality = "normal"}})
    DC("configure", T.lost_sig, {circuit_target = true, target_signal = {type = "item", name = "no-such-item"}})
    local c = DC("cannon", T.no_helpers)
    c.energy.destroy()
    c.readout.destroy()
    DC("set_cost", "interplanetary", {energy = 2000, capsules = 3, flight = 6})
  end
  if tick == 150 then
    T.kill.die()
    T.kill_rx.die()
  end
  if tick == 160 then
    local ghosts = n.find_entities_filtered{name = "entity-ghost", position = {30, 5}, radius = 14}
    check("destroyed: both leave ghosts", #ghosts == 2, #ghosts)
    for _, ghost in pairs(ghosts) do
      local _, built = ghost.revive{raise_revive = true}
      if built and built.name == "cargo-cannon" then T.kill = built else T.kill_rx = built end
    end
    local c = DC("cannon", T.kill)
    check("rebuilt: the cannon keeps its settings", c and c.cargo and c.cargo.name == "pipe" and c.full_stack == false and c.target ~= nil,
          c and serpent.line(c.cargo))
    local r = DC("receiver", T.kill_rx)
    check("rebuilt: the receiver keeps its name and channel", r and r.name == "Rebuilt" and r.channel == 5151, r and r.name)
    check("rebuilt: cannons still aim at the receiver", DC("cannon", T.kill_aim).target == T.kill_rx.unit_number, DC("cannon", T.kill_aim).target)
  end
  if tick == 200 then
    print("STA no power: status " .. DC("cannon", T.dark).status)
    check("no power: the status says so", DC("cannon", T.dark).status == "no-power", DC("cannon", T.dark).status)
    check("capsule as cargo: both slots stay apart, nothing broke", count(T.cap_rx, "cargo-cannon-capsule") == 50 or
          DC("flights") > 0, count(T.cap_rx, "cargo-cannon-capsule"))
  end
  if tick == 700 then
    local c = n.find_entities_filtered{name = "cargo-cannon", position = {-12, 0}, radius = 2}[1]
    local rx = n.find_entities_filtered{name = "cargo-cannon-receiver", position = {12, 0}, radius = 2}[1]
    print("STA upgraded: cannon " .. tostring(c and c.quality.name) .. ", receiver " .. tostring(rx and rx.quality.name))
    check("upgrade: the cannon is legendary", c and c.quality.name == "legendary", c and c.quality.name)
    check("upgrade: the receiver is legendary", rx and rx.quality.name == "legendary", rx and rx.quality.name)
    local cr = c and DC("cannon", c)
    check("upgrade: the cannon keeps its target and cargo", cr and cr.target and cr.cargo and cr.cargo.name == "iron-plate" and cr.full_stack == false,
          cr and serpent.line({cr.target, cr.cargo, cr.full_stack}))
    local rr = rx and DC("receiver", rx)
    check("upgrade: the receiver keeps its name and channel", rr and rr.name == "Depot" and rr.channel == 4242, rr and rr.name)
    local aim = DC("cannon", T.up_aim)
    check("upgrade: cannons aimed at the receiver still are", rx and aim.target == rx.unit_number, tostring(aim.target))
    check("upgrade: the capsule in the air still lands", rx and count(rx, "copper-plate") == 100 and rx.health == rx.max_health,
          rx and count(rx, "copper-plate"))
    check("upgrade: no spare helpers", n.count_entities_filtered{name = "cargo-cannon-readout", position = {-12, 0}, radius = 2} == 1 and
          n.count_entities_filtered{name = "cargo-cannon-energy", position = {-12, 0}, radius = 2} == 1)
    check("upgrade: a legendary cannon still has 2 slots", c and #c.get_inventory(CHEST) == 2, c and #c.get_inventory(CHEST))
    check("upgrade: a legendary receiver has more room", rx and #rx.get_inventory(CHEST) == 100, rx and #rx.get_inventory(CHEST))
    check("upgrade: the power follows the quality", cr and math.abs(cr.energy.input_flow_limit * 60 - 120e6) < 1, cr and cr.energy.input_flow_limit * 60)
  end
  if tick == 800 then
    check("a shot over 1 GJ: the buffer grows to fit", DC("cannon", T.big).energy.electric_buffer_size >= 2e9, DC("cannon", T.big).energy.electric_buffer_size)
    check("missing cargo: forgotten, not a crash", DC("cannon", T.lost_cargo).cargo == nil, serpent.line(DC("cannon", T.lost_cargo).cargo))
    check("missing target signal: forgotten, not a crash", DC("cannon", T.lost_sig).target_signal == nil and DC("cannon", T.lost_sig).status == "no-target",
          DC("cannon", T.lost_sig).status)
    local c = DC("cannon", T.no_helpers)
    check("destroyed helpers come back", c.energy.valid and c.readout.valid)
    check("channel 0 is never a target", count(T.ch0, "iron-ore") == 0 and DC("cannon", T.ch0_can).status == "no-target", DC("cannon", T.ch0_can).status)
    return true
  end
end

return S
