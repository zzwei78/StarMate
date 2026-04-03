import Foundation
import CoreBluetooth
import Combine

// MARK: - AT Service Client Implementation
/// GATT AT Command Service client (UUID: 0xABF2).
/// Handles AT command send/receive and URC notification dispatch.
final class AtServiceClientImpl: AtServiceClientProtocol {

    // MARK: - Streams
    nonisolated(unsafe) private var responseContinuations: [String: CheckedContinuation<AtResponse, Never>] = [:]
    private var responseQueue = DispatchQueue(label: "com.starmate.at.response")

    private var responseStreamContinuation: AsyncStream<AtResponse>.Continuation?
    lazy var responseStream: AsyncStream<AtResponse> = {
        AsyncStream { continuation in
            self.responseStreamContinuation = continuation
        }
    }()

    private var urcStreamContinuation: AsyncStream<AtNotification>.Continuation?
    lazy var urcStream: AsyncStream<AtNotification> = {
        AsyncStream { continuation in
            self.urcStreamContinuation = continuation
        }
    }()

    // MARK: - Private Properties
    private weak var peripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var responseCharacteristic: CBCharacteristic?

    private var atResponseBuffer = ""
    private var currentCommand: String?

    // MARK: - Initialization
    init() {}

    // MARK: - GATT Setup

    /// Set peripheral and characteristics after discovery
    func setPeripheral(_ peripheral: CBPeripheral, characteristics: [CBCharacteristic]) {
        self.peripheral = peripheral
        atResponseBuffer = ""

        for char in characteristics {
            switch char.uuid {
            case BleUuid.AT_COMMAND:
                commandCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
                print("[AtService] ✅ Command characteristic found (0xABF3), notifications enabled")
            case BleUuid.AT_RESPONSE:
                responseCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
                print("[AtService] ✅ Response characteristic found (0xABF1), notifications enabled")
            default:
                break
            }
        }

        if commandCharacteristic == nil {
            print("[AtService] ❌ Command characteristic NOT found")
        }
    }

    /// Clear GATT references on disconnect
    func clearGattReferences() {
        peripheral = nil
        commandCharacteristic = nil
        responseCharacteristic = nil
        atResponseBuffer = ""
        currentCommand = nil

        // Fail all pending responses
        responseQueue.sync(execute: {
            for (_, continuation) in responseContinuations {
                continuation.resume(returning: .timeout(command: ""))
            }
            responseContinuations.removeAll()
        })
    }

    // MARK: - Protocol: AtServiceClientProtocol

    func onGattClosed() {
        clearGattReferences()
    }

    func sendCommand(_ command: String) async -> Result<String, Error> {
        return await sendCommand(command, timeoutMs: 30_000)
    }

    func sendCommand(_ command: String, timeoutMs: Int64) async -> Result<String, Error> {
        guard let char = commandCharacteristic ?? responseCharacteristic else {
            return .failure(NSError(domain: "AtService", code: -1, userInfo: [NSLocalizedDescriptionKey: "AT characteristic not found"]))
        }
        guard let peripheral = peripheral else {
            return .failure(NSError(domain: "AtService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Peripheral not connected"]))
        }

        // Normalize command (ensure CR suffix)
        var cmd = command
        if !cmd.hasSuffix("\r") {
            cmd += "\r"
        }

        // Clear buffer and set current command
        atResponseBuffer = ""
        currentCommand = command

        let responseData = await withCheckedContinuation { (continuation: CheckedContinuation<AtResponse, Never>) in
            responseQueue.sync(execute: {
                self.responseContinuations[command] = continuation
            })

            // Set timeout
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
                responseQueue.sync(execute: {
                    if let cont = self.responseContinuations.removeValue(forKey: command) {
                        cont.resume(returning: .timeout(command: command))
                    }
                })
            }

            // Send command
            let data = cmd.data(using: .utf8)!
            peripheral.writeValue(data, for: char, type: .withResponse)
        }

        // Convert AtResponse to Result<String, Error>
        switch responseData {
        case .success(let data):
            return .success(data)
        case .error(let code, let msg):
            return .failure(NSError(domain: "AtService", code: code, userInfo: [NSLocalizedDescriptionKey: msg]))
        case .cmeError(let code):
            return .failure(NSError(domain: "AtService", code: Int(code), userInfo: [NSLocalizedDescriptionKey: "CME ERROR: \(code)"]))
        case .cmsError(let code):
            return .failure(NSError(domain: "AtService", code: Int(code), userInfo: [NSLocalizedDescriptionKey: "CMS ERROR: \(code)"]))
        case .timeout:
            return .failure(NSError(domain: "AtService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Timeout"]))
        }
    }

    func sendCommandNoWait(_ command: String) async -> Result<Void, Error> {
        guard let char = commandCharacteristic ?? responseCharacteristic else {
            return .failure(NSError(domain: "AtService", code: -1, userInfo: [NSLocalizedDescriptionKey: "AT characteristic not found"]))
        }
        guard let peripheral = peripheral else {
            return .failure(NSError(domain: "AtService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Peripheral not connected"]))
        }

        var cmd = command
        if !cmd.hasSuffix("\r") {
            cmd += "\r"
        }

        let data = cmd.data(using: .utf8)!
        peripheral.writeValue(data, for: char, type: .withResponse)
        return .success(())
    }

    // MARK: - Notification Handling

    /// Handle notification data from BLEManager
    func handleNotification(data: Data, from characteristic: CBCharacteristic) {
        guard let text = String(data: data, encoding: .utf8) else { return }

        // Check for URC (unsolicited result code) - no pending command
        if currentCommand == nil {
            handleUrc(text)
            return
        }

        // Accumulate response
        if !atResponseBuffer.isEmpty {
            atResponseBuffer += "\n"
        }
        atResponseBuffer += text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for terminal markers
        if atResponseBuffer.contains("OK") {
            completeResponse(.success(data: atResponseBuffer.replacingOccurrences(of: "\nOK", with: "").replacingOccurrences(of: "OK", with: "").trimmingCharacters(in: .whitespacesAndNewlines)))
        } else if atResponseBuffer.contains("ERROR") {
            completeResponse(.error(code: -1, message: atResponseBuffer))
        } else if atResponseBuffer.contains("+CME ERROR") {
            if let code = parseErrorCode(atResponseBuffer, prefix: "+CME ERROR:") {
                completeResponse(.cmeError(code: code))
            } else {
                completeResponse(.error(code: -1, message: atResponseBuffer))
            }
        } else if atResponseBuffer.contains("+CMS ERROR") {
            if let code = parseErrorCode(atResponseBuffer, prefix: "+CMS ERROR:") {
                completeResponse(.cmsError(code: code))
            } else {
                completeResponse(.error(code: -1, message: atResponseBuffer))
            }
        }
    }

    private func completeResponse(_ response: AtResponse) {
        guard let cmd = currentCommand else { return }

        currentCommand = nil
        atResponseBuffer = ""

        responseQueue.sync(execute: {
            if let continuation = responseContinuations.removeValue(forKey: cmd) {
                continuation.resume(returning: response)
            }
        })

        // Also emit to stream
        responseStreamContinuation?.yield(response)
    }

    private func handleUrc(_ text: String) {
        let notificationType: NotificationType

        if text.contains("RING") || text.contains("+CLIP:") {
            notificationType = .callIncoming
        } else if text.contains("+CMTI:") {
            notificationType = .smsReceived
        } else if text.contains("+CREG:") {
            notificationType = .networkReg
        } else if text.contains("+CLCC:") {
            notificationType = .callStatus
        } else {
            notificationType = .unknown
        }

        let notification = AtNotification(type: notificationType, data: text)
        urcStreamContinuation?.yield(notification)

        // Also post to NotificationCenter for backward compatibility
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .atUrcReceived, object: notification)
        }
    }

    private func parseErrorCode(_ text: String, prefix: String) -> Int? {
        guard let range = text.range(of: prefix) else { return nil }
        let codeStr = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(codeStr)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let atUrcReceived = Notification.Name("atUrcReceived")
}
