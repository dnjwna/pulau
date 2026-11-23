//
//  FocusTabView.swift
//  boringNotch — Pulau fork
//
//  Productivity island: Pomodoro · To-do · Clipboard history.
//

import Defaults
import SwiftUI

struct FocusTabView: View {
    var body: some View {
        HStack(spacing: PulauTheme.gap) {
            PomodoroCard()
                .frame(width: 170)
            TodoCard()
            ClipboardCard()
        }
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Pomodoro

private struct PomodoroCard: View {
    @ObservedObject private var timer = FocusTimer.shared

    var body: some View {
        PulauCard {
            VStack(alignment: .leading, spacing: 6) {
                PulauSectionHeader(title: timer.phase.title, systemImage: timer.phase.systemImage) {
                    Text("\(timer.completedToday) today")
                        .font(PulauTheme.font(9.5, .medium))
                        .foregroundStyle(PulauTheme.tertiaryText)
                }

                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 5)
                        Circle()
                            .trim(from: 0, to: max(0.001, timer.progress))
                            .stroke(ringColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.5), value: timer.progress)
                        Text(timer.formattedRemaining)
                            .font(PulauTheme.font(13, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(PulauTheme.primaryText)
                    }
                    .frame(width: 70, height: 70)

                    VStack(spacing: 6) {
                        PulauIconButton(
                            systemImage: timer.isRunning ? "pause.fill" : "play.fill",
                            size: 28, prominent: true,
                            help: timer.isRunning ? "Pause" : "Start"
                        ) { timer.toggle() }
                        HStack(spacing: 6) {
                            PulauIconButton(systemImage: "arrow.counterclockwise", size: 22, help: "Reset") { timer.reset() }
                            PulauIconButton(systemImage: "forward.end.fill", size: 22, help: "Skip phase") { timer.skip() }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                sessionDots
            }
        }
    }

    private var ringColor: Color {
        timer.phase == .work ? PulauTheme.accent : Color.green
    }

    private var sessionDots: some View {
        let total = max(1, Defaults[.pomodoroSessionsBeforeLongBreak])
        return HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i < timer.sessionsInCycle ? PulauTheme.accent : Color.white.opacity(0.12))
                    .frame(height: 3)
            }
        }
    }
}

// MARK: - To-do

private struct TodoCard: View {
    @Default(.pulauTodos) private var todos
    @State private var draft = ""

    var body: some View {
        PulauCard {
            VStack(alignment: .leading, spacing: 6) {
                PulauSectionHeader(title: "To-do", systemImage: "checklist") {
                    if todos.contains(where: \.isDone) {
                        Button("Clear done") {
                            withAnimation(PulauTheme.spring) { todos.removeAll(where: \.isDone) }
                        }
                        .buttonStyle(.plain)
                        .font(PulauTheme.font(9.5, .medium))
                        .foregroundStyle(PulauTheme.secondaryText)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(PulauTheme.font(10, .bold))
                        .foregroundStyle(PulauTheme.tertiaryText)
                    NotchTextField(placeholder: "Add a task", text: $draft, onSubmit: add)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.35)))

                if todos.isEmpty {
                    PulauEmptyState(systemImage: "checkmark.circle", title: "All clear")
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(sortedTodos) { item in
                                TodoRow(item: item, toggle: { toggle(item) }, delete: { delete(item) })
                            }
                        }
                    }
                }
            }
        }
    }

    private var sortedTodos: [TodoItem] {
        todos.filter { !$0.isDone } + todos.filter(\.isDone)
    }

    private func add() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        withAnimation(PulauTheme.spring) {
            todos.insert(TodoItem(title: title), at: 0)
        }
        draft = ""
    }

    private func toggle(_ item: TodoItem) {
        guard let i = todos.firstIndex(where: { $0.id == item.id }) else { return }
        withAnimation(PulauTheme.spring) { todos[i].isDone.toggle() }
    }

    private func delete(_ item: TodoItem) {
        withAnimation(PulauTheme.spring) { todos.removeAll { $0.id == item.id } }
    }
}

private struct TodoRow: View {
    let item: TodoItem
    let toggle: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggle) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(PulauTheme.font(12, .medium))
                    .foregroundStyle(item.isDone ? PulauTheme.accent : PulauTheme.secondaryText)
            }
            .buttonStyle(.plain)

            Text(item.title)
                .font(PulauTheme.body)
                .foregroundStyle(item.isDone ? PulauTheme.tertiaryText : PulauTheme.primaryText)
                .strikethrough(item.isDone, color: PulauTheme.tertiaryText)
                .lineLimit(1)

            Spacer(minLength: 0)

            if hovering {
                Button(action: delete) {
                    Image(systemName: "xmark")
                        .font(PulauTheme.font(9, .bold))
                        .foregroundStyle(PulauTheme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? PulauTheme.hoverFill : .clear))
        .onHover { hovering = $0 }
    }
}

// MARK: - Clipboard

private struct ClipboardCard: View {
    @ObservedObject private var clipboard = ClipboardMonitor.shared
    @Default(.clipboardHistoryEnabled) private var enabled
    @State private var copiedID: UUID?

    var body: some View {
        PulauCard {
            VStack(alignment: .leading, spacing: 6) {
                PulauSectionHeader(title: "Clipboard", systemImage: "doc.on.clipboard") {
                    if enabled && !clipboard.entries.isEmpty {
                        Button("Clear") { clipboard.clear() }
                            .buttonStyle(.plain)
                            .font(PulauTheme.font(9.5, .medium))
                            .foregroundStyle(PulauTheme.secondaryText)
                    }
                }

                if !enabled {
                    PulauEmptyState(systemImage: "eye.slash", title: "History is off", subtitle: "Enable it in Settings → Pulau")
                } else if clipboard.entries.isEmpty {
                    PulauEmptyState(systemImage: "doc.on.clipboard", title: "Copy something", subtitle: "Kept in memory only")
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(clipboard.entries) { entry in
                                ClipboardRow(entry: entry, copied: copiedID == entry.id) {
                                    clipboard.copy(entry)
                                    copiedID = clipboard.entries.first?.id
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                        copiedID = nil
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct ClipboardRow: View {
    let entry: ClipboardEntry
    let copied: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(entry.preview)
                    .font(PulauTheme.body)
                    .foregroundStyle(PulauTheme.primaryText.opacity(0.9))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: copied ? "checkmark" : "arrow.up.doc.on.clipboard")
                    .font(PulauTheme.font(9.5, .semibold))
                    .foregroundStyle(copied ? Color.green : PulauTheme.tertiaryText)
                    .opacity(hovering || copied ? 1 : 0)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? PulauTheme.hoverFill : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(entry.sourceApp.map { "Copied from \($0)" } ?? "Copy again")
    }
}
