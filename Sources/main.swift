import AppKit
import ScreenCaptureKit
import ServiceManagement

// Tuck: öndeki uygulamanın Dosya, Düzen, Görünüm... menülerini menü çubuğundan gizler,
// hepsini uygulamanın adının altındaki tek bir şemsiye menüde toplar.
//   Tuck --selftest   → koordinat çevirisini sınar

if CommandLine.arguments.contains("--selftest") {
    // Ana ekran 1920x1080; sağ üstünde, 98 nokta aşağıda 1512x982'lik ikinci ekran.
    let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let side = CGRect(x: -1512, y: 98, width: 1512, height: 982)
    let span = CGRect(x: 40, y: 0, width: 600, height: 30)
    precondition(anchorScreen(of: span, in: [main, side], primaryHeight: 1080) == main, "menünün ekranı")
    precondition(stripFrame(span: span, anchor: main, screen: side, barHeight: 32) == CGRect(x: -1472, y: 1048, width: 600, height: 32), "ikinci ekrandaki şerit")
    let sideSpan = CGRect(x: -1472, y: 0, width: 600, height: 32)
    precondition(anchorScreen(of: sideSpan, in: [main, side], primaryHeight: 1080) == side, "ikinci ekrandaki menü")
    let bar = CGRect(x: 0, y: 0, width: 1920, height: 30)
    precondition(!isFullScreen(bar: bar, windows: [CGRect(x: 100, y: 30, width: 800, height: 600)]), "normal pencere")
    precondition(!isFullScreen(bar: bar, windows: [CGRect(x: 0, y: 30, width: 1920, height: 1050)]), "ekranı dolduran pencere")
    precondition(!isFullScreen(bar: bar, windows: [CGRect(x: 1700, y: 0, width: 30, height: 30)]), "durum ikonu")
    precondition(isFullScreen(bar: bar, windows: [main]), "tam ekran pencere")
    precondition(isFullScreen(bar: bar, windows: [CGRect(x: 0, y: 0, width: 1920, height: 33)]), "çentikli ekrandaki üst şerit")
    print("selftest tamam")
    exit(0)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let controller = StripController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // İlk açılışta girişe eklenir; sonra menüdeki seçenek ne derse o.
        if !UserDefaults.standard.bool(forKey: "tuckLoginConfigured") {
            try? SMAppService.mainApp.register()
            UserDefaults.standard.set(true, forKey: "tuckLoginConfigured")
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "Tuck")
        let menu = NSMenu()
        let toggle = NSMenuItem(title: "Menüleri topla", action: #selector(toggle(_:)), keyEquivalent: "")
        toggle.target = self
        toggle.state = .on
        menu.addItem(toggle)
        let login = NSMenuItem(title: "Açılışta başlat", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Tuck'tan çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        // İzin pencereleri ilk açılışta gelir; Erişilebilirlik izni gelene kadar şerit görünmez.
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
            Task { _ = try? await SCShareableContent.current }   // Mac uygulamayı Ekran Kaydı listesine ancak gerçek bir denemede ekliyor
        }
        controller.start()
    }

    @objc private func toggle(_ item: NSMenuItem) {
        item.state = item.state == .on ? .off : .on
        controller.enabled = item.state == .on
    }

    @objc private func toggleLogin(_ item: NSMenuItem) {
        do {
            if item.state == .on { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {}
        item.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
