//
//  AssistantService.swift
//  boringNotch — Pulau fork
//
//  Streaming chat against any OpenAI-compatible endpoint:
//  Ollama / LM Studio (free, local) by default, or Groq / OpenRouter / OpenAI
//  with a key stored in the Keychain.
//

import AppKit
import Defaults
import Foundation

struct ChatMessage: Identifiable, Equatable {
    enum Role: String { case system, user, assistant }
    let id = UUID()
    let role: Role
    var content: String
}

enum AssistantError: LocalizedError {
    case badURL
    case http(Int, String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Invalid base URL. Check Settings → Pulau."
        case .http(let code, let message):
            let base = message.isEmpty ? "Server returned HTTP \(code)." : "HTTP \(code): \(message)"
            if [429, 500, 502, 503, 504].contains(code) {
                return base + " Retried automatically — try again shortly, or switch model in Settings → Pulau."
            }
            return base
        case .emptyResponse:
            return "The model returned an empty response."
        }
    }
}

@MainActor
final class AssistantService: ObservableObject {
    static let shared = AssistantService()
    static let apiKeyAccount = "apiKey"

    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isStreaming = false
    @Published var errorMessage: String?
    /// Transient status shown while waiting (e.g. "Server busy — retrying").
    @Published private(set) var statusMessage: String?

    private var streamTask: Task<Void, Never>?

    private init() {}

    // MARK: Public API

    func send(_ text: String) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isStreaming else { return }

        errorMessage = nil
        messages.append(ChatMessage(role: .user, content: prompt))
        messages.append(ChatMessage(role: .assistant, content: ""))
        let replyID = messages[messages.count - 1].id
        let payloadMessages = buildPayloadMessages()

        isStreaming = true
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.stream(messages: payloadMessages) { chunk in
                    self.append(chunk, to: replyID)
                }
                if self.messages.last(where: { $0.id == replyID })?.content
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                    throw AssistantError.emptyResponse
                }
            } catch is CancellationError {
                // user stopped
            } catch let error as URLError where error.code == .cancelled {
                // user stopped
            } catch {
                self.errorMessage = Self.describe(error)
                self.messages.removeAll { $0.id == replyID && $0.content.isEmpty }
            }
            self.isStreaming = false
            self.streamTask = nil
        }
    }

    /// Runs a canned instruction over the current clipboard text.
    func runOnClipboard(_ instruction: String) {
        guard let text = ClipboardMonitor.shared.latestText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            errorMessage = "Clipboard is empty."
            return
        }
        let clipped = text.count > 8000 ? String(text.prefix(8000)) + "\n[truncated]" : text
        send("\(instruction)\n\n\"\"\"\n\(clipped)\n\"\"\"")
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    func reset() {
        stop()
        messages.removeAll()
        errorMessage = nil
    }

    func copyLastReply() {
        guard let reply = messages.last(where: { $0.role == .assistant })?.content, !reply.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(Self.stripThinking(reply), forType: .string)
    }

    // MARK: Models list (for Settings)

    static func fetchModels(baseURL: String, apiKey: String?) async throws -> [String] {
        guard let url = endpoint(baseURL, path: "models") else { throw AssistantError.badURL }
        var request = URLRequest(url: url, timeoutInterval: 6)
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw AssistantError.http(code, parseError(data)) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else { return [] }
        return list.compactMap { $0["id"] as? String }.sorted()
    }

    // MARK: Internals

    private func buildPayloadMessages() -> [[String: String]] {
        var payload: [[String: String]] = []
        let system = Defaults[.assistantSystemPrompt].trimmingCharacters(in: .whitespacesAndNewlines)
        if !system.isEmpty {
            payload.append(["role": "system", "content": system + "\nCurrent date: \(Date().formatted(date: .complete, time: .shortened))."])
        }
        // Keep the last N turns (user+assistant pairs), excluding the empty placeholder.
        let history = messages.dropLast().filter { !$0.content.isEmpty }
        let limit = max(1, Defaults[.assistantMaxHistoryTurns]) * 2
        for message in history.suffix(limit) {
            payload.append(["role": message.role.rawValue, "content": Self.stripThinking(message.content)])
        }
        return payload
    }

    private func append(_ chunk: String, to id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content += chunk
    }

    private func stream(messages: [[String: String]], onChunk: @escaping @MainActor (String) -> Void) async throws {
        guard let url = Self.endpoint(Defaults[.assistantBaseURL], path: "chat/completions") else {
            throw AssistantError.badURL
        }
        let model = Defaults[.assistantModel]
        let candidates = Self.reasoningCandidates(for: url, model: model)

        var index = 0
        var transientRetries = 0
        defer { statusMessage = nil }

        while index < candidates.count {
            let effort = candidates[index]
            do {
                try await streamOnce(url: url, effort: effort, messages: messages) { [weak self] chunk in
                    self?.statusMessage = nil
                    onChunk(chunk)
                }
                Self.workingEffort[model] = effort ?? Self.omitMarker
                return
            } catch AssistantError.http(let code, let message)
                where code == 400 && index < candidates.count - 1 && Self.isThinkingRejection(message) {
                // The model doesn't accept this thinking level; try the next one.
                NSLog("[Pulau] %@ rejected reasoning_effort=%@, retrying", model, effort ?? "(omitted)")
                index += 1
            } catch AssistantError.http(let code, _)
                where Self.transientStatusCodes.contains(code) && transientRetries < Self.maxTransientRetries {
                // Overloaded / rate-limited before any token arrived: safe to resend.
                transientRetries += 1
                let delay = 1.5 * Double(transientRetries)
                NSLog("[Pulau] HTTP %d from %@, retry %d/%d in %.1fs", code, model, transientRetries, Self.maxTransientRetries, delay)
                statusMessage = "Server busy (HTTP \(code)) — retrying \(transientRetries)/\(Self.maxTransientRetries)…"
                try await Task.sleep(for: .seconds(delay))
            }
        }
    }

    private static let transientStatusCodes: Set<Int> = [429, 500, 502, 503, 504]
    private static let maxTransientRetries = 2

    private func streamOnce(url: URL, effort: String?, messages: [[String: String]], onChunk: @escaping @MainActor (String) -> Void) async throws {
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let key = KeychainStore.read(Self.apiKeyAccount), !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        var body: [String: Any] = [
            "model": Defaults[.assistantModel],
            "messages": messages,
            "stream": true,
            "temperature": 0.6
        ]
        if let effort {
            body["reasoning_effort"] = effort
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let startedAt = Date()
        var loggedFirstToken = false

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard code == 200 else {
            var raw = Data()
            for try await byte in bytes {
                raw.append(byte)
                if raw.count > 16_000 { break }
            }
            throw AssistantError.http(code, Self.parseError(raw))
        }

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let error = json["error"] {
                throw AssistantError.http(code, Self.errorText(error))
            }
            if let choices = json["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any],
               let content = delta["content"] as? String, !content.isEmpty {
                if !loggedFirstToken {
                    loggedFirstToken = true
                    NSLog("[Pulau] first token after %.2fs (model: %@)", Date().timeIntervalSince(startedAt), Defaults[.assistantModel])
                }
                onChunk(content)
            }
        }
    }

    // MARK: Thinking level negotiation

    private static let effortLevels = ["minimal", "low", "medium", "high"]
    private static let omitMarker = "__omit__"
    /// Level that last worked per model (this app session), so retries happen once.
    private static var workingEffort: [String: String] = [:]

    /// Ordered `reasoning_effort` values to try; `nil` means "omit the parameter".
    /// Providers differ on which levels each model accepts, so we fall back on HTTP 400.
    static func reasoningCandidates(for url: URL, model: String) -> [String?] {
        let setting = Defaults[.assistantReasoningEffort].lowercased()
        if setting == "off" || setting.isEmpty { return [nil] }

        if let known = workingEffort[model] {
            return [known == omitMarker ? nil : known]
        }

        let isGemini = (url.host ?? "").contains("generativelanguage.googleapis.com")
        let start: String
        if setting == "auto" {
            // Fastest level first; non-Gemini providers get nothing in auto mode.
            guard isGemini else { return [nil] }
            start = "minimal"
        } else {
            start = setting
        }
        let from = effortLevels.firstIndex(of: start) ?? 0
        return effortLevels[from...].map { Optional($0) } + [nil]
    }

    private static func isThinkingRejection(_ message: String) -> Bool {
        let m = message.lowercased()
        return m.contains("thinking") || m.contains("reasoning")
    }

    /// Forget negotiated levels (e.g. after the user changes the setting).
    static func resetThinkingNegotiation() {
        workingEffort.removeAll()
    }

    static func endpoint(_ base: String, path: String) -> URL? {
        var trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty, let url = URL(string: "\(trimmed)/\(path)"),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    private static func parseError(_ data: Data) -> String {
        let json = try? JSONSerialization.jsonObject(with: data)
        if let dict = json as? [String: Any], let error = dict["error"] {
            return errorText(error)
        }
        if let list = json as? [[String: Any]], let error = list.first?["error"] {
            return errorText(error)
        }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(200)
            .description ?? ""
    }

    private static func errorText(_ error: Any) -> String {
        if let text = error as? String { return text }
        if let dict = error as? [String: Any], let message = dict["message"] as? String { return message }
        return "Unknown error"
    }

    private static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost:
                return "Can't reach the model server. Is Ollama running? (ollama serve)"
            case .timedOut:
                return "The model server timed out."
            case .notConnectedToInternet:
                return "You're offline."
            default:
                return urlError.localizedDescription
            }
        }
        return error.localizedDescription
    }

    /// Reasoning models (deepseek-r1, qwen3…) emit <think>…</think>; hide it.
    static func stripThinking(_ text: String) -> String {
        var result = text.replacingOccurrences(
            of: #"<think>[\s\S]*?</think>"#, with: "", options: .regularExpression
        )
        // Unclosed block while still streaming.
        if let open = result.range(of: "<think>") {
            result = String(result[..<open.lowerBound])
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
