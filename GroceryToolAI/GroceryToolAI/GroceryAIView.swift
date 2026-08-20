import Foundation
import SwiftUI

struct GroceryAIView: View {
    @State private var messages: [GroceryAIMessage] = [
        GroceryAIMessage(role: .assistant, content: "Ask me about groceries, food storage, meal planning, receipt questions, shopping substitutions, or grocery budgeting.")
    ]
    @State private var draft = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if !GroceryAIService.isConfigured {
                Label("DeepSeek is not configured. Add your key to .deepseek-key and restart the app.", systemImage: "key.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.orange.opacity(0.10))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messages) { message in
                            messageBubble(message)
                                .id(message.id)
                        }
                        if isLoading {
                            HStack {
                                ProgressView()
                                Text("Thinking about groceries…").foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let id = messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask a grocery question", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .onSubmit { send() }
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.appBlue)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading || !GroceryAIService.isConfigured)
            }
            .padding()
            .background(.bar)
        }
        .background(Color.appBackground)
        .navigationTitle("Ask grocery AI")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func messageBubble(_ message: GroceryAIMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 48) }
            Text(message.content)
                .textSelection(.enabled)
                .padding(12)
                .foregroundStyle(message.role == .user ? .white : .primary)
                .background(message.role == .user ? Color.appBlue : Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
            if message.role == .assistant { Spacer(minLength: 48) }
        }
    }

    private func send() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isLoading else { return }
        draft = ""
        errorMessage = nil
        messages.append(GroceryAIMessage(role: .user, content: question))
        isLoading = true
        Task {
            do {
                let answer = try await GroceryAIService.answer(messages: messages)
                messages.append(GroceryAIMessage(role: .assistant, content: answer))
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

struct GroceryAIMessage: Identifiable, Equatable {
    enum Role: String { case user, assistant }
    let id = UUID()
    var role: Role
    var content: String
}

enum GroceryAIService {
    static var isConfigured: Bool { !apiKey.isEmpty }

    static func answer(messages: [GroceryAIMessage]) async throws -> String {
        guard !apiKey.isEmpty else { throw GroceryAIError.notConfigured }
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let conversation = messages.suffix(12).map { ["role": $0.role.rawValue, "content": $0.content] }
        let system = [
            "role": "system",
            "content": "You are GroceryTool AI. Answer only grocery-related questions: food shopping, prices, substitutions, nutrition basics, food safety and storage, meal planning, receipts, grocery budgets, and grocery-store comparisons. Politely decline unrelated requests. Be practical and concise. Do not claim live price or inventory knowledge unless the user supplies it. For medical dietary questions, provide general information and recommend professional advice when appropriate."
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "deepseek-v4-flash",
            "messages": [system] + conversation,
            "thinking": ["type": "disabled"],
            "max_tokens": 900,
            "stream": false
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GroceryAIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }?
                .flatMap { $0["message"] as? String }
            throw GroceryAIError.server(detail ?? "DeepSeek returned HTTP \(http.statusCode).")
        }
        let result = try JSONDecoder().decode(GroceryAIResponse.self, from: data)
        guard let answer = result.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines), !answer.isEmpty else {
            throw GroceryAIError.invalidResponse
        }
        return answer
    }

    private static var apiKey: String {
        ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private struct GroceryAIResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
    }
    let choices: [Choice]
}

private enum GroceryAIError: LocalizedError {
    case notConfigured
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "DeepSeek is not configured. Put your API key in .deepseek-key and restart the app."
        case .invalidResponse: "The grocery AI returned an invalid response."
        case .server(let message): message
        }
    }
}
