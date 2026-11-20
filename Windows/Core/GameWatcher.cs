using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Management;
using System.Threading;

namespace Optimizator.Core;

public sealed record GameHit(int Pid, string GameName, string ProcessName);

/// <summary>
/// Раз на 2 секунди дивиться список процесів і повідомляє, коли гра запустилась / закрилась.
/// Навантаження мізерне: GetProcesses + WMI-запит лише для нових java-процесів.
/// </summary>
public sealed class GameWatcher : IDisposable
{
    public event Action<GameHit>? Started;
    public event Action<GameHit>? Stopped;

    readonly Func<IReadOnlyList<GameProfile>> _games;
    readonly Dictionary<int, GameHit> _running = new();
    readonly Dictionary<int, bool> _javaChecked = new(); // pid -> чи це гра
    readonly Timer _timer;
    readonly object _lock = new();
    int _busy;

    public GameWatcher(Func<IReadOnlyList<GameProfile>> games)
    {
        _games = games;
        _timer = new Timer(_ => Tick(), null, Timeout.Infinite, Timeout.Infinite);
    }

    public void Start() => _timer.Change(0, 2000);

    public IReadOnlyCollection<GameHit> Running { get { lock (_lock) return _running.Values.ToList(); } }

    void Tick()
    {
        if (Interlocked.Exchange(ref _busy, 1) == 1) return;
        try
        {
            var profiles = _games().Where(g => g.Enabled).ToList();
            var map = new Dictionary<string, GameProfile>(StringComparer.OrdinalIgnoreCase);
            foreach (var g in profiles)
                foreach (var n in g.ProcessNames)
                    map.TryAdd(n.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ? n[..^4] : n, g);

            var alive = new HashSet<int>();
            var started = new List<GameHit>();

            foreach (var p in Process.GetProcesses())
            {
                using (p)
                {
                    int pid = p.Id;
                    string name;
                    try { name = p.ProcessName; } catch { continue; }
                    if (!map.TryGetValue(name, out var profile)) continue;

                    if (profile.CommandLineAny.Count > 0)
                    {
                        if (!_javaChecked.TryGetValue(pid, out bool isGame))
                        {
                            var cmd = GetCommandLine(pid) ?? "";
                            isGame = profile.CommandLineAny.Any(w => cmd.Contains(w, StringComparison.OrdinalIgnoreCase))
                                     && !cmd.Contains("nogui", StringComparison.OrdinalIgnoreCase); // сервери — не гра
                            _javaChecked[pid] = isGame;
                        }
                        if (!isGame) continue;
                    }

                    alive.Add(pid);
                    lock (_lock)
                    {
                        if (!_running.ContainsKey(pid))
                        {
                            var hit = new GameHit(pid, profile.Name, name);
                            _running[pid] = hit;
                            started.Add(hit);
                        }
                    }
                }
            }

            List<GameHit> stopped;
            lock (_lock)
            {
                stopped = _running.Values.Where(h => !alive.Contains(h.Pid)).ToList();
                foreach (var h in stopped) _running.Remove(h.Pid);
            }
            foreach (var pid in _javaChecked.Keys.ToList())
                if (!alive.Contains(pid) && !ProcessExists(pid)) _javaChecked.Remove(pid);

            foreach (var h in started) Started?.Invoke(h);
            foreach (var h in stopped) Stopped?.Invoke(h);
        }
        catch { /* ніколи не падаємо через монітор */ }
        finally { Interlocked.Exchange(ref _busy, 0); }
    }

    static bool ProcessExists(int pid)
    {
        try { using var p = Process.GetProcessById(pid); return !p.HasExited; } catch { return false; }
    }

    static string? GetCommandLine(int pid)
    {
        try
        {
            using var s = new ManagementObjectSearcher($"SELECT CommandLine FROM Win32_Process WHERE ProcessId = {pid}");
            foreach (ManagementObject o in s.Get())
                using (o) return o["CommandLine"]?.ToString();
        }
        catch { }
        return null;
    }

    public void Dispose() => _timer.Dispose();
}
