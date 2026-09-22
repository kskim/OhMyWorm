import XCTest
@testable import OhMyWorm

final class PetModelTests: XCTestCase {
    nonisolated(unsafe) private static var sharedGraph: ConnectomeGraph?

    override class func setUp() {
        super.setUp()
        sharedGraph = try? RealDataLoader.loadGraph()
    }

    private func realGraph() throws -> ConnectomeGraph {
        try XCTUnwrap(Self.sharedGraph, "bundled connectome must load")
    }

    /// CGRect.contains excludes the max edge, so compare directly.
    private func assertHeadInBounds(_ model: PetModel, _ limits: PetModel.Limits, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(model.head.x, limits.bounds.minX, file: file, line: line)
        XCTAssertLessThanOrEqual(model.head.x, limits.bounds.maxX, file: file, line: line)
        XCTAssertGreaterThanOrEqual(model.head.y, limits.bounds.minY, file: file, line: line)
        XCTAssertLessThanOrEqual(model.head.y, limits.bounds.maxY, file: file, line: line)
    }

    private func makeModel(engine: Brain = .light(MiniBrain())) -> (PetModel, PetModel.Limits) {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let limits = PetModel.Limits(bounds: bounds)
        var model = PetModel(head: CGPoint(x: 720, y: 450), heading: 0)
        model.brain = engine
        return (model, limits)
    }

    func testUpdateStaysInBounds() {
        var (model, limits) = makeModel()
        for _ in 0..<3000 {
            model.update(dt: 1.0 / 30.0, limits: limits)
            assertHeadInBounds(model, limits)
        }
    }

    func testPrefersEdgesOverCenter() {
        var (model, limits) = makeModel()
        let center = CGPoint(x: 720, y: 450)
        let startDist = hypot(model.head.x - center.x, model.head.y - center.y)
        for _ in 0..<900 {
            model.update(dt: 1.0 / 30.0, limits: limits)
        }
        let endDist = hypot(model.head.x - center.x, model.head.y - center.y)
        XCTAssertGreaterThan(endDist, startDist + 100)
    }

    func testSeeksAndEatsFood() {
        var (model, limits) = makeModel()
        model.satiety = 20
        model.dropFood(at: CGPoint(x: 900, y: 450))
        for _ in 0..<1200 {
            model.update(dt: 1.0 / 30.0, limits: limits)
            if model.food == nil { break }
        }
        XCTAssertNil(model.food)
        XCTAssertGreaterThan(model.satiety, 50)
    }

    func testStatsDecayOverTime() {
        var (model, limits) = makeModel()
        let satiety = model.satiety
        let mood = model.mood
        model.update(dt: 60, limits: limits)
        XCTAssertLessThan(model.satiety, satiety)
        XCTAssertLessThan(model.mood, mood)
        XCTAssertGreaterThanOrEqual(model.satiety, 0)
        XCTAssertGreaterThanOrEqual(model.mood, 0)
    }

    func testPetRestoresMood() {
        var (model, _) = makeModel()
        model.mood = 10
        model.pet()
        XCTAssertGreaterThan(model.mood, 10)
        XCTAssertTrue(model.isPetted)
        XCTAssertFalse(model.particles.isEmpty)
    }

    func testBodyPointsResampled() {
        var (model, limits) = makeModel()
        for _ in 0..<120 {
            model.update(dt: 1.0 / 30.0, limits: limits)
        }
        let points = model.bodyPoints(count: 16, spacing: 8)
        XCTAssertEqual(points.count, 16)
        XCTAssertEqual(points[0], model.head)
    }

    func testHitTestFindsBody() {
        var (model, limits) = makeModel()
        for _ in 0..<60 {
            model.update(dt: 1.0 / 30.0, limits: limits)
        }
        XCTAssertTrue(model.hitTest(model.head))
        XCTAssertFalse(model.hitTest(CGPoint(x: 100, y: 100), radius: 10))
    }

    func testWallContactSlidesInsteadOfBouncing() {
        var (model, limits) = makeModel()
        model.head = CGPoint(x: limits.bounds.minX + 0.5, y: 450)
        model.heading = .pi
        for _ in 0..<10 {
            model.update(dt: 1.0 / 30.0, limits: limits)
            if model.head.x <= limits.bounds.minX + 0.001 { break }
        }
        XCTAssertEqual(model.head.x, limits.bounds.minX, accuracy: 0.001)
        // Sliding along the wall means moving vertically, not reflecting.
        XCTAssertGreaterThan(abs(sin(model.heading)), 0.9)
    }

    func testWallSensorsIgnoreParallelCruising() {
        var (model, limits) = makeModel()
        model.head = CGPoint(x: 60, y: 450)
        model.heading = .pi / 2
        let parallel = model.sensors(limits: limits)
        XCTAssertGreaterThan(parallel[MiniBrain.Sensor.wallNear.rawValue], 0.3)
        XCTAssertEqual(parallel[MiniBrain.Sensor.wallLeft.rawValue], 0, accuracy: 0.05)
        XCTAssertEqual(parallel[MiniBrain.Sensor.wallRight.rawValue], 0, accuracy: 0.05)

        model.heading = .pi - 0.3
        let approaching = model.sensors(limits: limits)
        XCTAssertGreaterThan(approaching[MiniBrain.Sensor.wallLeft.rawValue], 0.05)
    }

    func testBrainOutputBounds() {
        var brain = MiniBrain()
        for _ in 0..<200 {
            var inputs = [Double](repeating: 0, count: MiniBrain.Sensor.count)
            inputs[MiniBrain.Sensor.cpg1.rawValue] = 1
            inputs[MiniBrain.Sensor.hunger.rawValue] = 0.5
            let output = brain.step(inputs)
            XCTAssertGreaterThanOrEqual(output.turn, -1)
            XCTAssertLessThanOrEqual(output.turn, 1)
            XCTAssertGreaterThanOrEqual(output.speed, 0)
            XCTAssertLessThanOrEqual(output.speed, 1)
        }
    }

    func testBrainTurnsTowardFoodAndAwayFromWall() {
        var towardFood = MiniBrain()
        var foodInputs = [Double](repeating: 0, count: MiniBrain.Sensor.count)
        foodInputs[MiniBrain.Sensor.foodLeft.rawValue] = 1
        XCTAssertGreaterThan(towardFood.step(foodInputs).turn, 0)

        var awayFromWall = MiniBrain()
        var wallInputs = [Double](repeating: 0, count: MiniBrain.Sensor.count)
        wallInputs[MiniBrain.Sensor.wallLeft.rawValue] = 1
        XCTAssertLessThan(awayFromWall.step(wallInputs).turn, 0)
    }

    func testMiniBrainWorksThroughProtocol() {
        var engine: any LocomotionEngine = MiniBrain()
        let inputs = [Double](repeating: 0, count: MiniBrain.Sensor.count)
        let output = engine.step(inputs)
        XCTAssertGreaterThanOrEqual(output.turn, -1)
        XCTAssertLessThanOrEqual(output.turn, 1)
        XCTAssertGreaterThanOrEqual(output.speed, 0)
        XCTAssertLessThanOrEqual(output.speed, 1)
    }

    func testModelIsDeterministic() {
        func run() -> CGPoint {
            var (model, limits) = makeModel()
            model.dropFood(at: CGPoint(x: 900, y: 450))
            for _ in 0..<600 {
                model.update(dt: 1.0 / 30.0, limits: limits)
            }
            return model.head
        }
        XCTAssertEqual(run(), run())
    }

    func testSpeedMultiplierRisesWithCPU() {
        var (model, _) = makeModel()
        model.vitals = SystemVitals(cpuLoad: 0, batteryLevel: nil, onBatteryPower: false)
        let idle = model.speedMultiplier
        model.vitals.cpuLoad = 1
        XCTAssertGreaterThan(model.speedMultiplier, idle)
    }

    func testOnBatteryShortensTailWithoutTouchingSpeed() {
        var (model, _) = makeModel()
        model.vitals = SystemVitals(cpuLoad: 0.5, batteryLevel: 0.5, onBatteryPower: false)
        let chargingSegments = model.tailSegments
        let chargingSpeed = model.speedMultiplier
        model.vitals.onBatteryPower = true
        XCTAssertLessThan(model.tailSegments, chargingSegments)
        XCTAssertEqual(model.speedMultiplier, chargingSpeed)
    }

    func testSizeScaleFollowsBattery() {
        var (model, _) = makeModel()
        model.vitals.batteryLevel = nil
        XCTAssertEqual(model.sizeScale, 1.0)
        model.vitals.batteryLevel = 1.0
        XCTAssertEqual(model.sizeScale, 1.0)
        model.vitals.batteryLevel = 0.0
        XCTAssertEqual(model.sizeScale, 0.7, accuracy: 0.001)
        model.vitals.batteryLevel = 0.5
        XCTAssertEqual(model.sizeScale, 0.85, accuracy: 0.001)
    }

    func testSkinsHaveDistinctBodyLengths() {
        let counts = Set(WormSkin.allCases.map(\.segments))
        XCTAssertEqual(counts.count, WormSkin.allCases.count)
    }

    func testRealBrainLoadsRealGraph() throws {
        let graph = try realGraph()
        XCTAssertEqual(graph.neurons.count, 302)
        let brain = try RealBrain(graph: graph)
        _ = brain
    }

    func testReadoutMapping() {
        XCTAssertGreaterThan(RealBrain.readoutSpeed(forward: 1, backward: -1), 0.9)
        XCTAssertLessThan(RealBrain.readoutSpeed(forward: -1, backward: 1), 0.1)
        XCTAssertGreaterThan(RealBrain.readoutTurn(bend: 1), 0.9)
        XCTAssertLessThan(RealBrain.readoutTurn(bend: -1), -0.9)
        XCTAssertEqual(RealBrain.readoutSpeed(forward: 0, backward: 0), 0.5, accuracy: 0.001)
        XCTAssertEqual(RealBrain.readoutTurn(bend: 0), 0, accuracy: 0.001)
    }

    func testRealStaysInBoundsAndMoves() throws {
        let graph = try realGraph()
        var (model, limits) = makeModel(engine: .real(try RealBrain(graph: graph)))
        let start = model.head
        for _ in 0..<600 {
            model.update(dt: 1.0 / 20.0, limits: limits)
            assertHeadInBounds(model, limits)
        }
        XCTAssertGreaterThan(hypot(model.head.x - start.x, model.head.y - start.y), 50)
    }

    func testRealOutputBounds() throws {
        let graph = try realGraph()
        var brain = try RealBrain(graph: graph)
        var (model, limits) = makeModel()
        for _ in 0..<200 {
            let output = brain.step(model.sensors(limits: limits))
            XCTAssertGreaterThanOrEqual(output.turn, -1)
            XCTAssertLessThanOrEqual(output.turn, 1)
            XCTAssertGreaterThanOrEqual(output.speed, 0)
            XCTAssertLessThanOrEqual(output.speed, 1)
            model.update(dt: 1.0 / 20.0, limits: limits)
        }
    }

    func testRealDeterministic() throws {
        let graph = try realGraph()
        func run() throws -> CGPoint {
            var (model, limits) = makeModel(engine: .real(try RealBrain(graph: graph)))
            for _ in 0..<300 {
                model.update(dt: 1.0 / 20.0, limits: limits)
            }
            return model.head
        }
        XCTAssertEqual(try run(), try run())
    }

    func testRealMuscleAnatomy() throws {
        let graph = try realGraph()
        let projection = NeuralProjection(graph: graph)
        let muscles = try MuscleLayer(graph: graph, neuronIndex: projection.index(of:))
        XCTAssertEqual(muscles.muscleIDs.count, 95)
        XCTAssertEqual(muscles.anteriorDorsal.count, 16)
        XCTAssertEqual(muscles.anteriorVentral.count, 16)
        XCTAssertEqual(muscles.bodyDorsal.count, 32)
        XCTAssertEqual(muscles.bodyVentral.count, 31)
        XCTAssertEqual(muscles.edges.count, 961)
        XCTAssertEqual(muscles.edges.filter { $0.polarity < 0 }.count, 121)
    }

    func testRealMuscleBoundsAndDecay() throws {
        let graph = try realGraph()
        let projection = NeuralProjection(graph: graph)
        var muscles = try MuscleLayer(graph: graph, neuronIndex: projection.index(of:))
        let count = projection.neuronIDs.count
        for _ in 0..<30 { muscles.step(activity: [Double](repeating: 1, count: count)) }
        let peak = muscles.activation.map(abs).max() ?? 0
        XCTAssertGreaterThan(peak, 0.01)
        for _ in 0..<200 { muscles.step(activity: [Double](repeating: 0, count: count)) }
        let rest = muscles.activation.map(abs).max() ?? 1
        XCTAssertLessThan(rest, peak * 0.01)
        XCTAssertLessThanOrEqual(muscles.headBend.magnitude, 2)
    }

    func testRealBrainDrivesMuscles() throws {
        let graph = try realGraph()
        var brain = try RealBrain(graph: graph)
        var (model, limits) = makeModel(engine: .real(try RealBrain(graph: graph)))
        for _ in 0..<50 {
            _ = brain.step(model.sensors(limits: limits))
            model.update(dt: 1.0 / 20.0, limits: limits)
        }
        XCTAssertGreaterThan(brain.muscles.activation.map(abs).max() ?? 0, 0)
    }

    func testKlinotaxisWeaveOnlyWithoutFood() {
        var controller = KlinotaxisController()
        let params = KlinotaxisParameters()
        var minDrive = Double.greatestFiniteMagnitude
        var maxDrive = -Double.greatestFiniteMagnitude
        for _ in 0..<100 {
            let drive = controller.step(concentration: 0, proximity: 0, lateral: 0, edgeLateral: 0, params: params)
            minDrive = min(minDrive, drive.dorsal)
            maxDrive = max(maxDrive, drive.dorsal)
        }
        XCTAssertLessThan(controller.bias.magnitude, 0.01)
        XCTAssertGreaterThan(maxDrive, 0.1)
        XCTAssertLessThan(minDrive, -0.1)
    }

    func testKlinotaxisCorrelationPolarity() {
        let params = KlinotaxisParameters()
        let omega = 2 * Double.pi * params.frequencyHz / KlinotaxisController.ticksPerSecond
        func run(sign: Double) -> Double {
            var controller = KlinotaxisController()
            for n in 0..<400 {
                let phase = Double(n + 1) * omega
                let c = 0.1 + sign * 0.005 * sin(phase)
                _ = controller.step(concentration: c, proximity: 0.5, lateral: 0, edgeLateral: 0, params: params)
            }
            return controller.bias
        }
        XCTAssertGreaterThan(run(sign: 1), 0.5)
        XCTAssertLessThan(run(sign: -1), -0.5)
    }

    func testKlinotaxisTropism() {
        let params = KlinotaxisParameters()
        func drive(lateral: Double) -> [Double] {
            var controller = KlinotaxisController()
            var drives: [Double] = []
            for _ in 0..<60 {
                let drive = controller.step(concentration: 0.2, proximity: 0.8, lateral: lateral, edgeLateral: 0, params: params)
                drives.append(drive.dorsal)
            }
            return Array(drives.suffix(10))
        }
        XCTAssertGreaterThan(drive(lateral: 0.5).min() ?? 0, 0.5)
        XCTAssertLessThan(drive(lateral: -0.5).max() ?? 0, -0.5)
    }

    func testKlinotaxisPirouetteAlternates() {
        var controller = KlinotaxisController()
        let params = KlinotaxisParameters()
        for _ in 0..<100 {
            _ = controller.step(concentration: 0.1, proximity: 0.5, lateral: 0, edgeLateral: 0, params: params)
        }
        _ = controller.step(concentration: 0.1, proximity: 0.45, lateral: 0, edgeLateral: 0, params: params)
        var first: [Double] = []
        for _ in 0..<10 {
            let drive = controller.step(concentration: 0.1, proximity: 0.45, lateral: 0, edgeLateral: 0, params: params)
            first.append(drive.dorsal)
        }
        XCTAssertEqual(first[0], -1.0, accuracy: 0.001)
        for _ in 0..<60 {
            _ = controller.step(concentration: 0.1, proximity: 0.45, lateral: 0, edgeLateral: 0, params: params)
        }
        _ = controller.step(concentration: 0.1, proximity: 0.41, lateral: 0, edgeLateral: 0, params: params)
        let second = controller.step(concentration: 0.1, proximity: 0.41, lateral: 0, edgeLateral: 0, params: params)
        XCTAssertEqual(second.dorsal, 1.0, accuracy: 0.001)
    }

    func testKlinotaxisForgetsWithoutFood() {
        var controller = KlinotaxisController()
        let params = KlinotaxisParameters()
        let omega = 2 * Double.pi * params.frequencyHz / KlinotaxisController.ticksPerSecond
        for n in 0..<200 {
            let c = 0.1 + 0.005 * sin(Double(n + 1) * omega)
            _ = controller.step(concentration: c, proximity: 0.5, lateral: 0, edgeLateral: 0, params: params)
        }
        XCTAssertGreaterThan(controller.bias, 0.2)
        for _ in 0..<200 {
            _ = controller.step(concentration: 0, proximity: 0, lateral: 0, edgeLateral: 0, params: params)
        }
        XCTAssertLessThan(controller.bias.magnitude, 0.05)
    }

    func testKlinotaxisEdgeDrive() {
        let params = KlinotaxisParameters()
        func meanDrive(edgeLateral: Double) -> Double {
            var controller = KlinotaxisController()
            var sum = 0.0
            for n in 0..<60 {
                let drive = controller.step(concentration: 0, proximity: 0, lateral: 0, edgeLateral: edgeLateral, params: params)
                if n >= 20 { sum += drive.dorsal }
            }
            return sum / 40
        }
        let positive = meanDrive(edgeLateral: 0.6)
        let negative = meanDrive(edgeLateral: -0.6)
        XCTAssertGreaterThan(positive, 0.4)
        XCTAssertLessThan(positive, 0.8)
        XCTAssertGreaterThan(negative, -0.8)
        XCTAssertLessThan(negative, -0.4)
    }

    func testRealFindsFoodLeftAndRight() throws {
        let graph = try realGraph()
        for food in [CGPoint(x: 720, y: 700), CGPoint(x: 720, y: 200)] {
            var (model, limits) = makeModel(engine: .real(try RealBrain(graph: graph)))
            model.dropFood(at: food)
            for _ in 0..<600 {
                model.update(dt: 1.0 / 20.0, limits: limits)
                if model.food == nil { break }
            }
            XCTAssertNil(model.food, "food at \(food) must be eaten")
        }
    }

    func testRealDwellsAtEdges() throws {
        let graph = try realGraph()
        var (model, limits) = makeModel(engine: .real(try RealBrain(graph: graph)))
        var edgeTicks = 0
        let total = 2500
        for _ in 0..<total {
            model.update(dt: 1.0 / 20.0, limits: limits)
            let bounds = limits.bounds
            let dEdge = min(model.head.x - bounds.minX, bounds.maxX - model.head.x,
                            model.head.y - bounds.minY, bounds.maxY - model.head.y)
            if dEdge < 130 { edgeTicks += 1 }
        }
        XCTAssertGreaterThan(Double(edgeTicks) / Double(total), 0.5)
    }

    func testSkinCyclesThroughAllCases() {
        var seen: Set<WormSkin> = []
        var skin = WormSkin.classic
        for _ in 0..<WormSkin.allCases.count {
            seen.insert(skin)
            skin = skin.next()
        }
        XCTAssertEqual(seen.count, WormSkin.allCases.count)
        XCTAssertEqual(skin, .classic)
    }
}
