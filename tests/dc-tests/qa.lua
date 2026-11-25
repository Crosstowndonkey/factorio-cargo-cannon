-- Suite "qa": scenarios from the 0.2.2 QA pass. Each one was a bug (or a gap) in 0.2.1.
local C = require("common")
local DC, check, count, CHEST = C.DC, C.check, C.count, C.CHEST
local S = {}

local function helpers_near(s, pos)
  local area = {{pos[1] - 1, pos[2] - 1}, {pos[1] + 1, pos[2] + 1}}
  return s.count_entities_filtered{area = area, name = "cargo-cannon-energy"},
         s.count_entities_filtered{area = area, name = "cargo-cannon-readout"}
end

local function player_with_body(n)
  local player = game.get_player(1)
  if player and not player.character then
    local body = n.create_entity{name = "character", position = {0, 4}, force = "player"}
    player.set_controller{type = defines.controllers.character, character = body}
  end
  return player
end

-- open an entity's window, standing next to it (opening needs reach)
local function open(player, entity)
  player.character.teleport({entity.position.x, entity.position.y + 4})
  local ok = pcall(function() player.opened = entity end)
  return ok and player.gui.relative.dc_panel
end

-- The mod's own GUI handler, run on a real element of its panel (scripts can't raise GUI events).
local function find_named(el, name)
  if el.name == name then return el end
  for _, child in pairs(el.children) do
    local found = find_named(child, name)
    if found then return found end
  end
end

local function gui(player, event, element)
  DC("test_gui_event", event, {player_index = player.index, element = element})
end

function S.setup(T)
  local W = C.world()
  DC("set_cost", "orbit", {energy = 20, capsules = 1, flight = 8})
  local n, p = W.n, W.p
  T.W = W

  -- 1. capsules of a better quality go into slot 1 and are fired
  T.q_rx = C.build(p, "cargo-cannon-receiver", {-30, -30})
  T.q = C.build(n, "cargo-cannon", {-55, -50})
  DC("configure", T.q, {cargo = {name = "iron-plate", quality = "normal"}})
  T.q_inserted = T.q.get_inventory(CHEST).insert{name = "cargo-cannon-capsule", quality = "uncommon", count = 5}
  T.q.get_inventory(CHEST)[2].set_stack{name = "iron-plate", count = 100}
  DC("set_target", T.q, T.q_rx)

  -- 2. a capsule on its way to a platform that is deleted, then a new platform gets the old surface's index:
  --    the capsule must not land (and explode) on the new platform
  T.doomed = C.platform("Doomed platform", "nauvis", 20)
  T.doomed_index = T.doomed.surface.index
  T.doomed_rx = C.build(T.doomed.surface, "cargo-cannon-receiver", {10, 10})
  T.to_doomed = C.cannon(n, {-47, -50}, T.doomed_rx, "copper-plate", 100)

  -- 3. another mod clones a cannon and a receiver (a spaceship mod moving a ship): the copies work, with no
  --    duplicate hidden helpers
  T.cl_rx = C.build(p, "cargo-cannon-receiver", {-20, -30})
  T.cl = C.cannon(n, {-39, -50}, T.cl_rx, "stone", 50, {full_stack = false})
  T.cl.get_inventory(CHEST)[1].clear() -- (fires only after the clone has been made)
  T.cl_src_rx = C.build(n, "cargo-cannon-receiver", {-39, -30})
  DC("configure_receiver", T.cl_src_rx, {name = "Cloned dock", channel = 4242})

  -- 4. a new receiver never gets a channel another receiver already uses
  T.ch1 = C.build(n, "cargo-cannon-receiver", {-55, 30})
  local next_channel = DC("receiver", T.ch1).channel + 1
  DC("configure_receiver", T.ch1, {channel = next_channel})
  T.ch2 = C.build(n, "cargo-cannon-receiver", {-47, 30})

  -- 5. a receiver from a blueprint keeps its name and channel (a fresh channel if that one is taken), and a
  --    blueprint never takes over the receiver it was made from
  T.bp_orig = C.build(p, "cargo-cannon-receiver", {-10, -30})
  DC("configure_receiver", T.bp_orig, {name = "Iron dock", channel = 77})
  T.bp_aim = C.cannon(n, {-31, -50}, T.bp_orig, "iron-ore", 50)
  T.bp_aim.get_inventory(CHEST)[1].clear()
  local tags = {dc_receiver = {name = "Iron dock", channel = 77}}
  T.bp_ghost1 = n.create_entity{name = "entity-ghost", inner_name = "cargo-cannon-receiver", position = {-39, 30}, force = "player", tags = tags}
  T.bp_ghost2 = n.create_entity{name = "entity-ghost", inner_name = "cargo-cannon-receiver", position = {-31, 30}, force = "player",
    tags = {dc_receiver = {name = "Copper dock", channel = 4343}}}
  -- (a receiver's settings as an older version's death ghost wrote them: the unit is that of a live receiver)
  T.bp_ghost3 = n.create_entity{name = "entity-ghost", inner_name = "cargo-cannon-receiver", position = {-23, 30}, force = "player",
    tags = {dc_receiver = {name = "Imposter", channel = 99, unit = T.bp_orig.unit_number}}}
  -- copy / paste between receivers copies the name
  T.cp_src = C.build(n, "cargo-cannon-receiver", {-15, 30})
  DC("configure_receiver", T.cp_src, {name = "Gear dock"})
  T.cp_dst = C.build(n, "cargo-cannon-receiver", {-7, 30})

  -- 6. a cannon and a receiver another mod placed without telling anyone (no raise_built) are adopted
  T.quiet = n.create_entity{name = "cargo-cannon", position = {1, 30}, force = "player"}
  T.quiet_rx = n.create_entity{name = "cargo-cannon-receiver", position = {9, 30}, force = "player"}

  -- 7. the panel's controls, with the mod's own handlers on the real elements
  T.g_rx = C.build(p, "cargo-cannon-receiver", {0, -30})
  T.g = C.build(n, "cargo-cannon", {-23, -50})
  T.g_rx2 = C.build(n, "cargo-cannon-receiver", {17, 30})
  C.load(T.g, 10, nil, 0)
end

function S.tick(T, tick)
  local W = T.W
  local n = W.n
  -- 2: delete the platform as soon as its capsule is in the air, then make a new one (it takes the old index)
  if not T.doomed_fired and count(T.to_doomed, "copper-plate") == 0 then
    T.doomed_fired = tick
    T.doomed.destroy(1)
  end
  if T.doomed_fired and not T.newcomer and not T.doomed.valid then
    T.newcomer = C.platform("Newcomer", "nauvis", 20)
    T.new_index = T.newcomer.surface.index
    T.witness = T.newcomer.surface.create_entity{name = "steel-chest", position = {10, 10}, force = "player"}
  end

  if tick == 5 then
    -- 3: clone the cannon and the receiver, as a spaceship mod would (the whole area, wires and all)
    n.clone_area{source_area = {{-41, -52}, {-37, -48}}, destination_area = {{-41, -38}, {-37, -34}}}
    n.clone_area{source_area = {{-42, -33}, {-36, -27}}, destination_area = {{-42, -25}, {-36, -19}}}
    T.clone = n.find_entities_filtered{name = "cargo-cannon", position = {-39, -36}, radius = 1}[1]
    T.clone_rx = n.find_entities_filtered{name = "cargo-cannon-receiver", position = {-39, -22}, radius = 1}[1]
    if T.clone then T.clone.get_inventory(CHEST)[1].set_stack{name = "cargo-cannon-capsule", count = 5} end
    -- 5: revive the ghosts
    local _, r1 = T.bp_ghost1.revive{raise_revive = true}
    local _, r2 = T.bp_ghost2.revive{raise_revive = true}
    local _, r3 = T.bp_ghost3.revive{raise_revive = true}
    T.bp1, T.bp2, T.bp3 = r1, r2, r3
    local player = player_with_body(n)
    T.cp_dst.copy_settings(T.cp_src, player)
    -- 6
    T.quiet_opened = open(player, T.quiet) ~= nil
    T.quiet_rx_opened = open(player, T.quiet_rx) ~= nil
    player.opened = nil
  end

  if tick == 10 then
    -- 7: open the cannon and use its controls
    local player = game.get_player(1)
    local frame = open(player, T.g)
    T.g_frame = frame ~= nil
    if frame then
      local dd = frame.dc_target
      local wanted
      for i, item in ipairs(dd.items) do if i > 1 and serpent.line(item):find(DC("receiver", T.g_rx).name, 1, true) then wanted = i end end
      T.g_items = #dd.items
      if wanted then
        dd.selected_index = wanted
        gui(player, defines.events.on_gui_selection_state_changed, dd)
      end
      local pick = frame.children[6] and frame.children[6].dc_cargo
      for _, child in pairs(frame.children) do if child.dc_cargo then pick = child.dc_cargo end end
      pick.elem_value = {name = "copper-cable", quality = "normal"}
      gui(player, defines.events.on_gui_elem_changed, pick)
      frame.dc_full_stack.state = false
      gui(player, defines.events.on_gui_checked_state_changed, frame.dc_full_stack)
      -- target by signal, with no signal picked yet: the status asks for the signal
      local by_signal = find_named(frame, "dc_circuit_target")
      by_signal.state = true
      gui(player, defines.events.on_gui_checked_state_changed, by_signal)
      T.g_by_signal_caption = DC("test_panel_status", player)
      by_signal.state = false
      gui(player, defines.events.on_gui_checked_state_changed, by_signal)
      T.g.get_inventory(CHEST)[2].set_stack{name = "copper-cable", count = 30}
    end
    local rframe = open(player, T.g_rx2)
    if rframe then
      rframe.dc_name.text = "Cable dock"
      gui(player, defines.events.on_gui_text_changed, rframe.dc_name)
      rframe.dc_channel.text = "515"
      gui(player, defines.events.on_gui_text_changed, rframe.dc_channel)
    end
    player.opened = nil
  end

  if tick == 1500 then
    -- 1
    local caps = T.q.get_inventory(CHEST)[1]
    check("quality capsules go into slot 1", T.q_inserted == 5, T.q_inserted .. " inserted")
    check("quality capsules are fired", count(T.q_rx, "iron-plate") == 100, count(T.q_rx, "iron-plate") .. " arrived")
    -- 2
    local reused = T.new_index == T.doomed_index
    local witness_ok = T.witness and T.witness.valid and T.witness.health == T.witness.max_health
    check("a capsule for a deleted platform doesn't land on a new platform that took its place",
      T.newcomer and witness_ok, "index reused: " .. tostring(reused) .. ", witness " ..
      (T.witness and T.witness.valid and (T.witness.health .. "/" .. T.witness.max_health) or "gone"))
    -- 3
    local e, r = helpers_near(n, {-39, -36})
    check("a cloned cannon has one set of hidden helpers", e == 1 and r == 1, e .. " energy, " .. r .. " readout")
    local cc = T.clone and DC("cannon", T.clone)
    check("a cloned cannon keeps its settings and fires", cc and cc.cargo and cc.cargo.name == "stone" and count(T.cl_rx, "stone") == 50,
      cc and (serpent.line(cc.cargo) .. ", " .. count(T.cl_rx, "stone") .. " stone arrived, status " .. cc.status ..
      ", slots " .. serpent.line(T.clone.get_inventory(CHEST).get_contents())) or "not a cannon")
    local cr = T.clone_rx and DC("receiver", T.clone_rx)
    check("a cloned receiver keeps its name and channel (a ship moved by a mod still gets its cargo)", cr and cr.name == "Cloned dock" and cr.channel == 4242,
      cr and (cr.name .. " #" .. cr.channel) or "not a receiver")
    -- 4
    local c1, c2 = DC("receiver", T.ch1).channel, DC("receiver", T.ch2).channel
    check("a new receiver doesn't take a channel already in use", c1 ~= c2, c1 .. " / " .. c2)
    -- 5
    local b1 = T.bp1 and DC("receiver", T.bp1)
    check("a receiver from a blueprint keeps its name; its channel is new, since the original still uses it",
      b1 and b1.name == "Iron dock" and b1.channel ~= 77, b1 and (b1.name .. " #" .. b1.channel) or "not built")
    local b2 = T.bp2 and DC("receiver", T.bp2)
    check("a receiver from a blueprint keeps a free channel", b2 and b2.name == "Copper dock" and b2.channel == 4343,
      b2 and (b2.name .. " #" .. b2.channel) or "not built")
    local aim = DC("cannon", T.bp_aim)
    check("a blueprint never takes over a live receiver's cannons", aim.target == T.bp_orig.unit_number,
      tostring(aim.target) .. " vs " .. T.bp_orig.unit_number)
    local b3 = T.bp3 and DC("receiver", T.bp3)
    check("old ghost tags naming a live receiver don't take it over either", aim.target == T.bp_orig.unit_number and b3 and b3.channel ~= 77,
      b3 and (b3.name .. " #" .. b3.channel) or "not built")
    local cp = DC("receiver", T.cp_dst)
    check("copy / paste between receivers copies the name", cp.name == "Gear dock", cp.name)
    -- 6
    check("a cannon and a receiver placed without an event are adopted when opened",
      T.quiet_opened and T.quiet_rx_opened and DC("cannon", T.quiet) ~= nil and DC("receiver", T.quiet_rx) ~= nil)
    -- 7
    local g = DC("cannon", T.g)
    check("panel: the target drop-down picks the receiver", g.target == T.g_rx.unit_number, tostring(T.g_items) .. " items, target " .. tostring(g.target))
    check("panel: picking the cargo and unticking 'full stack' works (30 cable sent)",
      g.cargo and g.cargo.name == "copper-cable" and g.full_stack == false and count(T.g_rx, "copper-cable") == 30,
      serpent.line(g.cargo) .. " full_stack " .. tostring(g.full_stack) .. ", " .. count(T.g_rx, "copper-cable") .. " arrived")
    check("panel: 'pick the target by signal' with no signal asks for the signal",
      T.g_by_signal_caption == "dc-gui.status-no-signal", tostring(T.g_by_signal_caption))
    local gr = DC("receiver", T.g_rx2)
    check("panel: the receiver's name and channel can be typed in", gr.name == "Cable dock" and gr.channel == 515, gr.name .. " #" .. gr.channel)
    return true
  end
end

return S
