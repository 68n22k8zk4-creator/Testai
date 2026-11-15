import SwiftUI

struct IDBox: Identifiable { let id: UUID }
struct DayBox: Identifiable { let id: Date }
struct NewShiftBox: Identifiable { let id = UUID(); let day: Date; let template: ShiftTemplate? }

struct ShiftsView: View {
    @EnvironmentObject var store: Store
    @State private var month = Date()
    @State private var settings = false
    @State private var dayBox: DayBox?
    @State private var edit: IDBox?
    @State private var menuDay: DayBox?
    @State private var newShift: NewShiftBox?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    summary
                    todayCard
                    calendarGrid.padding(12).glassCard()
                }
                .padding()
            }
            .navigationTitle("Смены")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { settings = true } label: { Image(systemName: "slider.horizontal.3") }
                }
            }
            .sheet(isPresented: $settings) { ShiftSettings() }
            .sheet(item: $dayBox) { DaySheet(day: $0.id) }
            .sheet(item: $edit) { RecordEditor(id: $0.id) }
            .sheet(item: $newShift) { NewShiftSheet(day: $0.day, template: $0.template) }
            // Компактное меню по нажатию на дату
            .confirmationDialog(menuDay.map { $0.id.formatted(.dateTime.weekday(.wide).day().month(.wide)) } ?? "",
                                isPresented: Binding(get: { menuDay != nil }, set: { if !$0 { menuDay = nil } }),
                                titleVisibility: .visible, presenting: menuDay) { box in
                let tpls = store.data.templates
                ForEach(tpls) { t in
                    Button("Добавить: \(t.name)") { newShift = NewShiftBox(day: box.id, template: t) }
                }
                Button(tpls.isEmpty ? "Добавить смену" : "Добавить свою смену") {
                    newShift = NewShiftBox(day: box.id, template: nil)
                }
                let n = store.data.dayRecords(box.id).count
                if n > 0 {
                    Button("Смены за день (\(n)) — изменить или удалить") { dayBox = box }
                }
                Button("Отмена", role: .cancel) {}
            }
        }
    }

    func moveMonth(_ v: Int) {
        month = Calendar.current.date(byAdding: .month, value: v, to: month) ?? month
    }

    var summary: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                FlameView(lit: store.data.shiftStreak > 0).frame(width: 46, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.data.shiftStreak > 0 ? "\(store.data.shiftStreak) дн. подряд" : "Серия смен")
                        .font(.headline)
                    Text(store.data.shiftStreak > 0 ? "серия смен" : "добавь смену — зажги огонёк")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack {
                Button { Haptics.select(); moveMonth(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Предыдущий месяц")
                Spacer()
                Text(month, format: .dateTime.month(.wide).year()).font(.headline)
                Spacer()
                Button { Haptics.select(); moveMonth(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Следующий месяц")
            }
            .glassCard(22)
            // Две карточки равной ширины: влезают и на узких экранах
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    ClockView().frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hoursStr(store.data.monthHours(month))).font(.system(size: 26, weight: .light))
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text("часов").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(12).frame(maxWidth: .infinity).glassCard()
                VStack(alignment: .leading, spacing: 2) {
                    Text(money(store.data.monthPay(month))).font(.system(size: 26, weight: .light))
                        .lineLimit(1).minimumScaleFactor(0.5)
                    Text("заработок").font(.caption).foregroundStyle(.secondary)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading).glassCard()
            }
        }
    }

    // MARK: Today / manual shift
    @ViewBuilder var todayCard: some View {
        let ai = store.data.records.firstIndex { $0.end == nil }
        VStack(spacing: 12) {
            if let i = ai { activeView(i) } else { startView }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .glassCard()
    }

    var bigButton: some View {
        Label("Начать смену", systemImage: "play.fill")
            .font(.headline).padding(.horizontal, 28).padding(.vertical, 14)
            .flameButton()
    }

    var startView: some View {
        let manual = store.data.templates.filter { !$0.auto }
        return VStack(spacing: 8) {
            Text("Сегодня").font(.caption).foregroundStyle(.secondary)
            if manual.count > 1 {
                Menu {
                    ForEach(manual) { t in Button(t.name) { start(t) } }
                } label: { bigButton }
            } else {
                Button { start(manual.first) } label: { bigButton }
            }
        }
    }

    func activeView(_ i: Int) -> some View {
        let r = store.data.records[i]
        return VStack(spacing: 10) {
            Text(r.title).font(.subheadline).foregroundStyle(.secondary)
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                Text(hoursStr(r.worked(now: ctx.date) / 3600)).font(.system(size: 46, weight: .thin))
            }
            Text(r.onPause ? ((r.pauses.last?.lunch ?? false) ? "Обед" : "Перерыв") : "Работаешь")
                .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if r.onPause {
                    pill("Продолжить", "play.fill") { resume(i) }
                } else {
                    pill("Перерыв", "pause.fill") { pause(i, false) }
                    pill("Обед", "fork.knife") { pause(i, true) }
                }
                pill("Завершить", "stop.fill") { finish(i) }
            }
            Button("Изменить") { edit = IDBox(id: r.id) }.font(.caption).foregroundStyle(.secondary)
        }
    }

    func pill(_ t: String, _ icon: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Label(t, systemImage: icon).font(.footnote).lineLimit(1)
                .padding(.horizontal, 10).padding(.vertical, 9)
                .background(Color.orange.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    func start(_ t: ShiftTemplate?) {
        store.data.records.append(ShiftRecord(templateID: t?.id, title: t?.name ?? "Смена", start: .now,
                                              breaksPaid: t?.paidBreaks ?? false))
    }
    func pause(_ i: Int, _ lunch: Bool) {
        store.data.records[i].pauses.append(Pause(start: .now, end: nil, lunch: lunch))
    }
    func resume(_ i: Int) {
        if let j = store.data.records[i].pauses.indices.last { store.data.records[i].pauses[j].end = .now }
    }
    func finish(_ i: Int) {
        if store.data.records[i].onPause { resume(i) }
        store.data.records[i].end = .now
    }

    // MARK: Calendar
    var calendarGrid: some View {
        let cal = Calendar.current
        let first = cal.date(from: cal.dateComponents([.year, .month], from: month)) ?? month
        let n = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let syms = cal.veryShortWeekdaySymbols
        let heads = (0..<7).map { syms[($0 + cal.firstWeekday - 1) % 7] }
        // Один массив ячеек с уникальными индексами: пустые + дни 1...n (раньше id пересекались и дни 1–6 пропадали)
        let cells: [Int?] = Array(repeating: nil, count: lead) + Array(1...max(n, 1)).map { Optional($0) }
        return VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(heads[i]).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 6) {
                ForEach(Array(cells.enumerated()), id: \.offset) { item in
                    if let d = item.element { cell(d, first) } else { Color.clear.frame(height: 44) }
                }
            }
        }
    }

    func cell(_ d: Int, _ first: Date) -> some View {
        let day = Calendar.current.date(byAdding: .day, value: d - 1, to: first) ?? first
        let recs = store.data.dayRecords(day)
        let today = Calendar.current.isDateInToday(day)
        return Button { menuDay = DayBox(id: day) } label: {
            VStack(spacing: 2) {
                Text("\(d)").font(.callout).fontWeight(today ? .bold : .regular)
                    .foregroundStyle(today ? Color.orange : Color.primary)
                Text(recs.first.map { String($0.title.prefix(1)) } ?? " ").font(.caption2)
            }
            .frame(height: 44).frame(maxWidth: .infinity)
            .background(recs.isEmpty ? Color.clear : Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Day sheet
struct DaySheet: View {
    @EnvironmentObject var store: Store
    let day: Date
    @State private var edit: IDBox?

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.data.dayRecords(day)) { r in
                    Button { edit = IDBox(id: r.id) } label: {
                        HStack {
                            Text(r.title)
                            Spacer()
                            Text(hoursStr(r.worked() / 3600)).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete { idx in
                    let list = store.data.dayRecords(day)
                    let ids = idx.map { list[$0].id }
                    store.data.records.removeAll { ids.contains($0.id) }
                }
                if store.data.templates.isEmpty {
                    Text("Создай шаблон смены в настройках ⚙︎").font(.footnote).foregroundStyle(.secondary)
                }
                Menu {
                    ForEach(store.data.templates) { t in Button(t.name) { add(t) } }
                    Button("Пустая смена") { add(nil) }
                } label: { Label("Добавить смену", systemImage: "plus") }
            }
            .navigationTitle(day.formatted(.dateTime.day().month(.wide)))
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $edit) { RecordEditor(id: $0.id) }
        }
        .presentationDetents([.medium, .large])
    }

    func add(_ t: ShiftTemplate?) {
        let cal = Calendar.current
        func at(_ m: Int) -> Date { cal.date(byAdding: .minute, value: m, to: cal.startOfDay(for: day)) ?? day }
        let auto = t?.auto ?? false
        let s = auto ? (t?.startMin ?? 540) : 9 * 60
        let e = auto ? (t?.endMin ?? 1080) : 17 * 60
        var r = ShiftRecord(templateID: t?.id, title: t?.name ?? "Смена", start: at(s),
                            end: at(e <= s ? e + 1440 : e), breaksPaid: t?.paidBreaks ?? false)
        if let t, t.auto, !t.paidBreaks { r.deductMin = t.breakMin + t.lunchMin }
        store.data.records.append(r)
        edit = IDBox(id: r.id)
    }
}

// MARK: - New shift
struct NewShiftSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    let day: Date
    let template: ShiftTemplate?

    @State private var title = ""
    @State private var start = Date()
    @State private var end = Date()
    @State private var loaded = false

    private var cal: Calendar { .current }
    private func at(_ minutes: Int) -> Date {
        cal.date(byAdding: .minute, value: minutes, to: cal.startOfDay(for: day)) ?? day
    }
    /// Конец после начала; если смена переходит через полночь — конец на следующий день
    private var resolvedEnd: Date {
        let t = cal.dateComponents([.hour, .minute], from: end)
        let s = cal.startOfDay(for: day)
        var e = cal.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: s) ?? end
        if e <= resolvedStart { e = cal.date(byAdding: .day, value: 1, to: e) ?? e }
        return e
    }
    private var resolvedStart: Date {
        let t = cal.dateComponents([.hour, .minute], from: start)
        return cal.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: cal.startOfDay(for: day)) ?? start
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Название", text: $title)
                DatePicker("Начало", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("Окончание", selection: $end, displayedComponents: .hourAndMinute)
                Section {
                    let h = resolvedEnd.timeIntervalSince(resolvedStart) - Double((template?.paidBreaks ?? true) ? 0 : (template?.breakMin ?? 0) + (template?.lunchMin ?? 0)) * 60
                    Text("Длительность: \(hoursStr(max(0, h) / 3600))").foregroundStyle(.secondary)
                    if resolvedEnd > cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: day))! {
                        Text("Смена закончится на следующий день").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(day.formatted(.dateTime.day().month(.wide)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить") { save() } }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                title = template?.name ?? "Смена"
                start = at(template?.startMin ?? 9 * 60)
                end = at(template?.endMin ?? 17 * 60)
            }
        }
        .presentationDetents([.medium])
    }

    func save() {
        var r = ShiftRecord(templateID: template?.id, title: title.isEmpty ? "Смена" : title,
                            start: resolvedStart, end: resolvedEnd, breaksPaid: template?.paidBreaks ?? false)
        if let t = template, t.auto, !t.paidBreaks { r.deductMin = t.breakMin + t.lunchMin }
        store.data.records.append(r)
        Haptics.success()
        dismiss()
    }
}

// MARK: - Record editor
struct RecordEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    let id: UUID

    var body: some View {
        NavigationStack {
            if let i = store.data.records.firstIndex(where: { $0.id == id }) {
                form($store.data.records[i])
            }
        }
    }

    func form(_ r: Binding<ShiftRecord>) -> some View {
        Form {
            TextField("Название", text: r.title)
            DatePicker("Начало", selection: r.start)
            Toggle("Смена завершена", isOn: Binding(
                get: { r.wrappedValue.end != nil },
                set: { r.wrappedValue.end = $0 ? (r.wrappedValue.end ?? .now) : nil }))
            if r.wrappedValue.end != nil {
                DatePicker("Конец", selection: Binding(
                    get: { r.wrappedValue.end ?? .now },
                    set: { r.wrappedValue.end = $0 }))
            }
            Section("Перерывы и обед") {
                Toggle("Оплачиваются", isOn: r.breaksPaid)
                ForEach(Array(r.wrappedValue.pauses.indices), id: \.self) { j in
                    VStack(alignment: .leading) {
                        Text(r.wrappedValue.pauses[j].lunch ? "Обед" : "Перерыв").font(.caption).foregroundStyle(.secondary)
                        DatePicker("С", selection: r.pauses[j].start)
                        DatePicker("До", selection: Binding(
                            get: { r.wrappedValue.pauses[j].end ?? .now },
                            set: { r.wrappedValue.pauses[j].end = $0 }))
                    }
                }
                .onDelete { r.wrappedValue.pauses.remove(atOffsets: $0) }
                Stepper("Вычесть ещё: \(r.wrappedValue.deductMin) мин", value: r.deductMin, in: 0...600, step: 5)
                Button("Добавить перерыв") {
                    let s = r.wrappedValue.start
                    r.wrappedValue.pauses.append(Pause(start: s, end: s.addingTimeInterval(900), lunch: false))
                }
                Button("Добавить обед") {
                    let s = r.wrappedValue.start
                    r.wrappedValue.pauses.append(Pause(start: s, end: s.addingTimeInterval(1800), lunch: true))
                }
            }
            let extra = store.data.bonuses.filter { $0.kind != .monthHours }
            if !extra.isEmpty {
                Section("Бонусы / штрафы") {
                    ForEach(extra) { b in
                        Toggle("\(b.name) \(b.negative ? "−" : "+")\(money(b.amount))", isOn: Binding(
                            get: { r.wrappedValue.bonusIDs.contains(b.id) },
                            set: { on in
                                if on { r.wrappedValue.bonusIDs.append(b.id) }
                                else { r.wrappedValue.bonusIDs.removeAll { $0 == b.id } }
                            }))
                    }
                }
            }
            Section {
                Text("Отработано: \(hoursStr(r.wrappedValue.worked() / 3600))")
                Button("Удалить смену", role: .destructive) {
                    store.data.records.removeAll { $0.id == id }
                    dismiss()
                }
            }
        }
        .navigationTitle("Смена")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
    }
}

// MARK: - Settings: templates, pay, bonuses
struct ShiftSettings: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Шаблоны смен") {
                    ForEach($store.data.templates) { $t in
                        NavigationLink { TemplateForm(t: $t) } label: {
                            HStack {
                                Text(t.name)
                                Spacer()
                                Text(t.auto ? "авто" : "ручная").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { store.data.templates.remove(atOffsets: $0) }
                    Button("Новая смена") { store.data.templates.append(ShiftTemplate(name: "Смена", auto: false)) }
                }
                Section("Оплата") {
                    ForEach($store.data.pays) { $p in
                        NavigationLink { PayForm(p: $p) } label: {
                            HStack { Text(p.name); Spacer(); Text("\(money(p.amount)) · \(p.kind.rawValue.lowercased())").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .onDelete { store.data.pays.remove(atOffsets: $0) }
                    Button("Новый тип оплаты") { store.data.pays.append(PayRule(name: "Ставка", kind: .hourly, amount: 0)) }
                }
                Section("Бонусы и штрафы") {
                    ForEach($store.data.bonuses) { $b in
                        NavigationLink { BonusForm(b: $b) } label: {
                            HStack { Text(b.name); Spacer(); Text("\(b.negative ? "−" : "+")\(money(b.amount))").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .onDelete { store.data.bonuses.remove(atOffsets: $0) }
                    Button("Новый бонус") { store.data.bonuses.append(Bonus(name: "Бонус", kind: .other)) }
                }
            }
            .navigationTitle("Настройки смен")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
}

func timeBinding(_ m: Binding<Int>) -> Binding<Date> {
    Binding(
        get: { Calendar.current.date(bySettingHour: m.wrappedValue / 60, minute: m.wrappedValue % 60, second: 0, of: .now) ?? .now },
        set: {
            let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
            m.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        })
}

struct TemplateForm: View {
    @EnvironmentObject var store: Store
    @Binding var t: ShiftTemplate

    var body: some View {
        Form {
            TextField("Название (можно со смайлом)", text: $t.name)
            Toggle("Авто (время задано заранее)", isOn: $t.auto)
            if t.auto {
                DatePicker("Начало", selection: timeBinding($t.startMin), displayedComponents: .hourAndMinute)
                DatePicker("Конец", selection: timeBinding($t.endMin), displayedComponents: .hourAndMinute)
                Stepper("Перерыв: \(t.breakMin) мин", value: $t.breakMin, in: 0...120, step: 5)
                Stepper("Обед: \(t.lunchMin) мин", value: $t.lunchMin, in: 0...180, step: 5)
            }
            Toggle("Перерывы оплачиваются", isOn: $t.paidBreaks)
            Picker("Оплата", selection: $t.payID) {
                Text("По умолчанию").tag(UUID?.none)
                ForEach(store.data.pays) { p in Text(p.name).tag(UUID?.some(p.id)) }
            }
        }
        .navigationTitle(t.name)
    }
}

struct PayForm: View {
    @Binding var p: PayRule
    var body: some View {
        Form {
            TextField("Название", text: $p.name)
            Picker("Тип", selection: $p.kind) {
                ForEach(PayKind.allCases, id: \.self) { Text($0.rawValue) }
            }
            HStack {
                Text("Сумма")
                TextField("0", value: $p.amount, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
        }
        .navigationTitle(p.name)
    }
}

struct BonusForm: View {
    @Binding var b: Bonus
    var body: some View {
        Form {
            TextField("Название", text: $b.name)
            Picker("За что", selection: $b.kind) {
                ForEach(BonusKind.allCases, id: \.self) { Text($0.rawValue) }
            }
            if b.kind == .monthHours {
                HStack {
                    Text("От часов в месяц")
                    TextField("0", value: $b.hours, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
            }
            HStack {
                Text("Сумма")
                TextField("0", value: $b.amount, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            Toggle("Прибавка к ставке в час", isOn: $b.addToRate)
            Toggle("Минус (штраф)", isOn: $b.negative)
            if b.kind == .other { TextField("Описание", text: $b.note) }
        }
        .navigationTitle(b.name)
    }
}
