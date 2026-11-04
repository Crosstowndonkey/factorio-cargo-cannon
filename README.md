# Cargo Cannon

A Factorio 2.1 / Space Age mod: fire capsules of cargo between surfaces.

- **Orbit shots:** from a planet to a space platform stopped above it, back down, or between two platforms at the
  same place. 1 capsule, 50 MJ, ~5 seconds in the air.
- **Interplanetary shots** (after the *Interplanetary cargo* research): from a planet to a receiver on another
  planet. 3 capsules, 1 GJ, ~90 seconds in the air.
- **One stack of one item per shot.** Slot 1 of the cannon takes capsules, slot 2 the cargo. By default it waits
  for a full stack.
- **Crashes:** a capsule that lands on a full receiver, or where there's no receiver, explodes like a grenade and
  its cargo is lost. A capsule aimed at a platform that has left orbit misses.
- **Circuits:** an enable / disable condition like an inserter's (one signal, Anything or Everything), or pick the
  target by signal (each receiver has a channel number). The cannon sends **Receiver space** (empty stacks in its
  target, minus capsules already on their way), **Cannon charge** (%) and its contents to its circuit network -
  fire only while Receiver space > 0 and nothing will crash. With several cannons on one wire, other machines see
  their signals added up, but each cannon's condition reads its own.
- **Logistics:** inserters load and empty both buildings; the cannon is a requester chest and the receiver a
  passive provider for robots. (Space platforms have no robots - use inserters there.)

All numbers are mod settings. The art is Factorio's own (the artillery turret and cargo landing pad, tinted).

Inspired by the delivery cannon in Earendel's [Space Exploration](https://mods.factorio.com/mod/space-exploration).
This is an independent mod for Space Age, written from scratch - not a port of Space Exploration and not affiliated
with it.

## Development

- `tools/run_tests.sh [suite ...]` runs the tests on a headless game in a throwaway folder (never ~/.factorio):
  - `main` (tests/dc-tests/main.lua, 24 checks): shots, crashes, robots, inserters, readouts, research;
  - `circuit` (50): every comparator, red + green, item signals, Anything / Everything / Each, switching on and off,
    targets by signal, shared wires, what other machines see;
  - `situations` (33): platforms leaving or travelling, quality, spoilage, armour equipment, power, cannons and
    receivers destroyed mid-flight, a deleted planet, copy / paste, blueprints, the GUI;
  - `saveload` (tests/dc-saveload, 8): saved with capsules in the air on a headless server, loaded, and landed.
- `tools/package.sh` builds the zip for the mod portal into dist/.

MIT licence.
