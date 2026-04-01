import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("Home")
                }
                .tag(0)

            DialerView()
                .tabItem {
                    Image(systemName: "phone.fill")
                    Text("Dialer")
                }
                .tag(1)

            SMSView()
                .tabItem {
                    Image(systemName: "message.fill")
                    Text("SMS")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
                .tag(3)
        }
        .tint(Color.systemBlue)
    }
}

#Preview {
    ContentView()
}
