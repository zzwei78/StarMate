import Foundation
import CoreBluetooth

// MARK: - Voice Service Client Implementation

/// GATT Voice Service client (UUID: 0xABF0).
///
/// 负责通过 BLE 收发语音数据，不处理音频录制/播放。
///
/// ## 协议格式
/// - 数据包格式: `AT^AUDPCM="<base64>"`
/// - AMR 格式: Raw AMR-NB 帧 (MR122 模式, 32 bytes, 无文件头)
///
/// ## 上行流程 (发送)
/// ```
/// CallManager → sendAmrFrame(amrData) → 包装为 AT^AUDPCM → BLE VOICE_IN
/// ```
///
/// ## 下行流程 (接收)
/// ```
/// BLE VOICE_OUT → 解析 AT^AUDPCM → Base64 解码 → onAmrFrameReceived(amrData)
/// ```
@MainActor
final class VoiceServiceClientImpl: VoiceServiceClientProtocol {

    // MARK: - Constants

    private enum Constants {
        /// AT^AUDPCM 命令前缀
        static let prefix = "AT^AUDPCM=\""

        /// 命令后缀
        static let suffix = "\""

        /// 最大包大小 (BLE MTU 限制)
        static let maxPacketSize: Int = 512
    }

    // MARK: - Callbacks

    /// 下行 AMR 帧接收回调
    ///
    /// 当从 BLE 接收到 AMR 数据时触发，回调 raw AMR 帧 (无文件头)
    var onAmrFrameReceived: ((Data) -> Void)?

    // MARK: - Streams

    private var voiceDataStreamContinuation: AsyncStream<VoicePacket>.Continuation?

    /// 语音数据流 (用于监控/调试)
    lazy var voiceDataStream: AsyncStream<VoicePacket> = {
        AsyncStream { continuation in
            self.voiceDataStreamContinuation = continuation
        }
    }()

    // MARK: - Private Properties

    /// BLE 外设
    private weak var peripheral: CBPeripheral?

    /// VOICE_IN 特征值 (用于发送上行数据)
    private var voiceInChar: CBCharacteristic?

    /// VOICE_OUT 特征值 (用于接收下行数据)
    private var voiceOutChar: CBCharacteristic?

    /// VOICE_DATA 特征值 (备用特征值)
    private var voiceDataChar: CBCharacteristic?

    /// 接收缓冲区
    private var receiveBuffer = Data()

    /// 序列号计数器
    private var sequenceCounter = 0

    /// 统计信息
    private(set) var framesSent: Int = 0
    private(set) var framesReceived: Int = 0
    private(set) var bytesSent: Int = 0
    private(set) var bytesReceived: Int = 0

    // MARK: - Initialization

    init() {
        print("[VoiceServiceClient] Initialized")
    }

    // MARK: - GATT Setup

    /// 设置 BLE 外设和特征值 (在服务发现后调用)
    func setPeripheral(_ peripheral: CBPeripheral, characteristics: [CBCharacteristic]) {
        self.peripheral = peripheral

        for char in characteristics {
            switch char.uuid {
            case BleUuid.VOICE_IN:
                voiceInChar = char
                print("[VoiceServiceClient] ✅ VOICE_IN characteristic found (0xABEE)")

            case BleUuid.VOICE_OUT:
                voiceOutChar = char
                // 启用通知以接收下行数据
                peripheral.setNotifyValue(true, for: char)
                print("[VoiceServiceClient] ✅ VOICE_OUT characteristic found, notifications enabled (0xABEF)")

            case BleUuid.VOICE_DATA:
                voiceDataChar = char
                // 启用通知
                peripheral.setNotifyValue(true, for: char)
                print("[VoiceServiceClient] ✅ VOICE_DATA characteristic found (0xABF1)")

            default:
                break
            }
        }

        // 如果没有 VOICE_IN，使用 VOICE_DATA 作为备用
        if voiceInChar == nil && voiceDataChar != nil {
            voiceInChar = voiceDataChar
            print("[VoiceServiceClient] ⚠️ Using VOICE_DATA as fallback for VOICE_IN")
        }
    }

    /// 清除 GATT 引用 (断开连接时调用)
    func clearGattReferences() {
        peripheral = nil
        voiceInChar = nil
        voiceOutChar = nil
        voiceDataChar = nil
        receiveBuffer.removeAll()

        print("[VoiceServiceClient] GATT references cleared")
    }

    // MARK: - Protocol: VoiceServiceClientProtocol

    func onGattClosed() {
        clearGattReferences()
    }

    // MARK: - Notification Handling

    /// 处理 BLE 通知数据
    ///
    /// 由 BLEManager 在收到 VOICE_OUT 或 VOICE_DATA 通知时调用
    func handleNotification(data: Data, from characteristic: CBCharacteristic) {
        // 添加到接收缓冲区
        receiveBuffer.append(data)
        bytesReceived += data.count

        // 处理缓冲区中的完整数据包
        processReceiveBuffer()

        // 发送到数据流 (用于监控)
        let packet = VoicePacket(data: data, timestamp: Date(), sequenceNumber: sequenceCounter)
        voiceDataStreamContinuation?.yield(packet)
    }

    // MARK: - Send AMR Frame (Public API)

    /// 发送 AMR 帧到设备
    ///
    /// 将 AMR 数据包装为 `AT^AUDPCM="<base64>"` 格式并发送到 BLE。
    ///
    /// - Parameter amrData: Raw AMR 帧数据 (32 bytes, MR122 模式, 无文件头)
    /// - Returns: 发送结果
    func sendAmrFrame(_ amrData: Data) async -> Result<Void, Error> {
        guard let peripheral = peripheral else {
            let error = VoiceServiceError.notConnected
            print("[VoiceServiceClient] ❌ Send failed: \(error)")
            return .failure(error)
        }

        // 获取发送特征值
        let char = voiceInChar ?? voiceDataChar
        guard let characteristic = char else {
            let error = VoiceServiceError.characteristicNotFound
            print("[VoiceServiceClient] ❌ Send failed: \(error)")
            return .failure(error)
        }

        // 包装为 AT^AUDPCM="<base64>"
        guard let packet = wrapAmrFrame(amrData) else {
            let error = VoiceServiceError.encodingFailed
            print("[VoiceServiceClient] ❌ Send failed: \(error)")
            return .failure(error)
        }

        // 检查包大小
        guard packet.count <= Constants.maxPacketSize else {
            let error = VoiceServiceError.packetTooLarge(packet.count)
            print("[VoiceServiceClient] ❌ Send failed: \(error)")
            return .failure(error)
        }

        // 发送到 BLE
        peripheral.writeValue(packet, for: characteristic, type: .withoutResponse)

        // 更新统计
        framesSent += 1
        bytesSent += packet.count
        sequenceCounter += 1

        return .success(())
    }

    // MARK: - Legacy Support

    /// 发送语音数据 (旧接口，保持兼容)
    func sendVoiceData(_ data: Data) async -> Result<Void, Error> {
        return await sendAmrFrame(data)
    }

    // MARK: - Private Methods

    /// 包装 AMR 帧为 AT^AUDPCM 数据包
    private func wrapAmrFrame(_ amrData: Data) -> Data? {
        let base64 = amrData.base64EncodedString()
        let packet = "\(Constants.prefix)\(base64)\(Constants.suffix)"
        return packet.data(using: .utf8)
    }

    /// 处理接收缓冲区，提取完整的 AT^AUDPCM 数据包
    private func processReceiveBuffer() {
        while true {
            let buffer = receiveBuffer

            // 需要至少前缀长度
            guard buffer.count >= Constants.prefix.count else {
                break
            }

            // 查找前缀
            guard let prefixRange = buffer.range(of: Data(Constants.prefix.utf8)) else {
                // 没有找到前缀，丢弃到下一个换行符
                if let newlineRange = buffer.range(of: Data("\r\n".utf8)) {
                    receiveBuffer = buffer.dropFirst(newlineRange.upperBound)
                    continue
                }
                // 没有换行符，保留缓冲区等待更多数据
                break
            }

            // 前缀之后的位置
            let afterPrefix = prefixRange.upperBound
            guard afterPrefix < buffer.endIndex else {
                break
            }

            // 查找结束引号
            guard let endQuoteRange = buffer[afterPrefix...].firstIndex(of: UInt8(ascii: "\"")) else {
                // 没有找到结束引号，等待更多数据
                break
            }

            // 提取 base64 数据
            let base64Start = afterPrefix
            let base64End = endQuoteRange
            let base64Data = buffer[base64Start..<base64End]

            // 移除已处理的数据包 (包括结束引号)
            let packetEnd = buffer.index(after: endQuoteRange)
            receiveBuffer = buffer.dropFirst(packetEnd.count)

            // 解码 base64 并回调
            if let base64String = String(data: base64Data, encoding: .utf8),
               let amrData = Data(base64Encoded: base64String) {
                framesReceived += 1

                // 回调 AMR 帧
                onAmrFrameReceived?(amrData)

                // 日志 (每 50 帧打印一次)
                if framesReceived % 50 == 0 {
                    print("[VoiceServiceClient] 📥 Received frame #\(framesReceived), size: \(amrData.count) bytes")
                }
            } else {
                print("[VoiceServiceClient] ⚠️ Failed to decode base64 data")
            }
        }
    }

    // MARK: - Statistics

    /// 重置统计信息
    func resetStatistics() {
        framesSent = 0
        framesReceived = 0
        bytesSent = 0
        bytesReceived = 0
        sequenceCounter = 0
    }

    /// 打印统计信息
    func printStatistics() {
        print("[VoiceServiceClient] Statistics:")
        print("  - Frames sent: \(framesSent)")
        print("  - Frames received: \(framesReceived)")
        print("  - Bytes sent: \(bytesSent)")
        print("  - Bytes received: \(bytesReceived)")
    }
}

// MARK: - Voice Service Error

/// Voice Service 错误类型
enum VoiceServiceError: LocalizedError {
    case notConnected
    case characteristicNotFound
    case encodingFailed
    case packetTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "BLE peripheral not connected"
        case .characteristicNotFound:
            return "Voice characteristic not found"
        case .encodingFailed:
            return "Failed to encode AMR frame"
        case .packetTooLarge(let size):
            return "Packet too large: \(size) bytes (max: 512)"
        }
    }
}

// MARK: - Voice Packet

/// 语音数据包 (用于数据流)
struct VoicePacket {
    let data: Data
    let timestamp: Date
    let sequenceNumber: Int
}
