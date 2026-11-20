import Foundation
import AppKit

/// Вмикає оптимізації на час гри і повертає все назад після виходу.
final class Optimizer {
    private(set) var isActive = false
    private let settings: () -> AppSettings
    private let log: (String) -> Void

    private var lowPowerWasOn = false
    private var activity: NSObjectProtocol?
    private var throttled: [pid_t: Int32] = [:]   // pid -> старий nice
    private var boosted: Set<pid_t> = []

    init(settings: @escaping () -> AppSettings, log: @escaping (String) -> Void) {
        self.settings = settings
        self.log = log
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        let s = settings()

        if s.disableLowPower, Self.lowPowerEnabled() {
            if Helper.run(["lowpower", "0"]) { lowPowerWasOn = true; log("Low Power Mode вимкнено на час гри") }
            else { log("Low Power Mode увімкнений — встанови помічника, щоб вимикати його автоматично") }
        }

        if s.preventSleep {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled, .latencyCritical],
                reason: "Optimizator: гра запущена")
        }

        if s.purgeMemory, Helper.run(["purge"]) { log("Неактивну пам'ять очищено") }
        if s.throttleBackground { throttleBackground(s.backgroundApps) }
    }

    func boost(_ hit: GameHit) {
        guard isActive, settings().gamePriority, !boosted.contains(hit.pid) else { return }
        if Helper.run(["prio", "\(hit.pid)", "-10"]) {
            boosted.insert(hit.pid)
            log("\(hit.gameName): високий пріоритет")
        }
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false

        if lowPowerWasOn { Helper.run(["lowpower", "1"]); lowPowerWasOn = false }
        if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }

        for (pid, nice) in throttled where kill(pid, 0) == 0 {
            Helper.run(["prio", "\(pid)", "\(nice)"])
        }
        throttled.removeAll()
        for pid in boosted where kill(pid, 0) == 0 { Helper.run(["prio", "\(pid)", "0"]) }
        boosted.removeAll()
        log("Буст вимкнено — система повернута до звичайного режиму")
    }

    private func throttleBackground(_ names: [String]) {
        let set = Set(names.map { $0.lowercased() })
        var count = 0
        for pid in GameWatcher.allPids() where pid > 1 {
            guard let path = GameWatcher.path(of: pid) else { continue }
            let name = (path as NSString).lastPathComponent.lowercased()
            guard set.contains(name), throttled[pid] == nil else { continue }
            errno = 0
            let old = getpriority(PRIO_PROCESS, id_t(pid))
            if errno != 0 { continue }
            if Helper.run(["prio", "\(pid)", "10"]) { throttled[pid] = old; count += 1 }
        }
        if count > 0 { log("Фонові програми пригальмовано: \(count) процесів") }
    }

    static func lowPowerEnabled() -> Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }
}
