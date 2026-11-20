using System;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Win32;
using Optimizator.Core;

namespace Optimizator;

public sealed class FanVM : INotifyPropertyChanged
{
    public FanChannel Ch { get; }
    public event Action<FanVM>? Changed;
    public event PropertyChangedEventHandler? PropertyChanged;
    void On([CallerMemberName] string? n = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(n));

    public FanVM(FanChannel ch, bool manual, double percent) { Ch = ch; _manual = manual; _percent = percent; }

    public string Name => Ch.Name;

    string _rpm = "—";
    public string RpmText { get => _rpm; set { if (_rpm != value) { _rpm = value; On(); } } }

    bool _manual;
    public bool Manual { get => _manual; set { if (_manual == value) return; _manual = value; On(); Changed?.Invoke(this); } }

    double _percent;
    public double Percent
    {
        get => _percent;
        set { if (Math.Abs(_percent - value) < 0.5) return; _percent = value; On(); On(nameof(PercentText)); Changed?.Invoke(this); }
    }
    public string PercentText => $"{_percent:0}%";
}

public partial class MainWindow : Window
{
    readonly AppSettings _s = AppSettings.Load();
    readonly Optimizer _opt;
    readonly GameWatcher _watcher;
    readonly FanService _fans = new();
    readonly ObservableCollection<string> _log = new();
    readonly ObservableCollection<GameProfile> _games;
    readonly ObservableCollection<FanVM> _fanVms = new();
    readonly DispatcherTimer _tick = new() { Interval = TimeSpan.FromSeconds(1.5) };
    System.Windows.Forms.NotifyIcon? _tray;
    bool _manualBoost, _failsafe, _exiting;

    public MainWindow()
    {
        InitializeComponent();
        ApplyAccent(_s.Accent);

        _opt = new Optimizer(_s, Log);
        _opt.RecoverAfterCrash();

        _games = new ObservableCollection<GameProfile>(_s.Games);
        GamesList.ItemsSource = _games;
        LogList.ItemsSource = _log;
        FansList.ItemsSource = _fanVms;
        OptionsCard.DataContext = _s;

        FansOnlyInGame.IsChecked = _s.FansOnlyInGame;
        FailsafeSlider.Value = _s.FailsafeTempC;
        AutoStart.IsChecked = _s.StartWithWindows = IsAutostartRegistered();
        ToTray.IsChecked = _s.MinimizeToTray;
        Notify.IsChecked = _s.Notifications;
        var ver = typeof(MainWindow).Assembly.GetName().Version;
        VersionText.Text = $"Optimizator {ver?.ToString(3)} · налаштування: {AppSettings.FilePath}";
        BgApps.Text = string.Join(", ", _s.BackgroundApps);

        _watcher = new GameWatcher(() => _games.ToList());
        _watcher.Started += h => Dispatcher.InvokeAsync(() => OnGameStarted(h));
        _watcher.Stopped += h => Dispatcher.InvokeAsync(() => OnGameStopped(h));
        _watcher.Start();

        SetupTray();
        SystemEvents.SessionEnding += (_, _) => Cleanup();
        AppDomain.CurrentDomain.ProcessExit += (_, _) => Cleanup();

        _tick.Tick += (_, _) => Tick();
        _tick.Start();

        Log("Optimizator запущено — чекаю на гру");
        Task.Run(() => _fans.Open()).ContinueWith(_ => Dispatcher.InvokeAsync(LoadFans));
        UpdateStatus();
    }

    // ================= Ігри та буст =================

    void OnGameStarted(GameHit h)
    {
        Log($"Запущено: {h.GameName} ({h.ProcessName}.exe)");
        _opt.Activate();
        _opt.BoostGame(h);
        UpdateStatus();
        ApplyFans();
        Toast($"Буст увімкнено · {h.GameName}");
    }

    void OnGameStopped(GameHit h)
    {
        Log($"Закрито: {h.GameName}");
        if (!_watcher.Running.Any() && !_manualBoost)
        {
            _opt.Deactivate();
            Toast("Гру закрито — буст вимкнено, система повернута до звичайного режиму");
        }
        UpdateStatus();
        ApplyFans();
    }

    void Toast(string text)
    {
        if (_s.Notifications && !IsVisible)
            _tray?.ShowBalloonTip(3000, "Optimizator", text, System.Windows.Forms.ToolTipIcon.None);
    }

    void ManualBoost(object sender, RoutedEventArgs e)
    {
        _manualBoost = !_manualBoost;
        if (_manualBoost) { _opt.Activate(); Log("Буст увімкнено вручну"); }
        else if (!_watcher.Running.Any()) _opt.Deactivate();
        UpdateStatus();
        ApplyFans();
    }

    void UpdateStatus()
    {
        bool on = _opt.IsActive;
        var games = _watcher.Running.Select(r => r.GameName).Distinct().ToList();
        var accent = (Brush)FindResource("Accent");

        StatusRing.BorderBrush = on ? accent : new SolidColorBrush(Color.FromRgb(0x33, 0x34, 0x3F));
        StatusIcon.Text = on ? "⚡" : "⏸";
        StatusTitle.Text = on ? (games.Count > 0 ? $"Буст активний · {string.Join(", ", games)}" : "Буст активний (вручну)") : "Очікування гри";
        StatusSub.Text = on
            ? "Система працює на максимум. Після закриття гри все повернеться як було."
            : "Запусти Minecraft, Roblox, CS2 або іншу гру — буст увімкнеться сам і вимкнеться після виходу.";
        ManualBtn.Content = _manualBoost ? "Вимкнути" : "Увімкнути зараз";
        SideDot.Fill = on ? (Brush)FindResource("Good") : (Brush)FindResource("Sub");
        SideStatus.Text = on ? "Буст активний" : "Очікування гри";
        if (_tray != null) _tray.Text = on ? "Optimizator — буст активний" : "Optimizator — очікування гри";
    }

    void Log(string msg)
    {
        void Add()
        {
            _log.Insert(0, $"{DateTime.Now:HH:mm:ss}  {msg}");
            while (_log.Count > 40) _log.RemoveAt(_log.Count - 1);
        }
        if (Dispatcher.CheckAccess()) Add(); else Dispatcher.InvokeAsync(Add);
    }

    // ================= Вентилятори =================

    void LoadFans()
    {
        foreach (var ch in _fans.Channels)
        {
            _s.FanManual.TryGetValue(ch.Id, out bool manual);
            double pct = _s.FanPercent.TryGetValue(ch.Id, out float p) ? p : 60;
            var vm = new FanVM(ch, manual, pct);
            vm.Changed += v =>
            {
                _s.FanManual[v.Ch.Id] = v.Manual;
                _s.FanPercent[v.Ch.Id] = (float)v.Percent;
                _s.Save();
                ApplyFans();
            };
            _fanVms.Add(vm);
        }

        if (_fans.Channels.Count == 0)
        {
            FanHint.Text = _fans.Error != null
                ? $"Не вдалося відкрити датчики: {_fans.Error}"
                : "Керовані вентилятори не знайдено. На багатьох ноутбуках виробник дозволяє міняти оберти лише у своїй програмі "
                  + "(Armoury Crate, Lenovo Vantage, MSI Center, OMEN Gaming Hub). Оберти й температури все одно показуються на головній.";
        }
        ApplyFans();
    }

    void ApplyFans()
    {
        bool allowManual = !_failsafe && (!_s.FansOnlyInGame || _opt.IsActive);
        foreach (var vm in _fanVms)
        {
            if (vm.Manual && allowManual) _fans.SetPercent(vm.Ch, (float)vm.Percent);
            else _fans.SetAuto(vm.Ch);
        }
    }

    void Tick()
    {
        _fans.Update();
        CpuTemp.Text = _fans.CpuTemp is float c ? $"{c:0} °C" : "— °C";
        GpuTemp.Text = _fans.GpuTemp is float g ? $"{g:0} °C" : "— °C";

        foreach (var vm in _fanVms)
            vm.RpmText = vm.Ch.Rpm is float r ? $"{r:0} об/хв" : (vm.Ch.CurrentPercent is float cp ? $"{cp:0}%" : "—");

        var rpms = _fanVms.Select(v => v.Ch.Rpm).Concat(_fans.RpmOnly.Select(s => s.Value)).Where(v => v is > 0).ToList();
        FanSummary.Text = rpms.Count > 0 ? $"{rpms.Max():0} об/хв" : (_fanVms.Count > 0 ? $"{_fanVms.Count} шт." : "—");

        float hottest = Math.Max(_fans.CpuTemp ?? 0, _fans.GpuTemp ?? 0);
        if (!_failsafe && hottest >= _s.FailsafeTempC && _fanVms.Any(v => v.Manual))
        {
            _failsafe = true;
            _fans.AllAuto();
            Log($"Перегрів {hottest:0} °C — вентилятори переведено в авто-режим");
        }
        else if (_failsafe && hottest < _s.FailsafeTempC - 8)
        {
            _failsafe = false;
            ApplyFans();
            Log("Температура в нормі — ручні оберти відновлено");
        }
    }

    void FanOff(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is not FanVM vm) return;
        var r = MessageBox.Show(
            "Повністю зупинити цей вентилятор?\n\nПід навантаженням це може перегріти комп'ютер. Захист від перегріву все одно спрацює.",
            "Optimizator", MessageBoxButton.YesNo, MessageBoxImage.Warning);
        if (r == MessageBoxResult.Yes) vm.Percent = 0;
    }

    void AllMax(object sender, RoutedEventArgs e)
    {
        foreach (var vm in _fanVms) { vm.Manual = true; vm.Percent = 100; }
    }

    void AllAuto(object sender, RoutedEventArgs e)
    {
        foreach (var vm in _fanVms) vm.Manual = false;
        _fans.AllAuto();
    }

    void FanOptionChanged(object sender, RoutedEventArgs e)
    {
        _s.FansOnlyInGame = FansOnlyInGame.IsChecked == true;
        _s.Save();
        ApplyFans();
    }

    void FailsafeChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (FailsafeText == null) return;
        _s.FailsafeTempC = (int)e.NewValue;
        FailsafeText.Text = $"{_s.FailsafeTempC} °C";
        _s.Save();
    }

    // ================= Ігри: список =================

    void AddGame(object sender, RoutedEventArgs e)
    {
        string name = NewGameName.Text.Trim(), exe = NewGameExe.Text.Trim();
        if (exe.Length == 0) { MessageBox.Show("Вкажи ім'я процесу гри, наприклад FortniteClient-Win64-Shipping.exe", "Optimizator"); return; }
        if (exe.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) exe = exe[..^4];
        var g = new GameProfile { Name = name.Length > 0 ? name : exe, ProcessNames = { exe } };
        _games.Insert(0, g);
        NewGameName.Clear(); NewGameExe.Clear();
        SaveSettings(this, e);
    }

    void RemoveGame(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is GameProfile g) { _games.Remove(g); SaveSettings(this, e); }
    }

    void SaveSettings(object sender, RoutedEventArgs e)
    {
        _s.Games = _games.ToList();
        _s.Save();
    }

    void BgAppsChanged(object sender, RoutedEventArgs e)
    {
        _s.BackgroundApps = BgApps.Text.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(x => x.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ? x[..^4] : x).Distinct().ToList();
        _s.Save();
    }

    // ================= Налаштування =================

    void PickAccent(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is string hex) { ApplyAccent(hex); _s.Accent = hex; _s.Save(); UpdateStatus(); }
    }

    static void ApplyAccent(string hex)
    {
        try { Application.Current.Resources["Accent"] = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex)); } catch { }
    }

    void AutoStartChanged(object sender, RoutedEventArgs e)
    {
        bool on = AutoStart.IsChecked == true;
        string exe = Environment.ProcessPath ?? "";
        string args = on
            ? $"/Create /TN \"Optimizator\" /TR \"\\\"{exe}\\\" --tray\" /SC ONLOGON /RL HIGHEST /F"
            : "/Delete /TN \"Optimizator\" /F";
        try
        {
            using var p = Process.Start(new ProcessStartInfo("schtasks.exe", args) { CreateNoWindow = true, UseShellExecute = false });
            p?.WaitForExit(5000);
            _s.StartWithWindows = on; _s.Save();
            Log(on ? "Автозапуск увімкнено" : "Автозапуск вимкнено");
        }
        catch (Exception ex) { MessageBox.Show(ex.Message, "Optimizator"); }
    }

    void TrayChanged(object sender, RoutedEventArgs e) { _s.MinimizeToTray = ToTray.IsChecked == true; _s.Save(); }

    void NotifyChanged(object sender, RoutedEventArgs e) { _s.Notifications = Notify.IsChecked == true; _s.Save(); }

    static bool IsAutostartRegistered()
    {
        try
        {
            using var p = Process.Start(new ProcessStartInfo("schtasks.exe", "/Query /TN \"Optimizator\"")
            { CreateNoWindow = true, UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardError = true });
            if (p == null) return false;
            p.StandardOutput.ReadToEnd();
            p.WaitForExit(5000);
            return p.ExitCode == 0;
        }
        catch { return false; }
    }

    // ================= Вікно / трей =================

    void Nav(object sender, RoutedEventArgs e)
    {
        if (PageHome == null) return;
        string tag = (string)((FrameworkElement)sender).Tag;
        foreach (var p in new FrameworkElement[] { PageHome, PageGames, PageFans, PageSettings })
            p.Visibility = p.Name == tag ? Visibility.Visible : Visibility.Collapsed;
    }

    void Drag(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState == MouseButtonState.Pressed && e.OriginalSource is not Button) try { DragMove(); } catch { }
    }

    void Minimize(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;

    void CloseClick(object sender, RoutedEventArgs e) => Close();

    protected override void OnClosing(CancelEventArgs e)
    {
        if (!_exiting && _s.MinimizeToTray)
        {
            e.Cancel = true;
            Hide();
            _tray?.ShowBalloonTip(2000, "Optimizator", "Працюю у треї й чекаю на гру", System.Windows.Forms.ToolTipIcon.None);
            return;
        }
        if (!_exiting)
        {
            _exiting = true;
            Cleanup();
            Dispatcher.InvokeAsync(() => Application.Current.Shutdown());
        }
        base.OnClosing(e);
    }

    void SetupTray()
    {
        _tray = new System.Windows.Forms.NotifyIcon
        {
            Icon = TrayIcon(),
            Text = "Optimizator",
            Visible = true
        };
        var menu = new System.Windows.Forms.ContextMenuStrip();
        menu.Items.Add("Відкрити", null, (_, _) => ShowFromTray());
        menu.Items.Add("Вийти", null, (_, _) => ExitApp());
        _tray.ContextMenuStrip = menu;
        _tray.DoubleClick += (_, _) => ShowFromTray();
    }

    static System.Drawing.Icon TrayIcon()
    {
        try { return System.Drawing.Icon.ExtractAssociatedIcon(Environment.ProcessPath!) ?? System.Drawing.SystemIcons.Application; }
        catch { return System.Drawing.SystemIcons.Application; }
    }

    internal void ShowFromTray()
    {
        Show();
        WindowState = WindowState.Normal;
        Activate();
    }

    internal void ExitApp()
    {
        _exiting = true;
        Cleanup();
        Application.Current.Shutdown();
    }

    bool _cleaned;
    void Cleanup()
    {
        if (_cleaned) return;
        _cleaned = true;
        try { _tick.Stop(); } catch { }
        try { _watcher.Dispose(); } catch { }
        try { _opt.Deactivate(); } catch { }
        try { _fans.Dispose(); } catch { }   // вентилятори завжди повертаються в авто
        try { _s.Save(); } catch { }
        if (_tray != null) { _tray.Visible = false; _tray.Dispose(); }
    }
}
