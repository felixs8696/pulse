import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let output = root.appendingPathComponent("build/AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let logoURL = root.appendingPathComponent("Sources/Pulse/Resources/Comet/comet-poses.png")
guard let atlas = NSImage(contentsOf: logoURL) else { fatalError("Missing Pulse mascot") }
let side = atlas.size.width / 3
let logo = NSImage(size: NSSize(width: side, height: atlas.size.height), flipped: false) { destination in
    atlas.draw(in: destination, from: NSRect(x: side * 2, y: 0, width: side, height: atlas.size.height),
               operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    return true
}
// Export the same pose for the README, directly from the bundled sprite cell.
let logoBitmap = NSBitmapImageRep(data: logo.tiffRepresentation!)!
try logoBitmap.representation(using: .png, properties: [:])!
    .write(to: root.appendingPathComponent("docs/images/pulse-logo.png"))
logo.isTemplate = false
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(red: 20/255, green: 21/255, blue: 26/255, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 184, yRadius: 184).fill()
        logo.draw(in: NSRect(x: 172, y: 172, width: 680, height: 680))
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!
            .write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
