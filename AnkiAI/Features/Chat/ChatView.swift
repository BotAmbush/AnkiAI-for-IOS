import SwiftUI

/// Shared chat surface for both reviewer chat ("Ask Claude") and the AI card
/// creator. Mirrors `fragment_ai_chat.xml` + `AiChatBottomSheetFragment`.
struct ChatView: View {
    @StateObject private var vm: AIChatViewModel
    @State private var input: String = ""

    init(viewModel: AIChatViewModel) {
        _vm = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !vm.hasAPIKey {
                APIKeyPrompt(vm: vm)
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
                            MessageBubble(message: message).id(message.id)
                        }
                        ForEach(vm.generationProposals) { proposal in
                            ProposalCard(proposal: proposal) {
                                Task { await vm.addCardFromProposal(proposal) }
                            } onDismiss: {
                                vm.removeGenerationProposal(proposal)
                            }
                        }
                    }
                    .padding()
                }
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
        .task { await vm.load() }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(vm.isCreatorMode ? "Describe what to learn…" : "Ask a question…", text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
            if vm.isLoading {
                ProgressView()
            } else {
                Button {
                    let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    input = ""
                    Task { await vm.sendMessage(text) }
                } label: {
                    Image(systemName: "paperplane.fill")
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !vm.hasAPIKey)
            }
        }
        .padding()
    }
}

private struct MessageBubble: View {
    let message: AIChatMessage
    var isUser: Bool { message.role == AIChatMessage.roleUser }
    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Text(message.content)
                .padding(10)
                .background(isUser ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 40) }
        }
    }
}

private struct ProposalCard: View {
    let proposal: CardProposal
    let onAdd: () -> Void
    let onDismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Proposed card → \(proposal.deckName)").font(.caption).foregroundColor(.secondary)
            CardWebView(html: proposal.front).frame(height: 90)
            Divider()
            CardWebView(html: proposal.back).frame(height: 120)
            HStack {
                Button("Add to deck", action: onAdd).buttonStyle(.borderedProminent)
                Button("Dismiss", action: onDismiss).buttonStyle(.bordered)
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
