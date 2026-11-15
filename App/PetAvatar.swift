import SwiftUI

// MARK: - Формы
private struct Tri: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

private struct Dome: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.maxY),
                   control1: CGPoint(x: r.minX, y: r.minY - r.height * 0.35),
                   control2: CGPoint(x: r.maxX, y: r.minY - r.height * 0.35))
        p.closeSubpath()
        return p
    }
}

private struct CrownShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.2))
        p.addLine(to: CGPoint(x: r.width * 0.25, y: r.height * 0.55))
        p.addLine(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.width * 0.75, y: r.height * 0.55))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.2))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Дуга: curve > 0 — улыбка/«n» вверх, curve < 0 — вниз
private struct Curve: Shape {
    var curve: CGFloat
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY), control: CGPoint(x: r.midX, y: r.midY + curve))
        return p
    }
}

// MARK: - Палитра лисы
private enum Fur {
    static let orange = Color(red: 1.0, green: 0.52, blue: 0.14)
    static let dark = Color(red: 0.88, green: 0.38, blue: 0.08)
    static let cream = Color(red: 1.0, green: 0.93, blue: 0.82)
    static let brown = Color(red: 0.26, green: 0.12, blue: 0.08)
    static let pink = Color(red: 1.0, green: 0.62, blue: 0.62)
}

// MARK: - Питомец (векторный, слоистый, анимированный)
struct PetAvatar: View {
    var mood: PetMood
    var outfit: [String: String]
    var hop: Int = 0

    @EnvironmentObject private var settings: AppSettings
    @Environment(\.tabActive) private var tabActive
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var lift: CGFloat = 0

    private var amp: Double { (reduce && settings.respectReduceMotion) ? 0.3 : 1 }

    var body: some View {
        GeometryReader { g in
            let sc = min(g.size.width / 200, g.size.height / 230)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !(tabActive && phase == .active))) { tl in
                figure(t: tl.date.timeIntervalSinceReferenceDate)
                    .frame(width: 200, height: 230)
                    .offset(y: lift)
                    .scaleEffect(sc)
                    .frame(width: g.size.width, height: g.size.height)
            }
        }
        .onChange(of: hop) { _, _ in jump() }
    }

    private func jump() {
        Task { @MainActor in
            withAnimation(.easeOut(duration: 0.14)) { lift = -18 }
            try? await Task.sleep(for: .milliseconds(140))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.45)) { lift = 0 }
        }
    }

    private func item(_ s: Slot) -> String? { outfit[s.rawValue] }

    // MARK: сборка
    private func figure(t: Double) -> some View {
        let breathe = sin(t * 1.7) * amp
        let lean = sin(t * 0.35) * amp           // медленная смена позы
        return ZStack {
            Ellipse().fill(Color.black.opacity(0.28)).frame(width: 118, height: 14).position(x: 100, y: 216)
            tail(t: t, lean: lean)
            ZStack {
                bodyLayer
                bottomLayer
                topLayer
                shoesLayer
                bodyAccessory
            }
            .scaleEffect(x: 1 + 0.01 * breathe, y: 1 + 0.025 * breathe, anchor: UnitPoint(x: 0.5, y: 0.92))
            head(t: t, lean: lean)
            if mood == .happy { hearts(t: t) }
            if mood == .sleep { zzz(t: t) }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.65), value: outfit)
    }

    // MARK: хвост
    private func tail(t: Double, lean: Double) -> some View {
        let speed = mood == .happy ? 5.0 : (mood == .sad || mood == .sleep ? 0.8 : 1.8)
        let swing = (mood == .happy ? 14.0 : 7.0) * amp
        let angle = -30 + sin(t * speed) * swing + lean * 3
        return ZStack(alignment: .trailing) {
            Capsule().fill(Fur.orange).frame(width: 84, height: 40)
            Circle().fill(Fur.cream).frame(width: 34, height: 34).offset(x: 6)
        }
        .frame(width: 84, height: 40)
        .rotationEffect(.degrees(angle), anchor: .leading)
        .position(x: 172, y: 170)
    }

    // MARK: тело и слои одежды
    private var bodyLayer: some View {
        ZStack {
            Ellipse().fill(Fur.orange).frame(width: 96, height: 92).position(x: 100, y: 165)
            Ellipse().fill(Fur.cream).frame(width: 56, height: 62).position(x: 100, y: 172)
            Ellipse().fill(Fur.brown).frame(width: 30, height: 18).position(x: 78, y: 206)
            Ellipse().fill(Fur.brown).frame(width: 30, height: 18).position(x: 122, y: 206)
        }
    }

    @ViewBuilder private var bottomLayer: some View {
        switch item(.bottom) {
        case "jeans":
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.22, green: 0.38, blue: 0.75)).frame(width: 90, height: 32)
                Rectangle().fill(Color.white.opacity(0.25)).frame(width: 2, height: 30)
                Capsule().fill(Color(red: 0.14, green: 0.24, blue: 0.5)).frame(width: 90, height: 6).offset(y: -13)
            }
            .position(x: 100, y: 194).transition(.scale(scale: 0.3).combined(with: .opacity))
        case "shorts":
            RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.85, green: 0.7, blue: 0.4)).frame(width: 90, height: 24)
                .position(x: 100, y: 192).transition(.scale(scale: 0.3).combined(with: .opacity))
        default: EmptyView()
        }
    }

    @ViewBuilder private var topLayer: some View {
        switch item(.top) {
        case "hoodie":
            ZStack {
                Ellipse().fill(Color(red: 0.5, green: 0.32, blue: 0.9)).frame(width: 102, height: 74)
                RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.16)).frame(width: 42, height: 18).offset(y: 14)
                Capsule().fill(Color(red: 0.4, green: 0.24, blue: 0.78)).frame(width: 56, height: 11).offset(y: -32)
            }
            .position(x: 100, y: 158).transition(.scale(scale: 0.3).combined(with: .opacity))
        case "sweater":
            ZStack {
                Ellipse().fill(Color(red: 0.8, green: 0.2, blue: 0.3)).frame(width: 100, height: 72)
                Capsule().fill(Color.white.opacity(0.35)).frame(width: 86, height: 7).offset(y: 2)
                Capsule().fill(Color.white.opacity(0.35)).frame(width: 80, height: 7).offset(y: 16)
                Capsule().fill(Color(red: 0.65, green: 0.14, blue: 0.24)).frame(width: 44, height: 10).offset(y: -31)
            }
            .position(x: 100, y: 158).transition(.scale(scale: 0.3).combined(with: .opacity))
        case "tshirt":
            ZStack {
                Ellipse().fill(Color(red: 0.4, green: 0.8, blue: 0.9)).frame(width: 98, height: 62)
                Capsule().fill(Color(red: 0.3, green: 0.65, blue: 0.78)).frame(width: 36, height: 8).offset(y: -27)
            }
            .position(x: 100, y: 153).transition(.scale(scale: 0.3).combined(with: .opacity))
        default: EmptyView()
        }
    }

    @ViewBuilder private var shoesLayer: some View {
        switch item(.shoes) {
        case "sneakers":
            ZStack {
                shoe(Color.white, sole: Color(red: 0.4, green: 0.3, blue: 0.9)).position(x: 78, y: 208)
                shoe(Color.white, sole: Color(red: 0.4, green: 0.3, blue: 0.9)).position(x: 122, y: 208)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        case "boots":
            ZStack {
                shoe(Color(red: 0.45, green: 0.28, blue: 0.14), sole: Color(red: 0.25, green: 0.14, blue: 0.08)).position(x: 78, y: 207)
                shoe(Color(red: 0.45, green: 0.28, blue: 0.14), sole: Color(red: 0.25, green: 0.14, blue: 0.08)).position(x: 122, y: 207)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        default: EmptyView()
        }
    }

    private func shoe(_ c: Color, sole: Color) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 8).fill(c).frame(width: 34, height: 18)
            Capsule().fill(sole).frame(width: 36, height: 5)
        }
    }

    @ViewBuilder private var bodyAccessory: some View {
        switch item(.accessory) {
        case "scarf":
            ZStack {
                Capsule().fill(Color(red: 0.85, green: 0.15, blue: 0.2)).frame(width: 86, height: 17).position(x: 100, y: 134)
                RoundedRectangle(cornerRadius: 5).fill(Color(red: 0.72, green: 0.1, blue: 0.16)).frame(width: 15, height: 32)
                    .rotationEffect(.degrees(-8)).position(x: 122, y: 150)
            }
            .transition(.scale(scale: 0.4).combined(with: .opacity))
        case "bowtie":
            ZStack {
                Tri().fill(Color(red: 0.8, green: 0.1, blue: 0.4)).frame(width: 22, height: 22).rotationEffect(.degrees(-90)).position(x: 86, y: 136)
                Tri().fill(Color(red: 0.8, green: 0.1, blue: 0.4)).frame(width: 22, height: 22).rotationEffect(.degrees(90)).position(x: 114, y: 136)
                Circle().fill(Color(red: 0.62, green: 0.06, blue: 0.3)).frame(width: 10, height: 10).position(x: 100, y: 136)
            }
            .transition(.scale(scale: 0.4).combined(with: .opacity))
        case "medal":
            ZStack {
                Capsule().fill(Color(red: 0.3, green: 0.4, blue: 0.9)).frame(width: 8, height: 26).position(x: 100, y: 140)
                Circle().fill(Color(red: 1, green: 0.8, blue: 0.2)).frame(width: 20, height: 20)
                    .overlay(Text("★").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(red: 0.8, green: 0.5, blue: 0.1)))
                    .position(x: 100, y: 158)
            }
            .transition(.scale(scale: 0.4).combined(with: .opacity))
        default: EmptyView()
        }
    }

    // MARK: голова
    private func blinking(_ t: Double) -> Bool { t.truncatingRemainder(dividingBy: 4.3) < 0.14 }

    private func head(t: Double, lean: Double) -> some View {
        let tilt = (mood == .wait ? 6.0 : 2.0) * sin(t * 0.9) * amp + lean * 1.5
        let bob = sin(t * 1.7 + 0.6) * 1.6 * amp
        let twitch = (mood == .wait && sin(t * 3.1) > 0.92) ? 8.0 : 0.0
        let closed = mood == .sleep || blinking(t)
        let look = mood == .wait ? CGFloat(sin(t * 0.8) * 3) : 0
        return ZStack {
            ear(left: true, twitch: twitch)
            ear(left: false, twitch: 0)
            Ellipse().fill(Fur.orange).frame(width: 124, height: 104).position(x: 100, y: 92)
            Ellipse().fill(Fur.cream).frame(width: 62, height: 50).position(x: 77, y: 110)
            Ellipse().fill(Fur.cream).frame(width: 62, height: 50).position(x: 123, y: 110)
            Ellipse().fill(Fur.cream).frame(width: 48, height: 36).position(x: 100, y: 113)
            Ellipse().fill(Fur.pink.opacity(0.5)).frame(width: 16, height: 10).position(x: 58, y: 104)
            Ellipse().fill(Fur.pink.opacity(0.5)).frame(width: 16, height: 10).position(x: 142, y: 104)
            eye(x: 76, closed: closed, look: look)
            eye(x: 124, closed: closed, look: look)
            if mood == .sad { brows; tear(t: t) }
            Ellipse().fill(Fur.brown).frame(width: 14, height: 10).position(x: 100, y: 103)
            mouth
            headAccessory
            hat
        }
        .rotationEffect(.degrees(tilt), anchor: UnitPoint(x: 0.5, y: 0.55))
        .offset(x: CGFloat(lean * 2), y: CGFloat(bob))
    }

    private func ear(left: Bool, twitch: Double) -> some View {
        ZStack {
            Tri().fill(Fur.dark).frame(width: 42, height: 50)
            Tri().fill(Fur.pink).frame(width: 22, height: 28).offset(y: 8)
        }
        .rotationEffect(.degrees((left ? -16 : 16) + (left ? -twitch : twitch)), anchor: .bottom)
        .position(x: left ? 62 : 138, y: 48)
    }

    @ViewBuilder private func eye(x: CGFloat, closed: Bool, look: CGFloat) -> some View {
        if mood == .happy {
            Curve(curve: -9).stroke(Fur.brown, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .frame(width: 20, height: 10).position(x: x, y: 88)
        } else if closed {
            Curve(curve: 8).stroke(Fur.brown, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .frame(width: 20, height: 10).position(x: x, y: 90)
        } else {
            ZStack {
                Circle().fill(Fur.brown).frame(width: 19, height: 19)
                Circle().fill(Color.white).frame(width: 6, height: 6).offset(x: 3, y: -4)
            }
            .offset(x: look).position(x: x, y: 88)
        }
    }

    private var brows: some View {
        ZStack {
            Capsule().fill(Fur.brown).frame(width: 18, height: 4).rotationEffect(.degrees(-18)).position(x: 76, y: 74)
            Capsule().fill(Fur.brown).frame(width: 18, height: 4).rotationEffect(.degrees(18)).position(x: 124, y: 74)
        }
    }

    private func tear(t: Double) -> some View {
        let p = t.truncatingRemainder(dividingBy: 2.2) / 2.2
        return Ellipse().fill(Color(red: 0.5, green: 0.8, blue: 1)).frame(width: 7, height: 10)
            .opacity(1 - p).position(x: 68, y: 98 + p * 22)
    }

    @ViewBuilder private var mouth: some View {
        switch mood {
        case .happy:
            ZStack {
                Ellipse().fill(Color(red: 0.55, green: 0.1, blue: 0.15)).frame(width: 20, height: 15)
                Ellipse().fill(Fur.pink).frame(width: 11, height: 7).offset(y: 4)
            }
            .position(x: 100, y: 120)
        case .sad:
            Curve(curve: -8).stroke(Fur.brown, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 22, height: 10).position(x: 100, y: 122)
        case .sleep:
            Curve(curve: 3).stroke(Fur.brown, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 14, height: 6).position(x: 100, y: 118)
        default:
            Curve(curve: 9).stroke(Fur.brown, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 24, height: 10).position(x: 100, y: 116)
        }
    }

    @ViewBuilder private var headAccessory: some View {
        if item(.accessory) == "glasses" {
            ZStack {
                Circle().fill(Color.black.opacity(0.78)).frame(width: 30, height: 30).position(x: 76, y: 88)
                Circle().fill(Color.black.opacity(0.78)).frame(width: 30, height: 30).position(x: 124, y: 88)
                Rectangle().fill(Color.black).frame(width: 20, height: 3).position(x: 100, y: 86)
                Capsule().fill(Color.white.opacity(0.3)).frame(width: 8, height: 3).rotationEffect(.degrees(-35)).position(x: 70, y: 81)
            }
            .transition(.scale(scale: 0.4).combined(with: .opacity))
        }
    }

    @ViewBuilder private var hat: some View {
        switch item(.head) {
        case "cap":
            ZStack {
                Dome().fill(Color(red: 0.25, green: 0.4, blue: 0.9)).frame(width: 98, height: 38).position(x: 100, y: 52)
                Capsule().fill(Color(red: 0.16, green: 0.28, blue: 0.7)).frame(width: 52, height: 9).position(x: 128, y: 62)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        case "tophat":
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.12, green: 0.1, blue: 0.16)).frame(width: 58, height: 46).position(x: 100, y: 34)
                Rectangle().fill(Color(red: 0.8, green: 0.15, blue: 0.2)).frame(width: 58, height: 8).position(x: 100, y: 50)
                Capsule().fill(Color(red: 0.12, green: 0.1, blue: 0.16)).frame(width: 90, height: 10).position(x: 100, y: 58)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        case "crown":
            CrownShape().fill(Color(red: 1, green: 0.8, blue: 0.2)).frame(width: 66, height: 34).position(x: 100, y: 44)
                .overlay(Circle().fill(Color(red: 0.9, green: 0.2, blue: 0.4)).frame(width: 8, height: 8).offset(y: 8))
                .transition(.move(edge: .top).combined(with: .opacity))
        case "grad":
            ZStack {
                Rectangle().fill(Color(red: 0.12, green: 0.12, blue: 0.16)).frame(width: 44, height: 16).position(x: 100, y: 56)
                Rectangle().fill(Color(red: 0.15, green: 0.15, blue: 0.2)).frame(width: 66, height: 66)
                    .rotationEffect(.degrees(45)).scaleEffect(x: 1, y: 0.38).position(x: 100, y: 46)
                Capsule().fill(Color(red: 1, green: 0.8, blue: 0.2)).frame(width: 4, height: 24).position(x: 134, y: 56)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        default: EmptyView()
        }
    }

    // MARK: эффекты
    private func hearts(t: Double) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let p = (t * 0.6 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                Text("❤️").font(.system(size: 16))
                    .opacity(sin(p * .pi))
                    .position(x: 52 + CGFloat(i) * 48 + CGFloat(sin(t + Double(i))) * 5, y: 30 - p * 36)
            }
        }
    }

    private func zzz(t: Double) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let p = (t * 0.35 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                Text("z").font(.system(size: 12 + CGFloat(i) * 5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.75, green: 0.7, blue: 1))
                    .opacity(sin(p * .pi))
                    .position(x: 150 + p * 18, y: 40 - p * 28)
            }
        }
    }
}
