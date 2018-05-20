/**
 * HTTP:X
 *
 * By [ --{-@ ] Black Rose
 *
 * A continuation and an evolution of HTTP2, originally based on HTTP v0.4 by Bugsy
 **/

/*
 * INCLUDES
 */
 
#include <amxmodx>
#include <sockets>
#include <engine>
#include <regex>

#define NVAULT 1
#define FVAULT 2

// Select vault system below
#define VAULT_SYSTEM NVAULT

#if VAULT_SYSTEM == NVAULT
#include <nvault>
#else
#include <fvault>
#endif

/* Threaded Sockets natives - Work in progress
 * If you want to use threaded sockets just download the module. The plugin will adapt automatically.
 * http://forums.alliedmods.net/showthread.php?t=262924
 */
/* WIP, behind the scenes.
native socket_create_t();
native socket_open_t(const iThreadHandle, const szHostname[], const port, const protocol, const CallBackHandler[]);
native socket_send_t(const iThreadHandle, const szData[], const iDataLen, const CallBackHandler[]);
native socket_recv_t(const iThreadHandle, const CallBackHandler[], const iRecvDataLen);
native socket_close_t(const iThreadHandle, const CallBackHandler[]);
native socket_destroy_t(const iThreadHandle);
*/

/*
 * GLOBALS
 */

#define KB(%0) %0*1024

#define MAX_DOWNLOAD_SLOTS	10
#define MAX_30X_REDIRECT	3
#define BUFFER_SIZE			KB(64)
#define THINK_INTERVAL		0.01
#define QUE_INTERVAL		0.2

#define ishex(%0) ( ( '0' <= %0 <= '9' || 'a' <= %0 <= 'f' || 'A' <= %0 <= 'F' ) ? true : false)
#define isurlsafe(%0) ( ( '0' <= %0 <= '9' || 'a' <= %0 <= 'z' || 'A' <= %0 <= 'Z' || %0 == '-' || %0 == '_' || %0 == '.' || %0 == '~' || %0 == '%' || %0 == ' ' ) ? true : false)
#define ctod(%0) ( '0' <= %0 <= '9' ? %0 - '0' : 'A' <= %0 <= 'Z' ? %0 -'A' + 10 : 'a' <= %0 <= 'z' ? %0 -'a' + 10 : 0 )
#define dtoc(%0) ( 0 <= %0 <= 9 ? %0 + '0' : 10 <= %0 <= 35 ? %0 + 'A' - 10 : 0 )

new const VersionNum = 111;

enum ( <<= 1 ) {
	STATUS_ACTIVE = 1,
	STATUS_FIRSTRUN,
	STATUS_CHUNKED_TRANSFER,
	STATUS_LARGE_SIZE
};

enum {
	REQUEST_GET,
	REQUEST_POST
};

new const RequestTypes[][] = {
	"GET",
	"POST"
};

new const Base64Table[] =
/*
 * 0000000000111111111122222222223333333333444444444455555555556666
 * 0123456789012345678901234567890123456789012345678901234567890123
 */
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

enum ItemDataEnum {
	_DownloadID,
	_QueID,
	_Filename[128],
	_BytesReceived,
	_BytesReceivedLarge[16],
	_Filesize,
	_FilesizeLarge[16],
	_LatestLarge[16],
	_hFile,
	_hSocket,
	_hProgress,
	_hComplete,
	_PluginID,
	_Port,
	_Status,
	_RequestType,
	_30XCount,
	_EndOfChunk,
	_PostVars[1024],
	_CustomValue
};

enum _:URLDataEnum {
	_Scheme[10],
	_Host[64],
	_URLPort,
	_User[64],
	_Pass[64],
	_Path[160],
	_Query[192],
	_Fragment[128]
};

enum _:QueDataEnum {
	_QueDownloadID,
	_QueURL[512],
	_QueFilename[128],
	_QueCompleteHandler[33],
	_QueProgressHandler[33],
	_QuePluginID,
	_QuePort,
	_QueRequestType,
	_QueUsername[64],
	_QuePassword[64],
	_QuePostVars[1024],
	_QueCustomValue
};

new gIndex;
new gInformation[MAX_DOWNLOAD_SLOTS][ItemDataEnum];
new gURLParsed[MAX_DOWNLOAD_SLOTS][URLDataEnum];
new gQueData[QueDataEnum];
new gQueIndex;
new gDataBuffer[BUFFER_SIZE];
new gBufferLen;
new gBufferPos;
new gDownloadID = 1;

new gReturnDummy;
new gDownloadEntity;
new gBufferSizeLarge[16];
new gOneLarge[1];
new bool:gInitialized;

new gPostVars[1024];

new Array:gQue_hArray;

new gQueEntity;
new gPluginID;

#if defined _nvault_included
new ghVault;
#else
new gVaultName[] = "HTTPX_AutoUpdate";
#endif

new ManagerHandler[2];

new gpcvarAutoupdate;

/* WIP, behind the scenes.
new bool:gThreadedSockets = true;
new gFilteredNatives[][] = {
	"socket_create_t",
	"socket_open_t",
	"socket_send_t",
	"socket_recv_t",
	"socket_close_t",
	"socket_destroy_t"
}
*/

/*
 * FORWARDS
 */

public plugin_init() {

	new temp[5];
	num_to_str(VersionNum, temp[1], charsmax(temp));
	temp[0] = temp[1];
	temp[1] = '.';

	register_plugin("HTTP:X", temp, "[ --{-@ ]");

/* WIP, behind the scenes.
	if ( gThreadedSockets )
		server_print("[HTTP:X] Threaded Sockets Enabled");
	else
		server_print("[HTTP:X] Threaded Sockets Disabled");
*/
}

public plugin_precache() {

	gpcvarAutoupdate = register_cvar("httpx_autoupdate", "");

	new temp[3];
	get_pcvar_string(gpcvarAutoupdate, temp, charsmax(temp));

	if ( read_flags(temp) & 1 )
		Download("digitaldecay.eu/forums/AM/HTTPX/httpx_version.txt", "", "HTTPX_VersionCheckComplete", "", 80, REQUEST_GET, "", "", 0, -1);
}

public HTTPX_VersionCheckComplete(Index, Error)
	if ( ! Error && str_to_num(gDataBuffer) > VersionNum )
		AutoupdatePlugin(-1, "154827", 0);

public plugin_end() {

	for ( new i ; i < MAX_DOWNLOAD_SLOTS ; i++ ) {
		if ( gInformation[i][_DownloadID] ) {
			TransferDone(i, 0, false);
			if ( file_exists(gInformation[i][_Filename]) )
				delete_file(gInformation[i][_Filename]);
		}
	}

#if defined _nvault_included
	nvault_close(ghVault);
#endif

	if ( gQue_hArray )
		ArrayDestroy(gQue_hArray);
}

public plugin_natives() {

	// set_native_filter("forwardNativeFilter"); // WIP, behind the scenes.

#if defined _nvault_included
	ghVault = nvault_open("HTTPX_AutoUpdate");
#endif

	register_native("HTTPX_Download", "nativeDownload");
	register_native("HTTPX_AddPostVar", "nativeAddPostVar");
	register_native("HTTPX_AddPostRaw", "nativeAddPostRaw");
	
	register_native("HTTPX_Abort", "nativeAbort");
	
	register_native("HTTPX_GetData", "nativeGetData");
	register_native("HTTPX_GetFilename", "nativeGetFilename");
	register_native("HTTPX_GetFilesize", "nativeGetFilesize");
	register_native("HTTPX_GetBytesReceived", "nativeGetBytesReceived");
	register_native("HTTPX_GetNewBytesReceived", "nativeGetNewBytesReceived");
	register_native("HTTPX_SetCustom", "nativeSetCustom");
	register_native("HTTPX_GetCustom", "nativeGetCustom");

	register_native("HTTPX_IsFilesizeLarge", "nativeIsFilesizeLarge");
	register_native("HTTPX_GetFilesizeLarge", "nativeGetFilesizeLarge");
	register_native("HTTPX_GetBytesReceivedLarge", "nativeGetBytesReceivedLarge");
	register_native("HTTPX_GetLargePercentage", "nativeGetLargePercentage");
	register_native("HTTPX_GetLargeDiff", "nativeGetLargeDiff");

	register_native("HTTPX_SetupManager", "nativeSetupManager");
}

/* WIP, behind the scenes.
public forwardNativeFilter(const Native[], Index, Trap) {
	
	if ( Trap )
		return PLUGIN_CONTINUE;

	for ( new i ; i < sizeof gFilteredNatives ; i++ ) {
		if ( equal(Native, gFilteredNatives[i]) ) {
			gThreadedSockets = false;
			return PLUGIN_HANDLED;
		}
	}

	return PLUGIN_CONTINUE;
}
*/

/*
 * NATIVES
 */
 
public nativeDownload(PluginID, NumParams) {
	static stURL[512],
		stFilename[128],
		stCompleteHandler[33],
		stProgressHandler[33],
		stPort,
		stRequestType,
		stUsername[64],
		stPassword[64];
	
	get_string(1, stURL, charsmax(stURL));
	get_string(2, stFilename, charsmax(stFilename));

	if ( NumParams >= 3 )
		get_string(3, stCompleteHandler, charsmax(stCompleteHandler));
	else
		stCompleteHandler[0] = 0;
		
	if ( NumParams >= 4 )
		get_string(4, stProgressHandler, charsmax(stProgressHandler));
	else
		stProgressHandler[0] = 0;
		
	if ( NumParams >= 5 )
		stPort = get_param(5);
	else
		stPort = 0;
		
	if ( NumParams >= 6 )
		stRequestType = get_param(6);
	else
		stRequestType = 0;
		
	if ( NumParams >= 7 )
		get_string(7, stUsername, charsmax(stUsername));
	else
		stUsername[0] = 0;
		
	if ( NumParams >= 8 )
		get_string(8, stPassword, charsmax(stPassword));
	else
		stPassword[0] = 0;

	if ( ! gQue_hArray ) {
		gQue_hArray = ArrayCreate(sizeof gQueData, 1);
		register_think("HTTPX_Que", "QueThink");
	}
	
	copy(gQueData[_QueURL], charsmax(gQueData[_QueURL]), stURL);
	copy(gQueData[_QueFilename], charsmax(gQueData[_QueFilename]), stFilename);
	copy(gQueData[_QueCompleteHandler], charsmax(gQueData[_QueCompleteHandler]), stCompleteHandler);
	copy(gQueData[_QueProgressHandler], charsmax(gQueData[_QueProgressHandler]), stProgressHandler);
	copy(gQueData[_QueUsername], charsmax(gQueData[_QueUsername]), stUsername);
	copy(gQueData[_QuePassword], charsmax(gQueData[_QuePassword]), stPassword);
	
	gQueData[_QueDownloadID] = gDownloadID;
	gQueData[_QuePort] = stPort;
	gQueData[_QueRequestType] = stRequestType;
	
	gQueData[_QuePluginID] = PluginID;
	
	if ( stRequestType == REQUEST_POST && gPostVars[0] ) {
		copy(gQueData[_QuePostVars], charsmax(gQueData[_QuePostVars]), gPostVars);
		gPostVars[0] = 0;
	}
	
	ArrayPushArray(gQue_hArray, gQueData);
	
	if ( ! gQueEntity ) {
		gQueEntity = create_entity("info_target");
		
		if ( ! gQueEntity ) {
			log_amx("[HTTP:X] Failed to create entity.");
			return -1;
		}
		
		entity_set_string(gQueEntity, EV_SZ_classname, "HTTPX_Que");
		entity_set_float(gQueEntity, EV_FL_nextthink, get_gametime() + QUE_INTERVAL);
	}
	
	return gDownloadID++;
}

public nativeAddPostVar(PluginID, NumParams) {
	
	static stVar[1024], stVal[1024];
	new len = strlen(gPostVars);
	
	get_string(1, stVar, charsmax(stVar));
	get_string(2, stVal, charsmax(stVal));
	
	URLEncode(stVar, charsmax(stVar));
	URLEncode(stVal, charsmax(stVal));
	
	formatex(gPostVars[len], charsmax(gPostVars) - len, "%s%s=%s", len ? "&" : "", stVar, stVal);
}

public nativeAddPostRaw(PluginID, NumParams) {
	
	new len = strlen(gPostVars);
	get_string(1, gPostVars[len], charsmax(gPostVars) - len);
}

public nativeAbort(PluginID, NumParams) {
	
	new Index = GetDownloadSlot(get_param(1));
	
	if ( Index == -1 )
		return;
	
	TransferDone(Index, 0, false);
	
	if ( get_param(2) && gInformation[Index][_Filename] && file_exists(gInformation[Index][_Filename]) )
		delete_file(gInformation[Index][_Filename]);
}

public nativeGetData(PluginID, NumParams) {

	new datalen = min(get_param(2), gBufferLen - gBufferPos);

	if ( ! datalen )
		return 0;

	set_string(1, gDataBuffer[gBufferPos], datalen);

	gBufferPos += datalen;

	return datalen;
}

public nativeGetFilename(PluginID, NumParams) {
	
	new Index = GetDownloadSlot(get_param(1));
	
	if ( Index == -1 )
		return;

	set_string(2, gInformation[Index][_Filename], get_param(3));
}

public nativeGetFilesize(PluginID, NumParams) {
	
	new Index = GetDownloadSlot(get_param(1));
	
	return Index == -1 ? 0 : gInformation[Index][_Filesize];
}

public nativeGetBytesReceived(PluginID, NumParams) {
	
	new Index = GetDownloadSlot(get_param(1));

	return Index == -1 ? 0 : gInformation[Index][_BytesReceived];
}

public nativeGetNewBytesReceived(PluginID, NumParams)
	return gBufferLen;

public nativeSetCustom(PluginID, NumParams) {

	new DownloadID = get_param(1);

	for ( new i = ArraySize(gQue_hArray) - 1 ; i >= gQueIndex ; i-- ) {

		ArrayGetArray(gQue_hArray, i, gQueData);

		if ( gQueData[_QueDownloadID] == DownloadID ) {
			gQueData[_QueCustomValue] = get_param(2);
			ArraySetArray(gQue_hArray, i, gQueData);
			return 1;
		}
	}

	for ( new i ; i < MAX_DOWNLOAD_SLOTS ; i++ ) {

		if ( gInformation[i][_DownloadID] == DownloadID ) {
			gInformation[i][_CustomValue] = get_param(2);
			return 1;
		}
	}

	log_amx("[HTTP:X] Could not set a custom value for %d.", DownloadID);
	return 0;
}

public nativeGetCustom(PluginID, NumParams) {

	new DownloadID = get_param(1);

	for ( new i ; i < MAX_DOWNLOAD_SLOTS ; i++ ) {
		if ( gInformation[i][_DownloadID] == DownloadID )
			return gInformation[i][_CustomValue]
	}

	log_amx("[HTTP:X] Could not retrieve custom value from %d.", DownloadID);
	return 0;
}

public bool:nativeIsFilesizeLarge() {
	
	new Index = GetDownloadSlot(get_param(1));
	
	return Index == -1 ? false : gInformation[Index][_Status] & STATUS_LARGE_SIZE ? true : false;
}

public nativeGetFilesizeLarge(PluginID, NumParams) {

	new Index = GetDownloadSlot(get_param(1));
	
	if ( Index == -1 )
		return;

	new temp[17];
	
	large_tostring(gInformation[Index][_FilesizeLarge], sizeof gInformation[][_FilesizeLarge], temp, charsmax(temp));
	set_string(2, temp, get_param(3));
}

public nativeGetBytesReceivedLarge(PluginID, NumParams) {

	new Index = GetDownloadSlot(get_param(1));
	
	if ( Index == -1 )
		return;

	new temp[17];
	
	large_tostring(gInformation[Index][_BytesReceivedLarge], sizeof gInformation[][_BytesReceivedLarge], temp, charsmax(temp));
	set_string(2, temp, get_param(3));
}

public nativeGetLargePercentage(PluginID, NumParams) {

	if ( NumParams == 1 ) {
		new Index = GetDownloadSlot(get_param(1));
		return Index == -1 ? 0 : large_percentage(gInformation[Index][_BytesReceivedLarge], gInformation[Index][_FilesizeLarge], sizeof gInformation[][_FilesizeLarge]);
	}

	if ( NumParams == 2 ) {

		new temp[17];
		new large[2][16];

		get_string(1, temp, charsmax(temp));
		large_fromstring(large[0], sizeof large[], temp);

		get_string(2, temp, charsmax(temp));
		large_fromstring(large[1], sizeof large[], temp);

		return large_percentage(large[0], large[1], sizeof large[]);
	}
	return 0;
}

public nativeGetLargeDiff(PluginID, NumParams) {

	new temp[16];

	new Index = GetDownloadSlot(get_param(1));

	if ( Index == -1 )
		return 0;

	for ( new i ; i < min(sizeof temp, sizeof gInformation[][_BytesReceivedLarge]) ; i++ )
		temp[i] = gInformation[Index][_BytesReceivedLarge][i];

	large_sub(temp, sizeof temp, gInformation[Index][_LatestLarge], sizeof gInformation[][_LatestLarge]);

	for ( new i ; i < min(sizeof gInformation[][_BytesReceivedLarge], sizeof gInformation[][_LatestLarge]) ; i++ )
		gInformation[Index][_LatestLarge][i] = gInformation[Index][_BytesReceivedLarge][i];

	return large_toint(temp, sizeof temp);
}

/*
 * INTERNAL FUNCTIONS
 */
 
Download(const URL[], const Filename[], const CompleteHandler[], const ProgressHandler[], Port, RequestType, const Username[], const Password[], PluginID, DownloadID, CustomValue = 0) {

	new i;
	while ( i < MAX_DOWNLOAD_SLOTS && ( gInformation[i][_Status] & STATUS_ACTIVE ) ) { i++; }
	
	if ( i == MAX_DOWNLOAD_SLOTS ) {
		log_amx("[HTTP:X] Out of free download slots.");
		gPostVars[0] = 0;
		return;
	}

	ParseURL(URL,
	gURLParsed[i][_Scheme], charsmax(gURLParsed[][_Scheme]),
	gURLParsed[i][_User], charsmax(gURLParsed[][_User]),
	gURLParsed[i][_Pass], charsmax(gURLParsed[][_Pass]),
	gURLParsed[i][_Host], charsmax(gURLParsed[][_Host]),
	gURLParsed[i][_URLPort],
	gURLParsed[i][_Path], charsmax(gURLParsed[][_Path]),
	gURLParsed[i][_Query], charsmax(gURLParsed[][_Query]),
	gURLParsed[i][_Fragment], charsmax(gURLParsed[][_Fragment]));
	
	gInformation[i][_Port] = gURLParsed[i][_URLPort] ? gURLParsed[i][_URLPort] : ! Port ? equali(gURLParsed[i][_Scheme], "https") ? 443 : 80 : Port;
	
	if ( ! gURLParsed[i][_User] )
		copy(gURLParsed[i][_User], charsmax(gURLParsed[][_User]), Username);
	
	if ( ! gURLParsed[i][_Pass] )
		copy(gURLParsed[i][_Pass], charsmax(gURLParsed[][_Pass]), Password);
	
	if ( ! Filename[0] )
		gInformation[i][_hFile] = 0;
	else if ( ! ( gInformation[i][_hFile] = fopen(Filename, "wb") ) ) {
		log_amx("[HTTP:X] Error creating local file.");
		gPostVars[0] = 0;
		return;
	}
	
	new Temp;
	
	if ( ProgressHandler[0] ) {
		if ( equal(ProgressHandler, "HTTPX_PluginUpdaterProgress") ) {
			if ( ! gPluginID )
				gPluginID = get_plugin(-1);

			gInformation[i][_hProgress] = CreateOneForward(gPluginID, ProgressHandler, FP_CELL);
		}
		else
			gInformation[i][_hProgress] = CreateOneForward(PluginID, ProgressHandler, FP_CELL);
	}
		
	if ( CompleteHandler[0] ) {
		if ( equal(CompleteHandler, "HTTPX_PluginUpdaterComplete") || equal(CompleteHandler, "HTTPX_VersionCheckComplete") ) {

			if ( ! gPluginID )
				gPluginID = get_plugin(-1);

			gInformation[i][_hComplete] = CreateOneForward(gPluginID, CompleteHandler, FP_CELL, FP_CELL);
		}
		else
			gInformation[i][_hComplete] = CreateOneForward(PluginID, CompleteHandler, FP_CELL, FP_CELL);
	}

	gInformation[i][_PluginID] = PluginID;
	
	gInformation[i][_hSocket] = socket_open(gURLParsed[i][_Host], gInformation[i][_Port], SOCKET_TCP, Temp);
	
	if ( Temp ) {
		switch ( Temp ) {
			case 1: log_amx("[HTTP:X] Socket error: Error while creating socket.");
			case 2: log_amx("[HTTP:X] Socket error: Couldn't resolve hostname. (%s)", gURLParsed[i][_Host]);
			case 3: log_amx("[HTTP:X] Socket error: Couldn't connect to host. (%s:%d)", gURLParsed[i][_Host], gInformation[i][_Port]);
		}
		gPostVars[0] = 0;
		return;
	}
	
	static stRequest[2048], stAuth[128], stTempStr[256], stTempScheme[10];
	
	copy(stTempScheme, charsmax(stTempScheme), gURLParsed[i][_Scheme]);
	strtoupper(stTempScheme);
	
	new RequestLen = formatex(stRequest, charsmax(stRequest), "%s /%s%s%s%s%s %s/1.1^r^nHost: %s", RequestTypes[RequestType], gURLParsed[i][_Path], gURLParsed[i][_Query] ? "?" : "", gURLParsed[i][_Query], gURLParsed[i][_Fragment] ? "#" : "", gURLParsed[i][_Fragment], stTempScheme, gURLParsed[i][_Host]);
	
	if ( gURLParsed[i][_User] || gURLParsed[i][_Pass] ) {
		formatex(stTempStr, charsmax(stTempStr), "%s:%s", gURLParsed[i][_User], gURLParsed[i][_Pass]);
		Encode64(stTempStr, stAuth, charsmax(stAuth));
	
		RequestLen += formatex(stRequest[RequestLen], charsmax(stRequest) - RequestLen, "^r^nAuthorization: Basic %s", stAuth);
	}
	
	if ( RequestType == REQUEST_POST && gPostVars[0] ) {
		RequestLen += formatex(stRequest[RequestLen], charsmax(stRequest) - RequestLen, "^r^nContent-Length: %d", strlen(gPostVars));
		RequestLen += copy(stRequest[RequestLen], charsmax(stRequest) - RequestLen, "^r^nContent-Type: application/x-www-form-urlencoded");
		RequestLen += formatex(stRequest[RequestLen], charsmax(stRequest) - RequestLen, "^r^n^r^n%s", gPostVars);
		copy(gInformation[i][_PostVars], charsmax(gInformation[][_PostVars]), gPostVars);
		gPostVars[0] = 0;
	}
	
	copy(stRequest[RequestLen], charsmax(stRequest) - RequestLen, "^r^n^r^n");
	
	socket_send(gInformation[i][_hSocket], stRequest, strlen(stRequest));
	
	if ( ! gDownloadEntity ) {
		gDownloadEntity = create_entity("info_target");
		
		if ( ! gDownloadEntity ) {
			log_amx("[HTTP:X] Failed to create entity.");
			gPostVars[0] = 0;
			return;
		}
		
		entity_set_string(gDownloadEntity, EV_SZ_classname, "HTTPX_Download");
		entity_set_float(gDownloadEntity, EV_FL_nextthink, get_gametime() + THINK_INTERVAL);
		gIndex = -1;
	}
	
	if ( ! gInitialized ) {
		register_think("HTTPX_Download", "DownloadThink");
		large_fromint(gBufferSizeLarge, sizeof gBufferSizeLarge, sizeof gDataBuffer);
		gInitialized = true;
	}
	
	copy(gInformation[i][_Filename], charsmax(gInformation[][_Filename]), Filename);
	gInformation[i][_Status] = STATUS_ACTIVE;
	gInformation[i][_Status] |= STATUS_FIRSTRUN;
	gInformation[i][_RequestType] = RequestType;
	gInformation[i][_DownloadID] = DownloadID;
	gInformation[i][_CustomValue] = CustomValue;
}

public DownloadThink(ent) {

	entity_set_float(gDownloadEntity, EV_FL_nextthink, get_gametime() + THINK_INTERVAL);
	static sti;

	for ( sti = 0 ; sti < MAX_DOWNLOAD_SLOTS ; sti++ ) {
		gIndex = ++gIndex % MAX_DOWNLOAD_SLOTS;
		if ( gInformation[gIndex][_Status] & STATUS_ACTIVE )
			break;
	}
	if ( sti == MAX_DOWNLOAD_SLOTS )
		return;

	if ( ! socket_change(gInformation[gIndex][_hSocket], 1000) )
		return;

	if ( gInformation[gIndex][_Status] & STATUS_FIRSTRUN ) {
		gInformation[gIndex][_Status] &= ~STATUS_FIRSTRUN;

		gBufferPos = 0;

		while ( gBufferPos < sizeof gDataBuffer && socket_recv(gInformation[gIndex][_hSocket], gDataBuffer[gBufferPos], 2) ) {
			if ( gBufferPos >= 3
			&& gDataBuffer[gBufferPos - 3] == '^r'
			&& gDataBuffer[gBufferPos - 2] == '^n'
			&& gDataBuffer[gBufferPos - 1] == '^r'
			&& gDataBuffer[gBufferPos] == '^n' ) {

				static stLocation[512];
				new ReturnCode;
				
				ParseHeader(gIndex, ReturnCode, stLocation, charsmax(stLocation));
				
				if ( 300 <= ReturnCode <= 307 ) {
					if ( FollowLocation(gIndex, stLocation) )
						return;
					else {
						TransferDone(gIndex, -4, true);
						return;
					}
				}
				else if ( ! ( 200 <= ReturnCode <= 299 ) ) {
					if ( ! ReturnCode )
						ReturnCode = -1;
					
					TransferDone(gIndex, ReturnCode, true);
					return;
				}
				break;
			}
			gBufferPos++;
		}
	}

	if ( gInformation[gIndex][_Status] & STATUS_CHUNKED_TRANSFER &&
		gInformation[gIndex][_BytesReceived] == gInformation[gIndex][_EndOfChunk] ) {

		new tempdata[1], strHex[6], i, bool:error;
		
		while ( ! error ) {
			socket_recv(gInformation[gIndex][_hSocket], tempdata, 2);
			
			switch ( tempdata[0] ) {
				case '^n' : {
					if ( i )
						break;
				}
				case '^r' : {}
				default : {
					if ( ishex(tempdata[0]) )
						strHex[i++] = tempdata[0];
					else
						error = true;
				}
			}
		}
		
		if ( error ) {
			TransferDone(gIndex, -2, true);
			return;
		}
		
		GetChunkSize(strHex, gInformation[gIndex][_EndOfChunk]);
		
		if ( ! gInformation[gIndex][_EndOfChunk] ) {
			gInformation[gIndex][_Filesize] = gInformation[gIndex][_BytesReceived];
			TransferDone(gIndex, 0, true);
			return;
		}
		
		gInformation[gIndex][_EndOfChunk] += gInformation[gIndex][_BytesReceived];
	}
	
	static stTempLarge[16];
	new tempsize;
	
	if ( gInformation[gIndex][_Status] & STATUS_CHUNKED_TRANSFER )
		tempsize = min(gInformation[gIndex][_EndOfChunk] - gInformation[gIndex][_BytesReceived] + 1, sizeof gDataBuffer);

	else if ( gInformation[gIndex][_Status] & STATUS_LARGE_SIZE ) {
		large_add(stTempLarge, sizeof stTempLarge, gInformation[gIndex][_FilesizeLarge], sizeof gInformation[][_FilesizeLarge]);
		large_sub(stTempLarge, sizeof stTempLarge, gInformation[gIndex][_BytesReceivedLarge], sizeof gInformation[][_BytesReceivedLarge]);
		large_add(stTempLarge, sizeof stTempLarge, gOneLarge, sizeof gOneLarge);
		
		if ( large_comp(stTempLarge, sizeof stTempLarge, gBufferSizeLarge, sizeof gBufferSizeLarge) == 1 )
			tempsize = sizeof gDataBuffer;
		else
			tempsize = large_toint(stTempLarge, sizeof stTempLarge);
	}
	else
		tempsize = min(gInformation[gIndex][_Filesize] - gInformation[gIndex][_BytesReceived] + 1, sizeof gDataBuffer);

	gBufferPos = 0;

	if ( ( gBufferLen = socket_recv(gInformation[gIndex][_hSocket], gDataBuffer, tempsize) ) <= 0 ) {
		TransferDone(gIndex, -3, true);
		return;
	}

	if ( gInformation[gIndex][_hFile] )
		fwrite_blocks(gInformation[gIndex][_hFile], gDataBuffer, gBufferLen, BLOCK_BYTE);

	gInformation[gIndex][_BytesReceived] += gBufferLen;
	
	if ( gInformation[gIndex][_Status] & STATUS_LARGE_SIZE ) {
		large_fromint(stTempLarge, sizeof stTempLarge, gBufferLen);
		large_add(gInformation[gIndex][_BytesReceivedLarge], sizeof gInformation[][_BytesReceivedLarge], stTempLarge, sizeof stTempLarge);
		
	}
	
	if ( ManagerHandler[0] )
		ExecuteForward(ManagerHandler[0], gReturnDummy, gIndex, gInformation[gIndex][_DownloadID]);

	if ( gInformation[gIndex][_hProgress] ) {
		ExecuteForward(gInformation[gIndex][_hProgress], gReturnDummy, gInformation[gIndex][_DownloadID]);
		
		if ( gReturnDummy == PLUGIN_HANDLED ) {
			TransferDone(gIndex, 0, false);
			return;
		}
	}
	
	if ( ( gInformation[gIndex][_Status] & STATUS_LARGE_SIZE
		&& ! large_comp(gInformation[gIndex][_BytesReceivedLarge], sizeof gInformation[][_BytesReceivedLarge], gInformation[gIndex][_FilesizeLarge], sizeof gInformation[][_FilesizeLarge]) )
	||
		( ! ( gInformation[gIndex][_Status] & STATUS_LARGE_SIZE )
		&& gInformation[gIndex][_BytesReceived] == gInformation[gIndex][_Filesize] )
	) {
		TransferDone(gIndex, 0, true);
		return;
	}
}

public QueThink() {

	new count;

	for ( new i = 0 ; i < MAX_DOWNLOAD_SLOTS ; i++ ) {
		if ( ! ( gInformation[i][_Status] & STATUS_ACTIVE ) )
			count++;
	}

	new Arraysize = ArraySize(gQue_hArray);
	
	if ( count > Arraysize - gQueIndex )
		count = Arraysize - gQueIndex;
	
	while ( count-- ) {
		ArrayGetArray(gQue_hArray, gQueIndex++, gQueData);
		
		if ( gQueData[_QueRequestType] == REQUEST_POST )
			copy(gPostVars, charsmax(gPostVars), gQueData[_QuePostVars]);

		replace_all(gQueData[_QueURL], charsmax(gQueData[_QueURL]), " ", "%20");
		
		Download(gQueData[_QueURL], gQueData[_QueFilename], gQueData[_QueCompleteHandler], gQueData[_QueProgressHandler], gQueData[_QuePort], gQueData[_QueRequestType], gQueData[_QueUsername], gQueData[_QuePassword], gQueData[_QuePluginID], gQueData[_QueDownloadID], gQueData[_QueCustomValue]);
	}
	
	if ( gQueIndex == Arraysize ) {
		ArrayClear(gQue_hArray);
		gQueIndex = 0;
		
		entity_set_int(gQueEntity, EV_INT_flags, FL_KILLME);
		call_think(gQueEntity);
		
		gQueEntity = 0;
		return;
	}
	
	entity_set_float(gQueEntity, EV_FL_nextthink, get_gametime() + QUE_INTERVAL);
}

TransferDone(Index, Error, bool:CallHandler) {

	if ( gInformation[Index][_hFile] )
		fclose(gInformation[Index][_hFile]);
	
	socket_close(gInformation[Index][_hSocket]);
	
	if ( ManagerHandler[1] )
		ExecuteForward(ManagerHandler[1], gReturnDummy, Index, gInformation[gIndex][_DownloadID], CallHandler? Error : -999);

	if ( CallHandler && gInformation[Index][_hComplete] )
		ExecuteForward(gInformation[Index][_hComplete], gReturnDummy, gInformation[Index][_DownloadID], Error);
	
	DestroyForward(gInformation[Index][_hProgress]);
	DestroyForward(gInformation[Index][_hComplete]);
	
	gInformation[Index][_BytesReceived] = 0;
	gInformation[Index][_Filesize] = 0;
	gInformation[Index][_EndOfChunk] = 0;
	gInformation[Index][_hSocket] = 0;
	gInformation[Index][_hProgress] = 0;
	gInformation[Index][_hComplete] = 0;
	gInformation[Index][_hFile] = 0;
	gInformation[Index][_Status] = 0;
	gInformation[Index][_PostVars] = 0;
	gInformation[Index][_DownloadID] = 0;
	gInformation[Index][_PluginID] = 0;
	
	for ( new i = 0 ; i < sizeof gInformation ; i++ ) {
		if ( gInformation[i][_Status] & STATUS_ACTIVE )
			return;
	}
	
	entity_set_int(gDownloadEntity, EV_INT_flags, FL_KILLME);
	call_think(gDownloadEntity);
	
	gDownloadEntity = 0;
}

FollowLocation(Index, const Location[]) {

	socket_close(gInformation[Index][_hSocket]);
	if ( gInformation[Index][_30XCount] >= MAX_30X_REDIRECT )
		TransferDone(Index, -5, true);

	new bool:Relative = true;
	static stFollow_TempURLParsed[URLDataEnum];
	
	arrayset(stFollow_TempURLParsed, 0, sizeof stFollow_TempURLParsed);
	ParseURL(Location,
	stFollow_TempURLParsed[_Scheme], charsmax(stFollow_TempURLParsed[_Scheme]),
	stFollow_TempURLParsed[_User], charsmax(stFollow_TempURLParsed[_User]),
	stFollow_TempURLParsed[_Pass], charsmax(stFollow_TempURLParsed[_Pass]),
	stFollow_TempURLParsed[_Host], charsmax(stFollow_TempURLParsed[_Host]),
	stFollow_TempURLParsed[_URLPort],
	stFollow_TempURLParsed[_Path], charsmax(stFollow_TempURLParsed[_Path]),
	stFollow_TempURLParsed[_Query], charsmax(stFollow_TempURLParsed[_Query]),
	stFollow_TempURLParsed[_Fragment], charsmax(stFollow_TempURLParsed[_Fragment]));
	
	if ( stFollow_TempURLParsed[_Scheme] )
		copy(gURLParsed[Index][_Scheme], charsmax(gURLParsed[][_Scheme]), stFollow_TempURLParsed[_Scheme]);
	if ( stFollow_TempURLParsed[_Host] ) {
		copy(gURLParsed[Index][_Host], charsmax(gURLParsed[][_Host]), stFollow_TempURLParsed[_Host]);
		Relative = false;
	}
	if ( stFollow_TempURLParsed[_URLPort] )
		gInformation[Index][_Port] = stFollow_TempURLParsed[_URLPort];
	if ( stFollow_TempURLParsed[_User] )
		copy(gURLParsed[Index][_User], charsmax(gURLParsed[][_User]), stFollow_TempURLParsed[_User]);
	if ( stFollow_TempURLParsed[_Pass] )
		copy(gURLParsed[Index][_Pass], charsmax(gURLParsed[][_Pass]), stFollow_TempURLParsed[_Pass]);
	if ( stFollow_TempURLParsed[_Path] ) {
		if ( Relative )
			add(gURLParsed[Index][_Path], charsmax(gURLParsed[][_Path]), stFollow_TempURLParsed[_Path]);
		else
			copy(gURLParsed[Index][_Path], charsmax(gURLParsed[][_Path]), stFollow_TempURLParsed[_Path]);
	}
	if ( stFollow_TempURLParsed[_Query] )
		copy(gURLParsed[Index][_Query], charsmax(gURLParsed[][_Query]), stFollow_TempURLParsed[_Query]);
	if ( stFollow_TempURLParsed[_Fragment] )
		copy(gURLParsed[Index][_Fragment], charsmax(gURLParsed[][_Fragment]), stFollow_TempURLParsed[_Fragment]);
	
	new ResultNum;
	gInformation[Index][_hSocket] = socket_open(gURLParsed[Index][_Host], gInformation[Index][_Port], SOCKET_TCP, ResultNum);
	
	if ( ResultNum ) {
		switch ( ResultNum ) {
		case 1: log_amx("[HTTP:X] Socket error: Error while creating socket.");
		case 2: log_amx("[HTTP:X] Socket error: Couldn't resolve hostname.");
		case 3: log_amx("[HTTP:X] Socket error: Couldn't connect to given hostname:port.");
		}
		return 0;
	}
	
	static stRequest[2048], stAuth[256], stTempStr[256], stTempScheme[10];
	
	copy(stTempScheme, charsmax(stTempScheme), gURLParsed[Index][_Scheme]);
	strtoupper(stTempScheme);
	
	new RequestLen = formatex(stRequest, charsmax(stRequest), "%s /%s%s%s%s%s %s/1.1^r^nHost: %s", RequestTypes[gInformation[Index][_RequestType]], gURLParsed[Index][_Path], gURLParsed[Index][_Query] ? "?" : "", gURLParsed[Index][_Query], gURLParsed[Index][_Fragment] ? "#" : "", gURLParsed[Index][_Fragment], stTempScheme, gURLParsed[Index][_Host]);
	
	if ( gURLParsed[Index][_User] || gURLParsed[Index][_Pass] ) {
		formatex(stTempStr, charsmax(stTempStr), "%s:%s", gURLParsed[Index][_User], gURLParsed[Index][_Pass]);
		Encode64(stTempStr, stAuth, charsmax(stAuth));
		
		RequestLen += formatex(stRequest[RequestLen], charsmax(stRequest) - RequestLen, "^r^nAuthorization: Basic %s", stAuth);
	}
	
	if ( gInformation[Index][_RequestType] == REQUEST_POST && gInformation[Index][_PostVars] ) {
		RequestLen += formatex(stRequest[RequestLen], charsmax(stRequest) - RequestLen, "^r^nContent-Length: %d", strlen(gInformation[Index][_PostVars]));
		RequestLen += copy(stRequest[RequestLen], charsmax(stRequest) - RequestLen, "^r^nContent-Type: application/x-www-form-urlencoded");
		RequestLen += formatex(stRequest[RequestLen], charsmax(stRequest) - RequestLen, "^r^n^r^n%s", gInformation[Index][_PostVars]);
	}
	
	copy(stRequest[RequestLen], charsmax(stRequest) - RequestLen, "^r^n^r^n");
	
	socket_send(gInformation[Index][_hSocket], stRequest, strlen(stRequest));
	
	gInformation[Index][_Status] = STATUS_ACTIVE;
	gInformation[Index][_Status] |= STATUS_FIRSTRUN;
	gInformation[Index][_30XCount]++;
	
	return 1;
}

ParseHeader(Index, &ReturnCode, Location[], LocationLen) {

	static stTempStr[256];
	new iPos, c;
	
	if ( gBufferPos ) {
		gBufferPos += 3;
		
		iPos = containi(gDataBuffer, "HTTP/1.1 ") + 9;
		
		if ( iPos != 8 && iPos < gBufferPos ) {
			while ( gDataBuffer[iPos + c] != '^r' && c < charsmax(stTempStr) )
				stTempStr[c] = gDataBuffer[iPos + c++];
			
			stTempStr[c] = 0;
			ReturnCode = str_to_num(stTempStr);
		}
		
		iPos = containi(gDataBuffer, "Transfer-Encoding: ") + 19;
		c = 0;
		
		if ( iPos != 18 && iPos < gBufferPos ) {
			while ( gDataBuffer[iPos + c] != '^r' && c < charsmax(stTempStr) )
				stTempStr[c] = gDataBuffer[iPos + c++];
			
			stTempStr[c] = 0;
			
			if ( equali(stTempStr, "chunked") )
				gInformation[Index][_Status] |= STATUS_CHUNKED_TRANSFER;
		}
		
		if ( 300 <= ReturnCode <= 399 ) {
			iPos = containi(gDataBuffer, "Location: ") + 10;
			c = 0;
			
			if ( iPos != 9 && iPos < gBufferPos ) {
				while ( gDataBuffer[iPos + c] != '^r' && c < LocationLen )
					Location[c] = gDataBuffer[iPos + c++];
				
				Location[c] = 0;
			}
		}
		
		iPos = containi(gDataBuffer, "Content-Length: ") + 16;
		c = 0;
		
		if ( iPos != 15 && iPos < gBufferPos ) {
			while ( gDataBuffer[iPos + c] != '^r' && c < charsmax(stTempStr) )
				stTempStr[c] = gDataBuffer[iPos + c++];
			
			stTempStr[c] = 0;
			gInformation[Index][_Filesize] = str_to_num(stTempStr);
			large_fromstring(gInformation[Index][_FilesizeLarge], sizeof gInformation[][_FilesizeLarge], stTempStr);
			
			static stTempLarge[16];
			large_fromint(stTempLarge, sizeof stTempLarge, gInformation[Index][_Filesize]);
			
			if ( large_comp(gInformation[Index][_FilesizeLarge], sizeof gInformation[][_FilesizeLarge], stTempLarge, sizeof stTempLarge) != 0 )
				gInformation[Index][_Status] |= STATUS_LARGE_SIZE;
		}
		else
			gInformation[Index][_Filesize] = -1;
	}
}

ParseURL(const URL[], Scheme[]="", Schemelen=0, User[]="", Userlen=0, Pass[]="", Passlen=0, Host[]="", Hostlen=0, &Port, Path[]="", Pathlen=0, Query[]="", Querylen=0, Fragment[]="", Fragmentlen=0) {
	
	new temp;
	static Regex:stParseURL_hRegex;
	
	if ( ! stParseURL_hRegex )
		stParseURL_hRegex = regex_compile("(?:(\w+):///?)?(?:([\w&\$\+\,/\.;=\[\]\{\}\|\\\^^\~%?#\-]+):([\w&\$\+\,/\.;=\[\]\{\}\|\\\^^\~%?#\-]+)@)?((?:[\w-]+\.)*[\w-]+\.[\w-]+)?(?::(\d+))?(?:/?([\w&\$\+\,/\.;=@\[\]\{\}\|\\\^^\~%:\-]*))?(?:\?([\w&\$\+\,/\.;=@\[\]\{\}\|\\\^^\~%:\-]*))?(?:#([\w&\$\+\,/\.;=@\[\]\{\}\|\\\^^\~%:\-]*))?", temp, "", 0);
	/*
	Scheme		(?:(\w+):///?)?
	Auth		(?:([\w&\$\+\,/\.;=\[\]\{\}\|\\\^^\~%?#\-]+):([\w&\$\+\,/\.;=\[\]\{\}\|\\\^^\~%?#\-]+)@)?
	Host		((?:[\w-]+\.)*[\w-]+\.[\w-]+)?
	Port		(?::(\d+))?
	Path		(?:/?([\w&\$\+\,/\.;=@\[\]\{\}\|\\\^^\~%:\- ]*))?
	Query		(?:\?([\w&\$\+\,/\.;=@\[\]\{\}\|\\\^^\~%:\- ]*))?
	Fragment	(?:#([\w&\$\+\,/\.;=@\[\]\{\}\|\\\^^\~%:\- ]*))?
	*/
	new TempPort[8];
	
	regex_match_c(URL, stParseURL_hRegex, temp);
	
	regex_substr(stParseURL_hRegex, 1, Scheme, Schemelen);
	if ( ! Scheme[0] || equali(Scheme, "https") )
		copy(Scheme, Schemelen, "http");
	regex_substr(stParseURL_hRegex, 2, User, Userlen);
	regex_substr(stParseURL_hRegex, 3, Pass, Passlen);
	regex_substr(stParseURL_hRegex, 4, Host, Hostlen);
	regex_substr(stParseURL_hRegex, 5, TempPort, charsmax(TempPort));
	Port = str_to_num(TempPort);
	regex_substr(stParseURL_hRegex, 6, Path, Pathlen);
	regex_substr(stParseURL_hRegex, 7, Query, Querylen);
	regex_substr(stParseURL_hRegex, 8, Fragment, Fragmentlen);
}

GetDownloadSlot(DownloadID) {
	for ( new i ; i < sizeof gInformation ; i++ ) {
		if ( gInformation[i][_DownloadID] == DownloadID )
			return i;
	}
	return -1;
}

GetChunkSize(const Data[], &ChunkSize) {
	
	new i, c, Hex[7];
	
	while ( Data[i] == '^r' || Data[i] == '^n' )
		i++;
	
	while ( ishex(Data[i]) && c < charsmax(Hex) )
		Hex[c++] = Data[i++];
	
	while ( Data[i] == '^r' || Data[i] == '^n' )
		i++;
	
	ChunkSize = HexToDec(Hex);
	
	return i;
}

URLEncode(string[], len) {
	new what[2], with[4] = "^%";
	
	replace_all(string, len, "^%", "^%25");
	
	for ( new i = 0 ; i < len ; i++ ) {
		
		if ( ! string[i] )
			break;
		
		if ( ! isurlsafe(string[i]) ) {
			what[0] = string[i];
			DecToHex(what[0], with[1], charsmax(with) - 1);
			replace_all(string, len, what, with);
		}
	}
	replace_all(string, len, " ", "+");
}

public nativeUpdatePlugin(PluginID, Dummy, file_id[], frequency) // Backwards compatibility
	AutoupdatePlugin(PluginID, file_id, frequency);

public AutoupdatePlugin(PluginID, file_id[], frequency) {

	new temp[3];
	get_pcvar_string(gpcvarAutoupdate, temp, charsmax(temp));

	if ( ! ( read_flags(temp) & 2 ) ) {
		log_amx("[HTTP:X] Autoupdating of plugins have been disabled. If you want to enable it, add ^"b^" to httpx_autoupdate")
		return;
	}

	if ( equali(file_id, "REPLACE_THIS_WITH_YOUR_FILE_ID") )
		return;

	static TempURL[512];
	new len = copy(TempURL, charsmax(TempURL), "http://www.amxmodx.org/plcompiler_vb.cgi?file_id=");
	
	new tempfile[40];
	new timestamp;

	copy(TempURL[len], charsmax(TempURL) - len, file_id);

	if ( frequency ) {
		get_plugin(PluginID, tempfile, charsmax(tempfile));

#if defined _nvault_included
		new result = nvault_lookup(ghVault, tempfile, temp, 0, timestamp);
#else
		new result = fvault_get_data(gVaultName, tempfile, temp, 0, timestamp);
#endif

		if ( result ) {
			if ( timestamp > get_systime() - frequency )
				return;
#if defined _nvault_included
			nvault_touch(ghVault, tempfile);
		}
		else
			nvault_set(ghVault, tempfile, "1");
#else
			fvault_touch(gVaultName, tempfile);
		}
		else
			fvault_set_data(gVaultName, tempfile, "1");
#endif
	}

	do
		formatex(tempfile, charsmax(tempfile), "temp%d.amxx", random_num(100000,999999));
	while ( file_exists(tempfile) );
	
	if ( ! gQue_hArray ) {
		gQue_hArray = ArrayCreate(sizeof gQueData, 1);
		register_think("HTTPX_Que", "QueThink");
	}
	
	copy(gQueData[_QueURL], charsmax(gQueData[_QueURL]), TempURL);
	copy(gQueData[_QueFilename], charsmax(gQueData[_QueFilename]), tempfile);
	copy(gQueData[_QueCompleteHandler], charsmax(gQueData[_QueCompleteHandler]), "HTTPX_PluginUpdaterComplete");
	copy(gQueData[_QueProgressHandler], charsmax(gQueData[_QueProgressHandler]), "HTTPX_PluginUpdaterProgress");
	copy(gQueData[_QueUsername], charsmax(gQueData[_QueUsername]), "");
	copy(gQueData[_QuePassword], charsmax(gQueData[_QuePassword]), "");
	
	gQueData[_QueDownloadID] = gDownloadID++;
	gQueData[_QuePort] = 80;
	gQueData[_QueRequestType] = REQUEST_GET;
	gQueData[_QuePluginID] = PluginID;
	
	ArrayPushArray(gQue_hArray, gQueData);
	
	if ( ! gQueEntity ) {
		gQueEntity = create_entity("info_target");
		
		if ( ! gQueEntity ) {
			log_amx("[HTTP:X] Failed to create entity.");
			return;
		}
		
		entity_set_string(gQueEntity, EV_SZ_classname, "HTTPX_Que");
		entity_set_float(gQueEntity, EV_FL_nextthink, get_gametime() + QUE_INTERVAL);
	}
}

public HTTPX_PluginUpdaterProgress(Index) {
	
	if ( ! equal(gDataBuffer, "Plugin failed to compile!", 25) )
		return 0;

	static pluginfile[320];
	new temp[1];
	get_plugin (-1, pluginfile, charsmax(pluginfile), temp, 0, temp, 0, temp, 0, temp, 0);
	log_amx("Error while autoupdating plugin: %s. The plugin could not be compiled.", pluginfile);

	return 1;
}

public HTTPX_PluginUpdaterComplete(Index, Error) {
	
	static pluginfile[320];
	new temp[1], len;
	
	if ( Error ) {
		get_plugin (-1, pluginfile, charsmax(pluginfile), temp, 0, temp, 0, temp, 0, temp, 0);
		log_amx("Error(%d) while autoupdating plugin: %s", pluginfile);
		return;
	}
	
	len = get_localinfo("amxx_pluginsdir", pluginfile, charsmax(pluginfile));
	pluginfile[len++] = '/';
	get_plugin(gInformation[GetDownloadSlot(Index)][_PluginID], pluginfile[len], charsmax(pluginfile) - len, temp, 0, temp, 0, temp, 0, temp, 0);
	
	delete_file(pluginfile);
	rename_file(gInformation[GetDownloadSlot(Index)][_Filename], pluginfile, 1);

	log_amx("Updated plugin %s", pluginfile);
}

HexToDec(string[]) {
	
	new result, mult = 1;
	
	for ( new i = strlen(string) - 1 ; i >= 0 ; i-- ) {
		result += ctod(string[i]) * mult;
		mult *= 16;
	}

	return result;
}

DecToHex(val, out[], len) {
	
	setc(out, len, 0);
	
	for ( new i = len - 1 ; val && i > -1 ; --i, val /= 16 )
		out[len - i - 1] = dtoc(val % 16);
	
	new len2 = strlen(out);
	out[len2] = 0;
	new temp;
	
	for ( new i = 0 ; i < len2 / 2 ; i++ ) {
		temp = out[i];
		out[i] = out[len2 - i - 1];
		out[len2 - i - 1] = temp;
	}
}

Encode64(const InputString[], OutputString[], len) {
	
	new nLength, resPos, nPos, cCode, cFillChar = '=';
	
	for ( nPos = 0, resPos = 0, nLength = strlen(InputString) ; nPos < nLength && resPos < len ; nPos++ ) {
		
		OutputString[resPos++] = Base64Table[(InputString[nPos] >> 2) & 0x3f];
		
		cCode = (InputString[nPos] << 4) & 0x3f;
		if ( ++nPos < nLength )
			cCode |= (InputString[nPos] >> 4) & 0x0f;
		OutputString[resPos++] = Base64Table[cCode];
		
		if ( nPos < nLength ) {
			cCode = (InputString[nPos] << 2) & 0x3f;
			if ( ++nPos < nLength )
				cCode |= (InputString[nPos] >> 6) & 0x03;
			
			OutputString[resPos++] = Base64Table[cCode];
		}
		else {
			nPos++;
			OutputString[resPos++] = cFillChar;
		}
		
		if(nPos < nLength)
			OutputString[resPos++] = Base64Table[InputString[nPos] & 0x3f];
		else
			OutputString[resPos++] = cFillChar;
	}

	OutputString[resPos] = 0;
	OutputString[len] = 0;
}

reverse_string(string[]) {
	
	new temp, len = strlen(string);
	
	for ( new i = 0 ; i < len / 2 ; i++ ) {
		temp = string[i];
		string[i] = string[len - i - 1];
		string[len - i - 1] = temp;
	}
}

large_add(large[], const large_size, const add_what[], const add_size) {
	
	new carry;
	
	for ( new i = 0 ; i < large_size ; i++ ) {
	
		if ( carry ) {
			large[i] += carry;
			carry = large[i] / 10;
			large[i] %= 10;
		}
		
		if ( i < add_size ) {
			large[i] += add_what[i];
			carry += large[i] / 10;
			large[i] %= 10;
		}
	}
}

large_sub(large[], const large_size, const sub_what[], const sub_size) {
	
	new carry;
	
	for ( new i = 0 ; i < large_size ; i++ ) {
		
		if ( i + 1 > large_size ) {
			large[i + 1]--;
			large[i] += 10;
		}
		
		if ( carry ) {
			large[i] += carry;
			carry = large[i] / 10;
			large[i] %= 10;
		}
		
		if ( i < sub_size ) {
			large[i] -= sub_what[i];
			carry += large[i] / 10;
			large[i] %= 10;
		}
	}
}

large_percentage(largepart[], largefull[], sizefull) {

	new val[2], temp = 1;

	for ( new i = sizefull - 1 ; i ; i-- ) {

		if ( largefull[i] ) {

			i = max(i - 2, 0);

			for ( new j = 0 ; j < 3 ; j++, i++ ) {

				val[1] += largefull[i] * temp;
				val[0] += largepart[i] * temp;
				temp *= 10;
			}

			return val[0] * 100 / val[1];
		}
	}
	return 0;
}

large_fromstring(large[], const large_size, string[]) {
	
	arrayset(large, 0, large_size);
	
	new len = strlen(string);
	reverse_string(string);
	
	for ( new i = 0 ; i < large_size && string[i] && i < len ; i++ )
		large[i] = ctod(string[i]);
	
	reverse_string(string);
}

large_tostring(large[], const large_size, string[], const len) {
	
	for ( new i = 0 ; i < large_size && i < len ; i++ )
		string[i] = dtoc(large[i]);
	
	new pos = strlen(string);
	while ( pos > 1 && string[pos - 1] == '0' )
		pos--;
	string[pos] = 0;
	
	reverse_string(string);
}

large_fromint(large[], const large_size, const int) {
	
	arrayset(large, 0, large_size);
	new int2 = int;
	
	for ( new i = 0 ; i < large_size && int2 ; i++ ) {
		large[i] = int2 % 10;
		int2 /= 10;
	}
}

large_toint(large[], large_size) {
	
	new retval, mult = 1;
	
	for ( new i = 0 ; i < large_size ; i++ ) {
		retval += large[i] * mult;
		mult *= 10;
	}
	
	return retval;
}

large_comp(large1[], const large1_size, large2[], const large2_size) {
	new len1 = large1_size;
	new len2 = large2_size;
	
	while ( --len1 > 0 && large1[len1] ) { }
	while ( --len2 > 0 && large2[len2] ) { }
	
	if ( len1 > len2 )
		return 1;
	
	if ( len2 > len1 )
		return -1;
	
	for ( new i = len1 ; i >= 0 ; i-- ) {
	
		if ( large1[i] > large2[i] )
			return 1;
		
		if ( large2[i] > large1[i] )
			return -1;
	}
	
	return 0;
}

public nativeSetupManager(PluginID, NumParams) {
	new Name[32];
	get_plugin(PluginID, _, _, Name, charsmax(Name));

	ManagerHandler[0] = CreateOneForward(PluginID, "ProgressHandler", FP_CELL, FP_CELL);
	ManagerHandler[1] = CreateOneForward(PluginID, "CompleteHandler", FP_CELL, FP_CELL, FP_CELL);

	return MAX_DOWNLOAD_SLOTS;
}