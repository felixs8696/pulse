import AppKit

/// App bundles must be self-contained. SwiftPM's generated Bundle.module accessor
/// searches beside the executable and then the build machine's absolute path,
/// which does not match a macOS app's Contents/Resources layout.
enum AppResources {
    static let bundle: Bundle? = {
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let url = Bundle.main.url(forResource: "Pulse_Pulse", withExtension: "bundle") else { return nil }
            return Bundle(url: url)
        }
        return Bundle.module
    }()

    /// Packaging smoke test. Does not start the app, scan chats, or install hooks.
    @MainActor
    static func verifyPackagedArtwork() -> Bool {
        guard Bundle.main.bundleURL.pathExtension == "app",
              let bundle,
              let resources = Bundle.main.resourceURL,
              bundle.bundleURL.resolvingSymlinksInPath().path.hasPrefix(resources.resolvingSymlinksInPath().path + "/") else {
            print("FAIL: packaged resource bundle is missing")
            return false
        }
        for name in ["claude", "cursor-light", "cursor-dark", "openai-light", "openai-dark"] {
            guard let image = BrandArtwork.image(name), image.isValid else {
                print("FAIL: provider artwork is missing or unreadable")
                return false
            }
        }
        for mood in [CometArtwork.Mood.idle, .working, .ready] {
            let image = CometPoseAtlas.image(mood)
            guard image.size.width > 0, image.size.height > 0, image.tiffRepresentation != nil else {
                print("FAIL: mascot artwork is missing or unreadable")
                return false
            }
        }
        print("PASS: packaged provider logos and all three mascot poses load")
        return true
    }
}
