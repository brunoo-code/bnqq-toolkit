using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
namespace Bnqq {
 public sealed class NvidiaTelemetryResult {
  public string Status,Error,Started,Stopped; public int IntervalMs=500; public bool DeviceWide=true;
  public NvidiaGpu[] Gpus; public NvidiaSample[] Samples;
 }
 public sealed class NvidiaTelemetry:IDisposable {
  readonly ManualResetEvent stop=new ManualResetEvent(false); readonly Thread thread;
  readonly List<NvidiaSample> samples=new List<NvidiaSample>(); readonly int seconds,limit;
  readonly NvidiaDriver driver; readonly string started=DateTime.UtcNow.ToString("o");
  readonly NvidiaGpu[] gpus; string error; bool joined;
  public NvidiaTelemetry(int captureSeconds) {
   if(captureSeconds<1 || captureSeconds>300)throw new ArgumentOutOfRangeException("captureSeconds");
   seconds=captureSeconds;limit=captureSeconds*2+10;driver=new NvidiaDriver();
   try{gpus=driver.Inventory();if(gpus.Length!=1)throw new NotSupportedException("Telemetry requires one NVIDIA GPU");driver.Sample();}
   catch{driver.Dispose();stop.Dispose();throw;}
   thread=new Thread(Run);thread.IsBackground=true;thread.Name="BNQQ GPU sampler";
   try{thread.Start();}catch{driver.Dispose();stop.Dispose();throw;}
  }
  void Run() {
   var clock=Stopwatch.StartNew();
   try {
    while(clock.Elapsed.TotalSeconds<seconds+5) {
     double time=clock.Elapsed.TotalSeconds;var row=driver.Sample();row.Seconds=time;
     lock(samples){if(samples.Count>=limit)break;samples.Add(row);}
     if(stop.WaitOne(500))break;
    }
   }catch(Exception e){error=e.Message;}
   finally{try{driver.Dispose();}catch(Exception e){error="NVAPI cleanup: "+e.Message;}}
  }
  public NvidiaTelemetryResult Finish() {
   if(!joined){stop.Set();joined=thread.Join(3000);}
   NvidiaSample[] rows;lock(samples){rows=samples.ToArray();}
   return new NvidiaTelemetryResult{Status=!joined?"StopTimeout":error!=null?"Failed":rows.Length<2?"InsufficientSamples":"Complete",Error=error,Started=started,Stopped=DateTime.UtcNow.ToString("o"),Gpus=gpus,Samples=rows};
  }
  public void Dispose(){if(!joined){Finish();}if(joined)stop.Dispose();}
 }
}
