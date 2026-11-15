import SwiftUI

// MARK: - Рекомендации
struct Rec: Identifiable {
    let id = UUID()
    let emoji: String
    let title: String
    let detail: String
}

extension WeatherSnapshot {
    /// Все актуальные рекомендации на сегодня — считаются из реальных данных прогноза
    var recommendations: [Rec] {
        var r: [Rec] = []
        let t = Int(feels.rounded())
        if feels < 5 {
            r.append(Rec(emoji: "🧥", title: "Одевайся тепло", detail: "Ощущается как \(t)°. Нужны куртка, шапка и перчатки."))
        } else if feels < 16 {
            r.append(Rec(emoji: "🧣", title: "Одевайся средне", detail: "Ощущается как \(t)°. Подойдут лёгкая куртка или свитер."))
        } else {
            r.append(Rec(emoji: "👕", title: "Одевайся легко", detail: "Ощущается как \(t)°. Хватит футболки или лёгкой одежды."))
        }
        if umbrella {
            r.append(Rec(emoji: "☂️", title: "Возьми зонт", detail: "Вероятность осадков сегодня — \(rainChance)%."))
        } else {
            r.append(Rec(emoji: "🕶️", title: "Зонт не нужен", detail: "Осадков сегодня почти не ожидается."))
        }
        if let uv = days.first?.uv, uv >= 6 {
            r.append(Rec(emoji: "🧴", title: "Нужен солнцезащитный крем", detail: "УФ-индекс сегодня \(Int(uv.rounded())) — кожа может обгореть за 30–40 минут."))
        }
        if let w = wind, w >= 30 {
            r.append(Rec(emoji: "💨", title: "Сильный ветер", detail: "Ветер \(Int(w.rounded())) км/ч. Закрепи капюшон и держи зонт крепче."))
        }
        if temp <= 1 && (precip > 0 || rainChance >= 40) {
            r.append(Rec(emoji: "🧊", title: "Возможна наледь", detail: "Около нуля и с осадками. Выбирай обувь с хорошей подошвой."))
        } else if temp <= -5 {
            r.append(Rec(emoji: "🥶", title: "Сильный мороз", detail: "Не оставайся долго на улице, закрой лицо и руки."))
        }
        if temp >= 28 {
            r.append(Rec(emoji: "💧", title: "Пей больше воды", detail: "Жарко. Носи головной убор и избегай полуденного солнца."))
        }
        if let v = visibility, v < 2000 {
            r.append(Rec(emoji: "🌫️", title: "Плохая видимость", detail: "Видно всего \(String(format: "%.1f", v / 1000)) км. Будь осторожнее на дороге."))
        }
        return r
    }
}

// MARK: - Экран
struct WeatherView: View {
    @EnvironmentObject var store: Store
    @State private var showSearch = false
    @State private var showRecs = false
    @State private var dayDetail: WeatherSnapshot.Day?
    @State private var selectedKey: String?
    @State private var metric: Metric?
    @State private var failed = false

    private var city: City? {
        let i = store.data.selectedCity
        return store.data.cities.indices.contains(i) ? store.data.cities[i] : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let w = store.data.weather, w.cityName == city?.name {
                    content(w)
                } else if city == nil {
                    Text("Добавь город кнопкой +").foregroundStyle(.secondary).padding(.top, 100)
                } else if failed {
                    VStack(spacing: 10) {
                        Text("Не удалось загрузить погоду").foregroundStyle(.secondary)
                        Button("Повторить") { Task { await refresh() } }.buttonStyle(.bordered)
                    }.padding(.top, 100)
                } else {
                    ProgressView().padding(.top, 100)
                }
            }
            .navigationTitle(city?.name ?? "Погода")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSearch = true } label: { Image(systemName: "plus") }
                }
            }
            .task(id: city?.id) { await refresh() }
            .refreshable { await refresh() }
            .sheet(isPresented: $showSearch) { CitySearch() }
            .sheet(isPresented: $showRecs) {
                if let w = store.data.weather { RecsSheet(recs: w.recommendations) }
            }
            .sheet(item: $dayDetail) { d in
                if let w = store.data.weather { HourlySheet(w: w, day: d) }
            }
            .sheet(item: $metric) { m in
                if let w = store.data.weather { MetricSheet(metric: m, w: w) }
            }
        }
    }

    func refresh() async {
        guard let c = city else { return }
        if let w = await WeatherService.fetch(c) { store.data.weather = w; failed = false }
        else if store.data.weather?.cityName != c.name { failed = true }
    }

    func content(_ w: WeatherSnapshot) -> some View {
        let recs = w.recommendations
        return VStack(spacing: 18) {
            Image(systemName: weatherSymbol(w.code)).font(.system(size: 60)).symbolRenderingMode(.multicolor)
            Text("\(Int(w.temp.rounded()))°").font(.system(size: 72, weight: .thin))
            Text("Ощущается как \(Int(w.feels.rounded()))°").foregroundStyle(.secondary)

            // Две главные рекомендации; нажатие открывает список всех
            HStack(spacing: 12) {
                ForEach(recs.prefix(2)) { r in
                    Button { showRecs = true } label: {
                        HStack(spacing: 6) {
                            Text(r.emoji)
                            Text(r.title).font(.footnote).lineLimit(1).minimumScaleFactor(0.8)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .glassCard(22)
                    }
                    .buttonStyle(.plain)
                }
            }
            if recs.count > 2 {
                Button("Ещё советов: \(recs.count - 2)") { showRecs = true }.font(.caption)
            }

            // Дни: нажатие открывает почасовой прогноз
            VStack(spacing: 0) {
                ForEach(w.days) { d in
                    let sel = d.key == selectedKey
                    Button {
                        selectedKey = d.key
                        dayDetail = d
                    } label: {
                        HStack {
                            Text(d.date, format: .dateTime.weekday(.wide)).frame(width: 120, alignment: .leading)
                            Image(systemName: weatherSymbol(d.code)).symbolRenderingMode(.multicolor)
                            Spacer()
                            Text("\(Int(d.min.rounded()))°").foregroundStyle(.secondary)
                            Text("\(Int(d.max.rounded()))°")
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 10).padding(.horizontal, 8)
                        .background(sel ? Color.orange.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().opacity(0.3)
                }
            }
            .padding(.horizontal, 6).glassCard()

            // Показатели: нажатие — объяснение простыми словами
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                ForEach(Metric.available(for: w)) { m in
                    Button { metric = m } label: {
                        VStack(spacing: 4) {
                            Image(systemName: m.icon).foregroundStyle(.orange)
                            Text(m.value(w)).font(.footnote).fontWeight(.semibold).lineLimit(1).minimumScaleFactor(0.7)
                            Text(m.title).font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .glassCard(14)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .onAppear { if selectedKey == nil { selectedKey = w.days.first?.key } }
    }
}

// MARK: - Все рекомендации
struct RecsSheet: View {
    @Environment(\.dismiss) var dismiss
    let recs: [Rec]
    var body: some View {
        NavigationStack {
            List(recs) { r in
                HStack(alignment: .top, spacing: 14) {
                    Text(r.emoji).font(.system(size: 32))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(r.title).font(.headline)
                        Text(r.detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Советы на сегодня")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Почасовой прогноз
struct HourlySheet: View {
    @EnvironmentObject var plus: PlusStore
    @State private var paywall = false
    @Environment(\.dismiss) var dismiss
    let w: WeatherSnapshot
    let day: WeatherSnapshot.Day

    private var tz: TimeZone { TimeZone(secondsFromGMT: w.utcOffset ?? 0) ?? .current }
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = tz; return c }

    private var hours: [WeatherSnapshot.Hour] {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = tz
        return (w.hours ?? []).filter { f.string(from: Date(timeIntervalSince1970: TimeInterval($0.t))) == day.key }
    }

    private func label(_ h: WeatherSnapshot.Hour) -> String {
        String(format: "%02d:00", cal.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(h.t))))
    }

    /// Лучшее двухчасовое окно с 8:00 до 22:00: комфортная температура, без осадков и ветра
    private func bestWalk(_ hs: [WeatherSnapshot.Hour]) -> String? {
        let day = hs.filter { (8...21).contains(cal.component(.hour, from: Date(timeIntervalSince1970: TimeInterval($0.t)))) }
        guard day.count >= 2 else { return nil }
        func score(_ h: WeatherSnapshot.Hour) -> Double { abs((h.feels ?? h.temp) - 18) * 0.6 + Double(h.rain) * 0.08 + h.wind * 0.15 }
        var bestIndex = 0
        var bestScore = Double.infinity
        for i in 0..<(day.count - 1) {
            let sc = score(day[i]) + score(day[i + 1])
            if sc < bestScore { bestScore = sc; bestIndex = i }
        }
        let h = cal.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(day[bestIndex].t)))
        return String(format: "%02d:00–%02d:00", h, h + 2)
    }

    @ViewBuilder private func walkBanner(_ hs: [WeatherSnapshot.Hour]) -> some View {
        if plus.isPlus {
            if let w = bestWalk(hs) {
                Label("Лучшее время для прогулки: \(w)", systemImage: "figure.walk")
                    .font(.subheadline).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal).padding(.bottom, 6)
            }
        } else {
            Button { paywall = true } label: {
                HStack {
                    Label("Лучшее время для прогулки", systemImage: "figure.walk").font(.subheadline)
                    Spacer()
                    PlusBadge()
                }
                .padding(12).background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal).padding(.bottom, 6)
            }
            .buttonStyle(.plain)
        }
    }

    var body: some View {
        NavigationStack {
            let hs = hours
            Group {
                if hs.isEmpty {
                    Text("Почасовых данных для этого дня нет").foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                    walkBanner(hs)
                    ScrollViewReader { proxy in
                        List(hs) { h in
                            HStack(spacing: 10) {
                                Text(label(h)).font(.callout.monospacedDigit()).frame(width: 52, alignment: .leading)
                                Image(systemName: weatherSymbol(h.code)).symbolRenderingMode(.multicolor).frame(width: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(Int(h.temp.rounded()))°").font(.headline)
                                    if let f = h.feels { Text("ощущ. \(Int(f.rounded()))°").font(.caption2).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 1) {
                                    Label("\(h.rain)%", systemImage: "drop.fill").font(.caption).foregroundStyle(.blue)
                                    Label("\(Int(h.wind.rounded())) км/ч", systemImage: "wind").font(.caption).foregroundStyle(.secondary)
                                    if let hum = h.hum { Label("\(hum)%", systemImage: "humidity").font(.caption2).foregroundStyle(.secondary) }
                                }
                            }
                            .id(h.t)
                        }
                        .listStyle(.plain)
                        .onAppear {
                            // для сегодняшнего дня прокручиваем к текущему часу
                            let now = Int(Date().timeIntervalSince1970)
                            if let cur = hs.last(where: { $0.t <= now }), Calendar.current.isDateInToday(day.date) {
                                proxy.scrollTo(cur.t, anchor: .top)
                            }
                        }
                    }
                    }
                }
            }
            .sheet(isPresented: $paywall) { PaywallView() }
            .navigationTitle(day.date.formatted(.dateTime.weekday(.wide).day().month()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Показатели
enum Metric: String, Identifiable, CaseIterable {
    case humidity, wind, pressure, uv, visibility, sunset
    var id: String { rawValue }

    var title: String {
        switch self {
        case .humidity: "Влажность"
        case .wind: "Ветер"
        case .pressure: "Давление"
        case .uv: "УФ-индекс"
        case .visibility: "Видимость"
        case .sunset: "Закат"
        }
    }
    var icon: String {
        switch self {
        case .humidity: "drop"
        case .wind: "wind"
        case .pressure: "gauge.medium"
        case .uv: "sun.max"
        case .visibility: "eye"
        case .sunset: "sunset"
        }
    }

    static func available(for w: WeatherSnapshot) -> [Metric] {
        allCases.filter { m in
            switch m {
            case .humidity: w.humidity != nil
            case .wind: w.wind != nil
            case .pressure: w.pressure != nil
            case .uv: w.days.first?.uv != nil
            case .visibility: w.visibility != nil
            case .sunset: w.sunset != nil
            }
        }
    }

    func value(_ w: WeatherSnapshot) -> String {
        switch self {
        case .humidity: return "\(w.humidity ?? 0)%"
        case .wind: return "\(Int((w.wind ?? 0).rounded())) км/ч"
        case .pressure: return "\(Int(((w.pressure ?? 0) * 0.75006).rounded())) мм"
        case .uv: return "\(Int((w.days.first?.uv ?? 0).rounded()))"
        case .visibility: return String(format: "%.1f км", (w.visibility ?? 0) / 1000)
        case .sunset:
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            f.timeZone = TimeZone(secondsFromGMT: w.utcOffset ?? 0)
            return f.string(from: Date(timeIntervalSince1970: TimeInterval(w.sunset ?? 0)))
        }
    }

    /// (оценка текущего значения, общее объяснение, шкала)
    func explain(_ w: WeatherSnapshot) -> (String, String, [String]) {
        switch self {
        case .humidity:
            let h = w.humidity ?? 0
            let now = h < 30 ? "Сейчас воздух сухой: может сохнуть кожа и першить в горле."
                : h <= 60 ? "Сейчас влажность комфортная."
                : h <= 80 ? "Сейчас воздух влажный: в холод кажется холоднее, в жару — душнее."
                : "Сейчас очень влажно: возможны туман или дождь, одежда сохнет медленно."
            return (now, "Влажность показывает, сколько водяного пара в воздухе (100% — предел, дальше появляется туман или дождь).",
                    ["до 30% — сухо", "30–60% — комфортно", "60–80% — влажно", "выше 80% — очень влажно"])
        case .wind:
            let v = w.wind ?? 0
            let now = v < 6 ? "Сейчас почти штиль."
                : v < 20 ? "Сейчас лёгкий или умеренный ветер, он едва мешает."
                : v < 40 ? "Сейчас сильный ветер: заметно холоднее, зонт может вывернуть."
                : "Сейчас очень сильный ветер. Лучше не гулять рядом с деревьями и рекламными щитами."
            return (now, "Скорость ветра на высоте около 10 м. Чем сильнее ветер, тем быстрее он уносит тепло — поэтому «ощущается как» ниже реальной температуры.",
                    ["до 6 км/ч — штиль", "6–20 — слабый", "20–40 — сильный", "выше 40 — очень сильный"])
        case .pressure:
            let mm = (w.pressure ?? 0) * 0.75006
            let now = mm < 735 ? "Сейчас давление пониженное: часто бывает пасмурно и дождливо."
                : mm <= 770 ? "Сейчас давление нормальное."
                : "Сейчас давление повышенное: обычно ясная и сухая погода."
            return (now, "Атмосферное давление — вес воздуха над нами. Само по себе число мало значит: важнее, быстро ли оно меняется. Резкие скачки могут ухудшать самочувствие метеочувствительных людей.",
                    ["ниже 735 мм — низкое", "735–770 мм — нормальное", "выше 770 мм — высокое"])
        case .uv:
            let u = w.days.first?.uv ?? 0
            let now = u < 3 ? "Сегодня защита не нужна."
                : u < 6 ? "Сегодня умеренный УФ: при долгой прогулке пригодятся очки и крем."
                : u < 8 ? "Сегодня высокий УФ: используй крем, очки и головной убор."
                : "Сегодня очень высокий УФ: избегай солнца в полдень."
            return (now, "УФ-индекс показывает силу ультрафиолета: от него зависит, как быстро можно получить ожог.",
                    ["0–2 — низкий", "3–5 — умеренный", "6–7 — высокий", "8+ — очень высокий"])
        case .visibility:
            let km = (w.visibility ?? 0) / 1000
            let now = km >= 10 ? "Сейчас видно отлично."
                : km >= 4 ? "Сейчас видимость хорошая."
                : km >= 1 ? "Сейчас дымка или лёгкий туман, будь внимательнее за рулём."
                : "Сейчас густой туман: видно очень плохо."
            return (now, "Видимость — как далеко можно различить предметы. Её уменьшают туман, дождь, снег и дымка.",
                    ["10+ км — отлично", "4–10 км — хорошо", "1–4 км — дымка", "до 1 км — туман"])
        case .sunset:
            return ("Время указано по местному времени выбранного города.",
                    "После заката темнеет и быстро становится прохладнее. Если планируешь прогулку или дорогу домой, учитывай это время.", [])
        }
    }
}

struct MetricSheet: View {
    @Environment(\.dismiss) var dismiss
    let metric: Metric
    let w: WeatherSnapshot

    var body: some View {
        let e = metric.explain(w)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: metric.icon).font(.largeTitle).foregroundStyle(.orange)
                        Text(metric.value(w)).font(.system(size: 40, weight: .light))
                    }
                    Text(e.0).font(.headline)
                    Text(e.1).foregroundStyle(.secondary)
                    if !e.2.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Как читать").font(.subheadline).fontWeight(.semibold)
                            ForEach(e.2, id: \.self) { Text("• " + $0).font(.subheadline).foregroundStyle(.secondary) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding()
            }
            .navigationTitle(metric.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Поиск города
struct CitySearch: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    @State private var q = ""
    @State private var results: [City] = []

    var body: some View {
        NavigationStack {
            List {
                if !results.isEmpty {
                    Section("Найдено") {
                        ForEach(results) { c in
                            Button("\(c.name), \(c.country)") {
                                store.data.cities.append(c)
                                store.data.selectedCity = store.data.cities.count - 1
                                dismiss()
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                Section("Мои города") {
                    ForEach(Array(store.data.cities.enumerated()), id: \.element.id) { i, c in
                        Button {
                            store.data.selectedCity = i
                            dismiss()
                        } label: {
                            HStack {
                                Text(c.name)
                                Spacer()
                                if i == store.data.selectedCity { Image(systemName: "checkmark") }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    .onDelete { offsets in
                        let selectedID = store.data.cities.indices.contains(store.data.selectedCity)
                            ? store.data.cities[store.data.selectedCity].id : nil
                        store.data.cities.remove(atOffsets: offsets)
                        store.data.selectedCity = store.data.cities.firstIndex { $0.id == selectedID } ?? 0
                    }
                }
            }
            .searchable(text: $q, prompt: "Название города")
            .onSubmit(of: .search) { Task { results = await WeatherService.search(q) } }
            .navigationTitle("Города")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
