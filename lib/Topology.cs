using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace Bnqq {
    public sealed class CoreInfo { public ushort Group; public ulong Mask; public byte EfficiencyClass; }
    public static class Topology {
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern bool GetLogicalProcessorInformationEx(int relation, IntPtr buffer, ref uint length);
        public static CoreInfo[] Read() {
            if(IntPtr.Size != 8) throw new PlatformNotSupportedException("64-bit host required");
            uint length=0;
            GetLogicalProcessorInformationEx(0,IntPtr.Zero,ref length);
            if(length==0 || Marshal.GetLastWin32Error()!=122) throw new Win32Exception();
            IntPtr buffer=Marshal.AllocHGlobal((int)length);
            try {
                if(!GetLogicalProcessorInformationEx(0,buffer,ref length)) throw new Win32Exception();
                List<CoreInfo> cores=new List<CoreInfo>();
                long offset=0;
                while(offset<length) {
                    IntPtr record=new IntPtr(buffer.ToInt64()+offset);
                    int size=Marshal.ReadInt32(record,4);
                    if(size<32 || offset+size>length) throw new InvalidOperationException("Invalid topology record");
                    int relation=Marshal.ReadInt32(record,0);
                    if(relation==0) {
                        ushort count=(ushort)Marshal.ReadInt16(record,30);
                        if(count!=1 || size<48) throw new PlatformNotSupportedException("Multi-group core unsupported; keep scheduler default");
                        CoreInfo core=new CoreInfo();
                        core.Mask=unchecked((ulong)Marshal.ReadInt64(record,32));
                        core.Group=(ushort)Marshal.ReadInt16(record,40);
                        core.EfficiencyClass=Marshal.ReadByte(record,9);
                        if(core.Mask==0) throw new InvalidOperationException("Empty core mask");
                        cores.Add(core);
                    }
                    offset+=size;
                }
                if(cores.Count==0) throw new InvalidOperationException("No measured cores");
                return cores.ToArray();
            } finally {Marshal.FreeHGlobal(buffer);}
        }
    }
}
