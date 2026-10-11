import Foundation

/// Read-only view of the existing CLI-owned config. Unknown keys survive because
/// the native application never serializes or rewrites this file.
public struct Configuration: Sendable {
    public let values: [String: String]

    public init(_ source: String = "") {
        var values: [String: String] = [:]
        for line in source.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<separator].trimmingCharacters(in: .whitespaces)
            var value = trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first,
               (first == "\"" || first == "'"), value.last == first {
                value.removeFirst(); value.removeLast()
            }
            if !key.isEmpty { values[key] = value }
        }
        self.values = values
    }

    public func string(_ key: String, default fallback: String) -> String { values[key] ?? fallback }
    public func number(_ key: String, default fallback: Double) -> Double {
        guard let raw = values[key], let number = Double(raw), number.isFinite else { return fallback }
        return number
    }
    public func bool(_ key: String, default fallback: Bool) -> Bool {
        switch values[key] { case "true": return true; case "false": return false; default: return fallback }
    }
    public static func url(environment: [String: String], home: String) -> URL {
        let base = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? "\(home)/.config"
        return URL(fileURLWithPath: base).appendingPathComponent("veil/config")
    }
}
