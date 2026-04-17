import SwiftUI
import CoreLocation

// MARK: - Location Manager Delegate Bridge
class LocationDelegate: NSObject, CLLocationManagerDelegate {
    var onUpdate: ((CLLocation) -> Void)?

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            onUpdate?(loc)
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
}

// MARK: - Satellite Pointing View
struct SatellitePointingView: View {
    @EnvironmentObject private var bleManager: BLEManager
    @EnvironmentObject private var callManager: CallManager
    @EnvironmentObject private var smsManager: SMSManager

    @StateObject private var viewModel = SatellitePointingViewModel()

    let showSosPanel: Bool

    @State private var showSosConfirm = false
    @State private var locationDelegate = LocationDelegate()

    init(showSosPanel: Bool = true) {
        self.showSosPanel = showSosPanel
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.lg) {
                    // Link chain status bar
                    linkChainBar

                    // Success strip (when aligned + connected)
                    if viewModel.uiState.chainFullySuccess {
                        successStrip
                    }

                    // Main angle guidance panel
                    angleGuidancePanel

                    // Compass
                    SatelliteFinderCompass(
                        deviceAzimuthDeg: viewModel.uiState.deviceAzimuthDeg,
                        satelliteAzimuthDeg: viewModel.uiState.satAzimuthDeg,
                        satelliteElevationDeg: viewModel.uiState.satElevationDeg,
                        isAligned: viewModel.uiState.pointingAligned,
                        size: 260
                    )
                    .padding(.vertical, AppTheme.Spacing.sm)

                    // Coordinates
                    coordinateRow

                    // SOS Panel (conditional)
                    if showSosPanel {
                        sosPanel
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.top, AppTheme.Spacing.lg)
                .padding(.bottom, 100)
            }
            .background(Color.systemGray6)
            .navigationBarHidden(true)
            .alert("紧急求助", isPresented: $showSosConfirm) {
                Button("取消", role: .cancel) {}
                Button("确认发送") {
                    Task {
                        _ = await viewModel.triggerSos()
                    }
                }
            } message: {
                let smsCount = viewModel.uiState.sosSmsSlotCount
                let callCount = viewModel.uiState.sosCallSlotCount
                Text("将发送 \(smsCount) 条短信并拨打 \(callCount) 个电话。\n确认发送紧急求助？")
            }
        }
        .onAppear {
            viewModel.updateDependencies(
                bleManager: bleManager,
                callManager: callManager,
                smsManager: smsManager
            )
            viewModel.start()
            setupLocationDelegate()
        }
        .onDisappear {
            viewModel.stop()
        }
    }

    // MARK: - Link Chain Bar

    private var linkChainBar: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            linkIcon(icon: "iphone", label: "手机", active: true)
            linkArrow
            linkIcon(icon: "antenna.radiowaves.left.and.right", label: "蓝牙",
                     active: viewModel.uiState.bleConnected)
            linkArrow
            linkIcon(icon: "cpu", label: "模块",
                     active: viewModel.uiState.ttModuleWorking)
            linkArrow
            linkIcon(icon: "network", label: "网络",
                     active: viewModel.uiState.networkRegistered)
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

            if let csq = viewModel.uiState.signalCsqRaw, csq != 99 {
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
        VStack(spacing: AppTheme.Spacing.md) {
            // Satellite direction
            if let satAz = viewModel.uiState.satAzimuthDeg {
                HStack {
                    Text("卫星方位")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(azimuthToChineseDirection(satAz))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.systemBlue)
                }
            }

            // Delta Azimuth (rotation)
            if let dAz = viewModel.uiState.deltaAzDeg {
                HStack {
                    Text("设备旋转")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(deltaAzText(dAz))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(deltaColor(trend: viewModel.uiState.deltaAzTrend))
                }
            }

            // Delta Elevation (lift)
            if let dEl = viewModel.uiState.deltaElDeg {
                HStack {
                    Text("设备扬起")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(deltaElText(dEl))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(deltaColor(trend: viewModel.uiState.deltaElTrend))
                }
            }

            // Signal strength
            if let csq = viewModel.uiState.signalCsqRaw, csq != 99 {
                Divider()
                HStack {
                    Text("信号强度")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    let dbm = csqToDbm(csq)
                    let asu = csqToAsu(csq)
                    Text("\(dbm)dBm (\(signalLevelText(csq: csq))) ASU:\(asu)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(Color.cardBackgroundLight)
        .cornerRadius(AppTheme.CornerRadius.large)
    }

    // MARK: - Coordinate Row

    private var coordinateRow: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            if let satEl = viewModel.uiState.satElevationDeg {
                VStack(spacing: 2) {
                    Text("卫星仰角")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f°", satEl))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.systemBlue)
                }
                .frame(maxWidth: .infinity)
            }

            if let fixTime = viewModel.uiState.locationFixTimeLabel {
                VStack(spacing: 2) {
                    Text("定位时间")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(fixTime)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(Color.cardBackgroundLight)
        .cornerRadius(AppTheme.CornerRadius.medium)
    }

    // MARK: - SOS Panel

    private var sosPanel: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            if let feedback = viewModel.uiState.sosFeedbackMessage {
                Text(feedback)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(AppTheme.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.systemGray6)
                    .cornerRadius(AppTheme.CornerRadius.small)
            }

            Button(action: { showSosConfirm = true }) {
                HStack(spacing: AppTheme.Spacing.md) {
                    if viewModel.uiState.sosInProgress {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 24))
                    }
                    Text(viewModel.uiState.sosInProgress ? "发送中..." : "SOS 紧急求助")
                        .font(.system(size: 20, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.lg)
                .background(
                    viewModel.uiState.sosInProgress
                    ? Color.systemOrange
                    : Color.systemGreen
                )
                .cornerRadius(AppTheme.CornerRadius.large)
            }
            .disabled(viewModel.uiState.sosInProgress)

            let smsCount = viewModel.uiState.sosSmsSlotCount
            let callCount = viewModel.uiState.sosCallSlotCount
            if smsCount == 0 && callCount == 0 {
                Text("未配置SOS联系人，请前往 设置 > SOS设置 配置")
                    .font(.caption)
                    .foregroundColor(.systemOrange)
            } else {
                Text("已配置: \(smsCount)个短信号码, \(callCount)个电话号码")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func deltaAzText(_ dAz: Double) -> String {
        let arrow = dAz > 0 ? "→" : "←"
        return "\(arrow) \(String(format: "%.1f", abs(dAz)))°"
    }

    private func deltaElText(_ dEl: Double) -> String {
        let arrow = dEl > 0 ? "↑" : "↓"
        return "\(arrow) \(String(format: "%.1f", abs(dEl)))°"
    }

    private func deltaColor(trend: PointingDeltaTrend) -> Color {
        switch trend {
        case .improving: return .systemGreen
        case .worsening: return .systemOrange
        case .steady: return .systemBlue
        }
    }

    private func setupLocationDelegate() {
        let manager = viewModel.locationManager
        manager.delegate = locationDelegate
        locationDelegate.onUpdate = { [weak viewModel] location in
            Task { @MainActor in
                viewModel?.onLocationUpdate(location)
            }
        }

        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            manager.distanceFilter = 5.0
            manager.startUpdatingLocation()
        }
    }
}

#Preview {
    SatellitePointingView(showSosPanel: true)
        .environmentObject(BLEManager())
        .environmentObject(CallManager())
        .environmentObject(SMSManager())
}
