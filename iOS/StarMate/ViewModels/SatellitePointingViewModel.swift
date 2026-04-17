import Foundation
import CoreLocation
import CoreMotion
import Combine

// MARK: - Pointing Delta Trend
enum PointingDeltaTrend {
    case improving   // getting closer
    case worsening   // getting farther
    case steady
}

// MARK: - UI State
struct SatellitePointingUiState {
    // Satellite target angles
    var satAzimuthDeg: Double?
    var satElevationDeg: Double?

    // Device orientation
    var deviceAzimuthDeg: Double?
    var deviceElevationDeg: Double?

    // Guidance deltas
    var deltaAzDeg: Double?
    var deltaElDeg: Double?
    var deltaAzTrend: PointingDeltaTrend = .steady
    var deltaElTrend: PointingDeltaTrend = .steady

    // Alignment
    var pointingAligned: Bool = false
    var chainFullySuccess: Bool = false

    // Link status
    var bleConnected: Bool = false
    var networkRegistered: Bool = false
    var ttModuleWorking: Bool = false

    // Signal
    var signalCsqRaw: Int?

    // Location
    var locationFixTimeLabel: String?

    // SOS
    var sosSmsSlotCount: Int = 0
    var sosCallSlotCount: Int = 0
    var sosFeedbackMessage: String?
    var sosInProgress: Bool = false
}

// MARK: - Satellite Pointing ViewModel
@MainActor
class SatellitePointingViewModel: ObservableObject {

    @Published var uiState = SatellitePointingUiState()

    // Dependencies (injected after init via updateDependencies)
    private var bleManager: BLEManager?
    private var callManager: CallManager?
    private var smsManager: SMSManager?
    private let sosPreferences: SosPreferences

    // Location
    let locationManager = CLLocationManager()

    // Motion
    private let motionManager = CMMotionManager()

    // Low-pass filters
    private let satAzFilter = AngleLowPass(alpha: 0.15)
    private let satElFilter = AngleLowPass(alpha: 0.15)
    private let devAzFilter = AngleLowPass(alpha: 0.15)
    private let devElFilter = AngleLowPass(alpha: 0.20)

    // Previous deltas for trend detection
    private var prevAbsDeltaAz: Double?
    private var prevAbsDeltaEl: Double?
    private let trendEpsDeg: Double = 0.12

    // Cancellables
    private var cancellables = Set<AnyCancellable>()

    init(sosPreferences: SosPreferences = .shared) {
        self.sosPreferences = sosPreferences
        setupObservers()
    }

    /// Called from View.onAppear to inject real EnvironmentObject instances.
    func updateDependencies(
        bleManager: BLEManager,
        callManager: CallManager,
        smsManager: SMSManager
    ) {
        self.bleManager = bleManager
        self.callManager = callManager
        self.smsManager = smsManager
    }

    // MARK: - Setup

    private func setupObservers() {
        sosPreferences.$slots
            .receive(on: RunLoop.main)
            .sink { [weak self] slots in
                self?.uiState.sosSmsSlotCount = slots.configuredSmsCount
                self?.uiState.sosCallSlotCount = slots.configuredCallCount
            }
            .store(in: &cancellables)

        let slots = sosPreferences.slots
        uiState.sosSmsSlotCount = slots.configuredSmsCount
        uiState.sosCallSlotCount = slots.configuredCallCount
    }

    // MARK: - Lifecycle

    func start() {
        startLocationUpdates()
        startMotionUpdates()
        refreshLinkStatus()
    }

    func stop() {
        stopMotionUpdates()
    }

    // MARK: - Location

    private func startLocationUpdates() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5.0

        if locationManager.authorizationStatus == .authorizedWhenInUse
            || locationManager.authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }

        // Use current location if available
        if let loc = locationManager.location {
            onLocationUpdate(loc)
        }
    }

    /// Called from the View's CLLocationManagerDelegate
    func onLocationUpdate(_ location: CLLocation) {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude

        let (azDeg, elDeg) = GeoMathEngine.getSatelliteAngle(
            latDeg: lat,
            lonDeg: lon
        )

        let filteredAz = satAzFilter.filterAzimuth360(azDeg)
        let filteredEl = satElFilter.filterLinear(elDeg)

        uiState.satAzimuthDeg = filteredAz
        uiState.satElevationDeg = filteredEl

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        uiState.locationFixTimeLabel = formatter.string(from: location.timestamp)

        recalculateGuidance()
    }

    // MARK: - Motion (Compass + Elevation)

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            print("[SatPointing] Device motion not available")
            return
        }

        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0 // 30 Hz (battery-friendly)

        motionManager.startDeviceMotionUpdates(using: .xTrueNorthZVertical, to: .main) { [weak self] motion, error in
            guard let self, let motion else { return }

            let heading = motion.heading
            let deviceAz = self.devAzFilter.filterAzimuth360(heading)

            let rotMatrix = motion.attitude.rotationMatrix
            let matrixArray: [Float] = [
                Float(rotMatrix.m11), Float(rotMatrix.m12), Float(rotMatrix.m13),
                Float(rotMatrix.m21), Float(rotMatrix.m22), Float(rotMatrix.m23),
                Float(rotMatrix.m31), Float(rotMatrix.m32), Float(rotMatrix.m33)
            ]
            let deviceEl = self.devElFilter.filterLinear(
                GuidanceEngine.deviceYElevationDegrees(rotationMatrix: matrixArray)
            )

            self.uiState.deviceAzimuthDeg = deviceAz
            self.uiState.deviceElevationDeg = deviceEl
            self.recalculateGuidance()
        }
    }

    private func stopMotionUpdates() {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
    }

    // MARK: - Guidance Calculation

    private func recalculateGuidance() {
        guard let satAz = uiState.satAzimuthDeg,
              let satEl = uiState.satElevationDeg,
              let devAz = uiState.deviceAzimuthDeg,
              let devEl = uiState.deviceElevationDeg else {
            return
        }

        let (dAz, dEl) = GuidanceEngine.getRelativeAngle(
            satAzDeg: satAz, satElDeg: satEl,
            deviceAzDeg: devAz, deviceElDeg: devEl
        )

        let absDAz = abs(dAz)
        let absDEl = abs(dEl)

        uiState.deltaAzTrend = computeTrend(current: absDAz, previous: prevAbsDeltaAz)
        uiState.deltaElTrend = computeTrend(current: absDEl, previous: prevAbsDeltaEl)

        prevAbsDeltaAz = absDAz
        prevAbsDeltaEl = absDEl

        uiState.deltaAzDeg = dAz
        uiState.deltaElDeg = dEl
        uiState.pointingAligned = GuidanceEngine.isAligned(deltaAz: dAz, deltaEl: dEl)
        uiState.chainFullySuccess = uiState.pointingAligned && uiState.bleConnected && uiState.ttModuleWorking
    }

    private func computeTrend(current: Double, previous: Double?) -> PointingDeltaTrend {
        guard let prev = previous else { return .steady }
        let diff = current - prev
        if diff > trendEpsDeg { return .worsening }
        if diff < -trendEpsDeg { return .improving }
        return .steady
    }

    // MARK: - Link Status

    func refreshLinkStatus() {
        guard let bleManager else { return }
        uiState.bleConnected = bleManager.connectionState.isConnected

        Task {
            await refreshSignalAndModule()
        }
    }

    private func refreshSignalAndModule() async {
        guard let bleManager, bleManager.connectionState.isConnected else { return }

        let systemClient = bleManager.getSystemClient()
        let atClient = bleManager.getAtCommandClient()

        // TT Module status
        let ttResult = await systemClient.getTtModuleStatus()
        switch ttResult {
        case .success(let status):
            if case .working = status.state {
                uiState.ttModuleWorking = true
            } else {
                uiState.ttModuleWorking = false
            }
        case .failure:
            uiState.ttModuleWorking = false
        }

        // Signal strength
        let csqResult = await atClient.sendCommand("AT+CSQ")
        switch csqResult {
        case .success(let response):
            if let range = response.range(of: "+CSQ:") {
                let values = response[range.upperBound...]
                    .trimmingCharacters(in: .whitespaces)
                    .split(separator: ",")
                if let first = values.first, let rssi = Int(first) {
                    uiState.signalCsqRaw = rssi
                }
            }
        case .failure:
            break
        }

        // Network registration
        let cregResult = await atClient.sendCommand("AT+CREG?")
        switch cregResult {
        case .success(let response):
            if let range = response.range(of: "+CREG:") {
                let values = response[range.upperBound...]
                    .trimmingCharacters(in: .whitespaces)
                    .split(separator: ",")
                if values.count >= 2,
                   let stat = Int(values[1].trimmingCharacters(in: .whitespaces)) {
                    uiState.networkRegistered = (stat == 1 || stat == 5)
                }
            }
        case .failure:
            break
        }
    }

    // MARK: - SOS Trigger

    func triggerSos() async -> String {
        guard uiState.bleConnected else {
            return "请先连接蓝牙设备"
        }
        guard uiState.ttModuleWorking else {
            return "天通模块未就绪"
        }
        guard uiState.networkRegistered else {
            return "卫星网络未注册"
        }

        let slots = sosPreferences.slots
        guard slots.hasAnyConfigured else {
            return "未配置SOS联系人，请先在设置中配置"
        }

        uiState.sosInProgress = true
        uiState.sosFeedbackMessage = nil

        let messageBody = SosPreviewTemplate.buildBody(
            customContent: slots.smsCustom,
            latitude: nil,
            longitude: nil
        )

        var feedback: [String] = []

        // Send SMS to all configured slots
        if let smsManager = smsManager {
            for phone in slots.smsSlots where !phone.trimmingCharacters(in: .whitespaces).isEmpty {
                smsManager.sendMessage(to: phone, content: messageBody)
                feedback.append("短信已发送: \(phone)")
            }
        }

        // Call first configured slot
        if let callManager = callManager,
           let firstCall = slots.callSlots.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            callManager.phoneNumber = firstCall
            callManager.makeCall()
            feedback.append("正在拨打: \(firstCall)")
        }

        uiState.sosInProgress = false
        uiState.sosFeedbackMessage = feedback.joined(separator: "\n")

        refreshLinkStatus()

        return feedback.joined(separator: "\n")
    }
}
