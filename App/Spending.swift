import SwiftUI
import Charts
import UniformTypeIdentifiers

// Экспорт истории в CSV (Flamio+)
struct CSVExport: Transferable {
    let text: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { Data($0.text.utf8) }
    }
}

// MARK: - Фильтры
enum Period: String, CaseIterable, Identifiable {
    case today = "Сегодня", yesterday = "Вчера", week = "Неделя", month = "Месяц", year = "Год", custom = "Период"
    var id: String { rawValue }
}

enum KindFilter: String, CaseIterable, Identifiable {
    case all = "Все", income = "Доходы", expense = "Расходы"
    var id: String { rawValue }
}

struct SpendingView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var plus: PlusStore
    @State private var paywall = false
    @State private var adding = false
    @State private var period: Period = .month
    @State private var kind: KindFilter = .all
    @State private var from = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    @State private var to = Date()
    @State private var selected: Expense?      // для меню действий
    @State private var editing: Expense?
    @State private var deleting: Expense?

    private var cal: Calendar { .current }

    /// Диапазон выбранного периода и равный ему предыдущий — для сравнения
    private func range(_ p: Period) -> (Date, Date) {
        let now = Date()
        let sod = cal.startOfDay(for: now)
        switch p {
        case .today: return (sod, cal.date(byAdding: .day, value: 1, to: sod)!)
        case .yesterday: return (cal.date(byAdding: .day, value: -1, to: sod)!, sod)
        case .week:
            let s = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? sod
            return (s, cal.date(byAdding: .day, value: 7, to: s)!)
        case .month:
            let i = cal.dateInterval(of: .month, for: now)!
            return (i.start, i.end)
        case .year:
            let i = cal.dateInterval(of: .year, for: now)!
            return (i.start, i.end)
        case .custom:
            let a = cal.startOfDay(for: min(from, to))
            let b = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: max(from, to)))!
            return (a, b)
        }
    }

    private func previousRange() -> (Date, Date) {
        let (a, b) = range(period)
        switch period {
        case .month: return (cal.date(byAdding: .month, value: -1, to: a)!, a)
        case .year: return (cal.date(byAdding: .year, value: -1, to: a)!, a)
        default: let len = b.timeIntervalSince(a); return (a.addingTimeInterval(-len), a)
        }
    }

    private func items(in r: (Date, Date)) -> [Expense] {
        store.data.expenses.filter { $0.date >= r.0 && $0.date < r.1 }
    }

    var body: some View {
        let r = range(period)
        let all = items(in: r)
        let prevExp = items(in: previousRange()).filter { !$0.isIncome }.reduce(0.0) { $0 + $1.amount }
        let income = all.filter { $0.isIncome }.reduce(0.0) { $0 + $1.amount }
        let expense = all.filter { !$0.isIncome }.reduce(0.0) { $0 + $1.amount }
        let shown = all.filter { kind == .all || (kind == .income) == $0.isIncome }
            .sorted { $0.date > $1.date }

        NavigationStack {
            List {
                Section {
                    Picker("Период", selection: $period) {
                        ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    if period == .custom {
                        DatePicker("С", selection: $from, displayedComponents: .date)
                        DatePicker("По", selection: $to, displayedComponents: .date)
                    }
                    Picker("Тип", selection: $kind) {
                        ForEach(KindFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    summary(income: income, expense: expense, prev: prevExp)
                }

                if kind != .income, !all.filter({ !$0.isIncome }).isEmpty {
                    Section("Расходы по категориям") { categories(all.filter { !$0.isIncome }, total: expense) }
                    Section("По дням") { dailyChart(all.filter { !$0.isIncome }) }
                }

                if expense > 0 {
                    Section("Анализ расходов") {
                        if plus.isPlus {
                            insights(all.filter { !$0.isIncome }, range: r, total: expense)
                        } else {
                            Button { paywall = true } label: {
                                HStack {
                                    Label("Средние траты, прогноз и топ-категория", systemImage: "sparkles")
                                    Spacer()
                                    PlusBadge()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Операции (\(shown.count))") {
                    if shown.isEmpty {
                        Text("Нет операций за выбранный период").foregroundStyle(.secondary)
                    }
                    ForEach(shown) { e in
                        Button { selected = e } label: { row(e) }
                            .foregroundStyle(.primary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .animation(.easeInOut(duration: 0.2), value: period)
            .animation(.easeInOut(duration: 0.2), value: kind)
            .navigationTitle("Траты")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if plus.isPlus {
                        ShareLink(item: CSVExport(text: csv(shown)), preview: SharePreview("Flamio — операции.csv")) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .disabled(shown.isEmpty)
                    } else {
                        Button { paywall = true } label: { Image(systemName: "square.and.arrow.up") }
                            .accessibilityLabel("Экспорт (Flamio+)")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $paywall) { PaywallView() }
            .sheet(isPresented: $adding) { ExpenseForm(existing: nil) }
            .sheet(item: $editing) { ExpenseForm(existing: $0) }
            // Меню действий при нажатии на запись
            .confirmationDialog("Операция", isPresented: Binding(
                get: { selected != nil }, set: { if !$0 { selected = nil } }), presenting: selected) { e in
                Button("Редактировать") { editing = e }
                Button("Удалить", role: .destructive) { deleting = e }
                Button("Отмена", role: .cancel) {}
            } message: { e in
                Text("\(e.note.isEmpty ? Cats.find(e.cat).name : e.note) · \(money(e.amount))")
            }
            .alert("Удалить операцию?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Удалить", role: .destructive) {
                    if let d = deleting { store.data.expenses.removeAll { $0.id == d.id }; Haptics.warning() }
                    deleting = nil
                }
                Button("Отмена", role: .cancel) { deleting = nil }
            } message: { Text("Это действие нельзя отменить.") }
        }
    }

    // MARK: Flamio+ — анализ и экспорт
    func insights(_ list: [Expense], range r: (Date, Date), total: Double) -> some View {
        let now = Date()
        let end = min(now, r.1)
        let days = max(1, Int(ceil(end.timeIntervalSince(r.0) / 86400)))
        let avg = total / Double(days)
        let biggest = list.max { $0.amount < $1.amount }
        var by = [String: Double]()
        for e in list { by[e.cat, default: 0] += e.amount }
        let top = by.max { $0.value < $1.value }
        return VStack(alignment: .leading, spacing: 10) {
            insightRow("calendar", "В среднем в день", money(avg))
            if period == .month, let n = cal.range(of: .day, in: .month, for: now)?.count {
                insightRow("chart.line.uptrend.xyaxis", "Прогноз на месяц", money(avg * Double(n)))
            }
            if let b = biggest {
                insightRow("arrow.up.circle", "Самая большая трата",
                           "\(b.emoji)\(b.emoji.isEmpty ? "" : " ")\(b.note.isEmpty ? Cats.find(b.cat).name : b.note) · \(money(b.amount))")
            }
            if let t = top {
                insightRow("chart.pie", "Больше всего уходит на", "\(Cats.find(t.key).name) · \(Int((t.value / max(total, 1) * 100).rounded()))%")
            }
        }
    }

    func insightRow(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(.orange).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline)
            }
        }
    }

    func csv(_ list: [Expense]) -> String {
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var out = "date,type,category,title,emoji,amount\n"
        for e in list.sorted(by: { $0.date < $1.date }) {
            out += [e.date.formatted(.iso8601.year().month().day()), e.isIncome ? "income" : "expense",
                    q(Cats.find(e.cat).name), q(e.note), q(e.emoji), String(format: "%.2f", e.amount)].joined(separator: ",") + "\n"
        }
        return out
    }

    // MARK: блоки
    func summary(income: Double, expense: Double, prev: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                stat("Доходы", income, .green)
                Divider()
                stat("Расходы", expense, .orange)
                Divider()
                stat("Баланс", income - expense, income - expense >= 0 ? .primary : .red)
            }
            if prev > 0 || expense > 0 {
                let diff = prev > 0 ? (expense - prev) / prev * 100 : nil
                HStack(spacing: 6) {
                    Image(systemName: (diff ?? 0) > 0 ? "arrow.up.right" : "arrow.down.right")
                    if let d = diff {
                        Text("Расходы \(d > 0 ? "выросли" : "снизились") на \(Int(abs(d).rounded()))% к прошлому периоду (\(money(prev)))")
                    } else {
                        Text("В прошлом периоде расходов не было")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    func stat(_ t: String, _ v: Double, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.caption).foregroundStyle(.secondary)
            Text(money(v)).font(.callout.weight(.semibold)).foregroundStyle(c).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func categories(_ list: [Expense], total: Double) -> some View {
        var by = [String: Double]()
        for e in list { by[e.cat, default: 0] += e.amount }
        return ForEach(by.sorted { $0.value > $1.value }, id: \.key) { item in
            HStack(spacing: 10) {
                Image(systemName: Cats.find(item.key).icon).frame(width: 24).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(Cats.find(item.key).name).font(.subheadline)
                        Spacer()
                        Text("\(money(item.value)) · \(Int((item.value / max(total, 1) * 100).rounded()))%").font(.caption)
                    }
                    GeometryReader { g in
                        Capsule().fill(Color.orange.opacity(0.8))
                            .frame(width: max(6, g.size.width * item.value / max(total, 1)))
                    }.frame(height: 6)
                }
            }
        }
    }

    func dailyChart(_ list: [Expense]) -> some View {
        var by = [Date: Double]()
        for e in list { by[cal.startOfDay(for: e.date), default: 0] += e.amount }
        let pts = by.map { (day: $0.key, sum: $0.value) }.sorted { $0.day < $1.day }
        return Chart(pts, id: \.day) {
            BarMark(x: .value("День", $0.day, unit: .day), y: .value("Сумма", $0.sum))
                .foregroundStyle(Color.orange.gradient)
        }
        .frame(height: 140)
        .padding(.vertical, 4)
    }

    func row(_ e: Expense) -> some View {
        HStack(spacing: 12) {
            Group {
                if e.emoji.isEmpty { Image(systemName: Cats.find(e.cat).icon).foregroundStyle(.orange) }
                else { Text(e.emoji).font(.title3) }
            }
            .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.note.isEmpty ? Cats.find(e.cat).name : e.note)
                Text("\(e.date.formatted(.dateTime.day().month())) · \(Cats.find(e.cat).name)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text((e.isIncome ? "+" : "−") + money(e.amount))
                .foregroundStyle(e.isIncome ? Color.green : Color.primary)
            Image(systemName: "ellipsis").font(.caption).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Добавление / редактирование
struct ExpenseForm: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    let existing: Expense?

    @State private var amount: Double?
    @State private var cat = "food"
    @State private var note = ""
    @State private var emoji = ""
    @State private var date = Date()
    @State private var income = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Тип", selection: $income) {
                    Text("Расход").tag(false)
                    Text("Доход").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: income) { _, v in
                    if !Cats.list(income: v).contains(where: { $0.id == cat }) { cat = Cats.list(income: v)[0].id }
                }

                Section {
                    TextField("Сумма", value: $amount, format: .number).keyboardType(.decimalPad)
                        .font(.system(size: 28, weight: .light))
                    TextField("Название", text: $note)
                    HStack {
                        Text("Эмодзи")
                        Spacer()
                        EmojiField(text: $emoji).frame(width: 60, height: 34)
                        if !emoji.isEmpty {
                            Button { emoji = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .buttonStyle(.plain)
                        }
                    }
                    DatePicker("Дата", selection: $date)
                }

                Section("Категория") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                        ForEach(Cats.list(income: income)) { c in
                            Button { cat = c.id } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: c.icon).font(.title3)
                                    Text(c.name).font(.caption2).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(cat == c.id ? Color.orange.opacity(0.25) : Color.gray.opacity(0.1),
                                            in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let e = existing {
                    Button("Удалить операцию", role: .destructive) {
                        store.data.expenses.removeAll { $0.id == e.id }
                        Haptics.warning()
                        dismiss()
                    }
                }
            }
            .navigationTitle(existing == nil ? "Новая операция" : "Редактирование")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Добавить" : "Сохранить") { save() }
                        .disabled((amount ?? 0) <= 0)
                }
            }
            .onAppear {
                guard !loaded, let e = existing else { loaded = true; return }
                loaded = true
                amount = e.amount; cat = e.cat; note = e.note; emoji = e.emoji; date = e.date; income = e.isIncome
            }
        }
        .presentationDetents([.large])
    }

    func save() {
        guard let a = amount, a > 0 else { return }
        if let e = existing, let i = store.data.expenses.firstIndex(where: { $0.id == e.id }) {
            store.data.expenses[i].amount = a
            store.data.expenses[i].cat = cat
            store.data.expenses[i].note = note
            store.data.expenses[i].emoji = emoji
            store.data.expenses[i].date = date
            store.data.expenses[i].isIncome = income
        } else {
            store.data.expenses.append(Expense(date: date, amount: a, cat: cat, note: note, emoji: emoji, isIncome: income))
        }
        Haptics.success()
        dismiss()
    }
}

// MARK: - Поле ввода эмодзи (открывает эмодзи-клавиатуру iOS)
struct EmojiField: UIViewRepresentable {
    @Binding var text: String

    final class Field: UITextField {
        // iOS показывает эмодзи-клавиатуру, если вернуть её режим ввода
        override var textInputMode: UITextInputMode? {
            UITextInputMode.activeInputModes.first { $0.primaryLanguage == "emoji" } ?? super.textInputMode
        }
    }

    func makeUIView(context: Context) -> Field {
        let f = Field()
        f.textAlignment = .center
        f.font = .systemFont(ofSize: 28)
        f.placeholder = "😀"
        f.delegate = context.coordinator
        f.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return f
    }

    func updateUIView(_ f: Field, context: Context) {
        if f.text != text { f.text = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: EmojiField
        init(_ p: EmojiField) { parent = p }

        @objc func changed(_ f: UITextField) {
            // храним ровно один эмодзи (последний введённый)
            let last = f.text?.last.map(String.init) ?? ""
            let isEmoji = last.unicodeScalars.contains { $0.properties.isEmojiPresentation }
                || (last.unicodeScalars.first?.properties.isEmoji == true && last.unicodeScalars.count > 1)
            let v = isEmoji ? last : ""
            if f.text != v { f.text = v }
            parent.text = v
        }
    }
}
