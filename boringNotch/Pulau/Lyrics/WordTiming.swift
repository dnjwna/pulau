//
//  WordTiming.swift
//  boringNotch — Pulau fork
//
//  Word-level timing for the word-by-word lyric highlight.
//
//  LRCLIB mostly serves line-level LRC. When a line carries enhanced-LRC word
//  tags (`[00:12.00]<00:12.00>Hello <00:12.40>world`) those exact times are
//  used. Otherwise the line's time span is split across its words in
//  proportion to their length: this is an ESTIMATE and can drift from the
//  singer, especially on long held notes.
//

import Foundation

extension LyricsService {
    /// Typical sung pace used to cap estimated lines, so a line followed by a
    /// long instrumental break doesn't stretch its words over the break.
    private static let estimatedSecondsPerWord = 0.42
    private static let estimatedLineLead = 0.35

    /// Strips enhanced-LRC `<mm:ss.xx>` word tags from `raw`.
    /// Returns the clean text plus the tagged words (empty if there were no tags).
    static func parseWordTags(_ raw: String, offset: Double) -> (text: String, words: [LyricWord]) {
        guard raw.contains("<"),
              let tag = try? NSRegularExpression(pattern: #"<(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?>"#)
        else { return (raw, []) }

        let ns = raw as NSString
        let matches = tag.matches(in: raw, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return (raw, []) }

        var words: [LyricWord] = []
        for (i, m) in matches.enumerated() {
            let start = m.range.location + m.range.length
            let end = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            guard end > start else { continue }
            let chunk = ns.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespaces)
            guard !chunk.isEmpty else { continue } // a trailing end-time tag has no word

            let minutes = Double(ns.substring(with: m.range(at: 1))) ?? 0
            let seconds = Double(ns.substring(with: m.range(at: 2))) ?? 0
            var fraction = 0.0
            let fr = m.range(at: 3)
            if fr.location != NSNotFound {
                let digits = ns.substring(with: fr)
                fraction = (Double(digits) ?? 0) / pow(10, Double(digits.count))
            }
            let time = max(0, minutes * 60 + seconds + fraction - offset)
            words.append(LyricWord(time: time, text: chunk))
        }

        let clean = tag.stringByReplacingMatches(
            in: raw, range: NSRange(location: 0, length: ns.length), withTemplate: ""
        )
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")

        return (clean, words)
    }

    /// Word start times for `lines[index]`.
    /// - Returns: the words and whether their timing is estimated.
    static func wordTimings(
        for index: Int,
        in lines: [LyricLine],
        songDuration: Double
    ) -> (words: [LyricWord], estimated: Bool) {
        guard lines.indices.contains(index) else { return ([], true) }
        let line = lines[index]
        if !line.words.isEmpty { return (line.words, false) }

        let tokens = line.text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return ([], true) }

        let nextStart: Double = index + 1 < lines.count
            ? lines[index + 1].time
            : (songDuration > line.time ? songDuration : line.time + 4)
        let paced = estimatedLineLead + Double(tokens.count) * estimatedSecondsPerWord
        // Finish the last word a little before the next line starts.
        let span = max(0.3, min(nextStart - line.time - 0.15, paced))

        // Weight by length (+1 so short words like "a" still get a beat).
        let weights = tokens.map { Double($0.count) + 1 }
        let total = weights.reduce(0, +)

        var words: [LyricWord] = []
        var cursor = line.time
        for (token, weight) in zip(tokens, weights) {
            words.append(LyricWord(time: cursor, text: token))
            cursor += span * weight / total
        }
        return (words, true)
    }

    /// Number of words in `words` already reached at `elapsed`.
    static func sungWordCount(_ words: [LyricWord], at elapsed: Double) -> Int {
        var count = 0
        for word in words where word.time <= elapsed { count += 1 }
        return count
    }
}
