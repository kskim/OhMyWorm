import AppKit

/// The single menu for the status item and worm right-click.
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

        let feed = NSMenuItem(title: "밥주기", action: #selector(PetController.dropFood), keyEquivalent: "")
        feed.target = controller
        menu.addItem(feed)

        let skins = NSMenuItem(title: "스킨 변경", action: nil, keyEquivalent: "")
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
        menu.addItem(.separator())

        let pauseTitle = controller.paused ? "계속하기" : "일시정지"
        let pause = NSMenuItem(title: pauseTitle, action: #selector(PetController.togglePause), keyEquivalent: "")
        pause.target = controller
        menu.addItem(pause)

        let quit = NSMenuItem(title: "종료", action: #selector(PetController.quitApp), keyEquivalent: "")
        quit.target = controller
        menu.addItem(quit)
    }
}
