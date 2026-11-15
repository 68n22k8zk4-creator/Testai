import SwiftUI
import StoreKit

// MARK: - Flamio+ : подписка на StoreKit 2 (реальные покупки, без имитации)
@MainActor
final class PlusStore: ObservableObject {
    static let monthlyID = "flamio.plus.monthly"
    static let yearlyID = "flamio.plus.yearly"
    static let ids = [monthlyID, yearlyID]

    @Published private(set) var products: [Product] = []
    @Published private(set) var storeActive = false
    /// Только для личных сборок (флаг PERSONAL_TEST): локально включает Flamio+ без оплаты, чтобы проверить функции
    @Published var testUnlock: Bool {
        didSet { UserDefaults.standard.set(testUnlock, forKey: "plus.testUnlock") }
    }
    static var personalBuild: Bool {
        #if PERSONAL_TEST
        true
        #else
        false
        #endif
    }
    var isPlus: Bool { storeActive || (Self.personalBuild && testUnlock) }
    @Published private(set) var expiration: Date?
    @Published private(set) var willRenew = true
    @Published private(set) var billingIssue = false
    @Published private(set) var loading = false
    @Published private(set) var trialText: [String: String] = [:]   // id -> «7 дней бесплатно»
    @Published var busy = false
    @Published var message: String?

    private var updates: Task<Void, Never>?

    init() {
        testUnlock = UserDefaults.standard.bool(forKey: "plus.testUnlock")
        // Транзакции, пришедшие вне приложения (продление, покупка с другого устройства, Ask to Buy)
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                await self?.handle(result)
            }
        }
    }

    func start() async {
        await loadProducts()
        await refresh()
    }

    func loadProducts() async {
        loading = true
        defer { loading = false }
        do {
            let list = try await Product.products(for: Self.ids)
            products = list.sorted { $0.price < $1.price }
            var trials: [String: String] = [:]
            for p in products {
                guard let sub = p.subscription, let offer = sub.introductoryOffer, offer.paymentMode == .freeTrial else { continue }
                let eligible = await sub.isEligibleForIntroOffer
                if eligible { trials[p.id] = "\(Self.period(offer.period)) бесплатно" }
            }
            trialText = trials
        } catch {
            products = []
            message = "Не удалось загрузить цены. Проверьте интернет и попробуйте ещё раз."
        }
    }

    /// Проверка активной подписки по данным App Store (работает офлайн по кэшу StoreKit)
    func refresh() async {
        var active = false
        var exp: Date?
        var activeID: String?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let t) = result, Self.ids.contains(t.productID), t.revocationDate == nil else { continue }
            let until = t.expirationDate ?? .distantFuture
            if until > .now {
                active = true
                if exp == nil || until > exp! { exp = until; activeID = t.productID }
            }
        }
        storeActive = active
        expiration = exp
        willRenew = true
        billingIssue = false
        if let id = activeID, let product = products.first(where: { $0.id == id }),
           let statuses = try? await product.subscription?.status {
            for st in statuses {
                if case .verified(let info) = st.renewalInfo { willRenew = info.willAutoRenew }
                if st.state == .inBillingRetryPeriod || st.state == .inGracePeriod { billingIssue = true }
            }
        }
    }

    func purchase(_ product: Product) async {
        busy = true
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                switch verification {
                case .verified(let t):
                    await t.finish()
                    await refresh()
                    Haptics.success()
                case .unverified:
                    message = "Не удалось подтвердить покупку. Если деньги списаны, нажмите «Восстановить покупки»."
                }
            case .pending:
                message = "Покупка ожидает подтверждения (например, от родителя). Подписка включится автоматически."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = "Ошибка оплаты: \(error.localizedDescription)"
        }
    }

    func restore() async {
        busy = true
        defer { busy = false }
        do {
            try await AppStore.sync()
            await refresh()
            if !storeActive { message = "Активных подписок Flamio+ не найдено." }
        } catch {
            message = "Не удалось восстановить покупки: \(error.localizedDescription)"
        }
    }

    private func handle(_ result: VerificationResult<StoreKit.Transaction>) async {
        if case .verified(let t) = result { await t.finish() }
        await refresh()
    }

    // MARK: форматирование
    static func period(_ p: Product.SubscriptionPeriod) -> String {
        let n = p.value
        func plural(_ one: String, _ few: String, _ many: String) -> String {
            let m10 = n % 10, m100 = n % 100
            if m10 == 1 && m100 != 11 { return "\(n) \(one)" }
            if (2...4).contains(m10) && !(12...14).contains(m100) { return "\(n) \(few)" }
            return "\(n) \(many)"
        }
        switch p.unit {
        case .day: return plural("день", "дня", "дней")
        case .week: return plural("неделя", "недели", "недель")
        case .month: return plural("месяц", "месяца", "месяцев")
        case .year: return plural("год", "года", "лет")
        @unknown default: return "\(n)"
        }
    }

    var monthly: Product? { products.first { $0.id == Self.monthlyID } }
    var yearly: Product? { products.first { $0.id == Self.yearlyID } }

    /// Экономия годового плана в процентах относительно 12 месяцев по месячной цене
    var yearlySavings: Int? {
        guard let m = monthly, let y = yearly, m.price > 0 else { return nil }
        let ratio = NSDecimalNumber(decimal: y.price / (m.price * 12)).doubleValue
        let pct = Int(((1 - ratio) * 100).rounded())
        return pct > 0 ? pct : nil
    }
}

// MARK: - Темы оформления (часть — только Flamio+)
enum ThemeChoice: String, CaseIterable, Identifiable {
    case night, aurora, sunset
    var id: String { rawValue }
    var title: String { switch self { case .night: "Ночь"; case .aurora: "Аврора"; case .sunset: "Закат" } }
    var plus: Bool { self != .night }
    var palette: (top: Color, bottom: Color, glowA: Color, glowB: Color) {
        switch self {
        case .night: (Theme.bgTop, Theme.bgBottom, Theme.purple, Theme.orange)
        case .aurora: (Color(red: 0.02, green: 0.10, blue: 0.16), Color(red: 0.01, green: 0.03, blue: 0.07),
                       Color(red: 0.1, green: 0.8, blue: 0.6), Theme.purple)
        case .sunset: (Color(red: 0.20, green: 0.05, blue: 0.18), Color(red: 0.05, green: 0.01, blue: 0.05),
                       Color(red: 1.0, green: 0.35, blue: 0.3), Theme.orange)
        }
    }
}

// MARK: - Экран Flamio+
struct PaywallView: View {
    @EnvironmentObject var plus: PlusStore
    @Environment(\.dismiss) var dismiss
    @State private var selectedID = PlusStore.yearlyID
    @State private var manage = false

    // Ссылки обязательны для App Review. Политику конфиденциальности нужно указать свою.
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
    static let privacyURL: URL? = nil

    private let features: [(String, String, String)] = [
        ("cloud.sun.fill", "Лучшее время для прогулки", "Подсказка по часам: когда теплее, суше и тише ветер"),
        ("chart.pie.fill", "Анализ расходов и экспорт", "Средние траты, прогноз на месяц, выгрузка истории в CSV"),
        ("tshirt.fill", "Эксклюзивная одежда питомца", "Корона, медаль и выпускная шапка"),
        ("paintpalette.fill", "Темы «Аврора» и «Закат»", "Новые цвета фона и свечения"),
        ("heart.fill", "Поддержка развития Flamio", "Основные функции остаются бесплатными")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(features, id: \.0) { f in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: f.0).font(.title3).foregroundStyle(Theme.orange).frame(width: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.1).font(.subheadline.weight(.semibold))
                                    Text(f.2).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding().background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))

                    if plus.isPlus { status } else { purchase }
                    legal
                }
                .padding()
            }
            .navigationTitle("Flamio+")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
            .alert("Flamio+", isPresented: Binding(get: { plus.message != nil }, set: { if !$0 { plus.message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(plus.message ?? "") }
            .manageSubscriptionsSheet(isPresented: $manage)
            .task { if plus.products.isEmpty { await plus.loadProducts() } }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "crown.fill").font(.system(size: 40)).foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background(LinearGradient(colors: [Theme.orange, Color(red: 1, green: 0.3, blue: 0.4)], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                .shadow(color: Theme.orange.opacity(0.5), radius: 18)
            Text("Flamio+").font(.largeTitle.bold())
            Text("Больше возможностей для тебя и питомца").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    @ViewBuilder private var purchase: some View {
        if plus.products.isEmpty {
            VStack(spacing: 10) {
                if plus.loading { ProgressView() }
                else {
                    Text("Цены сейчас недоступны").foregroundStyle(.secondary)
                    Button("Повторить") { Task { await plus.loadProducts() } }.buttonStyle(.bordered)
                }
            }
        } else {
            VStack(spacing: 10) {
                ForEach(plus.products.sorted { $0.id == PlusStore.yearlyID && $1.id != PlusStore.yearlyID }) { p in planCard(p) }
            }
            let chosen = plus.products.first { $0.id == selectedID } ?? plus.products[0]
            Button {
                Task { await plus.purchase(chosen) }
            } label: {
                Group {
                    if plus.busy { ProgressView().tint(.white) }
                    else { Text(plus.trialText[chosen.id] != nil ? "Попробовать бесплатно" : "Подписаться").font(.headline) }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(LinearGradient(colors: [Theme.orange, Color(red: 1, green: 0.35, blue: 0.3)], startPoint: .leading, endPoint: .trailing), in: Capsule())
                .foregroundStyle(.white)
            }
            .disabled(plus.busy)
            Button("Восстановить покупки") { Task { await plus.restore() } }
                .font(.footnote).disabled(plus.busy)
        }
    }

    private func planCard(_ p: Product) -> some View {
        let yearly = p.id == PlusStore.yearlyID
        let on = selectedID == p.id
        return Button { selectedID = p.id; Haptics.select() } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(yearly ? "Год" : "Месяц").font(.headline)
                        if yearly, let s = plus.yearlySavings {
                            Text("−\(s)%").font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.orange, in: Capsule()).foregroundStyle(.black)
                        }
                    }
                    if let t = plus.trialText[p.id] { Text(t).font(.caption).foregroundStyle(Theme.orange) }
                    if yearly { Text("\((p.price / 12).formatted(p.priceFormatStyle)) в месяц").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Text(p.displayPrice).font(.headline)
                Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Theme.orange : .secondary)
            }
            .padding()
            .background(on ? Theme.orange.opacity(0.14) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(on ? Theme.orange : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private var status: some View {
        VStack(spacing: 10) {
            Label("Flamio+ активен", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(.green)
            if !plus.storeActive && plus.isPlus {
                Text("Включён тестовый режим личной сборки — подписки в App Store нет.")
                    .font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
            }
            if plus.billingIssue {
                Text("Не удалось списать оплату. Обновите способ оплаты в Apple ID, иначе подписка закончится.")
                    .font(.footnote).foregroundStyle(.orange).multilineTextAlignment(.center)
            }
            if let e = plus.expiration, e < .distantFuture {
                Text(plus.willRenew ? "Продление: \(e.formatted(date: .long, time: .omitted))"
                                    : "Подписка отменена. Доступ сохранится до \(e.formatted(date: .long, time: .omitted))")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Button("Управление подпиской") { manage = true }.buttonStyle(.bordered)
            Button("Восстановить покупки") { Task { await plus.restore() } }.font(.footnote)
        }
        .frame(maxWidth: .infinity).padding().background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
    }

    private var legal: some View {
        VStack(spacing: 6) {
            Text("Оплата списывается с вашего Apple ID при подтверждении покупки. Подписка продлевается автоматически, если не отменить её минимум за 24 часа до конца текущего периода. Управлять подпиской и отключить автопродление можно в настройках Apple ID.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 16) {
                if let u = Self.termsURL { Link("Условия использования", destination: u) }
                if let u = Self.privacyURL { Link("Конфиденциальность", destination: u) }
            }
            .font(.caption2)
        }
    }
}

// MARK: - Мелкие помощники для мест, закрытых Flamio+
struct PlusBadge: View {
    var body: some View {
        Image(systemName: "crown.fill").font(.caption2).foregroundStyle(.black)
            .padding(4).background(Theme.orange, in: Circle())
    }
}
