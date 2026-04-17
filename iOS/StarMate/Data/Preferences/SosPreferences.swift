import Foundation
import Combine

// MARK: - SOS Preferences
/// Persists SOS slot configuration via UserDefaults.
class SosPreferences: ObservableObject {

    static let shared = SosPreferences()

    private let defaults = UserDefaults.standard
    private let kSmsSlots = "sos_sms_slots"
    private let kCallSlots = "sos_call_slots"
    private let kSmsContent = "sos_sms_content"

    @Published var slots: SosSlotsSnapshot {
        didSet {
            saveSlots()
        }
    }

    private var debounceTask: Task<Void, Never>?

    init() {
        self.slots = Self.loadSlots()
    }

    // MARK: - Debounced Save

    func updateSlotsDebounced(_ update: (inout SosSlotsSnapshot) -> Void) {
        update(&slots)
        // Debounce is handled by didSet → saveSlots()
    }

    private func saveSlots() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000) // 400ms debounce
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(self.slots) {
                self.defaults.set(data, forKey: self.kSmsSlots)
            }
        }
    }

    // MARK: - Load

    private static func loadSlots() -> SosSlotsSnapshot {
        let defaults = UserDefaults.standard

        // Try new format (Codable)
        if let data = defaults.data(forKey: "sos_sms_slots"),
           let snapshot = try? JSONDecoder().decode(SosSlotsSnapshot.self, from: data) {
            return snapshot
        }

        // Legacy migration: comma-separated values
        var slots = SosSlotsSnapshot.empty()
        if let sms1 = defaults.string(forKey: "sos_sms_slot_1") {
            slots.smsSlots[0] = sms1
            slots.smsSlots[1] = defaults.string(forKey: "sos_sms_slot_2") ?? ""
            slots.smsSlots[2] = defaults.string(forKey: "sos_sms_slot_3") ?? ""
            slots.callSlots[0] = defaults.string(forKey: "sos_call_slot_1") ?? ""
            slots.callSlots[1] = defaults.string(forKey: "sos_call_slot_2") ?? ""
            slots.callSlots[2] = defaults.string(forKey: "sos_call_slot_3") ?? ""
            slots.smsCustom = defaults.string(forKey: "sos_sms_content") ?? ""
        }

        return slots
    }
}
