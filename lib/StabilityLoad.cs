using System;
using System.IO;
using System.Security.Cryptography;
using System.Threading;
namespace Bnqq {
    public sealed class VerifiedLoad : IDisposable {
        private volatile bool stop;
        private Thread[] workers;
        private Thread io;
        private long cpuPasses,ioPasses;
        private int error;
        public long CpuPasses {get{return Interlocked.Read(ref cpuPasses);}}
        public long IoPasses {get{return Interlocked.Read(ref ioPasses);}}
        public bool Failed {get{return Interlocked.CompareExchange(ref error,0,0)!=0;}}
        public bool Running {get{if(workers==null)return false;foreach(Thread t in workers)if(!t.IsAlive)return false;return io!=null && io.IsAlive;}}
        public void Start(int threads,string file) {
            if(workers!=null)throw new InvalidOperationException("Already started");
            if(threads<1 || threads>128)throw new ArgumentOutOfRangeException("threads");
            stop=false;workers=new Thread[threads];
            for(int n=0;n<threads;n++) {Thread t=new Thread(Cpu);t.IsBackground=true;workers[n]=t;t.Start();}
            io=new Thread(delegate(){Io(file);});io.IsBackground=true;io.Start();
        }
        private static bool Equal(byte[] a,byte[] b){if(a.Length!=b.Length)return false;for(int i=0;i<a.Length;i++)if(a[i]!=b[i])return false;return true;}
        private void Cpu() {
            try {
                byte[] block=new byte[65536];new Random(12345).NextBytes(block);
                using(SHA256 hash=SHA256.Create()) {
                    byte[] expected=hash.ComputeHash(block);
                    while(!stop){if(!Equal(expected,hash.ComputeHash(block))){Interlocked.Exchange(ref error,1);return;}Interlocked.Increment(ref cpuPasses);}
                }
            }catch{Interlocked.Exchange(ref error,1);}
        }
        private void Io(string path) {
            try {
                byte[] block=new byte[262144];new Random(6789).NextBytes(block);
                byte[] read=new byte[block.Length];
                using(FileStream stream=new FileStream(path,FileMode.CreateNew,FileAccess.ReadWrite,FileShare.None,4096,FileOptions.WriteThrough)) {
                    while(!stop) {
                        stream.Position=0;stream.Write(block,0,block.Length);stream.Flush(true);stream.Position=0;
                        int offset=0,count;
                        while(offset<read.Length && (count=stream.Read(read,offset,read.Length-offset))>0)offset+=count;
                        if(offset!=read.Length || !Equal(block,read)){Interlocked.Exchange(ref error,1);return;}
                        Interlocked.Increment(ref ioPasses);Thread.Sleep(50);
                    }
                }
            }catch{Interlocked.Exchange(ref error,1);}
        }
        public void Stop() {
            stop=true;
            if(workers!=null)foreach(Thread t in workers)if(!t.Join(5000))Interlocked.Exchange(ref error,1);
            if(io!=null && !io.Join(5000))Interlocked.Exchange(ref error,1);
        }
        public void Dispose(){Stop();}
    }
}
