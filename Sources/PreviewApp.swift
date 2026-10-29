import AppKit
import ImageIO

@main
final class PreviewApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var clock: SenseClockView!
    private var weatherPicker: NSSegmentedControl!
    private var tourButton: NSButton!
    private var tourTimer: Timer?
    private var controlsBar: NSStackView!

    static func main() {
        let app = NSApplication.shared
        let delegate = PreviewApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
        withExtendedLifetime(delegate) {}
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--export-weather"), arguments.count > index + 1 {
            exportWeather(path: arguments[index + 1])
            NSApp.terminate(nil)
            return
        }
        if let index = arguments.firstIndex(of: "--snapshot") ?? arguments.firstIndex(of: "--live-snapshot"), arguments.count > index + 1 {
            if arguments.contains("--live-snapshot") {
                WeatherStore.shared.refresh(location: ClockPreferences().weatherLocation, force: true)
                let deadline = Date().addingTimeInterval(20)
                while WeatherStore.shared.isLoading && Date() < deadline {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                }
            }
            renderSnapshot(path: arguments[index + 1])
            NSApp.terminate(nil)
            return
        }
        rebuildMenus()
        NotificationCenter.default.addObserver(self, selector: #selector(refreshLanguage), name: L10n.didChange, object: nil)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.delegate = self
        window.minSize = NSSize(width: 680, height: 560)
        window.backgroundColor = .black
        let root = NSView(frame: window.contentView!.bounds)
        clock = SenseClockView(frame: NSRect(x: 0, y: 64, width: root.bounds.width, height: root.bounds.height - 64), isPreview: true)!
        clock.autoresizingMask = [.width, .height]
        root.addSubview(clock)
        weatherPicker = NSSegmentedControl(labels: [L10n.text("Live"), L10n.text("Clear"), L10n.text("Partly Cloudy"), L10n.text("Cloudy"), L10n.text("Rain"), L10n.text("Snow"), L10n.text("Fog"), L10n.text("Storm"), L10n.text("Clear Night")], trackingMode: .selectOne, target: self, action: #selector(pickWeather))
        weatherPicker.selectedSegment = 0
        tourButton = NSButton(title: L10n.text("Auto Tour"), target: self, action: #selector(toggleTour))
        tourButton.bezelStyle = .rounded
        let controls = NSStackView(views: [weatherPicker, tourButton])
        controlsBar = controls
        controls.spacing = 14
        controls.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(controls)
        NSLayoutConstraint.activate([
            controls.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            controls.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20)
        ])
        window.contentView = root
        if arguments.contains("--showcase") { clock.weatherDemo = .clear }
        if arguments.contains("--storm-demo") { clock.weatherDemo = .storm }
        updateTitle()
        window.center()
        window.makeKeyAndOrderFront(nil)
        clock.startAnimation()
        if arguments.contains("--showcase") { toggleTour() }
        NSApp.activate(ignoringOtherApps: true)
        if arguments.contains("--fullscreen") { window.toggleFullScreen(nil) }
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        controlsBar.isHidden = true
        clock.frame = window.contentView!.bounds
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        controlsBar.isHidden = false
        let bounds = window.contentView!.bounds
        clock.frame = NSRect(x: 0, y: 64, width: bounds.width, height: bounds.height - 64)
    }

    private func rebuildMenus() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L10n.text("Settings…"), action: #selector(showSettings), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: L10n.text("Demo Flip"), action: #selector(demoFlip), keyEquivalent: "d").target = self
        appMenu.addItem(withTitle: L10n.text("Toggle Full Screen"), action: #selector(toggleFullScreen), keyEquivalent: "f").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.text("Quit SenseClock"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let weatherItem = NSMenuItem()
        let weatherMenu = NSMenu(title: L10n.text("Weather Demo"))
        let live = weatherMenu.addItem(withTitle: L10n.text("Follow Live Weather"), action: #selector(selectWeather), keyEquivalent: "0")
        live.tag = 0; live.target = self
        for mode in WeatherDemo.allCases {
            let item = weatherMenu.addItem(withTitle: mode.title, action: #selector(selectWeather), keyEquivalent: String(mode.rawValue))
            item.tag = mode.rawValue; item.target = self
        }
        weatherMenu.addItem(.separator())
        weatherMenu.addItem(withTitle: L10n.text("Auto Tour / Pause"), action: #selector(toggleTour), keyEquivalent: "9").target = self
        weatherItem.submenu = weatherMenu
        menu.addItem(weatherItem)
        NSApp.mainMenu = menu
    }

    @objc private func refreshLanguage() {
        rebuildMenus()
        let keys = ["Live", "Clear", "Partly Cloudy", "Cloudy", "Rain", "Snow", "Fog", "Storm", "Clear Night"]
        for (index, key) in keys.enumerated() { weatherPicker.setLabel(L10n.text(key), forSegment: index) }
        tourButton.title = L10n.text(tourTimer == nil ? "Auto Tour" : "Pause Tour")
        updateTitle()
        clock.needsDisplay = true
    }

    private func updateTitle() {
        weatherPicker.selectedSegment = clock.weatherDemo?.rawValue ?? 0
        window.title = L10n.format("SenseClock — %@ · ⌘0–8 switch · ⌘9 tour", clock.weatherDemo.map { L10n.format("Demo · %@", $0.title) } ?? L10n.text("Live Weather"))
    }

    private func stopTour() {
        tourTimer?.invalidate(); tourTimer = nil
        tourButton.title = L10n.text("Auto Tour")
    }

    @objc private func selectWeather(_ sender: NSMenuItem) {
        stopTour()
        clock.weatherDemo = WeatherDemo(rawValue: sender.tag)
        updateTitle()
    }

    @objc private func pickWeather() {
        stopTour()
        clock.weatherDemo = WeatherDemo(rawValue: weatherPicker.selectedSegment)
        updateTitle()
    }

    @objc private func toggleTour() {
        if tourTimer != nil { stopTour(); return }
        if clock.weatherDemo == nil { clock.weatherDemo = .clear }
        updateTitle()
        tourButton.title = L10n.text("Pause Tour")
        let timer = Timer(timeInterval: 6, repeats: true) { [weak self] _ in
            guard let self, self.window.attachedSheet == nil else { return }
            let next = (self.clock.weatherDemo?.rawValue ?? 0) % WeatherDemo.allCases.count + 1
            self.clock.weatherDemo = WeatherDemo(rawValue: next)
            self.updateTitle()
        }
        RunLoop.main.add(timer, forMode: .common)
        tourTimer = timer
    }

    @objc private func showSettings() {
        if let sheet = clock.configureSheet { window.beginSheet(sheet) }
    }
    @objc private func toggleFullScreen() { window.toggleFullScreen(nil) }
    @objc private func demoFlip() {
        clock.fixedDate = Date().addingTimeInterval(-60)
        clock.fixedDate = nil
        clock.animateOneFrame()
    }

    private func bitmap(width: Int, height: Int) -> NSBitmapImageRep {
        NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    }

    private func renderSnapshot(path: String) {
        let view = SenseClockView(frame: NSRect(x: 0, y: 0, width: 1600, height: 1000), isPreview: true)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        view.fixedDate = CommandLine.arguments.contains("--live-snapshot") ? Date() : calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 12, minute: 47))!
        if CommandLine.arguments.contains("--storm-demo") { view.weatherDemo = .storm; view.fixedWeatherTime = 1.1 }
        let bitmap = bitmap(width: 1600, height: 1000)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        do { try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path)) }
        catch { fputs("Snapshot failed: \(error)\n", stderr); exit(1) }
    }

    private func exportWeather(path: String) {
        let url = URL(fileURLWithPath: path)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "com.compuserve.gif" as CFString, 128, nil) else { exit(1) }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let views = WeatherDemo.allCases.map { mode -> SenseClockView in
            let view = SenseClockView(frame: NSRect(x: 0, y: 0, width: 320, height: 360), isPreview: true)!
            view.fixedDate = Date()
            view.weatherDemo = mode
            return view
        }
        for frame in 0..<128 {
            autoreleasepool {
                let bitmap = self.bitmap(width: 1280, height: 820)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                NSColor.black.setFill(); NSRect(x: 0, y: 0, width: 1280, height: 820).fill()
                let context = NSGraphicsContext.current!.cgContext
                for (index, view) in views.enumerated() {
                    let x = CGFloat(index % 4) * 320
                    let y = CGFloat(1 - index / 4) * 410
                    view.fixedWeatherTime = Double(frame) / 10 + 0.1
                    context.saveGState()
                    context.translateBy(x: x, y: y + 8)
                    view.draw(view.bounds)
                    context.restoreGState()
                    let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
                    (WeatherDemo.allCases[index].title as NSString).draw(in: NSRect(x: x, y: y + 378, width: 320, height: 24), withAttributes: [.font: NSFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
                }
                NSGraphicsContext.restoreGraphicsState()
                CGImageDestinationAddImage(destination, bitmap.cgImage!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
                if frame == 8 {
                    try? bitmap.representation(using: .png, properties: [:])!.write(to: url.deletingPathExtension().appendingPathExtension("png"))
                }
            }
        }
        guard CGImageDestinationFinalize(destination) else { exit(1) }
        print("Exported eight weather animations: \(path)")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        tourTimer?.invalidate()
        clock?.stopAnimation()
    }
}
