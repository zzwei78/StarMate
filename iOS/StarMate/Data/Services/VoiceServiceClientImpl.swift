import Foundation
import CoreBluetooth
import AVFoundation
import Combine

// MARK: - Voice Service Client Implementation
/// GATT Voice Service client (UUID: 0xABF0).
/// Handles bidirectional voice data streaming during calls.
///
/// Protocol: AMR-NB 12.2k, 8kHz 16bit mono, 20ms frames.
/// Packet format (uplink & downlink): AT^AUDPCM="<base64>"
///
/// Uplink: PCM → AMR-NB encode → Base64 → AT^AUDPCM → VOICE_IN
/// Downlink: VOICE_OUT → parse AT^AUDPCM → Base64 decode → AMR-NB decode → PCM → AudioTrack
@MainActor
final class VoiceServiceClientImpl: VoiceServiceClientProtocol {

    // MARK: - Constants
    private enum Constants {
        static let SAMPLE_RATE: Double = 8000
        static let BIT_DEPTH: Int = 16
        static let CHANNELS: Int = 1
        static let FRAME_DURATION_MS: Int = 20
        static let PCM_FRAME_SIZE: Int = 320  // 8000 * 0.02 * 2
        static let AMR_FRAME_SIZE: Int = 33   // ~33 bytes (AMR-NB 12.2kbps)

        // Protocol
        static let PREFIX_AT_AUDPCM = "AT^AUDPCM="
        static let AMR_MIME = "audio/3gpp"
        static let AMR_BIT_RATE = 12200

        // Audio
        static let AUDIO_BUFFER_SIZE: AVAudioFrameCount = 1024
        static let SEND_INTERVAL_MS: UInt64 = 20
    }

    // MARK: - Streams
    private var voiceDataStreamContinuation: AsyncStream<VoicePacket>.Continuation?
    lazy var voiceDataStream: AsyncStream<VoicePacket> = {
        AsyncStream { continuation in
            self.voiceDataStreamContinuation = continuation
        }
    }()

    // MARK: - Private Properties
    private weak var peripheral: CBPeripheral?
    private var voiceInChar: CBCharacteristic?
    private var voiceOutChar: CBCharacteristic?
    private var voiceDataChar: CBCharacteristic?

    // Audio Engine
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var outputNode: AVAudioOutputNode?
    private var inputFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    // Audio Session
    private var audioSession: AVAudioSession {
        AVAudioSession.sharedInstance()
    }

    // State
    private var isRecording = false
    private var isPlaying = false
    private var currentAudioMode: AudioMode = .earpiece
    private var sequenceCounter = 0

    // Recording
    private var recordingTask: Task<Void, Never>?
    private var pcmBufferQueue: [Data] = []
    private let pcmBufferQueueLock = NSLock()

    // Playback
    private var playbackTask: Task<Void, Never>?
    private var receiveBuffer = Data()
    private var playerNode: AVAudioPlayerNode?
    private var outputAudioFormat: AVAudioFormat?

    // AMR Codec (optional - for devices that require AMR-NB)
    private var amrEncoder: AmrNbEncoder?
    private var amrDecoder: AmrNbDecoder?
    private var useAmrCodec = false

    // Call Recorder (optional)
    weak var callRecorder: CallRecorderProtocol?

    // MARK: - Initialization
    init(useAmrCodec: Bool = false) {
        self.useAmrCodec = useAmrCodec
        if useAmrCodec {
            self.amrEncoder = AmrNbEncoder()
            self.amrDecoder = AmrNbDecoder()
        }
    }

    // MARK: - GATT Setup

    /// Set peripheral and characteristics after discovery
    func setPeripheral(_ peripheral: CBPeripheral, characteristics: [CBCharacteristic]) {
        self.peripheral = peripheral

        for char in characteristics {
            switch char.uuid {
            case BleUuid.VOICE_IN:
                voiceInChar = char
                print("[VoiceService] ✅ Voice In characteristic found (0xABEE)")
            case BleUuid.VOICE_OUT:
                voiceOutChar = char
                peripheral.setNotifyValue(true, for: char)
                print("[VoiceService] ✅ Voice Out characteristic found, notifications enabled (0xABEF)")
            case BleUuid.VOICE_DATA:
                voiceDataChar = char
                peripheral.setNotifyValue(true, for: char)
                print("[VoiceService] ✅ Voice Data characteristic found (0xABF1)")
            default:
                break
            }
        }

        // Prefer VOICE_IN for sending, VOICE_DATA as fallback
        if voiceInChar == nil && voiceDataChar != nil {
            print("[VoiceService] Using VOICE_DATA (0xABF1) for both send and receive")
        }
    }

    /// Clear GATT references on disconnect
    func clearGattReferences() {
        peripheral = nil
        voiceInChar = nil
        voiceOutChar = nil
        voiceDataChar = nil

        Task {
            _ = await stopRecording()
            _ = await stopPlaying()
        }
    }

    // MARK: - Protocol: VoiceServiceClientProtocol

    func onGattClosed() {
        clearGattReferences()
    }

    // MARK: - Notification Handling

    /// Handle notification data from BLEManager
    func handleNotification(data: Data, from characteristic: CBCharacteristic) {
        // Queue the data for processing
        receiveBuffer.append(data)

        // Emit to stream
        let packet = VoicePacket(data: data, timestamp: Date(), sequenceNumber: sequenceCounter)
        voiceDataStreamContinuation?.yield(packet)
    }

    // MARK: - Send Voice Data

    func sendVoiceData(_ data: Data) async -> Result<Void, Error> {
        guard let peripheral = peripheral else {
            return .failure(NSError(domain: "VoiceService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Peripheral not connected"]))
        }

        // Prefer VOICE_IN, fallback to VOICE_DATA
        let char = voiceInChar ?? voiceDataChar
        guard let characteristic = char else {
            return .failure(NSError(domain: "VoiceService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Voice characteristic not found"]))
        }

        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        sequenceCounter += 1

        return .success(())
    }

    // MARK: - Recording

    func startRecording() async -> Result<Void, Error> {
        guard !isRecording else { return .success(()) }

        do {
            // Configure audio session for voice communication
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
            try audioSession.setActive(true)

            // Create audio engine
            audioEngine = AVAudioEngine()
            guard let audioEngine = audioEngine else {
                return .failure(NSError(domain: "VoiceService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio engine"]))
            }

            inputNode = audioEngine.inputNode
            guard let inputNode = inputNode else {
                return .failure(NSError(domain: "VoiceService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get input node"]))
            }

            // Create output format (8kHz, mono, 16-bit PCM)
            let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Constants.SAMPLE_RATE, channels: 1, interleaved: true)!
            self.outputAudioFormat = outputFormat

            // Get input format and create converter if needed
            let inputFormat = inputNode.outputFormat(forBus: 0)
            self.inputFormat = inputFormat

            // Install tap on input node
            inputNode.installTap(onBus: 0, bufferSize: Constants.AUDIO_BUFFER_SIZE, format: inputFormat) { [weak self] buffer, time in
                self?.processAudioBuffer(buffer, time: time)
            }

            // Start audio engine
            try audioEngine.start()
            isRecording = true

            // Start recording task for sending voice data
            recordingTask = Task { [weak self] in
                await self?.runRecordingLoop()
            }

            print("[VoiceService] Recording started (8kHz, mono, 16-bit)")
            return .success(())

        } catch {
            print("[VoiceService] Failed to start recording: \(error)")
            return .failure(error)
        }
    }

    func stopRecording() async -> Result<Void, Error> {
        guard isRecording else { return .success(()) }

        isRecording = false
        recordingTask?.cancel()
        recordingTask = nil

        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil

        // Deactivateate audio session if not playing
        if !isPlaying {
            try? audioSession.setActive(false)
        }

        print("[VoiceService] Recording stopped")
        return .success(())
    }

    // MARK: - Playback

    func startPlaying() async -> Result<Void, Error> {
        guard !isPlaying else { return .success(()) }

        do {
            // Configure audio session
            if !isRecording {
                try audioSession.setCategory(.playback, mode: .voiceChat, options: currentAudioMode == .speaker ? .defaultToSpeaker : [])
                try audioSession.setActive(true)
            }

            // Create audio engine for playback
            if audioEngine == nil {
                audioEngine = AVAudioEngine()
            }

            guard let audioEngine = audioEngine else {
                return .failure(NSError(domain: "VoiceService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio engine"]))
            }

            // Create player node
            playerNode = AVAudioPlayerNode()
            guard let playerNode = playerNode else {
                return .failure(NSError(domain: "VoiceService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create player node"]))
            }

            audioEngine.attach(playerNode)

            // Create output format
            let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Constants.SAMPLE_RATE, channels: 1, interleaved: true)!
            self.outputAudioFormat = outputFormat

            // Connect player node to output
            let mainMixer = audioEngine.mainMixerNode
            audioEngine.connect(playerNode, to: mainMixer, format: outputFormat)

            // Start audio engine if not already running
            if !audioEngine.isRunning {
                try audioEngine.start()
            }

            playerNode.play()
            isPlaying = true
            receiveBuffer = Data()

            // Start playback task
            playbackTask = Task { [weak self] in
                await self?.runPlaybackLoop()
            }

            print("[VoiceService] Playback started (mode: \(currentAudioMode))")
            return .success(())

        } catch {
            print("[VoiceService] Failed to start playing: \(error)")
            return .failure(error)
        }
    }

    func stopPlaying() async -> Result<Void, Error> {
        guard isPlaying else { return .success(()) }

        isPlaying = false
        playbackTask?.cancel()
        playbackTask = nil

        playerNode?.stop()
        playerNode = nil

        // Deactivateate audio session if not recording
        if !isRecording {
            try? audioSession.setActive(false)
        }

        print("[VoiceService] Playback stopped")
        return .success(())
    }

    // MARK: - Audio Mode

    func setAudioMode(_ mode: AudioMode) async -> Result<Void, Error> {
        currentAudioMode = mode

        // Restart playback with new mode if currently playing
        if isPlaying {
            _ = await stopPlaying()
            return await startPlaying()
        }

        return .success(())
    }

    // MARK: - Private Methods

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard isRecording else { return }

        // Convert to 8kHz mono 16-bit PCM
        guard let outputFormat = outputAudioFormat,
              let converter = AVAudioConverter(from: buffer.format, to: outputFormat) else {
            return
        }

        // Calculate frame count for 8kHz
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * Constants.SAMPLE_RATE / buffer.format.sampleRate)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCount) else {
            return
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            print("[VoiceService] Conversion error: \(error)")
            return
        }

        // Extract PCM data
        if let channelData = outputBuffer.int16ChannelData {
            let data = Data(bytes: channelData[0], count: Int(outputBuffer.frameLength) * 2)
            pcmBufferQueueLock.lock()
            pcmBufferQueue.append(data)
            pcmBufferQueueLock.unlock()
        }
    }

    private func runRecordingLoop() async {
        var frameIndex = 0
        let startNanos = Date().millisecondsSinceEpoch

        while isRecording && !Task.isCancelled {
            let elapsedMs = Date().millisecondsSinceEpoch - startNanos
            let targetMs = Int64(frameIndex * Constants.FRAME_DURATION_MS)
            let toWait = targetMs - elapsedMs

            if toWait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(toWait) * 1_000_000)
            }

            // Get PCM data from queue
            var pcmData: Data?
            pcmBufferQueueLock.lock()
            if !pcmBufferQueue.isEmpty {
                // Accumulate to get 320 bytes (20ms frame)
                var accumulated = Data()
                while accumulated.count < Constants.PCM_FRAME_SIZE && !pcmBufferQueue.isEmpty {
                    accumulated.append(pcmBufferQueue.removeFirst())
                }
                if accumulated.count >= Constants.PCM_FRAME_SIZE {
                    pcmData = accumulated.prefix(Constants.PCM_FRAME_SIZE)
                }
            }
            pcmBufferQueueLock.unlock()

            guard let pcm = pcmData else {
                frameIndex += 1
                continue
            }

            // Feed to call recorder
            callRecorder?.feedUplinkPcm(pcm)

            // Encode and send
            do {
                let packet = try encodeAndWrapPcm(pcm)
                let _ = await sendVoiceData(packet)

                if frameIndex % 50 == 0 {
                    print("[VoiceService] Sent frame \(frameIndex)")
                }
            } catch {
                print("[VoiceService] Encode/send failed: \(error)")
            }

            frameIndex += 1
        }

        print("[VoiceService] Recording loop ended")
    }

    private func runPlaybackLoop() async {
        while isPlaying && !Task.isCancelled {
            // Process receive buffer for AT^AUDPCM packets
            processReceiveBuffer()

            // Small delay to prevent busy loop
            try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
        }

        print("[VoiceService] Playback loop ended")
    }

    private func processReceiveBuffer() {
        while true {
            let buffer = receiveBuffer
            let len = buffer.count

            // Need at least prefix + 3 chars
            guard len >= Constants.PREFIX_AT_AUDPCM.count + 3 else { break }

            // Find prefix
            guard let prefixRange = buffer.range(of: Data(Constants.PREFIX_AT_AUDPCM.utf8)) else {
                // Skip to next newline
                if let newlineRange = buffer.range(of: Data("\r\n".utf8)) {
                    receiveBuffer = buffer.dropFirst(newlineRange.upperBound)
                    continue
                }
                break
            }

            // Find opening quote
            let afterPrefix = prefixRange.upperBound
            guard afterPrefix < buffer.endIndex else { break }

            var quoteStart = afterPrefix
            if buffer[quoteStart] == UInt8(ascii: "\\") && quoteStart + 1 < buffer.endIndex && buffer[quoteStart + 1] == UInt8(ascii: "\"") {
                quoteStart = buffer.index(afterPrefix, offsetBy: 2)
            } else if buffer[quoteStart] == UInt8(ascii: "\"") {
                quoteStart = buffer.index(afterPrefix, offsetBy: 1)
            } else {
                break
            }

            // Find closing quote
            guard let endQuote = buffer[quoteStart...].firstIndex(of: UInt8(ascii: "\"")) else {
                break
            }

            // Extract base64 data
            let base64Data = buffer[quoteStart..<endQuote]
            let packetData = buffer[buffer.startIndex..<buffer.index(after: endQuote)]
            receiveBuffer = buffer.dropFirst(packetData.count)

            // Parse and play
            if let base64String = String(data: base64Data, encoding: .utf8),
               let amrData = Data(base64Encoded: base64String) {
                playAmrData(amrData)
            }
        }
    }

    private func playAmrData(_ amrData: Data) {
        guard isPlaying, let playerNode = playerNode else { return }

        // Decode AMR to PCM
        let pcmData: Data
        if let decoder = amrDecoder {
            pcmData = decoder.decode(amrData)
        } else {
            // If no AMR decoder, assume it's raw PCM
            pcmData = amrData
        }

        // Feed to call recorder
        callRecorder?.feedDownlinkPcm(pcmData)

        // Play PCM
        guard let outputFormat = outputAudioFormat else { return }

        let frameCount = AVAudioFrameCount(pcmData.count / 2)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else {
            return
        }

        pcmBuffer.frameLength = frameCount
        if let channelData = pcmBuffer.int16ChannelData {
            pcmData.withUnsafeBytes { ptr in
                memcpy(channelData[0], ptr.baseAddress!, pcmData.count)
            }
        }

        playerNode.scheduleBuffer(pcmBuffer)
    }

    // MARK: - Encoding

    /// Encode PCM data and wrap in AT^AUDPCM packet
    private func encodeAndWrapPcm(_ pcmData: Data) throws -> Data {
        let encodedData: Data

        if let encoder = amrEncoder {
            // Encode to AMR-NB
            encodedData = encoder.encode(pcmData)
        } else {
            // Use raw PCM (Base64 encoded)
            encodedData = pcmData
        }

        // Wrap in AT^AUDPCM packet
        let base64 = encodedData.base64EncodedString()
        let packet = "AT^AUDPCM=\"\(base64)\""

        return packet.data(using: .utf8)!
    }
}

// MARK: - AMR-NB Codec Stubs
/// Placeholder AMR-NB encoder.
/// In production, use a library like opencore-amr or implement AMR-NB encoding.
class AmrNbEncoder {
    func encode(_ pcmData: Data) -> Data {
        // TODO: Implement AMR-NB encoding
        // For now, return raw PCM (devices may support PCM passthrough)
        return pcmData
    }
}

/// Placeholder AMR-NB decoder.
/// In production, use a library like opencore-amr or implement AMR-NB decoding.
class AmrNbDecoder {
    func decode(_ amrData: Data) -> Data {
        // TODO: Implement AMR-NB decoding
        // For now, return raw data (devices may send PCM)
        return amrData
    }
}

// MARK: - Date Extension

private extension Date {
    var millisecondsSinceEpoch: Int64 {
        return Int64(timeIntervalSince1970 * 1000)
    }
}
