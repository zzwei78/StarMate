import Foundation

// MARK: - SOS Models

/// SOS configuration data
struct SosSlotsSnapshot: Codable, Equatable {
    var smsSlots: [String]   // 3 slots
    var callSlots: [String]  // 3 slots
    var smsCustom: String    // Custom message (max 20 chars)

    static let maxSmsContentLen = 20

    static func empty() -> SosSlotsSnapshot {
        SosSlotsSnapshot(
            smsSlots: ["", "", ""],
            callSlots: ["", "", ""],
            smsCustom: ""
        )
    }

    var configuredSmsCount: Int {
        smsSlots.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    var configuredCallCount: Int {
        callSlots.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    var hasAnyConfigured: Bool {
        configuredSmsCount > 0 || configuredCallCount > 0
    }
}
