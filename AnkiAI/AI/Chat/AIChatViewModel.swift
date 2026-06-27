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
    /// Output language for this chat (overrides the global default; persisted).
    @Published public var language: AILanguage = .automatic
    /// The in-progress prompt draft (persisted for the creator session).
    @Published public var draft: String = ""
    /// Human-readable reasons for cards skipped during parsing (partial-success).
    @Published public private(set) var skippedCards: [String] = []
    /// True when the last generation produced a response we could not parse — the
    /// session is preserved and the user can retry/repair/regenerate.
    @Published public private(set) var parseFailed = false
    /// The creator's chosen destination deck (Repair 1), persisted + restored.
    @Published public private(set) var selectedDeckId: Int64?
    @Published public private(set) var selectedDeckPath: String?
    /// Restored attachment count for the UI (Repair 2 — from persisted refs).
    @Published public private(set) var attachmentCount = 0
    /// A proposal awaiting explicit confirmation because it duplicates an already
    /// accepted card this session (Repair 3).
    @Published public var duplicatePending: CardProposal?
    /// A reviewer add-card proposal whose deck does not exist yet — awaiting the
    /// user's explicit decision to create it or pick another (Repair 2).
    @Published public var pendingAddCardMissingDeck: AddCardProposal?

    // Preserved for retry without re-calling the API (Issue 5).
    private var lastRawResponse: String?
    private var lastPrompt: String?
    private var lastAttachments: [ImagePayload] = []
    private var attachmentRefs: [CreatorAttachmentRef] = []
    private var repairAttempted = false
    /// Fingerprints of cards already inserted this session (Repair 3).
    private var acceptedFingerprints: Set<String> = []

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
        self.language = settings.aiLanguage
    }

    /// Change the chat's output language and persist it as the new default (Issue 2).
    public func setLanguage(_ lang: AILanguage) {
        language = lang
        settings.aiLanguage = lang
        persistSession()
    }

    public func load() async {
        loadMessages()
        if isCreatorMode { restoreCreatorSession(); await revalidateSelectedDeck() }
        if !isCreatorMode { await loadCardContext() }
    }

    /// After relaunch, confirm the restored creator deck still exists; clear it (so
    /// the user must reselect) if it was deleted (Repair 1).
    private func revalidateSelectedDeck() async {
        guard let id = selectedDeckId else { return }
        let decks = await currentDecks()
        if !decks.contains(where: { $0.id == id }) {
            selectedDeckId = nil
            selectedDeckPath = nil
            persistSession()
        }
    }

    // MARK: - Creator session persistence (Issue 3)

    private func restoreCreatorSession() {
        guard let s = CreatorSessionStore.load(sessionId: sessionId) else { return }
        draft = s.draft
        language = AILanguage(rawValue: s.language) ?? language
        addedCount = s.addedCount
        parseFailed = s.parseFailed
        repairAttempted = s.repairAttempted
        lastRawResponse = s.rawResponse
        lastPrompt = s.lastPrompt
        selectedDeckId = s.selectedDeckId
        selectedDeckPath = s.selectedDeckPath
        acceptedFingerprints = Set(s.acceptedFingerprints)
        generationProposals = s.proposals.map {
            CardProposal(front: $0.front, back: $0.back, deckName: $0.deckName, deckId: $0.deckId)
        }
        // Validate + load attachment files; drop any whose file is missing/corrupt so
        // refs, payloads and count stay in sync with what is actually on disk.
        var loadedRefs: [CreatorAttachmentRef] = []
        var loadedPayloads: [ImagePayload] = []
        for ref in s.attachments {
            if let payload = try? CreatorAttachmentStore.load(ref: ref, sessionId: sessionId) {
                loadedRefs.append(ref); loadedPayloads.append(payload)
            }
        }
        attachmentRefs = loadedRefs
        lastAttachments = loadedPayloads
        attachmentCount = loadedPayloads.count
        // Note: the deck list is intentionally NOT persisted — it is re-resolved
        // from the live backend before any add/retry/repair.
    }

    /// Persist the unfinished creator session after every meaningful change.
    /// Stores ONLY attachment metadata (bytes are in scoped files).
    public func persistSession() {
        guard isCreatorMode else { return }
        let snapshot = PersistedCreatorSession(
            draft: draft,
            language: language.rawValue,
            addedCount: addedCount,
            parseFailed: parseFailed,
            repairAttempted: repairAttempted,
            rawResponse: lastRawResponse,
            lastPrompt: lastPrompt,
            selectedDeckId: selectedDeckId,
            selectedDeckPath: selectedDeckPath,
            proposals: generationProposals.map {
                PersistedProposal(front: $0.front, back: $0.back, deckName: $0.deckName, deckId: $0.deckId)
            },
            attachments: attachmentRefs,
            acceptedFingerprints: Array(acceptedFingerprints))
        CreatorSessionStore.save(snapshot, sessionId: sessionId)
    }

    // MARK: - Creator deck selection (Repair 1)

    /// Set the creator destination deck (persisted + restored).
    public func setCreatorDeck(id: Int64, path: String) {
        selectedDeckId = id
        selectedDeckPath = path
        persistSession()
    }

    /// Persist attachments to scoped files (Repair 2/3). THROWS on the first
    /// validation/write failure so the UI can surface it; only successfully-stored
    /// attachments are kept and later sent (a failed attachment is never silently
    /// kept or presented as persisted). `attachmentCount` always matches what is
    /// actually on disk.
    public func setAttachments(_ payloads: [ImagePayload]) throws {
        CreatorAttachmentStore.clear(sessionId: sessionId)
        var refs: [CreatorAttachmentRef] = []
        var stored: [ImagePayload] = []
        defer {
            attachmentRefs = refs
            lastAttachments = stored
            attachmentCount = stored.count
            persistSession()
        }
        for p in payloads {
            let ref = try CreatorAttachmentStore.save(payload: p, sessionId: sessionId)
            refs.append(ref); stored.append(p)
        }
    }

    /// Non-throwing wrapper for the UI: persists attachments and, on failure,
    /// surfaces an actionable message (with the exact limit) without silently
    /// keeping the failed one. Returns true on full success.
    @discardableResult
    public func attachFiles(_ payloads: [ImagePayload]) -> Bool {
        do { try setAttachments(payloads); return true }
        catch { self.error = Self.attachmentErrorMessage(error); return false }
    }

    static func attachmentErrorMessage(_ error: Error) -> String {
        let perFileMB = CreatorAttachmentStore.maxFileBytes / 1_048_576
        let perSessionMB = CreatorAttachmentStore.maxSessionBytes / 1_048_576
        switch error as? CreatorAttachmentError {
        case .tooLarge: return "That attachment is too large (limit \(perFileMB) MB per file). Remove it and try again."
        case .sessionTooLarge: return "Attachments exceed the per-session limit (\(perSessionMB) MB total). Remove some and try again."
        case .writeFailed: return "Couldn't save an attachment to disk. Retry or remove it."
        case .decodeFailed: return "An attachment couldn't be read. Remove it and try again."
        case .some(let e): return "Attachment error: \(e)"
        case .none: return "Attachment error: \(error.localizedDescription)"
        }
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
            systemPrompt: Prompts.reviewerSystemPrompt(context: ctx, language: language),
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
            // Do NOT resolve or create the deck here — that happens only at approval,
            // with explicit confirmation if the deck is missing (no deck-id-1 default).
            pendingAddCardProposal = AddCardProposal(front: front, back: back,
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

    /// Approve a reviewer add-card proposal. The deck is resolved ONLY now (never
    /// before approval): an existing deck by name is used; a missing deck requires
    /// explicit confirmation (`createIfMissing`) or an `overrideDeckId` the user
    /// picked. Never creates/mutates before approval and never defaults to deck 1.
    public func approveAddCardProposal(_ proposal: AddCardProposal,
                                       createIfMissing: Bool = false,
                                       overrideDeckId: Int64? = nil) async {
        isLoading = true
        do {
            let decks = try await gateway.allDecks()
            let targetDeckId: Int64
            if let override = overrideDeckId {
                guard decks.contains(where: { $0.id == override }) else {
                    error = "The chosen deck no longer exists — pick another."
                    isLoading = false; return
                }
                targetDeckId = override
            } else if let existing = decks.first(where: { $0.name.caseInsensitiveCompare(proposal.deckName) == .orderedSame }) {
                targetDeckId = existing.id
            } else if createIfMissing {
                targetDeckId = try await gateway.resolveOrCreateDeck(name: proposal.deckName)
            } else {
                // Missing deck — ask the user; do NOT mutate or default to deck 1.
                pendingAddCardMissingDeck = proposal
                isLoading = false; return
            }

            let notetypeId: Int64
            if Self.containsCloze(proposal.front) || Self.containsCloze(proposal.back) {
                notetypeId = try await gateway.notetypeId(named: "Cloze")
            } else if let sourceNoteId = cardContext?.noteId,
                      let sourceNotetypeId = try? await gateway.note(id: sourceNoteId).notetypeId {
                notetypeId = sourceNotetypeId
            } else {
                notetypeId = try await gateway.basicNotetypeId()
            }
            _ = try await gateway.addNote(notetypeId: notetypeId, fields: [proposal.front, proposal.back], deckId: targetDeckId)
            let landed = decks.first { $0.id == targetDeckId }?.name ?? proposal.deckName
            insertUser("✓ Card added to **\(landed)**.")
            pendingAddCardProposal = nil
            pendingAddCardMissingDeck = nil
        } catch {
            self.error = "Failed to add card: \(error.localizedDescription)"
        }
        isLoading = false
    }

    /// Confirm creating the missing proposed deck, then add the card there.
    public func confirmCreateMissingDeckAndAdd() async {
        guard let proposal = pendingAddCardMissingDeck else { return }
        pendingAddCardMissingDeck = nil
        await approveAddCardProposal(proposal, createIfMissing: true)
    }

    /// Add the pending reviewer proposal to a user-chosen EXISTING deck instead.
    public func addProposalToExistingDeck(_ deckId: Int64) async {
        guard let proposal = pendingAddCardMissingDeck ?? pendingAddCardProposal else { return }
        pendingAddCardMissingDeck = nil
        await approveAddCardProposal(proposal, overrideDeckId: deckId)
    }

    public func dismissMissingDeck() { pendingAddCardMissingDeck = nil }

    public func dismissAddCardProposal() { pendingAddCardProposal = nil; pendingAddCardMissingDeck = nil }

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

    /// Re-resolve the live deck list from the backend (never persisted/stale).
    private func currentDecks() async -> [DeckNameId] {
        (try? await gateway.allDecks()) ?? []
    }

    /// Live deck list for the creator deck picker (re-resolved from the backend).
    public func creatorDecks() async -> [DeckNameId] { await currentDecks() }

    /// Restored/pending attachments (loaded from scoped files) for UI display.
    public var pendingAttachments: [ImagePayload] { lastAttachments }

    public func generateCards(_ userPrompt: String, attachments: [ImagePayload]? = nil) async {
        guard let apiKey = settings.apiKey else { error = "Please enter your API key first."; return }
        // Require an explicit, still-existing destination deck — NEVER fall back to
        // the first/Default deck (Repair 1).
        guard let deckId = selectedDeckId, let deckPath = selectedDeckPath else {
            error = "Select a destination deck before generating cards."
            return
        }
        let allDecks = await currentDecks()
        guard allDecks.contains(where: { $0.id == deckId }) else {
            selectedDeckId = nil; selectedDeckPath = nil; persistSession()
            error = "Your selected deck no longer exists — choose another deck."
            return
        }
        if let attachments {
            // Surface attachment persistence/size failures; don't proceed silently.
            do { try setAttachments(attachments) }
            catch { self.error = Self.attachmentErrorMessage(error); return }
        }
        isLoading = true; error = nil; generationProposals = []; skippedCards = []; parseFailed = false
        repairAttempted = false
        lastPrompt = userPrompt
        persistSession()
        do {
            let hierarchy = allDecks.map { $0.name }.joined(separator: "\n")
            let client = clientFactory(apiKey, ClaudeAPIClient.defaultCreatorModel)
            let userMessage = Prompts.creatorUserMessage(userPrompt: userPrompt, attachmentCount: lastAttachments.count)
            let result = await client.chatWithImages(
                systemPrompt: Prompts.creatorStaticSystemPrompt(),
                history: [ChatTurnWithImage(role: "user", text: userMessage, images: lastAttachments)],
                dynamicSystemSuffix: Prompts.creatorDynamicSystemSuffix(deckHierarchy: hierarchy, defaultDeck: deckPath,
                                                                        language: language),
                onTokensUsed: { [weak self] usage in
                    Task { @MainActor in self?.recordSpend(AIPricing.costSonnet(input: usage.inputTokens, output: usage.outputTokens)) }
                })
            switch result {
            case .success(let reply):
                lastRawResponse = reply
                applyParse(reply, allDecks: allDecks)
            case .failure(let e):
                error = AIErrorPresenter.message(for: e)
            }
        } catch {
            self.error = AIErrorPresenter.message(for: .underlying("\(error)"))
        }
        isLoading = false
    }

    /// Re-parse the LAST raw response locally — no API call, no cost. Re-resolves
    /// the live deck list first (Repair 2 — never uses a stale persisted list).
    public func tryParseAgain() async {
        guard let reply = lastRawResponse else { return }
        applyParse(reply, allDecks: await currentDecks())
    }

    /// Ask Claude ONCE to repair its previous response into valid JSON. This is a
    /// paid API call (recorded in spend); allowed at most once per failure.
    public func repairResponse() async {
        guard !repairAttempted, let apiKey = settings.apiKey, let raw = lastRawResponse else { return }
        repairAttempted = true; persistSession()
        isLoading = true; error = nil
        let client = clientFactory(apiKey, ClaudeAPIClient.defaultCreatorModel)
        let result = await client.chat(
            systemPrompt: Prompts.repairSystemPrompt(),
            history: [ChatTurn(role: AIChatMessage.roleUser, content: Prompts.repairUserMessage(brokenResponse: raw))],
            dynamicSystemSuffix: "",
            onTokensUsed: { [weak self] usage in
                Task { @MainActor in self?.recordSpend(AIPricing.costSonnet(input: usage.inputTokens, output: usage.outputTokens)) }
            })
        switch result {
        case .success(let reply): lastRawResponse = reply; applyParse(reply, allDecks: await currentDecks())
        case .failure(let e): error = AIErrorPresenter.message(for: e)
        }
        isLoading = false
    }

    /// Regenerate from the preserved prompt + attachments (a fresh paid call). The
    /// accepted-card ledger is preserved so it can't recreate accepted duplicates.
    public func regenerate() async {
        guard let prompt = lastPrompt else { return }
        await generateCards(prompt)   // attachments already persisted; lastAttachments reused
    }

    private func applyParse(_ reply: String, allDecks: [DeckNameId]) {
        guard let outcome = AIResponseParser.parseGeneratedCards(reply) else {
            parseFailed = true
            // Sanitized diagnostics only (never the card content).
            AIDiagnostics.log(stage: "parse-failed", model: ClaudeAPIClient.defaultCreatorModel,
                              responseLength: reply.count, recovered: 0)
            error = "Could not parse Claude's response as a card list. Your prompt and attachment are kept — try parsing again, ask Claude to repair it, or regenerate."
            persistSession()
            return
        }
        parseFailed = false
        skippedCards = outcome.skipped
        generationProposals = outcome.cards.map { card in
            // Resolve the model's deck; if it doesn't match, fall back to the user's
            // SELECTED deck (never silently to allDecks.first).
            let resolved = resolveDeckId(card.deckName, in: allDecks)
            let deckId = resolved ?? (selectedDeckId ?? 0)
            let deckName = allDecks.first { $0.id == deckId }?.name ?? card.deckName
            return CardProposal(front: card.front, back: card.back, deckName: deckName, deckId: deckId)
        }
        AIDiagnostics.log(stage: outcome.stage, model: ClaudeAPIClient.defaultCreatorModel,
                          responseLength: reply.count, recovered: outcome.cards.count)
        if !outcome.skipped.isEmpty {
            error = "Added \(outcome.cards.count) card(s); \(outcome.skipped.count) could not be read: " + outcome.skipped.joined(separator: "; ")
        }
        persistSession()
    }

    /// Resolve a model-supplied deck name to a real deck id, or nil if none match
    /// (NEVER silently `allDecks.first`).
    private func resolveDeckId(_ deckName: String, in all: [DeckNameId]) -> Int64? {
        if let exact = all.first(where: { $0.name.caseInsensitiveCompare(deckName) == .orderedSame }) { return exact.id }
        if let suffix = all.first(where: { $0.name.lowercased().hasSuffix("::\(deckName.lowercased())") }) { return suffix.id }
        if let contains = all.first(where: { $0.name.lowercased().contains(deckName.lowercased()) }) { return contains.id }
        return nil
    }

    /// Add a generated card. By default it goes to the user's SELECTED creator deck;
    /// pass `useModelDeck` to honor the model's suggested deck instead. Verifies the
    /// deck still exists, and suppresses duplicates of already-accepted cards unless
    /// `allowDuplicate` is set (Repairs 1 + 3).
    public func addCardFromProposal(_ proposal: CardProposal, useModelDeck: Bool = false,
                                    allowDuplicate: Bool = false) async {
        // The destination is ALWAYS an explicit deck: the user's selected creator
        // deck by default, or the model's deck only when the user explicitly chose
        // it. Never the first/Default deck (Repair 1).
        let targetDeckId: Int64
        if useModelDeck {
            guard proposal.deckId != 0 else {
                error = "The suggested deck couldn't be resolved — choose a deck."; return
            }
            targetDeckId = proposal.deckId
        } else {
            guard let selected = selectedDeckId else {
                error = "Select a destination deck before adding cards."; return
            }
            targetDeckId = selected
        }
        isLoading = true
        do {
            let decks = await currentDecks()
            guard decks.contains(where: { $0.id == targetDeckId }) else {
                error = "That deck no longer exists — please choose another deck."
                isLoading = false; return
            }
            let cloze = Self.containsCloze(proposal.front) || Self.containsCloze(proposal.back)
            let fp = Self.fingerprint(proposal, deckId: targetDeckId)
            if acceptedFingerprints.contains(fp), !allowDuplicate {
                duplicatePending = proposal           // require explicit override
                isLoading = false; return
            }
            let notetypeId = cloze
                ? try await gateway.notetypeId(named: "Cloze")
                : try await gateway.basicNotetypeId()

            _ = try await gateway.addNote(notetypeId: notetypeId, fields: [proposal.front, proposal.back], deckId: targetDeckId)
            acceptedFingerprints.insert(fp)           // record ONLY after success
            addedCount += 1
            duplicatePending = nil
            generationProposals.removeAll { $0.id == proposal.id }
            persistSession()
        } catch {
            self.error = "Failed to add card: \(error.localizedDescription)"
        }
        isLoading = false
    }

    /// Confirm adding a card that duplicates an already-accepted one.
    public func confirmAddDuplicate(_ proposal: CardProposal, useModelDeck: Bool = false) async {
        await addCardFromProposal(proposal, useModelDeck: useModelDeck, allowDuplicate: true)
    }

    public func dismissDuplicateWarning() { duplicatePending = nil }

    /// Stable per-session fingerprint: a cloze/basic type discriminator + target
    /// deck + normalized fields (so HTML/whitespace-only differences don't matter).
    nonisolated static func fingerprint(_ proposal: CardProposal, deckId: Int64) -> String {
        let cloze = containsCloze(proposal.front) || containsCloze(proposal.back)
        return CardFingerprint.make(notetypeId: cloze ? -2 : -1, deckId: deckId,
                                    fields: [proposal.front, proposal.back])
    }

    /// True if this proposal would duplicate a card already accepted this session.
    public func isDuplicate(_ proposal: CardProposal) -> Bool {
        acceptedFingerprints.contains(Self.fingerprint(proposal, deckId: selectedDeckId ?? proposal.deckId))
    }

    public func removeGenerationProposal(_ proposal: CardProposal) {
        generationProposals.removeAll { $0.id == proposal.id }
        persistSession()
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

    /// Clear the chat + unfinished creator session (messages, draft state,
    /// proposals, parse-failure state). Cards already added to the collection are
    /// NOT removed. Persisted creator state is cleared too.
    public func clearSession() {
        try? db.deleteSession(sessionId)
        messages = []
        generationProposals = []
        skippedCards = []
        parseFailed = false
        lastRawResponse = nil
        lastPrompt = nil
        lastAttachments = []
        attachmentRefs = []
        attachmentCount = 0
        repairAttempted = false
        duplicatePending = nil
        acceptedFingerprints = []
        // Keep the selected deck (a stable user preference) across a session clear.
        CreatorSessionStore.clear(sessionId: sessionId)   // also deletes scoped attachment files
        persistSession()                                  // re-persist the kept deck (creator only)
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
