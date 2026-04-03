import Foundation
import AVFoundation

// MARK: - Call Recorder Protocol

protocol CallRecorderProtocol: AnyObject {
    var isActive: Bool { get }
    func feedUplinkPcm(_ data: Data)
    func feedDownlinkPcm(_ data: Data)
    func startRecording() async
    func stopRecording() async
}

// MARK: - Call Recorder Implementation
/// Records each call as one WAV file: 8kHz, 16bit, mono.
/// Mixes uplink (mic) and downlink (remote) PCM per frame; writes to Documents directory.
@MainActor
final class CallRecorderImpl: CallRecorderProtocol {

    // MARK: - Constants
    private enum Constants {
        static let SAMPLE_RATE = 8000
        static let CHANNELS = 1
        static let BITS_PER_SAMPLE = 16
        static let BYTES_PER_SAMPLE = 2
        /// 20ms frame: 8000 * 0.02 * 2 = 320 bytes
        static let PCM_FRAME_SIZE = 320
        static let FRAME_DURATION_MS = 20
        static let MAX_QUEUE_FRAMES = 150
    }

    // MARK: - Properties
    private var active = false
    private var outputFile: FileHandle?
    private var totalPcmBytesWritten: Int = 0
    private var currentFilePath: URL?

    private let uplinkQueue = ThreadSafeQueue<Data>()
    private let downlinkQueue = ThreadSafeQueue<Data>()
    private var downlinkBuffer = Data()
    private var downlinkBufferLen = 0

    private var recordingTask: Task<Void, Never>?

    private var recordingsDir: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsPath = documentsPath.appendingPathComponent("CallRecordings")
        try? FileManager.default.createDirectory(at: recordingsPath, withIntermediateDirectories: true)
        return recordingsPath
    }

    // MARK: - CallRecorderProtocol

    var isActive: Bool {
        return active
    }

    func feedUplinkPcm(_ data: Data) {
        guard active, data.count >= Constants.PCM_FRAME_SIZE else { return }

        let frame = data.prefix(Constants.PCM_FRAME_SIZE)
        uplinkQueue.push(frame)

        // Limit queue size
        while uplinkQueue.count > Constants.MAX_QUEUE_FRAMES {
            _ = uplinkQueue.pop()
        }
    }

    func feedDownlinkPcm(_ data: Data) {
        guard active, !data.isEmpty else { return }

        // Accumulate data into frames
        var remaining = data

        while downlinkBufferLen + remaining.count >= Constants.PCM_FRAME_SIZE {
            let toCopy = Constants.PCM_FRAME_SIZE - downlinkBufferLen
            downlinkBuffer.append(remaining.prefix(toCopy))
            remaining = remaining.dropFirst(toCopy)
            downlinkBufferLen = 0

            downlinkQueue.push(downlinkBuffer)
            downlinkBuffer = Data()

            // Limit queue size
            while downlinkQueue.count > Constants.MAX_QUEUE_FRAMES {
                _ = downlinkQueue.pop()
            }
        }

        if !remaining.isEmpty {
            downlinkBuffer.append(remaining)
            downlinkBufferLen += remaining.count
        }
    }

    // MARK: - Recording Control

    /// Start recording a new call
    func startRecording() async {
        guard !active else { return }

        // Clear queues
        uplinkQueue.clear()
        downlinkQueue.clear()
        downlinkBuffer = Data()
        downlinkBufferLen = 0
        totalPcmBytesWritten = 0

        // Create output file
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename = "call_\(timestamp).wav"
        let filePath = recordingsDir.appendingPathComponent(filename)
        currentFilePath = filePath

        do {
            // Create empty file with WAV header placeholder
            FileManager.default.createFile(atPath: filePath.path, contents: nil, attributes: nil)
            outputFile = try FileHandle(forWritingTo: filePath)

            // Write placeholder WAV header (will be updated on stop)
            let placeholderHeader = createWavHeader(dataBytes: 0)
            outputFile?.write(placeholderHeader)

            active = true

            // Start mixer task
            recordingTask = Task { [weak self] in
                await self?.runMixer()
            }

            print("[CallRecorder] Recording started: \(filePath.path)")
        } catch {
            print("[CallRecorder] Failed to start recording: \(error)")
        }
    }

    /// Stop recording and finalize WAV file
    func stopRecording() async {
        guard active else { return }

        active = false
        recordingTask?.cancel()
        recordingTask = nil

        do {
            // Update WAV header with actual data size
            if let fileHandle = outputFile, let filePath = currentFilePath {
                fileHandle.closeFile()

                // Reopen to update header
                let data = try Data(contentsOf: filePath)
                let header = createWavHeader(dataBytes: totalPcmBytesWritten)

                // Write updated header
                var updatedData = header
                updatedData.append(data.dropFirst(44)) // Skip old header

                try updatedData.write(to: filePath)

                print("[CallRecorder] Recording stopped, wrote \(totalPcmBytesWritten) bytes PCM")
                print("[CallRecorder] File saved: \(filePath.path)")
            }
        } catch {
            print("[CallRecorder] Failed to finalize WAV: \(error)")
        }

        outputFile = nil
        currentFilePath = nil
    }

    // MARK: - Private Methods

    private func runMixer() async {
        let silence = Data(repeating: 0, count: Constants.PCM_FRAME_SIZE)
        var frameIndex = 0
        let startNanos = Date().millisecondsSinceEpoch

        while active && !Task.isCancelled {
            let elapsedMs = Date().millisecondsSinceEpoch - startNanos
            let targetMs = Int64(frameIndex * Constants.FRAME_DURATION_MS)
            let toWait = targetMs - elapsedMs

            if toWait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(toWait) * 1_000_000)
            }

            // Get frames from queues (or silence if empty)
            let uplink = uplinkQueue.pop() ?? silence
            let downlink = downlinkQueue.pop() ?? silence

            // Mix frames
            let mixed = mixFrames(uplink, downlink)

            // Write to file
            if let fileHandle = outputFile {
                fileHandle.write(mixed)
                totalPcmBytesWritten += mixed.count
            }

            frameIndex += 1
        }

        print("[CallRecorder] Mixer stopped after \(frameIndex) frames")
    }

    /// Mix two PCM frames: (a + b) / 2 with 16-bit clamp
    private func mixFrames(_ a: Data, _ b: Data) -> Data {
        let len = min(a.count, b.count) & ~1 // Ensure even
        var mixed = Data(count: len)

        for i in stride(from: 0, to: len, by: 2) {
            // Read 16-bit samples (little endian)
            let s1 = Int16(bitPattern: UInt16(a[i]) | (UInt16(a[i + 1]) << 8))
            let s2 = Int16(bitPattern: UInt16(b[i]) | (UInt16(b[i + 1]) << 8))

            // Mix with average
            let avg = Int(s1) + Int(s2)
            let mixedSample = Int16(max(-32768, min(32767, avg / 2)))

            // Write back (little endian)
            mixed[i] = UInt8(UInt16(bitPattern: mixedSample) & 0xFF)
            mixed[i + 1] = UInt8((UInt16(bitPattern: mixedSample) >> 8) & 0xFF)
        }

        return mixed
    }

    /// Create WAV file header
    private func createWavHeader(dataBytes: Int) -> Data {
        let byteRate = Constants.SAMPLE_RATE * Constants.CHANNELS * Constants.BYTES_PER_SAMPLE
        let blockAlign = Constants.CHANNELS * Constants.BYTES_PER_SAMPLE
        let chunkSize = 36 + dataBytes
        let subChunk2Size = dataBytes

        var header = Data()

        // RIFF header
        header.append(contentsOf: "RIFF".utf8)
        header.append(intToLittleEndian(chunkSize))
        header.append(contentsOf: "WAVE".utf8)

        // fmt subchunk
        header.append(contentsOf: "fmt ".utf8)
        header.append(intToLittleEndian(16)) // Subchunk1Size (16 for PCM)
        header.append(shortToLittleEndian(1)) // AudioFormat (1 = PCM)
        header.append(shortToLittleEndian(Constants.CHANNELS))
        header.append(intToLittleEndian(Constants.SAMPLE_RATE))
        header.append(intToLittleEndian(byteRate))
        header.append(shortToLittleEndian(blockAlign))
        header.append(shortToLittleEndian(Constants.BITS_PER_SAMPLE))

        // data subchunk
        header.append(contentsOf: "data".utf8)
        header.append(intToLittleEndian(subChunk2Size))

        return header
    }

    private func intToLittleEndian(_ value: Int) -> Data {
        return Data([
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF)
        ])
    }

    private func shortToLittleEndian(_ value: Int) -> Data {
        return Data([
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF)
        ])
    }
}

// MARK: - Thread Safe Queue

/// Thread-safe queue for audio frames
final class ThreadSafeQueue<T> {
    private var items: [T] = []
    private let lock = NSLock()

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return items.count
    }

    func push(_ item: T) {
        lock.lock()
        defer { lock.unlock() }
        items.append(item)
    }

    func pop() -> T? {
        lock.lock()
        defer { lock.unlock() }
        return items.isEmpty ? nil : items.removeFirst()
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        items.removeAll()
    }
}

// MARK: - Date Extension

private extension Date {
    var millisecondsSinceEpoch: Int64 {
        return Int64(timeIntervalSince1970 * 1000)
    }
}
