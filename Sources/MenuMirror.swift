import AppKit

// Öndeki uygulamanın menü çubuğunu Erişilebilirlik arayüzünden okur ve şemsiye menüye aynalar.
// Şemsiyedeki bir maddeye basılınca uygulamadaki gerçek maddeye basılır.

func axValue(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}

func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    axValue(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func axString(_ element: AXUIElement, _ name: String) -> String? {
    axValue(element, name) as? String
}

func axFrame(_ element: AXUIElement) -> CGRect? {
    guard let p = axValue(element, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
          let s = axValue(element, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero, size = CGSize.zero
    AXValueGetValue(p as! AXValue, .cgPoint, &point)
    AXValueGetValue(s as! AXValue, .cgSize, &size)
    return CGRect(origin: point, size: size)
}

struct MenuBar {
    let appName: String
    let appItem: AXUIElement
    let menus: [AXUIElement]
    let span: CGRect          // AX koordinatlarında, Apple menüsünün bitiminden son menünün sonuna
    let titleInset: CGFloat   // uygulama adının şeridin başına uzaklığı
    let appItemWidth: CGFloat
}

func readMenuBar(pid: pid_t) -> MenuBar? {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 0.3)
    guard let bar = axValue(app, kAXMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
    let items = axChildren(bar as! AXUIElement)
    guard items.count >= 2, let apple = axFrame(items[0]), let first = axFrame(items[1]) else { return nil }
    let menus = Array(items.dropFirst(2))
    let last = menus.compactMap(axFrame).last ?? first
    // Gerçek menünün vurgusu öğenin sınırından taşar ve o boşluktan gerçek menü açılabilir;
    // şerit Apple menüsünün hemen ardından başlar, sonda da biraz taşar.
    let start = apple.maxX, end = last.maxX + 8
    return MenuBar(appName: axString(items[1], kAXTitleAttribute) ?? "",
                   appItem: items[1], menus: menus,
                   span: CGRect(x: start, y: first.minY, width: end - start, height: first.height),
                   titleInset: first.minX - start, appItemWidth: first.width)
}

@MainActor
final class MenuMirror: NSObject, NSMenuDelegate {
    private var owners: [ObjectIdentifier: AXUIElement] = [:]   // alt menü → AX'teki sahibi

    func tucked(for bar: MenuBar) -> NSMenu {
        owners.removeAll()
        let menu = NSMenu()
        menu.autoenablesItems = false
        fill(menu, from: bar.appItem)
        menu.addItem(.separator())
        for owner in bar.menus {
            let item = NSMenuItem(title: axString(owner, kAXTitleAttribute) ?? "", action: nil, keyEquivalent: "")
            item.submenu = lazyMenu(owner, title: item.title)
            menu.addItem(item)
        }
        return menu
    }

    // Alt menüler açılınca doldurulur; Yer İşaretleri gibi büyük menüler önceden okunmaz.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let owner = owners[ObjectIdentifier(menu)] else { return }
        menu.removeAllItems()
        fill(menu, from: owner)
    }

    private func lazyMenu(_ owner: AXUIElement, title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        menu.delegate = self
        owners[ObjectIdentifier(menu)] = owner
        return menu
    }

    private func fill(_ menu: NSMenu, from owner: AXUIElement) {
        guard let axMenu = axChildren(owner).first else { return }
        for element in axChildren(axMenu) { menu.addItem(mirror(element)) }
    }

    private func mirror(_ element: AXUIElement) -> NSMenuItem {
        let title = axString(element, kAXTitleAttribute) ?? ""
        let hasSubmenu = !axChildren(element).isEmpty
        if title.isEmpty && !hasSubmenu { return .separator() }
        let item = NSMenuItem(title: title, action: hasSubmenu ? nil : #selector(press(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = element
        item.isEnabled = axValue(element, kAXEnabledAttribute) as? Bool ?? true
        if let mark = axString(element, kAXMenuItemMarkCharAttribute), !mark.isEmpty { item.state = .on }
        if let key = axString(element, kAXMenuItemCmdCharAttribute), !key.isEmpty {
            // AX değiştirici bitleri: 1 Shift, 2 Option, 4 Control, 8 Command yok.
            let bits = axValue(element, kAXMenuItemCmdModifiersAttribute) as? Int ?? 0
            var mask: NSEvent.ModifierFlags = bits & 8 == 0 ? [.command] : []
            if bits & 1 != 0 { mask.insert(.shift) }
            if bits & 2 != 0 { mask.insert(.option) }
            if bits & 4 != 0 { mask.insert(.control) }
            item.keyEquivalent = key.lowercased()
            item.keyEquivalentModifierMask = mask
        }
        if hasSubmenu { item.submenu = lazyMenu(element, title: title) }
        return item
    }

    @objc private func press(_ sender: NSMenuItem) {
        guard let element = sender.representedObject else { return }
        AXUIElementPerformAction(element as! AXUIElement, kAXPressAction as CFString)
    }
}
