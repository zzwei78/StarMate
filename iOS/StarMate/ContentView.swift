import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // SOS / Satellite Pointing
            SatellitePointingView(showSosPanel: true)
                .tabItem {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 24))
                    Text("SOS")
                        .font(.system(size: 12))
                }
                .tag(0)

            DialerView()
                .tabItem {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 24))
                    Text("Dialer")
                        .font(.system(size: 12))
                }
                .tag(1)

            HomeView()
                .tabItem {
                    Image(systemName: "house.fill")
                        .font(.system(size: 24))
                    Text("Home")
                        .font(.system(size: 12))
                }
                .tag(2)

            SMSView()
                .tabItem {
                    Image(systemName: "message.fill")
                        .font(.system(size: 24))
                    Text("SMS")
                        .font(.system(size: 12))
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 24))
                    Text("Settings")
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
