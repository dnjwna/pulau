//
//  AssistantTabView.swift
//  boringNotch — Pulau fork
//
//  "Jarvis" in the notch: quick clipboard actions + a streaming chat.
//

import Defaults
import SwiftUI

struct AssistantTabView: View {
    @ObservedObject private var assistant = AssistantService.shared
    @Default(.assistantModel) private var model
    @State private var draft = ""

    private let quickActions: [QuickAction] = [
        QuickAction(title: "Summarize", icon: "text.alignleft", prompt: "Summarize the following text in 3 bullet points:"),
        QuickAction(title: "Explain", icon: "lightbulb", prompt: "Explain the following simply, as if to a smart beginner:"),
        QuickAction(title: "To English", icon: "character.bubble", prompt: "Translate the following into natural English. Output only the translation:"),
        QuickAction(title: "Fix grammar", icon: "wand.and.stars", prompt: "Fix grammar and spelling in the following text. Keep the original language and tone. Output only the corrected text:")
    ]

    var body: some View {
        HStack(alignment: .top, spacing: PulauTheme.gap) {
            actionsColumn
                .frame(width: 132)
            chatColumn
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Left

    private var actionsColumn: some View {
        PulauCard(padding: 8) {
            VStack(alignment: .leading, spacing: 4) {
                PulauSectionHeader(title: "Clipboard", systemImage: "doc.on.clipboard")
                ForEach(quickActions) { action in
                    QuickActionRow(title: action.title, icon: action.icon, disabled: assistant.isStreaming) {
                        assistant.runOnClipboard(action.prompt)
                    }
                }
            }
        }
    }

    // MARK: Right

    private var chatColumn: some View {
        PulauCard(padding: 8) {
            VStack(alignment: .leading, spacing: 6) {
                PulauSectionHeader(title: model, systemImage: "sparkles") {
                    HStack(spacing: 8) {
                        if assistant.messages.contains(where: { $0.role == .assistant && !$0.content.isEmpty }) {
                            headerButton("doc.on.doc", help: "Copy last reply") { assistant.copyLastReply() }
                        }
                        if !assistant.messages.isEmpty {
                            headerButton("arrow.counterclockwise", help: "New chat") { assistant.reset() }
                        }
                    }
                }

                conversation

                if let status = assistant.statusMessage {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        Text(status)
                            .font(PulauTheme.caption)
                            .foregroundStyle(PulauTheme.secondaryText)
                            .lineLimit(1)
                    }
                    .transition(.opacity)
                }

                HStack(spacing: 6) {
                    NotchTextField(placeholder: "Ask anything…", text: $draft, focusNotification: .pulauFocusAssistantInput, onSubmit: submit)
                    if assistant.isStreaming {
                        PulauIconButton(systemImage: "stop.fill", size: 22, help: "Stop") { assistant.stop() }
                    } else {
                        PulauIconButton(systemImage: "arrow.up", size: 22, prominent: !draft.isEmpty, help: "Send") { submit() }
                            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 3)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.35)))
            }
        }
    }

    @ViewBuilder
    private var conversation: some View {
        if let error = assistant.errorMessage {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text(error)
                    .font(PulauTheme.caption)
                    .foregroundStyle(PulauTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if assistant.messages.isEmpty {
            PulauEmptyState(
                systemImage: "sparkles",
                title: "How can I help?",
                subtitle: "Copy text, then pick a clipboard action"
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(assistant.messages) { message in
                            MessageBubble(message: message, streaming: assistant.isStreaming && message.id == assistant.messages.last?.id)
                                .id(message.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: assistant.messages.last?.content) { _, _ in
                    if let last = assistant.messages.last?.id {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func headerButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(PulauTheme.font(9.5, .semibold))
                .foregroundStyle(PulauTheme.secondaryText)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func submit() {
        let text = draft
        draft = ""
        assistant.send(text)
    }
}

private struct QuickAction: Identifiable {
    let title: String
    let icon: String
    let prompt: String
    var id: String { title }
}

private struct QuickActionRow: View {
    let title: String
    let icon: String
    let disabled: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(PulauTheme.font(10, .semibold))
                    .frame(width: 14)
                Text(title)
                    .font(PulauTheme.body)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(PulauTheme.primaryText.opacity(disabled ? 0.35 : 0.9))
            .padding(.vertical, 4)
            .padding(.horizontal, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(hovering && !disabled ? PulauTheme.hoverFill : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    let streaming: Bool

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 30) }
            content
                .font(PulauTheme.body)
                .foregroundStyle(message.role == .user ? Color.black : PulauTheme.primaryText.opacity(0.92))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(message.role == .user ? AnyShapeStyle(Color.white.opacity(0.9)) : AnyShapeStyle(Color.white.opacity(0.06)))
                )
            if message.role != .user { Spacer(minLength: 30) }
        }
    }

    @ViewBuilder
    private var content: some View {
        let visible = message.role == .assistant ? AssistantService.stripThinking(message.content) : message.content
        if visible.isEmpty && streaming {
            TypingDots()
        } else {
            Text(Self.markdown(visible))
        }
    }

    private static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private struct TypingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.3)) { timeline in
            let phase = Int(timeline.date.timeIntervalSinceReferenceDate / 0.3) % 3
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(i == phase ? 0.9 : 0.3))
                        .frame(width: 4, height: 4)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
