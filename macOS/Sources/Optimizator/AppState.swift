import Foundation
import SwiftUI
import AppKit
import ServiceManagement

final class AppState: ObservableObject {
    @Published var settings = AppSettings.load() { didSet { settings.save() } }
    @Published var log: [String] = []
    @Published var fans: [FanInfo] = []
    @Published var cpuTemp: Double?
    @Published var gpuTemp: Double?
    @Published var activeGames: [String] = []
    @Published var boostOn = false
    @Published var manualBoost = false
    @Published var helperInstalled = Helper.isInstalled
    @Published var failsafe = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var optimizer: Optimizer!
    private var watcher: GameWatcher!
    private var timer: Timer?
    private let smcOK = SMC.available
    private var sigterm: DispatchSourceSignal?

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var accent: Color { Color(hex: settings.accentHex) }

    init() {
        optimizer = Optimizer(settings: { [unowned self] in self.settings },
                              log: { [unowned self] msg in DispatchQueue.main.async { self.add(msg) } })
        watcher = GameWatcher(games: { [unowned self] in self.settings.games })
        watcher.onStart = { [unowned self] h in self.gameStarted(h) }
        watcher.onStop = { [unowned self] h in self.gameStopped(h) }
        watcher.start()

        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.tick() }
        tick()
        add(smcOK ? "Optimizator запущено — чекаю на гру" : "Optimizator запущено (датчики SMC недоступні)")

        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.shutdown()
        }

        // Оновлення / видалення закриває програму сигналом TERM — теж прибираємо за собою
        signal(SIGTERM, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        src.setEventHandler { [weak self] in self?.shutdown(); exit(0) }
        src.resume()
        sigterm = src
    }

    // MARK: - Буст

    private func gameStarted(_ h: GameHit) {
        add("Запущено: \(h.gameName)")
        optimizer.activate()
        optimizer.boost(h)
        refreshState()
    }

    private func gameStopped(_ h: GameHit) {
        add("Закрито: \(h.gameName)")
        if watcher.runningGames.isEmpty && !manualBoost { optimizer.deactivate() }
        refreshState()
    }

    func toggleManual() {
        manualBoost.toggle()
        if manualBoost { optimizer.activate(); add("Буст увімкнено вручну") }
        else if watcher.runningGames.isEmpty { optimizer.deactivate() }
        refreshState()
    }

    private func refreshState() {
        boostOn = optimizer.isActive
        activeGames = Array(Set(watcher.runningGames.map(\.gameName))).sorted()
        applyFans()
    }

    // MARK: - Вентилятори

    func setManual(_ fan: Int, _ on: Bool) {
        settings.fanManual[fan] = on
        applyFans()
    }

    func setTarget(_ fan: Int, _ rpm: Double) {
        settings.fanTargetRPM[fan] = rpm
        applyFans()
    }

    func allMax() {
        for f in fans { settings.fanManual[f.id] = true; settings.fanTargetRPM[f.id] = f.maxRPM }
        applyFans()
    }

    func allAuto() {
        for f in fans { settings.fanManual[f.id] = false }
        Helper.run(["auto-all"])
    }

    private var lastApplied: [Int: Double?] = [:]

    func applyFans() {
        guard helperInstalled else { return }
        let allow = !failsafe && (!settings.fansOnlyInGame || boostOn)
        var anyManual = false, changed = false
        for f in fans {
            let manual = allow && (settings.fanManual[f.id] ?? false)
            let target: Double? = manual ? (settings.fanTargetRPM[f.id] ?? (f.minRPM + f.maxRPM) / 2) : nil
            if manual { anyManual = true }
            if let last = lastApplied[f.id], last == target { continue }
            lastApplied[f.id] = target
            changed = true
            if let t = target { Helper.run(["set", "\(f.id)", "\(Int(t))"]) }
            else { Helper.run(["auto", "\(f.id)"]) }
        }
        // Усі вентилятори знову автоматичні — повністю віддаємо керування системі
        if changed && !anyManual { Helper.run(["auto-all"]) }
    }

    private func tick() {
        guard smcOK else { return }
        let newFans = SMC.fans()
        let countChanged = newFans.count != fans.count
        if newFans != fans { fans = newFans }
        if countChanged { applyFans() }
        cpuTemp = SMC.maxTemp(SMC.cpuKeys)
        gpuTemp = SMC.maxTemp(SMC.gpuKeys)

        let hottest = max(cpuTemp ?? 0, gpuTemp ?? 0)
        let anyManual = settings.fanManual.values.contains(true)
        if !failsafe && anyManual && hottest >= settings.failsafeTemp {
            failsafe = true
            lastApplied.removeAll()
            Helper.run(["auto-all"])
            add("Перегрів \(Int(hottest)) °C — вентилятори в авто-режимі")
        } else if failsafe && hottest < settings.failsafeTemp - 8 {
            failsafe = false
            lastApplied.removeAll()
            applyFans()
            add("Температура в нормі — ручні оберти відновлено")
        }
    }

    // MARK: - Інше

    func installHelper() {
        helperInstalled = Helper.install()
        add(helperInstalled ? "Помічник встановлено" : "Помічника не встановлено")
        lastApplied.removeAll()
        applyFans()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { add("Автозапуск: \(error.localizedDescription)") }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func add(_ msg: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        log.insert("\(f.string(from: Date()))  \(msg)", at: 0)
        if log.count > 40 { log.removeLast(log.count - 40) }
    }

    private var didShutdown = false

    func shutdown() {
        guard !didShutdown else { return }
        didShutdown = true
        timer?.invalidate()
        optimizer.deactivate()
        Helper.run(["auto-all"])
    }

    /// Повне видалення: вентилятори в авто, прибрати помічника, програму, налаштування й автозапуск.
    func uninstall() {
        let appPath = Bundle.main.bundlePath.replacingOccurrences(of: "'", with: "'\\''")
        let cmd = "\(Helper.installedPath) auto-all >/dev/null 2>&1; rm -f \(Helper.installedPath); "
                + "rm -rf '\(appPath)'; pkgutil --forget com.optimizator.app >/dev/null 2>&1; true"
        optimizer.deactivate()
        Helper.run(["auto-all"])
        guard Helper.runAsAdmin(cmd) else { add("Видалення скасовано"); return }
        try? SMAppService.mainApp.unregister()
        try? FileManager.default.removeItem(at: AppSettings.fileURL.deletingLastPathComponent())
        didShutdown = true
        NSApp.terminate(nil)
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0x8B5CF6
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
