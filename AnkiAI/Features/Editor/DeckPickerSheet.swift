import SwiftUI

/// Pure, testable helpers for the deck picker (Issue 1).
public enum DeckPickerModel {
    /// The leaf (last) component, shown prominently.
    public static func leaf(_ name: String) -> String {
        name.components(separatedBy: "::").last ?? name
    }

    /// The full parent hierarchy as a breadcrumb, e.g. "Parent › Child". Empty for
    /// a top-level deck.
    public static func parentPath(_ name: String) -> String {
        let parts = name.components(separatedBy: "::")
        guard parts.count > 1 else { return "" }
        return parts.dropLast().joined(separator: " › ")
    }

    /// Case-insensitive substring match against the FULL path, so searching by a
    /// parent OR a child name works.
    public static func filter(_ decks: [DeckNameId], query: String) -> [DeckNameId] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return decks }
        return decks.filter { $0.name.lowercased().contains(q) }
    }
}

/// A discoverable, searchable deck selection sheet. The distinguishing leaf is
/// prominent; the complete parent path wraps over multiple lines (never truncated);
/// VoiceOver reads the full path; selection is clearly indicated.
struct DeckPickerSheet: View {
    let decks: [DeckNameId]
    @Binding var selectedId: Int64
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [DeckNameId] { DeckPickerModel.filter(decks, query: query) }

    var body: some View {
        NavigationStack {
            List(filtered) { deck in
                Button {
                    selectedId = deck.id
                    dismiss()
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(DeckPickerModel.leaf(deck.name))
                                .font(.body)
                                .foregroundColor(.primary)
                            let path = DeckPickerModel.parentPath(deck.name)
                            if !path.isEmpty {
                                Text(path)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)  // wrap, no truncation
                            }
                        }
                        Spacer(minLength: 8)
                        if deck.id == selectedId {
                            Image(systemName: "checkmark").foregroundColor(.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(deck.name)           // full path for VoiceOver
                .accessibilityAddTraits(deck.id == selectedId ? [.isSelected] : [])
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Search decks (parent or child)")
            .navigationTitle("Select deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
