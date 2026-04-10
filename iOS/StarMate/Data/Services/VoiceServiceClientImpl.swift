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

    /// 通话录音器 (由 BleManager 注入)
    var callRecorder: CallRecorderImpl?

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

    /// 上行帧时间戳记录（用于计算发送间隔）
    private var lastUplinkSendTime: Date?

    /// 下行帧时间戳记录（用于计算接收间隔）
    private var lastDownlinkReceiveTime: Date?

    // MARK: - Initialization

    init() {
        print("[VoiceServiceClient] Initialized")
    }

    // MARK: - GATT Setup

    /// 设置 BLE 外设和特征值 (在服务发现后调用)
    func setPeripheral(_ peripheral: CBPeripheral, characteristics: [CBCharacteristic]) {
        self.peripheral = peripheral

        print("[VoiceService] 🔧 Setting up peripheral with \(characteristics.count) characteristics")

        for char in characteristics {
            switch char.uuid {
            case BleUuid.VOICE_IN:
                voiceInChar = char
                print("[VoiceService] ✅ VOICE_IN characteristic found (\(char.uuid.uuidString))")

            case BleUuid.VOICE_OUT:
                voiceOutChar = char
                // 启用通知以接收下行数据
                peripheral.setNotifyValue(true, for: char)
                print("[VoiceService] ✅ VOICE_OUT characteristic found, notifications enabled (\(char.uuid.uuidString))")

            case BleUuid.VOICE_DATA:
                voiceDataChar = char
                // 启用通知
                peripheral.setNotifyValue(true, for: char)
                print("[VoiceService] ✅ VOICE_DATA characteristic found (\(char.uuid.uuidString))")

            default:
                print("[VoiceService] ⚠️ Unknown characteristic: \(char.uuid.uuidString)")
            }
        }

        // 如果没有 VOICE_IN，使用 VOICE_DATA 作为备用
        if voiceInChar == nil && voiceDataChar != nil {
            voiceInChar = voiceDataChar
            print("[VoiceService] ⚠️ Using VOICE_DATA as fallback for VOICE_IN")
        }

        print("[VoiceService] 📊 Setup complete - IN: \(voiceInChar != nil), OUT: \(voiceOutChar != nil), DATA: \(voiceDataChar != nil)")
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
        receiveBuffer.removeAll()
        voiceDataStreamContinuation?.finish()
    }

    // MARK: - Notification Handling

    /// 处理 BLE 通知数据
    ///
    /// 由 BLEManager 在收到 VOICE_OUT 或 VOICE_DATA 通知时调用
    @MainActor
    func handleNotification(data: Data, from characteristic: CBCharacteristic) {
        // 添加调试日志
        if framesReceived == 0 {
            print("[VoiceService] 🔔 FIRST notification received from \(characteristic.uuid.uuidString)")
            print("[VoiceService]    - Data size: \(data.count) bytes")
            print("[VoiceService]    - Data (hex): \(data as NSData)")
        } else if framesReceived % 100 == 0 {
            print("[VoiceService] 🔔 Notification #\(framesReceived), size: \(data.count)B")
        }

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
            print("[VoiceService] ❌ Send failed: \(error)")
            return .failure(error)
        }

        // 获取发送特征值
        let char = voiceInChar ?? voiceDataChar
        guard let characteristic = char else {
            let error = VoiceServiceError.characteristicNotFound
            print("[VoiceService] ❌ Send failed: \(error)")
            return .failure(error)
        }

        // 包装为 AT^AUDPCM="<base64>"
        guard let packet = wrapAmrFrame(amrData) else {
            let error = VoiceServiceError.encodingFailed
            print("[VoiceService] ❌ Send failed: \(error)")
            return .failure(error)
        }

        // 检查包大小
        guard packet.count <= Constants.maxPacketSize else {
            let error = VoiceServiceError.packetTooLarge(packet.count)
            print("[VoiceService] ❌ Send failed: \(error)")
            return .failure(error)
        }

        // 发送到 BLE (Voice GATT Server 必须使用 writeWithoutResponse)
        let sendTime = Date()
        peripheral.writeValue(packet, for: characteristic, type: .withoutResponse)

        // 更新统计
        framesSent += 1
        bytesSent += packet.count
        sequenceCounter += 1

        // 计算发送间隔并打印
        if let lastTime = lastUplinkSendTime {
            let interval = sendTime.timeIntervalSince(lastTime) * 1000
            // 打印前 20 帧的间隔，或间隔异常时
            if framesSent <= 20 || abs(interval - 20) > 5 {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss.SSS"
                let timestamp = formatter.string(from: sendTime)
                print("[\(timestamp)] [VoiceService] 📤 BLE TX #\(framesSent), interval: \(String(format: "%.1f", interval))ms")
            }
        }
        lastUplinkSendTime = sendTime

        #if DEBUG
        if framesSent % 50 == 0 {  // 每1秒
            print("[VoiceService] 📤 BLE write: frame #\(framesSent), packet size: \(packet.count)B")
        }
        #endif

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
        // 调试：显示接收缓冲区状态
        if receiveBuffer.count > 0 && framesReceived == 0 {
            print("[VoiceService] 📦 Processing receive buffer, size: \(receiveBuffer.count)B")
            print("[VoiceService]    - Buffer (hex): \(receiveBuffer as NSData)")
            print("[VoiceService]    - Looking for prefix: \(Constants.prefix)")
        }

        while true {
            let buffer = receiveBuffer

            // 需要至少前缀长度
            guard buffer.count >= Constants.prefix.count else {
                if framesReceived == 0 && buffer.count > 0 {
                    print("[VoiceService] ⚠️ Buffer too small (\(buffer.count)B), waiting for more...")
                }
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

            if framesReceived == 0 {
                print("[VoiceService] ✅ Found prefix at position \(buffer.distance(from: buffer.startIndex, to: prefixRange.lowerBound))")
            }

            // 前缀之后的位置
            let afterPrefix = prefixRange.upperBound
            guard afterPrefix < buffer.endIndex else {
                break
            }

            // 查找结束引号
            guard let endQuoteRange = buffer[afterPrefix...].firstIndex(of: UInt8(ascii: "\"")) else {
                // 没有找到结束引号，等待更多数据
                if framesReceived == 0 {
                    print("[VoiceService] ⚠️ No closing quote found, waiting...")
                }
                break
            }

            // 提取 base64 数据
            let base64Start = afterPrefix
            let base64End = endQuoteRange
            let base64Data = buffer[base64Start..<base64End]

            // 移除已处理的数据包 (包括结束引号)
            let packetEnd = buffer.index(after: endQuoteRange)
            receiveBuffer = buffer.dropFirst(packetEnd)

            // 解码 base64 并回调
            if let base64String = String(data: base64Data, encoding: .utf8),
               let amrData = Data(base64Encoded: base64String) {
                let receiveTime = Date()
                framesReceived += 1

                if framesReceived == 1 {
                    print("[VoiceService] ✅ FIRST AMR frame decoded! size: \(amrData.count)B")
                    print("[VoiceService]    - Base64: \(base64String)")
                }

                // 计算接收间隔并打印
                if let lastTime = lastDownlinkReceiveTime {
                    let interval = receiveTime.timeIntervalSince(lastTime) * 1000
                    // 打印前 20 帧的间隔，或间隔异常时
                    if framesReceived <= 20 || abs(interval - 20) > 5 {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "HH:mm:ss.SSS"
                        let timestamp = formatter.string(from: receiveTime)
                        print("[\(timestamp)] [VoiceService] 📥 BLE RX #\(framesReceived), interval: \(String(format: "%.1f", interval))ms")
                    }
                }
                lastDownlinkReceiveTime = receiveTime

                // 回调 AMR 帧
                onAmrFrameReceived?(amrData)

                // 日志 (每 50 帧打印一次)
                if framesReceived % 50 == 0 {
                    print("[VoiceService] 📥 Received AMR frames: \(framesReceived) (size: \(amrData.count)B)")
                }
            } else {
                print("[VoiceService] ⚠️ Failed to decode base64 data")
                print("[VoiceService]    - Base64 data: \(base64Data as NSData)")
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

    // MARK: - Protocol Stubs (not implemented - handled by AudioPipelineManager)

    func startRecording() async -> Result<Void, Error> {
        // Recording is handled by AudioPipelineManager
        return .success(())
    }

    func stopRecording() async -> Result<Void, Error> {
        // Recording is handled by AudioPipelineManager
        return .success(())
    }

    func startPlaying() async -> Result<Void, Error> {
        // Playback is handled by AudioPipelineManager
        return .success(())
    }

    func stopPlaying() async -> Result<Void, Error> {
        // Playback is handled by AudioPipelineManager
        return .success(())
    }

    func setAudioMode(_ mode: AudioMode) async -> Result<Void, Error> {
        // Audio mode is handled by AudioPipelineManager
        return .success(())
    }
}

// MARK: - Voice Service Error

/// Voice Service 错误类型
enum VoiceServiceError: LocalizedError {
    case notConnected
    case characteristicNotFound
    case characteristicNotWritable
    case encodingFailed
    case packetTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "BLE peripheral not connected"
        case .characteristicNotFound:
            return "Voice characteristic not found"
        case .characteristicNotWritable:
            return "Voice characteristic not writable"
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
