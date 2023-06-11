#if defined _tf2gravihands_prophandling
 #endinput
#endif
#define _tf2gravihands_prophandling

#if !defined _tf2gravihands
 #error Please compile the main file!
#endif

#define DUMMY_MODEL "models/class_menu/random_class_icon.mdl"
#define GRAB_DISTANCE 150.0

#define GH_SOUND_PICKUP "weapons/physcannon/physcannon_pickup.wav"
#define GH_SOUND_DROP "weapons/physcannon/physcannon_drop.wav"
#define GH_SOUND_TOOHEAVY "weapons/physcannon/physcannon_tooheavy.wav"
#define GH_SOUND_INVALID "weapons/physcannon/physcannon_dryfire.wav"
#define GH_SOUND_THROW "weapons/physcannon/superphys_launch1.wav"
#define GH_SOUND_FIZZLED "weapons/physcannon/energy_disintegrate4.wav"
#define GH_SOUND_HOLD "weapons/physcannon/hold_loop.wav"
#define GH_ACTION_PICKUP 1
#define GH_ACTION_DROP 2
#define GH_ACTION_TOOHEAVY 3
#define GH_ACTION_INVALID 4
#define GH_ACTION_THROW 5
#define GH_ACTION_FIZZLED 6
#define GH_ACTION_HOLD 7

enum struct GraviPropData {
	//grab entity data
	int rotProxyEnt;
	int grabbedEnt;
	float previousEnd[3]; //allows flinging props
	float lastValid[3]; //prevent props from being dragged through walls
	bool dontCheckStartPost; //aabbs collide easily, allow pulling props out of those situations
	Collision_Group_t collisionFlags;// collisionFlags of held prop
	bool forceDropProp;
	bool blockPunt; //from spawnflags
	float grabDistance;
	
	//"gravity gun sound engine"
	float playNextAction;
	int lastAudibleAction;
	
	//prevent instant re-pickup
	float nextPickup;
	int justDropped;
	
	void Reset() {
		this.rotProxyEnt = INVALID_ENT_REFERENCE;
		this.grabbedEnt = INVALID_ENT_REFERENCE;
		ScaleVector(this.previousEnd, 0.0);
		ScaleVector(this.lastValid, 0.0);
		this.dontCheckStartPost = false;
		this.forceDropProp = false;
		this.grabDistance = -1.0;
		this.playNextAction = 0.0;
		this.lastAudibleAction = 0;
		this.nextPickup = 0.0;
		this.justDropped = INVALID_ENT_REFERENCE;
	}
}
GraviPropData GravHand[MAXPLAYERS+1];

#define TOSSED_TRACKING_TIME 10.0
enum struct TossedData {
	int entref;
	int userid;
	float timetossed;
}
ArrayList g_tossedTracker;
/** @return client if found or 0 */
static int GetTossedBy(int entity) {
	//cleanup timed out data and search entref
	TossedData data;
	float now = GetGameTime();
	int client;
	for (int idx=g_tossedTracker.Length-1; idx >= 0; idx-=1) {
		int dataent;
		g_tossedTracker.GetArray(idx,data);
		
		if ((dataent = EntRefToEntIndex(data.entref))==INVALID_ENT_REFERENCE || now-data.timetossed > TOSSED_TRACKING_TIME) {
			g_tossedTracker.Erase(idx);
		} else if (dataent == entity) {
			client = GetClientOfUserId(data.userid);
		}
	}
	return client;
}
static bool SetTossedBy(int entity, int client) {
	if (0 < entity < GetMaxEntities()) entity = EntIndexToEntRef(entity);
	if (entity == INVALID_ENT_REFERENCE || client <= 0 || client > MaxClients || !IsClientInGame(client)) return false;
	//remove old data
	int idx=g_tossedTracker.FindValue(entity);
	if (idx >= 0) g_tossedTracker.Erase(idx);
	//insert new data
	TossedData data;
	float now = GetGameTime();
	data.entref = entity;
	data.userid = GetClientUserId(client);
	data.timetossed = now;
	g_tossedTracker.PushArray(data);
	return true;
}


// if we parent the entity to a dummy, we don't have to care about the offset matrix
static int getOrCreateProxyEnt(int client, float atPos[3]) {
	int ent = EntRefToEntIndex(GravHand[client].rotProxyEnt);
	if (ent == INVALID_ENT_REFERENCE) {
		ent = CreateEntityByName("prop_dynamic_override");//CreateEntityByName("info_target");
		DispatchKeyValue(ent, "model", DUMMY_MODEL);
		SetEntPropFloat(ent, Prop_Send, "m_flModelScale", 0.0);
		DispatchSpawn(ent);
		TeleportEntity(ent, atPos, NULL_VECTOR, NULL_VECTOR);
		GravHand[client].rotProxyEnt = EntIndexToEntRef(ent);
	}
	return ent;
}

public bool grabFilter(int entity, int contentsMask, int client) {
	return entity != client
		&& entity > MaxClients //never clients
		&& IsValidEntity(entity) //don't grab stale refs
		&& entity != EntRefToEntIndex(GravHand[client].rotProxyEnt) //don't grab rot proxies
		&& entity != EntRefToEntIndex(GravHand[client].grabbedEnt) //don't grab grabbed stuff
		&& GetEntPropEnt(entity, Prop_Send, "moveparent")==INVALID_ENT_REFERENCE; //never grab stuff that's parented (already)
}

//static char[] vecfmt(float vec[3]) {
//	char buf[32];
//	Format(buf, sizeof(buf), "(%.2f, %.2f, %.2f)", vec[0], vec[1], vec[2]);
//	return buf;
//}

static void computeBounds(int entity, float mins[3], float maxs[3]) {
	float v[3]={8.0,...}; //helper, defining size of bounds box
	//entities stay inbounds if their COM is inside (thanks vphysics on this one)
	Entity_GetMinSize(entity, mins);
	Entity_GetMaxSize(entity, maxs);
	AddVectors(mins,maxs,mins);
	ScaleVector(mins,0.5); //mins = now Center
	//now rotate with the prop
	float r[3];
	Entity_GetAbsAngles(entity, r);
	Math_RotateVector(mins, r, mins);
	//create equidistant box to keep origin of prop in world
	AddVectors(mins,v,maxs);
	SubtractVectors(mins,v,mins);
}

/** 
 * @param targetPoint as ray end or max distance in look direction
 * @return entity under cursor if any
 */
static int pew(int client, float targetPoint[3], float scanDistance) {
	float eyePos[3], eyeAngles[3], fwrd[3];
	GetClientEyePosition(client, eyePos);
	GetClientEyeAngles(client, eyeAngles);
	Handle trace = TR_TraceRayFilterEx(eyePos, eyeAngles, MASK_SOLID, RayType_Infinite, grabFilter, client);
	int cursor = INVALID_ENT_REFERENCE;
	if(TR_DidHit(trace)) {
		float vecTarget[3];
		TR_GetEndPosition(vecTarget, trace);
		
		float maxdistance = (EntRefToEntIndex(GravHand[client].grabbedEnt)==INVALID_ENT_REFERENCE) ? scanDistance : GravHand[client].grabDistance;
		float distance = GetVectorDistance(eyePos, vecTarget);
		if(distance > maxdistance) { //looking beyond the held entity
			GetAngleVectors(eyeAngles, fwrd, NULL_VECTOR, NULL_VECTOR);
			ScaleVector(fwrd, maxdistance);
			AddVectors(eyePos, fwrd, targetPoint);
		} else { //maybe looking at a wall
			targetPoint = vecTarget;
		}
		
		int entity = TR_GetEntityIndex(trace);
		if (entity>0 && distance <= scanDistance) {
			cursor = entity;
		}
	}
	CloseHandle(trace);
	return cursor;
}

static bool movementCollides(int client, float endpos[3], bool onlyTarget) {
	//check if prop would collide at target position
	float offset[3], from[3], to[3], mins[3], maxs[3];
	int grabbed = EntRefToEntIndex(GravHand[client].grabbedEnt);
	if (grabbed == INVALID_ENT_REFERENCE) ThrowError("%L is not currently grabbing anything", client);
	//get movement
	SubtractVectors(endpos, GravHand[client].lastValid, offset);
	GetEntPropVector(grabbed, Prop_Data, "m_vecAbsOrigin", from);
	AddVectors(from, offset, to);
	if (onlyTarget) {
		from[0]=to[0]-0.1;
		from[1]=to[1]-0.1;
		from[2]=to[2]-0.1;
	}
	computeBounds(grabbed, mins, maxs);
	//trace it
	TR_TraceHullFilter(from, to, mins, maxs, MASK_SOLID, grabFilter, client);
	bool result = TR_DidHit();
	return result;
}

/**
 * This only gets call if isMeleeGravHands in OnPlayerRunCmd, so this does not 
 * have to check if gravity hands are out.
 */
bool clientCmdHoldProp(int client, int& buttons, float velocity[3], float angles[3]) {
	int grabbed = INVALID_ENT_REFERENCE;
	if (GravHand[client].grabbedEnt!=INVALID_ENT_REFERENCE) grabbed = EntRefToEntIndex(GravHand[client].grabbedEnt);
	
	bool atk2held = !!(buttons & IN_ATTACK2);
	//rotate this value
	bool atk2prev = !!(player[client].previousButtons & IN_ATTACK2);
	bool atk2in = atk2held && !atk2prev;
	
	if (grabbed != INVALID_ENT_REFERENCE) {
		//detect "down edge"
		if (atk2in || !!(buttons & IN_ATTACK) || GravHand[client].forceDropProp) {
			//drop anything held
			ForceDropItem(client, (buttons & IN_ATTACK) && !GravHand[client].forceDropProp, velocity, angles);
			buttons &=~ IN_ATTACK2;
			return true;
		} else {
			ThinkHeldProp(client, grabbed, buttons, angles);
		}
	} else if (!GravHand[client].forceDropProp && atk2held) {
		if (!(gGraviHandsGrabDistance>0.0 && TryPickupCursorEnt(client, angles)) &&
			!(gGraviHandsPullDistance>0.0 && TryPullCursorEnt(client, angles)) ) {
			//if another sound already played, nothing will happen
			PlayActionSound(client, GH_ACTION_INVALID, false);
			return false;
		}
	} else if (grabbed == INVALID_ENT_REFERENCE && GravHand[client].grabbedEnt != INVALID_ENT_REFERENCE) {
		//the entity was deleted, no sound is weird
		PlayActionSound(client, GH_ACTION_FIZZLED);
		GravHand[client].grabbedEnt = INVALID_ENT_REFERENCE;
	}
	if (!atk2held) { GravHand[client].justDropped = INVALID_ENT_REFERENCE; }
	return true;
}

#define PickupFlag_MotionDisabled 0x01
#define PickupFlag_SpawnFlags 0x02
#define PickupFlag_TooHeavy 0x04
#define PickupFlag_BlockPunting 0x100
#define PickupFlag_EnableMotion 0x200
static bool TryPickupCursorEnt(int client, float yawAngle[3]) {
	//this is too early
	if (GetClientTime(client) < GravHand[client].nextPickup) return false;
	
	float endpos[3], killVelocity[3];
	int cursorEnt = pew(client, endpos, gGraviHandsGrabDistance);
	if (cursorEnt == INVALID_ENT_REFERENCE || EntRefToEntIndex(GravHand[client].justDropped) == cursorEnt) return false;
	
	int rotProxy = getOrCreateProxyEnt(client, endpos);
	
	//check if cursor is a entity we can grab
	char classname[20];
	GetEntityClassname(cursorEnt, classname, sizeof(classname));
	int pickupFlags = 0;
	bool weaponOrGib;
	if (StrContains(classname, "prop_physics")==0) {
		if (Entity_GetFlags(cursorEnt) & FL_FROZEN) {
			pickupFlags |= PickupFlag_MotionDisabled;
		} else {
			int spawnFlags = Entity_GetSpawnFlags(cursorEnt);
			bool motion = Phys_IsMotionEnabled(cursorEnt);
			if ((spawnFlags & SF_PHYSPROP_ENABLE_ON_PHYSCANNON) && !motion) {
				pickupFlags |= PickupFlag_EnableMotion;
				motion = true;
			}
			if (!(spawnFlags & SF_PHYSPROP_ALWAYS_PICK_UP)) {
				if (spawnFlags & SF_PHYSPROP_PREVENT_PICKUP)
					pickupFlags |= PickupFlag_SpawnFlags;
				if (GetEntityMoveType(cursorEnt)==MOVETYPE_NONE || !motion)
					pickupFlags |= PickupFlag_MotionDisabled;
				if (Phys_GetMass(cursorEnt)>gGraviHandsMaxWeight)
					pickupFlags |= PickupFlag_TooHeavy;
			}
		}
	} else if (StrEqual(classname, "func_physbox")) {
		if (Entity_GetFlags(cursorEnt) & FL_FROZEN) {
			pickupFlags |= PickupFlag_MotionDisabled;
		} else {
			int spawnFlags = Entity_GetSpawnFlags(cursorEnt);
			bool motion = Phys_IsMotionEnabled(cursorEnt);
			if ((spawnFlags & SF_PHYSBOX_ENABLE_ON_PHYSCANNON) && !motion) {
				pickupFlags |= PickupFlag_EnableMotion;
				motion = true;
			}
			if (!(spawnFlags & SF_PHYSBOX_ALWAYS_PICK_UP)) {
				if (spawnFlags & SF_PHYSBOX_NEVER_PICK_UP)
					pickupFlags |= PickupFlag_SpawnFlags;
				if (GetEntityMoveType(cursorEnt)==MOVETYPE_NONE || !motion)
					pickupFlags |= PickupFlag_MotionDisabled;
				if (Phys_GetMass(cursorEnt)>gGraviHandsMaxWeight)
					pickupFlags |= PickupFlag_TooHeavy;
			}
			if ((spawnFlags & SF_PHYSBOX_NEVER_PUNT)!=0) pickupFlags |= PickupFlag_BlockPunting;
		}
	} else if (StrEqual(classname, "tf_dropped_weapon") || StrEqual(classname, "tf_ammo_pack")) {
		pickupFlags = 0;
		weaponOrGib = true;
	} else { //not an entity we could pick up
		PlayActionSound(client,GH_ACTION_INVALID, false);
		return false;
	}
	//ok we now have a potential candidate for grabbing and collected some meta info
	// lets ask all other plugins if they are ok with us grabbing this thing
	if (!NotifyGraviHandsGrab(client, cursorEnt, pickupFlags)) { //plugins said no
		PlayActionSound(client,GH_ACTION_INVALID, false);
		return false;
	}
	if ((pickupFlags & 0xff)) { //if not plugin blocked but still not possible, i want to react to the tooheavy flag
		PlayActionSound(client, (pickupFlags == PickupFlag_TooHeavy)?GH_ACTION_TOOHEAVY:GH_ACTION_INVALID, false);
		return false;
	}
	//ok now we can finally pick this thing up
	if (!weaponOrGib && (pickupFlags & PickupFlag_EnableMotion)!=0 && !Phys_IsMotionEnabled(cursorEnt)) {
		//Phys_EnableMotion(cursorEnt, true);
		AcceptEntityInput(cursorEnt, "EnableMotion", client, client);
	}
	GravHand[client].blockPunt = ((pickupFlags & PickupFlag_BlockPunting)!=0);
	
	//generate outputs
	if (!weaponOrGib) FireEntityOutput(cursorEnt, "OnPhysGunPickup", client);
	//check if this entity is already grabbed
	for (int i=1;i<=MaxClients;i++) {
		if (cursorEnt == EntRefToEntIndex(GravHand[client].grabbedEnt)) {
			PlayActionSound(client,GH_ACTION_INVALID, false);
			return false;
		}
	}
	//position entities
	TeleportEntity(rotProxy, endpos, yawAngle, NULL_VECTOR);
	TeleportEntity(cursorEnt, NULL_VECTOR, NULL_VECTOR, killVelocity);
	//grab entity
	GravHand[client].grabbedEnt = EntIndexToEntRef(cursorEnt);
	float vec[3], vec2[3];
	GetClientEyePosition(client, vec);
	GetEntPropVector(rotProxy, Prop_Data, "m_vecAbsOrigin", vec2);
	GravHand[client].grabDistance = GetVectorDistance(vec2, vec);
	//parent to make rotating easier
	SetVariantString("!activator");
	AcceptEntityInput(cursorEnt, "SetParent", rotProxy);
	//other setup
	GravHand[client].lastValid = endpos;
	GravHand[client].previousEnd = endpos;
	GravHand[client].dontCheckStartPost = movementCollides(client, endpos, true);
	GravHand[client].collisionFlags = Entity_GetCollisionGroup(cursorEnt);
	SetEntityCollisionGroup(cursorEnt, view_as<int>(COLLISION_GROUP_DEBRIS_TRIGGER));
	//sound
	PlayActionSound(client,GH_ACTION_PICKUP);
	//notify plugins
	NotifyGraviHandsGrabPost(client, cursorEnt);
	return true;
}

static bool TryPullCursorEnt(int client, float yawAngle[3]) {
	float target[3], eyePos[3];
	float force[3], grav[3];
	char classname[64];
	
	int entity = pew(client, target, gGraviHandsPullDistance);
	if (entity == INVALID_ENT_REFERENCE) {
		return false;
	}
	Entity_GetClassName(entity, classname, sizeof(classname));
	if (StrContains(classname,"prop_physics")!=0 && !StrEqual(classname, "func_physbox") &&
		!StrEqual(classname, "tf_dropped_weapon") && !StrEqual(classname, "tf_ammo_pack")) {
		return false;
	}
	//don't pull props right after dropping
	if (GetClientTime(client) < GravHand[client].nextPickup) {
		return false;
	}
	
	GetAngleVectors(yawAngle, force, NULL_VECTOR, NULL_VECTOR);
	GetClientEyePosition(client, eyePos);
	//manipulate the target position to be grab distance in front of the player
	float dist = gGraviHandsGrabDistance < 50.0 ? 50.0 : gGraviHandsGrabDistance;
	grav = force; //abuse the grav vector for distance
	ScaleVector(grav, dist);
	AddVectors(eyePos, grav, eyePos);
	//lerp the force over the distance
	dist = GetVectorDistance(eyePos, target);
	float normalizedDistance = 1.0-(dist / gGraviHandsPullDistance); //1- because we want to pull towards the player
	float forceRange = gGraviHandsPullForceNear-gGraviHandsPullForceFar; //force range
	float forceScale = normalizedDistance * forceRange + gGraviHandsPullForceFar; //scaled over range + min
	ScaleVector(force, -forceScale);
	Phys_GetEnvironmentGravity(grav);
	ScaleVector(grav, 0.8*normalizedDistance); //full gravity feels a bit much
	SubtractVectors(force, grav, force);
	Phys_ApplyForceCenter(entity, force);
//	Phys_ApplyForceOffset(entity, force, target); //does weird stuff :o
	
	//play sound
	PlayActionSound(client, GH_ACTION_TOOHEAVY);
	SetTossedBy(entity, client); //yes, track damage even for pulling. also prevents self-damage when bonking your head with it
	return true;
}

static void ThinkHeldProp(int client, int grabbed, int buttons, float yawAngle[3]) {
	float endpos[3], killVelocity[3];
	pew(client, endpos, gGraviHandsGrabDistance);
	int rotProxy = getOrCreateProxyEnt(client, endpos);
	if (rotProxy != INVALID_ENT_REFERENCE && grabbed != INVALID_ENT_REFERENCE) { //holding
		if (!movementCollides(client, endpos, GravHand[client].dontCheckStartPost)) {
			if (buttons & IN_ATTACK && !GravHand[client].blockPunt) { //punt
				GravHand[client].forceDropProp = true;
			} else {
				GravHand[client].lastValid = endpos;
				GravHand[client].previousEnd = endpos;
				GravHand[client].dontCheckStartPost = false;
				TeleportEntity(rotProxy, endpos, yawAngle, killVelocity);
			}
		} else if (GetVectorDistance(GravHand[client].lastValid, endpos) > gGraviHandsDropDistance) {
			GravHand[client].forceDropProp = true;
		}
		PlayActionSound(client, GH_ACTION_HOLD);
	}
}

bool ForceDropItem(int client, bool punt=false, const float dvelocity[3]=NULL_VECTOR, const float dvangles[3]=NULL_VECTOR) {
	bool didStuff = false;
	int entity;
	if ((entity = EntRefToEntIndex(GravHand[client].grabbedEnt))!=INVALID_ENT_REFERENCE) {
		float vec[3], origin[3];
		GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", origin);
		AcceptEntityInput(entity, "ClearParent");
		//fling
		bool didPunt;
		pew(client, vec, gGraviHandsDropDistance);
		if (punt && !IsNullVector(dvangles)) { //punt
			GetAngleVectors(dvangles, vec, NULL_VECTOR, NULL_VECTOR);
			ScaleVector(vec, gGraviHandsPuntForce * 100.0 / Phys_GetMass(entity));
//				AddVectors(vec, fwd, vec);
			didPunt=true;
		} else if (!movementCollides(client, vec, false)) { //throw with swing
			SubtractVectors(vec, GravHand[client].previousEnd, vec);
			ScaleVector(vec, 25.0); //give oomph
		} else {
			ScaleVector(vec, 0.0); //set 0
		}
		if (!IsNullVector(dvelocity)) AddVectors(vec, dvelocity, vec);
		float zeros[3];
		TeleportEntity(entity, origin, NULL_VECTOR, zeros); //reset entity
		Phys_SetVelocity(entity, vec, zeros, true);//use vphysics to accelerate, is more stable
		
		//fire output that the ent was dropped
		{	char classname[64];
			GetEntityClassname(entity, classname, sizeof(classname));
			if (StrContains(classname, "prop_physics")==0 || StrEqual(classname, "func_physbox"))
				FireEntityOutput(entity, punt?"OnPhysGunPunt":"OnPhysGunDrop", client);
		}
		//reset ref because we're nice
		SetEntityCollisionGroup(entity, view_as<int>(GravHand[client].collisionFlags));
		GravHand[client].justDropped = GravHand[client].grabbedEnt;
		GravHand[client].grabbedEnt = INVALID_ENT_REFERENCE;
		NotifyGraviHandsDropped(client, entity, didPunt);
		GravHand[client].nextPickup = GetClientTime(client) + (punt?0.5:0.1);
		SetTossedBy(entity, client);
		//play sound
		PlayActionSound(client,didPunt?GH_ACTION_THROW:GH_ACTION_DROP);
		didStuff = true;
	}
	if ((entity = EntRefToEntIndex(GravHand[client].rotProxyEnt))!=INVALID_ENT_REFERENCE) {
		AcceptEntityInput(entity, "Kill");
		GravHand[client].rotProxyEnt = INVALID_ENT_REFERENCE;
		didStuff = true;
	}
	GravHand[client].collisionFlags = COLLISION_GROUP_NONE;
	GravHand[client].grabDistance=0.0;
	GravHand[client].forceDropProp=false;
	return didStuff;
}

void PlayActionSound(int client, int sound, bool replace=true) {
	if (!gGraviHandsSounds) return;
	float ct = GetClientTime(client);
	bool played = GravHand[client].playNextAction - ct < 0;
	if (played || (replace && GravHand[client].lastAudibleAction != sound)) {
		if (GravHand[client].lastAudibleAction == GH_ACTION_HOLD && sound != GH_ACTION_HOLD) {
			//hold-loop sound interruption
			StopSound(client, SNDCHAN_WEAPON, GH_SOUND_HOLD);
		}
		switch (sound) {
			case GH_ACTION_PICKUP: {
				if (gGraviHandsSounds==2)
					EmitSoundToAll(GH_SOUND_PICKUP, client);
				else
					EmitSoundToClient(client, GH_SOUND_PICKUP);
				GravHand[client].playNextAction = ct + 1.5;
			}
			case GH_ACTION_DROP: {
				if (gGraviHandsSounds==2)
					EmitSoundToAll(GH_SOUND_DROP, client);
				else
					EmitSoundToClient(client, GH_SOUND_DROP);
				GravHand[client].playNextAction = ct + 1.5;
			}
			case GH_ACTION_TOOHEAVY: {
				if (gGraviHandsSounds==2)
					EmitSoundToAll(GH_SOUND_TOOHEAVY, client);
				else
					EmitSoundToClient(client, GH_SOUND_TOOHEAVY);
				GravHand[client].playNextAction = ct + 1.5;
			}
			case GH_ACTION_INVALID: {
				if (gGraviHandsSounds==2)
					EmitSoundToAll(GH_SOUND_INVALID, client);
				else
					EmitSoundToClient(client, GH_SOUND_INVALID);
				GravHand[client].playNextAction = ct + 0.5;
			}
			case GH_ACTION_THROW: {
				if (gGraviHandsSounds==2)
					EmitSoundToAll(GH_SOUND_THROW, client);
				else
					EmitSoundToClient(client, GH_SOUND_THROW);
				GravHand[client].playNextAction = ct + 0.5;
			}
			case GH_ACTION_FIZZLED: {
				EmitSoundToClient(client, GH_SOUND_FIZZLED, _, _, _, _, 0.33);
				GravHand[client].playNextAction = ct + 0.5;
			}
			case GH_ACTION_HOLD: {
				if (GravHand[client].lastAudibleAction != GH_ACTION_HOLD)
					EmitSoundToClient(client, GH_SOUND_HOLD, _, SNDCHAN_WEAPON, _, _, 0.66);
				GravHand[client].playNextAction = ct + 2.0; //loops with cue-points
			}
			default: {
				GravHand[client].playNextAction = ct + 1.5;
			}
		}
		GravHand[client].lastAudibleAction = sound;
	}
}

bool FixPhysPropAttacker(int victim, int& attacker, int& inflictor, int& damagetype) {
	if (attacker == inflictor && victim != attacker && !IsValidClient(attacker)) {
		char classname[64];
		Entity_GetClassName(attacker, classname, sizeof(classname));
		if (StrEqual(classname, "func_physbox") || StrContains(classname, "prop_physics")==0) {
			//victim is damaged by physics object, search thrower in our data
			int thrower = GetTossedBy(attacker);
			if (thrower > 0) { //we got a thrower, but timeout interactions
				//rewrite attacker
				attacker = thrower;
				//no self damage (a but too easy to do)
				bool blockDamage = attacker == victim;
				//I know that this is not the inteded use, but TF2 has no other use either
				damagetype |= DMG_PHYSGUN|DMG_CRUSH;
				//pvp plugin integration
				if (depOptInPvP && !pvp_CanAttack(attacker, victim)) {
					blockDamage = true;
				}
				return blockDamage;
			}
		}
	}
	return false;
}

//stock void DebugLine(int client, const float from[3], const float to[3]) {
//	int color[]={255,255,255,255};
//	TE_SetupBeamPoints(from, to, PrecacheModel("materials/sprites/laserbeam.vmt", false), 0, 0, 1, 1.0, 1.0, 1.0, 0, 0.0, color, 0);
//	TE_SendToClient(client);
//}
