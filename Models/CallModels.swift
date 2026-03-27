import Foundation

// MARK: - Call State
enum CallState: Equatable {
    case idle
    case dialing(phoneNumber: String)
    case connected(phoneNumber: String, startTime: Date)
    case incoming(phoneNumber: String)
    case ending

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isDialing: Bool {
        if case .dialing = self { return true }
        return false
    }
}

// MARK: - Call Record
struct CallRecord: Identifiable, Codable, Equatable {
    let id: String
    let phoneNumber: String
    let contactName: String?
    let callType: CallType
    let callStatus: CallStatus
    let startTime: Date
    let duration: TimeInterval

    init(id: String = UUID().uuidString,
         phoneNumber: String,
         contactName: String? = nil,
         callType: CallType,
         callStatus: CallStatus,
         startTime: Date = Date(),
         duration: TimeInterval = 0) {
        self.id = id
        self.phoneNumber = phoneNumber
        self.contactName = contactName
        self.callType = callType
        self.callStatus = callStatus
        self.startTime = startTime
        self.duration = duration
    }
}

// MARK: - Call Type
enum CallType: String, Codable {
    case incoming
    case outgoing
    case missed

    var icon: String {
        switch self {
        case .incoming: return "phone.arrow.down.left"
        case .outgoing: return "phone.arrow.up.right"
        case .missed: return "phone.arrow.down.left"
        }
    }

    var color: Color {
        switch self {
        case .incoming, .outgoing: return .systemBlue
        case .missed: return .systemRed
        }
    }
}

// MARK: - Call Status
enum CallStatus: String, Codable {
    case completed
    case rejected
    case missed
}

// MARK: - Call Duration Formatter
extension CallRecord {
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes)′\(seconds)″"
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: startTime)
    }

    var subtitle: String {
        if duration > 0 {
            return "\(formattedTime) · \(formattedDuration)"
        }
        return formattedTime
    }
}
