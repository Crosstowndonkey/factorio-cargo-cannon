-- Mod settings. Startup settings change prototypes (need a restart); the rest can be changed in a running game.
data:extend({
  {type = "double-setting", name = "cargo-cannon-orbit-energy", setting_type = "runtime-global",
   default_value = 50, minimum_value = 0, order = "a1"},
  {type = "int-setting", name = "cargo-cannon-orbit-capsules", setting_type = "runtime-global",
   default_value = 1, minimum_value = 1, maximum_value = 10, order = "a2"},
  {type = "double-setting", name = "cargo-cannon-orbit-flight", setting_type = "runtime-global",
   default_value = 5, minimum_value = 1, maximum_value = 600, order = "a3"},
  {type = "double-setting", name = "cargo-cannon-interplanetary-energy", setting_type = "runtime-global",
   default_value = 1000, minimum_value = 0, order = "b1"},
  {type = "int-setting", name = "cargo-cannon-interplanetary-capsules", setting_type = "runtime-global",
   default_value = 3, minimum_value = 1, maximum_value = 10, order = "b2"},
  {type = "double-setting", name = "cargo-cannon-interplanetary-flight", setting_type = "runtime-global",
   default_value = 90, minimum_value = 1, maximum_value = 3600, order = "b3"},
  {type = "double-setting", name = "cargo-cannon-charge-rate", setting_type = "startup",
   default_value = 20, minimum_value = 1, maximum_value = 10000, order = "c1"},
  {type = "double-setting", name = "cargo-cannon-crash-damage", setting_type = "startup",
   default_value = 1, minimum_value = 0, maximum_value = 100, order = "c2"},
  -- only does something when Space Exploration's graphics mods are installed (see data.lua)
  {type = "bool-setting", name = "cargo-cannon-se-graphics", setting_type = "startup",
   default_value = true, order = "c3"},
})
