// ============================================================================
// NetSec - Breach state
// ============================================================================
//
// WHERE STATE LIVES, AND WHY IT MATTERS
//
// Every piece of NetSec's state is stored ON THE THING IT DESCRIBES: timestamps
// on the device's own persistent state, and one on the NPC's. The number of
// them is bounded by what you have actually breached, and the game persists and
// discards them along with the entity.
//
// Better Netrunning also kept two arrays on the PLAYER - every breached access
// point's position and a matching timestamp - to drive a 50 m radial unlock.
// Those grow for as long as you play and are walked on load. Dropping radial
// unlock deletes them.
//
// FOUR RINGS, FOUR FIELDS
//
// Devices / Cameras / Defences / People, one persistent field each.
//
// The camera field was kept stamped but unused through the versions where
// cameras were folded in with doors, rather than being deleted - dead weight
// measured in bytes, against a save break measured in somebody's playthrough.
// When cameras earned their own ring back, that decision was what made it free.
// ============================================================================

module NetSec.State

import NetSec.Config.*

// CAMERAS EARNED THEIR OWN RING, and the old test was measuring the wrong thing.
//
// An earlier version folded cameras in with doors on the rule "can it kill you?" - a camera is
// a sensor, it feeds the defence, it does not shoot. That sorts by THREAT. But
// what a breach buys is not safety from the thing, it is the thing's
// CAPABILITY, and a camera's capability is the site's awareness. Owning the
// cameras is the whole stealth game and it is nothing like opening a door.
//
// Existing values keep their numbers so every logged EnumInt still means what it
// meant, and m_netSecUnlockCamera has been sitting in the save format from the very first version
// - deliberately retained and stamped in step when the rings merged, precisely
// so this could be undone without breaking a save.
public enum NetSecTarget {
  Device = 0,
  Defence = 1,
  People = 2,
  Camera = 3,
}

// THE CHAIN CLOCK. One number, on the player, persistent.
//
// "Access lasts six hours" measured from each individual breach means a player
// working a district steadily watches their earliest footholds die while they
// are still using them. Measuring from the last breach ANYWHERE turns the lease
// into something you maintain by working: keep breaching and you keep what you
// hold; stop for the length of the lease and it all lapses at once.
@addField(PlayerPuppetPS)
public persistent let m_netSecLastBreachAt: Float;

// ============================================================================
// WHO COUNTS AS STATIONED
// ============================================================================
//
// The rule NetSec needed and did not have: a guard standing a post is part of
// the site's security and should be behind its net; a pedestrian walking past
// is not, and never was. "Everyone on no network is freely hackable" collapsed
// those two into one answer, and it was the wrong answer for the first.
//
// Three tests, all of them the game's OWN, so none of this is NetSec guessing
// at what an NPC is for:
//
//   IsCrowd()   - scriptedPuppet.script:1815. True when the character record
//                 carries the crowd flag OR the puppet's CrowdMemberComponent
//                 says it is in a crowd. This is the population system: the
//                 pedestrians, the ambient street life, the people who exist to
//                 make the city look inhabited. Exactly the "walking around"
//                 the rule is meant to exclude, named by the system that spawns
//                 them rather than inferred from behaviour.
//
//   IsCivilian() - scriptedPuppet.script:1728. The reaction preset group, one
//                 of Civilian / Police / Ganger. A bystander is not somebody's
//                 security no matter where they are standing.
//
//   GetMountedVehicle() - vehicles.script:1727. Anyone in a car is travelling
//                 through, not guarding a place. Drivers and passengers both.
//
// WHY THIS LIVES IN State AND NOT IN People, where it belongs by subject:
// Daemon.reds needs it for the session registry and People.reds imports Daemon,
// so putting it in People would close an import cycle. State is the module both
// already depend on.
//
// It is deliberately a WHITELIST OF EXCLUSIONS rather than a test for
// guard-ness. There is no "is a guard" flag; there is only a pile of things
// that are demonstrably not one. Excluding what we can name and keeping the
// rest fails toward protecting somebody who did not need it, which costs the
// player one breach - where the other direction costs them the mechanic.
public func NetSecIsStationed(pup: ref<ScriptedPuppet>) -> Bool {
  if !IsDefined(pup) { return false; }
  if pup.IsCrowd() { return false; }
  if pup.IsCivilian() { return false; }
  if IsDefined(GetMountedVehicle(pup)) { return false; }
  return true;
}

@addField(SharedGameplayPS)
public persistent let m_netSecUnlockBasic: Float;

// Kept stamped through the versions where cameras were folded in with doors,
// which is what made giving them their own ring back a free change.
@addField(SharedGameplayPS)
public persistent let m_netSecUnlockCamera: Float;

@addField(SharedGameplayPS)
public persistent let m_netSecUnlockTurret: Float;

@addField(SharedGameplayPS)
public persistent let m_netSecUnlockNPC: Float;

// PEOPLE EXPIRE TOO, and the first version got this wrong.
//
// It once read vanilla's `m_quickHacksExposed` for NPCs and its own timestamps for
// devices. Vanilla's flag has no expiry, so devices went dark after six hours
// and people stayed open forever - two different rules inside one mod, which is
// exactly the inconsistency this whole thing exists to remove. This field is
// the missing half: when the game exposes an NPC's quickhacks, NetSec records
// WHEN, and applies the same clock it applies to everything else.
@addField(ScriptedPuppetPS)
public persistent let m_netSecExposedAt: Float;

public class NetSecState {

  // The game clock, in in-game seconds. Deliberately NOT wall-clock: "six hours
  // of access" should mean six hours of Night City, so sleeping through it
  // costs you the access, and staring at a menu does not.
  public static func Now(gi: GameInstance) -> Float {
    let ts: ref<TimeSystem> = GameInstance.GetTimeSystem(gi);
    if !IsDefined(ts) { return 0.0; }
    return ts.GetGameTimeStamp();
  }

  public static func ReadStamp(ps: ref<SharedGameplayPS>, target: NetSecTarget) -> Float {
    if !IsDefined(ps) { return 0.0; }
    switch target {
      case NetSecTarget.Defence: return ps.m_netSecUnlockTurret;
      case NetSecTarget.Camera:  return ps.m_netSecUnlockCamera;
      case NetSecTarget.People:  return ps.m_netSecUnlockNPC;
      default:                   return ps.m_netSecUnlockBasic;
    }
  }

  // Stamp ONE ring. Tiered breaching grants only what was uploaded, so the
  // all-rings UnlockAll below is now strictly the fallback path.
  public static func StampRing(ps: ref<SharedGameplayPS>, target: NetSecTarget, gi: GameInstance) -> Void {
    if !IsDefined(ps) { return; }
    let now: Float = NetSecState.Now(gi);
    switch target {
      case NetSecTarget.Defence: ps.m_netSecUnlockTurret = now; break;
      case NetSecTarget.Camera:  ps.m_netSecUnlockCamera = now; break;
      case NetSecTarget.People:  ps.m_netSecUnlockNPC = now; break;
      default:                   ps.m_netSecUnlockBasic = now; break;
    }
  }

  // When did the player last breach anything, anywhere.
  public static func LastBreach(gi: GameInstance) -> Float {
    let pp: ref<PlayerPuppetPS> = NetSecState.PlayerPS(gi);
    if !IsDefined(pp) { return 0.0; }
    return pp.m_netSecLastBreachAt;
  }

  public static func RecordBreachNow(gi: GameInstance) -> Void {
    let pp: ref<PlayerPuppetPS> = NetSecState.PlayerPS(gi);
    if IsDefined(pp) { pp.m_netSecLastBreachAt = NetSecState.Now(gi); }
  }

  public static func PlayerPS(gi: GameInstance) -> ref<PlayerPuppetPS> {
    let player: ref<PlayerPuppet> = GetPlayer(gi) as PlayerPuppet;
    if !IsDefined(player) { return null; }
    return player.GetPS() as PlayerPuppetPS;
  }

  // Shared by devices and people so the two can never disagree about whether an
  // hour has passed.
  //
  // TWO WAYS TO BE LIVE. Its own lease, or the chain: the last breach anywhere
  // is inside the lease AND this hold was still live when that breach happened.
  // The second clause is what makes a working netrunner keep their footholds.
  //
  // The chain is deliberately ONE HOP from the recorded stamp rather than a
  // running total, because there is nowhere to write a running total for a
  // device nobody has looked at. Devices that ARE looked at push their own stamp
  // forward (Devices.reds), so anything actually in use chains indefinitely and
  // anything ignored eventually lapses. That asymmetry is acceptable: access you
  // never exercise is access you would not notice losing.
  public static func StampIsLive(stamp: Float, gi: GameInstance) -> Bool {
    if stamp <= 0.0 { return false; }

    let cfg: ref<NetSecConfig> = new NetSecConfig();
    if cfg.unlockDurationHours <= 0 { return true; }
    let lease: Float = Cast<Float>(cfg.unlockDurationHours) * 3600.0;

    let elapsed: Float = NetSecState.Now(gi) - stamp;
    // A negative elapsed means the clock moved backwards under us - a save
    // loaded from earlier in the timeline. Treat that as expired rather than as
    // permanent access: a stamp from a future that no longer happens should not
    // hold a network open forever.
    if elapsed < 0.0 { return false; }
    if elapsed < lease { return true; }

    let last: Float = NetSecState.LastBreach(gi);
    if last <= 0.0 || last < stamp { return false; }
    return (NetSecState.Now(gi) - last) < lease && (last - stamp) < lease;
  }

  // Is this hold alive only because of the chain? If so the caller should push
  // the stamp forward, so the next link starts from here instead of from the
  // original breach.
  public static func NeedsRefresh(stamp: Float, gi: GameInstance) -> Bool {
    if stamp <= 0.0 { return false; }
    let cfg: ref<NetSecConfig> = new NetSecConfig();
    if cfg.unlockDurationHours <= 0 { return false; }
    let lease: Float = Cast<Float>(cfg.unlockDurationHours) * 3600.0;
    let elapsed: Float = NetSecState.Now(gi) - stamp;
    if elapsed < 0.0 || elapsed < lease { return false; }
    return NetSecState.StampIsLive(stamp, gi);
  }

  public static func IsUnlocked(ps: ref<SharedGameplayPS>, target: NetSecTarget, gi: GameInstance) -> Bool {
    return NetSecState.StampIsLive(NetSecState.ReadStamp(ps, target), gi);
  }

  public static func UnlockAll(ps: ref<SharedGameplayPS>, gi: GameInstance) -> Void {
    if !IsDefined(ps) { return; }
    let now: Float = NetSecState.Now(gi);
    ps.m_netSecUnlockBasic = now;
    ps.m_netSecUnlockCamera = now;
    ps.m_netSecUnlockTurret = now;
    ps.m_netSecUnlockNPC = now;
  }

  // Someone noticed and rebooted the system from clean storage. Everything you
  // held on this device is gone.
  public static func RevokeAll(ps: ref<SharedGameplayPS>) -> Void {
    if !IsDefined(ps) { return; }
    ps.m_netSecUnlockBasic = 0.0;
    ps.m_netSecUnlockCamera = 0.0;
    ps.m_netSecUnlockTurret = 0.0;
    ps.m_netSecUnlockNPC = 0.0;
  }

  // WHERE THE WAY IN IS.
  //
  // The mod locks a device behind breaching its network and then leaves the
  // player to find the access point by eye. It never had to: GetAccessPoints()
  // is the same call that answers "is this gated at all", and it returns the
  // access points themselves. Reporting where they are turns "I don't even know
  // where this one is" into a coordinate.
  //
  // This is the whole loop the mod exists for - sneak in, breach, sneak out -
  // and withholding the destination made it a hunt rather than an infiltration.
  public static func DescribeAccessPoints(ps: ref<SharedGameplayPS>) -> String {
    if !IsDefined(ps) { return "none"; }
    let aps: array<ref<AccessPointControllerPS>> = ps.GetAccessPoints();
    if ArraySize(aps) == 0 { return "none"; }

    let out: String = "";
    let i: Int32 = 0;
    while i < ArraySize(aps) {
      let owner: ref<GameObject> = aps[i].GetOwnerEntityWeak() as GameObject;
      if IsDefined(owner) {
        let p: Vector4 = owner.GetWorldPosition();
        out += " AP" + ToString(i) + "=" + ToString(owner.GetClassName())
             + "@" + ToString(p.X) + "," + ToString(p.Y) + "," + ToString(p.Z);
      } else {
        out += " AP" + ToString(i) + "=unresolved";
      }
      i += 1;
    }
    return out;
  }

  // THE WAY IN, AS A SENTENCE THE PLAYER CAN ACT ON.
  //
  // "34 m NE" beats a coordinate in a log file, and it beats a map marker too:
  // it appears on the greyed-out quickhack, which is the thing already under
  // the crosshair when the question "so where IS it" occurs. No menu, no map,
  // no second screen.
  //
  // Bearing is compass-style from the player, because that is how somebody
  // standing in Kabuki thinks. Vanilla's north is +Y.
  public static func WayInHint(ps: ref<SharedGameplayPS>, gi: GameInstance) -> String {
    if !IsDefined(ps) { return ""; }
    let aps: array<ref<AccessPointControllerPS>> = ps.GetAccessPoints();
    if ArraySize(aps) == 0 { return ""; }

    let player: ref<GameObject> = GetPlayer(gi);
    if !IsDefined(player) { return ""; }
    let me: Vector4 = player.GetWorldPosition();

    // Nearest access point - if a network has several, the useful one is the
    // one you can reach soonest.
    let bestD: Float = -1.0;
    let bestX: Float = 0.0;
    let bestY: Float = 0.0;
    let i: Int32 = 0;
    while i < ArraySize(aps) {
      let owner: ref<GameObject> = aps[i].GetOwnerEntityWeak() as GameObject;
      if IsDefined(owner) {
        let p: Vector4 = owner.GetWorldPosition();
        let dx: Float = p.X - me.X;
        let dy: Float = p.Y - me.Y;
        let dz: Float = p.Z - me.Z;
        let d: Float = SqrtF(dx*dx + dy*dy + dz*dz);
        if bestD < 0.0 || d < bestD { bestD = d; bestX = dx; bestY = dy; }
      }
      i += 1;
    }
    // NOT STREAMED IS THE NORMAL CASE, NOT AN ERROR.
    //
    // GetAccessPoints() reads the persistent network graph, so it happily
    // returns an access point whose ENTITY is not loaded - which is exactly
    // what happens when the way in is inside a building you have not entered.
    // Measured on this install: eight locked scans, eight unresolved access
    // points. A hint that only works when the door is already in front of you
    // is a hint for the case that did not need one.
    //
    // The persistent state still answers what it IS, so say that instead. "Look
    // for a netrunner terminal" is a real instruction; "unknown" is not.
    if bestD < 0.0 {
      let named: String = "";
      let j: Int32 = 0;
      while j < ArraySize(aps) {
        let nm: String = ToString(aps[j].GetDeviceName());
        if StrLen(nm) > 0 && !Equals(nm, "None") { named = nm; break; }
        j += 1;
      }
      if StrLen(named) > 0 { return "Way in: " + named + " (not nearby)"; }
      return "Way in: elsewhere on this network";
    }

    // Eight-point compass. Comparing the two axes avoids needing atan2 and is
    // accurate enough for "which way do I walk".
    let ax: Float = AbsF(bestX);
    let ay: Float = AbsF(bestY);
    let dir: String = "";
    if ay > ax * 2.0 {
      dir = bestY > 0.0 ? "N" : "S";
    } else if ax > ay * 2.0 {
      dir = bestX > 0.0 ? "E" : "W";
    } else {
      dir = (bestY > 0.0 ? "N" : "S") + (bestX > 0.0 ? "E" : "W");
    }
    return "Access point " + ToString(RoundF(bestD)) + "m " + dir;
  }

  // IS THERE A WAY IN THAT EXISTS IN THE WORLD RIGHT NOW.
  //
  // GetAccessPoints() reads the persistent graph, so it answers "this network
  // has an entrance" even when that entrance is not loaded. Resolving the owner
  // entity is the difference between an entrance that exists on paper and one a
  // player could walk to. Measured on this install: every locked device scanned
  // reported its access points unresolvable.
  //
  // A device that is gated, on a network, and cannot resolve a single access
  // point is STRANDED - the mod is asking the player to go somewhere that is
  // not there. That is the case that earns a port of its own.
  public static func AnyAccessPointResolves(ps: ref<SharedGameplayPS>) -> Bool {
    if !IsDefined(ps) { return false; }
    let aps: array<ref<AccessPointControllerPS>> = ps.GetAccessPoints();
    let i: Int32 = 0;
    while i < ArraySize(aps) {
      if IsDefined(aps[i].GetOwnerEntityWeak() as GameObject) { return true; }
      i += 1;
    }
    return false;
  }

  // Vanilla answers this for us. A network with no access point cannot be
  // breached by any means NetSec offers, which is why the config gets a say in
  // what happens to it.
  public static func HasAccessPoint(ps: ref<SharedGameplayPS>) -> Bool {
    if !IsDefined(ps) { return false; }
    let aps: array<ref<AccessPointControllerPS>> = ps.GetAccessPoints();
    return ArraySize(aps) > 0;
  }
}
