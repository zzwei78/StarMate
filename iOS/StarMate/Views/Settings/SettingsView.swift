import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var bleManager: BLEManager
    @EnvironmentObject var callManager: CallManager

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
                    if case .connected(let address, _) = bleManager.connectionState {
                        SettingsInfoItem(
                            title: "设备地址",
                            value: address
                        )
                    }
                }

                // About
                SettingsSection(title: "关于") {
                    SettingsInfoItem(
                        title: "版本",
                        value: "1.0.0"
                    )
                }
            }
            .background(Color.systemGray6)
            .navigationBarHidden(true)
        }
    }

    private var connectionStateText: String {
        switch bleManager.connectionState {
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

    init(title: String, subtitle: String? = nil, icon: String, isOn: Binding<Bool>, enabled: Bool = true) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self._isOn = isOn
        self.enabled = enabled
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

            Toggle("", isOn: $isOn)
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
    let action: () -> Void

    init(title: String, subtitle: String? = nil, icon: String, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(.systemBlue)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundColor(.primary)
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
    }
}

// MARK: - OTA Section View (Simplified)

struct OTASectionView: View {
    let otaState: OtaState
    let otaProgress: Int
    let isConnected: Bool
    let ttWorking: Bool
    let onMcuUpgrade: () -> Void
    let onTtUpgrade: () -> Void
    let onAbort: () -> Void
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Text("OTA 升级")
                .font(.headline)

            Text("状态: \(otaStateText)")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if otaProgress > 0 {
                ProgressView(value: Double(otaProgress), total: 100)
                Text("\(otaProgress)%")
                    .font(.caption)
            }
        }
        .padding()
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
    SettingsView()
        .environmentObject(BLEManager())
}
