import SwiftUI
import CoreGraphics

/// A SwiftUI view that renders the StarMate app icon
/// Use this to generate the app icon by taking a screenshot in the simulator
struct AppIconView: View {
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color(hex: "007AFF"), Color(hex: "0055CC")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Satellite dish
                VStack(spacing: 0) {
                    // Signal waves
                    ZStack {
                        SignalWave(start: CGPoint(x: size * 0.7, y: size * 0.18),
                                   end: CGPoint(x: size * 0.82, y: size * 0.3),
                                   opacity: 0.9,
                                   width: size * 0.016)
                        SignalWave(start: CGPoint(x: size * 0.75, y: size * 0.13),
                                   end: CGPoint(x: size * 0.9, y: size * 0.3),
                                   opacity: 0.7,
                                   width: size * 0.012)
                        SignalWave(start: CGPoint(x: size * 0.8, y: size * 0.08),
                                   end: CGPoint(x: size * 0.98, y: size * 0.3),
                                   opacity: 0.5,
                                   width: size * 0.008)
                    }

                    // Dish
                    ZStack {
                        // Main dish shape
                        DishShape()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white, Color(hex: "E0E0E0")],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: size * 0.45, height: size * 0.24)
                            .offset(y: size * 0.08)

                        // Inner ring
                        Ellipse()
                            .stroke(Color(hex: "007AFF").opacity(0.5), lineWidth: size * 0.008)
                            .frame(width: size * 0.29, height: size * 0.12)
                            .offset(y: size * 0.05)

                        // LNB
                        RoundedRectangle(cornerRadius: size * 0.015)
                            .fill(Color(hex: "333333"))
                            .frame(width: size * 0.06, height: size * 0.04)
                            .offset(y: size * 0.0)

                        // Support pole
                        RoundedRectangle(cornerRadius: size * 0.02)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white, Color(hex: "E0E0E0")],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: size * 0.04, height: size * 0.25)
                            .offset(y: size * 0.2)
                    }
                    .frame(maxHeight: .infinity)

                    // Base
                    Ellipse()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: size * 0.08, height: size * 0.03)
                        .offset(y: -size * 0.05)
                }

                // Stars
                StarShape()
                    .fill(Color(hex: "FFD700"))
                    .frame(width: size * 0.04, height: size * 0.04)
                    .position(x: size * 0.2, y: size * 0.2)

                StarShape()
                    .fill(Color(hex: "FFD700").opacity(0.8))
                    .frame(width: size * 0.025, height: size * 0.025)
                    .position(x: size * 0.85, y: size * 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: size * 0.224))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Dish Shape
struct DishShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height

        path.move(to: CGPoint(x: 0, y: height * 0.8))
        path.addQuadCurve(
            to: CGPoint(x: width, y: height * 0.8),
            control: CGPoint(x: width / 2, y: 0)
        )
        path.addLine(to: CGPoint(x: width * 0.85, y: height))
        path.addQuadCurve(
            to: CGPoint(x: width * 0.15, y: height),
            control: CGPoint(x: width / 2, y: height * 0.6)
        )
        path.closeSubpath()

        return path
    }
}

// MARK: - Signal Wave
struct SignalWave: Shape {
    let start: CGPoint
    let end: CGPoint
    let opacity: Double
    let width: CGFloat

    init(start: CGPoint, end: CGPoint, opacity: Double, width: CGFloat) {
        self.start = start
        self.end = end
        self.opacity = opacity
        self.width = width
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: CGPoint(
            x: (start.x + end.x) / 2 + (end.x - start.x) * 0.3,
            y: (start.y + end.y) / 2 - (end.y - start.y) * 0.2
        ))
        return path
    }

    // Note: CGPoint doesn't conform to VectorArithmetic, so we use a simpler approach
    // var animatableData: Double {
    //     get { opacity }
    //     set { opacity = newValue }
    // }
}

// MARK: - Star Shape
struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * 0.4

        for i in 0..<5 {
            let outerAngle = Angle.degrees(Double(i) * 72 - 90).radians
            let innerAngle = Angle.degrees(Double(i) * 72 + 36 - 90).radians

            let outerPoint = CGPoint(
                x: center.x + CGFloat(cos(outerAngle)) * outerRadius,
                y: center.y + CGFloat(sin(outerAngle)) * outerRadius
            )
            let innerPoint = CGPoint(
                x: center.x + CGFloat(cos(innerAngle)) * innerRadius,
                y: center.y + CGFloat(sin(innerAngle)) * innerRadius
            )

            if i == 0 {
                path.move(to: outerPoint)
            } else {
                path.addLine(to: outerPoint)
            }
            path.addLine(to: innerPoint)
        }
        path.closeSubpath()

        return path
    }
}

// MARK: - Preview
#Preview {
    AppIconView()
        .frame(width: 1024, height: 1024)
        .background(Color.black)
}

// MARK: - Icon Generator Screen
struct IconGeneratorScreen: View {
    @State private var iconSize: CGFloat = 1024

    let sizes = [20, 29, 40, 60, 76, 167, 1024]

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                Text("StarMate App Icon Generator")
                    .font(.title)
                    .bold()

                Text("Take screenshots of each icon size below")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                ForEach(sizes, id: \.self) { size in
                    VStack(spacing: 8) {
                        Text("\(size) x \(size)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        AppIconView()
                            .frame(width: CGFloat(size), height: CGFloat(size))
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                }
            }
            .padding()
        }
    }
}

#Preview("Generator") {
    IconGeneratorScreen()
}
