import Foundation

// MARK: - Guidance Engine
/// Calculates relative pointing angles between satellite and device orientation.
/// Pure math — no framework dependencies.
/// Ported from CosmoCat GuidanceEngine.kt
struct GuidanceEngine {

    /// Alignment thresholds (matching CosmoCat)
    static let pointingOkAzDeg: Double = 8.0
    static let pointingOkElDeg: Double = 12.0

    /// Calculate device +Y axis elevation from a 3x3 rotation matrix.
    /// The +Y axis is the top of the phone when held in portrait.
    /// - Parameter matrix: 9-element Float array (row-major)
    /// - Returns: Elevation in degrees (-90 to +90)
    static func deviceYElevationDegrees(rotationMatrix matrix: [Float]) -> Double {
        guard matrix.count == 9 else { return 0.0 }

        // Row 1 of rotation matrix = direction of device +Y in world frame
        // matrix[3] = yEast,  matrix[4] = yNorth,  matrix[5] = yUp
        let yEast = Double(matrix[3])
        let yNorth = Double(matrix[4])
        let yUp = Double(matrix[5])

        let horizontal = sqrt(yEast * yEast + yNorth * yNorth)
        let elevation = atan2(yUp, horizontal) * 180.0 / .pi

        return elevation
    }

    /// Calculate relative angles between satellite position and device orientation.
    /// - Parameters:
    ///   - satAzDeg: Satellite azimuth in degrees
    ///   - satElDeg: Satellite elevation in degrees
    ///   - deviceAzDeg: Device azimuth (heading) in degrees
    ///   - deviceElDeg: Device elevation in degrees
    /// - Returns: (deltaAz, deltaEl) in degrees, normalized to -180..180
    static func getRelativeAngle(
        satAzDeg: Double,
        satElDeg: Double,
        deviceAzDeg: Double,
        deviceElDeg: Double
    ) -> (deltaAz: Double, deltaEl: Double) {
        // Delta azimuth — handle 360° wrap
        var dAz = satAzDeg - deviceAzDeg
        if dAz > 180.0 { dAz -= 360.0 }
        if dAz < -180.0 { dAz += 360.0 }

        // Delta elevation (simple difference, no wrap)
        let dEl = satElDeg - deviceElDeg

        return (dAz, dEl)
    }

    /// Check if the pointing is within alignment tolerance.
    static func isAligned(deltaAz: Double, deltaEl: Double) -> Bool {
        return abs(deltaAz) <= pointingOkAzDeg && abs(deltaEl) <= pointingOkElDeg
    }
}
