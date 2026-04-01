import SwiftUI

// MARK: - iOS-inspired Color Scheme
extension Color {
    // System Colors (iOS style)
    static let systemBlue = Color(red: 0/255, green: 122/255, blue: 255/255)
    static let systemBlueDark = Color(red: 10/255, green: 132/255, blue: 255/255)
    static let systemGray = Color(red: 142/255, green: 142/255, blue: 147/255)
    static let systemGray2 = Color(red: 174/255, green: 174/255, blue: 178/255)
    static let systemGray3 = Color(red: 199/255, green: 199/255, blue: 204/255)
    static let systemGray4 = Color(red: 209/255, green: 209/255, blue: 214/255)
    static let systemGray5 = Color(red: 229/255, green: 229/255, blue: 234/255)
    static let systemGray6 = Color(red: 242/255, green: 242/255, blue: 247/255)
    static let systemRed = Color(red: 255/255, green: 59/255, blue: 48/255)
    static let systemGreen = Color(red: 52/255, green: 199/255, blue: 89/255)
    static let systemOrange = Color(red: 255/255, green: 149/255, blue: 0/255)

    // Card Backgrounds
    static let cardBackgroundLight = Color(red: 242/255, green: 244/255, blue: 245/255)
    static let cardBackgroundDark = Color(red: 42/255, green: 42/255, blue: 44/255)

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
