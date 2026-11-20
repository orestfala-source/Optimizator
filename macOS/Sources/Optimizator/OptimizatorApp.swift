import SwiftUI
import AppKit

@main
struct OptimizatorApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        Window("Optimizator", id: "main") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 920, minHeight: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuPanel().environmentObject(state)
        } label: {
            Image(systemName: state.boostOn ? "bolt.fill" : "bolt")
        }
        .menuBarExtraStyle(.window)
    }
}
