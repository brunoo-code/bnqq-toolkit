using System;
using System.Collections.Generic;
using System.Management;
using System.Runtime.InteropServices;
using System.Threading;

public static class BnqqProcessLasso
{
    private const uint PROCESS_SET_INFORMATION = 0x0200;
    private const uint PROCESS_QUERY_INFORMATION = 0x0400;
    private const uint PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    private const uint IDLE_PRIORITY_CLASS = 0x00000040;
    private const uint PROCESS_MODE_BACKGROUND_BEGIN = 0x00100000;
    private const uint PROCESS_MODE_BACKGROUND_END = 0x00200000;
    private const int ProcessMemoryPriority = 39;
    private const int ProcessIoPriority = 33;

    [StructLayout(LayoutKind.Sequential)]
    private struct MEMORY_PRIORITY_INFORMATION
    {
        public uint MemoryPriority;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(uint access, bool inheritHandle, int processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint GetPriorityClass(IntPtr process);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetPriorityClass(IntPtr process, uint priorityClass);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetProcessAffinityMask(IntPtr process, out UIntPtr processMask, out UIntPtr systemMask);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetProcessAffinityMask(IntPtr process, UIntPtr processMask);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetProcessInformation(IntPtr process, int informationClass, ref MEMORY_PRIORITY_INFORMATION information, int informationLength);

    [DllImport("ntdll.dll")]
    private static extern int NtSetInformationProcess(IntPtr process, int informationClass, ref int information, int informationLength);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

    private sealed class ProcessState
    {
        public uint PriorityClass;
        public ulong AffinityMask;
        public bool BackgroundMode;
        public bool ExplicitIoMemory;
    }

    private static readonly object Sync = new object();
    private static readonly Dictionary<int, ProcessState> Tracked = new Dictionary<int, ProcessState>();
    private static readonly HashSet<string> Protected = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
    private static ManagementEventWatcher _watcher;
    private static volatile bool _running;
    private static int _gamePid;
    private static ulong _backgroundMask = 0xAAAA;
    private static long _actions;
    private static string _lastError = "";
    private static string _lastProcess = "";
    private static DateTime _startedAt;

    public static bool Start(int gamePid, ulong backgroundMask, string[] protectedNames)
    {
        Stop();

        lock (Sync)
        {
            Protected.Clear();
            if (protectedNames != null)
            {
                for (int i = 0; i < protectedNames.Length; i++)
                {
                    string name = Normalize(protectedNames[i]);
                    if (!string.IsNullOrEmpty(name)) Protected.Add(name);
                }
            }
            Tracked.Clear();
            _gamePid = gamePid;
            _backgroundMask = backgroundMask == 0 ? 0xAAAAUL : backgroundMask;
            _actions = 0;
            _lastError = "";
            _lastProcess = "";
            _startedAt = DateTime.UtcNow;
            _running = true;
        }

        try
        {
            ManagementScope scope = new ManagementScope("\\\\.\\root\\cimv2");
            scope.Connect();
            WqlEventQuery query = new WqlEventQuery("SELECT * FROM Win32_ProcessStartTrace");
            ManagementEventWatcher watcher = new ManagementEventWatcher(scope, query);
            watcher.EventArrived += OnProcessStarted;
            watcher.Start();
            lock (Sync) { _watcher = watcher; }
            return true;
        }
        catch (Exception ex)
        {
            lock (Sync)
            {
                _running = false;
                _lastError = ex.Message;
            }
            return false;
        }
    }

    public static void Stop()
    {
        ManagementEventWatcher watcher;
        lock (Sync)
        {
            _running = false;
            watcher = _watcher;
            _watcher = null;
        }

        if (watcher != null)
        {
            try { watcher.Stop(); } catch { }
            try { watcher.Dispose(); } catch { }
        }

        RestoreAll();
    }

    public static string Status()
    {
        lock (Sync)
        {
            return string.Format(
                "running={0};tracked={1};actions={2};game_pid={3};mask=0x{4:X};last={5};error={6};uptime_s={7}",
                _running ? 1 : 0,
                Tracked.Count,
                _actions,
                _gamePid,
                _backgroundMask,
                _lastProcess,
                _lastError,
                _running ? (int)(DateTime.UtcNow - _startedAt).TotalSeconds : 0);
        }
    }

    public static int ApplyTo(int processId, string processName)
    {
        if (!_running || processId <= 0 || processId == _gamePid) return 0;
        if (IsProtected(processName)) return 0;
        if (!GameIsForeground()) return 0;

        IntPtr handle = OpenProcess(PROCESS_SET_INFORMATION | PROCESS_QUERY_INFORMATION | PROCESS_QUERY_LIMITED_INFORMATION, false, processId);
        if (handle == IntPtr.Zero) return 0;

        try
        {
            uint originalPriority = GetPriorityClass(handle);
            UIntPtr processMask;
            UIntPtr systemMask;
            ulong originalAffinity = 0;
            GetProcessAffinityMask(handle, out processMask, out systemMask);
            originalAffinity = processMask.ToUInt64();

            bool background = SetPriorityClass(handle, PROCESS_MODE_BACKGROUND_BEGIN);
            bool idle = SetPriorityClass(handle, IDLE_PRIORITY_CLASS);
            bool affinity = SetProcessAffinityMask(handle, new UIntPtr(_backgroundMask));
            bool explicitIoMemory = false;

            if (!background)
            {
                MEMORY_PRIORITY_INFORMATION memory = new MEMORY_PRIORITY_INFORMATION();
                memory.MemoryPriority = 1;
                explicitIoMemory = SetProcessInformation(handle, ProcessMemoryPriority, ref memory, Marshal.SizeOf(typeof(MEMORY_PRIORITY_INFORMATION)));
                int ioPriority = 0;
                if (NtSetInformationProcess(handle, ProcessIoPriority, ref ioPriority, sizeof(int)) != 0) explicitIoMemory = false;
            }

            if (!idle && !background && !affinity) return 0;

            lock (Sync)
            {
                if (_running)
                {
                    ProcessState state = new ProcessState();
                    state.PriorityClass = originalPriority;
                    state.AffinityMask = originalAffinity;
                    state.BackgroundMode = background;
                    state.ExplicitIoMemory = explicitIoMemory;
                    Tracked[processId] = state;
                    _actions++;
                    _lastProcess = processName + " (" + processId + ")";
                }
            }
            return 1;
        }
        catch (Exception ex)
        {
            lock (Sync) { _lastError = ex.Message; }
            return 0;
        }
        finally
        {
            CloseHandle(handle);
        }
    }

    private static void OnProcessStarted(object sender, EventArrivedEventArgs e)
    {
        if (!_running) return;
        try
        {
            int processId = Convert.ToInt32(e.NewEvent["ProcessID"]);
            string processName = Convert.ToString(e.NewEvent["ProcessName"]);
            ThreadPool.QueueUserWorkItem(delegate(object state)
            {
                ApplyTo(processId, processName);
            });
        }
        catch (Exception ex)
        {
            lock (Sync) { _lastError = ex.Message; }
        }
    }

    private static void RestoreAll()
    {
        KeyValuePair<int, ProcessState>[] snapshot;
        lock (Sync)
        {
            snapshot = new KeyValuePair<int, ProcessState>[Tracked.Count];
            int i = 0;
            foreach (KeyValuePair<int, ProcessState> pair in Tracked) snapshot[i++] = pair;
            Tracked.Clear();
        }

        for (int i = 0; i < snapshot.Length; i++)
        {
            int processId = snapshot[i].Key;
            ProcessState state = snapshot[i].Value;
            IntPtr handle = OpenProcess(PROCESS_SET_INFORMATION | PROCESS_QUERY_LIMITED_INFORMATION, false, processId);
            if (handle == IntPtr.Zero) continue;
            try
            {
                if (state.BackgroundMode) SetPriorityClass(handle, PROCESS_MODE_BACKGROUND_END);
                if (state.PriorityClass != 0) SetPriorityClass(handle, state.PriorityClass);
                if (state.AffinityMask != 0) SetProcessAffinityMask(handle, new UIntPtr(state.AffinityMask));
                if (state.ExplicitIoMemory)
                {
                    MEMORY_PRIORITY_INFORMATION memory = new MEMORY_PRIORITY_INFORMATION();
                    memory.MemoryPriority = 5;
                    SetProcessInformation(handle, ProcessMemoryPriority, ref memory, Marshal.SizeOf(typeof(MEMORY_PRIORITY_INFORMATION)));
                    int ioPriority = 2;
                    NtSetInformationProcess(handle, ProcessIoPriority, ref ioPriority, sizeof(int));
                }
            }
            catch { }
            finally { CloseHandle(handle); }
        }
    }

    private static bool GameIsForeground()
    {
        IntPtr window = GetForegroundWindow();
        if (window == IntPtr.Zero) return false;
        uint pid;
        GetWindowThreadProcessId(window, out pid);
        return (int)pid == _gamePid;
    }

    private static bool IsProtected(string processName)
    {
        string name = Normalize(processName);
        if (string.IsNullOrEmpty(name)) return true;
        lock (Sync) { return Protected.Contains(name); }
    }

    private static string Normalize(string processName)
    {
        if (string.IsNullOrEmpty(processName)) return "";
        string name = processName.Trim();
        int slash = name.LastIndexOf('\\');
        if (slash >= 0) name = name.Substring(slash + 1);
        if (name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) name = name.Substring(0, name.Length - 4);
        return name.ToLowerInvariant();
    }
}
