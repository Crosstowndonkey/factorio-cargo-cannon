-- Save / load test for Cargo Cannon (not part of the mod). tools/run_tests.sh saveload runs it in two parts:
--   1. a headless server (no players): the map is built in on_init, cannons fire capsules with 60 s flights, and
--      stopping the server saves the map while they're in the air;
--   2. that save is loaded with --test-save (a player joins): the capsules must land with their cargo intact, a
--      receiver removed after loading makes its capsule crash, and settings / wiring survive.
local CHEST = defines.inventory.chest
local RED = defines.wire_connector_id.circuit_red
local DC = function(name, ...) return remote.call("cargo-cannon", name, ...) end
local ARRIVE_BY = 3600 + 400   -- capsules fire around tick 70 and fly 60 s

local function floor_and_power(s, tile, size, f)
  local tiles = {}
  for x = -size, size do for y = -size, size do table.insert(tiles, {name = tile, position = {x, y}}) end end
  s.set_tiles(tiles)
  for _, e in pairs(s.find_entities_filtered{area = {{-size, -size}, {size, size}}}) do
    if e.valid and e.type ~= "character" and e.type ~= "space-platform-hub" then e.destroy() end
  end
  local eei = s.create_entity{name = "electric-energy-interface", position = {-size + 2, -size + 2}, force = f}
  eei.power_production = 1e10 / 60
  eei.electric_buffer_size = 1e11
  for x = -size + 4, size - 4, 16 do for y = -size + 4, size - 4, 16 do s.create_entity{name = "substation", position = {x, y}, force = f} end end
end
local function build(s, name, pos)
  return s.create_entity{name = name, position = pos, force = "player", raise_built = true}
end
local function check(name, ok, detail)
  storage.passed = (storage.passed or 0) + (ok and 1 or 0)
  storage.failed = (storage.failed or 0) + (ok and 0 or 1)
  print("STA " .. (ok and "PASS " or "FAIL ") .. name .. (detail and ("  (" .. tostring(detail) .. ")") or ""))
end
local function find(rx, item)
  local inv = rx.get_inventory(CHEST)
  for i = 1, #inv do if inv[i].valid_for_read and inv[i].name == item then return inv[i] end end
end

script.on_init(function()
  local f = game.forces.player
  f.research_all_technologies()
  DC("set_cost", "orbit", {energy = 20, capsules = 1, flight = 60})
  DC("set_cost", "interplanetary", {energy = 40, capsules = 3, flight = 60})
  local n = game.surfaces.nauvis
  n.always_day, n.peaceful_mode = true, true
  for _, e in pairs(n.find_entities_filtered{force = "enemy"}) do e.destroy() end
  floor_and_power(n, "concrete", 40, f)
  local platform = f.create_space_platform{name = "Save platform", planet = "nauvis", starter_pack = "space-platform-starter-pack"}
  platform.apply_starter_pack()
  floor_and_power(platform.surface, "space-platform-foundation", 30, f)
  local v = game.planets.vulcanus.create_surface()
  v.request_to_generate_chunks({0, 0}, 3)
  v.force_generate_chunk_requests()
  v.peaceful_mode = true
  for _, e in pairs(v.find_entities_filtered{force = "enemy"}) do e.destroy() end
  floor_and_power(v, "concrete", 30, f)

  local T = {}
  storage.T = T
  -- uncommon iron, up to the platform
  T.q_rx = build(platform.surface, "cargo-cannon-receiver", {-10, -10})
  T.q = build(n, "cargo-cannon", {-20, -20})
  DC("configure", T.q, {cargo = {name = "iron-plate", quality = "uncommon"}})
  T.q.get_inventory(CHEST)[1].set_stack{name = "cargo-cannon-capsule", count = 10}
  T.q.get_inventory(CHEST)[2].set_stack{name = "iron-plate", count = 100, quality = "uncommon"}
  DC("set_target", T.q, T.q_rx)
  -- armour with equipment, to Vulcanus
  T.a_rx = build(v, "cargo-cannon-receiver", {0, 0})
  T.a = build(n, "cargo-cannon", {-10, -20})
  DC("configure", T.a, {cargo = {name = "modular-armor", quality = "normal"}})
  T.a.get_inventory(CHEST)[1].set_stack{name = "cargo-cannon-capsule", count = 10}
  local armour = T.a.get_inventory(CHEST)[2]
  armour.set_stack{name = "modular-armor"}
  armour.grid.put{name = "solar-panel-equipment"}
  DC("set_target", T.a, T.a_rx)
  -- to a receiver that will be removed after loading
  T.gone_rx = build(platform.surface, "cargo-cannon-receiver", {10, -10})
  T.gone = build(n, "cargo-cannon", {0, -20})
  DC("configure", T.gone, {cargo = {name = "coal", quality = "normal"}})
  T.gone.get_inventory(CHEST)[1].set_stack{name = "cargo-cannon-capsule", count = 10}
  T.gone.get_inventory(CHEST)[2].set_stack{name = "coal", count = 50}
  DC("set_target", T.gone, T.gone_rx)
  -- settings that must survive: a circuit condition (A > 0) with no signal, so it holds
  T.held = build(n, "cargo-cannon", {10, -20})
  DC("configure", T.held, {cargo = {name = "wood", quality = "normal"}, circuit_enable = true,
     condition = {signal = {type = "virtual", name = "signal-A"}, comparator = ">", constant = 0}})
  T.held.get_inventory(CHEST)[1].set_stack{name = "cargo-cannon-capsule", count = 10}
  T.held.get_inventory(CHEST)[2].set_stack{name = "wood", count = 100}
  DC("set_target", T.held, T.q_rx)
end)

script.on_event(defines.events.on_tick, function(e)
  local T = storage.T
  if not T then return end
  if #game.players == 0 then  -- part 1, on the server
    if e.tick % 300 == 0 then print("STA server tick " .. e.tick .. ": " .. DC("flights") .. " capsules in the air") end
    return
  end
  if not storage.loaded_at then  -- part 2: the first tick after loading
    storage.loaded_at = e.tick
    print("STA info: loaded at tick " .. e.tick)
    check("after loading: the 3 capsules are still in the air", DC("flights") == 3 and e.tick < 3600, DC("flights") .. " at tick " .. e.tick)
    T.gone_rx.destroy()
    local c = DC("cannon", T.held)
    check("after loading: settings kept", c.circuit_enable and c.condition.comparator == ">" and c.cargo.name == "wood",
          serpent.line(c.condition))
    return
  end
  if e.tick == storage.loaded_at + 30 then
    local space = T.q.get_signal({type = "virtual", name = "cargo-cannon-receiver-space"}, RED)
    check("after loading: the readout still works (39 = 40 free - 1 on its way)", space == 39, space)
    check("after loading: the condition still holds fire", DC("cannon", T.held).status == "disabled", DC("cannon", T.held).status)
    -- wire signal A = 1 to it now
    local cc = T.held.surface.create_entity{name = "constant-combinator", position = {10, -16}, force = "player"}
    cc.get_or_create_control_behavior().get_section(1).set_slot(1,
      {value = {type = "virtual", name = "signal-A", quality = "normal"}, min = 1})
    cc.get_wire_connector(RED, true).connect_to(T.held.get_wire_connector(RED, true))
  end
  if e.tick == math.max(ARRIVE_BY, storage.loaded_at + 3700) then
    check("loaded mid-flight: uncommon iron arrived uncommon",
          T.q_rx.get_inventory(CHEST).get_item_count({name = "iron-plate", quality = "uncommon"}) == 100)
    local armour = find(T.a_rx, "modular-armor")
    check("loaded mid-flight: armour arrived with its equipment", armour and armour.grid and #armour.grid.equipment == 1)
    check("loaded mid-flight: receiver removed after loading - crashed, nothing left in the air", DC("flights") <= 1,
          DC("flights") .. " in the air")
    check("after loading: wiring A = 1 made the held cannon fire", T.held.get_inventory(CHEST).get_item_count("wood") == 0,
          DC("cannon", T.held).status)
    print("STA saveload: " .. storage.passed .. " passed, " .. storage.failed .. " failed")
    script.finish_test(storage.failed == 0)
  end
end)
