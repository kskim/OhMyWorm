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
        let colors = model.skin.colors
        for index in points.indices.reversed() {
            let t = Double(index) / Double(max(points.count - 1, 1))
            let radius = (9 - 3.5 * t) * k
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
            context.fill(Circle().path(in: rect), with: .color(colors.head.interpolated(to: colors.tail, amount: t)))
        }
        drawFace(head: points[0], model: model, size: size, context: &context)
    }

    private func drawFace(head: CGPoint, model: PetModel, size: CGSize, context: inout GraphicsContext) {
        let k = CGFloat(model.sizeScale) * Self.bodyScale
        let heading = -model.heading
        let forward = CGVector(dx: cos(heading), dy: sin(heading))
        let side = CGVector(dx: -forward.dy, dy: forward.dx)
        for sign in [-1.0, 1.0] {
            let eye = CGPoint(
                x: head.x + forward.dx * 6 * k + side.dx * 5.5 * k * sign,
                y: head.y + forward.dy * 6 * k + side.dy * 5.5 * k * sign
            )
            context.fill(Circle().path(in: CGRect(x: eye.x - 3.2 * k, y: eye.y - 3.2 * k, width: 6.4 * k, height: 6.4 * k)), with: .color(.white))
            let pupil = CGPoint(x: eye.x + forward.dx * 1.2 * k, y: eye.y + forward.dy * 1.2 * k)
            context.fill(Circle().path(in: CGRect(x: pupil.x - 1.6 * k, y: pupil.y - 1.6 * k, width: 3.2 * k, height: 3.2 * k)), with: .color(.black))
        }
        let mouth = CGPoint(x: head.x + forward.dx * 10 * k, y: head.y + forward.dy * 10 * k)
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
}

private struct SkinColors {
    var head: RGB
    var tail: RGB
}

private extension WormSkin {
    var colors: SkinColors {
        switch self {
        case .classic: return SkinColors(head: RGB(hex: 0x58B368), tail: RGB(hex: 0xB7E4A8))
        case .berry: return SkinColors(head: RGB(hex: 0xE5638C), tail: RGB(hex: 0xFFC9DA))
        case .honey: return SkinColors(head: RGB(hex: 0xD99A3D), tail: RGB(hex: 0xF6DEA8))
        case .ghost: return SkinColors(head: RGB(hex: 0x6FD3D3), tail: RGB(hex: 0xD9F7F7))
        }
    }
}
