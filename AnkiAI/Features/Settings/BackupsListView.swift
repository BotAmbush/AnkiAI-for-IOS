import SwiftUI
import UniformTypeIdentifiers

/// Wraps a local file for SwiftUI's `.fileExporter` ("Save to Files").
struct ColpkgFile: FileDocument {
    static var readableContentTypes: [UTType] { [UTType(filenameExtension: "colpkg") ?? .data] }
    let url: URL
    init(url: URL) { self.url = url }
    init(configuration: ReadConfiguration) throws { throw CocoaError(.fileReadUnknown) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { try FileWrapper(url: url) }
}

/// Lists the manual backups in Documents/Backups with share / save-to-Files /
/// delete (with confirmation).
struct BackupsListView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var backups: [BackupInfo] = []
    @State private var deleteTarget: BackupInfo?
    @State private var exportURL: URL?

    private let service = BackupService()

    var body: some View {
        List {
            if backups.isEmpty {
                Text("No backups yet. Use “Back up collection” in Settings.").foregroundColor(.secondary)
            }
            ForEach(backups) { b in
                VStack(alignment: .leading, spacing: 4) {
                    Text(b.name).font(.callout)
                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(b.size), countStyle: .file)) · \(b.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundColor(.secondary)
                    HStack(spacing: 16) {
                        ShareLink("Share", item: b.url)
                        Button("Save to Files") { exportURL = b.url }
                    }.font(.caption)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { deleteTarget = b } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        .navigationTitle("Backups")
        .alert("Delete this backup?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let t = deleteTarget { try? service.delete(t); deleteTarget = nil; load() }
            }
        } message: {
            Text(deleteTarget?.name ?? "")
        }
        .fileExporter(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } }),
                      document: exportURL.map { ColpkgFile(url: $0) },
                      contentType: UTType(filenameExtension: "colpkg") ?? .data,
                      defaultFilename: exportURL?.deletingPathExtension().lastPathComponent) { _ in
            exportURL = nil
        }
        .task { load() }
    }

    private func load() { backups = (try? service.list()) ?? [] }
}
