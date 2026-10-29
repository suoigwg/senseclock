import Foundation
import CoreGraphics

@main
struct ClockModelTests {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        func reading(_ hour: Int, _ minute: Int, _ use24: Bool) -> ClockReading {
            ClockReading(date: calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: hour, minute: minute))!, use24Hour: use24, calendar: calendar)
        }
        precondition(reading(0, 0, true).hour == "00")
        precondition(reading(0, 0, false).hour == "12")
        precondition(reading(0, 0, false).period == "AM")
        precondition(reading(12, 47, false).hour == "12")
        precondition(reading(12, 47, false).period == "PM")
        precondition(reading(23, 59, false).hour == "11")
        precondition(reading(9, 5, true).minute == "05")
        let before = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 23, minute: 59, second: 59))!
        let after = ClockReading(date: before.addingTimeInterval(1), use24Hour: true, calendar: calendar)
        precondition(after.hour == "00" && after.minute == "00")
        // Daylight saving rollback must follow the wall clock, not elapsed minutes.
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let iso = ISO8601DateFormatter()
        let dstBefore = ClockReading(date: iso.date(from: "2026-11-01T08:59:00Z")!, use24Hour: true, calendar: calendar)
        let dstAfter = ClockReading(date: iso.date(from: "2026-11-01T09:00:00Z")!, use24Hour: true, calendar: calendar)
        precondition(dstBefore.hour == "01" && dstBefore.minute == "59")
        precondition(dstAfter.hour == "01" && dstAfter.minute == "00")
        for backing: CGFloat in [1, 2] {
            let bounds = CGRect(x: 0, y: 0, width: 1001, height: 841)
            let scene = CGSize(width: 600, height: 560)
            func origin(_ time: Double, _ enabled: Bool = true) -> CGPoint {
                ClockScenePlacement.origin(bounds: bounds, scene: scene, scale: 1.173,
                    elapsed: time, shiftEnabled: enabled, backingScale: backing)
            }
            let first = origin(0)
            for frame in 0..<9000 {
                precondition(origin(Double(frame) / 30) == first, "Text anchor moved between frames")
            }
            precondition(origin(300) != first, "Optional anti-burn-in shift should occur once after five minutes")
            precondition(origin(300) == origin(599.99))
            precondition(origin(10_000, false) == origin(0, false), "Preview text must stay fixed")
            for time in [0.0, 300, 600, 900] {
                let point = origin(time)
                precondition((point.x * backing).rounded() == point.x * backing)
                precondition((point.y * backing).rounded() == point.y * backing)
            }
        }
        for aspect: CGFloat in [9.0 / 16, 1, 4.0 / 3, 16.0 / 10, 16.0 / 9, 21.0 / 9] {
            let width = max(600, 560 * aspect)
            let size = CGSize(width: width, height: width / aspect)
            for weather in [true, false] {
                let layout = ClockContentLayout(size: size, weather: weather)
                let bounds = CGRect(origin: .zero, size: size)
                precondition(bounds.contains(layout.hour) && bounds.contains(layout.minute))
                precondition(layout.hour.maxX < layout.minute.minX)
                precondition(layout.hour.size == layout.minute.size)
                precondition(layout.hour.minX / width < 0.06 && (width - layout.minute.maxX) / width < 0.06, "Clock must span the screen width")
                precondition(layout.weatherHeight > 0)
            }
        }
        for bounds in [CGSize(width: 320, height: 180), CGSize(width: 1920, height: 1080), CGSize(width: 1080, height: 1920), CGSize(width: 3440, height: 1440)] {
            for weather in [true, false] {
                let reference = ClockSceneLayout(bounds: bounds, weather: weather, contentFraction: 0.78)
                for fraction: CGFloat in [0.4, 0.78, 1] {
                    let scene = ClockSceneLayout(bounds: bounds, weather: weather, contentFraction: fraction)
                    precondition(abs(scene.backgroundSize.width * scene.backgroundScale - bounds.width) < 0.001)
                    precondition(abs(scene.backgroundSize.height * scene.backgroundScale - bounds.height) < 0.001)
                    precondition(scene.backgroundSize == reference.backgroundSize && scene.backgroundScale == reference.backgroundScale, "Component size must not change the backdrop")
                    precondition(scene.contentSize.width * scene.contentScale <= bounds.width + 0.001)
                    precondition(scene.contentSize.height * scene.contentScale <= bounds.height + 0.001)
                    precondition(abs(scene.contentScale / reference.contentScale - fraction / 0.78) < 0.001)
                }
            }
        }
        print("Independent layer checks passed: full-screen backdrop, adjustable centered content, all screen ratios.")
        print("Responsive layout checks passed: portrait, square, 4:3, 16:10, 16:9, ultrawide.")
        print("Clock checks passed: 24h, 12h, noon, midnight, year rollover, DST rollback.")
        print("Text placement checks passed: stable frames, 1x/2x pixel alignment, five-minute optional shift, fixed preview.")
    }
}
