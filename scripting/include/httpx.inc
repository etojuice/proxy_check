#if defined _HTTPX_included
	#endinput
#endif
#define _HTTPX_included

enum {
	REQUEST_GET,
	REQUEST_POST
}

/**
 * HTTPX_IsFilesizeLarge(DownloadID)
 *
 * If the filesize in bytes is beyond the limitations of integers the function will return true.
**/
native bool:HTTPX_IsFilesizeLarge(DownloadID)

/**
 * HTTPX_GetBytesReceived(DownloadID)
 *
 * Returns total ammount of bytes received for DownloadID.
**/
native HTTPX_GetBytesReceived(DownloadID)

/**
 * HTTPX_GetBytesReceivedLarge(DownloadID, string[], len)
 *
 * Formats total ammount of bytes received for DownloadID in string form.
**/
native HTTPX_GetBytesReceivedLarge(DownloadID, string[], len)

/**
 * HTTPX_GetNewBytesReceived()
 *
 * Returns the ammount of bytes that was received in this chunk.
**/
native HTTPX_GetNewBytesReceived()

/**
 * HTTPX_GetFilesize(DownloadID)
 *
 * Returns the filesize of DownloadID.
 * If unknown it will return -1.
**/
native HTTPX_GetFilesize(DownloadID)

/**
 * HTTPX_GetFilesizeLarge(DownloadID, string[], len)
 *
 * Formats the large filesize of DownloadID in string form.
**/
native HTTPX_GetFilesizeLarge(DownloadID, string[], len)

/**
 * HTTPX_GetFilename(DownloadID)
 *
 * Returns the filename of DownloadID.
**/
native HTTPX_GetFilename(DownloadID, name[], len)

/**
 * HTTPX_SetCustom(DownloadID, val)
 *
 * Set a custom value to follow along the download, retrievable as long as the download is in progress or on the complete call.
 * If you want to pass more data than an int you could supply a dynamic array index instead.
 *
 * Returns 1 on success, 0 on fail.
**/
native HTTPX_SetCustom(DownloadID, any:val)

/**
 * HTTPX_GetCustom(DownloadID)
 *
 * Returns the previously set value.
 * If the DownloadID is not found it will return -666.
**/
native any:HTTPX_GetCustom(DownloadID)

/**
 * HTTPX_GetData(data[], len)
 *
 * Fills variable data[] with the last chunk downloaded.
 *
 * len decides maxlen for the data[] variable.
 * Remember, this is raw data.
 * No need to make room for null at the end unless you're passing it to any function that is
 * trying to automatically find the end by searching for null (any string function).
 *
 * The function will return the ammount of bytes that was written to the data[] variable.
 *
 * By looping this function until it returns 0, you can get all the data.
**/
native HTTPX_GetData(data[], len)

/**
 * Automatic updating
 * Updates current plugin automatically (from AlliedModders webpage only, to prevent spreading of malicious code).
 *
 *
 * The file ID has to be the same as it is on the forum webpage. (Check the link of the .amxx file ("Get Plugin" link))
 *
 *
 * If frequency is supplied you can set how often to update the file. If none is provided it will update as soon as possible.
 * Please use this respectfully. Don't overload the AM forums.
 *
 * You can however provide your own method of determining whether the file needs to be updated or not before calling this function.
 * That way you don't stress AM servers when not required. An example of this is in the HTTPX source which uses this method.
 *
 * Examples:
 *    1w = 604800
 *   30d = 2592000
 *
 * I recommend using 30 days or more. How often do you update your code? (Honestly)
 * If the time is set too short and/or is abused, I will remove the function completely.
 *
 *
 * IMPORTANT!
 * The reason for this not being a native is that it does not halt the plugin if HTTPX is not running. HTTPX and automatic updating is optional.
 * Use this example. the File ID is the attachment in your post on the AM forums. Only use the ID, not the whole URL.
 * For example:
 *     The plugin Name Replacer by anakin_cstrike, @http://forums.alliedmods.net/showthread.php?t=77401
 *     Scroll down and hover the "Get Plugin", there you see the file ID. Just replace the placeholder with that value.
 *     #define AUTOUPDATE_FILE_ID "76775"
 *     Add the time or create your own method of deciding when it's supposed to be updated and you're done.

#define AUTOUPDATE_FILE_ID "REPLACE_THIS_WITH_YOUR_FILE_ID"
#define AUTOUPDATE_HOW_OFTEN REPLACE_THIS_WITH_DESIRED_FREQUENCY // 1d = 86400, 1w = 604800, 30d = 2592000 (30d is recommended)

UpdatePlugin() {
	new hHTTPX = is_plugin_loaded("HTTP:X");
	if ( hHTTPX ) {
		new filename[16];
		get_plugin(hHTTPX, filename, charsmax(filename));
		if ( callfunc_begin("AutoupdatePlugin", filename) == 1 ) {
			callfunc_push_int(get_plugin(-1));
			callfunc_push_str(AUTOUPDATE_FILE_ID, false);
			callfunc_push_int(AUTOUPDATE_HOW_OFTEN);
			callfunc_end();
		}
	}
}

**/

/**
 * HTTPX_Abort(DownloadID, bool:DeleteFile = true)
 *
 * Aborts the transfer of selected download DownloadID.
 * If DeleteFile is set to true the partially downloaded file will be deleted.
**/
native HTTPX_Abort(DownloadID, bool:DeleteFile = true)

/**
 * HTTPX_AddPostVar(const variable[], const value[])
 *
 * Adds a POST variable to the request.
 * This function is used before HTTPX_Download() or HTTP_AddToQue(), similar to set/show hudmessage.
 * It can be used multiple times before each download.
**/
native HTTPX_AddPostVar(const variable[], const value[])

/**
 * HTTPX_AddPostRaw(const data[])
 *
 * Adds raw POST data to the request.
 * This function is used before HTTPX_Download() or HTTP_AddToQue(), similar to set/show hudmessage.
 * It can be used multiple times before each download.
**/
native HTTPX_AddPostRaw(const data[])

/**
 * Number of parameters for the callbacks are 1 (DownloadID) for the progress event and 2 (DownloadID, Error) for the complete event.
 * Error codes:
 *     0   Download done. No problems encountered.
 * Positive returns is unhandled HTTP return codes. For example 404.
 * Negative is internal errors.
 *    -1   No response code was found in the HTTP response header or it was outside the accepted range (200-307).
 *    -2   Server is sending bad data or sizes for a chunked transfer or HTTPX has problems reading them.
 *    -3   Nothing received in last packet. Most likely due to an error.
 *    -4   HTTPX was redirected but could not follow due to a socket error.
 *    -5   HTTPX was redirected too many times. Usually happens when server is insisting on a SSL/TLS connection which HTTPX does not support.
**/

/**
 * HTTPX_Download(const URL[], const Filename[] = "", const CompleteHandler[] = "", const ProgressHandler[] = "", Port = (80<<443), RequestType = REQUEST_GET, const Username[] = "", const Password[] = "", ...)
 *
 * Begins download of a URL. Read parameters for information.
 *
 *
 * Parameters:
 *
 *   const URL[]
 *      URL that you want to download.
 *
 *   (Optional) const Filename[]
 *      Where should the information be stored? If no filename is entered it will download as a "stream".
 *      This means the data will be thrown away after it passes the buffer.
 *      You can read the data on progress forward and make use of it there.
 *
 *   (Optional) const CompleteHandler[] = ""
 *      The function you want called when the download is complete.
 *
 *   (Optional) const ProgressHandler[] = ""
 *      The function you want called when the download is in progress.
 *      This will be called every time data is downloaded.
 *
 *   (Optional) Port = 0
 *      The port that should be used.
 *      If this is left at default it will use 80 for http and 443 for https (when supported).
 *
 *   (Optional) RequestType = REQUEST_GET
 *      What type of request should be used.
 *      If this is left at default it will use GET.
 *      Possible values so far are REQUEST_GET and REQUEST_POST.
 *
 *   (Optional) const Username[] = ""
 *   (Optional) const Password[] = ""
 *      These are used to login to sites that require you to.
 *      It's only used for Basic authentication, not POST for example.
 *
 * Returns an DownloadID of the download that may be used to abort the download.
**/
native HTTPX_Download(const URL[], const Filename[] = "", const CompleteHandler[] = "", const ProgressHandler[] = "", Port = 0, RequestType = REQUEST_GET, const Username[] = "", const Password[] = "", ... /* For possible future use */)
