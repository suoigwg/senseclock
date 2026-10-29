import AppKit

enum WeatherDemo: Int, CaseIterable {
    case clear = 1, partlyCloudy, cloudy, rain, snow, fog, storm, night
    var title: String {
        ["晴天 · 柔和日光", "多云 · 自然积云", "阴天 · 灰色层云", "下雨 · 风中细雨",
         "下雪 · 远近飘雪", "雾天 · 低空薄雾", "雷雨 · 云间闪电", "晴夜 · 静谧月光"][rawValue - 1]
    }
    var code: Int { [0, 2, 3, 61, 73, 45, 95, 0][rawValue - 1] }
    var isDay: Bool { self != .night }
    func snapshot(location: WeatherLocation, date: Date = Date()) -> WeatherSnapshot {
        let temperature = [26.0, 22, 19, 17, -3, 12, 18, 14][rawValue - 1]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let days = (0..<6).map { offset in
            WeatherDay(date: formatter.string(from: Calendar.current.date(byAdding: .day, value: offset, to: date)!),
                       high: temperature + 3, low: temperature - 4, code: code)
        }
        return WeatherSnapshot(location: location, fetchedAt: date, timezone: TimeZone.current.identifier,
                               currentTime: "", temperature: temperature, code: code, isDay: isDay, days: days)
    }
}

// Photorealistic sprites and restrained atmospheric motion. The images are
// bundled locally; rendering never needs an image server or a web view.
enum WeatherEffects {
    static var assetRootOverride: URL?
    private static var images: [String: NSImage] = [:]
    static var loadedAssetCount: Int { images.count }
    private static func asset(_ name: String) -> NSImage? {
        if let image = images[name] { return image }
        let url = assetRootOverride?.appendingPathComponent(name + ".png")
            ?? Bundle(for: SenseClockView.self).url(forResource: name, withExtension: "png", subdirectory: "Weather")
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        images[name] = image
        return image
    }
    private static func fraction(_ value: Double) -> CGFloat { CGFloat(value - floor(value)) }
    private static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
    }
    static func glow(color: NSColor, rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let rgb = color.usingColorSpace(.deviceRGB),
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                  colors: [rgb.cgColor, rgb.withAlphaComponent(rgb.alphaComponent * 0.25).cgColor,
                           rgb.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 0.45, 1]) else { return }
        context.saveGState()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.translateBy(x: rect.midX, y: rect.midY)
        context.scaleBy(x: rect.width / 2, y: rect.height / 2)
        context.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
        context.restoreGState()
    }
    private static func line(_ points: [NSPoint], width: CGFloat, color: NSColor) {
        guard let first = points.first else { return }
        let path = NSBezierPath(); path.move(to: first)
        points.dropFirst().forEach { path.line(to: $0) }
        path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round
        color.setStroke(); path.stroke()
    }
    private static func random(_ seed: Int, _ index: Int) -> CGFloat {
        fraction(sin(Double(seed) * 12.9898 + Double(index) * 78.233) * 43758.5453)
    }
    private static func strikeID(_ time: Double) -> Int { Int(floor(max(0, time) / 6.4)) }
    static func lightning(time: Double) -> CGFloat {
        let event = strikeID(time)
        let phase = time - Double(event) * 6.4
        let onset = event == 0 ? 0.175 : 0.7 + Double(random(event, 19)) * 2.8
        // Multiple return strokes use one channel, with an uneven, very brief
        // primary discharge and a dimmer afterglow. Each event starts elsewhere.
        let pulses: [(Double, Double, Double)] = [(onset, 0.085, 1), (onset + 0.14, 0.04, 0.68), (onset + 0.32, 0.09, 0.22)]
        let intensity: Double = pulses.map { center, width, strength -> Double in
            let distance = abs(phase - center) / width
            return distance < 1 ? pow(1 - distance, 1.7) * strength : 0
        }.max() ?? 0
        return CGFloat(intensity)
    }

    private static var boltCache: [Int: [[NSPoint]]] = [:]
    private static func channels(event: Int) -> [[NSPoint]] {
        if let paths = boltCache[event] { return paths }
        func channel(_ start: NSPoint, _ end: NSPoint, _ seed: Int, _ levels: Int) -> [NSPoint] {
            var points = [start, end]
            for level in 0..<levels {
                var next: [NSPoint] = [points[0]]
                for index in 0..<(points.count - 1) {
                    let a = points[index], b = points[index + 1]
                    let dx = b.x - a.x, dy = b.y - a.y
                    let length = hypot(dx, dy)
                    let displacement = (random(seed + level * 47, index) - 0.5) * length * 0.56
                    let midpoint = NSPoint(x: (a.x + b.x) / 2 - dy / max(length, 0.001) * displacement,
                                           y: (a.y + b.y) / 2 + dx / max(length, 0.001) * displacement)
                    next.append(midpoint); next.append(b)
                }
                points = next
            }
            return points
        }
        let end = NSPoint(x: 29 + random(event + 31, 4) * 42, y: -48)
        let trunk = channel(NSPoint(x: 54, y: 42), end, event + 37, 6)
        var paths = [trunk]
        for branch in 0..<5 {
            let index = 13 + branch * 8
            let start = trunk[index]
            let direction: CGFloat = branch % 2 == 0 ? -1 : 1
            let endpoint = NSPoint(x: start.x + direction * (10 + random(event, branch + 4) * 18),
                                   y: start.y - 12 - random(event + 1, branch) * 23)
            paths.append(channel(start, endpoint, event + branch * 19 + 41, 4))
        }
        boltCache = [event: paths]
        return paths
    }

    private static func cloud(x: CGFloat, y: CGFloat, scale: CGFloat, dark: Bool, rim: CGFloat = 0, alpha: CGFloat = 1) {
        let context = NSGraphicsContext.current!.cgContext
        context.saveGState(); context.translateBy(x: x, y: y); context.scaleBy(x: scale, y: scale)
        if let image = asset(dark ? "cloud-storm" : "cloud-day") {
            let height = 124 * image.size.height / image.size.width
            let rect = NSRect(x: -12, y: 45 - height / 2, width: 124, height: height)
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
            if rim > 0.01 { image.draw(in: rect, from: .zero, operation: .plusLighter, fraction: min(0.36, rim * 0.36) * alpha) }
        } else {
            // A quiet fallback for incomplete local builds. Release packaging
            // and the integration check require the photographic assets.
            glow(color: NSColor(white: dark ? 0.45 : 0.85, alpha: alpha), rect: NSRect(x: 0, y: 18, width: 100, height: 55))
        }
        context.restoreGState()
    }

    private static func sun(time: Double, small: Bool) {
        let haze = CGFloat(0.24 + 0.012 * sin(time * 0.23))
        glow(color: color(1, 0.88, 0.65, haze), rect: NSRect(x: -8, y: 0, width: 124, height: 124))
        glow(color: color(1, 0.95, 0.8, 0.3), rect: NSRect(x: 17, y: 25, width: 74, height: 74))
        let disk = NSBezierPath(ovalIn: NSRect(x: 34, y: 42, width: 40, height: 40))
        NSGradient(colors: [color(1, 0.88, 0.61), color(1, 0.98, 0.89), .white])!.draw(in: disk, angle: 80)
        // A thin veil passing through the sunlight, without spokes or sparkles.
        let shift = CGFloat(sin(time * 0.2) * 16)
        glow(color: NSColor(white: 1, alpha: 0.065), rect: NSRect(x: -10 + shift, y: 35, width: 130, height: 38))
    }

    private static func moon(time: Double, small: Bool) {
        glow(color: color(0.83, 0.87, 0.94, 0.12 + CGFloat(sin(time * 0.15)) * 0.008),
             rect: NSRect(x: -3, y: 6, width: 114, height: 114))
        if let image = asset("moon") {
            let height = 91 * image.size.height / image.size.width
            image.draw(in: NSRect(x: 9, y: 61 - height / 2, width: 91, height: height),
                       from: .zero, operation: .sourceOver, fraction: 0.94)
        } else {
            NSColor(white: 0.82, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 30, y: 36, width: 52, height: 52)).fill()
        }
        if !small {
            for index in 0..<5 {
                let x = fraction(Double(index) * 0.618 + 0.09) * 98
                let y = 34 + fraction(Double(index) * 0.37) * 60
                NSColor(white: 0.9, alpha: 0.18 + CGFloat(sin(time * 0.45 + Double(index))) * 0.06).setFill()
                NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 0.7, height: 0.7)).fill()
            }
        }
    }

    private static func rainStreak(head: NSPoint, length: CGFloat, drift: CGFloat,
                                   width: CGFloat, alpha: CGFloat) {
        // Motion blur falls off along the streak, with the denser droplet at
        // the leading edge. No neon outline or identical capsule shapes.
        for segment in 0..<5 {
            let t = CGFloat(segment) / 5
            let next = CGFloat(segment + 1) / 5
            let a = NSPoint(x: head.x + drift * t, y: head.y + length * t)
            let b = NSPoint(x: head.x + drift * next, y: head.y + length * next)
            line([a, b], width: width * (1 - t * 0.45),
                 color: color(0.79, 0.81, 0.83, alpha * pow(1 - t, 1.5)))
        }
        if width > 0.85 {
            NSColor(white: 0.88, alpha: alpha * 0.65).setFill()
            NSBezierPath(ovalIn: NSRect(x: head.x - width / 2, y: head.y - width,
                                        width: width, height: width * 1.5)).fill()
        }
    }
    private static func drops(time: Double, storm: Bool, small: Bool) {
        let count = small ? 5 : (storm ? 28 : 20)
        for index in 0..<count {
            let depth = random(43, index)
            let speed = (storm ? 1.7 : 1.15) + Double(depth) * 0.75
            let f = fraction(time * speed + Double(random(71, index)))
            let wind = CGFloat(3.5 + sin(time * 0.21) * 1.6)
            let x = 15 + random(91, index) * 74 - f * wind
            let y = 27 - f * 61
            rainStreak(head: NSPoint(x: x, y: y), length: 3 + depth * 7,
                       drift: wind * 0.32, width: small ? 0.65 : 0.45 + depth * 0.55,
                       alpha: (0.28 + depth * 0.4) * (1 - f * 0.75))
        }
    }

    private static func snow(time: Double, small: Bool) {
        for index in 0..<(small ? 4 : 10) {
            let f = fraction(time * (0.14 + Double(index % 3) * 0.07) + Double(index) * 0.37)
            let x = 15 + CGFloat(index * 13 % 78) + CGFloat(sin(time * 0.4 + Double(index))) * 6
            let y = 25 - f * 50
            let size: CGFloat = index % 3 == 0 ? 1.8 : 1.05
            NSColor(white: 0.97, alpha: 0.7 - f * 0.42).setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: size, height: size)).fill()
        }
    }

    private static func bolt(time: Double) {
        let intensity = lightning(time: time)
        guard intensity > 0.025 else { return }
        glow(color: NSColor(white: 0.92, alpha: intensity * 0.25),
             rect: NSRect(x: 0, y: -64, width: 110, height: 115))
        for (index, branch) in channels(event: strikeID(time)).enumerated() {
            let width: CGFloat = index == 0 ? 0.85 : 0.32
            let brightness = intensity * (index == 0 ? 1 : 0.62)
            line(branch, width: width * 6, color: color(0.7, 0.76, 0.89, brightness * 0.07))
            line(branch, width: width * 2.5, color: color(0.77, 0.83, 0.95, brightness * 0.25))
            line(branch, width: width, color: NSColor(white: 1, alpha: brightness))
        }
    }

    static func drawWideLightning(time: Double, canvas: NSRect) {
        let intensity = lightning(time: time)
        guard intensity > 0.025, canvas.width > 0, canvas.height > 0 else { return }
        let context = NSGraphicsContext.current!.cgContext
        context.saveGState()
        context.clip(to: canvas)
        // This is a scene-wide discharge. The clock cards are drawn afterward
        // and remain an opaque foreground, so the digits stay readable.
        glow(color: NSColor(white: 0.94, alpha: intensity * 0.18),
             rect: canvas.insetBy(dx: -canvas.width * 0.1, dy: -canvas.height * 0.1))
        let event = strikeID(time)
        let origin = NSPoint(x: canvas.minX + canvas.width * (0.44 + random(event + 5, 17) * 0.2),
                             y: canvas.maxY - canvas.height * 0.025)
        let sx = canvas.width / 94
        let sy = canvas.height / 94
        let coreWidth = max(0.55, canvas.width / 1000)
        for (index, branch) in channels(event: event).enumerated() {
            let points = branch.map { NSPoint(x: origin.x + ($0.x - 54) * sx,
                                             y: origin.y + ($0.y - 42) * sy) }
            let path = NSBezierPath(); path.move(to: points[0])
            points.dropFirst().forEach { path.line(to: $0) }
            path.lineWidth = coreWidth * (index == 0 ? 1.1 : 0.65)
            path.lineJoinStyle = .miter; path.lineCapStyle = .butt
            let brightness = intensity * (index == 0 ? 1 : 0.7)
            context.setShadow(offset: .zero, blur: coreWidth * 4,
                              color: NSColor(white: 0.94, alpha: brightness * 0.42).cgColor)
            NSColor(white: 1, alpha: brightness).setStroke(); path.stroke()
        }
        context.restoreGState()
    }

    static func drawIcon(kind: WeatherKind, isDay: Bool, time: Double, center: NSPoint, size: CGFloat) {
        guard kind != .unknown else { return }
        let context = NSGraphicsContext.current!.cgContext
        context.saveGState()
        context.translateBy(x: center.x - size / 2, y: center.y - size / 2)
        context.scaleBy(x: size / 100, y: size / 100)
        let small = size < 80
        let t = time + Double(center.x) * 0.013
        if kind == .clear {
            isDay ? sun(time: t, small: small) : moon(time: t, small: small)
            context.restoreGState(); return
        }
        if kind == .partlyCloudy {
            context.saveGState(); context.translateBy(x: 17, y: 18); context.scaleBy(x: 0.78, y: 0.78)
            isDay ? sun(time: t, small: small) : moon(time: t, small: small)
            context.restoreGState()
        }
        if kind == .rain || kind == .storm { drops(time: t, storm: kind == .storm, small: small) }
        if kind == .snow { snow(time: t, small: small) }
        if kind == .storm && small { bolt(time: time) }
        let dark = kind == .rain || kind == .storm || kind == .cloudy
        let lift = CGFloat(sin(t * 0.19) * 0.6)
        let flash = kind == .storm ? lightning(time: time) : 0
        if !small || kind == .cloudy {
            cloud(x: 19 + CGFloat(sin(t * 0.16 + 1.7) * 6), y: 17 + lift * 0.5,
                  scale: 0.8, dark: dark, rim: flash * 0.7, alpha: 0.62)
        }
        cloud(x: CGFloat(sin(t * 0.22) * 3), y: lift - 6, scale: 1, dark: dark, rim: flash)
        if kind == .fog {
            for index in 0..<4 {
                let offset = CGFloat(sin(t * 0.16 + Double(index)) * 12)
                glow(color: NSColor(white: 0.87, alpha: 0.11),
                     rect: NSRect(x: -15 + offset, y: CGFloat(4 + index * 9), width: 132, height: 36))
            }
        }
        context.restoreGState()
    }

    static func draw(kind: WeatherKind, isDay: Bool, time: Double, panel: NSRect) {
        guard kind != .unknown else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: panel).addClip()
        NSGraphicsContext.current!.cgContext.translateBy(x: panel.minX, y: panel.minY)
        let area = panel.size
        NSGraphicsContext.current!.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
        let tint: NSColor
        switch kind {
        case .clear, .partlyCloudy: tint = isDay ? color(0.9, 0.83, 0.68, 0.13) : color(0.34, 0.4, 0.5, 0.2)
        case .rain, .storm: tint = color(0.38, 0.43, 0.49, 0.22)
        case .snow: tint = color(0.61, 0.65, 0.69, 0.2)
        case .fog: tint = color(0.63, 0.65, 0.67, 0.2)
        default: tint = NSColor(white: 0.4, alpha: 0.17)
        }
        glow(color: tint, rect: NSRect(x: -100, y: -90, width: area.width + 200, height: area.height + 90))
        if (kind == .clear || kind == .partlyCloudy) && isDay {
            glow(color: color(1, 0.93, 0.8, 0.17 + CGFloat(sin(time * 0.17)) * 0.009),
                 rect: NSRect(x: area.width * 0.3, y: area.height * 0.34, width: 550, height: 550))
        }
        if (kind == .clear || kind == .partlyCloudy) && !isDay { nightSky(time: time, area: area) }
        if kind == .cloudy || kind == .partlyCloudy || kind == .storm {
            for index in 0..<3 {
                let x = fraction(Double(index) * 0.36 + time * 0.004) * (area.width + 500) - 250
                cloud(x: x, y: area.height * (0.27 + CGFloat(index) * 0.18), scale: 3.2, dark: kind != .partlyCloudy,
                      rim: kind == .storm ? lightning(time: time) * 0.2 : 0, alpha: kind == .partlyCloudy ? 0.045 : 0.085)
            }
        }
        if kind == .rain || kind == .storm { precipitation(snow: false, storm: kind == .storm, time: time, area: area) }
        if kind == .snow { precipitation(snow: true, storm: false, time: time, area: area) }
        if kind == .fog {
            for index in 0..<12 {
                let x = fraction(Double(index) * 0.41 + time * 0.004) * (area.width + 440) - 220
                let y = area.height * (0.035 + CGFloat(index) * 0.043) + CGFloat(sin(time * 0.12 + Double(index)) * 10)
                glow(color: NSColor(white: 0.78, alpha: 0.08), rect: NSRect(x: x, y: y, width: 440, height: 140))
            }
        }
        if kind == .storm {
            glow(color: NSColor(white: 0.82, alpha: lightning(time: time) * 0.46),
                 rect: NSRect(x: area.width * 0.1, y: area.height * 0.16, width: area.width * 0.83, height: area.height * 0.79))
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func nightSky(time: Double, area: NSSize) {
        for index in 0..<40 {
            let x = fraction(Double(index) * 0.618 + 0.13) * (area.width - 30) + 15
            let y = fraction(Double(index) * 0.391 + 0.32) * (area.height - 50) + 25
            let alpha = CGFloat(0.1 + 0.15 * (sin(time * 0.37 + Double(index) * 1.9) + 1) / 2)
            NSColor(white: 0.86, alpha: alpha).setFill()
            let size: CGFloat = index % 9 == 0 ? 1.3 : 0.7
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: size, height: size)).fill()
        }
    }

    private static func glassDrop(at p: NSPoint, radius: CGFloat, alpha: CGFloat) {
        let rect = NSRect(x: p.x - radius, y: p.y - radius * 1.35, width: radius * 2, height: radius * 2.7)
        let lens = NSBezierPath(ovalIn: rect)
        NSGradient(colors: [NSColor(white: 0.1, alpha: alpha * 0.16),
                            NSColor(white: 0.8, alpha: alpha * 0.018),
                            NSColor(white: 0.9, alpha: alpha * 0.07)])!.draw(in: lens, angle: 55)
        NSColor(white: 0.86, alpha: alpha * 0.13).setStroke(); lens.lineWidth = 0.5; lens.stroke()
        let highlight = NSBezierPath()
        highlight.move(to: NSPoint(x: p.x - radius * 0.54, y: p.y + radius * 0.42))
        highlight.curve(to: NSPoint(x: p.x + radius * 0.15, y: p.y + radius * 0.95),
                        controlPoint1: NSPoint(x: p.x - radius * 0.48, y: p.y + radius * 0.91),
                        controlPoint2: NSPoint(x: p.x - radius * 0.12, y: p.y + radius * 1.05))
        NSColor(white: 1, alpha: alpha * 0.34).setStroke(); highlight.lineWidth = 0.7; highlight.stroke()
    }
    private static func precipitation(snow: Bool, storm: Bool, time: Double, area: NSSize) {
        let count = min(480, Int(CGFloat(snow ? 92 : (storm ? 205 : 142)) * area.width * area.height / (600 * 560)))
        let wind = 0.17 + sin(time * 0.18) * 0.055
        for index in 0..<count {
            let depth = random(29, index)
            let speed = snow ? 0.035 + Double(depth) * 0.075 : 0.65 + Double(depth) * 1.15
            let progress = fraction(time * speed + Double(random(113, index)))
            let y = (1 - progress) * (area.height + 40) - 20
            let travel = progress * (area.height + 40)
            let travelWidth = area.width + 120 + (area.height + 40) * CGFloat(wind)
            var x = random(59, index) * travelWidth - 60 - travel * CGFloat(wind)
            if snow { x += CGFloat(sin(time * 0.39 + Double(index)) * 16) }
            if snow {
                let size = 0.6 + depth * 2.8
                NSColor(white: 0.97, alpha: 0.1 + depth * 0.48).setFill()
                NSBezierPath(ovalIn: NSRect(x: x, y: y, width: size, height: size * (0.9 + depth * 0.2))).fill()
                if depth > 0.85 { glow(color: NSColor(white: 0.96, alpha: 0.1), rect: NSRect(x: x - 2, y: y - 2, width: size + 4, height: size + 4)) }
            } else {
                let length = 6 + depth * depth * 27
                rainStreak(head: NSPoint(x: x, y: y), length: length, drift: length * CGFloat(wind),
                           width: 0.4 + depth * 0.95, alpha: 0.11 + depth * 0.43)
            }
        }
        if !snow {
            // Slow, transparent water beads on the virtual glass. They collect
            // and accelerate downward, independently of the distant rainfall.
            for index in 0..<min(40, max(16, Int(area.width / 38))) {
                let duration = 14 + Double(random(151, index)) * 22
                let progress = fraction(time / duration + Double(random(89, index)))
                let x = 18 + random(211, index) * (area.width - 36) + CGFloat(sin(Double(progress) * 9 + Double(index))) * 1.8
                let y = area.height - 5 - pow(progress, 2.4) * (area.height + 40)
                let radius = 1.8 + random(137, index) * 4.2
                let fade = min(1, progress * 8) * min(1, (1 - progress) * 6)
                line([NSPoint(x: x, y: y + radius), NSPoint(x: x + 1, y: y + radius + progress * 35)],
                     width: 0.6, color: NSColor(white: 0.9, alpha: fade * 0.025))
                glassDrop(at: NSPoint(x: x, y: y), radius: radius, alpha: fade)
            }
        }
    }
}
