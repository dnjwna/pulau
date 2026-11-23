//
//  LockScreenBackdropView.swift
//  boringNotch — Pulau fork
//
//  Full-screen album-art backdrop behind the lock-screen player.
//
//  Artwork from music apps is often 300–600 px, which looks blocky stretched
//  over a 2–5K display, so it is shown blurred and slightly zoomed, with a
//  vignette that keeps the macOS clock and the password field readable.
//  The panel hosting this view ignores mouse events, so the lock-screen UI
//  underneath stays clickable.
//

import Defaults
import SwiftUI

struct LockScreenBackdropView: View {
    @ObservedObject private var music = MusicManager.shared
    @Default(.pulauLockScreenArtBackdrop) private var backdropEnabled

    @State private var drift = false

    private var hasTrack: Bool {
        !music.songTitle.isEmpty && (music.isPlaying || !music.isPlayerIdle)
    }

    /// Changes when the track changes, to cross-fade the artwork.
    private var trackKey: String { music.songTitle + "\u{1F}" + music.artistName }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if backdropEnabled && hasTrack {
                    ZStack {
                        Color.black

                        Image(nsImage: music.albumArt)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .scaleEffect(drift ? 1.16 : 1.10)
                            .blur(radius: 26)
                            .saturation(1.15)
                            .clipped()
                            .id(trackKey)
                            .transition(.opacity)

                        // Keep the top (clock) and bottom (login) readable.
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(0.45), location: 0),
                                .init(color: .black.opacity(0.10), location: 0.35),
                                .init(color: .black.opacity(0.10), location: 0.65),
                                .init(color: .black.opacity(0.55), location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        RadialGradient(
                            colors: [.clear, .black.opacity(0.45)],
                            center: .center,
                            startRadius: min(geo.size.width, geo.size.height) * 0.35,
                            endRadius: max(geo.size.width, geo.size.height) * 0.75
                        )
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.easeInOut(duration: 0.9), value: trackKey)
            .animation(.easeInOut(duration: 0.6), value: hasTrack && backdropEnabled)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            // Very slow zoom so the backdrop feels alive without distracting.
            withAnimation(.easeInOut(duration: 24).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}
