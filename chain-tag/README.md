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

### Step 3 — ServerScriptService (two Scripts)

Insert two **Script**s (the plain kind, not LocalScript) under
`ServerScriptService`:

| Name it exactly | Paste from |
|---|---|
| `GameSetup` | `src/ServerScriptService/GameSetup.server.lua` |
| `CatchDetection` | `src/ServerScriptService/CatchDetection.server.lua` |

If you already have scripts with these names, paste over them completely.

### Step 4 — StarterPlayerScripts (three LocalScripts)

Insert three **LocalScript**s under `StarterPlayer > StarterPlayerScripts`:

| Name it exactly | Paste from |
|---|---|
| `Sprint` | `src/StarterPlayer/StarterPlayerScripts/Sprint.client.lua` |
| `ChainTagUI` | `src/StarterPlayer/StarterPlayerScripts/ChainTagUI.client.lua` |
| `ChainVisuals` | `src/StarterPlayer/StarterPlayerScripts/ChainVisuals.client.lua` |

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
[ChainTag] ChainTagUI loaded and listening.
[ChainTag] ChainVisuals loaded. Chain mode: Leash
```

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

StarterPlayer
  StarterPlayerScripts
    Sprint                      LocalScript    sprint + stamina bar
    ChainTagUI                  LocalScript    the whole HUD
    ChainVisuals                LocalScript    chain, outlines, leash
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

**`Sprint`** (LocalScript) — hold Shift, L3 on a gamepad, or the on-screen
button on mobile. Stamina drains while sprinting and regrows when you stop.
Runners have a bigger tank than seekers, which is the runners' main defence.

**`ChainTagUI`** (LocalScript) — timer, phase, runners left, role banners, the
catch countdown, the win banner, the catch feed, and the red edge glow that
grows as a seeker closes in on you.

**`ChainVisuals`** (LocalScript) — draws the chain, outlines seekers (red),
reveals runners in the endgame, marks the last runner, and works out how much
the chain slows you down.

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

## 5. Tuning

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
| `TeleportOnCatch` | true | pull the catcher's whole chain back to Seeker Spawn after a catch |
| `SaveStats` | true | set false to keep stats to the session |

### About the chain

The old version welded parts with `RopeConstraint`s between two characters.
Roblox gives each player physics ownership of their own character, so a rope
between two of them is two computers fighting over the same simulation — that
is exactly why long chains got jostly and people occasionally got launched.

This version draws the chain **on each client with no physics at all**, and
does the pulling by slowing both ends down as they drift apart (`Chain.SlowStart`
to `Chain.MaxDistance`). Chained players still have to move as a group, but
nothing can fling anybody, and the server does no chain work at all.

### About the sounds

Every cue is one built-in sample (`rbxasset://sounds/electronicpingshort.wav`)
played at different pitches — low for a catch, high for a save. Built-in
`rbxasset://` paths ship with Roblox, so they can never fail with "not
authorized" the way a private `rbxassetid://` upload does.

When you have your own audio, replace `Config.Sounds.Blip`. Check every id you
add is owned by you or free to use before you publish.

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
- [ ] The chained pair slows down when they pull apart, and `CHAIN TAUT` appears
- [ ] `RUNNERS FREE` drops by one, and a dot in the pip row goes dark
- [ ] Catching the last runner ends the round immediately with `SEEKERS WIN`
- [ ] Letting the clock run out ends it with `RUNNERS WIN` and names the survivors
- [ ] Points and Catches appear on the player list and go up
- [ ] Resetting your character mid-round puts you back at the right spawn with your role intact
- [ ] Shift sprints, the stamina bar drains and refills, and it stops at zero

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

---

## Using Rojo instead of copy-paste

`default.project.json` is set up for Rojo 7. `rojo serve` from this folder and
connect from Studio — file names map to the right class automatically
(`.server.lua` becomes a Script, `.client.lua` a LocalScript). Copy-paste is
still fine; the two approaches produce the same tree.
