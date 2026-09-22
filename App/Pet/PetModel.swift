import Foundation

// MARK: - Skin

enum WormSkin: String, CaseIterable, Identifiable, Sendable {
    case classic
    case dragon
    case rattlesnake

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return L10n.text("예쁜꼬마선충", "C. elegans")
        case .dragon: return L10n.text("드레곤", "Dragon")
        case .rattlesnake: return L10n.text("방울뱀", "Rattlesnake")
        }
    }

    func next() -> WormSkin {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }

    /// Body length in segments. Part of each skin's identity.
    var segments: Int {
        switch self {
        case .classic: return 16
        case .dragon: return 15
        case .rattlesnake: return 17
        }
    }
}

// MARK: - Food

enum FoodKind: String, CaseIterable, Sendable {
    case apple, banana, orange, grape, melon

    var emoji: String {
        switch self {
        case .apple: return "🍎"
        case .banana: return "🍌"
        case .orange: return "🍊"
        case .grape: return "🍇"
        case .melon: return "🍉"
        }
    }
}

struct Food: Sendable {
    var position: CGPoint
    var kind: FoodKind
}

// MARK: - Model

/// Pure game state. UI-free so unit tests can drive it directly.
/// Coordinates are macOS screen points (origin at bottom-left).
/// All locomotion decisions flow through ``MiniBrain``; discrete game
/// states (eating, carried) only gate its output.
struct PetModel: Sendable {
    struct Limits: Sendable {
        var bounds: CGRect
        var baseSpeed: CGFloat = 62
        var turnRate: Double = 3.2
        var edgeMargin: CGFloat = 130
        var wallMargin: CGFloat = 0
    }

    struct Particle: Sendable {
        enum Kind: Sendable { case heart, crumb }
        var kind: Kind
        var position: CGPoint
        var age: Double
    }

    static let eatDuration = 1.4
    static let petDuration = 1.6
    static let satietyFullSeconds = 600.0
    static let moodFullSeconds = 480.0

    var head: CGPoint
    var heading: Double
    var brain = Brain.light(MiniBrain())
    var trail: [CGPoint] = []
    var satiety: Double = 80
    var mood: Double = 80
    var food: Food? = nil
    var cursor: CGPoint? = nil
    var eatTimer: Double = 0
    var petTimer: Double = 0
    var carried: Bool = false
    var carryTarget: CGPoint = .zero
    var time: Double = 0
    var wigglePhase: Double = 0
    var particles: [Particle] = []
    var skin: WormSkin = .classic
    var vitals = SystemVitals()

    var isEating: Bool { eatTimer > 0 }
    var isPetted: Bool { petTimer > 0 }

    var statusText: String {
        L10n.text("포만감 \(Int(satiety)) · 기분 \(Int(mood))", "Satiety \(Int(satiety)) · Mood \(Int(mood))")
    }

    /// Neuromodulation from system state: busy CPU speeds the worm up.
    var speedMultiplier: Double {
        let cpu = min(max(vitals.cpuLoad, 0), 1)
        return 0.6 + 1.4 * cpu
    }

    /// Tail length from power source. Unplugging the charger shortens
    /// the tail instead of touching speed, so CPU keeps its own channel.
    var tailSegments: Int {
        vitals.onBatteryPower ? max(6, skin.segments * 5 / 8) : skin.segments
    }

    /// Body scale from battery level. Macs without a battery stay full size.
    var sizeScale: Double {
        guard let level = vitals.batteryLevel else { return 1.0 }
        return 0.7 + 0.3 * min(max(level, 0), 1)
    }

    // MARK: Update

    mutating func update(dt: Double, limits: Limits) {
        time += dt
        satiety = max(0, satiety - dt * (100.0 / Self.satietyFullSeconds))
        mood = max(0, mood - dt * (100.0 / Self.moodFullSeconds))
        if eatTimer > 0 { eatTimer = max(0, eatTimer - dt) }
        if petTimer > 0 { petTimer = max(0, petTimer - dt) }
        if satiety <= 0, food == nil, !carried, !isEating {
            dropFoodNearHead(limits: limits)
        }

        if carried {
            moveCarried(dt: dt, limits: limits)
        } else if isEating {
            wigglePhase += dt * 14
        } else {
            neuralDrive(dt: dt, limits: limits)
        }

        pushTrail()
        ageParticles(dt: dt)
    }

    // MARK: Actions

    mutating func dropFood(at point: CGPoint) {
        food = Food(position: point, kind: FoodKind.allCases.randomElement() ?? .apple)
    }

    /// Drops a random fruit near the head, nudged toward the nearest edge
    /// to match the worm's preference.
    mutating func dropFoodNearHead(limits: Limits) {
        let angle = Double.random(in: 0 ..< 2 * Double.pi)
        let dist = CGFloat.random(in: 120...220)
        var point = CGPoint(
            x: head.x + cos(angle) * dist,
            y: head.y + sin(angle) * dist
        )
        let bounds = limits.bounds
        let dxMin = point.x - bounds.minX
        let dxMax = bounds.maxX - point.x
        let dyMin = point.y - bounds.minY
        let dyMax = bounds.maxY - point.y
        let nearest = min(dxMin, dxMax, dyMin, dyMax)
        if nearest == dxMin { point.x -= 60 } else if nearest == dxMax { point.x += 60 }
        else if nearest == dyMin { point.y -= 60 } else { point.y += 60 }
        let inset = bounds.insetBy(dx: 40, dy: 40)
        point.x = min(max(point.x, inset.minX), inset.maxX)
        point.y = min(max(point.y, inset.minY), inset.maxY)
        dropFood(at: point)
    }

    mutating func pet() {
        mood = min(100, mood + 22)
        petTimer = Self.petDuration
        for i in 0..<5 {
            let angle = Double(i) * 2.4 + time
            let offset = CGVector(dx: cos(angle) * 22, dy: 18 + sin(angle) * 10)
            particles.append(Particle(
                kind: .heart,
                position: CGPoint(x: head.x + offset.dx, y: head.y + offset.dy),
                age: -Double(i) * 0.08
            ))
        }
    }

    mutating func setCarried(_ value: Bool, target: CGPoint) {
        carried = value
        carryTarget = target
        if value { food = nil }
    }

    // MARK: Queries

    func bodyPoints(count: Int = 16, spacing: CGFloat = 8) -> [CGPoint] {
        var points = [head]
        points.reserveCapacity(count)
        var carriedOver: CGFloat = 0
        var previous = head
        for anchor in trail {
            var segmentStart = previous
            var segmentLength = distance(segmentStart, anchor)
            while carriedOver + segmentLength >= spacing, points.count < count, segmentLength > 0.0001 {
                let need = spacing - carriedOver
                let t = need / segmentLength
                let next = CGPoint(
                    x: segmentStart.x + (anchor.x - segmentStart.x) * t,
                    y: segmentStart.y + (anchor.y - segmentStart.y) * t
                )
                points.append(next)
                segmentStart = next
                segmentLength = distance(segmentStart, anchor)
                carriedOver = 0
            }
            carriedOver += segmentLength
            previous = anchor
            if points.count >= count { break }
        }
        while points.count < count { points.append(points.last ?? head) }
        return points
    }

    func hitTest(_ point: CGPoint, radius: CGFloat = 17) -> Bool {
        let effective = radius * CGFloat(sizeScale)
        if distance(head, point) <= effective { return true }
        for anchor in trail.stride(by: 3) {
            if distance(anchor, point) <= effective { return true }
        }
        return false
    }

    // MARK: Neural locomotion

    /// Sense the world into the brain's input vector.
    func sensors(limits: Limits) -> [Double] {
        let bounds = limits.bounds
        var inputs = [Double](repeating: 0, count: MiniBrain.Sensor.count)

        if let foodPosition = food?.position {
            let dist = distance(head, foodPosition)
            let angle = atan2(foodPosition.y - head.y, foodPosition.x - head.x) - heading
            let proximity = max(0, 1 - dist / 500)
            inputs[MiniBrain.Sensor.foodProximity.rawValue] = proximity
            inputs[MiniBrain.Sensor.foodLeft.rawValue] = max(0, sin(angle)) * proximity
            inputs[MiniBrain.Sensor.foodRight.rawValue] = max(0, -sin(angle)) * proximity
        }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let outwardAngle: Double
        if distance(head, center) < 1 {
            outwardAngle = heading
        } else {
            outwardAngle = atan2(head.y - center.y, head.x - center.x)
        }
        let dEdge = min(
            head.x - bounds.minX, bounds.maxX - head.x,
            head.y - bounds.minY, bounds.maxY - head.y
        )
        let interiority = min(1, max(0, (dEdge - 60) / 200))
        var edgeGain = interiority
        if food != nil { edgeGain *= 0.25 }
        let edgeAngle = outwardAngle - heading
        inputs[MiniBrain.Sensor.edgeLeft.rawValue] = max(0, sin(edgeAngle)) * edgeGain
        inputs[MiniBrain.Sensor.edgeRight.rawValue] = max(0, -sin(edgeAngle)) * edgeGain

        let dxMin = head.x - bounds.minX
        let dxMax = bounds.maxX - head.x
        let dyMin = head.y - bounds.minY
        let dyMax = bounds.maxY - head.y
        let wallPoint: CGPoint
        let wallDist = min(dxMin, dxMax, dyMin, dyMax)
        if wallDist == dxMin {
            wallPoint = CGPoint(x: bounds.minX, y: head.y)
        } else if wallDist == dxMax {
            wallPoint = CGPoint(x: bounds.maxX, y: head.y)
        } else if wallDist == dyMin {
            wallPoint = CGPoint(x: head.x, y: bounds.minY)
        } else {
            wallPoint = CGPoint(x: head.x, y: bounds.maxY)
        }
        // Fixed lookahead so the brains see walls early and steer away.
        let wallRange: CGFloat = 140
        let wallNear = max(0, 1 - wallDist / wallRange)
        inputs[MiniBrain.Sensor.wallNear.rawValue] = wallNear
        if wallNear > 0 {
            let wallAngle = atan2(wallPoint.y - head.y, wallPoint.x - head.x) - heading
            // Gate steering by approach: cruising parallel to a wall must
            // not push the worm away, or it could never hug edges.
            let lateral = wallNear * max(0, cos(wallAngle))
            inputs[MiniBrain.Sensor.wallLeft.rawValue] = max(0, sin(wallAngle)) * lateral
            inputs[MiniBrain.Sensor.wallRight.rawValue] = max(0, -sin(wallAngle)) * lateral
        }

        if let cursor {
            let dist = distance(head, cursor)
            let angle = atan2(cursor.y - head.y, cursor.x - head.x) - heading
            let proximity = max(0, 1 - dist / 200)
            inputs[MiniBrain.Sensor.cursorLeft.rawValue] = max(0, sin(angle)) * proximity
            inputs[MiniBrain.Sensor.cursorRight.rawValue] = max(0, -sin(angle)) * proximity
        }

        inputs[MiniBrain.Sensor.hunger.rawValue] = 1 - satiety / 100
        inputs[MiniBrain.Sensor.cpg1.rawValue] = sin(time * 0.9)
        inputs[MiniBrain.Sensor.cpg2.rawValue] = sin(time * 1.7 + 1.3)
        return inputs
    }

    private mutating func neuralDrive(dt: Double, limits: Limits) {
        if let foodPosition = food?.position, distance(head, foodPosition) < 26 {
            self.food = nil
            eatTimer = Self.eatDuration
            satiety = min(100, satiety + 38)
            for i in 0..<6 {
                let angle = Double(i) * 1.05
                particles.append(Particle(
                    kind: .crumb,
                    position: CGPoint(x: head.x + cos(angle) * 14, y: head.y + sin(angle) * 12),
                    age: 0
                ))
            }
            return
        }
        let output = brain.step(sensors(limits: limits))
        heading += output.turn * limits.turnRate * dt
        var speed = limits.baseSpeed * CGFloat(0.35 + 0.9 * output.speed)
        if mood < 30 { speed *= 0.85 }
        if isPetted { speed *= 1.25 }
        speed *= CGFloat(speedMultiplier)
        advance(speed: speed, dt: dt, limits: limits)
    }

    private mutating func moveCarried(dt: Double, limits: Limits) {
        let toTarget = CGVector(dx: carryTarget.x - head.x, dy: carryTarget.y - head.y)
        let dist = (toTarget.dx * toTarget.dx + toTarget.dy * toTarget.dy).squareRoot()
        if dist > 4 {
            heading = atan2(toTarget.dy, toTarget.dx)
            advance(speed: min(600, dist * 8), dt: dt, limits: limits)
        }
        wigglePhase += dt * 10
    }

    /// Mechanics plus hard collision constraint. Steering comes from the brain.
    private mutating func advance(speed: CGFloat, dt: Double, limits: Limits) {
        head.x += cos(heading) * speed * CGFloat(dt)
        head.y += sin(heading) * speed * CGFloat(dt)
        let bounds = limits.bounds.insetBy(dx: limits.wallMargin, dy: limits.wallMargin)
        // Slide along walls instead of bouncing: keep the tangential
        // direction, drop the inward one. Brains steer away before this.
        if head.x < bounds.minX || head.x > bounds.maxX {
            head.x = min(max(head.x, bounds.minX), bounds.maxX)
            heading = Self.tangentAngle(flow: sin(heading), position: head.y, middle: bounds.midY, axisAngle: .pi / 2)
        }
        if head.y < bounds.minY || head.y > bounds.maxY {
            head.y = min(max(head.y, bounds.minY), bounds.maxY)
            heading = Self.tangentAngle(flow: cos(heading), position: head.x, middle: bounds.midX, axisAngle: 0)
        }
        wigglePhase += dt * (4 + Double(speed) / 25)
    }

    /// Heading tangent to a wall: preserves the current direction of travel
    /// along it, deflects toward the center on head-on contact.
    private static func tangentAngle(flow: Double, position: CGFloat, middle: CGFloat, axisAngle: Double) -> Double {
        let sign: Double
        if abs(flow) < 0.2 {
            sign = position < middle ? 1 : -1
        } else {
            sign = flow > 0 ? 1 : -1
        }
        return axisAngle + (sign > 0 ? 0 : .pi)
    }

    private mutating func pushTrail() {
        if let first = trail.first, distance(first, head) < 4 { return }
        trail.insert(head, at: 0)
        if trail.count > 80 { trail.removeLast(trail.count - 80) }
    }

    private mutating func ageParticles(dt: Double) {
        for i in particles.indices { particles[i].age += dt }
        particles.removeAll { $0.age > ($0.kind == .heart ? 1.3 : 1.0) }
    }
}

// MARK: - Helpers

private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = a.x - b.x
    let dy = a.y - b.y
    return (dx * dx + dy * dy).squareRoot()
}

private extension Array {
    func stride(by step: Int) -> [Element] {
        guard step > 0 else { return self }
        var result: [Element] = []
        var i = startIndex
        while i < endIndex {
            result.append(self[i])
            i = index(i, offsetBy: step, limitedBy: endIndex) ?? endIndex
        }
        return result
    }
}
