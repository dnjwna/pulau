//
//  LockScreenPlayerView.swift
//  boringNotch — Pulau fork
//
//  Content of the lock-screen Now Playing widget: artwork, title, the active
//  synced lyric line (from LRCLIB, if any), a progress bar and transport
//  controls. Pulau's own design: a dark card tinted by the artwork colour,
//  click/drag-to-seek progress bar, and auto-hide after a long pause.
//

import Defaults
import SwiftUI

struct LockScreenPlayerView: View {
    @ObservedObject private var music = MusicManager.shared
    @Default(.pulauLyricsOffset) private var lyricsOffset
    @Default(.pulauLockScreenShowLyrics) private var showLyrics
    @Default(.pulauLockScreenWordHighlight) private var wordHighlight
    @Default(.pulauLockScreenHideAfterPauseMinutes) private var hideAfterMinutes
    @Default(.pulauLockScreenStyle) private var style
    @Default(.pulauLockScreenGlass) private var glass

    /// Set once playback has been paused for `hideAfterMinutes`.
    @State private var pausedTooLong = false
    /// Fraction (0…1) shown while the user drags the progress bar.
    @State private var scrubFraction: Double?
    @State private var hoveringProgress = false

    /// Upstream's `isPlayerIdle` flips a few seconds after pausing, which would
    /// hide the card almost immediately; the lock-screen card uses its own
    /// (much longer, configurable) pause timer instead.
    private var visible: Bool {
        !music.songTitle.isEmpty && !pausedTooLong
    }

    var body: some View {
        ZStack {
            if visible {
                Group {
                    if style == LockScreenStyle.artwork.rawValue { artworkCard } else { card }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .frame(
            width: LockScreenStyle.size(for: style).width,
            height: LockScreenStyle.size(for: style).height
        )
        .animation(.easeOut(duration: 0.3), value: visible)
        .preferredColorScheme(.dark)
        // Restarts whenever play/pause or the setting changes; cancelled automatically.
        .task(id: "\(music.isPlaying)-\(hideAfterMinutes)") {
            if music.isPlaying || hideAfterMinutes <= 0 {
                pausedTooLong = false
                return
            }
            try? await Task.sleep(for: .seconds(Double(hideAfterMinutes) * 60))
            if !Task.isCancelled, !music.isPlaying { pausedTooLong = true }
        }
        .onChange(of: visible, initial: true) { _, isVisible in
            // A hidden card must not swallow clicks in the middle of the lock screen.
            PulauLockScreen.shared.setCardInteractive(isVisible)
        }
    }

    /// Artwork colour, darkened and desaturated enough to keep white text readable.
    private var tint: Color {
        let base = (music.avgColor.usingColorSpace(.deviceRGB) ?? .gray)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        base.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(nsColor: NSColor(
            hue: hue,
            saturation: min(saturation, 0.75),
            brightness: min(max(brightness, 0.25), 0.45),
            alpha: 1
        ))
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
                progress(timesAbove: false)
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

    /// Artwork-coloured base, blurred artwork, then a dark scrim. Materials /
    /// vibrancy are avoided on purpose: they may not render on the lock-screen layer.
    private var background: some View {
        ZStack {
            tint
            Image(nsImage: music.albumArt)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: 48)
                .opacity(0.45)
                .saturation(1.2)
            LinearGradient(
                colors: [Color.black.opacity(0.15), Color.black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .animation(.easeInOut(duration: 0.8), value: music.avgColor)
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

    // MARK: Artwork style

    /// Square card: the artwork fills the card, with a title chip and a
    /// favourite button on top, and lyric / progress / controls over a
    /// bottom gradient.
    private var artworkCard: some View {
        let size = LockScreenStyle.size(for: LockScreenStyle.artwork.rawValue)
        let inset: CGFloat = 10
        return ZStack {
            // Outer frame: Liquid Glass (macOS 26+) lightly tinted by the
            // artwork colour, or a solid artwork-coloured frame as fallback.
            Color.clear
                .pulauGlass(
                    glass,
                    in: RoundedRectangle(cornerRadius: 40, style: .continuous),
                    tint: tint.opacity(0.35),
                    fallback: tint.opacity(0.85)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 40, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )

            ZStack {
                Image(nsImage: music.albumArt)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width - inset * 2, height: size.height - inset * 2)
                    .clipped()

                VStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 90)
                    Spacer(minLength: 0)
                    LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                        .frame(height: showLyrics ? 190 : 160)
                }

                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: 8) {
                        titleChip
                        Spacer(minLength: 0)
                        if music.canFavoriteTrack {
                            LockScreenControlButton(
                                systemImage: music.isFavoriteTrack ? "heart.fill" : "heart",
                                size: 15,
                                style: .glass,
                                useGlass: glass
                            ) {
                                music.toggleFavoriteTrack()
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    if showLyrics {
                        lyricLine
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 8)
                    }
                    progress(timesAbove: true)
                    HStack(spacing: 18) {
                        LockScreenControlButton(systemImage: "backward.end.fill", size: 15, style: .glass, useGlass: glass) {
                            music.previousTrack()
                        }
                        LockScreenControlButton(
                            systemImage: music.isPlaying ? "pause.fill" : "play.fill",
                            size: 18,
                            prominent: true,
                            style: .glass,
                            useGlass: glass
                        ) {
                            music.togglePlay()
                        }
                        LockScreenControlButton(systemImage: "forward.end.fill", size: 15, style: .glass, useGlass: glass) {
                            music.nextTrack()
                        }
                    }
                    .padding(.top, 6)
                }
                .padding(14)
            }
            .frame(width: size.width - inset * 2, height: size.height - inset * 2)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .frame(width: size.width, height: size.height)
        .animation(.easeInOut(duration: 0.8), value: music.avgColor)
    }

    /// Small artwork thumbnail + title + artist in a translucent capsule.
    private var titleChip: some View {
        HStack(spacing: 8) {
            Image(nsImage: music.albumArt)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 30, height: 30)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(music.songTitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(music.artistName)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .lineLimit(1)
        }
        .padding(.leading, 4)
        .padding(.trailing, 14)
        .padding(.vertical, 4)
        .pulauGlass(glass, in: Capsule(), fallback: Color.black.opacity(0.35))
        .overlay(Capsule().strokeBorder(Color.white.opacity(glass ? 0.06 : 0.12), lineWidth: 1))
        .frame(maxWidth: 240, alignment: .leading)
    }

    // MARK: Lyrics

    @ViewBuilder
    private var lyricLine: some View {
        if !music.lyricLines.isEmpty {
            TimelineView(.animation(minimumInterval: wordHighlight ? 0.08 : 0.2, paused: !music.isPlaying)) { timeline in
                let elapsed = music.estimatedPlaybackPosition(at: timeline.date) + lyricsOffset
                let index = LyricsService.activeIndex(in: music.lyricLines, at: elapsed)
                lyricText(index: index, elapsed: elapsed)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(index ?? -1)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 4)),
                        removal: .identity
                    ))
                    .animation(.easeOut(duration: 0.25), value: index)
            }
        } else if music.lyricsAreInstrumental {
            Text("Instrumental")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    /// The active line, with already-sung words bright and upcoming ones dim
    /// when word highlight is on. Word timing is estimated unless the lyrics
    /// carry enhanced-LRC word tags (see WordTiming.swift).
    private func lyricText(index: Int?, elapsed: Double) -> Text {
        guard let index, !music.lyricLines[index].text.isEmpty else {
            return Text(verbatim: "♪").foregroundColor(.white.opacity(0.92))
        }
        guard wordHighlight else {
            return Text(verbatim: music.lyricLines[index].text).foregroundColor(.white.opacity(0.92))
        }
        let timing = LyricsService.wordTimings(for: index, in: music.lyricLines, songDuration: music.songDuration)
        let sung = LyricsService.sungWordCount(timing.words, at: elapsed)
        var result = Text(verbatim: "")
        for (i, word) in timing.words.enumerated() {
            let piece = i == timing.words.count - 1 ? word.text : word.text + " "
            result = result + Text(verbatim: piece)
                .foregroundColor(i < sung ? .white : .white.opacity(0.38))
        }
        return result
    }

    // MARK: Progress

    private func progress(timesAbove: Bool) -> some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: !music.isPlaying || scrubFraction != nil)) { timeline in
            let duration = max(music.songDuration, 0)
            let playing = music.estimatedPlaybackPosition(at: timeline.date)
            let livePosition = duration > 0 ? min(max(playing / duration, 0), 1) : 0
            let fraction = scrubFraction ?? livePosition
            let position = duration * fraction
            let canSeek = duration > 0

            VStack(spacing: 5) {
                if timesAbove { timeLabels(position: position, duration: duration) }
                GeometryReader { geo in
                    let barHeight: CGFloat = (hoveringProgress || scrubFraction != nil) ? 7 : 4
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18))
                        Capsule()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: max(barHeight, geo.size.width * fraction))
                    }
                    .frame(height: barHeight)
                    .frame(maxHeight: .infinity) // centre the bar in the taller hit area
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard canSeek, geo.size.width > 0 else { return }
                                scrubFraction = min(max(value.location.x / geo.size.width, 0), 1)
                            }
                            .onEnded { value in
                                guard canSeek, geo.size.width > 0 else { scrubFraction = nil; return }
                                let target = min(max(value.location.x / geo.size.width, 0), 1)
                                music.seek(to: target * duration)
                                // Keep the scrubbed position briefly so the bar doesn't
                                // jump back before the player reports the new time.
                                Task {
                                    try? await Task.sleep(for: .milliseconds(600))
                                    scrubFraction = nil
                                }
                            }
                    )
                    .onHover { hoveringProgress = $0 && canSeek }
                    .animation(.easeOut(duration: 0.15), value: barHeight)
                }
                .frame(height: 14) // larger than the bar so it's easy to hit
                if !timesAbove { timeLabels(position: position, duration: duration) }
            }
        }
    }

    private func timeLabels(position: Double, duration: Double) -> some View {
        HStack {
            Text(Self.format(position))
            Spacer()
            Text(duration > 0 ? "-" + Self.format(duration - position) : "--:--")
        }
        .font(.system(size: 10.5, weight: .medium, design: .rounded).monospacedDigit())
        .foregroundStyle(.white.opacity(scrubFraction != nil ? 0.9 : 0.6))
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
    enum Style { case plain, glass }

    let systemImage: String
    var size: CGFloat
    var prominent = false
    var style: Style = .plain
    /// Use Liquid Glass for `.glass` buttons when the OS supports it.
    var useGlass = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: prominent ? 46 : 36, height: prominent ? 46 : 36)
                .pulauGlass(style == .glass && useGlass, in: Circle(), fallback: fill)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var fill: Color {
        switch style {
        case .plain:
            return Color.white.opacity(prominent ? (hovering ? 0.24 : 0.16) : (hovering ? 0.12 : 0))
        case .glass:
            // Always visible over artwork; dark enough for the white glyph.
            return Color.black.opacity(hovering ? 0.5 : 0.35)
        }
    }
}

private extension View {
    /// Liquid Glass in `shape` on macOS 26+ when `enabled`; otherwise a plain
    /// `fallback` fill (also used on older macOS versions).
    @ViewBuilder
    func pulauGlass<S: Shape>(_ enabled: Bool, in shape: S, tint: Color? = nil, fallback: Color) -> some View {
        // Kept as a lone `#available` condition: result builders only support
        // availability checks that are the sole condition of an `if`.
        if #available(macOS 26.0, *) {
            if enabled, let tint {
                self.glassEffect(.regular.tint(tint), in: shape)
            } else if enabled {
                self.glassEffect(.regular, in: shape)
            } else {
                self.background(shape.fill(fallback))
            }
        } else {
            self.background(shape.fill(fallback))
        }
    }
}

/// Lock-screen widget layouts. Stored as the raw value in Defaults.
enum LockScreenStyle: String, CaseIterable {
    case card
    case artwork

    static func size(for raw: String) -> NSSize {
        LockScreenStyle(rawValue: raw) == .artwork
            ? NSSize(width: 360, height: 360)
            : NSSize(width: 560, height: 212)
    }
}
