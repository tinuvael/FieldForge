import Foundation

struct GSIChartPosition: Codable, Equatable {
    let x: Double
    let y: Double
    /// View-local logical points; origin top left. Outside touches are rejected, not clamped.
    static func touch(x: Double, y: Double, width: Double, height: Double) -> Self? {
        guard [x, y, width, height].allSatisfy(\.isFinite), width > 0, height > 0,
              (0...width).contains(x), (0...height).contains(y) else { return nil }
        return Self(x: x / width, y: y / height)
    }
}

/// Numerical geometry extracted from Table 5.34, printed p.126 / PDF p.141.
/// See docs/gsi-chart-dxf-elevation.md for calibration, controls and endpoint limits.
enum GSIChart {
    static let version = "Read-Stacey-2009/table5.34/vector-contours-v1"
    static let left = 289.24, top = 267.216507, width = 155.9765042, height = 257.5161922
    static let surfaceEdges = [0.0, (320.6291924-left)/width, (352.2131924-left)/width,
                               (383.3141924-left)/width, (414.5991924-left)/width, 1.0]
    static let structureEdges = [0.0, (309.788507-top)/height, (352.347507-top)/height,
        (394.920507-top)/height, (437.4916992-top)/height, (480.1556992-top)/height, 1.0]
    struct Contour {
        let value: Int
        let ax: Double, ay: Double, bx: Double, by: Double
        var a: GSIChartPosition { GSIChartPosition(x: (ax-left)/width, y: (ay-top)/height) }
        var b: GSIChartPosition { GSIChartPosition(x: (bx-left)/width, y: (by-top)/height) }
        func signedDistance(_ p: GSIChartPosition) -> Double {
            let dx = bx-ax, dy = by-ay
            return (dx * (top + p.y*height-ay) - dy * (left + p.x*width-ax)) / hypot(dx, dy)
        }
    }
    static let contours: [Contour] = [
        Contour(value: 95, ax: 288.9407959, ay: 280.2810974, bx: 303.9147959, by: 267.0210974),
        Contour(value: 90, ax: 289.2287959, ay: 294.9830974, bx: 320.6167959, by: 267.5980974),
        Contour(value: 85, ax: 289.2287959, ay: 315.1620974, bx: 336.1677959, by: 267.7010974),
        Contour(value: 80, ax: 289.1367959, ay: 331.6970974, bx: 352.2017959, by: 267.1240974),
        Contour(value: 75, ax: 288.9407959, ay: 352.3479004, bx: 365.2527959, by: 267.5979004),
        Contour(value: 70, ax: 289.1365051, ay: 369.2642059, bx: 378.6955051, by: 267.4132059),
        Contour(value: 65, ax: 289.3325051, ay: 389.6392059, bx: 383.1065051, by: 278.5522059),
        Contour(value: 60, ax: 289.1365051, ay: 410.9709930, bx: 383.3145051, by: 292.7799930),
        Contour(value: 55, ax: 289.5270996, ay: 434.0328979, bx: 383.1070996, by: 309.4998979),
        Contour(value: 50, ax: 289.4351044, ay: 459.2154999, bx: 397.5051044, by: 310.0764999),
        Contour(value: 45, ax: 294.4121044, ay: 480.1554999, bx: 410.1761044, by: 309.7994999),
        Contour(value: 40, ax: 315.7221044, ay: 480.2474999, bx: 424.2061044, by: 309.6844999),
        Contour(value: 35, ax: 336.4555054, ay: 480.4553070, bx: 438.1205054, by: 309.7993070),
        Contour(value: 30, ax: 352.2135010, ay: 484.5830994, bx: 445.1235010, by: 323.7290994),
        Contour(value: 25, ax: 352.0065010, ay: 524.1570994, bx: 445.0315010, by: 346.2150994),
        Contour(value: 20, ax: 370.0675010, ay: 524.5490994, bx: 445.0315010, by: 372.8260994),
        Contour(value: 15, ax: 391.1695010, ay: 524.4570994, bx: 445.0315010, by: 405.9660994),
        Contour(value: 10, ax: 410.1755010, ay: 524.1570994, bx: 445.1235010, by: 443.4420994),
        Contour(value: 5, ax: 428.6055010, ay: 524.4570994, bx: 445.3085010, by: 482.9460994)
    ]
    static func categories(_ p: GSIChartPosition) -> GSIChartSelection? {
        guard p.x.isFinite, p.y.isFinite, (0...1).contains(p.x), (0...1).contains(p.y) else { return nil }
        let column = min(4, surfaceEdges.dropFirst().prefix { p.x >= $0 }.count)
        let row = min(5, structureEdges.dropFirst().prefix { p.y >= $0 }.count)
        let selection = GSIChartSelection(structure: GSIStructure.allCases[row], surface: GSISurface.allCases[column])
        return selection.applicable ? selection : nil
    }
    struct Estimate: Equatable {
        let value: Int
        let lower: Int
        let upper: Int
    }
    static func estimate(_ p: GSIChartPosition) -> Estimate? {
        guard categories(p) != nil else { return nil }
        for c in contours where abs(c.signedDistance(p)) <= 1e-8 {
            return Estimate(value: c.value, lower: c.value, upper: c.value)
        }
        for (high, low) in zip(contours, contours.dropFirst()) {
            let a = high.signedDistance(p), b = low.signedDistance(p)
            if a > 0 && b < 0 {
                // Local interpolation between adjacent verified straight contours only.
                let fraction = a / (a-b)
                let value = Double(high.value) + fraction * Double(low.value-high.value)
                return Estimate(value: Int(value.rounded()), lower: low.value, upper: high.value)
            }
        }
        // No numerical extrapolation beyond the outermost published contours (5 and 95).
        return nil
    }
}
