using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

namespace Optimizator.Core;

public sealed class GameProfile
{
    public string Name { get; set; } = "";
    /// <summary>Імена процесів без .exe (регістр не важливий).</summary>
    public List<string> ProcessNames { get; set; } = new();
    /// <summary>Якщо задано — процес рахується грою лише коли його командний рядок містить хоча б одне слово (для java).</summary>
    public List<string> CommandLineAny { get; set; } = new();
    public bool Enabled { get; set; } = true;
    public string ProcessesText => string.Join(", ", ProcessNames);
}

public sealed class AppSettings
{
    // ---- Оптимізації, які вмикаються тільки поки гра запущена ----
    public bool PowerPlan { get; set; } = true;          // Висока продуктивність + режим "Найкраща продуктивність"
    public bool GamePriority { get; set; } = true;       // Високий пріоритет процесу гри
    public bool DisableEcoQoS { get; set; } = true;      // Вимкнути енергозбереження Windows для гри
    public bool TimerResolution { get; set; } = true;    // Таймер 0.5 мс (рівніший frametime)
    public bool ThrottleBackground { get; set; } = true; // Знизити пріоритет фонових програм
    public bool PurgeStandby { get; set; } = false;      // Очистити кеш RAM при старті гри
    public bool GpuHighPerformance { get; set; } = true; // Дискретна відеокарта для гри (ноутбуки)

    public List<string> BackgroundApps { get; set; } = new()
    {
        "chrome", "msedge", "firefox", "opera", "opera_gx", "brave", "yandex",
        "OneDrive", "Teams", "ms-teams", "steamwebhelper", "EpicGamesLauncher",
        "EADesktop", "Spotify", "Telegram", "AdobeARM", "SearchApp"
    };

    public List<GameProfile> Games { get; set; } = DefaultGames();

    // ---- Вентилятори ----
    public bool FansOnlyInGame { get; set; } = true;
    public int FailsafeTempC { get; set; } = 90;
    public Dictionary<string, float> FanPercent { get; set; } = new();
    public Dictionary<string, bool> FanManual { get; set; } = new();

    // ---- Інтерфейс ----
    public string Accent { get; set; } = "#8B5CF6";
    public bool StartWithWindows { get; set; } = false;
    public bool MinimizeToTray { get; set; } = true;
    public bool Notifications { get; set; } = true;

    public static List<GameProfile> DefaultGames() => new()
    {
        new() { Name = "Minecraft Java (Zontas / Fabric / ванільний)", ProcessNames = { "javaw", "java" },
                CommandLineAny = { "minecraft", "fabricmc", "zontas", "net.minecraft" } },
        new() { Name = "Minecraft Bedrock", ProcessNames = { "Minecraft.Windows" } },
        new() { Name = "Roblox", ProcessNames = { "RobloxPlayerBeta", "Windows10Universal" } },
        new() { Name = "Counter-Strike 2", ProcessNames = { "cs2" } },
        new() { Name = "CS:GO", ProcessNames = { "csgo" } },
        new() { Name = "Valorant", ProcessNames = { "VALORANT-Win64-Shipping" } },
        new() { Name = "Fortnite", ProcessNames = { "FortniteClient-Win64-Shipping" } },
        new() { Name = "Dota 2", ProcessNames = { "dota2" } },
        new() { Name = "GTA V", ProcessNames = { "GTA5", "GTA5_Enhanced" } },
        new() { Name = "Apex Legends", ProcessNames = { "r5apex", "r5apex_dx12" } },
        new() { Name = "Rust", ProcessNames = { "RustClient" } },
        new() { Name = "PUBG", ProcessNames = { "TslGame" } },
        new() { Name = "League of Legends", ProcessNames = { "League of Legends" } },
        new() { Name = "Overwatch 2", ProcessNames = { "Overwatch" } },
    };

    /// <summary>
    /// Папка даних: поруч з програмою (наприклад D:\Optimizator), а якщо програма стоїть у Program Files —
    /// у %LocalAppData%\Optimizator, як годиться звичайній встановленій програмі.
    /// </summary>
    public static string DataDir
    {
        get
        {
            string baseDir = AppContext.BaseDirectory;
            string pf = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            string pf86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
            bool inProgramFiles = (pf.Length > 0 && baseDir.StartsWith(pf, StringComparison.OrdinalIgnoreCase))
                               || (pf86.Length > 0 && baseDir.StartsWith(pf86, StringComparison.OrdinalIgnoreCase));
            string dir = inProgramFiles
                ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Optimizator")
                : baseDir;
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static string FilePath => Path.Combine(DataDir, "settings.json");
    static readonly JsonSerializerOptions Json = new() { WriteIndented = true };

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath), Json) ?? new AppSettings();
        }
        catch { /* пошкоджений файл — беремо стандартні */ }
        return new AppSettings();
    }

    public void Save()
    {
        try { File.WriteAllText(FilePath, JsonSerializer.Serialize(this, Json)); } catch { }
    }
}
