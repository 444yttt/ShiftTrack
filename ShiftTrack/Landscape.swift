import SwiftUI

/// Original landscape for the home header, drawn with `Canvas` (no image assets):
/// sky, sun or moon, clouds, far mountains, a small town on the hill, a road
/// and trees. The palette follows the time of day.
struct LandscapeView: View {
    var date: Date

    var body: some View {
        let palette = LandscapePalette.palette(for: LandscapePalette.Phase(date: date))
        Canvas { context, size in
            LandscapePainter(palette: palette, size: size).paint(&context)
        }
        .accessibilityHidden(true)
    }
}

struct LandscapePalette {
    enum Phase: Equatable {
        case dawn, day, dusk, night

        init(date: Date, calendar: Calendar = .current) {
            self.init(hour: calendar.component(.hour, from: date))
        }

        init(hour: Int) {
            switch hour {
            case 5..<9: self = .dawn
            case 9..<16: self = .day
            case 16..<19: self = .dusk
            default: self = .night
            }
        }

        /// Spoken name of the scene, for previews and tests.
        var name: String {
            switch self {
            case .dawn: "朝"
            case .day: "昼"
            case .dusk: "夕方"
            case .night: "夜"
            }
        }
    }

    var skyTop: Color
    var skyBottom: Color
    var body: Color
    var glow: Color
    /// Position of the sun or moon in unit coordinates.
    var bodyCenter: CGPoint
    var isMoon: Bool
    var showsStars: Bool
    var cloud: Color
    var far: Color
    var mid: Color
    var near: Color
    var road: Color
    var building: Color
    var roof: Color
    var window: Color
    /// Dusk and night light some windows; by day the panes just reflect the sky.
    var windowsLit: Bool
    var tree: Color
    var trunk: Color

    static func palette(for phase: Phase) -> LandscapePalette {
        switch phase {
        case .dawn:
            return LandscapePalette(
                skyTop: Color(hex: 0xF2B49C), skyBottom: Color(hex: 0xFCE7C7),
                body: Color(hex: 0xFFD27A), glow: Color(hex: 0xFFE7B5),
                bodyCenter: CGPoint(x: 0.44, y: 0.4), isMoon: false, showsStars: false,
                cloud: Color(hex: 0xFFF2EA), far: Color(hex: 0xB8A6C4), mid: Color(hex: 0x8EBB7B),
                near: Color(hex: 0x5F9B5C), road: Color(hex: 0xF3E3C6), building: Color(hex: 0x7A7493),
                roof: Color(hex: 0x5E587A), window: Color(hex: 0xFCE9B8), windowsLit: false, tree: Color(hex: 0x4D8A50),
                trunk: Color(hex: 0x6B4E3A)
            )
        case .day:
            return LandscapePalette(
                skyTop: Color(hex: 0x79C1EE), skyBottom: Color(hex: 0xDCF1FA),
                body: Color(hex: 0xFFE27A), glow: Color(hex: 0xFFF5C8),
                bodyCenter: CGPoint(x: 0.8, y: 0.24), isMoon: false, showsStars: false,
                cloud: Color.white, far: Color(hex: 0x9DBACB), mid: Color(hex: 0x9CCB7C),
                near: Color(hex: 0x6EAE5E), road: Color(hex: 0xF5E8CB), building: Color(hex: 0xF4F1EA),
                roof: Color(hex: 0xD86F55), window: Color(hex: 0x8DB3CF), windowsLit: false, tree: Color(hex: 0x4F9452),
                trunk: Color(hex: 0x6B4E3A)
            )
        case .dusk:
            return LandscapePalette(
                skyTop: Color(hex: 0xE5876A), skyBottom: Color(hex: 0xF8CF90),
                body: Color(hex: 0xFFB45E), glow: Color(hex: 0xFFD8A0),
                bodyCenter: CGPoint(x: 0.88, y: 0.44), isMoon: false, showsStars: false,
                cloud: Color(hex: 0xFBD6C0), far: Color(hex: 0x9A7FA2), mid: Color(hex: 0x7C9B69),
                near: Color(hex: 0x557F4E), road: Color(hex: 0xEBCFA7), building: Color(hex: 0x5C5269),
                roof: Color(hex: 0x473F55), window: Color(hex: 0xFFD27A), windowsLit: true, tree: Color(hex: 0x44704A),
                trunk: Color(hex: 0x5A4030)
            )
        case .night:
            return LandscapePalette(
                skyTop: Color(hex: 0x131D35), skyBottom: Color(hex: 0x32456D),
                body: Color(hex: 0xF4F0DC), glow: Color(hex: 0xF4F0DC).opacity(0.22),
                bodyCenter: CGPoint(x: 0.8, y: 0.24), isMoon: true, showsStars: true,
                cloud: Color(hex: 0x41527B), far: Color(hex: 0x2A3A5B), mid: Color(hex: 0x23374A),
                near: Color(hex: 0x1A2B39), road: Color(hex: 0x56607A), building: Color(hex: 0x111A2D),
                roof: Color(hex: 0x0C1322), window: Color(hex: 0xFFD86B), windowsLit: true, tree: Color(hex: 0x14273A),
                trunk: Color(hex: 0x0F1E2C)
            )
        }
    }
}

/// Draws the scene. Every shape is computed from the canvas size, so the
/// picture stays the same at any width.
private struct LandscapePainter {
    var palette: LandscapePalette
    var size: CGSize

    private var w: CGFloat { size.width }
    private var h: CGFloat { size.height }

    private func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x * w, y: y * h)
    }

    func paint(_ context: inout GraphicsContext) {
        sky(&context)
        if palette.showsStars { stars(&context) }
        celestial(&context)
        clouds(&context)
        farMountains(&context)
        town(&context)
        midHill(&context)
        nearHill(&context)
        road(&context)
        trees(&context)
    }

    private func sky(_ context: inout GraphicsContext) {
        let rect = Path(CGRect(origin: .zero, size: size))
        context.fill(rect, with: .linearGradient(
            Gradient(colors: [palette.skyTop, palette.skyBottom]),
            startPoint: .zero,
            endPoint: CGPoint(x: 0, y: h * 0.72)
        ))
    }

    private func stars(_ context: inout GraphicsContext) {
        // Fixed pseudo-random positions so the sky does not flicker between redraws.
        var seed: UInt32 = 0x5EED_1234
        func next() -> CGFloat {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return CGFloat(seed >> 8) / CGFloat(1 << 24)
        }
        for index in 0..<46 {
            let x = next() * w
            let y = next() * h * 0.5
            let radius: CGFloat = index % 7 == 0 ? 1.6 : 0.9
            let star = Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            context.fill(star, with: .color(Color.white.opacity(index % 3 == 0 ? 0.9 : 0.55)))
        }
    }

    private func celestial(_ context: inout GraphicsContext) {
        let center = p(palette.bodyCenter.x, palette.bodyCenter.y)
        let radius = min(w, h) * 0.11
        let glowRadius = radius * 2.6
        let glow = Path(ellipseIn: CGRect(x: center.x - glowRadius, y: center.y - glowRadius, width: glowRadius * 2, height: glowRadius * 2))
        context.fill(glow, with: .radialGradient(
            Gradient(colors: [palette.glow, palette.glow.opacity(0)]),
            center: center,
            startRadius: radius * 0.6,
            endRadius: glowRadius
        ))
        let disc = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        if palette.isMoon {
            context.drawLayer { layer in
                layer.fill(disc, with: .color(palette.body))
                layer.blendMode = .destinationOut
                let bite = Path(ellipseIn: CGRect(x: center.x - radius * 0.45, y: center.y - radius * 1.15, width: radius * 2, height: radius * 2))
                layer.fill(bite, with: .color(.black))
            }
        } else {
            context.fill(disc, with: .color(palette.body))
        }
    }

    private func cloud(at origin: CGPoint, scale: CGFloat, _ context: inout GraphicsContext) {
        var path = Path()
        let unit = min(w, h) * 0.07 * scale
        path.addRoundedRect(
            in: CGRect(x: origin.x, y: origin.y, width: unit * 5, height: unit * 1.3),
            cornerSize: CGSize(width: unit * 0.65, height: unit * 0.65)
        )
        path.addEllipse(in: CGRect(x: origin.x + unit * 0.7, y: origin.y - unit * 0.9, width: unit * 1.8, height: unit * 1.8))
        path.addEllipse(in: CGRect(x: origin.x + unit * 2.0, y: origin.y - unit * 1.4, width: unit * 2.2, height: unit * 2.2))
        path.addEllipse(in: CGRect(x: origin.x + unit * 3.3, y: origin.y - unit * 0.6, width: unit * 1.4, height: unit * 1.4))
        context.fill(path, with: .color(palette.cloud.opacity(palette.isMoon ? 0.55 : 0.92)))
    }

    private func clouds(_ context: inout GraphicsContext) {
        cloud(at: p(0.06, 0.2), scale: 1.0, &context)
        cloud(at: p(0.46, 0.12), scale: 0.7, &context)
        cloud(at: p(0.62, 0.36), scale: 0.55, &context)
    }

    private func farMountains(_ context: inout GraphicsContext) {
        var path = Path()
        path.move(to: p(0, 0.6))
        path.addQuadCurve(to: p(0.16, 0.42), control: p(0.08, 0.46))
        path.addQuadCurve(to: p(0.33, 0.54), control: p(0.24, 0.4))
        path.addQuadCurve(to: p(0.52, 0.36), control: p(0.42, 0.38))
        path.addQuadCurve(to: p(0.72, 0.52), control: p(0.62, 0.36))
        path.addQuadCurve(to: p(0.88, 0.4), control: p(0.8, 0.44))
        path.addQuadCurve(to: p(1, 0.5), control: p(0.95, 0.4))
        path.addLine(to: p(1, 0.8))
        path.addLine(to: p(0, 0.8))
        path.closeSubpath()
        context.fill(path, with: .color(palette.far))
    }

    private func town(_ context: inout GraphicsContext) {
        // (x, width, height) in unit coordinates; bases sit behind the mid hill.
        let blocks: [(CGFloat, CGFloat, CGFloat)] = [
            (0.62, 0.05, 0.13), (0.675, 0.055, 0.19), (0.737, 0.042, 0.11),
            (0.785, 0.06, 0.16), (0.852, 0.045, 0.22), (0.904, 0.055, 0.12)
        ]
        let base: CGFloat = 0.7
        for (index, block) in blocks.enumerated() {
            let rect = CGRect(x: block.0 * w, y: (base - block.2) * h, width: block.1 * w, height: block.2 * h)
            context.fill(Path(rect), with: .color(palette.building))
            let roofHeight = rect.width * 0.35
            var roof = Path()
            if index % 2 == 0 {
                roof.move(to: CGPoint(x: rect.minX - 1, y: rect.minY))
                roof.addLine(to: CGPoint(x: rect.midX, y: rect.minY - roofHeight))
                roof.addLine(to: CGPoint(x: rect.maxX + 1, y: rect.minY))
                roof.closeSubpath()
            } else {
                roof.addRect(CGRect(x: rect.minX - 1, y: rect.minY - 3, width: rect.width + 2, height: 3))
            }
            context.fill(roof, with: .color(palette.roof))
            // Windows on a small grid.
            let columns = 2
            let rows = max(1, Int(block.2 * 20))
            let cellW = rect.width / CGFloat(columns * 2 + 1)
            let cellH = min(cellW * 1.2, rect.height / CGFloat(rows * 2 + 1))
            for row in 0..<rows {
                for column in 0..<columns {
                    // Lit scenes leave a few windows dark so the town does not look like a grid.
                    if palette.windowsLit, (row + column + index) % 3 == 0 { continue }
                    let window = CGRect(
                        x: rect.minX + cellW * CGFloat(column * 2 + 1),
                        y: rect.minY + cellH * CGFloat(row * 2 + 1),
                        width: cellW,
                        height: cellH
                    )
                    context.fill(Path(window), with: .color(palette.window))
                }
            }
        }
    }

    private func midHill(_ context: inout GraphicsContext) {
        var path = Path()
        path.move(to: p(0, 0.72))
        path.addCurve(to: p(0.5, 0.66), control1: p(0.18, 0.62), control2: p(0.34, 0.7))
        path.addCurve(to: p(1, 0.6), control1: p(0.68, 0.62), control2: p(0.86, 0.6))
        path.addLine(to: p(1, 1))
        path.addLine(to: p(0, 1))
        path.closeSubpath()
        context.fill(path, with: .color(palette.mid))
    }

    private func nearHill(_ context: inout GraphicsContext) {
        var path = Path()
        path.move(to: p(0, 0.84))
        path.addCurve(to: p(1, 0.86), control1: p(0.3, 0.74), control2: p(0.7, 0.8))
        path.addLine(to: p(1, 1))
        path.addLine(to: p(0, 1))
        path.closeSubpath()
        context.fill(path, with: .color(palette.near))
    }

    private func road(_ context: inout GraphicsContext) {
        // A path that narrows towards the town.
        var path = Path()
        path.move(to: p(0.58, 1))
        path.addCurve(to: p(0.755, 0.69), control1: p(0.66, 0.9), control2: p(0.78, 0.8))
        path.addLine(to: p(0.775, 0.69))
        path.addCurve(to: p(0.8, 1), control1: p(0.83, 0.8), control2: p(0.74, 0.9))
        path.closeSubpath()
        context.fill(path, with: .color(palette.road))
    }

    private func trees(_ context: inout GraphicsContext) {
        let spots: [(CGFloat, CGFloat, CGFloat)] = [
            (0.06, 0.86, 1.0), (0.11, 0.84, 0.8), (0.5, 0.8, 0.9), (0.55, 0.81, 0.7),
            (0.9, 0.86, 1.0), (0.96, 0.87, 0.85), (0.3, 0.69, 0.6), (0.97, 0.62, 0.55)
        ]
        let unit = min(w, h) * 0.06
        for spot in spots {
            let base = p(spot.0, spot.1)
            let size = unit * spot.2
            let trunk = CGRect(x: base.x - size * 0.12, y: base.y - size * 0.5, width: size * 0.24, height: size * 0.6)
            context.fill(Path(trunk), with: .color(palette.trunk))
            let crown = CGRect(x: base.x - size * 0.6, y: base.y - size * 1.6, width: size * 1.2, height: size * 1.25)
            context.fill(Path(ellipseIn: crown), with: .color(palette.tree))
        }
    }
}

/// Header of the home screen: the landscape with a paper plate holding the
/// date and the dot-matrix clock. The plate keeps text at 4.5:1 or more on
/// any sky.
struct LandscapeHeader: View {
    var now: Date
    @ScaledMetric(relativeTo: .largeTitle) private var height: CGFloat = 220

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LandscapeView(date: now)
                .frame(maxWidth: .infinity)
                .frame(height: min(height, 300))
            VStack(alignment: .leading, spacing: 0) {
                Text(Formatters.longDay(now))
                    .font(AppFont.label)
                    .foregroundStyle(Theme.ink2)
                    .accessibilityIdentifier("today.clock")
                DotoText(
                    Formatters.clock(of: now),
                    size: 60,
                    spoken: "現在 \(Formatters.spokenClock(of: now))",
                    maxScale: 1.3
                )
                .contentTransition(.numericText())
                .accessibilityIdentifier("today.time")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Theme.paper.opacity(0.94), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .padding(Space.s)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.hero, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
                .stroke(Theme.ink.opacity(0.08), lineWidth: 1)
        )
    }
}
