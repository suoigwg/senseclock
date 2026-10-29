import Foundation
import CoreGraphics

struct ClockSceneLayout {
    let backgroundSize: CGSize
    let backgroundScale: CGFloat
    let contentSize: CGSize
    let contentScale: CGFloat

    init(bounds: CGSize, weather: Bool, contentFraction: CGFloat) {
        let aspect = bounds.width / bounds.height
        let width = max(600, 560 * aspect)
        backgroundSize = CGSize(width: width, height: width / aspect)
        backgroundScale = min(bounds.width / backgroundSize.width, bounds.height / backgroundSize.height)
        contentSize = CGSize(width: 600, height: weather ? 560 : 360)
        contentScale = min(bounds.width / contentSize.width, bounds.height / contentSize.height) * contentFraction
    }
}

struct ClockContentLayout {
    let size: CGSize
    let margin: CGFloat
    let hour: CGRect
    let minute: CGRect
    let weatherHeight: CGFloat
    init(size: CGSize, weather: Bool) {
        self.size = size
        margin = max(18, min(size.width, size.height) * 0.048)
        let gap = max(18, size.width * 0.028)
        let width = (size.width - margin * 2 - gap) / 2
        let height = min(size.height * (weather ? 0.53 : 0.78), width * 1.05)
        let y = size.height - margin - height
        hour = CGRect(x: margin, y: y, width: width, height: height)
        minute = CGRect(x: margin + width + gap, y: y, width: width, height: height)
        weatherHeight = y
    }
}

enum ClockScenePlacement {
    static func origin(bounds: CGRect, scene: CGSize, scale: CGFloat, elapsed: TimeInterval,
                       shiftEnabled: Bool, backingScale: CGFloat) -> CGPoint {
        let pixelsPerPoint = max(1, backingScale)
        let positions: [(CGFloat, CGFloat)] = [(0, 0), (8, 0), (8, 6), (0, 6), (-8, 6), (-8, 0), (-8, -6), (0, -6), (8, -6)]
        let index = shiftEnabled ? Int(max(0, elapsed) / 300) % positions.count : 0
        let offset = positions[index]
        let x = bounds.midX - scene.width * scale / 2 + offset.0 / pixelsPerPoint
        let y = bounds.midY - scene.height * scale / 2 + offset.1 / pixelsPerPoint
        return CGPoint(x: (x * pixelsPerPoint).rounded() / pixelsPerPoint,
                       y: (y * pixelsPerPoint).rounded() / pixelsPerPoint)
    }
}

struct ClockReading: Equatable {
    let hour: String
    let minute: String
    let period: String

    init(date: Date, use24Hour: Bool, calendar: Calendar = .current) {
        let hour = calendar.component(.hour, from: date)
        self.hour = String(format: "%02d", use24Hour ? hour : (hour % 12 == 0 ? 12 : hour % 12))
        minute = String(format: "%02d", calendar.component(.minute, from: date))
        period = use24Hour ? "" : (hour < 12 ? "AM" : "PM")
    }
}

struct ClockPreferences {
    static let domain = "com.senseclock.screensaver"
    private let defaults: UserDefaults
    init() {
        defaults = UserDefaults(suiteName: Self.domain) ?? .standard
        defaults.register(defaults: ["use24Hour": true, "showWeather": true, "drift": true, "scale": 0.78, "weatherAnimations": true])
    }
    var weatherLocation: WeatherLocation {
        get {
            guard let data = defaults.data(forKey: "weatherLocation"),
                  let location = try? JSONDecoder().decode(WeatherLocation.self, from: data) else { return .cupertino }
            return location
        }
        nonmutating set { defaults.set(try? JSONEncoder().encode(newValue), forKey: "weatherLocation") }
    }
    var weatherAnimations: Bool {
        get { defaults.bool(forKey: "weatherAnimations") }
        nonmutating set { defaults.set(newValue, forKey: "weatherAnimations") }
    }
    var fahrenheit: Bool {
        get { defaults.bool(forKey: "fahrenheit") }
        nonmutating set { defaults.set(newValue, forKey: "fahrenheit") }
    }
    var use24Hour: Bool {
        get { defaults.bool(forKey: "use24Hour") }
        nonmutating set { defaults.set(newValue, forKey: "use24Hour") }
    }
    var showWeather: Bool {
        get { defaults.bool(forKey: "showWeather") }
        nonmutating set { defaults.set(newValue, forKey: "showWeather") }
    }
    var drift: Bool {
        get { defaults.bool(forKey: "drift") }
        nonmutating set { defaults.set(newValue, forKey: "drift") }
    }
    var scale: Double {
        get { min(1, max(0.4, defaults.double(forKey: "scale"))) }
        nonmutating set { defaults.set(newValue, forKey: "scale") }
    }
}
