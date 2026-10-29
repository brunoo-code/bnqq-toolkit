using System;
using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Threading;

public static class VirtualInGameQA
{
    private static volatile bool _stop;
    private static long _ticks;
    private static long _physicsOps;
    private static long _memoryOps;
    private static long _packets;
    private static long _jitterTicks;
    private static long _jitterMaxTicks;
    private static long _affinityFailures;
    private static int _tickRate = 128;
    private static int _seconds = 30;
    private static int _threads;
    private static long _mask = 0x5555;
    private static uint _timerCurrent;
    private static uint _timerMin;
    private static uint _timerMax;
    private static bool _timerSet;

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentThread();

    [DllImport("kernel32.dll")]
    private static extern IntPtr SetThreadAffinityMask(IntPtr hThread, IntPtr mask);

    [DllImport("ntdll.dll")]
    private static extern int NtSetTimerResolution(uint desired, bool set, out uint current);

    [DllImport("ntdll.dll")]
    private static extern int NtQueryTimerResolution(out uint min, out uint max, out uint current);

    public static int Main(string[] args)
    {
        ParseArgs(args);
        if (_threads <= 0) _threads = Math.Max(4, Environment.ProcessorCount / 2);
        _threads = Math.Min(_threads, Math.Max(4, CountBits(_mask)));

        try
        {
            uint current;
            if (NtSetTimerResolution(5000, true, out current) == 0)
            {
                _timerSet = true;
            }
            NtQueryTimerResolution(out _timerMin, out _timerMax, out _timerCurrent);
        }
        catch
        {
        }

        Console.WriteLine("engine=BNQQ VirtualInGameQA");
        Console.WriteLine("version=1.4.0");
        Console.WriteLine("duration_s=" + _seconds.ToString(CultureInfo.InvariantCulture));
        Console.WriteLine("tick_rate=" + _tickRate.ToString(CultureInfo.InvariantCulture));
        Console.WriteLine("threads=" + _threads.ToString(CultureInfo.InvariantCulture));
        Console.WriteLine("mask=0x" + _mask.ToString("X", CultureInfo.InvariantCulture));

        Thread ticker = new Thread(TickLoop);
        ticker.IsBackground = true;
        ticker.Priority = ThreadPriority.AboveNormal;
        ticker.Start();

        Thread[] workers = new Thread[_threads];
        for (int i = 0; i < workers.Length; i++)
        {
            workers[i] = new Thread(PhysicsLoop);
            workers[i].IsBackground = true;
            workers[i].Priority = ThreadPriority.Normal;
            workers[i].Start();
        }

        Thread memory = new Thread(MemoryLoop);
        memory.IsBackground = true;
        memory.Priority = ThreadPriority.BelowNormal;
        memory.Start();

        Thread network = new Thread(NetworkLoop);
        network.IsBackground = true;
        network.Priority = ThreadPriority.BelowNormal;
        network.Start();

        Thread.Sleep(_seconds * 1000);
        _stop = true;

        ticker.Join(5000);
        foreach (Thread worker in workers) worker.Join(3000);
        memory.Join(3000);
        network.Join(3000);

        if (_timerSet)
        {
            uint ignored;
            NtSetTimerResolution(_timerCurrent, true, out ignored);
        }

        double elapsedSeconds = Math.Max(0.001, _seconds);
        double jitterAvg = _jitterTicks / (double)Math.Max(1, _ticks);
        double jitterMax = _jitterMaxTicks;
        double frequency = Stopwatch.Frequency;
        long expected = (long)_seconds * _tickRate;

        Console.WriteLine("ticks=" + _ticks.ToString(CultureInfo.InvariantCulture));
        Console.WriteLine("tick_hz=" + (_ticks / elapsedSeconds).ToString("0.0", CultureInfo.InvariantCulture));
        Console.WriteLine("jitter_avg_us=" + (jitterAvg * 1000000.0 / frequency).ToString("0.0", CultureInfo.InvariantCulture));
        Console.WriteLine("jitter_max_us=" + (jitterMax * 1000000.0 / frequency).ToString("0.0", CultureInfo.InvariantCulture));
        Console.WriteLine("physics_ops=" + _physicsOps.ToString(CultureInfo.InvariantCulture));
        Console.WriteLine("memory_ops=" + _memoryOps.ToString(CultureInfo.InvariantCulture));
        Console.WriteLine("network_packets=" + _packets.ToString(CultureInfo.InvariantCulture));
        Console.WriteLine("timer_ms=" + (_timerCurrent / 10000.0).ToString("0.000", CultureInfo.InvariantCulture));
        Console.WriteLine("affinity_failures=" + _affinityFailures.ToString(CultureInfo.InvariantCulture));
        Console.WriteLine("stable=" + ((_ticks >= (long)(expected * 0.90) && _affinityFailures == 0) ? "true" : "false"));
        return 0;
    }

    private static void ParseArgs(string[] args)
    {
        for (int i = 0; i < args.Length; i++)
        {
            string key = args[i];
            string value = (i + 1 < args.Length) ? args[i + 1] : null;
            if (value == null) continue;
            if (key == "--seconds") { int.TryParse(value, out _seconds); i++; }
            else if (key == "--ticks") { int.TryParse(value, out _tickRate); i++; }
            else if (key == "--threads") { int.TryParse(value, out _threads); i++; }
            else if (key == "--mask")
            {
                string text = value.StartsWith("0x", StringComparison.OrdinalIgnoreCase) ? value.Substring(2) : value;
                long parsed;
                if (long.TryParse(text, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out parsed)) _mask = parsed;
                i++;
            }
        }
        if (_seconds < 5) _seconds = 5;
        if (_tickRate < 32) _tickRate = 32;
    }

    private static int CountBits(long value)
    {
        int count = 0;
        while (value != 0) { value &= (value - 1); count++; }
        return count;
    }

    private static void PinCurrentThread()
    {
        try
        {
            if (SetThreadAffinityMask(GetCurrentThread(), new IntPtr(_mask)) == IntPtr.Zero)
            {
                Interlocked.Increment(ref _affinityFailures);
            }
        }
        catch
        {
            Interlocked.Increment(ref _affinityFailures);
        }
    }

    private static void TickLoop()
    {
        PinCurrentThread();
        Stopwatch clock = Stopwatch.StartNew();
        long tickIndex = 0;
        double intervalTicks = Stopwatch.Frequency / (double)_tickRate;

        while (!_stop)
        {
            long target = (long)(tickIndex * intervalTicks);
            long now = clock.ElapsedTicks;
            if (now > target)
            {
                long jitter = now - target;
                Interlocked.Add(ref _jitterTicks, jitter);
                long currentMax = Interlocked.Read(ref _jitterMaxTicks);
                while (jitter > currentMax)
                {
                    long original = Interlocked.CompareExchange(ref _jitterMaxTicks, jitter, currentMax);
                    if (original == currentMax) break;
                    currentMax = original;
                }
            }

            Interlocked.Increment(ref _ticks);
            tickIndex++;

            long next = (long)(tickIndex * intervalTicks);
            double remainingMs = (next - clock.ElapsedTicks) * 1000.0 / Stopwatch.Frequency;
            if (remainingMs > 1.5) Thread.Sleep((int)remainingMs - 1);
            else if (remainingMs > 0) Thread.SpinWait(200);
        }
    }

    private static void PhysicsLoop()
    {
        PinCurrentThread();
        double accumulator = 0.0;
        while (!_stop)
        {
            for (int i = 0; i < 2500; i++)
            {
                double angle = (i + 1) * 0.0174532925;
                accumulator += Math.Sin(angle) * Math.Cos(angle * 0.5);
                accumulator += Math.Sqrt(1.0 + (i & 1023));
            }
            if (double.IsNaN(accumulator) || double.IsInfinity(accumulator)) accumulator = 0.0;
            Interlocked.Add(ref _physicsOps, 2500);
            Thread.Sleep(0);
        }
    }

    private static void MemoryLoop()
    {
        PinCurrentThread();
        byte[] buffer = new byte[32 * 1024 * 1024];
        Random random = new Random(5700);
        while (!_stop)
        {
            long sum = 0;
            for (int i = 0; i < 12000; i++)
            {
                int index = random.Next(buffer.Length);
                sum += buffer[index];
                buffer[index] = (byte)(sum & 0xFF);
            }
            Interlocked.Add(ref _memoryOps, 12000);
            Thread.Sleep(0);
        }
    }

    private static void NetworkLoop()
    {
        PinCurrentThread();
        UdpClient client = null;
        try
        {
            client = new UdpClient(0);
            client.Connect(new IPEndPoint(IPAddress.Loopback, 27015));
        }
        catch
        {
            client = null;
        }

        byte[] packet = new byte[64];
        int interval = Math.Max(1, 1000 / Math.Max(32, _tickRate));
        while (!_stop)
        {
            try
            {
                if (client != null) client.Send(packet, packet.Length);
                Interlocked.Increment(ref _packets);
            }
            catch
            {
                Interlocked.Increment(ref _packets);
            }
            Thread.Sleep(interval);
        }

        if (client != null)
        {
            try { client.Close(); } catch { }
        }
    }
}
