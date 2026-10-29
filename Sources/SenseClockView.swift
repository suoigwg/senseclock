import AppKit
import ScreenSaver
import CoreText

// The legacy screen saver host can strip the title bar while presenting the
// settings remotely. A plain NSWindow then refuses to become key.
private final class SenseClockSettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@objc(SenseClockView)
final class SenseClockView: ScreenSaverView {
    private let preferences = ClockPreferences()
    private var reading: ClockReading?
    private var previous: ClockReading?
    private var flipStart: TimeInterval = 0
    private var lastDateKey = ""
    private var dateLabel = ""
    private var settingsWindow: NSWindow?
    private var settingsLanguage: AppLanguage?
    private var languagePicker: NSPopUpButton!
    private var hourToggle: NSButton!
    private var weatherToggle: NSButton!
    private var driftToggle: NSButton!
    private var sizeSlider: NSSlider!
    private var fahrenheitToggle: NSButton!
    private var animationToggle: NSButton!
    private var cardRasterScale: CGFloat = 1
    private var cachedRasterScale: CGFloat = 0
    private var cachedCardSize: NSSize = .zero
    private var cityField: NSTextField!
    private var cityPicker: NSPopUpButton!
    private var searchStatus: NSTextField!
    private var searchButton: NSButton!
    private var cityResults: [WeatherLocation] = []
    private var searchTask: URLSessionDataTask?
    private var searchGeneration = 0
    private var lastWeatherTick = -1
    private var texture: NSImage?
    private let duration: TimeInterval = 0.72
    private var positionEpoch = ProcessInfo.processInfo.systemUptime
    private var demoSnapshot: WeatherSnapshot?
    var weatherDemo: WeatherDemo? {
        didSet {
            demoSnapshot = weatherDemo?.snapshot(location: preferences.weatherLocation)
            needsDisplay = true
        }
    }
    // Only used for deterministic export; never persisted in user preferences.
    var fixedWeatherTime: TimeInterval?
    private var weatherMotionEnabled: Bool {
        fixedWeatherTime != nil || (preferences.weatherAnimations && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
    private var weatherTime: Double { weatherMotionEnabled ? (fixedWeatherTime ?? ProcessInfo.processInfo.systemUptime) : 0 }
    private var activeWeather: WeatherSnapshot? {
        demoSnapshot ?? (WeatherStore.shared.snapshot?.location == preferences.weatherLocation ? WeatherStore.shared.snapshot : nil)
    }
    // Used by the preview app's deterministic rendering checks.
    var fixedDate: Date? {
        didSet { updateTime(animate: fixedDate == nil) }
    }

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 30.0
        updateTime(animate: false)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        animationTimeInterval = 1.0 / 30.0
        updateTime(animate: false)
    }

    override func startAnimation() {
        positionEpoch = ProcessInfo.processInfo.systemUptime
        updateTime(animate: false)
        if preferences.showWeather && fixedDate == nil && weatherDemo == nil {
            WeatherStore.shared.refresh(location: preferences.weatherLocation)
        }
        super.startAnimation()
    }

    override func animateOneFrame() {
        updateTime(animate: true)
        // Weather and minute flips animate; the text anchor stays pixel-aligned.
        let now = ProcessInfo.processInfo.systemUptime
        if Int(now) != lastWeatherTick {
            lastWeatherTick = Int(now)
            if preferences.showWeather && fixedDate == nil && weatherDemo == nil {
                WeatherStore.shared.refresh(location: preferences.weatherLocation)
            }
            needsDisplay = true
        }
        if ((preferences.showWeather || weatherDemo != nil) && weatherMotionEnabled) || now - flipStart < duration {
            needsDisplay = true
        }
    }

    private func updateTime(animate: Bool) {
        let date = fixedDate ?? Date()
        let next = ClockReading(date: date, use24Hour: preferences.use24Hour)
        if next != reading {
            previous = animate ? reading : nil
            reading = next
            flipStart = ProcessInfo.processInfo.systemUptime
            needsDisplay = true
        }
        let key = "\(Calendar.current.startOfDay(for: date))-\(L10n.locale.identifier)-\(TimeZone.current.identifier)"
        if key != lastDateKey {
            lastDateKey = key
            let formatter = DateFormatter()
            formatter.locale = L10n.locale
            formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
            dateLabel = formatter.string(from: date)
        }
    }

    override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        guard bounds.width > 0, bounds.height > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        updateTime(animate: true)
        let weather = preferences.showWeather || weatherDemo != nil
        let scene = ClockSceneLayout(bounds: bounds.size, weather: weather, contentFraction: preferences.scale)
        let sceneSize = scene.contentSize
        let scale = scene.contentScale
        let layout = ClockContentLayout(size: sceneSize, weather: weather)
        let backing = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1
        cardRasterScale = min(8, max(1, scale * backing))

        // The weather belongs to the entire display. Clock size and anti-burn-in
        // offsets apply only to foreground content, keeping the backdrop stable.
        context.saveGState()
        context.translateBy(x: bounds.minX, y: bounds.minY)
        context.scaleBy(x: scene.backgroundScale, y: scene.backgroundScale)
        let canvas = NSRect(origin: .zero, size: scene.backgroundSize)
        drawPanel(rect: canvas)
        if weather, weatherMotionEnabled, let snapshot = activeWeather {
            WeatherEffects.draw(kind: WeatherKind.from(code: snapshot.code), isDay: snapshot.isDay,
                                time: weatherTime, panel: canvas)
            if WeatherKind.from(code: snapshot.code) == .storm {
                WeatherEffects.drawWideLightning(time: weatherTime, canvas: canvas)
            }
        }
        context.restoreGState()

        let t = ProcessInfo.processInfo.systemUptime
        let shift = preferences.drift && !isPreview && fixedDate == nil
            && bounds.width >= 640 && bounds.height >= 480
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let origin = ClockScenePlacement.origin(bounds: bounds, scene: sceneSize, scale: scale,
            elapsed: t - positionEpoch, shiftEnabled: shift,
            backingScale: window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1)
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: scale, y: scale)
        let progress = min(1, max(0, (t - flipStart) / duration))
        drawCard(current: reading?.hour ?? "00", old: previous?.hour, frame: layout.hour, progress: progress)
        drawCard(current: reading?.minute ?? "00", old: previous?.minute, frame: layout.minute, progress: progress)
        if let period = reading?.period, !period.isEmpty {
            text(period, rect: NSRect(x: layout.hour.minX + 13, y: layout.hour.minY + 13, width: 42, height: 18), size: 13, weight: .medium, color: .darkGray)
        }
        if weather {
            drawWeather(layout: layout)
        } else {
            text(dateLabel, rect: NSRect(x: layout.margin, y: max(20, layout.weatherHeight / 2 - 11), width: sceneSize.width - layout.margin * 2, height: 24), size: 16, color: NSColor(white: 0.7, alpha: 1), alignment: .center)
        }
        context.restoreGState()
    }

    private func drawPanel(rect: NSRect) {
        let path = NSBezierPath(rect: rect)
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSGradient(colors: [NSColor(white: 0.19, alpha: 1), NSColor(white: 0.095, alpha: 1), NSColor(white: 0.035, alpha: 1)])!
            .draw(in: path, angle: -80)
        if texture == nil { texture = makeTexture() }
        texture?.draw(in: rect, from: .zero, operation: .softLight, fraction: 0.23)
        NSGraphicsContext.restoreGraphicsState()
        NSColor(white: 1, alpha: 0.055).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func makeTexture() -> NSImage {
        let side = 600
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32)!
        var seed: UInt32 = 4271
        if let data = bitmap.bitmapData {
            for i in 0..<(side * side) {
                seed = 1664525 &* seed &+ 1013904223
                let value = UInt8(70 + (seed >> 24) % 110)
                data[i * 4] = value; data[i * 4 + 1] = value; data[i * 4 + 2] = value; data[i * 4 + 3] = 255
            }
        }
        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(bitmap)
        return image
    }

    private func cardImage(_ number: String, size: NSSize) -> NSImage {
        let pixels = NSSize(width: ceil(size.width * cardRasterScale), height: ceil(size.height * cardRasterScale))
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        // NSGraphicsContext uses bitmap.size to apply the backing resolution.
        let box = NSRect(origin: .zero, size: size)
        let outline = NSBezierPath(roundedRect: box.insetBy(dx: 1, dy: 1), xRadius: 13, yRadius: 13)
        outline.addClip()
        NSGradient(colors: [NSColor(white: 0.83, alpha: 1), NSColor(white: 0.98, alpha: 1)])!.draw(in: box, angle: 90)
        NSGradient(starting: NSColor(white: 0.89, alpha: 1), ending: NSColor(white: 1, alpha: 1))!.draw(in: NSRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2), angle: 90)
        func clockLine(_ value: String, fontSize: CGFloat) -> CTLine {
            let font = NSFont(name: "HelveticaNeue-UltraLight", size: fontSize) ?? .systemFont(ofSize: fontSize, weight: .ultraLight)
            return CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [.font: font, .foregroundColor: NSColor(white: 0.045, alpha: 1), .kern: -fontSize * 0.027]) as CFAttributedString)
        }
        let reference = CTLineGetBoundsWithOptions(clockLine("88", fontSize: 100), .useGlyphPathBounds)
        let fontSize = 100 * min(size.width * 0.86 / reference.width, size.height * 0.79 / reference.height)
        let line = clockLine(number, fontSize: fontSize)
        let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: (size.width - ink.width) / 2 - ink.minX, y: (size.height - ink.height) / 2 - ink.minY)
        CTLineDraw(line, context)
        NSColor(white: 0, alpha: 0.38).setFill()
        NSRect(x: 0, y: size.height / 2 - 1, width: size.width, height: 2).fill()
        NSColor(white: 1, alpha: 0.8).setFill()
        NSRect(x: 0, y: size.height / 2 - 2, width: size.width, height: 0.7).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size); image.addRepresentation(bitmap)
        return image
    }

    private var cardCache: [String: NSImage] = [:]
    private func cachedCard(_ number: String, size: NSSize) -> NSImage {
        if cachedCardSize != size || cachedRasterScale != cardRasterScale {
            cardCache.removeAll(keepingCapacity: true)
            cachedCardSize = size; cachedRasterScale = cardRasterScale
        }
        if let image = cardCache[number] { return image }
        if cardCache.count >= 8 { cardCache.removeAll(keepingCapacity: true) }
        let image = cardImage(number, size: size)
        cardCache[number] = image
        return image
    }

    private func drawCard(current: String, old: String?, frame: NSRect, progress: Double) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.85)
        shadow.shadowBlurRadius = 9
        shadow.shadowOffset = NSSize(width: 0, height: -4)
        shadow.set()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: frame.insetBy(dx: -2, dy: -2), xRadius: 15, yRadius: 15).fill()
        NSGraphicsContext.restoreGraphicsState()
        let newImage = cachedCard(current, size: frame.size)
        guard let old, old != current, progress < 1 else {
            newImage.draw(in: frame)
            return
        }
        let oldImage = cachedCard(old, size: frame.size)
        let half = frame.height / 2
        let top = NSRect(x: frame.minX, y: frame.midY, width: frame.width, height: half)
        let bottom = NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: half)
        let sourceTop = NSRect(x: 0, y: half, width: frame.width, height: half)
        let sourceBottom = NSRect(x: 0, y: 0, width: frame.width, height: half)
        newImage.draw(in: top, from: sourceTop, operation: .sourceOver, fraction: 1)
        oldImage.draw(in: bottom, from: sourceBottom, operation: .sourceOver, fraction: 1)
        // Two hinged leaves: the outgoing upper leaf falls to the seam, then
        // the incoming lower leaf unfolds. Cosine projection gives angular motion.
        if progress < 0.5 {
            let angle = progress * .pi
            let height = half * cos(angle)
            let leaf = NSRect(x: frame.minX, y: frame.midY, width: frame.width, height: height)
            oldImage.draw(in: leaf, from: sourceTop, operation: .sourceOver, fraction: 1)
            NSColor.black.withAlphaComponent(0.24 * sin(angle)).setFill()
            leaf.fill(using: .sourceOver)
        } else {
            let angle = (progress - 0.5) * .pi
            let height = half * sin(angle)
            let leaf = NSRect(x: frame.minX, y: frame.midY - height, width: frame.width, height: height)
            newImage.draw(in: leaf, from: sourceBottom, operation: .sourceOver, fraction: 1)
            NSColor.black.withAlphaComponent(0.24 * cos(angle)).setFill()
            leaf.fill(using: .sourceOver)
        }
    }

    private func drawWeather(layout: ClockContentLayout) {
        let store = WeatherStore.shared
        let snapshot = activeWeather
        let now = Date()
        let fahrenheit = preferences.fahrenheit
        func temperature(_ value: Double?) -> String { WeatherSnapshot.temperatureLabel(value, fahrenheit: fahrenheit) }
        func range(_ day: WeatherDay?) -> String { "\(temperature(day?.high)) / \(temperature(day?.low))" }
        let width = layout.size.width
        let margin = layout.margin
        let height = layout.weatherHeight
        let infoY = height * 0.68
        let typeScale = min(1.25, max(0.85, height / 235))
        let cityWidth = width * 0.34 - margin
        let city = weatherDemo == nil ? preferences.weatherLocation.name : L10n.text("Weather Demo")
        text(dateLabel, rect: NSRect(x: margin, y: infoY + 31 * typeScale, width: cityWidth, height: 25 * typeScale), size: 16 * typeScale, color: NSColor(white: 0.82, alpha: 1))
        let preferredCitySize: CGFloat = 28 * typeScale
        let measuredCityWidth = (city as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: preferredCitySize, weight: .medium)]).width
        let citySize = min(preferredCitySize, max(12 * typeScale, preferredCitySize * cityWidth * 0.98 / max(1, measuredCityWidth)))
        text(city, rect: NSRect(x: margin, y: infoY, width: cityWidth, height: 34 * typeScale), size: citySize, weight: .medium)
        let condition = weatherDemo?.title.components(separatedBy: " · ").first ?? snapshot.map { WeatherKind.from(code: $0.code).title } ?? (store.isLoading ? L10n.text("Loading weather…") : L10n.text("Weather unavailable"))
        text(condition, rect: NSRect(x: margin, y: infoY - 24 * typeScale, width: cityWidth, height: 22 * typeScale), size: 16 * typeScale, color: NSColor(white: 0.77, alpha: 1))
        drawWeatherIcon(center: NSPoint(x: width / 2, y: infoY + 30 * typeScale), size: 146 * typeScale,
                        kind: WeatherKind.from(code: snapshot?.code).rawValue, isDay: snapshot?.isDay ?? true)
        text(temperature(snapshot?.temperature), rect: NSRect(x: width - margin - 180 * typeScale, y: infoY + 5 * typeScale, width: 180 * typeScale, height: 53 * typeScale), size: 48 * typeScale, alignment: .right)
        text(range(snapshot?.today(at: now)), rect: NSRect(x: width - margin - 180 * typeScale, y: infoY - 24 * typeScale, width: 180 * typeScale, height: 28 * typeScale), size: 21 * typeScale, alignment: .right)
        let days = snapshot?.upcoming(at: now) ?? []
        for index in 0..<5 {
            let day = days.indices.contains(index) ? days[index] : nil
            let column = (width - margin * 2) / 5
            let x = margin + CGFloat(index) * column
            let center = x + column / 2
            text(day.map { WeatherSnapshot.weekday($0.date) } ?? "—", rect: NSRect(x: x, y: height * 0.38, width: column, height: 23 * typeScale), size: 16 * typeScale, alignment: .center)
            drawWeatherIcon(center: NSPoint(x: center, y: height * 0.245), size: 47 * typeScale, kind: WeatherKind.from(code: day?.code).rawValue)
            text(range(day), rect: NSRect(x: x, y: height * 0.075, width: column, height: 21 * typeScale), size: 14 * typeScale, color: NSColor(white: 0.86, alpha: 1), alignment: .center)
        }
    }

    private func drawWeatherIcon(center: NSPoint, size: CGFloat, kind: Int, isDay: Bool = true) {
        let weatherKind = WeatherKind(rawValue: kind) ?? .unknown
        if weatherKind == .unknown {
            text("—", rect: NSRect(x: center.x - size / 2, y: center.y - 10, width: size, height: 30), size: size * 0.35, color: .gray, alignment: .center)
            return
        }
        WeatherEffects.drawIcon(kind: weatherKind, isDay: isDay, time: weatherTime, center: center, size: size)
    }

    private func text(_ value: String, rect: NSRect, size: CGFloat, weight: NSFont.Weight = .regular,
                      color: NSColor = .white, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        (value as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .paragraphStyle: paragraph])
    }

    override var hasConfigureSheet: Bool { true }
    override var configureSheet: NSWindow? {
        NSLog("SenseClock: configureSheet requested in %@", Bundle.main.bundleIdentifier ?? "unknown host")
        if settingsWindow == nil || settingsLanguage != L10n.language { buildSettings() }
        languagePicker.selectItem(at: AppLanguage.allCases.firstIndex(of: preferences.language) ?? 0)
        hourToggle.state = preferences.use24Hour ? .on : .off
        weatherToggle.state = preferences.showWeather ? .on : .off
        driftToggle.state = preferences.drift ? .on : .off
        fahrenheitToggle.state = preferences.fahrenheit ? .on : .off
        animationToggle.state = preferences.weatherAnimations ? .on : .off
        sizeSlider.doubleValue = preferences.scale
        searchGeneration += 1
        searchTask?.cancel()
        searchButton.isEnabled = true
        cityField.stringValue = preferences.weatherLocation.name
        cityResults = [preferences.weatherLocation]
        cityPicker.removeAllItems()
        cityPicker.addItem(withTitle: preferences.weatherLocation.title)
        searchStatus.stringValue = L10n.text("Search, select a city, then save.")
        return settingsWindow
    }

    private func buildSettings() {
        let window = SenseClockSettingsPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 570), styleMask: [.titled], backing: .buffered, defer: false)
        window.isFloatingPanel = false
        window.becomesKeyOnlyIfNeeded = false
        window.isReleasedWhenClosed = false
        window.title = L10n.text("SenseClock Settings")
        let content = window.contentView!
        func label(_ value: String, _ frame: NSRect, size: CGFloat = 13) -> NSTextField {
            let field = NSTextField(labelWithString: value)
            field.font = .systemFont(ofSize: size)
            field.frame = frame
            content.addSubview(field)
            return field
        }
        _ = label(L10n.text("SenseClock Flip Clock"), NSRect(x: 24, y: 523, width: 420, height: 28), size: 20)
        settingsLanguage = L10n.language
        _ = label(L10n.text("Language"), NSRect(x: 24, y: 485, width: 150, height: 22))
        languagePicker = NSPopUpButton(frame: NSRect(x: 180, y: 481, width: 336, height: 28), pullsDown: false)
        languagePicker.addItems(withTitles: AppLanguage.allCases.map { $0.title })
        content.addSubview(languagePicker)
        hourToggle = NSButton(checkboxWithTitle: L10n.text("Use 24-hour time"), target: nil, action: nil)
        weatherToggle = NSButton(checkboxWithTitle: L10n.text("Show live weather"), target: nil, action: nil)
        driftToggle = NSButton(checkboxWithTitle: L10n.text("Shift every 5 minutes (screen saver only)"), target: nil, action: nil)
        fahrenheitToggle = NSButton(checkboxWithTitle: L10n.text("Use Fahrenheit (°F)"), target: nil, action: nil)
        animationToggle = NSButton(checkboxWithTitle: L10n.text("Weather animation (respects Reduce Motion)"), target: nil, action: nil)
        for (index, button) in [hourToggle!, weatherToggle!, driftToggle!, fahrenheitToggle!, animationToggle!].enumerated() {
            button.frame = NSRect(x: 24, y: 434 - index * 34, width: 492, height: 24)
            content.addSubview(button)
        }
        _ = label(L10n.text("Clock and weather size"), NSRect(x: 24, y: 253, width: 175, height: 22))
        sizeSlider = NSSlider(value: preferences.scale, minValue: 0.4, maxValue: 1, target: nil, action: nil)
        sizeSlider.frame = NSRect(x: 204, y: 253, width: 308, height: 24)
        content.addSubview(sizeSlider)
        _ = label(L10n.text("Weather city (city + country supported)"), NSRect(x: 24, y: 215, width: 422, height: 22))
        cityField = NSTextField(frame: NSRect(x: 24, y: 181, width: 321, height: 25))
        cityField.placeholderString = L10n.text("e.g. Beijing / Paris, France")
        cityField.target = self
        cityField.action = #selector(searchCity)
        content.addSubview(cityField)
        searchButton = NSButton(title: L10n.text("Search"), target: self, action: #selector(searchCity))
        searchButton.bezelStyle = .rounded
        searchButton.frame = NSRect(x: 353, y: 177, width: 93, height: 32)
        content.addSubview(searchButton)
        cityPicker = NSPopUpButton(frame: NSRect(x: 24, y: 141, width: 422, height: 28), pullsDown: false)
        content.addSubview(cityPicker)
        searchStatus = label("", NSRect(x: 24, y: 104, width: 422, height: 29), size: 11)
        searchStatus.maximumNumberOfLines = 2
        let attribution = NSMutableAttributedString(string: L10n.text("Weather: Open-Meteo · CC BY 4.0"), attributes: [.font: NSFont.systemFont(ofSize: 11)])
        attribution.addAttribute(.link, value: URL(string: "https://open-meteo.com/")!, range: (attribution.string as NSString).range(of: "Open-Meteo"))
        attribution.addAttribute(.link, value: URL(string: "https://creativecommons.org/licenses/by/4.0/")!, range: (attribution.string as NSString).range(of: "CC BY 4.0"))
        let source = NSTextField(labelWithAttributedString: attribution)
        source.isSelectable = true
        source.allowsEditingTextAttributes = true
        source.frame = NSRect(x: 24, y: 77, width: 422, height: 20)
        content.addSubview(source)
        _ = label(L10n.text("Refreshes every 30 min · No location permission"), NSRect(x: 24, y: 59, width: 310, height: 18), size: 11)
        let done = NSButton(title: L10n.text("Save"), target: self, action: #selector(saveSettings))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        done.frame = NSRect(x: 350, y: 24, width: 96, height: 32)
        content.addSubview(done)
        let cancel = NSButton(title: L10n.text("Cancel"), target: self, action: #selector(cancelSettings))
        cancel.bezelStyle = .rounded
        cancel.keyEquivalent = "\u{1b}"
        cancel.frame = NSRect(x: 248, y: 24, width: 96, height: 32)
        content.addSubview(cancel)
        settingsWindow = window
    }

    @objc private func searchCity() {
        let query = cityField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { searchStatus.stringValue = L10n.text("Enter at least two characters."); return }
        searchGeneration += 1
        let generation = searchGeneration
        searchTask?.cancel()
        searchButton.isEnabled = false
        searchStatus.stringValue = L10n.text("Searching…")
        searchTask = WeatherAPI.search(query) { [weak self] result in
            guard let self, self.searchGeneration == generation else { return }
            self.searchButton.isEnabled = true
            switch result {
            case .success(let cities):
                self.cityResults = cities
                self.cityPicker.removeAllItems()
                self.cityPicker.addItems(withTitles: cities.map { $0.title })
                self.searchStatus.stringValue = L10n.format("Found %ld results. Confirm the region and save.", cities.count)
            case .failure(let error):
                self.searchStatus.stringValue = L10n.format("Search failed: %@", error.localizedDescription)
            }
        }
    }

    @objc private func cancelSettings() {
        searchGeneration += 1
        searchTask?.cancel()
        dismissSettings()
    }

    @objc private func saveSettings() {
        searchGeneration += 1
        searchTask?.cancel()
        preferences.language = AppLanguage.allCases[languagePicker.indexOfSelectedItem]
        preferences.use24Hour = hourToggle.state == .on
        preferences.showWeather = weatherToggle.state == .on
        preferences.drift = driftToggle.state == .on
        preferences.fahrenheit = fahrenheitToggle.state == .on
        preferences.weatherAnimations = animationToggle.state == .on
        preferences.scale = sizeSlider.doubleValue
        let selected = cityPicker.indexOfSelectedItem
        if cityResults.indices.contains(selected) { preferences.weatherLocation = cityResults[selected] }
        if preferences.showWeather { WeatherStore.shared.refresh(location: preferences.weatherLocation, force: true) }
        updateTime(animate: false)
        needsDisplay = true
        dismissSettings()
        NotificationCenter.default.post(name: L10n.didChange, object: nil)
    }

    private func dismissSettings() {
        guard let window = settingsWindow else { return }
        // Use the ScreenSaver framework's documented NSApplication API: the
        // remote host need not expose a local sheetParent to the plugin.
        NSApp.endSheet(window)
        window.orderOut(nil)
    }
}
