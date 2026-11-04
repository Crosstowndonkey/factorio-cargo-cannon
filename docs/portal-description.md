Fire capsules of cargo between surfaces. Shoot supplies up to a space platform waiting in orbit, send its output back
down to the planet, and - after more research - fire across space to receivers on other planets.

## How it works
- **Cargo cannon** (3x3): slot 1 takes **cargo capsules**, slot 2 the cargo. Each shot carries **one stack of one item**
  (any quality). By default it waits for a full stack.
- **Cargo receiver** (5x5): catches the capsules. Give it a name and a channel number in its window.
- Each shot needs capsules and a full charge of power:

| | Orbit shot | Interplanetary shot |
|---|---|---|
| Reaches | a platform stopped above the cannon's planet, the planet below a platform, or another platform at the same place | a receiver on another planet |
| Research | Cargo cannon | Interplanetary cargo |
| Capsules | 1 | 3 |
| Energy | 50 MJ | 1 GJ |
| Time in the air | 5 seconds | 90 seconds |

## Set it up right
A capsule that lands on a **full receiver**, or where there is **no receiver**, explodes like a grenade and its cargo
is lost. A capsule aimed at a platform that has left orbit misses.

The cannon tells its circuit network what it needs to know:
- **Receiver space** - empty stacks in its target, minus capsules already on their way
- **Cannon charge** - in %
- and its contents, like a chest

Wire it to fire only while Receiver space > 0 and nothing will ever crash.

## Circuit control
- An enable / disable condition, like an inserter's: one signal, Anything or Everything.
- Or pick the target by signal: the signal's value is a receiver's channel number (0 = hold fire).
- Several cannons can share a wire: each one's condition reads its own Receiver space and charge.

## Logistics
- Inserters load and empty both buildings.
- For robots, the cannon is a **requester chest** (request capsules and cargo) and the receiver a **passive provider**.
  Space platforms have no robots, so use inserters there.
- Copy / paste and blueprints keep a cannon's settings.

## Settings
Energy, capsules and flight time for each kind of shot, the cannon's charging rate and the crash damage are all mod
settings.

## Optional: Space Exploration's cannon art
Install Earendel's graphics mods [space-exploration-graphics](https://mods.factorio.com/mod/space-exploration-graphics)
and [space-exploration-graphics-5](https://mods.factorio.com/mod/space-exploration-graphics-5) and the cannon,
receiver, capsules and icons use his delivery cannon art instead. They're graphics only, so they work alongside Space
Age (Space Exploration itself doesn't). The startup setting *Use Space Exploration's cannon art* turns it off.
The buildings keep the same size either way, so saves and blueprints aren't affected.

## Credits
Inspired by the delivery cannon in Earendel's [Space Exploration](https://mods.factorio.com/mod/space-exploration) -
thank you, Earendel. This is an independent mod for Space Age, written from scratch: not a port of Space Exploration,
and not affiliated with it or its author.

The buildings use Factorio's own art (the artillery turret and cargo landing pad), tinted; the mod contains no images
of its own. With Space Exploration's graphics mods installed, they use Earendel's delivery cannon art instead, with his
permission - the art stays in his mods and is only referred to, never copied.

Source code (MIT): https://github.com/Crosstowndonkey/factorio-cargo-cannon
