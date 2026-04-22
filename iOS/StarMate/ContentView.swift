import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 2  // 默认选中主页（中间位置）

    var body: some View {
        TabView(selection: $selectedTab) {
            // SMS
            SMSView()
                .tabItem {
                    Image(systemName: "message.fill")
                        .font(.system(size: 24))
                    Text("短信")
                        .font(.system(size: 12))
                }
                .tag(0)

            // Dialer
            DialerView()
                .tabItem {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 24))
                    Text("拨号")
                        .font(.system(size: 12))
                }
                .tag(1)

            // Home (主页在中间)
            HomeView()
                .tabItem {
                    Image(systemName: "house.fill")
                        .font(.system(size: 24))
                    Text("主页")
                        .font(.system(size: 12))
                }
                .tag(2)

            // SOS
            SatellitePointingView(showSosPanel: true)
                .tabItem {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 24))
                    Text("SOS")
                        .font(.system(size: 12))
                }
                .tag(3)

            // Settings
            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 24))
                    Text("设置")
                        .font(.system(size: 12))
                }
                .tag(4)
        }
        .tint(Color.systemBlue)
    }
}

#Preview {
    ContentView()
}
