import Foundation

// MARK: - Angle Low-Pass Filter
/// Exponential smoothing filter for sensor noise reduction.
/// Pure math — no framework dependencies.
/// Ported from CosmoCat AngleLowPass.kt
class AngleLowPass {

    private var previousValue: Double?
    let alpha: Double

    init(alpha: Double) {
        self.alpha = alpha
    }

    /// Filter a linear (non-circular) value, e.g. elevation.
    func filterLinear(_ newValue: Double) -> Double {
        guard let prev = previousValue else {
            previousValue = newValue
            return newValue
        }
        let filtered = alpha * newValue + (1.0 - alpha) * prev
        previousValue = filtered
        return filtered
    }

    /// Filter an azimuth value, handling 0-360° wraparound.
    func filterAzimuth360(_ newValue: Double) -> Double {
        guard let prev = previousValue else {
            previousValue = newValue
            return newValue
        }

        // Compute shortest angular difference
        var diff = newValue - prev
        if diff > 180.0 { diff -= 360.0 }
        if diff < -180.0 { diff += 360.0 }

        let filtered = prev + alpha * diff
        // Normalize to [0, 360)
        var result = filtered
        if result < 0 { result += 360.0 }
        if result >= 360.0 { result -= 360.0 }

        previousValue = result
        return result
    }

    /// Reset the filter state.
    func reset() {
        previousValue = nil
    }
}
