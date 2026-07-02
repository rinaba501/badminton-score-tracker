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

private struct ShuttlecockImage: View {
    var body: some View {
        Image("avatar_shuttlecock_happy")
            .renderingMode(.original)
            .resizable()
            .widgetAccentedRenderingMode(.fullColor)
            .scaledToFit()
    }
}

/// Vector shuttlecock silhouette for slots (like the circular Modular face) that
/// strip color from bitmap images and render them as a flat monochrome mask.
/// Unlike `ShuttlecockImage`, a vector `Shape` filled with `foregroundStyle`
/// tints correctly in that mode instead of disappearing into a plain circle.
private struct ShuttlecockGlyph: View {
    var body: some View {
        ZStack {
            ShuttlecockSkirt()
                .fill(.yellow)
            Circle()
                .fill(.yellow)
                .frame(width: 4, height: 4)
                .offset(y: 6.5)
        }
    }
}

private struct ShuttlecockSkirt: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: w * 0.5, y: h * 0.6))
        path.addLine(to: CGPoint(x: w * 0.12, y: h * 0.05))
        path.addLine(to: CGPoint(x: w * 0.32, y: h * 0.05))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.6))
        path.addLine(to: CGPoint(x: w * 0.68, y: h * 0.05))
        path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.05))
        path.closeSubpath()
        return path
    }
}

struct BadmintonComplicationEntryView: View {
    var entry: BadmintonEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                ShuttlecockGlyph()
                    .frame(width: 20, height: 20)
            }
        case .accessoryCorner:
            ShuttlecockImage()
                .widgetLabel("Badminton")
        case .accessoryInline:
            Label("New Match", systemImage: "figure.badminton")
        case .accessoryRectangular:
            HStack(spacing: 8) {
                ShuttlecockImage()
                    .frame(width: 32, height: 32)
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
            ShuttlecockImage()
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
