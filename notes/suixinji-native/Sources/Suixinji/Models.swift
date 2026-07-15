import Foundation

struct NoteMeta: Codable, Equatable {
    var id: String
    var title: String
    var icon: String
    var category: String   // category id, "" = 未归类
    var mtime: Int         // unix seconds
}

struct Category: Codable, Equatable, Hashable {
    var id: String
    var name: String
}

/// Sortable, unique note id: YYYYMMDD-HHMMSS-xxxx (matches the legacy format).
func newNoteId() -> String {
    let d = Date()
    var t = time_t()
    let tt = time(&t)
    _ = tt
    let cal = Calendar(identifier: .gregorian)
    let comp = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
    let p = { (n: Int, l: Int) in String(format: "%0\(l)d", n) }
    let stamp = "\(p(comp.year!, 4))\(p(comp.month!, 2))\(p(comp.day!, 2))" +
                "-\(p(comp.hour!, 2))\(p(comp.minute!, 2))\(p(comp.second!, 2))"
    let rand = String(format: "%04x", Int.random(in: 0..<0x10000))
    return "\(stamp)-\(rand)"
}

func formatTime(_ mtime: Int) -> String {
    let d = Date(timeIntervalSince1970: TimeInterval(mtime))
    let cal = Calendar.current
    let p = { (n: Int) in String(format: "%02d", n) }
    if cal.isDateInToday(d) {
        return "今天 \(p(cal.component(.hour, from: d))):\(p(cal.component(.minute, from: d)))"
    }
    if cal.isDateInYesterday(d) {
        return "昨天 \(p(cal.component(.hour, from: d))):\(p(cal.component(.minute, from: d)))"
    }
    return "\(cal.component(.month, from: d))月\(cal.component(.day, from: d))日"
}
