import SwiftUI

@main
struct StarMateApp: App {
    @StateObject private var bleManager = BLEManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bleManager)
                .environmentObject(CallManager(bleManager: bleManager))
                .environmentObject(SMSManager())
        }
    }
}
