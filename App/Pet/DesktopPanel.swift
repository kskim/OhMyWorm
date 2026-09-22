import AppKit

/// Small transparent overlay that tracks the worm. It never takes clicks;
/// interaction is observed through a global event monitor instead.
final class DesktopPanel: NSPanel {
    init(contentView: NSView, frame: CGRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        contentView.frame = NSRect(origin: .zero, size: frame.size)
        contentView.autoresizingMask = [.width, .height]
        self.contentView = contentView
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        isExcludedFromWindowsMenu = true
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func moveTo(_ frame: CGRect) {
        setFrame(frame, display: true)
    }
}
