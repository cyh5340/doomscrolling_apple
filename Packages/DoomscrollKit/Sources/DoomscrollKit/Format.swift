import Foundation

public func formatMinutes(_ minutes: Int) -> String {
    if minutes < 60 { return "\(minutes) min" }
    if minutes % 60 == 0 { return "\(minutes / 60)h" }
    return "\(minutes / 60)h \(minutes % 60)m"
}

// ponytail: USD only; take a currency code from the group if stakes go international.
public func formatMoney(_ cents: Int) -> String {
    cents % 100 == 0 ? "$\(cents / 100)" : String(format: "$%d.%02d", cents / 100, cents % 100)
}

/// The code from a pasted invite link ("https://host/join/abc123/?x=1") or a bare code.
public func inviteCode(_ text: String) -> String {
    var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let i = s.firstIndex(of: "?") { s = String(s[..<i]) }
    if let i = s.firstIndex(of: "#") { s = String(s[..<i]) }
    while s.hasSuffix("/") { s.removeLast() }
    if let i = s.lastIndex(of: "/") { s = String(s[s.index(after: i)...]) }
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// The invite code in an https://<host>/join/<code> link, or nil for any other URL.
public func inviteCode(from url: URL) -> String? {
    let parts = url.pathComponents.filter { $0 != "/" }
    guard parts.count >= 2, parts[0] == "join", !parts[1].isEmpty else { return nil }
    return parts[1]
}

/// Monday of the week containing `date`, as the server counts weeks (Monday to Sunday, local dates).
public func weekStart(_ date: Date, calendar: Calendar = .current) -> Date {
    var cal = calendar
    cal.firstWeekday = 2
    return cal.dateInterval(of: .weekOfYear, for: date)!.start
}
