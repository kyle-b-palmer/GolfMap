import Foundation
import GolfCore

/// Traced or imported course rows on this device, in the bundled row format. Mirrors Flutter's
/// `UserCourseStorageService`: saving a course replaces every row with the same name.
struct UserCourseStore: Sendable {
    let url: URL

    init(url: URL = CourseRepository.defaultUserCoursesURL) {
        self.url = url
    }

    func rows() throws -> [JSONValue] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONValue.parse(Data(contentsOf: url)).arrayValue ?? []
    }

    func courseNames() throws -> [String] {
        Set(try rows().compactMap { $0["course_name"]?.dartString?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }).sorted()
    }

    func rows(forCourse name: String) throws -> [JSONValue] {
        let course = name.trimmingCharacters(in: .whitespaces)
        return try rows().filter { $0["course_name"]?.dartString == course }
    }

    func save(course name: String, rows newRows: [JSONValue]) throws {
        let course = name.trimmingCharacters(in: .whitespaces)
        guard !course.isEmpty else { return }
        let kept = try rows().filter { $0["course_name"]?.dartString != course }
        try write(kept + newRows)
    }

    func delete(course name: String) throws {
        let course = name.trimmingCharacters(in: .whitespaces)
        guard !course.isEmpty else { return }
        try write(try rows().filter { $0["course_name"]?.dartString != course })
    }

    private func write(_ rows: [JSONValue]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONValue.array(rows).encoded().write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
