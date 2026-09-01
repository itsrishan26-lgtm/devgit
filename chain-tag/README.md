# Chain Tag

Round-based chain tag for Roblox, in Luau. One seeker starts; everyone they
chain becomes a seeker too, until the park is one long chain or the clock runs
out.

Seven scripts, no models to import, no paid assets. Everything you would want
to tune lives in one file (`ChainTagConfig`).

---

## 1. Setup (about five minutes)

Do these in order. **Names matter** — the scripts find each other by name, and
a typo is a silent failure.

### Step 1 — the two spawn pads

In **Workspace** you need two `SpawnLocation` parts named exactly:

```
Seeker Spawn        <- with the space
Runner Spawn        <- with the space
```

On both of them set:

| Property | Value | Why |
|---|---|---|
| `Enabled` | **off** | the round script does the spawning, not Roblox |
| `Neutral` | **on** | stops team colours from hijacking spawns |
| `Anchored` | **on** | so they do not fall through the map |

Put them far apart — a good gap is most of the map.

> If a pad is missing, the game still boots: it makes a grey placeholder and
> tells you in the Output window. Rename your real pad and the warning stops.

### Step 2 — ReplicatedStorage (two ModuleScripts)

Insert two **ModuleScript**s under `ReplicatedStorage` and paste the matching
file into each:

| Name it exactly | Paste from |
|---|---|
| `ChainTagConfig` | `src/ReplicatedStorage/ChainTagConfig.lua` |
| `ChainTagShared` | `src/ReplicatedStorage/ChainTagShared.lua` |

You do **not** create the RemoteEvents by hand — `ChainTagShared` builds them
when the server starts.

### Step 3 — ServerScriptService

**Watch the Type column.** `ChainService` is a **ModuleScript**; everything
else here is a plain **Script**. Insert the wrong class and it silently never
runs.

| Name it exactly | Type | Paste from |
|---|---|---|
| `GameSetup` | Script | `src/ServerScriptService/GameSetup.server.lua` |
| `CatchDetection` | Script | `src/ServerScriptService/CatchDetection.server.lua` |
| `MapEvents` | Script | `src/ServerScriptService/MapEvents.server.lua` |
| `Powerups` | Script | `src/ServerScriptService/Powerups.server.lua` |
| `Shop` | Script | `src/ServerScriptService/Shop.server.lua` |
| `ChainService` | **ModuleScript** | `src/ServerScriptService/ChainService.lua` |
| `MovementService` | Script | `src/ServerScriptService/MovementService.server.lua` |

If you already have scripts with these names, paste over them completely.

### Step 4 — StarterPlayerScripts (three LocalScripts)

Insert three **LocalScript**s under `StarterPlayer > StarterPlayerScripts`:

| Name it exactly | Paste from |
|---|---|
| `Sprint` | `src/StarterPlayer/StarterPlayerScripts/Sprint.client.lua` |
| `ChainTagUI` | `src/StarterPlayer/StarterPlayerScripts/ChainTagUI.client.lua` |
| `ChainVisuals` | `src/StarterPlayer/StarterPlayerScripts/ChainVisuals.client.lua` |
| `ScoreboardUI` | `src/StarterPlayer/StarterPlayerScripts/ScoreboardUI.client.lua` |
| `AbilityBar` | `src/StarterPlayer/StarterPlayerScripts/AbilityBar.client.lua` |
| `ShopUI` | `src/StarterPlayer/StarterPlayerScripts/ShopUI.client.lua` |
| `ChainTagSettings` | `src/StarterPlayer/StarterPlayerScripts/ChainTagSettings.client.lua` |
| `Movement` | `src/StarterPlayer/StarterPlayerScripts/Movement.client.lua` |

### Step 5 — delete the old stuff

* `StarterPlayerScripts > CatchCountdownUI` — replaced by `ChainTagUI`. Two
  countdown scripts means two countdowns on screen.
* Anything sitting in **StarterPack**. Everything in StarterPack is copied into
  every player's Backpack and runs there; the `attempt to index nil with
  'CharacterAdded'` error you were seeing is a script in there calling
  `Players.LocalPlayer` from a server Script. Nothing in this game needs to be
  in StarterPack.
* `ParkDecor` / `TerrainDecor` — if your map is already baked into Workspace,
  disable or delete these so they do not rebuild it every server start.

`GameSetup` prints a warning in the Output window for each of these if it finds
them, plus for any `Sound` still using the private id `rbxassetid://5028439856`.

### Step 6 — press Play

The Output window should show:

```
[ChainTag] GameSetup running. Round length 120s, 2 player(s) needed.
[ChainTag] CatchDetection running. Tag range 6 studs.
[ChainTag] MapEvents running. Pickups: true, beacon: true, rescue: true
[ChainTag] Powerups running. Dash 9s, Radar 24s, Vanish 26s.
[ChainTag] Shop running. 10 items in the catalogue.
[ChainTag] MovementService running. Slide and vault validated server-side.
[ChainTag] ChainTagUI loaded and listening.
[ChainTag] ChainVisuals loaded. Chain mode: Leash
[ChainTag] ScoreboardUI loaded. Hold Tab.
[ChainTag] AbilityBar loaded. Keys 1 and 2.
[ChainTag] ShopUI loaded. Press P or click STORE.
[ChainTag] ChainTagSettings loaded. Press O or click SETTINGS.
[ChainTag] Movement loaded. C to slide, Space to vault.
```

Six from the server, seven from the client. A few seconds later one more line
appears saying what frame rate it measured and which quality level it chose. **If the client four are
missing, the LocalScripts are not installed** — and `GameSetup` will name
each missing one in a warning, including if you added it as the wrong class
(a Script instead of a LocalScript).

Testing alone? Open `ChainTagConfig` and set `Config.MinPlayers = 1`. You get a
solo practice round (no seeker, nothing to catch) so you can walk the map and
check the HUD. Use **Test > Players > 2 Players** in Studio for a real round.

---

## 2. What ends up in the Explorer

```
Workspace
  Seeker Spawn                  SpawnLocation, Enabled off, Neutral on
  Runner Spawn                  SpawnLocation, Enabled off, Neutral on

ReplicatedStorage
  ChainTagConfig                ModuleScript   every tunable number
  ChainTagShared                ModuleScript   helpers + wiring
  ChainTagRemotes               (made at runtime)
    CatchCountdown              RemoteEvent
    Toast                       RemoteEvent
  ChainTagState                 (made at runtime) attributes the HUD reads

ServerScriptService
  GameSetup                     Script         round loop, roles, scoring
  CatchDetection                Script         tagging
  MapEvents                     Script         pickups, beacon, rescue
  Powerups                      Script         abilities and their cooldowns
  Shop                          Script         purchases and equipping
  ChainService                  ModuleScript   the chain: order, tension, breaks
  MovementService               Script         validates and counts slides/vaults

StarterPlayer
  StarterPlayerScripts
    Sprint                      LocalScript    sprint + stamina bar
    ChainTagUI                  LocalScript    the whole HUD
    ChainVisuals                LocalScript    chain, outlines, leash
    ScoreboardUI                LocalScript    Tab scoreboard + results
    AbilityBar                  LocalScript    the two ability buttons
    ShopUI                      LocalScript    the store panel
    Movement                    LocalScript    slide, vault, landing weight
    ChainTagSettings            LocalScript    settings, and the quality dial

Workspace
  ChainTagMap                   (made at runtime) pickups and the beacon
```

---

## 3. How a round plays

```
Waiting  ->  Intermission  ->  Starting  ->  Round  ->  Results  ->  repeat
```

| Phase | What happens |
|---|---|
| **Waiting** | Not enough players yet. Everyone idles at Runner Spawn. |
| **Intermission** | 12s. Everyone is a runner, chains cleared, next round counting down. |
| **Starting** | 8s head start. One player is picked as seeker and **frozen** at Seeker Spawn while the runners scatter. Nobody can be tagged yet. |
| **Round** | 120s. Seekers hunt. Every catch grows the chain. Ends the second the last runner is caught. |
| **Results** | 8s. Win banner, points handed out. |

**Getting caught:** a seeker within 6 studs of a runner, with a clear line of
sight, tags them. Everyone on the server sees a red 3-2-1 countdown, then the
catcher's whole chain — including the new prisoner — is pulled back to Seeker
Spawn and released together. The caught player is now a seeker and can tag too.

That trip home is the price of every catch: the seeker team loses its position
and the runners get three seconds of breathing room. Set
`Config.TeleportOnCatch = false` if you would rather the chain stayed put and
only the two players involved froze.

**Winning:** seekers win by chaining everyone before the timer ends. Runners win
if a single one of them is still free when it hits zero.

### Things to do in the park

Three systems run during the round. None of them need you to mark or place
anything — every position is found at runtime by raycasting for flat ground
inside `Config.Map.Radius` of `Config.Map.Center`.

**Energy crystals.** Eight glowing pickups scattered on the ground, and each
one rolls its own rarity when it lands:

| Rarity | Chance | Stamina | Speed | Points |
|---|---|---|---|---|
| Common | 62% | +40 | +4 for 4s | — |
| Rare | 26% | +70 | +6 for 5s | +5 |
| Epic | 9% | +100 | +8 for 6s | +15 |
| **Legendary** | **3%** | +140 | +11 for 8s | +40 |

The weights are the point. Common and Rare are scenery, Epic is a find, and
Legendary is a **server-wide event** — it announces itself to everybody the
moment it lands, so people drop what they are doing and race for it.

Rarity is communicated by one thing only: colour. The same colour appears on
the crystal, its light, the burst it leaves when taken, the card on your
screen and the ring of orbs that spins around you afterwards. Seekers get a
smaller share of the speed than runners, so a crystal is worth taking for
both sides without making a seeker unstoppable.

**The beacon.** A marked circle that lands somewhere random 15 seconds into
the round and moves every 35 seconds. Runners score a point per second while
they stand in it. It drags people out of the far corners and tells the
seekers exactly where to go — the whole point is that both sides know. Your
HUD shows a needle pointing at it and the distance.

**Prison breaks.** Stand within nine studs of somebody on the *end* of a
chain and hold your ground for four seconds: they are cut loose and go back
to being a runner, untouchable for three seconds so they cannot be instantly
re-tagged. Worth 20 points to whoever frees them. Only the end of a chain can
be freed, each player only once per round, and rescues are locked out once
the endgame reveal starts — otherwise a big enough runner team could stall
forever.

This is the biggest change to how the game plays. If you want it off, set
`Config.Rescue.Enabled = false` and everything else carries on working.

### The store

Press **P**, or click **STORE** on the left edge. Everything costs Points,
which you earn by playing.

| | |
|---|---|
| **Trails** | stream behind you when you run |
| **Auras** | orbit you all round long |
| **Chains** | recolour the chain you drag |
| **Titles** | float over your head |

**Everything in it is cosmetic on purpose.** A store that sells speed turns
every round into a question of who has ground the most points, and the people
who most need a fair round are the new ones with nothing bought.

**Spending never costs you a level.** `Points` is a balance the store spends
down; `TotalPoints` is everything you have ever earned and only goes up. Levels
read the second one.

Adding an item is one line in `Config.Shop.Items` — the store UI builds itself
from that list, and the server re-reads the price and your balance from its own
copy, so nothing about a purchase trusts your client.

### Movement

| | |
|---|---|
| **Shift** | sprint (stamina) |
| **C** or Ctrl | slide |
| **Space** at something waist-high | vault it instead of jumping into it |

All three are on every player from their first round. **Nothing about
movement is ever unlocked, bought or levelled into** — the moment movement
is a reward, the chase stops being about skill and starts being about
playtime.

**Sliding** needs you to already be moving at 17 studs/sec, so it rewards
commitment rather than being a second dash. It starts at 34 and sheds speed,
locks your steering for its length, and costs 12 stamina. That last part is
what stops it being a permanent way to travel.

**Vaulting** is on the jump button on purpose — no new key to learn, and the
game works out what you meant. It fires when there is something between 1.2
and 4.6 studs tall ahead of you, nothing at chest height, and floor on the
far side to land on. If any of that is missing you just jump. You keep 24
studs/sec of momentum on the other side, so a vault is faster than going
around, which is the whole reason to learn where they are.

**Landings** have weight. Drop more than 14 studs and the camera dips; more
than 30 and you lose half your speed for half a second. Without that, a
rooftop is a free escape from anything.

#### How it is split

Movement runs on the client and answers on the same frame you press the key.
A round trip to the server first would put 100ms of nothing between the
button and the slide, and no amount of correctness makes that feel good.

`MovementService` on the server owns the cooldowns and the counters. That is
the part worth protecting: Roblox gives every client authority over its own
character's physics, so pretending the server can stop a cheater from moving
strangely would be theatre — but **nothing is ever paid out from a client's
word**, so a player spamming the remote earns nothing for it. Server
cooldowns run slightly shorter than the client's so a bad connection is never
told no for a move it legitimately made.

### Powerups

Two slots, bottom of the screen. Press **1** and **2**, or tap them on a phone.
Slot 2 relabels itself when your role changes, so you are never shown a button
you are not allowed to press.

| Slot | Who | What it does | Cooldown |
|---|---|---|---|
| **DASH** | everyone | A hard shove in the direction you are moving. Breaks a tackle, or closes one. | 9s |
| **RADAR** | seekers | Every runner lights up through walls for 4 seconds. | 24s |
| **VANISH** | runners | You fade out on everyone else's screen for 4 seconds. | 26s |

Vanish is deliberately the answer to Radar: a runner who fades at the right
moment is not on the sweep. And Vanish does not make you safe — you can still
be tagged while faded, it just breaks the chase.

Cooldowns are counted **on the server**, which is the only place they can be
counted safely. The buttons on screen just draw what the server already
decided, so a player editing their own client cannot shorten one.

**Anti-camping:** with 30 seconds left, every remaining runner is outlined
through walls for the seeker team. When one runner is left, everybody sees a
`LAST RUNNER` marker over them. Hiding in a bush until the timer runs out does
not work.

**Joining mid-round:** you spectate the rest of the round as a normal player —
you cannot tag and cannot be tagged — and you are in automatically next round.

---

## 4. What each script does

**`ChainTagConfig`** — every number in the game. Round length, speeds, catch
range, chain behaviour, points, colours, sounds. Nothing else needs editing to
rebalance.

**`ChainTagShared`** — required by all the others. It builds the RemoteEvents
and the state folder on the server, waits for them on the client, and holds the
helpers both server scripts use (freezing, teleporting, spawn ring maths) so
nothing is written twice.

**`GameSetup`** (Script) — the round loop and the only thing that decides who is
what. Also owns teams, the `leaderstats` (Points and Catches), saved stats, and
the startup check that warns you about a broken setup.

**`CatchDetection`** (Script) — checks seeker-to-runner distance ten times a
second, confirms with one raycast, and runs the catch sequence.

**`Powerups`** (Script) — the three abilities and, more importantly, their
cooldowns. Nothing else on the server or the client is allowed to decide
whether an ability fires.

**`MapEvents`** (Script) — the pickups, the beacon and the rescue mechanic.
Deliberately separate: if you delete this script the game still runs a
perfectly good round without it.

**`Sprint`** (LocalScript) — hold Shift, L3 on a gamepad, or the on-screen
button on mobile. Stamina drains while sprinting and regrows when you stop.
Runners have a bigger tank than seekers, which is the runners' main defence.

**`ChainTagUI`** (LocalScript) — timer, phase, runners left, role banners, the
catch countdown, the win banner, the catch feed, and the red edge glow that
grows as a seeker closes in on you.

**`ChainVisuals`** (LocalScript) — draws the chain, outlines seekers (red),
reveals runners in the endgame, marks the last runner, spins the pickups and
pulses the beacon, and works out how much the chain slows you down.

**`ScoreboardUI`** (LocalScript) — hold Tab for role, level, catches, prison
breaks and points. Opens on its own when a round ends.

**`AbilityBar`** (LocalScript) — the two ability buttons, their cooldown
sweeps and the countdown numbers. It also applies the dash shove, because a
shove pushed from the server stutters and one applied by the client that owns
the character does not.

### How the scripts talk to each other

* **Player attributes** — `IsSeeker`, `InRound`, `Frozen`, `ChainedTo`. Set by
  the server, readable by everyone.
* **`ReplicatedStorage.ChainTagState` attributes** — `Phase`, `PhaseEndsAt`,
  `RunnersLeft`, `TotalRunners`, `Winner`, `EndgameReveal` and friends.
  Attributes replicate on their own, so the HUD stays in sync without a
  RemoteEvent firing every second. The timer on your screen is the server's
  clock (`workspace:GetServerTimeNow()`), not a local countdown, so it cannot
  drift.
* **RemoteEvents** — only two: `CatchCountdown` and `Toast`.
* **`CT_` attributes** (`CT_ChainSlow`, `CT_ChainTaut`, `CT_Danger`) — written
  by `ChainVisuals` on your own client and read by the other two LocalScripts.
  They never leave your machine.
* `_G.GameActive` is still set for compatibility with older scripts, but nothing
  here depends on it.

---

## 5. Performance

Frame rate is a feature. The whole client draws through one quality dial,
auto-detected on your first join by **measuring actual frame time for four
seconds** — not by guessing from whether you are on a phone, because plenty
of phones outrun plenty of laptops. Change it any time in Settings.

| | Low | Medium | High |
|---|---|---|---|
| Chain links | 3 | 5 | 7 |
| Chain draw distance | 90 | 150 | 220 |
| Aura draw distance | 70 | 130 | 220 |
| Aura orbs | half | three quarters | all |
| Pickup burst | off | on | on |
| Speed streaks | off | on | on |
| Screen shake | off | on | on |
| Head titles | off | on | on |

**Quality never touches gameplay.** Low draws a shorter chain; it never gives
a shorter cooldown, a bigger tag radius or more speed. Nobody can turn the
settings down for an advantage.

### What the client does each frame

Roblox's own advice is to [audit every RenderStepped connection, because each
one adds to the frame budget](https://create.roblox.com/docs/performance-optimization).
So the client work is split by how often it can actually be noticed:

**Ten times a second** — anything that scans every player or walks a
character's descendants: the vanish fade, deciding who has an aura, trail
enable/disable, and the nearest-seeker scan behind the danger glow and the
heartbeat.

**Every frame** — only moving parts that already exist: chain links, aura
orbs, the crystal spin, and the chain leash. The leash has to be per frame
because it feeds your walk speed, and at 10 Hz you would feel it stepping.

That is roughly six times less per-frame work than the first version, with no
visible difference.

### The one thing you have to do yourself

**Turn on StreamingEnabled.** It cannot be set from a script, and for a map
your size it is [the single biggest performance win available](https://create.roblox.com/docs/performance-optimization):

1. Click **Workspace** in the Explorer
2. In Properties, tick **StreamingEnabled**
3. Set **StreamingTargetRadius** to `512`

Without it every player downloads your entire park before they can move.
`GameSetup` warns you in Output if it is off and your map is large.

Two more that are worth the click:

- `Lighting.Technology` → **ShadowMap** if you are targeting low-end phones.
- Untick **CastShadow** on small decor. Shadows on 121 flowers cost real
  frames and nobody has ever noticed them.

## 5b. Tuning

Open `ChainTagConfig`. The ones you will actually reach for:

| Setting | Default | Effect |
|---|---|---|
| `MinPlayers` | 2 | set to 1 to test alone |
| `RoundLength` | 120 | length of the hunt |
| `HeadStart` | 8 | seeker freeze at round start; raise it on a bigger map |
| `CatchRadius` | 6 | tag range in studs; 5 is tight, 8 is generous |
| `Speeds.SeekerWalk` | 17 | seekers are slightly faster than runners on purpose |
| `Stamina.RunnerBonus` | 25 | extra stamina runners get over seekers |
| `Chain.Mode` | `"Leash"` | `"Visual"` draws the chain without slowing anyone, `"Off"` removes it |
| `Chain.MaxDistance` | 22 | how far chained players can stretch apart |
| `EndgameRevealAt` | 30 | seconds left when runners get outlined |
| `Map.Radius` | 170 | how far out from centre pickups and beacons can land |
| `Pickups.Count` | 8 | crystals on the map at once; 0 or `Enabled = false` to remove |
| `Beacon.MoveEvery` | 35 | seconds before the beacon jumps somewhere new |
| `Rescue.Enabled` | true | prison breaks; false removes the mechanic entirely |
| `Rescue.HoldTime` | 4 | seconds you have to hold to free someone |
| `Movement.Slide.MinSpeed` | 17 | how fast you must be going to slide at all |
| `Movement.Slide.Stamina` | 12 | what a slide costs |
| `Movement.Vault.MaxHeight` | 4.6 | the tallest thing you can clear |
| `Movement.Landing.HardDrop` | 30 | fall further than this and you stumble |
| `Abilities.Enabled` | true | false hides the ability bar and refuses every use |
| `Abilities.Dash.Cooldown` | 9 | seconds between dashes |
| `Abilities.Dash.Power` | 62 | how hard the dash shoves |
| `Levels.PointsPerLevel` | 40 | level 2 at 40 points, 3 at 160, 4 at 360 |
| `Combo.Window` | 20 | seconds to keep a catch streak alive |
| `Rarities` | 4 tiers | weights, colours and rewards for the crystals |
| `Aura.Orbs` | 4 | orbs spinning around somebody with an aura |
| `Shop.Items` | 10 | the catalogue; add a line to add an item |
| `Sounds.Cues` | — | pitch and volume per event, with optional per-cue ids |
| `Quality.Levels` | 3 tiers | what each graphics level draws |
| `Quality.LowFpsThreshold` | 35 | measured FPS below this picks Low |
| `Aura.Styles` | 4 shapes | Motes, Ring, DualRing, Halo |
| `Heartbeat.FastInterval` | 0.32 | beat spacing when a seeker is on top of you |
| `Music.Tracks` | empty | paste ids you own |
| `TeleportOnCatch` | true | pull the catcher's whole chain back to Seeker Spawn after a catch |
| `SaveStats` | true | set false to keep stats to the session |

### About the chain

The chain is a **line of at most four**, and the fourth one is the number
that matters. An eight-person chain is not twice as interesting as a
four-person one — it is a conga line that cannot lose. Everyone caught past
the cap becomes a **Support Seeker** instead: no chain, no formation bonus,
but a Radar that recharges twice as fast. No chain, better eyes.

**A chain in formation is faster than four loose seekers.** This is the whole
balance and everything else follows from it. Being chained has to be a prize
the seekers hold on to by moving as a unit — otherwise it is pure penalty,
and a runner breaking it would be doing the seeker team a favour.

| Distance between two links | What happens |
|---|---|
| under 14 studs | **Formation** — everyone on the chain is faster |
| 14 to 22 | bonus fades out |
| 22 to 30 | **Stretched** — the chain starts dragging, down to 30% speed |
| 30 to 38 | **Warning** — the link glows red, both ends are told |
| past 38 for 1.1s | **SNAP** |

You can read all of it off the chain itself: the links run from grey through
amber to red as they stretch, and the sag pulls out of them as they tighten.
A chain about to break is visible from across the park.

**When it snaps**, everyone behind the break detaches into Support Seekers,
the member left holding the front half recoils to 55% speed for three
seconds, and the nearest runner is paid 30 points and a `ChainBreaks` stat
for forcing it. A Support Seeker walks into the empty slot four seconds
later, so a break buys the runners a window rather than permanently crippling
the seeker team.

That is what makes the chain a mechanic rather than a decoration: a runner
who baits two seekers around opposite sides of a building takes their speed
bonus away, and both sides know it.

The whole thing lives in `ChainService`, which owns membership, order,
tension, speed and breaks. It is **server-authoritative** — the client draws
the chain, it does not decide who is on it, how fast they are, or when it
breaks. Rescues and catches call in; nothing else needs to know how a chain
works.

*(Note on physics: none of this uses `RopeConstraint`. Ropes between two
player characters are a tug of war between two machines' physics ownership,
which is what made long chains jostle and occasionally launch people. The
links are drawn locally and the tension is simulated, not physical.)*

### The settings panel

**O**, or the SETTINGS button on the left edge above STORE. Graphics quality,
sound effect volume, music volume and screen shake. Settings save with your
profile, and they are re-validated on the server — a client can ask for any
setting it likes, and only known keys inside their proper ranges survive.

### About the sounds

There is one sample in the whole game — `rbxasset://sounds/electronicpingshort.wav`
— and every cue is that sample at a different pitch. Built-in `rbxasset://`
paths ship with Roblox itself, so they can never fail with "not authorized"
the way a private `rbxassetid://` upload does.

Cues with a `chord` play several pitches in quick succession. That is the
whole trick behind why a Legendary crystal sounds like an event and a Common
one sounds like a click — four rising notes versus one.

**The heartbeat** is the one sound allowed to play continuously, because it
tells you something the HUD cannot: how close the thing behind you is. It
starts when a seeker is inside about 32 studs and the beat tightens from
1.15s to 0.32s as they close.

**Music** is a four-state machine — Lobby, Round, Final, Results — that
crossfades rather than cutting. `Config.Music.Tracks` is empty on purpose:
with no ids it plays nothing and says nothing about it, which is the right
behaviour for a game shipped without music. Paste ids you own and it starts
working with no other change.

`Config.Sounds.Cues` is the full sheet. Each cue takes an optional `soundId`,
so you can replace them one at a time as you find audio you own, without
touching any script. `Config.Sounds.Music` is deliberately empty — only paste
an id you own, or the whole server gets a red error and silence.

---

## 6. Test checklist

Studio, **Test > Players > 2 Players**:

- [ ] Output shows all four `[ChainTag]` lines and no red errors
- [ ] Intermission counts down, then one player gets `YOU ARE THE SEEKER`
- [ ] The seeker cannot move during the head start; the runner can
- [ ] Nobody can be tagged during Intermission or the head start
- [ ] Walking into a runner as the seeker triggers the red 3-2-1 on both screens
- [ ] After the countdown both players are at Seeker Spawn with a chain between them
- [ ] A third catch drags the whole existing chain home, not just the catcher
- [ ] The chain stops at four; the fifth catch says SUPPORT SEEKER in the feed
- [ ] Walking together as a chain is faster than walking alone
- [ ] Pulling apart turns the links amber then red, and the HUD warns twice
- [ ] Past breaking distance the chain snaps, the banner fires, and the nearest runner scores
- [ ] After a break a Support Seeker walks into the empty slot a few seconds later
- [ ] A seeker's HUD reads CHAIN 3/4; a runner's reads how many runners are free
- [ ] Sprinting then pressing C slides, locks your steering, and costs stamina
- [ ] Sliding from a standstill does nothing (you have to already be moving)
- [ ] Space at a waist-high wall vaults it; Space in the open still just jumps
- [ ] You come out of a vault still moving, faster than walking round would be
- [ ] A long drop dips the camera and briefly slows you
- [ ] Another player's slide visibly drops them on your screen too
- [ ] The chained pair slows down when they pull apart, and `CHAIN TAUT` appears
- [ ] `RUNNERS FREE` drops by one, and a dot in the pip row goes dark
- [ ] Catching the last runner ends the round immediately with `SEEKERS WIN`
- [ ] Letting the clock run out ends it with `RUNNERS WIN` and names the survivors
- [ ] Points and Catches appear on the player list and go up
- [ ] Resetting your character mid-round puts you back at the right spawn with your role intact
- [ ] Shift sprints, the stamina bar drains and refills, and it stops at zero
- [ ] Crystals are scattered on the ground, spin, and refill stamina when touched
- [ ] A beacon appears 15s in, the HUD needle points at it, and standing in it earns points
- [ ] Standing next to a chained player fills the FREEING bar and cuts them loose
- [ ] Tab opens the scoreboard, and it opens by itself when the round ends
- [ ] Keys 1 and 2 fire abilities, and slot 2 says RADAR as a seeker, VANISH as a runner
- [ ] A used ability greys out, counts down, then flashes and chirps when it is ready
- [ ] Radar lights the runners up; a runner who vanishes at the right time is not lit
- [ ] Earning points floats a +N up the right of the screen
- [ ] The round starts with 3-2-1-GO and getting tagged shakes the screen
- [ ] Crystals come in four colours; taking one bursts, plays a chord and shows a card
- [ ] After a pickup a ring of orbs spins around you for a few seconds
- [ ] A Legendary crystal announces itself to the whole server when it lands
- [ ] P opens the store, buying deducts points, and the item equips itself
- [ ] A bought trail streams behind you when you sprint, and stops when you stop
- [ ] Buying something does not drop your level
- [ ] O opens Settings, and switching to Low visibly shortens the chain
- [ ] Sound effects OFF actually silences everything, including the heartbeat
- [ ] The heartbeat starts as a seeker closes in and speeds up as they get closer
- [ ] Each rarity of aura is a different shape, not just a different colour

---

## 7. Still on the list

Not done, deliberately, because they are map and asset work rather than code:

1. **Part count.** The baked park is heavy. Merging repeated decor (trees,
   fences) into single MeshParts is the big win; turning off `CastShadow` on
   small props is the cheap one.
2. **Audio.** There is one built-in blip. Music and a proper catch sound need
   asset ids you own.
3. **Map flow.** The head start is 8 seconds; if runners cannot get anywhere
   useful in that time the map needs more cover near Runner Spawn, or a longer
   `HeadStart`.
4. **Cover.** A radial map with long straight paths gives seekers sightlines
   down every spoke. Runners need objects they can *loop around* to break a
   chase — hedge blocks, sheds, a raised deck with two staircases. That is
   map building, not code, but it is what decides whether the game is fun.

---

## Using Rojo instead of copy-paste

`default.project.json` is set up for Rojo 7. `rojo serve` from this folder and
connect from Studio — file names map to the right class automatically
(`.server.lua` becomes a Script, `.client.lua` a LocalScript). Copy-paste is
still fine; the two approaches produce the same tree.
