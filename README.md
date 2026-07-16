# Rubble

Destructible objects for Roblox that break where you actually hit them. You give a part some health, hit it a few times, and when it finally gives it shatters into fine shards right at the impact and coarse chunks everywhere else, all thrown outward from the spot the hit landed. It works on parts and meshes alike because the engine does the cutting.

It's built on the Fragment API that shipped in mid-2026 (`GeometryService:FragmentAsync`), so this is not another hand-rolled voronoi slicer. The engine handles turning geometry into pieces. What Rubble adds is the two things the raw API doesn't: a **damage model** so things wear down over several hits instead of popping in one, and **impact-localized fracturing** so a hit cracks the surface it struck rather than uniformly exploding the whole object like a bomb went off in the middle.

## the impact trick

`FragmentAsync` builds a 3D voronoi diagram from a list of points you hand it, one cell per point. Feed it an even spread and you get an even, boring break. The whole idea here is to feed it an *uneven* spread: a tight cluster of points packed around the impact, and a sparse scattering across the rest of the body. Cells come out tiny where the points are dense and big where they're sparse, so you get a crater of shards at the hit fading into large slabs at the edges. In testing the near shards come out around 5-6x smaller than the far chunks, which reads as a real impact instead of a shatter effect.

Then every fragment gets launched with a falloff, the pieces sitting on the impact fly hardest and the far ones barely move, plus a nudge along the hit direction so it looks like something drove through it.

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
| Health | 100 | hits worth of damage before it breaks |
| ImpactCount | 24 | shard points clustered at the hit |
| ImpactRadius | 2.4 | studs the shattered zone spreads |
| ImpactSkew | 1.6 | higher pulls shards tighter to the center |
| FarSpacing | 2.4 | stud spacing of the coarse chunks |
| MaxFragments | 90 | hard cap on total pieces |
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

## limitations

- `MaxFragments` exists for a reason. Every fragment is a physics part, and a wall that bursts into 300 of them will drop the frame rate on anything, so the cap keeps it sane. Turn it up if your scene can afford it.
- Debris just gets cleaned up on a timer right now. No settling detection, no merging small pieces back into static geometry, so a very active scene can pile up briefly before the timer catches up.
- It fractures the whole part on break. Partial hits wear down the health and fire `OnDamage`, but they don't chip actual geometry off yet, that's the next thing I want to add and it's not here.
- The fracture points are laid out in the bounding box, so a long thin or very hollow mesh will get points in empty space that produce nothing. Fine for walls, crates, rock, less ideal for a chandelier.
- Fragment API is newish. If Roblox changes the signature this'll need a small patch.

## license

MIT
