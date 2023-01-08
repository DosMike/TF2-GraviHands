#if defined _tf2gravihands
 #endinput
#endif
#define _tf2gravihands

//generic includes
#include <clients>
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <regex>
#include <convars>

//generic dependencies
#include <smlib>
#include "morecolors.inc"
#include <vphysics>

//game specific includes
#include <tf2>
#include <tf2_stocks>

//game specific dependencies
#include <tf2items>
#include <tf2attributes>
#include <tf_econ_data>

//game specific dependencies (optional)
#undef REQUIRE_PLUGIN
//currently only supporting opt in pvp, dunno how firendly plugins handle this
#include <pvpoptin>
#define REQUIRE_PLUGIN

#pragma newdecls required
#pragma semicolon 1

#define PLUGIN_VERSION "23w01b"
//#define PLUGIN_DEBUG

public Plugin myinfo = {
	name = "[TF2] Gravity Hands",
	author = "reBane",
	description = "Budget Gravity Gun for TF2",
	version = PLUGIN_VERSION,
	url = "N/A"
}

// this plugin implements a disarmed state (having only fists)
// and handling prop_physics enabled states and inputs for when players try
// and pick them up.

// note on how holstering works:
// basically, when you holster, the melee weapon is stripped and
// replaced with heavy's fists. that's a stock weapon so valve should be fine.
// additionally fists don't have a model, which is exactly what you want for
// "unarmed". the downside is, that heavies with stock melee can not use that
// as weapon.
// unholstering will regenerate the melee weapon with stock properties. this
// will nuke warpaints, attachments, decals from objectors, etc and probably 
// remove all custom attributes, but this is the easiest way

#if defined PLUGIN_DEBUG
 #define PLDBG(%1) %1
#else
 #define PLDBG(%1) {}
#endif

#define INVALID_ITEM_DEFINITION -1
#define ITEM_DEFINITION_HEAVY_FISTS 5

enum struct PlayerData {
	float timeSpawned;
	bool handledDeath;
	int weaponsStripped; //if we find out that the player is a posing, we mark this here. 1=detected, 2=given fists
	
	int holsteredWeapon;
	int holsteredMeta[2];
	int holsteredAttributeCount;
	int holsteredAttributeIds[32];
	any holsteredAttributeValues[32];
	
	int previousButtons;
	
	void Reset() {
		this.timeSpawned     = 0.0;
		this.handledDeath    = false;
		
		this.holsteredWeapon = INVALID_ITEM_DEFINITION;
		//other holstered data go with this one
		
		this.previousButtons = 0;
	}
}
PlayerData player[MAXPLAYERS+1];
bool depOptInPvP;

static ConVar cvarGraviHandsMaxWeight;
float gGraviHandsMaxWeight;
static ConVar cvarGraviHandsPuntForce;
float gGraviHandsPuntForce;
static ConVar cvarGraviHandsDropDistance;
float gGraviHandsDropDistance;
static ConVar cvarGraviHandsGrabDistance;
float gGraviHandsGrabDistance;
static ConVar cvarGraviHandsPullDistance;
float gGraviHandsPullDistance;
static ConVar cvarGraviHandsPullForceFar;
float gGraviHandsPullForceFar;
static ConVar cvarGraviHandsPullForceNear;
float gGraviHandsPullForceNear;
static ConVar cvarFeatureEnabled;
#define PZ_FEATURE_HOLSTER 1
#define PZ_FEATURE_GRAVIHANDS 2
int gEnabledFeatures;

//global structures and data defined, include submodules
#include "tf2gravihands_weapons.sp"
#include "tf2gravihands_prophandling.sp"

public void OnPluginStart() {
	
	RegConsoleCmd("sm_hands", Command_Holster, "Put away weapons");
	RegConsoleCmd("sm_holster", Command_Holster, "Put away weapons");
	
	HookEvent("player_death", OnClientDeathPost);
	HookEvent("teamplay_round_start", OnMapEntitiesRefreshed);
	HookEvent("teamplay_restart_round", OnMapEntitiesRefreshed);
	
	CreateConvars();
	CreateForwards();
	
	for (int client=1; client<=MaxClients; client++) {
		if (!IsValidClient(client)) continue;
		OnClientConnected(client);
		AttachClientHooks(client);
	}
}

public void OnAllPluginsLoaded() {
	depOptInPvP = LibraryExists("pvpoptin");
}
public void OnLibraryAdded(const char[] name) {
	if (StrEqual(name, "pvpoptin")) { depOptInPvP = true; }
}
public void OnLibraryRemoved(const char[] name) {
	if (StrEqual(name, "pvpoptin")) { depOptInPvP = false; }
}

public void OnMapStart() {
	PrecacheModel(DUMMY_MODEL);
	PrecacheSound(GH_SOUND_PICKUP);
	PrecacheSound(GH_SOUND_DROP);
	PrecacheSound(GH_SOUND_INVALID);
	PrecacheSound(GH_SOUND_TOOHEAVY);
	PrecacheSound(GH_SOUND_THROW);
	PrecacheSound(GH_SOUND_FIZZLED);
	PrecacheSound(GH_SOUND_HOLD);
	g_tossedTracker = new ArrayList(sizeof(TossedData));
	CreateTimer(1.0, OnNotifyGravihandsActive, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapEntitiesRefreshed(Event event, const char[] name, bool dontBroadcast) {
	for (int client=1;client<=MaxClients;client++)
		if (IsValidClient(client) && IsPlayerAlive(client))
			HandlePlayerDeath(client); //force reset plugin internal state
}

public void OnPluginEnd() {
	for (int client=1;client<=MaxClients;client++) {
		if (!IsValidClient(client)) continue;
		ForceDropItem(client);
		DropHolsteredMelee(client); //unholstering is not possible, requires 1 tick delay
	}
}


public void OnClientConnected(int client) {
	player[client].Reset();
	GravHand[client].Reset();
}

public void OnClientDisconnect(int client) {
	ForceDropItem(client);
	player[client].Reset();
	GravHand[client].Reset();
}

public void OnEntityCreated(int entity, const char[] classname) {
	if (StrEqual(classname, "player")) {
		AttachClientHooks(entity);
	}
}

void AttachClientHooks(int client) {
	SDKHook(client, SDKHook_SpawnPost, OnPlayerSpawnPost);
	SDKHook(client, SDKHook_OnTakeDamage, OnPlayerTakeDamage);
	SDKHook(client, SDKHook_OnTakeDamagePost, OnPlayerTakeDamagePost);
	SDKHook(client, SDKHook_WeaponSwitchPost, OnClientWeaponSwitchPost); //unholster on switch
	SDKHook(client, SDKHook_WeaponEquip, OnClientWeaponEquip); //drop holster if resupplied/otherwise equipped
}

public void OnPlayerSpawnPost(int client) {
	player[client].handledDeath = false;
}

//this is for when something else replaces the melee weapon
public Action OnClientWeaponEquip(int client, int weapon) {
	if (!IsValidClient(client,false) || weapon == INVALID_ENT_REFERENCE) return Plugin_Continue;
	
	// THIS WOULD WORK BETTER WITH NOSOOPS TF2UTILS BUT I DON'T WANT TO INTRODUCE
	// ANOTHER DEPENDENCY. IF YOU THINK IT'S WORTH IT, JUST INCLUDE THE PLUGIN AND 
	// SWAP COMMENTS FOR THE NEXT TWO LINES 
	//int slot = TF2Util_GetWeaponSlot(weapon);
	int iindex = GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex");
	int slot = TF2Econ_GetItemDefaultLoadoutSlot(iindex);
	if (slot == TFWeaponSlot_Melee && player[client].holsteredWeapon != INVALID_ITEM_DEFINITION) {
		//dont get stuff stuck when we switch away
		ForceDropItem(client);
		//equipped melee while melee was holstered
		DropHolsteredMelee(client);
	}
	//undo the stripped status
	if (player[client].weaponsStripped == 1 && iindex == ITEM_DEFINITION_HEAVY_FISTS) {
		player[client].weaponsStripped = 2;
	} else if (player[client].weaponsStripped) {
		player[client].weaponsStripped = false;
		if (slot != TFWeaponSlot_Melee) { //the weapon we got is not melee? drop fists and use whatever we got
			TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
			Client_SetActiveWeapon(client, weapon);
		}
	}
	
	return Plugin_Continue;
}
void OnClientWeaponSwitchPost(int client, int weapon) {
	if (!IsValidClient(client, false)) return;
	if (weapon != INVALID_ENT_REFERENCE && player[client].holsteredWeapon != INVALID_ITEM_DEFINITION) {//no holstered weapon, always ok
		UnholsterMelee(client);
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2]) {
	bool changed;
	
	int activeWeapon = Client_GetActiveWeapon(client);
	bool isMeleeActive = activeWeapon != INVALID_ENT_REFERENCE && Client_GetWeaponBySlot(client, TFWeaponSlot_Melee) == activeWeapon;
	bool isMeleeGravHands = isMeleeActive && IsActiveWeaponHolster(client, activeWeapon);
	bool suppressButtons = player[client].weaponsStripped!=0;
	int actualButtons = buttons;
	
	if ((buttons & IN_ATTACK3) && !(player[client].previousButtons & IN_ATTACK3) && isMeleeActive) {
		//pressed down on mouse3 while ative weapon == melee (and there is a melee)
		// -> use this to /holster
		if (gEnabledFeatures & PZ_FEATURE_HOLSTER) {
			if (player[client].holsteredWeapon!=INVALID_ITEM_DEFINITION) UnholsterMelee(client);
			else HolsterMelee(client);
		} else {
			PrintToChat(client, "[SM] Holstering is currently not enabled");
		}
	} else if (isMeleeGravHands && (gEnabledFeatures & PZ_FEATURE_GRAVIHANDS)) {
		float velocity[3];
		Entity_GetAbsVelocity(client, velocity);
		clientCmdHoldProp(client, buttons, velocity, angles);
		suppressButtons = true;
	}
	if (suppressButtons && (buttons & (IN_ATTACK|IN_ATTACK2|IN_ATTACK3))) {
		buttons &=~ (IN_ATTACK|IN_ATTACK2|IN_ATTACK3);
		changed = true;
	}
	
	player[client].previousButtons = actualButtons;
	return changed?Plugin_Changed:Plugin_Continue;
}


public Action OnPlayerTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom) {
	//player was hit by a prop and we fixed the attacker, but we shall suppress prop damage
	if (FixPhysPropAttacker(victim, attacker, inflictor, damagetype)) {
		ScaleVector(damageForce, 0.0);
		damagetype |= DMG_PREVENT_PHYSICS_FORCE;
		damage = 0.0;
		return Plugin_Changed;
	}
	
	if (IsValidClient(attacker) && victim != attacker && (damagetype & DMG_CLUB)!=0) { //melee is using club damage type
		int gun=weapon; //prevent writeback on invalid ent ref
		if (player[attacker].weaponsStripped || IsActiveWeaponHolster(attacker, gun)) {
			//this player is currently using gravity hands or is unarmed, don't damage
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

public void OnPlayerTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype, int weapon, const float damageForce[3], const float damagePosition[3], int damagecustom) {
	if (GetClientHealth(victim)<=0) HandlePlayerDeath(victim);
}

public void OnClientDeathPost(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid", 0));
//	int attacker = GetClientOfUserId(event.GetInt("attacker", 0));
	HandlePlayerDeath(victim);
}

void HandlePlayerDeath(int client) {
	if (player[client].handledDeath) return;
	player[client].handledDeath = true;
	
	DropHolsteredMelee(client);
}

bool IsValidClient(int client, bool allowBots=true) {
	return ( 1<=client<=MaxClients && IsClientInGame(client) ) && ( allowBots || !IsFakeClient(client) );
}

public Action Command_Holster(int client, int args) {
	if (!IsValidClient(client,false)) return Plugin_Handled;
	if (gEnabledFeatures & PZ_FEATURE_HOLSTER) {
		if (player[client].holsteredWeapon!=INVALID_ITEM_DEFINITION) UnholsterMelee(client);
		else HolsterMelee(client);
	} else {
		ReplyToCommand(client, "[SM] Holstering is currently not enabled");
	}
	return Plugin_Handled;
}


public Action OnNotifyGravihandsActive(Handle timer) {
	SetHudTextParams(0.1, 0.95, 1.0, 255, 200, 0, 255, _, 0.0, 0.0, 0.1);
	for (int client=1;client<=MaxClients;client++) {
		if (!IsValidClient(client,false)) continue;
		else if (player[client].weaponsStripped) ShowHudText(client, -1, "Unarmed");
		else if (player[client].holsteredWeapon!=INVALID_ITEM_DEFINITION) ShowHudText(client, -1, "Weapons Holstered");
	}
	return Plugin_Continue;
}

/** convar **/

void CreateConvars() {
	ConVar version = CreateConVar("tf2gravihands_version", PLUGIN_VERSION, "TF2 Gravity Hands Version", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	version.AddChangeHook(OnCVarLockedChange);
	
	cvarGraviHandsMaxWeight = CreateConVar("tf2gravihands_maxmass", "250.0", _, _, true, 0.0);
	cvarGraviHandsMaxWeight.AddChangeHook(OnCVarGraviHandsMaxWeightChange);
	
	cvarGraviHandsPuntForce = CreateConVar("tf2gravihands_throwforce", "1000.0", _, _, true, 0.0);
	cvarGraviHandsPuntForce.AddChangeHook(OnCVarGraviHandsPuntForceChange);
	
	cvarGraviHandsDropDistance = CreateConVar("tf2gravihands_dropdistance", "200.0", "Maximum distance to the grab point when getting stuck, before being dropped", _, true, 0.0);
	cvarGraviHandsDropDistance.AddChangeHook(OnCVarGraviHandsDropDistanceChange);
	
	cvarGraviHandsGrabDistance = CreateConVar("tf2gravihands_grabdistance", "120.0", "Maximum distance to grab stuff from", _, true, 0.0);
	cvarGraviHandsGrabDistance.AddChangeHook(OnCVarGraviHandsGrabDistanceChange);
	
	cvarGraviHandsPullDistance = CreateConVar("tf2gravihands_pulldistance", "850.0", "Maximum distance to pull props from", _, true, 0.0);
	cvarGraviHandsPullDistance.AddChangeHook(OnCVarGraviHandsPullDistanceChange);
	
	cvarGraviHandsPullForceFar = CreateConVar("tf2gravihands_pullforce_far", "400.0", _, _, true, 0.0);
	cvarGraviHandsPullForceFar.AddChangeHook(OnCVarGraviHandsPullForceFarChange);
	
	cvarGraviHandsPullForceNear = CreateConVar("tf2gravihands_pullforce_near", "1000.0", _, _, true, 0.0);
	cvarGraviHandsPullForceNear.AddChangeHook(OnCVarGraviHandsPullForceNearChange);
	
	cvarFeatureEnabled = CreateConVar("tf2gravihands_enabled", "2", "0=Disabled; 1=Only allow players to /holster their weapon (w/o T-Posing); 2=Enable Gravity Hands", _, true, 0.0, true, 2.0);
	cvarFeatureEnabled.AddChangeHook(OnCVarFeatureEnabledChange);
	
	AutoExecConfig();
	
	OnCVarGraviHandsMaxWeightChange(cvarGraviHandsMaxWeight, "", "");
	OnCVarGraviHandsPuntForceChange(cvarGraviHandsPuntForce, "", "");
	OnCVarGraviHandsDropDistanceChange(cvarGraviHandsDropDistance, "", "");
	OnCVarGraviHandsGrabDistanceChange(cvarGraviHandsGrabDistance, "", "");
	OnCVarGraviHandsPullDistanceChange(cvarGraviHandsPullDistance, "", "");
	OnCVarGraviHandsPullForceFarChange(cvarGraviHandsPullForceFar, "", "");
	OnCVarGraviHandsPullForceNearChange(cvarGraviHandsPullForceNear, "", "");
	OnCVarFeatureEnabledChange(cvarFeatureEnabled, "", "");
}
public void OnCVarLockedChange(ConVar convar, const char[] oldValue, const char[] newValue) {
	char dbuf[32];
	convar.GetDefault(dbuf, sizeof(dbuf));
	if (!StrEqual(dbuf,newValue)) convar.RestoreDefault();
}
public void OnCVarGraviHandsMaxWeightChange(ConVar convar, const char[] oldValue, const char[] newValue) {
	gGraviHandsMaxWeight = convar.FloatValue;
}
public void OnCVarGraviHandsPuntForceChange(ConVar convar, const char[] oldValue, const char[] newValue) {
	gGraviHandsPuntForce = convar.FloatValue;
}
public void OnCVarGraviHandsDropDistanceChange(ConVar convar, const char[] oldValue, const char[] newValue) {
	gGraviHandsDropDistance = convar.FloatValue;
}
public void OnCVarGraviHandsGrabDistanceChange(ConVar convar, const char[] oldValue, const char[] newValue) {
	gGraviHandsGrabDistance = convar.FloatValue;
}
public void OnCVarGraviHandsPullDistanceChange(ConVar convar, const char[] oldValue, const char[] newValue) {
	gGraviHandsPullDistance = convar.FloatValue;
}
public void OnCVarGraviHandsPullForceFarChange(ConVar convar, const char[] oldValue, const char[] newValue) {
	gGraviHandsPullForceFar = convar.FloatValue;
}
public void OnCVarGraviHandsPullForceNearChange(ConVar convar, const char[] oldValue, const char[] newValue) {
	gGraviHandsPullForceNear = convar.FloatValue;
}
public void OnCVarFeatureEnabledChange(ConVar convar, const char[] oldValue, const char[] newValue) {
	int newFlags;
	switch (convar.IntValue) {
		case 2: newFlags = PZ_FEATURE_HOLSTER|PZ_FEATURE_GRAVIHANDS;
		case 1: newFlags = PZ_FEATURE_HOLSTER;
	}
	//enabled features that changed were just now disabled
	int disabled = gEnabledFeatures & (newFlags^gEnabledFeatures);
	gEnabledFeatures = newFlags;
	
	for (int client=1;client<=MaxClients;client++) {
		if (Client_IsIngame(client) && IsPlayerAlive(client)) {
			if (disabled & PZ_FEATURE_GRAVIHANDS) ForceDropItem(client);
			if (disabled & PZ_FEATURE_HOLSTER) UnholsterMelee(client);
		}
	}
}

/** natives & forwards **/

static GlobalForward fwdWeaponHolster;
static GlobalForward fwdWeaponHolsterPost;
static GlobalForward fwdWeaponUnholster;
static GlobalForward fwdWeaponUnholsterPost;
static GlobalForward fwdGraviHandsGrab;
static GlobalForward fwdGraviHandsGrabPost;
static GlobalForward fwdGraviHandsDropped;

void CreateForwards() {
	fwdWeaponHolster       = CreateGlobalForward("TF2GH_OnClientHolsterWeapon", ET_Event, Param_Cell, Param_Cell);
	fwdWeaponHolsterPost   = CreateGlobalForward("TF2GH_OnClientHolsterWeaponPost", ET_Ignore, Param_Cell, Param_Cell);
	fwdWeaponUnholster     = CreateGlobalForward("TF2GH_OnClientUnholsterWeapon", ET_Event, Param_Cell, Param_Cell);
	fwdWeaponUnholsterPost = CreateGlobalForward("TF2GH_OnClientUnholsterWeaponPost", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	fwdGraviHandsGrab      = CreateGlobalForward("TF2GH_OnClientGraviHandsGrab", ET_Event, Param_Cell, Param_Cell, Param_CellByRef);
	fwdGraviHandsGrabPost  = CreateGlobalForward("TF2GH_OnClientGraviHandsGrabPost", ET_Ignore, Param_Cell, Param_Cell);
	fwdGraviHandsDropped   = CreateGlobalForward("TF2GH_OnClientGraviHandsDropped", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
}

bool NotifyWeaponHolster(int client, int weaponDef) {
	Action result;
	Call_StartForward(fwdWeaponHolster);
	Call_PushCell(client);
	Call_PushCell(weaponDef);
	Call_Finish(result);
	return (result < Plugin_Handled);
}
void NotifyWeaponHolsterPost(int client, int weaponDef) {
	Call_StartForward(fwdWeaponHolsterPost);
	Call_PushCell(client);
	Call_PushCell(weaponDef);
	Call_Finish();
}
bool NotifyWeaponUnholster(int client, int weaponDef) {
	Action result;
	Call_StartForward(fwdWeaponUnholster);
	Call_PushCell(client);
	Call_PushCell(weaponDef);
	Call_Finish(result);
	return (result < Plugin_Handled);
}
void NotifyWeaponUnholsterPost(int client, int weaponDef, bool dropped) {
	Call_StartForward(fwdWeaponUnholsterPost);
	Call_PushCell(client);
	Call_PushCell(weaponDef);
	Call_PushCell(dropped);
	Call_Finish();
}
bool NotifyGraviHandsGrab(int client, int entity, int& pickupFlags) {
	Action result;
	int tmp = pickupFlags;
	Call_StartForward(fwdGraviHandsGrab);
	Call_PushCell(client);
	Call_PushCell(entity);
	Call_PushCellRef(tmp);
	Call_Finish(result);
	if (result == Plugin_Changed) pickupFlags = tmp;
	return (result < Plugin_Handled);
}
void NotifyGraviHandsGrabPost(int client, int entity) {
	Call_StartForward(fwdGraviHandsGrabPost);
	Call_PushCell(client);
	Call_PushCell(entity);
	Call_Finish();
}
void NotifyGraviHandsDropped(int client, int entity, bool punted) {
	Call_StartForward(fwdGraviHandsDropped);
	Call_PushCell(client);
	Call_PushCell(entity);
	Call_PushCell(punted);
	Call_Finish();
}


public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	CreateNative("TF2GH_GetClientHoslteredWeapon", NativeGetPlayerHolster);
	CreateNative("TF2GH_GetGraviHandsHeldEntity", NativeGetGraviHandsEntity);
	CreateNative("TF2GH_ForceGraviHandsDropEntity", NativeDropGraviHandsEntity);
	CreateNative("TF2GH_PreventClientAPosing", NativePreventAPosing);
	CreateNative("TF2GH_SetClientWeaponHolster", NativeHolsterWeapon);
	RegPluginLibrary("tf2gravihands");
	return APLRes_Success;
}
public any NativeGetPlayerHolster(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	if (!IsValidClient(client)) return -1;
	return player[client].holsteredWeapon;
}
public any NativeGetGraviHandsEntity(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	if (!IsValidClient(client) || GravHand[client].forceDropProp) return INVALID_ENT_REFERENCE;
	return GravHand[client].grabbedEnt;
}
public any NativeDropGraviHandsEntity(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	bool punt = GetNativeCell(2);
	if (!IsValidClient(client) || GravHand[client].forceDropProp || GravHand[client].grabbedEnt == INVALID_ENT_REFERENCE) return 0;
	float vel[3];
	Entity_GetAbsVelocity(client, vel);
	if (punt) {
		float ang[3];
		GetClientEyeAngles(client, ang);
		ForceDropItem(client, true, vel, ang);
	} else {
		ForceDropItem(client, false, vel);
	}
	return 0;
}
public any NativePreventAPosing(Handle plugin, int numPrams) {
	int client = GetNativeCell(1);
	if (!(1<=client<=MaxClients)||!IsClientInGame(client)||!IsPlayerAlive(client))
		ThrowNativeError(SP_ERROR_PARAM, "Invalid client or client not alive (client %i)", client);
	PreventAPosing(client);
	return 0;
}
public any NativeHolsterWeapon(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	if (!(1<=client<=MaxClients)||!IsClientInGame(client)||!IsPlayerAlive(client))
		ThrowNativeError(SP_ERROR_PARAM, "Invalid client or client not alive (client %i)", client);
	
	if (player[client].weaponsStripped) return 0; //can not holster right now
	
	bool doHolster = GetNativeCell(2)!=0;
	bool isHolstered = player[client].holsteredWeapon != INVALID_ITEM_DEFINITION;
	
	if (doHolster && !isHolstered) {
		HolsterMelee(client);
	} else if (!doHolster && isHolstered) {
		UnholsterMelee(client);
	}
	return 0;
}