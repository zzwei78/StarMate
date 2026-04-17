import Foundation

// MARK: - SOS Preview Template
/// Generates the SOS message body with GPS coordinates and map link.
/// Pure logic — no framework dependencies.
/// Ported from CosmoCat SosPreviewTemplate.kt
struct SosPreviewTemplate {

    /// Build the SOS message body.
    /// - Parameters:
    ///   - customContent: User-defined custom text (max 20 chars)
    ///   - latitude: GPS latitude (nil if unknown)
    ///   - longitude: GPS longitude (nil if unknown)
    /// - Returns: Complete SOS message string
    static func buildBody(
        customContent: String,
        latitude: Double?,
        longitude: Double?
    ) -> String {
        let timestamp = Self.formatTimestamp()

        let locationStr: String
        if let lat = latitude, let lon = longitude {
            let eW = lon >= 0 ? "E" : "W"
            let nS = lat >= 0 ? "N" : "S"
            locationStr = String(format: "\(eW)%.6f\u{00B0}, \(nS)%.6f\u{00B0}", abs(lon), abs(lat))
        } else {
            locationStr = "未知"
        }

        var lines: [String] = []
        lines.append("紧急求助")
        lines.append("时间: \(timestamp)")
        lines.append("位置: \(locationStr)")

        if let lat = latitude, let lon = longitude {
            lines.append("详情: https://uri.amap.com/marker?position=\(lon),\(lat)")
        }

        let trimmed = customContent.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            lines.append(trimmed)
        }

        return lines.joined(separator: "\n")
    }

    private static func formatTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: Date())
    }
}
