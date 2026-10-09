import AppKit
import SwiftUI

// `Inkling --render-icon <dir>` renders the app icon PNGs from the same SwiftUI
// view used in the app, so the icon and the in-app logo never drift apart.
if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--render-icon" {
    MainActor.assumeIsolated { IconRenderer.render(to: URL(fileURLWithPath: CommandLine.arguments[2])) }
    exit(0)
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
