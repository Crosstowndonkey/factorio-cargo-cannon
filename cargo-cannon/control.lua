-- Cargo Cannon: fires capsules of cargo from one surface to a receiver on another.
--
-- A cannon is a 2-slot container: slot 1 holds capsules, slot 2 the cargo (one stack of one item per shot). Two
-- hidden helpers sit on it: an electric-energy-interface (the charge) and a constant combinator wired to the cannon
-- by script, which tells the circuit network how much room the target receiver has and how charged the cannon is.
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
local FALL_TICKS = 60    -- the falling shell is shown for this long before a capsule lands
local RED, GREEN = defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green
local CHEST = defines.inventory.chest

local ANYTHING, EVERYTHING = "signal-anything", "signal-everything"
local function is_special(signal)
  local proto = signal and signal.type == "virtual" and prototypes.virtual_signal[signal.name]
  return proto and proto.special or false
end

local COMPARATORS = {">", "<", "=", "≥", "≤", "≠"}
local function compare(a, op, b)
  if op == ">" then return a > b elseif op == "<" then return a < b elseif op == "=" then return a == b
  elseif op == "≥" then return a >= b elseif op == "≤" then return a <= b else return a ~= b end
end

local function init_storage()
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
          circuit_enable = false, condition = {signal = nil, comparator = ">", constant = 0},
          circuit_target = false, target_signal = nil, status = "no-target"}
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

local function add_cannon(entity, tags)
  local s, pos, force = entity.surface, entity.position, entity.force
  local c = default_cannon(entity)
  c.energy = s.create_entity{name = ENERGY, position = pos, force = force}
  c.energy.destructible = false
  c.readout = s.create_entity{name = READOUT, position = pos, force = force}
  c.readout.destructible = false
  for _, id in pairs({RED, GREEN}) do
    entity.get_wire_connector(id, true).connect_to(c.readout.get_wire_connector(id, true), false, defines.wire_origin.script)
  end
  entity.get_or_create_control_behavior()  -- its contents go on its wires, even before anything else is wired to it
  local cb = c.readout.get_or_create_control_behavior()
  if cb.sections_count == 0 then cb.add_section() end
  storage.cannons[entity.unit_number] = c
  if tags and tags.dc_settings then
    for k, v in pairs(tags.dc_settings) do c[k] = v end
  end
  apply_slots(c, entity.get_inventory(CHEST))
end

local function add_receiver(entity)
  local ch = storage.next_channel
  storage.next_channel = ch + 1
  storage.receivers[entity.unit_number] = {entity = entity, name = "Receiver " .. ch, channel = ch}
end

local function remove_cannon(unit)
  local c = storage.cannons[unit]
  if not c then return end
  for _, helper in pairs({c.energy, c.readout}) do if helper and helper.valid then helper.destroy() end end
  storage.cannons[unit] = nil
end

local function on_built(e)
  local entity = e.entity
  if not (entity and entity.valid) then return end
  if entity.name == CANNON then add_cannon(entity, e.tags)
  elseif entity.name == RECEIVER then add_receiver(entity) end
end

local function on_removed(e)
  local entity = e.entity
  if not (entity and entity.valid and entity.unit_number) then return end
  if entity.name == CANNON then remove_cannon(entity.unit_number)
  elseif entity.name == RECEIVER then storage.receivers[entity.unit_number] = nil end
end

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
  local cb = c.readout.get_or_create_control_behavior()
  local section = cb.get_section(1)
  section.set_slot(1, {value = {type = "virtual", name = SPACE_SIGNAL.name, quality = "normal"}, min = space})
  section.set_slot(2, {value = {type = "virtual", name = CHARGE_SIGNAL.name, quality = "normal"}, min = charge})
end

-- The enable condition, as on an inserter: one signal, or Anything (true if any signal passes) / Everything (true
-- if every signal passes, or there are none). Each can't be picked (the GUI refuses it).
-- The cannon is joined to its readout on both wires, so whatever it sends is on both networks, and reading red +
-- green would count it twice: its contents are counted once, and its two readouts are read as they are (other
-- cannons sharing the wire would add theirs).
local function condition_met(e, cond, space, charge)
  local sig, op, k = cond.signal, cond.comparator, cond.constant or 0
  local inv = e.get_inventory(CHEST)
  local own = {[SPACE_SIGNAL.name] = space, [CHARGE_SIGNAL.name] = charge}
  local function value(signal, count)
    local t = signal.type or "item"
    if t == "virtual" and own[signal.name] then return own[signal.name] end
    if t == "item" then return count - inv.get_item_count({name = signal.name, quality = signal.quality or "normal"}) end
    return count
  end
  local name = sig.type == "virtual" and sig.name
  if name == ANYTHING or name == EVERYTHING then
    local any, all = false, true
    local function test(v) if compare(v, op, k) then any = true else all = false end end
    for _, s in pairs(e.get_signals(RED, GREEN) or {}) do
      if not (s.signal.type == "virtual" and own[s.signal.name]) then
        local v = value(s.signal, s.count)
        if v ~= 0 then test(v) end
      end
    end
    for _, v in pairs(own) do if v ~= 0 then test(v) end end
    if name == ANYTHING then return any end
    return all
  end
  if is_special(sig) then return false end
  return compare(value(sig, e.get_signal(sig, RED, GREEN)), op, k)
end

local function update_cannon(c)
  local e = c.entity
  local inv = e.get_inventory(CHEST)
  apply_slots(c, inv)
  local r, unit = current_target(c)
  local kind, why
  if r then kind, why = shot_kind(e.surface, r.entity.surface, e.force) else why = "no-target" end

  local need = kind and (shot_cost(kind)) or 0
  if kind and c.energy.electric_buffer_size ~= need then c.energy.electric_buffer_size = math.max(need, 1) end
  local charge = need > 0 and math.floor(100 * math.min(1, c.energy.energy / need)) or (kind and 100 or 0)
  local space = r and receiver_space(r, unit) or 0
  set_readout(c, space, charge)

  if not kind then c.status = why return end
  if c.circuit_enable then
    local cond = c.condition
    if not cond.signal then c.status = "disabled" return end
    if not condition_met(e, cond, space, charge) then c.status = "disabled" return end
  end
  local _, capsules = shot_cost(kind)
  local caps = inv[1]
  if not (caps.valid_for_read and caps.name == CAPSULE and caps.count >= capsules) then c.status = "no-capsules" return end
  if not c.cargo then c.status = "no-cargo-picked" return end
  local cargo = inv[2]
  if not cargo.valid_for_read then c.status = "no-cargo" return end
  if cargo.name ~= c.cargo.name or cargo.quality.name ~= c.cargo.quality then c.status = "wrong-cargo" return end
  if c.full_stack and cargo.count < cargo.prototype.stack_size then c.status = "waiting-full" return end
  if c.energy.energy < need then c.status = "charging" return end
  fire(c, r, unit, kind)
  c.status = "fired"
end

local refresh_panels -- defined below

script.on_nth_tick(CHECK_EVERY, function()
  for unit, c in pairs(storage.cannons) do
    if c.entity.valid then update_cannon(c) else remove_cannon(unit) end
  end
  for unit, r in pairs(storage.receivers) do
    if not r.entity.valid then storage.receivers[unit] = nil end
  end
  update_flights()
  refresh_panels()
end)

script.on_init(init_storage)
script.on_configuration_changed(function()
  init_storage()
  for _, c in pairs(storage.cannons) do  -- cannons built by 0.1.0 test builds: contents on the wire too
    if c.entity.valid then c.entity.get_or_create_control_behavior() end
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
  frame.add{type = "label", caption = {"dc-gui.circuit"}, style = "caption_label"}
  frame.add{type = "checkbox", name = "dc_circuit_enable", caption = {"dc-gui.enable"}, state = c.circuit_enable}
  local row = frame.add{type = "flow", name = "dc_cond", direction = "horizontal"}
  row.style.vertical_align = "center"
  local sig = row.add{type = "choose-elem-button", name = "dc_cond_signal", elem_type = "signal"}
  sig.elem_value = c.condition.signal
  local cmp_index = 1
  for i, op in ipairs(COMPARATORS) do if op == c.condition.comparator then cmp_index = i end end
  row.add{type = "drop-down", name = "dc_cond_cmp", items = COMPARATORS, selected_index = cmp_index}.style.width = 60
  local num = row.add{type = "textfield", name = "dc_cond_value", text = tostring(c.condition.constant or 0),
                      numeric = true, allow_negative = true}
  num.style.width = 80
  frame.add{type = "checkbox", name = "dc_circuit_target", caption = {"dc-gui.target-by-signal"}, state = c.circuit_target,
            tooltip = {"dc-gui.target-by-signal-tooltip"}}
  local row2 = frame.add{type = "flow", direction = "horizontal"}
  row2.add{type = "choose-elem-button", name = "dc_target_signal", elem_type = "signal"}.elem_value = c.target_signal
  local hint = frame.add{type = "label", caption = {"dc-gui.readout-hint"}}
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
    frame.dc_status.caption = {"dc-gui.status-" .. c.status}
    frame.dc_charge.value = need > 0 and math.min(1, c.energy.energy / need) or 0
    frame.dc_charge_text.caption = need > 0 and {"dc-gui.charge", math.floor(c.energy.energy / 1e6), math.floor(need / 1e6)} or ""
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
  elseif el.name == "dc_cond_cmp" then
    rec.condition.comparator = COMPARATORS[el.selected_index]
  end
end)

script.on_event(defines.events.on_gui_checked_state_changed, function(e)
  local rec = open_record(e.player_index)
  if not rec then return end
  local el = e.element
  if el.name == "dc_full_stack" then rec.full_stack = el.state
  elseif el.name == "dc_circuit_enable" then rec.circuit_enable = el.state
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
  if el.name == "dc_cond_signal" then
    local v = el.elem_value
    if is_special(v) and v.name ~= ANYTHING and v.name ~= EVERYTHING then
      el.elem_value = rec.condition.signal
      game.get_player(e.player_index).create_local_flying_text{text = {"dc-gui.no-each"}, create_at_cursor = true}
      return
    end
    rec.condition.signal = v
  elseif el.name == "dc_target_signal" then
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
  if el.name == "dc_cond_value" then rec.condition.constant = tonumber(el.text) or 0
  elseif el.name == "dc_name" then rec.name = el.text ~= "" and el.text or ("Receiver " .. rec.channel)
  elseif el.name == "dc_channel" then rec.channel = tonumber(el.text) or rec.channel end
end)

---------------------------------------------------------------------------------------------------------
-- Copy / paste and blueprints carry a cannon's settings
---------------------------------------------------------------------------------------------------------

local SETTINGS = {"target", "cargo", "full_stack", "circuit_enable", "condition", "circuit_target", "target_signal"}
local function settings_of(c)
  local t = {}
  for _, k in pairs(SETTINGS) do t[k] = c[k] end
  t.condition = {signal = c.condition.signal, comparator = c.condition.comparator, constant = c.condition.constant}
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
