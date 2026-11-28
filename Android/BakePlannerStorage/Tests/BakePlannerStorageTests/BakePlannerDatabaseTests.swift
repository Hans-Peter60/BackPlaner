//
//  BakePlannerDatabaseTests.swift
//  BakePlannerStorageTests
//
//  Opening the file: a database from a newer app is refused, not migrated.
//

import BakePlannerStorage
import Foundation
import SkipSQLPlus
import Testing

@Suite("The database file on Android")
struct BakePlannerDatabaseTests {

    @Test("A file from a newer version is refused and left as it is")
    func newerSchemaIsRefused() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("newer-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let context = try SQLContext(path: path, flags: [.create, .readWrite], configuration: .plus)
        context.userVersion = 999
        try context.close()

        #expect(throws: BakePlannerDatabaseError.self) {
            _ = try BakePlannerDatabase(path: path)
        }
        let reopened = try SQLContext(path: path, flags: [.readWrite], configuration: .plus)
        #expect(reopened.userVersion == 999)
        try reopened.close()
    }
}
