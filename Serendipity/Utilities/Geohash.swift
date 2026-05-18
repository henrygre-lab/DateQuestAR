// MARK: - Vibe Coding Security Checklist Compliance
// [x] Pure native Swift — no external dependencies
// [x] Precision 7 (≈150 m × 150 m) as required for Quest Mode
// [x] Correct bit-interleaving algorithm (longitude first per canonical spec)

import Foundation

extension String {
    /// Encode latitude/longitude to geohash string (base32)
    static func geohashEncode(latitude: Double, longitude: Double, precision: Int = 7) -> String {
        let base32 = Array("0123456789bcdefghjkmnpqrstuvwxyz")
        let lat = latitude.clamped(to: -90...90)
        let lon = longitude.clamped(to: -180...180)
        var latInterval = (-90.0, 90.0)
        var lonInterval = (-180.0, 180.0)
        var geohash = ""
        var bits = 0
        var ch = 0
        var even = true

        while geohash.count < precision {
            if even {
                let mid = (lonInterval.0 + lonInterval.1) / 2
                if lon >= mid {
                    ch |= 1 << (4 - bits)
                    lonInterval.0 = mid
                } else {
                    lonInterval.1 = mid
                }
            } else {
                let mid = (latInterval.0 + latInterval.1) / 2
                if lat >= mid {
                    ch |= 1 << (4 - bits)
                    latInterval.0 = mid
                } else {
                    latInterval.1 = mid
                }
            }

            even.toggle()
            bits += 1

            if bits == 5 {
                geohash.append(base32[ch])
                bits = 0
                ch = 0
            }
        }
        return geohash
    }

    /// Decode geohash back to approximate center lat/lon
    func geohashDecode() -> (lat: Double, lon: Double)? {
        guard !isEmpty else { return nil }

        let base32 = "0123456789bcdefghjkmnpqrstuvwxyz"
        var latInterval = (-90.0, 90.0)
        var lonInterval = (-180.0, 180.0)
        var even = true

        for char in self {
            guard let idx = base32.firstIndex(of: char) else { return nil }
            let value = base32.distance(from: base32.startIndex, to: idx)

            for bit in (0...4).reversed() {
                let mask = 1 << bit
                if even {
                    if (value & mask) != 0 {
                        lonInterval.0 = (lonInterval.0 + lonInterval.1) / 2
                    } else {
                        lonInterval.1 = (lonInterval.0 + lonInterval.1) / 2
                    }
                } else {
                    if (value & mask) != 0 {
                        latInterval.0 = (latInterval.0 + latInterval.1) / 2
                    } else {
                        latInterval.1 = (latInterval.0 + latInterval.1) / 2
                    }
                }
                even.toggle()
            }
        }

        let lat = (latInterval.0 + latInterval.1) / 2
        let lon = (lonInterval.0 + lonInterval.1) / 2
        return (lat, lon)
    }
}

// Helper for clamping (Swift 5.1+)
extension Double {
    func clamped(to limits: ClosedRange<Double>) -> Double {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}
