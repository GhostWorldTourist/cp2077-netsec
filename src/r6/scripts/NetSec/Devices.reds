// ============================================================================
// NetSec - Devices
// ============================================================================
//
// ONE HOOK. Better Netrunning gates devices across several methods -
// MarkActionsAsQuickHacks, FinalizeGetQuickHackActions, GetRemoteActions and
// CanRevealRemoteActionsWheel, two of them @replaceMethod. NetSec wraps
// FinalizeGetQuickHackActions only, because it is the last step before the
// action list reaches the UI and therefore sees everything the others do.
//
// Fewer hooks is not a stylistic preference. Every @replaceMethod is a promise
// that no other mod wants that method, and every extra hook is another place
// this mod can disagree with itself about whether a device is locked.
//
// GREYED OUT, NOT REMOVED. A locked quickhack stays in the list, disabled, with
// the vanilla reason "No network access rights" (LocKey#7021). Deleting it would
// be tidier and much worse: the player would have no way to tell "this network
// is locked" from "this hack does not exist here", which is exactly the
// ambiguity that makes a mechanic feel arbitrary.
// ============================================================================

module NetSec.Devices

import NetSec.Config.*
import NetSec.Daemon.*
import NetSec.State.*
import NetSec.Progression.*

// Where a thing is, in the form the AMM Locations file uses, so a logged gap
// and a hand-saved location describe the same point in the same units.
public static func NetSecWhere(ps: ref<SharedGameplayPS>) -> String {
  let owner: ref<GameObject> = ps.GetOwnerEntityWeak() as GameObject;
  if !IsDefined(owner) { return "at=unknown"; }
  let p: Vector4 = owner.GetWorldPosition();
  return "at=" + ToString(p.X) + "," + ToString(p.Y) + "," + ToString(p.Z);
}

@addMethod(ScriptableDeviceComponentPS)
public final func NetSecTargetKind() -> NetSecTarget {
  // Only things that shoot are Defences. A camera does not shoot - but owning
  // one buys the site's AWARENESS, which is a different purchase from opening a
  // door and the reason cameras got their own ring.
  //
  // SurveillanceCameraControllerPS and SecurityTurretControllerPS are siblings
  // under SensorDeviceControllerPS, not parent and child, so neither test
  // shadows the other and the order here is for reading, not correctness.
  if IsDefined(this as SecurityTurretControllerPS) { return NetSecTarget.Defence; }
  if IsDefined(this as SurveillanceCameraControllerPS) { return NetSecTarget.Camera; }
  return NetSecTarget.Device;
}

// VENDING MACHINES ARE NEVER GATED.
//
// They are not security infrastructure - they are the corner shop. Locking the
// drinks machine behind a network breach is the kind of rule that makes a
// mechanic feel arbitrary rather than hard, and it gates flavour rather than
// power. They stay open, and because they carry a backdoor they remain a place
// you can breach a network FROM, on foot, by walking up to one.
//
// That last part needs no code here: NetSec has no remote breach at all, so
// every breach in this mod is already a direct connection.
@addMethod(ScriptableDeviceComponentPS)
public final func NetSecIsExemptDevice() -> Bool {
  // Vending machines: the corner shop, not security infrastructure.
  if IsDefined(this as VendingMachineControllerPS) { return true; }

  // VEHICLES BELONG TO A DIFFERENT MOD, AND TO A DIFFERENT IDEA.
  //
  // A car is not on a subnet and never will be, so NetSec's whole question -
  // "has this network been breached?" - is meaningless for one. Worse, vehicle
  // security is already modelled properly elsewhere: Vehicle Security Rework
  // gives cars their own hack levels, auto-unlock chances and police response.
  // Gating them here would override a system built for the job with one that
  // knows nothing about it.
  //
  // This is also what made the strict setting unusable. With
  // unlockWhenNoAccessPoint off, every car in Night City reported no access
  // point and had its quickhacks greyed out - which would have silently broken
  // Vehicle Security Rework and looked like that mod's fault. Exempting them
  // is what makes "off" a difficulty setting rather than a trap.
  //
  // It also cleans the diagnostic: 252 of 261 logged coverage gaps were parked
  // cars, which drowned the handful of real ones.
  if IsDefined(this as VehicleComponentPS) { return true; }

  return false;
}

// Hacks that stay available on a locked network, because they are how you find
// out anything at all. Ping is reconnaissance, not an attack; locking it makes
// the player blind rather than challenged.
@addMethod(ScriptableDeviceComponentPS)
public final func NetSecIsAlwaysAllowed(action: ref<ScriptableDeviceAction>) -> Bool {
  let cfg: ref<NetSecConfig> = new NetSecConfig();
  // Matched on class NAME rather than by casting. The cast form needs the type
  // to exist at compile time, which couples this mod to whichever actions the
  // base game happens to declare; the name form does not, and still matches
  // when another mod subclasses the action.
  let name: CName = action.GetClassName();

  // THE WAY IN IS NEVER LOCKED. Not behind a setting, not behind progression.
  //
  // This gate greys out every action on an unbreached network, and Breach
  // Protocol is an action on the device. Without these two lines the rule eats
  // its own entry condition: you cannot breach the network because you have not
  // breached the network.
  //
  // It survived every test because a physical access point is an INTERACTION,
  // not a quickhack, so jacking in on foot never routes through this gate. It
  // took a satellite dish carrying a control-point marker and no jack-in point
  // - the one shape where the quickhack is the only entrance - to expose it.
  //
  // Better Netrunning carried this whitelist explicitly. Dropping it was the
  // most expensive line not copied across.
  // SetBreachedSubnet is unconditional: it is the mechanism a breach already in
  // progress uses to apply itself, not a way to start one. Blocking it would
  // break the breach a player legitimately earned.
  if Equals(name, n"SetBreachedSubnet") { return true; }

  // BREACHING IS NEVER GATED BEHIND HAVING BREACHED. Unconditional, and it used
  // to be behind an `allowRemoteBreach` setting whose own description said it
  // did nothing - it did: turning it off re-gated the way in and left a network
  // with no entrance. A setting that contradicts its description is a bug
  // report waiting to be filed, and this one had no legitimate off position, so
  // it is gone rather than corrected.
  if Equals(name, n"RemoteBreach") { return true; }

  if cfg.alwaysAllowPing && Equals(name, n"PingDevice") { return true; }
  if cfg.alwaysAllowDistract && Equals(name, n"QuickHackDistraction") { return true; }
  return false;
}

// REGISTERED WHEN IT STREAMS IN, not when the player aims at it.
//
// The device half of the bug fixed for NPCs in 1.6.0, found because devices were
// not unlocking from a breach that had plainly worked. The stranded set is built
// inside the GetAccessPoints wrap, which runs while the quickhack list is being
// assembled - so it held exactly the devices already inspected. You breach
// before you look, so at the moment the breach needed to know what to open, it
// knew about almost nothing.
//
// Registration here is unconditional: this is "what exists nearby", and whether
// any given device is stranded is decided later, at the point that question is
// actually asked.
@wrapMethod(ScriptableDeviceComponentPS)
protected func GameAttached() -> Void {
  wrappedMethod();

  let cfg: ref<NetSecConfig> = new NetSecConfig();
  if !cfg.enabled { return; }

  let session: ref<NetSecSession> = NetSecSession.Get(this.GetGameInstance());
  if IsDefined(session) { session.RegisterDevice(this); }
}

@wrapMethod(ScriptableDeviceComponentPS)
protected final func FinalizeGetQuickHackActions(outActions: script_ref<array<ref<DeviceAction>>>, const context: script_ref<GetActionsContext>) -> Void {
  wrappedMethod(outActions, context);

  let cfg: ref<NetSecConfig> = new NetSecConfig();
  if !cfg.enabled { return; }

  let gi: GameInstance = this.GetGameInstance();
  let shared: ref<SharedGameplayPS> = this;
  let kind: NetSecTarget = this.NetSecTargetKind();

  if this.NetSecIsExemptDevice() { return; }

  // Split so the diagnostic can say WHICH rule locked this, not merely that
  // something did. "No access point" and "not breached yet" want different
  // answers from the player, and telling them apart is the whole point of the
  // counting exercise.
  let unlocked: Bool = NetSecState.IsUnlocked(shared, kind, gi);
  let hasAP: Bool = NetSecState.HasAccessPoint(shared);
  // A STRANDED DEVICE ACCEPTS A BREACH THAT HAPPENED NEARBY.
  //
  // Stranded means gated, on a network, and unable to resolve a single access
  // point in the world - the shape where the mod is pointing the player at a
  // door that is not there. If a breach happened within the radius and is still
  // live on the same clock everything else uses, that breach counts here.
  //
  // A device whose network HAS a reachable access point is never eligible, at
  // any distance. Better Netrunning's radial unlock applied to everything and
  // dissolved the hunt; this only ever reaches things nothing else can open.
  //
  // ASK THE REGISTRY, NOT THE WRAPPED ACCESSOR. AnyAccessPointResolves() calls
  // GetAccessPoints(), and Adopt.reds wraps that to APPEND the adopted access
  // point - so a device reported a resolvable way in the instant it was
  // adopted, this test went false, and the branch that only ever runs for
  // stranded devices could never run again. The question "is this abandoned"
  // was being answered by the code that un-abandons it.
  //
  // A device the session has adopted is stranded by definition: adoption only
  // ever claims something whose own access points did not resolve.
  let session0: ref<NetSecSession> = NetSecSession.Get(gi);
  let isStranded: Bool = hasAP
    && (!NetSecState.AnyAccessPointResolves(shared)
        || (IsDefined(session0) && session0.IsAdopted(this)));

  let strandedOpen: Bool = false;
  if isStranded && cfg.strandedBreachRadius > 0 {
    let session: ref<NetSecSession> = NetSecSession.Get(gi);
    if IsDefined(session) && session.HasBreach() && NetSecState.StampIsLive(session.BreachStamp(), gi) {
      let me: ref<GameObject> = this.GetOwnerEntityWeak() as GameObject;
      if IsDefined(me) {
        let d: Float = session.BreachDistanceFrom(me.GetWorldPosition());
        if d >= 0.0 && d <= Cast<Float>(cfg.strandedBreachRadius) {
          strandedOpen = true;
          if cfg.debugLogging {
            LogChannel(n"DEBUG", "[NetSec] STRANDED opened by nearby breach d="
              + ToString(RoundF(d)) + "m class=" + ToString(this.GetClassName()));
          }
        }
      }
    }
  }

  // PUSH A CHAINED LEASE FORWARD. StampIsLive can keep a hold alive because a
  // later breach refreshed it, but that refresh is one hop from the recorded
  // stamp - so without writing it back, a hold would keep measuring from the
  // original breach and eventually lapse mid-chain. Devices the player actually
  // uses advance their own stamp here; ones nobody touches are left to expire,
  // which is the right way round.
  if unlocked && NetSecState.NeedsRefresh(NetSecState.ReadStamp(shared, kind), gi) {
    NetSecState.StampRing(shared, kind, gi);
  }

  let hasAccess: Bool = unlocked || strandedOpen || (!hasAP && cfg.unlockWhenNoAccessPoint);
  let hasSkill: Bool = NetSecProgression.AllowsTarget(kind, gi);

  if cfg.debugLogging {
    // IDENTIFY WHAT WE ARE LOOKING AT.
    //
    // Making a specific kind of device breachable needs its class name, and
    // there is no way to read that off a screenshot or out of the compiled
    // vanilla scripts. So the mod reports it: aim at the thing, read the log.
    //
    // backdoor= is the answer to "why is there no Breach Protocol here" -
    // vanilla only offers it on a device that has one, so a dish reporting
    // backdoor=false was never being blocked by NetSec at all.
    LogChannel(n"DEBUG", "[NetSec] SEEN class=" + ToString(this.GetClassName())
      + " backdoor=" + ToString(this.HasNetworkBackdoor())
      + " hasAP=" + ToString(hasAP)
      + " " + NetSecWhere(this));

    // IS IT A BACKDOOR, OR MERELY ON A NETWORK THAT HAS ONE.
    //
    // The line above logs HasNetworkBackdoor() - "somewhere on this network
    // there is a way in" - and it has been read three times as though it said
    // "this device is the way in". Those are different questions and only the
    // second one explains a device with a breach mappin on the minimap and no
    // breach action on the device.
    //
    // IsBackdoor() answers it directly. HasPersonalLinkSlot() answers the other
    // half: a jack-in point is a slot on the entity, not a property of the
    // network, and no script can add one - so if this reports false, physical
    // entry on this device is impossible and remote is the only route there
    // will ever be.
    LogChannel(n"DEBUG", "[NetSec] IDENT class=" + ToString(this.GetClassName())
      + " connectedToBackdoor=" + ToString(this.IsConnectedToBackdoorDevice())
      + " personalLinkSlot=" + ToString(this.HasPersonalLinkSlot())
      + " " + NetSecWhere(this));

    // WHAT DOES IT ACTUALLY OFFER. The question behind "there is no breach on
    // this thing" is whether the game ever built a breach action for it, and
    // that has been argued about for two days without once being read off the
    // list. If RemoteBreach is absent here, nothing NetSec does to permissions
    // will ever make it appear - the action does not exist to be permitted.
    let a: Int32 = 0;
    let offered: String = "";
    while a < ArraySize(Deref(outActions)) {
      let act: ref<ScriptableDeviceAction> = Deref(outActions)[a] as ScriptableDeviceAction;
      if IsDefined(act) { offered += " " + ToString(act.GetObjectActionRecord().ActionName()); }
      a += 1;
    }
    LogChannel(n"DEBUG", "[NetSec] OFFERS class=" + ToString(this.GetClassName()) + " ->" + offered);

    // WHO SAID NO. The dish offers RemoteBreach, NetSec permits it, and it is
    // still not usable - so the decision is being made by something neither of
    // those two facts covers. An action carries its own answer: whether it is
    // inactive, whether it considers itself possible at all, and the reason
    // string it would show. Reading that is the difference between knowing and
    // another evening of theories about backdoors.
    let b: Int32 = 0;
    while b < ArraySize(Deref(outActions)) {
      let ba: ref<ScriptableDeviceAction> = Deref(outActions)[b] as ScriptableDeviceAction;
      if IsDefined(ba) && IsDefined(ba.GetObjectActionRecord()) {
        let bn: CName = ba.GetObjectActionRecord().ActionName();
        if Equals(bn, n"RemoteBreach") {
          LogChannel(n"DEBUG", "[NetSec] WHYNOT class=" + ToString(this.GetClassName())
            + " action=RemoteBreach inactive=" + ToString(ba.IsInactive())
            + " reason=" + ToString(ba.GetInactiveReason())
            + " " + NetSecWhere(this));
        }
      }
      b += 1;
    }

    // THE INTERESTING LINE IS THE ONE ABOUT SOMETHING THAT STAYED OPEN.
    //
    // A locked target is the mechanic working. A target that came out OPEN
    // because its network has no access point is a hole in the world - there
    // was nothing to breach, so the rule could not apply. Those are the places
    // worth adding an access point to, and they are invisible in play: nothing
    // happens, which is exactly why they need to report themselves.
    //
    // Coordinates are included so a gap can be found again without having been
    // noticed at the time.
    if !hasAP && cfg.unlockWhenNoAccessPoint {
      LogChannel(n"DEBUG", "[NetSec] GAP device no-access-point " + NetSecWhere(this));
    } else if !(hasAccess && hasSkill) {
      let reason: String = "UNBREACHED";
      if hasAccess && !hasSkill { reason = "INTELLIGENCE"; }
      LogChannel(n"DEBUG", "[NetSec] LOCKED device reason=" + reason
        + " ring=" + ToString(EnumInt(kind)) + " " + NetSecWhere(this)
        + " ||WAY IN:" + NetSecState.DescribeAccessPoints(shared));
    }
  }

  // GRANT A PORT TO A STRANDED DEVICE, BEFORE greying anything out.
  //
  // Conditions are all four together: NetSec is locking it, it is on a network,
  // it has no port of its own, and not one of its network's access points can
  // be resolved in the world. That last one is what keeps this off a camera
  // standing next to a terminal.
  //
  // The grant is one-way and never revoked. An access point can fail to resolve
  // because it is genuinely elsewhere or merely because it is not streamed, and
  // the two are indistinguishable from here - so the failure mode is a port
  // somewhere that did not strictly need one, which is a far better outcome
  // than a network the player cannot enter at all.
  if cfg.grantStrandedJackIn && !hasAccess && isStranded
     && !this.HasPersonalLinkSlot() {
    this.SetHasPersonalLinkSlot(true);
    if cfg.debugLogging {
      LogChannel(n"DEBUG", "[NetSec] STRANDED granted jack-in port class="
        + ToString(this.GetClassName()) + " " + NetSecWhere(this));
    }
  }

  if hasAccess && hasSkill { return; }

  let i: Int32 = 0;
  while i < ArraySize(Deref(outActions)) {
    let action: ref<ScriptableDeviceAction> = Deref(outActions)[i] as ScriptableDeviceAction;
    if IsDefined(action) && !this.NetSecIsAlwaysAllowed(action) {
      // Say WHERE, not just no. Falls back to the vanilla "No network access
      // rights" string when there is no access point to point at - which is
      // the honest message in that case, because there is nowhere to go.
      let hint: String = NetSecState.WayInHint(shared, gi);
      if StrLen(hint) > 0 {
        action.SetInactiveWithReason(false, hint);
      } else {
        action.SetInactiveWithReason(false, "LocKey#7021");
      }
    }
    i += 1;
  }
}
