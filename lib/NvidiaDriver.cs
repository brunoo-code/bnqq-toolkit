// NVAPI ABI/constants: NVIDIA/nvapi, MIT; see NVIDIA-NOTICE.txt in this directory.
// Only the installed System32 library is loaded. No driver, hook or game injection.
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
namespace Bnqq {
 public sealed class NvidiaSetting {
  public uint Id,Value,Location,CurrentPredefined,PredefinedValid,PredefinedValue;
  public bool Found; public uint[] Available; public int CapabilityStatus;
 }
 public sealed class NvidiaProfile {
  public string Application,Name; public uint DriverVersion; public bool Predefined;
  public string[] Applications; public NvidiaSetting[] Settings;
 }
 public sealed class NvidiaGpu {public string Name;public uint DriverVersion;public string Branch;}
 internal sealed class NvBuffer:IDisposable {
  public IntPtr Ptr; public int Size;
  public NvBuffer(int size,uint version) {Size=size;Ptr=Marshal.AllocHGlobal(size);Marshal.Copy(new byte[size],0,Ptr,size);Marshal.WriteInt32(Ptr,unchecked((int)((uint)size | version<<16)));}
  public uint U(int offset){return unchecked((uint)Marshal.ReadInt32(Ptr,offset));}
  public string W(int offset){return Marshal.PtrToStringUni(IntPtr.Add(Ptr,offset),2048).TrimEnd('\0');}
  public void Dispose(){if(Ptr!=IntPtr.Zero){Marshal.FreeHGlobal(Ptr);Ptr=IntPtr.Zero;}}
 }
 public sealed class NvidiaDriver:IDisposable {
  public const uint PowerId=0x1057EB71,ShaderId=0x00198FFF,ShaderSizeId=0x00AC8497;
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr LoadLibraryEx(string path,IntPtr file,uint flags);
  [DllImport("kernel32.dll",CharSet=CharSet.Ansi,ExactSpelling=true)] static extern IntPtr GetProcAddress(IntPtr library,string name);
  [DllImport("kernel32.dll")] static extern bool FreeLibrary(IntPtr library);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr Query(uint id);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int Zero();
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int Create(out IntPtr session);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int One(IntPtr session);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DriverVersion(out uint version,StringBuilder branch);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int EnumGpus([Out] IntPtr[] gpus,out uint count);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int GpuName(IntPtr gpu,StringBuilder name);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int FindApp(IntPtr session,[MarshalAs(UnmanagedType.LPWStr)]string app,out IntPtr profile,IntPtr application);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int GetBase(IntPtr session,out IntPtr profile);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int ProfileInfo(IntPtr session,IntPtr profile,IntPtr info);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int EnumApps(IntPtr session,IntPtr profile,uint start,ref uint count,IntPtr apps);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int GetSetting(IntPtr session,IntPtr profile,uint id,IntPtr setting);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int SetSetting(IntPtr session,IntPtr profile,IntPtr setting);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DeleteSetting(IntPtr session,IntPtr profile,uint id);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int EnumValues(uint id,ref uint count,IntPtr values);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int GpuBuffer(IntPtr gpu,IntPtr buffer);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int GpuThermal(IntPtr gpu,uint sensor,IntPtr buffer);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int GpuPstate(IntPtr gpu,out uint state);
  IntPtr library,session,profile; Query query; bool initialized,canWrite; public readonly uint Version; public readonly string Branch; readonly IntPtr[] gpus;
  T Bind<T>(uint id) where T:class {if(library==IntPtr.Zero)throw new ObjectDisposedException("NvidiaDriver");IntPtr p=query(id);if(p==IntPtr.Zero)throw new NotSupportedException("NVAPI interface unavailable: "+id.ToString("X8"));return (T)(object)Marshal.GetDelegateForFunctionPointer(p,typeof(T));}
  static void Check(int status){if(status!=0)throw new InvalidOperationException("NVAPI status "+status);}
  public NvidiaDriver() {
   if(IntPtr.Size!=8)throw new NotSupportedException("NVAPI requires a 64-bit host");
   try {
    library=LoadLibraryEx(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"nvapi64.dll"),IntPtr.Zero,0x800);
    if(library==IntPtr.Zero)throw new Win32Exception();
    IntPtr q=GetProcAddress(library,"nvapi_QueryInterface");if(q==IntPtr.Zero)throw new NotSupportedException("Missing NVAPI entry point");
    query=(Query)Marshal.GetDelegateForFunctionPointer(q,typeof(Query));Check(Bind<Zero>(0x0150e828)());initialized=true;
    var b=new StringBuilder(64);uint v;Check(Bind<DriverVersion>(0x2926aaad)(out v,b));Version=v;Branch=b.ToString();
    var handles=new IntPtr[64];uint count;Check(Bind<EnumGpus>(0xe5ac921f)(handles,out count));
    if(count==0 || count>64)throw new NotSupportedException("No NVIDIA GPU or invalid GPU count");Array.Resize(ref handles,(int)count);gpus=handles;
   }catch{Dispose();throw;}
  }
  void EnsureSession(){if(session!=IntPtr.Zero)return;Check(Bind<Create>(0x0694d52e)(out session));Check(Bind<One>(0x375dbd6b)(session));}
  public NvidiaGpu[] Inventory(){var result=new List<NvidiaGpu>();foreach(var gpu in gpus){var n=new StringBuilder(64);Check(Bind<GpuName>(0xceee8e9f)(gpu,n));result.Add(new NvidiaGpu{Name=n.ToString(),DriverVersion=Version,Branch=Branch});}return result.ToArray();}
  static void Admit(uint id){if(id!=PowerId && id!=ShaderId && id!=ShaderSizeId)throw new ArgumentException("Unapproved NVIDIA setting");}
  public NvidiaSetting ReadSetting(uint id) {
   Admit(id);var result=new NvidiaSetting{Id=id,Available=new uint[0]};
   using(var values=new NvBuffer(414112,1)) {
    uint count=100;int status=Bind<EnumValues>(0x2ec39f90)(id,ref count,values.Ptr);result.CapabilityStatus=status;
    if(status==0){uint actual=values.U(4);if(count>100 || actual>100 || values.U(8)!=0)throw new InvalidOperationException("Unsupported NVAPI value metadata");var list=new uint[actual];for(int i=0;i<list.Length;i++)list[i]=values.U(4112+i*4100);result.Available=list;}
   }
   using(var setting=new NvBuffer(12320,1)) {
    int status=Bind<GetSetting>(0x73bf8338)(session,profile,id,setting.Ptr);if(status==-160)return result;Check(status);
    if(setting.U(4100)!=id || setting.U(4104)!=0)throw new InvalidOperationException("NVAPI setting identity/type mismatch");
    result.Found=true;result.Location=setting.U(4108);result.CurrentPredefined=setting.U(4112);result.PredefinedValid=setting.U(4116);result.PredefinedValue=setting.U(4120);result.Value=setting.U(8220);
   }return result;
  }
  public NvidiaProfile ReadProfile(string application) {
   EnsureSession();canWrite=false;
   if(String.IsNullOrEmpty(application)){Check(Bind<GetBase>(0xda8466a0)(session,out profile));}
   else {if(application.Length>=2048)throw new ArgumentException("Application path too long");using(var app=new NvBuffer(12296,1)){Check(Bind<FindApp>(0xeee566b2)(session,application,out profile,app.Ptr));}}
   var result=new NvidiaProfile{Application=application,DriverVersion=Version};uint count;
   using(var info=new NvBuffer(4116,1)){Check(Bind<ProfileInfo>(0x61cd6fd6)(session,profile,info.Ptr));result.Name=info.W(4);result.Predefined=info.U(4104)!=0;count=info.U(4108);}
   if(count>256)throw new NotSupportedException("Profile contains too many applications");
   var names=new List<string>();
   for(uint i=0;i<count;i++){using(var app=new NvBuffer(12296,1)){uint one=1;Check(Bind<EnumApps>(0x7fa2173a)(session,profile,i,ref one,app.Ptr));if(one!=1)throw new InvalidOperationException("Application enumeration changed");names.Add(app.W(8));}}
   names.Sort(StringComparer.OrdinalIgnoreCase);result.Applications=names.ToArray();result.Settings=new[]{ReadSetting(PowerId),ReadSetting(ShaderId),ReadSetting(ShaderSizeId)};
   canWrite=!String.IsNullOrEmpty(application);return result;
  }
  public void Stage(uint id,uint value) {
   if(id!=PowerId)throw new ArgumentException("Only documented per-application power mode is writable");if(!canWrite)throw new InvalidOperationException("Only an existing application profile may be changed");
   var caps=ReadSetting(id);if(caps.CapabilityStatus!=0 || Array.IndexOf(caps.Available,value)<0)throw new NotSupportedException("Value not advertised by NVIDIA driver");
   using(var setting=new NvBuffer(12320,1)){Marshal.WriteInt32(setting.Ptr,4100,unchecked((int)id));Marshal.WriteInt32(setting.Ptr,8220,unchecked((int)value));Check(Bind<SetSetting>(0x577dd202)(session,profile,setting.Ptr));}
  }
  public void StageRemoveOverride(uint id){if(id!=PowerId)throw new ArgumentException("Only power override can be removed");if(!canWrite)throw new InvalidOperationException("No application profile selected");Check(Bind<DeleteSetting>(0xe4a26362)(session,profile,id));}
  public void Save(){if(!canWrite)throw new InvalidOperationException("Global writes are forbidden");Check(Bind<One>(0xfcbc7e14)(session));}
  public NvidiaSample Sample() {
   if(gpus.Length!=1)throw new NotSupportedException("Explicit single NVIDIA GPU required for telemetry");var sample=new NvidiaSample{Utc=DateTime.UtcNow.ToString("o")};var gpu=gpus[0];
   using(var p=new NvBuffer(72,1)){Check(Bind<GpuBuffer>(0x60ded2ed)(gpu,p.Ptr));if((p.U(8)&1)==0)throw new NotSupportedException("GPU utilization unavailable");sample.GpuPercent=p.U(12);if(sample.GpuPercent>100)throw new InvalidOperationException("Invalid GPU utilization");}
   using(var p=new NvBuffer(264,2)){Check(Bind<GpuBuffer>(0xdcb616c3)(gpu,p.Ptr));if((p.U(8)&1)!=0)sample.GraphicsMHz=p.U(12)/1000.0;if((p.U(40)&1)!=0)sample.MemoryMHz=p.U(44)/1000.0;}
   using(var p=new NvBuffer(68,2)){Check(Bind<GpuThermal>(0xe3640a56)(gpu,0,p.Ptr));if(p.U(4)<1 || p.U(4)>3)throw new InvalidOperationException("Invalid thermal sensors");sample.TemperatureC=Marshal.ReadInt32(p.Ptr,20);if(sample.TemperatureC< -50 || sample.TemperatureC>150)throw new InvalidOperationException("Invalid GPU temperature");}
   uint state;Check(Bind<GpuPstate>(0x927da4f6)(gpu,out state));sample.Pstate=state;return sample;
  }
  public void Dispose(){try{if(session!=IntPtr.Zero && query!=null)Bind<One>(0xdad9cff8)(session);}finally{session=IntPtr.Zero;try{if(initialized)Bind<Zero>(0xd22bdd7e)();}finally{initialized=false;if(library!=IntPtr.Zero){FreeLibrary(library);library=IntPtr.Zero;}}}}
 }
 public sealed class NvidiaSample {public string Utc;public double Seconds;public uint GpuPercent,Pstate;public double? GraphicsMHz,MemoryMHz;public int TemperatureC;}
}
