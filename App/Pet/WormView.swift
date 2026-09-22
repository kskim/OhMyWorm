import SwiftUI

/// Draws the worm, food, and particles on the transparent overlay.
/// Model coordinates (bottom-left origin) are flipped to view coordinates here.
struct WormView: View {
    var controller: PetController

    var body: some View {
        Canvas { context, size in
            draw(context: &context, size: size)
        }
        .frame(width: controller.viewSize.width, height: controller.viewSize.height)
        .accessibilityIdentifier("worm-stage")
    }

    private func convert(_ point: CGPoint, size: CGSize) -> CGPoint {
        CGPoint(
            x: point.x - controller.viewOrigin.x,
            y: size.height - (point.y - controller.viewOrigin.y)
        )
    }

    /// Emoji are color bitmaps: fractional positions make them shimmer
    /// while the panel glides, so text draws snap to whole points.
    private func snap(_ point: CGPoint) -> CGPoint {
        CGPoint(x: round(point.x), y: round(point.y))
    }

    private func draw(context: inout GraphicsContext, size: CGSize) {
        let model = controller.model
        if let food = model.food {
            drawFood(kind: food.kind, at: snap(convert(food.position, size: size)), context: &context)
        }
        drawWorm(model: model, size: size, context: &context)
        drawParticles(model: model, size: size, context: &context)
        if controller.paused {
            context.draw(
                Text("일시정지됨").font(.title3).foregroundColor(.gray),
                at: CGPoint(x: size.width / 2, y: size.height / 2)
            )
        }
    }

    private func drawFood(kind: FoodKind, at point: CGPoint, context: inout GraphicsContext) {
        context.draw(Text(kind.emoji).font(.system(size: 22)), at: point)
    }

    private static let bodyScale = 0.64

    private func drawWorm(model: PetModel, size: CGSize, context: inout GraphicsContext) {
        let k = CGFloat(model.sizeScale) * Self.bodyScale
        let points = model.bodyPoints(count: model.tailSegments, spacing: 8 * k).map { convert($0, size: size) }
        let style = model.skin.style
        context.opacity = style.alpha
        if style.wings {
            drawWings(points: points, phase: model.wigglePhase, k: k,
                      color: style.head.interpolated(to: style.tail, amount: 0.2), context: &context)
        }
        for index in points.indices.reversed() {
            let t = Double(index) / Double(max(points.count - 1, 1))
            let radius = (style.headRadius + (style.tailRadius - style.headRadius) * t) * k
            var center = points[index]
            if index + 1 < points.count {
                let next = points[index + 1]
                let dx = center.x - next.x
                let dy = center.y - next.y
                let len = max((dx * dx + dy * dy).squareRoot(), 0.001)
                let sway = sin(model.wigglePhase - Double(index) * 0.55) * (1.6 + Double(index) * 0.22) * k
                center.x += -dy / len * sway
                center.y += dx / len * sway
            }
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            var color = style.head.interpolated(to: style.tail, amount: t)
            switch style.pattern {
            case .solid:
                break
            case .saddles:
                if index % 3 == 2 {
                    color = style.head.mixed(with: RGB(hex: 0x2A1D12), amount: 0.55)
                }
            }
            context.fill(Circle().path(in: rect), with: .color(color))
        }
        if style.tailAccessory == .rattle, points.count >= 2 {
            drawRattle(points: points, k: k, context: &context)
        }
        drawFace(head: points[0], model: model, size: size, context: &context)
        context.opacity = 1
    }

    private func drawRattle(points: [CGPoint], k: CGFloat, context: inout GraphicsContext) {
        let tip = points[points.count - 1]
        let prev = points[points.count - 2]
        var dx = tip.x - prev.x
        var dy = tip.y - prev.y
        let len = max((dx * dx + dy * dy).squareRoot(), 0.001)
        dx /= len
        dy /= len
        for i in 0..<3 {
            let center = CGPoint(x: tip.x + dx * CGFloat(i) * 4.5 * k, y: tip.y + dy * CGFloat(i) * 4.5 * k)
            let radius = (3.2 - Double(i) * 0.6) * k
            context.fill(
                Circle().path(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(Color(red: 0.79, green: 0.66, blue: 0.42))
            )
        }
    }

    private func drawWings(points: [CGPoint], phase: Double, k: CGFloat, color: Color, context: inout GraphicsContext) {
        guard points.count >= 3 else { return }
        let shoulder = points[1]
        var fx = points[0].x - points[2].x
        var fy = points[0].y - points[2].y
        let len = max((fx * fx + fy * fy).squareRoot(), 0.001)
        fx /= len
        fy /= len
        let sx = -fy
        let sy = fx
        let flap = sin(phase * 0.9)
        for sign: CGFloat in [1, -1] {
            let elbow = CGPoint(
                x: shoulder.x + sx * sign * 9 * k - fx * 1 * k,
                y: shoulder.y + sy * sign * 9 * k - fy * 1 * k
            )
            let tip = CGPoint(
                x: shoulder.x + sx * sign * 17 * k - fx * (5 - flap * 5) * k,
                y: shoulder.y + sy * sign * 17 * k - fy * (5 - flap * 5) * k
            )
            let notch = CGPoint(
                x: shoulder.x + sx * sign * 8 * k - fx * 7 * k,
                y: shoulder.y + sy * sign * 8 * k - fy * 7 * k
            )
            var wing = Path()
            wing.move(to: shoulder)
            wing.addLine(to: elbow)
            wing.addLine(to: tip)
            wing.addLine(to: notch)
            wing.closeSubpath()
            context.fill(wing, with: .color(color.opacity(0.9)))
            var bone = Path()
            bone.move(to: shoulder)
            bone.addLine(to: tip)
            context.stroke(bone, with: .color(.black.opacity(0.25)), lineWidth: 1.2)
        }
    }

    private func drawFace(head: CGPoint, model: PetModel, size: CGSize, context: inout GraphicsContext) {
        let k = CGFloat(model.sizeScale) * Self.bodyScale
        let style = model.skin.style
        let heading = -model.heading
        let forward = CGVector(dx: cos(heading), dy: sin(heading))
        let side = CGVector(dx: -forward.dy, dy: forward.dx)
        let e = style.eyeScale
        for sign in [-1.0, 1.0] {
            let eye = CGPoint(
                x: head.x + forward.dx * 6 * k + side.dx * 5.5 * k * sign,
                y: head.y + forward.dy * 6 * k + side.dy * 5.5 * k * sign
            )
            context.fill(Circle().path(in: CGRect(x: eye.x - 3.2 * k * e, y: eye.y - 3.2 * k * e, width: 6.4 * k * e, height: 6.4 * k * e)), with: .color(.white))
            let pupil = CGPoint(x: eye.x + forward.dx * 1.2 * k, y: eye.y + forward.dy * 1.2 * k)
            context.fill(Circle().path(in: CGRect(x: pupil.x - 1.6 * k * e, y: pupil.y - 1.6 * k * e, width: 3.2 * k * e, height: 3.2 * k * e)), with: .color(.black))
        }
        let mouth = CGPoint(x: head.x + forward.dx * 10 * k, y: head.y + forward.dy * 10 * k)
        switch style.accessory {
        case .none:
            break
        case .horns:
            for sign in [-1.0, 1.0] {
                let base = CGPoint(
                    x: head.x - forward.dx * 2 * k + side.dx * 5 * k * sign,
                    y: head.y - forward.dy * 2 * k + side.dy * 5 * k * sign
                )
                let tip = CGPoint(
                    x: base.x - forward.dx * 8 * k + side.dx * 3 * k * sign,
                    y: base.y - forward.dy * 8 * k + side.dy * 3 * k * sign
                )
                var horn = Path()
                horn.move(to: CGPoint(x: base.x + side.dx * 2 * k * sign, y: base.y + side.dy * 2 * k * sign))
                horn.addLine(to: tip)
                horn.addLine(to: CGPoint(x: base.x - side.dx * 2 * k * sign, y: base.y - side.dy * 2 * k * sign))
                horn.closeSubpath()
                context.fill(horn, with: .color(Color(red: 0.93, green: 0.88, blue: 0.74)))
            }
        case .tongue:
            let tip = CGPoint(x: mouth.x + forward.dx * 9 * k, y: mouth.y + forward.dy * 9 * k)
            var tongue = Path()
            tongue.move(to: mouth)
            tongue.addLine(to: tip)
            tongue.move(to: tip)
            tongue.addLine(to: CGPoint(
                x: tip.x + forward.dx * 4.5 * k + side.dx * 2.5 * k,
                y: tip.y + forward.dy * 4.5 * k + side.dy * 2.5 * k
            ))
            tongue.move(to: tip)
            tongue.addLine(to: CGPoint(
                x: tip.x + forward.dx * 4.5 * k - side.dx * 2.5 * k,
                y: tip.y + forward.dy * 4.5 * k - side.dy * 2.5 * k
            ))
            context.stroke(tongue, with: .color(.red.opacity(0.85)), lineWidth: 1.6)
        }
        if model.isEating {
            context.fill(Circle().path(in: CGRect(x: mouth.x - 2 * k, y: mouth.y - 2 * k, width: 4 * k, height: 4 * k)), with: .color(.black.opacity(0.7)))
        } else if model.mood >= 50 || model.isPetted {
            var path = Path()
            path.move(to: CGPoint(x: mouth.x - 3.5 * k, y: mouth.y - k))
            path.addQuadCurve(
                to: CGPoint(x: mouth.x + 3.5 * k, y: mouth.y - k),
                control: CGPoint(x: mouth.x, y: mouth.y + 3.5 * k)
            )
            context.stroke(path, with: .color(.black.opacity(0.7)), lineWidth: 1.4)
        }
    }

    private func drawParticles(model: PetModel, size: CGSize, context: inout GraphicsContext) {
        let s = CGFloat(model.sizeScale)
        for particle in model.particles where particle.age >= 0 {
            let point = convert(particle.position, size: size)
            switch particle.kind {
            case .heart:
                let alpha = max(0, 1 - particle.age / 1.3)
                context.opacity = alpha
                context.draw(
                    Text("❤️").font(.system(size: 12 * s)),
                    at: snap(CGPoint(x: point.x, y: point.y - particle.age * 34))
                )
                context.opacity = 1
            case .crumb:
                let alpha = max(0, 1 - particle.age / 1.0)
                let rect = CGRect(x: point.x - 2 * s, y: point.y - 2 * s, width: 4 * s, height: 4 * s)
                context.fill(Circle().path(in: rect), with: .color(.brown.opacity(alpha)))
            }
        }
    }
}

// MARK: - Skin colors

private struct RGB {
    var r: Double
    var g: Double
    var b: Double

    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    func interpolated(to other: RGB, amount t: Double) -> Color {
        Color(red: r + (other.r - r) * t, green: g + (other.g - g) * t, blue: b + (other.b - b) * t)
    }

    func mixed(with other: RGB, amount t: Double) -> Color {
        interpolated(to: other, amount: t)
    }
}

private enum SkinAccessory {
    case none
    case horns
    case tongue
}

private enum SkinPattern {
    case solid
    case saddles
}

private enum TailAccessory {
    case none
    case rattle
}

private struct SkinStyle {
    var head: RGB
    var tail: RGB
    var headRadius: Double
    var tailRadius: Double
    var pattern: SkinPattern
    var eyeScale: Double
    var alpha: Double
    var accessory: SkinAccessory
    var tailAccessory: TailAccessory
    var wings: Bool
}

private extension WormSkin {
    var style: SkinStyle {
        switch self {
        case .classic:
            return SkinStyle(
                head: RGB(hex: 0x58B368), tail: RGB(hex: 0xB7E4A8),
                headRadius: 9, tailRadius: 5.5,
                pattern: .solid, eyeScale: 1.0, alpha: 1.0,
                accessory: .none, tailAccessory: .none, wings: false
            )
        case .dragon:
            return SkinStyle(
                head: RGB(hex: 0xC0392B), tail: RGB(hex: 0xF5B041),
                headRadius: 9.5, tailRadius: 4.0,
                pattern: .solid, eyeScale: 1.15, alpha: 1.0,
                accessory: .horns, tailAccessory: .none, wings: true
            )
        case .rattlesnake:
            return SkinStyle(
                head: RGB(hex: 0xA67C52), tail: RGB(hex: 0xE0C896),
                headRadius: 8.5, tailRadius: 5.0,
                pattern: .saddles, eyeScale: 1.0, alpha: 1.0,
                accessory: .tongue, tailAccessory: .rattle, wings: false
            )
        }
    }
}
