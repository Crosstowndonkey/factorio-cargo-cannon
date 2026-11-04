-- Suite "situations": platforms on the move, items with data, power, destruction, copy/paste, blueprints, the GUI.
local C = require("common")
local DC, check, count, CHEST = C.DC, C.check, C.count, C.CHEST
local S = {}

local function connection(from, to)
  for name, sc in pairs(prototypes.space_connection) do
    if sc.from.name == from and sc.to.name == to then return name end
  end
end
local function helpers(surface)
  return surface.count_entities_filtered{name = "cargo-cannon-energy"},
         surface.count_entities_filtered{name = "cargo-cannon-readout"},
         surface.count_entities_filtered{name = "cargo-cannon"}
end
local function find(rx, item)
  local inv = rx.get_inventory(CHEST)
  for i = 1, #inv do if inv[i].valid_for_read and inv[i].name == item then return inv[i] end end
end

function S.setup(T)
  local W = C.world()
  local n, p, v = W.n, W.p, W.v
  T.sink = C.build(p, "cargo-cannon-receiver", {-30, -30})

  -- 1. an orbit shot at a platform that leaves (starts travelling) while the capsule flies: lost, no error
  T.leave_pl = C.platform("Leaving platform", "nauvis", 20)
  T.leave_rx = C.build(T.leave_pl.surface, "cargo-cannon-receiver", {0, 0})
  T.leave = C.cannon(n, {-55, -50}, T.leave_rx, "iron-plate", 100)
  -- 2. ... and at one that jumps to another planet's orbit
  T.jump_pl = C.platform("Jumping platform", "nauvis", 20)
  T.jump_rx = C.build(T.jump_pl.surface, "cargo-cannon-receiver", {0, 0})
  T.jump = C.cannon(n, {-47, -50}, T.jump_rx, "copper-plate", 100)
  -- 3. a travelling platform: its cannon can't fire, and nothing can be fired at it
  T.trav_pl = C.platform("Travelling platform", "nauvis", 20)
  T.trav_rx = C.build(T.trav_pl.surface, "cargo-cannon-receiver", {0, 0})
  T.trav_cannon = C.cannon(T.trav_pl.surface, {6, 0}, T.sink, "iron-plate", 100)
  T.to_trav = C.cannon(n, {-39, -50}, T.trav_rx, "iron-plate", 100)
  T.trav_pl.space_connection = connection("nauvis", "vulcanus")
  -- 4. platform -> platform above the same planet (orbit)
  T.pp = C.cannon(p, {0, 0}, T.leave_rx, "steel-plate", 100)
  T.pp_pl = C.platform("Second platform", "nauvis", 20)
  T.pp_rx = C.build(T.pp_pl.surface, "cargo-cannon-receiver", {0, 0})
  T.pp2 = C.cannon(p, {6, 0}, T.pp_rx, "stone-brick", 100)
  -- 5. orbit at another planet: Vulcanus -> a platform above Vulcanus; Nauvis -> that platform = not in orbit
  T.vpl = C.platform("Vulcanus platform", "vulcanus", 20)
  T.vpl_rx = C.build(T.vpl.surface, "cargo-cannon-receiver", {0, 0})
  T.v_up = C.cannon(v, {-20, 0}, T.vpl_rx, "tungsten-ore", 50)
  T.notorbit = C.cannon(n, {-31, -50}, T.vpl_rx, "iron-plate", 100)
  -- 6. aimed at a receiver on its own surface
  T.same_rx = C.build(n, "cargo-cannon-receiver", {40, 40})
  T.same = C.cannon(n, {-23, -50}, T.same_rx, "iron-plate", 100)

  -- 7. quality: uncommon iron arrives uncommon; normal iron can't go into its slot; a wrong-quality stack waits
  T.q_rx = C.build(p, "cargo-cannon-receiver", {-20, -30})
  T.q = C.build(n, "cargo-cannon", {-55, -40})
  C.load(T.q, 10, "iron-plate", 100, "uncommon")
  DC("set_target", T.q, T.q_rx)
  T.q_filter = C.build(n, "cargo-cannon", {-47, -40})
  C.load(T.q_filter, 10, "iron-plate", 0, "uncommon")
  T.q_inserted = T.q_filter.get_inventory(CHEST).insert{name = "iron-plate", count = 100, quality = "normal"}
  DC("set_target", T.q_filter, T.q_rx)
  T.q_wrong = C.build(n, "cargo-cannon", {-39, -40})
  C.load(T.q_wrong, 10, "iron-plate", 0, "uncommon")
  T.q_wrong.get_inventory(CHEST)[2].set_stack{name = "iron-plate", count = 100, quality = "normal"}
  DC("set_target", T.q_wrong, T.q_rx)
  -- 8. half-spoiled fruit keeps its spoilage; armour keeps its equipment
  T.spoil_rx = C.build(p, "cargo-cannon-receiver", {-10, -30})
  T.spoil = C.cannon(n, {-31, -40}, T.spoil_rx, "yumako", 50)
  T.spoil.get_inventory(CHEST)[2].spoil_percent = 0.5
  T.armour = C.cannon(n, {-23, -40}, T.spoil_rx, "modular-armor", 1)
  local grid = T.armour.get_inventory(CHEST)[2].grid
  grid.put{name = "solar-panel-equipment"}
  grid.put{name = "battery-equipment"}
  -- 9. "full stacks only" off: 30 plates fire at once
  T.part = C.cannon(n, {-15, -40}, T.sink, "iron-plate", 30, {full_stack = false})
  -- 10. no power: charges forever
  C.floor_and_power(n, "concrete", 6, nil, 200, 0)
  T.nopower = C.cannon(n, {200, 0}, T.sink, "iron-plate", 100)
  -- 11. the cargo picked is changed while a stack waits: nothing is lost, it waits as wrong cargo
  T.change = C.cannon(n, {-7, -40}, T.sink, "iron-plate", 50)  -- half a stack: waiting
  DC("configure", T.change, {cargo = {name = "copper-plate", quality = "normal"}})
  T.unpick = C.cannon(n, {1, -40}, T.sink, "iron-plate", 50)
  DC("configure", T.unpick, {cargo = false})

  -- 12. the cannon is destroyed while its capsule flies: it still lands
  T.dead_rx = C.build(p, "cargo-cannon-receiver", {0, -30})
  T.dead = C.cannon(n, {-55, -30}, T.dead_rx, "plastic-bar", 100)
  -- 13. mined with capsules and cargo inside: everything comes back, helpers are removed
  T.mined = C.cannon(n, {-47, -30}, T.sink, "iron-plate", 50)
  -- 14. a planet's surface is deleted while a capsule flies to it: lost, no error
  T.fulgora = C.planet("fulgora")
  T.fg_rx = C.build(T.fulgora, "cargo-cannon-receiver", {0, 0})
  T.to_fg = C.cannon(n, {-39, -30}, T.fg_rx, "sulfur", 50)
  -- 15. the receiver is killed (dies) mid-flight: the capsule crashes where it stood
  T.killed_rx = C.build(p, "cargo-cannon-receiver", {10, -30})
  T.to_killed = C.cannon(n, {-31, -30}, T.killed_rx, "coal", 50)
  -- 16. no wiring, one free slot, two cannons: one lands, one crashes (the consequence the mod is built around)
  T.unsafe_rx = C.build(p, "cargo-cannon-receiver", {20, -30})
  local inv = T.unsafe_rx.get_inventory(CHEST)
  for i = 1, 39 do inv[i].set_stack{name = "stone", count = 50} end
  T.unsafe_a = C.cannon(n, {-23, -30}, T.unsafe_rx, "wood", 100)
  T.unsafe_b = C.cannon(n, {-15, -30}, T.unsafe_rx, "wood", 100)
  -- 17. twenty cannons at one receiver at once: all twenty stacks arrive
  T.many_rx = C.build(p, "cargo-cannon-receiver", {30, -30})
  T.many = {}
  for i = 1, 20 do table.insert(T.many, C.cannon(n, {-55 + 5 * ((i - 1) % 10), -20 + 5 * math.floor((i - 1) / 10)}, T.many_rx, "iron-gear-wheel", 100)) end

  -- 18. copy / paste settings
  T.cp_rx = C.build(p, "cargo-cannon-receiver", {-30, 0})
  T.cp_src = C.build(n, "cargo-cannon", {0, 0})
  DC("set_target", T.cp_src, T.cp_rx)
  DC("configure", T.cp_src, {cargo = {name = "copper-cable", quality = "normal"}, full_stack = false, circuit_enable = true,
     condition = {signal = C.sig("signal-B"), comparator = "≤", constant = 12}})
  T.cp_dst = C.build(n, "cargo-cannon", {6, 0})
  -- 19. a blueprint ghost carrying settings in its tags, revived
  T.ghost = n.create_entity{name = "entity-ghost", inner_name = "cargo-cannon", position = {12, 0}, force = "player",
    tags = {dc_settings = {cargo = {name = "pipe", quality = "normal"}, full_stack = false, circuit_enable = true,
            condition = {signal = C.sig("signal-D"), comparator = "<", constant = 3}}}}
  -- 20. GUI
  T.gui_cannon = C.cannon(n, {20, 0}, T.cp_rx, "iron-plate", 50)
  T.gui_rx = C.build(n, "cargo-cannon-receiver", {16, 9})
end

local function has(el, name)
  if not el then return false end
  if el.name == name then return true end
  for _, child in pairs(el.children) do if has(child, name) then return true end end
  return false
end
local function opened_ok(player, entity)
  local ok, err = pcall(function() player.opened = entity end)
  return ok, err
end

function S.tick(T, tick)
  local player = game.get_player(1)
  local n = game.surfaces.nauvis
  if not T.left and count(T.leave, "iron-plate") == 0 then
    T.left = true
    T.leave_pl.space_connection = (function()
      for name, sc in pairs(prototypes.space_connection) do if sc.from.name == "nauvis" then return name end end
    end)()
  end
  if not T.jumped and count(T.jump, "copper-plate") == 0 then
    T.jumped = true
    T.jump_pl.space_location = "vulcanus"
  end
  if not T.fg_gone and count(T.to_fg, "sulfur") == 0 then
    T.fg_gone = true
    game.delete_surface(T.fulgora)
  end
  if not T.killed and count(T.to_killed, "coal") == 0 then
    T.killed = true
    T.killed_pos = T.killed_rx.position
    T.killed_rx.die()
  end
  if not T.dead_done and count(T.dead, "plastic-bar") == 0 then
    T.dead_done = true
    T.dead.die()
  end

  if tick == 35 then
    check("travelling platform: its cannon can't fire", C.status(T.trav_cannon) == "cannon-travelling", C.status(T.trav_cannon))
    check("travelling platform: can't be fired at", C.status(T.to_trav) == "target-travelling", C.status(T.to_trav))
    check("planet -> platform above another planet: not in orbit", C.status(T.notorbit) == "not-in-orbit", C.status(T.notorbit))
    check("aimed at its own surface", C.status(T.same) == "same-surface", C.status(T.same))
    check("quality: normal iron refused by the uncommon cargo slot", T.q_inserted == 0, T.q_inserted)
    -- mine one with things inside
    local box = game.create_inventory(20)
    local before_e, before_r, before_c = helpers(n)
    T.mined.mine{inventory = box, raise_destroyed = true}
    local e, r, c = helpers(n)
    check("mined: cannon, capsules and cargo come back",
          box.get_item_count("cargo-cannon") == 1 and box.get_item_count("cargo-cannon-capsule") == 10 and box.get_item_count("iron-plate") == 50,
          serpent.line(box.get_contents()))
    check("mined: its hidden helpers are removed", e == before_e - 1 and r == before_r - 1 and c == before_c - 1,
          e .. "/" .. r .. "/" .. c .. " (was " .. before_e .. "/" .. before_r .. "/" .. before_c .. ")")
    box.destroy()
    -- copy / paste
    if not player.character then
      local body = n.create_entity{name = "character", position = {10, 4}, force = "player"}
      player.set_controller{type = defines.controllers.character, character = body}
    end
    T.cp_dst.copy_settings(T.cp_src, player)
    local d = DC("cannon", T.cp_dst)
    check("copy/paste: settings copied", d.target == T.cp_rx.unit_number and d.cargo and d.cargo.name == "copper-cable" and
          d.full_stack == false and d.circuit_enable and d.condition.comparator == "≤" and d.condition.constant == 12 and
          d.condition.signal.name == "signal-B", serpent.line(d.condition))
    local f2 = T.cp_dst.get_inventory(CHEST).get_filter(2)
    check("copy/paste: the cargo slot filter follows", f2 and f2.name == "copper-cable", serpent.line(f2))
    -- ghost revive
    local _, cannon = T.ghost.revive{raise_revive = true}
    local g = cannon and DC("cannon", cannon)
    check("blueprint tags: a revived ghost gets the settings", g and g.cargo and g.cargo.name == "pipe" and g.full_stack == false and
          g.condition.signal.name == "signal-D" and g.condition.constant == 3, g and serpent.line(g.cargo))
    -- a blueprint of the area holds only the cannon (the hidden helpers aren't blueprintable)
    local bpinv = game.create_inventory(1)
    bpinv[1].set_stack("blueprint")
    bpinv[1].create_blueprint{surface = n, force = "player", area = {{18, -2}, {22, 2}}}
    local names = {}
    for _, be in pairs(bpinv[1].get_blueprint_entities() or {}) do names[be.name] = (names[be.name] or 0) + 1 end
    check("blueprint: only the cannon is in it", names["cargo-cannon"] == 1 and not names["cargo-cannon-energy"] and
          not names["cargo-cannon-readout"], serpent.line(names))
    bpinv.destroy()
    -- GUI
    local ok, err = opened_ok(player, T.gui_cannon)
    local frame = player.gui.relative.dc_panel
    check("GUI: opening a cannon shows the panel", ok and has(frame, "dc_target") and has(frame, "dc_cargo") and has(frame, "dc_cond_signal") and has(frame, "dc_target_signal"), err)
  end
  if tick == 65 then
    local frame = player.gui.relative.dc_panel
    check("GUI: the panel's status updates", frame and frame.dc_status.caption and frame.dc_status.caption[1] ~= nil,
          frame and serpent.line(frame.dc_status.caption))
    local ok, err = opened_ok(player, T.gui_rx)
    frame = player.gui.relative.dc_panel
    check("GUI: opening a receiver shows its panel", ok and has(frame, "dc_name") and has(frame, "dc_channel"), err)
    opened_ok(player, T.gui_cannon)
  end
  if tick == 90 then
    T.gui_cannon.die()  -- the cannon dies with its panel open
  end
  if tick == 120 then
    check("GUI: the cannon dying with its panel open causes no error", true)
    opened_ok(player, nil)
  end
  if tick == 1500 then
    check("platform left mid-flight: cargo lost, nothing in the receiver", count(T.leave_rx, "iron-plate") == 0)
    check("platform jumped to Vulcanus mid-flight: cargo lost", count(T.jump_rx, "copper-plate") == 0)
    check("platform -> platform above Nauvis: arrived", count(T.pp_rx, "stone-brick") == 100, count(T.pp_rx, "stone-brick"))
    check("Vulcanus -> platform above Vulcanus: arrived", count(T.vpl_rx, "tungsten-ore") == 50, count(T.vpl_rx, "tungsten-ore"))
    check("quality: uncommon iron arrived uncommon", count(T.q_rx, "iron-plate", "uncommon") == 100 and count(T.q_rx, "iron-plate", "normal") == 0,
          count(T.q_rx, "iron-plate", "uncommon") .. " uncommon")
    check("quality: a normal stack in an uncommon slot waits as wrong cargo",
          C.status(T.q_wrong) == "wrong-cargo" or not T.q_wrong.get_inventory(CHEST)[2].valid_for_read, C.status(T.q_wrong))
    local fruit = find(T.spoil_rx, "yumako")
    check("spoilage: half-spoiled fruit arrived still half spoiled (not fresh)", fruit and fruit.count == 50 and fruit.spoil_percent >= 0.5,
          fruit and (fruit.count .. " at " .. fruit.spoil_percent))
    local armour = find(T.spoil_rx, "modular-armor")
    check("armour: arrived with its equipment", armour and armour.grid and #armour.grid.equipment == 2,
          armour and armour.grid and #armour.grid.equipment)
    check("not full stacks only: 30 plates fired", count(T.part, "iron-plate") == 0, C.status(T.part))
    check("no power: still charging, nothing fired", count(T.nopower, "iron-plate") == 100 and C.status(T.nopower) == "charging",
          C.status(T.nopower))
    check("cargo picked changed: the old stack waits, nothing lost", count(T.change, "iron-plate") == 50 and C.status(T.change) == "wrong-cargo",
          C.status(T.change))
    check("cargo un-picked: the stack stays, cannon waits", count(T.unpick, "iron-plate") == 50 and C.status(T.unpick) == "no-cargo-picked",
          C.status(T.unpick))
    check("cannon destroyed mid-flight: its capsule still landed", T.dead_done and count(T.dead_rx, "plastic-bar") == 100,
          count(T.dead_rx, "plastic-bar"))
    local e, r, c = helpers(n)
    check("helpers: one energy + one readout per cannon on Nauvis", e == c and r == c, e .. "/" .. r .. "/" .. c)
    check("planet deleted mid-flight: nothing left in the air", T.fg_gone and DC("flights") == 0 and C.status(T.to_fg) == "no-target",
          DC("flights") .. ", " .. C.status(T.to_fg))
    check("receiver killed mid-flight: crashed (cargo gone, no error)", T.killed and not T.killed_rx.valid)
    local wood = count(T.unsafe_rx, "wood")
    check("unwired, one free slot, two cannons: one landed, one crashed and hurt the receiver",
          wood == 100 and T.unsafe_rx.health < T.unsafe_rx.max_health, wood .. ", health " .. T.unsafe_rx.health)
    check("twenty at once: all twenty stacks arrived", count(T.many_rx, "iron-gear-wheel") == 2000, count(T.many_rx, "iron-gear-wheel"))
    return true
  end
end


return S
