import Foundation

func parseDuration(_ text: String) -> TimeInterval? {
    let units: [Character: TimeInterval] = ["s": 1, "m": 60, "h": 3600, "d": 86400]
    let scale = text.last.flatMap { units[$0] }
    let number = scale == nil ? Double(text) : Double(text.dropLast())
    guard let number, number > 0, number.isFinite else { return nil }
    return number * (scale ?? 1)
}

func parseClock(_ text: String) -> DateComponents? {
    let parts = text.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2, parts[1].count == 2,
          let hour = Int(parts[0]), let minute = Int(parts[1]),
          (0...23).contains(hour), (0...59).contains(minute) else { return nil }
    return DateComponents(hour: hour, minute: minute)
}

func parseAt(_ text: String, now: Date = Date()) -> DateComponents? {
    if let clock = parseClock(text) { return clock }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.isLenient = false
    for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm"] {
        formatter.dateFormat = format
        if let date = formatter.date(from: text), date > now {
            return Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        }
    }
    return nil
}

func parseEvery(_ text: String) -> DateComponents? {
    let parts = text.lowercased().split(separator: "@", omittingEmptySubsequences: false).map(String.init)
    guard parts.count <= 2, var components = parseClock(parts[parts.count - 1]) else { return nil }
    if parts.count == 2 && parts[0] != "daily" {
        guard let index = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"].firstIndex(of: parts[0]) else { return nil }
        components.weekday = index + 1
    }
    return components
}
