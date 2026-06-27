import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Shared chat surface for both reviewer chat ("Ask Claude") and the AI card
/// creator. Mirrors `fragment_ai_chat.xml` + `AiChatBottomSheetFragment`.
struct ChatView: View {
    @StateObject private var vm: AIChatViewModel
    @State private var input: String = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var attachments: [ImagePayload] = []
    @State private var showPDFImporter = false
    @State private var loadingAttachment = false
    @State private var showClearConfirm = false
    @State private var decks: [DeckNameId] = []
    @State private var showDeckPicker = false
    @State private var deckSelection: Int64 = 0

    @Environment(\.scenePhase) private var scenePhase

    init(viewModel: AIChatViewModel) {
        _vm = StateObject(wrappedValue: viewModel)
    }

    private var composeIsRTL: Bool {
        TextDirection.isRTL(language: vm.language, text: vm.isCreatorMode ? vm.draft : input)
    }

    private var selectedDeckName: String {
        vm.selectedDeckPath ?? decks.first(where: { $0.id == vm.selectedDeckId })?.name ?? "Not selected"
    }

    var body: some View {
        VStack(spacing: 0) {
            if !vm.hasAPIKey {
                APIKeyPrompt(vm: vm)
            }
            if vm.isCreatorMode {
                CreatorDeckBar(vm: vm, decks: decks) { showDeckPicker = true }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if vm.isCreatorMode && vm.messages.isEmpty {
                            Text("Describe what you want to learn and Claude will generate flashcards.")
                                .foregroundColor(.secondary)
                                .padding()
                        }
                        ForEach(vm.messages) { message in
                            MessageBubble(message: message, language: vm.language).id(message.id)
                        }
                        ForEach(vm.generationProposals) { proposal in
                            ProposalCard(proposal: proposal,
                                         selectedDeckName: selectedDeckName,
                                         isDuplicate: vm.isDuplicate(proposal),
                                         modelDeckDiffers: vm.selectedDeckId != nil && proposal.deckId != vm.selectedDeckId) {
                                Task { await vm.addCardFromProposal(proposal) }
                            } onUseModelDeck: {
                                Task { await vm.addCardFromProposal(proposal, useModelDeck: true) }
                            } onDismiss: {
                                vm.removeGenerationProposal(proposal)
                            }
                        }
                        if vm.parseFailed {
                            ParseFailureBar(vm: vm)
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: vm.messages.count) { _ in
                    if let last = vm.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }

            if let edit = vm.pendingEditProposal {
                EditProposalBar(proposal: edit,
                                onApply: { Task { await vm.approveEditProposal(edit) } },
                                onDismiss: { vm.dismissEditProposal() })
            }
            if let add = vm.pendingAddCardProposal {
                AddProposalBar(proposal: add,
                               onApply: { Task { await vm.approveAddCardProposal(add) } },
                               onDismiss: { vm.dismissAddCardProposal() })
            }

            if let error = vm.error {
                Text(error).font(.footnote).foregroundColor(.red)
                    .padding(.horizontal).padding(.vertical, 4)
            }

            inputBar
        }
        .navigationTitle(vm.isCreatorMode ? "Create Cards with AI" : "Ask Claude")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Language", selection: Binding(get: { vm.language }, set: { vm.setLanguage($0) })) {
                        ForEach(AILanguage.allCases) { Text($0.displayName).tag($0) }
                    }
                    Divider()
                    Button(role: .destructive) { showClearConfirm = true } label: {
                        Label(vm.isCreatorMode ? "Clear session" : "Clear chat", systemImage: "trash")
                    }
                } label: {
                    Label("Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .top) {
            HStack(spacing: 10) {
                Label(vm.language.displayName, systemImage: "globe").font(.caption2)
                if vm.isCreatorMode {
                    Label("\(vm.generationProposals.count) pending", systemImage: "rectangle.stack").font(.caption2)
                    if !attachments.isEmpty { Label("\(attachments.count)", systemImage: "paperclip").font(.caption2) }
                }
                Spacer()
            }
            .foregroundColor(.secondary)
            .padding(.horizontal).padding(.vertical, 4)
            .background(.ultraThinMaterial)
        }
        .confirmationDialog("Clear session?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear session", role: .destructive) {
                vm.clearSession(); input = ""; attachments = []; photoItems = []
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the chat history, draft, attachments, and any unresolved generated-card proposals. Cards already added to your collection are NOT deleted.")
        }
        .sheet(isPresented: $showDeckPicker) {
            DeckPickerSheet(decks: decks, selectedId: $deckSelection)
        }
        .onChange(of: deckSelection) { id in
            if let d = decks.first(where: { $0.id == id }) { vm.setCreatorDeck(id: d.id, path: d.name) }
        }
        .alert("Duplicate card", isPresented: Binding(get: { vm.duplicatePending != nil }, set: { if !$0 { vm.dismissDuplicateWarning() } })) {
            Button("Add anyway", role: .destructive) {
                if let p = vm.duplicatePending { Task { await vm.confirmAddDuplicate(p) } }
            }
            Button("Cancel", role: .cancel) { vm.dismissDuplicateWarning() }
        } message: {
            Text("You already added an identical card to this deck in this session. Add it again?")
        }
        .alert("Create deck?", isPresented: Binding(get: { vm.pendingAddCardMissingDeck != nil }, set: { if !$0 { vm.dismissMissingDeck() } })) {
            Button("Create & add") { Task { await vm.confirmCreateMissingDeckAndAdd() } }
            Button("Cancel", role: .cancel) { vm.dismissMissingDeck() }
        } message: {
            Text("The deck “\(vm.pendingAddCardMissingDeck?.deckName ?? "")” doesn't exist yet. Create it and add the card, or cancel and adjust the proposal.")
        }
        .task {
            await vm.load()
            if vm.isCreatorMode {
                decks = await vm.creatorDecks()
                deckSelection = vm.selectedDeckId ?? 0
                attachments = vm.pendingAttachments   // reflect restored attachments
            }
        }
        .onDisappear { vm.persistSession() }
        .onChange(of: scenePhase) { phase in if phase != .active { vm.persistSession() } }
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if vm.isCreatorMode && vm.selectedDeckId == nil {
                Button { showDeckPicker = true } label: {
                    Label("Select a deck to generate cards", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundColor(.orange)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal)
            }
            if vm.isCreatorMode && (!attachments.isEmpty || loadingAttachment) {
                HStack(spacing: 6) {
                    if loadingAttachment { ProgressView().scaleEffect(0.8) }
                    Image(systemName: "paperclip")
                    Text("\(attachments.count) attachment\(attachments.count == 1 ? "" : "s")")
                        .font(.caption)
                    Button("Clear") { vm.attachFiles([]); attachments = []; photoItems = [] }.font(.caption)
                    Spacer()
                }
                .foregroundColor(.secondary)
                .padding(.horizontal)
            }
            HStack(spacing: 8) {
                if vm.isCreatorMode {
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 6, matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                    }
                    Button { showPDFImporter = true } label: { Image(systemName: "doc.fill") }
                }
                TextField(vm.isCreatorMode ? "Describe what to learn…" : "Ask a question…",
                          text: vm.isCreatorMode ? $vm.draft : $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .multilineTextAlignment(composeIsRTL ? .trailing : .leading)
                if vm.isLoading {
                    ProgressView()
                } else {
                    Button {
                        let source = vm.isCreatorMode ? vm.draft : input
                        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        if vm.isCreatorMode {
                            vm.draft = ""   // attachments are already persisted via attachFiles
                            Task { await vm.generateCards(text) }
                        } else {
                            input = ""
                            Task { await vm.sendMessage(text) }
                        }
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .disabled((vm.isCreatorMode ? vm.draft : input).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || !vm.hasAPIKey
                              || (vm.isCreatorMode && vm.selectedDeckId == nil))   // require a deck (Repair 1)
                }
            }
        }
        .padding()
        .onChange(of: photoItems) { items in
            Task {
                loadingAttachment = true
                var loaded: [ImagePayload] = []
                for item in items {
                    if let p = await AttachmentLoader.payload(from: item) { loaded.append(p) }
                }
                // Persist + validate now; failures (oversize/limit) surface via vm.error
                // and only successfully-stored attachments are kept.
                vm.attachFiles(loaded)
                attachments = vm.pendingAttachments
                loadingAttachment = false
            }
        }
        .fileImporter(isPresented: $showPDFImporter, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            loadingAttachment = true
            let pages = AttachmentLoader.pdfPayloads(from: url)
            vm.attachFiles(vm.pendingAttachments + pages)
            attachments = vm.pendingAttachments
            loadingAttachment = false
        }
    }
}

private struct MessageBubble: View {
    let message: AIChatMessage
    var language: AILanguage = .automatic
    var isUser: Bool { message.role == AIChatMessage.roleUser }
    private var isRTL: Bool { TextDirection.isRTL(language: language, text: message.content) }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Group {
                if isUser {
                    // User messages stay plain text, but use language-aware alignment.
                    Text(message.content)
                        .multilineTextAlignment(isRTL ? .trailing : .leading)
                        .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
                } else {
                    // Assistant messages render safe Markdown (Issue 4).
                    ChatMarkdownView(text: message.content, language: language)
                }
            }
            .padding(10)
            .background(isUser ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 40) }
        }
    }
}

/// Creator destination-deck banner (Repair 1).
private struct CreatorDeckBar: View {
    @ObservedObject var vm: AIChatViewModel
    let decks: [DeckNameId]
    let onPick: () -> Void
    var body: some View {
        Button(action: onPick) {
            HStack {
                Image(systemName: "tray.and.arrow.down")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Add to deck").font(.caption2).foregroundColor(.secondary)
                    Text(vm.selectedDeckPath.map { DeckPickerModel.leaf($0) } ?? "Choose a deck")
                        .font(.callout)
                    if let p = vm.selectedDeckPath, !DeckPickerModel.parentPath(p).isEmpty {
                        Text(DeckPickerModel.parentPath(p)).font(.caption2).foregroundColor(.secondary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal).padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(Color(.secondarySystemBackground))
    }
}

private struct ProposalCard: View {
    let proposal: CardProposal
    var selectedDeckName: String = ""
    var isDuplicate: Bool = false
    var modelDeckDiffers: Bool = false
    let onAdd: () -> Void
    var onUseModelDeck: () -> Void = {}
    let onDismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Proposed card → \(selectedDeckName.isEmpty ? proposal.deckName : selectedDeckName)")
                .font(.caption).foregroundColor(.secondary)
            if isDuplicate {
                Label("Looks like a card you already added this session.", systemImage: "exclamationmark.triangle")
                    .font(.caption2).foregroundColor(.orange)
            }
            CardWebView(html: proposal.front).frame(height: 90)
            Divider()
            CardWebView(html: proposal.back).frame(height: 120)
            HStack {
                Button("Add to deck", action: onAdd).buttonStyle(.borderedProminent)
                Button("Dismiss", action: onDismiss).buttonStyle(.bordered)
            }
            if modelDeckDiffers {
                Button("Use suggested deck “\(proposal.deckName)” instead", action: onUseModelDeck)
                    .font(.caption).buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct EditProposalBar: View {
    let proposal: EditProposal
    let onApply: () -> Void
    let onDismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Edit proposal — \(proposal.fieldName)").font(.caption.bold())
            CardWebView(html: proposal.newContent).frame(height: 100)
            HStack {
                Button("Apply edit", action: onApply).buttonStyle(.borderedProminent)
                Button("Dismiss", action: onDismiss).buttonStyle(.bordered)
            }
        }
        .padding().background(Color(.secondarySystemBackground))
    }
}

private struct AddProposalBar: View {
    let proposal: AddCardProposal
    let onApply: () -> Void
    let onDismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("New card → \(proposal.deckName)").font(.caption.bold())
            CardWebView(html: proposal.front).frame(height: 70)
            CardWebView(html: proposal.back).frame(height: 100)
            HStack {
                Button("Add to deck", action: onApply).buttonStyle(.borderedProminent)
                Button("Dismiss", action: onDismiss).buttonStyle(.bordered)
            }
        }
        .padding().background(Color(.secondarySystemBackground))
    }
}

/// Parse-failure recovery (Issue 5). The session is preserved; actions that cost a
/// paid API call are labelled.
private struct ParseFailureBar: View {
    @ObservedObject var vm: AIChatViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Couldn't read the response as cards", systemImage: "exclamationmark.triangle")
                .font(.caption.bold()).foregroundColor(.orange)
            Text("Your prompt and attachment are kept.").font(.caption2).foregroundColor(.secondary)
            HStack {
                Button("Try parsing again") { Task { await vm.tryParseAgain() } }.buttonStyle(.bordered)
                Button("Ask Claude to repair ($)") { Task { await vm.repairResponse() } }.buttonStyle(.bordered)
                Button("Regenerate ($)") { Task { await vm.regenerate() } }.buttonStyle(.bordered)
            }.font(.caption)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct APIKeyPrompt: View {
    @ObservedObject var vm: AIChatViewModel
    @State private var key = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connect Claude AI").font(.headline)
            Text("Enter your Claude API key to enable AI features.").font(.caption).foregroundColor(.secondary)
            HStack {
                SecureField("sk-ant-…", text: $key).textFieldStyle(.roundedBorder)
                Button("Connect") { vm.saveAPIKey(key); key = "" }
                    .disabled(key.isEmpty)
            }
        }
        .padding().background(Color(.secondarySystemBackground))
    }
}
