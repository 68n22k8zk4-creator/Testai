import SwiftUI
import UserNotifications
import UIKit

// MARK: - Настроение
enum PetMood { case idle, happy, sad, sleep, wait }

// MARK: - Гардероб (слои: голова, верх, низ, обувь, аксессуары)
enum Slot: String, CaseIterable, Identifiable, Codable {
    case head, top, bottom, shoes, accessory
    var id: String { rawValue }
    var title: String {
        switch self {
        case .head: "Голова"
        case .top: "Верх"
        case .bottom: "Низ"
        case .shoes: "Обувь"
        case .accessory: "Аксессуары"
        }
    }
}

struct WardrobeItem: Identifiable {
    let id: String
    let slot: Slot
    let name: String
    let icon: String
    var plus: Bool = false
}

enum Wardrobe {
    static let items: [WardrobeItem] = [
        .init(id: "cap", slot: .head, name: "Кепка", icon: "🧢"),
        .init(id: "tophat", slot: .head, name: "Цилиндр", icon: "🎩"),
        .init(id: "crown", slot: .head, name: "Корона", icon: "👑", plus: true),
        .init(id: "grad", slot: .head, name: "Выпускная", icon: "🎓", plus: true),
        .init(id: "hoodie", slot: .top, name: "Худи", icon: "🧥"),
        .init(id: "sweater", slot: .top, name: "Свитер", icon: "🧶"),
        .init(id: "tshirt", slot: .top, name: "Футболка", icon: "👕"),
        .init(id: "jeans", slot: .bottom, name: "Джинсы", icon: "👖"),
        .init(id: "shorts", slot: .bottom, name: "Шорты", icon: "🩳"),
        .init(id: "sneakers", slot: .shoes, name: "Кроссовки", icon: "👟"),
        .init(id: "boots", slot: .shoes, name: "Ботинки", icon: "🥾"),
        .init(id: "glasses", slot: .accessory, name: "Очки", icon: "🕶️"),
        .init(id: "scarf", slot: .accessory, name: "Шарф", icon: "🧣"),
        .init(id: "bowtie", slot: .accessory, name: "Бабочка", icon: "🎀"),
        .init(id: "medal", slot: .accessory, name: "Медаль", icon: "🏅", plus: true)
    ]
    static func items(in slot: Slot) -> [WardrobeItem] { items.filter { $0.slot == slot } }
}

// MARK: - Профиль питомца (имя, наряд, настройки уведомлений) — хранится в UserDefaults
struct PetPrefs: Codable, Equatable {
    var name = "Огонёк"
    var nameChosen = false
    var outfit: [String: String] = [:]      // slot.rawValue -> item id
    var notifOn = false
    var feedOn = true
    var playOn = true
    var greetOn = true
    var eventsOn = true
    var achvOn = true
    var greetMin = 8 * 60 + 30
    var feedMin = 12 * 60 + 30
    var playMin = 18 * 60 + 30

    init() {}
    // Мягкое чтение: новые поля в будущем не сбросят сохранённое
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ k: CodingKeys, _ def: T) -> T { (try? c.decodeIfPresent(T.self, forKey: k)) ?? def }
        name = get(.name, name); nameChosen = get(.nameChosen, nameChosen); outfit = get(.outfit, outfit)
        notifOn = get(.notifOn, notifOn); feedOn = get(.feedOn, feedOn); playOn = get(.playOn, playOn)
        greetOn = get(.greetOn, greetOn); eventsOn = get(.eventsOn, eventsOn); achvOn = get(.achvOn, achvOn)
        greetMin = get(.greetMin, greetMin); feedMin = get(.feedMin, feedMin); playMin = get(.playMin, playMin)
    }
    enum CodingKeys: String, CodingKey {
        case name, nameChosen, outfit, notifOn, feedOn, playOn, greetOn, eventsOn, achvOn, greetMin, feedMin, playMin
    }
    /// Меняется только при изменении того, что влияет на расписание уведомлений
    var signature: String {
        "\(name)|\(notifOn)|\(feedOn)|\(playOn)|\(greetOn)|\(eventsOn)|\(greetMin)|\(feedMin)|\(playMin)"
    }
}

@MainActor
final class PetProfile: ObservableObject {
    private static let key = "pet.prefs.v1"
    @Published var p: PetPrefs { didSet { save() } }

    init() {
        if let d = UserDefaults.standard.data(forKey: Self.key),
           let v = try? JSONDecoder().decode(PetPrefs.self, from: d) { p = v } else { p = PetPrefs() }
    }
    private func save() {
        if let d = try? JSONEncoder().encode(p) { UserDefaults.standard.set(d, forKey: Self.key) }
        UserDefaults.standard.set(p.notifOn && p.achvOn, forKey: "pet.achv.active")
    }

    func setName(_ s: String) {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { p.name = String(t.prefix(20)) }
        p.nameChosen = true
    }
    func equipped(_ slot: Slot) -> String? { p.outfit[slot.rawValue] }
    /// Нажатие на надетую вещь снимает её
    func toggle(_ item: WardrobeItem) {
        if p.outfit[item.slot.rawValue] == item.id { p.outfit[item.slot.rawValue] = nil }
        else { p.outfit[item.slot.rawValue] = item.id }
    }
    func clearOutfit() { p.outfit = [:] }
    /// Наряд, который реально показывается: платные вещи скрыты, если подписка закончилась (выбор не стирается)
    func visibleOutfit(plus: Bool) -> [String: String] {
        p.outfit.filter { slot, id in plus || Wardrobe.items.first { $0.id == id }?.plus != true }
    }
}

// MARK: - Уведомления
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private var center: UNUserNotificationCenter { .current() }

    func setup() { center.delegate = self }

    // Показывать баннер, даже когда приложение открыто
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func status() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }

    /// Стандартный системный запрос разрешения iOS
    func request() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func cancelAll() async {
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("flamio.") }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // Разные тексты, чтобы уведомления не повторялись изо дня в день
    private func feedText(_ n: String) -> [String] { [
        "\(n) проголодался и ждёт тебя 🍽️", "Пора покормить \(n)! Он уже скучает",
        "У \(n) урчит в животике. Заглянешь?", "\(n) мечтает о вкусной рыбке 🐟",
        "Не забудь накормить \(n) — он очень ждёт", "\(n) хочет перекусить. Загляни на минутку"] }
    private func playText(_ n: String) -> [String] { [
        "\(n) хочет играть! 🎮", "Давай немного поиграем? \(n) уже готов",
        "\(n) скучает без игр. Загляни на минутку", "Минутка игры подарит \(n) хорошее настроение",
        "\(n) приготовил для тебя игру ✨"] }
    private let greetText = [
        "Доброе утро! Удачи на работе сегодня 🍀", "Хорошего дня! Я в тебя верю 🔥",
        "Сегодня всё получится. Я рядом!", "Новый день — новые победы. Удачи!",
        "Пусть смена пройдёт легко ☀️", "Ты справишься, как всегда 💪"]
    private let supportText = [
        "Ты отлично справляешься! Я горжусь тобой 💜", "Сделай небольшой перерыв — ты это заслужил",
        "Половина дня позади. Так держать!", "Не забудь попить воды 💧",
        "Улыбнись — скоро домой 🙂", "Маленькая пауза делает день легче ☕"]

    /// Планирует уведомления на ближайшие 10 дней (лимит iOS — 64 ожидающих)
    func reschedule(prefs: PetPrefs, data: AppData) async {
        await cancelAll()
        guard prefs.notifOn else { return }
        let st = await status()
        guard st == .authorized || st == .provisional || st == .ephemeral else { return }

        let cal = Calendar.current
        let now = Date()
        let n = prefs.name
        let fedToday = data.petLogs.contains { $0.kind == "feed" && cal.isDateInToday($0.date) }
        let playedToday = data.petLogs.contains { $0.kind == "play" && cal.isDateInToday($0.date) }

        func add(_ id: String, day: Date, minutes: Int, title: String, body: String) async {
            var c = cal.dateComponents([.year, .month, .day], from: day)
            c.hour = minutes / 60; c.minute = minutes % 60
            guard let fire = cal.date(from: c), fire > now else { return }
            let content = UNMutableNotificationContent()
            content.title = title; content.body = body; content.sound = .default
            let req = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: false))
            try? await center.add(req)
        }

        for i in 0..<10 {
            guard let day = cal.date(byAdding: .day, value: i, to: now) else { continue }
            let doy = cal.ordinality(of: .day, in: .year, for: day) ?? i
            if prefs.greetOn {
                await add("flamio.greet.\(i)", day: day, minutes: prefs.greetMin, title: n, body: greetText[doy % greetText.count])
                await add("flamio.support.\(i)", day: day, minutes: 15 * 60 + 30, title: n, body: supportText[(doy * 3 + 1) % supportText.count])
            }
            if prefs.feedOn && !(i == 0 && fedToday) {
                let t = feedText(n); await add("flamio.feed.\(i)", day: day, minutes: prefs.feedMin, title: n, body: t[(doy * 5) % t.count])
            }
            if prefs.playOn && !(i == 0 && playedToday) {
                let t = playText(n); await add("flamio.play.\(i)", day: day, minutes: prefs.playMin, title: n, body: t[(doy * 2 + 1) % t.count])
            }
        }

        // Важные события: запланированные смены — напоминание за час до начала
        if prefs.eventsOn {
            let upcoming = data.records.filter { $0.start > now.addingTimeInterval(3600) && $0.start < now.addingTimeInterval(10 * 86400) }
                .sorted { $0.start < $1.start }.prefix(8)
            for r in upcoming {
                let fire = r.start.addingTimeInterval(-3600)
                var c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                c.second = 0
                let content = UNMutableNotificationContent()
                content.title = "Скоро смена"
                content.body = "\(r.title) начнётся в \(r.start.formatted(date: .omitted, time: .shortened))"
                content.sound = .default
                try? await center.add(UNNotificationRequest(identifier: "flamio.event.\(r.id.uuidString)", content: content,
                                                            trigger: UNCalendarNotificationTrigger(dateMatching: c, repeats: false)))
            }
        }
    }

    /// Поздравление с достижением (серия дней) — показывается через несколько секунд
    func milestone(days: Int) {
        guard UserDefaults.standard.bool(forKey: "pet.achv.active") else { return }
        let content = UNMutableNotificationContent()
        content.title = "Новое достижение! 🏆"
        content.body = "Серия — \(days) \(days % 10 == 1 && days % 100 != 11 ? "день" : (2...4).contains(days % 10) && !(12...14).contains(days % 100) ? "дня" : "дней") подряд. Так держать!"
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "flamio.milestone.\(days)", content: content,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)))
    }
}
