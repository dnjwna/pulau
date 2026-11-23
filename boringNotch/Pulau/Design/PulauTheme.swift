//
//  PulauTheme.swift
//  boringNotch — Pulau fork
//
//  One small design system so every Pulau view looks consistent:
//  rounded type, soft glass cards, a single accent, generous spacing.
//

import SwiftUI

enum PulauTheme {
    // MARK: Spacing / shape
    static let gap: CGFloat = 8
    static let cardRadius: CGFloat = 14
    static let chipRadius: CGFloat = 9
    static let cardPadding: CGFloat = 10

    // MARK: Colors (the notch is always dark)
    static let cardFill = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.08)
    static let hoverFill = Color.white.opacity(0.10)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.32)

    static var accent: Color { .effectiveAccent }

    // MARK: Type
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let title = font(13, .semibold)
    static let body = font(12, .regular)
    static let caption = font(10.5, .medium)
    static let mono = Font.system(size: 12, weight: .regular, design: .monospaced)

    static let spring = Animation.spring(response: 0.35, dampingFraction: 0.82)
}

// MARK: - Card

struct PulauCard<Content: View>: View {
    var padding: CGFloat = PulauTheme.cardPadding
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: PulauTheme.cardRadius, style: .continuous)
                    .fill(PulauTheme.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PulauTheme.cardRadius, style: .continuous)
                    .strokeBorder(PulauTheme.cardStroke, lineWidth: 0.5)
            )
    }
}

// MARK: - Section header

struct PulauSectionHeader<Trailing: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(PulauTheme.font(10, .semibold))
                .foregroundStyle(PulauTheme.secondaryText)
            Text(title.uppercased())
                .font(PulauTheme.font(9.5, .semibold))
                .kerning(0.6)
                .foregroundStyle(PulauTheme.secondaryText)
            Spacer(minLength: 0)
            trailing()
        }
    }
}

extension PulauSectionHeader where Trailing == EmptyView {
    init(title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
        self.trailing = { EmptyView() }
    }
}

// MARK: - Icon button

struct PulauIconButton: View {
    let systemImage: String
    var size: CGFloat = 26
    var prominent: Bool = false
    var help: String? = nil
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(PulauTheme.font(size * 0.46, .semibold))
                .foregroundStyle(prominent ? Color.black : PulauTheme.primaryText)
                .frame(width: size, height: size)
                .background(
                    Circle().fill(
                        prominent
                            ? AnyShapeStyle(Color.white)
                            : AnyShapeStyle(hovering ? PulauTheme.hoverFill : PulauTheme.cardFill)
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help ?? "")
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

// MARK: - Chip button

struct PulauChip: View {
    let title: String
    var systemImage: String? = nil
    var selected: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage).font(PulauTheme.font(9.5, .semibold))
                }
                Text(title).font(PulauTheme.caption)
            }
            .foregroundStyle(selected ? Color.black : PulauTheme.primaryText.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: PulauTheme.chipRadius, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(hovering ? PulauTheme.hoverFill : PulauTheme.cardFill))
            )
            .contentShape(RoundedRectangle(cornerRadius: PulauTheme.chipRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Empty state

struct PulauEmptyState: View {
    let systemImage: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(PulauTheme.font(18, .medium))
                .foregroundStyle(PulauTheme.tertiaryText)
            Text(title)
                .font(PulauTheme.body)
                .foregroundStyle(PulauTheme.secondaryText)
            if let subtitle {
                Text(subtitle)
                    .font(PulauTheme.caption)
                    .foregroundStyle(PulauTheme.tertiaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
