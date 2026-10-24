import SwiftUI

@main
struct ExtractPromptImageApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 880, minHeight: 560)
                // Follow macOS System Settings → Appearance.
                .preferredColorScheme(nil)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1040, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Image…") {
                    NotificationCenter.default.post(name: .openImagePicker, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let openImagePicker = Notification.Name("openImagePicker")
}
