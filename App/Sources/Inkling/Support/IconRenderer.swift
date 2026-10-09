import AppKit
import SwiftUI

@MainActor
enum IconRenderer {
    /// Writes an .iconset folder (all sizes macOS needs).
    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let sizes: [(String, CGFloat)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for (name, px) in sizes {
            // macOS icons sit on a transparent canvas with ~10% margin.
            let view = InklingMark(size: px * 0.805)
                .frame(width: px, height: px)
                .shadow(color: .black.opacity(px > 64 ? 0.22 : 0), radius: px * 0.018, y: px * 0.012)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            renderer.isOpaque = false
            guard let cg = renderer.cgImage else { continue }
            let rep = NSBitmapImageRep(cgImage: cg)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }
    }
}
