import Foundation

// MARK: - Geo Math Engine
/// GEO satellite look angle calculations.
/// Pure math — no framework dependencies.
/// Ported from CosmoCat GeoMathEngine.kt
struct GeoMathEngine {

    /// Default Tiantong GEO satellite longitude (101.4°E)
    static let defaultSatelliteLongitudeDeg: Double = 101.4

    /// Earth radius in km
    private static let earthRadiusKm: Double = 6378.137

    /// GEO orbit radius in km
    private static let geoOrbitRadiusKm: Double = 42164.0

    /// Calculate azimuth and elevation to a GEO satellite.
    /// - Parameters:
    ///   - latDeg: Observer latitude in degrees
    ///   - lonDeg: Observer longitude in degrees
    ///   - satLonDeg: Satellite longitude in degrees (default 101.4°E)
    /// - Returns: (azimuth 0-360°, elevation 0-90°)
    static func getSatelliteAngle(
        latDeg: Double,
        lonDeg: Double,
        satLonDeg: Double = defaultSatelliteLongitudeDeg
    ) -> (azimuth: Double, elevation: Double) {
        let phi = latDeg * .pi / 180.0
        let lambda = lonDeg * .pi / 180.0
        let lambdaS = satLonDeg * .pi / 180.0

        let deltaLambda = lambdaS - lambda

        // Azimuth
        let azRad = atan2(sin(deltaLambda), -sin(phi) * cos(deltaLambda))
        var azDeg = azRad * 180.0 / .pi
        if azDeg < 0 { azDeg += 360.0 }

        // Elevation
        let c = cos(phi) * cos(deltaLambda)
        let ratio = earthRadiusKm / geoOrbitRadiusKm  // ≈ 0.1512
        let elRad = atan((c - ratio) / sqrt(1.0 - c * c))
        var elDeg = elRad * 180.0 / .pi

        // Clamp
        if elDeg < 0 { elDeg = 0 }
        if elDeg > 90 { elDeg = 90 }

        return (azDeg, elDeg)
    }
}
