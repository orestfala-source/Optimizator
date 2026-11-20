using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.Json;
using Microsoft.Win32;

namespace Optimizator.Core;

/// <summary>
/// Вмикає ігрові оптимізації при старті гри і ПОВНІСТЮ повертає все як було, коли ігор не залишилось.
/// Нічого не змінюється назавжди: стан для відновлення пишеться у restore.json,
/// тож навіть якщо програму вбили — при наступному запуску все відкотиться.
/// </summary>
public sealed class Optimizer
{
    readonly AppSettings _s;
    readonly Action<string> _log;
    readonly object _lock = new();

    sealed class RestoreState
    {
        public Guid? Scheme { get; set; }
        public Guid? Overlay { get; set; }
        public List<string> GpuPrefsAdded { get; set; } = new();
    }

    RestoreState? _state;
    bool _timerSet;
    readonly Dictionary<int, uint> _bgOriginal = new();   // pid -> старий пріоритет
    readonly HashSet<int> _boostedGames = new();

    static string RestoreFile => Path.Combine(AppSettings.DataDir, "restore.json");
    const string GpuKey = @"Software\Microsoft\DirectX\UserGpuPreferences";

    public bool IsActive { get { lock (_lock) return _state != null; } }

    public Optimizer(AppSettings s, Action<string> log) { _s = s; _log = log; }

    /// <summary>Якщо минулого разу програма закрилась аварійно під час бусту — відкатуємо.</summary>
    public void RecoverAfterCrash()
    {
        try
        {
            if (!File.Exists(RestoreFile)) return;
            var st = JsonSerializer.Deserialize<RestoreState>(File.ReadAllText(RestoreFile));
            if (st != null) { _state = st; Deactivate(); _log("Відновлено налаштування після аварійного закриття"); }
            File.Delete(RestoreFile);
        }
        catch { }
    }

    public void Activate()
    {
        lock (_lock)
        {
            if (_state != null) return;
            _state = new RestoreState();

            if (_s.PowerPlan)
            {
                _state.Scheme = Native.GetActiveScheme();
                _state.Overlay = Native.GetOverlay();
                bool hp = Native.SetActiveScheme(Native.HighPerformance);
                bool ov = Native.SetOverlay(Native.OverlayBestPerformance);
                _log(hp ? "Схема живлення: Висока продуктивність"
                        : ov ? "Режим живлення: Найкраща продуктивність"
                             : "Схема живлення недоступна на цьому ПК");
            }

            if (_s.TimerResolution && Native.NtSetTimerResolution(5000, true, out _) == 0)
            {
                _timerSet = true;
                _log("Таймер системи: 0.5 мс");
            }

            if (_s.PurgeStandby)
                _log(Native.PurgeStandbyList() ? "Кеш RAM очищено" : "Не вдалося очистити кеш RAM");

            if (_s.ThrottleBackground) ThrottleBackground();
            SaveState();
        }
    }

    /// <summary>Оптимізувати конкретний процес гри.</summary>
    public void BoostGame(GameHit hit)
    {
        lock (_lock)
        {
            if (!_boostedGames.Add(hit.Pid)) return;
            IntPtr h = Native.OpenProcess(Native.PROCESS_SET_INFORMATION | Native.PROCESS_QUERY_LIMITED_INFORMATION, false, hit.Pid);
            if (h == IntPtr.Zero) { _log($"{hit.GameName}: немає доступу до процесу (античит) — працює решта оптимізацій"); }
            else
            {
                try
                {
                    if (_s.GamePriority && Native.SetPriorityClass(h, Native.HIGH_PRIORITY_CLASS))
                        _log($"{hit.GameName}: високий пріоритет");
                    if (_s.DisableEcoQoS) Native.SetEcoQoS(h, false);
                }
                finally { Native.CloseHandle(h); }
            }

            if (_s.GpuHighPerformance && _state != null)
            {
                var path = Native.GetProcessPath(hit.Pid);
                if (path != null) SetGpuPreference(path);
            }
            SaveState();
        }
    }

    public void Deactivate()
    {
        lock (_lock)
        {
            if (_state == null) return;

            if (_state.Scheme is Guid sc) Native.SetActiveScheme(sc);
            if (_state.Overlay is Guid ov) Native.SetOverlay(ov);

            if (_timerSet) { Native.NtSetTimerResolution(0, false, out _); _timerSet = false; }

            foreach (var (pid, prio) in _bgOriginal)
            {
                IntPtr h = Native.OpenProcess(Native.PROCESS_SET_INFORMATION, false, pid);
                if (h == IntPtr.Zero) continue;
                Native.SetPriorityClass(h, prio);
                Native.SetEcoQoS(h, null);
                Native.CloseHandle(h);
            }
            _bgOriginal.Clear();

            // Налаштування дискретної відеокарти НЕ видаляємо: Windows застосовує його лише при старті гри,
            // тому воно має лишитись до наступного запуску. Воно безпечне і стосується лише цього exe.

            _boostedGames.Clear();
            _state = null;
            try { File.Delete(RestoreFile); } catch { }
            _log("Буст вимкнено — система повернута до звичайного режиму");
        }
    }

    void ThrottleBackground()
    {
        var names = new HashSet<string>(_s.BackgroundApps, StringComparer.OrdinalIgnoreCase);
        int count = 0;
        foreach (var p in Process.GetProcesses())
        {
            using (p)
            {
                string n;
                try { n = p.ProcessName; } catch { continue; }
                if (!names.Contains(n) || _bgOriginal.ContainsKey(p.Id)) continue;

                IntPtr h = Native.OpenProcess(Native.PROCESS_SET_INFORMATION | Native.PROCESS_QUERY_LIMITED_INFORMATION, false, p.Id);
                if (h == IntPtr.Zero) continue;
                uint old = Native.GetPriorityClass(h);
                if (old != 0 && Native.SetPriorityClass(h, Native.BELOW_NORMAL_PRIORITY_CLASS))
                {
                    Native.SetEcoQoS(h, true);
                    _bgOriginal[p.Id] = old;
                    count++;
                }
                Native.CloseHandle(h);
            }
        }
        if (count > 0) _log($"Фонові програми пригальмовано: {count} процесів");
    }

    void SetGpuPreference(string exePath)
    {
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(GpuKey, true);
            if (key.GetValue(exePath) != null) return; // користувач уже налаштував сам — не чіпаємо
            key.SetValue(exePath, "GpuPreference=2;");
            _state!.GpuPrefsAdded.Add(exePath);
            _log($"Дискретна відеокарта: {Path.GetFileName(exePath)} (діє з наступного запуску гри)");
        }
        catch { }
    }

    void SaveState()
    {
        try { File.WriteAllText(RestoreFile, JsonSerializer.Serialize(_state)); } catch { }
    }
}
