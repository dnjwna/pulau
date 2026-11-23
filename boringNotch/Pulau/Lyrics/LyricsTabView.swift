//
//  LyricsTabView.swift
//  boringNotch — Pulau fork
//
//  Full karaoke view: time-synced lines that auto-scroll and highlight,
//  click a line to seek, adjustable sync offset.
//

import Defaults
import SwiftUI

struct LyricsTabView: View {
    @ObservedObject private var music = MusicManager.shared
    @Default(.pulauLyricsOffset) private var offset

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            nowPlayingColumn
                .frame(width: 128)
            lyricsColumn
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Left column

    private var nowPlayingColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(nsImage: music.albumArt)
                .resizable()
                .aspectRatio(1, contentMode: .fill)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: Color(nsColor: music.avgColor).opacity(0.45), radius: 10, y: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text(music.songTitle)
                    .font(PulauTheme.title)
                    .foregroundStyle(PulauTheme.primaryText)
                    .lineLimit(1)
                Text(music.artistName)
                    .font(PulauTheme.caption)
                    .foregroundStyle(PulauTheme.secondaryText)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                PulauIconButton(systemImage: "backward.fill", size: 22) { music.previousTrack() }
                PulauIconButton(systemImage: music.isPlaying ? "pause.fill" : "play.fill", size: 22, prominent: true) {
                    music.togglePlay()
                }
                PulauIconButton(systemImage: "forward.fill", size: 22) { music.nextTrack() }
            }
        }
    }

    // MARK: Right column

    @ViewBuilder
    private var lyricsColumn: some View {
        if music.isPlayerIdle && music.songTitle.isEmpty {
            PulauEmptyState(systemImage: "music.note", title: "Nothing playing")
        } else if music.isFetchingLyrics {
            PulauEmptyState(systemImage: "ellipsis", title: "Looking for lyrics…")
        } else if music.lyricsAreInstrumental {
            PulauEmptyState(systemImage: "pianokeys", title: "Instrumental")
        } else if !music.lyricLines.isEmpty {
            syncedLyrics
        } else if !music.currentLyrics.isEmpty {
            plainLyrics
        } else {
            PulauEmptyState(systemImage: "text.badge.xmark", title: "No lyrics found", subtitle: "Source: LRCLIB")
        }
    }

    private var syncedLyrics: some View {
        TimelineView(.animation(minimumInterval: 0.15, paused: !music.isPlaying)) { timeline in
            let elapsed = music.estimatedPlaybackPosition(at: timeline.date) + offset
            let active = LyricsService.activeIndex(in: music.lyricLines, at: elapsed)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 7) {
                        // Top spacer so the first line can sit in the middle.
                        Color.clear.frame(height: 40)
                        ForEach(Array(music.lyricLines.enumerated()), id: \.offset) { index, line in
                            LyricRow(
                                text: line.isInstrumental ? "♪" : line.text,
                                state: rowState(index: index, active: active)
                            )
                            .id(index)
                            .onTapGesture {
                                music.seek(to: max(0, line.time - offset))
                            }
                        }
                        Color.clear.frame(height: 40)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.22),
                            .init(color: .black, location: 0.78),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .onChange(of: active) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(PulauTheme.spring) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
                .onAppear {
                    if let active { proxy.scrollTo(active, anchor: .center) }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) { offsetControl }
    }

    private var plainLyrics: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(music.currentLyrics)
                .font(PulauTheme.font(12.5, .medium))
                .foregroundStyle(PulauTheme.primaryText.opacity(0.85))
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
        }
        .overlay(alignment: .bottomTrailing) {
            Text("Unsynced · \(music.lyricsSource)")
                .font(PulauTheme.font(9, .medium))
                .foregroundStyle(PulauTheme.tertiaryText)
                .padding(4)
        }
    }

    private var offsetControl: some View {
        HStack(spacing: 2) {
            Button { offset -= 0.25 } label: { Image(systemName: "minus") }
            Text(String(format: "%+.2fs", offset))
                .font(PulauTheme.font(9, .medium))
                .monospacedDigit()
                .frame(minWidth: 40)
            Button { offset += 0.25 } label: { Image(systemName: "plus") }
        }
        .buttonStyle(.plain)
        .font(PulauTheme.font(9, .bold))
        .foregroundStyle(PulauTheme.secondaryText)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .help("Lyrics sync offset")
        .padding(2)
    }

    private func rowState(index: Int, active: Int?) -> LyricRow.RowState {
        guard let active else { return .upcoming }
        if index == active { return .active }
        return index < active ? .past : .upcoming
    }
}

private struct LyricRow: View {
    enum RowState { case past, active, upcoming }
    let text: String
    let state: RowState

    var body: some View {
        Text(text)
            .font(PulauTheme.font(state == .active ? 15 : 13, state == .active ? .bold : .semibold))
            .foregroundStyle(color)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .scaleEffect(state == .active ? 1.0 : 0.98, anchor: .leading)
            .blur(radius: state == .active ? 0 : 0.4)
            .animation(PulauTheme.spring, value: state)
            .contentShape(Rectangle())
    }

    private var color: Color {
        switch state {
        case .active: return .white
        case .past: return .white.opacity(0.28)
        case .upcoming: return .white.opacity(0.45)
        }
    }
}
