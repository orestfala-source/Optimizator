import Foundation

/// Запуск root-помічника. Встановлюється один раз (один запит пароля), далі працює без запитів.
enum Helper {
    static let installedPath = "/usr/local/libexec/optimizator-smc"

    static var isInstalled: Bool {
        guard let a = try? FileManager.default.attributesOfItem(atPath: installedPath) else { return false }
        let perms = (a[.posixPermissions] as? NSNumber)?.intValue ?? 0
        let owner = (a[.ownerAccountID] as? NSNumber)?.intValue ?? -1
        return owner == 0 && (perms & 0o4000) != 0
    }

    /// Шлях до помічника всередині .app (Contents/Resources/optimizator-smc)
    static var bundledPath: String? {
        if let p = Bundle.main.path(forResource: "optimizator-smc", ofType: nil) { return p }
        let near = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("optimizator-smc").path
        return FileManager.default.fileExists(atPath: near) ? near : nil
    }

    /// Показує системне вікно пароля адміністратора і встановлює помічника.
    /// (Якщо програму встановлено через .pkg, помічник уже стоїть і це не потрібно.)
    @discardableResult
    static func install() -> Bool {
        guard let src = bundledPath else { return false }
        let esc = src.replacingOccurrences(of: "'", with: "'\\''")
        return runAsAdmin("mkdir -p /usr/local/libexec && install -o root -g wheel -m 4755 '\(esc)' \(installedPath)") && isInstalled
    }

    /// Виконати shell-команду з правами адміністратора (системне вікно пароля). false — якщо скасовано.
    static func runAsAdmin(_ shell: String) -> Bool {
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var err: NSDictionary?
        NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")?.executeAndReturnError(&err)
        return err == nil
    }

    @discardableResult
    static func run(_ args: [String]) -> Bool {
        guard isInstalled else { return false }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: installedPath)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
