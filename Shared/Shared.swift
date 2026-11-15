import Foundation

// MARK: - Storage
enum Shared {
    // Должен совпадать с App Group в твоём provisioning profile
    static let group = "group.flamio.ios.ipa"
    static let key = "appdata.v1"
    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }
    /// true, только если App Group реально есть в подписи (иначе виджет не увидит данные приложения)
    static var groupAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil
    }
}

func money(_ v: Double) -> String {
    v.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD").precision(.fractionLength(0...2)))
}

func hoursStr(_ h: Double) -> String {
    let m = Int((h * 60).rounded())
    return String(format: "%d:%02d", m / 60, m % 60)
}

// MARK: - Weather
struct City: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var country: String
    var lat: Double
    var lon: Double
}

struct WeatherSnapshot: Codable {
    struct Day: Codable, Identifiable {
        var id = UUID()
        var date: Date
        var min: Double
        var max: Double
        var code: Int
        var rain: Int
        var key: String?          // yyyy-MM-dd в часовом поясе города
        var uv: Double?
    }
    struct Hour: Codable, Identifiable {
        var t: Int                // unix time
        var temp: Double
        var feels: Double?
        var code: Int
        var rain: Int
        var wind: Double
        var hum: Int?
        var id: Int { t }
    }
    var cityName: String
    var temp: Double
    var feels: Double
    var code: Int
    var rainChance: Int
    var precip: Double
    var days: [Day]
    var updated: Date
    // Новые поля — опциональные, чтобы старые сохранения продолжали читаться
    var humidity: Int?
    var wind: Double?
    var pressure: Double?
    var visibility: Double?   // метры
    var sunset: Int?          // unix
    var utcOffset: Int?
    var hours: [Hour]?

    var clothes: (String, String) {
        if feels < 5 { return ("🧥", "Одевайся тепло") }
        if feels < 16 { return ("🧣", "Одевайся средне") }
        return ("👕", "Одевайся легко")
    }
    var umbrella: Bool { rainChance >= 40 || precip > 0 }
}

func weatherSymbol(_ c: Int) -> String {
    switch c {
    case 0: return "sun.max"
    case 1, 2: return "cloud.sun"
    case 3: return "cloud"
    case 45, 48: return "cloud.fog"
    case 51...57: return "cloud.drizzle"
    case 61...67, 80...82: return "cloud.rain"
    case 71...77, 85, 86: return "cloud.snow"
    case 95...99: return "cloud.bolt.rain"
    default: return "cloud"
    }
}

enum WeatherService {
    private struct Geo: Decodable {
        struct R: Decodable { let name: String; let country: String?; let latitude: Double; let longitude: Double }
        let results: [R]?
    }
    private struct Fc: Decodable {
        struct Cur: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double
            let weather_code: Int
            let precipitation: Double
            let relative_humidity_2m: Double?
            let wind_speed_10m: Double?
            let surface_pressure: Double?
            let visibility: Double?
        }
        struct Daily: Decodable {
            let time: [Int]
            let temperature_2m_max: [Double?]
            let temperature_2m_min: [Double?]
            let weather_code: [Int?]
            let precipitation_probability_max: [Int?]
            let uv_index_max: [Double?]?
            let sunset: [Int?]?
        }
        struct Hourly: Decodable {
            let time: [Int]
            let temperature_2m: [Double?]
            let apparent_temperature: [Double?]?
            let weather_code: [Int?]
            let precipitation_probability: [Int?]?
            let wind_speed_10m: [Double?]?
            let relative_humidity_2m: [Double?]?
        }
        let utc_offset_seconds: Int?
        let current: Cur
        let daily: Daily
        let hourly: Hourly?
    }

    static func search(_ q: String) async -> [City] {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [.init(name: "name", value: q), .init(name: "count", value: "6"), .init(name: "language", value: "ru")]
        guard let u = c.url else { return [] }
        do {
            let (d, _) = try await URLSession.shared.data(from: u)
            let r = try JSONDecoder().decode(Geo.self, from: d)
            return (r.results ?? []).map { City(name: $0.name, country: $0.country ?? "", lat: $0.latitude, lon: $0.longitude) }
        } catch { return [] }
    }

    static func fetch(_ city: City) async -> WeatherSnapshot? {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(city.lat)),
            .init(name: "longitude", value: String(city.lon)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,precipitation,relative_humidity_2m,wind_speed_10m,surface_pressure,visibility"),
            .init(name: "hourly", value: "temperature_2m,apparent_temperature,weather_code,precipitation_probability,wind_speed_10m,relative_humidity_2m"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max,uv_index_max,sunset"),
            .init(name: "timezone", value: "auto"),
            .init(name: "timeformat", value: "unixtime"),
            .init(name: "forecast_days", value: "5")
        ]
        guard let u = c.url else { return nil }
        do {
            let (d, _) = try await URLSession.shared.data(from: u)
            let f = try JSONDecoder().decode(Fc.self, from: d)
            let off = f.utc_offset_seconds ?? 0

            let keyFmt = DateFormatter()
            keyFmt.dateFormat = "yyyy-MM-dd"
            keyFmt.locale = Locale(identifier: "en_US_POSIX")
            keyFmt.timeZone = TimeZone(secondsFromGMT: off)
            let localFmt = DateFormatter()
            localFmt.dateFormat = "yyyy-MM-dd"
            localFmt.locale = Locale(identifier: "en_US_POSIX")

            var days: [WeatherSnapshot.Day] = []
            for i in f.daily.time.indices {
                let key = keyFmt.string(from: Date(timeIntervalSince1970: TimeInterval(f.daily.time[i])))
                days.append(.init(date: localFmt.date(from: key) ?? .now,
                                  min: (f.daily.temperature_2m_min[safe: i] ?? nil) ?? 0,
                                  max: (f.daily.temperature_2m_max[safe: i] ?? nil) ?? 0,
                                  code: (f.daily.weather_code[safe: i] ?? nil) ?? 3,
                                  rain: (f.daily.precipitation_probability_max[safe: i] ?? nil) ?? 0,
                                  key: key,
                                  uv: (f.daily.uv_index_max?[safe: i] ?? nil)))
            }

            var hours: [WeatherSnapshot.Hour] = []
            if let h = f.hourly {
                for i in h.time.indices {
                    guard let t = h.temperature_2m[safe: i] ?? nil else { continue }
                    hours.append(.init(t: h.time[i], temp: t,
                                       feels: (h.apparent_temperature?[safe: i] ?? nil),
                                       code: (h.weather_code[safe: i] ?? nil) ?? 3,
                                       rain: (h.precipitation_probability?[safe: i] ?? nil) ?? 0,
                                       wind: (h.wind_speed_10m?[safe: i] ?? nil) ?? 0,
                                       hum: (h.relative_humidity_2m?[safe: i] ?? nil).map { Int($0.rounded()) }))
                }
            }
            let rain = days.first?.rain ?? 0
            return WeatherSnapshot(cityName: city.name, temp: f.current.temperature_2m,
                                   feels: f.current.apparent_temperature, code: f.current.weather_code,
                                   rainChance: rain, precip: f.current.precipitation, days: days, updated: .now,
                                   humidity: f.current.relative_humidity_2m.map { Int($0.rounded()) },
                                   wind: f.current.wind_speed_10m, pressure: f.current.surface_pressure,
                                   visibility: f.current.visibility,
                                   sunset: (f.daily.sunset?.first ?? nil), utcOffset: off, hours: hours)
        } catch { return nil }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - Shifts & pay
enum PayKind: String, Codable, CaseIterable {
    case hourly = "В час", perShift = "За смену", perDay = "За день"
}

struct PayRule: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var kind: PayKind
    var amount: Double
}

enum BonusKind: String, Codable, CaseIterable {
    case monthHours = "За часы в месяц", task = "За работу", other = "Другое"
}

struct Bonus: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var kind: BonusKind
    var hours: Double = 0
    var amount: Double = 0
    var addToRate = false
    var negative = false
    var note = ""
    var signed: Double { negative ? -amount : amount }
}

struct ShiftTemplate: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var auto: Bool
    var startMin: Int = 9 * 60
    var endMin: Int = 18 * 60
    var breakMin: Int = 15
    var lunchMin: Int = 30
    var paidBreaks = false
    var payID: UUID?
}

struct Pause: Codable, Hashable {
    var start: Date
    var end: Date?
    var lunch: Bool
}

struct ShiftRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var templateID: UUID?
    var title: String
    var start: Date
    var end: Date?
    var pauses: [Pause] = []
    var deductMin: Int = 0
    var bonusIDs: [UUID] = []
    var breaksPaid = false

    var onPause: Bool { end == nil && pauses.last != nil && pauses.last!.end == nil }

    func worked(now: Date = .now) -> TimeInterval {
        let e = end ?? now
        var t = e.timeIntervalSince(start) - Double(deductMin) * 60
        if !breaksPaid {
            for p in pauses { t -= (p.end ?? e).timeIntervalSince(p.start) }
        }
        return max(0, t)
    }
}

// MARK: - Spending
struct Cat: Identifiable {
    let id: String
    let icon: String
    let name: String
}

enum Cats {
    static let all = [
        Cat(id: "food", icon: "cart", name: "Еда"),
        Cat(id: "transport", icon: "car", name: "Транспорт"),
        Cat(id: "home", icon: "house", name: "Дом"),
        Cat(id: "fun", icon: "gamecontroller", name: "Отдых"),
        Cat(id: "health", icon: "cross.case", name: "Здоровье"),
        Cat(id: "shop", icon: "bag", name: "Покупки"),
        Cat(id: "other", icon: "ellipsis.circle", name: "Другое")
    ]
    static let income = [
        Cat(id: "salary", icon: "banknote", name: "Зарплата"),
        Cat(id: "bonus", icon: "gift", name: "Бонус"),
        Cat(id: "gift_in", icon: "heart", name: "Подарок"),
        Cat(id: "other_in", icon: "plus.circle", name: "Другое")
    ]
    static func list(income isIncome: Bool) -> [Cat] { isIncome ? income : all }
    static func find(_ id: String) -> Cat {
        (all + income).first { $0.id == id } ?? all[all.count - 1]
    }
}

struct Expense: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var amount: Double
    var cat: String
    var note: String
    var emoji: String = ""       // любой эмодзи; пусто — иконка категории
    var isIncome: Bool = false   // доход / расход
}

// Старые сохранения не содержат emoji/isIncome — читаем их мягко, чтобы не потерять данные
extension Expense {
    enum CodingKeys: String, CodingKey { case id, date, amount, cat, note, emoji, isIncome }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decode(Date.self, forKey: .date)
        amount = try c.decode(Double.self, forKey: .amount)
        cat = try c.decodeIfPresent(String.self, forKey: .cat) ?? "other"
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? ""
        isIncome = try c.decodeIfPresent(Bool.self, forKey: .isIncome) ?? false
    }
}

// MARK: - Pet
struct Food: Identifiable {
    let emoji: String
    let name: String
    let health: Int      // -2 ... 3
    let group: String
    var id: String { emoji }
    init(_ e: String, _ n: String, _ h: Int, _ g: String) { emoji = e; name = n; health = h; group = g }
}

enum Foods {
    static let all = [
        Food("🥦", "Брокколи", 3, "veg"), Food("🥕", "Морковь", 3, "veg"),
        Food("🍎", "Яблоко", 3, "fruit"), Food("🍌", "Банан", 2, "fruit"),
        Food("🐟", "Рыба", 3, "protein"), Food("🍗", "Курица", 2, "protein"),
        Food("🍚", "Рис", 2, "grain"), Food("🥛", "Молоко", 1, "dairy"),
        Food("🍕", "Пицца", -1, "junk"), Food("🍔", "Бургер", -2, "junk"),
        Food("🍟", "Фри", -2, "junk"), Food("🍫", "Шоколад", -2, "junk")
    ]
    static func find(_ id: String) -> Food? { all.first { $0.id == id } }
}

struct PetLog: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var kind: String   // "feed" | "play"
    var item: String
}

// MARK: - All data
struct AppData: Codable {
    var cities: [City] = []
    var selectedCity = 0
    var weather: WeatherSnapshot?
    var templates: [ShiftTemplate] = []
    var pays: [PayRule] = [PayRule(name: "Почасовая", kind: .hourly, amount: 0)]
    var bonuses: [Bonus] = []
    var records: [ShiftRecord] = []
    var expenses: [Expense] = []
    var petLogs: [PetLog] = []

    static func load() -> AppData {
        guard let d = Shared.defaults.data(forKey: Shared.key) else { return AppData() }
        do {
            return try JSONDecoder().decode(AppData.self, from: d)
        } catch {
            // Данные не читаются — не теряем их: сохраняем исходную копию, прежде чем приложение запишет новые
            let k = Shared.key + ".corrupt"
            if Shared.defaults.data(forKey: k) == nil { Shared.defaults.set(d, forKey: k) }
            return AppData()
        }
    }
}

// Мягкое чтение: отсутствующие поля получают значения по умолчанию, кэш погоды не может испортить остальные данные
extension AppData {
    enum CodingKeys: String, CodingKey {
        case cities, selectedCity, weather, templates, pays, bonuses, records, expenses, petLogs
    }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cities = try c.decodeIfPresent([City].self, forKey: .cities) ?? cities
        selectedCity = try c.decodeIfPresent(Int.self, forKey: .selectedCity) ?? selectedCity
        weather = try? c.decodeIfPresent(WeatherSnapshot.self, forKey: .weather)
        templates = try c.decodeIfPresent([ShiftTemplate].self, forKey: .templates) ?? templates
        pays = try c.decodeIfPresent([PayRule].self, forKey: .pays) ?? pays
        bonuses = try c.decodeIfPresent([Bonus].self, forKey: .bonuses) ?? bonuses
        records = try c.decodeIfPresent([ShiftRecord].self, forKey: .records) ?? records
        expenses = try c.decodeIfPresent([Expense].self, forKey: .expenses) ?? expenses
        petLogs = try c.decodeIfPresent([PetLog].self, forKey: .petLogs) ?? petLogs
    }
}

extension AppData {
    private var cal: Calendar { .current }

    func rule(for r: ShiftRecord) -> PayRule? {
        let tid = templates.first { $0.id == r.templateID }?.payID
        return pays.first { $0.id == tid } ?? pays.first
    }
    func monthRecords(_ d: Date) -> [ShiftRecord] {
        records.filter { cal.isDate($0.start, equalTo: d, toGranularity: .month) }
    }
    func dayRecords(_ d: Date) -> [ShiftRecord] {
        records.filter { cal.isDate($0.start, inSameDayAs: d) }
    }
    func monthHours(_ d: Date) -> Double {
        monthRecords(d).reduce(0.0) { $0 + $1.worked() / 3600 }
    }
    func monthPay(_ d: Date) -> Double {
        let recs = monthRecords(d)
        let hours = recs.reduce(0.0) { $0 + $1.worked() / 3600 }
        let hit = bonuses.filter { $0.kind == .monthHours && hours >= $0.hours }
        let monthRate = hit.filter { $0.addToRate }.reduce(0.0) { $0 + $1.signed }
        var total = hit.filter { !$0.addToRate }.reduce(0.0) { $0 + $1.signed }
        var seen = Set<Date>()
        for r in recs {
            let h = r.worked() / 3600
            let att = bonuses.filter { r.bonusIDs.contains($0.id) }
            let rateB = att.filter { $0.addToRate }.reduce(0.0) { $0 + $1.signed } + monthRate
            total += att.filter { !$0.addToRate }.reduce(0.0) { $0 + $1.signed }
            guard let rule = rule(for: r) else { continue }
            switch rule.kind {
            case .hourly: total += h * (rule.amount + rateB)
            case .perShift: total += rule.amount + rateB * h
            case .perDay:
                if seen.insert(cal.startOfDay(for: r.start)).inserted { total += rule.amount }
                total += rateB * h
            }
        }
        return total
    }

    func monthSpend(_ d: Date) -> Double { spendByCat(d).values.reduce(0, +) }
    func spendByCat(_ d: Date) -> [String: Double] {
        var r = [String: Double]()
        for e in expenses where !e.isIncome && cal.isDate(e.date, equalTo: d, toGranularity: .month) { r[e.cat, default: 0] += e.amount }
        return r
    }

    /// Сколько дней подряд были смены (до сегодня; сегодня можно ещё не работать)
    var shiftStreak: Int {
        let days = Set(records.filter { $0.start <= .now }.map { cal.startOfDay(for: $0.start) })
        var d = cal.startOfDay(for: .now)
        if !days.contains(d) { d = cal.date(byAdding: .day, value: -1, to: d) ?? d }
        var n = 0
        while days.contains(d) {
            n += 1
            d = cal.date(byAdding: .day, value: -1, to: d) ?? .distantPast
        }
        return n
    }

    var streakAlive: Bool { petLogs.contains { cal.isDateInToday($0.date) } }
    var streak: Int {
        let days = Set(petLogs.map { cal.startOfDay(for: $0.date) })
        var d = cal.startOfDay(for: .now)
        if !days.contains(d) { d = cal.date(byAdding: .day, value: -1, to: d) ?? d }
        var n = 0
        while days.contains(d) {
            n += 1
            d = cal.date(byAdding: .day, value: -1, to: d) ?? .distantPast
        }
        return n
    }
    func feeds(on day: Date) -> [Food] {
        petLogs.filter { $0.kind == "feed" && cal.isDate($0.date, inSameDayAs: day) }.compactMap { Foods.find($0.item) }
    }
    func plays(on day: Date) -> Int {
        petLogs.filter { $0.kind == "play" && cal.isDate($0.date, inSameDayAs: day) }.count
    }
    func dayHealth(_ day: Date) -> Double? {
        let f = feeds(on: day)
        guard !f.isEmpty else { return nil }
        return Double(f.map(\.health).reduce(0, +)) / Double(f.count)
    }
    func bestFood() -> Food {
        let since = cal.date(byAdding: .day, value: -3, to: .now) ?? .now
        let eaten = petLogs.filter { $0.kind == "feed" && $0.date >= since }.compactMap { Foods.find($0.item) }
        func cnt(_ g: String) -> Int { eaten.filter { $0.group == g }.count }
        let good = Foods.all.filter { $0.health > 0 }
        return good.min { (cnt($0.group), -$0.health) < (cnt($1.group), -$1.health) } ?? good[0]
    }
}
