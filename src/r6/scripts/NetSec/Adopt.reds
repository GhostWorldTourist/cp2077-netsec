// ============================================================================
// NetSec - Adoption: putting a device on an access point's network
// ============================================================================
//
// THE PROBLEM, STATED PRECISELY
//
// An access point placed into the world by a mod has no slaves, and a device
// whose own network has no reachable entrance has no way in. Neither can be
// fixed where you would expect, and all three dead ends were checked rather
// than assumed:
//
//   - SetSlaves does not exist on AccessPointControllerPS. The device graph is
//     READABLE from script and not writable.
//   - Sector data does not carry it. The dish's own sector was extracted by
//     hash and converted to JSON: its device nodes are worldEntityNode with
//     instanceData chunks like DoorController and LcdScreenController, and
//     there is no parents or deviceLinks anywhere in them.
//   - Nor does the entity template. accesspoint.ent contains hasPersonalLinkSlot
//     and hasNetworkBackdoor, a WorkspotMapperComponent and personal-link
//     workspot data - and the strings DeviceLink and parents appear in it zero
//     times.
//
// So membership is not authored in any file that could be copied. It has to be
// supplied at runtime. Better Netrunning never attempted it: it reads the graph
// and falls back to a 50 m radial unlock, which is what NetSec 0.9.0 settled
// for too.
//
// THE APPROACH: ANSWER THE QUESTIONS THE GAME ASKS
//
// Membership is not a stored edge the game consults. It is whatever
// GetAccessPoints() and GetImmediateSlaves() return, and both are wrappable. So
// a device is on a network exactly when those two answers say it is:
//
//   GetAccessPoints()     on the DEVICE -> also report the adopted access point
//   GetImmediateSlaves()  on the MASTER -> also report the adopted devices
//
// Vanilla does the rest. RefreshSlaves already runs over GetImmediateSlaves
// after a successful dive, so a breach reaches adopted devices through the base
// game's own propagation rather than a radius check bolted on beside it.
//
// WHY THIS IS SAFE
//
// Adoption only ever ADDS, and only to a device whose own access points cannot
// be resolved in the world - the shape where the mod was pointing the player at
// a door that is not there. A device with a reachable access point is returned
// untouched at any distance, because walking to that access point is the game.
// ============================================================================

module NetSec.Adopt

import NetSec.Config.*
import NetSec.Daemon.*

// The registry itself lives on NetSecSession in Daemon.reds. It cannot be
// grafted on from here: @addField is for GAME classes, and pointing it at one of
// our own classes fails with "constant pool error: definition not found: 206869"
// and no indication that the annotation is what is wrong.

// ----------------------------------------------------------------------------
// Access points announce themselves
// ----------------------------------------------------------------------------
@wrapMethod(AccessPointControllerPS)
public func GameAttached() -> Void {
  wrappedMethod();

  let cfg: ref<NetSecConfig> = new NetSecConfig();
  if !cfg.enabled || !cfg.adoptStrandedDevices { return; }

  let session: ref<NetSecSession> = NetSecSession.Get(this.GetGameInstance());
  if IsDefined(session) {
    session.RegisterAccessPoint(this);
    if cfg.debugLogging {
      LogChannel(n"DEBUG", "[NetSec] AP registered, known access points="
        + ToString(ArraySize(session.m_accessPoints)));
    }
  }
}

// ----------------------------------------------------------------------------
// A stranded device reports the adopted access point as its own
// ----------------------------------------------------------------------------
//
// wrappedMethod() FIRST, and its result is what decides. Asking
// NetSecState.HasAccessPoint here would call straight back into this wrapper.
@wrapMethod(SharedGameplayPS)
public final const func GetAccessPoints() -> array<ref<AccessPointControllerPS>> {
  let aps: array<ref<AccessPointControllerPS>> = wrappedMethod();

  let cfg: ref<NetSecConfig> = new NetSecConfig();
  if !cfg.enabled || !cfg.adoptStrandedDevices { return aps; }

  // On no network at all is a different rule, handled by unlockWhenNoAccessPoint.
  if ArraySize(aps) == 0 { return aps; }

  // A device with a reachable access point is never adopted. This is the whole
  // safety property: adoption reaches only what nothing else can open.
  let i: Int32 = 0;
  while i < ArraySize(aps) {
    if IsDefined(aps[i].GetOwnerEntityWeak() as GameObject) { return aps; }
    i += 1;
  }

  let me: ref<GameObject> = this.GetOwnerEntityWeak() as GameObject;
  if !IsDefined(me) { return aps; }

  let session: ref<NetSecSession> = NetSecSession.Get(this.GetGameInstance());
  if !IsDefined(session) { return aps; }

  let adopted: ref<AccessPointControllerPS> =
    session.NearestAccessPoint(me.GetWorldPosition(), Cast<Float>(cfg.adoptionRadius));
  if IsDefined(adopted) {
    ArrayPush(aps, adopted);

    // REGISTER THE DEVICE, so the access point can name it as a slave.
    //
    // Both halves are needed and each is useless alone: without this the
    // adopted access point would appear on the device (a way in the player can
    // see) while RefreshSlaves would never reach the device, so breaching would
    // still unlock nothing.
    //
    // Mutating from a const method is legal here because the const applies to
    // `this` - the device - and the object being written is the session.
    let dev: ref<ScriptableDeviceComponentPS> = this as ScriptableDeviceComponentPS;
    if IsDefined(dev) {
      session.RegisterStranded(dev);
      if cfg.debugLogging {
        LogChannel(n"DEBUG", "[NetSec] ADOPT device class=" + ToString(dev.GetClassName())
          + " onto access point; stranded registry=" + ToString(ArraySize(session.m_strandedDevices)));
      }
    }
  }
  return aps;
}

// ----------------------------------------------------------------------------
// The access point reports the adopted devices as its slaves
// ----------------------------------------------------------------------------
//
// This is the half that makes a breach WORK rather than merely look right.
// RefreshSlaves runs over this list after a successful dive, so an adopted
// device is unlocked by the base game's own propagation.
@wrapMethod(MasterControllerPS)
public final func GetImmediateSlaves() -> array<ref<DeviceComponentPS>> {
  let slaves: array<ref<DeviceComponentPS>> = wrappedMethod();

  let cfg: ref<NetSecConfig> = new NetSecConfig();
  if !cfg.enabled || !cfg.adoptStrandedDevices { return slaves; }

  let ap: ref<AccessPointControllerPS> = this as AccessPointControllerPS;
  if !IsDefined(ap) { return slaves; }

  let owner: ref<GameObject> = this.GetOwnerEntityWeak() as GameObject;
  if !IsDefined(owner) { return slaves; }
  let here: Vector4 = owner.GetWorldPosition();

  let session: ref<NetSecSession> = NetSecSession.Get(this.GetGameInstance());
  if !IsDefined(session) { return slaves; }

  let radius: Float = Cast<Float>(cfg.adoptionRadius);
  let i: Int32 = 0;
  let added: Int32 = 0;
  while i < ArraySize(session.m_strandedDevices) {
    let dev: ref<ScriptableDeviceComponentPS> = session.m_strandedDevices[i];
    if IsDefined(dev) {
      let dOwner: ref<GameObject> = dev.GetOwnerEntityWeak() as GameObject;
      if IsDefined(dOwner) {
        let p: Vector4 = dOwner.GetWorldPosition();
        let dx: Float = p.X - here.X;
        let dy: Float = p.Y - here.Y;
        let dz: Float = p.Z - here.Z;
        if SqrtF(dx*dx + dy*dy + dz*dz) <= radius {
          ArrayPush(slaves, dev);
          added += 1;
        }
      }
    }
    i += 1;
  }

  if cfg.debugLogging && added > 0 {
    LogChannel(n"DEBUG", "[NetSec] ADOPTED " + ToString(added)
      + " device(s) onto access point at "
      + ToString(RoundF(here.X)) + "," + ToString(RoundF(here.Y)));
  }
  return slaves;
}

// ----------------------------------------------------------------------------
// The access point reports the stationed NPCs as its people
// ----------------------------------------------------------------------------
//
// THE HALF THAT WAS MISSING FOR THREE VERSIONS, and the reason a failed breach
// did nothing.
//
// GetImmediateSlaves() is not the function the game asks about people.
// GetPuppets() is - masterController.script:128 - and it does NOT route through
// GetImmediateSlaves at all. It calls GetAllDescendants(), which goes straight
// to the DeviceSystem and reads the real device graph. So the adoption wrap
// above, which works perfectly for devices, is INVISIBLE to every NPC-facing
// path in the base game. Nothing announces that; the two functions simply have
// different implementations and only one of them was wrapped.
//
// What that cost, precisely: SendMinigameFailedToAllNPCs()
// (accessPointController.script:1151) walks GetPuppets() and queues a
// MinigameFailEvent at each one. On an adopted network that list was empty, so
// vanilla's own failure alert was addressed to nobody. "Failing the breach does
// nothing" was never a weak alarm - it was an alarm with no recipients.
//
// Wrapping GetPuppets() fixes that at the source, and fixes more than the
// alarm: PingSquad (accessPointController.script:1357) walks the same list, so
// an adopted NPC answers a network ping too. That is the argument for mending
// the graph rather than hand-rolling a roster inside the failure path - every
// vanilla behaviour keyed on network membership comes back at once.
@wrapMethod(MasterControllerPS)
public final const func GetPuppets() -> array<ref<PuppetDeviceLinkPS>> {
  let puppets: array<ref<PuppetDeviceLinkPS>> = wrappedMethod();

  let cfg: ref<NetSecConfig> = new NetSecConfig();
  if !cfg.enabled || !cfg.adoptStrandedDevices { return puppets; }

  // Only an access point adopts. Every other master - a door bank, a lighting
  // group - keeps exactly the people it had.
  let ap: ref<AccessPointControllerPS> = this as AccessPointControllerPS;
  if !IsDefined(ap) { return puppets; }

  let owner: ref<GameObject> = this.GetOwnerEntityWeak() as GameObject;
  if !IsDefined(owner) { return puppets; }

  let session: ref<NetSecSession> = NetSecSession.Get(this.GetGameInstance());
  if !IsDefined(session) { return puppets; }

  let links: array<ref<PuppetDeviceLinkPS>> =
    session.PuppetLinksNear(owner.GetWorldPosition(), Cast<Float>(cfg.adoptionRadius));

  // ADDITIVE, NEVER REPLACING, and deduped. A duplicate entry would queue the
  // fail event twice at the same NPC and ping the same squad twice.
  let vanillaCount: Int32 = ArraySize(puppets);
  let addedPuppets: Int32 = 0;
  let j: Int32 = 0;
  while j < ArraySize(links) {
    if !ArrayContains(puppets, links[j]) {
      ArrayPush(puppets, links[j]);
      addedPuppets += 1;
    }
    j += 1;
  }

  if cfg.debugLogging && addedPuppets > 0 {
    LogChannel(n"DEBUG", "[NetSec] PUPPETS +" + ToString(addedPuppets)
      + " stationed adopted (vanilla had " + ToString(vanillaCount) + ")");
  }
  return puppets;
}
