import XCTest
@testable import AnkiAI

/// Repair P0 — a seeded/unknown collection must never be allowed to replace the
/// user's remote AnkiWeb data. Verifies the upload-forbidden gate.
final class CollectionProvenanceTests: XCTestCase {

    private func store() -> AISettingsStore {
        AISettingsStore(keychain: InMemorySecretStore(),
                        defaults: UserDefaults(suiteName: "prov-\(UUID().uuidString)")!)
    }

    func testDefaultsToUnknownAndForbidsUpload() {
        let s = store()
        XCTAssertEqual(s.collectionProvenance, .unknown)
        XCTAssertTrue(s.isUploadForbidden, "unknown provenance must forbid upload")
    }

    func testSeededSampleForbidsUpload() {
        let s = store()
        s.collectionProvenance = .seededSample
        XCTAssertTrue(s.isUploadForbidden, "the demo/sample collection must never replace AnkiWeb")
    }

    func testDownloadedFromAnkiWebAllowsUpload() {
        let s = store()
        s.collectionProvenance = .downloadedFromAnkiWeb
        XCTAssertFalse(s.isUploadForbidden)
    }

    func testRestoredAndCreatedAllowUpload() {
        let s = store()
        s.collectionProvenance = .restoredFromBackup
        XCTAssertFalse(s.isUploadForbidden)
        s.collectionProvenance = .createdLocally
        XCTAssertFalse(s.isUploadForbidden)
    }

    func testProvenancePersistsAcrossStoreInstances() {
        let suite = "prov-persist-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let s1 = AISettingsStore(keychain: InMemorySecretStore(), defaults: d)
        s1.collectionProvenance = .downloadedFromAnkiWeb
        let s2 = AISettingsStore(keychain: InMemorySecretStore(), defaults: d)
        XCTAssertEqual(s2.collectionProvenance, .downloadedFromAnkiWeb)
        XCTAssertFalse(s2.isUploadForbidden)
    }
}
