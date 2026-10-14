import Foundation
import GolfCore
import os

/// Current conditions for plays-like yardage. Any failure returns the last reading (or nil), so the
/// round screen keeps showing raw yardage when weather is unavailable.
actor WeatherService {
    static let shared = WeatherService()

    /// Total time allowed for one fetch, as in the Flutter app.
    static let timeout: Duration = .seconds(8)

    private let session: URLSession
    private let now: @Sendable () -> Date
    private var cache = WeatherCache()
    private var inFlight: Task<WeatherConditions?, Never>?

    private static let logger = Logger(subsystem: "com.golfmapapp.golfMapFlutter", category: "weather")

    init(session: URLSession = .shared, now: @escaping @Sendable () -> Date = { Date() }) {
        self.session = session
        self.now = now
    }

    func conditions(at point: Coordinate) async -> WeatherConditions? {
        if let fresh = cache.fresh(for: point, now: now()) { return fresh }
        if let inFlight { return await inFlight.value }

        let session = session
        let task = Task { await Self.fetch(point, session: session) }
        inFlight = task
        let fetched = await task.value
        inFlight = nil

        guard let fetched else { return cache.conditions }
        cache.store(fetched, for: point, at: now())
        return fetched
    }

    private static func fetch(_ point: Coordinate, session: URLSession) async -> WeatherConditions? {
        let request = URLRequest(url: OpenMeteo.currentConditionsURL(for: point))
        return await withTaskGroup(of: WeatherConditions?.self) { group in
            group.addTask {
                do {
                    let (data, response) = try await session.data(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                    return OpenMeteo.parse(data)
                } catch {
                    logger.notice("Weather fetch failed: \(error.localizedDescription)")
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
