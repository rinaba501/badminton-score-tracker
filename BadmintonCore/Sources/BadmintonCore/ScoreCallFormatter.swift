//
//  ScoreCallFormatter.swift
//  BadmintonCore
//
//  Pure locale-aware score announcement formatting. No side effects —
//  returns a String; the caller decides whether and when to speak it.
//  The `strings` parameter defaults to NSLocalizedString(Bundle.main) so
//  runtime app usage is zero-config; tests inject explicit format strings.
//

import Foundation

public enum ScoreCallFormatter {

    private static let katakanaNumbers = [
        "ラブ", "ワン", "ツー", "スリー", "フォー",
        "ファイブ", "シックス", "セブン", "エイト", "ナイン",
        "テン", "イレブン", "トゥエルブ", "サーティーン", "フォーティーン",
        "フィフティーン", "シックスティーン", "セブンティーン", "エイティーン", "ナインティーン",
        "トゥエンティ", "トゥエンティワン", "トゥエンティツー", "トゥエンティスリー", "トゥエンティフォー",
        "トゥエンティファイブ", "トゥエンティシックス", "トゥエンティセブン", "トゥエンティエイト", "トゥエンティナイン",
        "サーティ"
    ]

    private static func katakana(_ n: Int) -> String {
        guard n >= 0 && n < katakanaNumbers.count else { return "\(n)" }
        return katakanaNumbers[n]
    }

    private static func loveScore(_ n: Int) -> String {
        n == 0 ? "love" : "\(n)"
    }

    /// Returns a spoken score announcement for the current match state.
    ///
    /// - Parameters:
    ///   - match: Current match (server/scores/winner derive the wording).
    ///   - myName: Display name for the near side.
    ///   - opponentName: Display name for the far side.
    ///   - locale: The locale that selects number-word style (katakana / Chinese numerals / English love-score).
    ///   - strings: Localization lookup; defaults to `NSLocalizedString` from `Bundle.main`.
    public static func format(
        match: BadmintonMatch,
        myName: String,
        opponentName: String,
        locale: Locale,
        strings: (String) -> String = { NSLocalizedString($0, comment: "") }
    ) -> String {
        let serverScore = match.serverIsMe ? match.myScore : match.opponentScore
        let receiverScore = match.serverIsMe ? match.opponentScore : match.myScore
        let tied = serverScore == receiverScore
        let langCode = locale.language.languageCode?.identifier ?? "en"
        let isJapanese = langCode == "ja"
        let isZhHans = langCode == "zh"

        func name(for side: Side) -> String { side == .me ? myName : opponentName }

        func fmt(_ key: String, _ a: Int, _ b: Int) -> String {
            if isJapanese { return String(format: strings(key), katakana(a), katakana(b)) }
            if isZhHans { return String(format: strings(key), a, b) }
            return String(format: strings(key), loveScore(a), loveScore(b))
        }

        func fmtTied(_ key: String, _ n: Int) -> String {
            if isJapanese { return String(format: strings(key), katakana(n)) }
            if isZhHans { return String(format: strings(key), n) }
            let word = n == 0 ? "love" : "\(n)"
            return String(format: strings(key), word)
        }

        if let winner = match.matchWinner {
            return String(format: strings("speech.wins_match"), name(for: winner))
        } else if let winner = match.gameWinner {
            return String(format: strings("speech.wins_game"), name(for: winner))
        } else if match.isMatchPoint {
            return tied ? fmtTied("speech.tied", serverScore) : fmt("speech.match_point", serverScore, receiverScore)
        } else if match.isGamePoint {
            return tied ? fmtTied("speech.tied", serverScore) : fmt("speech.game_point", serverScore, receiverScore)
        } else if tied {
            return fmtTied("speech.tied", serverScore)
        } else {
            return fmt("speech.score", serverScore, receiverScore)
        }
    }
}
