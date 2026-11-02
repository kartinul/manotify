import AppKit
import ArgumentParser

struct RGBA: Equatable, ExpressibleByArgument {
    var red, green, blue: Double
    var alpha = 1.0

    private static let names = [
        "white": "ffffff", "black": "000000", "clear": "00000000", "red": "ff3b30", "orange": "ff9500",
        "yellow": "ffcc00", "green": "34c759", "mint": "00c7be", "teal": "30b0c7", "cyan": "32ade6",
        "blue": "007aff", "indigo": "5856d6", "purple": "af52de", "pink": "ff2d55", "brown": "a2845e", "gray": "8e8e93",
    ]

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        (self.red, self.green, self.blue, self.alpha) = (red, green, blue, alpha)
    }

    init?(argument: String) {
        let text = argument.trimmingCharacters(in: .whitespaces).lowercased()
        if text.contains(",") {
            self.init(decimal: text)
        } else {
            self.init(hex: Self.names[text] ?? (text.hasPrefix("#") ? String(text.dropFirst()) : text))
        }
    }

    private init?(decimal text: String) {
        let body = text.replacingOccurrences(of: "rgb", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "() "))
        let parts = body.split(separator: ",", omittingEmptySubsequences: false)
            .map { UInt8($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 3, let red = parts[0], let green = parts[1], let blue = parts[2] else { return nil }
        self.init(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }

    private init?(hex text: String) {
        guard [3, 6, 8].contains(text.count), text.allSatisfy(\.isHexDigit) else { return nil }
        let full = text.count == 3 ? text.map { "\($0)\($0)" }.joined() : text
        let bytes = stride(from: 0, to: full.count, by: 2).compactMap { offset -> Double? in
            let start = full.index(full.startIndex, offsetBy: offset)
            return UInt8(full[start..<full.index(start, offsetBy: 2)], radix: 16).map { Double($0) / 255 }
        }
        self.init(red: bytes[0], green: bytes[1], blue: bytes[2], alpha: bytes.count == 4 ? bytes[3] : 1)
    }

    var ns: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
    var key: String { "\(red),\(green),\(blue),\(alpha)" }
}
