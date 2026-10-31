using System;
using System.Collections.Generic;
using System.Management;
using System.Threading;

// Bounded WMI observer. No memory, I/O, background-mode or affinity mutations.
// Process scheduling experiments are owned exclusively by the journalled watcher.
public static class BnqqProcessLasso {
    public const int MaxPendingEvents=64;
    public const int MaxTrackedProcesses=512;
    private static readonly object Sync=new object();
    private static readonly Queue<int> Pending=new Queue<int>();
    private static readonly Dictionary<int,string> Tracked=new Dictionary<int,string>();
    private static ManagementEventWatcher watcher;
    private static bool running;
    private static long dropped;
    private static long seen;
    public static bool Start() {
        lock(Sync) {
            if(running) return true;
            Pending.Clear();Tracked.Clear();dropped=0;seen=0;
            ManagementEventWatcher next=new ManagementEventWatcher(new WqlEventQuery("SELECT * FROM Win32_ProcessStartTrace"));
            next.EventArrived+=OnStart;
            running=true;watcher=next;
            try {next.Start();return true;}
            catch {running=false;watcher=null;next.Dispose();throw;}
        }
    }
    private static void OnStart(object sender,EventArrivedEventArgs e) {
        lock(Sync) {
            // Queued callbacks from an old subscription may not enter a new session.
            if(!running || !Object.ReferenceEquals(sender,watcher)) return;
            EnqueueLocked(Convert.ToInt32(e.NewEvent["ProcessID"]),Convert.ToString(e.NewEvent["ProcessName"]));
        }
    }
    private static bool EnqueueLocked(int pid,string name) {
        if(Pending.Count>=MaxPendingEvents || (!Tracked.ContainsKey(pid) && Tracked.Count>=MaxTrackedProcesses)) {
            Interlocked.Increment(ref dropped);return false;
        }
        Pending.Enqueue(pid);Tracked[pid]=name;Interlocked.Increment(ref seen);return true;
    }
    public static int Drain() {
        lock(Sync) {
            int n=Pending.Count;
            Pending.Clear();Tracked.Clear();return n;
        }
    }
    public static long[] Counters() {
        lock(Sync){return new long[]{Pending.Count,Tracked.Count,Interlocked.Read(ref seen),Interlocked.Read(ref dropped)};}
    }
    public static void Stop() {
        ManagementEventWatcher old;
        lock(Sync){running=false;old=watcher;watcher=null;}
        // Never stop WMI while holding the callback lock.
        if(old!=null){try{old.Stop();}finally{old.Dispose();}}
        lock(Sync){Pending.Clear();Tracked.Clear();}
    }
    // Deterministic concurrency test of the exact bounded enqueue path; no WMI/process mutations.
    public static void TestEnqueue(int pid) {lock(Sync){EnqueueLocked(pid,"fixture");}}
}
