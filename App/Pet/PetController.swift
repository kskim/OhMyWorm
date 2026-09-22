import AppKit
import Observation
import SwiftUI

/// Owns the game loop, screen bounds, and global mouse interaction.
/// The worm panel itself is click-through; all clicks are observed here.
@MainActor @Observable
final class PetController: NSObject {
    static let tickInterval = 1.0 / 20.0
    private static let skinKey = "worm.skin"

    var model: PetModel
    var limits: PetModel.Limits
    var paused = false

    /// Current overlay frame in screen coordinates. The panel tracks the
    /// worm instead of covering the whole screen, to keep compositing cheap.
    private(set) var viewOrigin: CGPoint = .zero
    private(set) var viewSize: CGSize = .zero

    /// Called with a screen point when the worm is right-clicked.
    var onRequestMenu: ((CGPoint) -> Void)?

    private var screen: NSScreen
    private var panel: DesktopPanel?
    private var timer: Timer?
    private var monitors: [Any] = []
    private var sampler = VitalsSampler()
    private var frame = 0

    init(screen: NSScreen) {
        self.screen = screen
        let bounds = screen.visibleFrame.insetBy(dx: 10, dy: 10)
        self.limits = PetModel.Limits(bounds: bounds)
        let savedSkin = UserDefaults.standard.string(forKey: Self.skinKey)
            .flatMap(WormSkin.init(rawValue:)) ?? .classic
        self.model = PetModel(
            head: CGPoint(x: bounds.midX + 200, y: bounds.minY + 160),
            heading: 0.6,
            skin: savedSkin
        )
        super.init()
        let frame = contentRect()
        viewOrigin = frame.origin
        viewSize = frame.size
        panel = DesktopPanel(contentView: NSHostingView(rootView: WormView(controller: self)), frame: frame)
    }

    func start() {
        stop()
        model.vitals = sampler.sample()
        let timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true, block: { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        })
        timer.tolerance = 0.005
        self.timer = timer
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown]
        ) { [weak self] event in
            let type = event.type
            let location = NSEvent.mouseLocation
            Task { @MainActor [weak self] in self?.handle(type: type, at: location) }
        } {
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
        limits.bounds = screen.visibleFrame.insetBy(dx: 10, dy: 10)
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
        // Drop near the worm so it stays visible and reachable.
        let angle = Double.random(in: 0 ..< 2 * Double.pi)
        let dist = CGFloat.random(in: 120...220)
        var point = CGPoint(
            x: model.head.x + cos(angle) * dist,
            y: model.head.y + sin(angle) * dist
        )
        // Nudge toward the nearest edge, matching the worm's preference.
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
        model.dropFood(at: point)
        movePanel()
    }

    @objc func setSkin(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let skin = WormSkin(rawValue: raw) else { return }
        model.skin = skin
        UserDefaults.standard.set(skin.rawValue, forKey: Self.skinKey)
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
        }
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
        case .rightMouseDown:
            if model.hitTest(point, radius: 44) { onRequestMenu?(point) }
        default:
            break
        }
    }
}
