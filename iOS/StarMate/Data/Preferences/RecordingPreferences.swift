import Foundation
import SwiftUI
import Combine

/// Recording preferences stored in UserDefaults
class RecordingPreferences: ObservableObject {
    static let shared = RecordingPreferences()

    @Published var allowCallRecording: Bool = {
        UserDefaults.standard.bool(forKey: "allow_call_recording")
    }()

    private init() {}

    func setAllowCallRecording(_ enabled: Bool) {
        allowCallRecording = enabled
        UserDefaults.standard.set(enabled, forKey: "allow_call_recording")
    }
}
