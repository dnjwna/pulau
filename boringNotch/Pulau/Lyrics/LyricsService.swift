//
//  LyricsService.swift
//  boringNotch — Pulau fork
//
//  LRCLIB client (free, no key): exact-match lookup by duration first, then a
//  scored search fallback that prefers time-synced lyrics. Results are cached
//  in memory so artwork refreshes don't refetch.
//

import Foundation

struct LyricWord: Equatable, Hashable {
    /// Absolute start time in seconds (same clock as `LyricLine.time`).
    let time: Double
    let text: String
}

struct LyricLine: Equatable, Hashable {
    let time: Double
    let text: String
    /// Per-word start times, only when the source has enhanced LRC word tags
    /// (`<mm:ss.xx>word`). Empty otherwise; see `LyricsService.wordTimings`.
    var words: [LyricWord] = []

    /// Empty LRC lines are instrumental gaps.
    var isInstrumental: Bool { text.isEmpty }
}

struct LyricsResult: Equatable {
    var synced: [LyricLine]
    var plain: String
    var isInstrumental: Bool
    var source: String

    static let empty = LyricsResult(synced: [], plain: "", isInstrumental: false, source: "")
    var isEmpty: Bool { synced.isEmpty && plain.isEmpty && !isInstrumental }
}

actor LyricsService {
    static let shared = LyricsService()

    private var cache: [String: LyricsResult] = [:]
    private var cacheOrder: [String] = []
    private let cacheLimit = 64

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.httpAdditionalHeaders = [
            // LRCLIB asks clients to identify themselves.
            "User-Agent": "Pulau (boring.notch fork) https://github.com/TheBoredTeam/boring.notch"
        ]
        return URLSession(configuration: config)
    }()

    func lyrics(title: String, artist: String, album: String, duration: Double) async -> LyricsResult {
        let key = Self.cacheKey(title: title, artist: artist)
        if let hit = cache[key] { return hit }

        let cleanTitle = Self.normalize(title)
        let cleanArtist = Self.normalize(artist)
        guard !cleanTitle.isEmpty else { return .empty }

        var result = LyricsResult.empty

        if duration > 0, let exact = await fetchExact(title: cleanTitle, artist: cleanArtist, album: album, duration: duration) {
            result = exact
        }

        if result.synced.isEmpty && !result.isInstrumental {
            if let searched = await search(title: cleanTitle, artist: cleanArtist, duration: duration) {
                // Only replace a plain-text exact hit if search found synced lyrics.
                if result.isEmpty || !searched.synced.isEmpty {
                    result = searched
                }
            }
        }

        if Task.isCancelled { return result }
        store(key: key, value: result)
        return result
    }

    // MARK: - Network

    private func fetchExact(title: String, artist: String, album: String, duration: Double) async -> LyricsResult? {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
            URLQueryItem(name: "album_name", value: album),
            URLQueryItem(name: "duration", value: String(Int(duration.rounded())))
        ]
        guard let url = components?.url else { return nil }
        guard let json = await getJSON(url) as? [String: Any] else { return nil }
        return Self.parseRecord(json)
    }

    private func search(title: String, artist: String, duration: Double) async -> LyricsResult? {
        var components = URLComponents(string: "https://lrclib.net/api/search")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        guard let url = components?.url else { return nil }
        guard let records = await getJSON(url) as? [[String: Any]], !records.isEmpty else { return nil }

        // Score: synced lyrics matter most, then duration closeness.
        func score(_ record: [String: Any]) -> Double {
            var s = 0.0
            if let synced = record["syncedLyrics"] as? String, !synced.isEmpty { s += 100 }
            if let plain = record["plainLyrics"] as? String, !plain.isEmpty { s += 10 }
            if duration > 0, let d = record["duration"] as? Double {
                let diff = abs(d - duration)
                s += diff <= 2 ? 50 : max(0, 30 - diff)
            }
            return s
        }

        guard let best = records.max(by: { score($0) < score($1) }) else { return nil }
        return Self.parseRecord(best)
    }

    private func getJSON(_ url: URL) async -> Any? {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }
    }

    // MARK: - Cache

    private func store(key: String, value: LyricsResult) {
        if cache[key] == nil { cacheOrder.append(key) }
        cache[key] = value
        while cacheOrder.count > cacheLimit {
            let evicted = cacheOrder.removeFirst()
            cache.removeValue(forKey: evicted)
        }
    }

    // MARK: - Parsing helpers (static so they are testable)

    static func parseRecord(_ record: [String: Any]) -> LyricsResult {
        let synced = (record["syncedLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let plain = (record["plainLyrics"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let instrumental = (record["instrumental"] as? Bool) ?? false
        return LyricsResult(
            synced: synced.isEmpty ? [] : parseLRC(synced),
            plain: plain,
            isInstrumental: instrumental,
            source: "LRCLIB"
        )
    }

    /// Supports `[mm:ss]`, `[mm:ss.x]`, `[mm:ss.xx]`, `[mm:ss.xxx]`, several
    /// timestamps on one line, and the `[offset:±ms]` tag.
    static func parseLRC(_ lrc: String) -> [LyricLine] {
        guard let stamp = try? NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#),
              let offsetTag = try? NSRegularExpression(pattern: #"^\[offset:\s*([+-]?\d+)\s*\]"#, options: [.caseInsensitive])
        else { return [] }

        var offset = 0.0
        var lines: [LyricLine] = []

        for raw in lrc.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)

            if let m = offsetTag.firstMatch(in: line, range: full) {
                offset = (Double(ns.substring(with: m.range(at: 1))) ?? 0) / 1000.0
                continue
            }

            let matches = stamp.matches(in: line, range: full)
            guard let last = matches.last else { continue }
            let textStart = last.range.location + last.range.length
            let rawText = ns.substring(from: textStart).trimmingCharacters(in: .whitespaces)
            let (text, enhancedWords) = parseWordTags(rawText, offset: offset)
            // Word times are absolute, so they only make sense for a line with one timestamp.
            let words = matches.count == 1 ? enhancedWords : []

            for m in matches {
                let minutes = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let seconds = Double(ns.substring(with: m.range(at: 2))) ?? 0
                var fraction = 0.0
                let fr = m.range(at: 3)
                if fr.location != NSNotFound {
                    let digits = ns.substring(with: fr)
                    fraction = (Double(digits) ?? 0) / pow(10, Double(digits.count))
                }
                // LRC spec: positive offset shifts lyrics earlier.
                let time = max(0, minutes * 60 + seconds + fraction - offset)
                lines.append(LyricLine(time: time, text: text, words: words))
            }
        }

        lines.sort { $0.time < $1.time }

        // Collapse consecutive instrumental gaps and drop a leading empty line at 0s.
        var collapsed: [LyricLine] = []
        for line in lines {
            if line.isInstrumental, collapsed.last?.isInstrumental == true { continue }
            collapsed.append(line)
        }
        if collapsed.first?.isInstrumental == true && collapsed.count > 1 && collapsed[0].time < 0.5 {
            collapsed.removeFirst()
        }
        return collapsed
    }

    /// Index of the line active at `elapsed` (binary search), or nil before the first line.
    static func activeIndex(in lines: [LyricLine], at elapsed: Double) -> Int? {
        guard let first = lines.first, elapsed >= first.time else { return nil }
        var low = 0
        var high = lines.count - 1
        var idx = 0
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= elapsed {
                idx = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return idx
    }

    static func normalize(_ string: String) -> String {
        var s = string
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "\u{FFFD}", with: "")
        // Drop decorations that break matching: "(Remastered 2011)", "- Live", "[Official Video]".
        let patterns = [
            #"\s*[\(\[][^\)\]]*(remaster|live|version|edit|official|video|audio|lyrics|mono|stereo)[^\)\]]*[\)\]]"#,
            #"\s+-\s+.*(remaster|live|version|edit).*$"#
        ]
        for p in patterns {
            s = s.replacingOccurrences(of: p, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cacheKey(title: String, artist: String) -> String {
        "\(title.lowercased())|\(artist.lowercased())"
    }
}
