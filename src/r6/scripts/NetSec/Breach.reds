// ============================================================================
// NetSec - Breach
// ============================================================================
//
// The only way in. Breach an access point the normal way - the vanilla minigame,
// unmodified - and every device on that network opens.
//
// WHY THE VANILLA MINIGAME IS LEFT ALONE
//
// The minigame itself - the grid, the buffer, the sequences - is untouched.
// NetSec changes only WHICH PROGRAMS are on the board and what completing one
// means. Better Netrunning's idea of per-category daemons is here in full, as
// four nested rings; what is not here is any change to how the puzzle plays.
//
// The rings are nested rather than parallel on purpose: you are not buying four
// permissions, you are getting further into one network, and you cannot be
// deeper in the net than the turrets while still locked out of the doors.
//
// Every failure mode leans open. No access point means open; an incomplete
// offer stands the whole tiered rule down to a single unlock; the deepest ring
// is always on the board. A record that fails to load may cost a feature. It
// must never cost the network.
// ============================================================================

module NetSec.Breach

import NetSec.Config.*
import NetSec.State.*
import NetSec.Daemon.*
import NetSec.Progression.*

// RefreshSlaves runs after a successful access-point breach, over exactly the
// devices that breach earned. Wrapping it means NetSec never has to decide what
// "this network" means - the base game already decided, and any mod that
// changes network membership is automatically respected.

// GRANT WHAT WAS BOUGHT, AND NOTHING ELSE.
//
// UnlockAll survives as exactly one thing now: the fallback. Calling it on the
// tiered success path would hand over every ring regardless of what was
// uploaded - which is the bug already fixed once for the single daemon, where the
// daemon became decoration and the breach opened everything anyway. With four
// rings that mistake is four times as invisible, because three of them would
// still look like they had worked.
public func NetSecGrant(ps: ref<SharedGameplayPS>, tiers: array<NetSecTarget>, tiered: Bool, gi: GameInstance) -> Bool {
  if !IsDefined(ps) { return false; }
  if !tiered {
    NetSecState.UnlockAll(ps, gi);
    return true;
  }
  let i: Int32 = 0;
  while i < ArraySize(tiers) {
    NetSecState.StampRing(ps, tiers[i], gi);
    i += 1;
  }
  return ArraySize(tiers) > 0;
}

// Affiliation, without assuming a puppet has a record or that the record names
// one. Both are null on some spawns, and reading them blind crashed a breach.
public func NetSecAffiliationOf(pup: ref<ScriptedPuppet>, out aff: gamedataAffiliation) -> Bool {
  if !IsDefined(pup) { return false; }
  let rec: wref<Character_Record> = pup.GetRecord();
  if !IsDefined(rec) { return false; }
  let a: wref<Affiliation_Record> = rec.Affiliation();
  if !IsDefined(a) { return false; }
  aff = a.Type();
  return true;
}

@wrapMethod(AccessPointControllerPS)
private final func RefreshSlaves(const devices: script_ref<array<ref<DeviceComponentPS>>>) -> Void {
  // PAY BEFORE VANILLA LOOKS, and let vanilla decide how much.
  //
  // Tiered mode removes the three Datamines from the board, which removes the
  // eurodollars, components and shards with them. That hole is filled by handing
  // the base game the Datamine IDs a ring is judged to be worth, BEFORE its own
  // RefreshSlaves reads ActivePrograms off the blackboard - so the payout is
  // vanilla's, at vanilla's rates, through vanilla's ProcessLoot (which is
  // private and could not be called even if we wanted to).
  //
  // It also cleans up after itself: the same loop erases what it paid for and
  // writes the array back, so nothing we inject survives into anything else that
  // reads the blackboard afterwards.
  //
  // Only ever injected when NO generic Datamine is already there. In tiered mode
  // there cannot be one, but paying twice for the same breach is the kind of
  // thing that would go unnoticed for months.
  let cfgPre: ref<NetSecConfig> = new NetSecConfig();
  if cfgPre.enabled && cfgPre.requireAccessDaemon && cfgPre.ringsPayOut {
    let giPre: GameInstance = this.GetGameInstance();
    let bbPre: ref<IBlackboard> = GameInstance.GetBlackboardSystem(giPre).Get(GetAllBlackboardDefs().HackingMinigame);
    if IsDefined(bbPre) {
      let progs: array<TweakDBID> =
        FromVariant<array<TweakDBID>>(bbPre.GetVariant(GetAllBlackboardDefs().HackingMinigame.ActivePrograms));

      let sessPre: ref<NetSecSession> = NetSecSession.Get(giPre);
      let alreadyPaid: Bool = IsDefined(sessPre) && sessPre.HasPaid();
      let q: Int32 = 0;
      while q < ArraySize(progs) {
        if NetSecDaemon.IsGenericLoot(progs[q]) { alreadyPaid = true; }
        q += 1;
      }

      if !alreadyPaid {
        let earned: array<TweakDBID> =
          NetSecDaemon.LootFor(NetSecDaemon.Cumulative(NetSecDaemon.UploadedTiers(progs)));
        if ArraySize(earned) > 0 {
          let e: Int32 = 0;
          while e < ArraySize(earned) {
            ArrayPush(progs, earned[e]);
            e += 1;
          }
          bbPre.SetVariant(GetAllBlackboardDefs().HackingMinigame.ActivePrograms, ToVariant(progs));
          if IsDefined(sessPre) { sessPre.MarkPaid(); }
          if cfgPre.debugLogging {
            LogChannel(n"DEBUG", "[NetSec] rings paid out as " + ToString(ArraySize(earned))
              + " datamine tier(s)");
          }
        }
      }
    }
  }

  wrappedMethod(devices);

  let cfg: ref<NetSecConfig> = new NetSecConfig();
  if !cfg.enabled { return; }

  let gi: GameInstance = this.GetGameInstance();

  // WHICH DAEMONS DID THEY ACTUALLY UPLOAD?
  //
  // ActivePrograms is populated on the minigame blackboard once the breach
  // completes. If our access daemon is among them, that is the player choosing
  // access over loot and the network opens.
  //
  // If it is ABSENT we cannot tell "declined it" from "never offered it", and
  // the two want opposite outcomes. So the fallback is deliberately generous:
  // unless we saw the daemon on offer, completing a breach unlocks as it always
  // did. A player who skipped it loses nothing they had before; a broken record
  // cannot lock anybody out of every network in the game.
  // The blackboard is fetched from the game instance rather than through a
  // helper: GetMinigameBlackboard() is Better Netrunning's own @addMethod, not
  // a vanilla one, and borrowing a name from a mod that is not installed is how
  // a fork inherits a dependency it does not have.
  let bb: ref<IBlackboard> = GameInstance.GetBlackboardSystem(gi).Get(GetAllBlackboardDefs().HackingMinigame);
  let programs: array<TweakDBID>;
  if IsDefined(bb) {
    programs = FromVariant<array<TweakDBID>>(bb.GetVariant(GetAllBlackboardDefs().HackingMinigame.ActivePrograms));
  }

  // THE FALLBACK, WHICH USED TO BE A COMMENT AND NOT A CHECK.
  //
  // Requiring the daemon is only safe while the daemon is actually reaching the
  // breach screen. `WasOffered` is what makes the promise above true: if the
  // daemon never appeared - the record failed to load, vanilla changed, another
  // mod filtered it - the requirement stands down and the breach unlocks the
  // network exactly as it did before. Without this, a player who switched the
  // requirement on would have sealed every network in the game with no way back
  // in and nothing on screen explaining why.
  let session: ref<NetSecSession> = NetSecSession.Get(gi);

  // Same all-or-nothing rule as the dive path, and it has to be the same rule:
  // these two functions both resolve a breach, and if they disagreed about what
  // was bought a wired network and an adopted one would grant different things
  // from the same upload.
  let tiered: Bool = cfg.requireAccessDaemon
                  && IsDefined(session) && session.OfferWasComplete();
  let tiers: array<NetSecTarget>;

  if tiered {
    tiers = NetSecDaemon.Cumulative(NetSecDaemon.UploadedTiers(programs));
    if ArraySize(tiers) == 0 {
      if cfg.debugLogging {
        LogChannel(n"DEBUG", "[NetSec] breach completed with no ring daemon - no unlock");
      }
      return;
    }
  } else if cfg.requireAccessDaemon && cfg.debugLogging {
    LogChannel(n"DEBUG", "[NetSec] ring daemons were not all offered - unlocking everything (fallback)");
  }

  // RECORD WHERE THIS HAPPENED, so a stranded network nearby can accept it.
  //
  // An access point spawned into the world by a world-edit mod has no slaves -
  // membership lives in sector node data and nothing wires a new device into an
  // existing graph. This is the wiring, supplied in script: the breach publishes
  // its position, and Devices.reds lets stranded devices within the configured
  // radius treat it as their own.
  let apOwner: ref<GameObject> = this.GetOwnerEntityWeak() as GameObject;
  if IsDefined(apOwner) {
    let session: ref<NetSecSession> = NetSecSession.Get(gi);
    if IsDefined(session) {
      session.RecordBreachAt(apOwner.GetWorldPosition(), NetSecState.Now(gi));
      if cfg.debugLogging {
        let bp: Vector4 = apOwner.GetWorldPosition();
        LogChannel(n"DEBUG", "[NetSec] breach recorded at "
          + ToString(RoundF(bp.X)) + "," + ToString(RoundF(bp.Y)) + "," + ToString(RoundF(bp.Z)));
      }
    }
  }

  // The chain clock, on the wired path too.
  NetSecState.RecordBreachNow(gi);

  // The access point is part of its own network.
  NetSecGrant(this, tiers, tiered, gi);

  let count: Int32 = 0;
  let i: Int32 = 0;
  while i < ArraySize(Deref(devices)) {
    let shared: ref<SharedGameplayPS> = Deref(devices)[i] as SharedGameplayPS;
    if IsDefined(shared) {
      NetSecGrant(shared, tiers, tiered, gi);
      count += 1;
    }
    i += 1;
  }

  NetSecProgression.Announce(tiers, gi);

  if cfg.debugLogging {
    LogChannel(n"DEBUG", "[NetSec] breach opened " + ToString(count) + " device(s) for "
      + ToString(cfg.unlockDurationHours) + "h");
  }
}

// ============================================================================
// Failing a breach
// ============================================================================
//
// THE HOOK IS FinalizeNetrunnerDive, and finding it mattered: an earlier
// attempt guessed OnAccessPointMiniGameStatus and the compiler rejected it -
// that handler lives on ScriptedPuppet, not on the access point.
//
// wrappedMethod IS CALLED FIRST, AND THAT IS THE FEATURE. Vanilla's failure
// path calls SendMinigameFailedToAllNPCs(): the room hears you. Better
// Netrunning wrapped this same method specifically to SKIP that call, trading
// the instant alert for a slow interruptible trace. NetSec keeps vanilla's
// alert by not removing it, then escalates on top.
//
// The model is a forced lock: noise at the site, the console trips instantly,
// the call chain starts.
@wrapMethod(AccessPointControllerPS)
public func FinalizeNetrunnerDive(state: HackingMinigameState) -> Void {
  // Vanilla first - including the NPC alert on failure.
  wrappedMethod(state);

  let cfg: ref<NetSecConfig> = new NetSecConfig();
  if !cfg.enabled { return; }

  // SUCCESS IS HANDLED HERE, NOT ONLY IN RefreshSlaves.
  //
  // RefreshSlaves was the only unlock path until now, and it simply does not
  // run for an access point with no real slaves - measured: eight access points
  // registered, a daemon offered and uploaded, and ZERO "breach opened" lines
  // ever. The breach completed and nothing downstream fired, so quickhacks
  // stayed locked on everything including NPCs.
  //
  // FinalizeNetrunnerDive always runs, which makes it the honest place for
  // "this breach succeeded". RefreshSlaves keeps its own path for the ordinary
  // case of a wired network; this covers the adopted one.
  if Equals(state, HackingMinigameState.Succeeded) {
    let gi: GameInstance = this.GetGameInstance();
    let session: ref<NetSecSession> = NetSecSession.Get(gi);

    // THE DAEMON REQUIREMENT HAS TO LIVE HERE TOO.
    //
    // It was written once, in RefreshSlaves - which never runs for an adopted
    // access point. So this path, added later to make adopted networks work
    // at all, opened them unconditionally and the daemon became decoration:
    // reported from play as a breach where one program uploaded, it was not
    // NETWORK ACCESS, and the network opened anyway.
    //
    // Same rule as the other path: the requirement only binds if the daemon was
    // actually on offer, so a record that fails to load can never seal a
    // network.
    let bb: ref<IBlackboard> = GameInstance.GetBlackboardSystem(gi).Get(GetAllBlackboardDefs().HackingMinigame);
    let programs: array<TweakDBID>;
    if IsDefined(bb) {
      programs = FromVariant<array<TweakDBID>>(bb.GetVariant(GetAllBlackboardDefs().HackingMinigame.ActivePrograms));
    }
    // WHICH RINGS DID THEY PAY FOR, and is the tiered promise safe to keep?
    //
    // The offer has to have been COMPLETE. A target that showed two of the four
    // daemons would hand back a network that is half open, and the player cannot
    // tell that apart from having chosen to upload two - nor can NetSec. So
    // unless every ring reached the screen, the tiered rule stands down and this
    // behaves exactly as it did before tiering existed. A record that fails to
    // load may cost a feature; it must never cost the network.
    let tiered: Bool = cfg.requireAccessDaemon
                    && IsDefined(session) && session.OfferWasComplete();
    let tiers: array<NetSecTarget>;

    if tiered {
      tiers = NetSecDaemon.Cumulative(NetSecDaemon.UploadedTiers(programs));
      if ArraySize(tiers) == 0 {
        if cfg.debugLogging {
          LogChannel(n"DEBUG", "[NetSec] DIVE SUCCEEDED but no ring daemon uploaded - paid, not in ("
            + ToString(ArraySize(programs)) + " program(s) run)");
        }
        return;
      }
    } else if cfg.requireAccessDaemon && cfg.debugLogging {
      LogChannel(n"DEBUG", "[NetSec] tiering stood down - ring daemons did not all reach the screen; unlocking everything");
    }

    let owner: ref<GameObject> = this.GetOwnerEntityWeak() as GameObject;
    if IsDefined(session) && IsDefined(owner) {
      let here: Vector4 = owner.GetWorldPosition();
      session.RecordBreachAt(here, NetSecState.Now(gi));
      // The chain clock: this breach refreshes every hold still inside its lease.
      NetSecState.RecordBreachNow(gi);
      // A breach is the moment the registries are about to be walked, so it is
      // the right moment to drop what is no longer there.
      session.Sweep();

      // EVERY DEVICE IN REACH, not only the ones already inspected.
      //
      // This used to walk m_strandedDevices, which is filled when the player
      // AIMS at something - so a breach opened the devices already looked at and
      // silently missed the rest. The registry is filled at GameAttached now, so
      // this is what is genuinely streamed in.
      let radius: Float = Cast<Float>(cfg.adoptionRadius);
      let near: array<ref<ScriptableDeviceComponentPS>> = session.DevicesNear(here, radius);
      let opened: Int32 = 0;
      let i: Int32 = 0;
      while i < ArraySize(near) {
        if IsDefined(near[i]) && NetSecGrant(near[i], tiers, tiered, gi) { opened += 1; }
        i += 1;
      }

      // The access point is on its own network.
      NetSecGrant(this, tiers, tiered, gi);

      NetSecProgression.Announce(tiered ? tiers : NetSecDaemon.Cumulative(NetSecDaemon.UploadedTiers(programs)), gi);

      // MAKE THE ADOPTED NETWORK PAY, by making vanilla's own payout run.
      //
      // The loot lives inside AccessPointControllerPS.RefreshSlaves, and on an
      // adopted access point RefreshSlaves never runs - the whole reason this
      // dive path exists. So a placed access point granted access and paid
      // nothing, which is a rule nobody chose and would have read as the mod
      // being stingy about its own content.
      //
      // OnRefreshSlavesEvent runs RefreshSlaves whenever IsON() or the event is
      // FORCED (accessPointController.script:1242), so a forced event queued at
      // ourselves gets vanilla to do its own accounting. Everything downstream
      // of that is the base game's: its rates, its notification, its cleanup.
      //
      // Safe to fire unconditionally because the PAYMENT is guarded, not the
      // trigger - if vanilla's RefreshSlaves already ran and paid for this
      // breach, the injection above finds it marked and adds nothing. That is
      // deliberate: the order these two paths run in is not something to depend
      // on.
      if cfg.ringsPayOut && IsDefined(session) && !session.HasPaid() {
        let refresh: ref<RefreshSlavesEvent> = new RefreshSlavesEvent();
        refresh.force = true;
        this.QueuePSEvent(this, refresh);
        if cfg.debugLogging {
          LogChannel(n"DEBUG", "[NetSec] adopted network - forcing vanilla RefreshSlaves so the rings pay out");
        }
      }

      // PEOPLE ARE NOT DEVICES, and the People ring has nothing to stamp unless
      // it is stamped here. A device carries its rings on its own persistent
      // state; a puppet is opened through m_netSecExposedAt. Without this the
      // People daemon would upload, cost buffer, and appear to do nothing while
      // the other three worked.
      let peopleOpened: Int32 = 0;
      if !tiered || ArrayContains(tiers, NetSecTarget.People) {
        let crew: array<ref<ScriptedPuppetPS>> = session.StationedNear(here, radius);
        let j: Int32 = 0;
        while j < ArraySize(crew) {
          if IsDefined(crew[j]) {
            crew[j].m_netSecExposedAt = NetSecState.Now(gi);
            peopleOpened += 1;
          }
          j += 1;
        }
      }

      if cfg.debugLogging {
        let what: String = "everything";
        if tiered {
          what = "";
          let t2: Int32 = 0;
          while t2 < ArraySize(tiers) {
            what += NetSecDaemon.TierName(tiers[t2]) + " ";
            t2 += 1;
          }
        }
        LogChannel(n"DEBUG", "[NetSec] DIVE SUCCEEDED - granted [" + what + "] to "
          + ToString(opened) + " device(s) and " + ToString(peopleOpened)
          + " person(s); " + ToString(session.DeviceCount()) + " device(s) known, at "
          + ToString(RoundF(here.X)) + "," + ToString(RoundF(here.Y)));
      }
    }
    return;
  }

  if NotEquals(state, HackingMinigameState.Failed) { return; }

  // FAILURE HAS TO REACH THE ADOPTED SET, exactly as success does.
  //
  // Reported from play: a failed breach at an adopted access point did nothing
  // at all - no revoke, no alarm. Both halves have the same cause as the unlock
  // bug. RevokeAll(this) only ever touched the access point itself, and
  // vanilla's SendMinigameFailedToAllNPCs tells the NPCs ON THAT NETWORK, which
  // for an adopted access point is nobody. So the console trips and the room
  // does not hear it.
  if cfg.failureRevokesAccess {
    NetSecState.RevokeAll(this);

    let gi2: GameInstance = this.GetGameInstance();
    let session: ref<NetSecSession> = NetSecSession.Get(gi2);
    let owner2: ref<GameObject> = this.GetOwnerEntityWeak() as GameObject;

    if IsDefined(session) && IsDefined(owner2) {
      let here: Vector4 = owner2.GetWorldPosition();
      let radius: Float = Cast<Float>(cfg.adoptionRadius);
      let revoked: Int32 = 0;
      let alerted: Int32 = 0;

      // Devices this access point had adopted lose what they held.
      let i: Int32 = 0;
      while i < ArraySize(session.m_strandedDevices) {
        let dev: ref<ScriptableDeviceComponentPS> = session.m_strandedDevices[i];
        if IsDefined(dev) {
          let dOwner: ref<GameObject> = dev.GetOwnerEntityWeak() as GameObject;
          if IsDefined(dOwner) {
            let p: Vector4 = dOwner.GetWorldPosition();
            let dx: Float = p.X - here.X; let dy: Float = p.Y - here.Y; let dz: Float = p.Z - here.Z;
            if SqrtF(dx*dx + dy*dy + dz*dz) <= radius {
              NetSecState.RevokeAll(dev);
              revoked += 1;
            }
          }
        }
        i += 1;
      }

      // And the people near it lose their stamp, so a failed dive costs the
      // access a successful one would have granted rather than being free.
      let j: Int32 = 0;
      while j < ArraySize(session.m_npcs) {
        let npc: ref<ScriptedPuppetPS> = session.m_npcs[j];
        if IsDefined(npc) {
          let nOwner: ref<GameObject> = npc.GetOwnerEntityWeak() as GameObject;
          if IsDefined(nOwner) {
            let p2: Vector4 = nOwner.GetWorldPosition();
            let ex: Float = p2.X - here.X; let ey: Float = p2.Y - here.Y; let ez: Float = p2.Z - here.Z;
            if SqrtF(ex*ex + ey*ey + ez*ez) <= radius {
              npc.m_netSecExposedAt = 0.0;
              alerted += 1;
            }
          }
        }
        j += 1;
      }

      // THE ALARM: point them at the player, not merely at a noise.
      //
      // SOURCED FROM THE NETWORK, because that is what was asked for and
      // because every other source was measurably wrong.
      //
      // Two earlier cuts, both kept here as a warning:
      //
      //   session.m_npcs alone - held only people NetSec had already evaluated,
      //   which meant people the player had scanned or aimed at. You breach
      //   BEFORE you look at anyone, so it was empty exactly when it mattered.
      //
      //   TSQ_ALL from the targeting system - view-limited. It answers "what
      //   could you shoot from here", not "who is present". Measured: four
      //   Tyger Claws 15 m from the access point missed entirely, and two
      //   civilians at 60 m returned instead.
      //
      // GetPuppets() is the game's OWN answer to "who is on this network", and
      // Adopt.reds now makes it include the stationed people this access point
      // adopted. So the set below is "everyone this access point unlocks" - the
      // same list a successful breach opens. That is the property worth having:
      // success and failure become two outcomes of one rule, instead of two
      // features that can quietly disagree about who is on the net.
      if cfg.failureRaisesAlarm {
        let player: ref<GameObject> = GetPlayer(gi2);
        if IsDefined(player) {
          let ppos: Vector4 = player.GetWorldPosition();
          let aRadius: Float = Cast<Float>(cfg.alarmRadius);

          let nearby: array<ref<ScriptedPuppet>>;

          // The network first.
          let links: array<ref<PuppetDeviceLinkPS>> = this.GetPuppets();
          let netCount: Int32 = 0;
          let n: Int32 = 0;
          while n < ArraySize(links) {
            // EVERY HOP GETS A CHECK. A registered link outlives the puppet it
            // describes, and dereferencing one of those is what crashed three
            // breaches in 1.5.x - twice inside code added to diagnose the
            // previous crash.
            let lnk: ref<PuppetDeviceLinkPS> = links[n];
            let lpup: ref<ScriptedPuppet>;
            if IsDefined(lnk) { lpup = lnk.GetOwnerEntityWeak() as ScriptedPuppet; }
            if IsDefined(lpup) && ScriptedPuppet.IsActive(lpup) && ScriptedPuppet.IsAlive(lpup)
               && !lpup.IsCivilian() && !ArrayContains(nearby, lpup) {
              ArrayPush(nearby, lpup);
              netCount += 1;
            }
            n += 1;
          }

          // FALLBACK, AND A REAL ONE RATHER THAN A HEDGE.
          //
          // A vanilla access point in a wired building answers the question
          // above completely. A mod-placed one with nothing adopted yet answers
          // it with nobody - and "the console tripped and not one person in the
          // compound reacted" is the bug being fixed here, so silence is not an
          // acceptable outcome of the fix for it.
          //
          // The registry is filled at OnGameAttached now rather than by being
          // looked at, so unlike the earlier version it actually has people in it.
          // Stationed only, so this can never rope in a passer-by.
          if ArraySize(nearby) == 0 {
            let stationed: array<ref<ScriptedPuppetPS>> = session.StationedNear(here, aRadius);
            let s: Int32 = 0;
            while s < ArraySize(stationed) {
              let sp: ref<ScriptedPuppet> = stationed[s].GetOwnerEntityWeak() as ScriptedPuppet;
              if IsDefined(sp) && !ArrayContains(nearby, sp) { ArrayPush(nearby, sp); }
              s += 1;
            }
            if cfg.debugLogging {
              LogChannel(n"DEBUG", "[NetSec] ALARM network empty - fell back to "
                + ToString(ArraySize(nearby)) + " stationed within " + ToString(RoundF(aRadius)) + "m");
            }
          }

          // WHOSE NET IS IT: the affiliation most common among the people at the
          // ACCESS POINT, not across the whole alarm radius. The crew holding
          // the terminal defines the network; anyone further out is a responder.
          // Most-common rather than nearest, so one stray by the console cannot
          // redefine whose net it is.
          let siteAff: gamedataAffiliation;
          let haveAff: Bool = false;
          if cfg.alarmSameFactionOnly {
            let bestCount: Int32 = 0;
            let a: Int32 = 0;
            while a < ArraySize(nearby) {
              // Validated at insert, but streaming can invalidate between then
              // and here, so re-check rather than trust the earlier pass.
              // redscript has NO continue statement, so this is a guarded block.
              if IsDefined(nearby[a]) {
              let ap2: Vector4 = nearby[a].GetWorldPosition();
              let ax2: Float = ap2.X - here.X; let ay2: Float = ap2.Y - here.Y; let az2: Float = ap2.Z - here.Z;
              if SqrtF(ax2*ax2 + ay2*ay2 + az2*az2) <= radius {
                let candidate: gamedataAffiliation;
                if NetSecAffiliationOf(nearby[a], candidate) {
                  let count: Int32 = 0;
                  let b: Int32 = 0;
                  while b < ArraySize(nearby) {
                    if IsDefined(nearby[b]) {
                    let bp2: Vector4 = nearby[b].GetWorldPosition();
                    let bx2: Float = bp2.X - here.X; let by2: Float = bp2.Y - here.Y; let bz2: Float = bp2.Z - here.Z;
                    let other: gamedataAffiliation;
                    if SqrtF(bx2*bx2 + by2*by2 + bz2*bz2) <= radius
                       && NetSecAffiliationOf(nearby[b], other)
                       && Equals(other, candidate) {
                      count += 1;
                    }
                    }
                    b += 1;
                  }
                  if count > bestCount { bestCount = count; siteAff = candidate; haveAff = true; }
                }
              }
              }
              a += 1;
            }
          }

          let raised: Int32 = 0;
          let k: Int32 = 0;
          while k < ArraySize(nearby) {
            let puppet: ref<ScriptedPuppet> = nearby[k];
            let mine: gamedataAffiliation;
            let known: Bool = NetSecAffiliationOf(puppet, mine);
            let sameCrew: Bool = !cfg.alarmSameFactionOnly || !haveAff || !known
                              || Equals(mine, siteAff);
            if IsDefined(puppet) && sameCrew {
              // HOSTILITY FIRST, or the rest is noise they have no reason to act
              // on. Measured: "ALARM - 4 nearby, 4 sent after the player" and
              // nothing happened in game. A notification and a stim tell a
              // neutral NPC that something occurred; neither gives them a reason
              // to shoot you.
              //
              // Turning attitude hostile is what converts "someone tripped the
              // net" into "the netrunner who did it is standing there".
              let theirAgent: ref<AttitudeAgent> = puppet.GetAttitudeAgent();
              let myAgent: ref<AttitudeAgent> = player.GetAttitudeAgent();
              if IsDefined(theirAgent) && IsDefined(myAgent) {
                theirAgent.SetAttitudeTowards(myAgent, EAIAttitude.AIA_Hostile);
              }

              // VANILLA'S OWN FAILED-BREACH EVENT IS NOT ENOUGH BY ITSELF, and
              // reading its handler is what settled an assumption this mod had
              // carried from early on. OnMinigameFailEvent
              // (scriptedPuppet.script:5769) does exactly two things: a
              // ProjectileDistraction stim, and AlertPuppet. That is "go and
              // look over there" - not hostility, not combat, and never a
              // direction to the player. So a perfectly wired VANILLA network
              // answers a blown breach with a shrug, and the README's claim that
              // "the room hears you" was always generous.
              //
              // It is still sent, because it is the message the base game's NPC
              // logic expects and other mods hook. The COMBAT notification and
              // the Combat stim below are the escalation on top of it.
              puppet.QueueEvent(new MinigameFailEvent());

              puppet.TriggerSecuritySystemNotification(ppos, player, ESecurityNotificationType.COMBAT);
              let stim: ref<StimBroadcasterComponent> = puppet.GetStimBroadcasterComponent();
              if IsDefined(stim) {
                stim.TriggerSingleBroadcast(player, gamedataStimType.Combat);
              }
              if cfg.debugLogging {
                let aff2: gamedataAffiliation;
                let known2: Bool = NetSecAffiliationOf(puppet, aff2);
                let pp: Vector4 = puppet.GetWorldPosition();
                let ddx: Float = pp.X - ppos.X; let ddy: Float = pp.Y - ppos.Y; let ddz: Float = pp.Z - ppos.Z;
                LogChannel(n"DEBUG", "[NetSec]   target class=" + ToString(puppet.GetClassName())
                  + " alive=" + ToString(ScriptedPuppet.IsAlive(puppet))
                  + " crowd=" + ToString(puppet.IsCrowd())
                  + " civilian=" + ToString(puppet.IsCivilian())
                  + " aff=" + (known2 ? ToString(EnumInt(aff2)) : "unknown")
                  + " distFromPlayer=" + ToString(RoundF(SqrtF(ddx*ddx + ddy*ddy + ddz*ddz))) + "m");
              }

              raised += 1;
            }
            k += 1;
          }

          if cfg.debugLogging {
            LogChannel(n"DEBUG", "[NetSec] ALARM - network=" + ToString(netCount)
              + " of " + ToString(ArraySize(links)) + " puppet link(s), registry="
              + ToString(session.NPCCount())
              + ", " + ToString(ArraySize(nearby)) + " to alert, "
              + ToString(raised) + " sent after the player; factionScoped="
              + ToString(cfg.alarmSameFactionOnly) + " identified=" + ToString(haveAff));
            if ArraySize(nearby) == 0 {
              LogChannel(n"DEBUG", "[NetSec] ALARM found nobody who would care - no people on this access point and no stationed NPC within "
                + ToString(RoundF(aRadius)) + "m");
            }
          }
        }
      }

      // The breach record itself is void - a failed dive must not leave a live
      // position behind that keeps opening things.
      session.ClearBreach();

      if cfg.debugLogging {
        LogChannel(n"DEBUG", "[NetSec] DIVE FAILED - revoked " + ToString(revoked)
          + " adopted device(s), cleared " + ToString(alerted) + " NPC stamp(s)");
      }
    }
  }

  // NO SECOND ALARM, and that is a finding rather than a gap.
  //
  // Vanilla's failure path already calls SendMinigameFailedToAllNPCs(), which
  // tells every NPC ON THAT NETWORK - which is precisely the call chain: the
  // console trips and everyone wired to it is told. Better Netrunning removed
  // that; NetSec keeps it by calling wrappedMethod above.
  //
  // Adding TriggerSecuritySystemNotification on top was tried and dropped. It
  // is declared on ScriptedPuppet, and an access point's owner is a device, so
  // there is no puppet to report it - the compiler said so. Reaching one would
  // mean walking the network for an NPC to speak on its behalf, to raise a
  // second alert alongside the one the game already raised. That is redundancy
  // with extra failure modes, not escalation.
  if cfg.debugLogging {
    LogChannel(n"DEBUG", "[NetSec] breach FAILED - vanilla alert kept, revoked=" + ToString(cfg.failureRevokesAccess));
  }
}
