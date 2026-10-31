import AppKit
import CoreImage
import ScreenCaptureKit

// README kayıtları:  open -n Tuck.app --args --record <senaryo> <klasör>
// Ana ekranın sol üst köşesini saniyede 12 kare kaydeder. Görüntüye yalnız masaüstü, menü çubuğu ve Tuck girer;
// öbür uygulamaların pencereleri görünmez. Fareyi ve uygulamaları Tuck kendisi oynatır, sonunda fareyi yerine koyup kapanır.
//   tuck  → gerçek menüler, Tuck açılınca kalan ad, toplanan menü ve bir alt menü
//   apps  → uygulamalar arasında geçerken adın değişmesi

let recordRect = CGRect(x: 0, y: 0, width: 960, height: 660)

final class Recorder: NSObject, SCStreamOutput {
    private let queue = DispatchQueue(label: "tuck.record")
    private let context = CIContext()
    private let dir: URL
    private var stream: SCStream?
    private var timer: DispatchSourceTimer?
    private var latest: CGImage?
    private var index = 0

    init(dir: URL) { self.dir = dir }

    func start(scale: CGFloat) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else { return }
        let keep: Set<String> = [Bundle.main.bundleIdentifier ?? "", "com.apple.dock"]   // Dock duvar kağıdını çizer
        let filter = SCContentFilter(display: display, excludingApplications: content.applications.filter { !keep.contains($0.bundleIdentifier) },
                                     exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = recordRect
        config.width = Int(recordRect.width * scale)
        config.height = Int(recordRect.height * scale)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0 / 12)
        timer.setEventHandler { [weak self] in self?.writeLatest() }
        timer.resume()
        self.timer = timer
    }

    func stop() async {
        timer?.cancel()
        try? await stream?.stopCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let pixels = buffer.imageBuffer else { return }   // ekran değişmeyince görüntüsüz kare gelir
        let image = CIImage(cvPixelBuffer: pixels)
        latest = context.createCGImage(image, from: image.extent)
    }

    // Ekran değişmese de kare yazılır; GIF gerçek süresinde oynar.
    private func writeLatest() {
        let url = dir.appendingPathComponent(String(format: "f%05d.png", index))
        guard let latest, let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, latest, nil)
        CGImageDestinationFinalize(dest)
        index += 1
    }
}

enum Demo {
    static func run(scenario: String, dir: String, controller: StripController) {
        let url = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 1
        Thread.detachNewThread {
            let home = CGEvent(source: nil)?.location ?? .zero
            let recorder = Recorder(dir: url)
            let start = { blocking { try? await recorder.start(scale: scale) } }
            if scenario == "apps" { apps(controller, start: start) } else { tuck(controller, start: start) }
            blocking { await recorder.stop() }
            post(.mouseMoved, at: home)
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private static func tuck(_ c: StripController, start: () -> Void) {
        open("com.anthropic.claudefordesktop")
        onMain { c.enabled = false }
        let parked = CGPoint(x: 640, y: 330)
        post(.mouseMoved, at: parked)
        wait(1.2)
        start()
        wait(1.6)
        onMain { c.enabled = true }
        wait(1.8)
        guard let target = onMain({ c.demoTarget }) else { return }
        glide(to: target.title)
        wait(0.3)
        click(at: target.title)
        wait(1.2)
        if target.menus.count > 2, let item = itemFrame(target.menus[2]) {   // Görünüm / View
            glide(to: CGPoint(x: item.midX, y: item.midY))
            wait(1.3)
            glide(to: CGPoint(x: item.maxX + 70, y: item.midY + 24))
            wait(1.6)
        }
        onMain { c.closeMenu() }
        wait(0.6)
        glide(to: parked)
        wait(0.8)
    }

    private static func apps(_ c: StripController, start: () -> Void) {
        onMain { c.enabled = true }
        open("com.apple.finder")
        post(.mouseMoved, at: CGPoint(x: 1500, y: 760))   // kayıt alanının dışında
        wait(1.2)
        start()
        wait(1.0)
        for id in ["com.anthropic.claudefordesktop", "com.brave.Browser", "md.obsidian", "com.apple.finder"] {
            open(id)
            wait(1.5)
        }
    }

    private static func blocking(_ work: @escaping () async -> Void) {
        let done = DispatchSemaphore(value: 0)
        Task.detached { await work(); done.signal() }
        done.wait()
    }

    private static func onMain<T>(_ work: @MainActor () -> T) -> T {
        DispatchQueue.main.sync { MainActor.assumeIsolated(work) }
    }

    private static func wait(_ seconds: Double) { Thread.sleep(forTimeInterval: seconds) }

    private static func open(_ bundleID: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-b", bundleID]
        try? task.run()
        task.waitUntilExit()
    }

    private static func post(_ type: CGEventType, at point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    private static func glide(to target: CGPoint, duration: Double = 0.5) {
        let from = CGEvent(source: nil)?.location ?? target
        let steps = 24
        for i in 1...steps {
            let t = Double(i) / Double(steps), e = t * t * (3 - 2 * t)
            post(.mouseMoved, at: CGPoint(x: from.x + (target.x - from.x) * e, y: from.y + (target.y - from.y) * e))
            wait(duration / Double(steps))
        }
    }

    private static func click(at point: CGPoint) {
        post(.leftMouseDown, at: point)
        wait(0.08)
        post(.leftMouseUp, at: point)
    }

    /// Açık menüdeki bir maddenin çerçevesi; Tuck kendi menüsünü de Erişilebilirlik arayüzünden okur.
    private static func itemFrame(_ title: String) -> CGRect? {
        func search(_ element: AXUIElement, depth: Int) -> AXUIElement? {
            if axString(element, kAXRoleAttribute) == kAXMenuItemRole, axString(element, kAXTitleAttribute) == title { return element }
            guard depth > 0 else { return nil }
            for child in axChildren(element) { if let hit = search(child, depth: depth - 1) { return hit } }
            return nil
        }
        let app = AXUIElementCreateApplication(getpid())
        AXUIElementSetMessagingTimeout(app, 1)
        return search(app, depth: 4).flatMap(axFrame)
    }
}
