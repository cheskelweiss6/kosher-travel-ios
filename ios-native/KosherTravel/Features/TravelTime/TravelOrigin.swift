// Where the traveler is, for the travel-time chips. Port of the website's src/lib/travelTime.ts "finding the traveler".
// In order: what they chose before (UserDefaults, the website's localStorage key and JSON), the phone's location when
// they tap "Use my current location" (or when location permission was already given; never a prompt by itself),
// otherwise an approximate city from the website's own /api/geo (IP location; no prompt).
import Foundation
import CoreLocation
import Observation

enum TravelOriginSource: String, Codable { case gps, ip, pick }

/// Same fields and JSON as the website's Origin (stored under "kt-travel-origin-v1").
struct TravelOriginValue: Codable, Equatable {
    var lat: Double
    var lng: Double
    var label: String
    var us: Bool
    var source: TravelOriginSource
    var at: Double
}

enum TravelLocateStatus { case idle, locating, denied, error }

@Observable
final class TravelOrigin {
    static let shared = TravelOrigin()

    static let storageKey = "kt-travel-origin-v1"
    static let ipMaxAge: Double = 7 * 24 * 3600 * 1000
    static let geoURL = URL(string: "https://www.yourkoshertravel.com/api/geo")!

    private(set) var origin: TravelOriginValue?
    private(set) var status: TravelLocateStatus = .idle

    @ObservationIgnored private var started = false
    @ObservationIgnored private var cities: [CityInfo] = []
    @ObservationIgnored private var locator: TTLocator?
    @ObservationIgnored private var waiting: [(Bool) -> Void] = []

    private init() {}

    private static func nowMs() -> Double { (Date().timeIntervalSince1970 * 1000).rounded(.down) }

    // MARK: storage

    private func save() {
        let d = UserDefaults.standard
        if let o = origin, let data = try? JSONEncoder().encode(o), let s = String(data: data, encoding: .utf8) {
            d.set(s, forKey: Self.storageKey)
        } else {
            d.removeObject(forKey: Self.storageKey)
        }
    }

    private func setOrigin(_ o: TravelOriginValue?) {
        origin = o
        save()
    }

    private static func loadSaved() -> TravelOriginValue? {
        let d = UserDefaults.standard
        var data: Data?
        if let s = d.string(forKey: storageKey) { data = s.data(using: .utf8) } else { data = d.data(forKey: storageKey) }
        guard let data, let o = try? JSONDecoder().decode(TravelOriginValue.self, from: data),
              o.lat.isFinite, o.lng.isFinite else { return nil }
        return o
    }

    // MARK: start

    @ObservationIgnored private var startScheduled = false

    /// Safe to call from a view's body: starts once, on the next main-queue turn (chips that show nothing yet still start it).
    @discardableResult
    func startSoon(cities: [CityInfo]) -> Bool {
        if startScheduled { return true }
        startScheduled = true
        DispatchQueue.main.async { [weak self] in self?.start(cities: cities) }
        return true
    }

    /// Called when a screen with travel times shows (every chip and bar does it). Never opens a permission prompt by itself.
    func start(cities: [CityInfo]) {
        if !cities.isEmpty && self.cities.isEmpty { self.cities = cities }
        if started { return }
        started = true
        if origin == nil, let o = Self.loadSaved() { origin = o }
        if let o = origin, o.source != .ip || Self.nowMs() - o.at < Self.ipMaxAge { return }
        // Reuse a location permission already given (no prompt); otherwise an approximate city from the IP.
        let auth = CLLocationManager().authorizationStatus
        if auth == .authorizedWhenInUse || auth == .authorizedAlways {
            locateMe { [weak self] ok in if !ok { self?.fromIp() } }
        } else {
            fromIp()
        }
    }

    // MARK: actions

    /// Ask the phone for its location (from a tap). Calls back with true when an origin was set.
    func locateMe(_ done: @escaping (Bool) -> Void = { _ in }) {
        waiting.append(done)
        if locator != nil { return } // already asking: answered together
        status = .locating
        let l = TTLocator()
        locator = l
        l.locate { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.locator = nil
                let finish: (Bool) -> Void = { ok in
                    let all = self.waiting
                    self.waiting = []
                    all.forEach { $0(ok) }
                }
                switch result {
                case .success(let c):
                    let lat = TTMath.round(c.latitude, 2), lng = TTMath.round(c.longitude, 2) // ~1 km: enough for a city
                    self.labelFor(lat, lng) { label, us in
                        self.status = .idle
                        self.setOrigin(TravelOriginValue(lat: lat, lng: lng, label: label, us: us, source: .gps, at: Self.nowMs()))
                        finish(true)
                    }
                case .denied:
                    self.status = .denied
                    finish(false)
                case .failed:
                    self.status = .error
                    finish(false)
                }
            }
        }
    }

    func pick(lat: Double, lng: Double, label: String, us: Bool) {
        status = .idle
        setOrigin(TravelOriginValue(lat: TTMath.round(lat, 2), lng: TTMath.round(lng, 2), label: label, us: us, source: .pick, at: Self.nowMs()))
    }

    func clear() { setOrigin(nil) }

    // MARK: lookups

    private static let urlSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 5
        c.timeoutIntervalForResource = 5
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    private static func str(_ v: Any?) -> String {
        if let s = v as? String { return s }
        return ""
    }

    /// The place name for a point: the same free reverse lookup the website uses, else the nearest app city.
    private func labelFor(_ lat: Double, _ lng: Double, _ done: @escaping (String, Bool) -> Void) {
        let fallback = { [weak self] in
            let us = TTMath.inUS(lat, lng)
            done(us ? TTGeo.nearestUSCityLabel(lat, lng, cities: self?.cities ?? []) : "your location", us)
        }
        guard let url = URL(string: "https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=\(lat)&longitude=\(lng)&localityLanguage=en") else {
            fallback(); return
        }
        Self.urlSession.dataTask(with: url) { data, resp, _ in
            var answer: (String, Bool)?
            if let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data,
               let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                let code = Self.str(j["countryCode"])
                let us = code == "US"
                let locality = Self.str(j["locality"])
                let place = locality.isEmpty ? Self.str(j["city"]) : locality
                var region = us ? Self.str(j["principalSubdivisionCode"]) : Self.str(j["countryName"])
                if us, region.hasPrefix("US-") { region = String(region.dropFirst(3)) }
                if !place.isEmpty {
                    answer = (region.isEmpty ? place : "\(place), \(region)", us)
                } else if !code.isEmpty {
                    let name = Self.str(j["countryName"])
                    answer = (name.isEmpty ? "your location" : name, us)
                }
            }
            let result = answer
            DispatchQueue.main.async {
                if let result { done(result.0, result.1) } else { fallback() }
            }
        }.resume()
    }

    private static func number(_ v: Any?) -> Double {
        // JavaScript Number(): null -> 0, missing -> NaN, numeric strings parse.
        if v == nil { return .nan }
        if v is NSNull { return 0 }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? 0 : (Double(t) ?? .nan)
        }
        return .nan
    }

    /// An approximate city from the website's /api/geo (IP location headers). Silent on any failure.
    private func fromIp() {
        var req = URLRequest(url: Self.geoURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        Self.urlSession.dataTask(with: req) { data, resp, _ in
            guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data,
                  (http.value(forHTTPHeaderField: "Content-Type") ?? "").contains("json"),
                  let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
            let lat = Self.number(j["lat"]), lng = Self.number(j["lng"])
            if !lat.isFinite || !lng.isFinite || (lat == 0 && lng == 0) { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let o = self.origin, o.source != .ip { return } // the traveler chose meanwhile
                let us = Self.str(j["country"]) == "US"
                let city = Self.str(j["city"]), region = Self.str(j["region"])
                let label = !city.isEmpty ? (us && !region.isEmpty ? "\(city), \(region)" : city)
                    : (us ? TTGeo.nearestUSCityLabel(lat, lng, cities: self.cities) : "your area")
                self.setOrigin(TravelOriginValue(lat: TTMath.round(lat, 1), lng: TTMath.round(lng, 1), label: label, us: us, source: .ip, at: Self.nowMs()))
            }
        }.resume()
    }

    // MARK: times

    func times(toLat lat: Double, lng: Double, placeUS: Bool) -> TravelTimes {
        TTMath.times(from: origin, toLat: lat, lng: lng, placeUS: placeUS)
    }
}

/// One-shot CoreLocation request (when in use, city accuracy, 12 s limit, a fix up to 30 min old is fine).
final class TTLocator: NSObject, CLLocationManagerDelegate {
    enum Result { case success(CLLocationCoordinate2D), denied, failed }

    private let manager = CLLocationManager()
    private var done: ((Result) -> Void)?
    private var waitingForAuth = false
    private var requested = false
    private var timeout: DispatchWorkItem?

    override init() {
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func locate(_ done: @escaping (Result) -> Void) {
        self.done = done
        manager.delegate = self
        let t = DispatchWorkItem { [weak self] in self?.finish(.failed) }
        timeout = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: t)
        proceed(manager.authorizationStatus)
    }

    private func proceed(_ auth: CLAuthorizationStatus) {
        guard done != nil else { return }
        switch auth {
        case .notDetermined:
            if !waitingForAuth {
                waitingForAuth = true
                manager.requestWhenInUseAuthorization()
            }
        case .denied, .restricted:
            finish(.denied)
        default:
            if requested { return }
            requested = true
            if let l = manager.location, Date().timeIntervalSince(l.timestamp) < 30 * 60 {
                finish(.success(l.coordinate))
            } else {
                manager.requestLocation()
            }
        }
    }

    private func finish(_ r: Result) {
        guard let d = done else { return }
        done = nil
        timeout?.cancel()
        timeout = nil
        manager.delegate = nil
        d(r)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.waitingForAuth else { return }
            let s = manager.authorizationStatus
            if s != .notDetermined { self.proceed(s) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        DispatchQueue.main.async { [weak self] in self?.finish(.success(l.coordinate)) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        DispatchQueue.main.async { [weak self] in self?.finish(denied ? .denied : .failed) }
    }
}
