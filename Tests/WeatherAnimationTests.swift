import AppKit

@main
struct WeatherAnimationTests {
    static func render(_ view: SenseClockView, time: Double) -> NSBitmapImageRep {
        view.fixedWeatherTime = time
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width), pixelsHigh: Int(view.bounds.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
    static func main() {
        L10n.resourceRootOverride = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets/Localizations")
        _ = NSApplication.shared
        WeatherEffects.assetRootOverride = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets/Weather")
        let view = SenseClockView(frame: NSRect(x: 0, y: 0, width: 600, height: 560), isPreview: true)!
        view.fixedDate = Date(timeIntervalSince1970: 1793216820)
        for mode in WeatherDemo.allCases {
            view.weatherDemo = mode
            let first = render(view, time: 0.1)
            if mode == .clear {
                let scene = ClockSceneLayout(bounds: view.bounds.size, weather: true, contentFraction: ClockPreferences().scale)
                let layout = ClockContentLayout(size: scene.contentSize, weather: true)
                let origin = ClockScenePlacement.origin(bounds: view.bounds, scene: scene.contentSize, scale: scene.contentScale, elapsed: 0, shiftEnabled: false, backingScale: NSScreen.main?.backingScaleFactor ?? 1)
                for source in [layout.hour, layout.minute] {
                    let card = source.applying(CGAffineTransform(scaleX: scene.contentScale, y: scene.contentScale)).offsetBy(dx: origin.x, dy: origin.y)
                    let interior = card.insetBy(dx: 20, dy: 20)
                    var inkPixels = 0
                    for y in stride(from: Int(interior.minY), to: Int(interior.maxY), by: 2) where abs(CGFloat(y) - card.midY) > 5 {
                        for x in stride(from: Int(interior.minX), to: Int(interior.maxX), by: 2) {
                            let color = first.colorAt(x: x, y: 559 - y)!.usingColorSpace(.deviceRGB)!
                            if max(color.redComponent, color.greenComponent, color.blueComponent) < 0.4 { inkPixels += 1 }
                        }
                    }
                    precondition(inkPixels > 100, "Both cards must contain visible digits at Retina resolution")
                }
            }
            let second = render(view, time: 1.1)
            precondition(first.representation(using: .png, properties: [:]) != second.representation(using: .png, properties: [:]), "Weather must move: \(mode.title)")
            if mode == .storm {
                var movingBackgroundPixels = 0
                for y in stride(from: 0, to: 560, by: 4) {
                    for x in stride(from: 0, to: 50, by: 4) {
                        if first.colorAt(x: x, y: y) != second.colorAt(x: x, y: y) { movingBackgroundPixels += 1 }
                    }
                }
                precondition(movingBackgroundPixels > 10, "Weather must animate outside the centered component")
            }
            let repeatFrame = render(view, time: 0.1)
            precondition(first.representation(using: .png, properties: [:]) == repeatFrame.representation(using: .png, properties: [:]), "Frame export must be deterministic")
            // Weather animation is behind the cards: the interior of the hour
            // card must remain byte-for-byte stable while the weather moves.
            // Bitmap rows start at the top; NSView coordinates start at the bottom.
            for y in 160..<210 {
                for x in 180..<230 {
                    precondition(first.colorAt(x: x, y: y) == second.colorAt(x: x, y: y), "Weather covered the clock card")
                }
            }
        }
        view.weatherDemo = .storm
        let beforeResize = render(view, time: 0.1).representation(using: .png, properties: [:])
        for size in [NSSize(width: 320, height: 180), NSSize(width: 1920, height: 1080), NSSize(width: 1080, height: 1920), NSSize(width: 3440, height: 1440)] {
            view.setFrameSize(size)
            let frame = render(view, time: 0.1)
            for point in [NSPoint(x: 3, y: 3), NSPoint(x: size.width - 4, y: 3), NSPoint(x: 3, y: size.height - 4), NSPoint(x: size.width - 4, y: size.height - 4)] {
                let color = frame.colorAt(x: Int(point.x), y: Int(point.y))!.usingColorSpace(.deviceRGB)!
                precondition(max(color.redComponent, color.greenComponent, color.blueComponent) > 0.01, "Fullscreen background must cover every corner")
            }
        }
        view.setFrameSize(NSSize(width: 600, height: 560))
        precondition(render(view, time: 0.1).representation(using: .png, properties: [:]) == beforeResize, "Resizing must rebuild the clock cards without stale sizes")
        print("Fullscreen rendering checks passed: mini preview, landscape, portrait, ultrawide, resize round trip.")
        precondition(WeatherEffects.loadedAssetCount == 3, "Photographic weather assets must load")
        precondition(WeatherEffects.lightning(time: 0.175) > 0.9)
        precondition(WeatherEffects.lightning(time: 2) == 0)
        print("Animation checks passed: eight moving weather modes, deterministic frames, clear clock cards, bounded lightning pulse.")
    }
}
