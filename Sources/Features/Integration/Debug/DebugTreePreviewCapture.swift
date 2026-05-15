import AppKit
import CoreGraphics

enum DebugTreePreviewCapture {
    static func capture(region: CGRect) -> NSImage? {
        guard let cgImage = CGWindowListCreateImage(
            region,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: region.width, height: region.height))
    }
}

