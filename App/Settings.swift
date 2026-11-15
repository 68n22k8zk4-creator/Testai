import SwiftUI

// MARK: - Настройки (сохраняются в UserDefaults и переживают перезапуск)
@MainActor
final class AppSettings: ObservableObject {
    private let d = UserDefaults.standard

    @Published var animations: Bool { didSet { d.set(animations, forKey: "anim.on") } }
    @Published var speed: Int { didSet { d.set(speed, forKey: "anim.speed") } }          // 0 медленная, 1 стандартная, 2 быстрая
    @Published var backgroundAnim: Bool { didSet { d.set(backgroundAnim, forKey: "bg.on") } }
    @Published var respectReduceMotion: Bool { didSet { d.set(respectReduceMotion, forKey: "reduceMotion.respect") } }
    @Published var haptics: Bool { didSet { d.set(haptics, forKey: "haptics") } }
    @Published var theme: ThemeChoice { didSet { d.set(theme.rawValue, forKey: "theme") } }

    init() {
        animations = d.object(forKey: "anim.on") as? Bool ?? true
        speed = d.object(forKey: "anim.speed") as? Int ?? 1
        backgroundAnim = d.object(forKey: "bg.on") as? Bool ?? true
        respectReduceMotion = d.object(forKey: "reduceMotion.respect") as? Bool ?? true
        haptics = d.object(forKey: "haptics") as? Bool ?? true
        theme = ThemeChoice(rawValue: d.string(forKey: "theme") ?? "") ?? .night
    }

    var duration: Double {
        switch speed { case 0: 0.55; case 2: 0.18; default: 0.32 }
    }

    /// nil — переход мгновенный (анимации выключены)
    func transitionAnimation(reduceMotion: Bool) -> Animation? {
        guard animations else { return nil }
        let d = (reduceMotion && respectReduceMotion) ? min(duration, 0.2) : duration
        return .easeInOut(duration: d)
    }
}

struct SettingsView: View {
    @EnvironmentObject var s: AppSettings
    @EnvironmentObject var plus: PlusStore
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var paywall = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button { paywall = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "crown.fill").foregroundStyle(Theme.orange).font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Flamio+").font(.headline)
                                Text(plus.isPlus ? "Подписка активна" : "Анализ расходов, темы, эксклюзивная одежда")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("Тема оформления") {
                    HStack(spacing: 10) {
                        ForEach(ThemeChoice.allCases) { t in
                            let locked = t.plus && !plus.isPlus
                            Button {
                                if locked { paywall = true } else { s.theme = t; Haptics.select() }
                            } label: {
                                VStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(LinearGradient(colors: [t.palette.glowA, t.palette.top, t.palette.bottom], startPoint: .topTrailing, endPoint: .bottomLeading))
                                        .frame(height: 46)
                                        .overlay(alignment: .topTrailing) { if locked { PlusBadge().padding(3) } }
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(s.theme == t ? Theme.orange : .clear, lineWidth: 2))
                                    Text(t.title).font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    Toggle("Анимации интерфейса", isOn: $s.animations)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Скорость переходов").font(.subheadline)
                        Picker("Скорость", selection: $s.speed) {
                            Text("Медленная").tag(0)
                            Text("Стандартная").tag(1)
                            Text("Быстрая").tag(2)
                        }
                        .pickerStyle(.segmented)
                    }
                    .disabled(!s.animations)
                    .opacity(s.animations ? 1 : 0.5)
                    Toggle("Анимированный фон", isOn: $s.backgroundAnim)
                    Toggle("Учитывать «Уменьшение движения»", isOn: $s.respectReduceMotion)
                } header: { Text("Анимации") } footer: {
                    Text(reduce
                         ? "В iOS сейчас включено «Уменьшение движения»: фон неподвижен, переходы только плавное появление."
                         : "Фон останавливается в режиме энергосбережения и когда приложение не на экране.")
                }

                Section("Отклик") {
                    Toggle("Тактильная отдача", isOn: $s.haptics)
                        .onChange(of: s.haptics) { _, on in if on { Haptics.tap() } }
                }

                Section {
                    if Shared.groupAvailable {
                        Label("Общее хранилище доступно", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("App Group недоступна", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text("Приложение подписано без App Group, поэтому виджет не видит данные приложения. Нужен профиль с App Group.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text("Виджет") }

                #if PERSONAL_TEST
                Section {
                    Toggle("Flamio+ без оплаты", isOn: $plus.testUnlock)
                } header: { Text("Личная сборка") } footer: {
                    Text("Только для проверки платных функций на своём устройстве. В релизной сборке этого переключателя нет.")
                }
                #endif

                Section("О приложении") {
                    LabeledContent("Версия", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Настройки")
            .sheet(isPresented: $paywall) { PaywallView() }
        }
    }
}
