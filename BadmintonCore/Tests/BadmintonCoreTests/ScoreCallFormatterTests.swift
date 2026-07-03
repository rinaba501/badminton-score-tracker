//
//  ScoreCallFormatterTests.swift
//  BadmintonCoreTests
//
//  Tests for ScoreCallFormatter. The `strings` closure is injected so we can
//  provide real English format strings without depending on Bundle.main
//  (which is unavailable in `swift test` on macOS).
//

import Foundation
import Testing
@testable import BadmintonCore

// Format strings matching the English Localizable.strings entries.
private let englishStrings: (String) -> String = { key in
    switch key {
    case "speech.score":        return "%@ serving %@"
    case "speech.tied":         return "%@ all"
    case "speech.game_point":   return "game point, %@ serving %@"
    case "speech.match_point":  return "match point, %@ serving %@"
    case "speech.wins_game":    return "%@ wins the game"
    case "speech.wins_match":   return "%@ wins the match"
    default:                    return key
    }
}

// Japanese format strings (katakana arguments, %@ placeholders).
private let japaneseStrings: (String) -> String = { key in
    switch key {
    case "speech.score":        return "%@サービング%@"
    case "speech.tied":         return "%@オール"
    case "speech.game_point":   return "ゲームポイント%@サービング%@"
    case "speech.match_point":  return "マッチポイント%@サービング%@"
    case "speech.wins_game":    return "%@ゲームを取りました"
    case "speech.wins_match":   return "%@マッチを取りました"
    default:                    return key
    }
}

struct ScoreCallFormatterTests {

    private func fmt(
        match: BadmintonMatch,
        myName: String = "Me",
        opponentName: String = "Opp",
        locale: Locale = Locale(identifier: "en"),
        strings: ((String) -> String)? = nil
    ) -> String {
        ScoreCallFormatter.format(
            match: match,
            myName: myName,
            opponentName: opponentName,
            locale: locale,
            strings: strings ?? englishStrings
        )
    }

    // MARK: - English

    @Test func normalScoreEnglish() {
        var match = BadmintonMatch()
        match.score(.me)   // 1-0, Me serving
        match.score(.me)   // 2-0
        let result = fmt(match: match)
        #expect(result == "2 serving love")
    }

    @Test func tiedScoreEnglish() {
        var match = BadmintonMatch()
        match.score(.me)
        match.score(.opponent)  // 1-1 tied, opponent serving
        let result = fmt(match: match)
        #expect(result == "1 all")
    }

    @Test func loveAllAtStart() {
        // Before any point is scored the server is "me" by default.
        // Formatter is not called before first score in practice, but it
        // should still produce a sensible string.
        let match = BadmintonMatch()
        let result = fmt(match: match)
        #expect(result == "love all")
    }

    @Test func gamePointEnglish() {
        var match = BadmintonMatch()
        // Score 20 for me, 0 for opponent → me needs one more to win
        for _ in 0..<20 { match.score(.me) }
        #expect(match.isGamePoint)
        let result = fmt(match: match)
        #expect(result == "game point, 20 serving love")
    }

    @Test func matchPointEnglish() {
        var match = BadmintonMatch()
        // Win the first game
        for _ in 0..<21 { match.score(.me) }
        match.startNextGame()
        // Reach match point in the second game
        for _ in 0..<20 { match.score(.me) }
        #expect(match.isMatchPoint)
        let result = fmt(match: match)
        #expect(result == "match point, 20 serving love")
    }

    @Test func gameWinnerEnglish() {
        var match = BadmintonMatch()
        for _ in 0..<21 { match.score(.me) }
        let result = fmt(match: match)
        #expect(result == "Me wins the game")
    }

    @Test func matchWinnerEnglish() {
        var match = BadmintonMatch()
        for _ in 0..<21 { match.score(.me) }
        match.startNextGame()
        for _ in 0..<21 { match.score(.me) }
        #expect(match.matchWinner == .me)
        let result = fmt(match: match)
        #expect(result == "Me wins the match")
    }

    @Test func opponentWinsMatchEnglish() {
        var match = BadmintonMatch()
        for _ in 0..<21 { match.score(.opponent) }
        match.startNextGame()
        for _ in 0..<21 { match.score(.opponent) }
        let result = fmt(match: match)
        #expect(result == "Opp wins the match")
    }

    // MARK: - Japanese (katakana numbers)

    @Test func normalScoreJapanese() {
        var match = BadmintonMatch()
        match.score(.me)   // 1-0, Me serving
        match.score(.me)   // 2-0
        let result = fmt(match: match, locale: Locale(identifier: "ja"), strings: japaneseStrings)
        // Server score 2 → "ツー", receiver score 0 → "ラブ"
        #expect(result == "ツーサービングラブ")
    }

    @Test func tiedScoreJapanese() {
        var match = BadmintonMatch()
        match.score(.me)
        match.score(.opponent)  // 1-1, opponent serving
        let result = fmt(match: match, locale: Locale(identifier: "ja"), strings: japaneseStrings)
        // Tied at 1 → "ワンオール"
        #expect(result == "ワンオール")
    }

    @Test func gameWinnerJapanese() {
        var match = BadmintonMatch()
        for _ in 0..<21 { match.score(.me) }
        let result = fmt(match: match, locale: Locale(identifier: "ja"), strings: japaneseStrings)
        #expect(result == "Meゲームを取りました")
    }

    // MARK: - Chinese (numeric integers, not katakana or love-score)

    @Test func normalScoreChinese() {
        var match = BadmintonMatch()
        match.score(.me)
        match.score(.me)  // 2-0, Me serving
        let chStrings: (String) -> String = { key in
            switch key {
            case "speech.score": return "发球方%d，接球方%d"
            default: return key
            }
        }
        let result = fmt(match: match, locale: Locale(identifier: "zh"), strings: chStrings)
        #expect(result == "发球方2，接球方0")
    }
}
