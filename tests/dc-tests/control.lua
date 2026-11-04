-- Test harness for Cargo Cannon (not part of the mod). Run with --test-save and --test-arg <suite>
-- (tools/run_tests.sh does it): the suite builds its world on tick 1, runs, prints STA PASS / FAIL lines and finishes.
local common = require("common")
local SUITES = {main = require("main"), circuit = require("circuit"), situations = require("situations")}

script.on_event(defines.events.on_tick, function(e)
  if e.tick == 0 then return end
  if not storage.suite then
    local name = script.test_arg
    if not SUITES[name] then
      print("STA FAIL unknown suite '" .. tostring(name) .. "'")
      script.finish_test(false)
      return
    end
    storage.suite, storage.T, storage.start = name, {}, e.tick
    SUITES[name].setup(storage.T)
    return
  end
  if SUITES[storage.suite].tick(storage.T, e.tick - storage.start) then
    common.summary(storage.suite)
  end
end)
