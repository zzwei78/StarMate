import Foundation

// MARK: - OTA State
enum OTAState: Equatable {
    case idle
    case writing(progress: Int)
    case verifying
    case success
    case failed(reason: String)

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    var progress: Int {
        if case .writing(let p) = self { return p }
        return 0
    }
}

// MARK: - OTA Target
enum OTATarget: String {
    case mcu = "MCU"
    case ttModule = "TT"
}
