import SwiftUI
import WidgetKit
import UserNotifications

@main
struct LifeAppMain: App {
    @StateObject private var store = Store()
    @StateObject private var settings = AppSettings()
    @StateObject private var pet = PetProfile()
    @StateObject private var plus = PlusStore()
    init() { NotificationManager.shared.setup() }
    var body: some Scene {
        WindowGroup { RootView().environmentObject(store).environmentObject(settings).environmentObject(pet).environmentObject(plus) }
    }
}

@MainActor
final class Store: ObservableObject {
    @Published var data: AppData { didSet { save() } }
    init() { data = AppData.load() }

    private func save() {
        if let d = try? JSONEncoder().encode(data) { Shared.defaults.set(d, forKey: Shared.key) }
        WidgetCenter.shared.reloadAllTimelines()
    }
    func log(_ kind: String, _ item: String) {
        let wasAlive = data.streakAlive
        data.petLogs.append(PetLog(date: .now, kind: kind, item: item))
        // первое действие за день может принести новую серию — поздравляем на круглых числах
        if !wasAlive, [3, 7, 14, 30, 50, 100, 365].contains(data.streak) {
            NotificationManager.shared.milestone(days: data.streak)
        }
    }
}

// MARK: - Вкладки
enum AppTab: Int, CaseIterable, Identifiable {
    case weather, shifts, pet, spending, settings
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .weather: "Погода"
        case .shifts: "Смены"
        case .pet: "Огонёк"
        case .spending: "Траты"
        case .settings: "Ещё"
        }
    }
    var icon: String {
        switch self {
        case .weather: "cloud.sun"
        case .shifts: "calendar"
        case .pet: "flame"
        case .spending: "creditcard"
        case .settings: "gearshape"
        }
    }
    var iconFilled: String {
        switch self {
        case .weather: "cloud.sun.fill"
        case .shifts: "calendar"
        case .pet: "flame.fill"
        case .spending: "creditcard.fill"
        case .settings: "gearshape.fill"
        }
    }
}

struct RootView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var store: Store
    @EnvironmentObject var pet: PetProfile
    @EnvironmentObject var plus: PlusStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var tab: AppTab = .weather
    @Namespace private var ns

    private var anim: Animation? { settings.transitionAnimation(reduceMotion: reduce) }
    /// Без сдвига и масштаба: при «Уменьшении движения» или выключенных анимациях остаётся только fade
    private var calm: Bool { !settings.animations || (reduce && settings.respectReduceMotion) }

    var body: some View {
        ZStack {
            FlamioBackground()
            // Все вкладки живут одновременно — состояние (прокрутка, город, формы) не теряется
            ZStack {
                ForEach(AppTab.allCases) { t in
                    let selected = tab == t
                    let dir: CGFloat = t.rawValue < tab.rawValue ? -1 : 1
                    page(t)
                        .opacity(selected ? 1 : 0)
                        .scaleEffect(selected || calm ? 1 : 0.97)
                        .offset(x: selected || calm ? 0 : dir * 28)
                        .allowsHitTesting(selected)
                        .accessibilityHidden(!selected)
                        .environment(\.tabActive, selected)
                        .zIndex(selected ? 1 : 0)
                }
            }
            .animation(anim, value: tab)
            .safeAreaInset(edge: .bottom, spacing: 0) { bar }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.orange)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // Расписание уведомлений обновляется при смене данных, настроек и возврате в приложение
        .task { resched() }
        .task { await plus.start() }
        .onChange(of: scenePhase) { _, p in if p == .active { resched(); Task { await plus.refresh() } } }
        .onChange(of: pet.p.signature) { _, _ in resched() }
        .onChange(of: store.data.petLogs.count) { _, _ in resched() }
        .onChange(of: store.data.records.count) { _, _ in resched() }
    }

    private func resched() {
        let prefs = pet.p, data = store.data
        Task { await NotificationManager.shared.reschedule(prefs: prefs, data: data) }
    }

    @ViewBuilder func page(_ t: AppTab) -> some View {
        switch t {
        case .weather: WeatherView()
        case .shifts: ShiftsView()
        case .pet: PetView()
        case .spending: SpendingView()
        case .settings: SettingsView()
        }
    }

    var bar: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { t in
                Button {
                    guard tab != t else { return }
                    Haptics.select()
                    withAnimation(anim) { tab = t }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab == t ? t.iconFilled : t.icon).font(.system(size: 19, weight: .semibold))
                        Text(t.title).font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(tab == t ? Theme.orange : Color.white.opacity(0.65))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .background {
                        if tab == t {
                            Capsule().fill(Theme.orange.opacity(0.16))
                                .overlay(Capsule().stroke(Theme.orange.opacity(0.5), lineWidth: 1))
                                .matchedGeometryEffect(id: "sel", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.title)
                .accessibilityAddTraits(tab == t ? .isSelected : [])
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Theme.purple.opacity(0.35), lineWidth: 1))
        .padding(.horizontal, 16).padding(.bottom, 6)
    }
}
