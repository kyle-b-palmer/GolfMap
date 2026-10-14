import Foundation
@testable import GolfCore
import Testing

@Suite("Course draft")
struct CourseDraftTests {
    let origin = Coordinate(latitude: 29.45, longitude: -98.47)
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func offset(_ north: Double, _ east: Double) -> Coordinate {
        Coordinate(latitude: origin.latitude + north * 0.0001, longitude: origin.longitude + east * 0.0001)
    }

    func square(_ draft: inout CourseDraft, size: Double = 1) {
        for point in [offset(0, 0), offset(0, size), offset(size, size), offset(size, 0)] { draft.addPoint(point) }
    }

    @Test func drawnPointsRespectSpacing() {
        var draft = CourseDraft(courseName: "Backyard")
        draft.addPoint(origin)
        draft.addPoint(offset(0.2, 0), minimumSpacing: CourseDraft.minimumPointSpacingMeters)
        #expect(draft.pending.count == 1, "2 m is inside the 4 m spacing")
        draft.addPoint(offset(0.5, 0), minimumSpacing: CourseDraft.minimumPointSpacingMeters)
        #expect(draft.pending.count == 2)
        draft.undoPoint()
        #expect(draft.pending == [origin])
    }

    @Test func committingNeedsANameAndThreePoints() {
        var draft = CourseDraft(courseName: " ")
        square(&draft)
        #expect(draft.commitShape(user: nil, now: now) == "Enter a course name first.")
        draft.courseName = "Backyard"
        draft.clearPoints()
        draft.addPoint(origin)
        draft.addPoint(offset(1, 0))
        #expect(draft.commitShape(user: nil, now: now).hasPrefix("Add at least 3 points"))
        #expect(draft.features.isEmpty)
    }

    @Test func aSingleTeeTapBecomesASquareAndTeesAccumulate() throws {
        var draft = CourseDraft(courseName: "Backyard")
        draft.featureType = .tee
        #expect(draft.commitShape(user: origin, now: now) == "Saved tee for hole 1.")
        draft.addPoint(offset(3, 0))
        _ = draft.commitShape(user: nil, now: now)
        #expect(draft.features.count == 2)
        let ring = try #require(draft.features.first?.geometry.rings.first)
        #expect(ring.count == 5 && ring.first == ring.last)
    }

    @Test func greensReplaceAndCarryTheHoleParButBunkersAccumulate() {
        var draft = CourseDraft(courseName: "Backyard")
        draft.featureType = .green
        draft.setPar(3)
        square(&draft)
        _ = draft.commitShape(user: nil, now: now)
        square(&draft, size: 2)
        _ = draft.commitShape(user: nil, now: now)
        #expect(draft.features.count == 1)
        #expect(draft.features[0].par == 3)

        draft.setPar(5)
        #expect(draft.features[0].par == 5, "editing par updates the green already on the hole")

        draft.featureType = .bunker
        square(&draft)
        _ = draft.commitShape(user: nil, now: now)
        square(&draft, size: 2)
        _ = draft.commitShape(user: nil, now: now)
        #expect(draft.features.filter { $0.featureType == "bunker" }.count == 2)
        #expect(draft.features.last?.par == nil)
    }

    @Test func holesStayInRangeAndShowTheirPar() {
        var draft = CourseDraft(courseName: "Backyard", holeCount: 2)
        draft.featureType = .green
        draft.setPar(3)
        square(&draft)
        _ = draft.commitShape(user: nil, now: now)
        #expect(draft.goToHole(2) == nil)
        #expect(draft.par == 4, "a hole without a green shows the default")
        #expect(draft.goToHole(3) == "Already on the last hole.")
        #expect(draft.goToHole(0) == nil)
        #expect(draft.currentHole == 2)
        _ = draft.goToHole(1)
        #expect(draft.par == 3)
    }

    @Test func editingInsertsMovesDeletesAndUndoes() throws {
        var draft = CourseDraft(courseName: "Backyard")
        square(&draft)
        _ = draft.commitShape(user: nil, now: now)
        let id = try #require(draft.features.first?.id)

        #expect(draft.beginEditing(id) == nil)
        #expect(draft.editing?.vertices.count == 4)
        draft.insertEditPoint(offset(-0.1, 0.5))
        #expect(draft.editing?.vertices.count == 5)
        #expect(draft.editing?.vertices[1] == offset(-0.1, 0.5), "inserted on the nearest (bottom) edge")
        draft.insertEditPoint(offset(0, 0.01))
        #expect(draft.editing?.vertices.count == 5, "a tap on an existing vertex doesn't add one")

        draft.moveEditVertex(at: 0, to: offset(-0.5, -0.5))
        #expect(draft.deleteEditVertex(at: 1) == nil)
        #expect(draft.editing?.vertices.count == 4)
        #expect(draft.undoEdit() == nil)
        #expect(draft.editing?.vertices.count == 5)

        #expect(draft.saveEdit() == "Saved fairway.")
        #expect(draft.editing == nil)
        #expect(draft.features[0].geometry.editableVertices.count == 5)
    }

    @Test func shapesKeepThreePointsAndCancelRestores() throws {
        var draft = CourseDraft(courseName: "Backyard")
        draft.addPoint(offset(0, 0)); draft.addPoint(offset(0, 1)); draft.addPoint(offset(1, 0))
        _ = draft.commitShape(user: nil, now: now)
        let id = try #require(draft.features.first?.id)
        let original = draft.features[0].geometry
        _ = draft.beginEditing(id)
        #expect(draft.deleteEditVertex(at: 0) == "A shape needs at least 3 points.")
        draft.moveEditVertex(at: 0, to: offset(-1, -1))
        #expect(draft.cancelEdit() == "Discarded changes.")
        #expect(draft.features[0].geometry == original)
    }

    @Test func moveAndCopyBetweenHoles() throws {
        var draft = CourseDraft(courseName: "Backyard")
        draft.featureType = .green
        square(&draft)
        _ = draft.commitShape(user: nil, now: now)
        _ = draft.goToHole(2)
        square(&draft, size: 2)
        _ = draft.commitShape(user: nil, now: now)
        let holeTwoGreen = try #require(draft.features.last?.id)

        #expect(draft.transferFeature(holeTwoGreen, toHole: 2, copy: true, now: now) == "The green is already on hole 2.")
        #expect(draft.transferFeature(holeTwoGreen, toHole: 1, copy: true, now: now) == "Copied green to hole 1.")
        #expect(draft.features.filter { $0.holeNumber == "1" }.count == 1, "the copy replaced hole 1's green")
        #expect(draft.features.count == 2)
        #expect(draft.currentHole == 1)

        #expect(draft.transferFeature(holeTwoGreen, toHole: 3, copy: false, now: now) == "Moved green from hole 2 to hole 3.")
        #expect(draft.features.first { $0.id == holeTwoGreen }?.holeNumber == "3")
    }

    @Test func renamingStampsEveryFeatureAndExportsGeoJSON() throws {
        var draft = CourseDraft(courseName: "Old")
        square(&draft)
        _ = draft.commitShape(user: nil, now: now)
        draft.courseName = " New Name "
        #expect(draft.features.allSatisfy { $0.courseName == "New Name" })
        #expect(draft.rows.first?["course_name"] == .string("New Name"))

        let collection = try JSONValue.parse(draft.geoJSON())
        #expect(collection["type"] == .string("FeatureCollection"))
        #expect(collection["features"]?.arrayValue?.first?["geometry"]?["type"] == .string("Polygon"))
    }

    @Test func importedFeaturesSetHolesAndPar() {
        var green = GolfFeature(id: .int(1), featureType: "green", holeNumber: "3", name: nil, par: 5, handicap: 7, courseName: "Elsewhere", geometry: .polygon(vertices: [origin, offset(0, 1), offset(1, 1)]))
        var draft = CourseDraft(courseName: "Mine")
        draft.replaceFeatures([green, { green.holeNumber = "9"; green.par = 3; return green }()])
        #expect(draft.holeCount == 9)
        #expect(draft.currentHole == 3)
        #expect(draft.par == 5 && draft.handicap == 7)
        #expect(draft.features.allSatisfy { $0.courseName == "Mine" })
    }
}

@Suite("Course import")
struct CourseImportTests {
    @Test func rankingMatchesNamesAndOrdersByScoreThenSource() {
        let matches = CourseImportRanking.matches(
            query: "brackenridge",
            databaseNames: ["Brackenridge Golf Course", "Olmos Basin"],
            bundledNames: ["Brackenridge Golf Course", "The Brackenridge Park Course"],
            osm: [],
            near: nil
        )
        #expect(matches.map(\.source) == [.database, .bundled, .bundled])
        #expect(matches.last?.name == "The Brackenridge Park Course", "a prefix match ranks above a contains match")
        #expect(CourseImportRanking.nameMatches("Quarry Golf Club", "the quarry golf"))
        #expect(!CourseImportRanking.nameMatches("Olmos Basin", "quarry"))
    }

    @Test func nearbyOSMResultsLeadWhenLocated() {
        let near = OSMCourseSummary(osmType: "way", osmID: 1, name: "Near", center: Coordinate(latitude: 29.45, longitude: -98.47))
        let far = OSMCourseSummary(osmType: "way", osmID: 2, name: "Far", center: Coordinate(latitude: 30.5, longitude: -97.7))
        let matches = CourseImportRanking.matches(query: "golf", databaseNames: ["Golf Database"], bundledNames: [], osm: [far, near], near: Coordinate(latitude: 29.4, longitude: -98.5))
        #expect(matches.map(\.name) == ["Near", "Far", "Golf Database"])
    }

    @Test func searchVariantsAndOverpassPattern() {
        #expect(OSMCourseParser.searchQueries("Quarry") == ["Quarry", "Quarry golf", "Quarry Golf Club", "Quarry Golf Course"])
        #expect(OSMCourseParser.searchQueries("The Quarry Golf Club") == ["The Quarry Golf Club", "The Quarry Golf Club Course", "Quarry Golf Club", "Quarry Golf Course"])
        #expect(OSMCourseParser.overpassNamePattern("St. Mary's Golf") == #"St\..*Mary's"#)
        #expect(OSMCourseParser.overpassNamePattern("the golf club") == nil)
    }

    @Test func nominatimFiltersQuarriesAndDiscGolf() throws {
        let rows = try JSONValue.parse(Data("""
        [{"type":"golf_course","category":"leisure","name":"Quarry Golf Club","lat":"29.5","lon":"-98.48","osm_type":"way","osm_id":42,"boundingbox":["29.49","29.51","-98.49","-98.47"]},
         {"type":"quarry","category":"landuse","name":"Quarry","lat":"0","lon":"0"},
         {"type":"park","category":"leisure","name":"Disc Golf Park","display_name":"Disc Golf Park","lat":"0","lon":"0"}]
        """.utf8)).arrayValue ?? []
        let kept = rows.filter(OSMCourseParser.isGolfCourse)
        #expect(kept.count == 1)
        let summary = try #require(kept.first.flatMap(OSMCourseParser.summary(nominatim:)))
        #expect(summary.osmID == 42)
        #expect(summary.bounds == OSMBounds(south: 29.49, west: -98.49, north: 29.51, east: -98.47))
        #expect(OSMCourseParser.featureQuery(for: summary).contains("(29.4885,-98.49149999999999,29.5115,-98.4685)"), "padded like Dart, same double formatting")
    }

    @Test func overpassFeaturesJoinTheNearestHoleAndTakeItsPar() throws {
        func way(_ id: Int, _ tags: String, _ points: [(Double, Double)]) -> String {
            let geometry = points.map { #"{"lat":\#($0.0),"lon":\#($0.1)}"# }.joined(separator: ",")
            return #"{"type":"way","id":\#(id),"tags":{\#(tags)},"geometry":[\#(geometry)]}"#
        }
        let square = [(29.0, -98.0), (29.0, -97.999), (29.001, -97.999), (29.001, -98.0)]
        let farSquare = square.map { ($0.0 + 0.01, $0.1) }
        let json = "[" + [
            way(1, #""golf":"hole","ref":"1","par":"4""#, [(29.0, -98.0), (29.0005, -98.0)]),
            way(2, #""golf":"hole","ref":"2","par":"3""#, [(29.01, -98.0), (29.0105, -98.0)]),
            way(3, #""golf":"green""#, farSquare),
            way(4, #""golf":"sand_trap","ref":"1""#, square),
            way(5, #""golf":"water_hazard""#, square),
            way(6, #""golf":"tee""#, [(29.0, -98.0), (29.0, -97.9)]),
        ].joined(separator: ",") + "]"
        let elements = try JSONValue.parse(Data(json.utf8)).arrayValue ?? []
        let features = OSMCourseParser.features(from: elements, courseName: "OSM Course")
        #expect(features.map(\.featureType) == ["green", "bunker"])
        #expect(features[0].holeNumber == "2" && features[0].par == 3)
        #expect(features[1].holeNumber == "1" && features[1].par == nil)
        #expect(features[0].id == .string("osm-way-3-0"))
    }

    @Test func cloningRenamesWithFreshIDs() {
        let feature = GolfFeature(id: .int(9), featureType: "green", holeNumber: "1", name: nil, par: 4, handicap: nil, courseName: "Source", geometry: .point(Coordinate(latitude: 1, longitude: 2)))
        let cloned = CourseImportRanking.clone([feature], as: " Mine ", now: Date(timeIntervalSince1970: 1))
        #expect(cloned.first?.id == .string("user-1000-0"))
        #expect(cloned.first?.courseName == "Mine")
    }
}
