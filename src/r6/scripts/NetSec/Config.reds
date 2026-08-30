// ============================================================================
// NetSec - Configuration
// ============================================================================
//
// Even gonks employ a little netsec.
//
// ---------------------------------------------------------------------------
// CREDIT
//
// NetSec stands on two mods and would not exist without either:
//
//   Better Netrunning        by finley243
//   Better Netrunning Fix    by Kei Sagano, who kept it alive across game
//                            patches long after the original stopped building
//
// Used under the original's modification permission, with credit and with
// thanks. The IDEA is theirs - quickhacking as an access problem rather than a
// resource one - and it is a good enough idea to be worth rebuilding around.
//
// This is a REWRITE rather than a patch: the mechanic is the same, almost none
// of the code is. Where NetSec differs, it is usually because Better Netrunning
// had already found the shape of the problem and NetSec could start from there
// instead of from nothing.
//
// (An earlier version of this header credited Better Netrunning Fix to
// "dodecadevin". That was wrong. It is Kei Sagano's work.)
// ---------------------------------------------------------------------------
//
// ---------------------------------------------------------------------------
// WHY THERE IS NO CET, NO LUA AND NO DATABASE HERE
//
// Better Netrunning carries 1,355 lines of Lua across five files, a sqlite
// database, and a Lua-to-redscript settings bridge, to do four jobs: define
// four TweakDB records, draw a settings screen, persist those settings, and
// run remote breach. NetSec does none of those things that way.
//
// Settings are plain redscript fields carrying ModSettings annotations. The
// Mod Settings framework reads them, draws the screen itself, and writes the
// values into this class's defaults at load - so `new NetSecConfig()` simply
// returns what the user chose. That deletes the Lua, the database, the bridge,
// and the CET dependency outright, and it puts the settings in `user.ini`
// where they can be read, diffed and version-controlled like anything else.
//
// The cost is real and worth stating: ModSettings cannot draw the richer
// controls Native Settings can, and it is a different dependency rather than
// no dependency. That trade is deliberate.
// ============================================================================

module NetSec.Config

public class NetSecConfig {

  // ===========================================================================
  // Access - the core rule
  // ===========================================================================

  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Access")
  @runtimeProperty("ModSettings.category.order", "1")
  @runtimeProperty("ModSettings.displayName", "Enable NetSec")
  @runtimeProperty("ModSettings.description", "Master switch. Off means vanilla quickhack rules - nothing is gated behind a breach.")
  let enabled: Bool = true;

  // THE ONE THAT MAKES THE MECHANIC HONEST.
  //
  // A device on a network with an access point is locked until that access
  // point is breached. A device with no access point anywhere on its network
  // cannot be unlocked by any amount of work, so by default it is simply open -
  // otherwise the world contains devices that exist only to refuse you.
  //
  // Turn this off if you would rather those devices stay shut. That is a
  // coherent choice; it is just a harsher one.
  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Access")
  @runtimeProperty("ModSettings.displayName", "Unlock devices with no access point")
  @runtimeProperty("ModSettings.description", "ON: a device whose network has no access point is hackable without a breach - there is nothing to breach. OFF: it stays locked forever.")
  let unlockWhenNoAccessPoint: Bool = true;


  // A JACK-IN PORT FOR A NETWORK WITH NO DOOR.
  //
  // Breach Protocol as a quickhack was REMOVED from the base game in 2.0. It
  // survives in TweakDB as an orphaned record - which is why other mods clone
  // it as a template - but a player cannot use it. So the only way into any
  // network is to physically jack into something, and a device whose network
  // offers nothing to jack into is not difficult, it is sealed.
  //
  // A satellite dish on this install carries a breach marker on the minimap,
  // sits on a network, and has no port and no reachable access point. The game
  // promises an entrance and does not provide one. This grants that specific
  // shape a port of its own, and nothing else: a device whose network HAS a
  // reachable access point is left exactly as it was, because finding that
  // access point is the game.
  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Access")
  @runtimeProperty("ModSettings.displayName", "Give stranded breach points a jack-in port")
  @runtimeProperty("ModSettings.description", "ON: a locked device whose network has no reachable access point gets a physical jack-in port, so a sealed network always has one way in. Devices on networks you CAN reach are untouched. OFF: a network with no reachable entrance stays sealed.")
  let grantStrandedJackIn: Bool = true;

  // HOW FAR A BREACH REACHES INTO A STRANDED NETWORK.
  //
  // Only ever applied to devices that are stranded - gated, on a network, and
  // unable to resolve a single access point in the world. A device with a
  // reachable access point is untouched at any distance, because walking to
  // that access point is the game.
  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Access")
  @runtimeProperty("ModSettings.displayName", "Stranded-network breach radius (m)")
  @runtimeProperty("ModSettings.description", "A breach opens STRANDED devices within this many metres - ones whose own network has no reachable access point. Devices on networks you can reach are never affected.")
  @runtimeProperty("ModSettings.step", "5")
  @runtimeProperty("ModSettings.min", "0")
  @runtimeProperty("ModSettings.max", "200")
  let strandedBreachRadius: Int32 = 50;

  // ADOPTION: a stranded device joins a real access point network.
  //
  // Replaces the radius fallback with actual membership. The device reports the
  // access point among its own, the access point reports the device among its
  // slaves, and vanilla RefreshSlaves propagates a breach to it through the base
  // game code path. Only ever applies where the device own access points cannot
  // be resolved in the world.
  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Access")
  @runtimeProperty("ModSettings.displayName", "Adopt stranded devices onto a nearby access point")
  @runtimeProperty("ModSettings.description", "ON: a device whose own network has no reachable way in joins the nearest real access point, so breaching that access point opens it through the game own network propagation. Devices with a reachable access point are never touched.")
  let adoptStrandedDevices: Bool = true;

  // GUARDS ARE SECURITY. PASSERS-BY ARE NOT.
  //
  // "An NPC on no network is freely hackable" was written for a lone gonk in an
  // alley and quietly applied to four gangers standing around a stash. The game
  // never wired those four to anything, so NetSec read them as unprotected and
  // they could be fried from the roof opposite - while the crate beside them,
  // adopted onto a nearby access point, had gone dark. Same yard, two rules.
  //
  // This puts stationed people behind the nearest access point exactly as
  // stranded devices already are, and it is what makes a failed breach able to
  // reach anybody: the alarm goes to the network, so people have to BE on it.
  //
  // Stationed is the game's own answer rather than a guess - not crowd
  // population, not a civilian reaction preset, not sitting in a vehicle.
  // Pedestrians, traffic and bystanders are untouched at any distance; they
  // were never guarding anything. Someone with no access point within reach
  // stays open, because there would be nothing to breach.
  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Access")
  @runtimeProperty("ModSettings.displayName", "Stationed NPCs are on the local network")
  @runtimeProperty("ModSettings.description", "ON: guards and gangers posted near an access point are locked behind it, like the devices around them, and a failed breach brings them down on you. Pedestrians, drivers and civilians are never affected. OFF: anyone the game did not wire to a network is freely hackable.")
  let protectStationedNPCs: Bool = true;

  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Access")
  @runtimeProperty("ModSettings.displayName", "Adoption radius (m)")
  @runtimeProperty("ModSettings.description", "How far an access point reaches when adopting stranded devices and stationed people.")
  @runtimeProperty("ModSettings.step", "5")
  @runtimeProperty("ModSettings.min", "5")
  @runtimeProperty("ModSettings.max", "200")
  let adoptionRadius: Int32 = 50;

  // THE ALARM. Everyone knows quickhacks exist, and everyone is afraid of them.
  //
  // The design this mod is for: netrunning should be RISKY and the payoff huge.
  // Vanilla makes quickhacks a win button - you fry a room from behind a wall
  // and nothing ever comes back at you. A network that notices you and sends
  // people to kill you is what turns a win button into a gamble worth taking.
  //
  // So a failed breach does not merely deny access. It tells the people nearby
  // that a netrunner is working on them, and points them at the player. They
  // come running, because the alternative is that they and everyone they know
  // die to something they never saw.
  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Consequences")
  @runtimeProperty("ModSettings.displayName", "A failed breach raises the alarm")
  @runtimeProperty("ModSettings.description", "ON: blowing a breach tells everyone in range where you are and sends them after you. OFF: a failed breach only costs you the access.")
  let failureRaisesAlarm: Bool = true;

  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Consequences")
  @runtimeProperty("ModSettings.displayName", "Alarm radius (m)")
  @runtimeProperty("ModSettings.description", "How far the alarm carries. Deliberately larger than the adoption radius: a tripped net brings the whole building, not the nearest room.")
  @runtimeProperty("ModSettings.step", "10")
  @runtimeProperty("ModSettings.min", "10")
  @runtimeProperty("ModSettings.max", "300")
  let alarmRadius: Int32 = 120;

  // WHOSE NET IS IT. A Maelstrom walking past does not care that some Tyger
  // Claws are being hacked - not his problem, not his crew, not his net.
  //
  // The alarm is a NET SIGNAL, not an omniscient alert state, and that boundary
  // is the feature. It travels to the people whose network was touched, so
  // breaching in contested turf pulls one gang and leaves the other watching.
  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Consequences")
  @runtimeProperty("ModSettings.displayName", "Only the owning crew answers the alarm")
  @runtimeProperty("ModSettings.description", "ON: the alarm reaches only NPCs of the same affiliation as the crew holding the access point. OFF: everyone in range answers, including passers-by who have no stake in it.")
  let alarmSameFactionOnly: Bool = true;

  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Access")
  @runtimeProperty("ModSettings.displayName", "Ping is always available")
  @runtimeProperty("ModSettings.description", "Ping stays usable on locked targets. You are still a netrunner; you just cannot fry anyone yet.")
  let alwaysAllowPing: Bool = true;

  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Access")
  @runtimeProperty("ModSettings.displayName", "Whistle is always available")
  @runtimeProperty("ModSettings.description", "Distraction hacks stay usable on locked NPCs.")
  let alwaysAllowWhistle: Bool = false;

  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Access")
  @runtimeProperty("ModSettings.displayName", "Distract is always available")
  @runtimeProperty("ModSettings.description", "Distraction hacks stay usable on locked devices.")
  let alwaysAllowDistract: Bool = false;

  // ===========================================================================
  // Duration
  // ===========================================================================

  // Measured in IN-GAME hours against the game clock, not wall clock. Six
  // in-game hours is a meaningful stretch of a day, not a coffee break.
  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Duration")
  @runtimeProperty("ModSettings.category.order", "2")
  @runtimeProperty("ModSettings.displayName", "Access lasts (in-game hours)")
  @runtimeProperty("ModSettings.description", "How long a breached network stays open, measured from your LAST breach anywhere - keep working and you keep what you hold. 0 means permanent.")
  @runtimeProperty("ModSettings.step", "1")
  @runtimeProperty("ModSettings.min", "0")
  @runtimeProperty("ModSettings.max", "72")
  let unlockDurationHours: Int32 = 2;

  // ===========================================================================
  // Progression - Intelligence
  // ===========================================================================
  //
  // Better Netrunning could gate on cyberdeck quality and enemy rarity as well.
  // Both were off on the install this was written for, and three overlapping
  // gates make it impossible to tell WHY a hack is unavailable. NetSec gates on
  // Intelligence only. If cyberdeck tiers come back it will be as a replacement
  // for this, not a third condition stacked on top.

  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Progression")
  @runtimeProperty("ModSettings.category.order", "3")
  @runtimeProperty("ModSettings.displayName", "Gate hacks behind Intelligence")
  @runtimeProperty("ModSettings.description", "Breaching opens the network; Intelligence decides which hacks you are good enough to use on it. Off means a breach opens everything.")
  let progressionEnabled: Bool = true;

  // THREE RINGS, and the line between them is "can it kill you?".
  //   Devices  - doors, computers, terminals, cameras. A camera is a SENSOR:
  //              it feeds the defence, it does not shoot.
  //   Defences - turrets, drones, mechs. Things with weapons.
  //   People   - everyone.
  // Each ring gets a one-sentence justification, which is the test a tier
  // should pass. Four categories could not state one for cameras.
  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Progression")
  @runtimeProperty("ModSettings.displayName", "INT - devices (doors, terminals)")
  @runtimeProperty("ModSettings.step", "1")
  @runtimeProperty("ModSettings.min", "3")
  @runtimeProperty("ModSettings.max", "20")
  let intDevices: Int32 = 4;

  // A camera is not a weapon and it is not a door. It is the site's eyes, and
  // taking them is what turns a guarded place into a passable one - so it prices
  // between the two.
  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Progression")
  @runtimeProperty("ModSettings.displayName", "INT - cameras")
  @runtimeProperty("ModSettings.step", "1")
  @runtimeProperty("ModSettings.min", "3")
  @runtimeProperty("ModSettings.max", "20")
  let intCameras: Int32 = 5;

  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Progression")
  @runtimeProperty("ModSettings.displayName", "INT - defences (turrets, drones, mechs)")
  @runtimeProperty("ModSettings.step", "1")
  @runtimeProperty("ModSettings.min", "3")
  @runtimeProperty("ModSettings.max", "20")
  let intDefences: Int32 = 6;

  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Progression")
  @runtimeProperty("ModSettings.displayName", "INT - covert hacks on people")
  @runtimeProperty("ModSettings.step", "1")
  @runtimeProperty("ModSettings.min", "3")
  @runtimeProperty("ModSettings.max", "20")
  let intNPCsCovert: Int32 = 4;

  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Progression")
  @runtimeProperty("ModSettings.displayName", "INT - damage hacks on people")
  @runtimeProperty("ModSettings.step", "1")
  @runtimeProperty("ModSettings.min", "3")
  @runtimeProperty("ModSettings.max", "20")
  let intNPCsCombat: Int32 = 5;

  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Progression")
  @runtimeProperty("ModSettings.displayName", "INT - control hacks on people")
  @runtimeProperty("ModSettings.step", "1")
  @runtimeProperty("ModSettings.min", "3")
  @runtimeProperty("ModSettings.max", "20")
  let intNPCsControl: Int32 = 6;

  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Progression")
  @runtimeProperty("ModSettings.displayName", "INT - ultimate hacks on people")
  @runtimeProperty("ModSettings.step", "1")
  @runtimeProperty("ModSettings.min", "3")
  @runtimeProperty("ModSettings.max", "20")
  let intNPCsUltimate: Int32 = 9;

  // ===========================================================================
  // The access daemon
  // ===========================================================================
  //
  // ON by default, and it was off for most of this mod's life for a reason that
  // has since expired: a setting able to lock every network in the game should
  // be one somebody chose, and until the daemons had been seen working in a real
  // breach nobody had chosen anything.
  //
  // They have now, repeatedly, and every failure mode leans open - no access
  // point means open, an incomplete offer stands tiering down, the deepest ring
  // is always on the board. The other reason to hold it back was that tiering
  // removed the Datamines and with them the money; ringsPayOut settled that.
  //
  // Leaving it off would have shipped a mod whose entire description is about
  // rings, to a player who would never see one.
  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Access")
  @runtimeProperty("ModSettings.displayName", "Tiered breaching (ring daemons)")
  @runtimeProperty("ModSettings.description", "ON: the breach screen offers rings of the network - devices, cameras, defences, everything - and you get the ring you upload plus everything under it. OFF: the vanilla board is left alone and completing any breach opens the whole network.")
  let requireAccessDaemon: Bool = true;

  // ===========================================================================
  // Consequences
  // ===========================================================================
  //
  // Failing a breach should cost, and it should cost the way forcing a lock
  // costs: noise at the site, the console trips instantly, and the call chain
  // starts. Security 20 m away hustles over. In a world where people fry brains
  // by thinking about it, netsec is not going to be *worse* than a factory's.
  //
  // Vanilla already does the first part - a failed breach calls
  // SendMinigameFailedToAllNPCs() and the room notices. Better Netrunning
  // deliberately SUPPRESSED that, trading it for a slow interruptible trace.
  // NetSec keeps vanilla's alert by simply not removing it, and adds the
  // escalation on top.

  // BREACHING SHOULD STILL PAY. Taking the Datamines off the board took the
  // eurodollars with them, and "netrunning is now strategic AND broke" was not
  // the trade. A ring hands you what the equivalent Datamine would have: deeper
  // ring, better haul, at the base game's own rates.
  //
  // Off means the harder game - you breach for access and nothing else, and
  // money comes from somewhere that is not the net.
  // A breach opens the network; Intelligence decides what you can do on it.
  // Those are two gates and the player sees one outcome - a quickhack still grey
  // after a breach they just won. Saying so on screen is the difference between
  // a rule and a bug report.
  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Access")
  @runtimeProperty("ModSettings.displayName", "Announce what a breach got you")
  @runtimeProperty("ModSettings.description", "Puts a line on screen after a successful breach naming the rings you took, and any that your Intelligence is not high enough to use yet.")
  let announceAccess: Bool = true;

  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Access")
  @runtimeProperty("ModSettings.displayName", "Rings pay out like Datamines")
  @runtimeProperty("ModSettings.description", "ON: uploading a ring pays what the matching Datamine would have - eurodollars, components at DEF, a shard chance at ALL. OFF: breaching buys access only.")
  let ringsPayOut: Bool = true;

  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Consequences")
  @runtimeProperty("ModSettings.category.order", "4")
  @runtimeProperty("ModSettings.displayName", "A failed breach reboots the network")
  @runtimeProperty("ModSettings.description", "Losing a breach also revokes access you already held here. Someone noticed and restarted the system from clean storage - which is the same reason access expires at all.")
  let failureRevokesAccess: Bool = true;

  // ===========================================================================
  // Diagnostics
  // ===========================================================================

  @runtimeProperty("ModSettings.mod", "NetSec")
  @runtimeProperty("ModSettings.category", "Diagnostics")
  @runtimeProperty("ModSettings.category.order", "9")
  @runtimeProperty("ModSettings.displayName", "Log decisions to the game log")
  @runtimeProperty("ModSettings.description", "Writes one tagged line per locked target saying WHICH rule locked it. Tally them afterwards to find out whether \"no access point\" is rare or everywhere - see the README.")
  let debugLogging: Bool = false;
}
