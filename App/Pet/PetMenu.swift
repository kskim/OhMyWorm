import AppKit

/// The single menu, hosted by the status item.
/// Rebuilt on every open so stats and pause state stay fresh.
@MainActor final class PetMenuDelegate: NSObject, NSMenuDelegate {
    weak var controller: PetController?

    func menuWillOpen(_ menu: NSMenu) {
        if let controller { PetMenu.rebuild(menu, controller: controller) }
    }
}

@MainActor enum PetMenu {
    static func make(controller: PetController, delegate: NSMenuDelegate) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = delegate
        rebuild(menu, controller: controller)
        return menu
    }

    static func rebuild(_ menu: NSMenu, controller: PetController) {
        menu.removeAllItems()
        let info = NSMenuItem(title: controller.model.statusText, action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(.separator())

        let feed = NSMenuItem(title: L10n.text("밥주기", "Feed"), action: #selector(PetController.dropFood), keyEquivalent: "")
        feed.target = controller
        menu.addItem(feed)

        let skins = NSMenuItem(title: L10n.text("스킨 변경", "Change Skin"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for skin in WormSkin.allCases {
            let item = NSMenuItem(title: skin.displayName, action: #selector(PetController.setSkin(_:)), keyEquivalent: "")
            item.target = controller
            item.representedObject = skin.rawValue
            item.state = (skin == controller.model.skin) ? .on : .off
            submenu.addItem(item)
        }
        skins.submenu = submenu
        menu.addItem(skins)

        let engines = NSMenuItem(title: L10n.text("엔진 변경", "Change Engine"), action: nil, keyEquivalent: "")
        let engineSubmenu = NSMenu()
        for id in EngineID.allCases {
            let item = NSMenuItem(title: id.displayName, action: #selector(PetController.setEngine(_:)), keyEquivalent: "")
            item.target = controller
            item.representedObject = id.rawValue
            item.state = (id == controller.model.brain.id) ? .on : .off
            engineSubmenu.addItem(item)
        }
        engines.submenu = engineSubmenu
        menu.addItem(engines)
        menu.addItem(.separator())

        let pauseTitle = controller.paused
            ? L10n.text("계속하기", "Resume")
            : L10n.text("일시정지", "Pause")
        let pause = NSMenuItem(title: pauseTitle, action: #selector(PetController.togglePause), keyEquivalent: "")
        pause.target = controller
        menu.addItem(pause)

        let quit = NSMenuItem(title: L10n.text("종료", "Quit"), action: #selector(PetController.quitApp), keyEquivalent: "")
        quit.target = controller
        menu.addItem(quit)
    }
}
