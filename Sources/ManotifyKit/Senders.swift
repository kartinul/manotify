import ArgumentParser
import Foundation
import UserNotifications

func validateSenderName(_ name: String) throws {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    guard !name.isEmpty, name.unicodeScalars.allSatisfy(allowed.contains), name.allSatisfy(\.isASCII) else {
        throw ValidationError("sender names may only use letters, numbers, - and _")
    }
}

let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

@discardableResult
func runTool(_ path: String, _ arguments: [String]) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

enum Senders {
    private static let fileManager = FileManager.default

    static var directory: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("manotify/senders")
    }

    static func bundle(_ name: String) -> URL { directory.appendingPathComponent("\(name).app") }
    static func bundleID(_ name: String) -> String { "io.github.kartinul.manotify.sender.\(name)" }
    private static func infoPlist(_ bundle: URL) -> URL { bundle.appendingPathComponent("Contents/Info.plist") }
    private static func executable(_ bundle: URL) -> URL { bundle.appendingPathComponent("Contents/MacOS/manotify") }

    static func names() -> [String] {
        let items = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return items.filter { $0.hasSuffix(".app") }.map { String($0.dropLast(4)) }.sorted()
    }

    static func exists(_ name: String) -> Bool { fileManager.fileExists(atPath: bundle(name).path) }

    static func create(_ name: String, displayName: String?, icon: IconOptions) throws {
        let app = bundle(name)
        try fileManager.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: app.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        try writeInfo(app, id: bundleID(name), displayName: displayName ?? name)
        try writeIcon(app, icon)
        try installExecutable(app)
        try sign(app)
    }

    static func edit(_ name: String, displayName: String?, icon: IconOptions?) throws {
        let app = bundle(name)
        if let displayName { try writeInfo(app, id: bundleID(name), displayName: displayName) }
        if let icon { try writeIcon(app, icon) }
        try sign(app)
    }

    static func remove(_ name: String) throws {
        let app = bundle(name)
        _ = try? runTool("/usr/bin/tccutil", ["reset", "UserNotification", bundleID(name)])
        _ = try? runTool(lsregister, ["-u", app.path])
        try fileManager.removeItem(at: app)
    }

    /// Senders hold a copy of the binary, so refresh it after an upgrade.
    static func ensureCurrent(_ name: String) throws -> URL {
        let app = bundle(name)
        guard let data = try? Data(contentsOf: infoPlist(app)),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw Failure("no sender named \(name); create it with `manotify sender add \(name) -sf bell.fill`")
        }
        if info["CFBundleVersion"] as? String != version && Bundle.main.bundleIdentifier != bundleID(name) {
            try writeInfo(app, id: bundleID(name), displayName: info["CFBundleName"] as? String ?? name)
            try installExecutable(app)
            try sign(app)
        }
        return app
    }

    static func handOff(to app: URL) throws -> Never {
        let path = executable(app).path
        let arguments = ([path] + CommandLine.arguments.dropFirst()).map { strdup($0) } + [nil]
        execv(path, arguments)
        throw Failure("cannot start sender at \(path)")
    }

    private static func writeInfo(_ app: URL, id: String, displayName: String) throws {
        let info: [String: Any] = [
            "CFBundleIdentifier": id, "CFBundleExecutable": "manotify", "CFBundlePackageType": "APPL",
            "CFBundleName": displayName, "CFBundleDisplayName": displayName, "CFBundleVersion": version,
            "CFBundleShortVersionString": version, "CFBundleIconFile": "AppIcon",
            "LSMinimumSystemVersion": "13.0", "LSUIElement": true,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: infoPlist(app), options: .atomic)
    }

    private static func writeIcon(_ app: URL, _ icon: IconOptions) throws {
        let work = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".iconset")
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: work) }
        for side in [16, 32, 128, 256, 512] {
            try icon.png(side: side).write(to: work.appendingPathComponent("icon_\(side)x\(side).png"))
            try icon.png(side: side * 2).write(to: work.appendingPathComponent("icon_\(side)x\(side)@2x.png"))
        }
        let output = app.appendingPathComponent("Contents/Resources/AppIcon.icns")
        guard try runTool("/usr/bin/iconutil", ["-c", "icns", "-o", output.path, work.path]) == 0 else {
            throw Failure("iconutil failed")
        }
    }

    private static func installExecutable(_ app: URL) throws {
        guard let source = Bundle.main.executablePath else { throw Failure("cannot locate the manotify binary") }
        let target = executable(app)
        try? fileManager.removeItem(at: target)
        try fileManager.copyItem(atPath: source, toPath: target.path)
    }

    private static func sign(_ app: URL) throws {
        guard try runTool("/usr/bin/codesign", ["--force", "--sign", "-", app.path]) == 0 else {
            throw Failure("codesign failed for \(app.path)")
        }
        try runTool(lsregister, ["-f", app.path])
    }
}

struct SenderCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sender", abstract: "Manage senders, each with its own left icon.",
        subcommands: [Add.self, Edit.self, Rm.self, Ls.self]
    )

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a sender. Use -sf or -i for its icon.")
        @Argument var name: String
        @Option(help: "Name shown on notifications.") var displayName: String?
        @OptionGroup var icon: IconOptions

        func run() throws {
            try validateSenderName(name)
            guard !Senders.exists(name) else { throw Failure("sender \(name) already exists; use `sender edit`") }
            guard icon.symbol != nil || icon.image != nil else { throw ValidationError("give an icon with -sf or -i") }
            try Senders.create(name, displayName: displayName, icon: icon)
            print("Created \(name). Send with: manotify -n \(name) -t \"Hello\"")
        }
    }

    struct Edit: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Change a sender's icon or display name.")
        @Argument var name: String
        @Option(help: "Name shown on notifications.") var displayName: String?
        @OptionGroup var icon: IconOptions

        func run() throws {
            try validateSenderName(name)
            guard Senders.exists(name) else { throw Failure("no sender named \(name)") }
            try Senders.edit(name, displayName: displayName, icon: icon.symbol != nil || icon.image != nil ? icon : nil)
        }
    }

    struct Rm: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete a sender.")
        @Argument var name: String

        func run() throws {
            try validateSenderName(name)
            guard Senders.exists(name) else { throw Failure("no sender named \(name)") }
            try Senders.remove(name)
            warn("macOS has no API to remove its row in System Settings > Notifications, so one may remain")
        }
    }

    struct Ls: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "list", abstract: "List senders.")
        @Flag(name: .shortAndLong, help: "Print JSON.") var json = false

        func run() {
            if json { printJSON(Senders.names()) } else { Senders.names().forEach { print($0) } }
        }
    }
}
