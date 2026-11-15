import SwiftUI
import UIKit

// MARK: - Палитра
enum Theme {
    static let orange = Color(red: 1.0, green: 0.56, blue: 0.12)
    static let purple = Color(red: 0.55, green: 0.33, blue: 0.98)
    static let bgTop = Color(red: 0.07, green: 0.03, blue: 0.16)
    static let bgBottom = Color(red: 0.02, green: 0.01, blue: 0.05)
}

// MARK: - Общие стили: стеклянные карточки и градиентные кнопки
extension View {
    func glassCard(_ radius: CGFloat = 20) -> some View {
        background {
            RoundedRectangle(cornerRadius: radius)
                .fill(LinearGradient(colors: [Theme.purple.opacity(0.22), Color.white.opacity(0.04)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(Theme.purple.opacity(0.35), lineWidth: 1))
        }
    }
    /// Оранжевая кнопка со свечением (главные действия)
    func flameButton() -> some View {
        background(LinearGradient(colors: [Color(red: 1, green: 0.65, blue: 0.1), Color(red: 1, green: 0.35, blue: 0.3)],
                                  startPoint: .leading, endPoint: .trailing), in: Capsule())
            .foregroundStyle(.white)
            .shadow(color: Theme.orange.opacity(0.45), radius: 12, y: 4)
    }
    /// Фиолетовая кнопка (второстепенные действия)
    func purpleButton() -> some View {
        background(LinearGradient(colors: [Theme.purple.opacity(0.9), Color(red: 0.4, green: 0.2, blue: 0.8)],
                                  startPoint: .leading, endPoint: .trailing), in: Capsule())
            .foregroundStyle(.white)
    }
}

// MARK: - Тактильная отдача (учитывает настройку)
enum Haptics {
    static var enabled: Bool { UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true }
    static func select() { guard enabled else { return }; UISelectionFeedbackGenerator().selectionChanged() }
    static func tap() { guard enabled else { return }; UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { guard enabled else { return }; UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { guard enabled else { return }; UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

// MARK: - Звёздный фон
private struct SeededRNG: RandomNumberGenerator {
    var s: UInt64
    mutating func next() -> UInt64 {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return s
    }
}

private struct Star {
    let x, y, r, speed, twinkle, phase, depth: Double
}

private struct Ember {
    let x, y, r, rate, phase: Double
}

private enum Sky {
    // Фиксированный seed: звёзды всегда в одних и тех же местах, без пересоздания при перерисовке
    static let stars: [Star] = {
        var g = SeededRNG(s: 0xF1A31)
        return (0..<70).map { i in
            let layer = Double(i % 3)               // 0 дальний, 2 ближний — эффект глубины
            let depth = 0.45 + layer * 0.25
            return Star(x: .random(in: 0...1, using: &g), y: .random(in: 0...1, using: &g),
                        r: 0.5 + layer * 0.45 + .random(in: 0...0.3, using: &g),
                        speed: 0.0008 + layer * 0.0012,
                        twinkle: .random(in: 0.4...1.6, using: &g),
                        phase: .random(in: 0...6.28, using: &g), depth: depth)
        }
    }()
    static let embers: [Ember] = {
        var g = SeededRNG(s: 0xE3BE2)
        return (0..<12).map { _ in
            Ember(x: .random(in: 0.05...0.95, using: &g), y: .random(in: 0.5...1.0, using: &g),
                  r: .random(in: 1.0...2.0, using: &g), rate: .random(in: 0.025...0.06, using: &g),
                  phase: .random(in: 0...1, using: &g))
        }
    }()
}

struct StarField: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var animate: Bool {
        settings.backgroundAnim
            && !(reduce && settings.respectReduceMotion)
            && phase == .active
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        let on = animate
        // 15 кадров/с и только на активном экране — минимум нагрузки на батарею
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !on)) { tl in
            Canvas { ctx, size in
                let t = on ? tl.date.timeIntervalSinceReferenceDate : 0
                for s in Sky.stars {
                    var y = (s.y - t * s.speed).truncatingRemainder(dividingBy: 1)
                    if y < 0 { y += 1 }
                    let x = s.x + (on ? sin(t * 0.12 + s.phase) * 0.010 * s.depth : 0)
                    let tw = on ? 0.5 + 0.5 * sin(t * s.twinkle + s.phase) : 0.7
                    let a = (0.25 + 0.75 * tw) * s.depth
                    let rect = CGRect(x: x * size.width - s.r, y: y * size.height - s.r, width: s.r * 2, height: s.r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(a)))
                }
                guard on else { return }
                // Тёплые искры: медленно поднимаются, плавно появляются и исчезают
                for e in Sky.embers {
                    let life = (t * e.rate + e.phase).truncatingRemainder(dividingBy: 1)
                    let a = sin(life * .pi) * 0.55
                    let px = (e.x + sin(t * 0.3 + e.phase * 6) * 0.01) * size.width
                    let py = (e.y - life * 0.28) * size.height
                    let rect = CGRect(x: px - e.r, y: py - e.r, width: e.r * 2, height: e.r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(Theme.orange.opacity(a)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct FlamioBackground: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var plus: PlusStore

    var body: some View {
        // платная тема без подписки откатывается на «Ночь», выбор пользователя не теряется
        let t = (settings.theme.plus && !plus.isPlus) ? ThemeChoice.night : settings.theme
        let c = t.palette
        ZStack {
            LinearGradient(colors: [c.top, c.bottom], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [c.glowA.opacity(0.28), .clear], center: .topTrailing, startRadius: 0, endRadius: 400)
            RadialGradient(colors: [c.glowB.opacity(0.10), .clear], center: .bottomLeading, startRadius: 0, endRadius: 340)
            StarField()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Активна ли вкладка (чтобы скрытые вкладки не тратили батарею на анимации)
private struct TabActiveKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var tabActive: Bool {
        get { self[TabActiveKey.self] }
        set { self[TabActiveKey.self] = newValue }
    }
}
