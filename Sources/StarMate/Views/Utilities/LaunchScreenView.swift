import SwiftUI

/// Launch Screen View - SwiftUI version
/// This can be used as the initial view while the app is loading
struct LaunchScreenView: View {
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            // Background
            Color("LaunchBackground")
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Logo Animation
                ZStack {
                    // Signal waves animation
                    ForEach(0..<3) { index in
                        Circle()
                            .stroke(Color.systemBlue.opacity(0.3 - Double(index) * 0.1), lineWidth: 2)
                            .frame(width: 120 + CGFloat(index * 30), height: 120 + CGFloat(index * 30))
                            .scaleEffect(isAnimating ? 1.2 : 0.8)
                            .opacity(isAnimating ? 0 : 0.5)
                            .animation(
                                Animation.easeInOut(duration: 1.5)
                                    .repeatForever(autoreverses: false)
                                    .delay(Double(index) * 0.3),
                                value: isAnimating
                            )
                    }

                    // Satellite icon
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 60, weight: .light))
                        .foregroundColor(.systemBlue)
                        .symbolEffect(.pulse, options: .repeating, isActive: true)
                }

                // App Name
                Text("StarMate")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.systemBlue)

                // Tagline
                Text("天通卫星通信终端")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                // Loading indicator
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .systemBlue))
                    .padding(.top, 32)
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// MARK: - Launch Screen Transition Modifier
extension View {
    /// Adds a launch screen overlay that dismisses after loading
    func withLaunchScreen(isLoading: Binding<Bool>) -> some View {
        ZStack {
            self

            if isLoading.wrappedValue {
                LaunchScreenView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
    }
}

#Preview {
    LaunchScreenView()
}

#Preview("Dark Mode") {
    LaunchScreenView()
        .preferredColorScheme(.dark)
}
