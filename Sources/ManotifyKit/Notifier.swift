import AppKit
import Security
import UserNotifications

enum UserInfoKey {
    static let open = "manotify.open", exec = "manotify.exec", activate = "manotify.activate"
    static let directory = "manotify.cwd", data = "manotify.data"
}

var launchedBySystem: Bool {
    getppid() == 1 && CommandLine.arguments.count == 1 && Bundle.main.bundleIdentifier != nil
}

final class NotificationEvents: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationEvents()
    var onResponse: ((UNNotificationResponse) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completion: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completion([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completion: @escaping () -> Void
    ) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            performClick(response.notification.request.content.userInfo)
        }
        completion()
        onResponse?(response)
    }
}

private func performClick(_ info: [AnyHashable: Any]) {
    if let target = info[UserInfoKey.open] as? String, let url = URL(string: target) {
        NSWorkspace.shared.open(url)
    }
    if let id = info[UserInfoKey.activate] as? String,
       let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
        NSWorkspace.shared.openApplication(at: app, configuration: .init())
    }
    if let command = info[UserInfoKey.exec] as? String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        if let directory = info[UserInfoKey.directory] as? String {
            process.currentDirectoryURL = URL(fileURLWithPath: directory)
        }
        try? process.run()
    }
}

func respondToSystemLaunch() -> Never {
    let events = NotificationEvents.shared
    events.onResponse = { _ in DispatchQueue.main.async { exit(0) } }
    UNUserNotificationCenter.current().delegate = events
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { exit(0) }
    NSApplication.shared.run()
    exit(0)
}

func notificationCenter() throws -> UNUserNotificationCenter {
    guard Bundle.main.bundleIdentifier != nil else {
        throw Failure("not running inside manotify.app; build it with scripts/bundle.sh")
    }
    var session = SecuritySessionId()
    var attributes = SessionAttributeBits()
    guard SessionGetInfo(callerSecuritySession, &session, &attributes) == errSecSuccess,
          attributes.contains(.sessionHasGraphicAccess) else {
        throw Failure("no GUI session; notifications cannot be sent over SSH or from a root daemon")
    }
    let app = Bundle.main.bundleURL.resolvingSymlinksInPath()
    let known = Bundle.main.bundleIdentifier.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    if known?.resolvingSymlinksInPath() != app {
        // usernoted rejects bundles LaunchServices doesn't know, such as one just rebuilt or upgraded.
        try runTool(lsregister, ["-f", app.path])
    }
    let center = UNUserNotificationCenter.current()
    center.delegate = NotificationEvents.shared
    return center
}

func ensureAuthorized(_ center: UNUserNotificationCenter, provisional: Bool = false) async throws {
    let denied = Failure("notifications are off for \(Bundle.main.bundleIdentifier ?? "this app"); enable them with `manotify settings`")
    switch await center.notificationSettings().authorizationStatus {
    case .denied:
        throw denied
    case .notDetermined:
        FileHandle.standardError.write(Data("Waiting for you to allow manotify in the prompt at the top right.\n".utf8))
        let options: UNAuthorizationOptions = provisional ? [.alert, .sound, .badge, .provisional] : [.alert, .sound, .badge]
        do {
            guard try await center.requestAuthorization(options: options) else { throw denied }
        } catch let error as UNError where error.code == .notificationsNotAllowed {
            throw Failure("macOS rejected \(Bundle.main.bundlePath); apps in /tmp or unregistered locations can't post notifications")
        }
    default:
        break
    }
}

