# proxy_check
[AMXX](https://www.amxmodx.org/) script that prevents players from joining a game through proxy/VPN.

## Installation
 - Compile proxy_check.sma locally. There's [plenty](https://forums.alliedmods.net/showthread.php?t=130511) of [guides](https://wiki.alliedmods.net/Compiling_Plugins_%28AMX_Mod_X%29)
 - Download (if you didn't download from this repo already) and install [HTTP:X](https://forums.alliedmods.net/showthread.php?t=282949?t=282949)
 - Add the following lines to _amxmodx/configs/plugins.ini_ in this order:
 ```
 httpx.amxx
 proxy_check.amxx
 ```