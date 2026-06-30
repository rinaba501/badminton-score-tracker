import WidgetKit
import SwiftUI

// MARK: - Timeline

struct BadmintonEntry: TimelineEntry {
    let date: Date
}

struct BadmintonProvider: TimelineProvider {
    func placeholder(in context: Context) -> BadmintonEntry {
        BadmintonEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (BadmintonEntry) -> Void) {
        completion(BadmintonEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BadmintonEntry>) -> Void) {
        completion(Timeline(entries: [BadmintonEntry(date: Date())], policy: .never))
    }
}

// MARK: - Views

struct BadmintonComplicationEntryView: View {
    var entry: BadmintonEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "figure.badminton")
                    .font(.system(size: 20))
                    .foregroundColor(.yellow)
            }
        case .accessoryCorner:
            Image(systemName: "figure.badminton")
                .font(.system(size: 20))
                .foregroundColor(.yellow)
                .widgetLabel("Badminton")
        case .accessoryInline:
            Label("New Match", systemImage: "figure.badminton")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "figure.badminton")
                    .font(.system(size: 24))
                    .foregroundColor(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Badminton")
                        .font(.headline)
                    Text("Tap to start")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            Image(systemName: "figure.badminton")
                .foregroundColor(.yellow)
        }
    }
}

// MARK: - Widget

@main
struct BadmintonComplicationWidget: Widget {
    let kind = "BadmintonComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BadmintonProvider()) { entry in
            BadmintonComplicationEntryView(entry: entry)
                .widgetURL(URL(string: "badminton://newmatch"))
        }
        .configurationDisplayName("Badminton")
        .description("Tap to start a new match.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular
        ])
    }
}
