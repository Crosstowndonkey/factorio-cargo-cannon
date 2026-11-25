-- Screenshot run for Cargo Cannon (not part of the mod): tools/run_screens.sh opens a real game window on a
-- throwaway save; this builds a small scene, uses the panels (through the mod's own GUI handlers), and saves
-- screenshots of what the headless tests can't see: the panels beside the game's windows, firing, landing, a crash
-- and its message. They land in <work>/write/script-output/dc-screens/.
local C = require("common")
local DC, CHEST = C.DC, C.CHEST
local OUT = "dc-screens/"

local function shot(name, args)
  args = args or {}
  args.path = OUT .. name .. ".png"
  args.resolution = args.resolution or {1600, 900}
  args.quality = 90
  game.take_screenshot(args)
  print("STA screenshot " .. name)
end

local function gui(player, event, element)
  DC("test_gui_event", event, {player_index = player.index, element = element})
end

local function find(frame, name)
  if frame.name == name then return frame end
  for _, child in pairs(frame.children) do
    local found = find(child, name)
    if found then return found end
  end
end

-- Every message and status line the mod can show, translated by the game for the real player: a missing or broken
-- one comes back untranslated. (Chat doesn't show in screenshots, so the crash messages are checked this way.)
local function translate_all(player)
  local keys = {}
  for _, why in pairs({"full", "gone"}) do
    table.insert(keys, {"cargo-cannon.crashed-" .. why, "[item=coal,quality=normal] x50", "[gps=8,-20,platform-1]"})
  end
  table.insert(keys, {"cargo-cannon.missed-platform", "[item=coal,quality=normal] x50", "Test platform"})
  table.insert(keys, {"cargo-cannon.lost", "[item=coal,quality=normal] x50"})
  for _, st in pairs({"no-target", "no-signal", "no-channel", "same-surface", "no-route", "cannon-travelling", "target-travelling",
                      "needs-research", "not-in-orbit", "disabled", "no-capsules", "no-cargo-picked", "no-cargo",
                      "wrong-cargo", "waiting-full", "charging", "no-power", "fired"}) do
    table.insert(keys, {"dc-gui.status-" .. st, 3})
  end
  for _, why in pairs({"same-surface", "no-route", "cannon-travelling", "target-travelling", "needs-research", "not-in-orbit"}) do
    table.insert(keys, {"dc-gui.why-" .. why})
  end
  storage.pending_translations = #keys
  for _, k in pairs(keys) do player.request_translation(k) end
end

script.on_event(defines.events.on_string_translated, function(e)
  local key = type(e.localised_string) == "table" and e.localised_string[1] or tostring(e.localised_string)
  if e.translated then
    if key:find("cargo-cannon.", 1, true) == 1 then print("STA text " .. key .. ": " .. e.result) end
  else
    print("STA FAIL text " .. key .. " did not translate")
  end
  storage.pending_translations = (storage.pending_translations or 1) - 1
  if storage.pending_translations == 0 then print("STA all texts translated") end
end)

script.on_event(defines.events.on_tick, function(e)
  local T = storage.T
  local player = game.get_player(1)
  if not player then return end
  if not T then
    T = {}
    storage.T = T
    local W = C.world()
    DC("set_cost", "orbit", {energy = 5, capsules = 1, flight = 4})
    T.W = W
    local n, p = W.n, W.p
    T.rx = C.build(p, "cargo-cannon-receiver", {-8, -20})
    DC("configure_receiver", T.rx, {name = "Iron dock"})
    T.full = C.build(p, "cargo-cannon-receiver", {8, -20})
    DC("configure_receiver", T.full, {name = "Full dock"})
    for slot = 1, 40 do T.full.get_inventory(CHEST)[slot].set_stack{name = "stone", count = 50} end
    T.local_rx = C.build(n, "cargo-cannon-receiver", {8, 10})
    DC("configure_receiver", T.local_rx, {name = "Nauvis yard"})
    T.cannon = C.build(n, "cargo-cannon", {0, 10})
    T.cannon.get_inventory(CHEST).insert{name = "cargo-cannon-capsule", quality = "uncommon", count = 10}
    T.crasher = C.cannon(n, {-8, 10}, T.full, "coal", 50)
    T.crasher.get_inventory(CHEST)[1].clear()
    if player.character then
      player.character.teleport({0, 15}, n)
    else
      local body = n.create_entity{name = "character", position = {0, 15}, force = "player"}
      player.set_controller{type = defines.controllers.character, character = body}
    end
    T.start = e.tick
    return
  end
  local t = e.tick - T.start
  if t == 5 then translate_all(player) end
  if t == 20 then
    -- the cannon's window, target and cargo picked in its panel
    player.opened = T.cannon
    local frame = player.gui.relative.dc_panel
    T.panel_ok = frame ~= nil
    if frame then
      local dd = frame.dc_target
      for i, item in ipairs(dd.items) do
        if i > 1 and serpent.line(item):find("Iron dock", 1, true) then dd.selected_index = i end
      end
      gui(player, defines.events.on_gui_selection_state_changed, dd)
      local pick = find(frame, "dc_cargo")
      pick.elem_value = {name = "iron-plate", quality = "normal"}
      gui(player, defines.events.on_gui_elem_changed, pick)
    end
    print("STA cannon panel open: " .. tostring(T.panel_ok))
  end
  if t == 40 then shot("1-cannon-window", {player = player, by_player = player, show_gui = true}) end
  if t == 50 then
    player.opened = T.local_rx
    print("STA receiver panel open: " .. tostring(player.gui.relative.dc_panel ~= nil))
  end
  if t == 70 then shot("2-receiver-window", {player = player, by_player = player, show_gui = true}) end
  if t == 80 then
    player.opened = nil
    T.cannon.get_inventory(CHEST)[2].set_stack{name = "iron-plate", count = 100}
    T.crasher.get_inventory(CHEST)[1].set_stack{name = "cargo-cannon-capsule", count = 5}
  end
  -- the moment it fires
  if t > 80 and not T.fired and not T.cannon.get_inventory(CHEST)[2].valid_for_read then
    T.fired = t
    print("STA fired at " .. t)
  end
  if T.fired and t == T.fired + 4 then shot("3-firing", {surface = T.W.n, position = {0, 2}, zoom = 1}) end
  -- the capsule falling onto the platform (it falls for the last second, from 60 tiles up)
  if T.fired and t == T.fired + 215 then shot("4-falling", {surface = T.W.p, position = {-14, -45}, zoom = 0.75}) end
  -- landing: the iron shows up in the dock
  if T.fired and not T.landed and T.rx.get_inventory(CHEST).get_item_count("iron-plate") > 0 then
    T.landed = t
    print("STA landed at " .. t)
  end
  if T.landed and t == T.landed + 2 then shot("5-landed", {surface = T.W.p, position = {0, -20}, zoom = 1}) end
  -- the crash on the full dock
  if not T.crashed and T.full.valid and T.full.health < T.full.max_health then
    T.crashed = t
    print("STA crash at " .. t .. ": full dock health " .. T.full.health .. "/" .. T.full.max_health)
  end
  if T.crashed and t == T.crashed + 3 then shot("6-crash", {surface = T.W.p, position = {0, -20}, zoom = 1}) end
  if T.crashed and t == T.crashed + 30 then
    game.print("STA test: a plain chat line, to see if chat shows in screenshots")
  end
  if T.crashed and t == T.crashed + 40 then shot("7-message", {player = player, by_player = player, show_gui = true}) end
  if T.crashed and t == T.crashed + 50 then player.opened = T.cannon end
  if T.crashed and t == T.crashed + 70 then shot("8-cannon-after", {player = player, by_player = player, show_gui = true}) end
end)
