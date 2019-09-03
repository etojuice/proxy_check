// This plugin requires gRIP module https://dev-cs.ru/resources/650/
#include <amxmodx>
#include <grip>
#include <nvault>


#if !defined PLATFORM_MAX_PATH
    #define PLATFORM_MAX_PATH 256
#endif

#if !defined MAX_IP_LENGTH
    #define MAX_IP_LENGTH 16
#endif

new g_szDataDir[PLATFORM_MAX_PATH];
new g_hVault = INVALID_HANDLE;


public plugin_init()
{
    register_plugin("Proxy Check GRIP", "2.0-grip", "juice/voed")
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
   
    new szIP[MAX_IP_LENGTH];
    get_user_ip(id, szIP, charsmax(szIP), .without_port = 1);

    if(equal(szIP, "loopback")) {
        return;
    }
    else {
        new szIPcopy[MAX_IP_LENGTH];
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
        if((address & 0xFF000000) == 0x0A000000 ||    //10.0.0.0/8
        (address & 0xFFF00000) == 0xAC100000 ||       //172.16.0.0/12
        (address & 0xFFFF0000) == 0xC0A80000 ||       //192.168.0.0/16
        (address & 0xFF000000) == 0x7F000000)         //127.0.0.0/8
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
        formatex(szRequest, charsmax(szRequest), "https://ip.teoh.io/api/vpn/%s", szIP);
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

    if(data == Invalid_GripJSONValue) {
      return;
    }

    new szIP[MAX_IP_LENGTH];
    grip_json_get_string(grip_json_object_get_value(data, "ip"), szIP, MAX_IP_LENGTH);

    grip_json_get_string(grip_json_object_get_value(data, "vpn_or_proxy"), response, charsmax(response));
    if(equal(response, "yes"))
    {
        nvault_set(g_hVault, szIP, "1");
        new id = find_player("d", szIP);
        if(id)
            punish_player(id);

    }
    else
    {
        nvault_set(g_hVault, szIP, "2");
    }
        
    grip_destroy_json_value(data);
}

punish_player(id) {
    server_cmd("kick #%d ^"Proxy/VPN not Allowed!^"", get_user_userid(id));
}