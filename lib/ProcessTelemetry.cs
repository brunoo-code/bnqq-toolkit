using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Diagnostics;
using Microsoft.Win32.SafeHandles;
// Version the CLR contract: an older CLI invocation may still have V1 types loaded.
namespace Bnqq.TelemetryV2 {
 public sealed class ProcessCpuSample {
  public int ProcessId; public string Name,StartTime; public double CpuMs;
 }
 public sealed class ProcessPrioritySample {
  public int ProcessId; public string Name,StartTime,Priority;
 }
 public static class ProcessTelemetry {
  [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint access,bool inherit,int pid);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetProcessTimes(IntPtr handle,out long created,out long exited,out long kernel,out long user);
  [DllImport("kernel32.dll",SetLastError=true)] static extern uint GetPriorityClass(IntPtr handle);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetExitCodeProcess(IntPtr handle,out uint code);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool QueryFullProcessImageName(IntPtr handle,uint flags,StringBuilder name,ref uint size);
  [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
  [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetTokenInformation(IntPtr token,int information,out uint value,uint size,out uint needed);
  [DllImport("kernel32.dll",SetLastError=true)] static extern uint WaitForSingleObject(SafeWaitHandle handle,uint milliseconds);
  public sealed class ProcessLifetime : IDisposable {
   readonly SafeWaitHandle handle;
   internal ProcessLifetime(IntPtr value){handle=new SafeWaitHandle(value,true);}
   public bool IsAlive(){
    // SafeHandle marshalling retains the handle across the call, including concurrent disposal.
    uint result=WaitForSingleObject(handle,0);
    if(result==258)return true;
    if(result==0)return false;
    if(result==0xffffffff)throw new Win32Exception();
    throw new InvalidOperationException("Unexpected process wait result");
   }
   public void Dispose(){handle.Dispose();}
  }
  public static ProcessLifetime Watch(int pid,string expectedName,string expectedStart,string expectedOwner,uint expectedSession){
   if(pid<=0 || String.IsNullOrEmpty(expectedName) || String.IsNullOrEmpty(expectedStart) || String.IsNullOrEmpty(expectedOwner))throw new ArgumentException("Missing process identity/scope");
   // QUERY_LIMITED_INFORMATION | SYNCHRONIZE, never process modification or VM access.
   IntPtr process=OpenProcess(0x101000,false,pid);
   if(process==IntPtr.Zero){int error=Marshal.GetLastWin32Error();if(error==87)return null;throw new Win32Exception(error);}
   ProcessLifetime watch=null;
   try{
    ProcessCpuSample sample=ReadHandle(process,pid,expectedName,expectedOwner,expectedSession);
    if(sample==null || !String.Equals(sample.StartTime,expectedStart,StringComparison.Ordinal))return null;
    watch=new ProcessLifetime(process);process=IntPtr.Zero;
    if(!watch.IsAlive()){watch.Dispose();return null;}
    return watch;
   }catch{if(watch!=null)watch.Dispose();throw;}
   finally{if(process!=IntPtr.Zero)CloseHandle(process);}
  }
  public static ProcessCpuSample Read(int pid,string expectedName,string expectedOwner,uint expectedSession) {
   if(pid<=0 || String.IsNullOrEmpty(expectedName) || String.IsNullOrEmpty(expectedOwner))throw new ArgumentException("Missing process identity/scope");
   // QUERY_LIMITED_INFORMATION only: no VM_READ, SET_INFORMATION or termination rights.
   IntPtr process=OpenProcess(0x1000,false,pid);
   if(process==IntPtr.Zero){int error=Marshal.GetLastWin32Error();if(error==87)return null;throw new Win32Exception(error);}
   try{return ReadHandle(process,pid,expectedName,expectedOwner,expectedSession);}
   finally{CloseHandle(process);}
  }
  public static ProcessPrioritySample ReadPriority(int pid,string expectedName,string expectedStart,string expectedOwner,uint expectedSession){
   if(pid<=0 || String.IsNullOrEmpty(expectedOwner))throw new ArgumentException("Missing process identity/scope");
   bool discovery=String.IsNullOrEmpty(expectedName) && String.IsNullOrEmpty(expectedStart);
   if(!discovery && (String.IsNullOrEmpty(expectedName) || String.IsNullOrEmpty(expectedStart)))throw new ArgumentException("Incomplete expected identity");
   IntPtr process=OpenProcess(0x1000,false,pid);
   if(process==IntPtr.Zero){int error=Marshal.GetLastWin32Error();if(error==87)return null;throw new Win32Exception(error);}
   try{
    uint exitCode;
    if(!GetExitCodeProcess(process,out exitCode))throw new Win32Exception();
    // A non-259 code confirms termination. 259 alone is NOT proof of liveness.
    if(exitCode!=259)return null;
    ProcessCpuSample sample=ReadHandle(process,pid,discovery?null:expectedName,expectedOwner,expectedSession);
    if(sample==null || (!discovery && !String.Equals(sample.StartTime,expectedStart,StringComparison.Ordinal)))return null;
    uint priority=GetPriorityClass(process);
    if(priority==0)throw new Win32Exception();
    if(!Enum.IsDefined(typeof(ProcessPriorityClass),(int)priority))throw new InvalidOperationException("Unknown process priority class");
    return new ProcessPrioritySample{ProcessId=pid,Name=sample.Name,StartTime=sample.StartTime,Priority=((ProcessPriorityClass)priority).ToString()};
   }catch(Win32Exception){
    // The process may exit between the first query and token/priority reads.
    uint exitCode;
    if(GetExitCodeProcess(process,out exitCode) && exitCode!=259)return null;
    throw;
   }finally{CloseHandle(process);}
  }
  static ProcessCpuSample ReadHandle(IntPtr process,int pid,string expectedName,string expectedOwner,uint expectedSession){
    IntPtr token;
    if(!OpenProcessToken(process,8,out token))throw new Win32Exception();
    try{
     uint session,needed;
     if(!GetTokenInformation(token,12,out session,4,out needed))throw new Win32Exception();
     if(needed!=4 || session!=expectedSession)throw new UnauthorizedAccessException("Process session differs");
     using(WindowsIdentity identity=new WindowsIdentity(token)){
      if(identity.User==null || !String.Equals(identity.User.Value,expectedOwner,StringComparison.Ordinal))throw new UnauthorizedAccessException("Process owner differs");
     }
    }finally{CloseHandle(token);}
    uint capacity=1024;StringBuilder path=new StringBuilder((int)capacity);
    if(!QueryFullProcessImageName(process,0,path,ref capacity)){
     if(Marshal.GetLastWin32Error()!=122)throw new Win32Exception();
     capacity=32768;path=new StringBuilder((int)capacity);
     if(!QueryFullProcessImageName(process,0,path,ref capacity))throw new Win32Exception();
    }
    string name=Path.GetFileNameWithoutExtension(path.ToString());
    if(expectedName!=null && !String.Equals(name,expectedName,StringComparison.OrdinalIgnoreCase))return null;
    long created,exited,kernel,user;
    if(!GetProcessTimes(process,out created,out exited,out kernel,out user))throw new Win32Exception();
    if(created<=0 || kernel<0 || user<0)throw new InvalidOperationException("Invalid process time counters");
    return new ProcessCpuSample{ProcessId=pid,Name=name,StartTime=DateTime.FromFileTimeUtc(created).ToString("o"),CpuMs=((double)kernel+(double)user)/10000.0};
  }
 }
}
