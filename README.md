# Rubble

Destructible objects for Roblox that break where you actually hit them, a chunk at a time. Hit a wall and it knocks a small piece out right at the impact, hit it again and the hole grows, and how fast it gives way depends on how thick it is, a thin wall punches through in a couple hits while a thick one just gets chewed at. It works on parts and meshes alike because the engine does the cutting.

It's built on the Fragment API that shipped in mid-2026 (`GeometryService:FragmentAsync`), so this isn't another hand-rolled voronoi slicer, the engine turns geometry into pieces. What Rubble adds is the part the raw API doesn't have: a system that lets you erode an object gradually and locally, instead of one call that turns the whole thing to rubble at once.

## two modes

`Mode = "Chip"` is the default and it's the progressive one. The first hit quietly fractures the whole part into little chunks and freezes them in place so it still looks solid, and every hit after that knocks loose the nearest few chunks to the impact, capped by `ChipPerHit` so a single hit never clears the whole thing. Because those chunks run through the full thickness of the wall, a thin wall's chunks reach all the way through and you get a real hole on the first solid hit, while a thick wall only loses the ones near the surface and takes a dent. The thickness behaviour isn't special-cased anywhere, it just falls out of the geometry. The rim around each hole darkens a little every time it's hit, so the cracking builds up visibly. After every hit it also checks what's still holding on: it flood-fills out from the chunks touching the ground, and anything no longer connected to that gets cut loose and falls, so you can knock the base out from under a section and watch the top drop instead of hanging in the air. Once enough of the part is gone (`CollapseAt`) whatever's left comes down at once.

`Mode = "Shatter"` is the one-shot version. It carries a health value, wears down over hits, and when it hits zero the whole thing blows apart at once. The neat bit here is the fracture is biased toward the impact: `FragmentAsync` builds its cells around a list of points, so Rubble packs points tight at the hit and sparse elsewhere, which gives you fine shards at the impact fading to coarse slabs at the edges. In testing the near shards come out around 5-6x smaller than the far chunks, so it reads as a real impact and not a uniform pop.

Either way, the pieces launch with a falloff so the ones on the impact fly hardest and the far ones barely move, plus a nudge along the hit direction so it looks like something drove through it.

## requirements

- The Fragment API. It's recent, so make sure your Studio and the target place have it available. If `GeometryService:FragmentAsync` errors, that's why.
- `FragmentAsync` yields and it's a solid-modeling op, so run this on the **server**. Rubble already wraps the call in a spawned thread, but the part you're breaking needs to live server-side and replicate normally.
- Works on parts and MeshParts. Anything with a sensible bounding box, since that's what the fracture points are laid out in before being clipped to the real shape.

## use

```lua
local Rubble = require(game.ReplicatedStorage.Rubble)

Rubble.Register(workspace.Wall, {
    Health = 120,
    ImpactForce = 60,
})

-- from your weapon / tool hit code, on the server:
Rubble.Hit(workspace.Wall, hitPosition, 40, hitDirection)
```

Each `Hit` subtracts damage at the point you pass. Once health reaches zero it breaks on its own, using that last hit as the impact center. If you'd rather skip the health model and just blow something up, call `Rubble.Break(part, position, direction)` directly.

`hitDirection` is optional. Pass the unit direction the shot was travelling and the debris carries some of that momentum, leave it off and it just bursts outward from the point.

## config

Passed as the second arg to `Register`, all optional.

| key | default | what it does |
| --- | --- | --- |
| Mode | "Chip" | "Chip" for progressive holes, "Shatter" for one-shot |
| ChunkSize | 2.4 | stud size of the chunks in chip mode, smaller is finer but heavier |
| ChipRadius | 2.4 | studs of reach per hit |
| ChipPerHit | 6 | most chunks a single hit can knock loose, keeps it gradual |
| ChipPower | 0.015 | how much extra reach each point of damage adds |
| CollapseAt | 0.15 | fraction of chunks left before the rest drops |
| Scorch | 0.16 | how much the rim darkens per hit, 0 to turn it off |
| MaxCells | 80 | cap on chunks a part is prefractured into |
| Health | 100 | shatter mode only, damage before it breaks |
| ImpactCount | 24 | shatter mode, shard points clustered at the hit |
| ImpactRadius | 2.4 | studs the shattered zone spreads |
| ImpactSkew | 1.6 | higher pulls shards tighter to the center |
| FarSpacing | 2.4 | shatter mode, spacing of the coarse chunks |
| MaxFragments | 90 | shatter mode, cap on total pieces |
| ImpactForce | 55 | outward launch speed at the impact |
| Penetration | 20 | momentum carried along the hit direction |
| Scatter | 8 | random spread on the launch |
| Spin | 12 | random angular velocity |
| Lifetime | 6 | seconds before debris is cleaned up |
| CollisionGroup | nil | collision group for the fragments |
| Gravity | nil | body name so debris falls under that gravity, see below |
| OnDamage | nil | fires each hit: part, health, maxHealth, position |
| OnBreak | nil | fires on shatter: part, impact, fragmentCount |

## gravity

Rubble ships with a small gravity module at `Rubble.Gravity`, mostly so the debris can fall at a real rate, but it works standalone on anything.

The catch with "1:1 Earth" is that Roblox measures gravity in studs and reality measures it in metres, so the two only line up once you pick a stud-to-metre scale. The module holds every body's real surface gravity in m/s² and multiplies by that scale, which defaults to 20. I landed on 20 because Roblox's own default gravity of 196.2 turns out to be Earth at 20.007 studs per metre, so it's already tuned to look right and I'm just matching it. If you actually want the literal 9.80665 you can drop the scale to 1, but fair warning, everything falls in slow motion because a 5-stud character is then a 5-metre giant.

```lua
local Gravity = require(game.ReplicatedStorage.Rubble).Gravity

Gravity.SetWorld("Earth")      -- Workspace.Gravity = 196.2
Gravity.SetWorld("Moon")       -- 32.4, everything drifts
Gravity.Reset()                -- back to Roblox default

Gravity.SetScale(1)            -- switch to 1 stud = 1 metre
Gravity.Earth()                -- now 9.80665, proper floaty realism
```

`Apply` puts one object on its own gravity without touching the rest of the world, which is what the `Gravity` config key uses under the hood so you can have moon-gravity debris in an earth-gravity level:

```lua
Gravity.Apply(someFragment, "Moon")
Gravity.Remove(someFragment)
```

Bodies included: Earth, Moon, Mars, Mercury, Venus, Jupiter, Saturn, Uranus, Neptune, Pluto, Sun. `Gravity.Studs(body)` gives you the studs/s² value if you just want the number.

## api

| call | does |
| --- | --- |
| Register(Part, Options) | make a part destructible |
| Unregister(Part) | stop tracking it |
| IsRegistered(Part) | boolean |
| Hit(Part, Position, Damage, Direction) | damage it at a point |
| Break(Part, Position, Direction) | shatter it now |
| GetHealth(Part) | returns health, maxHealth |
| SetHealth(Part, Health) | set health directly |
| Heal(Part, Amount) | add health, capped at max |
| Clear() | destroy all live debris |

## performance

Every chunk is a real part, so the count is what costs you. `ChunkSize` and `MaxCells` are the knobs, smaller chunks look better and hit the frame rate harder, and 2.4 with an 80 cap is a middle ground that holds up. Rubble also sets up two collision groups on load so the flying debris ignores the still-standing wall and ignores other debris, which is both a big physics saving and the thing that stops freed chunks from wedging against the anchored ones and jittering when you chip a wall from different sides. Debris only ends up colliding with the world, not with each other.

Fragment meshes come in at whatever collision fidelity the engine picks, and a plain script can't change that (it's a plugin-only property), so the win here is keeping the chunk count down rather than cheapening each chunk's collision.

## limitations

- `MaxFragments` exists for a reason. Every fragment is a physics part, and a wall that bursts into 300 of them will drop the frame rate on anything, so the cap keeps it sane. Turn it up if your scene can afford it.
- It registers two collision groups (`RubbleStructure`, `RubbleDebris`). If you already manage collision groups, know that debris goes in `RubbleDebris` and won't collide with your structure group or with each other unless you change that.
- The support check treats "connected to the ground" as connected through neighbouring chunks, using the bottom of the original part as the ground line. It's a proximity flood-fill, not a real stress solver, so it handles walls, towers and pillars well but won't reason about a cantilever that should snap under its own weight.
- Debris just gets cleaned up on a timer right now. No settling detection, no merging small pieces back into static geometry, so a very active scene can pile up briefly before the timer catches up.
- It fractures the whole part on break. Partial hits wear down the health and fire `OnDamage`, but they don't chip actual geometry off yet, that's the next thing I want to add and it's not here.
- The fracture points are laid out in the bounding box, so a long thin or very hollow mesh will get points in empty space that produce nothing. Fine for walls, crates, rock, less ideal for a chandelier.
- Fragment API is newish. If Roblox changes the signature this'll need a small patch.

## license

MIT
