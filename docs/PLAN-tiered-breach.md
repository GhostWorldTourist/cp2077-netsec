# Plan: four tiers, a replaced board, and a lease that survives being used

Written before implementing, criticised in the same document, then built. The
criticism section is the useful half — most of it changed the plan.

## What was asked for

1. Four tiers rather than three; cameras earn their own.
2. Breaching people — confirm it is reachable for us.
3. Replace the vanilla programs rather than adding to them, because past ~4
   programs the minigame solves itself.
4. Reset every breach lease when any new breach happens.
5. Do not tier the alarm.

## P0 — the blocker nobody asked me to fix

**Devices did not unlock, and the three-ring design was not why.** The rings are
INT gates; a breach calls `UnlockAll`, which stamps devices, defences and people
together. So devices should have opened with the Claws.

The measurement that explains it: those devices **ping-resolve to the placed
access point**. That means adoption already claimed them — and adoption is what
broke the unlock, in two places:

**(a) `AnyAccessPointResolves` is polluted by our own wrap.** It calls
`GetAccessPoints()`, which `Adopt.reds` wraps to *append* the adopted access
point. So the moment a device is adopted it starts reporting a resolvable access
point, `Devices.reds` concludes it is not stranded, and `strandedOpen` can never
fire again. The function that decides "is this device abandoned" is answered by
the code that un-abandons it.

**(b) The stranded registry is look-driven.** Devices are registered inside the
`GetAccessPoints()` wrap, which runs when the quickhack list is built — i.e.
when the player aims at the device. You breach *before* you look. Identical in
shape to the NPC registry bug fixed in 1.6.0, and it survived because the device
half was never re-examined.

Fix: ask the registry, not the wrapped accessor — a device known to have been
adopted **is** stranded by definition. And register devices eagerly at
`ScriptableDeviceComponentPS.GameAttached()` (confirmed wrappable), so the set at
breach time is what is streamed in rather than what has been looked at.

## P1 — four tiers

`NetSecTarget` gains `Camera = 3`. Existing values keep their numbers, so nothing
that logs `EnumInt` changes meaning.

`m_netSecUnlockCamera` **already exists and is already stamped** — v0.1 shipped
four fields and the camera one was deliberately retained when the rings merged.
Splitting them back out costs no save break.

`SurveillanceCameraControllerPS` is a sibling of `SecurityTurretControllerPS`
under `SensorDeviceControllerPS`, so testing for it before the turret test is
safe and neither shadows the other. New `intCameras` sits at 5, between devices
(4) and defences (6).

## P2 — four daemons that replace the board

Four `MinigameAction` records, one per ring, each with its own `Interactions`
record and its own LocKey in NetSec's onscreens archive.

When `requireAccessDaemon` is on, the three Datamines are removed and the four
unlock daemons take their place. When it is off, the board is left **completely**
alone — the daemon is not decoration any more, it is absent.

## P3 — a lease that survives being used

`@addField(PlayerPuppetPS) persistent m_netSecLastBreachAt`. A hold is live if
its own lease has not run out, **or** the last breach anywhere is inside the
lease and the hold was still live when that breach happened. Devices refresh
their own stamp forward when observed live, so repeated breaching chains.

Default duration 1h → 2h.

---

# Criticism

Written by re-reading the plan looking for what it would do wrong. Six of these
changed it.

### 1. Removing the Datamines can break quests — CHANGED THE PLAN

There are quest daemons on the same board. A plan that says "remove the
datamines" would strip a quest-critical program and soft-lock a mission, and it
would do it rarely enough to look like something else entirely.

**CORRECTED AFTER THE FACT.** This section originally named
`Gameplay-Devices-Interactions-NetworkDataMineLootQ003` as the record at risk.
That is an *Interactions* record - the caption - not the MinigameAction, and I
took it from a LocKey secondaryKey without checking. The real quest programs are
named in the shipped scripts, and there are only three in the whole game:

    MinigameAction.NetworkLootQ003          accessPointController.script:434
    MinigameAction.NetworkLootMQ015Recipe   scriptedPuppet.script:811
    minigame_v2.FindAnna                    accessPointController.script:443

The guard is right for the right reason regardless - it removes three exact
generic IDs and nothing else, so none of those three can be touched. But the
risk is far smaller than this section claimed: three scripted moments, not a
standing hazard on every quest breach.

**Only ever remove the three generic loot daemons by exact ID** —
`NetworkDataMineLootAll`, `...Advanced`, `...Master`. Anything else on the board
is somebody's quest and is not ours to touch.

### 2. Emptying the board is a hard lock — CHANGED THE PLAN

If the four records fail to load, the removal still runs and the player gets a
board with nothing on it and no way to open anything, ever.

**Remove nothing until at least one daemon has actually been inserted.** The
removal is conditional on the insertion having succeeded, in that order.

### 3. Partial offers are worse than no offer — CHANGED THE PLAN

With one daemon the fallback was simple: not offered, unlock everything as
before. With four, a target could be offered two and drop two, and the player
gets a silently partial network with no way to tell that from "I only uploaded
two."

**The offered set is all-or-nothing.** If fewer than four were offered, the
breach reverts to the old single-unlock rule and says so in the log. A confusing
subset is never granted.

### 4. `UnlockAll` is now wrong on the success path — CHANGED THE PLAN

Both breach paths call `NetSecState.UnlockAll`. In tiered mode that hands over
every ring regardless of what was uploaded, which makes the daemons decoration
again — exactly the bug 1.1.0 fixed for the single daemon and would reintroduce
fourfold.

Success must grant **only the uploaded rings**. `UnlockAll` survives solely as
the fallback path.

### 5. The People tier has no devices to stamp — CHANGED THE PLAN

Rings for devices are stamped on device PS. People are not devices; they are
opened through `m_netSecExposedAt` and the proximity rule. Uploading the People
daemon has to reach `StationedNear` and stamp those puppets, or the tier will
appear to do nothing while three others work.

### 6. Complexity has to come from somewhere

tohuw has said complexity is not the issue and to leave it alone, so I am not
picking numbers. Each daemon clones `NetworkDataMineLootAll`, whose complexity is
whatever the base game ships and is demonstrably completable on a real board.
Cloning the proven record is the same reasoning that fixed the daemon in 1.3.

### 7. Things I considered and rejected

**A generation counter instead of timestamps** for the lease chain. Correct, and
it invalidates every existing save's stamps. Not worth it.

**Storing the chain clock on the session** rather than persistently. Simpler, no
new field, but the chain dies on every load — and "my access lapsed because I
reloaded" is indistinguishable from a bug.

**Keeping one Datamine so access still competes with money.** Arbitrary — why
the basic one? The honest framing is that in tiered mode the choice is *which
parts of this network you take*, and breaching for money is what the switch being
off is for.

### 8. Consequence to state plainly

Tiered mode **removes the eurodollar income from breaching**. That is a real
economic change, not a side effect, and the switch is how someone declines it.
