import Foundation
import GolfCore
import Testing
@testable import GolfMap

@MainActor
@Suite("Course editor")
struct CourseEditorTests {
    let userCourses = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)/user-courses.json")
    let origin = Coordinate(latitude: 29.45, longitude: -98.47)

    func repository(remote: @escaping StubURLProtocol.Handler = { _ in (503, Data()) }) async -> CourseRepository {
        let repository = CourseRepository(
            userCoursesURL: userCourses,
            bundledURL: Bundle(for: RoundRepository.self).url(forResource: "san_antonio_courses", withExtension: "json"),
            remote: CourseRemoteClient(session: StubURLProtocol.session(remote))
        )
        await repository.load()
        return repository
    }

    func trace(_ store: CourseEditorStore, type: TraceFeatureType = .green) {
        store.featureType = type
        store.setMode(.draw)
        for (north, east) in [(0.0, 0.0), (0.0, 1.0), (1.0, 1.0), (1.0, 0.0)] {
            store.drawStroke(Coordinate(latitude: origin.latitude + north * 0.0002, longitude: origin.longitude + east * 0.0002), isStart: true)
        }
        store.commitShape()
    }

    @Test func seedsFromBuiltInDataWhenTheDatabaseFailsThenSavesAndReopens() async throws {
        let repository = await repository()
        let seeded = CourseEditorStore(seed: "Brackenridge Golf Course", repository: repository)
        await seeded.load()
        let builtIn = repository.sourceFeatures.filter { $0.matchesCourse("Brackenridge Golf Course") }
        #expect(seeded.draft.features.count == builtIn.count)
        #expect(seeded.importSource == "Brackenridge Golf Course (Built-in)")
        #expect(seeded.draft.features.allSatisfy { $0.id?.description.hasPrefix("user-") == true })

        let store = CourseEditorStore(repository: repository)
        await store.load()
        store.courseName = "Backyard Links"
        trace(store)
        #expect(store.draft.features.count == 1)
        #expect(store.hasUnsavedChanges)
        await store.save()
        #expect(store.isFinished)
        #expect(repository.userCourseNames == ["Backyard Links"])

        let reopened = CourseEditorStore(existing: "Backyard Links", repository: repository)
        await reopened.load()
        #expect(reopened.draft.features == store.draft.features)
        #expect(!reopened.hasUnsavedChanges)
        reopened.courseName = "Renamed"
        #expect(reopened.draft.trimmedName == "Backyard Links", "a saved course keeps its name")
    }

    @Test func unsavedShapeEditsAskBeforeChangingHoles() async throws {
        let store = CourseEditorStore(repository: await repository())
        await store.load()
        store.courseName = "Backyard Links"
        trace(store)
        let id = try #require(store.draft.features.first?.id)
        store.beginEditing(id)
        let moved = Coordinate(latitude: origin.latitude - 0.0001, longitude: origin.longitude)
        store.moveEditVertex(0, to: moved)
        store.goToHole(2)
        #expect(store.prompt == .unsavedEdit("green", then: .hole(2)))
        #expect(store.draft.currentHole == 1)
        store.resolveUnsavedEdit(keepChanges: true, then: .hole(2))
        #expect(store.editing == nil)
        #expect(store.draft.currentHole == 2)
        #expect(store.draft.features[0].geometry.editableVertices.first == moved)
    }

    @Test func savingOverAnotherLocalCourseAsksFirst() async throws {
        let repository = await repository()
        try repository.userCourses.save(course: "Backyard Links", rows: [GolfFeature(id: .int(1), featureType: "green", holeNumber: "1", name: nil, par: 4, handicap: 1, courseName: "Backyard Links", geometry: .point(origin)).row])
        let store = CourseEditorStore(repository: repository)
        await store.load()
        store.courseName = "Backyard Links"
        trace(store)
        await store.save()
        #expect(store.prompt == .overwrite(.local, detail: "on this device (1 saved features)"))
        #expect(!store.isFinished)
        await store.performSave()
        #expect(try repository.userCourses.rows(forCourse: "Backyard Links").count == 1)
    }

    @Test func uploadReplacesRemoteRowsAndRestoresThemOnFailure() async throws {
        let log = RequestLog()
        let insertFails = Locked(false)
        let repository = await repository { request in
            log.append(request)
            switch request.httpMethod {
            case "GET" where request.queryValue("order") == "id.desc": return (200, Data(#"[{"id":500}]"#.utf8))
            case "GET": return (200, Data("[\(CourseRemoteClientTests.row(7, course: "Backyard Links"))]".utf8))
            case "POST" where insertFails.value && request.bodyJSON?.arrayValue?.first?["id"] == .int(501):
                return (500, Data())
            default: return (201, Data())
            }
        }
        let store = CourseEditorStore(repository: repository)
        await store.load()
        store.courseName = "Backyard Links"
        trace(store)
        await store.upload()
        #expect(store.prompt == .overwrite(.database, detail: "in the shared database (1 features)"))

        await store.performUpload()
        #expect(store.message == "Uploaded 1 features for Backyard Links.")
        let writes = log.all.filter { $0.httpMethod != "GET" }
        #expect(writes.map(\.httpMethod) == ["DELETE", "POST"])
        #expect(writes[0].url?.query()?.contains("course_name=eq.Backyard%20Links") == true)
        let inserted = try #require(writes[1].bodyJSON?.arrayValue?.first)
        #expect(inserted["id"] == .int(501))
        #expect(inserted["course_name"] == .string("Backyard Links"))
        #expect(inserted["par"] == .int(4))

        insertFails.value = true
        await store.performUpload()
        #expect(store.message == CourseRemoteClient.Failure.uploadFailed(restored: true).errorDescription)
        let restore = try #require(log.all.last)
        #expect(restore.httpMethod == "POST")
        #expect(restore.bodyJSON?.arrayValue?.first?["id"] == .int(7), "the backup goes back with its original ID")
    }

    @Test func osmSearchFallsBackAcrossOverpassServers() async throws {
        let log = RequestLog()
        let client = OSMClient(session: StubURLProtocol.session { request in
            log.append(request)
            if request.url?.host() == "nominatim.openstreetmap.org" { return (200, Data("[]".utf8)) }
            if request.url?.host() == "overpass.kumi.systems" { return (504, Data()) }
            return (200, Data(#"{"elements":[{"type":"way","id":9,"tags":{"name":"Quarry Golf Club"},"center":{"lat":29.5,"lon":-98.48}}]}"#.utf8))
        })
        let results = try await client.searchCourses(named: "Quarry", near: origin)
        #expect(results.map(\.name) == ["Quarry Golf Club"])
        let hosts = log.all.compactMap { $0.url?.host() }
        #expect(hosts.filter { $0 == "nominatim.openstreetmap.org" }.count == 4, "every name variant before Overpass")
        #expect(hosts.suffix(2) == ["overpass.kumi.systems", "overpass-api.de"])
        #expect(log.all.first?.value(forHTTPHeaderField: "User-Agent") == OSMClient.userAgent)
        #expect(log.all.first?.queryValue("countrycodes") == "us")
    }
}

final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

extension URLRequest {
    /// URLProtocol receives bodies as streams.
    var bodyJSON: JSONValue? {
        if let httpBody { return try? JSONValue.parse(httpBody) }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return try? JSONValue.parse(data)
    }
}
