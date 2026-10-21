import SwiftUI

/// One quiet, independently moving trace for each visible working session.
struct ActivityOrbit: View {
    let sessionIDs: [String]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var traces: [Trace] = []

    private struct Trace: Identifiable {
        let id: String
        let born: Date
        var retired: Date?

        // Stable phases and slightly different tempos keep each agent recognizable.
        private var seed: UInt64 {
            id.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        }
        var offset: Double { Double(seed % 10_000) / 10_000 }
        var period: Double { 4.8 + Double((seed >> 16) % 160) / 100 }

        func position(at now: Date) -> Double {
            let elapsed: Double
            if let retired {
                let tail = max(0, now.timeIntervalSince(retired))
                // Keep position continuous, easing to rest as the trace dissolves.
                elapsed = retired.timeIntervalSinceReferenceDate + 0.45 * (1 - exp(-tail / 0.45))
            } else { elapsed = now.timeIntervalSinceReferenceDate }
            return (elapsed / period + offset).truncatingRemainder(dividingBy: 1)
        }

        func opacity(at now: Date) -> Double {
            let entrance = min(1, max(0, now.timeIntervalSince(born) / 0.7))
            let exit = retired.map { max(0, 1 - now.timeIntervalSince($0) / 1.25) } ?? 1
            return entrance * exit * exit
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: traces.isEmpty || reduceMotion)) { timeline in
            Canvas { context, size in
                let path = Capsule().path(in: CGRect(origin: .zero, size: size).insetBy(dx: 0.8, dy: 0.8))
                // Confine the trail and blurred head to one uniform border band.
                // Round caps and glow must not widen the pill at its curved ends.
                context.clip(to: path.strokedPath(StrokeStyle(lineWidth: 1.6)))
                // Keep the total light restrained even when many agents are working.
                let intensity = min(1, 2.8 / sqrt(Double(max(1, traces.count))))
                for trace in traces {
                    if reduceMotion {
                        guard trace.retired == nil else { continue }
                        stroke(path, from: trace.offset, length: 0.035, in: &context,
                               color: Self.brand.opacity(0.7 * intensity), width: 1.4)
                        continue
                    }
                    let opacity = trace.opacity(at: timeline.date) * intensity
                    guard opacity > 0 else { continue }
                    let head = trace.position(at: timeline.date)
                    // Feathered trail rather than a rotating gradient washing the whole pill.
                    for step in 0..<12 {
                        let strength = Double(step + 1) / 12
                        let start = head - 0.12 + Double(step) * 0.01
                        stroke(path, from: start, length: 0.012, in: &context,
                               color: Self.brand.opacity(opacity * strength * strength * 0.85), width: 1.4)
                    }
                    context.drawLayer { halo in
                        halo.addFilter(.blur(radius: 2.5))
                        stroke(path, from: head - 0.024, length: 0.028, in: &halo,
                               color: Self.brand.opacity(opacity * 0.65), width: 3)
                    }
                    stroke(path, from: head - 0.014, length: 0.014, in: &context,
                           color: Self.highlight.opacity(opacity * 0.95), width: 1.6)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: sessionIDs) {
            let now = Date()
            let working = Set(sessionIDs)
            traces.removeAll { $0.retired.map { now.timeIntervalSince($0) >= 1.25 } ?? false }
            for index in traces.indices {
                if working.contains(traces[index].id) { traces[index].retired = nil }
                else if traces[index].retired == nil { traces[index].retired = now }
            }
            let known = Set(traces.map(\.id))
            traces += sessionIDs.filter { !known.contains($0) }.map { Trace(id: $0, born: now) }
            // Retire the final trace too, allowing the animation clock to sleep at idle.
            do { try await Task.sleep(for: .milliseconds(1300)) } catch { return }
            traces.removeAll { $0.retired.map { Date().timeIntervalSince($0) >= 1.25 } ?? false }
        }
    }

    // Lavender traces with a pale leading edge.
    private static let brand = Color(red: 187/255, green: 166/255, blue: 244/255)
    private static let highlight = Color(red: 230/255, green: 221/255, blue: 255/255)

    private func stroke(_ path: Path, from start: Double, length: Double,
                        in context: inout GraphicsContext, color: Color, width: CGFloat) {
        let start = start - floor(start)
        let end = start + length
        let style = StrokeStyle(lineWidth: width, lineCap: .round)
        context.stroke(path.trimmedPath(from: start, to: min(1, end)), with: .color(color), style: style)
        if end > 1 {
            context.stroke(path.trimmedPath(from: 0, to: end - 1), with: .color(color), style: style)
        }
    }
}
