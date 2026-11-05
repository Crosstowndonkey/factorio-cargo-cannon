-- Suite "circuit": every way the circuit network controls a cannon, and what the network sees from it.
local C = require("common")
local DC, check, count, CHEST, RED, GREEN = C.DC, C.check, C.count, C.CHEST, C.RED, C.GREEN
local S = {}

local COMPARE = {  -- signal A is 5 on every one of these
  {">", 4, true}, {">", 5, false}, {"<", 6, true}, {"<", 5, false}, {"=", 5, true}, {"=", 4, false},
  {"≥", 5, true}, {"≥", 6, false}, {"≤", 5, true}, {"≤", 4, false}, {"≠", 4, true}, {"≠", 5, false},
}

local function cond(signal, op, constant)
  return {circuit_enable = true, condition = {signal = C.sig(signal), comparator = op, constant = constant}}
end
local function item_cond(item, op, constant)
  return {circuit_enable = true, condition = {signal = {type = "item", name = item}, comparator = op, constant = constant}}
end
local function fired(cannon, item) return count(cannon, item) == 0 end
local function full_rx(rx, free)  -- fill all but `free` slots with stone
  local inv = rx.get_inventory(CHEST)
  for i = 1, #inv - free do inv[i].set_stack{name = "stone", count = 50} end
end

function S.setup(T)
  local W = C.world()
  local n, p = W.n, W.p
  T.reload = {}  -- cannons refilled with a stack whenever their cargo slot is empty

  -- 1. each comparator, true and false
  T.cmp_rx = C.build(p, "cargo-cannon-receiver", {-30, -30})
  T.cmp = {}
  for i, t in ipairs(COMPARE) do
    local c = C.cannon(n, {-55 + 8 * (i - 1), -50}, T.cmp_rx, "iron-plate", 100, cond("signal-A", t[1], t[2]))
    C.combinator(n, {-55 + 8 * (i - 1), -46}, {["signal-A"] = 5}, c)
    T.cmp[i] = c
  end
  -- 2. red and green add up: A = 3 on red + 4 on green
  T.sum_rx = C.build(p, "cargo-cannon-receiver", {-20, -30})
  T.sum7 = C.cannon(n, {-55, -36}, T.sum_rx, "copper-plate", 100, cond("signal-A", "=", 7))
  T.sum3 = C.cannon(n, {-47, -36}, T.sum_rx, "copper-plate", 100, cond("signal-A", "=", 3))
  for _, c in pairs({T.sum7, T.sum3}) do
    C.combinator(n, {c.position.x - 1, -32}, {["signal-A"] = 3}, c, {RED})
    C.combinator(n, {c.position.x + 1, -32}, {["signal-A"] = 4}, c, {GREEN})
  end
  -- 3. negative values
  T.neg = C.cannon(n, {-39, -36}, T.sum_rx, "steel-plate", 100, cond("signal-A", "<", 0))
  C.combinator(n, {-39, -32}, {["signal-A"] = -5}, T.neg)
  -- 4. an item signal from a chest: copper ore >= 100 (50 at first, 150 from tick 400)
  T.ore_chest = n.create_entity{name = "iron-chest", position = {-31, -32}, force = "player"}
  T.ore_chest.insert{name = "copper-ore", count = 50}
  T.ore = C.cannon(n, {-31, -36}, T.sum_rx, "stone-brick", 100, item_cond("copper-ore", "≥", 100))
  T.ore_chest.get_wire_connector(RED, true).connect_to(T.ore.get_wire_connector(RED, true))
  -- 5. its own charge: "charge = 100" fires; "charge < 100" never can (a shot needs a full charge)
  T.ch_full = C.cannon(n, {-23, -36}, T.sum_rx, "plastic-bar", 100, cond(C.CHARGE, "=", 100))
  T.ch_low = C.cannon(n, {-15, -36}, T.sum_rx, "plastic-bar", 100, cond(C.CHARGE, "<", 100))
  -- 6. its own contents, with no outside wires: "iron plate >= 100"
  T.own = C.cannon(n, {-7, -36}, T.sum_rx, "iron-plate", 100, item_cond("iron-plate", "≥", 100))
  -- 6b. its own contents count once (not once per wire): 50 plates, "iron plate >= 100" holds, "= 50" fires
  T.own_half = C.cannon(n, {9, -36}, T.sum_rx, "iron-plate", 50, {full_stack = false, circuit_enable = true,
                        condition = {signal = {type = "item", name = "iron-plate"}, comparator = "≥", constant = 100}})
  T.own_eq = C.cannon(n, {17, -36}, T.sum_rx, "iron-plate", 50, {full_stack = false, circuit_enable = true,
                      condition = {signal = {type = "item", name = "iron-plate"}, comparator = "=", constant = 50}})
  T.own_red = C.cannon(n, {25, -36}, T.sum_rx, "iron-plate", 50, {full_stack = false, circuit_enable = true,
                       condition = {signal = {type = "item", name = "iron-plate"}, comparator = "=", constant = 80}})
  C.combinator(n, {25, -32}, {["iron-plate"] = 30}, T.own_red)  -- + 30 from outside on red = 80
  -- 7. no signal picked: disabled
  T.nosig = C.cannon(n, {1, -36}, T.sum_rx, "iron-plate", 100, {circuit_enable = true,
                     condition = {signal = nil, comparator = ">", constant = 0}})

  -- 8. one free slot, two cannons wired safely (space > 0): exactly one fires, nothing crashes
  T.one_rx = C.build(p, "cargo-cannon-receiver", {-10, -30})
  full_rx(T.one_rx, 1)
  T.one_a = C.cannon(n, {-55, -20}, T.one_rx, "iron-ore", 50, cond(C.SPACE, ">", 0))
  T.one_b = C.cannon(n, {-47, -20}, T.one_rx, "iron-ore", 50, cond(C.SPACE, ">", 0))
  -- 9. a receiver limited by its inventory bar to 2 slots; a safe cannon refilled forever sends exactly 2
  T.bar_rx = C.build(p, "cargo-cannon-receiver", {0, -30})
  T.bar_rx.get_inventory(CHEST).set_bar(3)
  T.bar = C.cannon(n, {-39, -20}, T.bar_rx, "coal", 50, cond(C.SPACE, ">", 0))
  table.insert(T.reload, {T.bar, "coal", 50})
  -- 10. two safe cannons on one shared red network, aimed at different receivers (40 free and 1 free): each reads
  --     its own receiver's space, not the network's sum
  T.shared_rx_big = C.build(p, "cargo-cannon-receiver", {10, -30})
  T.shared_rx_one = C.build(p, "cargo-cannon-receiver", {20, -30})
  full_rx(T.shared_rx_one, 1)
  T.sh_big = C.cannon(n, {-31, -20}, T.shared_rx_big, "wood", 100, cond(C.SPACE, ">", 0))
  T.sh_one = C.cannon(n, {-23, -20}, T.shared_rx_one, "wood", 100, cond(C.SPACE, ">", 0))
  T.sh_one.get_wire_connector(RED, true).connect_to(T.sh_big.get_wire_connector(RED, true))
  table.insert(T.reload, {T.sh_one, "wood", 100})
  T.sh_lamp = n.create_entity{name = "small-lamp", position = {-27, -16}, force = "player"}
  T.sh_lamp.get_wire_connector(RED, true).connect_to(T.sh_big.get_wire_connector(RED, true))

  -- 11. switched on and off: A = 1 from tick 100 to 600, refilled all the time
  T.tog_rx = C.build(p, "cargo-cannon-receiver", {30, -30})
  T.tog = C.cannon(n, {-55, -4}, T.tog_rx, "iron-gear-wheel", 100, cond("signal-A", ">", 0))
  T.tog_cc = C.combinator(n, {-55, 0}, {["signal-A"] = 0}, T.tog)
  table.insert(T.reload, {T.tog, "iron-gear-wheel", 100})
  -- 12. target by signal, switched: channel A until 600, then B, then 0 (none) at 1000, then an unknown channel
  T.sw_a = C.build(p, "cargo-cannon-receiver", {-30, 0})
  T.sw_b = C.build(p, "cargo-cannon-receiver", {-20, 0})
  T.sw = C.cannon(n, {-47, -4}, nil, "copper-cable", 200, {circuit_target = true, target_signal = C.sig("signal-C")})
  T.sw_cc = C.combinator(n, {-47, 0}, {["signal-C"] = DC("receiver", T.sw_a).channel}, T.sw)
  table.insert(T.reload, {T.sw, "copper-cable", 200})
  -- 13. another force's receiver on that channel is not a target
  local beta = game.create_force("beta")
  T.beta_rx = C.build(p, "cargo-cannon-receiver", {-10, 0}, beta)
  DC("configure_receiver", T.beta_rx, {channel = 777})
  T.other = C.cannon(n, {-39, -4}, nil, "iron-stick", 100, {circuit_target = true, target_signal = C.sig("signal-C")})
  C.combinator(n, {-39, 0}, {["signal-C"] = 777}, T.other)
  -- 14. two receivers of ours share channel 555: the capsule goes to one of them, never lost
  T.dup_a = C.build(p, "cargo-cannon-receiver", {0, 0})
  T.dup_b = C.build(p, "cargo-cannon-receiver", {10, 0})
  for _, r in pairs({T.dup_a, T.dup_b}) do DC("configure_receiver", r, {channel = 555}) end
  T.dup = C.cannon(n, {-31, -4}, nil, "pipe", 100, {circuit_target = true, target_signal = C.sig("signal-C")})
  C.combinator(n, {-31, 0}, {["signal-C"] = 555}, T.dup)
  -- 15. both: aimed by signal C and enabled by A
  T.both_rx = C.build(p, "cargo-cannon-receiver", {20, 0})
  T.both = C.cannon(n, {-23, -4}, nil, "stone", 50, {circuit_target = true, target_signal = C.sig("signal-C"),
                    circuit_enable = true, condition = {signal = C.sig("signal-A"), comparator = ">", constant = 0}})
  T.both_cc = C.combinator(n, {-23, 0}, {["signal-C"] = DC("receiver", T.both_rx).channel, ["signal-A"] = 0}, T.both)

  -- 16. what other machines on the wire see: lamps on red and on green of a cannon aimed at an empty receiver
  T.ro_rx = C.build(p, "cargo-cannon-receiver", {30, 0})
  T.ro = C.build(n, "cargo-cannon", {-15, -4})
  C.load(T.ro, 7, nil)
  DC("set_target", T.ro, T.ro_rx)
  T.lamp_red = n.create_entity{name = "small-lamp", position = {-17, 0}, force = "player"}
  T.lamp_green = n.create_entity{name = "small-lamp", position = {-13, 0}, force = "player"}
  T.lamp_red.get_wire_connector(RED, true).connect_to(T.ro.get_wire_connector(RED, true))
  T.lamp_green.get_wire_connector(GREEN, true).connect_to(T.ro.get_wire_connector(GREEN, true))
  -- the lamp on red is lit by "Receiver space > 10"
  local lcb = T.lamp_red.get_or_create_control_behavior()
  lcb.circuit_enable_disable = true
  lcb.circuit_condition = {first_signal = C.sig(C.SPACE), comparator = ">", constant = 10}

  -- 16b. a player who only uses green: the signals move to green
  T.ro_g = C.build(n, "cargo-cannon", {-7, -4})
  DC("set_target", T.ro_g, T.ro_rx)
  T.lamp_only_green = n.create_entity{name = "small-lamp", position = {-7, 0}, force = "player"}
  T.lamp_only_green.get_wire_connector(GREEN, true).connect_to(T.ro_g.get_wire_connector(GREEN, true))
  -- 16c. both wires connected: nothing the cannon sends is counted twice in its own condition
  T.two_rx = C.build(p, "cargo-cannon-receiver", {30, 20})
  T.two = C.cannon(n, {1, -4}, T.two_rx, "iron-plate", 100, cond(C.CHARGE, "=", 100))
  C.combinator(n, {0, 0}, {["signal-A"] = 1}, T.two, {RED})
  C.combinator(n, {2, 0}, {["signal-B"] = 1}, T.two, {GREEN})
  -- 16d. the game's condition: compared with a second signal (A = 5, B = 3 and 9)
  T.vs_rx = C.build(p, "cargo-cannon-receiver", {20, 20})
  T.vs_yes = C.cannon(n, {9, -4}, T.vs_rx, "iron-plate", 100)
  C.native(T.vs_yes, {first_signal = C.sig("signal-A"), comparator = ">", second_signal = C.sig("signal-B")})
  C.combinator(n, {9, 0}, {["signal-A"] = 5, ["signal-B"] = 3}, T.vs_yes)
  T.vs_no = C.cannon(n, {17, -4}, T.vs_rx, "iron-plate", 100)
  C.native(T.vs_no, {first_signal = C.sig("signal-A"), comparator = ">", second_signal = C.sig("signal-B")})
  C.combinator(n, {17, 0}, {["signal-A"] = 5, ["signal-B"] = 9}, T.vs_no)
  -- 16e. its own signal against a second signal: space (40) > B
  T.own_vs_no = C.cannon(n, {25, -4}, T.vs_rx, "iron-plate", 100)
  C.native(T.own_vs_no, {first_signal = C.sig(C.SPACE), comparator = ">", second_signal = C.sig("signal-B")})
  C.combinator(n, {25, 0}, {["signal-B"] = 100}, T.own_vs_no)
  T.own_vs_yes = C.cannon(n, {33, -4}, T.vs_rx, "iron-plate", 100)
  C.native(T.own_vs_yes, {first_signal = C.sig(C.SPACE), comparator = ">", second_signal = C.sig("signal-B")})
  C.combinator(n, {33, 0}, {["signal-B"] = 1}, T.own_vs_yes)
  -- 16f. a condition that's switched off doesn't hold fire
  T.off = C.cannon(n, {41, -4}, T.vs_rx, "iron-plate", 100)
  C.native(T.off, {first_signal = C.sig("signal-A"), comparator = ">", constant = 0}, false)

  -- 17. special signals. Condition: Anything / Everything work as on an inserter (A = 5, plus the cannon's own
  --     contents and readouts); Each is refused by the GUI and never fires. Target signal: special = no target.
  T.spec_rx = C.build(p, "cargo-cannon-receiver", {-30, 20})
  T.special = {}
  local cases = {
    {"anything > 4", "signal-anything", ">", 4, true}, {"anything < 0", "signal-anything", "<", 0, false},
    {"everything > 0", "signal-everything", ">", 0, true}, {"everything > 6", "signal-everything", ">", 6, false},
    {"each > 0", "signal-each", ">", 0, false},
  }
  for i, t in ipairs(cases) do
    local c1 = C.cannon(n, {-55 + 8 * (i - 1), 12}, T.spec_rx, "iron-plate", 100, cond(t[2], t[3], t[4]))
    C.combinator(n, {-55 + 8 * (i - 1), 16}, {["signal-A"] = 5}, c1)
    T.special[i] = {name = t[1], cannon = c1, fires = t[5]}
  end
  T.spec_target = {}
  for i, name in ipairs({"signal-anything", "signal-everything", "signal-each"}) do
    local c2 = C.cannon(n, {-55 + 8 * (i - 1), 22}, nil, "iron-plate", 100, {circuit_target = true, target_signal = C.sig(name)})
    C.combinator(n, {-55 + 8 * (i - 1), 26}, {["signal-C"] = DC("receiver", T.spec_rx).channel}, c2)
    T.spec_target[name] = c2
  end
end

local function sig_at(e, name, wire) return e.get_signal(C.sig(name), wire) end

function S.tick(T, tick)
  for _, r in pairs(T.reload) do
    local slot = r[1].get_inventory(CHEST)[2]
    if not slot.valid_for_read then slot.set_stack{name = r[2], count = r[3]} end
    local caps = r[1].get_inventory(CHEST)[1]
    if not caps.valid_for_read or caps.count < 5 then caps.set_stack{name = "cargo-cannon-capsule", count = 50} end
  end
  if tick == 100 then
    C.set_value(T.tog_cc, 1, "signal-A", 1)
    check("readout on red: other machines see receiver space 40", sig_at(T.lamp_red, C.SPACE, RED) == 40, sig_at(T.lamp_red, C.SPACE, RED))
    check("both wires connected: the signals are on red only", sig_at(T.lamp_green, C.SPACE, GREEN) == 0,
          sig_at(T.lamp_green, C.SPACE, GREEN))
    check("green only: the signals move to green", sig_at(T.lamp_only_green, C.SPACE, GREEN) == 40,
          sig_at(T.lamp_only_green, C.SPACE, GREEN))
    print("STA info: the cannon's own contents on its wire: capsules = " ..
          T.lamp_red.get_signal({type = "item", name = "cargo-cannon-capsule"}, RED))
  end
  if tick == 200 then
    check("readout: charge reaches 100 on the wire", sig_at(T.lamp_red, C.CHARGE, RED) == 100, sig_at(T.lamp_red, C.CHARGE, RED))
    local lit = not T.lamp_red.get_control_behavior().disabled
    check("readout: a lamp wired to 'Receiver space > 10' is lit", lit)
  end
  if tick == 400 then
    check("item signal: held while copper ore = 50", count(T.ore, "stone-brick") == 100, C.status(T.ore))
    T.ore_chest.insert{name = "copper-ore", count = 100}
    C.set_value(T.both_cc, 2, "signal-A", 1)
  end
  if tick == 600 then
    C.set_value(T.tog_cc, 1, "signal-A", 0)
    C.set_value(T.sw_cc, 1, "signal-C", DC("receiver", T.sw_b).channel)
  end
  if tick == 900 then
    T.tog_after = count(T.tog_rx, "iron-gear-wheel")
    T.sw_a_after = count(T.sw_a, "copper-cable")
  end
  if tick == 1000 then C.set_value(T.sw_cc, 1, "signal-C", 0) end
  if tick == 1100 then
    check("target by signal: C = 0 means no target", C.status(T.sw) == "no-target", C.status(T.sw))
    C.set_value(T.sw_cc, 1, "signal-C", 99999)
  end
  if tick == 1200 then
    check("target by signal: an unknown channel means no target", C.status(T.sw) == "no-target", C.status(T.sw))
  end
  if tick == 1300 then T.sw_b_after = count(T.sw_b, "copper-cable") end  -- the last capsule fired before C = 0 has landed
  if tick == 1500 then
    for i, t in ipairs(COMPARE) do
      local f = fired(T.cmp[i], "iron-plate")
      check("comparator: 5 " .. t[1] .. " " .. t[2] .. (t[3] and " fires" or " holds"), f == t[3], C.status(T.cmp[i]))
    end
    check("red + green add up: A = 7 fires", fired(T.sum7, "copper-plate"), C.status(T.sum7))
    check("red + green add up: A = 3 holds", not fired(T.sum3, "copper-plate"), C.status(T.sum3))
    check("negative signal: A = -5 < 0 fires", fired(T.neg, "steel-plate"), C.status(T.neg))
    check("item signal: fired once the chest had 150 copper ore", fired(T.ore, "stone-brick"), C.status(T.ore))
    check("own charge = 100: fires", fired(T.ch_full, "plastic-bar"), C.status(T.ch_full))
    check("own charge < 100: holds (a shot needs a full charge)", not fired(T.ch_low, "plastic-bar"), C.status(T.ch_low))
    check("own contents: 'iron plate >= 100' fires with no outside wires", fired(T.own, "iron-plate"), C.status(T.own))
    check("own contents count once: 50 plates, '>= 100' holds", not fired(T.own_half, "iron-plate"), C.status(T.own_half))
    check("own contents count once: 50 plates, '= 50' fires", fired(T.own_eq, "iron-plate"), C.status(T.own_eq))
    check("own contents + 30 from a combinator: '= 80' fires", fired(T.own_red, "iron-plate"), C.status(T.own_red))
    check("both wires: 'charge = 100' fires (not counted twice)", fired(T.two, "iron-plate"), C.status(T.two))
    check("second signal: A 5 > B 3 fires", fired(T.vs_yes, "iron-plate"), C.status(T.vs_yes))
    check("second signal: A 5 > B 9 holds", not fired(T.vs_no, "iron-plate"), C.status(T.vs_no))
    check("own signal vs second signal: space > B 100 holds", not fired(T.own_vs_no, "iron-plate"), C.status(T.own_vs_no))
    check("own signal vs second signal: space > B 1 fires", fired(T.own_vs_yes, "iron-plate"), C.status(T.own_vs_yes))
    check("a condition switched off doesn't hold fire", fired(T.off, "iron-plate"), C.status(T.off))
    check("no signal picked: disabled", C.status(T.nosig) == "disabled", C.status(T.nosig))
    local a, b = fired(T.one_a, "iron-ore"), fired(T.one_b, "iron-ore")
    check("one free slot, two safe cannons: exactly one fired", a ~= b, tostring(a) .. " / " .. tostring(b))
    check("one free slot: it arrived, nothing crashed", count(T.one_rx, "iron-ore") == 50 and T.one_rx.health == T.one_rx.max_health,
          count(T.one_rx, "iron-ore") .. ", health " .. T.one_rx.health)
    check("inventory bar of 2 slots: exactly 2 stacks sent, then holds",
          count(T.bar_rx, "coal") == 100 and C.status(T.bar) == "disabled" and T.bar_rx.health == T.bar_rx.max_health,
          count(T.bar_rx, "coal") .. ", " .. C.status(T.bar))
    check("shared network: each cannon reads its own receiver (the 1-slot one got exactly 1 stack)",
          count(T.shared_rx_one, "wood") == 100 and T.shared_rx_one.health == T.shared_rx_one.max_health,
          count(T.shared_rx_one, "wood") .. ", health " .. T.shared_rx_one.health)
    check("shared network: the other fired as normal", count(T.shared_rx_big, "wood") == 100, count(T.shared_rx_big, "wood"))
    print("STA info: a lamp on that shared red wire sees receiver space " .. sig_at(T.sh_lamp, C.SPACE, RED) ..
          " (the sum of both cannons' readouts)")
    local tog_end = count(T.tog_rx, "iron-gear-wheel")
    check("switched on: fired while A = 1", T.tog_after >= 200, T.tog_after)
    check("switched off: no shots after A went back to 0", tog_end == T.tog_after and C.status(T.tog) == "disabled",
          T.tog_after .. " -> " .. tog_end .. ", " .. C.status(T.tog))
    check("target by signal: switching C moved the shots from A to B",
          T.sw_a_after > 0 and count(T.sw_a, "copper-cable") == T.sw_a_after and T.sw_b_after > 0,
          "A " .. T.sw_a_after .. " -> " .. count(T.sw_a, "copper-cable") .. ", B " .. T.sw_b_after)
    check("target by signal: nothing more after C = 0 / unknown", count(T.sw_b, "copper-cable") == T.sw_b_after,
          T.sw_b_after .. " -> " .. count(T.sw_b, "copper-cable"))
    check("another force's receiver on the channel is not a target",
          not fired(T.other, "iron-stick") and C.status(T.other) == "no-target" and count(T.beta_rx, "iron-stick") == 0, C.status(T.other))
    local da, db = count(T.dup_a, "pipe"), count(T.dup_b, "pipe")
    check("two receivers on one channel: the shot arrived in one of them", da + db == 100, da .. " + " .. db)
    check("aimed by signal + enabled by signal: fired after A = 1", count(T.both_rx, "stone") == 50, C.status(T.both))
    for _, t in ipairs(T.special) do
      check("special condition: " .. t.name .. (t.fires and " fires" or " holds"), fired(t.cannon, "iron-plate") == t.fires, C.status(t.cannon))
    end
    for name, c2 in pairs(T.spec_target) do
      check("special target signal: " .. name .. " = no target", C.status(c2) == "no-target" and not fired(c2, "iron-plate"), C.status(c2))
    end
    return true
  end
end

return S
