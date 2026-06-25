import Foundation

/// A manual backup file in the user-accessible Documents/Backups folder.
public struct BackupInfo: Identifiable, Equatable, Sendable {
    public let url: URL
    public let size: Int
    public let date: Date
    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
    public init(url: URL, size: Int, date: Date) { self.url = url; self.size = size; self.date = date }
}

public enum BackupError: Error, LocalizedError, Equatable {
    case exportFailed(String)
    case tooSmall
    case notArchive
    case moveFailed

    public var errorDescription: String? {
        switch self {
        case .exportFailed(let m): return "Backup export failed: \(m)"
        case .tooSmall: return "The exported backup was empty or implausibly small."
        case .notArchive: return "The exported file is not a valid .colpkg archive."
        case .moveFailed: return "Could not save the backup into Documents/Backups."
        }
    }
}

/// Creates / lists / deletes manual `.colpkg` backups in a user-accessible
/// `Documents/Backups` folder, with end-to-end validation before reporting success
/// and atomic placement (never overwrites an existing backup, cleans up partials).
public struct BackupService {
    let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let docs = (try? FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true))
                ?? FileManager.default.temporaryDirectory
            self.directory = docs.appendingPathComponent("Backups", isDirectory: true)
        }
    }

    public func backupsDirectory() throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func filename(date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return "AnkiAI-Backup-\(f.string(from: date)).colpkg"
    }

    private func uniqueDestination() throws -> URL {
        let dir = try backupsDirectory()
        let base = Self.filename()
        var dest = dir.appendingPathComponent(base)
        var i = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            let stem = (base as NSString).deletingPathExtension
            dest = dir.appendingPathComponent("\(stem)-\(i).colpkg")
            i += 1
        }
        return dest
    }

    /// `export(tempPath)` must write the full collection backup to `tempPath`.
    /// Validates (exists / non-empty / plausible size / zip archive) then atomically
    /// moves into Documents/Backups. Throws (and cleans the partial temp) on any
    /// failure — never reports success for an incomplete backup.
    public func create(export: (String) async throws -> Void) async throws -> BackupInfo {
        let dest = try uniqueDestination()
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".colpkg")
        do {
            do { try await export(temp.path) }
            catch { throw BackupError.exportFailed("\(error)") }

            guard FileManager.default.fileExists(atPath: temp.path) else {
                throw BackupError.exportFailed("no file was produced")
            }
            let size = (try FileManager.default.attributesOfItem(atPath: temp.path)[.size] as? Int) ?? 0
            guard size > 256 else { throw BackupError.tooSmall }
            guard Self.looksLikeZip(temp) else { throw BackupError.notArchive }

            try FileManager.default.moveItem(at: temp, to: dest)
            guard FileManager.default.fileExists(atPath: dest.path) else { throw BackupError.moveFailed }
            return BackupInfo(url: dest, size: size, date: Date())
        } catch {
            try? FileManager.default.removeItem(at: temp)  // clean up incomplete temp
            throw error
        }
    }

    /// `.colpkg` (like `.apkg`) is a ZIP archive → "PK" magic bytes.
    static func looksLikeZip(_ url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        return Array(h.readData(ofLength: 2)) == [0x50, 0x4B]
    }

    public func list() throws -> [BackupInfo] {
        let dir = try backupsDirectory()
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])) ?? []
        return urls.filter { $0.pathExtension.lowercased() == "colpkg" }.map { url in
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attrs?[.size] as? Int) ?? 0
            let date = (attrs?[.modificationDate] as? Date) ?? .distantPast
            return BackupInfo(url: url, size: size, date: date)
        }.sorted { $0.date > $1.date }
    }

    public func delete(_ info: BackupInfo) throws {
        try FileManager.default.removeItem(at: info.url)
    }
}
