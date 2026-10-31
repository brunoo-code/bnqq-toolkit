using System;
using System.Diagnostics;
using System.Threading;
namespace Bnqq {
 public sealed class SyntheticLoad : IDisposable {
  private readonly ManualResetEvent cancel = new ManualResetEvent(false);
  private Thread[] workers;
  private long[] passes;
  private int failure,disposed;
  private readonly Stopwatch clock = new Stopwatch();
  private int seconds,duty,cycle,memoryMiB;
  public bool Failed {get{return Interlocked.CompareExchange(ref failure,0,0)!=0;}}
  public bool Running {get{if(workers==null)return false;foreach(Thread t in workers)if(t!=null && t.IsAlive)return true;return false;}}
  public double ElapsedSeconds {get{return clock.Elapsed.TotalSeconds;}}
  public long Passes {get{long sum=0;if(passes!=null)for(int i=0;i<passes.Length;i+=16)sum+=Interlocked.Read(ref passes[i]);return sum;}}
  public static void Validate(int threads,int duration,int dutyPercent,int cycleMs,int perWorkerMiB) {
   if(threads<1 || threads>16 || duration<1 || duration>120 || dutyPercent<10 || dutyPercent>90 || cycleMs<20 || cycleMs>1000 || perWorkerMiB<1 || perWorkerMiB>16)throw new ArgumentOutOfRangeException("bounded synthetic workload");
  }
  private static uint Pattern(int index){unchecked{uint x=(uint)index+0x9e3779b9U;x^=x>>16;x*=0x85ebca6bU;x^=x>>13;return x;}}
  private static bool VerifyPass(uint[] data,ref uint seed) {
   unchecked {
    for(int n=0;n<1024;n++) {
     seed=1664525U*seed+1013904223U;
     int i=(int)(seed%(uint)data.Length);
     if(data[i]!=Pattern(i))return false;
    }
   }
   return true;
  }
  // Small deterministic correctness fixture, not a load run or stability claim.
  public static bool VerifyKernelFixture(bool corrupt) {
   uint[] data=new uint[32];for(int i=0;i<data.Length;i++)data[i]=Pattern(i);
   if(corrupt)for(int i=0;i<data.Length;i++)data[i]^=1U;
   uint seed=7;return VerifyPass(data,ref seed);
  }
  public void Start(int threads,int duration,int dutyPercent,int cycleMs,int perWorkerMiB) {
   Validate(threads,duration,dutyPercent,cycleMs,perWorkerMiB);
   if(Interlocked.CompareExchange(ref disposed,0,0)!=0)throw new ObjectDisposedException("SyntheticLoad");
   if(workers!=null)throw new InvalidOperationException("Already started");
   seconds=duration;duty=dutyPercent;cycle=cycleMs;memoryMiB=perWorkerMiB;
   passes=new long[threads*16];workers=new Thread[threads];clock.Start();
   try{
    for(int n=0;n<threads;n++){int index=n;workers[n]=new Thread(delegate(){Work(index);});workers[n].IsBackground=true;workers[n].Start();}
   }catch{Interlocked.Exchange(ref failure,1);Stop();throw;}
  }
  private bool Cancelled(){return cancel.WaitOne(0) || clock.Elapsed.TotalSeconds>=seconds;}
  private void Work(int index) {
   long completed=0;
   try {
    uint[] data=new uint[memoryMiB*1024*1024/4];
    for(int i=0;i<data.Length;i++){if((i&4095)==0 && Cancelled())return;data[i]=Pattern(i);}
    uint seed=(uint)(12345+index);
    while(!Cancelled()){
     double begin=clock.Elapsed.TotalMilliseconds;
     double busyEnd=Math.Min(seconds*1000.0,begin+cycle*duty/100.0);
     while(!Cancelled() && clock.Elapsed.TotalMilliseconds<busyEnd){
      if(!VerifyPass(data,ref seed)){Interlocked.Exchange(ref failure,1);cancel.Set();return;}
      completed++;
     }
     Interlocked.Exchange(ref passes[index*16],completed);
     double remaining=Math.Min(seconds*1000.0,begin+cycle)-clock.Elapsed.TotalMilliseconds;
     if(remaining>0)cancel.WaitOne((int)Math.Ceiling(remaining));
    }
   }catch{Interlocked.Exchange(ref failure,1);cancel.Set();}
   finally{Interlocked.Exchange(ref passes[index*16],completed);}
  }
  public void Stop() {
   if(Interlocked.CompareExchange(ref disposed,0,0)!=0)return;
   cancel.Set();
   if(workers!=null)foreach(Thread t in workers)if(t!=null && t.IsAlive && !t.Join(3000))Interlocked.Exchange(ref failure,1);
  }
  public void Dispose() {
   if(Interlocked.CompareExchange(ref disposed,0,0)!=0)return;
   Stop();
   // Never dispose the stop event if a worker somehow remains alive.
   if(!Running){Interlocked.Exchange(ref disposed,1);cancel.Dispose();}
  }
 }
}
