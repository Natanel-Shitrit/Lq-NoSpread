#include <sourcemod>
#include <sdkhooks>

#pragma newdecls required
#pragma semicolon 1

#define PREFIX " \x04"... PREFIX_NO_COLOR ..."\x01"
#define PREFIX_NO_COLOR "[No-Spread]"

ConVar g_cvWeaponAccuracyNospread;

enum
{
	NOSPREAD_OPTION_IGNORE = -1, 
	NOSPREAD_OPTION_FALSE, 
	NOSPREAD_OPTION_TRUE
}

enum struct NoSpreadWeapon
{
	char weapon_classname[64];
	
	int nospread_option_scoped;
	int nospread_option_mid_air;
	
	int velocity_range[2];
}
ArrayList g_NoSpreadWeapons;

int g_ClientNoSpreadWeaponIndex[MAXPLAYERS + 1] =  { -1, ... };

public Plugin myinfo = 
{
	name = "[Lq] NoSpread", 
	author = "Natanel 'LuqS'", 
	description = "Control Your NoSpread ;D", 
	version = "1.2.0", 
	url = "https://steamcommunity.com/id/luqsgood || Discord: LuqS#6505"
};

//=========================[ Server Events ]=========================//

public void OnPluginStart()
{
	if (GetEngineVersion() != Engine_CSGO)
	{
		SetFailState("This plugin is for CSGO only.");
	}
	//=======================[ Initialize ]=======================//
	g_NoSpreadWeapons = new ArrayList(sizeof(NoSpreadWeapon));
	
	//=======================[ ConVars ]==========================//
	g_cvWeaponAccuracyNospread = FindConVar("weapon_accuracy_nospread");
	
	if (!g_cvWeaponAccuracyNospread)
	{
		SetFailState("'weapon_accuracy_nospread' ConVar couldn't be found.");
	}
	
	//========================[ Events ]==========================//
	HookEvent("weapon_fire", Event_OnWeaponFire, EventHookMode_Pre);
	
	//=======================[ Late-Load ]========================//
	for (int current_client = 1; current_client <= MaxClients; current_client++)
	{
		if (IsClientInGame(current_client))
		{
			OnClientPutInServer(current_client);
		}
	}
}

public void OnMapStart()
{
	g_NoSpreadWeapons.Clear();
	
	// Load KeyValues Config
	KeyValues kv = CreateKeyValues("Lq_NoSpread");
	
	// Find the Config
	char sFilePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFilePath, sizeof(sFilePath), "configs/Lq_NoSpread/Lq_NoSpread.cfg");
	
	// Open file and go directly to the settings, if something doesn't work don't continue.
	if (!kv.ImportFromFile(sFilePath))
	{
		SetFailState("%s Couldn't load plugin config.", PREFIX_NO_COLOR);
	}
	
	if (kv.JumpToKey("weapons") && kv.GotoFirstSubKey())
	{
		do
		{
			NoSpreadWeapon weapon;
			
			// Find the icon name
			kv.GetSectionName(weapon.weapon_classname, sizeof(NoSpreadWeapon::weapon_classname));
			
			weapon.nospread_option_mid_air = kv.GetNum("mid-air", NOSPREAD_OPTION_IGNORE);
			weapon.nospread_option_scoped = kv.GetNum("scoped", NOSPREAD_OPTION_IGNORE);
			
			weapon.velocity_range[0] = kv.GetNum("velocity_min", -1);
			weapon.velocity_range[1] = kv.GetNum("velocity_max", -1);
			
			g_NoSpreadWeapons.PushArray(weapon, sizeof(weapon));
			
		} while (kv.GotoNextKey());
	}
	
	kv.Close();
}

//=========================[ Client Events ]=========================//

public void OnClientPutInServer(int client)
{
	g_ClientNoSpreadWeaponIndex[client] = -1;
	SDKHook(client, SDKHook_WeaponSwitch, OnWeaponSwitch);
}

public Action OnWeaponSwitch(int client, int weapon)
{
	if (!IsFakeClient(client))
	{
		SDKUnhook(client, SDKHook_PostThinkPost, OnPostThinkPost);
		
		char weapon_classname[64];
		GetEntityClassname(weapon, weapon_classname, sizeof(weapon_classname));
		
		if ((g_ClientNoSpreadWeaponIndex[client] = g_NoSpreadWeapons.FindString(weapon_classname)) != -1)
		{
			SDKHook(client, SDKHook_PostThinkPost, OnPostThinkPost);
		}
		else
		{
			g_cvWeaponAccuracyNospread.ReplicateToClient(client, g_cvWeaponAccuracyNospread.BoolValue ? "1" : "0");
		}
	}
}

public void OnPostThinkPost(int client)
{
	g_cvWeaponAccuracyNospread.ReplicateToClient(client, ClientShouldGetNoSpread(client) ? "1" : "0");
}

public void Event_OnWeaponFire(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	if (0 < client <= MaxClients && g_ClientNoSpreadWeaponIndex[client] != -1 && ClientShouldGetNoSpread(client))
	{
		g_cvWeaponAccuracyNospread.BoolValue = true;
		RequestFrame(DisableNoSpread);
	}
}

bool ClientShouldGetNoSpread(int client)
{
	bool apply_nospread = true;
	
	NoSpreadWeapon weapon; weapon = GetNoSpreadWeaponByIndex(g_ClientNoSpreadWeaponIndex[client]);
	
	if (weapon.nospread_option_scoped != NOSPREAD_OPTION_IGNORE)
	{
		apply_nospread &= weapon.nospread_option_scoped == GetEntProp(client, Prop_Send, "m_bIsScoped");
	}
	
	if (weapon.nospread_option_mid_air != NOSPREAD_OPTION_IGNORE)
	{
		apply_nospread &= view_as<bool>(weapon.nospread_option_mid_air) == !(GetEntityFlags(client) & FL_ONGROUND);
	}
	
	if (weapon.velocity_range[0] != -1 || weapon.velocity_range[1] != -1)
	{
		float client_velocity = GetClientVelocity(client);
		apply_nospread 	&= (weapon.velocity_range[0] != -1 && client_velocity >= weapon.velocity_range[0])
		 				&& (weapon.velocity_range[1] != -1 && client_velocity <= weapon.velocity_range[1]);
	}
	
	return apply_nospread;
}

//=========================[ Other ]=========================//

void DisableNoSpread()
{
	g_cvWeaponAccuracyNospread.BoolValue = false;
}

float GetClientVelocity(int client)
{
	float client_velocity_vector[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", client_velocity_vector);
	return GetVectorLength(client_velocity_vector);
}

any[] GetNoSpreadWeaponByIndex(int index)
{
	NoSpreadWeapon weapon;
	g_NoSpreadWeapons.GetArray(index, weapon, sizeof(weapon));
	
	return weapon;
} 