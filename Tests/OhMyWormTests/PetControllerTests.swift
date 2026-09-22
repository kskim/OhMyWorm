import XCTest
@testable import OhMyWorm

@MainActor
final class PetControllerTests: XCTestCase {
    private func makeController() -> PetController? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        return PetController(screen: screen)
    }

    func testTickKeepsFiringWhileMenuIsOpen() {
        guard let controller = makeController() else { return }
        controller.start()
        defer { controller.stop() }
        let start = controller.model.time
        // Menu tracking runs the run loop in the event-tracking mode.
        // (RunLoop.run(mode:before:) never fires timers here; CF does.)
        CFRunLoopRunInMode(CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString), 0.3, false)
        XCTAssertGreaterThan(controller.model.time, start)
    }

    func testDropFoodPlacesFoodInBounds() {
        guard let controller = makeController() else { return }
        controller.dropFood()
        guard let food = controller.model.food else {
            XCTFail("dropFood must place food")
            return
        }
        XCTAssertTrue(controller.limits.bounds.contains(food.position))
    }

    func testSetSkinPersistsSelection() {
        guard let controller = makeController() else { return }
        let previous = UserDefaults.standard.string(forKey: "worm.skin")
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: "worm.skin")
            } else {
                UserDefaults.standard.removeObject(forKey: "worm.skin")
            }
        }
        let item = NSMenuItem()
        item.representedObject = WormSkin.dragon.rawValue
        controller.setSkin(item)
        XCTAssertEqual(controller.model.skin, .dragon)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "worm.skin"), WormSkin.dragon.rawValue)
    }

    func testTogglePauseFlips() {
        guard let controller = makeController() else { return }
        XCTAssertFalse(controller.paused)
        controller.togglePause()
        XCTAssertTrue(controller.paused)
        controller.togglePause()
        XCTAssertFalse(controller.paused)
    }

    func testContentRectCoversWormAndFood() {
        guard let controller = makeController() else { return }
        controller.dropFood()
        let rect = controller.contentRect()
        XCTAssertTrue(rect.contains(controller.model.head))
        if let food = controller.model.food {
            XCTAssertTrue(rect.contains(food.position))
        } else {
            XCTFail("dropFood must place food")
        }
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            XCTAssertTrue(screen.frame.contains(rect))
        }
    }

    func testSamplerReturnsSaneValues() {
        let sampler = VitalsSampler()
        let vitals = sampler.sample()
        XCTAssertGreaterThanOrEqual(vitals.cpuLoad, 0)
        XCTAssertLessThanOrEqual(vitals.cpuLoad, 1)
        if let level = vitals.batteryLevel {
            XCTAssertGreaterThanOrEqual(level, 0)
            XCTAssertLessThanOrEqual(level, 1)
        }
    }

    func testSetEngineSwitchesAndPersists() {
        guard let controller = makeController() else { return }
        let previous = UserDefaults.standard.string(forKey: "worm.engine")
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: "worm.engine")
            } else {
                UserDefaults.standard.removeObject(forKey: "worm.engine")
            }
        }
        for id in EngineID.allCases {
            let item = NSMenuItem()
            item.representedObject = id.rawValue
            controller.setEngine(item)
            XCTAssertEqual(controller.model.brain.id, id)
            XCTAssertEqual(UserDefaults.standard.string(forKey: "worm.engine"), id.rawValue)
        }
    }

    func testStatusTextReflectsModel() {
        guard let controller = makeController() else { return }
        controller.model.satiety = 72
        controller.model.mood = 85
        XCTAssertEqual(controller.model.statusText, "포만감 72 · 기분 85")
    }
}
