import Foundation

struct GameProfile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// Ім'я виконуваного файлу (останній компонент шляху), регістр не важливий
    var processNames: [String]
    /// Для java: процес рахується грою, якщо в аргументах є хоча б одне слово
    var commandLineAny: [String] = []
    var enabled = true
}

struct AppSettings: Codable {
    // Оптимізації — діють тільки поки гра запущена
    var disableLowPower = true
    var gamePriority = true
    var throttleBackground = true
    var preventSleep = true
    var purgeMemory = false

    var backgroundApps: [String] = [
        "Google Chrome Helper", "Google Chrome", "Safari", "Firefox", "Opera", "Brave Browser",
        "Discord", "Discord Helper", "Telegram", "Spotify", "Steam Helper", "OneDrive",
        "Dropbox", "photoanalysisd", "mediaanalysisd", "Microsoft Teams"
    ]

    var games: [GameProfile] = AppSettings.defaultGames

    // Вентилятори
    var fansOnlyInGame = true
    var failsafeTemp: Double = 95
    var fanManual: [Int: Bool] = [:]
    var fanTargetRPM: [Int: Double] = [:]

    // Інтерфейс
    var accentHex = "#8B5CF6"

    static let defaultGames: [GameProfile] = [
        GameProfile(name: "Minecraft Java (Zontas / Fabric / ванільний)", processNames: ["java"],
                    commandLineAny: ["minecraft", "fabricmc", "zontas"]),
        GameProfile(name: "Roblox", processNames: ["RobloxPlayer"]),
        GameProfile(name: "Counter-Strike 2 (через CrossOver / Whisky)", processNames: ["cs2.exe", "cs2"]),
        GameProfile(name: "CS:GO (legacy)", processNames: ["csgo_osx64"]),
        GameProfile(name: "Dota 2", processNames: ["dota2"]),
        GameProfile(name: "League of Legends", processNames: ["League of Legends", "LeagueofLegends"]),
        GameProfile(name: "World of Warcraft", processNames: ["World of Warcraft"]),
        GameProfile(name: "Genshin Impact", processNames: ["Genshin Impact", "GenshinImpact"]),
    ]

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Optimizator", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    static func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let s = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return s
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = .prettyPrinted
        if let data = try? enc.encode(self) { try? data.write(to: AppSettings.fileURL, options: .atomic) }
    }
}
