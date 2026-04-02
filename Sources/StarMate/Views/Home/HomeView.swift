import SwiftUI

struct HomeView: View {
    @EnvironmentObject var bleManager: BLEManager
    @State private var showScanDialog = false

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
                        onConnect: { showScanDialog = true },
                        onDisconnect: {
                            if bleManager.isScanning {
                                bleManager.stopScan()
                            } else {
                                bleManager.disconnect()
                            }
                        }
                    )

                    // Device Info Card
                    if let info = bleManager.deviceInfo {
                        DeviceInfoCard(
                            info: info,
                            softwareVersion: bleManager.terminalVersion?.softwareVersion
                        )
                    }

                    // Satellite Module Card
                    if bleManager.ttModuleState.isWorking || bleManager.signalCsqRaw != nil {
                        SatelliteModuleCard(
                            state: bleManager.ttModuleState,
                            signalCsqRaw: bleManager.signalCsqRaw,
                            regStatus: bleManager.deviceInfo?.regStatus,
                            simState: bleManager.simState,
                            networkRegistrationState: bleManager.networkRegistrationStatus
                        )
                    }

                    // Refresh Button
                    if bleManager.connectionState.isConnected {
                        RefreshButton(
                            isRefreshing: bleManager.isRefreshing,
                            hint: bleManager.refreshHint,
                            action: { bleManager.refreshDeviceInfo() }
                        )
                    }

                    // Error Message
                    if let error = bleManager.errorMessage {
                        ErrorCard(message: error, onDismiss: { bleManager.clearError() })
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
                        bleManager.connect(to: device)
                    },
                    onRescan: { bleManager.startScan() },
                    onDismiss: {
                        showScanDialog = false
                        bleManager.stopScan()
                    }
                )
            }
            .onAppear {
                // Auto-start scan if not connected
                if !bleManager.connectionState.isConnected {
                    // bleManager.startScan()
                }
            }
        }
    }
}

// MARK: - Connection Status Card
struct ConnectionStatusCard: View {
    let connectionState: ConnectionState
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

                    if case .connected(let device) = connectionState {
                        Text("TTCat \(device.address.suffix(8))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if case .error(let message) = connectionState {
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.systemRed)
                    }
                }

                Spacer()
            }

            Divider()

            switch connectionState {
            case .connected:
                Button(action: onDisconnect) {
                    Text("断开连接")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

            case .connecting:
                ProgressView()
                    .frame(maxWidth: .infinity)

            case .scanning:
                HStack(spacing: AppTheme.Spacing.sm) {
                    ProgressView()
                    Button(action: onDisconnect) {
                        Text("停止搜索")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

            default:
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
        case .connecting, .scanning: return "antenna.radiowaves.left.and.right"
        case .error: return "antenna.radiowaves.left.and.right.slash"
        default: return "antenna.radiowaves.left.and.right.slash"
        }
    }

    var statusText: String {
        switch connectionState {
        case .connected: return "已连接"
        case .connecting: return "正在连接..."
        case .scanning: return "正在搜索..."
        case .error: return "连接错误"
        default: return "未连接"
        }
    }

    var statusColor: Color {
        switch connectionState {
        case .connected: return .systemGreen
        case .connecting, .scanning: return .systemOrange
        case .error: return .systemRed
        default: return .systemGray
        }
    }
}

// MARK: - Device Info Card
struct DeviceInfoCard: View {
    let info: DeviceInfo
    let softwareVersion: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            Text("设备信息")
                .font(.headline)

            Divider()

            InfoRow(icon: "battery.100", label: "电池电量", value: "\(info.batteryLevel)%")
            InfoRow(icon: "bolt.fill", label: "电压", value: "\(info.voltageMv) mV")
            InfoRow(icon: "speedometer", label: "电流", value: "\(info.currentMa) mA")
            InfoRow(icon: "info.circle", label: "软件版本", value: softwareVersion ?? "—")
        }
        .padding(AppTheme.Spacing.lg)
        .background(Color.cardBackgroundLight)
        .cornerRadius(AppTheme.CornerRadius.large)
    }
}

// MARK: - Satellite Module Card
struct SatelliteModuleCard: View {
    let state: TtModuleState
    let signalCsqRaw: Int?
    let regStatus: Int?
    let simState: SimState?
    let networkRegistrationState: NetworkRegistrationStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 24))
                    .foregroundColor(.systemBlue)

                Text("卫星模块")
                    .font(.headline)

                Spacer()

                if state.isWorking || signalCsqRaw != nil {
                    Image(systemName: isNoSignal ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right")
                        .foregroundColor(isNoSignal ? .systemGray : .systemBlue)
                }
            }

            Divider()

            InfoRow(icon: "antenna.radiowaves.left.and.right", label: "模块状态", value: state.displayText)
            InfoRow(icon: "signal", label: "信号强度 (CSQ)", value: signalText)
            InfoRow(icon: "building.2.crop.circle", label: "网络状态", value: networkText)
            InfoRow(icon: "simcard", label: "SIM状态", value: simText)
        }
        .padding(AppTheme.Spacing.lg)
        .background(Color.cardBackgroundLight)
        .cornerRadius(AppTheme.CornerRadius.large)
    }

    var isNoSignal: Bool {
        guard let csq = signalCsqRaw else { return true }
        return csq == 99 || csq < 0 || csq > 31
    }

    var signalText: String {
        guard let csq = signalCsqRaw else {
            return state.isWorking ? "无信号" : "NA"
        }
        if csq == 99 { return "无信号" }
        if csq >= 0 && csq <= 31 { return "\(csq)" }
        return "无信号"
    }

    var networkText: String {
        if state.isWorking {
            return networkRegistrationState?.displayText ?? regStatusText
        }
        return "NA"
    }

    var regStatusText: String {
        switch regStatus {
        case 0: return "未注册"
        case 1: return "已注册"
        case 2: return "搜索中"
        case 3: return "拒绝"
        case 4: return "未知"
        case 5: return "漫游"
        default: return "—"
        }
    }

    var simText: String {
        if state.isWorking {
            return simState?.displayText ?? "-"
        }
        return "NA"
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.systemBlue)
                .frame(width: 24)

            Text(label)
                .font(.subheadline)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Refresh Button
struct RefreshButton: View {
    let isRefreshing: Bool
    let hint: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            Button(action: action) {
                HStack {
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("刷新中...")
                    } else {
                        Image(systemName: "arrow.clockwise")
                        Text("刷新信息")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshing)

            if let hint = hint {
                Text(hint)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Error Card
struct ErrorCard: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.systemRed)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.systemRed)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(AppTheme.CornerRadius.medium)
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
                        Button("重新搜索") { onRescan() }
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
