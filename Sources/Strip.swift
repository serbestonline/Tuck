import AppKit
import ScreenCaptureKit

// Menü çubuğunda, uygulama adından son menüye kadar uzanan şerit. Arkasındaki duvar kağıdını
// canlı yakalayıp çizer (Aerial duvar kağıtları hareket ettiği için sabit resim yetmiyor),
// üstüne yalnız uygulamanın adını yazar. Ada tıklanınca şemsiye menü açılır.

/// AX koordinatları ana ekranın sol üst köşesinden başlar, Cocoa'nınkiler sol alttan.
func anchorScreen(of span: CGRect, in screens: [CGRect], primaryHeight: CGFloat) -> CGRect? {
    let point = CGPoint(x: span.minX + 1, y: primaryHeight - span.minY - 1)
    return screens.first { $0.contains(point) }
}

/// Menüler her ekranın menü çubuğunda aynı yatay konumda durur; şerit o konuma, ekranın tepesine oturur.
func stripFrame(span: CGRect, anchor: CGRect, screen: CGRect, barHeight: CGFloat) -> CGRect {
    CGRect(x: screen.minX + span.minX - anchor.minX, y: screen.maxY - barHeight, width: span.width, height: barHeight)
}

/// Tam ekran bir Space'te uygulama o ekranın menü çubuğunun üstüne ekran boyu bir pencere koyar: çentiksiz
/// ekranda pencerenin kendisi, çentikli ekranda üstteki şerit. Normal pencereler ve durum ikonları buna uymaz.
/// Dikdörtgenler AX koordinatında; windows yalnız uygulama pencereleri (sistem ve Tuck hariç).
func isFullScreen(bar: CGRect, windows: [CGRect]) -> Bool {
    windows.contains { $0.width >= bar.width * 0.9 && $0.intersects(bar.insetBy(dx: 0, dy: 1)) }
}

func appWindows() -> [CGRect] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return list.compactMap { info in
        guard info[kCGWindowOwnerPID as String] as? pid_t != getpid(),
              !["Window Server", "Dock"].contains(info[kCGWindowOwnerName as String] as? String ?? ""),
              (info[kCGWindowLayer as String] as? Int ?? -1) >= 0 else { return nil }
        return info[kCGWindowBounds as String].flatMap { CGRect(dictionaryRepresentation: $0 as! CFDictionary) }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID { deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0 }
    var menuBarHeight: CGFloat { frame.maxY - visibleFrame.maxY }
}

@MainActor
final class StripController {
    var enabled = true { didSet { refresh() } }
    private var strips: [CGDirectDisplayID: StripWindow] = [:]
    private var bar: MenuBar?
    private let mirror = MenuMirror()
    private var capturing = false

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // Menüler uygulama içinde de değişir (yeni pencere, farklı sekme); yarım saniyede bir bakmak yeterli.
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
                self?.captureBackgrounds()
            }
        }
        refresh()
    }

    func refresh() {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier == getpid() { return }
        guard enabled, AXIsProcessTrusted(), let front,
              let bar = readMenuBar(pid: front.processIdentifier), !bar.menus.isEmpty,
              let primary = NSScreen.screens.first?.frame,
              let anchor = anchorScreen(of: bar.span, in: NSScreen.screens.map(\.frame), primaryHeight: primary.maxY)
        else {
            strips.values.forEach { $0.orderOut(nil) }
            bar = nil
            return
        }
        self.bar = bar
        var shown = Set<CGDirectDisplayID>()
        let windows = appWindows()
        for screen in NSScreen.screens where screen.menuBarHeight > 0 {
            let axBar = CGRect(x: screen.frame.minX, y: primary.maxY - screen.frame.maxY, width: screen.frame.width, height: screen.menuBarHeight)
            if isFullScreen(bar: axBar, windows: windows) { continue }
            let strip = strips[screen.displayID] ?? StripWindow(controller: self)
            strips[screen.displayID] = strip
            let frame = stripFrame(span: bar.span, anchor: anchor, screen: screen.frame, barHeight: screen.menuBarHeight)
            strip.show(frame: frame, offset: frame.minX - screen.frame.minX, title: bar.appName,
                       titleInset: bar.titleInset, titleWidth: bar.appItemWidth)
            shown.insert(screen.displayID)
        }
        for (id, strip) in strips where !shown.contains(id) { strip.orderOut(nil) }
    }

    func openMenus(from view: StripView) {
        guard let bar else { return }
        view.isOpen = true
        mirror.tucked(for: bar).popUp(positioning: nil, at: NSPoint(x: bar.titleInset, y: 0), in: view)
        view.isOpen = false
    }

    // Her ekranın menü çubuğu boyunca yalnız masaüstü katmanını yakalar: menü yazıları ve şeridin kendisi
    // görüntüye girmez. Şerit genişleyip daralınca aynı görüntünün başka bir parçasını çizer.
    private func captureBackgrounds() {
        guard !capturing, CGPreflightScreenCaptureAccess(), strips.values.contains(where: \.isVisible) else { return }
        capturing = true
        Task {
            defer { capturing = false }
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return }
            let desktop = content.windows.filter { $0.windowLayer < 0 }
            for (id, strip) in strips where strip.isVisible {
                guard let display = content.displays.first(where: { $0.displayID == id }),
                      let screen = NSScreen.screens.first(where: { $0.displayID == id }) else { continue }
                let config = SCStreamConfiguration()
                config.sourceRect = CGRect(x: 0, y: 0, width: screen.frame.width, height: screen.menuBarHeight)
                config.width = Int(screen.frame.width * screen.backingScaleFactor)
                config.height = Int(screen.menuBarHeight * screen.backingScaleFactor)
                config.showsCursor = false
                let filter = SCContentFilter(display: display, including: desktop)
                if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                    strip.view.background = image
                }
            }
        }
    }
}

@MainActor
final class StripWindow: NSPanel {
    let view: StripView

    init(controller: StripController) {
        view = StripView()
        view.controller = controller
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        contentView = view
    }

    func show(frame: CGRect, offset: CGFloat, title: String, titleInset: CGFloat, titleWidth: CGFloat) {
        if self.frame != frame { setFrame(frame, display: false) }
        if view.title != title || view.titleWidth != titleWidth || view.titleInset != titleInset || view.offset != offset {
            view.title = title
            view.titleInset = titleInset
            view.titleWidth = titleWidth
            view.offset = offset
            view.needsDisplay = true
        }
        if !isVisible { orderFrontRegardless() }
    }
}

@MainActor
final class StripView: NSView {
    weak var controller: StripController?
    var title = ""
    var titleInset: CGFloat = 0
    var titleWidth: CGFloat = 0
    var offset: CGFloat = 0          // şeridin ekranın sol kenarına uzaklığı
    var isOpen = false { didSet { needsDisplay = true } }
    var background: CGImage? {
        didSet {
            darkText = background.map(isBright) ?? false
            needsDisplay = true
        }
    }
    private var darkText = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { controller?.openMenus(from: self) }

    override func draw(_ dirtyRect: NSRect) {
        if let background, let ctx = NSGraphicsContext.current?.cgContext {
            let width = CGFloat(background.width) * bounds.height / CGFloat(background.height)
            ctx.draw(background, in: CGRect(x: -offset, y: 0, width: width, height: bounds.height))
        }
        let color: NSColor = darkText ? .black : .white
        let text = NSAttributedString(string: title, attributes: [.font: NSFont.boldSystemFont(ofSize: 13), .foregroundColor: color])
        let size = text.size()
        let x = titleInset + (titleWidth - size.width) / 2
        if isOpen {
            color.withAlphaComponent(0.2).setFill()
            NSBezierPath(roundedRect: NSRect(x: x - 9, y: 3, width: size.width + 18, height: bounds.height - 6), xRadius: 7, yRadius: 7).fill()
        }
        text.draw(at: NSPoint(x: x, y: (bounds.height - size.height) / 2))
    }

    private func isBright(_ image: CGImage) -> Bool {
        guard let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let p = data.assumingMemoryBound(to: UInt8.self)
        return 0.299 * Double(p[0]) + 0.587 * Double(p[1]) + 0.114 * Double(p[2]) > 150
    }
}
