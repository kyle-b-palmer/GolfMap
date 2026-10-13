import Foundation
import GolfCore
import Testing
@testable import GolfMap

@Suite("Weather service")
struct WeatherServiceTests {
    let course = Coordinate(latitude: 29.4515, longitude: -98.4766)
    static let body = Data(#"{"elevation":200,"current":{"temperature_2m":91,"wind_speed_10m":9,"wind_direction_10m":200}}"#.utf8)

    @Test func cachesForNearbyFixes() async {
        let log = RequestLog()
        let service = WeatherService(session: StubURLProtocol.session { request in
            log.append(request)
            return (200, Self.body)
        })
        let first = await service.conditions(at: course)
        let second = await service.conditions(at: GeoMath.destination(from: course, bearing: 90, meters: 200))
        #expect(first?.temperatureF == 91)
        #expect(second == first)
        #expect(log.all.count == 1)
    }

    @Test func failuresFallBackToTheLastReading() async {
        let log = RequestLog()
        let service = WeatherService(session: StubURLProtocol.session { request in
            log.append(request)
            return log.all.count == 1 ? (200, Self.body) : (503, Data())
        })
        let first = await service.conditions(at: course)
        let elsewhere = await service.conditions(at: GeoMath.destination(from: course, bearing: 0, meters: 5_000))
        #expect(log.all.count == 2)
        #expect(elsewhere == first)
    }

    @Test func noReadingMeansRawYardage() async {
        let service = WeatherService(session: StubURLProtocol.session { _ in (200, Data(#"{"current":{}}"#.utf8)) })
        #expect(await service.conditions(at: course) == nil)
    }
}

@Suite("Course remote client")
struct CourseRemoteClientTests {
    static func row(_ id: Int, course: String = "Remote Course") -> String {
        #"{"id":\#(id),"feature_type":"green","hole_number":"1","name":null,"par":4,"handicap":7,"course_name":"\#(course)","geom":{"type":"Polygon","coordinates":[[[-98.1,29.1],[-98.1,29.2],[-98.2,29.2],[-98.1,29.1]]]}}"#
    }

    static func page(_ ids: Range<Int>) -> Data {
        Data("[\(ids.map { row($0) }.joined(separator: ","))]".utf8)
    }

    @Test func pagesThroughEveryRowWithTheKey() async throws {
        let log = RequestLog()
        let client = CourseRemoteClient(session: StubURLProtocol.session { request in
            log.append(request)
            let offset = Int(request.queryValue("offset") ?? "0") ?? 0
            return (200, offset == 0 ? Self.page(0..<CourseRemoteClient.pageSize) : Self.page(1000..<1003))
        })
        let features = try await client.allFeatures()
        #expect(features.count == 1003)
        #expect(features.first?.par == 4)

        let requests = log.all
        #expect(requests.map { $0.queryValue("offset") } == ["0", "1000"])
        #expect(requests.first?.url?.path() == "/rest/v1/golf_features")
        #expect(requests.first?.queryValue("select") == CourseRemoteClient.featureColumns)
        #expect(requests.first?.value(forHTTPHeaderField: "apikey") == CourseRemoteClient.Configuration.app.publishableKey)
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer \(CourseRemoteClient.Configuration.app.publishableKey)")
    }

    @Test func courseFilterIsEncoded() async throws {
        let log = RequestLog()
        let client = CourseRemoteClient(session: StubURLProtocol.session { request in
            log.append(request)
            return (200, Data("[\(Self.row(1, course: "A+B Links"))]".utf8))
        })
        let features = try await client.features(forCourse: "  A+B Links ")
        #expect(features.map(\.courseName) == ["A+B Links"])
        #expect(log.all.first?.url?.query()?.contains("course_name=eq.A%2BB%20Links") == true)
    }

    @Test func courseNamesAreTrimmedUniqueAndSorted() async throws {
        let client = CourseRemoteClient(session: StubURLProtocol.session { _ in
            (200, Data(#"[{"course_name":" Zeta "},{"course_name":"Alpha"},{"course_name":"Zeta"},{"course_name":""},{"course_name":null}]"#.utf8))
        })
        #expect(try await client.courseNames() == ["Alpha", "Zeta"])
    }

    @Test func serverErrorsSurface() async {
        let client = CourseRemoteClient(session: StubURLProtocol.session { _ in (401, Data(#"{"message":"bad key"}"#.utf8)) })
        await #expect(throws: CourseRemoteClient.Failure.status(401)) { try await client.allFeatures() }
    }

    @MainActor
    @Test func repositoryFallsBackToSupabaseWithoutTheBundledAsset() async {
        let remote = CourseRemoteClient(session: StubURLProtocol.session { _ in (200, Self.page(0..<3)) })
        let repository = CourseRepository(
            userCoursesURL: FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json"),
            bundledURL: nil,
            remote: remote
        )
        await repository.load()
        #expect(repository.state == .loaded)
        #expect(repository.features.count == 3)
        #expect(repository.catalog.map(\.name) == ["Remote Course"])
    }
}
