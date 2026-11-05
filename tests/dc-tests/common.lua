-- Shared world setup and helpers for the Cargo Cannon test suites (not part of the mod).
local M = {}

M.CHEST = defines.inventory.chest
M.RED, M.GREEN = defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green
M.SPACE, M.CHARGE = "cargo-cannon-receiver-space", "cargo-cannon-charge"
function M.DC(name, ...) return remote.call("cargo-cannon", name, ...) end
local DC = M.DC

M.passed, M.failed = 0, 0
function M.check(name, ok, detail)
  if ok then M.passed = M.passed + 1 else M.failed = M.failed + 1 end
  print("STA " .. (ok and "PASS " or "FAIL ") .. name .. (detail and ("  (" .. tostring(detail) .. ")") or ""))
end
function M.count(entity, item, quality)
  if quality then return entity.get_inventory(M.CHEST).get_item_count({name = item, quality = quality}) end
  return entity.get_inventory(M.CHEST).get_item_count(item)
end
function M.status(cannon) return DC("cannon", cannon).status end
function M.sig(name) return {type = "virtual", name = name} end

function M.floor_and_power(s, tile, size, f, cx, cy)
  cx, cy = cx or 0, cy or 0
  local tiles = {}
  for x = cx - size, cx + size do for y = cy - size, cy + size do table.insert(tiles, {name = tile, position = {x, y}}) end end
  s.set_tiles(tiles)
  for _, e in pairs(s.find_entities_filtered{area = {{cx - size, cy - size}, {cx + size, cy + size}}}) do
    if e.valid and e.type ~= "character" and e.type ~= "space-platform-hub" then e.destroy() end
  end
  if not f then return end
  local eei = s.create_entity{name = "electric-energy-interface", position = {cx - size + 2, cy - size + 2}, force = f}
  eei.power_production = 1e10 / 60
  eei.electric_buffer_size = 1e11
  for x = cx - size + 4, cx + size - 4, 16 do
    for y = cy - size + 4, cy + size - 4, 16 do s.create_entity{name = "substation", position = {x, y}, force = f} end
  end
end

-- Nauvis, a platform above it (W.platform / W.p) and Vulcanus (W.v), all floored and powered
function M.world()
  local f = game.forces.player
  f.research_all_technologies()
  game.map_settings.enemy_expansion.enabled = false
  DC("set_cost", "orbit", {energy = 20, capsules = 1, flight = 4})
  DC("set_cost", "interplanetary", {energy = 40, capsules = 3, flight = 6})
  local n = game.surfaces.nauvis
  n.always_day, n.peaceful_mode = true, true
  for _, e in pairs(n.find_entities_filtered{force = "enemy"}) do e.destroy() end
  M.floor_and_power(n, "concrete", 60, f)
  local W = {f = f, n = n}
  W.platform = M.platform("Test platform", "nauvis")
  W.p = W.platform.surface
  W.v = M.planet("vulcanus")
  return W
end

function M.platform(name, planet, size)
  size = size or 40
  local f = game.forces.player
  local platform = f.create_space_platform{name = name, planet = planet, starter_pack = "space-platform-starter-pack"}
  platform.apply_starter_pack()
  M.floor_and_power(platform.surface, "space-platform-foundation", size, f)
  return platform
end

function M.planet(name)
  local s = game.planets[name].surface or game.planets[name].create_surface()
  s.request_to_generate_chunks({0, 0}, 3)
  s.force_generate_chunk_requests()
  s.peaceful_mode = true
  for _, e in pairs(s.find_entities_filtered{force = "enemy"}) do e.destroy() end
  M.floor_and_power(s, "concrete", 40, game.forces.player)
  return s
end

function M.build(s, name, pos, force)
  local e = s.create_entity{name = name, position = pos, force = force or "player", raise_built = true}
  if not e then print("STA setup: could not place " .. name .. " at " .. serpent.line(pos)) end
  return e
end

-- capsules in slot 1; item (picked as the cargo) in slot 2
function M.load(cannon, capsules, item, n_items, quality)
  if item then DC("configure", cannon, {cargo = {name = item, quality = quality or "normal"}}) end
  local inv = cannon.get_inventory(M.CHEST)
  if capsules > 0 then inv[1].set_stack{name = "cargo-cannon-capsule", count = capsules} end
  if item and n_items > 0 then inv[2].set_stack{name = item, count = n_items, quality = quality or "normal"} end
end

-- a cannon at pos on s aimed at receiver rx, loaded with 10 capsules and a stack of item
function M.cannon(s, pos, rx, item, n_items, settings)
  local c = M.build(s, "cargo-cannon", pos)
  M.load(c, 10, item, n_items or 100)
  if rx then DC("set_target", c, rx) end
  if settings then DC("configure", c, settings) end
  return c
end

-- sets the game's own circuit condition on a cannon, as the normal circuit tab does
function M.native(cannon, condition, enabled)
  local cb = cannon.get_or_create_control_behavior()
  cb.circuit_condition = condition
  cb.circuit_condition_enabled = enabled ~= false
end

-- a constant combinator at pos sending {signal name = value, ...} on the wire(s) to entity
function M.combinator(s, pos, values, entity, wires)
  local cc = s.create_entity{name = "constant-combinator", position = pos, force = "player"}
  local section = cc.get_or_create_control_behavior().get_section(1)
  local i = 1
  for name, value in pairs(values) do
    local t = prototypes.virtual_signal[name] and "virtual" or "item"
    section.set_slot(i, {value = {type = t, name = name, quality = "normal"}, min = value})
    i = i + 1
  end
  for _, w in pairs(wires or {M.RED}) do cc.get_wire_connector(w, true).connect_to(entity.get_wire_connector(w, true)) end
  return cc
end
function M.set_value(cc, slot, name, value)
  local t = prototypes.virtual_signal[name] and "virtual" or "item"
  cc.get_or_create_control_behavior().get_section(1).set_slot(slot, {value = {type = t, name = name, quality = "normal"}, min = value})
end

function M.summary(suite)
  print("STA " .. suite .. ": " .. M.passed .. " passed, " .. M.failed .. " failed")
  script.finish_test(M.failed == 0)
end

return M
