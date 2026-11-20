// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Optimizator",
    platforms: [.macOS(.v13)],
    targets: [
        // Доступ до SMC (датчики температури, вентилятори) — спільний для програми й помічника
        .target(
            name: "CSMC",
            path: "Sources/CSMC",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        // Маленький root-помічник: оберти вентиляторів, пріоритети, Low Power Mode, очищення RAM
        .executableTarget(
            name: "optimizator-smc",
            dependencies: ["CSMC"],
            path: "Sources/optimizator-smc"
        ),
        // Сама програма (SwiftUI)
        .executableTarget(
            name: "Optimizator",
            dependencies: ["CSMC"],
            path: "Sources/Optimizator"
        ),
    ]
)
