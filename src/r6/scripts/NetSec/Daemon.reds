// ============================================================================
// NetSec - the access daemon
// ============================================================================
//
// The breach screen offers three Datamine daemons and says nothing about
// network access, because until now nothing on that screen was responsible for
// it: completing a breach at all granted access, invisibly. The reason you were
// standing at the terminal was the one thing the terminal never mentioned.
//
// In tiered mode the three Datamines come OFF the board and four rings go on in
// their place, because the board is generated to contain the sequences it
// offers - so adding an option makes every breach easier, and for eight
// versions this file did exactly that while its own comments claimed to be
// adding a price. Uploading a ring opens that ring and everything under it.
//
// With tiering off, the vanilla board is left completely alone.
//
// A DECLARED RECORD IS NOT AN OFFERED DAEMON, which is the bug this file was
// rewritten to fix. An earlier version created MinigameAction.NetSecUnlock in TweakDB and
// then only ever wrapped vanilla's filter to lift that daemon out of the
// program list and put it back afterwards - faithfully protecting something
// nothing had added. The record existed, nothing referenced it, and the breach
// screen showed the same three Datamines it always had. A screenshot settled in
// one glance what the code had asserted for a whole version.
//
// The program list is built from MinigameProgramData VALUES. To offer a daemon
// you construct one and put it in the array; declaring the record only gives
// that value something to point at.
//
// WHY INJECT AFTER wrappedMethod
//
// Vanilla's filter drops programs it does not recognise, so a daemon added
// before it runs has to be extracted and restored around it. Adding it after
// the filter has already run needs neither, and there is no window in which
// vanilla can discard it. The extract/restore dance the previous version
// performed was solving a problem this ordering does not have.
//
// IT CANNOT LOCK YOU OUT - now actually true
//
// If the daemon is not offered, `WasOffered` reports false and Breach.reds
// unlocks the network exactly as it did before. The previous version asserted
// this in a comment and did not implement it: it tested only whether the daemon
// had been UPLOADED, so with the requirement switched on and the daemon never
// appearing, every network in the game would have been permanently sealed.
// ============================================================================

module NetSec.Daemon

import NetSec.Config.*
import NetSec.State.*

// WHY A SYSTEM AND NOT A FIELD.
//
// The offer happens on the minigame rule; the decision that depends on it
// happens on the access point after the breach resolves. Those are two objects
// with no path between them, so the fact has to live somewhere both can reach.
// It is deliberately NOT persistent - "was a daemon offered in the breach you
// just finished" is a question about the last thirty seconds, and a stale true
// carried across a save load would seal a network on the strength of a breach
// from another session.
public class NetSecSession extends ScriptableSystem {

  private let m_daemonOffered: Bool;

  public final static func Get(gi: GameInstance) -> ref<NetSecSession> {
    return GameInstance.GetScriptableSystemsContainer(gi)
      .Get(n"NetSec.Daemon.NetSecSession") as NetSecSession;
  }

  public final func SetOffered(offered: Bool) -> Void {
    this.m_daemonOffered = offered;
  }

  public final func WasOffered() -> Bool {
    return this.m_daemonOffered;
  }

  // WHERE THE LAST BREACH HAPPENED.
  //
  // An access point placed into the world by a mod has no slaves: network
  // membership is baked into the sector's node data, and nothing wires a new
  // device into an existing graph. Rather than attempt that surgery, NetSec
  // supplies the wiring itself - a breach records WHERE it happened, and a
  // stranded device near that spot accepts it.
  //
  // Deliberately session-scoped and not persistent. It is a claim about the
  // last few minutes; carrying it across a save load would open networks on the
  // strength of a breach from another session.
  private let m_breachX: Float;
  private let m_breachY: Float;
  private let m_breachZ: Float;
  private let m_breachAt: Float;
  private let m_hasBreach: Bool;

  public final func RecordBreachAt(p: Vector4, now: Float) -> Void {
    this.m_breachX = p.X; this.m_breachY = p.Y; this.m_breachZ = p.Z;
    this.m_breachAt = now;
    this.m_hasBreach = true;
  }

  public final func HasBreach() -> Bool { return this.m_hasBreach; }
  public final func BreachStamp() -> Float { return this.m_breachAt; }

  // ADOPTION REGISTRY.
  //
  // Access points register as they attach; devices register the first time
  // NetSec gates them. Session-scoped by design: these describe what is
  // streamed in right now, and a stale entry would adopt a device onto an
  // access point nowhere near it.
  //
  // These live in the class body rather than arriving by @addField from
  // Adopt.reds: @addField grafts onto GAME classes, and using it on one of our
  // own produces "constant pool error: definition not found" with no hint that
  // the annotation is the problem.
  public let m_accessPoints: array<ref<AccessPointControllerPS>>;
  public let m_strandedDevices: array<ref<ScriptableDeviceComponentPS>>;
  public let m_npcs: array<ref<ScriptedPuppetPS>>;

  public final func RegisterAccessPoint(ap: ref<AccessPointControllerPS>) -> Void {
    if !IsDefined(ap) { return; }
    let i: Int32 = 0;
    while i < ArraySize(this.m_accessPoints) {
      if this.m_accessPoints[i] == ap { return; }
      i += 1;
    }
    ArrayPush(this.m_accessPoints, ap);
  }

  // People are registered as NetSec evaluates them, for the same reason devices
  // are: the failure path has to reach the NPCs a success would have opened,
  // and there is no way to enumerate them from an access point that is not
  // really on their network.
  //
  // REGISTERED BY PRESENCE, NOT BY BEING LOOKED AT - and that was the whole bug.
  //
  // This array once was filled from GetAllChoices, which runs when the
  // player opens a quickhack menu on somebody. You breach BEFORE you look at
  // people, so the registry was empty at exactly the moment the alarm needed it
  // - measured as "ALARM - 4 parts, 0 non-civilian, 0 sent". People.reds now
  // registers at OnGameAttached instead, so the set is what is STREAMED IN
  // rather than what has been aimed at.
  public final const func NPCCount() -> Int32 {
    return ArraySize(this.m_npcs);
  }

  // Stationed NPCs within reach of a point, revalidated on the way out.
  //
  // Registration happens at attach, where the reaction preset that decides
  // IsCivilian has not necessarily resolved yet and nothing knows what the
  // puppet will be doing later. So the stationed test is applied AGAIN here
  // rather than trusted from registration time: the cheap half runs once, the
  // authoritative half runs when the answer is actually used.
  public final const func StationedNear(here: Vector4, radius: Float) -> array<ref<ScriptedPuppetPS>> {
    let out: array<ref<ScriptedPuppetPS>>;
    let i: Int32 = 0;
    while i < ArraySize(this.m_npcs) {
      // The SLOT ITSELF can be null: a registered persistent state outlives the
      // puppet it describes, and dereferencing one of those crashed a breach
      // three times in testing. Every hop gets a check.
      let ps: ref<ScriptedPuppetPS> = this.m_npcs[i];
      if IsDefined(ps) {
        let pup: ref<ScriptedPuppet> = ps.GetOwnerEntityWeak() as ScriptedPuppet;
        if IsDefined(pup) && ScriptedPuppet.IsActive(pup) && ScriptedPuppet.IsAlive(pup)
           && NetSecIsStationed(pup) {
          let p: Vector4 = pup.GetWorldPosition();
          let dx: Float = p.X - here.X;
          let dy: Float = p.Y - here.Y;
          let dz: Float = p.Z - here.Z;
          if SqrtF(dx*dx + dy*dy + dz*dz) <= radius { ArrayPush(out, ps); }
        }
      }
      i += 1;
    }
    return out;
  }

  // The same set, in the currency the game's own network functions speak.
  //
  // GetPuppets() returns PuppetDeviceLinkPS, not puppets - the link is the
  // NPC's seat in the device graph, and it is what SendMinigameFailedToAllNPCs
  // addresses its event to. Handing back links is what lets an adopted NPC be
  // reached by VANILLA code rather than by a roster NetSec walks itself.
  public final const func PuppetLinksNear(here: Vector4, radius: Float) -> array<ref<PuppetDeviceLinkPS>> {
    let out: array<ref<PuppetDeviceLinkPS>>;
    let near: array<ref<ScriptedPuppetPS>> = this.StationedNear(here, radius);
    let i: Int32 = 0;
    while i < ArraySize(near) {
      let link: ref<PuppetDeviceLinkPS> = near[i].GetDeviceLink();
      if IsDefined(link) { ArrayPush(out, link); }
      i += 1;
    }
    return out;
  }

  // Is there an access point close enough that this spot is somebody's turf?
  // Answers "should a guard standing here be protected at all", which is a
  // different question from "which access point owns them".
  public final const func HasAccessPointWithin(here: Vector4, radius: Float) -> Bool {
    return IsDefined(this.NearestAccessPoint(here, radius));
  }

  public final func RegisterNPC(npc: ref<ScriptedPuppetPS>) -> Void {
    if !IsDefined(npc) { return; }
    let i: Int32 = 0;
    while i < ArraySize(this.m_npcs) {
      if this.m_npcs[i] == npc { return; }
      i += 1;
    }
    ArrayPush(this.m_npcs, npc);
    this.m_sinceSweep += 1;
    if this.m_sinceSweep >= 64 { this.Sweep(); }
  }

  public final func ClearBreach() -> Void {
    this.m_hasBreach = false;
    this.m_breachAt = 0.0;
  }

  public final func RegisterStranded(dev: ref<ScriptableDeviceComponentPS>) -> Void {
    if !IsDefined(dev) { return; }
    let i: Int32 = 0;
    while i < ArraySize(this.m_strandedDevices) {
      if this.m_strandedDevices[i] == dev { return; }
      i += 1;
    }
    ArrayPush(this.m_strandedDevices, dev);
  }

  // ONCE ADOPTED, ALWAYS STRANDED - and this is the answer to a circular
  // question that quietly broke device unlocking for several versions.
  //
  // "Is this device stranded" was asked by calling GetAccessPoints() and seeing
  // whether any access point resolved. But Adopt.reds WRAPS GetAccessPoints to
  // append the adopted access point - so the instant a device was adopted it
  // began reporting a resolvable way in, the stranded test went false, and the
  // breach path that only ever fires for stranded devices could never fire
  // again. The function deciding whether a device is abandoned was being
  // answered by the code that un-abandons it.
  //
  // The registry does not have that problem. A device is in it only because
  // adoption put it there, and adoption only ever claims something whose own
  // access points did not resolve.
  public final const func IsAdopted(dev: ref<ScriptableDeviceComponentPS>) -> Bool {
    if !IsDefined(dev) { return false; }
    let i: Int32 = 0;
    while i < ArraySize(this.m_strandedDevices) {
      if this.m_strandedDevices[i] == dev { return true; }
      i += 1;
    }
    return false;
  }

  // EVERY DEVICE THAT IS STREAMED IN, registered when it attaches.
  //
  // Same fix as the NPC registry got in 1.6.0, for the same reason and against
  // the same bug. The stranded set is filled inside the GetAccessPoints wrap,
  // which runs when the quickhack list is built - when the player AIMS at
  // something. You breach before you look, so at the moment a breach needed to
  // know which devices to open, it knew about the ones already inspected and
  // nothing else. This set is filled by presence instead.
  public let m_devices: array<ref<ScriptableDeviceComponentPS>>;

  public final func RegisterDevice(dev: ref<ScriptableDeviceComponentPS>) -> Void {
    if !IsDefined(dev) { return; }
    let i: Int32 = 0;
    while i < ArraySize(this.m_devices) {
      if this.m_devices[i] == dev { return; }
      i += 1;
    }
    ArrayPush(this.m_devices, dev);
    this.m_sinceSweep += 1;
    if this.m_sinceSweep >= 64 { this.Sweep(); }
  }

  // SWEEP OUT WHAT IS NO LONGER THERE.
  //
  // These registries are filled at attach and were never emptied, so they grew
  // for as long as the session ran - in dense districts, thousands of entries,
  // most of them describing things that streamed out hours ago, and every
  // breach walked all of them.
  //
  // That is a cousin of the thing this mod's own README criticises Better
  // Netrunning for: two arrays on the player that "grow for as long as you
  // play". Ours are session-scoped rather than saved, which is the difference
  // that matters, but publishing that table while quietly doing a version of it
  // is not a position worth defending.
  //
  // The test is whether the persistent state still resolves to a live entity.
  // A device that has streamed out fails it, and is dropped. If the player
  // comes back, GameAttached registers it again - so this costs nothing except
  // the entries it removes.
  //
  // Walking backwards so removal does not disturb the indices ahead.
  private let m_sinceSweep: Int32;

  public final func Sweep() -> Void {
    this.m_sinceSweep = 0;

    let i: Int32 = ArraySize(this.m_devices) - 1;
    while i >= 0 {
      let d: ref<ScriptableDeviceComponentPS> = this.m_devices[i];
      if !IsDefined(d) || !IsDefined(d.GetOwnerEntityWeak() as GameObject) {
        ArrayErase(this.m_devices, i);
      }
      i -= 1;
    }

    let j: Int32 = ArraySize(this.m_npcs) - 1;
    while j >= 0 {
      let n: ref<ScriptedPuppetPS> = this.m_npcs[j];
      let pup: ref<ScriptedPuppet>;
      if IsDefined(n) { pup = n.GetOwnerEntityWeak() as ScriptedPuppet; }
      // The dead are swept too. A corpse cannot answer an alarm and cannot be
      // quickhacked into doing anything useful, so keeping it costs a walk and
      // buys nothing.
      if !IsDefined(pup) || !ScriptedPuppet.IsActive(pup) || !ScriptedPuppet.IsAlive(pup) {
        ArrayErase(this.m_npcs, j);
      }
      j -= 1;
    }

    let k: Int32 = ArraySize(this.m_accessPoints) - 1;
    while k >= 0 {
      let a: ref<AccessPointControllerPS> = this.m_accessPoints[k];
      if !IsDefined(a) || !IsDefined(a.GetOwnerEntityWeak() as GameObject) {
        ArrayErase(this.m_accessPoints, k);
      }
      k -= 1;
    }

    let m: Int32 = ArraySize(this.m_strandedDevices) - 1;
    while m >= 0 {
      let sd: ref<ScriptableDeviceComponentPS> = this.m_strandedDevices[m];
      if !IsDefined(sd) || !IsDefined(sd.GetOwnerEntityWeak() as GameObject) {
        ArrayErase(this.m_strandedDevices, m);
      }
      m -= 1;
    }
  }

  public final const func DeviceCount() -> Int32 { return ArraySize(this.m_devices); }

  public final const func DevicesNear(here: Vector4, radius: Float) -> array<ref<ScriptableDeviceComponentPS>> {
    let out: array<ref<ScriptableDeviceComponentPS>>;
    let i: Int32 = 0;
    while i < ArraySize(this.m_devices) {
      let dev: ref<ScriptableDeviceComponentPS> = this.m_devices[i];
      if IsDefined(dev) {
        let owner: ref<GameObject> = dev.GetOwnerEntityWeak() as GameObject;
        if IsDefined(owner) {
          let p: Vector4 = owner.GetWorldPosition();
          let dx: Float = p.X - here.X;
          let dy: Float = p.Y - here.Y;
          let dz: Float = p.Z - here.Z;
          if SqrtF(dx*dx + dy*dy + dz*dz) <= radius { ArrayPush(out, dev); }
        }
      }
      i += 1;
    }
    return out;
  }

  // WHICH DAEMONS REACHED THE SCREEN, as a count rather than a set.
  //
  // All-or-nothing on purpose. With one daemon the fallback was simple: not
  // offered, unlock everything as before. With four, a target could be offered
  // two and drop two, and the player would get a silently partial network with
  // no way to tell that apart from having chosen to upload only two. A
  // confusing subset is worse than either outcome, so unless every ring was on
  // offer the breach reverts to the old single-unlock rule.
  // EXPECTED is not always four, and conflating the two would break the very
  // networks this is meant to tidy up. A yard with no cameras SHOULD be offered
  // three rings - that is the feature. If "did every ring reach the screen" were
  // measured against a hard four, every camera-less network in the game would
  // read as a broken offer and fall back to unlocking everything.
  //
  // So the test is offered == expected, where expected is what this target was
  // judged to have. Four means four; three means three; zero of an expected
  // three still means something is wrong.
  private let m_offeredCount: Int32;
  private let m_expectedCount: Int32;

  public final func SetOfferedCount(n: Int32) -> Void { this.m_offeredCount = n; }
  public final const func OfferedCount() -> Int32 { return this.m_offeredCount; }
  // PAID ONCE PER BREACH, whichever path gets there first.
  //
  // The payout rides vanilla's RefreshSlaves, and on an adopted access point
  // that never runs - so the dive path has to make it run. Which means two
  // routes can now reach the same payment, and their order is not something to
  // rely on. So the guard is on the PAYMENT rather than on the triggering:
  // whoever pays first marks it, and the other finds it already done.
  //
  // Reset when a breach screen is built, which is the one unambiguous "a new
  // breach is starting" signal available.
  private let m_paidThisBreach: Bool;
  public final func MarkPaid() -> Void { this.m_paidThisBreach = true; }
  public final const func HasPaid() -> Bool { return this.m_paidThisBreach; }
  public final func ResetPaid() -> Void { this.m_paidThisBreach = false; }

  public final func SetExpectedCount(n: Int32) -> Void { this.m_expectedCount = n; }
  public final const func ExpectedCount() -> Int32 { return this.m_expectedCount; }

  // Did the board come out as intended for this target?
  public final const func OfferWasComplete() -> Bool {
    return this.m_expectedCount > 0 && this.m_offeredCount >= this.m_expectedCount;
  }

  // Nearest registered access point. Null when nothing qualifies, which is the
  // ordinary case and not a failure.
  public final const func NearestAccessPoint(to: Vector4, radius: Float) -> ref<AccessPointControllerPS> {
    let best: ref<AccessPointControllerPS>;
    let bestD: Float = -1.0;
    let i: Int32 = 0;
    while i < ArraySize(this.m_accessPoints) {
      let ap: ref<AccessPointControllerPS> = this.m_accessPoints[i];
      if IsDefined(ap) {
        let owner: ref<GameObject> = ap.GetOwnerEntityWeak() as GameObject;
        if IsDefined(owner) {
          let p: Vector4 = owner.GetWorldPosition();
          let dx: Float = p.X - to.X;
          let dy: Float = p.Y - to.Y;
          let dz: Float = p.Z - to.Z;
          let d: Float = SqrtF(dx*dx + dy*dy + dz*dz);
          if d <= radius && (bestD < 0.0 || d < bestD) { bestD = d; best = ap; }
        }
      }
      i += 1;
    }
    return best;
  }

  public final func BreachDistanceFrom(p: Vector4) -> Float {
    if !this.m_hasBreach { return -1.0; }
    let dx: Float = p.X - this.m_breachX;
    let dy: Float = p.Y - this.m_breachY;
    let dz: Float = p.Z - this.m_breachZ;
    return SqrtF(dx*dx + dy*dy + dz*dz);
  }
}

public class NetSecDaemon {

  // Retained: the single-unlock daemon, still the record used when tiering is
  // off and still what the fallback path names.
  public static func Id() -> TweakDBID {
    return t"MinigameAction.NetSecUnlock";
  }

  public static func TierCount() -> Int32 { return 4; }

  public static func TierAt(i: Int32) -> NetSecTarget {
    switch i {
      case 1:  return NetSecTarget.Camera;
      case 2:  return NetSecTarget.Defence;
      case 3:  return NetSecTarget.People;
      default: return NetSecTarget.Device;
    }
  }

  public static func TierId(target: NetSecTarget) -> TweakDBID {
    switch target {
      case NetSecTarget.Camera:  return t"MinigameAction.NetSecUnlockCameras";
      case NetSecTarget.Defence: return t"MinigameAction.NetSecUnlockDefences";
      case NetSecTarget.People:  return t"MinigameAction.NetSecUnlockPeople";
      default:                   return t"MinigameAction.NetSecUnlockDevices";
    }
  }

  // RINGS ARE NESTED, NOT PARALLEL - and that is the whole mental model.
  //
  // You are not buying four separate permissions, you are getting further into
  // ONE network. Ring 3 is not "the turrets"; it is everything up to and
  // including the turrets, because you cannot be deeper in the net than the
  // turrets while still locked out of the doors.
  //
  // This was observed before it was designed: with PEOPLE uploaded and DEVICES
  // failed, the devices opened anyway - through the stranded-breach path, which
  // never consulted rings at all. That was an accident, and the right response
  // was not to close it but to make it the rule everywhere so success and the
  // failure path cannot disagree about what a ring means.
  public static func Rank(target: NetSecTarget) -> Int32 {
    switch target {
      case NetSecTarget.Camera:  return 2;
      case NetSecTarget.Defence: return 3;
      case NetSecTarget.People:  return 4;
      default:                   return 1;
    }
  }

  // Everything up to the deepest ring bought.
  public static func Cumulative(uploaded: array<NetSecTarget>) -> array<NetSecTarget> {
    let deepest: Int32 = 0;
    let i: Int32 = 0;
    while i < ArraySize(uploaded) {
      let r: Int32 = NetSecDaemon.Rank(uploaded[i]);
      if r > deepest { deepest = r; }
      i += 1;
    }
    let out: array<NetSecTarget>;
    if deepest <= 0 { return out; }
    let t: Int32 = 0;
    while t < NetSecDaemon.TierCount() {
      let tier: NetSecTarget = NetSecDaemon.TierAt(t);
      if NetSecDaemon.Rank(tier) <= deepest { ArrayPush(out, tier); }
      t += 1;
    }
    return out;
  }

  public static func TierName(target: NetSecTarget) -> String {
    switch target {
      case NetSecTarget.Camera:  return "cameras";
      case NetSecTarget.Defence: return "defences";
      case NetSecTarget.People:  return "people";
      default:                   return "devices";
    }
  }

  // THE THREE GENERIC LOOT DAEMONS, BY EXACT ID, and nothing else ever.
  //
  // Tiered mode takes the Datamines off the board to make room, and "remove the
  // datamines" is a sentence that will soft-lock somebody's playthrough if it is
  // implemented as a pattern match. The quest programs are named in the shipped
  // scripts and there are exactly three in the whole game:
  //
  //     MinigameAction.NetworkLootQ003          accessPointController.script:434
  //     MinigameAction.NetworkLootMQ015Recipe   scriptedPuppet.script:811
  //     minigame_v2.FindAnna                    accessPointController.script:443
  //
  // Note what they are NOT called. The Interactions records behind their captions
  // are NetworkDataMineLootQ003 and NetworkDataMineLootQ015Recipe, which is close
  // enough to the generic loot IDs to fool a substring match and close enough to
  // fool me - the first draft of this comment named the Interactions record as
  // the thing at risk. A player who cannot upload the quest daemon cannot finish
  // the quest, and it would happen rarely enough to look like anything but this.
  //
  // So the removal is an allowlist of three known IDs. Anything else on that
  // board belongs to somebody's mission and is not ours to touch.
  // WHAT A RING IS WORTH, IN THE GAME'S OWN CURRENCY.
  //
  // Tiered mode takes the Datamines off the board, which takes the eurodollars,
  // components and shards with them. That is a real economic hole and the fix
  // should not be invented numbers: the base game already has three tuned
  // payouts and the player already knows what they are worth.
  //
  // So a ring is paid by handing vanilla the Datamine IDs it would have paid
  // for. Cumulative, matching how the rings themselves nest - the deeper you
  // got, the more you carry out:
  //
  //     /DEVICE/           Basic
  //     /DEVICE|CAM/       Basic
  //     /DEVICE|CAM|DEF/   Basic + Advanced        (money + components)
  //     /ALL/              Basic + Advanced + Master (+ shard chance)
  //
  // Reading the vanilla payout at accessPointController.script:450 - Basic adds
  // money, Advanced adds money and sets craftingMaterial, Master adds shard
  // drop chance. Nothing here decides how much any of that is; it decides only
  // which of the three the network is judged to be worth.
  public static func LootFor(tiers: array<NetSecTarget>) -> array<TweakDBID> {
    let out: array<TweakDBID>;
    let deepest: Int32 = 0;
    let i: Int32 = 0;
    while i < ArraySize(tiers) {
      let r: Int32 = NetSecDaemon.Rank(tiers[i]);
      if r > deepest { deepest = r; }
      i += 1;
    }
    if deepest <= 0 { return out; }
    ArrayPush(out, t"MinigameAction.NetworkDataMineLootAll");
    if deepest >= 3 { ArrayPush(out, t"MinigameAction.NetworkDataMineLootAllAdvanced"); }
    if deepest >= 4 { ArrayPush(out, t"MinigameAction.NetworkDataMineLootAllMaster"); }
    return out;
  }

  public static func IsGenericLoot(id: TweakDBID) -> Bool {
    return id == t"MinigameAction.NetworkDataMineLootAll"
        || id == t"MinigameAction.NetworkDataMineLootAllAdvanced"
        || id == t"MinigameAction.NetworkDataMineLootAllMaster";
  }

  public static func WasUploaded(programs: array<TweakDBID>) -> Bool {
    let i: Int32 = 0;
    while i < ArraySize(programs) {
      if programs[i] == NetSecDaemon.Id() { return true; }
      i += 1;
    }
    return false;
  }

  // Which rings did the player actually pay for?
  public static func UploadedTiers(programs: array<TweakDBID>) -> array<NetSecTarget> {
    let out: array<NetSecTarget>;
    let t: Int32 = 0;
    while t < NetSecDaemon.TierCount() {
      let tier: NetSecTarget = NetSecDaemon.TierAt(t);
      let id: TweakDBID = NetSecDaemon.TierId(tier);
      let i: Int32 = 0;
      while i < ArraySize(programs) {
        if programs[i] == id { ArrayPush(out, tier); break; }
        i += 1;
      }
      t += 1;
    }
    return out;
  }
}

@wrapMethod(MinigameGenerationRuleScalingPrograms)
public final func FilterPlayerPrograms(programs: script_ref<array<MinigameProgramData>>) -> Void {
  // Vanilla decides its own program list first, untouched.
  wrappedMethod(programs);

  let cfg: ref<NetSecConfig> = new NetSecConfig();

  // The rule has no GetGameInstance(). It does hold the entity being breached,
  // and a GameObject knows its own game - so the instance comes from the target
  // rather than from the rule.
  let target: ref<GameObject> = this.m_entity as GameObject;
  let session: ref<NetSecSession>;
  if IsDefined(target) { session = NetSecSession.Get(target.GetGame()); }

  if !cfg.enabled {
    if IsDefined(session) { session.SetOffered(false); }
    return;
  }

  // ONLY OFFER IT WHERE IT MEANS SOMETHING.
  //
  // It once injected unconditionally, so the daemon appeared on every breach in the
  // game including targets that are on no network at all - offering to unlock
  // access to nothing. The daemon is only honest when there is a network behind
  // the target, which is the same question the device gate already asks.
  let ps: ref<SharedGameplayPS>;
  let dev: ref<Device> = this.m_entity as Device;
  if IsDefined(dev) {
    ps = dev.GetDevicePS();
  } else {
    let pup: ref<ScriptedPuppet> = this.m_entity as ScriptedPuppet;
    if IsDefined(pup) { ps = pup.GetPS().GetDeviceLink(); }
  }

  // WHICH MINIGAME DEFINITION IS THIS.
  //
  // FilterPlayerPrograms exists ONLY on MinigameGenerationRuleScalingPrograms -
  // not on the base rule, not on OverridePrograms (both probed). So a target
  // whose definition does not use that rule never reaches this function at all,
  // and the daemon is absent with no line in the log saying so. That is exactly
  // what a world-placed access point did: three options, and total silence
  // here. Logging the definition names the difference between a target this
  // hook reaches and one it does not.
  if cfg.debugLogging {
    let defName: String = "none";
    if IsDefined(ps) {
      let dps: ref<ScriptableDeviceComponentPS> = ps as ScriptableDeviceComponentPS;
      if IsDefined(dps) { defName = TDBID.ToStringDEBUG(dps.GetMinigameDefinition()); }
    }
    LogChannel(n"DEBUG", "[NetSec] minigame definition=" + defName
      + " entity=" + ToString(this.m_entity.GetClassName()));
  }

  // AN ACCESS POINT IS NOT ON A NETWORK - IT IS ONE.
  //
  // The gate below asks "does this target's network have an access point", which
  // is the right question for a camera and exactly the wrong one for the access
  // point itself: GetAccessPoints() on a master returns empty, so the daemon was
  // refused on the one target where breaching actually happens. Observed as
  // "daemon NOT offered - target has no network" with entity=AccessPoint, on a
  // spawned access point offering three programs.
  let isMaster: Bool = IsDefined(this.m_entity as AccessPoint)
                    || IsDefined(ps as MasterControllerPS);

  if !isMaster && (!IsDefined(ps) || !NetSecState.HasAccessPoint(ps)) {
    if IsDefined(session) { session.SetOffered(false); }
    if cfg.debugLogging {
      LogChannel(n"DEBUG", "[NetSec] daemon NOT offered - target has no network");
    }
    return;
  }

  // Construct the daemon and put it at the top of the list, where the thing you
  // came here for belongs - above the loot.
  //
  // programName IS NOT WHAT THE PLAYER READS, and believing it was cost nine
  // versions of a placeholder caption plus one crash.
  //
  // The breach screen builds its label in hackingMinigameUtils.script:854:
  //
  //     program.name = StringToName( LocKeyToString( miniGameActionRecord.ObjectActionUI().Caption() ) );
  //
  // That is the MinigameAction record's objectActionUI - our Interactions
  // record - and nothing on this value. programName is only a validity token:
  // hackingMinigameUtils.script:891 erases any program whose programName fails
  // IsNameValid or equals 'None', and never displays it. The borrowed vanilla
  // key below is kept because it is known-valid, not because it is read.

  // ============================================================================
  // TIERED MODE: four rings replace the three Datamines
  // ============================================================================
  //
  // WHY REPLACE RATHER THAN ADD, which is what every version until now did.
  //
  // The board is generated to contain the sequences it offers. More sequences on
  // a fixed grid means more overlap, so the chance that a buffer path completes
  // SOMETHING rises with the number of programs. Every version that added a
  // fourth option was quietly making breaching easier while its own comments
  // claimed to be adding a price. Four unlock daemons on top of three Datamines
  // would be seven, and seven programs is not a puzzle.
  //
  // ORDER MATTERS AND IS NOT COSMETIC. Insert first, and remove only what the
  // insertion has earned the room for. If these records ever fail to load,
  // removing the Datamines first would hand the player an empty board - no
  // programs, no way to open anything, ever. Nothing is taken away until
  // something has actually been put there.
  if cfg.requireAccessDaemon {
    // ONLY OFFER A RING THIS NETWORK ACTUALLY HAS.
    //
    // A yard with no cameras should not be selling you the cameras, and the base
    // game already agrees: hackingMinigameUtils.script:910 erases a CameraAccess
    // daemon when the network reports no surveillance camera, a TurretAccess one
    // when there is no turret, and an NPC-type one when there are no puppets. It
    // reads all three off ConnectedClassTypes, which the network answers for
    // itself.
    //
    // Our daemons are inserted AFTER that filter has run, so they escape it -
    // which means asking the same question here rather than inventing a test.
    // There is deliberately no flag for plain devices: doors and terminals are
    // the base case, and an access point with nothing behind it at all would
    // have been rejected by the network check above.
    let kinds: ConnectedClassTypes;

    // AN ACCESS POINT IS NOT ON A NETWORK - IT IS ONE, and asking it the
    // question the wrong way round is what left the breach screen showing only
    // DEVICES. CheckMasterConnectedClassTypes() works by walking
    // GetAccessPoints() and asking each one what it has; on a master that list
    // is empty, so it returns a struct with every flag false. Vanilla never
    // noticed because its Datamines are not gated on these flags - ours are.
    //
    // The master has its own accessor for this, CheckConnectedClassTypes(),
    // which walks its slaves directly. That is the one to ask when the thing
    // being breached IS the access point.
    if IsDefined(ps) {
      let master: ref<AccessPointControllerPS> = ps as AccessPointControllerPS;
      if IsDefined(master) {
        // THE WHOLE SUBTREE, NOT THE FIRST LEVEL DOWN.
        //
        // CheckConnectedClassTypes() walks GetImmediateSlaves() - direct
        // children only (accessPointController.script:1416). A device network is
        // a TREE: an access point's immediate slaves are frequently sub-masters,
        // and the cameras and turrets hang off those. So asking the access point
        // what it has returns the first rank and stops.
        //
        // Measured, and it is the cleanest possible demonstration: the vending
        // machine outside the club offered all four rings, while the access
        // point twenty metres away offered two. A DEVICE asks
        // CheckMasterConnectedClassTypes(), which aggregates across every access
        // point it can see; the access point asked only about itself. The same
        // network, described two different ways, and the shallower answer came
        // from the thing you actually breach.
        //
        // GetAllDescendants() is the deep walk - it is what GetPuppets() uses,
        // which is why PEOPLE was offered correctly all along while CAMERAS and
        // DEFENCES were not.
        let all: array<ref<DeviceComponentPS>>;
        master.GetAllDescendants(all);
        let z: Int32 = 0;
        while z < ArraySize(all) {
          let child: ref<DeviceComponentPS> = all[z];
          if IsDefined(child) {
            if IsDefined(child as SurveillanceCameraControllerPS) { kinds.surveillanceCamera = true; }
            if IsDefined(child as SecurityTurretControllerPS) { kinds.securityTurret = true; }
            if IsDefined(child as PuppetDeviceLinkPS) { kinds.puppet = true; }
          }
          z += 1;
        }
      } else {
        let dev2: ref<Device> = this.m_entity as Device;
        if IsDefined(dev2) {
          kinds = dev2.GetDevicePS().CheckMasterConnectedClassTypes();
        } else {
          let pup2: ref<ScriptedPuppet> = this.m_entity as ScriptedPuppet;
          if IsDefined(pup2) { kinds = pup2.GetMasterConnectedClassTypes(); }
        }
      }
    }

    // AND THE VANILLA ANSWER IS ONLY AS GOOD AS THE VANILLA GRAPH.
    //
    // CheckConnectedClassTypes counts a PuppetDeviceLinkPS found in
    // GetImmediateSlaves(). Adoption puts DEVICES in that list; people go into
    // the GetPuppets() wrap instead, which this never consults. So on a placed
    // access point the people are genuinely there, genuinely get opened by a
    // breach, and are invisible to the question "does this network have people".
    //
    // Rather than shove puppet links into the slave list - which would change
    // what every vanilla caller of GetImmediateSlaves sees, for one flag - the
    // registries answer for themselves and the two answers are unioned. NetSec
    // supplies this membership at runtime, so NetSec has to be able to report
    // it.
    let session2: ref<NetSecSession> = session;
    let selfObj: ref<GameObject> = this.m_entity as GameObject;
    if IsDefined(session2) && IsDefined(selfObj) {
      let here2: Vector4 = selfObj.GetWorldPosition();
      let reach: Float = Cast<Float>(cfg.adoptionRadius);

      if !kinds.puppet && ArraySize(session2.StationedNear(here2, reach)) > 0 {
        kinds.puppet = true;
      }
      if !kinds.surveillanceCamera || !kinds.securityTurret {
        let near2: array<ref<ScriptableDeviceComponentPS>> = session2.DevicesNear(here2, reach);
        let n2: Int32 = 0;
        while n2 < ArraySize(near2) {
          if IsDefined(near2[n2] as SurveillanceCameraControllerPS) { kinds.surveillanceCamera = true; }
          if IsDefined(near2[n2] as SecurityTurretControllerPS) { kinds.securityTurret = true; }
          n2 += 1;
        }
      }
    }

    // /DEVICE/ and /ALL/ ARE ALWAYS ON THE BOARD. The two in between are not.
    //
    // The middle rings only appear where the network has that class of thing,
    // which is the feature - a yard with no cameras does not sell you cameras.
    //
    // /ALL/ is unconditional, and that is the hole this closes. It used to be
    // gated on `puppet`, because it is implemented as the People tier - but its
    // subtitle is "Full network access" and that is what it actually is. On a
    // network with no people links, gating it meant the deepest available ring
    // was whatever detection happened to find; and if detection UNDER-reports,
    // as it did before the subtree fix, a class of device could end up with no
    // option on the board that opens it. Locked, with nothing to buy.
    //
    // Every other safeguard here leans the same way: no access point means open,
    // an incomplete offer stands tiering down, insertion precedes removal so the
    // board is never empty. A record that fails to load may cost a feature; it
    // must never cost the network. "Give me everything" is a coherent purchase
    // on any network, including one with nobody standing on it, so it is always
    // available and the grace is total rather than nearly total.
    let wanted: array<NetSecTarget>;
    ArrayPush(wanted, NetSecTarget.Device);
    if kinds.surveillanceCamera { ArrayPush(wanted, NetSecTarget.Camera); }
    if kinds.securityTurret { ArrayPush(wanted, NetSecTarget.Defence); }
    ArrayPush(wanted, NetSecTarget.People);

    let inserted: Int32 = 0;
    let t: Int32 = ArraySize(wanted) - 1;
    while t >= 0 {
      let p: MinigameProgramData;
      p.actionID = NetSecDaemon.TierId(wanted[t]);
      p.programName = n"LocKey#34844";
      ArrayInsert(Deref(programs), 0, p);
      inserted += 1;
      t -= 1;
    }
    if IsDefined(session) {
      session.SetExpectedCount(ArraySize(wanted));
      session.ResetPaid();
    }

    if inserted > 0 {
      let k: Int32 = ArraySize(Deref(programs)) - 1;
      while k >= 0 {
        if NetSecDaemon.IsGenericLoot(Deref(programs)[k].actionID) {
          ArrayErase(Deref(programs), k);
        }
        k -= 1;
      }
    }

    if IsDefined(session) {
      session.SetOfferedCount(inserted);
      session.SetOffered(inserted > 0);
    }

    if cfg.debugLogging {
      LogChannel(n"DEBUG", "[NetSec] TIERED board - " + ToString(inserted)
        + " of " + ToString(ArraySize(wanted)) + " ring daemon(s) offered"
        + " (camera=" + ToString(kinds.surveillanceCamera)
        + " turret=" + ToString(kinds.securityTurret)
        + " puppet=" + ToString(kinds.puppet) + ")"
        + ", loot daemons removed, total programs="
        + ToString(ArraySize(Deref(programs))));
    }
    return;
  }

  // ============================================================================
  // Untiered: leave the board exactly as the base game built it
  // ============================================================================
  //
  // The single access daemon is gone from this path rather than sitting on the
  // board doing nothing. A switch that decides whether access costs buffer
  // should not also leave a decoration behind when it is off - with it off, this
  // is the vanilla breach screen and completing any breach opens the network,
  // which is what "off" always meant.
  if IsDefined(session) {
    session.SetOffered(false);
    session.SetOfferedCount(0);
    session.SetExpectedCount(0);
    session.ResetPaid();
  }
  if cfg.debugLogging {
    LogChannel(n"DEBUG", "[NetSec] untiered - vanilla board left alone, any breach unlocks");
  }
}
