import Foundation

final class StubWeatherProtocol: URLProtocol {
    static var status = 200
    static var body = Data()
    static var count = 0
    static var delay: TimeInterval = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.count += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        let body = Self.body
        if Self.delay > 0 { Thread.sleep(forTimeInterval: Self.delay) }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
struct WeatherTests {
    static let fixture = """
    {"timezone":"Asia/Shanghai","current":{"time":"2026-11-02T00:00","temperature_2m":12.5,"weather_code":2,"is_day":0},"daily":{"time":["2026-11-02","2026-11-03","2026-11-04"],"temperature_2m_max":[18.1,19.5,null],"temperature_2m_min":[8.0,9.0,null],"weather_code":[2,61,null]}}
    """.data(using: .utf8)!

    static func wait(_ condition: () -> Bool, timeout: TimeInterval = 8) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        precondition(condition(), "Asynchronous operation timed out")
    }

    static func main() throws {
        let response = try JSONDecoder().decode(WeatherResponse.self, from: fixture)
        let snapshot = try response.snapshot(location: .cupertino)
        let now = ISO8601DateFormatter().date(from: "2026-11-01T16:01:00Z")!
        precondition(snapshot.today(at: now)?.date == "2026-11-02", "Use the city's date, not the Mac's date")
        precondition(snapshot.upcoming(at: now).first?.date == "2026-11-03")
        precondition(snapshot.upcoming(at: now).last?.high == nil)
        precondition(WeatherSnapshot.temperatureLabel(0, fahrenheit: true) == "32°")
        precondition(WeatherSnapshot.temperatureLabel(-8.5, fahrenheit: false) == "-9°")
        precondition(WeatherSnapshot.temperatureLabel(nil, fahrenheit: false) == "—")
        precondition(WeatherKind.from(code: nil) == .unknown)
        precondition(WeatherKind.from(code: 75) == .snow && WeatherKind.from(code: 95) == .storm)
        let malformed = String(data: fixture, encoding: .utf8)!.replacingOccurrences(of: "[18.1,19.5,null]", with: "[]").data(using: .utf8)!
        do {
            _ = try JSONDecoder().decode(WeatherResponse.self, from: malformed).snapshot(location: .cupertino)
            preconditionFailure("Mismatched forecast arrays should be rejected")
        } catch {}
        let suite = "com.senseclock.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubWeatherProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        StubWeatherProtocol.body = fixture
        let store = WeatherStore(defaults: defaults, session: session)
        store.refresh(location: .cupertino)
        store.refresh(location: .cupertino)
        wait { !store.isLoading }
        precondition(StubWeatherProtocol.count == 1 && store.snapshot?.temperature == 12.5)
        store.refresh(location: .cupertino)
        precondition(!store.isLoading && StubWeatherProtocol.count == 1, "Throttle fresh data")
        let restored = WeatherStore(defaults: defaults, session: session)
        restored.refresh(location: .cupertino)
        precondition(!restored.isLoading && restored.snapshot?.temperature == 12.5, "Restore cache without a request")
        StubWeatherProtocol.status = 503
        restored.refresh(location: .cupertino, force: true)
        wait { !restored.isLoading }
        precondition(restored.failed && restored.snapshot?.temperature == 12.5)
        precondition(restored.footer(fahrenheit: false).contains(L10n.text("Cached")))
        let count = StubWeatherProtocol.count
        restored.refresh(location: .cupertino)
        precondition(StubWeatherProtocol.count == count && !restored.isLoading, "Back off after failures")
        let other = WeatherLocation(id: 1, name: "Other", latitude: 20, longitude: 30, country: nil, admin1: nil)
        restored.refresh(location: other)
        precondition(restored.snapshot == nil, "Never show another city's cached weather")
        wait { !restored.isLoading }
        precondition(restored.failed && restored.snapshot == nil)
        precondition(!restored.footer(fahrenheit: false).contains(L10n.text("Updated")))
        // A late response from the previous city must not overwrite the new one.
        StubWeatherProtocol.status = 200
        StubWeatherProtocol.delay = 0.1
        restored.refresh(location: .cupertino, force: true)
        restored.refresh(location: other, force: true)
        wait { !restored.isLoading }
        precondition(restored.snapshot?.location == other)
        print("Weather checks passed: decoding, nulls, malformed arrays, timezone, units, caching, throttling, offline fallback, city isolation, late responses.")
        if CommandLine.arguments.contains("--live") {
            var cities: [WeatherLocation] = []
            var searchDone = false
            WeatherAPI.search("Cupertino") { result in
                switch result {
                case .success(let found): cities = found
                case .failure(let error): fputs("Live city search failed: \(error)\n", stderr)
                }
                searchDone = true
            }
            wait({ searchDone }, timeout: 20)
            precondition(!cities.isEmpty, "Live geocoding must return a city")
            let live = WeatherStore(defaults: defaults)
            live.refresh(location: cities[0], force: true)
            wait({ !live.isLoading }, timeout: 20)
            precondition(!live.failed && live.snapshot != nil, "Live forecast must decode")
            precondition(live.snapshot!.days.count == 6)
            print("Live APIs passed: \(cities[0].title), \(live.snapshot!.temperature) °C, \(live.snapshot!.days.count) forecast days.")
        }
    }
}
