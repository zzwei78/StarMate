import Foundation
import Combine

// MARK: - Satellite Phone Manager Implementation

/// 卫星电话管理器实现
///
/// 通过 AT 命令管理 SIM 卡、基带信息和网络状态。
///
/// ## AT 命令参考
/// - `AT+CPIN?` - 查询 SIM 状态
/// - `AT+CPIN=<pin>` - 输入 PIN 码
/// - `AT+CPIN=<puk>,<newpin>` - 输入 PUK 码
/// - `AT+CPWD="SC",<old>,<new>` - 更改 PIN 码
/// - `AT+CGSN` - 获取 IMEI
/// - `AT+CIMI` - 获取 IMSI
/// - `AT+CCID` - 获取 ICCID
/// - `AT+CGMR` - 获取软件版本
/// - `AT+CREG?` - 查询网络注册状态
/// - `AT+CSQ` - 查询信号强度
@MainActor
final class SatellitePhoneManagerImpl: SatellitePhoneManagerProtocol, ObservableObject {

    // MARK: - Published State

    @Published private(set) var simState: SimState = .unknown
    @Published private(set) var basebandVersion: BasebandVersion?
    @Published private(set) var networkRegState: NetworkRegistrationStatus = .unknown
    @Published private(set) var signalInfo: SignalInfo?

    // MARK: - Dependencies

    private let atClient: AtServiceClientImpl

    // MARK: - Cancellation

    private var refreshTask: Task<Void, Never>?

    // MARK: - Initialization

    init(atClient: AtServiceClientImpl) {
        self.atClient = atClient
        print("[SatellitePhoneManager] Initialized")
    }

    deinit {
        refreshTask?.cancel()
    }

    // MARK: - SIM Management

    /// 获取 SIM 卡状态
    func getSimState() async -> Result<SimState, Error> {
        let result = await atClient.sendCommand("AT+CPIN?")

        switch result {
        case .success(let response):
            let state = parseSimState(response)
            await MainActor.run {
                self.simState = state
            }
            return .success(state)

        case .failure(let error):
            print("[SatellitePhoneManager] ❌ getSimState failed: \(error)")
            return .failure(error)
        }
    }

    /// 解析 SIM 状态
    private func parseSimState(_ response: String) -> SimState {
        let upper = response.uppercased()

        if upper.contains("+CPIN: READY") {
            return .ready
        } else if upper.contains("+CPIN: SIM PIN") {
            return .simPinRequired(remainingAttempts: -1)
        } else if upper.contains("+CPIN: SIM PIN2") {
            return .simPin2Required(remainingAttempts: -1)
        } else if upper.contains("+CPIN: SIM PUK") {
            return .simPukRequired(remainingAttempts: -1)
        } else if upper.contains("+CPIN: SIM PUK2") {
            return .simPuk2Required(remainingAttempts: -1)
        } else if upper.contains("+CPIN: NOT INSERTED") || upper.contains("+CPIN: NOT READY") {
            return .absent
        } else if upper.contains("+CPIN: PH-NET PIN") || upper.contains("+CPIN: PH-NETSUB PIN") {
            return .phSimPinRequired(remainingAttempts: -1)
        } else if upper.contains("+CME ERROR") {
            return .error
        }

        return .unknown
    }

    /// 输入 PIN 码
    func enterPin(_ pin: String) async -> Result<Void, Error> {
        guard pin.count >= 4 && pin.count <= 8 else {
            return .failure(SatPhoneError.invalidPinLength)
        }

        let result = await atClient.sendCommand("AT+CPIN=\(pin)")

        switch result {
        case .success:
            print("[SatellitePhoneManager] ✅ PIN accepted")
            // 刷新状态
            _ = await getSimState()
            return .success(())

        case .failure(let error):
            print("[SatellitePhoneManager] ❌ enterPin failed: \(error)")
            return .failure(error)
        }
    }

    /// 解锁 PUK (需要 PUK 码和新 PIN 码)
    func enterPuk(_ puk: String, newPin: String) async -> Result<Void, Error> {
        guard puk.count == 8 else {
            return .failure(SatPhoneError.invalidPukLength)
        }
        guard newPin.count >= 4 && newPin.count <= 8 else {
            return .failure(SatPhoneError.invalidPinLength)
        }

        let result = await atClient.sendCommand("AT+CPIN=\"\(puk)\",\"\(newPin)\"")

        switch result {
        case .success:
            print("[SatellitePhoneManager] ✅ PUK accepted")
            _ = await getSimState()
            return .success(())

        case .failure(let error):
            print("[SatellitePhoneManager] ❌ enterPuk failed: \(error)")
            return .failure(error)
        }
    }

    /// 更改 PIN 码
    func changePin(oldPin: String, newPin: String) async -> Result<Void, Error> {
        guard oldPin.count >= 4 && oldPin.count <= 8 else {
            return .failure(SatPhoneError.invalidPinLength)
        }
        guard newPin.count >= 4 && newPin.count <= 8 else {
            return .failure(SatPhoneError.invalidPinLength)
        }

        let result = await atClient.sendCommand("AT+CPWD=\"SC\",\"\(oldPin)\",\"\(newPin)\"")

        switch result {
        case .success:
            print("[SatellitePhoneManager] ✅ PIN changed")
            return .success(())

        case .failure(let error):
            print("[SatellitePhoneManager] ❌ changePin failed: \(error)")
            return .failure(error)
        }
    }

    // MARK: - Baseband Info

    /// 获取 IMEI
    func getIMEI() async -> Result<String, Error> {
        let result = await atClient.sendCommand("AT+CGSN")

        switch result {
        case .success(let response):
            let imei = extractValue(from: response, prefix: "")
            let cleaned = imei.replacingOccurrences(of: " ", with: "").trimmingCharacters(in: .whitespacesAndNewlines)

            if cleaned.count >= 15 {
                await updateBasebandVersion(imei: cleaned)
                return .success(cleaned)
            }

            return .failure(SatPhoneError.parseError)

        case .failure(let error):
            return .failure(error)
        }
    }

    /// 获取 IMSI
    func getIMSI() async -> Result<String, Error> {
        let result = await atClient.sendCommand("AT+CIMI")

        switch result {
        case .success(let response):
            let imsi = response.trimmingCharacters(in: .whitespacesAndNewlines)

            if imsi.count >= 15 {
                await updateBasebandVersion(imsi: imsi)
                return .success(imsi)
            }

            return .failure(SatPhoneError.parseError)

        case .failure(let error):
            return .failure(error)
        }
    }

    /// 获取 ICCID
    func getICCID() async -> Result<String, Error> {
        let result = await atClient.sendCommand("AT+CCID")

        switch result {
        case .success(let response):
            // 可能是 +CCID: xxxxx 或直接 xxxxx
            var iccid = extractValue(from: response, prefix: "+CCID:")
            if iccid.isEmpty {
                iccid = response.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let cleaned = iccid.replacingOccurrences(of: " ", with: "")

            if cleaned.count >= 19 {
                await updateBasebandVersion(ccid: cleaned)
                return .success(cleaned)
            }

            return .failure(SatPhoneError.parseError)

        case .failure(let error):
            return .failure(error)
        }
    }

    /// 获取基带软件版本
    func getBasebandSwVersion() async -> Result<String, Error> {
        let result = await atClient.sendCommand("AT+CGMR")

        switch result {
        case .success(let response):
            let version = response.trimmingCharacters(in: .whitespacesAndNewlines)

            if !version.isEmpty {
                await updateBasebandVersion(softwareVersion: version)
                return .success(version)
            }

            return .failure(SatPhoneError.parseError)

        case .failure(let error):
            return .failure(error)
        }
    }

    /// 获取完整基带信息
    func getBasebandVersion() async -> Result<BasebandVersion, Error> {
        // 并行获取所有信息
        async let imeiResult = getIMEI()
        async let imsiResult = getIMSI()
        async let iccidResult = getICCID()
        async let swVersionResult = getBasebandSwVersion()
        async let hwVersionResult = atClient.sendCommand("AT+CGMM")  // 获取型号

        let imei = (try? await imeiResult.get()) ?? ""
        let imsi = (try? await imsiResult.get()) ?? ""
        let ccid = (try? await iccidResult.get()) ?? ""
        let softwareVersion = (try? await swVersionResult.get()) ?? ""
        let model = (try? await hwVersionResult.get()).map { extractValue(from: $0, prefix: "") } ?? ""
        let hardwareVersion = ""
        let manufacturer = ""

        let baseband = BasebandVersion(
            imei: imei,
            imsi: imsi,
            ccid: ccid,
            softwareVersion: softwareVersion,
            hardwareVersion: hardwareVersion,
            model: model,
            manufacturer: manufacturer
        )

        await MainActor.run {
            self.basebandVersion = baseband
        }

        return .success(baseband)
    }

    // MARK: - Network

    /// 获取网络注册状态
    func getNetworkRegistrationStatus() async -> Result<NetworkRegistrationStatus, Error> {
        let result = await atClient.sendCommand("AT+CREG?")

        switch result {
        case .success(let response):
            let state = parseNetworkRegistrationStatus(response)
            await MainActor.run {
                self.networkRegState = state
            }
            return .success(state)

        case .failure(let error):
            return .failure(error)
        }
    }

    /// 解析网络注册状态
    private func parseNetworkRegistrationStatus(_ response: String) -> NetworkRegistrationStatus {
        // +CREG: <n>,<stat>[,<lac>,<ci>]
        // stat: 0=未注册, 1=已注册本地, 2=正在搜索, 3=注册被拒绝, 4=未知, 5=已注册漫游

        guard let range = response.range(of: "+CREG:") else {
            return .unknown
        }

        let afterPrefix = response[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = afterPrefix.split(separator: ",")

        guard parts.count >= 2 else {
            return .unknown
        }

        // 第二个参数是状态
        guard let stat = Int(parts[1].trimmingCharacters(in: .whitespaces)) else {
            return .unknown
        }

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

    /// 获取信号强度
    func getSignalInfo() async -> Result<SignalInfo, Error> {
        let result = await atClient.sendCommand("AT+CSQ")

        switch result {
        case .success(let response):
            guard let info = parseSignalInfo(response) else {
                return .failure(SatPhoneError.parseError)
            }

            await MainActor.run {
                self.signalInfo = info
            }
            return .success(info)

        case .failure(let error):
            return .failure(error)
        }
    }

    /// 解析信号强度
    private func parseSignalInfo(_ response: String) -> SignalInfo? {
        // +CSQ: <rssi>,<ber>
        guard let range = response.range(of: "+CSQ:") else {
            return nil
        }

        let afterPrefix = response[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = afterPrefix.split(separator: ",")

        guard parts.count >= 2 else {
            return nil
        }

        guard let rssi = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let ber = Int(parts[1].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }

        // Convert RSSI (0-31) to strength (0-5 bars)
        let strength: Int
        if rssi == 99 {
            strength = 0
        } else if rssi >= 20 {
            strength = 5
        } else if rssi >= 15 {
            strength = 4
        } else if rssi >= 10 {
            strength = 3
        } else if rssi >= 5 {
            strength = 2
        } else {
            strength = 1
        }

        return SignalInfo(strength: strength, ber: ber, isRegistered: false, regStatus: 0)
    }

    // MARK: - Convenience

    /// 是否准备好拨打电话
    func isReadyForCall() -> Bool {
        return simState.isReady
    }

    /// 刷新所有状态
    func refreshAllStatus() async {
        async let simResult = getSimState()
        async let networkResult = getNetworkRegistrationStatus()
        async let signalResult = getSignalInfo()

        // 等待所有完成
        _ = await simResult
        _ = await networkResult
        _ = await signalResult

        print("[SatellitePhoneManager] Status refreshed")
    }

    /// 开始定期刷新 (可选)
    func startPeriodicRefresh(intervalSeconds: Int = 10) {
        refreshTask?.cancel()

        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshAllStatus()
                try? await Task.sleep(nanoseconds: UInt64(intervalSeconds) * 1_000_000_000)
            }
        }
    }

    /// 停止定期刷新
    func stopPeriodicRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Private Helpers

    /// 从响应中提取值
    private func extractValue(from response: String, prefix: String) -> String {
        var text = response

        if !prefix.isEmpty {
            guard let range = text.range(of: prefix, options: .caseInsensitive) else {
                return ""
            }
            text = String(text[range.upperBound...])
        }

        // 移除 OK、ERROR 等尾随文本
        if let okRange = text.range(of: "OK", options: .caseInsensitive) {
            text = String(text[..<okRange.lowerBound])
        }
        if let errorRange = text.range(of: "ERROR", options: .caseInsensitive) {
            text = String(text[..<errorRange.lowerBound])
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 更新 basebandVersion 的单个字段
    private func updateBasebandVersion(
        imei: String? = nil,
        imsi: String? = nil,
        ccid: String? = nil,
        softwareVersion: String? = nil,
        hardwareVersion: String? = nil,
        model: String? = nil,
        manufacturer: String? = nil
    ) async {
        let current = basebandVersion ?? BasebandVersion(
            imei: "",
            imsi: "",
            ccid: "",
            softwareVersion: "",
            hardwareVersion: "",
            model: "",
            manufacturer: ""
        )

        basebandVersion = BasebandVersion(
            imei: imei ?? current.imei,
            imsi: imsi ?? current.imsi,
            ccid: ccid ?? current.ccid,
            softwareVersion: softwareVersion ?? current.softwareVersion,
            hardwareVersion: hardwareVersion ?? current.hardwareVersion,
            model: model ?? current.model,
            manufacturer: manufacturer ?? current.manufacturer
        )
    }
}

// MARK: - Satellite Phone Error

/// 卫星电话错误
enum SatPhoneError: LocalizedError {
    case invalidPinLength
    case invalidPukLength
    case parseError
    case simNotReady
    case networkNotAvailable

    var errorDescription: String? {
        switch self {
        case .invalidPinLength:
            return "PIN 码长度无效 (需要 4-8 位)"
        case .invalidPukLength:
            return "PUK 码长度无效 (需要 8 位)"
        case .parseError:
            return "响应解析失败"
        case .simNotReady:
            return "SIM 卡未就绪"
        case .networkNotAvailable:
            return "网络不可用"
        }
    }
}

// MARK: - Debug Extensions

#if DEBUG
extension SatellitePhoneManagerImpl {
    /// 打印当前状态
    func printStatus() {
        print("[SatellitePhoneManager] Status:")
        print("  - SIM State: \(simState)")
        print("  - Network State: \(networkRegState)")
        print("  - Signal Strength: \(signalInfo?.strength ?? 0)")
        print("  - Ready for call: \(isReadyForCall())")

        if let baseband = basebandVersion {
            print("  - IMEI: \(baseband.imei.isEmpty ? "N/A" : baseband.imei)")
            print("  - IMSI: \(baseband.imsi.isEmpty ? "N/A" : baseband.imsi)")
            print("  - ICCID: \(baseband.ccid.isEmpty ? "N/A" : baseband.ccid)")
            print("  - SW Version: \(baseband.softwareVersion)")
        }
    }
}
#endif
