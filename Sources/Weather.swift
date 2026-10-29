import Foundation

struct WeatherLocation: Codable, Equatable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let admin1: String?
    var title: String { [name, admin1, country].compactMap { $0 }.joined(separator: ", ") }
    static let cupertino = WeatherLocation(id: 5341145, name: "Cupertino", latitude: 37.323, longitude: -122.0322, country: "United States", admin1: "California")
}

enum WeatherKind: Int {
    case partlyCloudy = 0, cloudy, rain, clear, snow, fog, storm, unknown
    static func from(code: Int?) -> WeatherKind {
        guard let code else { return .unknown }
        switch code {
        case 0: return .clear
        case 1, 2: return .partlyCloudy
        case 3: return .cloudy
        case 45, 48: return .fog
        case 51...67, 80...82: return .rain
        case 71...77, 85, 86: return .snow
        case 95...99: return .storm
        default: return .unknown
        }
    }
    var title: String {
        switch self {
        case .partlyCloudy: return "多云"
        case .cloudy: return "阴天"
        case .rain: return "有雨"
        case .clear: return "晴朗"
        case .snow: return "降雪"
        case .fog: return "有雾"
        case .storm: return "雷暴"
        case .unknown: return "天气未知"
        }
    }
}

struct WeatherDay: Codable {
    let date: String
    let high: Double?
    let low: Double?
    let code: Int?
}

struct WeatherSnapshot: Codable {
    let location: WeatherLocation
    let fetchedAt: Date
    let timezone: String
    let currentTime: String
    let temperature: Double
    let code: Int?
    let isDay: Bool
    let days: [WeatherDay]

    func dateKey(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timezone) ?? TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func today(at date: Date) -> WeatherDay? { days.first { $0.date == dateKey(at: date) } }
    func upcoming(at date: Date) -> [WeatherDay] { Array(days.filter { $0.date > dateKey(at: date) }.prefix(5)) }

    static func temperatureLabel(_ value: Double?, fahrenheit: Bool) -> String {
        guard let value, value.isFinite, abs(value) < 1000 else { return "—" }
        return "\(Int((fahrenheit ? value * 1.8 + 32 : value).rounded()))°"
    }

    static func weekday(_ date: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let day = formatter.date(from: date) else { return "—" }
        formatter.dateFormat = "EEE"
        return formatter.string(from: day)
    }
}

struct WeatherResponse: Decodable {
    struct Current: Decodable {
        let time: String
        let temperature_2m: Double?
        let weather_code: Int?
        let is_day: Int?
    }
    struct Daily: Decodable {
        let time: [String]
        let temperature_2m_max: [Double?]
        let temperature_2m_min: [Double?]
        let weather_code: [Int?]
    }
    let timezone: String
    let current: Current
    let daily: Daily

    func snapshot(location: WeatherLocation, now: Date = Date()) throws -> WeatherSnapshot {
        guard let temperature = current.temperature_2m, temperature.isFinite,
              abs(temperature) < 150, TimeZone(identifier: timezone) != nil,
              daily.time.count == daily.temperature_2m_max.count,
              daily.time.count == daily.temperature_2m_min.count,
              daily.time.count == daily.weather_code.count else { throw WeatherError.invalidData }
        let days = daily.time.indices.map {
            WeatherDay(date: daily.time[$0], high: daily.temperature_2m_max[$0], low: daily.temperature_2m_min[$0], code: daily.weather_code[$0])
        }
        return WeatherSnapshot(location: location, fetchedAt: now, timezone: timezone,
                               currentTime: current.time, temperature: temperature, code: current.weather_code,
                               isDay: current.is_day != 0, days: days)
    }
}

enum WeatherError: LocalizedError {
    case invalidData, server, noCities
    var errorDescription: String? {
        switch self {
        case .invalidData: return "天气数据不完整，请稍后重试"
        case .server: return "天气服务暂时不可用"
        case .noCities: return "没有找到城市，请尝试英文或添加国家名"
        }
    }
}

enum WeatherAPI {
    static func forecastURL(location: WeatherLocation) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "6")
        ]
        return components.url!
    }

    @discardableResult
    static func search(_ query: String, completion: @escaping (Result<[WeatherLocation], Error>) -> Void) -> URLSessionDataTask {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [URLQueryItem(name: "name", value: query), URLQueryItem(name: "count", value: "10"), URLQueryItem(name: "language", value: "zh")]
        struct Response: Decodable { let results: [WeatherLocation]? }
        return request(components.url!) { result in
            completion(result.flatMap { data in
                Result {
                    let cities = try JSONDecoder().decode(Response.self, from: data).results ?? []
                    guard !cities.isEmpty else { throw WeatherError.noCities }
                    return cities
                }
            })
        }
    }

    @discardableResult
    static func request(_ url: URL, session: URLSession = .shared,
                        completion: @escaping (Result<Data, Error>) -> Void) -> URLSessionDataTask {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let task = session.dataTask(with: request) { data, response, error in
            let result: Result<Data, Error>
            if let error { result = .failure(error) }
            else if let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), let data {
                result = .success(data)
            } else { result = .failure(WeatherError.server) }
            DispatchQueue.main.async { completion(result) }
        }
        task.resume()
        return task
    }
}

// All state is used on the main thread. Multiple screen saver views share one
// request/cache; no repeating network timer survives after the saver stops.
final class WeatherStore {
    static let shared = WeatherStore()
    static let refreshInterval: TimeInterval = 30 * 60
    static let retryInterval: TimeInterval = 5 * 60
    private(set) var snapshot: WeatherSnapshot?
    private(set) var isLoading = false
    private(set) var failed = false
    private var nextAttempt = Date.distantPast
    private var location: WeatherLocation?
    private var task: URLSessionDataTask?
    private var generation = 0
    private let defaults: UserDefaults
    private let session: URLSession
    private let cacheKey = "weatherCache.v1"

    init(defaults: UserDefaults = UserDefaults(suiteName: ClockPreferences.domain) ?? .standard,
         session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
    }

    func refresh(location: WeatherLocation, now: Date = Date(), force: Bool = false) {
        if self.location != location {
            generation += 1
            task?.cancel()
            task = nil
            isLoading = false
            failed = false
            self.location = location
            snapshot = defaults.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode(WeatherSnapshot.self, from: $0) }
            if snapshot?.location != location { snapshot = nil }
            nextAttempt = snapshot.map { $0.fetchedAt.addingTimeInterval(Self.refreshInterval) } ?? .distantPast
            // A clock correction must not postpone requests indefinitely.
            if let snapshot, snapshot.fetchedAt > now { nextAttempt = .distantPast }
        }
        guard !isLoading, force || now >= nextAttempt else { return }
        isLoading = true
        let requestGeneration = generation
        task = WeatherAPI.request(WeatherAPI.forecastURL(location: location), session: session) { [weak self] result in
            guard let self, self.generation == requestGeneration else { return }
            self.isLoading = false
            self.task = nil
            let decoded = result.flatMap { data in
                Result { try JSONDecoder().decode(WeatherResponse.self, from: data).snapshot(location: location) }
            }
            switch decoded {
            case .success(let snapshot):
                self.snapshot = snapshot
                self.failed = false
                self.nextAttempt = Date().addingTimeInterval(Self.refreshInterval)
                if let data = try? JSONEncoder().encode(snapshot) { self.defaults.set(data, forKey: self.cacheKey) }
            case .failure:
                self.failed = true
                self.nextAttempt = Date().addingTimeInterval(Self.retryInterval)
            }
        }
    }

    func footer(fahrenheit: Bool, now: Date = Date()) -> String {
        let unit = fahrenheit ? "°F" : "°C"
        guard let snapshot else {
            return "open-meteo.com · \(isLoading ? "正在获取天气…" : "天气暂不可用，稍后重试") · \(unit)"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM/dd HH:mm"
        let stale = failed || now.timeIntervalSince(snapshot.fetchedAt) > Self.refreshInterval + 60
        return "open-meteo.com · \(stale ? "缓存" : "更新") \(formatter.string(from: snapshot.fetchedAt)) · \(unit)"
    }
}
