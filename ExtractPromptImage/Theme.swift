import SwiftUI
import AppKit

enum Theme {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.45, green: 0.82, blue: 0.68, alpha: 1)
            : NSColor(srgbRed: 0.12, green: 0.48, blue: 0.40, alpha: 1)
    })

    static let accentSoft = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.70, green: 0.92, blue: 0.84, alpha: 1)
            : NSColor(srgbRed: 0.10, green: 0.42, blue: 0.36, alpha: 1)
    })

    static let accentButton = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.22, green: 0.55, blue: 0.44, alpha: 1)
            : NSColor(srgbRed: 0.16, green: 0.52, blue: 0.42, alpha: 1)
    })

    static let primaryText = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    static let quaternaryText = Color(nsColor: .quaternaryLabelColor)

    static let separator = Color(nsColor: .separatorColor)

    static let panelFill = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.05)
            : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.04)
    })

    static let panelFillStrong = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10)
            : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.07)
    })

    static let panelStroke = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10)
            : NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.08)
    })

    static let sidebarBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.22)
            : NSColor(srgbRed: 0.96, green: 0.97, blue: 0.96, alpha: 1)
    })

    static let chipBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.08)
            : NSColor(srgbRed: 0.12, green: 0.48, blue: 0.40, alpha: 0.10)
    })

    static func backgroundGradient(for scheme: ColorScheme) -> LinearGradient {
        if scheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.09, blue: 0.11),
                    Color(red: 0.10, green: 0.14, blue: 0.13),
                    Color(red: 0.08, green: 0.10, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.97, blue: 0.96),
                Color(red: 0.92, green: 0.95, blue: 0.94),
                Color(red: 0.94, green: 0.96, blue: 0.97)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func glowPrimary(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.18, green: 0.45, blue: 0.38).opacity(0.18)
            : Color(red: 0.18, green: 0.55, blue: 0.45).opacity(0.14)
    }

    static func glowSecondary(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.55, green: 0.42, blue: 0.18).opacity(0.10)
            : Color(red: 0.75, green: 0.62, blue: 0.28).opacity(0.12)
    }
}
