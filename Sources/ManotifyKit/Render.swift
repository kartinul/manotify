import AppKit
import ArgumentParser
import CryptoKit
import Foundation

enum SymbolWeight: String, CaseIterable, ExpressibleByArgument {
    case ultralight, thin, light, regular, medium, semibold, bold, heavy, black

    var ns: NSFont.Weight {
        switch self {
        case .ultralight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        }
    }
}

enum SymbolScale: String, CaseIterable, ExpressibleByArgument {
    case small, medium, large

    var ns: NSImage.SymbolScale {
        switch self {
        case .small: .small
        case .medium: .medium
        case .large: .large
        }
    }
}

enum SymbolStyle: String, CaseIterable, ExpressibleByArgument {
    case mono, hierarchical, palette, multicolor
}

struct IconOptions: ParsableArguments {
    @Option(name: [.customLong("sf", withSingleDash: true), .customLong("symbol")], help: "SF Symbol name.")
    var symbol: String?

    @Option(name: [.short, .long], help: "Symbol color: white, ffffff, '#ffffff', 255,0,0 or '(255,0,0)'.")
    var color = RGBA(red: 1, green: 1, blue: 1)

    @Option(name: [.customShort("C"), .long], help: "Background color. Defaults to near black.")
    var background = RGBA(red: 0.11, green: 0.11, blue: 0.12)

    @Option(help: "Symbol weight: ultralight to black.")
    var weight = SymbolWeight.regular

    @Option(help: "Symbol scale: small, medium, large.")
    var scale = SymbolScale.medium

    @Option(help: "Symbol style: mono, hierarchical, palette, multicolor.")
    var style = SymbolStyle.mono

    @Option(help: "Palette color, repeatable. Used with --style palette.")
    var palette: [RGBA] = []

    @Option(help: "Variable symbol value, 0 to 1.")
    var value: Double?

    @Option(name: [.short, .long], help: "Custom image used instead of a symbol.", completion: .file())
    var image: String?

    func validate() throws {
        if symbol != nil && image != nil { throw ValidationError("use either -sf or -i, not both") }
        if let value, !(0...1).contains(value) { throw ValidationError("--value must be between 0 and 1") }
    }

    private var cacheKey: String {
        let modified = image.flatMap { try? FileManager.default.attributesOfItem(atPath: $0)[.modificationDate] as? Date }
        let parts = [symbol ?? "", image ?? "", modified.map { "\($0.timeIntervalSince1970)" } ?? "", color.key, background.key, weight.rawValue, scale.rawValue, style.rawValue,
                     palette.map(\.key).joined(separator: ";"), value.map { "\($0)" } ?? ""]
        return SHA256.hash(data: Data(parts.joined(separator: "|").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func cachedThumbnail() throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("manotify")
        let file = directory.appendingPathComponent("\(cacheKey).png")
        if FileManager.default.fileExists(atPath: file.path) { return file }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png(side: 512).write(to: file, options: .atomic)
        return file
    }

    func png(side: Int) throws -> Data {
        let foreground: NSImage
        var fill = false
        if let image {
            guard let loaded = NSImage(contentsOfFile: image) else { throw Failure("cannot read image: \(image)") }
            foreground = loaded
            fill = true
        } else {
            foreground = try glyph(side: Double(side))
        }

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )?.retagging(with: .sRGB), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw Failure("cannot create bitmap")
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let canvas = NSRect(x: 0, y: 0, width: side, height: side)
        background.ns.setFill()
        canvas.fill()
        foreground.draw(in: fitted(foreground.size, in: canvas, fill: fill))
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw Failure("cannot encode png") }
        return data
    }

    private func glyph(side: Double) throws -> NSImage {
        let name = symbol ?? "bell.fill"
        let base = value.map { NSImage(systemSymbolName: name, variableValue: $0, accessibilityDescription: nil) }
            ?? NSImage(systemSymbolName: name, accessibilityDescription: nil)
        guard let base else { throw Failure("unknown SF Symbol: \(name)") }

        var config = NSImage.SymbolConfiguration(pointSize: side * 0.6, weight: weight.ns, scale: scale.ns)
        switch style {
        case .mono: break
        case .hierarchical: config = config.applying(.init(hierarchicalColor: color.ns))
        case .palette: config = config.applying(.init(paletteColors: (palette.isEmpty ? [color] : palette).map(\.ns)))
        case .multicolor: config = config.applying(.preferringMulticolor())
        }
        guard let shaped = base.withSymbolConfiguration(config) else { throw Failure("cannot configure symbol: \(name)") }
        guard style == .mono else { return shaped }

        let tint = color.ns
        return NSImage(size: shaped.size, flipped: false) { rect in
            shaped.draw(in: rect)
            tint.setFill()
            rect.fill(using: .sourceIn)
            return true
        }
    }

    private func fitted(_ size: NSSize, in canvas: NSRect, fill: Bool) -> NSRect {
        let scale = fill
            ? max(canvas.width / size.width, canvas.height / size.height)
            : canvas.width * 0.62 / max(size.width, size.height)
        let (width, height) = (size.width * scale, size.height * scale)
        return NSRect(x: (canvas.width - width) / 2, y: (canvas.height - height) / 2, width: width, height: height)
    }
}
