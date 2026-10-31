using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace Bnqq {
 public sealed class CpuSetInfo {
  public uint Id; public ushort Group; public byte Logical, Core, Cache, Efficiency, Flags;
 }
 public static class CpuSets {
  [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
  public static string OwnerSid(IntPtr process) {
   IntPtr token;
   if(!OpenProcessToken(process,8,out token))throw new Win32Exception();
   try{using(var identity=new System.Security.Principal.WindowsIdentity(token)){return identity.User.Value;}}
   finally{CloseHandle(token);}
  }
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetSystemCpuSetInformation(IntPtr p,uint n,out uint needed,IntPtr process,uint flags);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetProcessDefaultCpuSets(IntPtr process,[Out] uint[] ids,uint count,out uint needed);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetProcessDefaultCpuSets(IntPtr process,uint[] ids,uint count);
  public static CpuSetInfo[] Enumerate() {
   uint n; bool ok=GetSystemCpuSetInformation(IntPtr.Zero,0,out n,IntPtr.Zero,0);
   if(!ok && Marshal.GetLastWin32Error()!=122) throw new Win32Exception();
   for(int attempt=0;attempt<3;attempt++) {
    if(n==0 || n>1048576) throw new InvalidOperationException("Invalid CPU Set buffer size");
    uint capacity=n; IntPtr p=Marshal.AllocHGlobal((int)n);
    try {
     if(!GetSystemCpuSetInformation(p,capacity,out n,IntPtr.Zero,0)) {
      if(Marshal.GetLastWin32Error()==122) continue; throw new Win32Exception();
     }
     if(n>capacity) throw new InvalidOperationException("CPU Set buffer overflow");
     var rows=new List<CpuSetInfo>(); int pos=0;
     while(pos<(int)n) {
      if((int)n-pos<8) throw new InvalidOperationException("Truncated CPU Set header");
      IntPtr r=IntPtr.Add(p,pos); uint size=(uint)Marshal.ReadInt32(r);
      if(size<8 || size>n-(uint)pos) throw new InvalidOperationException("Invalid CPU Set record");
      if(Marshal.ReadInt32(r,4)==0) {
       if(size<32) throw new InvalidOperationException("Truncated CPU Set record");
       rows.Add(new CpuSetInfo { Id=(uint)Marshal.ReadInt32(r,8),Group=(ushort)Marshal.ReadInt16(r,12),Logical=Marshal.ReadByte(r,14),Core=Marshal.ReadByte(r,15),Cache=Marshal.ReadByte(r,16),Efficiency=Marshal.ReadByte(r,18),Flags=Marshal.ReadByte(r,19) });
      }
      pos+=(int)size;
     }
     if(rows.Count>4096) throw new InvalidOperationException("Too many CPU Sets");
     return rows.ToArray();
    } finally { Marshal.FreeHGlobal(p); }
   }
   throw new InvalidOperationException("CPU Set topology changed repeatedly");
  }
  public static uint[] Read(IntPtr handle) {
   uint n; bool ok=GetProcessDefaultCpuSets(handle,null,0,out n);
   if(!ok && Marshal.GetLastWin32Error()!=122) throw new Win32Exception();
   for(int attempt=0;attempt<3;attempt++) {
    if(n>256) throw new InvalidOperationException("CPU Set assignment exceeds supported limit");
    if(n==0) return new uint[0];
    var ids=new uint[n];
    if(GetProcessDefaultCpuSets(handle,ids,(uint)ids.Length,out n)) {
     if(n>ids.Length) throw new InvalidOperationException("CPU Set assignment overflow");
     Array.Resize(ref ids,(int)n); Array.Sort(ids); return ids;
    }
    if(Marshal.GetLastWin32Error()!=122) throw new Win32Exception();
   }
   throw new InvalidOperationException("CPU Set assignment changed repeatedly");
  }
  public static void Write(IntPtr handle,uint[] ids) {
   if(ids==null || ids.Length>256) throw new ArgumentException("Invalid CPU Set assignment");
   if(!SetProcessDefaultCpuSets(handle,ids.Length==0?null:ids,(uint)ids.Length)) throw new Win32Exception();
  }
 }
}
