import Foundation

/// Native port of `ai/chat/AiChatViewModel.kt`.
///
/// Handles both modes:
///  - Reviewer chat (`cardId >= 0`): card-aware Q&A, edit/add-card proposals (Haiku).
///  - Creator mode (`cardId == -1`): freeform card generation into proposals (Sonnet).
///
/// Collection access goes through `CollectionGateway`; persistence through
/// `AIDatabase`; network through an injectable `clientFactory`.
@MainActor
public final class AIChatViewModel: ObservableObject {
    public let cardId: Int64
    public var isCreatorMode: Bool { cardId == -1 }
    public var sessionId: String { isCreatorMode ? "creator" : "card_\(cardId)" }

    @Published public private(set) var messages: [AIChatMessage] = []
    @Published public private(set) var isLoading = false
    @Published public var error: String?
    @Published public private(set) var cardContext: CardChatContext?
    @Published public private(set) var hasAPIKey: Bool
    @Published public private(set) var pendingEditProposal: EditProposal?
    @Published public private(set) var pendingAddCardProposal: AddCardProposal?
    @Published public private(set) var totalSpentUSD: Double
    @Published public private(set) var generationProposals: [CardProposal] = []
    @Published public private(set) var addedCount = 0

    private let gateway: CollectionGateway
    private let db: AIDatabase
    private let settings: AISettingsStore
    private let clientFactory: (_ apiKey: String, _ model: String) -> AIChatAPIClient

    public init(
        cardId: Int64,
        gateway: CollectionGateway,
        db: AIDatabase,
        settings: AISettingsStore = AISettingsStore(),
        clientFactory: @escaping (_ apiKey: String, _ model: String) -> AIChatAPIClient = { key, model in
            ClaudeAPIClient(apiKey: key, model: model)
        }
    ) {
        self.cardId = cardId
        self.gateway = gateway
        self.db = db
        self.settings = settings
        self.clientFactory = clientFactory
        self.hasAPIKey = settings.hasAPIKey
        self.totalSpentUSD = settings.totalSpentUSD
    }

    public func load() async {
        loadMessages()
        if !isCreatorMode { await loadCardContext() }
    }

    private func loadMessages() {
        messages = (try? db.messages(sessionId: sessionId)) ?? []
    }

    private func loadCardContext() async {
        do {
            guard let ctx = try await gateway.cardContext(cardId: cardId) else { return }
            let allDecks = try await gateway.allDecks()
            let deckName = allDecks.first { $0.id == ctx.deckId }?.name ?? "Default"
            let hierarchy = allDecks.map { "  - \($0.name)" }.joined(separator: "\n")
            let frontRaw = ctx.fields.first ?? ""
            let backRaw = ctx.fields.count > 1 ? ctx.fields[1] : ""
            cardContext = CardChatContext(
                cardId: cardId, noteId: ctx.noteId,
                front: HTMLText.stripHTML(frontRaw), back: HTMLText.stripHTML(backRaw),
                frontRaw: frontRaw, backRaw: backRaw,
                deckName: deckName, deckHierarchy: hierarchy,
                fieldNames: ["Front", "Back"])
        } catch {
            // Non-fatal: chat still works without context for plain questions.
        }
    }

    // MARK: - Sending

    public func sendMessage(_ userText: String) async {
        if isCreatorMode { await generateCards(userText); return }
        guard let apiKey = settings.apiKey else {
            error = "Please enter your Claude API key in Settings → AI Assistant."
            return
        }
        if cardContext == nil {
            // Context loads asynchronously when the chat opens; try to load it now.
            await loadCardContext()
        }
        guard cardContext != nil else {
            error = "Card context isn't ready yet — please try again in a moment."
            return
        }

        isLoading = true; error = nil
        try? db.insert(AIChatMessage(sessionId: sessionId, role: AIChatMessage.roleUser, content: userText))
        loadMessages()
        let history = textHistory()
        await callClaude(apiKey: apiKey, history: history)
        isLoading = false
    }

    public func requestEditProposal() async {
        guard let ctx = cardContext else { return }
        await dispatchSpecialRequest(Prompts.editProposalRequest(context: ctx))
    }

    public func requestAddCardProposal(userPrompt: String) async {
        guard let ctx = cardContext else { return }
        await dispatchSpecialRequest(Prompts.addCardProposalRequest(userPrompt: userPrompt, deckHierarchy: ctx.deckHierarchy))
    }

    private func dispatchSpecialRequest(_ systemRequestText: String) async {
        guard let apiKey = settings.apiKey, cardContext != nil else { return }
        isLoading = true; error = nil
        var history = textHistory()
        history.append(ChatTurn(role: AIChatMessage.roleUser, content: systemRequestText))
        await callClaude(apiKey: apiKey, history: history)
        isLoading = false
    }

    private func textHistory() -> [ChatTurn] {
        messages.filter { $0.messageType == AIChatMessage.typeText }
            .map { ChatTurn(role: $0.role, content: $0.content) }
    }

    private func callClaude(apiKey: String, history: [ChatTurn]) async {
        guard let ctx = cardContext else { return }
        let client = clientFactory(apiKey, ClaudeAPIClient.defaultChatModel)
        let result = await client.chat(
            systemPrompt: Prompts.reviewerSystemPrompt(context: ctx),
            history: history, dynamicSystemSuffix: "",
            onTokensUsed: { [weak self] usage in
                Task { @MainActor in self?.recordSpend(AIPricing.costHaiku(input: usage.inputTokens, output: usage.outputTokens)) }
            })
        switch result {
        case .success(let reply): await handleAssistantReply(reply, context: ctx)
        case .failure(let e): error = AIErrorPresenter.message(for: e)
        }
    }

    private func handleAssistantReply(_ reply: String, context ctx: CardChatContext) async {
        switch AIResponseParser.interpretReviewerReply(reply) {
        case .editCard(let fieldName, let newContent, let explanation):
            let fieldIndex = max(0, ctx.fieldNames.firstIndex { $0.caseInsensitiveCompare(fieldName) == .orderedSame } ?? 0)
            let oldContent = fieldIndex == 0 ? ctx.frontRaw : ctx.backRaw
            pendingEditProposal = EditProposal(noteId: ctx.noteId, fieldIndex: fieldIndex,
                                               fieldName: fieldName, oldContent: oldContent,
                                               newContent: newContent, explanation: explanation)
            insertAssistant("I've prepared an edit proposal for the **\(fieldName)** field. \(explanation)",
                            type: AIChatMessage.typeEditProposal)
        case .addCard(let front, let back, let deckName, let explanation):
            let deckId = (try? await gateway.resolveOrCreateDeck(name: deckName)) ?? 1
            pendingAddCardProposal = AddCardProposal(front: front, back: back, deckId: deckId,
                                                     deckName: deckName, explanation: explanation)
            insertAssistant("I've prepared a new card proposal for deck **\(deckName)**. \(explanation)",
                            type: AIChatMessage.typeAddCardProposal)
        case .text(let text):
            insertAssistant(text)
        }
    }

    private func insertAssistant(_ content: String, type: String = AIChatMessage.typeText, metadata: String = "") {
        try? db.insert(AIChatMessage(sessionId: sessionId, role: AIChatMessage.roleAssistant,
                                     content: content, messageType: type, metadata: metadata))
        loadMessages()
    }

    // MARK: - Proposals

    public func approveEditProposal(_ proposal: EditProposal) async {
        isLoading = true
        do {
            var note = try await gateway.note(id: proposal.noteId)
            if proposal.fieldIndex < note.fields.count {
                note.fields[proposal.fieldIndex] = proposal.newContent
                try await gateway.updateNote(note)
            }
            await loadCardContext()
            insertUser("✓ Edit applied to the **\(proposal.fieldName)** field.")
        } catch {
            self.error = "Failed to save edit: \(error.localizedDescription)"
        }
        pendingEditProposal = nil
        isLoading = false
    }

    public func dismissEditProposal() { pendingEditProposal = nil }

    public func approveAddCardProposal(_ proposal: AddCardProposal) async {
        isLoading = true
        do {
            let notetypeId: Int64
            if Self.containsCloze(proposal.front) || Self.containsCloze(proposal.back) {
                notetypeId = try await gateway.notetypeId(named: "Cloze")
            } else if let sourceNoteId = cardContext?.noteId,
                      let sourceNotetypeId = try? await gateway.note(id: sourceNoteId).notetypeId {
                notetypeId = sourceNotetypeId
            } else {
                notetypeId = try await gateway.basicNotetypeId()
            }
            _ = try await gateway.addNote(notetypeId: notetypeId, fields: [proposal.front, proposal.back], deckId: proposal.deckId)
            insertUser("✓ Card added to **\(proposal.deckName)**.")
        } catch {
            self.error = "Failed to add card: \(error.localizedDescription)"
        }
        pendingAddCardProposal = nil
        isLoading = false
    }

    public func dismissAddCardProposal() { pendingAddCardProposal = nil }

    /// True if the text contains Anki cloze syntax (`{{c1::…}}`), so the card
    /// should be created with the Cloze note type rather than Basic.
    nonisolated static func containsCloze(_ s: String) -> Bool {
        s.range(of: "\\{\\{c[0-9]+::", options: .regularExpression) != nil
    }

    private func insertUser(_ text: String) {
        try? db.insert(AIChatMessage(sessionId: sessionId, role: AIChatMessage.roleUser, content: text))
        loadMessages()
    }

    // MARK: - Creator mode

    public func generateCards(_ userPrompt: String, defaultDeckName: String = "",
                              attachments: [ImagePayload] = []) async {
        guard let apiKey = settings.apiKey else { error = "Please enter your API key first."; return }
        isLoading = true; error = nil; generationProposals = []
        do {
            let allDecks = try await gateway.allDecks()
            let hierarchy = allDecks.map { $0.name }.joined(separator: "\n")
            let resolvedDefault = defaultDeckName.isEmpty ? (allDecks.first?.name ?? "Default") : defaultDeckName
            let client = clientFactory(apiKey, ClaudeAPIClient.defaultCreatorModel)
            let userMessage = Prompts.creatorUserMessage(userPrompt: userPrompt, attachmentCount: attachments.count)
            let result = await client.chatWithImages(
                systemPrompt: Prompts.creatorStaticSystemPrompt(),
                history: [ChatTurnWithImage(role: "user", text: userMessage, images: attachments)],
                dynamicSystemSuffix: Prompts.creatorDynamicSystemSuffix(deckHierarchy: hierarchy, defaultDeck: resolvedDefault),
                onTokensUsed: { [weak self] usage in
                    Task { @MainActor in self?.recordSpend(AIPricing.costSonnet(input: usage.inputTokens, output: usage.outputTokens)) }
                })
            switch result {
            case .success(let reply): try await parseGenerationProposals(reply, allDecks: allDecks)
            case .failure(let e): error = AIErrorPresenter.message(for: e)
            }
        } catch {
            self.error = AIErrorPresenter.message(for: .underlying("\(error)"))
        }
        isLoading = false
    }

    private func parseGenerationProposals(_ reply: String, allDecks: [DeckNameId]) async throws {
        guard let raw = AIResponseParser.parseGeneratedCards(reply) else {
            error = "Could not parse Claude response as card list."; return
        }
        generationProposals = raw.map { card in
            let deckId = resolveDeckId(card.deckName, in: allDecks)
            return CardProposal(front: card.front, back: card.back, deckName: card.deckName, deckId: deckId)
        }
    }

    /// Port of the deck-resolution fallback chain in `parseGenerationProposals`.
    private func resolveDeckId(_ deckName: String, in all: [DeckNameId]) -> Int64 {
        if let exact = all.first(where: { $0.name.caseInsensitiveCompare(deckName) == .orderedSame }) { return exact.id }
        if let suffix = all.first(where: { $0.name.lowercased().hasSuffix("::\(deckName.lowercased())") }) { return suffix.id }
        if let contains = all.first(where: { $0.name.lowercased().contains(deckName.lowercased()) }) { return contains.id }
        return all.first?.id ?? 1
    }

    public func addCardFromProposal(_ proposal: CardProposal) async {
        isLoading = true
        do {
            let cloze = Self.containsCloze(proposal.front) || Self.containsCloze(proposal.back)
            let notetypeId = cloze
                ? try await gateway.notetypeId(named: "Cloze")
                : try await gateway.basicNotetypeId()
            _ = try await gateway.addNote(notetypeId: notetypeId, fields: [proposal.front, proposal.back], deckId: proposal.deckId)
            addedCount += 1
            generationProposals.removeAll { $0.id == proposal.id }
        } catch {
            self.error = "Failed to add card: \(error.localizedDescription)"
        }
        isLoading = false
    }

    public func removeGenerationProposal(_ proposal: CardProposal) {
        generationProposals.removeAll { $0.id == proposal.id }
    }

    // MARK: - Settings / spend

    public func saveAPIKey(_ key: String) {
        settings.apiKey = key
        hasAPIKey = settings.hasAPIKey
    }

    public func clearAPIKey() {
        settings.apiKey = nil
        hasAPIKey = false
    }

    public func clearSession() {
        try? db.deleteSession(sessionId)
        messages = []
    }

    public func clearError() { error = nil }

    public var budgetLimit: Double { settings.budgetLimitUSD }

    public func resetSpending() {
        settings.totalSpentUSD = 0
        totalSpentUSD = 0
    }

    private func recordSpend(_ amount: Double) {
        let newTotal = settings.totalSpentUSD + amount
        settings.totalSpentUSD = newTotal
        totalSpentUSD = newTotal
    }
}
