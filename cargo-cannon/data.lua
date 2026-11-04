-- Cargo Cannon: prototypes. Every picture and sound is Factorio's own (the artillery turret, the cargo landing
-- pad, the artillery shell), copied from the game's prototypes and tinted - the mod ships no art of its own.
-- Optional: when Earendel's Space Exploration graphics mods are installed (and the startup setting is on), the
-- buildings, capsule and icons use his delivery cannon art instead, by reference only (used with his permission,
-- 2026-11-03). Nothing is copied: the files stay in his mods.

local util = require("util")

local CANNON_TINT = {1, 0.82, 0.55}   -- warm brass, so it can't be mistaken for an artillery turret
local RECEIVER_TINT = {0.75, 0.9, 1}
local CAPSULE_TINT = {1, 0.75, 0.3}

local charge_rate = settings.startup["cargo-cannon-charge-rate"].value       -- MW
local crash_damage = settings.startup["cargo-cannon-crash-damage"].value     -- x a grenade

-- A one-frame copy of a sprite layer: the first direction of a rotated sheet becomes a plain sprite.
local function still(layer, extra_shift, tint)
  local l = util.table.deepcopy(layer)
  if l.filenames then l.filename = l.filenames[1] end
  l.filenames, l.lines_per_file, l.direction_count, l.dice = nil, nil, nil, nil
  l.allow_low_quality_rotation, l.line_length, l.frame_count = nil, nil, nil
  l.x, l.y = 0, 0
  local s = l.shift or {0, 0}
  extra_shift = extra_shift or {0, 0}
  l.shift = {s[1] + extra_shift[1], s[2] + extra_shift[2]}
  if tint and not l.draw_as_shadow then l.tint = tint end
  return l
end

-- The cannon: the artillery turret's base with its mount and barrel pointing straight up (north).
local artillery = data.raw["artillery-turret"]["artillery-turret"]
local cannon_layers = {}
for _, l in pairs(artillery.base_picture.layers) do table.insert(cannon_layers, still(l, nil, CANNON_TINT)) end
local HEIGHT = artillery.cannon_base_shift and artillery.cannon_base_shift[3] or 0.97
for _, l in pairs(artillery.cannon_barrel_pictures.layers) do
  table.insert(cannon_layers, still(l, l.draw_as_shadow and {HEIGHT, 0} or {0, -HEIGHT}, CANNON_TINT))
end
for _, l in pairs(artillery.cannon_base_pictures.layers) do
  table.insert(cannon_layers, still(l, l.draw_as_shadow and {HEIGHT, 0} or {0, -HEIGHT}, CANNON_TINT))
end

-- The receiver: the cargo landing pad's still layers, shrunk from 8x8 to 5x5.
local pad = data.raw["cargo-landing-pad"]["cargo-landing-pad"]
local SHRINK = 5 / 8
local receiver_layers = {}
for _, group in pairs(pad.graphics_set.picture) do
  for _, l in pairs(group.layers) do
    local c = util.table.deepcopy(l)
    c.scale = (c.scale or 1) * SHRINK
    local s = c.shift or {0, 0}
    c.shift = {s[1] * SHRINK, s[2] * SHRINK}
    if not c.draw_as_shadow and not c.draw_as_glow then c.tint = RECEIVER_TINT end
    table.insert(receiver_layers, c)
  end
end

local function tinted_icon(path, tint, size)
  return {{icon = path, icon_size = size or 64, tint = tint}}
end

-- Which art to use: icons per role here; the pictures are swapped below.
local SE = "__space-exploration-graphics__/graphics/"
local SE5 = "__space-exploration-graphics-5__/graphics/entity/delivery-cannon/"
local se_art = mods["space-exploration-graphics"] and mods["space-exploration-graphics-5"]
               and settings.startup["cargo-cannon-se-graphics"].value
local icon = {
  cannon = tinted_icon("__base__/graphics/icons/artillery-turret.png", CANNON_TINT),
  receiver = tinted_icon("__base__/graphics/icons/cargo-landing-pad.png", RECEIVER_TINT),
  capsule = tinted_icon("__base__/graphics/icons/artillery-shell.png", CAPSULE_TINT),
  tech = tinted_icon("__base__/graphics/technology/artillery.png", CANNON_TINT, 256),
  tech_far = tinted_icon("__base__/graphics/technology/artillery-range.png", CANNON_TINT, 256),
}

if se_art then
  icon.cannon = {{icon = SE .. "icons/delivery-cannon.png", icon_size = 64}}
  icon.receiver = {{icon = SE .. "icons/delivery-cannon-chest.png", icon_size = 64}}
  icon.capsule = {{icon = SE .. "icons/delivery-cannon-capsule.png", icon_size = 64}}
  icon.tech = {{icon = SE .. "technology/delivery-cannon.png", icon_size = 128}}
  icon.tech_far = {
    {icon = SE .. "technology/delivery-cannon.png", icon_size = 128},
    {icon = "__space-age__/graphics/icons/starmap-planet-vulcanus.png", icon_size = 512, scale = 0.1, shift = {40, 40}},
  }
  -- SE's cannon is 5x5 and its receiving chest 3x3; ours are 3x3 and 5x5, so the pictures are scaled to fit
  -- (the buildings' sizes never change, so saves and blueprints work the same with or without this art).
  local C, R = 3 / 5, 5 / 3
  cannon_layers = {
    {filename = SE5 .. "delivery-cannon.png", width = 320, height = 640, scale = 0.5 * C, shift = {0, -2.5 * C}},
    {filename = SE5 .. "delivery-cannon-shadow.png", width = 470, height = 306, scale = 0.5 * C,
     shift = {1.25 * C, 1 / 32}, draw_as_shadow = true},
  }
  receiver_layers = {
    {filename = SE5 .. "delivery-cannon-chest.png", width = 208, height = 200, scale = 0.5 * R, shift = {0, 0}},
    {filename = SE5 .. "delivery-cannon-chest-shadow.png", width = 278, height = 150, scale = 0.5 * R,
     shift = {0.5625 * R, 0.5875 * R}, draw_as_shadow = true},
  }
end

-- Hidden helpers: a power buffer and a circuit readout, placed on the cannon by script.
local energy = {
  type = "electric-energy-interface",
  name = "cargo-cannon-energy",
  icons = icon.cannon,
  flags = {"not-on-map", "not-blueprintable", "not-deconstructable", "placeable-off-grid", "not-in-kill-statistics",
           "no-copy-paste"},
  hidden = true,
  hidden_in_factoriopedia = true,
  selectable_in_game = false,
  collision_box = {{-1.2, -1.2}, {1.2, 1.2}},
  collision_mask = {layers = {}},
  max_health = 1,
  energy_source = {
    type = "electric",
    usage_priority = "secondary-input",
    buffer_capacity = "1GJ",
    input_flow_limit = charge_rate .. "MW",
    output_flow_limit = "0W",
    render_no_power_icon = false,
    render_no_network_icon = false,
  },
  energy_production = "0W",
  energy_usage = "0W",
  gui_mode = "none",
}

local readout = util.table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
readout.name = "cargo-cannon-readout"
readout.flags = {"not-on-map", "not-blueprintable", "not-deconstructable", "placeable-off-grid",
                 "not-in-kill-statistics", "no-copy-paste"}
readout.hidden = true
readout.hidden_in_factoriopedia = true
readout.selectable_in_game = false
readout.minable = nil
readout.collision_mask = {layers = {}}
readout.collision_box = {{-0.1, -0.1}, {0.1, 0.1}}
readout.selection_box = {{-0.1, -0.1}, {0.1, 0.1}}
readout.sprites = util.empty_sprite()
readout.activity_led_sprites = util.empty_sprite()
readout.corpse, readout.dying_explosion, readout.fast_replaceable_group, readout.next_upgrade = nil, nil, nil, nil
readout.created_smoke = nil
readout.draw_circuit_wires = false
readout.circuit_wire_max_distance = 64

local cannon = {
  type = "logistic-container",
  logistic_mode = "requester",   -- robots bring capsules and cargo you request; inserters work too
  name = "cargo-cannon",
  icons = icon.cannon,
  flags = {"placeable-player", "player-creation"},
  minable = {mining_time = 1, result = "cargo-cannon"},
  max_health = 1500,
  corpse = "artillery-turret-remnants",
  dying_explosion = "artillery-turret-explosion",
  collision_box = {{-1.2, -1.2}, {1.2, 1.2}},
  selection_box = {{-1.5, -1.5}, {1.5, 1.5}},
  drawing_box_vertical_extension = 3,
  damaged_trigger_effect = artillery.damaged_trigger_effect,
  resistances = artillery.resistances,
  open_sound = artillery.open_sound,
  close_sound = artillery.close_sound,
  -- slot 1 = capsules (filtered by script), slot 2 = the cargo
  inventory_size = 2,
  inventory_type = "with_filters_and_bar",
  picture = {layers = cannon_layers},
  circuit_connector = {artillery.circuit_connector},
  circuit_wire_max_distance = artillery.circuit_wire_max_distance,
}

local receiver = {
  type = "logistic-container",
  logistic_mode = "passive-provider",   -- robots take arrivals out as they're needed; inserters work too
  name = "cargo-cannon-receiver",
  icons = icon.receiver,
  flags = {"placeable-player", "player-creation"},
  minable = {mining_time = 1, result = "cargo-cannon-receiver"},
  max_health = 1000,
  corpse = "cargo-landing-pad-remnants",
  dying_explosion = "medium-explosion",
  collision_box = {{-2.4, -2.4}, {2.4, 2.4}},
  selection_box = {{-2.5, -2.5}, {2.5, 2.5}},
  damaged_trigger_effect = pad.damaged_trigger_effect,
  open_sound = pad.open_sound,
  close_sound = pad.close_sound,
  inventory_size = 40,
  inventory_type = "with_bar",
  picture = {layers = receiver_layers},
  circuit_connector = circuit_connector_definitions["chest"],
  circuit_wire_max_distance = default_circuit_wire_max_distance,
}

-- What you see: a shell leaving the cannon, and one falling onto the receiver. Neither does anything itself.
local flight = util.table.deepcopy(data.raw["artillery-projectile"]["artillery-projectile"])
flight.name = "cargo-cannon-capsule-flight"
flight.reveal_map = false
flight.action, flight.final_action, flight.chart_picture = nil, nil, nil
flight.picture.tint = CAPSULE_TINT
if se_art then
  flight.picture = {filename = SE5 .. "delivery-cannon-capsule.png", width = 58, height = 94, scale = 0.25,
                    priority = "high"}
  flight.shadow = {filename = SE5 .. "delivery-cannon-capsule-shadow.png", width = 98, height = 50, scale = 0.25,
                   priority = "high", draw_as_shadow = true}
end

-- A capsule that lands where it can't be caught: a grenade's blast (x the crash damage setting).
local crash = util.table.deepcopy(data.raw.projectile.grenade)
crash.name = "cargo-cannon-capsule-crash"
local function scale_damage(node)
  if type(node) ~= "table" then return end
  if node.type == "damage" and node.damage then node.damage.amount = node.damage.amount * crash_damage end
  for _, v in pairs(node) do scale_damage(v) end
end
scale_damage(crash.action)
table.insert(crash.action[1].action_delivery.target_effects, {type = "create-entity", entity_name = "big-explosion"})

data:extend({
  energy, readout, cannon, receiver, flight, crash,
  {
    type = "sound",
    name = "cargo-cannon-fire",
    variations = {
      {filename = "__base__/sound/fight/artillery-shoots-1.ogg", volume = 0.7},
      {filename = "__base__/sound/fight/artillery-shoots-2.ogg", volume = 0.7},
    },
    audible_distance_modifier = 2,
  },
  {
    type = "virtual-signal",
    name = "cargo-cannon-receiver-space",
    icons = icon.receiver,
    subgroup = "virtual-signal",
    order = "z[cargo-cannon]-a",
  },
  {
    type = "virtual-signal",
    name = "cargo-cannon-charge",
    icon = "__base__/graphics/icons/signal/signal-battery-full.png",
    subgroup = "virtual-signal",
    order = "z[cargo-cannon]-b",
  },
  {
    type = "item",
    name = "cargo-cannon",
    icons = icon.cannon,
    subgroup = "space-related",
    order = "z[cargo-cannon]-a",
    place_result = "cargo-cannon",
    stack_size = 10,
    weight = 200 * kg,
  },
  {
    type = "item",
    name = "cargo-cannon-receiver",
    icons = icon.receiver,
    subgroup = "space-related",
    order = "z[cargo-cannon]-b",
    place_result = "cargo-cannon-receiver",
    stack_size = 10,
    weight = 100 * kg,
  },
  {
    type = "item",
    name = "cargo-cannon-capsule",
    icons = icon.capsule,
    subgroup = "space-related",
    order = "z[cargo-cannon]-c",
    stack_size = 50,
    weight = 10 * kg,
  },
  {
    type = "recipe",
    name = "cargo-cannon",
    enabled = false,
    energy_required = 20,
    ingredients = {
      {type = "item", name = "steel-plate", amount = 100},
      {type = "item", name = "concrete", amount = 100},
      {type = "item", name = "low-density-structure", amount = 20},
      {type = "item", name = "processing-unit", amount = 20},
    },
    results = {{type = "item", name = "cargo-cannon", amount = 1}},
  },
  {
    type = "recipe",
    name = "cargo-cannon-receiver",
    enabled = false,
    energy_required = 10,
    ingredients = {
      {type = "item", name = "steel-plate", amount = 50},
      {type = "item", name = "concrete", amount = 50},
      {type = "item", name = "electronic-circuit", amount = 20},
    },
    results = {{type = "item", name = "cargo-cannon-receiver", amount = 1}},
  },
  {
    type = "recipe",
    name = "cargo-cannon-capsule",
    enabled = false,
    energy_required = 5,
    ingredients = {
      {type = "item", name = "steel-plate", amount = 2},
      {type = "item", name = "explosives", amount = 1},
      {type = "item", name = "electronic-circuit", amount = 1},
    },
    results = {{type = "item", name = "cargo-cannon-capsule", amount = 1}},
  },
  {
    type = "technology",
    name = "cargo-cannon",
    icons = icon.tech,
    prerequisites = {"rocket-silo"},
    effects = {
      {type = "unlock-recipe", recipe = "cargo-cannon"},
      {type = "unlock-recipe", recipe = "cargo-cannon-receiver"},
      {type = "unlock-recipe", recipe = "cargo-cannon-capsule"},
    },
    unit = {
      count = 1000,
      time = 60,
      ingredients = {
        {"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"chemical-science-pack", 1},
        {"production-science-pack", 1}, {"utility-science-pack", 1},
      },
    },
  },
  {
    type = "technology",
    name = "cargo-cannon-interplanetary",
    icons = icon.tech_far,
    prerequisites = {"cargo-cannon", "space-platform-thruster"},
    effects = {{type = "nothing", effect_description = {"technology-description.cargo-cannon-interplanetary-effect"}}},
    unit = {
      count = 1500,
      time = 60,
      ingredients = {
        {"automation-science-pack", 1}, {"logistic-science-pack", 1}, {"chemical-science-pack", 1},
        {"production-science-pack", 1}, {"utility-science-pack", 1}, {"space-science-pack", 1},
      },
    },
  },
})
