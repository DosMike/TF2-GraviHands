#if defined _tf2gravihands_weapons
 #endinput
#endif
#define _tf2gravihands_weapons

#if !defined _tf2gravihands
 #error Please compile the main file!
#endif

//on the invalid default values:
// some stuff uses negative levels (like the physgun) as it shows positive but can mark custom weapons
// quality afaik is always positive
int EquipPlayerMelee(int client, int definitionIndex, int level=9000, int quality=-1,
			int attribCount=0, int customAttribIds[]={}, any customAttribVals[]={}) {
	if (!TF2Econ_IsValidItemDefinition(definitionIndex))
		ThrowError("Definition index %d is invalid", definitionIndex);
	
	char class[72];
	int maxlvl;
	if (TF2Econ_GetItemDefaultLoadoutSlot(definitionIndex)!=TFWeaponSlot_Melee)
		ThrowError("Weapon %d (%s) uses non-melee slot!", definitionIndex, class);
	
	TF2Econ_GetItemClassName(definitionIndex, class, sizeof(class));
	if (level > 255) TF2Econ_GetItemLevelRange(definitionIndex, level, maxlvl);
	if (quality < 0) quality = TF2Econ_GetItemQuality(definitionIndex);
	
	if (StrEqual(class, "saxxy") && !TF2Econ_TranslateWeaponEntForClass(class, sizeof(class), TF2_GetPlayerClass(client)))
		ThrowError("Could not translate saxxy (%d) for player class %d", definitionIndex, TF2_GetPlayerClass(client));
	if (StrContains(class, "tf_weapon_")!=0 && !StrEqual(class, "saxxy"))
		ThrowError("Definition index %d (%s) is not a weapon", definitionIndex, class);
	
	int flags = FORCE_GENERATION|OVERRIDE_ITEM_DEF|OVERRIDE_ITEM_LEVEL|OVERRIDE_ITEM_QUALITY;
	if (attribCount>0) flags|=OVERRIDE_ATTRIBUTES;
	else flags|=PRESERVE_ATTRIBUTES;
	Handle weapon = TF2Items_CreateItem(flags);
	TF2Items_SetLevel(weapon, level>=0?level:0);
	TF2Items_SetQuality(weapon, quality);
//	TF2Items_SetNumAttributes(weapon, attribCount);
//	for (int a; a<attribCount; a++) {
//		TF2Items_SetAttribute(weapon, a, customAttribIds[a], customAttribVals[a]);
//	}
	TF2Items_SetNumAttributes(weapon, 0);
	TF2Items_SetItemIndex(weapon, definitionIndex);
	TF2Items_SetClassname(weapon, class);
	
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Melee);
	int entity = TF2Items_GiveNamedItem(client, weapon);
	delete weapon;
	if (entity != INVALID_ENT_REFERENCE) {
		//post apply arttribs, because tf2attribs allows for more attribs than the ol tf2items
		for (int a; a<attribCount; a++)
			TF2Attrib_SetByDefIndex(entity, customAttribIds[a], customAttribVals[a]);
		if (attribCount) TF2Attrib_ClearCache(entity);
		
		EquipPlayerWeapon(client, entity);
		TF2Attrib_ClearCache(client);
		
		SetEntProp(entity, Prop_Send, "m_bValidatedAttachedEntity", 1);
		SetEntProp(entity, Prop_Send, "m_iAccountID", GetSteamAccountID(client));
	}
	return entity;
}

bool HolsterMelee(int client) {
	if (!IsValidClient(client, false)) {
		return false; //not for bots
	}
	if (player[client].holsteredWeapon != INVALID_ITEM_DEFINITION) {
		return false; //already holstered
	}
	if (player[client].weaponsStripped) {
		return false; //wow hey, don't holster grav hands
	}
	
	int active = Client_GetActiveWeapon(client);
	int melee = Client_GetWeaponBySlot(client, TFWeaponSlot_Melee);
	bool switchTo = (melee == INVALID_ENT_REFERENCE || active != melee); //if melee was not active switch, to holster guns
	int holsterIndex = INVALID_ITEM_DEFINITION;
	if (melee != INVALID_ENT_REFERENCE) { 
		holsterIndex = GetEntProp(melee, Prop_Send, "m_iItemDefinitionIndex");
	}
	if ((GetClientButtons(client) & (IN_ATTACK|IN_ATTACK2))!=0) {
		//holstering while healing someone breaks the medic beam (infinite heal)
		PrintToChat(client, "[SM] You can not holster while holding attack buttons!");
		return false;
	}
	
	if (!NotifyWeaponHolster(client, holsterIndex)) return false; //was cancelled
	//copy melee metadata into holster
	if (holsterIndex != INVALID_ITEM_DEFINITION) {
		player[client].holsteredMeta[0] = GetEntProp(melee, Prop_Send, "m_iEntityLevel");
		player[client].holsteredMeta[1] = GetEntProp(melee, Prop_Send, "m_iEntityQuality");
		//collect attributes. while up to 20 are supported here, we seem to only be able to restore 16 with tf2items
		int attribCount = TF2Attrib_ListDefIndices(melee, player[client].holsteredAttributeIds, sizeof(PlayerData::holsteredAttributeIds));
		if (attribCount > sizeof(PlayerData::holsteredAttributeIds))
			attribCount = sizeof(PlayerData::holsteredAttributeIds);
		for (int a; a<attribCount; a++)
			player[client].holsteredAttributeValues[a] = TF2Attrib_GetByDefIndex(melee, player[client].holsteredAttributeValues[a]);
		player[client].holsteredAttributeCount = attribCount;
	}
	//equip new melee
	int fists = EquipPlayerMelee(client, ITEM_DEFINITION_HEAVY_FISTS);
	if (fists == INVALID_ENT_REFERENCE) return false; //giving fists failed?
	//needs to be set after Equip call due to event order
	player[client].holsteredWeapon = holsterIndex;
	if (switchTo) Client_SetActiveWeapon(client, fists);
	
	NotifyWeaponHolsterPost(client, holsterIndex);
	return true;
}

void UnholsterMelee(int client) {
	//doing this immediately causes too many issues with regenerating inventories
	//an unholster as in an actual unholster will always be manual and thus
	//does not require tick precision
	RequestFrame(ActualUnholsterMelee, client);
}
void ActualUnholsterMelee(int client) {
	if (!IsValidClient(client, false)) {
		return; //not for bots
	}
	if (player[client].holsteredWeapon == INVALID_ITEM_DEFINITION || player[client].weaponsStripped) {
		return; //no weapon holstered
	}
	if (!NotifyWeaponUnholster(client, player[client].holsteredWeapon)) {
		return; //was cancelled
	}
	
	int restore = player[client].holsteredWeapon;
	player[client].holsteredWeapon = INVALID_ITEM_DEFINITION;
	if (restore != INVALID_ITEM_DEFINITION) {
		EquipPlayerMelee(client, restore, 
			player[client].holsteredMeta[0],
			player[client].holsteredMeta[1],
			player[client].holsteredAttributeCount,
			player[client].holsteredAttributeIds,
			player[client].holsteredAttributeValues);
		player[client].holsteredWeapon = INVALID_ITEM_DEFINITION;
	}
	NotifyWeaponUnholsterPost(client, restore, false);
}

void DropHolsteredMelee(int client) {
	if (player[client].holsteredWeapon == INVALID_ITEM_DEFINITION)
		return;
	int restore = player[client].holsteredWeapon;
	player[client].holsteredWeapon = INVALID_ITEM_DEFINITION;
	NotifyWeaponUnholsterPost(client, restore, true);
}

bool IsActiveWeaponHolster(int client, int& weapon=INVALID_ENT_REFERENCE) {
	if (weapon == INVALID_ENT_REFERENCE) {
		weapon = Client_GetActiveWeapon(client);
	} else if (weapon < 0) {
		weapon = EntRefToEntIndex(weapon);
	}
	if (!IsValidEdict(weapon)) return false;
	
	//if the holster is empty, this has to be an actual weapon
	// if weapons were stripped, there is no holster but fists are sill gravi-hands
	if (player[client].holsteredWeapon == INVALID_ITEM_DEFINITION && !player[client].weaponsStripped) return false;
	//we use heavy stock fists for "no model"
	if (GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex") != ITEM_DEFINITION_HEAVY_FISTS) return false;
	return true;
}

void PreventAPosing(int client) {
	if (Client_GetActiveWeapon(client) != INVALID_ENT_REFERENCE) return;
	for (int slot=0;slot<5;slot++) {
		int weapon = GetPlayerWeaponSlot(client, slot);
		if (weapon != INVALID_ENT_REFERENCE) {
			Client_SetActiveWeapon(client, weapon);
			return;
		}
	}
	
	player[client].weaponsStripped = true;
	EquipPlayerMelee(client, ITEM_DEFINITION_HEAVY_FISTS);
}
