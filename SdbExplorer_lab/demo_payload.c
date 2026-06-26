/*
 * demo_payload.c  —  SdbExplorer Lab  |  Benign demonstration DLL
 *
 * This DLL is the lab's "malicious" payload — but it does nothing harmful.
 * When injected into notepad.exe via the Application Shimming mechanism,
 * it performs two visible actions to prove the injection occurred:
 *
 *   1. Creates a log file at C:\Windows\Temp\shimmed.log
 *   2. Shows a Windows message box
 *
 * These artifacts are what the Blue Team investigates in the detection phase.
 *
 * Compile on Ubuntu (32-bit, for SysWOW64\notepad.exe):
 *   sudo apt-get install -y mingw-w64
 *   i686-w64-mingw32-gcc -shared -o demo.dll demo_payload.c -luser32 -lkernel32
 *
 * The resulting demo.dll must be placed in ~/BnB/SdbExplorer/
 * so the Python web server can serve it to the Windows VM.
 */

#include <windows.h>

/* Path where the DLL writes its execution log on the Windows VM. */
#define LOG_PATH   "C:\\Windows\\Temp\\shimmed.log"
#define LOG_MSG    "[SdbExplorer Lab] demo.dll injected into this process via Application Shimming.\r\n"

#define POPUP_TITLE "SdbExplorer Lab \x2014 Shim Active"
#define POPUP_MSG   "Application Shimming Demo\n\n" \
                    "This message box was triggered by demo.dll,\n" \
                    "which was injected into Notepad by the\n" \
                    "custom Shim Database (patch.sdb).\n\n" \
                    "Open Task Manager to see demo.dll loaded\n" \
                    "in the Notepad process before clicking OK."

static void write_log(void)
{
    HANDLE hFile = CreateFileA(
        LOG_PATH,
        GENERIC_WRITE,
        FILE_SHARE_READ,
        NULL,
        OPEN_ALWAYS,
        FILE_ATTRIBUTE_NORMAL,
        NULL
    );

    if (hFile == INVALID_HANDLE_VALUE) return;

    SetFilePointer(hFile, 0, NULL, FILE_END);

    DWORD written;
    WriteFile(hFile, LOG_MSG, (DWORD)(sizeof(LOG_MSG) - 1), &written, NULL);
    CloseHandle(hFile);
}

BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpvReserved)
{
    switch (fdwReason)
    {
        case DLL_PROCESS_ATTACH:
            DisableThreadLibraryCalls(hinstDLL);
            write_log();
            MessageBoxA(
                NULL,
                POPUP_MSG,
                POPUP_TITLE,
                MB_OK | MB_ICONWARNING | MB_SETFOREGROUND
            );
            break;

        case DLL_PROCESS_DETACH:
        case DLL_THREAD_ATTACH:
        case DLL_THREAD_DETACH:
            break;
    }
    return TRUE;
}
