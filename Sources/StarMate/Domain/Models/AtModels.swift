import Foundation

// MARK: - AT Response
/// AT command response types
enum AtResponse: Equatable {
    case success(data: String)
    case error(code: Int, message: String)
    case cmeError(code: Int)
    case cmsError(code: Int)
    case timeout(command: String)

    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    var data: String? {
        if case .success(let data) = self { return data }
        return nil
    }
}

// MARK: - AT Notification
/// AT unsolicited notification (URC)
struct AtNotification: Equatable {
    let type: NotificationType
    let data: String
}

// MARK: - Notification Type
/// Types of AT URC notifications
enum NotificationType: String, Codable {
    case callIncoming    // +CLIP / RING
    case smsReceived     // +CMTI
    case networkReg      // +CREG
    case callStatus      // +CLCC
    case unknown
}

// MARK: - AT Response Parser
/// Parser for AT command responses
struct AtResponseParser {

    /// Parse a raw AT response string
    /// - Parameter response: Raw response string
    /// - Returns: Parsed AtResponse
    static func parse(_ response: String) -> AtResponse {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for OK
        if trimmed.hasSuffix("OK") || trimmed.contains("\nOK") {
            let data = trimmed
                .replacingOccurrences(of: "\nOK", with: "")
                .replacingOccurrences(of: "OK", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .success(data: data)
        }

        // Check for ERROR
        if trimmed.contains("ERROR") {
            return .error(code: -1, message: trimmed)
        }

        // Check for +CME ERROR
        if let range = trimmed.range(of: "+CME ERROR:") {
            let codeStr = trimmed[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if let code = Int(codeStr) {
                return .cmeError(code: code)
            }
        }

        // Check for +CMS ERROR
        if let range = trimmed.range(of: "+CMS ERROR:") {
            let codeStr = trimmed[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if let code = Int(codeStr) {
                return .cmsError(code: code)
            }
        }

        // Default: treat as success with data
        return .success(data: trimmed)
    }

    /// Parse +CSQ response: +CSQ: <rssi>,<ber>
    /// - Parameter response: Raw response string
    /// - Returns: (rssi, ber) tuple or nil
    static func parseCsq(_ response: String) -> (rssi: Int, ber: Int)? {
        guard response.contains("+CSQ:") else { return nil }

        let parts = response.replacingOccurrences(of: "+CSQ: ", with: "")
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }

        guard parts.count >= 2 else { return nil }
        return (rssi: parts[0], ber: parts[1])
    }

    /// Map CSQ rssi value (0-31, 99) to signal bars (0-5)
    /// - Parameter rssi: Raw RSSI value from AT+CSQ
    /// - Returns: Signal strength in bars (0-5)
    static func mapCsqToBars(_ rssi: Int) -> Int {
        switch rssi {
        case 0, 99: return 0
        case 1...4: return 1
        case 5...9: return 2
        case 10...14: return 3
        case 15...19: return 4
        case 20...31: return 5
        default: return 0
        }
    }

    /// Parse +CREG response: +CREG: <n>,<stat>[,<lac>,<ci>] or +CREG: <stat>
    /// - Parameter response: Raw response string
    /// - Returns: NetworkRegistrationStatus
    static func parseCreg(_ response: String) -> NetworkRegistrationStatus? {
        guard response.contains("+CREG:") else { return nil }

        // Extract all digits
        let digits = response.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }

        // The last digit is the stat when format is +CREG: <n>,<stat>
        // Or it's the only digit when format is +CREG: <stat>
        guard let stat = digits.last else { return nil }

        switch stat {
        case 0:
            return .notRegistered
        case 1:
            return .registered(isRoaming: false)
        case 2:
            return .searching
        case 3:
            return .registrationDenied
        case 4:
            return .unknown
        case 5:
            return .registered(isRoaming: true)
        default:
            return .unknown
        }
    }

    /// Parse +CPIN? response
    /// - Parameter response: Raw response string
    /// - Returns: SimState
    static func parseCpin(_ response: String) -> SimState {
        let trimmed = response.uppercased()

        if trimmed.contains("READY") {
            return .ready
        } else if trimmed.contains("SIM PIN") && !trimmed.contains("PUK") && !trimmed.contains("2") {
            return .simPinRequired(remainingAttempts: 3)
        } else if trimmed.contains("SIM PUK") && !trimmed.contains("2") {
            return .simPukRequired(remainingAttempts: 10)
        } else if trimmed.contains("SIM PIN2") {
            return .simPin2Required(remainingAttempts: 3)
        } else if trimmed.contains("SIM PUK2") {
            return .simPuk2Required(remainingAttempts: 10)
        } else if trimmed.contains("PH-SIM PIN") {
            return .phSimPinRequired(remainingAttempts: 3)
        } else if trimmed.contains("NOT INSERTED") || trimmed.contains("NOT READY") {
            return .absent
        } else if trimmed.contains("ERROR") {
            return .error
        }

        return .unknown
    }
}
