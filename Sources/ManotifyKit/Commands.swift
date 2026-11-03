import AppKit
import ArgumentParser
import UserNotifications

private func describe(_ content: UNNotificationContent, id: String) -> [String: Any] {
    ["id": id, "title": content.title, "subtitle": content.subtitle, "body": content.body, "group": content.threadIdentifier]
}

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List pending and delivered notifications.")
    @Flag(help: "Only scheduled notifications.") var pending = false
    @Flag(help: "Only delivered notifications.") var delivered = false
    @Flag(name: .shortAndLong, help: "Print JSON.") var json = false

    func run() async throws {
        let center = try notificationCenter()
        let both = pending == delivered
        let waiting = pending || both ? await center.pendingNotificationRequests().map { describe($0.content, id: $0.identifier) } : []
        let shown = delivered || both ? await center.deliveredNotifications().map { describe($0.request.content, id: $0.request.identifier) } : []
        if json { return printJSON(["pending": waiting, "delivered": shown]) }
        for (state, items) in [("pending", waiting), ("delivered", shown)] {
            for item in items { print("\(state)\t\(item["id"] ?? "")\t\(item["title"] ?? "")") }
        }
    }
}

struct Remove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "remove", abstract: "Remove notifications.", aliases: ["rm"])
    @Argument(help: "IDs to remove.") var ids: [String] = []
    @Flag(help: "Only scheduled notifications.") var pending = false
    @Flag(help: "Only delivered notifications.") var delivered = false
    @Flag(help: "Remove everything in scope.") var all = false

    func validate() throws {
        if ids.isEmpty == !all { throw ValidationError("give IDs or --all") }
    }

    func run() throws {
        let center = try notificationCenter()
        let both = pending == delivered
        if pending || both {
            all ? center.removeAllPendingNotificationRequests() : center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        if delivered || both {
            all ? center.removeAllDeliveredNotifications() : center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }
}

struct Auth: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Ask for notification permission.")
    @Flag(help: "Skip the prompt and deliver quietly to Notification Center.") var provisional = false

    func run() async throws {
        try await ensureAuthorized(try notificationCenter(), provisional: provisional)
    }
}

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show this app's notification settings.", aliases: ["doctor"])
    @Flag(name: .shortAndLong, help: "Print JSON.") var json = false

    private func name(_ setting: UNNotificationSetting) -> String {
        switch setting {
        case .enabled: "enabled"
        case .disabled: "disabled"
        default: "unsupported"
        }
    }

    func run() async throws {
        let settings = await (try notificationCenter()).notificationSettings()
        let authorization = switch settings.authorizationStatus {
        case .authorized: "authorized"
        case .denied: "denied"
        case .provisional: "provisional"
        default: "not determined"
        }
        let style = switch settings.alertStyle {
        case .alert: "alert"
        case .banner: "banner"
        default: "none"
        }
        let report: [String: String] = [
            "version": version, "bundle": Bundle.main.bundleIdentifier ?? "", "authorization": authorization,
            "alertStyle": style, "alert": name(settings.alertSetting), "sound": name(settings.soundSetting),
            "badge": name(settings.badgeSetting), "notificationCenter": name(settings.notificationCenterSetting),
            "lockScreen": name(settings.lockScreenSetting), "timeSensitive": name(settings.timeSensitiveSetting),
            "critical": name(settings.criticalAlertSetting), "scheduledDelivery": name(settings.scheduledDeliverySetting),
        ]
        if json { return printJSON(report) }
        report.sorted { $0.key < $1.key }.forEach { print("\($0.key): \($0.value)") }
    }
}

struct OpenSettings: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "settings", abstract: "Open System Settings > Notifications.")

    func run() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
    }
}
