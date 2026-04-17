import SwiftUI

// MARK: - Satellite Finder Compass
/// Circular compass dial with satellite bearing marker.
/// Uses SwiftUI Canvas for high-performance drawing.
struct SatelliteFinderCompass: View {
    let deviceAzimuthDeg: Double?
    let satelliteAzimuthDeg: Double?
    let satelliteElevationDeg: Double?
    let isAligned: Bool
    let size: CGFloat

    init(
        deviceAzimuthDeg: Double?,
        satelliteAzimuthDeg: Double?,
        satelliteElevationDeg: Double?,
        isAligned: Bool = false,
        size: CGFloat = 220
    ) {
        self.deviceAzimuthDeg = deviceAzimuthDeg
        self.satelliteAzimuthDeg = satelliteAzimuthDeg
        self.satelliteElevationDeg = satelliteElevationDeg
        self.isAligned = isAligned
        self.size = size
    }

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let radius = min(canvasSize.width, canvasSize.height) / 2 - 16

            // Draw compass dial (world-fixed, rotated by device heading)
            let deviceAz = deviceAzimuthDeg ?? 0

            context.saveGState()
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: .degrees(-deviceAz))  // Rotate dial opposite to heading

            // Outer circle
            let outerRect = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
            context.stroke(
                Path(ellipseIn: outerRect),
                with: .color(.systemGray3),
                lineWidth: 1.5
            )

            // Tick marks
            for deg in stride(from: 0.0, through: 350.0, by: 10.0) {
                let isMajor = deg.truncatingRemainder(dividingBy: 30) == 0
                let tickLen: CGFloat = isMajor ? 12 : 6
                let angle = Angle.degrees(deg - 90).radians

                let outerPoint = CGPoint(
                    x: CGFloat(cos(angle)) * radius,
                    y: CGFloat(sin(angle)) * radius
                )
                let innerPoint = CGPoint(
                    x: CGFloat(cos(angle)) * (radius - tickLen),
                    y: CGFloat(sin(angle)) * (radius - tickLen)
                )

                var tickPath = Path()
                tickPath.move(to: outerPoint)
                tickPath.addLine(to: innerPoint)

                context.stroke(
                    tickPath,
                    with: .color(isMajor ? .systemGray : .systemGray4),
                    lineWidth: isMajor ? 1.5 : 0.8
                )
            }

            // Cardinal directions (N/E/S/W) — drawn at fixed positions on the rotating dial
            let cardinalDirs: [(String, Double, Color)] = [
                ("N", 0, .systemRed),
                ("E", 90, .systemGray),
                ("S", 180, .systemGray),
                ("W", 270, .systemGray)
            ]

            for (label, deg, color) in cardinalDirs {
                let angle = Angle.degrees(deg - 90).radians
                let textRadius = radius - 24
                let textCenter = CGPoint(
                    x: CGFloat(cos(angle)) * textRadius,
                    y: CGFloat(sin(angle)) * textRadius
                )

                let text = Text(label)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(color)
                let resolvedText = context.resolve(text)
                let textSize = resolvedText.measure(in: CGSize(width: 30, height: 20))
                resolvedText.draw(
                    at: CGPoint(x: textCenter.x - textSize.width / 2,
                                y: textCenter.y - textSize.height / 2)
                )
            }

            context.restoreGState()

            // Satellite marker (fixed on screen, shows satellite azimuth relative to device)
            if let satAz = satelliteAzimuthDeg {
                let relativeAz = satAz - deviceAz  // Satellite angle relative to device heading
                let satAngle = Angle.degrees(relativeAz - 90).radians  // -90 to start from top

                let markerRadius = radius - 36
                let markerCenter = CGPoint(
                    x: center.x + CGFloat(cos(satAngle)) * markerRadius,
                    y: center.y + CGFloat(sin(satAngle)) * markerRadius
                )

                // Satellite arrow (triangle pointing inward)
                let arrowLen: CGFloat = 14
                let arrowAngle = Angle.degrees(relativeAz + 90).radians  // Point toward center

                var arrow = Path()
                arrow.move(to: CGPoint(
                    x: markerCenter.x + CGFloat(cos(arrowAngle)) * arrowLen,
                    y: markerCenter.y + CGFloat(sin(arrowAngle)) * arrowLen
                ))
                arrow.addLine(to: CGPoint(
                    x: markerCenter.x + CGFloat(cos(arrowAngle + .pi / 2)) * (arrowLen / 2),
                    y: markerCenter.y + CGFloat(sin(arrowAngle + .pi / 2)) * (arrowLen / 2)
                ))
                arrow.addLine(to: CGPoint(
                    x: markerCenter.x + CGFloat(cos(arrowAngle - .pi / 2)) * (arrowLen / 2),
                    y: markerCenter.y + CGFloat(sin(arrowAngle - .pi / 2)) * (arrowLen / 2)
                ))
                arrow.closeSubpath()

                let satColor: Color = isAligned ? .systemGreen : .systemBlue
                context.fill(arrow, with: .color(satColor))
                context.stroke(arrow, with: .color(satColor), lineWidth: 1)

                // Satellite icon dot
                let dotRect = CGRect(
                    x: markerCenter.x - 4,
                    y: markerCenter.y - 4,
                    width: 8,
                    height: 8
                )
                context.fill(Path(ellipseIn: dotRect), with: .color(satColor))
            }

            // Center crosshair
            var crossH = Path()
            crossH.move(to: CGPoint(x: center.x - 10, y: center.y))
            crossH.addLine(to: CGPoint(x: center.x + 10, y: center.y))
            context.stroke(crossH, with: .color(.systemGray2), lineWidth: 1)

            var crossV = Path()
            crossV.move(to: CGPoint(x: center.x, y: center.y - 10))
            crossV.addLine(to: CGPoint(x: center.x, y: center.y + 10))
            context.stroke(crossV, with: .color(.systemGray2), lineWidth: 1)

            // Center dot
            let centerDotRect = CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)
            context.fill(
                Path(ellipseIn: centerDotRect),
                with: .color(isAligned ? .systemGreen : .systemBlue)
            )

            // Elevation text at center bottom
            if let el = satelliteElevationDeg {
                let elText = Text(String(format: "%.1f°", el))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                let resolvedEl = context.resolve(elText)
                let elSize = resolvedEl.measure(in: CGSize(width: 60, height: 16))
                resolvedEl.draw(
                    at: CGPoint(x: center.x - elSize.width / 2,
                                y: center.y + 16)
                )
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Azimuth to Chinese Direction
/// Converts azimuth (0-360°) to Chinese 16-point compass direction.
func azimuthToChineseDirection(_ azimuth: Double) -> String {
    // Normalize to 0-360
    var az = azimuth.truncatingRemainder(dividingBy: 360)
    if az < 0 { az += 360 }

    // 16-point compass with Chinese names
    let directions = [
        (0.0,   "北"),
        (22.5,  "北偏东"),
        (45.0,  "东北"),
        (67.5,  "东偏北"),
        (90.0,  "东"),
        (112.5, "东偏南"),
        (135.0, "东南"),
        (157.5, "南偏东"),
        (180.0, "南"),
        (202.5, "南偏西"),
        (225.0, "西南"),
        (247.5, "西偏南"),
        (270.0, "西"),
        (292.5, "西偏北"),
        (315.0, "西北"),
        (337.5, "北偏西")
    ]

    var best = directions[0]
    var bestDiff = 360.0
    for (deg, name) in directions {
        var diff = abs(az - deg)
        if diff > 180 { diff = 360 - diff }
        if diff < bestDiff {
            bestDiff = diff
            best = (deg, name)
        }
    }

    // Append exact angle
    return "\(best.1) \(String(format: "%.1f", az))°"
}

// MARK: - Signal Level Text
func signalLevelText(csq: Int?) -> String {
    guard let csq = csq else { return "未知" }
    if csq == 99 || csq < 0 { return "无信号" }
    if csq >= 20 { return "极好" }
    if csq >= 15 { return "良好" }
    if csq >= 10 { return "一般" }
    return "较弱"
}

func csqToDbm(_ csq: Int) -> Int {
    if csq == 99 { return -999 }
    return -113 + csq * 2
}

func csqToAsu(_ csq: Int) -> Int {
    if csq == 99 { return 0 }
    return csq
}
