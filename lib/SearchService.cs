using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
namespace Bnqq {
    // ControlService refuses active dependents (1051); unlike ServiceController.Stop,
    // it does NOT recursively stop other services. Only the indexer is addressable.
    public static class SearchService {
        [StructLayout(LayoutKind.Sequential)] private struct Status {
            public uint Type, State, Accepted, ExitCode, SpecificExit, Checkpoint, WaitHint;
        }
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern IntPtr OpenSCManager(string machine,string database,uint access);
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern IntPtr OpenService(IntPtr manager,string name,uint access);
        [DllImport("advapi32.dll", SetLastError=true)] private static extern bool QueryServiceStatus(IntPtr service,out Status status);
        [DllImport("advapi32.dll", SetLastError=true)] private static extern bool ControlService(IntPtr service,uint control,out Status status);
        [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] private static extern bool StartService(IntPtr service,uint argc,IntPtr argv);
        [DllImport("advapi32.dll")] private static extern bool CloseServiceHandle(IntPtr handle);
        private static Status Read(IntPtr h) {Status s;if(!QueryServiceStatus(h,out s))throw new Win32Exception();return s;}
        public static uint State() {return Access(false,null);}
        public static void SetRunning(bool running) {Access(true,running);}
        private static uint Access(bool write,bool? running) {
            IntPtr manager=OpenSCManager(null,null,1),service=IntPtr.Zero;
            if(manager==IntPtr.Zero)throw new Win32Exception();
            try {
                service=OpenService(manager,"WSearch",4u | (write ? (running.Value?16u:32u):0u));
                if(service==IntPtr.Zero)throw new Win32Exception();
                Status s=Read(service);if(!write)return s.State;
                uint target=running.Value?4u:1u;
                // Pending writes after a timeout are reconciled before requesting another transition.
                Stopwatch timer=Stopwatch.StartNew();
                while(s.State==2 || s.State==3) {if(timer.Elapsed.TotalSeconds>15)throw new TimeoutException("WSearch pending transition");Thread.Sleep(100);s=Read(service);}
                if(s.State==target)return s.State;
                if(s.State!=1 && s.State!=4)throw new InvalidOperationException("WSearch state not admitted");
                if(running.Value){if(!StartService(service,0,IntPtr.Zero))throw new Win32Exception();}
                else {if(!ControlService(service,1,out s))throw new Win32Exception();}
                timer.Restart();
                do {s=Read(service);if(s.State==target)return s.State;if(timer.Elapsed.TotalSeconds>15)throw new TimeoutException("WSearch transition not verified");Thread.Sleep(100);}while(true);
            } finally {if(service!=IntPtr.Zero)CloseServiceHandle(service);CloseServiceHandle(manager);}
        }
    }
}
