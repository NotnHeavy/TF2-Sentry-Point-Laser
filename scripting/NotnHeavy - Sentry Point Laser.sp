//////////////////////////////////////////////////////////////////////////////
// MADE BY NOTNHEAVY. USES GPL-3, AS PER REQUEST OF SOURCEMOD               //
//////////////////////////////////////////////////////////////////////////////

// i'm not going to lie i know jack shit about tempents lol
// so thanks bakugo for pointing me towards BeamEntPoint

// and also vector maths !!! and game maths in general !!! i need to learn more !!!

#define MAXENTITIES 2048
#define BEAM_MODEL "materials/sprites/laserbeam.vmt"

#include <sourcemod>
#include <sdkhooks>
#include <tf2_stocks>

#define PLUGIN_NAME "NotnHeavy - Sentry Point Laser"

//////////////////////////////////////////////////////////////////////////////
// GLOBALS                                                                  //
//////////////////////////////////////////////////////////////////////////////

enum
{	
	SENTRYGUN_ATTACHMENT_MUZZLE = 0,
	SENTRYGUN_ATTACHMENT_MUZZLE_ALT,
	SENTRYGUN_ATTACHMENT_ROCKET,
};

enum struct sentry_t
{
    int m_iStart;
    int m_iEnd;
}
static sentry_t g_SentryData[MAXENTITIES + 1];

static int g_iBeamModel;

static any CObjectSentrygun_m_vecCurAngles;
static any CObjectSentrygun_m_iAttachments;
static any CObjectSentrygun_m_iLastMuzzleAttachmentFired;

static Handle SDKCall_CBaseAnimating_GetAttachment;

//////////////////////////////////////////////////////////////////////////////
// PLUGIN INFO                                                              //
//////////////////////////////////////////////////////////////////////////////

public Plugin myinfo =
{
    name = PLUGIN_NAME,
    author = "NotnHeavy",
    description = "A random plugin that spawns a beam between a sentry and its target point.",
    version = "1.0",
    url = "none"
};

//////////////////////////////////////////////////////////////////////////////
// INITIALISATION                                                           //
//////////////////////////////////////////////////////////////////////////////

public void OnPluginStart()
{
    LoadTranslations("common.phrases");

    // Find offsets.
    CObjectSentrygun_m_vecCurAngles = FindSendPropInfo("CObjectSentrygun", "m_iAmmoShells") - 28;
    CObjectSentrygun_m_iAttachments = FindSendPropInfo("CObjectSentrygun", "m_nShieldLevel") + 12;
    CObjectSentrygun_m_iLastMuzzleAttachmentFired = FindSendPropInfo("CObjectSentrygun", "m_hAutoAimTarget") + 32;

    // Load gamedata.
    GameData config = new GameData(PLUGIN_NAME);
    if (config == null)
        ThrowError("Failed to load gamedata for plugin \"%s\"", PLUGIN_NAME);

    // Prep SDKCalls.
    StartPrepSDKCall(SDKCall_Entity);
    PrepSDKCall_SetFromConf(config, SDKConf_Signature, "CBaseAnimating::GetAttachment()");
    PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);                              // int iAttachment;
    PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef, .encflags = VENCODE_FLAG_COPYBACK); // Vector& absOrigin;
    PrepSDKCall_AddParameter(SDKType_QAngle, SDKPass_ByRef, .encflags = VENCODE_FLAG_COPYBACK); // QAngle& absAngles;
    PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);                                     // bool
    SDKCall_CBaseAnimating_GetAttachment = EndPrepSDKCall();

    delete config;
    PrintToServer("--------------------------------------------------------\n\"%s\" has loaded.\n--------------------------------------------------------", PLUGIN_NAME);
}

public void OnPluginEnd()
{
    // Remove all target entities to prevent memory leaks.
    for (int i = MaxClients + 1; i <= MAXENTITIES; ++i)
    {
        if (g_SentryData[i].m_iStart && IsValidEntity(g_SentryData[i].m_iStart))
        {
            RemoveNotWorld(g_SentryData[i].m_iStart);
            RemoveNotWorld(g_SentryData[i].m_iEnd);
        }
    }   
}

public void OnMapStart()
{
    g_iBeamModel = PrecacheModel(BEAM_MODEL);
}

//////////////////////////////////////////////////////////////////////////////
// ENTITIES                                                                 //
//////////////////////////////////////////////////////////////////////////////

static void RemoveNotWorld(int entity)
{
    if (IsValidEntity(entity) && entity)
        RemoveEntity(entity);
}

//////////////////////////////////////////////////////////////////////////////
// FILTERS                                                                  //
//////////////////////////////////////////////////////////////////////////////

static bool Filter_IgnoreSentry(int entity, int contentsMask, any data)
{
    if (entity == data)
        return false;
    return true;
}

//////////////////////////////////////////////////////////////////////////////
// FORWARDS                                                                 //
//////////////////////////////////////////////////////////////////////////////

public void OnGameFrame()
{
    static int frame = 0;
    ++frame;
    for (int i = MaxClients + 1; i <= MAXENTITIES; ++i)
    {
        if (IsValidEntity(i))
        {
            char classname[64];
            GetEntityClassname(i, classname, sizeof(classname));
            if (strcmp(classname, "obj_sentrygun") == 0 && !GetEntProp(i, Prop_Send, "m_bCarried") && !GetEntProp(i, Prop_Send, "m_bPlacing") && !GetEntProp(i, Prop_Send, "m_bBuilding"))
            {
                // Validate the existence of the target entity.
                if (!IsValidEntity(g_SentryData[i].m_iStart) || g_SentryData[i].m_iStart == 0)
                {
                    RemoveNotWorld(g_SentryData[i].m_iStart);
                    RemoveNotWorld(g_SentryData[i].m_iEnd);

                    int target = CreateEntityByName("info_target");
                    SetEntityModel(target, BEAM_MODEL);
                    SetEntityRenderMode(target, RENDER_NONE);
                    DispatchSpawn(target);
                    g_SentryData[i].m_iStart = EntIndexToEntRef(target);

                    target = CreateEntityByName("info_target");
                    SetEntityModel(target, BEAM_MODEL);
                    SetEntityRenderMode(target, RENDER_NONE);
                    DispatchSpawn(target);
                    g_SentryData[i].m_iEnd = EntIndexToEntRef(target);
                }
                
                // Get targets.
                int start = EntRefToEntIndex(g_SentryData[i].m_iStart);
                int end = EntRefToEntIndex(g_SentryData[i].m_iEnd);

                // Get muzzle origin.
                float origin[3];
                float throwaway[3];
                int attachment = GetEntData(i, CObjectSentrygun_m_iLastMuzzleAttachmentFired);
                if (!attachment)
                    attachment = GetEntData(i, CObjectSentrygun_m_iAttachments + SENTRYGUN_ATTACHMENT_MUZZLE * 4);
                if (!SDKCall(SDKCall_CBaseAnimating_GetAttachment, i, attachment, origin, throwaway))
                    continue;
                TeleportEntity(start, origin);

                // Get an origin where the sentry is pointing.
                float angles[3];
                float buffer[3];
                GetEntDataVector(i, CObjectSentrygun_m_vecCurAngles, angles);
                TR_TraceRayFilter(origin, angles, MASK_SHOT, RayType_Infinite, Filter_IgnoreSentry, i);
                TR_GetEndPosition(buffer);
                //AddVectors(buffer, {0.00, 0.00, 50.00}, buffer);
                TeleportEntity(end, buffer);

                // Create the beam point and send it to all clients.
                TE_Start("BeamEntPoint");
                TE_WriteEncodedEnt("m_nStartEntity", start);
                TE_WriteEncodedEnt("m_nEndEntity", end);
                TE_WriteNum("m_nModelIndex", g_iBeamModel);
                TE_WriteNum("m_nHaloIndex", 0);
                TE_WriteNum("m_nStartFrame", 0);
                TE_WriteNum("m_nFrameRate", 0);
                TE_WriteNum("m_nFadeLength", 0);
                TE_WriteNum("m_nSpeed", 0);
                TE_WriteNum("r", 255);
                TE_WriteNum("g", 0);
                TE_WriteNum("b", 0);
                TE_WriteNum("a", 255);
                TE_WriteFloat("m_fLife", 0.1);
                TE_WriteFloat("m_fWidth", 1.0);
                TE_WriteFloat("m_fEndWidth", 1.0);
                TE_WriteFloat("m_fAmplitude", 0.0);
                TE_SendToAll();

                // Check if there is an enemy target to hit.
                int enemy = GetEntPropEnt(i, Prop_Send, "m_hEnemy");
                if (IsValidEntity(enemy))
                {
                    // Create the beam point and send it to all clients.
                    TE_Start("BeamEntPoint");
                    TE_WriteEncodedEnt("m_nStartEntity", start);
                    TE_WriteEncodedEnt("m_nEndEntity", enemy);
                    TE_WriteNum("m_nModelIndex", g_iBeamModel);
                    TE_WriteNum("m_nHaloIndex", 0);
                    TE_WriteNum("m_nStartFrame", 0);
                    TE_WriteNum("m_nFrameRate", 0);
                    TE_WriteNum("m_nFadeLength", 0);
                    TE_WriteNum("m_nSpeed", 0);
                    TE_WriteNum("r", 0);
                    TE_WriteNum("g", 255);
                    TE_WriteNum("b", 0);
                    TE_WriteNum("a", 255);
                    TE_WriteFloat("m_fLife", 0.1);
                    TE_WriteFloat("m_fWidth", 1.0);
                    TE_WriteFloat("m_fEndWidth", 1.0);
                    TE_WriteFloat("m_fAmplitude", 0.0);
                    TE_SendToAll();
                }
            }
        }
        else if (g_SentryData[i].m_iStart && IsValidEntity(g_SentryData[i].m_iStart))
        {
            RemoveNotWorld(g_SentryData[i].m_iStart);
            RemoveNotWorld(g_SentryData[i].m_iEnd);
        }
    }
}