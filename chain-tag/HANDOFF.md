# Chain Tag — project handoff

Paste this file at the start of a new AI session to hand over the project.
It replaces the older handoff doc; the code layout described here is what is in
`chain-tag/src`.

## The game

Round-based chain tag (Roblox, Luau).

* One player is the seeker and starts at **Seeker Spawn** (red). Everyone else
  are runners and start at **Runner Spawn** (blue).
* Seekers get an 8 second freeze at the start so runners can scatter.
* A seeker within 6 studs of a runner, with line of sight, catches them: a red
  3-2-1 plays on every screen, then the chain plus the new prisoner is pulled
  back to Seeker Spawn and released. Losing position on every catch is what
  keeps the seeker team from steamrolling.
* **The chain is a line of at most four.** Overflow catches become Support
  Seekers - free-roaming, no formation bonus, Radar at half cooldown. A chain
  in formation is FASTER than four loose seekers, which is the whole balance:
  it is a prize the seekers hold by moving as a unit, so stretching it costs
  speed and snapping it costs the bonus. Past 38 studs for 1.1s a link snaps,
  the tail detaches into Support Seekers, the member holding the front half
  recoils, and the nearest runner takes 30 points and a ChainBreaks stat.
  A Support Seeker refills the gap after four seconds. All of it is in
  ChainService and all of it is server-authoritative.
* Seekers win by catching everyone before the timer. If one runner is still
  free when it hits zero, runners win.
* With 30 seconds left the remaining runners are outlined through walls for the
  seeker team; the last runner gets a marker everyone can see.

Three systems give the map itself something to do, all in `MapEvents` and all
placed at runtime by raycasting for flat ground - nothing in the map needs
tagging or marking:

* **Energy crystals** - eight pickups, each rolling its own rarity when it
  lands: Common 62%, Rare 26%, Epic 9%, Legendary 3%. Legendary announces
  itself to the whole server, so it is an event rather than a better drop.
  Rarity is communicated by colour alone, reused across the crystal, its
  burst, the card and the aura. Seekers get `Pickups.SeekerScale` of the
  speed reward.
* **Store** - Points buy trails, auras, chain colours and titles from
  `Config.Shop.Items`. Cosmetic only, deliberately. Ownership is a comma
  separated string attribute (`OwnedItems`) plus one `Equipped<Kind>` per
  slot, all saved with the stats. Spending reduces `Points` but never
  `TotalPoints`, which is what levels read.
* **Beacon** - a marked circle that moves every 35s and pays runners a point a
  second for standing in it. Pulls people out of the corners and tells seekers
  where to look. The HUD carries a needle pointing at it.
* **Powerups** - Dash for everyone, Radar for seekers, Vanish for runners, on
  slots 1 and 2. Cooldowns are counted on the server and written to
  `AbilityReady_<Name>` attributes; the bar only draws them. The dash impulse
  itself is applied by the owning client, since a shove pushed from the server
  stutters. Vanish is the counter to Radar by design.
* **Prison breaks** - hold your ground next to the end of a chain for four
  seconds to free that player. They get three seconds of immunity. Only chain
  ends, once per player per round, and locked out during the endgame reveal.
  `Config.Rescue.Enabled = false` removes it cleanly.

## Map

Baked into Workspace (roughly 400x400 grass base, top at y=0): fountain, loop
path, playground, picnic zone, formal garden, grove, lamp posts, trees,
flowers, invisible boundary walls. Decor has `CastShadow = false`.

Two `SpawnLocation`s named exactly `Seeker Spawn` and `Runner Spawn`, both with
`Enabled = false` and `Neutral = true` — the round script does the spawning.
If either is missing, `GameSetup` creates a grey placeholder and warns in the
Output window.

Part count is high. Merging repeated decor into MeshParts is the remaining
performance job; nothing in the code depends on how the map is built.

## Code

Seven scripts. Setup instructions, exact names and a test checklist are in
`chain-tag/README.md`.

```
ReplicatedStorage
  ChainTagConfig       ModuleScript  every tunable number, nothing else
  ChainTagShared       ModuleScript  remotes + state folder + shared helpers
  ChainTagRemotes      Folder (runtime): CatchCountdown, Toast
  ChainTagState        Folder (runtime): the attributes the HUD reads

ServerScriptService
  GameSetup            Script  round loop, roles, spawning, scoring, saved stats
  CatchDetection       Script  proximity tagging + the catch sequence
  MapEvents            Script  pickups, beacon, rescue (optional, self-contained)
  Powerups             Script  the three abilities and their cooldowns
  ChainService         ModuleScript  chain order, tension, breaks, chain speed
  Shop                 Script  purchases, equipping, ownership

StarterPlayer/StarterPlayerScripts
  Sprint               LocalScript  sprint, stamina, stamina bar, mobile button
  ChainTagUI           LocalScript  the whole HUD
  ChainVisuals         LocalScript  chain, outlines, leash, danger glow, map props
  ScoreboardUI         LocalScript  Tab scoreboard and the results panel
  AbilityBar           LocalScript  ability buttons, cooldown sweeps, dash impulse
  ShopUI               LocalScript  the store panel
  ChainTagSettings     LocalScript  settings panel and the quality dial

Workspace
  ChainTagMap          Folder (runtime): pickups and the beacon
```

## Performance model

Everything a client draws runs through one quality level (Low/Medium/High),
auto-detected on the first join by sampling real frame time for four seconds
rather than guessing from the device. It scales chain links, draw distances,
aura orb counts, the pickup burst, speed streaks, screen shake and head
titles. It never touches gameplay - Low is a shorter chain, never a shorter
cooldown - so turning settings down can never be an advantage.

Client work is split by cadence. Ten times a second: anything that scans all
players or walks a character's descendants (vanish fade, aura assignment,
trail toggling, nearest-seeker danger). Every frame: only moving parts that
already exist (chain links, aura orbs, crystal spin) plus the chain leash,
which has to be per frame because it feeds walk speed.

Server side: the tag sweep and the map sweep both run at 10 Hz, the
line-of-sight raycast filter is cached and invalidated on join/leave/respawn
rather than rebuilt per tick, and the Settings remote is throttled per player
and re-validated by round-tripping through parse/serialize.

**StreamingEnabled cannot be set from a script.** It is a Workspace property
and it is the biggest single win available for this map; GameSetup warns in
Output when it is off and the map is large.

## Conventions that matter

* **Roles** are player attributes: `IsSeeker`, `InRound`, `Frozen`,
  `ChainedTo` (the catcher's UserId). Server writes, everyone reads.
* **Round state** is attributes on `ReplicatedStorage.ChainTagState`: `Phase`
  (`Waiting`/`Intermission`/`Starting`/`Round`/`Results`), `PhaseEndsAt`
  (server clock), `RunnersLeft`, `TotalRunners`, `SeekerCount`, `Winner`,
  `ResultText`, `EndgameReveal`, `LastRunnerUserId`, `CatchesInProgress`,
  `SoloPractice`, `PlayersNeeded`, `BeaconActive`, `BeaconPosition`.
  Attributes replicate by themselves, so the HUD needs no per-second
  RemoteEvent.
* **Timers** use `workspace:GetServerTimeNow()` on both sides. The client never
  runs its own countdown.
* **Freezing** is the `Frozen` attribute, which the client movement script
  obeys. The server does not fight the client over `WalkSpeed`. The 3 second
  catch countdown additionally anchors the HumanoidRootPart.
* **`CT_` attributes** (`CT_ChainSlow`, `CT_ChainTaut`, `CT_Danger`) are written
  by `ChainVisuals` on the local client only and read by the other two
  LocalScripts. They do not replicate.
* `_G.GameActive` is still set by `GameSetup` for older scripts, but nothing in
  this codebase reads it.

## Two deliberate changes from the original build

1. **Catching is proximity based, not `.Touched`.** A 10 Hz distance check plus
   one raycast for line of sight. `.Touched` missed fast passes, double-fired,
   and let people tag through thin walls.
2. **The chain is not physics.** No `RopeConstraint`s, no welded parts. Each
   client draws the chain locally and both ends are slowed as they drift apart
   (`Config.Chain.SlowStart` .. `MaxDistance`). Ropes between two player
   characters are a tug of war between two machines' physics ownership, which
   is what made long chains jostly and occasionally launched people.

## Working

Round loop with all five phases; head start; proximity catching gated to the
Round phase; 3-2-1 countdown; chain drawing and leash; win/lose both ways with
a result banner and survivor names; early finish when the last runner is
caught; on-screen timer, phase, runners-left counter and pips; catch feed;
danger vignette; endgame reveal and last-runner marker; sprint and stamina
(mobile button included); teams; Points/Catches on the player list with
DataStore saving; mid-round joiners sit out and join next round; seeker leaving
promotes a replacement; solo practice round when `MinPlayers = 1`; energy
crystals, the roaming beacon with an on-screen needle, prison breaks with an
immunity window, a Tab scoreboard that opens itself on the results, two
server-checked powerup slots, levels from total points, catch streaks, and the
screen feedback around them - 3-2-1-GO, catch shake and flash, sprint streaks
and floating point popups.

## What is NOT built, and why

There is a much larger design brief for this game covering nine game modes,
five maps, map voting, spectating, parties, private servers, missions, an
inventory screen, emotes, victory animations, wall running, sliding, vaulting,
ledge grabs and a seventeen-service architecture.

Almost none of that is built, deliberately. The brief's own build order says
to make one round of tag extremely fun first and expand from there, and its
own coding rule says never to replace working systems unnecessarily. What
exists is one mode (Chain Tag) taken a long way rather than nine modes taken
nowhere.

If picking that up, the honest order is:

1. **A second mode.** The round loop in `GameSetup` is currently Chain Tag
   shaped. Extracting a GameMode module with `onRoundStart`, `onCatch` and
   `checkWinCondition` is the prerequisite for Infection, Freeze Tag and the
   rest, and it is a refactor of `GameSetup` rather than new systems.
2. **Movement.** Sliding and vaulting are the highest-value additions for how
   the game feels, and they are client-predicted with server validation - the
   same shape as the dash already in `Powerups`.
3. **Spectating.** Cheap to build and it fixes the worst moment in the game,
   which is being caught early.
4. **Maps.** The code assumes nothing about the map except two spawn pads and
   walkable ground, so a second map needs no code at all.

Anything past that is scope, not craft.

## Still open

1. **Map performance** — merge repeated decor into MeshParts, cut lights.
2. **Audio** — one built-in `rbxasset://` blip pitched for each cue. Music and
   a real catch sound need ids you own. Never ship a private `rbxassetid://`.
3. **Balance passes** — `HeadStart`, `CatchRadius`, `Rescue.HoldTime` and
   `Beacon.MoveEvery` want real playtesting on the real map. All of it is in
   `ChainTagConfig`.
4. **Map cover** — the park is radial with long straight sightlines down every
   path, and the outer grass ring is empty. Runners need objects they can loop
   around to break a chase. Map building, not code, but it decides how the game
   feels.
5. **Not built on purpose** — no shop, no rank progression, no round vote.

## Style for the assistant

* The developer is fairly new to Roblox/Luau. Give complete, copy-paste-ready
  scripts, not fragments. Say exactly where each goes (service + Script vs
  LocalScript vs ModuleScript) and flag names that must match the Explorer
  exactly, like `Seeker Spawn`.
* Keep comments and prints useful for debugging.
* When something "does not work", ask what the Output window says before
  guessing.
