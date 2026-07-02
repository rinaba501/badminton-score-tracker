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
/// The `avatar_shuttlecock_happy` mascot as a vector: five petal-shaped
/// feathers fanning out of a rounded cork body that carries the smiling
/// face. Colored like the mascot (light-blue feathers, white body, navy
/// face); on faces that render complications tinted/vibrant, the system
/// reduces these to luminance shades, so the dark-on-light features still
/// read.
/// The petals' bases converge behind the body, so no feather tip crosses
/// the face.
private struct ShuttlecockGlyph: View {
    var body: some View {
        ZStack {
            ShuttlecockFeathers()
                .fill(Color(red: 0.52, green: 0.65, blue: 0.82))
            ShuttlecockBody()
                .fill(.white)
            ShuttlecockFace()
                .fill(Color(red: 0.16, green: 0.21, blue: 0.33))
        }
    }
}

/// Five distinct feather petals radiating from a hub hidden inside the body
/// — separate lobes with visible gaps, like the mascot's feather crown,
/// rather than one continuous scalloped fan.
private struct ShuttlecockFeathers: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let hub = CGPoint(x: w * 0.5, y: h * 0.68)
        let anglesDegrees: [CGFloat] = [-40, -20, 0, 20, 40]
        let lengths: [CGFloat] = [0.50, 0.57, 0.62, 0.57, 0.50]
        let halfWidth = 0.105 * w
        var path = Path()

        for (angleDegrees, length) in zip(anglesDegrees, lengths) {
            let angle = angleDegrees * .pi / 180
            let along = CGVector(dx: sin(angle), dy: -cos(angle))
            let across = CGVector(dx: cos(angle), dy: sin(angle))
            // Point at distance `t` from the hub along the petal axis,
            // shifted `s` sideways.
            func at(_ t: CGFloat, _ s: CGFloat) -> CGPoint {
                CGPoint(
                    x: hub.x + along.dx * t * h + across.dx * s,
                    y: hub.y + along.dy * t * h + across.dy * s
                )
            }
            path.move(to: at(0, -halfWidth))
            path.addQuadCurve(
                to: at(length, -halfWidth * 0.85),
                control: at(length * 0.55, -halfWidth * 1.05)
            )
            path.addQuadCurve(
                to: at(length, halfWidth * 0.85),
                control: at(length + 0.05, 0)
            )
            path.addQuadCurve(
                to: at(0, halfWidth),
                control: at(length * 0.55, halfWidth * 1.05)
            )
            path.closeSubpath()
        }

        return path
    }
}

/// Rounded cork body, drawn over the feathers so it hides their bases.
private struct ShuttlecockBody: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: w * x, y: h * y) }
        var path = Path()

        path.move(to: pt(0.5, 0.98))
        path.addCurve(to: pt(0.30, 0.77), control1: pt(0.375, 0.956), control2: pt(0.30, 0.87))
        path.addCurve(to: pt(0.50, 0.63), control1: pt(0.30, 0.685), control2: pt(0.39, 0.63))
        path.addCurve(to: pt(0.70, 0.77), control1: pt(0.61, 0.63), control2: pt(0.70, 0.685))
        path.addCurve(to: pt(0.5, 0.98), control1: pt(0.70, 0.87), control2: pt(0.625, 0.956))
        path.closeSubpath()

        return path
    }
}

/// The mascot's face — two round eyes and a small smile — drawn on the
/// white cork body in a dark contrasting fill, where the artwork puts it.
private struct ShuttlecockFace: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: w * x, y: h * y) }
        var path = Path()

        let eyeRadius = w * 0.0425
        for cx in [CGFloat(0.405), CGFloat(0.595)] {
            let center = pt(cx, 0.7625)
            path.addEllipse(in: CGRect(
                x: center.x - eyeRadius, y: center.y - eyeRadius,
                width: eyeRadius * 2, height: eyeRadius * 2
            ))
        }

        let mouthLeft = pt(0.447, 0.8375)
        let mouthRight = pt(0.553, 0.8375)
        path.move(to: mouthLeft)
        path.addQuadCurve(to: mouthRight, control: pt(0.50, 0.855))
        path.addQuadCurve(to: mouthLeft, control: pt(0.50, 0.9125))
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
