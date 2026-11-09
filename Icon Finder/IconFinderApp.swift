import SwiftUI
import AppKit

@main struct IconFinderApp: App {
    var body: some Scene {
        WindowGroup("IconFinder") {
            ContentView()
        }
        .defaultSize(width: 1000, height: 650)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About IconFinder") {
                    showAboutPanel()
                }
            }
        }
    }

    /// Shows the standard About panel with author and license credits.
    /// Name, version and copyright come from Info.plist.
    private func showAboutPanel() {
        let credits = NSMutableAttributedString(
            string: "Created by Russell Collis\n\n",
            attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)]
        )
        credits.append(NSAttributedString(
            string: "Extracts icons from .app bundles, .pkg installers and .dmg disk images as PNG files.\n\n"
                + "Released under the MIT License.",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
        ))
        credits.addAttribute(
            .foregroundColor,
            value: NSColor.labelColor,
            range: NSRange(location: 0, length: credits.length)
        )

        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .credits: credits,
        ])
        NSApplication.shared.activate()
    }
}
