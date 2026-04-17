import SwiftUI
import CoreLocation

// MARK: - Location Info View
struct LocationInfoView: View {
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var altitude: Double?
    @State private var satAzimuth: Double?
    @State private var satElevation: Double?
    @State private var deviceAzimuth: Double?
    @State private var locationAuthAlert = false

    @State private var locationDelegate = LocationInfoDelegate()
    private let locationManager = CLLocationManager()

    var body: some View {
        List {
            // Satellite Angles
            Section(header: Text("卫星角度")) {
                HStack {
                    Text("方位角")
                        .font(.body)
                    Spacer()
                    if let az = satAzimuth {
                        Text(azimuthToChineseDirection(az))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.systemBlue)
                    } else {
                        Text("获取中...")
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text("仰角")
                        .font(.body)
                    Spacer()
                    if let el = satElevation {
                        Text(String(format: "%.1f°", el))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.systemBlue)
                    } else {
                        Text("获取中...")
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Compass
            Section(header: Text("卫星罗盘")) {
                VStack(spacing: AppTheme.Spacing.md) {
                    SatelliteFinderCompass(
                        deviceAzimuthDeg: deviceAzimuth,
                        satelliteAzimuthDeg: satAzimuth,
                        satelliteElevationDeg: satElevation,
                        size: 240
                    )
                    .frame(maxWidth: .infinity)

                    if let az = deviceAzimuth {
                        Text("当前朝向: \(String(format: "%.1f°", az))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, AppTheme.Spacing.sm)
            }

            // GPS Coordinates
            Section(header: Text("GPS 坐标")) {
                HStack {
                    Text("经度")
                        .font(.body)
                    Spacer()
                    if let lon = longitude {
                        Text(String(format: "%.6f°%@", abs(lon), lon >= 0 ? "E" : "W"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.primary)
                    } else {
                        Text("获取中...")
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text("纬度")
                        .font(.body)
                    Spacer()
                    if let lat = latitude {
                        Text(String(format: "%.6f°%@", abs(lat), lat >= 0 ? "N" : "S"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.primary)
                    } else {
                        Text("获取中...")
                            .foregroundColor(.secondary)
                    }
                }

                if let alt = altitude {
                    HStack {
                        Text("海拔")
                            .font(.body)
                        Spacer()
                        Text(String(format: "%.1f m", alt))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.primary)
                    }
                }
            }

            // Refresh
            Section {
                Button(action: requestLocation) {
                    HStack {
                        Image(systemName: "location.fill")
                        Text("刷新位置")
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("位置信息")
        .navigationBarTitleDisplayMode(.inline)
        .alert("位置权限", isPresented: $locationAuthAlert) {
            Button("去设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("需要位置权限来计算卫星方向。请在设置中开启定位权限。")
        }
        .onAppear {
            setupLocation()
        }
    }

    private func setupLocation() {
        locationManager.delegate = locationDelegate

        locationDelegate.onUpdate = { location in
            let lat = location.coordinate.latitude
            let lon = location.coordinate.longitude

            latitude = lat
            longitude = lon
            altitude = location.altitude

            let (az, el) = GeoMathEngine.getSatelliteAngle(latDeg: lat, lonDeg: lon)
            satAzimuth = az
            satElevation = el
        }

        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            locationManager.startUpdatingLocation()
        } else {
            locationAuthAlert = true
        }

        // Use current location if available
        if let loc = locationManager.location {
            locationDelegate.onUpdate?(loc)
        }
    }

    private func requestLocation() {
        let status = locationManager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.requestLocation()
        } else {
            locationAuthAlert = true
        }
    }
}

// MARK: - Location Delegate for LocationInfoView
class LocationInfoDelegate: NSObject, CLLocationManagerDelegate {
    var onUpdate: ((CLLocation) -> Void)?

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            onUpdate?(loc)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[LocationInfo] Error: \(error.localizedDescription)")
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            manager.startUpdatingLocation()
        }
    }
}

#Preview {
    NavigationStack {
        LocationInfoView()
    }
}
