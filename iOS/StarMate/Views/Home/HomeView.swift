import SwiftUI

struct HomeView: View {
    @EnvironmentObject var bleManager: BLEManager
    @State private var showScanDialog = false
    @State private var scanTask: Task<Void, Never>?

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
            }
        }
    }

    private func startScan() {
        scanTask?.cancel()
        scanTask = Task {
            for await _ in bleManager.scanDevices() {
                // Devices are automatically added to bleManager.scannedDevices
            }
        }
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
