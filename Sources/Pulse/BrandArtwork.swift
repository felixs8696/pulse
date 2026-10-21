import AppKit
import SwiftUI

/// Bundled provider artwork and the app's original waveform mark.
enum BrandArtwork {
    private static let resources: Bundle = {
        if let url = Bundle.main.url(forResource: "Pulse_Pulse", withExtension: "bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return .module
    }()
    private static let images: [String: NSImage] = {
        var result: [String: NSImage] = [:]
        for name in ["claude", "cursor-light", "cursor-dark", "openai-light", "openai-dark", "pulse-mark"] {
            if let url = resources.url(forResource: name, withExtension: "svg", subdirectory: "Logos"),
               let image = NSImage(contentsOf: url) {
                image.isTemplate = false
                result[name] = image
            }
        }
        return result
    }()
    static func image(_ name: String) -> NSImage? { images[name] }

    static func titleFont(size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }
}

struct PulseLogo: View {
    var body: some View {
        if let image = BrandArtwork.image("pulse-mark") {
            Image(nsImage: image).resizable().renderingMode(.original).scaledToFit()
                .accessibilityLabel("Pulse")
        }
    }
}
