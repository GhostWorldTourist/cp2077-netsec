# NetSec: Make Netrunning Strategic Again

The year is 2077. Most of the world knows about quickhacks: dangerous software that can be emitted into your skull by someone just *thinking about it*. So why the hell is no one implementing network security? There was an implementation in the game, but it was a ridiculous, boring power creep. Let's bring it back, the right way. NetSec is a mod for Cyberpunk 2077 that locks out networks from hacking until *you* hack in: any access point, vending machine, forklift with a jack in slot is suddenly your doorway into pwning the network. Breach as far as you can in the hacking minigame and you can gain some or even total control. This mod is built upon the excellent foundation laid by Kei Sagano in [Better Netrunning Fix](https://www.nexusmods.com/cyberpunk2077/mods/24482). If you're a Japanese player, Kei has made translations of many of the most popular CP2077 mods; go [check them out](https://www.nexusmods.com/profile/KeiSagano/mods)!

This re-imagining of Better Netrunning offers numerous improvements over [the original Better Netrunning](https://www.nexusmods.com/cyberpunk2077/mods/2302) by finley243 and the fix Kei created. Most importantly, this mod shouldn't cause the crashes and save instabilities the earlier versions could introduce.

## Hacking Options
When you hack one of these jack-in points, you'll see some new options:

### /DEVICE/ (Requires INT 4)
This gets you access only to devices on the network: doors, windows, microwaves, gas tanks, that sort of thing.

### /DEVICE|CAM/ (Requires INT 5)
Same as above, but also cameras for control and disabling purposes.

### /DEVICE|CAM|DEF/ (Requires INT 6)
Same as above, but also defences like turrets and bots.

### /ALL/
Full network access, which is required to hack personnel. It grants everything above it too.

There is no single INT number on this one: each ring keeps its own requirement, and quickhacks on people have four of their own (see below). Uploading /ALL/ always works — Intelligence only decides how much of what you took you can actually use.

## Things to Know
1. If you fail to hack anything at all, either by completely failing the hacking minigame or canceling out of it before any hacks are complete, the crew whose net you touched is coming for you. People are terrified of getting quickhacked. They will dispose of any suspected netrunners with extreme prejudice.

2. A breached network stays open for 2 in-game hours, measured from your **most recent breach anywhere** — so keep working and you keep what you hold; walk away and it all lapses together. Someone notices the quiet and resets security. (Configurable in options.)

3. Each of the types of access have default intelligence requirements. If you lack the needed INT, you can still hack the tier, but a HUD message will tell you what access you gained and what access you needed higher INT to get.

4. Quickhacks on NPCs have tiered requirements by default: 4 for covert hacks, 5 for damage hacks, 6 for control, and 9 for ultimate quickhacks.

5. Tiered breaching takes the three Datamine daemons off the board and puts the rings there instead. You do not lose the income — see below — but if you are used to Datamines, that is where they went.

6. You get the rewards from hacking still: /DEVICE/ and /DEVICE|CAM/ give you eurodollars, /DEVICE|CAM|DEF/ give you components and eddies, and /ALL/ gives you those plus a chance at a quickhack shard (you can turn this off in options).

7. If a device or person isn't on a network with a way in, it stays unlocked. Stupid gonk shoulda set up a net; they get what they get.

8. I have placed some access points in the world where APs previously did not exist (just 1 in Kabuki for now; more to come).

## Options

Everything below is in the **Mod Settings** menu, under NetSec. Defaults are what you get if you never open it, and the defaults are a complete game — you do not have to configure anything.

### Access

| Option | Default | What it does |
|---|---|---|
| **Enable NetSec** | On | The master switch. Off gives you the vanilla quickhack rules back. |
| **Tiered breaching** | On | The rings. Off leaves the vanilla breach board alone, and any completed breach opens the whole network. |
| **Rings pay out like Datamines** | On | A ring pays what the matching Datamine would have — eurodollars, components at any tier above, a quickhack shard chance at ALL. Off means you breach for access and nothing else. |
| **Unlock devices with no access point** | On | Some networks have no way in at all. This leaves those open, because a device that exists only to refuse you is a bug and not a difficulty setting. Turn it off for the harsh game. |
| **Stationed NPCs are on the local network** | On | Guards and gangers posted near an access point are behind it, even where the game never wired them to one. Pedestrians, drivers and civilians are never affected. |
| **Adopt stranded devices onto a nearby access point** | On | A device whose own way in does not exist anywhere in the world joins the nearest real access point instead. |
| **Adoption radius** | 50 m | How far an access point reaches when adopting stranded devices and posted people. |
| **Give stranded breach points a jack-in port** | On | A locked device on a sealed network gets a physical port, so there is always one way in. Devices you *can* already reach are untouched. |
| **Stranded-network breach radius** | 50 m | How far a breach reaches into a network that has no way in of its own. Networks you can reach are never affected at any distance. |
| **Ping is always available** | On | Ping keeps working on locked targets. Turning this off means hunting for the way in with no help from the red lines. |
| **Whistle is always available** | Off | Distraction hacks stay usable on locked NPCs. |
| **Distract is always available** | Off | Distraction hacks stay usable on locked devices. |

### Duration

| Option | Default | What it does |
|---|---|---|
| **Access lasts (in-game hours)** | 2 | How long a breached network stays open — measured from your **last breach anywhere**, so a working netrunner keeps what they hold and someone who walks away loses it all together. Set 0 for permanent. |

### Progression

Breaching gets you *in*. Intelligence decides what you are good enough to *do* once you are there. If a quickhack is still greyed out after a successful breach, this is why.

| Option | Default |
|---|---|
| **Gate hacks behind Intelligence** | On — off means a breach opens everything |
| INT — devices (doors, terminals) | 4 |
| INT — cameras | 5 |
| INT — defences (turrets, drones, mechs) | 6 |
| INT — covert hacks on people | 4 |
| INT — damage hacks on people | 5 |
| INT — control hacks on people | 6 |
| INT — ultimate hacks on people | 9 |

### Consequences

| Option | Default | What it does |
|---|---|---|
| **A failed breach raises the alarm** | On | Blowing a breach tells the crew where you are and sends them after you. |
| **Alarm radius** | 120 m | How far it carries. Deliberately wider than the adoption radius — a tripped net brings the building, not the room. |
| **Only the owning crew answers** | On | The alarm reaches the crew holding the access point. A Maelstrom passer-by does not care that you tripped a Tyger Claw net. Off means everyone in range answers. |
| **A failed breach reboots the network** | On | Losing a breach also revokes access you already held there. Someone noticed and restarted the system from clean storage. |

### Diagnostics

| Option | Default | What it does |
|---|---|---|
| **Log decisions to the game log** | Off | Writes one line per locked target saying *which* rule locked it, and flags networks that came out open because they had no access point. Useful if you want to help find places that still need one. |

Settings are stored in `red4ext/plugins/mod_settings/user.ini`, so you can read, diff and back them up like any other text file.

## Requirements and Compatibility

### Requirements

| | Why |
|---|---|
| **[RED4ext](https://www.nexusmods.com/cyberpunk2077/mods/2380)** | Runs the two frameworks below. |
| **[redscript](https://www.nexusmods.com/cyberpunk2077/mods/1511)** | The mod is redscript. |
| **[TweakXL](https://www.nexusmods.com/cyberpunk2077/mods/4197)** | Declares the ring daemons. |
| **[ArchiveXL](https://www.nexusmods.com/cyberpunk2077/mods/4198)** | Supplies NetSec's own on-screen strings, and registers the access points it places in the world. |
| **[Mod Settings](https://www.nexusmods.com/cyberpunk2077/mods/4885)** | Draws the options menu. |

That is the whole list. **No CET, no Codeware, no CustomHackingSystem** — NetSec needs no Lua and ships no database.

Written and tested against game version **2.31**.

### Known conflicts

**Do not run this with [Better Netrunning](https://www.nexusmods.com/cyberpunk2077/mods/2302) or [Better Netrunning Fix](https://www.nexusmods.com/cyberpunk2077/mods/24482).** NetSec is a rewrite of the same idea and gates the same methods. They will fight. Uninstall the other one first. Other mods that change quickhacking are likely to be okay, but it depends on what they change.

### Specifically compatible

- **[Vehicle Security Rework](https://www.nexusmods.com/cyberpunk2077/mods/5092)** — vehicles are explicitly exempt. NetSec never gates a car, because car security is that mod's job and it does it properly. (You should totally get this mod, it's awesome)
- **Vending machines** are never gated either. They are the corner shop, not security infrastructure — and they stay usable as a way *into* a network.
- **Quest daemons are never removed.** Tiered breaching clears the three generic Datamines by exact ID and touches nothing else, so mission-critical programs stay on the board.

### Your save

NetSec adds six persistent fields — four to devices, one to people, one to the player — to remember what you have breached and when. Adding them is safe and does not alter anything the base game stores.

Removing them is the ordinary redscript uninstall case and should be equally safe, but **this has not yet been tested on a real save**, so treat uninstalling mid-playthrough as untested rather than as known-good. Turning **Enable NetSec** off is always safe: nothing is gated, and the stored timestamps simply stop being read.

### Nerd notes

NetSec uses **no `@replaceMethod` anywhere**. Every hook is a `@wrapMethod`, which means other mods touching the same methods still run — a replace would claim the method exclusively and silently delete whatever else wanted it. Twelve methods in total:

```
SharedGameplayPS.GetAccessPoints            MasterControllerPS.GetImmediateSlaves
MasterControllerPS.GetPuppets               AccessPointControllerPS.RefreshSlaves
AccessPointControllerPS.FinalizeNetrunnerDive
AccessPointControllerPS.GameAttached        ScriptableDeviceComponentPS.GameAttached
ScriptableDeviceComponentPS.FinalizeGetQuickHackActions
ScriptedPuppet.OnGameAttached               ScriptedPuppetPS.GetAllChoices
ScriptedPuppetPS.OnSetExposeQuickHacks
MinigameGenerationRuleScalingPrograms.FilterPlayerPrograms
```

Another mod that wraps these will co-exist mechanically, but if it has its own opinion about *what may be quickhacked*, expect the two to disagree.

#### Make your own way in

Night City has networks with a breach marker and nothing you can reach — a rooftop dish, a sealed yard, a shop cluster wired to nobody. NetSec leaves those open by default rather than taunting you with them, but the better answer is an access point that should have been there all along. **If you find one and place it, send it to me and I'll add it to the mod as soon as I can, giving you credit in the mod description for your work.**

You need [World Builder](https://www.nexusmods.com/cyberpunk2077/mods/12871) (formerly Object Spawner). Everything below happens in-game.

1. Find a spot that needs one. Turn on **Diagnostics → Log decisions** and play normally. Lines tagged `GAP` in `bin\x64\plugins\cyber_engine_tweaks\scripting.log` are the holes — a device or a person that came out open because nothing on their network could ever be breached. Each carries coordinates. Or just trust your eyes: if a place *feels* like it should have security and doesn't, it probably should.

2. Spawn the access point. In World Builder's **Spawn New** tab, search `accesspoint` and pick:

```
base\gameplay\devices\masters\access_points\accesspoint.ent
```

Then the part that's easy to get wrong: there are **two dropdowns**. The first is `Object type`. Leave it on **Entity**. The second says `Template`. Change that to **Device**.

> Template gives you a `worldEntityNode`, which looks identical in the world and is not a device. It has no persistent state and no seat in the network graph, and nothing will work. **Device** gives you a `worldDeviceNode`.

Avoid `virtual_accesspoint.ent`. It's meshless and offers no interaction. Vanilla uses it as a network's invisible hub, not as a thing you jack into.

3. Set it up. In the node's properties:

- **Persistent**: tick it. Without this the access point forgets it was ever breached.
- **Node Ref**: press the ⟳ button beside the field to generate a unique one. Don't type your own; duplicates collide.
- **Device Class Name** should fill itself in as `AccessPointControllerPS`.
- Appearance `access_point_arasaka_access_point_b` is the one used so far.

4. Place it somewhere a person would. This is the part that actually matters, and it's judgement rather than procedure. Good placements are **reachable on foot**, sit where a real installation would (a wall, a pole, a service alcove, that sort of thing), and are **within about 50 m of the things they should serve**, which is NetSec's adoption radius.

5. Save the group, THEN export. Put the node in a group in the **Spawned** tab and press save. This order is not optional: the Export tab reads the *saved file off disk*, not your live session, so exporting an unsaved group silently gives you an empty file with no nodes in it.

6. Export it. In the **Export** tab: add your group, give the project a name, set **XL Format** to **YAML**, and press Export. That writes to:

```
bin\x64\plugins\cyber_engine_tweaks\mods\entSpawner\export\<yourname>_exported.json
```

**Send me that file.** It carries the entity path, the exact position and rotation, the streaming ranges and the appearance — everything needed to build it into the mod properly as a `.streamingsector`. A screenshot of where it is and a line about why it belongs there helps me judge it; the coordinates alone don't say whether a placement is *good*.

If the export has `"nodes": []` in it, go back to step 5 — the group wasn't saved.

## Credits

NetSec wouldn't exist without the important foundational work from these modders:
[the original Better Netrunning](https://www.nexusmods.com/cyberpunk2077/mods/2302) by finley243
[Better Netrunning Fix](https://www.nexusmods.com/cyberpunk2077/mods/24482) by Kei Sagano

NetSec was built with AI assistance from [Cyberwise](https://github.com/GhostWorldTourist/cyberwise), a suite of AI tools for working with modded Cyberpunk 2077 games. If you're interested, I'd love feedback on it. To those opposed to it based on its description, I respect your right to that opinion, and I'm very aware of how many poorly written tools and ideas there are for using AI for modded games. Please try to understand I've spent considerable time and expertise on this; look into it before you call it "slop", please and thank you.