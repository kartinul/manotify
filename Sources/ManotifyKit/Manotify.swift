import AppKit
import ArgumentParser

let version = "0.1.0"

struct Failure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

func warn(_ message: String) {
    FileHandle.standardError.write(Data("warning: \(message)\n".utf8))
}

func printJSON(_ value: Any) {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return }
    print(String(decoding: data, as: UTF8.self))
}

/// Runs the CLI off the main thread so the main run loop stays free for notification callbacks.
public func launch() -> Never {
    if launchedBySystem { respondToSystemLaunch() }
    Task {
        await Manotify.main()
        exit(0)
    }
    NSApplication.shared.run()
    exit(0)
}

struct Manotify: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Send native macOS notifications.",
        discussion: "-sf, -c and -i add a thumbnail on the right. The left icon is the sending app's icon: create one with `sender add` and send with -n.",
        version: version,
        subcommands: [Send.self, List.self, Remove.self, SenderCommand.self, Auth.self, Status.self, OpenSettings.self],
        defaultSubcommand: Send.self
    )
}
