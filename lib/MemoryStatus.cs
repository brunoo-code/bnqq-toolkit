using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace Bnqq {
 public sealed class MemorySnapshot {
  public string Utc; public ulong PhysicalTotalBytes,PhysicalAvailableBytes,CommitUsedBytes,CommitLimitBytes,SystemCacheBytes;
 }
 public static class MemoryStatus {
  [StructLayout(LayoutKind.Sequential)] struct Info {
   public uint Size;
   public UIntPtr CommitTotal,CommitLimit,CommitPeak,PhysicalTotal,PhysicalAvailable,SystemCache,KernelTotal,KernelPaged,KernelNonpaged,PageSize;
   public uint Handles,Processes,Threads;
  }
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool K32GetPerformanceInfo(out Info info,uint bytes);
  public static MemorySnapshot Read() {
   Info p;if(!K32GetPerformanceInfo(out p,(uint)Marshal.SizeOf(typeof(Info))))throw new Win32Exception();
   ulong size=p.PageSize.ToUInt64(),total=p.PhysicalTotal.ToUInt64(),available=p.PhysicalAvailable.ToUInt64(),commit=p.CommitTotal.ToUInt64(),limit=p.CommitLimit.ToUInt64();
   if(size==0 || size>1048576 || total==0 || available>total || limit==0 || commit>limit)throw new InvalidOperationException("Invalid kernel memory counters");
   checked{return new MemorySnapshot{Utc=DateTime.UtcNow.ToString("o"),PhysicalTotalBytes=total*size,PhysicalAvailableBytes=available*size,CommitUsedBytes=commit*size,CommitLimitBytes=limit*size,SystemCacheBytes=p.SystemCache.ToUInt64()*size};}
  }
 }
}
