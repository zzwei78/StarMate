import SwiftUI
import Combine
import CoreLocation
import CoreMotion

struct HomeView: View {
    @EnvironmentObject var bleManager: BLEManager
    @EnvironmentObject var callManager: CallManager
    @EnvironmentObject var smsManager: SMSManager
    @State private var showScanDialog = false
    @State private var scanTask: Task<Void, Never>?

    // Device Info State
    @State private var batteryInfo: BatteryInfo?
    @State private var terminalVersion: TerminalVersion?
    @State private var ttModuleStatus: TtModuleStatus?
    @State private var simState: SimState?
    @State private var networkRegStatus: NetworkRegistrationStatus?
    @State private var signalCsqRaw: Int?

    // Satellite Pointing State
    @StateObject private var pointingViewModel = SatellitePointingViewModel()

    // Location & Motion State (simplified for HomeView)
    @State private var satAzimuth: Double?
    @State private var satElevation: Double?
    @State private var deviceAzimuth: Double?
    @State private var deviceElevation: Double?  // 设备当前倾斜角度
    @State private var deltaElevation: Double?    // 设备需要扬起的角度
    private let locationDelegate = HomeLocationDelegate()
    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private let devAzFilter = AngleLowPass(alpha: 0.15)
    private let devElFilter = AngleLowPass(alpha: 0.20)
    private let satAzFilter = AngleLowPass(alpha: 0.15)
    private let satElFilter = AngleLowPass(alpha: 0.15)

    // Refresh State
    @State private var isRefreshing = false
    @State private var isRefreshInCooldown = false
    @State private var refreshHint: String?
    @State private var errorMessage: String?

    // Auto-refresh timer
    @State private var refreshTimer: Timer?
    @State private var wasConnected = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {
                    // Title
                    Text("天通猫")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.systemBlue)
                        .padding(.top, AppTheme.Spacing.lg)

                    // Link Chain Status Bar
                    linkChainBar

                    // Connect Button
                    connectButton

                    // Satellite Pointing Info (always visible)
                    satellitePointingSection

                    // Device Info Cards (only when connected)
                    if bleManager.connectionState.isConnected {
                        if let battery = batteryInfo {
                            DeviceInfoCard(
                                batteryInfo: battery,
                                softwareVersion: terminalVersion?.softwareVersion
                            )
                        }

                        // Satellite Module Card
                        if let ttStatus = ttModuleStatus {
                            SatelliteModuleCard(
                                ttModuleStatus: ttStatus,
                                signalCsqRaw: signalCsqRaw,
                                simState: simState,
                                networkRegStatus: networkRegStatus
                            )
                        }

                        // Refresh Button
                        refreshButton

                        // Refresh Hint
                        if let hint = refreshHint {
                            Text(hint)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Error Message
                        if let error = errorMessage {
                            errorCard(error)
                        }
                    }

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
            }
            .background(Color.systemGray6)
            .navigationBarHidden(true)
            .sheet(isPresented: $showScanDialog) {
                ScanDeviceSheet(
                    isScanning: bleManager.isScanning,
                    devices: bleManager.scannedDevices,
                    onDeviceSelected: { device in
                        showScanDialog = false
                        scanTask?.cancel()
                        scanTask = nil
                        // 停止扫描
                        bleManager.stopScan()
                        // 连接设备
                        bleManager.connect(device.address)
                    },
                    onRescan: {
                        startScan()
                    },
                    onDismiss: {
                        showScanDialog = false
                        scanTask?.cancel()
                        scanTask = nil
                    }
                )
            }
            .onDisappear {
                scanTask?.cancel()
                scanTask = nil
                refreshTimer?.invalidate()
                refreshTimer = nil
                stopLocationAndMotionUpdates()
            }
            .onChange(of: bleManager.connectionState) { _, newState in
                handleConnectionStateChange(newState)
            }
            .onAppear {
                pointingViewModel.updateDependencies(
                    bleManager: bleManager,
                    callManager: callManager,
                    smsManager: smsManager
                )
                pointingViewModel.start()
                startLocationAndMotionUpdates()
            }
        }
    }

    // MARK: - Connect Button
    private var connectButton: some View {
        Button(action: {
            showScanDialog = true
            startScan()
        }) {
            HStack(spacing: AppTheme.Spacing.sm) {
                if bleManager.isScanning {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                    Text("正在搜索天通猫...")
                        .font(.subheadline)
                        .foregroundColor(.white)
                } else if case .connected = bleManager.connectionState {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.systemGreen)
                    Text("已连接")
                        .font(.subheadline)
                        .foregroundColor(.systemGreen)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.subheadline)
                    Text("搜索并连接天通猫")
                        .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.md)
            .background(bleManager.connectionState.isConnected ? Color.systemGreen : Color.systemBlue)
            .foregroundColor(.white)
            .cornerRadius(AppTheme.CornerRadius.medium)
        }
        .disabled(bleManager.isScanning || bleManager.connectionState.isConnected)
    }

    // MARK: - Satellite Pointing Section
    private var satellitePointingSection: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            // Success strip (when aligned)
            if isPointingAligned {
                successStrip
            }

            // Angle guidance panel
            angleGuidancePanel

            // Compass
            SatelliteFinderCompass(
                deviceAzimuthDeg: deviceAzimuth,
                satelliteAzimuthDeg: satAzimuth,
                satelliteElevationDeg: satElevation,
                isAligned: isPointingAligned,
                size: 240
            )
            .frame(maxWidth: .infinity)

            // Coordinates row
            coordinateRow
        }
    }

    // MARK: - Pointing Computed Properties
    private var isPointingAligned: Bool {
        guard let satAz = satAzimuth,
              let satEl = satElevation,
              let devAz = deviceAzimuth,
              let devEl = deviceElevation else { return false }

        // 检查方位角是否对齐 (15度内)
        let azDiff = abs(satAz - devAz)
        let normalizedAzDiff = min(azDiff, 360 - azDiff)
        let azAligned = normalizedAzDiff < 15

        // 检查仰角是否对齐 (10度内)
        let elDiff = abs(satEl - devEl)
        let elAligned = elDiff < 10

        return azAligned && elAligned
    }

    // MARK: - Link Chain Bar
    private var linkChainBar: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            linkIcon(icon: "iphone", label: "手机", active: true)
            linkArrow
            linkIcon(icon: "antenna.radiowaves.left.and.right", label: "蓝牙",
                     active: bleManager.connectionState.isConnected)
            linkArrow
            linkIcon(icon: "cpu", label: "模块",
                     active: ttModuleStatus?.state == .working)
            linkArrow
            linkIcon(icon: "network", label: "网络",
                     active: networkRegStatus?.isRegistered == true)
        }
        .padding(AppTheme.Spacing.md)
        .background(Color.cardBackgroundLight)
        .cornerRadius(AppTheme.CornerRadius.medium)
    }

    private func linkIcon(icon: String, label: String, active: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(active ? .systemGreen : .systemGray)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(active ? .systemGreen : .systemGray)
        }
        .frame(maxWidth: .infinity)
    }

    private var linkArrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 10))
            .foregroundColor(.systemGray3)
    }

    // MARK: - Success Strip
    private var successStrip: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.systemGreen)
            Text("已对准卫星")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.systemGreen)

            if let csq = signalCsqRaw, csq != 99 {
                Text("CSQ: \(csq)")
                    .font(.caption)
                    .foregroundColor(.systemGreen)
            }
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(Color.systemGreen.opacity(0.1))
        .cornerRadius(AppTheme.CornerRadius.medium)
    }

    // MARK: - Angle Guidance Panel
    private var angleGuidancePanel: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            // 第一行：卫星方位 + 卫星仰角
            HStack(spacing: AppTheme.Spacing.lg) {
                // 卫星方位
                HStack(spacing: 6) {
                    Image(systemName: "satellite")
                        .foregroundColor(.systemBlue)
                        .font(.caption)
                    Text("方位")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let satAz = satAzimuth {
                        Text(azimuthToChineseDirection(satAz))
                            .font(.system(size: 15, weight: .medium))
                    } else {
                        Text("获取中...")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // 卫星仰角
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(.systemBlue)
                        .font(.caption)
                    Text("卫星仰角")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let satEl = satElevation {
                        Text("\(String(format: "%.0f", satEl))°")
                            .font(.system(size: 15, weight: .medium))
                    } else {
                        Text("--")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            // 第二行：设备旋转 + 设备扬起
            HStack(spacing: AppTheme.Spacing.lg) {
                // 旋转引导
                HStack(spacing: 6) {
                    Image(systemName: "arrow.trianglehead.2.clockwise")
                        .foregroundColor(.systemOrange)
                        .font(.caption)
                    Text("旋转")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let satAz = satAzimuth, let devAz = deviceAzimuth {
                        let deltaAz = satAz - devAz
                        let normalizedDelta = (deltaAz + 540).truncatingRemainder(dividingBy: 360) - 180
                        let isAligned = abs(normalizedDelta) < 15
                        let arrow = normalizedDelta > 0 ? "→" : "←"
                        Text("\(arrow) \(String(format: "%.0f", abs(normalizedDelta)))°")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(isAligned ? .systemGreen : .systemOrange)
                    } else {
                        Text("--")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // 设备扬起
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up")
                        .foregroundColor(.systemOrange)
                        .font(.caption)
                    Text("扬起")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let deltaEl = deltaElevation {
                        let isElAligned = abs(deltaEl) < 10
                        let arrow = deltaEl > 0 ? "↑" : "↓"
                        Text("\(arrow) \(String(format: "%.0f", abs(deltaEl)))°")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(isElAligned ? .systemGreen : .systemOrange)
                        if isElAligned {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.systemGreen)
                        }
                    } else {
                        Text("--")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(Color.cardBackgroundLight)
        .cornerRadius(AppTheme.CornerRadius.large)
    }

    // MARK: - Coordinate Row
    private var coordinateRow: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            // 对齐状态
            VStack(spacing: 2) {
                Text("对准状态")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if isPointingAligned {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.systemGreen)
                            .font(.caption)
                        Text("已对准")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.systemGreen)
                    }
                } else {
                    Text("调整中")
                        .font(.system(size: 13))
                        .foregroundColor(.systemOrange)
                }
            }
            .frame(maxWidth: .infinity)

            // GPS 定位时间
            VStack(spacing: 2) {
                Text("定位状态")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let _ = satAzimuth {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .foregroundColor(.systemGreen)
                            .font(.caption)
                        Text("已定位")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.systemGreen)
                    }
                } else {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("定位中...")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(AppTheme.Spacing.md)
        .background(Color.cardBackgroundLight)
        .cornerRadius(AppTheme.CornerRadius.medium)
    }

    // MARK: - Location & Motion
    private func startLocationAndMotionUpdates() {
        // Set up location delegate callback (每次都设置，确保能接收到更新)
        locationDelegate.onLocationUpdate = { location in
            Task { @MainActor in
                self.onLocationUpdate(location)
            }
        }

        // 设置 delegate（只设置一次，但每次都检查）
        if locationManager.delegate !== locationDelegate {
            locationManager.delegate = locationDelegate
        }

        // 请求位置权限
        locationManager.requestWhenInUseAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 5.0

        // 根据权限状态启动位置更新
        let status = locationManager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.startUpdatingLocation()
            print("[HomeView] Location updates started")
        } else if status == .notDetermined {
            print("[HomeView] Location permission not determined, waiting for user response...")
        } else {
            print("[HomeView] Location permission denied or restricted: \(status.rawValue)")
        }

        // 如果当前有位置信息，立即使用
        if let loc = locationManager.location {
            print("[HomeView] Using existing location: \(loc.coordinate.latitude), \(loc.coordinate.longitude)")
            onLocationUpdate(loc)
        } else {
            print("[HomeView] No existing location, using test data (Beijing)...")
            // 使用北京坐标作为测试数据
            let testLocation = CLLocation(latitude: 39.9, longitude: 116.4)
            onLocationUpdate(testLocation)
        }

        // Motion (compass & elevation)
        guard motionManager.isDeviceMotionAvailable else {
            print("[HomeView] Device motion not available")
            return
        }

        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(using: .xTrueNorthZVertical, to: .main) { motion, _ in
            guard let motion = motion else { return }

            // 方位角
            let heading = motion.heading
            self.deviceAzimuth = self.devAzFilter.filterAzimuth360(heading)

            // 使用和 SOS 页面相同的方法计算设备仰角
            let rotMatrix = motion.attitude.rotationMatrix
            let matrixArray: [Float] = [
                Float(rotMatrix.m11), Float(rotMatrix.m12), Float(rotMatrix.m13),
                Float(rotMatrix.m21), Float(rotMatrix.m22), Float(rotMatrix.m23),
                Float(rotMatrix.m31), Float(rotMatrix.m32), Float(rotMatrix.m33)
            ]
            let deviceEl = self.devElFilter.filterLinear(
                GuidanceEngine.deviceYElevationDegrees(rotationMatrix: matrixArray)
            )

            self.deviceElevation = deviceEl

            // 计算需要扬起的角度
            if let satEl = self.satElevation {
                let delta = satEl - deviceEl
                self.deltaElevation = delta
            }

            // 调试输出（每60帧输出一次，避免刷屏）
            if Int.random(in: 1...60) == 1 {
                print("[HomeView] Motion - Az: \(String(format: "%.1f", self.deviceAzimuth ?? 0))°, El: \(String(format: "%.1f", deviceEl))°, Delta: \(String(format: "%.1f", self.deltaElevation ?? 0))°")
            }
        }
        print("[HomeView] Motion updates started")
    }

    private func stopLocationAndMotionUpdates() {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
    }

    private func onLocationUpdate(_ location: CLLocation) {
        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude

        let (azDeg, elDeg) = GeoMathEngine.getSatelliteAngle(
            latDeg: lat,
            lonDeg: lon
        )

        let filteredAz = satAzFilter.filterAzimuth360(azDeg)
        let filteredEl = satElFilter.filterLinear(elDeg)

        satAzimuth = filteredAz
        satElevation = filteredEl

        print("[HomeView] ✅ Location: \(lat), \(lon) -> Sat Az: \(filteredAz)°, El: \(filteredEl)°")
        print("[HomeView] satAzimuth: \(String(describing: satAzimuth)), satElevation: \(String(describing: satElevation))")
    }

    // MARK: - Refresh Button
    private var refreshButton: some View {
        Button(action: refreshDeviceInfo) {
            HStack(spacing: AppTheme.Spacing.sm) {
                if isRefreshing {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("刷新中...")
                        .font(.subheadline)
                } else {
                    Image(systemName: "arrow.clockwise")
                    Text("刷新信息")
                        .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.sm)
        }
        .buttonStyle(.bordered)
        .disabled(isRefreshing || isRefreshInCooldown)
        .opacity((isRefreshing || isRefreshInCooldown) ? 0.6 : 1.0)
    }

    // MARK: - Error Card
    private func errorCard(_ message: String) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.systemRed)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.systemRed)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: { errorMessage = nil }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(Color.systemRed.opacity(0.1))
        .cornerRadius(AppTheme.CornerRadius.medium)
    }

    // MARK: - Private Methods

    private func startScan() {
        scanTask?.cancel()
        scanTask = Task {
            for await _ in bleManager.scanDevices() {
                // Devices are automatically added to bleManager.scannedDevices
            }
        }
    }

    private func handleConnectionStateChange(_ state: ConnectState) {
        let isConnected = state.isConnected

        if isConnected && !wasConnected {
            // Just connected - refresh device info immediately
            Task {
                // 立即刷新一次
                await refreshDeviceInfoInternal()
                // 短暂延迟后再刷新
                try? await Task.sleep(nanoseconds: 500_000_000)
                await refreshDeviceInfoInternal()
                try? await Task.sleep(nanoseconds: 500_000_000)
                await refreshDeviceInfoInternal()
                startAutoRefreshTimer()
            }
        } else if !isConnected {
            // Disconnected - clear state
            batteryInfo = nil
            terminalVersion = nil
            ttModuleStatus = nil
            simState = nil
            networkRegStatus = nil
            signalCsqRaw = nil
            errorMessage = nil
            refreshTimer?.invalidate()
            refreshTimer = nil
        }

        wasConnected = isConnected
    }

    private func startAutoRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
            Task {
                await refreshDeviceInfoInternal()
            }
        }
    }

    private func refreshDeviceInfo() {
        guard !isRefreshing else {
            refreshHint = "正在刷新，请稍候"
            clearRefreshHintAfterDelay()
            return
        }
        guard !isRefreshInCooldown else {
            refreshHint = "请稍后再试"
            clearRefreshHintAfterDelay()
            return
        }

        Task {
            await refreshDeviceInfoInternal()
        }
    }

    private func refreshDeviceInfoInternal() async {
        await MainActor.run {
            isRefreshing = true
        }

        let systemClient = bleManager.getSystemClient()

        // Fetch battery info
        let batteryResult = await systemClient.readBattery()
        switch batteryResult {
        case .success(let info):
            await MainActor.run { batteryInfo = info }
        case .failure(let error):
            print("[HomeView] Failed to read battery: \(error.localizedDescription)")
        }

        // Fetch version info
        let versionResult = await systemClient.readVersionInfo()
        switch versionResult {
        case .success(let version):
            await MainActor.run { terminalVersion = version }
        case .failure(let error):
            print("[HomeView] Failed to read version: \(error.localizedDescription)")
        }

        // Fetch TT module status
        let ttResult = await systemClient.getTtModuleStatus()
        switch ttResult {
        case .success(let status):
            await MainActor.run { ttModuleStatus = status }
        case .failure(let error):
            print("[HomeView] Failed to read TT status: \(error.localizedDescription)")
        }

        // Fetch AT-based status (SIM, Network, Signal) via AT client
        let atClient = bleManager.getAtCommandClient()

        // AT+CSQ - Signal strength
        let csqResult = await atClient.sendCommand("AT+CSQ")
        switch csqResult {
        case .success(let response):
            if let csq = parseCsqResponse(response) {
                await MainActor.run { signalCsqRaw = csq }
            }
        case .failure(let error):
            print("[HomeView] Failed to read CSQ: \(error.localizedDescription)")
        }

        // AT+CPIN? - SIM status
        let cpinResult = await atClient.sendCommand("AT+CPIN?")
        switch cpinResult {
        case .success(let response):
            if let sim = parseCpinResponse(response) {
                await MainActor.run { simState = sim }
            }
        case .failure(let error):
            print("[HomeView] Failed to read CPIN: \(error.localizedDescription)")
        }

        // AT+CREG? - Network registration
        let cregResult = await atClient.sendCommand("AT+CREG?")
        switch cregResult {
        case .success(let response):
            if let reg = parseCregResponse(response) {
                await MainActor.run { networkRegStatus = reg }
            }
        case .failure(let error):
            print("[HomeView] Failed to read CREG: \(error.localizedDescription)")
        }

        await MainActor.run {
            isRefreshing = false
            isRefreshInCooldown = true
        }

        // Cooldown period
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        await MainActor.run {
            isRefreshInCooldown = false
        }
    }

    private func clearRefreshHintAfterDelay() {
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 seconds
            await MainActor.run {
                refreshHint = nil
            }
        }
    }

    // MARK: - AT Response Parsers

    private func parseCsqResponse(_ response: String) -> Int? {
        // +CSQ: <rssi>,<ber>
        guard let range = response.range(of: "+CSQ:") else { return nil }
        let values = response[range.upperBound...]
            .trimmingCharacters(in: .whitespaces)
            .split(separator: ",")
        guard let first = values.first, let rssi = Int(first) else { return nil }
        return rssi
    }

    private func parseCpinResponse(_ response: String) -> SimState? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("READY") {
            return .ready
        } else if trimmed.contains("SIM PIN") {
            return .simPinRequired(remainingAttempts: 3)
        } else if trimmed.contains("SIM PUK") {
            return .simPukRequired(remainingAttempts: 10)
        } else if trimmed.contains("PH-SIM PIN") {
            return .phSimPinRequired(remainingAttempts: 3)
        } else if trimmed.contains("ERROR") || trimmed.contains("NO SIM") {
            return .absent
        }
        return .unknown
    }

    private func parseCregResponse(_ response: String) -> NetworkRegistrationStatus? {
        // +CREG: <n>,<stat>[,<lac>,<ci>]
        guard let range = response.range(of: "+CREG:") else { return nil }
        let values = response[range.upperBound...]
            .trimmingCharacters(in: .whitespaces)
            .split(separator: ",")

        guard values.count >= 2, let stat = Int(values[1].trimmingCharacters(in: .whitespaces)) else {
            return nil
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
}

// MARK: - Device Info Card
struct DeviceInfoCard: View {
    let batteryInfo: BatteryInfo
    let softwareVersion: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("设备信息")
                .font(.headline)
                .foregroundColor(.primary)

            Divider()

            InfoRow(
                icon: "battery.100",
                label: "电池电量",
                value: "\(batteryInfo.level)%",
                iconColor: batteryInfo.level > 20 ? .systemGreen : .systemRed
            )

            InfoRow(
                icon: "bolt.fill",
                label: "电压",
                value: "\(batteryInfo.voltage) mV",
                iconColor: .systemBlue
            )

            InfoRow(
                icon: "gauge.with.dots.needle.67percent",
                label: "电流",
                value: "\(batteryInfo.current) mA",
                iconColor: batteryInfo.current >= 0 ? .systemGreen : .systemOrange
            )

            InfoRow(
                icon: "info.circle",
                label: "软件版本",
                value: softwareVersion ?? "—",
                iconColor: .systemBlue
            )
        }
        .padding(AppTheme.Spacing.lg)
        .background(Color.cardBackgroundLight)
        .cornerRadius(AppTheme.CornerRadius.large)
    }
}

// MARK: - Satellite Module Card
struct SatelliteModuleCard: View {
    let ttModuleStatus: TtModuleStatus
    let signalCsqRaw: Int?
    let simState: SimState?
    let networkRegStatus: NetworkRegistrationStatus?

    private var isWorking: Bool {
        if case .working = ttModuleStatus.state { return true }
        return false
    }

    private var moduleStatusText: String {
        return ttModuleStatus.state.displayText
    }

    private var signalText: String {
        guard isWorking else { return "NA" }
        if let csq = signalCsqRaw {
            if csq == 99 || csq < 0 || csq > 31 {
                return "无信号"
            }
            return "\(csq)"
        }
        return "无信号"
    }

    private var networkText: String {
        guard isWorking else { return "NA" }
        if let reg = networkRegStatus {
            return reg.displayText
        }
        return "-"
    }

    private var simText: String {
        guard isWorking else { return "NA" }
        if let sim = simState {
            switch sim {
            case .absent:
                return "无卡"
            case .ready, .simPinRequired, .simPukRequired, .simPin2Required, .simPuk2Required, .phSimPinRequired:
                return "有卡"
            default:
                return "-"
            }
        }
        return "-"
    }

    private var hasSignal: Bool {
        if let csq = signalCsqRaw {
            return csq != 99 && csq >= 0 && csq <= 31
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Image(systemName: "satellite")
                    .font(.system(size: 24))
                    .foregroundColor(.systemBlue)

                Text("卫星模块")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                if isWorking || signalCsqRaw != nil {
                    Image(systemName: hasSignal ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .foregroundColor(hasSignal ? .systemGreen : .systemGray)
                }
            }

            Divider()

            InfoRow(
                icon: "cpu",
                label: "模块状态",
                value: moduleStatusText,
                iconColor: isWorking ? .systemGreen : .systemOrange
            )

            InfoRow(
                icon: "signal.cellular.3",
                label: "信号强度 (CSQ)",
                value: signalText,
                iconColor: hasSignal ? .systemGreen : .systemGray
            )

            InfoRow(
                icon: "antenna.radiowaves.left.and.right",
                label: "网络状态",
                value: networkText,
                iconColor: networkRegStatus?.isRegistered == true ? .systemGreen : .systemOrange
            )

            InfoRow(
                icon: "simcard",
                label: "SIM状态",
                value: simText,
                iconColor: simState?.isReady == true ? .systemGreen : .systemOrange
            )
        }
        .padding(AppTheme.Spacing.lg)
        .background(Color.cardBackgroundLight)
        .cornerRadius(AppTheme.CornerRadius.large)
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let icon: String
    let label: String
    let value: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 24)

            Text(label)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }
}

// MARK: - Scan Device Sheet
struct ScanDeviceSheet: View {
    let isScanning: Bool
    let devices: [ScannedDevice]
    let onDeviceSelected: (ScannedDevice) -> Void
    let onRescan: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if isScanning {
                    Section {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                        Text("正在搜索附近的TTCat设备...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                if devices.isEmpty && !isScanning {
                    Text("未发现设备，请确认TTCat已开机并在附近")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                }

                ForEach(devices) { device in
                    DeviceScanRow(device: device)
                        .contentShape(Rectangle())
                        .onTapGesture { onDeviceSelected(device) }
                }
            }
            .navigationTitle("搜索 TTCat 设备")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !isScanning {
                        Button("重新搜索") {
                            onRescan()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Device Scan Row
struct DeviceScanRow: View {
    let device: ScannedDevice

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 24))
                .foregroundColor(.systemBlue)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.headline)
                Text(device.address)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: device.signalIcon)
                .foregroundColor(device.signalColor)

            Text("\(device.rssi)dBm")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }
}

// MARK: - Home Location Delegate
class HomeLocationDelegate: NSObject, CLLocationManagerDelegate {
    var onLocationUpdate: ((CLLocation) -> Void)?

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            onLocationUpdate?(loc)
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(BLEManager())
}
