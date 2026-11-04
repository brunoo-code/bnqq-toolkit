using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace Bnqq {
 public static class CleanupFilesV1 {
  [StructLayout(LayoutKind.Sequential)] struct FT {public uint Low,High;}
  [StructLayout(LayoutKind.Sequential)] struct Info {public uint Attributes;public FT Created,Accessed,Written;public uint Volume,SizeHigh,SizeLow,Links,IndexHigh,IndexLow;}
  [StructLayout(LayoutKind.Sequential)] struct Disposition {public int Delete;}
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern SafeFileHandle CreateFileW(string path,uint access,uint share,IntPtr security,uint creation,uint flags,IntPtr template);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle file,out Info info);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFinalPathNameByHandleW(SafeFileHandle file,StringBuilder path,uint count,uint flags);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetFileInformationByHandle(SafeFileHandle file,int kind,ref Disposition info,uint size);
  static long Ticks(FT t){return DateTime.FromFileTimeUtc((long)(((ulong)t.High<<32)|t.Low)).Ticks;}
  public static bool Protected(string relative) {
   foreach(string part in relative.Split('\\')) {
    string p=part.ToLowerInvariant();
    foreach(string word in new string[]{"cache","shader","riot","valorant","vanguard","steam","bnqq","codex","office","outlook","unsaved","recovery"})if(p.Contains(word))return true;
    if(p.EndsWith(".dmp")||p.EndsWith(".hdmp"))return true;
   }
   return false;
  }
  // Open exclusively, verify the actual handle target and snapshot, then delete that handle.
  // No pathname delete after releasing the verification handle; no recursion or forced unlock.
  public static string DeleteOld(string path,string root,long length,long written,long created,long cutoff) {
   string scope=Path.GetFullPath(root).TrimEnd('\\')+"\\";
   string full=Path.GetFullPath(path);
   if(scope.Length<4||!full.StartsWith(scope,StringComparison.OrdinalIgnoreCase)||Protected(full.Substring(scope.Length)))return "RefusedScope";
   using(SafeFileHandle h=CreateFileW(full,0x10080,0,IntPtr.Zero,3,0x00200000,IntPtr.Zero)) {
    if(h.IsInvalid)return "BusyOrDenied:"+Marshal.GetLastWin32Error();
    Info i;if(!GetFileInformationByHandle(h,out i))return "MetadataError";
    if((i.Attributes&0x411)!=0||i.Links!=1)return "ProtectedAttributesOrLinks";
    StringBuilder b=new StringBuilder(32768);uint n=GetFinalPathNameByHandleW(h,b,(uint)b.Capacity,0);
    if(n==0||n>=b.Capacity)return "FinalPathError";
    string actual=b.ToString();if(actual.StartsWith(@"\\?\"))actual=actual.Substring(4);
    if(!actual.Equals(full,StringComparison.OrdinalIgnoreCase)||!actual.StartsWith(scope,StringComparison.OrdinalIgnoreCase)||Protected(actual.Substring(scope.Length)))return "RefusedFinalPath";
    long size=(long)(((ulong)i.SizeHigh<<32)|i.SizeLow);
    if(size!=length||Ticks(i.Written)!=written||Ticks(i.Created)!=created||Ticks(i.Written)>=cutoff)return "ChangedOrRecent";
    Disposition d=new Disposition();d.Delete=1;
    if(!SetFileInformationByHandle(h,4,ref d,4))return "DeleteDenied:"+Marshal.GetLastWin32Error();
   }
   return "Deleted";
  }
 }
}
