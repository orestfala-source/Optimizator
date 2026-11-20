using System;
using System.Linq;
using System.Threading;
using System.Windows;

namespace Optimizator;

public partial class App : Application
{
    const string MutexName = "Global\\Optimizator.Single";
    const string ShowEventName = "Global\\Optimizator.Show";
    const string ExitEventName = "Global\\Optimizator.Exit";

    Mutex? _single;
    bool _ownsMutex;
    EventWaitHandle? _showEvent, _exitEvent;
    RegisteredWaitHandle? _showWait, _exitWait;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        bool Has(string a) => e.Args.Any(x => x.Equals(a, StringComparison.OrdinalIgnoreCase));

        // Інсталер / деінсталятор просить запущену копію коректно закритись
        // (повернути схему живлення та вентилятори в авто).
        if (Has("--shutdown"))
        {
            Signal(ExitEventName);
            try
            {
                using var m = new Mutex(false, MutexName);
                if (m.WaitOne(10000)) m.ReleaseMutex();
            }
            catch (AbandonedMutexException) { }
            catch { }
            Shutdown();
            return;
        }

        _single = new Mutex(true, MutexName, out _ownsMutex);
        if (!_ownsMutex)
        {
            // Програма вже працює (у треї) — просто показуємо її вікно
            Signal(ShowEventName);
            Shutdown();
            return;
        }

        var w = new MainWindow();
        MainWindow = w;

        _showEvent = new EventWaitHandle(false, EventResetMode.AutoReset, ShowEventName);
        _exitEvent = new EventWaitHandle(false, EventResetMode.AutoReset, ExitEventName);
        _showWait = ThreadPool.RegisterWaitForSingleObject(_showEvent,
            (_, _) => Dispatcher.InvokeAsync(w.ShowFromTray), null, Timeout.Infinite, false);
        _exitWait = ThreadPool.RegisterWaitForSingleObject(_exitEvent,
            (_, _) => Dispatcher.InvokeAsync(w.ExitApp), null, Timeout.Infinite, true);

        if (!Has("--tray")) w.Show();
    }

    static void Signal(string name)
    {
        try { using var ev = EventWaitHandle.OpenExisting(name); ev.Set(); } catch { }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _showWait?.Unregister(null);
        _exitWait?.Unregister(null);
        _showEvent?.Dispose();
        _exitEvent?.Dispose();
        if (_ownsMutex) try { _single?.ReleaseMutex(); } catch { }
        _single?.Dispose();
        base.OnExit(e);
    }
}
