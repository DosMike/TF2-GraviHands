# TF2 Gravity Hands

I want to make puzzle/coop maps for TF2 similar to HL2DM Puzzle servers.
This requires a gravity gun in most cases to move around props, so this is the main aspect.

For now I'll only implement the Gravity Gun, a separate plugin for custom map logic is planned,
but I'm waiting for the new entity lump API in SM 1.11 that hopefully is as flexible as nosoop's draft.

But why am I not using [TF2_PhysicsGun](https://github.com/BattlefieldDuck/TF2_PhysicsGun) or
[Gravity Gun Mod](https://forums.alliedmods.net/showthread.php?p=1294817)?
Well simply put those plugin are too powerful for what I want. Those plugins implement a
Super-PhysGun style of prop handling while I want a normal Gravity Gun behaviour of pull stuff,
pick it up and throw it. After all, every player is supposed to be allowed to manipulate props
with it, and that in the style of HL2DM Puzzle maps!

## Gravity Hands

Players can use `/hands` or `/holster` to put away their weapons. (`+attack3` while holding the melee is 
currently aliased to this as well, but I might change that in the future).
This equips players with non-damaging fists (breaking heavys stock fists in the process but whatever).
Physics props below a mass of 250 can be moved around with right click and can be punted away.
It tries to fire apropriate physgun related outputs and to honor frozen and motion disabled props.

Left-clicking while holding a prop will punt it, otherwise left-click is just a normal melee punch.

I know that it's not perfect and you can work props through walls, but it should work well enough.
(aka I don't know how to fix that lul)

## Config

The config is auto created in the usual spot in `cfg/sourcemod/plugin.tf2gravihands.cfg` with the following values:
```
tf2gravihands_maxmass 250.0 - Max weight, the hands can pick up
tf2gravihands_throwforce 1000.0 - Multiplier used when throwing props
tf2gravihands_dropdistance 200.0 - Props get dropped when they move more than this distance from the grab point
tf2gravihands_grabdistance 120.0 - Maximum distance to grab stuff from, 0 to disable
tf2gravihands_pulldistance 850.0 - Maximum distance to pull props from, 0 to disable
tf2gravihands_pullforce_far 400.0 - Pull force to apply per tick when at max pull distance
tf2gravihands_pullforce_near 1000.0 - Theoretic pull force to apply per tick when at the player
tf2gravihands_sounds global - Sound engine configuration for Gravity Hands: global|player|disable
tf2gravihands_enabled 2 - 0=Disabled; 1=Only allow players to /holster their weapon (w/o T-Posing); 2=Enable Gravity Hands
```

## Natives and Forwards

Plugin developers get rich access to the GraviHand feature, being allowed to check when melee weapons are 
(un)holstered as well as limited control over what physics entities can be picked up.

Check the [include file](https://github.com/DosMike/TF2-GraviHands/blob/master/tf2gravihands.inc) for more info.

## Dependencies

* [SMLib](https://github.com/bcserv/smlib/tree/transitional_syntax) (Compile)
* [MoreColors](https://raw.githubusercontent.com/DoctorMcKay/sourcemod-plugins/master/scripting/include/morecolors.inc) (Compile)
* [VPhysics](https://forums.alliedmods.net/showthread.php?t=136350?t=136350)
* [TF2Items](https://forums.alliedmods.net/showthread.php?p=1050170?p=1050170)
* [TF2 Attributes](https://github.com/nosoop/tf2attributes)
* [TF Econ Data](https://github.com/nosoop/SM-TFEconData) (Use TF Econ Compat if you have old plugins)
* [PvP OptIn](https://github.com/DosMike/TF2-PvP-OptIn) (Optional/Supported)

## Credits

At some point some code was loosely based on the Physics Gun plugin by BattlefieldDuck / FlaminSarge, since then this code went through two rewrites.
If I accidentally didn't credit some code please tell me, and I'll add the appropriate notes.
