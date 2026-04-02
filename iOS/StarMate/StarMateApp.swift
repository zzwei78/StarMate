import SwiftUI

@main
struct StarMateApp: App {
    @StateObject private var bleManager = BLEManager()
    @StateObject private var callManager = CallManager()
    @StateObject private var smsManager = SMSManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bleManager)
                .environmentObject(callManager)
                .environmentObject(smsManager)
        }
    }
}
