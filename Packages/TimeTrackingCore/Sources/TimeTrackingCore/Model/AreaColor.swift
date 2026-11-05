// AreaColor: `#RRGGBB` area colors, the default-color rule, and display
// derivations (data_and_sync.md §1.2, projects.md §4.4).

import Foundation

/// An sRGB color stored as uppercase `#RRGGBB`.
public struct AreaColor: Hashable, Sendable, CustomStringConvertible {
    /// The text color that contrasts best with a solid area color.
    public enum TextColor: Sendable {
        case black
        case white
    }

    /// sRGB components in 0...1.
    public struct RGB: Hashable, Sendable {
        public var red: Double
        public var green: Double
        public var blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// Hue in degrees (0..<360), saturation and brightness in 0...1.
    public struct HSB: Hashable, Sendable {
        public var hue: Double
        public var saturation: Double
        public var brightness: Double
    }

    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Parses `#RRGGBB` in either case; anything else is `invalidColor`.
    public init(_ string: String) throws(StoreError) {
        let hex = string.utf8
        guard hex.count == 7, hex.first == UInt8(ascii: "#"),
              hex.dropFirst().allSatisfy({ Self.hexDigits.contains($0) }),
              let value = UInt32(string.dropFirst(), radix: 16)
        else {
            throw .invalidColor
        }
        self.init(red: UInt8(value >> 16 & 0xFF), green: UInt8(value >> 8 & 0xFF), blue: UInt8(value & 0xFF))
    }

    /// From sRGB components in 0...1, clamped and rounded to 8 bits.
    public init(red: Double, green: Double, blue: Double) {
        func channel(_ value: Double) -> UInt8 {
            UInt8((min(max(value, 0), 1) * 255).rounded())
        }
        self.init(red: channel(red), green: channel(green), blue: channel(blue))
    }

    /// From HSB with hue in degrees and saturation and brightness in 0...1.
    public init(hue: Double, saturation: Double, brightness: Double) {
        let sector = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let chroma = brightness * saturation
        let second = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let base = brightness - chroma
        let rgb = switch Int(sector) {
        case 0: RGB(red: chroma, green: second, blue: 0)
        case 1: RGB(red: second, green: chroma, blue: 0)
        case 2: RGB(red: 0, green: chroma, blue: second)
        case 3: RGB(red: 0, green: second, blue: chroma)
        case 4: RGB(red: second, green: 0, blue: chroma)
        default: RGB(red: chroma, green: 0, blue: second)
        }
        self.init(red: rgb.red + base, green: rgb.green + base, blue: rgb.blue + base)
    }

    /// The stored form, `#RRGGBB` uppercase.
    public var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    public var description: String {
        hex
    }

    /// Components in 0...1.
    public var components: RGB {
        RGB(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }

    /// Hue in degrees (0..<360), saturation and brightness in 0...1.
    public var hsb: HSB {
        let rgb = components
        let maximum = max(rgb.red, rgb.green, rgb.blue)
        let delta = maximum - min(rgb.red, rgb.green, rgb.blue)
        let saturation = maximum == 0 ? 0 : delta / maximum
        return HSB(hue: Self.hue(rgb, maximum: maximum, delta: delta), saturation: saturation, brightness: maximum)
    }

    /// WCAG relative luminance.
    public var relativeLuminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let rgb = components
        return 0.2126 * linear(rgb.red) + 0.7152 * linear(rgb.green) + 0.0722 * linear(rgb.blue)
    }

    /// The WCAG contrast ratio with `other`.
    public func contrastRatio(with other: Self) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Black or white, whichever has the higher contrast on this color.
    public var textColor: TextColor {
        let black = Self(red: UInt8(0), green: 0, blue: 0)
        let white = Self(red: UInt8(255), green: 255, blue: 255)
        return contrastRatio(with: black) >= contrastRatio(with: white) ? .black : .white
    }

    /// The HSL lightness offsets of the per-project steps.
    public static let lightnessOffsets: [Double] = [0, 0.12, -0.12, 0.24, -0.24, 0.36]

    /// Whether step `index` repeats an earlier one (Reports adds a hatch).
    public static func isRepeatedStep(_ index: Int) -> Bool {
        index >= lightnessOffsets.count
    }

    /// The color at lightness step `index` (0-based): the step's offset
    /// added to the HSL lightness, clamped to 0.15...0.90.
    public func lightnessStep(_ index: Int) -> Self {
        let offset = Self.lightnessOffsets[index % Self.lightnessOffsets.count]
        let rgb = components
        let maximum = max(rgb.red, rgb.green, rgb.blue)
        let minimum = min(rgb.red, rgb.green, rgb.blue)
        let delta = maximum - minimum
        let lightness = (maximum + minimum) / 2
        let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness - 1))
        let hue = Self.hue(rgb, maximum: maximum, delta: delta)
        let newLightness = min(max(lightness + offset, 0.15), 0.90)
        let chroma = (1 - abs(2 * newLightness - 1)) * saturation
        // HSL to HSB: brightness = L + C / 2, saturation = C / brightness.
        let brightness = newLightness + chroma / 2
        return Self(hue: hue, saturation: brightness == 0 ? 0 : chroma / brightness, brightness: brightness)
    }

    /// The default color of a new area (data_and_sync.md §1.2): the
    /// midpoint of the largest circular gap between the whole-degree hues of
    /// `existing` colors with saturation at least 0.1, or 210 without any; at
    /// saturation 0.65 and brightness 0.80.
    public static func defaultColor(existing: [Self]) -> Self {
        Self(hue: Double(defaultHue(existing: existing)), saturation: 0.65, brightness: 0.80)
    }

    /// The hue of `defaultColor(existing:)`, in whole degrees.
    public static func defaultHue(existing: [Self]) -> Int {
        let hues = existing
            .map(\.hsb)
            .filter { $0.saturation >= 0.1 }
            .map { Int($0.hue.rounded()) % 360 }
            .sorted()
        guard let first = hues.first else {
            return 210
        }
        var bestStart = first
        var bestGap = -1
        for (index, hue) in hues.enumerated() {
            let next = index + 1 < hues.count ? hues[index + 1] : first + 360
            let gap = next - hue
            if gap > bestGap {
                bestGap = gap
                bestStart = hue
            }
        }
        return (bestStart + bestGap / 2) % 360
    }

    private static let hexDigits = Set("0123456789abcdefABCDEF".utf8)

    private static func hue(_ rgb: RGB, maximum: Double, delta: Double) -> Double {
        guard delta > 0 else {
            return 0
        }
        let raw: Double = if maximum == rgb.red {
            ((rgb.green - rgb.blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == rgb.green {
            (rgb.blue - rgb.red) / delta + 2
        } else {
            (rgb.red - rgb.green) / delta + 4
        }
        let degrees = raw * 60
        return degrees < 0 ? degrees + 360 : degrees
    }
}
