import AppKit
import SwiftUI

/// Rendered pose experiment. Motion is deliberately subtle, not skeletal animation.
struct CometArtwork: View {
    enum Mood: Equatable { case idle, working, ready }
    let mood: CometArtwork.Mood
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: reduceMotion || !visible)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let period = mood == .working ? 2.8 : 5.6
            let phase = time * .pi * 2 / period
            // Mix slow, unequal cycles for gentle variation without random jumps.
            let rawSway = sin(phase + 0.28 * sin(phase * 0.23))
                * (0.65 + 0.20 * sin(phase * 0.37))
            let sway = reduceMotion ? 0 : rawSway * (rawSway < 0 ? 0.55 : 0.8)
            let drift = reduceMotion ? 0 : 0.65 * sin(phase * 0.81 + .pi / 3)
                + 0.15 * sin(phase * 0.31)
            let tilt = reduceMotion ? 0 : sway * 1.8 + 0.3 * sin(phase * 0.43)
            let intensity = mood == .working ? 1.0 : 0.45
            Image(nsImage: CometPoseAtlas.image(mood))
                .resizable().interpolation(.high).scaledToFit()
                // Keep the layout slot fixed so counts and pill geometry never move.
                .scaleEffect(x: 0.8 * (1 - drift * 0.006),
                             y: 0.8 * (1 + drift * 0.012), anchor: .bottom)
                .rotationEffect(.degrees(tilt * intensity), anchor: .bottom)
                .offset(x: sway * 0.45 * intensity, y: drift * 0.4 * intensity)
        }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .accessibilityHidden(true)
    }
}

@MainActor
private enum CometPoseAtlas {
    static let poses: [NSImage] = {
        guard let url = Bundle.module.url(forResource: "comet-poses", withExtension: "png", subdirectory: "Comet"),
              let atlas = NSImage(contentsOf: url) else { return [] }
        let side = atlas.size.width / 3
        // Draw one cell from the bundled atlas without altering the original artwork.
        return (0..<3).map { index in
            NSImage(size: NSSize(width: side, height: atlas.size.height), flipped: false) { destination in
                atlas.draw(in: destination,
                           from: NSRect(x: CGFloat(index) * side, y: 0, width: side, height: atlas.size.height),
                           operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
                return true
            }
        }
    }()
    static func image(_ mood: CometArtwork.Mood) -> NSImage {
        let index = mood == .idle ? 0 : mood == .working ? 1 : 2
        return poses.indices.contains(index) ? poses[index] : NSImage()
    }
}
