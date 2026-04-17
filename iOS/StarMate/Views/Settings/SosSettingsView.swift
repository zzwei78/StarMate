import SwiftUI
import ContactsUI

// MARK: - SOS Settings View
struct SosSettingsView: View {
    @StateObject private var viewModel = SosSettingsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            // Header
            Section {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.systemOrange)
                        Text("SOS 紧急求助模式")
                            .font(.headline)
                    }
                    Text("配置紧急求助的接收人和自定义消息。触发SOS后将自动发送短信并拨打电话。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, AppTheme.Spacing.xs)
            }

            // Message Preview
            Section(header: Text("消息预览")) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text(viewModel.previewBody)
                        .font(.callout)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppTheme.Spacing.md)
                        .background(Color.systemGray6)
                        .cornerRadius(AppTheme.CornerRadius.small)

                    HStack {
                        Spacer()
                        Text("\(viewModel.previewCharCount) 字符")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Custom SMS Content
            Section(header: Text("自定义内容（最多\(SosSlotsSnapshot.maxSmsContentLen)字）")) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("输入自定义求助信息（可选）", text: $viewModel.smsCustom)
                        .font(.body)
                        .onChange(of: viewModel.smsCustom) { _, newValue in
                            if newValue.count > SosSlotsSnapshot.maxSmsContentLen {
                                viewModel.smsCustom = String(newValue.prefix(SosSlotsSnapshot.maxSmsContentLen))
                            }
                            viewModel.recomputePreview()
                        }

                    HStack {
                        Spacer()
                        Text("\(viewModel.smsCustom.count)/\(SosSlotsSnapshot.maxSmsContentLen)")
                            .font(.caption2)
                            .foregroundColor(viewModel.smsCustom.count >= SosSlotsSnapshot.maxSmsContentLen ? .systemRed : .secondary)
                    }
                }
            }

            // SMS Recipients
            Section(header: Text("短信接收号码")) {
                sosPhoneRow(label: "号码 1", text: $viewModel.smsSlot1)
                sosPhoneRow(label: "号码 2", text: $viewModel.smsSlot2)
                sosPhoneRow(label: "号码 3", text: $viewModel.smsSlot3)
            }

            // Call Recipients
            Section(header: Text("电话拨打号码")) {
                sosPhoneRow(label: "号码 1", text: $viewModel.callSlot1)
                sosPhoneRow(label: "号码 2", text: $viewModel.callSlot2)
                sosPhoneRow(label: "号码 3", text: $viewModel.callSlot3)
            }
        }
        .navigationTitle("SOS 设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Phone Row

    private func sosPhoneRow(label: String, text: Binding<String>) -> some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Text(label)
                .font(.body)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .leading)

            TextField("输入手机号码", text: text)
                .font(.body)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)

            Button(action: {
                // Contact picker would require UIViewControllerRepresentable
                // For now, manual entry
            }) {
                Image(systemName: "person.circle")
                    .foregroundColor(.systemBlue)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        SosSettingsView()
    }
}
