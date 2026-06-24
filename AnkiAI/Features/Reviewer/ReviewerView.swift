import SwiftUI

/// Minimal reviewer surface for milestone 1: renders a card's front/back with
/// MathJax and exposes "Ask Claude". The scheduling/answer-button behaviour is
/// supplied by the Rust backend in milestone 2; this proves the AI + rendering
/// path end-to-end.
struct ReviewerView: View {
    @EnvironmentObject private var env: AppEnvironment
    let cardId: Int64

    @State private var showAnswer = false
    @State private var showChat = false
    @State private var front = ""
    @State private var back = ""

    var body: some View {
        VStack(spacing: 0) {
            CardWebView(html: showAnswer ? "\(front)<hr>\(back)" : front)
                .frame(maxHeight: .infinity)
            Divider()
            HStack {
                if !showAnswer {
                    Button("Show Answer") { showAnswer = true }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Ask Claude") { showChat = true }
                        .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showChat) {
            NavigationStack {
                ChatView(viewModel: env.makeChatViewModel(cardId: cardId))
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showChat = false }
                        }
                    }
            }
        }
        .task {
            if let ctx = try? await env.gateway.cardContext(cardId: cardId) {
                front = ctx.fields.first ?? ""
                back = ctx.fields.count > 1 ? ctx.fields[1] : ""
            }
        }
    }
}
