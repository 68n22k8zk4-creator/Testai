import SwiftUI

// MARK: - Огонёк
private struct FlameShape: Shape {
    var sway: CGFloat   // -1...1 — наклон языка пламени
    var animatableData: CGFloat { get { sway } set { sway = newValue } }
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        var p = Path()
        let tip = CGPoint(x: r.midX + sway * w * 0.14, y: r.minY)
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addCurve(to: tip,
                   control1: CGPoint(x: r.minX - w * 0.06, y: r.maxY - h * 0.12),
                   control2: CGPoint(x: r.minX + w * 0.12 + sway * w * 0.06, y: r.minY + h * 0.46))
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY),
                   control1: CGPoint(x: r.maxX - w * 0.12 + sway * w * 0.06, y: r.minY + h * 0.46),
                   control2: CGPoint(x: r.maxX + w * 0.06, y: r.maxY - h * 0.12))
        p.closeSubpath()
        return p
    }
}

/// Горящий огонёк: три слоя пламени колышутся независимо, свечение пульсирует
struct FlameView: View {
    var lit = true
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.tabActive) private var tabActive
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduce

    private var amp: Double { (reduce && settings.respectReduceMotion) ? 0.25 : 1 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !(tabActive && phase == .active))) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            GeometryReader { g in
                let w = g.size.width, h = g.size.height
                ZStack(alignment: .bottom) {
                    Circle()
                        .fill(Theme.orange.opacity(lit ? 0.30 + 0.14 * sin(t * 6.5) * amp : 0.05))
                        .blur(radius: w * 0.22)
                        .frame(width: w * 0.9, height: w * 0.9)
                        .offset(y: -h * 0.08)
                    layer(t: t, phase: 0.0, speed: 2.9, scale: 1.00,
                          colors: [Color(red: 1, green: 0.25, blue: 0.1), Color(red: 1, green: 0.55, blue: 0.1)], w: w, h: h)
                    layer(t: t, phase: 1.7, speed: 3.7, scale: 0.72,
                          colors: [Color(red: 1, green: 0.5, blue: 0.1), Color(red: 1, green: 0.8, blue: 0.2)], w: w, h: h)
                    layer(t: t, phase: 3.1, speed: 4.6, scale: 0.42,
                          colors: [Color(red: 1, green: 0.85, blue: 0.3), Color(red: 1, green: 0.97, blue: 0.7)], w: w, h: h)
                }
                .frame(width: w, height: h, alignment: .bottom)
                .saturation(lit ? 1 : 0)
            }
        }
        .accessibilityHidden(true)
    }

    private func layer(t: Double, phase: Double, speed: Double, scale: CGFloat, colors: [Color], w: CGFloat, h: CGFloat) -> some View {
        let sway = CGFloat(sin(t * speed + phase) * 0.8 + sin(t * speed * 2.3 + phase) * 0.2) * CGFloat(amp)
        let flick = 1 + 0.07 * sin(t * speed * 2.1 + phase) * amp         // высота «дышит»
        let squash = 1 - 0.03 * sin(t * speed * 1.7 + phase) * amp
        return FlameShape(sway: sway)
            .fill(LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top))
            .frame(width: w * 0.8 * scale * squash, height: h * 0.92 * scale * flick)
    }
}

// MARK: - Часы с настоящими стрелками
struct ClockView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.tabActive) private var tabActive
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        // 20 кадров/с нужны только для плавной секундной стрелки
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !(tabActive && phase == .active))) { tl in
            face(date: tl.date)
        }
        .accessibilityHidden(true)
    }

    private func face(date: Date) -> some View {
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let ns = Double(c.nanosecond ?? 0) / 1_000_000_000
        let discrete = reduce && settings.respectReduceMotion
        let sec = Double(c.second ?? 0) + (discrete ? 0 : ns)
        let mins = Double(c.minute ?? 0) + sec / 60
        let hr = Double((c.hour ?? 0) % 12) + mins / 60
        return GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            ZStack {
                Circle().fill(Color(red: 0.12, green: 0.07, blue: 0.25))
                Circle().stroke(Theme.purple, lineWidth: max(1.5, s * 0.07))
                ForEach(0..<12, id: \.self) { i in
                    Capsule().fill(Color.white.opacity(i % 3 == 0 ? 0.85 : 0.35))
                        .frame(width: max(1, s * 0.03), height: s * (i % 3 == 0 ? 0.10 : 0.06))
                        .offset(y: -s * 0.36)
                        .rotationEffect(.degrees(Double(i) * 30))
                }
                hand(length: 0.24, width: 0.07, color: .white, angle: hr * 30, size: s)
                hand(length: 0.34, width: 0.05, color: .white, angle: mins * 6, size: s)
                hand(length: 0.37, width: 0.025, color: Theme.orange, angle: sec * 6, size: s)
                Circle().fill(Theme.orange).frame(width: s * 0.1, height: s * 0.1)
            }
            .frame(width: s, height: s)
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
    }

    private func hand(length: CGFloat, width: CGFloat, color: Color, angle: Double, size s: CGFloat) -> some View {
        Capsule().fill(color)
            .frame(width: max(1, s * width), height: s * length)
            .offset(y: -s * length / 2)
            .rotationEffect(.degrees(angle))
    }
}
