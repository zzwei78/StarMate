import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var bleManager: BLEManager
    @EnvironmentObject var callManager: CallManager

    @State private var showRebootMcuDialog = false
    @State private var showRebootTtDialog = false
    @State private var showPowerOffTtDialog = false
    @State private var showPowerOnTtDialog = false
    @State private var showFilePicker = false
    @State private var otaTarget: OTATarget = .mcu

    var body: some View {
        NavigationStack {
            List {
                // Header
                Section {
                    EmptyView()
                } header: {
                    HStack(spacing: AppTheme.Spacing.md) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 20))
                        Text("设置")
                            .font(.system(size: 20, weight: .bold))
                        Spacer()
                    }
                    .textCase(nil)
                }

                // Charging Management
                SettingsSection(title: "充电管理") {
                    SettingsSwitchItem(
                        title: "无线充电",
                        subtitle: "开启/关闭无线充电功能",
                        icon: "bolt.circle.fill",
                        isOn: $bleManager.isWirelessChargingEnabled,
                        enabled: bleManager.connectionState.isConnected
                    )

                    SettingsSwitchItem(
                        title: "Boost输出",
                        subtitle: "开启/关闭Boost升压输出",
                        icon: "powerplug.fill",
                        isOn: $bleManager.isBoostEnabled,
                        enabled: bleManager.connectionState.isConnected
                    )
                }

                // Call Recording
                SettingsSection(title: "通话录音") {
                    SettingsSwitchItem(
                        title: "允许通话录音",
                        subtitle: "开启后，通话时自动录音",
                        icon: "mic.fill",
                        isOn: $callManager.allowCallRecording,
                        enabled: true
                    )
                }

                // Device Management
                SettingsSection(title: "设备管理") {
                    SettingsClickItem(
                        title: "重启TTCat终端",
                        subtitle: "重启BLE终端设备(MCU)",
                        icon: "arrow.clockwise",
                        enabled: bleManager.connectionState.isConnected
                    ) {
                        showRebootMcuDialog = true
                    }

                    let rebootTtDisabled = bleManager.ttModuleState.isWorking == false &&
                        !(bleManager.ttModuleState == .working)

                    SettingsClickItem(
                        title: "重启天通模块",
                        subtitle: "重启卫星基带模块",
                        icon: "antenna.radiowaves.left.and.right",
                        enabled: bleManager.connectionState.isConnected && !rebootTtDisabled
                    ) {
                        showRebootTtDialog = true
                    }

                    if bleManager.ttModuleState.isWorking {
                        SettingsClickItem(
                            title: "关闭天通模块",
                            subtitle: "关闭卫星模块电源",
                            icon: "poweroff",
                            enabled: bleManager.connectionState.isConnected
                        ) {
                            showPowerOffTtDialog = true
                        }
                    } else {
                        SettingsClickItem(
                            title: "开启天通模块",
                            subtitle: "开启卫星模块电源",
                            icon: "power",
                            enabled: bleManager.connectionState.isConnected
                        ) {
                            showPowerOnTtDialog = true
                        }
                    }
                }

                // Terminal Info
                SettingsSection(title: "终端信息") {
                    if !bleManager.connectionState.isConnected {
                        Text("未连接设备")
                            .foregroundColor(.secondary)
                    } else if let v = bleManager.terminalVersion {
                        SettingsInfoItem(label: "软件版本", value: v.softwareVersion.isEmpty ? "—" : v.softwareVersion)
                        SettingsInfoItem(label: "硬件版本", value: v.hardwareVersion.isEmpty ? "—" : v.hardwareVersion)
                        SettingsInfoItem(label: "型号", value: v.modelNumber.isEmpty ? "—" : v.modelNumber)
                    } else {
                        Text("正在获取...")
                            .foregroundColor(.secondary)
                    }
                }

                // Baseband Info
                SettingsSection(title: "基带信息") {
                    if !bleManager.connectionState.isConnected {
                        Text("未连接设备")
                            .foregroundColor(.secondary)
                    } else if !bleManager.ttModuleState.isWorking {
                        SettingsInfoItem(label: "IMSI", value: "NA")
                        SettingsInfoItem(label: "CCID", value: "NA")
                        SettingsInfoItem(label: "软件版本", value: "NA")
                        SettingsInfoItem(label: "硬件版本", value: "NA")
                    } else if let v = bleManager.basebandVersion {
                        SettingsInfoItem(label: "IMSI", value: v.imsi.isEmpty ? "—" : v.imsi)
                        SettingsInfoItem(label: "CCID", value: v.ccid.isEmpty ? "—" : v.ccid)
                        SettingsInfoItem(label: "软件版本", value: v.softwareVersion.isEmpty ? "—" : v.softwareVersion)
                        SettingsInfoItem(label: "硬件版本", value: v.hardwareVersion.isEmpty ? "—" : v.hardwareVersion)
                    } else {
                        Text("正在获取...")
                            .foregroundColor(.secondary)
                    }

                    Button(action: { bleManager.refreshDeviceInfo() }) {
                        HStack {
                            if bleManager.isRefreshing {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("刷新中...")
                            } else {
                                Image(systemName: "arrow.clockwise")
                                Text("刷新")
                            }
                        }
                    }
                    .disabled(!bleManager.connectionState.isConnected || bleManager.isRefreshing)
                }

                // OTA Upgrade
                SettingsSection(title: "固件升级 (OTA)") {
                    OTASectionView(
                        otaState: bleManager.otaState,
                        otaProgress: bleManager.otaProgress,
                        isConnected: bleManager.connectionState.isConnected,
                        ttWorking: bleManager.ttModuleState.isWorking,
                        onMcuUpgrade: {
                            otaTarget = .mcu
                            showFilePicker = true
                        },
                        onTtUpgrade: {
                            otaTarget = .ttModule
                            showFilePicker = true
                        },
                        onAbort: { bleManager.abortOta() },
                        onComplete: { bleManager.resetOtaState() }
                    )
                }

                // About
                SettingsSection(title: "关于") {
                    SettingsInfoItem(label: "应用版本", value: "1.0.0")
                }

                // Error Display
                if let error = bleManager.errorMessage {
                    Section {
                        ErrorCard(message: error, onDismiss: { bleManager.clearError() })
                    }
                }
            }
            .listStyle(.insetGrouped)
            .alert("重启终端", isPresented: $showRebootMcuDialog) {
                Button("取消", role: .cancel) {}
                Button("确认重启", role: .destructive) {
                    bleManager.rebootDevice()
                }
            } message: {
                Text("确定要重启TTCat终端设备吗？\n重启后需要重新连接蓝牙。")
            }
            .alert("重启天通模块", isPresented: $showRebootTtDialog) {
                Button("取消", role: .cancel) {}
                Button("确认重启", role: .destructive) {
                    bleManager.rebootTtModule()
                }
            } message: {
                Text("确定要重启天通基带模块吗？\n重启过程中通话和短信功能暂不可用。")
            }
            .alert("关闭天通模块", isPresented: $showPowerOffTtDialog) {
                Button("取消", role: .cancel) {}
                Button("确认关闭", role: .destructive) {
                    bleManager.setTtModulePower(false)
                }
            } message: {
                Text("确定要关闭天通卫星模块吗？关闭后通话和短信功能不可用。")
            }
            .alert("开启天通模块", isPresented: $showPowerOnTtDialog) {
                Button("取消", role: .cancel) {}
                Button("确认开启") {
                    bleManager.setTtModulePower(true)
                }
            } message: {
                Text("确定要开启天通卫星模块吗？")
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        bleManager.startOta(target: otaTarget, firmwareUrl: url)
                    }
                case .failure:
                    break
                }
            }
        }
    }
}

// MARK: - Settings Section
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Section(header: Text(title).foregroundColor(.systemBlue)) {
            content()
        }
    }
}

// MARK: - Settings Switch Item
struct SettingsSwitchItem: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool
    let enabled: Bool

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .foregroundColor(enabled ? .systemBlue : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundColor(enabled ? .primary : .secondary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .disabled(!enabled)
        }
    }
}

// MARK: - Settings Click Item
struct SettingsClickItem: View {
    let title: String
    let subtitle: String
    let icon: String
    let enabled: Bool
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: icon)
                    .foregroundColor(enabled ? .systemBlue : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundColor(enabled ? .primary : .secondary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
        }
        .disabled(!enabled)
    }
}

// MARK: - Settings Info Item
struct SettingsInfoItem: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
    }
}

// MARK: - OTA Section View
struct OTASectionView: View {
    let otaState: OTAState
    let otaProgress: Int
    let isConnected: Bool
    let ttWorking: Bool
    let onMcuUpgrade: () -> Void
    let onTtUpgrade: () -> Void
    let onAbort: () -> Void
    let onComplete: () -> Void

    var body: some View {
        Group {
            switch otaState {
            case .idle:
                SettingsClickItem(
                    title: "终端软件升级（MCU固件）",
                    subtitle: "更新终端MCU固件",
                    icon: "arrow.down.circle.fill",
                    enabled: isConnected
                ) {
                    onMcuUpgrade()
                }

                SettingsClickItem(
                    title: "天通模块固件升级",
                    subtitle: "更新卫星基带模块固件",
                    icon: "icloud.and.arrow.down",
                    enabled: isConnected && ttWorking
                ) {
                    onTtUpgrade()
                }

            case .writing(let progress):
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text("正在写入固件...")
                        .font(.subheadline)

                    ProgressView(value: Double(progress), total: 100)
                        .tint(.systemBlue)

                    Text("\(progress)%")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("取消升级", role: .destructive, action: onAbort)
                }
                .padding(.vertical, AppTheme.Spacing.sm)

            case .verifying:
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text("正在校验固件...")
                        .font(.subheadline)
                    ProgressView()
                }
                .padding(.vertical, AppTheme.Spacing.sm)

            case .success:
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text("固件升级成功！")
                        .font(.subheadline)
                        .foregroundColor(.systemGreen)
                    Text("设备将自动重启")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("完成", action: onComplete)
                        .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, AppTheme.Spacing.sm)

            case .failed(let reason):
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text("固件升级失败")
                        .font(.subheadline)
                        .foregroundColor(.systemRed)
                    Text(reason)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("重试", action: onComplete)
                        .buttonStyle(.bordered)
                }
                .padding(.vertical, AppTheme.Spacing.sm)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(BLEManager())
        .environmentObject(CallManager())
}
