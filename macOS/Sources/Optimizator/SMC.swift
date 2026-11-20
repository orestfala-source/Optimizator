import Foundation
import CSMC

struct FanInfo: Identifiable, Equatable {
    let id: Int
    var rpm: Double
    var minRPM: Double
    var maxRPM: Double
    var name: String { id == 0 ? "Лівий / основний вентилятор" : (id == 1 ? "Правий вентилятор" : "Вентилятор \(id + 1)") }
}

/// Читання SMC (без root). Запис робить помічник optimizator-smc.
enum SMC {
    static let cpuKeys = ["TC0P", "TC0D", "TC0E", "TC0F", "TCXC",          // Intel
                          "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0T", "Tp0b",  // M1 / M2
                          "Tp0f", "Tp0j", "Te05", "Tf04", "Tf09", "Tf0A"]  // M3 / M4
    static let gpuKeys = ["TG0P", "TG0D", "TG0E", "Tg05", "Tg0D", "Tg0f", "Tg0j", "Tg0L", "Tf14", "Tf18"]

    static var available: Bool { smc_open() == 0 }

    static func number(_ key: String) -> Double? {
        var v: Double = 0
        return key.withCString { smc_read_number($0, &v) } == 0 ? v : nil
    }

    static func fans() -> [FanInfo] {
        let n = Int(smc_fan_count())
        return (0..<n).map { i in
            FanInfo(id: i,
                    rpm: number("F\(i)Ac") ?? 0,
                    minRPM: number("F\(i)Mn") ?? 0,
                    maxRPM: number("F\(i)Mx") ?? 6000)
        }
    }

    static func maxTemp(_ keys: [String]) -> Double? {
        let best = keys.compactMap { number($0) }.filter { $0 > 5 && $0 < 125 }.max()
        return best
    }
}
