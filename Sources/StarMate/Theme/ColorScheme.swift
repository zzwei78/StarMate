import SwiftUI

// MARK: - iOS-inspired Color Scheme
extension Color {
    // System Colors
    static let systemBlue = Color(hex: "007AFF")
    static let systemBlueDark = Color(hex: "0A84FF")
    static let systemGray = Color(hex: "8E8E93")
    static let systemGray2 = Color(hex: "AEAEB2")
    static let systemGray3 = Color(hex: "C7C7CC")
    static let systemGray4 = Color(hex: "D1D1D6")
    static let systemGray5 = Color(hex: "E5E5EA")
    static let systemGray6 = Color(hex: "F2F2F7")
    static let systemRed = Color(hex: "FF3B30")
    static let systemGreen = Color(hex: "34C759")
    static let systemOrange = Color(hex: "FF9500")

    // Card Backgrounds
    static let cardBackgroundLight = Color(hex: "F2F4F5")
    static let cardBackgroundDark = Color(hex: "2A2A2C")

    // Convenience initializer for hex colors
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - App Colors
struct AppColors {
    static let primary = Color.systemBlue
    static let background = Color.systemGray6
    static let cardBackground = Color.cardBackgroundLight
    static let error = Color.systemRed
    static let success = Color.systemGreen
    static let textPrimary = Color.primary
    static let textSecondary = Color.systemGray

    // Dynamic colors for dark mode
    static func primaryBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.black : Color.systemGray6
    }

    static func cardBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.cardBackgroundDark : Color.cardBackgroundLight
    }
}
