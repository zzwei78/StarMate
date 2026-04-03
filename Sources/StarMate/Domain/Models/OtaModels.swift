import Foundation

// MARK: - OTA State
/// OTA upgrade state machine
enum OtaState: Equatable {
    case idle
    case writing(progress: Int)
    case verifying
    case success
    case failed(reason: String)

    var isInProgress: Bool {
        switch self {
        case .writing, .verifying:
            return true
        default:
            return false
        }
    }

    var progress: Int {
        switch self {
        case .writing(let p): return p
        case .verifying: return 100
        case .success: return 100
        default: return 0
        }
    }
}

// MARK: - OTA Target
/// OTA target types
enum OtaTarget: String, Codable {
    case mcu         // Terminal MCU firmware
    case ttModule    // TT satellite module firmware
}

// MARK: - OTA Progress Info
/// OTA progress information
struct OtaProgressInfo: Equatable {
    let state: OtaState
    let target: OtaTarget
    let bytesWritten: Int
    let totalBytes: Int
    let percentage: Int

    var progressText: String {
        switch state {
        case .idle:
            return "准备中"
        case .writing:
            return "正在写入 \(percentage)%"
        case .verifying:
            return "正在验证..."
        case .success:
            return "升级成功"
        case .failed(let reason):
            return "升级失败: \(reason)"
        }
    }
}
