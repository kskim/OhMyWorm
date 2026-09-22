import AppKit
import Observation
import SwiftUI

/// Owns the game loop, screen bounds, and global mouse interaction.
/// The worm panel itself is click-through; all clicks are observed here.
@MainActor @Observable
final class PetController: NSObject {
    static let tickInterval = 1.0 / 20.0
    private static let skinKey = "worm.skin"
    private static let engineKey = "worm.engine"

    var model: PetModel
    var limits: PetModel.Limits
    var paused = false

    /// Current overlay frame in screen coordinates. The panel tracks the
    /// worm instead of covering the whole screen, to keep compositing cheap.
    private(set) var viewOrigin: CGPoint = .zero
    private(set) var viewSize: CGSize = .zero

    private var screen: NSScreen
    private var panel: DesktopPanel?
    private var timer: Timer?
    private var monitors: [Any] = []
    private var sampler = VitalsSampler()
    private var frame = 0
    /// Cached on first Real use: only Real needs the 3 MB dataset.
    private var realGraphCache: ConnectomeGraph?
    private var realGraphLoaded = false

    private func loadRealGraph() -> ConnectomeGraph? {
        if !realGraphLoaded {
            realGraphLoaded = true
            realGraphCache = try? RealDataLoader.loadGraph()
        }
        return realGraphCache
    }

    /// Play area: the full frame minus the Dock. The menu bar strip stays
    /// open (the worm may slip under it); only the Dock side is cut out.
    /// The Dock never sits at the top, so the top edge always stays full.
    static func playBounds(frame: CGRect, visible: CGRect) -> CGRect {
        CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: frame.maxY - visible.minY)
    }

    init(screen: NSScreen) {
        self.screen = screen
        let bounds = Self.playBounds(frame: screen.frame, visible: screen.visibleFrame)
        self.limits = PetModel.Limits(bounds: bounds)
        let savedSkin = UserDefaults.standard.string(forKey: Self.skinKey)
            .flatMap(WormSkin.init(rawValue:)) ?? .classic
        let model = PetModel(
            head: CGPoint(x: bounds.midX + 200, y: bounds.minY + 160),
            heading: 0.6,
            skin: savedSkin
        )
        var engineID = UserDefaults.standard.string(forKey: Self.engineKey)
            .flatMap(EngineID.init(storedValue:)) ?? .light
        self.model = model
        super.init()
        if engineID == .real, loadRealGraph() == nil {
            engineID = .light
            UserDefaults.standard.set(engineID.rawValue, forKey: Self.engineKey)
        }
        self.model.brain = Self.makeBrain(engineID, graph: engineID == .real ? loadRealGraph() : nil)
        let frame = contentRect()
        viewOrigin = frame.origin
        viewSize = frame.size
        panel = DesktopPanel(contentView: NSHostingView(rootView: WormView(controller: self)), frame: frame)
    }

    func start() {
        stop()
        model.vitals = sampler.sample()
        // Common modes so the worm keeps moving while the menu is open
        // (menu tracking switches the run loop out of the default mode).
        // Synchronous: the timer fires on the main thread, so no Task hop.
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true, block: { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        })
        timer.tolerance = 0.005
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp],
            handler: { [weak self] event in
                let type = event.type
                let location = NSEvent.mouseLocation
                Task { @MainActor [weak self] in self?.handle(type: type, at: location) }
            }
        ) {
            monitors.append(monitor)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
    }

    func refit(screen: NSScreen) {
        self.screen = screen
        limits.bounds = Self.playBounds(frame: screen.frame, visible: screen.visibleFrame)
        let inset = limits.bounds.insetBy(dx: limits.wallMargin, dy: limits.wallMargin)
        model.head.x = min(max(model.head.x, inset.minX), inset.maxX)
        model.head.y = min(max(model.head.y, inset.minY), inset.maxY)
        if let food = model.food, !limits.bounds.contains(food) {
            model.food = nil
        }
        movePanel(force: true)
    }

    /// Fixed-size panel centered on the worm. Fixed size avoids per-frame
    /// layer reallocations; only the origin moves.
    func contentRect() -> CGRect {
        let frame = screen.frame
        let width = min(760, frame.width)
        let height = min(760, frame.height)
        let x = min(max(model.head.x - width / 2, frame.minX), frame.maxX - width)
        let y = min(max(model.head.y - height / 2, frame.minY), frame.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func movePanel(force: Bool = false) {
        let frame = contentRect()
        let moved = abs(frame.origin.x - viewOrigin.x) > 0.5 || abs(frame.origin.y - viewOrigin.y) > 0.5
        let resized = abs(frame.width - viewSize.width) > 1 || abs(frame.height - viewSize.height) > 1
        guard force || moved || resized else { return }
        viewOrigin = frame.origin
        if resized { viewSize = frame.size }
        panel?.moveTo(frame)
    }

    // MARK: - Menu actions

    @objc func dropFood() {
        model.dropFoodNearHead(limits: limits)
    }

    @objc func setSkin(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let skin = WormSkin(rawValue: raw) else { return }
        model.skin = skin
        UserDefaults.standard.set(skin.rawValue, forKey: Self.skinKey)
    }

    /// Switching brains resets neural state; position and stats are kept.
    @objc func setEngine(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let id = EngineID(rawValue: raw) else { return }
        if id == .real, loadRealGraph() == nil { return }
        model.brain = Self.makeBrain(id, graph: id == .real ? loadRealGraph() : nil)
        UserDefaults.standard.set(id.rawValue, forKey: Self.engineKey)
    }

    private static func makeBrain(_ id: EngineID, graph: ConnectomeGraph?) -> Brain {
        switch id {
        case .light:
            return .light(MiniBrain())
        case .real:
            if let graph, let brain = try? RealBrain(graph: graph) {
                return .real(brain)
            }
            return .light(MiniBrain())
        }
    }

    @objc func togglePause() {
        paused.toggle()
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Private

    private func tick() {
        guard !paused else { return }
        frame += 1
        if frame % 40 == 1 {
            model.vitals = sampler.sample()
            // Pick up Dock moves/resizes between screen-change notifications.
            let fresh = Self.playBounds(frame: screen.frame, visible: screen.visibleFrame)
            if fresh != limits.bounds {
                refit(screen: screen)
            }
        }
        model.cursor = NSEvent.mouseLocation
        model.update(dt: Self.tickInterval, limits: limits)
        movePanel()
    }

    private func handle(type: NSEvent.EventType, at point: CGPoint) {
        switch type {
        case .leftMouseDown:
            if model.hitTest(point) {
                model.setCarried(true, target: point)
                model.pet()
            }
        case .leftMouseDragged:
            if model.carried { model.carryTarget = point }
        case .leftMouseUp:
            if model.carried { model.setCarried(false, target: point) }
        default:
            break
        }
    }
}
