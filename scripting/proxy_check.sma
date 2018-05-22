/*
	Download HTTP:X from: https://forums.alliedmods.net/showthread.php?t=282949
	This plugin is using http://proxy.mind-media.com/block/ service
*/

#include <amxmodx>
#include <nvault>
#include <httpx>

//#define USE_ADDIP_CMD

#define IP_LENGTH 16

#if !defined PLATFORM_MAX_PATH
	#define PLATFORM_MAX_PATH 256
#endif

new g_szDataDir[PLATFORM_MAX_PATH];
new g_hVault = INVALID_HANDLE;

public plugin_init() {
	register_plugin("Proxy/VPN check", "1.1", "juice");
}

public plugin_cfg() {
	g_hVault = nvault_open("proxycheck");
	
	if(g_hVault == INVALID_HANDLE) {
		set_fail_state("Error opening nVault!");
		return;
	}
	
	get_localinfo("amxx_datadir", g_szDataDir, charsmax(g_szDataDir));
	add(g_szDataDir, charsmax(g_szDataDir), "/proxycheck");
	
	if(!dir_exists(g_szDataDir)) {
		mkdir(g_szDataDir);
	}
}

public client_putinserver(id) {
	if(is_user_bot(id) || is_user_hltv(id)) {
		return;
	}
	
	new szIP[IP_LENGTH];
	get_user_ip(id, szIP, charsmax(szIP), .without_port = 1);

	if(equal(szIP, "loopback")) {
		return;
	}
	else {
		new szIPcopy[IP_LENGTH];
		copy(szIPcopy, charsmax(szIPcopy), szIP);
		replace_all(szIPcopy, charsmax(szIPcopy), ".", " ");
		
		new szFields[4][4];
		parse(szIPcopy, szFields[0], charsmax(szFields[]),
			szFields[1], charsmax(szFields[]),
			szFields[2], charsmax(szFields[]),
			szFields[3], charsmax(szFields[]));
				
		new address = (str_to_num(szFields[0]) << 24) |
			(str_to_num(szFields[1]) << 16) |
			(str_to_num(szFields[2]) << 8) |
			(str_to_num(szFields[3]));
		
		// Ignore private IPv4 address spaces
		if((address & 0xFF000000) == 0x0A000000 ||	//10.0.0.0/8
		(address & 0xFFF00000) == 0xAC100000 ||		//172.16.0.0/12
		(address & 0xFFFF0000) == 0xC0A80000)		//192.168.0.0/16 
		{
			return;
		}
	}
	
	new data = nvault_get(g_hVault, szIP);

	if(data) {
		if(data == 1) {
			punish_player(id);
		}
		return;
	}
	
	new szFile[PLATFORM_MAX_PATH];
	formatex(szFile, charsmax(szFile), "%s/check_%s.txt", g_szDataDir, szIP);
	
	if(!file_exists(szFile)) {
		new szRequest[68];
		formatex(szRequest, charsmax(szRequest), "http://proxy.mind-media.com/block/proxycheck.php?ip=%s", szIP);
		HTTPX_Download(szRequest, szFile, "DownloadComplete", _, _, REQUEST_GET);
	}
}

public DownloadComplete(const download, const error) {
	new szFile[PLATFORM_MAX_PATH];
	HTTPX_GetFilename(download, szFile, charsmax(szFile));
	
	if(!error) {
		new file = fopen(szFile, "r");

		if(file) {
			new data[2];
			fgets(file, data, charsmax(data));
			
			if(data[0] == 'Y' || data[0] == 'N') {
				new pos_start = strfind(szFile, "check_", false, strlen(g_szDataDir));
				new pos_end = (pos_start == -1) ? -1 : strfind(szFile, ".txt", false, (pos_start += 6));
				
				if(pos_end != -1) {
					new szIP[IP_LENGTH];
					add(szIP, charsmax(szIP), szFile[pos_start], pos_end - pos_start);
					
					if(data[0] == 'Y') {
						new id = find_player("d", szIP);

						if(id) {
							punish_player(id);
						}

						nvault_set(g_hVault, szIP, "1");
					#if defined USE_ADDIP_CMD
						server_cmd("addip 0 %s;wait;writeip", szIP);
					#endif
					}
					else {
						nvault_set(g_hVault, szIP, "2");
					}	
				}
			}
			fclose(file);
		}
	}
	delete_file(szFile);
}

punish_player(id) {
	server_cmd("kick #%d ^"Proxy/VPN not Allowed!^"", get_user_userid(id));
}