import Foundation

// MARK: - AT Command Constants
/// AT command string constants.
/// All AT commands must be defined here; hardcoding in business logic is forbidden.
enum AtCommands {
    // ========== Basic Commands ==========
    static let AT = "AT"
    static let ATI = "ATI"

    // ========== Device Identification ==========
    /// Get manufacturer: AT+GMI
    static let GET_MANUFACTURER = "AT+GMI"
    /// Get model: AT+GMM
    static let GET_MODEL = "AT+GMM"
    /// Get software version: AT+GMR
    static let GET_SW_VERSION = "AT+GMR"
    /// Get hardware version: AT^HVER
    static let GET_HW_VERSION = "AT^HVER"
    /// Get IMEI: AT+GSN (or AT+CGSN)
    static let GET_IMEI = "AT+GSN"
    /// Get IMSI: AT+CIMI
    static let GET_IMSI = "AT+CIMI"
    /// Get CCID/ICCID: AT+CCID
    static let GET_CCID = "AT+CCID"

    // ========== SIM Card ==========
    /// Get SIM state: AT+CPIN?
    static let GET_SIM_STATE = "AT+CPIN?"
    /// Enter PIN: AT+CPIN="<pin>"
    static func enterPin(_ pin: String) -> String { "AT+CPIN=\"\(pin)\"" }
    /// Enter PUK: AT+CPIN="<puk>","<newPin>"
    static func enterPuk(_ puk: String, _ newPin: String) -> String { "AT+CPIN=\"\(puk)\",\"\(newPin)\"" }

    // ========== Network ==========
    /// Get signal strength: AT+CSQ
    static let GET_SIGNAL = "AT+CSQ"
    /// Get network registration: AT+CREG?
    static let GET_NETWORK_REG = "AT+CREG?"
    /// Enable network registration notification: AT+CREG=2
    static let ENABLE_NETWORK_REG_NOTIFY = "AT+CREG=2"
    /// Get operator: AT+COPS?
    static let GET_OPERATOR = "AT+COPS?"

    // ========== Call Management ==========
    /// Dial number: ATD<number>;
    static func dial(_ number: String) -> String { "ATD\(number);" }
    /// Answer call: ATA
    static let ANSWER = "ATA"
    /// Hang up: AT+CHUP
    static let HANGUP = "AT+CHUP"
    /// Get call list: AT+CLCC
    static let GET_CALL_LIST = "AT+CLCC"
    /// Enable caller ID: AT+CLIP=1
    static let ENABLE_CALLER_ID = "AT+CLIP=1"
    /// Send DTMF: AT+VTS="<dtmf>"
    static func sendDtmf(_ dtmf: String) -> String { "AT+VTS=\"\(dtmf)\"" }

    // ========== SMS Management ==========
    /// Set text mode: AT+CMGF=1
    static let SET_TEXT_MODE = "AT+CMGF=1"
    /// Send SMS: AT+CMGS="<number>",129
    static func sendSms(_ number: String) -> String { "AT+CMGS=\"\(number)\",129" }
    /// Get all SMS: AT+CMGL="ALL"
    static let GET_ALL_SMS = "AT+CMGL=\"ALL\""
    /// Get unread SMS: AT+CMGL="REC UNREAD"
    static let GET_UNREAD_SMS = "AT+CMGL=\"REC UNREAD\""
    /// Read SMS by index: AT+CMGR=<index>
    static func readSms(_ index: Int) -> String { "AT+CMGR=\(index)" }
    /// Delete SMS by index: AT+CMGD=<index>
    static func deleteSms(_ index: Int) -> String { "AT+CMGD=\(index)" }
    /// Delete all SMS: AT+CMGD=1,4
    static let DELETE_ALL_SMS = "AT+CMGD=1,4"
    /// Set new message indicator: AT+CNMI=2,1,0,0,0
    static let SET_NEW_MSG_INDICATOR = "AT+CNMI=2,1,0,0,0"
    /// Get SMSC: AT+CSCA?
    static let GET_SMSC = "AT+CSCA?"
    /// Set SMSC: AT+CSCA="<number>",<type>
    static func setSmsc(_ number: String, _ type: Int = 129) -> String { "AT+CSCA=\"\(number)\",\(type)" }

    // ========== Control Characters ==========
    /// Ctrl-Z for SMS send termination
    static let CTRL_Z = "\u{1A}"
    /// Carriage return
    static let CR = "\r"
}
