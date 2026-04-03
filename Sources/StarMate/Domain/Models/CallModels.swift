import Foundation

// MARK: - Call State
/// Call state machine for satellite phone calls
enum CallState: Equatable {
    case idle
    case dialing(phoneNumber: String)
    case incoming(phoneNumber: String)
    case connected(phoneNumber: String, startTime: Date)
    case ending(reason: EndReason)

    var isInCall: Bool {
        switch self {
        case .dialing, .incoming, .connected:
            return true
        default:
            return false
        }
    }

    var phoneNumber: String? {
        switch self {
        case .dialing(let num), .incoming(let num), .connected(let num, _):
            return num
        default:
            return nil
        }
    }
}

// MARK: - End Reason
/// Reason for call termination
enum EndReason: String, Codable {
    case localHangup
    case remoteHangup
    case bleDisconnected
    case moduleError
}

// MARK: - Active Call
/// Active call information
struct ActiveCall: Equatable {
    let phoneNumber: String
    let startTime: Date
    var isSpeakerOn: Bool = false
    let callState: CallState

    /// Call duration in seconds
    var duration: TimeInterval {
        return Date().timeIntervalSince(startTime)
    }

    /// Formatted duration string (MM:SS)
    var durationText: String {
        let duration = Int(self.duration)
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Incoming Call
/// Incoming call notification from AT+CLIP
struct IncomingCall: Equatable {
    let phoneNumber: String
    let numberType: Int
    let name: String?
    let timestamp: Date
}

// MARK: - DTMF Key
/// DTMF key definitions for in-call keypad
enum DtmfKey: String, CaseIterable {
    case key0 = "0"
    case key1 = "1"
    case key2 = "2"
    case key3 = "3"
    case key4 = "4"
    case key5 = "5"
    case key6 = "6"
    case key7 = "7"
    case key8 = "8"
    case key9 = "9"
    case keyStar = "*"
    case keyHash = "#"
    case keyA = "A"
    case keyB = "B"
    case keyC = "C"
    case keyD = "D"

    var value: String {
        return rawValue
    }
}

// MARK: - Audio Mode
/// Audio output mode during calls
enum AudioMode: String, Codable {
    case speaker
    case earpiece
}

// MARK: - Voice Packet
/// Voice data packet for GATT Voice Service
struct VoicePacket: Equatable {
    let data: Data
    let timestamp: Date
    let sequenceNumber: Int
}
