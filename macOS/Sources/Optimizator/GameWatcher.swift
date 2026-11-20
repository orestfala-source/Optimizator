import Foundation
import Darwin

struct GameHit: Hashable {
    let pid: pid_t
    let gameName: String
    let processName: String
}

/// Раз на 2 секунди переглядає процеси. Аргументи читаються лише для нових java-процесів.
final class GameWatcher {
    var onStart: ((GameHit) -> Void)?
    var onStop: ((GameHit) -> Void)?

    private let games: () -> [GameProfile]
    private var running: [pid_t: GameHit] = [:]
    private var javaCache: [pid_t: Bool] = [:]
    private var timer: Timer?
    private let queue = DispatchQueue(label: "optimizator.watcher", qos: .utility)

    init(games: @escaping () -> [GameProfile]) { self.games = games }

    var runningGames: [GameHit] { queue.sync { Array(running.values) } }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let profiles = self.games().filter(\.enabled)
            self.queue.async { self.tick(profiles) }
        }
        timer?.fire()
    }

    private func tick(_ profiles: [GameProfile]) {
        var map: [String: GameProfile] = [:]
        for g in profiles { for n in g.processNames { map[n.lowercased()] = map[n.lowercased()] ?? g } }

        var alive = Set<pid_t>()
        var started: [GameHit] = []

        for pid in Self.allPids() where pid > 0 {
            guard let path = Self.path(of: pid) else { continue }
            let name = (path as NSString).lastPathComponent
            guard let profile = map[name.lowercased()] else { continue }

            if !profile.commandLineAny.isEmpty {
                let isGame: Bool
                if let c = javaCache[pid] { isGame = c } else {
                    let cmd = (Self.commandLine(of: pid) ?? "").lowercased()
                    isGame = profile.commandLineAny.contains { cmd.contains($0.lowercased()) } && !cmd.contains("nogui") // сервери — не гра
                    javaCache[pid] = isGame
                }
                if !isGame { continue }
            }

            alive.insert(pid)
            if running[pid] == nil {
                let hit = GameHit(pid: pid, gameName: profile.name, processName: name)
                running[pid] = hit
                started.append(hit)
            }
        }

        let stopped = running.values.filter { !alive.contains($0.pid) }
        for h in stopped { running[h.pid] = nil }
        javaCache = javaCache.filter { kill($0.key, 0) == 0 }

        DispatchQueue.main.async {
            started.forEach { self.onStart?($0) }
            stopped.forEach { self.onStop?($0) }
        }
    }

    // MARK: - Низькорівневе читання процесів

    static func allPids() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 64)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return Array(pids.prefix(Int(max(n, 0))))
    }

    static func path(of pid: pid_t) -> String? {
        var buf = [CChar](repeating: 0, count: 4096)
        let r = proc_pidpath(pid, &buf, UInt32(buf.count))
        return r > 0 ? String(cString: buf) : nil
    }

    static func commandLine(of pid: pid_t) -> String? {
        var argmax: Int32 = 0
        var size = MemoryLayout<Int32>.size
        var mibMax: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&mibMax, 2, &argmax, &size, nil, 0) == 0, argmax > 0 else { return nil }

        var buf = [UInt8](repeating: 0, count: Int(argmax))
        var len = Int(argmax)
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &buf, &len, nil, 0) == 0, len > 4 else { return nil }
        let bytes = buf[4..<len].map { $0 == 0 ? UInt8(ascii: " ") : $0 }
        return String(decoding: bytes, as: UTF8.self)
    }
}
