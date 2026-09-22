import Foundation

// MARK: - Skin

enum WormSkin: String, CaseIterable, Identifiable, Sendable {
    case classic
    case berry
    case honey
    case ghost

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "기본"
        case .berry: return "베리"
        case .honey: return "허니"
        case .ghost: return "고스트"
        }
    }

    func next() -> WormSkin {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
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
        var wallMargin: CGFloat = 30
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
    var brain = MiniBrain()
    var trail: [CGPoint] = []
    var satiety: Double = 80
    var mood: Double = 80
    var food: CGPoint? = nil
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
        "포만감 \(Int(satiety)) · 기분 \(Int(mood))"
    }

    /// Neuromodulation from system state, RunCat-style: busy CPU speeds
    /// the worm up, running on battery slows it down.
    var speedMultiplier: Double {
        let cpu = min(max(vitals.cpuLoad, 0), 1)
        return (0.6 + 1.4 * cpu) * (vitals.onBatteryPower ? 0.75 : 1.0)
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
        food = point
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

    func hitTest(_ point: CGPoint, radius: CGFloat = 21) -> Bool {
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

        if let food {
            let dist = distance(head, food)
            let angle = atan2(food.y - head.y, food.x - head.x) - heading
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
        let wallRange = limits.wallMargin * 2.5
        let wallNear = max(0, 1 - wallDist / wallRange)
        inputs[MiniBrain.Sensor.wallNear.rawValue] = wallNear
        if wallNear > 0 {
            let wallAngle = atan2(wallPoint.y - head.y, wallPoint.x - head.x) - heading
            inputs[MiniBrain.Sensor.wallLeft.rawValue] = max(0, sin(wallAngle)) * wallNear
            inputs[MiniBrain.Sensor.wallRight.rawValue] = max(0, -sin(wallAngle)) * wallNear
        }

        inputs[MiniBrain.Sensor.hunger.rawValue] = 1 - satiety / 100
        inputs[MiniBrain.Sensor.cpg1.rawValue] = sin(time * 0.9)
        inputs[MiniBrain.Sensor.cpg2.rawValue] = sin(time * 1.7 + 1.3)
        return inputs
    }

    private mutating func neuralDrive(dt: Double, limits: Limits) {
        if let food, distance(head, food) < 26 {
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
        if head.x < bounds.minX { head.x = bounds.minX; heading = Double.pi - heading }
        if head.x > bounds.maxX { head.x = bounds.maxX; heading = Double.pi - heading }
        if head.y < bounds.minY { head.y = bounds.minY; heading = -heading }
        if head.y > bounds.maxY { head.y = bounds.maxY; heading = -heading }
        wigglePhase += dt * (4 + Double(speed) / 25)
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
