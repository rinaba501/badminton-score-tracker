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
/// face. Drawn sticker-style like the artwork — every shape gets a dark
/// contour outline, the feathers get rib lines, and a red collar band marks
/// where the body meets the crown. On faces that render complications
/// tinted/vibrant, the system reduces the colors to luminance shades, so
/// the dark-on-light features still read.
/// The petals' bases converge behind the body, so no feather tip crosses
/// the face.
private struct ShuttlecockGlyph: View {
    private static let featherBlue = Color(red: 0.52, green: 0.65, blue: 0.82)
    private static let inkNavy = Color(red: 0.16, green: 0.21, blue: 0.33)
    private static let collarRed = Color(red: 0.79, green: 0.31, blue: 0.31)
    private static let outline = StrokeStyle(lineWidth: 0.85, lineJoin: .round)

    var body: some View {
        ZStack {
            feathers
            ShuttlecockRibs()
                .stroke(Self.inkNavy, style: StrokeStyle(lineWidth: 0.5, lineCap: .round))
                .opacity(0.55)
            corkBody
            ShuttlecockCollar()
                .stroke(Self.collarRed, style: StrokeStyle(lineWidth: 1.05, lineCap: .round))
            ShuttlecockFace()
                .fill(Self.inkNavy)
        }
    }

    private var feathers: some View {
        ZStack {
            ShuttlecockFeathers()
                .fill(Self.featherBlue)
            ShuttlecockFeathers()
                .stroke(Self.inkNavy, style: Self.outline)
        }
    }

    private var corkBody: some View {
        ZStack {
            ShuttlecockBody()
                .fill(.white)
            ShuttlecockBody()
                .stroke(Self.inkNavy, style: Self.outline)
        }
    }
}

/// One rib line down the middle of each feather petal, matching the fan's
/// petal angles.
private struct ShuttlecockRibs: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: w * x, y: h * y) }
        var path = Path()

        path.move(to: pt(0.206, 0.288))
        path.addQuadCurve(to: pt(0.45, 0.55), control: pt(0.325, 0.413))
        path.move(to: pt(0.306, 0.156))
        path.addQuadCurve(to: pt(0.45, 0.5625), control: pt(0.375, 0.344))
        path.move(to: pt(0.5, 0.075))
        path.addLine(to: pt(0.5, 0.55))
        path.move(to: pt(0.694, 0.156))
        path.addQuadCurve(to: pt(0.55, 0.5625), control: pt(0.625, 0.344))
        path.move(to: pt(0.794, 0.288))
        path.addQuadCurve(to: pt(0.55, 0.55), control: pt(0.675, 0.413))

        return path
    }
}

/// The red collar band across the top of the cork body.
private struct ShuttlecockCollar: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: w * x, y: h * y) }
        var path = Path()

        path.move(to: pt(0.259, 0.656))
        path.addQuadCurve(to: pt(0.741, 0.656), control: pt(0.5, 0.575))

        return path
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
        path.addCurve(to: pt(0.25, 0.7175), control1: pt(0.33, 0.975), control2: pt(0.25, 0.865))
        path.addCurve(to: pt(0.50, 0.5425), control1: pt(0.25, 0.611), control2: pt(0.3625, 0.5425))
        path.addCurve(to: pt(0.75, 0.7175), control1: pt(0.6375, 0.5425), control2: pt(0.75, 0.611))
        path.addCurve(to: pt(0.5, 0.98), control1: pt(0.75, 0.865), control2: pt(0.67, 0.975))
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

        let eyeRadius = w * 0.053
        for cx in [CGFloat(0.381), CGFloat(0.619)] {
            let center = pt(cx, 0.708)
            path.addEllipse(in: CGRect(
                x: center.x - eyeRadius, y: center.y - eyeRadius,
                width: eyeRadius * 2, height: eyeRadius * 2
            ))
        }

        // Gentle closed smile: an upward-curving crescent, thick enough to
        // stay visible at complication size.
        let mouthLeft = pt(0.42, 0.805)
        let mouthRight = pt(0.58, 0.805)
        path.move(to: mouthLeft)
        path.addQuadCurve(to: mouthRight, control: pt(0.50, 0.845))
        path.addQuadCurve(to: mouthLeft, control: pt(0.50, 0.935))
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
