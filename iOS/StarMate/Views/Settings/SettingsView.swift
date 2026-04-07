import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel

    // Dialog states
    @State private var showRebootMcuDialog = false
    @State private var showRebootTtDialog = false
    @State private var showPowerOffTtDialog = false
    @State private var showPowerOnTtDialog = false

    // File picker state
    @State private var showFilePicker = false
    @State private var otaTarget: OtaTarget?

    init(bleManager: BLEManager = BLEManager()) {
        _viewModel = StateObject(wrappedValue: SettingsViewModel(bleManager: bleManager))
    }

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

                // Connection Info
                SettingsSection(title: "连接信息") {
                    SettingsInfoItem(
                        title: "状态",
                        value: connectionStateText
                    )
                    if let address = viewModel.connectedDeviceAddress {
                        SettingsInfoItem(
                            title: "设备地址",
                            value: address
                        )
                    }
                }

                // 通话录音
                SettingsSection(title: "通话录音") {
                    SettingsSwitchItem(
                        title: "允许通话录音",
                        subtitle: "开启后，通话时自动录音",
                        icon: "mic.fill",
                        isOn: $viewModel.allowCallRecording,
                        enabled: true,
                        onChange: { viewModel.setAllowCallRecording($0) }
                    )
                }

                // 设备管理
                SettingsSection(title: "设备管理") {
                    // 重启TTCat终端
                    SettingsClickItem(
                        title: "重启TTCat终端",
                        subtitle: "重启BLE终端设备(MCU)",
                        icon: "arrow.clockwise",
                        enabled: viewModel.isConnected && !viewModel.isRebooting,
                        action: { showRebootMcuDialog = true }
                    )

                    // 重启天通模块
                    let rebootTtDisabled = isTtRebootDisabled(viewModel.ttModuleState)
                    SettingsClickItem(
                        title: "重启天通模块",
                        subtitle: "重启卫星基带模块",
                        icon: "satellite",
                        enabled: viewModel.isConnected && !viewModel.isRebooting && !rebootTtDisabled,
                        action: { showRebootTtDialog = true }
                    )

                    // 天通模块电源控制 (动态显示)
                    if viewModel.ttModuleState?.isWorking == true {
                        SettingsClickItem(
                            title: "关闭天通模块",
                            subtitle: "关闭卫星模块电源",
                            icon: "power",
                            enabled: viewModel.isConnected && !viewModel.isRebooting,
                            action: { showPowerOffTtDialog = true }
                        )
                    } else {
                        // Disable power on if low battery
                        let isLowBattery = isTtLowBatteryOff(viewModel.ttModuleState)
                        SettingsClickItem(
                            title: "开启天通模块",
                            subtitle: "开启卫星模块电源",
                            icon: "power",
                            enabled: viewModel.isConnected && !viewModel.isRebooting && !isLowBattery,
                            action: { showPowerOnTtDialog = true }
                        )
                    }

                    if viewModel.isRebooting {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding()
                            Spacer()
                        }
                    }
                }

                // 终端信息
                SettingsSection(title: "终端信息") {
                    if !viewModel.isConnected {
                        Text("未连接设备")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else if let version = viewModel.terminalVersion {
                        SettingsInfoItem(title: "软件版本", value: version.softwareVersion)
                        SettingsInfoItem(title: "硬件版本", value: version.hardwareVersion)
                        SettingsInfoItem(title: "型号", value: version.modelNumber)
                    } else {
                        Text("正在获取...")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    }
                }

                // 基带信息
                SettingsSection(title: "基带信息") {
                    let ttWorking = viewModel.ttModuleState?.isWorking == true

                    if !viewModel.isConnected {
                        Text("未连接设备")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else if !ttWorking {
                        SettingsInfoItem(title: "IMSI", value: "NA")
                        SettingsInfoItem(title: "CCID", value: "NA")
                        SettingsInfoItem(title: "软件版本", value: "NA")
                        SettingsInfoItem(title: "硬件版本", value: "NA")
                    } else if let baseband = viewModel.basebandVersion {
                        SettingsInfoItem(title: "IMSI", value: baseband.imsi.isEmpty ? "—" : baseband.imsi)
                        SettingsInfoItem(title: "CCID", value: baseband.ccid.isEmpty ? "—" : baseband.ccid)
                        SettingsInfoItem(title: "软件版本", value: baseband.softwareVersion.isEmpty ? "—" : baseband.softwareVersion)
                        SettingsInfoItem(title: "硬件版本", value: baseband.hardwareVersion.isEmpty ? "—" : baseband.hardwareVersion)
                    } else {
                        Text("正在获取...")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    }

                    // 刷新按钮
                    Button(action: {
                        Task { await viewModel.refreshVersions() }
                    }) {
                        HStack {
                            if viewModel.isRefreshing {
                                ProgressView()
                                    .padding(.trailing, 4)
                                Text("刷新中...")
                            } else {
                                Image(systemName: "arrow.clockwise")
                                Text("刷新")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!viewModel.isConnected || viewModel.isRefreshing || viewModel.ttModuleState?.isWorking != true)
                    .buttonStyle(.bordered)
                    .padding(.vertical, 8)
                }

                // 固件升级 (OTA)
                SettingsSection(title: "固件升级 (OTA)") {
                    OTASectionView(
                        otaState: viewModel.otaState,
                        otaProgress: viewModel.otaProgress,
                        isConnected: viewModel.isConnected,
                        ttWorking: viewModel.ttModuleState?.isWorking == true,
                        onMcuUpgrade: {
                            otaTarget = .mcu
                            showFilePicker = true
                        },
                        onTtUpgrade: {
                            otaTarget = .ttModule
                            showFilePicker = true
                        },
                        onAbort: {
                            Task { await viewModel.abortOta() }
                        },
                        onComplete: {
                            viewModel.resetOtaState()
                            Task { await viewModel.refreshVersions() }
                        },
                        onRetry: {
                            viewModel.resetOtaState()
                        }
                    )
                }

                // 关于
                SettingsSection(title: "关于") {
                    SettingsInfoItem(title: "版本", value: "1.0.0")
                }

                // Error display
                if let error = viewModel.error {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.body)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("关闭") {
                                viewModel.clearError()
                            }
                        }
                    }
                }

                // Success message
                if let msg = viewModel.message {
                    Section {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(msg)
                                .font(.body)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("关闭") {
                                viewModel.clearMessage()
                            }
                        }
                    }
                }
            }
            .background(Color.systemGray6)
            .navigationBarHidden(true)
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task {
                        if otaTarget == .mcu {
                            await viewModel.startMcuOta(firmwareUrl: url)
                        } else if otaTarget == .ttModule {
                            await viewModel.startTtOta(firmwareUrl: url)
                        }
                    }
                case .failure(let error):
                    viewModel.error = error.localizedDescription
                }
            }
            .alert("重启终端", isPresented: $showRebootMcuDialog) {
                Button("取消", role: .cancel) {}
                Button("确认重启", role: .destructive) {
                    Task { await viewModel.rebootMcu() }
                }
            } message: {
                Text("确定要重启TTCat终端设备吗？\n重启后需要重新连接蓝牙。")
            }
            .alert("重启天通模块", isPresented: $showRebootTtDialog) {
                Button("取消", role: .cancel) {}
                Button("确认重启", role: .destructive) {
                    Task { await viewModel.rebootTtModule() }
                }
            } message: {
                Text("确定要重启天通基带模块吗？\n重启过程中通话和短信功能暂不可用。")
            }
            .alert("关闭天通模块", isPresented: $showPowerOffTtDialog) {
                Button("取消", role: .cancel) {}
                Button("确认关闭", role: .destructive) {
                    Task { await viewModel.setTtModulePower(false) }
                }
            } message: {
                Text("确定要关闭天通卫星模块吗？关闭后通话和短信功能不可用。")
            }
            .alert("开启天通模块", isPresented: $showPowerOnTtDialog) {
                Button("取消", role: .cancel) {}
                Button("确认开启") {
                    Task { await viewModel.setTtModulePower(true) }
                }
            } message: {
                Text("确定要开启天通卫星模块吗？")
            }
        }
    }

    private var connectionStateText: String {
        switch viewModel.connectionState {
        case .disconnected:
            return "未连接"
        case .connecting:
            return "正在连接..."
        case .connected:
            return "已连接"
        case .error:
            return "连接错误"
        }
    }

    private func isTtLowBatteryOff(_ state: TtModuleState?) -> Bool {
        if case .lowBatteryOff = state {
            return true
        }
        return false
    }

    private func isTtRebootDisabled(_ state: TtModuleState?) -> Bool {
        // Disable reboot if UserOff, Initializing, or LowBatteryOff
        switch state {
        case .userOff, .initializing, .lowBatteryOff, .poweredOff:
            return true
        default:
            return false
        }
    }
}

// MARK: - Settings Section

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Section {
            content
        } header: {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
    }
}

// MARK: - Settings Info Item

struct SettingsInfoItem: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.body)
            Spacer()
            Text(value)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Settings Switch Item

struct SettingsSwitchItem: View {
    let title: String
    let subtitle: String?
    let icon: String
    @Binding var isOn: Bool
    let enabled: Bool
    let onChange: ((Bool) -> Void)?

    init(title: String, subtitle: String? = nil, icon: String, isOn: Binding<Bool>, enabled: Bool = true, onChange: ((Bool) -> Void)? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self._isOn = isOn
        self.enabled = enabled
        self.onChange = onChange
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.systemBlue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isOn },
                set: { newValue in
                    isOn = newValue
                    onChange?(newValue)
                }
            ))
            .disabled(!enabled)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Settings Click Item

struct SettingsClickItem: View {
    let title: String
    let subtitle: String?
    let icon: String
    let enabled: Bool
    let action: () -> Void

    init(title: String, subtitle: String? = nil, icon: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(enabled ? .systemBlue : .secondary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundColor(enabled ? .primary : .secondary)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .disabled(!enabled)
    }
}

// MARK: - OTA Section View

struct OTASectionView: View {
    let otaState: OtaState
    let otaProgress: Int
    let isConnected: Bool
    let ttWorking: Bool
    let onMcuUpgrade: () -> Void
    let onTtUpgrade: () -> Void
    let onAbort: () -> Void
    let onComplete: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            switch otaState {
            case .idle:
                // 显示升级选项
                VStack(spacing: 0) {
                    SettingsClickItem(
                        title: "终端软件升级（MCU固件）",
                        subtitle: "更新终端MCU固件",
                        icon: "arrow.down.circle",
                        enabled: isConnected,
                        action: onMcuUpgrade
                    )

                    Divider()
                        .padding(.leading, 48)

                    SettingsClickItem(
                        title: "天通模块固件升级",
                        subtitle: "更新卫星基带模块固件",
                        icon: "cloud.download",
                        enabled: isConnected && ttWorking,
                        action: onTtUpgrade
                    )
                }

            case .writing:
                VStack(alignment: .leading, spacing: 8) {
                    Text("正在写入固件...")
                        .font(.body)

                    ProgressView(value: Double(otaProgress), total: 100)
                        .progressViewStyle(.linear)

                    Text("\(otaProgress)%")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: onAbort) {
                        Text("取消升级")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 8)

            case .verifying:
                VStack(alignment: .leading, spacing: 8) {
                    Text("正在校验固件...")
                        .font(.body)

                    ProgressView()
                        .progressViewStyle(.linear)
                }
                .padding(.vertical, 8)

            case .success:
                VStack(alignment: .leading, spacing: 8) {
                    Text("固件升级成功！")
                        .font(.body)
                        .foregroundColor(.green)

                    Text("设备将自动重启")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: onComplete) {
                        Text("完成")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 8)

            case .failed(let reason):
                VStack(alignment: .leading, spacing: 8) {
                    Text("固件升级失败")
                        .font(.body)
                        .foregroundColor(.red)

                    Text(reason)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: onRetry) {
                        Text("重试")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var otaStateText: String {
        switch otaState {
        case .idle: return "空闲"
        case .writing: return "写入中"
        case .verifying: return "验证中"
        case .success: return "成功"
        case .failed: return "失败"
        }
    }
}

#Preview {
    SettingsView(bleManager: BLEManager())
}
