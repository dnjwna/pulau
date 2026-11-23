//
//  LockScreenPlayerView.swift
//  boringNotch — Pulau fork
//
//  Content of the lock-screen Now Playing widget: artwork, title, the active
//  synced lyric line (from LRCLIB, if any), a progress bar and transport
//  controls. Pulau's own design — dark card tinted by the artwork colour.
//

import Defaults
import SwiftUI

struct LockScreenPlayerView: View {
    @ObservedObject private var music = MusicManager.shared
    @Default(.pulauLyricsOffset) private var lyricsOffset
    @Default(.pulauLockScreenShowLyrics) private var showLyrics

    private var hasTrack: Bool {
        !music.songTitle.isEmpty && (music.isPlaying || !music.isPlayerIdle)
    }

    var body: some View {
        ZStack {
            if hasTrack {
                card
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .frame(width: PulauLockScreen.panelSize.width, height: PulauLockScreen.panelSize.height)
        .animation(.easeOut(duration: 0.3), value: hasTrack)
        .preferredColorScheme(.dark)
    }

    // MARK: Card

    private var card: some View {
        HStack(spacing: 22) {
            artwork
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 8)
                if showLyrics { lyricLine }
                Spacer(minLength: 8)
                progress
                controls
                    .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    /// Blurred artwork under a dark scrim. Materials/vibrancy are avoided on
    /// purpose: they may not render behind a window on the lock-screen layer.
    private var background: some View {
        ZStack {
            Color.black
            Image(nsImage: music.albumArt)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: 48)
                .opacity(0.55)
                .saturation(1.2)
            LinearGradient(
                colors: [Color.black.opacity(0.35), Color.black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var artwork: some View {
        Image(nsImage: music.albumArt)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: 168, height: 168)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color(nsColor: music.avgColor).opacity(0.45), radius: 18, y: 6)
            .scaleEffect(music.isPlaying ? 1 : 0.94)
            .animation(.spring(response: 0.4, dampingFraction: 0.75), value: music.isPlaying)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(music.songTitle)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(music.artistName)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
    }

    // MARK: Lyrics

    @ViewBuilder
    private var lyricLine: some View {
        if !music.lyricLines.isEmpty {
            TimelineView(.animation(minimumInterval: 0.2, paused: !music.isPlaying)) { timeline in
                let elapsed = music.estimatedPlaybackPosition(at: timeline.date) + lyricsOffset
                let index = LyricsService.activeIndex(in: music.lyricLines, at: elapsed)
                let current = index.map { music.lyricLines[$0].text } ?? ""
                Text(current.isEmpty ? "♪" : current)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(index ?? -1)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 6)),
                        removal: .opacity
                    ))
                    .animation(.easeOut(duration: 0.25), value: index)
            }
        } else if music.lyricsAreInstrumental {
            Text("Instrumental")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    // MARK: Progress

    private var progress: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: !music.isPlaying)) { timeline in
            let position = music.estimatedPlaybackPosition(at: timeline.date)
            let duration = max(music.songDuration, 0)
            let fraction = duration > 0 ? min(max(position / duration, 0), 1) : 0
            VStack(spacing: 5) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 4)
                HStack {
                    Text(Self.format(position))
                    Spacer()
                    Text(duration > 0 ? "-" + Self.format(duration - position) : "--:--")
                }
                .font(.system(size: 10.5, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 26) {
            Spacer(minLength: 0)
            LockScreenControlButton(systemImage: "backward.fill", size: 18) {
                music.previousTrack()
            }
            LockScreenControlButton(
                systemImage: music.isPlaying ? "pause.fill" : "play.fill",
                size: 24,
                prominent: true
            ) {
                music.togglePlay()
            }
            LockScreenControlButton(systemImage: "forward.fill", size: 18) {
                music.nextTrack()
            }
            Spacer(minLength: 0)
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct LockScreenControlButton: View {
    let systemImage: String
    var size: CGFloat
    var prominent = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: prominent ? 46 : 36, height: prominent ? 46 : 36)
                .background(
                    Circle().fill(Color.white.opacity(prominent ? (hovering ? 0.24 : 0.16) : (hovering ? 0.12 : 0)))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
