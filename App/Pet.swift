import SwiftUI
import UserNotifications

struct PetView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var pet: PetProfile
    @EnvironmentObject var plus: PlusStore
    @Environment(\.tabActive) private var tabActive
    @State private var feed = false
    @State private var games = false
    @State private var wardrobe = false
    @State private var settings = false
    @State private var reaction = ""
    @State private var override: PetMood?
    @State private var hop = 0
    @State private var nameAlert = false
    @State private var draft = ""

    /// Базовое настроение зависит от времени суток и от того, как давно с питомцем взаимодействовали
    private var baseMood: PetMood {
        let h = Calendar.current.component(.hour, from: .now)
        if h >= 23 || h < 6 { return .sleep }
        if let last = store.data.petLogs.map(\.date).max(), Date().timeIntervalSince(last) > 2 * 86400 { return .sad }
        if !store.data.streakAlive { return .wait }
        return .idle
    }

    var body: some View {
        let d = store.data
        let best = d.bestFood()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 6) {
                        PetAvatar(mood: override ?? baseMood, outfit: pet.visibleOutfit(plus: plus.isPlus), hop: hop)
                            .frame(height: 250)
                            .contentShape(Rectangle())
                            .onTapGesture { react(.happy) }
                            .accessibilityLabel("\(pet.p.name). Нажми, чтобы погладить")
                        Button { draft = pet.p.name; nameAlert = true } label: {
                            HStack(spacing: 6) {
                                Text(pet.p.name).font(.title2.bold())
                                Image(systemName: "pencil").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        HStack(spacing: 6) {
                            Image(systemName: "flame.fill").font(.title)
                                .foregroundStyle(d.streakAlive ? Color.orange : Color.gray)
                            Text("\(d.streak)").font(.system(size: 40, weight: .semibold))
                        }
                        Text(d.streakAlive ? "дней подряд" : "покорми или поиграй сегодня")
                            .font(.footnote).foregroundStyle(.secondary)
                        if !reaction.isEmpty { Text(reaction).font(.footnote).padding(.top, 4) }
                    }
                    .padding(.top, 8)

                    HStack(spacing: 12) {
                        big("Покормить", "fork.knife") { feed = true }
                        big("Играть", "gamecontroller") { games = true }
                    }

                    card {
                        HStack {
                            Text(best.emoji).font(.system(size: 36))
                            VStack(alignment: .leading) {
                                Text("Лучшее сейчас").font(.caption).foregroundStyle(.secondary)
                                Text(best.name)
                            }
                            Spacer()
                            Button("Дать") { give(best) }.buttonStyle(.bordered)
                        }
                    }
                    card {
                        HStack {
                            Text("Вчера").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            let f = d.feeds(on: yesterday)
                            Text(f.isEmpty ? "—" : f.map(\.emoji).joined()).font(.title3)
                        }
                    }
                    NavigationLink("Всё о питомце") { PetInfo() }.font(.footnote)
                }
                .padding()
            }
            .navigationTitle("Питомец")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { wardrobe = true } label: { Image(systemName: "tshirt") }
                        .accessibilityLabel("Гардероб")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { settings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Настройки питомца")
                }
            }
            .sheet(isPresented: $feed) { FeedSheet { give($0) } }
            .sheet(isPresented: $games) { GamesList() }
            .sheet(isPresented: $wardrobe) { WardrobeSheet() }
            .sheet(isPresented: $settings) { PetSettingsSheet() }
            .alert("Как зовут питомца?", isPresented: $nameAlert) {
                TextField("Имя", text: $draft)
                Button("Сохранить") { pet.setName(draft) }
                Button("Отмена", role: .cancel) { pet.p.nameChosen = true }
            } message: { Text("Имя можно изменить в любой момент.") }
            // Первый запуск: предлагаем дать имя, когда пользователь открыл вкладку
            .task(id: tabActive) {
                if tabActive && !pet.p.nameChosen { draft = pet.p.name; nameAlert = true }
            }
        }
    }

    func react(_ m: PetMood) {
        override = m
        hop += 1
        Haptics.tap()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if override == m { override = nil }
        }
    }

    func give(_ f: Food) {
        store.log("feed", f.emoji)
        reaction = f.health > 0 ? "Вкусно! 😋" : (f.health < 0 ? "Это не самая здоровая еда" : "Ням")
        react(f.health < 0 ? .idle : .happy)
    }

    func big(_ t: String, _ icon: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Label(t, systemImage: icon).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                .modifier(PetButtonStyle(feed: icon == "fork.knife"))
        }
        .buttonStyle(.plain)
    }

    func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        c().padding().glassCard(16)
    }
}

struct PetButtonStyle: ViewModifier {
    let feed: Bool
    func body(content: Content) -> some View {
        if feed { content.flameButton() } else { content.purpleButton() }
    }
}

// MARK: - Гардероб
struct WardrobeSheet: View {
    @EnvironmentObject var pet: PetProfile
    @EnvironmentObject var plus: PlusStore
    @State private var paywall = false
    @Environment(\.dismiss) var dismiss
    @State private var slot: Slot = .head
    @State private var hop = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                PetAvatar(mood: .happy, outfit: pet.visibleOutfit(plus: plus.isPlus), hop: hop).frame(height: 240)
                Picker("Слот", selection: $slot) {
                    ForEach(Slot.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                        ForEach(Wardrobe.items(in: slot)) { it in
                            let on = pet.equipped(slot) == it.id
                            let locked = it.plus && !plus.isPlus
                            Button {
                                if locked { paywall = true; Haptics.warning(); return }
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) { pet.toggle(it) }
                                hop += 1
                                Haptics.tap()
                            } label: {
                                VStack(spacing: 4) {
                                    Text(it.icon).font(.system(size: 36)).opacity(locked ? 0.55 : 1)
                                    Text(it.name).font(.caption)
                                }
                                .overlay(alignment: .topTrailing) { if locked { PlusBadge().offset(x: 18, y: -6) } }
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(on ? Color.orange.opacity(0.25) : Color.gray.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? Color.orange : .clear, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    Text("Нажми на вещь, чтобы надеть. Нажми ещё раз — снять.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }
            }
            .navigationTitle("Гардероб")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Снять всё") { withAnimation { pet.clearOutfit() }; Haptics.tap() }
                        .disabled(pet.p.outfit.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } }
            }
        }
        .presentationDetents([.large])
        .sheet(isPresented: $paywall) { PaywallView() }
    }
}

// MARK: - Настройки питомца и уведомлений
struct PetSettingsSheet: View {
    @EnvironmentObject var pet: PetProfile
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var name = ""

    private func time(_ keyPath: WritableKeyPath<PetPrefs, Int>) -> Binding<Date> {
        Binding(
            get: {
                let m = pet.p[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: .now) ?? .now
            },
            set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                pet.p[keyPath: keyPath] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            })
    }

    private var master: Binding<Bool> {
        Binding(
            get: { pet.p.notifOn },
            set: { on in
                if on {
                    Task {
                        let ok = await NotificationManager.shared.request()
                        pet.p.notifOn = ok
                        status = await NotificationManager.shared.status()
                    }
                } else {
                    pet.p.notifOn = false
                }
            })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Питомец") {
                    TextField("Имя", text: $name).onSubmit { pet.setName(name) }
                }

                Section {
                    Toggle("Уведомления от питомца", isOn: master)
                    if status == .denied {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Уведомления запрещены в iOS", systemImage: "bell.slash.fill").foregroundStyle(.orange)
                            Text("Откройте Настройки iPhone → Flamio → Уведомления и включите «Допуск уведомлений».")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Открыть настройки iPhone") {
                                if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) }
                            }
                        }
                    }
                } footer: { Text("Питомец напоминает о кормлении, играх и поддерживает в течение дня.") }

                if pet.p.notifOn {
                    Section("Категории") {
                        Toggle("Напоминания о кормлении", isOn: $pet.p.feedOn)
                        if pet.p.feedOn { DatePicker("Время кормления", selection: time(\.feedMin), displayedComponents: .hourAndMinute) }
                        Toggle("Напоминания об играх", isOn: $pet.p.playOn)
                        if pet.p.playOn { DatePicker("Время игры", selection: time(\.playMin), displayedComponents: .hourAndMinute) }
                        Toggle("Приветствия и пожелания", isOn: $pet.p.greetOn)
                        if pet.p.greetOn { DatePicker("Время приветствия", selection: time(\.greetMin), displayedComponents: .hourAndMinute) }
                        Toggle("Напоминания о сменах", isOn: $pet.p.eventsOn)
                        Toggle("Поздравления с достижениями", isOn: $pet.p.achvOn)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Настройки питомца")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { pet.setName(name); dismiss() } } }
            .task {
                name = pet.p.name
                status = await NotificationManager.shared.status()
                // разрешение отозвали в iOS — выключаем флаг, чтобы настройки не врали
                if status == .denied && pet.p.notifOn { pet.p.notifOn = false }
            }
        }
        .presentationDetents([.large])
    }
}

struct FeedSheet: View {
    @Environment(\.dismiss) var dismiss
    let pick: (Food) -> Void

    var body: some View {
        NavigationStack {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 14) {
                ForEach(Foods.all) { f in
                    Button { pick(f); dismiss() } label: {
                        VStack(spacing: 4) {
                            Text(f.emoji).font(.system(size: 40))
                            Text(f.name).font(.caption)
                            Circle().fill(f.health > 0 ? Color.green : (f.health < 0 ? Color.red : Color.orange))
                                .frame(width: 6, height: 6)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .navigationTitle("Чем накормить?")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

struct PetInfo: View {
    @EnvironmentObject var store: Store

    var body: some View {
        let d = store.data
        let days = (0..<7).map { Calendar.current.date(byAdding: .day, value: -$0, to: .now) ?? .now }
        let lastFed = d.petLogs.last { $0.kind == "feed" }?.date
        List {
            Section("Сегодня") {
                HStack { Text("Последнее кормление"); Spacer()
                    if let lastFed { Text(lastFed, style: .relative).foregroundStyle(.secondary) } else { Text("—") } }
                HStack { Text("Кормлений"); Spacer(); Text("\(d.feeds(on: .now).count)").foregroundStyle(.secondary) }
                HStack { Text("Игр"); Spacer(); Text("\(d.plays(on: .now))").foregroundStyle(.secondary) }
            }
            Section("Питание за неделю") {
                ForEach(days, id: \.self) { day in
                    HStack {
                        Text(day, format: .dateTime.weekday(.abbreviated)).frame(width: 36, alignment: .leading)
                        Text(d.feeds(on: day).map(\.emoji).joined())
                        Spacer()
                        if let h = d.dayHealth(day) {
                            Circle().fill(h > 0.5 ? Color.green : (h > -0.5 ? Color.orange : Color.red)).frame(width: 10, height: 10)
                        }
                    }
                }
            }
            Section("Лучшая еда") {
                Text(Foods.all.sorted { $0.health > $1.health }.prefix(5).map(\.emoji).joined(separator: "  ")).font(.title2)
                Text("Больше овощей, фруктов и белка. Фастфуд и сладкое — редко.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Всего") {
                HStack { Text("Кормлений"); Spacer(); Text("\(d.petLogs.filter { $0.kind == "feed" }.count)").foregroundStyle(.secondary) }
                HStack { Text("Игр"); Spacer(); Text("\(d.petLogs.filter { $0.kind == "play" }.count)").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Инфо")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Games
struct GamesList: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Крестики-нолики") { TicTacToeView() }
                NavigationLink("21") { BlackjackView() }
                NavigationLink("Дурак") { DurakView() }
                NavigationLink("Морской бой") { BattleshipView() }
                NavigationLink("Камень-ножницы-бумага") { RPSView() }
            }
            .navigationTitle("Играть")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}

func ttWinner(_ b: [Int]) -> Int {
    let l = [[0, 1, 2], [3, 4, 5], [6, 7, 8], [0, 3, 6], [1, 4, 7], [2, 5, 8], [0, 4, 8], [2, 4, 6]]
    for x in l where b[x[0]] != 0 && b[x[0]] == b[x[1]] && b[x[1]] == b[x[2]] { return b[x[0]] }
    return 0
}

func ttMinimax(_ b: [Int], bot: Bool) -> Int {
    let w = ttWinner(b)
    if w == 2 { return 1 }
    if w == 1 { return -1 }
    if !b.contains(0) { return 0 }
    var best = bot ? -2 : 2
    for i in 0..<9 where b[i] == 0 {
        var n = b
        n[i] = bot ? 2 : 1
        let s = ttMinimax(n, bot: !bot)
        best = bot ? max(best, s) : min(best, s)
    }
    return best
}

struct TicTacToeView: View {
    @EnvironmentObject var store: Store
    @State private var b = Array(repeating: 0, count: 9)
    @State private var logged = false

    var result: String? {
        let w = ttWinner(b)
        if w == 1 { return "Ты выиграл! 🎉" }
        if w == 2 { return "Победил огонёк 🦊" }
        if !b.contains(0) { return "Ничья" }
        return nil
    }

    var body: some View {
        VStack(spacing: 24) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(0..<9, id: \.self) { i in
                    Button { tap(i) } label: {
                        Text(b[i] == 1 ? "✕" : (b[i] == 2 ? "◯" : ""))
                            .font(.system(size: 44, weight: .light))
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            Text(result ?? "Твой ход").foregroundStyle(.secondary)
            Button("Заново") { b = Array(repeating: 0, count: 9); logged = false }
            Spacer()
        }
        .navigationTitle("Крестики-нолики")
    }

    func tap(_ i: Int) {
        guard b[i] == 0, result == nil else { return }
        b[i] = 1
        if result == nil { botMove() }
        if result != nil, !logged { logged = true; store.log("play", "ttt") }
    }

    func botMove() {
        let free = (0..<9).filter { b[$0] == 0 }
        guard !free.isEmpty else { return }
        if Int.random(in: 0..<4) == 0 { b[free.randomElement() ?? free[0]] = 2; return }  // иногда ошибается
        var best = -2, mv = free[0]
        for i in free {
            var n = b
            n[i] = 2
            let s = ttMinimax(n, bot: false)
            if s > best { best = s; mv = i }
        }
        b[mv] = 2
    }
}

struct Card: Hashable {
    let rank: Int
    let suit: String
    var value: Int { min(rank, 10) }
    var text: String {
        let r = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
        return r[rank - 1] + suit
    }
}

func bjTotal(_ h: [Card]) -> Int {
    var t = h.reduce(0) { $0 + $1.value }
    if h.contains(where: { $0.rank == 1 }) && t + 10 <= 21 { t += 10 }
    return t
}

struct BlackjackView: View {
    @EnvironmentObject var store: Store
    @State private var me: [Card] = []
    @State private var pet: [Card] = []
    @State private var over = false
    @State private var msg = ""

    var body: some View {
        VStack(spacing: 30) {
            hand(over ? "🦊 Огонёк · \(bjTotal(pet))" : "🦊 Огонёк", pet, hide: !over)
            hand("Ты · \(bjTotal(me))", me, hide: false)
            if over {
                Text(msg).font(.headline)
                Button("Ещё раз") { deal() }.buttonStyle(.borderedProminent)
            } else {
                HStack(spacing: 16) {
                    Button("Ещё") { hit() }
                    Button("Хватит") { stand() }
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding()
        .navigationTitle("21")
        .onAppear { if me.isEmpty { deal() } }
    }

    func hand(_ title: String, _ cards: [Card], hide: Bool) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            HStack {
                ForEach(Array(cards.enumerated()), id: \.offset) { item in
                    Text(hide && item.offset == 1 ? "?" : item.element.text)
                        .font(.title2).frame(minWidth: 44).padding(10)
                        .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
    }

    func draw() -> Card {
        Card(rank: Int.random(in: 1...13), suit: ["♠", "♥", "♦", "♣"].randomElement() ?? "♠")
    }
    func deal() { me = [draw(), draw()]; pet = [draw(), draw()]; over = false; msg = "" }
    func hit() { me.append(draw()); if bjTotal(me) > 21 { end("Перебор. Выиграл огонёк 🦊") } }
    func stand() {
        while bjTotal(pet) < 17 { pet.append(draw()) }
        let m = bjTotal(me), p = bjTotal(pet)
        if p > 21 || m > p { end("Ты выиграл! 🎉") }
        else if m == p { end("Ничья") }
        else { end("Выиграл огонёк 🦊") }
    }
    func end(_ s: String) { msg = s; over = true; store.log("play", "21") }
}
