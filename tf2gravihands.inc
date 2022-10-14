#if defined _tf2_gravihands
 #endinput
#endif
#define _tf2_gravihands

#define GRAVIHANDS_VERSION "22w41a"
#define GRAVIHANDS_BUILD   224101

/**
 * There are two flags that might not be immediately obvious:
 *  *_ALWAYS_PICK_UP and *_NEVER_PICK_UP
 * I don't know how those exactly influenced behaviour in hl2/hl2dm but i 
 *  decided to use them as follows:
 * - FL_FROZEN entity flag always has priority on MotionDisabled.
 * - if ALWAYS_PICK_UP is set, no further conditions are checked.
 * - then
 *   - if ENABLE_ON_PHYSCANNON is set, ignore the entity movetype and DisableMotion state;
 *     otherwise set MotionDisable if movetype is none or spawned with/something fired DisableMotion
 *   - if NEVER_PICK_UP is set, flag as SpawnFlags
 *   - if mass exceeds the limig (250.0 by default) set TooHeavy flag
 * If of these three flags only TooHeavy remains, it will play a different sound
 *  indicating that the prop is too heavy.
 */
/**
 * This flag means that either 
 * - the entity spawned with the DisableMotion flag and physgun pickup won't enable it
 * - the map or the VPHysics extension called DisableMotion
 * - the entity has the FL_FROZEN flag set
 */
#define GHPickupFlag_MotionDisabled 0x01
/**
 * This flag means the spawnflags tell the prop to never be picked up by a physgun,
 * while not being told to always be picked up by a physgun. (yes there are two)
 * See the comment block above these defines for more clarification.
 */
#define GHPickupFlag_SpawnFlags 0x02
/**
 * This flag is set when the mass of the prop exceeds the physguns limit (250)
 */
#define GHPickupFlag_TooHeavy 0x04
/**
 * This flag is a mapping to another spawnflag, preventing the entity from being
 * punted (thrown) with mouse1. You can set or clear this flag as you like without
 * changeing the 'grab-ability' of the entity
 */
#define GHPickupFlag_BlockPunting 0x100
/**
 * If the VPhysics motion on this entity is disabled and this flag is set (default
 * from ENABLE_ON_PHYSCANNON), the plugin will call 'EnableMotion' on this entity
 * when it's picked up.
 */
#define GHPickupFlag_EnableMotion 0x200

/**
 * Called just before a client puts their weapons away. This can be useful to
 * prevent hosltering or to temporarily disable weapon change hooks.
 *
 * @param client - the client that is about to get their weapons holstered
 * @param itemDefinition - the item definition index of the clients melee
 * @return >= Plugin_Handled to prevent holstering
 */
forward Action TF2GH_OnClientHolsterWeapon(int client, int itemDefinition);

/**
 * Called after a client put their melee weapon away. Weapon slot 2 (keyboard 3)
 * should now contain heavys fists and be the active slot.
 *
 * @param client - the client that holstered their weapons
 * @param itemDefinition - the item definition index that is now stored
 */
forward void TF2GH_OnClientHolsterWeaponPost(int client, int itemDefinition);

/**
 * Called before a clients melee weapon is unholstered. Again this might be useful to
 * temporarily disable weapon change hooks. This is ONLY called if the melee is actually
 * about to be restored. This will not notify you about the holstered melee being dropepd.
 * 
 * @param client - the client that was unholstering
 * @param itemDefinition - the item definition index that was stored in the holster
 * @return >= Plugin_Handled to prevent unholstering
 */
forward Action TF2GH_OnClientUnholsterWeapon(int client, int itemDefinition);

/**
 * Called when a clients holstered state ends. This can be caused by switching
 * weapons, regenerating inventory, using the command again or otherwise.
 * Under some condition the stored/holstered weapon is not restored, but simply
 * dropped (e.g. ignored for the sake of regenerating the inventory)
 * 
 * @param client - the client that was unholstering
 * @param itemDefinition - the item definition index that was stored in the holster
 * @param dropped - true if the weapon was stripped, false if actually restored
 */
forward void TF2GH_OnClientUnholsterWeaponPost(int client, int itemDefinition, bool dropped);

/**
 * Retrieve a clients current holstered melee weapon by item definition index.
 * While a melee is holstered it is safe to assume the player is using
 * gravity hands.
 * 
 * @param client - the client to query
 * @return the item definition index or -1 if no melee is holstered
 */
native int TF2GH_GetClientHoslteredWeapon(int client);

/**
 * Called when a player tries to pick up a prop_physics_* or a func_physbox.
 * This does not mean the player can pick it up, but you can allow them to anyways.
 * 
 * @param client - the client that tries to pick up stuff
 * @param entity - the entity a client wants to grab
 * @param pickupFlags - modifiable flags (see GHPickupFlag_*)
 * @return >= Plugin_Handled to prevent grabbing the entity
 */
forward Action TF2GH_OnClientGraviHandsGrab(int client, int entity, int& pickupFlags);

/**
 * Called after a player grabbed a physics entity.
 * 
 * @param client - the client that grabbed the entity
 * @param entity - the entity picked up by the client
 */
forward void TF2GH_OnClientGraviHandsGrabPost(int client, int entity);

/**
 * Called after a client has dropped or thrown an entity.
 * 
 * @param client - the client that grabbed the entity
 * @param entity - the entity picked up by the client
 * @param punted - if punting this prop is possible and it was thrown
 */
forward void TF2GH_OnClientGraviHandsDropped(int client, int entity, bool punted);

/**
 * Receive the entity this client is holding if any
 *
 * @param client - the player to check
 * @return entity index or -1 if nothing is held
 */
native int TF2GH_GetGraviHandsHeldEntity(int client);

/**
 * Force this client to drop whatever entity they are holding
 *
 * @param client - the client to target
 * @param punt - force the client to throw the entity instead of dropping it
 */
native void TF2GH_ForceGraviHandsDropEntity(int client, bool punt=false);

/**
 * Prevent a player from a-posing after all weapons were removed.
 * If no more weapons are present, this state will be noted and fists will be
 * equipped.
 * This is intended to be called after TF2_RemoveAllWeapons(client)
 * 
 * @param client - the client to check
 * @error invalid client or client not ingame or client not alive
 */
native void TF2GH_PreventClientAPosing(int client);

public SharedPlugin:__pl_tf2gravihands = {
	name = "tf2gravihands",
	file = "tf2gravihands.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};


#if !defined REQUIRE_PLUGIN
public __pl_tf2gravihands_SetNTVOptional() {
	MarkNativeAsOptional("TF2GH_GetClientHoslteredWeapon");
	MarkNativeAsOptional("TF2GH_GetGraviHandsHeldEntity");
	MarkNativeAsOptional("TF2GH_ForceGraviHandsDropEntity");
	MarkNativeAsOptional("TF2GH_PreventClientAPosing");
}
#endif