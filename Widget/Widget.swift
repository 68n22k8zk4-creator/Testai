import WidgetKit
import SwiftUI
import AppIntents

enum WidgetSection: String, AppEnum {
    case off, shifts, pet, spending, weather
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Блок"
    static let caseDisplayRepresentations: [WidgetSection: DisplayRepresentation] = [
        .off: "Пусто", .shifts: "Смены", .pet: "Огонёк", .spending: "Траты", .weather: "Погода"
    ]
}

struct WidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Виджет"
    @Parameter(title: "Блок 1", default: .pet) var first: WidgetSection
    @Parameter(title: "Блок 2", default: .shifts) var second: WidgetSection
    @Parameter(title: "Блок 3", default: .weather) var third: WidgetSection
    @Parameter(title: "Всё сразу (большой размер)", default: false) var everything: Bool
    @Parameter(title: "Город для погоды (без App Group)", default: "Прага") var city: String
}

struct Entry: TimelineEntry {
    let date: Date
    let cfg: WidgetIntent
    let data: AppData
    /// false — приложение подписано без App Group, общих данных у виджета нет
    let linked = Shared.groupAvailable
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, cfg: WidgetIntent(), data: AppData()) }

    func snapshot(for configuration: WidgetIntent, in context: Context) async -> Entry {
        Entry(date: .now, cfg: configuration, data: AppData.load())
    }

    func timeline(for configuration: WidgetIntent, in context: Context) async -> Timeline<Entry> {
        var d = AppData.load()
        if !Shared.groupAvailable {
            // Нет общего хранилища: виджет сам находит город и грузит погоду
            if let c = await WeatherService.search(configuration.city).first, let w = await WeatherService.fetch(c) {
                d.cities = [c]; d.selectedCity = 0; d.weather = w
            }
            let now = Date()
            return Timeline(entries: [Entry(date: now, cfg: configuration, data: d)],
                            policy: .after(now.addingTimeInterval(30 * 60)))
        }
        let needsWeather = configuration.everything
            || [configuration.first, configuration.second, configuration.third].contains(.weather)
        if needsWeather, d.cities.indices.contains(d.selectedCity),
           let w = await WeatherService.fetch(d.cities[d.selectedCity]) {
            d.weather = w
        }
        let now = Date()
        // Один запрос раз в 30 минут — минимальная нагрузка на батарею
        return Timeline(entries: [Entry(date: now, cfg: configuration, data: d)],
                        policy: .after(now.addingTimeInterval(30 * 60)))
    }
}

struct WidgetView: View {
    @Environment(\.widgetFamily) var family
    let e: Entry

    var sections: [WidgetSection] {
        let all = [e.cfg.first, e.cfg.second, e.cfg.third].filter { $0 != .off }
        let n = family == .systemSmall ? 1 : (family == .systemMedium ? 2 : 3)
        return Array(all.prefix(n))
    }

    func block(_ s: WidgetSection) -> some View { BlockView(s: s, d: e.data) }

    var body: some View {
        Group {
            if !e.linked {
                // Без App Group доступна только погода выбранного города
                VStack(alignment: .leading, spacing: 8) {
                    block(.weather)
                    Text("Смены, огонёк и траты появятся, когда приложение подписано с App Group.")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else if family == .systemLarge && e.cfg.everything {
                VStack(spacing: 14) {
                    HStack { block(.shifts); Divider(); block(.pet) }
                    Divider()
                    HStack { block(.spending); Divider(); block(.weather) }
                }
            } else if family == .systemMedium {
                HStack {
                    ForEach(Array(sections.enumerated()), id: \.offset) { item in
                        if item.offset > 0 { Divider() }
                        block(item.element)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { item in
                        if item.offset > 0 { Divider() }
                        block(item.element)
                    }
                }
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

struct BlockView: View {
    let s: WidgetSection
    let d: AppData

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch s {
            case .shifts: shifts
            case .pet: pet
            case .spending: spending
            case .weather: weather
            case .off: EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func label(_ icon: String, _ t: String) -> some View {
        Label(t, systemImage: icon).font(.caption2).foregroundStyle(.secondary)
    }

    var shifts: some View {
        let act = d.records.first { $0.end == nil }
        let today = d.dayRecords(.now).reduce(0.0) { $0 + $1.worked() / 3600 }
        let big = act.map { hoursStr($0.worked() / 3600) } ?? (today > 0 ? hoursStr(today) : "—")
        return VStack(alignment: .leading, spacing: 2) {
            label("calendar", "Смены")
            Text(big).font(.system(size: 28, weight: .light))
            Text(act != nil ? "идёт смена" : "сегодня").font(.caption2).foregroundStyle(.secondary)
            Text("\(hoursStr(d.monthHours(.now))) ч · \(money(d.monthPay(.now)))")
                .font(.caption2).lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    var pet: some View {
        VStack(alignment: .leading, spacing: 2) {
            label("flame", "Огонёк")
            HStack(spacing: 4) {
                Image(systemName: "flame.fill").foregroundStyle(d.streakAlive ? Color.orange : Color.gray)
                Text("\(d.streak)").font(.system(size: 28, weight: .light))
            }
            Text(d.streakAlive ? "дней подряд" : "покорми сегодня!").font(.caption2).foregroundStyle(.secondary)
        }
    }

    var spending: some View {
        let by = d.spendByCat(.now)
        let top = by.max { $0.value < $1.value }
        return VStack(alignment: .leading, spacing: 2) {
            label("creditcard", "Траты")
            Text(money(d.monthSpend(.now))).font(.system(size: 24, weight: .light)).lineLimit(1).minimumScaleFactor(0.5)
            Text(top.map { "больше всего: \(Cats.find($0.key).name)" } ?? "в этом месяце")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    var weather: some View {
        VStack(alignment: .leading, spacing: 2) {
            label("cloud.sun", d.weather?.cityName ?? "Погода")
            if let w = d.weather {
                HStack(spacing: 6) {
                    Image(systemName: weatherSymbol(w.code)).symbolRenderingMode(.multicolor)
                    Text("\(Int(w.temp.rounded()))°").font(.system(size: 28, weight: .light))
                }
                Text("\(w.clothes.1)\(w.umbrella ? " · ☂️" : "")")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            } else {
                Text("Добавь город").font(.caption)
            }
        }
    }
}

@main
struct LifeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "LifeWidget", intent: WidgetIntent.self, provider: Provider()) { e in
            WidgetView(e: e)
        }
        .configurationDisplayName("Life")
        .description("Смены, огонёк, траты и погода")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
