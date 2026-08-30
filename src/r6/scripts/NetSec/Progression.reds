// ============================================================================
// NetSec - Progression
// ============================================================================
//
// Breaching decides whether you have ACCESS to a network. Intelligence decides
// whether you are good enough to use a given class of hack on it. Those are two
// different questions and NetSec keeps them separate, because a player who
// cannot use a quickhack deserves to know which of the two is stopping them.
//
// Better Netrunning could also gate on cyberdeck quality and enemy rarity, and
// ANDed all three together via a "require all" switch. Three overlapping gates
// make "why is this greyed out?" genuinely hard to answer, and the install this
// was written for had two of the three switched off. NetSec gates on
// Intelligence alone.
// ============================================================================

module NetSec.Progression

import NetSec.Config.*
import NetSec.State.*

public class NetSecProgression {

  public static func Intelligence(gi: GameInstance) -> Int32 {
    let stats: ref<StatsSystem> = GameInstance.GetStatsSystem(gi);
    let player: ref<PlayerPuppet> = GetPlayer(gi);
    if !IsDefined(stats) || !IsDefined(player) { return 0; }
    return Cast<Int32>(stats.GetStatValue(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatType.Intelligence));
  }

  // Device families.
  public static func AllowsTarget(target: NetSecTarget, gi: GameInstance) -> Bool {
    let cfg: ref<NetSecConfig> = new NetSecConfig();
    if !cfg.progressionEnabled { return true; }

    let intel: Int32 = NetSecProgression.Intelligence(gi);
    switch target {
      case NetSecTarget.Defence: return intel >= cfg.intDefences;
      case NetSecTarget.Camera:  return intel >= cfg.intCameras;
      // People are gated per hack category elsewhere; the ring-level answer is
      // the cheapest thing you can do to one, which is a covert hack.
      case NetSecTarget.People:  return intel >= cfg.intNPCsCovert;
      default:                   return intel >= cfg.intDevices;
    }
  }

  // Hacks aimed at people, keyed on the game's own HackCategory enum name.
  // Anything unrecognised is treated as a covert hack: unknown categories come
  // from other mods, and the gentlest gate is the right default for something
  // NetSec has never heard of.
  public static func AllowsHackCategory(category: CName, gi: GameInstance) -> Bool {
    let cfg: ref<NetSecConfig> = new NetSecConfig();
    if !cfg.progressionEnabled { return true; }

    let intel: Int32 = NetSecProgression.Intelligence(gi);
    if Equals(category, n"DamageHack")   { return intel >= cfg.intNPCsCombat; }
    if Equals(category, n"ControlHack")  { return intel >= cfg.intNPCsControl; }
    if Equals(category, n"UltimateHack") { return intel >= cfg.intNPCsUltimate; }
    return intel >= cfg.intNPCsCovert;
  }

  // WHAT A RING COSTS IN INTELLIGENCE, and the short name it goes by on screen.
  //
  // People are gated per hack CATEGORY rather than as one ring, so the number
  // reported for them is the covert threshold - the cheapest thing you can do to
  // a person. It is the honest answer to "can I do anything at all here yet",
  // which is the question somebody staring at a greyed-out wheel is asking.
  public static func RequirementFor(target: NetSecTarget) -> Int32 {
    let cfg: ref<NetSecConfig> = new NetSecConfig();
    switch target {
      case NetSecTarget.Camera:  return cfg.intCameras;
      case NetSecTarget.Defence: return cfg.intDefences;
      case NetSecTarget.People:  return cfg.intNPCsCovert;
      default:                   return cfg.intDevices;
    }
  }

  public static func ShortName(target: NetSecTarget) -> String {
    switch target {
      case NetSecTarget.Camera:  return "CAM";
      case NetSecTarget.Defence: return "DEF";
      case NetSecTarget.People:  return "PEOPLE";
      default:                   return "DEVICE";
    }
  }

  // TELL THEM WHAT THEY BOUGHT, AND WHAT THEY CANNOT SPEND YET.
  //
  // Breaching opens the network; Intelligence decides what you are good enough
  // to do on it. Those are two different gates and the player sees one outcome -
  // a quickhack that is still grey after a breach they just won. Without a word
  // on screen that reads as the mod being broken, and it is the single most
  // likely thing anybody reports.
  //
  // A ring is offered regardless of INT, on purpose: you can always breach for
  // the payout even when you cannot use half of what you opened. This is the
  // line that makes that feel deliberate rather than faulty.
  public static func Announce(tiers: array<NetSecTarget>, gi: GameInstance) -> Void {
    let cfg: ref<NetSecConfig> = new NetSecConfig();
    if !cfg.announceAccess || ArraySize(tiers) == 0 { return; }

    let granted: String = "";
    let locked: String = "";
    let i: Int32 = 0;
    while i < ArraySize(tiers) {
      let t: NetSecTarget = tiers[i];
      granted += NetSecProgression.ShortName(t) + " ";
      if cfg.progressionEnabled && !NetSecProgression.AllowsTarget(t, gi) {
        if StrLen(locked) > 0 { locked += ", "; }
        locked += NetSecProgression.ShortName(t) + " " + ToString(NetSecProgression.RequirementFor(t));
      }
      i += 1;
    }

    let text: String = "NETWORK ACCESS: " + granted;
    if StrLen(locked) > 0 { text += " // NEEDS INT: " + locked; }

    let msg: SimpleScreenMessage;
    msg.isShown = true;
    msg.duration = 4.0;
    msg.message = text;
    GameInstance.GetBlackboardSystem(gi)
      .Get(GetAllBlackboardDefs().UI_Notifications)
      .SetVariant(GetAllBlackboardDefs().UI_Notifications.WarningMessage, ToVariant(msg), true);
  }
}
