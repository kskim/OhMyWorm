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

    private func draw(context: inout GraphicsContext, size: CGSize) {
        let model = controller.model
        if let food = model.food {
            drawFood(at: convert(food, size: size), context: &context)
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

    private func drawFood(at point: CGPoint, context: inout GraphicsContext) {
        context.fill(Circle().path(in: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18)), with: .color(.green))
        context.fill(Circle().path(in: CGRect(x: point.x - 5, y: point.y - 6, width: 6, height: 6)), with: .color(.white.opacity(0.5)))
    }

    private static let bodyScale = 0.64

    private func drawWorm(model: PetModel, size: CGSize, context: inout GraphicsContext) {
        let k = CGFloat(model.sizeScale) * Self.bodyScale
        let points = model.bodyPoints(spacing: 8 * k).map { convert($0, size: size) }
        let style = model.skin.style
        context.opacity = style.alpha
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
            if style.striped, (index / 2) % 2 == 1 {
                color = style.head.mixed(with: RGB(hex: 0xFFFFFF), amount: 0.45)
            }
            context.fill(Circle().path(in: rect), with: .color(color))
        }
        drawFace(head: points[0], model: model, size: size, context: &context)
        context.opacity = 1
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
        case .antennae:
            for sign in [-1.0, 1.0] {
                let base = CGPoint(
                    x: head.x + forward.dx * 4 * k + side.dx * 4 * k * sign,
                    y: head.y + forward.dy * 4 * k + side.dy * 4 * k * sign
                )
                let tip = CGPoint(
                    x: base.x + forward.dx * 9 * k + side.dx * 5 * k * sign,
                    y: base.y + forward.dy * 9 * k + side.dy * 5 * k * sign
                )
                var stalk = Path()
                stalk.move(to: base)
                stalk.addLine(to: tip)
                context.stroke(stalk, with: .color(.black.opacity(0.6)), lineWidth: 1.5)
                context.fill(Circle().path(in: CGRect(x: tip.x - 2 * k, y: tip.y - 2 * k, width: 4 * k, height: 4 * k)), with: .color(style.head.interpolated(to: style.tail, amount: 0.3)))
            }
        case .blush:
            for sign in [-1.0, 1.0] {
                let cheek = CGPoint(
                    x: mouth.x + side.dx * 7 * k * sign - forward.dx * 2 * k,
                    y: mouth.y + side.dy * 7 * k * sign - forward.dy * 2 * k
                )
                context.fill(
                    Ellipse().path(in: CGRect(x: cheek.x - 2.8 * k, y: cheek.y - 1.8 * k, width: 5.6 * k, height: 3.6 * k)),
                    with: .color(.pink.opacity(0.7))
                )
            }
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
                    at: CGPoint(x: point.x, y: point.y - particle.age * 34)
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
    case antennae
    case blush
}

private struct SkinStyle {
    var head: RGB
    var tail: RGB
    var headRadius: Double
    var tailRadius: Double
    var striped: Bool
    var eyeScale: Double
    var alpha: Double
    var accessory: SkinAccessory
}

private extension WormSkin {
    var style: SkinStyle {
        switch self {
        case .classic:
            return SkinStyle(
                head: RGB(hex: 0x58B368), tail: RGB(hex: 0xB7E4A8),
                headRadius: 9, tailRadius: 5.5,
                striped: false, eyeScale: 1.0, alpha: 1.0, accessory: .none
            )
        case .berry:
            return SkinStyle(
                head: RGB(hex: 0xE5638C), tail: RGB(hex: 0xFFC9DA),
                headRadius: 8, tailRadius: 4.5,
                striped: true, eyeScale: 1.1, alpha: 1.0, accessory: .blush
            )
        case .honey:
            return SkinStyle(
                head: RGB(hex: 0xD99A3D), tail: RGB(hex: 0xF6DEA8),
                headRadius: 10.5, tailRadius: 7,
                striped: false, eyeScale: 0.9, alpha: 1.0, accessory: .antennae
            )
        case .ghost:
            return SkinStyle(
                head: RGB(hex: 0x6FD3D3), tail: RGB(hex: 0xD9F7F7),
                headRadius: 7.5, tailRadius: 4.5,
                striped: false, eyeScale: 1.35, alpha: 0.7, accessory: .none
            )
        }
    }
}
