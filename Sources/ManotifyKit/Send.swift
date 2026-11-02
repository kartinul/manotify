import AppKit
import ArgumentParser
import UserNotifications

enum Level: String, CaseIterable, ExpressibleByArgument {
    case passive, active, timeSensitive = "time-sensitive", critical

    var ns: UNNotificationInterruptionLevel {
        switch self {
        case .passive: .passive
        case .active: .active
        case .timeSensitive: .timeSensitive
        case .critical: .critical
        }
    }
}

struct ActionSpec: Equatable, ExpressibleByArgument {
    let id, title: String

    init?(argument: String) {
        let parts = argument.split(separator: ":", maxSplits: 1).map(String.init)
        guard let first = parts.first else { return nil }
        (id, title) = (first, parts.count == 2 ? parts[1] : first)
    }
}

func parsePair(_ text: String) -> (id: String, value: String)? {
    let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
    return parts.count == 2 ? (parts[0], parts[1]) : nil
}

struct Send: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Send a notification (default command).")

    @Argument(help: "Title, same as -t.") var text: String?
    @Option(name: .shortAndLong, help: "Title.") var title: String?
    @Option(name: [.customShort("u"), .long], help: "Subtitle.") var subtitle: String?
    @Option(name: .shortAndLong, help: "Body, or - for stdin.") var body: String?
    @OptionGroup(title: "Thumbnail") var icon: IconOptions
    @Option(name: [.customShort("a"), .long], help: "Extra audio, image or movie attachment, repeatable.", completion: .file()) var attach: [String] = []
    @Option(help: "Crop the thumbnail: x,y,w,h from 0 to 1.") var clip: String?
    @Option(help: "Thumbnail frame number or movie seconds.") var thumbTime: Double?
    @Flag(help: "Hide the attachment thumbnail.") var noThumb = false

    @Option(name: .shortAndLong, help: "Sound: default, none or a name.") var sound = "default"
    @Option(name: .shortAndLong, help: "Group notifications into a stack.") var group: String?
    @Option(name: [.customShort("I"), .long], help: "ID; reusing one replaces that notification and alerts again.") var id: String?
    @Option(name: .shortAndLong, help: "Level: passive, active, time-sensitive, critical.") var level: Level?
    @Option(name: [.customShort("n"), .long], help: "Send from this sender, which sets the left icon.") var sender: String?
    @Option(help: "Sort order in the stack, 0 to 1.") var relevance: Double?
    @Option(help: "App badge number.") var badge: Int?
    @Option(help: "JSON stored on the notification and returned by --json.") var userInfo: String?
    @Option(help: "Focus filter criteria.") var filter: String?

    @Option(name: [.customShort("A"), .long], help: "Button as id:title, repeatable.") var action: [ActionSpec] = []
    @Option(help: "Action options as id:destructive,auth,foreground.") var actionOpt: [String] = []
    @Option(help: "Action icon as id:symbol.") var actionIcon: [String] = []
    @Option(name: .shortAndLong, help: "Add a text reply button with this placeholder.") var reply: String?
    @Flag(help: "Report explicit dismissals.") var reportDismiss = false
    @Option(help: "Hidden preview text.") var hiddenText: String?
    @Option(help: "Group summary format, such as '%u new'.") var summary: String?
    @Flag(help: "Show the title when previews are hidden.") var showHiddenTitle = false

    @Option(name: .shortAndLong, help: "URL or path to open on click.") var open: String?
    @Option(name: [.customShort("x"), .long], help: "Shell command to run on click.") var exec: String?
    @Option(help: "Bundle ID to activate on click.") var activate: String?
    @Flag(name: .shortAndLong, help: "Wait and print what the user did. Exit 2 if dismissed or timed out.") var wait = false
    @Option(name: [.customShort("T"), .long], help: "Seconds to wait before removing it. Implies --wait.") var timeout: Double?
    @Flag(name: .shortAndLong, help: "Print JSON.") var json = false
    @Flag(name: [.customShort("D"), .long], help: "Print the request without sending it.") var dryRun = false

    @Option(name: [.customShort("d"), .customLong("in")], help: "Delay: 90s, 5m, 2h, 1d.") var delay: String?
    @Option(help: "Time: HH:MM or 'yyyy-MM-dd HH:mm'.") var at: String?
    @Flag(name: .customLong("repeat"), help: "Repeat --in (60s or more) or --at HH:MM.") var repeats = false
    @Option(help: "Recurring time: 14:00, daily@14:00 or tue@14:00.") var every: String?

    private var waits: Bool { wait || timeout != nil }

    func validate() throws {
        if text != nil && title != nil { throw ValidationError("give the title once") }
        if let relevance, !(0...1).contains(relevance) { throw ValidationError("--relevance must be between 0 and 1") }
        if let timeout, timeout <= 0 { throw ValidationError("--timeout must be positive") }
        if [delay, at, every].compactMap({ $0 }).count > 1 { throw ValidationError("use only one of --in, --at, --every") }
        if waits && (delay ?? at ?? every) != nil { throw ValidationError("--wait cannot be used with a schedule") }
        if repeats && delay == nil && at == nil { throw ValidationError("--repeat needs --in or --at") }
        if let userInfo, (try? JSONSerialization.jsonObject(with: Data(userInfo.utf8))) == nil {
            throw ValidationError("--user-info must be JSON")
        }
        if let clip, parseClip(clip) == nil { throw ValidationError("--clip must be x,y,w,h from 0 to 1") }
        if let sender { try validateSenderName(sender) }
        _ = try makeTrigger()
    }

    private func parseClip(_ text: String) -> CGRect? {
        let parts = text.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...1).contains($0) }) else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    func makeTrigger() throws -> UNNotificationTrigger? {
        if let delay {
            guard let seconds = parseDuration(delay) else { throw ValidationError("bad --in value: \(delay)") }
            if repeats && seconds < 60 { throw ValidationError("--repeat needs an interval of at least 60s") }
            return UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: repeats)
        }
        if let at {
            guard let date = parseAt(at) else { throw ValidationError("bad --at value, or it is in the past: \(at)") }
            if repeats && date.year != nil { throw ValidationError("--repeat needs --at HH:MM") }
            return UNCalendarNotificationTrigger(dateMatching: date, repeats: repeats)
        }
        if let every {
            guard let date = parseEvery(every) else { throw ValidationError("bad --every value: \(every)") }
            return UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        }
        return nil
    }

    func run() async throws {
        let content = try makeContent()
        let identifier = id ?? UUID().uuidString
        if dryRun { return printDryRun(content, identifier) }

        if let sender {
            let bundle = try Senders.ensureCurrent(sender)
            if Bundle.main.bundleIdentifier != Senders.bundleID(sender) { try Senders.handOff(to: bundle) }
        }

        let center = try notificationCenter()
        try await ensureAuthorized(center)
        await warnIfLevelUnavailable(center)
        content.attachments = try makeAttachments()
        if icon.symbol != nil || icon.image != nil {
            content.attachments.insert(try attachment(icon.symbol != nil ? icon.cachedThumbnail().path : icon.image!), at: 0)
        }
        if let category = makeCategory() {
            content.categoryIdentifier = category.identifier
            var categories = await center.notificationCategories()
            categories.update(with: category)
            center.setNotificationCategories(categories)
            _ = await center.notificationCategories()
        }

        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: makeTrigger()))
        if json && !waits { printJSON(["id": identifier]) }
        if waits {
            await MainActor.run { watch(center, identifier) }
            try await Task.sleep(nanoseconds: .max)
        }
    }

    private func makeContent() throws -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = text ?? title ?? ""
        content.subtitle = subtitle ?? ""
        content.body = try resolveBody()
        guard !(content.title + content.subtitle + content.body).isEmpty else {
            throw ValidationError("nothing to send; give a title or body")
        }
        content.sound = try resolveSound()
        content.threadIdentifier = group ?? ""
        if let level { content.interruptionLevel = level.ns }
        if let relevance { content.relevanceScore = relevance }
        if let badge { content.badge = badge as NSNumber }
        content.filterCriteria = filter
        content.userInfo = makeUserInfo()
        return content
    }

    private func resolveBody() throws -> String {
        guard body == "-" else { return body ?? "" }
        let input = FileHandle.standardInput.readDataToEndOfFile()
        return String(decoding: input, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolveSound() throws -> UNNotificationSound? {
        switch sound {
        case "none": return nil
        case "default": return .default
        default:
            let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].path
            let roots = ["\(library)/Sounds", "/Library/Sounds", "/System/Library/Sounds", Bundle.main.resourcePath ?? ""]
            let found = roots.contains { root in
                ["", ".aiff", ".wav", ".caf"].contains { FileManager.default.fileExists(atPath: "\(root)/\(sound)\($0)") }
            }
            guard found else { throw ValidationError("unknown sound: \(sound)") }
            return UNNotificationSound(named: UNNotificationSoundName(sound))
        }
    }

    private func makeUserInfo() -> [String: String] {
        var info = [UserInfoKey.directory: FileManager.default.currentDirectoryPath]
        if let open {
            let isURL = URL(string: open)?.scheme != nil
            info[UserInfoKey.open] = isURL ? open : URL(fileURLWithPath: open).absoluteString
        }
        info[UserInfoKey.exec] = exec
        info[UserInfoKey.activate] = activate
        info[UserInfoKey.data] = userInfo
        return info
    }

    private func makeAttachments() throws -> [UNNotificationAttachment] {
        try attach.map(attachment)
    }

    private func attachment(_ path: String) throws -> UNNotificationAttachment {
        var options: [String: Any] = [:]
        if noThumb { options[UNNotificationAttachmentOptionsThumbnailHiddenKey] = true }
        if let thumbTime { options[UNNotificationAttachmentOptionsThumbnailTimeKey] = thumbTime }
        if let clip, let rect = parseClip(clip) {
            options[UNNotificationAttachmentOptionsThumbnailClippingRectKey] = rect.dictionaryRepresentation
        }
        guard FileManager.default.fileExists(atPath: path) else { throw ValidationError("no such file: \(path)") }
        // The system moves attachments into its store, so hand it a copy.
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension((path as NSString).pathExtension)
        try FileManager.default.copyItem(atPath: path, toPath: copy.path)
        return try UNNotificationAttachment(identifier: UUID().uuidString, url: copy, options: options)
    }

    private func makeActions() -> [UNNotificationAction] {
        let optionNames: [String: UNNotificationActionOptions] = [
            "destructive": .destructive, "auth": .authenticationRequired, "foreground": .foreground,
        ]
        let options = Dictionary(actionOpt.compactMap(parsePair).map { pair in
            (pair.id, pair.value.split(separator: ",").reduce(into: UNNotificationActionOptions()) {
                $0.formUnion(optionNames[String($1)] ?? [])
            })
        }, uniquingKeysWith: { $1 })
        let icons = Dictionary(actionIcon.compactMap(parsePair).map { ($0.id, $0.value) }, uniquingKeysWith: { $1 })
        var actions = action.map {
            UNNotificationAction(
                identifier: $0.id, title: $0.title, options: options[$0.id] ?? [],
                icon: icons[$0.id].map { UNNotificationActionIcon(systemImageName: $0) }
            )
        }
        if let reply {
            actions.append(UNTextInputNotificationAction(identifier: "reply", title: "Reply", options: [], textInputButtonTitle: "Send", textInputPlaceholder: reply))
        }
        return actions
    }

    private func makeCategory() -> UNNotificationCategory? {
        let actions = makeActions()
        let customized = hiddenText != nil || summary != nil || showHiddenTitle
        guard !actions.isEmpty || waits || reportDismiss || customized else { return nil }
        var options: UNNotificationCategoryOptions = []
        if waits || reportDismiss { options.insert(.customDismissAction) }
        if showHiddenTitle { options.insert(.hiddenPreviewsShowTitle) }
        // A category with the same spec reuses its ID, so repeat sends don't pile up categories.
        let parts = action.map { "\($0.id)=\($0.title)" } + actionOpt + actionIcon
            + [reply ?? "", "\(options.rawValue)", hiddenText ?? "", summary ?? ""]
        return UNNotificationCategory(
            identifier: "manotify." + parts.joined(separator: "|"), actions: actions, intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: hiddenText ?? "", categorySummaryFormat: summary, options: options
        )
    }

    private func warnIfLevelUnavailable(_ center: UNUserNotificationCenter) async {
        let settings = await center.notificationSettings()
        if level == .timeSensitive && settings.timeSensitiveSetting != .enabled {
            warn("time-sensitive is unavailable for this app, so it won't break through Focus")
        }
        if level == .critical && settings.criticalAlertSetting != .enabled {
            warn("critical alerts need an Apple-approved entitlement, so this won't bypass Do Not Disturb")
        }
    }

    private func watch(_ center: UNUserNotificationCenter, _ identifier: String) {
        NotificationEvents.shared.onResponse = { response in
            guard response.notification.request.identifier == identifier else { return }
            let action = response.actionIdentifier
            let dismissed = action == UNNotificationDismissActionIdentifier
            let name = dismissed ? "@DISMISS" : action == UNNotificationDefaultActionIdentifier ? "@CLICK" : action
            let info = response.notification.request.content.userInfo
            finish(name, reply: (response as? UNTextInputNotificationResponse)?.userText,
                   data: info[UserInfoKey.data] as? String, identifier: identifier, code: dismissed ? 2 : 0)
        }
        if let timeout {
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                center.removeDeliveredNotifications(withIdentifiers: [identifier])
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
                finish("@TIMEOUT", reply: nil, data: userInfo, identifier: identifier, code: 2)
            }
        }
    }

    private func finish(_ action: String, reply: String?, data: String?, identifier: String, code: Int32) -> Never {
        if json {
            var output = ["id": identifier, "action": action]
            output["reply"] = reply
            output["userInfo"] = data
            printJSON(output)
        } else {
            print(reply ?? action)
        }
        Darwin.exit(code)
    }

    private func printDryRun(_ content: UNNotificationContent, _ identifier: String) {
        var output: [String: Any] = [
            "id": identifier, "title": content.title, "subtitle": content.subtitle, "body": content.body,
            "group": content.threadIdentifier, "level": level?.rawValue ?? "active", "sound": sound,
            "actions": action.map(\.id), "attachments": [icon.symbol ?? icon.image].compactMap { $0 } + attach,
        ]
        output["sender"] = sender
        if let trigger = try? makeTrigger() { output["trigger"] = trigger.description }
        printJSON(output)
    }
}
