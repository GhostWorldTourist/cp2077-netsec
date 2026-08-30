// ============================================================================
// NetSec - People
// ============================================================================
//
// Even gonks employ a little netsec. The whole mod is named for this file: a
// random Tyger Claw is not an open port, and Overheat should not be something
// you can apply to anyone you can see from behind a wall.
//
// NO PERSISTENT STATE HERE, AND THAT IS THE POINT.
//
// Better Netrunning adds a persistent flag to every NPC to remember whether it
// was breached directly. NetSec adds nothing, because the base game already
// tracks this: `m_quickHacksExposed` is set when the network an NPC belongs to
// is breached, and `IsConnectedToAccessPoint()` says whether it belongs to one
// at all. Reading vanilla's own answer is cheaper than keeping a second copy of
// it, and a second copy is a second thing that can be wrong after a load.
//
// An NPC on no network is hackable. There is nothing to breach, and an
// unreachable enemy is a bug rather than a difficulty setting - the same reason
// the "no access point" rule exists for devices.
// ============================================================================

module NetSec.People

import NetSec.Config.*
import NetSec.Daemon.*
import NetSec.State.*
import NetSec.Progression.*

// Record WHEN the game exposed this NPC, so the same clock applies to people as
// to devices. Without this, vanilla's flag never ages and that let people stay
// breached forever while devices expired after six hours - one mod, two rules.
@wrapMethod(ScriptedPuppetPS)
public func OnSetExposeQuickHacks(evt: ref<SetExposeQuickHacks>) -> EntityNotificationType {
  let result: EntityNotificationType = wrappedMethod(evt);
  if this.m_quickHacksExposed {
    this.m_netSecExposedAt = NetSecState.Now(this.GetGameInstance());
  }
  return result;
}

// REGISTERED WHEN THEY ARRIVE, NOT WHEN THEY ARE LOOKED AT.
//
// This is the fix for an empty registry, and the bug was in the timing rather
// than in the storing. Registration used to happen in GetAllChoices, which the
// game calls when the player opens a quickhack menu on somebody - so the set
// held exactly the people already scanned. You breach BEFORE you look at
// anyone, so at the moment the alarm asked who was present the answer was
// nobody, every time. Measured: "ALARM - 4 parts, 0 non-civilian, 0 sent",
// standing in a yard with four Tyger Claws in it.
//
// OnGameAttached fires when the puppet streams in, which is the honest
// definition of present.
//
// wrappedMethod() FIRST is load-bearing here and not a habit: vanilla's own
// OnGameAttached is where `m_isCrowd = GetCrowd()` is assigned
// (scriptedPuppet.script:645). Testing IsCrowd() before that line has run reads
// an unset field, and every pedestrian in Night City would register as
// stationed.
@wrapMethod(ScriptedPuppet)
protected cb func OnGameAttached() -> Bool {
  let result: Bool = wrappedMethod();

  let cfg: ref<NetSecConfig> = new NetSecConfig();
  if !cfg.enabled { return result; }

  if NetSecIsStationed(this) {
    let session: ref<NetSecSession> = NetSecSession.Get(this.GetGame());
    if IsDefined(session) { session.RegisterNPC(this.GetPS()); }
  }

  return result;
}

@addMethod(ScriptedPuppetPS)
public final const func NetSecHasNetworkAccess(gi: GameInstance) -> Bool {
  // NOT ON A NETWORK - and this is where "freely hackable" was too generous.
  //
  // The old rule was one line: no access point, no gate, hack away. It is right
  // for the person it was written for - a lone gonk in an alley, who has no
  // security because he IS the security, and whose only ICE is his own.
  //
  // It was wrong for the four gangers standing around a stash. They are not on
  // a network because the game never wired them to one, not because nobody is
  // guarding that spot - and NetSec reading absence-of-wiring as
  // absence-of-protection is what made a guarded yard hackable from the roof
  // opposite. The device beside them got adopted onto a nearby access point and
  // went dark; the people did not, and stayed open.
  //
  // So the question becomes "is anyone protecting this SPOT", asked of the same
  // registry and the same radius the devices use, and answered only for someone
  // the game says is stationed there. A pedestrian walking through the same
  // radius is still open, because IsCrowd already excluded them.
  if !this.IsConnectedToAccessPoint() {
    let cfg: ref<NetSecConfig> = new NetSecConfig();
    if !cfg.protectStationedNPCs { return true; }

    let pup: ref<ScriptedPuppet> = this.GetOwnerEntityWeak() as ScriptedPuppet;
    if !IsDefined(pup) || !NetSecIsStationed(pup) { return true; }

    let session: ref<NetSecSession> = NetSecSession.Get(gi);
    if !IsDefined(session)
       || !session.HasAccessPointWithin(pup.GetWorldPosition(), Cast<Float>(cfg.adoptionRadius)) {
      // Nothing within reach owns this spot. There is no way in, so there is no
      // gate - the same rule devices get, for the same reason.
      return true;
    }
    // Falls through: there IS an access point, so the normal breach rules apply.
  }
  if !this.m_quickHacksExposed { return false; }

  // A stamp of zero is someone exposed before NetSec was recording. Treat that
  // as still open rather than retroactively revoking access already granted.
  if this.m_netSecExposedAt <= 0.0 { return true; }
  return NetSecState.StampIsLive(this.m_netSecExposedAt, gi);
}

@wrapMethod(ScriptedPuppetPS)
public final const func GetAllChoices(const actions: script_ref<array<wref<ObjectAction_Record>>>, const context: script_ref<GetActionsContext>, puppetActions: script_ref<array<ref<PuppetAction>>>) -> Void {
  wrappedMethod(actions, context, puppetActions);

  let cfg: ref<NetSecConfig> = new NetSecConfig();
  if !cfg.enabled { return; }

  let gi: GameInstance = this.GetGameInstance();
  let hasAccess: Bool = this.NetSecHasNetworkAccess(gi);

  // A BACKSTOP, no longer the source. OnGameAttached above is what fills the
  // registry now; this catches anyone who attached before NetSec's session
  // system existed - a save loaded into a populated street. Filtered the same
  // way, so looking at a pedestrian can never put one in the alarm's set, which
  // is precisely what the unconditional version used to do.
  let reg: ref<NetSecSession> = NetSecSession.Get(gi);
  if IsDefined(reg) {
    let self: ref<ScriptedPuppet> = this.GetOwnerEntityWeak() as ScriptedPuppet;
    if IsDefined(self) && NetSecIsStationed(self) { reg.RegisterNPC(this); }
    if cfg.debugLogging {
      LogChannel(n"DEBUG", "[NetSec] npc seen -> registry size="
        + ToString(reg.NPCCount()));
    }
  } else {
    if cfg.debugLogging { LogChannel(n"DEBUG", "[NetSec] npc register FAILED - no session"); }
  }

  // A NEARBY BREACH OPENS PEOPLE TOO.
  //
  // Devices gained this first and NPCs did not, so a breach at an adopted
  // access point opened the dish and left every ganger around it untouchable -
  // reported from play as "hacks still locked on the npcs". Vanilla exposes
  // NPCs through the network they belong to, which an adopted access point is
  // not part of, so the same rule that reaches stranded devices has to reach
  // the people standing next to them.
  //
  // Same clock and same radius as devices, so the two can never disagree about
  // whether a breach is still live.
  if !hasAccess {
    let cfg2: ref<NetSecConfig> = new NetSecConfig();
    if cfg2.adoptStrandedDevices {
      let session: ref<NetSecSession> = NetSecSession.Get(gi);
      if IsDefined(session) && session.HasBreach() && NetSecState.StampIsLive(session.BreachStamp(), gi) {
        let owner: ref<GameObject> = this.GetOwnerEntityWeak() as GameObject;
        if IsDefined(owner) {
          let d: Float = session.BreachDistanceFrom(owner.GetWorldPosition());
          if d >= 0.0 && d <= Cast<Float>(cfg2.adoptionRadius) {
            hasAccess = true;

            // STAMP IT, so people and devices obey one rule.
            //
            // Devices opened by a breach get a PERSISTENT stamp and survive a
            // reload until the clock expires them. People were opened from the
            // session record only, so a reload silently re-locked every NPC
            // while the dish beside them stayed open - a regression test would
            // read that as a pass, when it is really state loss wearing expiry's
            // clothes. m_netSecExposedAt is already persistent and already the
            // field NetSecHasNetworkAccess reads, so stamping here puts people
            // on exactly the clock devices use.
            if this.m_netSecExposedAt <= 0.0 || !NetSecState.StampIsLive(this.m_netSecExposedAt, gi) {
              this.m_netSecExposedAt = session.BreachStamp();
            }

            if cfg2.debugLogging {
              LogChannel(n"DEBUG", "[NetSec] people opened by nearby breach d=" + ToString(RoundF(d))
                + "m - stamped, expires with the same clock as devices");
            }
          }
        }
      }
    }
  }

  if cfg.debugLogging {
    // An enemy on no network at all is the same hole as a device with no access
    // point: nothing could ever have gated them. This is the line that finds a
    // group of gangers standing next to three vending machines that are not
    // wired to anything.
    if !this.IsConnectedToAccessPoint() {
      let owner: ref<GameObject> = this.GetOwnerEntityWeak() as GameObject;
      let where: String = "at=unknown";
      if IsDefined(owner) {
        let p: Vector4 = owner.GetWorldPosition();
        where = "at=" + ToString(p.X) + "," + ToString(p.Y) + "," + ToString(p.Z);
      }
      LogChannel(n"DEBUG", "[NetSec] GAP people no-network " + where);
    } else if !hasAccess {
      LogChannel(n"DEBUG", "[NetSec] LOCKED people reason=UNBREACHED");
    }
  }

  // WHAT WAS OFFERED AT ALL, not merely what got blocked.
  //
  // The blocked-action log alone cannot tell "ping was allowed" from "ping was
  // never on the list", because both produce silence - and that ambiguity was
  // read as proof the mod does not touch ping. It was not proof of anything:
  // the log came from the build that had just been changed to allow ping.
  //
  // This line lists everything the game handed us BEFORE NetSec judges any of
  // it, so the two cases are distinguishable and the claim can be checked
  // instead of assumed.
  if cfg.debugLogging {
    let k: Int32 = 0;
    let all: String = "";
    while k < ArraySize(Deref(puppetActions)) {
      let pa: ref<PuppetAction> = Deref(puppetActions)[k];
      if IsDefined(pa) {
        let pr: wref<ObjectAction_Record> = pa.GetObjectActionRecord();
        if IsDefined(pr) { all += " " + ToString(pr.ActionName()); }
      }
      k += 1;
    }
    LogChannel(n"DEBUG", "[NetSec] OFFERS people (" + ToString(ArraySize(Deref(puppetActions)))
      + ") ->" + all);
  }

  let i: Int32 = 0;
  while i < ArraySize(Deref(puppetActions)) {
    let action: ref<PuppetAction> = Deref(puppetActions)[i];
    if IsDefined(action) {

      let allowed: Bool = hasAccess;
      let record: wref<ObjectAction_Record> = action.GetObjectActionRecord();

      // Category gate applies even once you are in: access says you can reach
      // them, Intelligence says what you can do to them.
      if allowed && IsDefined(record) {
        allowed = NetSecProgression.AllowsHackCategory(record.HackCategory().EnumName(), gi);
      }

      // Reconnaissance and noise-making survive a locked network if configured.
      //
      // PING HAS BEEN MATCHED TWO DIFFERENT WRONG WAYS, so it is now matched
      // three ways at once and none of them is load-bearing alone.
      //
      // The device side matches the action NAME `PingDevice`, and that provably
      // works - ping stays available on a locked device. The people side was
      // written to match the CLASS `PingSquad` by cast, on the reasoning that an
      // action's name is not its type. Both `PingSquad` and `PingDevice` exist
      // in the compiled bundle, and which identity a puppet's ping action
      // actually carries was never once looked up - it was guessed as a name,
      // reported broken, guessed as a class, and reported broken again.
      //
      // So: the cast, the exact name, or any action whose name contains "Ping".
      // The substring is the safety net, and it is deliberately loose. The cost
      // of matching one action too many is that a player can ping something they
      // could not fry; the cost of matching none is that the player cannot see
      // the network the whole mod is asking them to find.
      if !allowed && cfg.alwaysAllowPing {
        if IsDefined(action as PingSquad) {
          allowed = true;
        } else if IsDefined(record) {
          let an: String = ToString(record.ActionName());
          if StrContains(an, "Ping") || StrContains(an, "ping") { allowed = true; }
        }
      }
      if !allowed && cfg.alwaysAllowWhistle && IsDefined(record) && Equals(record.ActionName(), n"Whistle") {
        allowed = true;
      }

      // BREACHING A PERSON IS HOW YOU GET IN, so gating it behind being in is
      // the same catch-22 that was fixed for devices a version ago and not
      // carried across. The device whitelist has allowed RemoteBreach since
      // then; people never did, so an NPC breach was greyed out by the rule it
      // is the entry condition for. The log named it in one scan.
      if !allowed && IsDefined(record) && Equals(record.ActionName(), n"RemoteBreach") {
        allowed = true;
      }

      // WHAT IS THIS ACTION, ACTUALLY. One scan of one enemy answers for good
      // what two releases of guessing did not: the name every blocked NPC action
      // carries, so the next person to gate one matches on a fact.
      if !allowed && cfg.debugLogging {
        let an2: String = "none";
        if IsDefined(record) { an2 = ToString(record.ActionName()); }
        LogChannel(n"DEBUG", "[NetSec] BLOCKED people action=" + an2
          + " isPingSquadClass=" + ToString(IsDefined(action as PingSquad)));
      }

      if !allowed {
        action.SetInactiveWithReason(false, "LocKey#7021");
      }
    }
    i += 1;
  }

}
