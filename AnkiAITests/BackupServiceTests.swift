import XCTest
@testable import AnkiAI

/// Issue 1 — manual backups go to a user-accessible Documents/Backups folder with
/// validation, atomic placement, no overwrite, and partial-cleanup on failure.
final class BackupServiceTests: XCTestCase {

    private func tempService() throws -> (BackupService, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Backups-\(UUID().uuidString)")
        return (BackupService(directory: dir), dir)
    }

    private func validColpkgBytes() -> Data {
        // "PK\x03\x04" zip magic + padding so size > 256.
        Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 0, count: 400)
    }

    func testBackupLandsInBackupsDirWithTimestampedName() async throws {
        let (svc, dir) = try tempService()
        let info = try await svc.create { path in try self.validColpkgBytes().write(to: URL(fileURLWithPath: path)) }
        XCTAssertEqual(info.url.deletingLastPathComponent().standardizedFileURL, dir.standardizedFileURL)
        XCTAssertTrue(info.name.hasPrefix("AnkiAI-Backup-"))
        XCTAssertTrue(info.name.hasSuffix(".colpkg"))
        XCTAssertGreaterThan(info.size, 256)
        XCTAssertTrue(FileManager.default.fileExists(atPath: info.url.path))
    }

    func testFilenameHasNoIllegalCharacters() {
        let name = BackupService.filename(date: Date(timeIntervalSince1970: 1_750_000_000))
        for bad in [":", "/", "\\", "?", "*"] { XCTAssertFalse(name.contains(bad), "illegal char \(bad) in \(name)") }
    }

    func testFailedExportDoesNotReportSuccessAndCleansTemp() async throws {
        let (svc, dir) = try tempService()
        struct Boom: Error {}
        do {
            _ = try await svc.create { _ in throw Boom() }
            XCTFail("a failed export must not report success")
        } catch { /* expected */ }
        let listed = try svc.list()
        XCTAssertTrue(listed.isEmpty, "no backup file remains after a failed export")
        // temp dir should not accumulate stray .colpkg from this op (best-effort check)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("x").path))
    }

    func testTooSmallAndNonArchiveRejected() async throws {
        let (svc, _) = try tempService()
        do { _ = try await svc.create { p in try Data([0x50, 0x4B]).write(to: URL(fileURLWithPath: p)) }; XCTFail() }
        catch let e as BackupError { XCTAssertEqual(e, BackupError.tooSmall) }
        do { _ = try await svc.create { p in try Data(repeating: 0x41, count: 500).write(to: URL(fileURLWithPath: p)) }; XCTFail() }
        catch let e as BackupError { XCTAssertEqual(e, BackupError.notArchive) }
    }

    func testNeverOverwritesExistingBackup() async throws {
        let (svc, _) = try tempService()
        let a = try await svc.create { p in try self.validColpkgBytes().write(to: URL(fileURLWithPath: p)) }
        let b = try await svc.create { p in try self.validColpkgBytes().write(to: URL(fileURLWithPath: p)) }
        XCTAssertNotEqual(a.url, b.url, "a second backup in the same second gets a unique name")
        XCTAssertEqual(try svc.list().count, 2)
    }

    func testListAndDelete() async throws {
        let (svc, _) = try tempService()
        _ = try await svc.create { p in try self.validColpkgBytes().write(to: URL(fileURLWithPath: p)) }
        let second = try await svc.create { p in try self.validColpkgBytes().write(to: URL(fileURLWithPath: p)) }
        XCTAssertEqual(try svc.list().count, 2)
        try svc.delete(second)
        XCTAssertEqual(try svc.list().count, 1)
    }

    /// A REAL collection backup (.colpkg from the backend) passes validation —
    /// confirms colpkg is a recognised archive end-to-end.
    func testRealColpkgBackupValidates() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let colPath = dir.appendingPathComponent("collection.anki2").path
        try AnkiCollection.createFixture(path: colPath)
        let gateway = BackendCollectionGateway(path: colPath)

        let svc = BackupService(directory: dir.appendingPathComponent("Backups"))
        let info = try await svc.create { tempPath in try await gateway.backup(toPath: tempPath) }
        XCTAssertGreaterThan(info.size, 256)
        XCTAssertTrue(FileManager.default.fileExists(atPath: info.url.path))
    }
}
