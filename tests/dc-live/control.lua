-- Live test bench for Cargo Cannon (not part of the mod). tools/run_live.sh opens a real game window on a throwaway
-- save. A panel lists the tests: picking one builds it, says what to do and what to look for, and shows live numbers.
-- Pass / Problem and notes are written to script-output/cargo-cannon-live-notes.txt.
local C = require("common")
local DC, CHEST, RED = C.DC, C.CHEST, C.RED
local NOTES = "cargo-cannon-live-notes.txt"

-- Nauvis: a 4 x 4 grid of plots, each clear of the substations for 6 tiles around its centre
local function plot(i)
  local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
  return {x = -48 + col * 32, y = -48 + row * 32}
end
-- platform and Vulcanus: the same, on their smaller floors (the hub is in the middle)
local SPOTS = {{-28, -28}, {-12, -28}, {4, -28}, {20, -28}, {-28, -12}, {20, -12}, {-28, 4}, {20, 4}, {-28, 20}, {-12, 20}, {4, 20}, {20, 20},
  {-12, -44}, {4, -44}, {-28, -44}}
local function at(p, dx, dy) return {p.x + dx, p.y + dy} end
local function spot(i) return {SPOTS[i][1], SPOTS[i][2]} end

local function cannon(s, pos, rx, item, n, settings) return C.cannon(s, pos, rx, item, n, settings) end
local function lamp(s, pos, wire_to, signal, comparator, constant)
  local l = s.create_entity{name = "small-lamp", position = pos, force = "player"}
  l.get_wire_connector(RED, true).connect_to(wire_to.get_wire_connector(RED, true))
  local cb = l.get_or_create_control_behavior()
  cb.circuit_condition = {first_signal = C.sig(signal), comparator = comparator, constant = constant}
  return l
end
local function toggle(cc) local cb = cc.get_or_create_control_behavior(); cb.enabled = not cb.enabled end

local TESTS = {
  {title = "Orbit shot, up", view = "nauvis",
    text = "A loaded cannon fires 100 iron plates at a receiver on the platform.\n\nWatch: it charges, then fires (flash, sound, a shell going up). About 5 seconds later the plates arrive.\nThen press View platform: did the capsule land on the receiver and do the plates show up inside?\nClick the cannon and read its window: is the status clear at every stage?",
    build = function(T, P, W, i)
      T.rx = C.build(W.p, "cargo-cannon-receiver", spot(i))
      T.c = cannon(W.n, at(P, -3, 0), T.rx, "iron-plate", 100)
    end},
  {title = "Orbit shot, down", view = "platform",
    text = "A cannon on the platform fires 100 gears down to Nauvis.\n\nWatch the cannon on the platform, then press View Nauvis: does the falling capsule look right and land on the receiver?",
    build = function(T, P, W, i)
      T.rx = C.build(W.n, "cargo-cannon-receiver", at(P, 0, 0))
      T.c = cannon(W.p, spot(i), T.rx, "iron-gear-wheel", 100)
    end},
  {title = "Interplanetary shot", view = "nauvis",
    text = "Nauvis to Vulcanus, using 3 capsules and 1 GJ. The flight is cut to 15 seconds here (90 in a real game).\n\nWatch how long the charge takes and whether the window explains it. Press View Vulcanus before it lands.\nCheck that exactly 3 capsules left the cannon.",
    build = function(T, P, W, i)
      T.rx = C.build(W.v, "cargo-cannon-receiver", spot(i))
      T.c = cannon(W.n, at(P, -3, 0), T.rx, "steel-plate", 100)
    end},
  {title = "Crash: full receiver", view = "platform",
    text = "The receiver on the platform is completely full of stone, so this shot should explode.\n\nPress View platform and watch it land: a grenade-style blast, cargo lost, receiver damaged.\nIs the warning message clear, and does its map link work?",
    build = function(T, P, W, i)
      T.rx = C.build(W.p, "cargo-cannon-receiver", spot(i))
      for slot = 1, 40 do T.rx.get_inventory(CHEST)[slot].set_stack{name = "stone", count = 50} end
      T.c = cannon(W.n, at(P, -3, 0), T.rx, "coal", 50)
    end},
  {title = "Crash: receiver removed", view = "platform", step = "Remove the receiver",
    text = "1. Press View platform, then wait until the cannon fires (the live line shows a capsule in the air).\n2. Press \"Remove the receiver\" straight away.\n\nThe capsule should crash where the receiver was. No script error, and a clear message.",
    build = function(T, P, W, i)
      T.rx = C.build(W.p, "cargo-cannon-receiver", spot(i))
      T.c = cannon(W.n, at(P, -3, 0), T.rx, "sulfur", 50)
    end,
    act = function(T) if T.rx.valid then T.rx.destroy{raise_destroy = true} end end},
  {title = "Cannon window by hand", view = "nauvis",
    text = "This cannon is empty and unset. Use it as a new player would, with no help:\n1. Click it. Pick a cargo and a target from the window.\n2. Drop capsules and iron plates in from your inventory.\n3. Check it fires.\n\nWatch for: anything confusing, text cut off, wrong tooltips, the window jumping about, slots refusing the wrong items.",
    build = function(T, P, W, i)
      T.rx = C.build(W.p, "cargo-cannon-receiver", spot(i))
      T.c = C.build(W.n, "cargo-cannon", at(P, -3, 0))
    end},
  {title = "Receiver window by hand", view = "nauvis",
    text = "Click the receiver here. Rename it and change its channel.\nThen click the cannon: does the new name appear in its target list straight away?\nAim the cannon at it and fire. A shot to the same planet shouldn't be allowed: is the reason clear?",
    build = function(T, P, W, i)
      T.rx = C.build(W.n, "cargo-cannon-receiver", at(P, 3, 0))
      T.c = cannon(W.n, at(P, -4, 0), nil, "iron-plate", 100)
    end},
  {title = "Enable if switch", view = "nauvis", step = "Flip the switch",
    text = "The cannon only fires while signal A > 0. The switch starts off.\n1. Click the cannon: the game's own Circuit connection panel should show the condition.\n2. Press \"Flip the switch\": it should start firing, and stop when you flip it back.\n\nWatch the cannon's status and the wires. Do both make sense?",
    build = function(T, P, W, i)
      T.rx = C.build(W.p, "cargo-cannon-receiver", spot(i))
      T.c = cannon(W.n, at(P, -3, 0), T.rx, "stone-brick", 100)
      T.cc = C.combinator(W.n, at(P, -3, 4), {["signal-A"] = 1}, T.c)
      T.cc.get_or_create_control_behavior().enabled = false
      C.native(T.c, {first_signal = C.sig("signal-A"), comparator = ">", constant = 0})
      T.c.get_inventory(CHEST)[2].set_stack{name = "stone-brick", count = 100}
    end,
    act = function(T) toggle(T.cc) end},
  {title = "Safe wiring", view = "nauvis",
    text = "Fires only while Receiver space > 0, at a receiver with one free slot, and an inserter keeps the cannon loaded.\n\nExpected: one shot lands, then it holds fire with no crash. The lamp shows space > 0.\nHover the wire or cannon to read Receiver space and Cannon charge. Do the numbers match what you see?",
    build = function(T, P, W, i)
      T.rx = C.build(W.p, "cargo-cannon-receiver", spot(i))
      for slot = 1, 39 do T.rx.get_inventory(CHEST)[slot].set_stack{name = "stone", count = 50} end
      T.c = cannon(W.n, at(P, -3, 0), T.rx, "iron-plate", 100)
      C.native(T.c, {first_signal = C.sig(C.SPACE), comparator = ">", constant = 0})
      lamp(W.n, at(P, -3, 4), T.c, C.SPACE, ">", 0)
      local box = W.n.create_entity{name = "infinity-chest", position = at(P, 2.5, 0.5), force = "player"}
      box.infinity_container_filters = {{index = 1, name = "iron-plate", count = 200, mode = "exactly"}}
      W.n.create_entity{name = "fast-inserter", position = at(P, 0.5, 0.5), direction = defines.direction.east, force = "player"}
    end},
  {title = "Target by signal", view = "nauvis", step = "Switch target",
    text = "Signal C picks the target by channel number. Two receivers are on the platform.\nPress \"Switch target\" between shots.\n\nDoes the cannon's window show the current target? Do the plates go to the right receiver (see the live line)?",
    build = function(T, P, W, i)
      T.rx = C.build(W.p, "cargo-cannon-receiver", spot(i))
      T.rx2 = C.build(W.p, "cargo-cannon-receiver", {SPOTS[i][1] + 7, SPOTS[i][2]})
      T.c = cannon(W.n, at(P, -3, 0), nil, "copper-plate", 100, {circuit_target = true, target_signal = C.sig("signal-C")})
      T.ch = {DC("receiver", T.rx).channel, DC("receiver", T.rx2).channel}
      T.on = 1
      T.cc = C.combinator(W.n, at(P, -3, 4), {["signal-C"] = T.ch[1]}, T.c)
      local box = W.n.create_entity{name = "infinity-chest", position = at(P, 2.5, 0.5), force = "player"}
      box.infinity_container_filters = {{index = 1, name = "copper-plate", count = 200, mode = "exactly"}}
      W.n.create_entity{name = "fast-inserter", position = at(P, 0.5, 0.5), direction = defines.direction.east, force = "player"}
    end,
    act = function(T) T.on = 3 - T.on; C.set_value(T.cc, 1, "signal-C", T.ch[T.on]) end},
  {title = "Robots and inserters", view = "nauvis",
    text = "Robots should bring capsules and cargo to the cannon (it's a requester), and take gears out of the receiver (a passive provider) to the chest on the right.\nThe gears are fired down from the platform by a second cannon.\n\nWatch that robots don't overfill it or put cargo in the capsule slot.",
    build = function(T, P, W, i)
      local rp = W.n.create_entity{name = "roboport", position = at(P, 0, -4), force = "player"}
      rp.insert{name = "logistic-robot", count = 30}
      local store = W.n.create_entity{name = "storage-chest", position = at(P, -5.5, -4.5), force = "player"}
      store.insert{name = "cargo-cannon-capsule", count = 50}
      store.insert{name = "iron-plate", count = 500}
      T.rx_up = C.build(W.p, "cargo-cannon-receiver", spot(i))
      T.c = C.build(W.n, "cargo-cannon", at(P, -4, 3))
      DC("set_target", T.c, T.rx_up)
      DC("configure", T.c, {cargo = {name = "iron-plate", quality = "normal"}})
      local sec = T.c.get_logistic_sections().add_section()
      sec.set_slot(1, {value = {name = "cargo-cannon-capsule", quality = "normal"}, min = 5})
      sec.set_slot(2, {value = {name = "iron-plate", quality = "normal"}, min = 100})
      T.rx = C.build(W.n, "cargo-cannon-receiver", at(P, 3, 3))
      T.c2 = cannon(W.p, {SPOTS[i][1], SPOTS[i][2] + 7}, T.rx, "iron-gear-wheel", 100)
      local want = W.n.create_entity{name = "requester-chest", position = at(P, 5.5, -4.5), force = "player"}
      want.get_logistic_sections().add_section().set_slot(1, {value = {name = "iron-gear-wheel", quality = "normal"}, min = 40})
    end},
  {title = "Low power", view = "nauvis", step = "Connect the power",
    text = "This cannon sits on its own small network with no generator, far from the substations' reach.\n\nCheck its window says why it isn't firing, and that the power warning icon looks right.\nThen press \"Connect the power\" and watch the charge climb.",
    build = function(T, P, W, i)
      T.island = game.surfaces.nauvis
      T.pos = {-90, -90 + i * 10}
      local tiles = {}
      for x = -8, 8 do for y = -8, 8 do table.insert(tiles, {name = "concrete", position = {T.pos[1] + x, T.pos[2] + y}}) end end
      W.n.set_tiles(tiles)
      for _, e in pairs(W.n.find_entities_filtered{area = {{T.pos[1] - 8, T.pos[2] - 8}, {T.pos[1] + 8, T.pos[2] + 8}}}) do
        if e.type ~= "character" then e.destroy() end
      end
      T.rx = C.build(W.p, "cargo-cannon-receiver", spot(i))
      T.c = cannon(W.n, T.pos, T.rx, "iron-plate", 100)
      T.goto_pos = T.pos
      T.extra = {T.c}
    end,
    act = function(T, P, W)
      if T.eei then return end
      T.eei = W.n.create_entity{name = "electric-energy-interface", position = {T.pos[1] + 5, T.pos[2]}, force = "player"}
      T.eei.power_production = 1e10 / 60
      T.eei.electric_buffer_size = 1e11
      W.n.create_entity{name = "substation", position = {T.pos[1] + 3, T.pos[2] + 3}, force = "player"}
    end},
  {title = "Quality", view = "nauvis",
    text = "A legendary cannon and a normal one fire legendary plates at the same receiver.\n\nDoes the legendary cannon use more power, as its tooltip says? Does the cargo arrive still legendary?\nDo the buildings show their quality icon?",
    build = function(T, P, W, i)
      T.rx = C.build(W.p, "cargo-cannon-receiver", spot(i))
      T.c = W.n.create_entity{name = "cargo-cannon", position = at(P, -4, 0), force = "player", quality = "legendary", raise_built = true}
      C.load(T.c, 10, "iron-plate", 100, "legendary")
      DC("set_target", T.c, T.rx)
      T.c2 = C.build(W.n, "cargo-cannon", at(P, 3, 0))
      C.load(T.c2, 10, "iron-plate", 100, "legendary")
      DC("set_target", T.c2, T.rx)
    end},
  {title = "Copy, paste, blueprint", view = "nauvis",
    text = "1. Shift + right-click the set-up cannon, then Shift + left-click the blank one: do its cargo and target come across?\n2. Select the set-up cannon into a blueprint and place it (it's in your inventory if you need one). Does the new cannon keep its settings?\n3. Pick up a cannon with Q from the blank one, rotate, and mine one: anything odd?",
    build = function(T, P, W, i)
      T.rx = C.build(W.p, "cargo-cannon-receiver", spot(i))
      T.c = C.build(W.n, "cargo-cannon", at(P, -4, 0))
      DC("configure", T.c, {cargo = {name = "copper-cable", quality = "normal"}})
      DC("set_target", T.c, T.rx)
      T.c2 = C.build(W.n, "cargo-cannon", at(P, 3, 0))
    end},
  {title = "Platform leaves mid-flight", view = "nauvis", step = "Send the platform away",
    text = "1. Wait until the live line shows a capsule in the air.\n2. Press \"Send the platform away\" straight away.\n\nThe capsule should miss, with a clear message and no error. The cannon should then say its target isn't in orbit.",
    build = function(T, P, W, i)
      local pl = C.platform("Leaving platform " .. game.tick, "nauvis", 12)
      T.pl = pl
      T.rx = C.build(pl.surface, "cargo-cannon-receiver", {8, 8})
      T.c = cannon(W.n, at(P, -3, 0), T.rx, "iron-plate", 100)
    end,
    act = function(T)
      if not T.pl.valid or T.pl.space_connection then return end
      for _, conn in pairs(prototypes.space_connection) do
        if conn.from.name == "nauvis" or conn.to.name == "nauvis" then T.pl.space_connection = conn return end
      end
    end},
}

local function world() return storage.W end

local function clear(i)
  local W, P = world(), plot(i)
  local T = storage.tests[i]
  if T then for _, e in pairs(T.extra or {}) do if e.valid then e.destroy{raise_destroy = true} end end end
  local function wipe(s, cx, cy, r)
    for _, e in pairs(s.find_entities_filtered{area = {{cx - r, cy - r}, {cx + r, cy + r}}}) do
      if e.valid and e.type ~= "character" and e.type ~= "substation" and e.type ~= "electric-energy-interface" and e.type ~= "space-platform-hub" then
        e.destroy{raise_destroy = true}
      end
    end
  end
  wipe(W.n, P.x, P.y, 7)
  local sx, sy = SPOTS[i][1], SPOTS[i][2]
  wipe(W.p, sx + 3, sy + 3, 7)
  wipe(W.v, sx, sy, 4)
end

local function build(i)
  clear(i)
  local T = {}
  storage.tests[i] = T
  TESTS[i].build(T, plot(i), world(), i)
  return T
end

local function live_line(i)
  local T = storage.tests[i]
  if not T then return "" end
  local parts = {"Capsules in the air: " .. DC("flights")}
  if T.c and T.c.valid then
    local c = DC("cannon", T.c)
    parts[#parts + 1] = "Cannon: " .. tostring(c and c.status)
    local inv = T.c.get_inventory(CHEST)
    parts[#parts + 1] = "slots: " .. (inv[1].valid_for_read and inv[1].count or 0) .. " capsules, " .. (inv[2].valid_for_read and inv[2].count or 0) .. " cargo"
  end
  for _, key in pairs({"rx", "rx2"}) do
    local r = T[key]
    if r then parts[#parts + 1] = key == "rx" and (r.valid and ("Receiver: " .. r.get_inventory(CHEST).get_item_count() .. " items") or "Receiver: gone")
      or (r.valid and ("Second: " .. r.get_inventory(CHEST).get_item_count() .. " items") or "Second: gone") end
  end
  return table.concat(parts, "   |   ")
end

local function note(player, text)
  local i = storage.current or 0
  local title = TESTS[i] and TESTS[i].title or "general"
  helpers.write_file(NOTES, string.format("[tick %d] %d %s: %s  ||  %s\n", game.tick, i, title, text, live_line(i)), true, player.index)
end

local function show(player, i)
  storage.current = i
  local panel = player.gui.screen.dc_live
  if not panel then return end
  local t = TESTS[i]
  panel.head.caption = i .. " of " .. #TESTS .. ": " .. t.title
  panel.body.caption = t.text
  panel.buttons.dc_act.visible = t.step ~= nil
  panel.buttons.dc_act.caption = t.step or ""
end

local function view(player, where)
  local W = world()
  local i = storage.current or 1
  if where == "character" then
    if player.controller_type == defines.controllers.remote then player.exit_remote_view() end
    return
  end
  local T = storage.tests[i] or {}
  local s, pos
  if where == "nauvis" then s, pos = W.n, T.goto_pos or {plot(i).x, plot(i).y}
  elseif where == "platform" then s, pos = (T.pl and T.pl.valid and T.pl.surface) or W.p, (T.pl and {8, 8}) or spot(i)
  else s, pos = W.v, spot(i) end
  player.set_controller{type = defines.controllers.remote, surface = s, position = pos}
  player.zoom = 0.75
end

local function go(player, i)
  build(i)
  show(player, i)
  local T = storage.tests[i]
  if player.character then player.character.teleport(T.goto_pos and {T.goto_pos[1], T.goto_pos[2] + 5} or at(plot(i), 0, 6.5), world().n) end
  view(player, "character")
  if TESTS[i].view ~= "nauvis" then view(player, TESTS[i].view) end
end

local function make_panel(player)
  if player.gui.screen.dc_live then player.gui.screen.dc_live.destroy() end
  local f = player.gui.screen.add{type = "frame", name = "dc_live", direction = "vertical", caption = "Cargo Cannon test bench"}
  f.location = {10, 60}
  f.style.width = 470
  f.add{type = "drop-down", name = "dc_pick", items = (function()
    local names = {}
    for n, t in ipairs(TESTS) do names[n] = n .. ". " .. t.title end
    return names
  end)(), selected_index = 1}
  local h = f.add{type = "label", name = "head", style = "caption_label"}
  local b = f.add{type = "label", name = "body"}
  b.style.single_line = false
  b.style.maximal_width = 440
  local l = f.add{type = "label", name = "live"}
  l.style.single_line = false
  l.style.maximal_width = 440
  l.style.font_color = {1, 0.8, 0.3}
  local a = f.add{type = "flow", name = "buttons", direction = "horizontal"}
  a.add{type = "button", name = "dc_build", caption = "Build / reset"}
  a.add{type = "button", name = "dc_act", caption = ""}
  a.add{type = "button", name = "dc_next", caption = "Next test"}
  local v = f.add{type = "flow", direction = "horizontal"}
  v.add{type = "button", name = "dc_v_character", caption = "Character"}
  v.add{type = "button", name = "dc_v_nauvis", caption = "View Nauvis"}
  v.add{type = "button", name = "dc_v_platform", caption = "View platform"}
  v.add{type = "button", name = "dc_v_vulcanus", caption = "View Vulcanus"}
  local n = f.add{type = "flow", direction = "horizontal"}
  n.add{type = "textfield", name = "dc_note"}.style.width = 240
  n.add{type = "button", name = "dc_ok", caption = "Pass"}
  n.add{type = "button", name = "dc_bad", caption = "Problem"}
  f.add{type = "label", caption = "Type what you saw, then press Pass or Problem. It's saved for Claude to read."}
  show(player, storage.current or 1)
end

local function kit(player)
  local inv = player.get_main_inventory()
  if not inv then return end
  for name, count in pairs({["cargo-cannon"] = 10, ["cargo-cannon-receiver"] = 10, ["cargo-cannon-capsule"] = 100, ["iron-plate"] = 400,
      ["red-wire"] = 50, ["green-wire"] = 50, ["constant-combinator"] = 10, ["fast-inserter"] = 20, ["blueprint"] = 1, ["substation"] = 10}) do
    if prototypes.item[name] then player.insert{name = name, count = count} end
  end
end

local function welcome(player)
  if player.controller_type == defines.controllers.cutscene then player.exit_cutscene() end
  if not player.character then
    player.create_character()
  end
  player.character_running_speed_modifier = 2
  if player.character then
    player.character.destructible = false
    player.character.teleport({0, 8}, world().n)
  end
  kit(player)
  make_panel(player)
  go(player, 1)
end

script.on_init(function()
  storage.tests = {}
  if remote.interfaces["freeplay"] then
    remote.call("freeplay", "set_skip_intro", true)
    remote.call("freeplay", "set_disable_crashsite", true)
  end
end)

local function setup()
  local W = C.world()
  storage.W = W
  DC("set_cost", "orbit", nil)
  DC("set_cost", "interplanetary", {energy = 1000, capsules = 3, flight = 15})
  W.f.chart(W.n, {{-120, -120}, {120, 120}})
end

script.on_event(defines.events.on_tick, function(e)
  if not storage.W then
    if e.tick == 0 then return end
    setup()
    if script.test_arg == "selftest" then
      for i = 1, #TESTS do
        local ok, err = pcall(function()
          local T = build(i)
          for key, value in pairs(T) do
            if key == "c" or key == "rx" then assert(value and value.valid, key .. " missing") end
          end
          if TESTS[i].act and i ~= 5 then TESTS[i].act(T, plot(i), storage.W) end
        end)
        print("STA " .. (ok and "PASS " or "FAIL ") .. i .. " " .. TESTS[i].title .. (ok and "" or ("  " .. tostring(err))))
        storage.current = i
        print("STA live " .. live_line(i))
      end
      print("STA selftest done")
      script.finish_test(true)
      return
    end
    for _, p in pairs(game.connected_players) do welcome(p) end
    return
  end
  if e.tick % 15 == 0 and storage.current then
    for _, p in pairs(game.connected_players) do
      local panel = p.gui.screen.dc_live
      if panel then panel.live.caption = live_line(storage.current) end
    end
  end
end)

script.on_event(defines.events.on_player_joined_game, function(e)
  if storage.W then
    local p = game.get_player(e.player_index)
    if not p.gui.screen.dc_live then welcome(p) end
  end
end)

script.on_event(defines.events.on_gui_click, function(e)
  local p, n = game.get_player(e.player_index), e.element.name
  local i = storage.current or 1
  if n == "dc_build" then go(p, i)
  elseif n == "dc_next" then
    local nx = i % #TESTS + 1
    p.gui.screen.dc_live.dc_pick.selected_index = nx
    go(p, nx)
  elseif n == "dc_act" then
    local T = storage.tests[i]
    if T and TESTS[i].act then TESTS[i].act(T, plot(i), world()) note(p, "(pressed " .. TESTS[i].step .. ")") end
  elseif n == "dc_v_character" then view(p, "character")
  elseif n == "dc_v_nauvis" then view(p, "nauvis")
  elseif n == "dc_v_platform" then view(p, "platform")
  elseif n == "dc_v_vulcanus" then view(p, "vulcanus")
  elseif n == "dc_ok" or n == "dc_bad" then
    local field = e.element.parent.dc_note
    note(p, (n == "dc_ok" and "PASS " or "PROBLEM ") .. field.text)
    p.print((n == "dc_ok" and "Pass" or "Problem") .. " saved.")
    field.text = ""
  end
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(e)
  if e.element.name == "dc_pick" then go(game.get_player(e.player_index), e.element.selected_index) end
end)
