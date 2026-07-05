//
//  ShareCard.swift
//  badminton score tracker (iOS)
//
//  Shareable match-result card (#13): a SwiftUI card rendered to a PNG via
//  ImageRenderer and shared through the native share sheet (ShareLink). The
//  shared item exposes BOTH the image (for Photos / AirDrop / Save) and a
//  plain-text summary (for pasting into messages). Team-name formatting and
//  duration reuse the same BadmintonCore helpers the history row uses.
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import BadmintonCore

// MARK: - Label helpers (shared by the card and the plain-text summary)

extension MatchRecord {
    private func teamLabel(name: String, partnerName: String?) -> String {
        guard let partnerName else { return name }
        return String(format: NSLocalizedString("game.team_names_format", comment: ""),
                      name, Player.displayName(for: partnerName))
    }

    var shareMyLabel: String {
        teamLabel(name: myName.isEmpty ? Player.defaultMyName : Player.displayName(for: myName),
                  partnerName: myPartnerName)
    }

    var shareOpponentLabel: String {
        let fallback = NSLocalizedString("history.opponent_fallback", comment: "")
        let name = opponentName.isEmpty ? fallback : Player.displayName(for: opponentName)
        return teamLabel(name: name, partnerName: opponentPartnerName)
    }

    var shareGameLine: String {
        games.map { "\($0.my)-\($0.opponent)" }.joined(separator: ", ")
    }

    var iWonShare: Bool { winner == myName }

    /// Plain-text fallback shared alongside the image.
    var shareSummaryText: String {
        var lines = ["\(shareMyLabel)  \(myGamesWon)–\(opponentGamesWon)  \(shareOpponentLabel)"]
        if !shareGameLine.isEmpty { lines.append(shareGameLine) }
        lines.append(date.formatted(date: .abbreviated, time: .shortened))
        return lines.joined(separator: "\n")
    }
}

// MARK: - The card view

struct ShareCard: View {
    let record: MatchRecord

    private var iWon: Bool { record.iWonShare }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "figure.badminton")
                    .foregroundStyle(.tint)
                Text("ios.title")
                    .font(.headline)
                Spacer()
                Text(record.date, format: .dateTime.year().month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            teamRow(label: record.shareMyLabel, games: record.myGamesWon, isWinner: iWon)
            teamRow(label: record.shareOpponentLabel, games: record.opponentGamesWon, isWinner: !iWon)

            if !record.shareGameLine.isEmpty {
                Text(record.shareGameLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if record.duration > 0 {
                Label(StatsCalculator.durationString(record.duration), systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 340, alignment: .leading)
        .background(Color(.secondarySystemBackground))
    }

    private func teamRow(label: String, games: Int, isWinner: Bool) -> some View {
        HStack {
            Text(label)
                .font(.title3)
                .fontWeight(isWinner ? .bold : .regular)
                .lineLimit(1)
            Spacer()
            Text("\(games)")
                .font(.system(.title2, design: .rounded))
                .fontWeight(isWinner ? .bold : .regular)
                .foregroundStyle(isWinner ? Color.green : Color.primary)
                .monospacedDigit()
        }
    }
}

// MARK: - Transferable wrapper (image + plain-text)

struct SharableMatchCard: Transferable {
    let png: Data
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.png }
        ProxyRepresentation(exporting: \.text)
    }
}

enum MatchCardShare {
    /// Renders the card to a PNG and pairs it with the plain-text summary.
    /// Must run on the main actor (ImageRenderer requirement).
    @MainActor static func make(for record: MatchRecord) -> (item: SharableMatchCard, preview: Image)? {
        let renderer = ImageRenderer(content: ShareCard(record: record))
        renderer.scale = 3
        guard let uiImage = renderer.uiImage, let png = uiImage.pngData() else { return nil }
        return (SharableMatchCard(png: png, text: record.shareSummaryText), Image(uiImage: uiImage))
    }
}
