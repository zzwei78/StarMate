import Foundation
import SwiftUI

/// Recording preferences stored in UserDefaults
class RecordingPreferences: ObservableObject {
    static let shared = RecordingPreferences()

    @AppStorage("allow_call_recording") var allowCallRecording: Bool = false

    private init() {}

    func setAllowCallRecording(_ enabled: Bool) {
        allowCallRecording = enabled
    }
}
