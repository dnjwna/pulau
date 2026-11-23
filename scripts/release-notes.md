First public beta of **Pulau**, a free and open-source notch app for macOS, built on [Boring Notch](https://github.com/TheBoredTeam/boring.notch) (GPL-3.0).

## What's new in Pulau

- **Lyrics** in the notch: time-synced karaoke view from LRCLIB, click a line to seek, sync offset.
- **Focus**: Pomodoro timer, to-do list, clipboard history.
- **Assistant**: streaming chat with any OpenAI-compatible endpoint (Ollama by default, free and local; presets for Gemini, Groq, OpenRouter, OpenAI, LM Studio).
- **Lock-screen player** *(beta)*: large Now Playing widget with artwork, current lyric line and controls.
- **Presence** *(experimental, off by default)*: pauses music when no face is detected. Not a security feature.
- Plus everything Boring Notch does.

## Install

1. Download `Pulau-{{VERSION}}.zip`, unzip it, and move **Pulau.app** to `/Applications`.
2. Open it. macOS will block it the first time because the app is not notarized (no paid Apple Developer account).
3. Go to **System Settings → Privacy & Security**, scroll down, click **Open Anyway** next to Pulau, and confirm with your password. You only need to do this once.

Requirements: macOS 15 Sequoia or later. Architectures: {{ARCHS}}.

## Known limitations

- The lock-screen player uses a private macOS API and may break after a macOS update.
- No automatic updates yet: check this Releases page for new versions.
- Pulau uses its own bundle ID, so it does not share settings with Boring Notch. Run only one of the two at a time; both draw in the notch.

## Verify the download

SHA-256 of `Pulau-{{VERSION}}.zip`:

```
{{SHA256}}
```

Source code for this release is attached below (GPL-3.0).
