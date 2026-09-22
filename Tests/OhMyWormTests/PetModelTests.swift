import XCTest
@testable import OhMyWorm

final class PetModelTests: XCTestCase {
    private func makeModel() -> (PetModel, PetModel.Limits) {
        let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let limits = PetModel.Limits(bounds: bounds)
        let model = PetModel(head: CGPoint(x: 720, y: 450), heading: 0)
        return (model, limits)
    }

    func testUpdateStaysInBounds() {
        var (model, limits) = makeModel()
        for _ in 0..<3000 {
            model.update(dt: 1.0 / 30.0, limits: limits)
            XCTAssertTrue(limits.bounds.insetBy(dx: 29, dy: 29).contains(model.head))
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
