import SwiftUI
import Combine

struct HomeView: View {
    @EnvironmentObject var bleManager: BLEManager
    @State private var showScanDialog = false
    @State private var scanTask: Task<Void, Never>?

    // Device Info State
    @State private var batteryInfo: BatteryInfo?
    @State private var terminalVersion: TerminalVersion?
    @State private var ttModuleStatus: TtModuleStatus?
    @State private var simState: SimState?
    @State private var networkRegStatus: NetworkRegistrationStatus?
    @State private var signalCsqRaw: Int?

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
                    VStack(spacing: AppTheme.Spacing.xs) {
                        Text("StarMate")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.systemBlue)

                        Text("天通卫星通信终端")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, AppTheme.Spacing.lg)

                    // Connection Status Card
                    ConnectionStatusCard(
                        connectionState: bleManager.connectionState,
                        isScanning: bleManager.isScanning,
                        onConnect: {
                            showScanDialog = true
                            startScan()
                        },
                        onDisconnect: { bleManager.disconnect() }
                    )

                    // Device Info Card (when connected)
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
            }
            .onChange(of: bleManager.connectionState) { _, newState in
                handleConnectionStateChange(newState)
            }
        }
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
            // Just connected - refresh device info
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000) // 900ms
                await refreshDeviceInfoInternal()
                try? await Task.sleep(nanoseconds: 900_000_000)
                await refreshDeviceInfoInternal()
            }
            startAutoRefreshTimer()
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

// MARK: - Connection Status Card
struct ConnectionStatusCard: View {
    let connectionState: ConnectState
    let isScanning: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: statusIcon)
                    .font(.system(size: 28))
                    .foregroundColor(statusColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                        .font(.headline)

                    if case .connected(let address, _) = connectionState {
                        Text("TTCat \(address.suffix(8))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if case .error(_, let message) = connectionState {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.systemRed)
                    }
                }

                Spacer()
            }

            Divider()

            if isScanning {
                HStack(spacing: AppTheme.Spacing.sm) {
                    ProgressView()
                    Text("正在搜索...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else if connectionState.isConnected {
                Button(action: onDisconnect) {
                    Text("断开连接")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else if case .connecting = connectionState {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Button(action: onConnect) {
                    Label("搜索并连接 TTCat", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(Color.cardBackgroundLight)
        .cornerRadius(AppTheme.CornerRadius.large)
    }

    var statusIcon: String {
        switch connectionState {
        case .connected: return "antenna.radiowaves.left.and.right"
        case .connecting: return "antenna.radiowaves.left.and.right"
        case .error: return "antenna.radiowaves.left.and.right.slash"
        default: return "antenna.radiowaves.left.and.right.slash"
        }
    }

    var statusText: String {
        switch connectionState {
        case .connected: return "已连接"
        case .connecting: return "正在连接..."
        case .error: return "连接错误"
        default: return "未连接"
        }
    }

    var statusColor: Color {
        switch connectionState {
        case .connected: return .systemGreen
        case .connecting: return .systemOrange
        case .error: return .systemRed
        default: return .systemGray
        }
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

#Preview {
    HomeView()
        .environmentObject(BLEManager())
}
