#include <amxmodx>
#include <grip>
#include <nvault>

#pragma semicolon 1

#if !defined _grip_included
    #assert "gRIP module is required! https://dev-cs.ru/resources/650/"
#endif

new g_szDataDir[PLATFORM_MAX_PATH];
new g_hVault = INVALID_HANDLE;

public plugin_init() {
    register_plugin("Proxy Check", "2.1", "juice, voed");
   
    if ((g_hVault = nvault_open("proxycheck")) == INVALID_HANDLE) {
        set_fail_state("nvault Error: Vault wasn't opened!");
        return;
    }
   
    get_localinfo("amxx_datadir", g_szDataDir, charsmax(g_szDataDir));
    add(g_szDataDir, charsmax(g_szDataDir), "/proxycheck");
   
    if (!dir_exists(g_szDataDir)) {
        mkdir(g_szDataDir);
    }
}

public client_putinserver(id) {
    if (is_user_bot(id) || is_user_hltv(id)) {
        return;
    }
   
    new netAddress[MAX_IP_LENGTH];
    get_user_ip(id, netAddress, charsmax(netAddress), 1);

    if (netAddress[0] == 'l') {
        return;
    } else {
        new buf[sizeof netAddress];

        copy(buf, charsmax(buf), netAddress);
        replace_all(buf, charsmax(buf), ".", " ");
       
        new octets[4][4];
        parse(buf, octets[0], charsmax(octets[]),
            octets[1], charsmax(octets[]),
            octets[2], charsmax(octets[]),
            octets[3], charsmax(octets[]));
               
        new address = (str_to_num(octets[0]) << 24) |
            (str_to_num(octets[1]) << 16) |
            (str_to_num(octets[2]) << 8) |
            (str_to_num(octets[3]));
       
        // Ignore private IPv4 address spaces
        if ((address & 0xFF000000) == 0x0A000000 ||    //10.0.0.0/8
        (address & 0xFFF00000) == 0xAC100000 ||       //172.16.0.0/12
        (address & 0xFFFF0000) == 0xC0A80000 ||       //192.168.0.0/16
        (address & 0xFF000000) == 0x7F000000)         //127.0.0.0/8
        {
            return;
        }
    }

    new data = nvault_get(g_hVault, netAddress);

    if (data) {
        if (data == 1) {
            punish_player(id);
        }

        return;
    }

    new szFile[PLATFORM_MAX_PATH];
    formatex(szFile, charsmax(szFile), "%s/check_%s.txt", g_szDataDir, netAddress);

    if (!file_exists(szFile)) {
        new szRequest[68];

        formatex(szRequest, charsmax(szRequest), "https://ip.teoh.io/api/vpn/%s", netAddress);
        grip_request(szRequest, Empty_GripBody, GripRequestTypeGet, "HandleRequest");
    }
}

public HandleRequest() {
    new GripResponseState:responseState = grip_get_response_state();

    if (responseState == GripResponseStateError) {
        return;
    }

    new GripHTTPStatus:status = grip_get_response_status_code();

    if (status != GripHTTPStatusOk) {
        return;
    }

    new response[512];
    grip_get_response_body_string(response, charsmax(response));

    new GripJSONValue:data = grip_json_parse_response_body(response, charsmax(response));

    if (data == Invalid_GripJSONValue) {
        return;
    }

    new netAddress[MAX_IP_LENGTH];
    
    grip_json_get_string(grip_json_object_get_value(data, "ip"), netAddress, MAX_IP_LENGTH);
    grip_json_get_string(grip_json_object_get_value(data, "vpn_or_proxy"), response, charsmax(response));

    if (equal(response, "yes")) {
        nvault_set(g_hVault, netAddress, "1");
        punish_player(find_player("d", netAddress));
    } else {
        nvault_set(g_hVault, netAddress, "2");
    }
        
    grip_destroy_json_value(data);
}

punish_player(id) {
    if(!is_user_connected(id)) {
        return;
    }
    
    server_cmd("kick #%d ^"Proxy/VPN not Allowed!^"", get_user_userid(id));
}