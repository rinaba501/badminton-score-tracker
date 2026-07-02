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
/// The mascot from `avatar_shuttlecock_happy`, reduced to a flat monochrome
/// silhouette: a rounded body with a smiling face, and a crown of feathers
/// fanning up from behind it. Two yellow layers union into one shape — the
/// feathers' hidden convergence point sits behind the body, so no stray tip
/// pokes through the face.
private struct ShuttlecockGlyph: View {
    var body: some View {
        ZStack {
            ShuttlecockFeathers()
                .fill(.yellow)
            ShuttlecockBody()
                .fill(.yellow, style: FillStyle(eoFill: true))
        }
    }
}

/// Scalloped crown of feathers converging to a point low in the frame; the
/// lower half is covered by the body, so only the fanned tips show above it.
private struct ShuttlecockFeathers: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: w * x, y: h * y) }
        let tip = pt(0.5, 0.58)
        var path = Path()

        path.move(to: tip)
        path.addQuadCurve(to: pt(0.14, 0.08), control: pt(0.16, 0.42))
        path.addQuadCurve(to: pt(0.23, 0.16), control: pt(0.20, 0.15))
        path.addQuadCurve(to: pt(0.32, 0.06), control: pt(0.28, 0.08))
        path.addQuadCurve(to: pt(0.41, 0.16), control: pt(0.37, 0.15))
        path.addQuadCurve(to: pt(0.50, 0.05), control: pt(0.46, 0.06))
        path.addQuadCurve(to: pt(0.59, 0.16), control: pt(0.54, 0.06))
        path.addQuadCurve(to: pt(0.68, 0.06), control: pt(0.63, 0.08))
        path.addQuadCurve(to: pt(0.77, 0.16), control: pt(0.72, 0.15))
        path.addQuadCurve(to: pt(0.86, 0.08), control: pt(0.80, 0.15))
        path.addQuadCurve(to: tip, control: pt(0.84, 0.42))
        path.closeSubpath()

        return path
    }
}

/// Rounded bell-shaped body with the mascot's eyes and smile punched out as
/// holes (even-odd fill). Drawn over the feathers so it hides their base.
private struct ShuttlecockBody: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: w * x, y: h * y) }
        var path = Path()

        path.move(to: pt(0.5, 0.97))
        path.addCurve(to: pt(0.22, 0.60), control1: pt(0.26, 0.93), control2: pt(0.20, 0.78))
        path.addCurve(to: pt(0.50, 0.42), control1: pt(0.24, 0.46), control2: pt(0.36, 0.42))
        path.addCurve(to: pt(0.78, 0.60), control1: pt(0.64, 0.42), control2: pt(0.76, 0.46))
        path.addCurve(to: pt(0.5, 0.97), control1: pt(0.80, 0.78), control2: pt(0.74, 0.93))
        path.closeSubpath()

        let eyeRadius = w * 0.06
        for cx in [CGFloat(0.40), CGFloat(0.60)] {
            let center = pt(cx, 0.60)
            path.addEllipse(in: CGRect(
                x: center.x - eyeRadius, y: center.y - eyeRadius,
                width: eyeRadius * 2, height: eyeRadius * 2
            ))
        }

        let mouthLeft = pt(0.43, 0.74)
        let mouthRight = pt(0.57, 0.74)
        path.move(to: mouthLeft)
        path.addQuadCurve(to: mouthRight, control: pt(0.50, 0.73))
        path.addQuadCurve(to: mouthLeft, control: pt(0.50, 0.84))
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
                    .frame(width: 38, height: 38)
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
