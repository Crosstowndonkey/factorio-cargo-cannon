-- Cargo Cannon: fires capsules of cargo from one surface to a receiver on another.
--
-- A cannon is a 2-slot container: slot 1 holds capsules, slot 2 the cargo (one stack of one item per shot). Two
-- hidden helpers sit on it: an electric-energy-interface (the charge) and a constant combinator wired to the cannon
-- by script, which tells the circuit network how much room the target receiver has and how charged the cannon is.
-- Whether it may fire is the game's own circuit condition, in the building's normal circuit tab (it also stops robots
-- loading it); there is no second condition in our panel.
--
-- Shots:  orbit          planet <-> a platform stopped above it (or two platforms at the same place)
--         interplanetary planet -> another planet (needs the "Interplanetary cargo" research)
-- A capsule in flight is a record in storage.flights holding its cargo in a script inventory (so items keep their
-- data: quality, spoilage, armour grids...). When it lands it goes into the receiver - or, if the receiver is full
-- or gone, it explodes like a grenade and the cargo is lost. Wiring the cannon so that can't happen is the game.

local CANNON, RECEIVER, CAPSULE = "cargo-cannon", "cargo-cannon-receiver", "cargo-cannon-capsule"
local ENERGY, READOUT = "cargo-cannon-energy", "cargo-cannon-readout"
local FLIGHT, CRASH = "cargo-cannon-capsule-flight", "cargo-cannon-capsule-crash"
local SPACE_SIGNAL = {type = "virtual", name = "cargo-cannon-receiver-space"}
local CHARGE_SIGNAL = {type = "virtual", name = "cargo-cannon-charge"}
local INTERPLANETARY_TECH = "cargo-cannon-interplanetary"
local CHECK_EVERY = 10   -- ticks between updates
local WIRE_CHECK_EVERY = 6  -- updates between looks at a cannon's wires
local FALL_TICKS = 60    -- the falling shell is shown for this long before a capsule lands
local RED, GREEN = defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green
local CHEST = defines.inventory.chest

local QUALITY_POWER = 1   -- +100% per quality level, as an accumulator's capacity: legendary (level 5) = 6x (data.lua shows the same)
local function is_special(signal)
  local proto = signal and signal.type == "virtual" and prototypes.virtual_signal[signal.name]
  return proto and proto.special or false
end

local function compare(a, op, b)
  if op == ">" then return a > b elseif op == "<" then return a < b elseif op == "=" then return a == b
  elseif op == "≥" or op == ">=" then return a >= b elseif op == "≤" or op == "<=" then return a <= b
  else return a ~= b end
end

-- Prototype tables for each kind of signal (the rest are named the same as the signal's type)
local SIGNAL_TABLES = {virtual = "virtual_signal", ["space-location"] = "space_location", ["asteroid-chunk"] = "asteroid_chunk"}
local function signal_exists(signal)
  local list = prototypes[SIGNAL_TABLES[signal.type or "item"] or signal.type or "item"]
  return not list or list[signal.name] ~= nil
end

local function init_storage()
  storage.fallen = storage.fallen or {}        -- unit_number -> settings of a building that just died (for its ghost)
  storage.replaced = storage.replaced or {}    -- spot -> settings of a building mined this tick (it may be an upgrade)
  storage.cannons = storage.cannons or {}      -- unit_number -> cannon record
  storage.receivers = storage.receivers or {}  -- unit_number -> {entity, name, channel}
  storage.flights = storage.flights or {}      -- list of capsules in the air
  storage.inflight = storage.inflight or {}    -- receiver unit_number -> capsules on their way to it
  storage.next_channel = storage.next_channel or 1
  storage.open = storage.open or {}            -- player index -> the entity whose panel is open
  storage.target_lists = storage.target_lists or {} -- player index -> receiver unit_numbers in the drop-down
end

-- Settings for each kind of shot: energy (J), capsules, flight time (ticks)
local function shot_cost(kind)
  local o = storage.cost_override and storage.cost_override[kind]
  if o then return o.energy * 1e6, o.capsules, math.max(1, math.floor(o.flight * 60)) end
  local g = settings.global
  return g["cargo-cannon-" .. kind .. "-energy"].value * 1e6,
         g["cargo-cannon-" .. kind .. "-capsules"].value,
         math.max(1, math.floor(g["cargo-cannon-" .. kind .. "-flight"].value * 60))
end

---------------------------------------------------------------------------------------------------------
-- Where a surface is, and which kind of shot reaches from one surface to another
---------------------------------------------------------------------------------------------------------

-- "planet", <planet name>  |  "platform", <location it's stopped at, or nil while travelling>
local function where(surface)
  if surface.platform then
    local loc = surface.platform.space_location
    return "platform", loc and loc.name
  elseif surface.planet then
    return "planet", surface.planet.name
  end
end

-- kind ("orbit" / "interplanetary") or nil + the reason it can't be done
local function shot_kind(from, to, force)
  if from == to then return nil, "same-surface" end
  local fk, fl = where(from)
  local tk, tl = where(to)
  if not (fk and tk) then return nil, "no-route" end
  if fk == "platform" and not fl then return nil, "cannon-travelling" end
  if tk == "platform" and not tl then return nil, "target-travelling" end
  if fl == tl then return "orbit" end
  if fk == "planet" and tk == "planet" then
    local tech = force.technologies[INTERPLANETARY_TECH]
    if tech and tech.researched then return "interplanetary" end
    return nil, "needs-research"
  end
  return nil, "not-in-orbit"
end

local function surface_label(surface)
  if surface.platform then return surface.platform.name end
  if surface.planet then return surface.planet.prototype.localised_name end
  return surface.name
end

---------------------------------------------------------------------------------------------------------
-- Building and removing
---------------------------------------------------------------------------------------------------------

local function default_cannon(entity)
  return {entity = entity, target = nil, cargo = nil, full_stack = true,
          circuit_target = false, target_signal = nil, status = "no-target", space = 0, charge = 0}
end

-- 0.1.0 kept its own condition in the cannon's record (and in blueprint tags): move it to the game's own.
local function move_old_condition(c)
  if c.circuit_enable == nil and c.condition == nil then return end
  local old = c.condition
  if c.circuit_enable then
    local cb = c.entity.get_or_create_control_behavior()
    if old and old.signal then
      cb.circuit_condition = {first_signal = old.signal, comparator = old.comparator, constant = old.constant or 0}
    end
    cb.circuit_condition_enabled = true
  end
  c.circuit_enable, c.condition = nil, nil
end

-- A mod removed since these were picked (or a blueprint from another game): forget them, as they can't be used.
local function forget_missing(c)
  local cargo = c.cargo
  if cargo and not (prototypes.item[cargo.name] and prototypes.quality[cargo.quality]) then c.cargo = nil end
  if c.target_signal and not signal_exists(c.target_signal) then c.target_signal = nil end
end

-- A better cannon charges faster: the same draw the tooltip shows.
local function apply_power(c)
  local mw = settings.startup["cargo-cannon-charge-rate"].value * (1 + QUALITY_POWER * c.entity.quality.level)
  c.energy.input_flow_limit = mw * 1e6 / 60
end

local function wired_by_player(connector, helper)
  local wires = connector.connection_count
  if connector.is_connected_to(helper, defines.wire_origin.script) then wires = wires - 1 end
  return wires > 0
end

-- The readout goes on one wire only: on both, the cannon's own condition would add red + green and see everything
-- twice. It follows the player's wire: green if only green is used, otherwise red.
local function route_readout(c)
  local e = c.entity
  local red, green = e.get_wire_connector(RED, true), e.get_wire_connector(GREEN, true)
  local out_red, out_green = c.readout.get_wire_connector(RED, true), c.readout.get_wire_connector(GREEN, true)
  local to_green = wired_by_player(green, out_green) and not wired_by_player(red, out_red)
  local join, join_out, leave, leave_out = red, out_red, green, out_green
  if to_green then join, join_out, leave, leave_out = green, out_green, red, out_red end
  if leave.is_connected_to(leave_out, defines.wire_origin.script) then
    leave.disconnect_from(leave_out, defines.wire_origin.script)
  end
  if not join.is_connected_to(join_out, defines.wire_origin.script) then
    join.connect_to(join_out, false, defines.wire_origin.script)
  end
end

-- Slot 1 only takes capsules; slot 2 only takes the picked cargo, and is locked (inventory bar) until one is picked,
-- so an inserter or robot can never fill the cargo slot with capsules (or anything else) by mistake.
local function apply_slots(c, inv)
  local f1 = inv.get_filter(1)
  if not (f1 and f1.name == CAPSULE) then inv.set_filter(1, CAPSULE) end
  local cargo = c.cargo
  if cargo then
    if inv.get_bar() <= #inv then inv.set_bar() end
    local f2 = inv.get_filter(2)
    if not (f2 and f2.name == cargo.name and (f2.quality or "normal") == cargo.quality) then
      if not inv.set_filter(2, {name = cargo.name, quality = cargo.quality, comparator = "="}) then
        inv.set_filter(2, cargo.name)
      end
    end
  else
    if inv.get_filter(2) then inv.set_filter(2, nil) end
    if inv.get_bar() ~= 2 then inv.set_bar(2) end
  end
end

-- Makes the hidden helpers (at building time, or if something has destroyed them).
local function make_helpers(c)
  local e = c.entity
  local s, pos, force = e.surface, e.position, e.force
  if not (c.energy and c.energy.valid) then
    c.energy = s.create_entity{name = ENERGY, position = pos, force = force}
    c.energy.destructible = false
    apply_power(c)
  end
  if not (c.readout and c.readout.valid) then
    c.readout = s.create_entity{name = READOUT, position = pos, force = force}
    c.readout.destructible = false
    c.sent_space, c.sent_charge = nil, nil
    local cb = c.readout.get_or_create_control_behavior()
    if cb.sections_count == 0 then cb.add_section() end
    route_readout(c)
  end
end

local function remove_cannon(unit)
  local c = storage.cannons[unit]
  if not c then return end
  for _, helper in pairs({c.energy, c.readout}) do if helper and helper.valid then helper.destroy() end end
  storage.cannons[unit] = nil
end

local CANNON_SETTINGS = {"target", "cargo", "full_stack", "circuit_target", "target_signal"}

-- What a new building on this spot should inherit: the same shape as a blueprint's or ghost's tags.
local function remember(entity)
  local unit = entity.unit_number
  local c, r = storage.cannons[unit], storage.receivers[unit]
  if c then
    local t = {}
    for _, k in pairs(CANNON_SETTINGS) do t[k] = c[k] end
    return {dc_settings = t, dc_energy = c.energy and c.energy.valid and c.energy.energy or 0}
  elseif r then
    return {dc_receiver = {name = r.name, channel = r.channel, unit = unit}}
  end
end

local function spot(entity)
  return entity.surface.index .. ":" .. entity.position.x .. ":" .. entity.position.y
end

-- A quality upgrade or a fast replace mines the old building and builds the new one in the same tick.
local function replaced_here(entity)
  local key = spot(entity)
  local old = storage.replaced[key]
  storage.replaced[key] = nil
  return old and old.tick == game.tick and old.tags or nil
end

local function add_cannon(entity, tags)
  tags = replaced_here(entity) or tags
  local c = default_cannon(entity)
  make_helpers(c)
  entity.get_or_create_control_behavior()  -- its contents go on its wires, even before anything else is wired to it
  storage.cannons[entity.unit_number] = c
  if tags and tags.dc_settings then
    for k, v in pairs(tags.dc_settings) do c[k] = v end
    move_old_condition(c)  -- a blueprint saved with 0.1.0
  end
  if tags and tags.dc_energy then c.energy.energy = tags.dc_energy end
  forget_missing(c)
  apply_slots(c, entity.get_inventory(CHEST))
end

-- Cannons aimed at the old receiver, and capsules on their way to it, now mean this one.
local function take_over_receiver(old_unit, unit)
  if not old_unit then return end
  for _, c in pairs(storage.cannons) do
    if c.target == old_unit then c.target = unit end
  end
  for _, flight in pairs(storage.flights) do
    if flight.receiver == old_unit then flight.receiver = unit end
  end
  storage.inflight[unit] = storage.inflight[old_unit]
  storage.inflight[old_unit] = nil
end

local function add_receiver(entity, tags)
  tags = replaced_here(entity) or tags
  local unit = entity.unit_number
  local old = tags and tags.dc_receiver
  local r = {entity = entity}
  if old then
    r.name, r.channel = old.name, old.channel
    take_over_receiver(old.unit, unit)
  else
    r.channel = storage.next_channel
    r.name = "Receiver " .. r.channel
    storage.next_channel = r.channel + 1
  end
  storage.receivers[unit] = r
end

local function on_built(e)
  local entity = e.entity
  if not (entity and entity.valid) then return end
  if entity.name == CANNON then add_cannon(entity, e.tags)
  elseif entity.name == RECEIVER then add_receiver(entity, e.tags) end
end

local function on_removed(e)
  local entity = e.entity
  if not (entity and entity.valid and entity.unit_number) then return end
  local unit = entity.unit_number
  local tags = remember(entity)
  if tags and e.name == defines.events.on_entity_died then
    storage.fallen[unit] = tags
  elseif tags then
    storage.replaced[spot(entity)] = {tick = game.tick, tags = tags}
  end
  if entity.name == CANNON then remove_cannon(unit)
  elseif entity.name == RECEIVER then storage.receivers[unit] = nil end
end

-- A destroyed building's ghost keeps its settings, so what robots rebuild works as it did.
script.on_event(defines.events.on_post_entity_died, function(e)
  local fallen = e.unit_number and storage.fallen[e.unit_number]
  if not fallen then return end
  storage.fallen[e.unit_number] = nil
  if e.ghost and e.ghost.valid then
    local tags = e.ghost.tags or {}
    for k, v in pairs(fallen) do tags[k] = v end
    e.ghost.tags = tags
  end
end, {{filter = "type", type = "logistic-container"}})

local filters = {{filter = "name", name = CANNON}, {filter = "name", name = RECEIVER}}
for _, ev in pairs({defines.events.on_built_entity, defines.events.on_robot_built_entity,
                    defines.events.on_space_platform_built_entity, defines.events.script_raised_built,
                    defines.events.script_raised_revive}) do
  script.on_event(ev, on_built, filters)
end
for _, ev in pairs({defines.events.on_player_mined_entity, defines.events.on_robot_mined_entity,
                    defines.events.on_space_platform_mined_entity, defines.events.on_entity_died,
                    defines.events.script_raised_destroy}) do
  script.on_event(ev, on_removed, filters)
end

---------------------------------------------------------------------------------------------------------
-- Targets
---------------------------------------------------------------------------------------------------------

local function receiver_by_channel(channel, force)
  if not channel or channel == 0 then return nil end
  for unit, r in pairs(storage.receivers) do
    if r.entity.valid and r.channel == channel and r.entity.force == force then return r, unit end
  end
end

-- The receiver this cannon aims at right now (its picked target, or the one its circuit signal names)
local function current_target(c)
  local e = c.entity
  if c.circuit_target then
    if not c.target_signal or is_special(c.target_signal) then return nil end
    return receiver_by_channel(e.get_signal(c.target_signal, RED, GREEN), e.force)
  end
  local r = c.target and storage.receivers[c.target]
  if r and r.entity.valid then return r, c.target end
end

-- Empty stacks in a receiver, minus the capsules already on their way to it: each capsule is at most one stack,
-- so while this is above 0 the next shot is sure to fit.
local function receiver_space(r, unit)
  local free = r.entity.get_inventory(CHEST).count_empty_stacks(false, false)
  return free - (storage.inflight[unit] or 0)
end

---------------------------------------------------------------------------------------------------------
-- Firing, flying and landing
---------------------------------------------------------------------------------------------------------

local function item_text(stack_data)
  return "[item=" .. stack_data.name .. ",quality=" .. stack_data.quality .. "] x" .. stack_data.count
end
local function gps(surface, pos)
  return "[gps=" .. math.floor(pos.x) .. "," .. math.floor(pos.y) .. "," .. surface.name .. "]"
end

local function fire(c, r, unit, kind)
  local e = c.entity
  local inv = e.get_inventory(CHEST)
  local energy, capsules, flight_ticks = shot_cost(kind)
  local cargo = inv[2]
  local box = game.create_inventory(1)
  box[1].transfer_stack(cargo)
  local caps = inv[1]
  if caps.count > capsules then caps.count = caps.count - capsules else caps.clear() end
  c.energy.energy = math.max(0, c.energy.energy - energy)

  local s, p = e.surface, e.position
  s.create_entity{name = "artillery-cannon-muzzle-flash", position = {p.x, p.y - 2}, target = {p.x, p.y - 12}}
  s.play_sound{path = "cargo-cannon-fire", position = p}
  s.create_entity{name = FLIGHT, position = {p.x, p.y - 2}, target = {p.x + 6, p.y - 70}, speed = 1.2, force = e.force}

  local _, location = where(s)
  local stack = box[1]
  table.insert(storage.flights, {
    box = box, receiver = unit, surface = r.entity.surface.index, position = r.entity.position,
    arrive = game.tick + flight_ticks, kind = kind, location = location, force = e.force.name, fell = false,
    cargo = {name = stack.name, quality = stack.quality.name, count = stack.count},
  })
  storage.inflight[unit] = (storage.inflight[unit] or 0) + 1
end

local function crash(surface, pos, force, why, cargo)
  surface.create_entity{name = CRASH, position = pos, target = pos, speed = 1, force = "neutral"}
  local f = game.forces[force]
  if f then f.print({"cargo-cannon.crashed-" .. why, item_text(cargo), gps(surface, pos)}) end
end

local function land(flight)
  local unit = flight.receiver
  storage.inflight[unit] = math.max(0, (storage.inflight[unit] or 1) - 1)
  if storage.inflight[unit] == 0 then storage.inflight[unit] = nil end
  local box = flight.box
  local surface = game.get_surface(flight.surface)
  local f = game.forces[flight.force]
  if not surface then
    if f then f.print({"cargo-cannon.lost", item_text(flight.cargo)}) end
    box.destroy()
    return
  end
  -- an orbit shot at a platform that has since flown off: the capsule finds empty space
  local kind, location = where(surface)
  if kind == "platform" and flight.kind == "orbit" and location ~= flight.location then
    if f then f.print({"cargo-cannon.missed-platform", item_text(flight.cargo), surface_label(surface)}) end
    box.destroy()
    return
  end
  local r = storage.receivers[unit]
  if r and r.entity.valid then
    local inv = r.entity.get_inventory(CHEST)
    local stack = box[1]
    if stack.valid_for_read and inv.get_insertable_count({name = stack.name, quality = stack.quality.name}) >= stack.count then
      inv.insert(stack)
      surface.create_entity{name = "explosion-hit", position = r.entity.position}
      box.destroy()
      return
    end
    crash(surface, r.entity.position, flight.force, "full", flight.cargo)
  else
    crash(surface, flight.position, flight.force, "gone", flight.cargo)
  end
  box.destroy()
end

local function update_flights()
  local tick = game.tick
  local flights = storage.flights
  local i = 1
  while i <= #flights do
    local fl = flights[i]
    if not fl.fell and tick >= fl.arrive - FALL_TICKS then
      fl.fell = true
      local surface = game.get_surface(fl.surface)
      if surface then
        local p = fl.position
        surface.create_entity{name = FLIGHT, position = {p.x - 10, p.y - 60}, target = p,
                              speed = 61 / FALL_TICKS, force = fl.force}
      end
    end
    if tick >= fl.arrive then
      table.remove(flights, i)
      land(fl)
    else
      i = i + 1
    end
  end
end

---------------------------------------------------------------------------------------------------------
-- Each cannon, every CHECK_EVERY ticks
---------------------------------------------------------------------------------------------------------

local function set_readout(c, space, charge)
  if c.sent_space == space and c.sent_charge == charge then return end
  c.sent_space, c.sent_charge = space, charge
  local cb = c.readout.get_or_create_control_behavior()
  local section = cb.get_section(1)
  section.set_slot(1, {value = {type = "virtual", name = SPACE_SIGNAL.name, quality = "normal"}, min = space})
  section.set_slot(2, {value = {type = "virtual", name = CHARGE_SIGNAL.name, quality = "normal"}, min = charge})
end

-- The game's own condition, from the building's normal circuit tab. Its answer is used as it is, except when the
-- condition is about Receiver space or Cannon charge: those are this cannon's own numbers, read directly, so a cannon
-- sharing a wire with others never adds their free space to its own and fires at a full receiver.
local function condition_met(e, cb, space, charge)
  local cond = cb.circuit_condition
  local own = {[SPACE_SIGNAL.name] = space, [CHARGE_SIGNAL.name] = charge}
  local first = cond.first_signal
  if not (first and first.type == "virtual" and own[first.name]) then return cond.fulfilled end
  local other = cond.constant or 0
  local second = cond.second_signal
  if second then
    other = second.type == "virtual" and own[second.name] or e.get_signal(second, RED, GREEN)
  end
  return compare(own[first.name], cond.comparator, other)
end

local function update_cannon(c)
  local e = c.entity
  local inv = e.get_inventory(CHEST)
  make_helpers(c)
  apply_slots(c, inv)
  -- there's no event for wires changing, so each cannon looks about once a second, not all on the same tick
  if (e.unit_number + game.tick / CHECK_EVERY) % WIRE_CHECK_EVERY == 0 then route_readout(c) end
  local r, unit = current_target(c)
  local kind, why
  if r then kind, why = shot_kind(e.surface, r.entity.surface, e.force) else why = "no-target" end

  local need = kind and (shot_cost(kind)) or 0
  if kind and c.energy.electric_buffer_size ~= need then c.energy.electric_buffer_size = math.max(need, 1) end
  local charge = need > 0 and math.floor(100 * math.min(1, c.energy.energy / need)) or (kind and 100 or 0)
  local space = r and receiver_space(r, unit) or 0
  set_readout(c, space, charge)
  c.space, c.charge = space, charge

  if not kind then c.status = why return end
  local cb = e.get_or_create_control_behavior()
  if cb.circuit_condition_enabled and not condition_met(e, cb, space, charge) then c.status = "disabled" return end
  local _, capsules = shot_cost(kind)
  local caps = inv[1]
  if not (caps.valid_for_read and caps.name == CAPSULE and caps.count >= capsules) then c.status = "no-capsules" return end
  if not c.cargo then c.status = "no-cargo-picked" return end
  local cargo = inv[2]
  if not cargo.valid_for_read then c.status = "no-cargo" return end
  if cargo.name ~= c.cargo.name or cargo.quality.name ~= c.cargo.quality then c.status = "wrong-cargo" return end
  if c.full_stack and cargo.count < cargo.prototype.stack_size then c.status = "waiting-full" return end
  if c.energy.energy < need then
    c.status = c.energy.is_connected_to_electric_network() and "charging" or "no-power"
    return
  end
  fire(c, r, unit, kind)
  c.status = "fired"
  -- anything reading these from the wire sees the shot straight away, not at the next check
  c.space = receiver_space(r, unit)
  c.charge = need > 0 and math.floor(100 * math.min(1, c.energy.energy / need)) or 100
  set_readout(c, c.space, c.charge)
end

local refresh_panels -- defined below

script.on_nth_tick(CHECK_EVERY, function()
  init_storage()  -- a save from a test build of the same version doesn't get on_configuration_changed
  for unit, c in pairs(storage.cannons) do
    if c.entity.valid then update_cannon(c) else remove_cannon(unit) end
  end
  for unit, r in pairs(storage.receivers) do
    if not r.entity.valid then storage.receivers[unit] = nil end
  end
  update_flights()
  refresh_panels()
  if next(storage.replaced) then storage.replaced = {} end
end)

script.on_init(init_storage)
script.on_configuration_changed(function()
  init_storage()
  for _, c in pairs(storage.cannons) do
    if c.entity.valid then
      c.entity.get_or_create_control_behavior()  -- cannons built by 0.1.0 test builds: contents on the wire too
      move_old_condition(c)
      forget_missing(c)
      make_helpers(c)
      route_readout(c)
      apply_power(c)
    end
  end
end)

---------------------------------------------------------------------------------------------------------
-- The panel beside the cannon's / receiver's window
---------------------------------------------------------------------------------------------------------

local PANEL = "dc_panel"

local function close_panel(player)
  local old = player.gui.relative[PANEL]
  if old then old.destroy() end
  storage.open[player.index] = nil
  storage.target_lists[player.index] = nil
end

local function target_caption(c, r)
  local kind, why = shot_kind(c.entity.surface, r.entity.surface, c.entity.force)
  return {"", r.name, " (#", r.channel, ") - ", surface_label(r.entity.surface), " - ",
          kind and {"dc-gui.kind-" .. kind} or {"dc-gui.why-" .. why}}
end

local function fill_targets(player, c, dropdown)
  local list, items, selected = {}, {{"dc-gui.no-target"}}, 1
  local sorted = {}
  for unit, r in pairs(storage.receivers) do
    if r.entity.valid and r.entity.force == c.entity.force and r.entity.surface ~= c.entity.surface then
      table.insert(sorted, {unit = unit, r = r})
    end
  end
  table.sort(sorted, function(a, b) return a.r.name < b.r.name end)
  for _, x in ipairs(sorted) do
    table.insert(list, x.unit)
    table.insert(items, target_caption(c, x.r))
    if x.unit == c.target then selected = #items end
  end
  dropdown.items = items
  dropdown.selected_index = selected
  storage.target_lists[player.index] = list
end

local function open_cannon_panel(player, entity)
  local c = storage.cannons[entity.unit_number]
  if not c then return end
  local frame = player.gui.relative.add{type = "frame", name = PANEL, direction = "vertical", caption = {"dc-gui.cannon-title"},
    anchor = {gui = defines.relative_gui_type.container_gui, position = defines.relative_gui_position.right, name = CANNON}}
  local status = frame.add{type = "label", name = "dc_status"}
  status.style.single_line = false
  status.style.maximal_width = 300
  frame.add{type = "progressbar", name = "dc_charge", value = 0}.style.horizontally_stretchable = true
  frame.add{type = "label", name = "dc_charge_text"}
  frame.add{type = "label", caption = {"dc-gui.target"}, style = "caption_label"}
  local dd = frame.add{type = "drop-down", name = "dc_target"}
  dd.style.width = 300
  fill_targets(player, c, dd)
  dd.enabled = not c.circuit_target
  local cargo_row = frame.add{type = "flow", direction = "horizontal"}
  cargo_row.style.vertical_align = "center"
  cargo_row.add{type = "label", caption = {"dc-gui.cargo"}, style = "caption_label", tooltip = {"dc-gui.cargo-tooltip"}}
  local pick = cargo_row.add{type = "choose-elem-button", name = "dc_cargo", elem_type = "item-with-quality",
                             elem_filters = {{filter = "hidden", invert = true}}, tooltip = {"dc-gui.cargo-tooltip"}}
  if c.cargo then pick.elem_value = {name = c.cargo.name, quality = c.cargo.quality} end
  frame.add{type = "checkbox", name = "dc_full_stack", caption = {"dc-gui.full-stack"}, state = c.full_stack,
            tooltip = {"dc-gui.full-stack-tooltip"}}

  frame.add{type = "line"}
  frame.add{type = "checkbox", name = "dc_circuit_target", caption = {"dc-gui.target-by-signal"}, state = c.circuit_target,
            tooltip = {"dc-gui.target-by-signal-tooltip"}}
  local row2 = frame.add{type = "flow", direction = "horizontal"}
  row2.add{type = "choose-elem-button", name = "dc_target_signal", elem_type = "signal"}.elem_value = c.target_signal

  frame.add{type = "line"}
  frame.add{type = "label", caption = {"dc-gui.signals"}, style = "caption_label", tooltip = {"dc-gui.signals-tooltip"}}
  frame.add{type = "label", name = "dc_space", tooltip = {"dc-gui.space-tooltip"}}
  frame.add{type = "label", name = "dc_charge_signal", tooltip = {"dc-gui.charge-tooltip"}}
  local hint = frame.add{type = "label", caption = {"dc-gui.condition-hint"}}
  hint.style.single_line = false
  hint.style.maximal_width = 300
  hint.style.font_color = {0.7, 0.7, 0.7}
end

local function open_receiver_panel(player, entity)
  local r = storage.receivers[entity.unit_number]
  if not r then return end
  local frame = player.gui.relative.add{type = "frame", name = PANEL, direction = "vertical", caption = {"dc-gui.receiver-title"},
    anchor = {gui = defines.relative_gui_type.container_gui, position = defines.relative_gui_position.right, name = RECEIVER}}
  frame.add{type = "label", caption = {"dc-gui.name"}, style = "caption_label"}
  frame.add{type = "textfield", name = "dc_name", text = r.name}.style.width = 220
  frame.add{type = "label", caption = {"dc-gui.channel"}, style = "caption_label", tooltip = {"dc-gui.channel-tooltip"}}
  frame.add{type = "textfield", name = "dc_channel", text = tostring(r.channel), numeric = true, tooltip = {"dc-gui.channel-tooltip"}}.style.width = 100
  frame.add{type = "label", name = "dc_incoming"}
end

local function refresh_panel(player)
  local frame = player.gui.relative[PANEL]
  local entity = storage.open[player.index]
  if not (frame and entity and entity.valid) then return end
  if entity.name == CANNON then
    local c = storage.cannons[entity.unit_number]
    if not c then return end
    local r = current_target(c)
    local kind = r and shot_kind(entity.surface, r.entity.surface, entity.force)
    local need = kind and shot_cost(kind) or 0
    local status = c.status == "no-target" and c.circuit_target and "no-channel" or c.status
    frame.dc_status.caption = {"dc-gui.status-" .. status, kind and select(2, shot_cost(kind)) or 1}
    frame.dc_charge.value = need > 0 and math.min(1, c.energy.energy / need) or 0
    frame.dc_charge_text.caption = need > 0 and {"dc-gui.charge", math.floor(c.energy.energy / 1e6), math.floor(need / 1e6)} or ""
    frame.dc_space.caption = {"dc-gui.signal-space", c.space or 0}
    frame.dc_charge_signal.caption = {"dc-gui.signal-charge", c.charge or 0}
  else
    local n = storage.inflight[entity.unit_number] or 0
    frame.dc_incoming.caption = {"dc-gui.incoming", n}
  end
end

refresh_panels = function()
  for index, entity in pairs(storage.open) do
    local player = game.get_player(index)
    if player and entity.valid then refresh_panel(player) else storage.open[index] = nil end
  end
end

script.on_event(defines.events.on_gui_opened, function(e)
  local player = game.get_player(e.player_index)
  close_panel(player)
  local ent = e.entity
  if not (ent and ent.valid) then return end
  if ent.name == CANNON then open_cannon_panel(player, ent)
  elseif ent.name == RECEIVER then open_receiver_panel(player, ent)
  else return end
  storage.open[player.index] = ent
  refresh_panel(player)
end)

script.on_event(defines.events.on_gui_closed, function(e)
  if e.entity then close_panel(game.get_player(e.player_index)) end
end)

local function open_record(player_index)
  local entity = storage.open[player_index]
  if not (entity and entity.valid) then return end
  return storage.cannons[entity.unit_number] or storage.receivers[entity.unit_number], entity
end

script.on_event(defines.events.on_gui_selection_state_changed, function(e)
  local rec = open_record(e.player_index)
  if not rec then return end
  local el = e.element
  if el.name == "dc_target" then
    local list = storage.target_lists[e.player_index] or {}
    rec.target = list[el.selected_index - 1]
  end
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(e)
  local rec = open_record(e.player_index)
  if not rec then return end
  local el = e.element
  if el.name == "dc_full_stack" then rec.full_stack = el.state
  elseif el.name == "dc_circuit_target" then
    rec.circuit_target = el.state
    local frame = game.get_player(e.player_index).gui.relative[PANEL]
    if frame and frame.dc_target then frame.dc_target.enabled = not el.state end
  end
end)

script.on_event(defines.events.on_gui_elem_changed, function(e)
  local rec = open_record(e.player_index)
  if not rec then return end
  local el = e.element
  if el.name == "dc_target_signal" then
    local v = el.elem_value
    if is_special(v) then
      el.elem_value = rec.target_signal
      game.get_player(e.player_index).create_local_flying_text{text = {"dc-gui.no-special-target"}, create_at_cursor = true}
      return
    end
    rec.target_signal = v
  elseif el.name == "dc_cargo" then
    local v = el.elem_value
    rec.cargo = v and {name = v.name, quality = v.quality or "normal"} or nil
    if rec.entity and rec.entity.valid then apply_slots(rec, rec.entity.get_inventory(CHEST)) end
  end
end)

script.on_event(defines.events.on_gui_text_changed, function(e)
  local rec = open_record(e.player_index)
  if not rec then return end
  local el = e.element
  if el.name == "dc_name" then rec.name = el.text ~= "" and el.text or ("Receiver " .. rec.channel)
  elseif el.name == "dc_channel" then rec.channel = tonumber(el.text) or rec.channel end
end)

---------------------------------------------------------------------------------------------------------
-- Copy / paste and blueprints carry a cannon's settings
---------------------------------------------------------------------------------------------------------

-- (The circuit condition is the game's own, so the game copies it.)
local function settings_of(c)
  local t = {}
  for _, k in pairs(CANNON_SETTINGS) do t[k] = c[k] end
  return t
end

script.on_event(defines.events.on_entity_settings_pasted, function(e)
  local src, dst = e.source, e.destination
  if not (src.valid and dst.valid and src.name == CANNON and dst.name == CANNON) then return end
  local a, b = storage.cannons[src.unit_number], storage.cannons[dst.unit_number]
  if a and b then
    for k, v in pairs(settings_of(a)) do b[k] = v end
    apply_slots(b, dst.get_inventory(CHEST))
  end
end)

script.on_event(defines.events.on_player_setup_blueprint, function(e)
  local player = game.get_player(e.player_index)
  local function usable(x)
    if not x then return false end
    local ok, result = pcall(function()
      if x.object_name == "LuaRecord" then return x.valid and x.type == "blueprint" and x.is_blueprint_setup() end
      return x.valid_for_read and x.is_blueprint and x.is_blueprint_setup()
    end)
    return ok and result
  end
  local bp
  for _, candidate in pairs({e.stack, e.record, player.blueprint_to_setup, player.cursor_stack}) do
    if usable(candidate) then bp = candidate break end
  end
  if not bp then return end
  for index, entity in pairs(e.mapping.get()) do
    local c = entity.valid and entity.name == CANNON and storage.cannons[entity.unit_number]
    if c then bp.set_blueprint_entity_tag(index, "dc_settings", settings_of(c)) end
  end
end)

remote.add_interface("cargo-cannon", {
  -- for tests and other mods
  cannon = function(entity) return entity and entity.valid and storage.cannons[entity.unit_number] end,
  receiver = function(entity) return entity and entity.valid and storage.receivers[entity.unit_number] end,
  set_target = function(cannon, receiver)
    local c = storage.cannons[cannon.unit_number]
    if c then c.target = receiver and receiver.unit_number or nil end
  end,
  configure = function(cannon, values)
    local c = storage.cannons[cannon.unit_number]
    if c then
      for k, v in pairs(values) do c[k] = v end
      move_old_condition(c)  -- so the tests can stand in for a 0.1.0 cannon
      forget_missing(c)
      apply_slots(c, cannon.get_inventory(CHEST))
    end
  end,
  -- a receiver's name and / or channel ({name = "...", channel = n})
  configure_receiver = function(receiver, values)
    local r = storage.receivers[receiver.unit_number]
    if not r then return end
    if values.name then r.name = values.name end
    if values.channel then r.channel = values.channel end
  end,
  flights = function() return #storage.flights end,
  -- override a kind of shot's cost ({energy = MJ, capsules = n, flight = seconds}; nil = back to the mod settings)
  set_cost = function(kind, cost)
    storage.cost_override = storage.cost_override or {}
    storage.cost_override[kind] = cost
  end,
})
