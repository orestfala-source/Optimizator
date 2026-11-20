import SwiftUI
import AppKit

enum Theme {
    static let bg = Color(red: 0.055, green: 0.059, blue: 0.075)
    static let side = Color(red: 0.075, green: 0.078, blue: 0.10)
    static let card = Color(red: 0.10, green: 0.106, blue: 0.133)
    static let stroke = Color.white.opacity(0.07)
    static let sub = Color(red: 0.55, green: 0.55, blue: 0.60)
    static let swatches = ["#8B5CF6", "#22C55E", "#FACC15", "#3B82F6", "#EF4444", "#EC4899", "#F97316"]
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.stroke))
    }
}

struct OptionToggle: View {
    let title: String, subtitle: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(Theme.sub)
            }
        }
        .toggleStyle(.switch)
    }
}

struct AccentButton: ButtonStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

struct GhostButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5))
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

enum Page: String, CaseIterable, Identifiable {
    case home = "Головна", games = "Ігри", fans = "Вентилятори", settings = "Налаштування"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .home: return "bolt.fill"
        case .games: return "gamecontroller.fill"
        case .fans: return "fanblades.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

// MARK: - Головне вікно

struct ContentView: View {
    @EnvironmentObject var st: AppState
    @State private var page: Page = .home

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(page.rawValue).font(.system(size: 26, weight: .semibold)).padding(.bottom, 4)
                    switch page {
                    case .home: HomePage()
                    case .games: GamesPage()
                    case .fans: FansPage()
                    case .settings: SettingsPage()
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.bg)
        .tint(st.accent)
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(st.accent)
                    .frame(width: 36, height: 36)
                    .overlay(Text("O").font(.system(size: 19, weight: .bold)).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Optimizator").font(.system(size: 15, weight: .semibold))
                    Text("FPS optimizer").font(.caption).foregroundStyle(Theme.sub)
                }
            }
            .padding(.bottom, 24).padding(.leading, 6)

            ForEach(Page.allCases) { p in
                Button { page = p } label: {
                    HStack(spacing: 10) {
                        Image(systemName: p.icon).frame(width: 18)
                        Text(p.rawValue)
                        Spacer()
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .foregroundStyle(page == p ? Color.white : Theme.sub)
                    .background(page == p ? Color.white.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            HStack(spacing: 8) {
                Circle().fill(st.boostOn ? Color.green : Theme.sub).frame(width: 8, height: 8)
                Text(st.boostOn ? "Буст активний" : "Очікування гри").font(.caption).foregroundStyle(Theme.sub)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(16).padding(.top, 20)
        .frame(width: 220)
        .background(Theme.side)
    }
}

// MARK: - Головна

struct HomePage: View {
    @EnvironmentObject var st: AppState

    var body: some View {
        Card {
            HStack(spacing: 18) {
                Circle().stroke(st.boostOn ? st.accent : Color.white.opacity(0.15), lineWidth: 3)
                    .frame(width: 60, height: 60)
                    .overlay(Image(systemName: st.boostOn ? "bolt.fill" : "pause.fill").font(.system(size: 22)))
                VStack(alignment: .leading, spacing: 4) {
                    Text(st.boostOn ? (st.activeGames.isEmpty ? "Буст активний (вручну)" : "Буст активний · \(st.activeGames.joined(separator: ", "))")
                                    : "Очікування гри")
                        .font(.system(size: 18, weight: .semibold))
                    Text(st.boostOn ? "Mac працює на максимум. Після закриття гри все повернеться як було."
                                    : "Запусти Minecraft, Roblox або іншу гру — буст увімкнеться сам і вимкнеться після виходу.")
                        .font(.callout).foregroundStyle(Theme.sub)
                }
                Spacer()
                Button(st.manualBoost ? "Вимкнути" : "Увімкнути зараз") { st.toggleManual() }
                    .buttonStyle(AccentButton(color: st.accent))
            }
        }

        HStack(spacing: 12) {
            stat("CPU", st.cpuTemp.map { "\(Int($0)) °C" } ?? "—")
            stat("GPU", st.gpuTemp.map { "\(Int($0)) °C" } ?? "—")
            stat("Вентилятори", st.fans.map(\.rpm).max().map { "\(Int($0)) об/хв" } ?? "—")
        }

        if !st.helperInstalled {
            Card {
                Text("Потрібен помічник").font(.headline)
                Text("Щоб змінювати оберти вентиляторів, пріоритет гри та Low Power Mode, встанови помічника. macOS один раз попросить пароль.")
                    .font(.callout).foregroundStyle(Theme.sub)
                Button("Встановити помічника") { st.installHelper() }.buttonStyle(AccentButton(color: st.accent))
            }
        }

        Card {
            Text("Що вмикається під час гри").font(.headline)
            OptionToggle(title: "Вимкнути Low Power Mode", subtitle: "Процесор і графіка без обмежень енергозбереження", isOn: $st.settings.disableLowPower)
            OptionToggle(title: "Високий пріоритет гри", subtitle: "Гра отримує процесорний час першою", isOn: $st.settings.gamePriority)
            OptionToggle(title: "Пригальмувати фонові програми", subtitle: "Браузери, Discord, Spotify тощо — нижчий пріоритет, не закриваються", isOn: $st.settings.throttleBackground)
            OptionToggle(title: "Не засинати під час гри", subtitle: "Mac не засне, навіть якщо граєш з геймпадом", isOn: $st.settings.preventSleep)
            OptionToggle(title: "Очистити неактивну пам'ять", subtitle: "Корисно на Mac з 8 ГБ RAM", isOn: $st.settings.purgeMemory)
        }

        Card {
            Text("Журнал").font(.headline)
            ForEach(Array(st.log.enumerated()), id: \.offset) { _, line in
                Text(line).font(.caption.monospaced()).foregroundStyle(Theme.sub)
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        Card {
            Text(title).font(.caption).foregroundStyle(Theme.sub)
            Text(value).font(.system(size: 22, weight: .semibold))
        }
    }
}

// MARK: - Ігри

struct GamesPage: View {
    @EnvironmentObject var st: AppState
    @State private var newName = ""
    @State private var newProc = ""

    var body: some View {
        Text("Буст вмикається, коли запущена будь-яка увімкнена гра. Minecraft через лаунчер Zontas визначається автоматично.")
            .font(.callout).foregroundStyle(Theme.sub)

        Card {
            HStack {
                TextField("Назва гри", text: $newName).textFieldStyle(.roundedBorder)
                TextField("Ім'я процесу (з Моніторингу системи)", text: $newProc).textFieldStyle(.roundedBorder)
                Button("Додати") {
                    let proc = newProc.trimmingCharacters(in: .whitespaces)
                    guard !proc.isEmpty else { return }
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    st.settings.games.insert(GameProfile(name: name.isEmpty ? proc : name, processNames: [proc]), at: 0)
                    newName = ""; newProc = ""
                }
                .buttonStyle(AccentButton(color: st.accent))
            }
        }

        ForEach(st.settings.games) { g in
            Card {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.name).font(.system(size: 14, weight: .semibold))
                        Text(g.processNames.joined(separator: ", ")).font(.caption).foregroundStyle(Theme.sub)
                    }
                    Spacer()
                    Button("Видалити") { st.settings.games.removeAll { $0.id == g.id } }.buttonStyle(GhostButton())
                    Toggle("", isOn: Binding(
                        get: { g.enabled },
                        set: { v in
                            if let i = st.settings.games.firstIndex(where: { $0.id == g.id }) { st.settings.games[i].enabled = v }
                        }))
                    .toggleStyle(.switch).labelsHidden()
                }
            }
        }
    }
}

// MARK: - Вентилятори

struct FansPage: View {
    @EnvironmentObject var st: AppState

    var body: some View {
        Text("Перемикач вмикає ручне керування. Вимкнений — вентилятор працює автоматично, як задумав Apple.")
            .font(.callout).foregroundStyle(Theme.sub)

        Card {
            OptionToggle(title: "Ручні оберти лише під час гри", subtitle: "Після виходу з гри вентилятори повертаються в авто",
                         isOn: Binding(get: { st.settings.fansOnlyInGame },
                                       set: { st.settings.fansOnlyInGame = $0; st.applyFans() }))
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Захист від перегріву")
                    Text("Якщо CPU або GPU гарячіші — всі вентилятори одразу в авто").font(.caption).foregroundStyle(Theme.sub)
                }
                Spacer()
                Slider(value: $st.settings.failsafeTemp, in: 75...105, step: 1).frame(width: 160)
                Text("\(Int(st.settings.failsafeTemp)) °C").frame(width: 54, alignment: .trailing)
            }
            HStack {
                Button("Всі на максимум") { st.allMax() }.buttonStyle(GhostButton())
                Button("Всі в авто") { st.allAuto() }.buttonStyle(GhostButton())
            }
            if st.failsafe {
                Label("Спрацював захист від перегріву", systemImage: "thermometer.high").foregroundStyle(.orange)
            }
        }

        if st.fans.isEmpty {
            Card { Text("Вентиляторів не знайдено (наприклад, MacBook Air без вентилятора).").foregroundStyle(Theme.sub) }
        }
        ForEach(st.fans) { f in FanRow(fan: f) }
    }
}

struct FanRow: View {
    @EnvironmentObject var st: AppState
    let fan: FanInfo
    @State private var target: Double = 0

    var body: some View {
        let manual = st.settings.fanManual[fan.id] ?? false
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(fan.name).font(.system(size: 14, weight: .semibold))
                    Text("\(Int(fan.rpm)) об/хв · діапазон \(Int(fan.minRPM))–\(Int(fan.maxRPM))").font(.caption).foregroundStyle(Theme.sub)
                }
                Spacer()
                Toggle("Ручне", isOn: Binding(get: { manual }, set: { st.setManual(fan.id, $0) }))
                    .toggleStyle(.switch)
                    .disabled(!st.helperInstalled)
            }
            HStack {
                Slider(value: $target, in: fan.minRPM...max(fan.maxRPM, fan.minRPM + 1), onEditingChanged: { editing in
                    if !editing { st.setTarget(fan.id, target) }
                })
                Text("\(Int(target))").frame(width: 56, alignment: .trailing)
                Button("Мінімум") { target = fan.minRPM; st.setTarget(fan.id, target) }.buttonStyle(GhostButton())
            }
            .disabled(!manual || !st.helperInstalled)
            .opacity(manual ? 1 : 0.45)
        }
        .onAppear { target = st.settings.fanTargetRPM[fan.id] ?? (fan.minRPM + fan.maxRPM) / 2 }
    }
}

// MARK: - Налаштування

struct SettingsPage: View {
    @EnvironmentObject var st: AppState
    @State private var bgText = ""
    @State private var confirmUninstall = false

    var body: some View {
        Card {
            Text("Колір акценту").font(.headline)
            HStack(spacing: 10) {
                ForEach(Theme.swatches, id: \.self) { hex in
                    Circle().fill(Color(hex: hex)).frame(width: 30, height: 30)
                        .overlay(Circle().stroke(.white, lineWidth: st.settings.accentHex == hex ? 2 : 0))
                        .onTapGesture { st.settings.accentHex = hex }
                }
            }
        }

        Card {
            OptionToggle(title: "Запускати під час входу", subtitle: "Тихо працює в рядку меню і чекає на гру",
                         isOn: Binding(get: { st.launchAtLogin }, set: { st.setLaunchAtLogin($0) }))
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Помічник")
                    Text(st.helperInstalled ? "Встановлено: /usr/local/libexec/optimizator-smc" : "Не встановлено")
                        .font(.caption).foregroundStyle(Theme.sub)
                }
                Spacer()
                Button(st.helperInstalled ? "Перевстановити" : "Встановити") { st.installHelper() }.buttonStyle(GhostButton())
            }
        }

        Card {
            Text("Фонові програми, які пригальмовуються").font(.headline)
            Text("Імена процесів через кому. Вони не закриваються — лише отримують нижчий пріоритет поки ти граєш.")
                .font(.caption).foregroundStyle(Theme.sub)
            TextField("", text: $bgText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
                .onSubmit(saveBg)
            Button("Зберегти список", action: saveBg).buttonStyle(GhostButton())
        }
        .onAppear { bgText = st.settings.backgroundApps.joined(separator: ", ") }

        Card {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Optimizator").font(.headline)
                    Text("Версія \(AppState.version) · налаштування: ~/Library/Application Support/Optimizator")
                        .font(.caption).foregroundStyle(Theme.sub)
                }
                Spacer()
                Button("Видалити Optimizator") { confirmUninstall = true }
                    .buttonStyle(GhostButton())
                    .foregroundStyle(.red)
            }
        }
        .alert("Видалити Optimizator?", isPresented: $confirmUninstall) {
            Button("Видалити", role: .destructive) { st.uninstall() }
            Button("Скасувати", role: .cancel) {}
        } message: {
            Text("Вентилятори повернуться в автоматичний режим, програма, помічник і налаштування будуть видалені.")
        }
    }

    private func saveBg() {
        st.settings.backgroundApps = bgText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}

// MARK: - Рядок меню

struct MenuPanel: View {
    @EnvironmentObject var st: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(st.boostOn ? Color.green : Theme.sub).frame(width: 8, height: 8)
                Text(st.boostOn ? "Буст активний" : "Очікування гри").font(.headline)
            }
            if !st.activeGames.isEmpty { Text(st.activeGames.joined(separator: ", ")).font(.caption).foregroundStyle(Theme.sub) }
            HStack {
                Text("CPU \(st.cpuTemp.map { "\(Int($0))°" } ?? "—")")
                Text("GPU \(st.gpuTemp.map { "\(Int($0))°" } ?? "—")")
                Text("Fan \(st.fans.map(\.rpm).max().map { "\(Int($0))" } ?? "—")")
            }
            .font(.caption.monospaced())
            Button(st.manualBoost ? "Вимкнути буст" : "Увімкнути буст") { st.toggleManual() }
                .buttonStyle(AccentButton(color: st.accent))
            HStack {
                Button("Відкрити") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }.buttonStyle(GhostButton())
                Button("Вийти") { st.shutdown(); NSApp.terminate(nil) }.buttonStyle(GhostButton())
            }
        }
        .padding(16)
        .frame(width: 260)
        .tint(st.accent)
        .preferredColorScheme(.dark)
    }
}
