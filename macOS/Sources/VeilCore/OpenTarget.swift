import Foundation

public struct OpenTarget: Equatable, Sendable {
    public let directory: String
    public let file: String?
    public init?(raw: String, editFile: Bool = true) {
        var path = raw
        if raw.hasPrefix("veil:") {
            guard let url = URLComponents(string: raw) else { return nil }
            path = url.queryItems?.first(where: { $0.name == "path" })?.value ?? url.path
        } else if raw.hasPrefix("file:") {
            guard let url = URL(string: raw), url.isFileURL else { return nil }
            path = url.path
        }
        guard !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else { return nil }
        self.directory = directory.boolValue ? url.path : url.deletingLastPathComponent().path
        self.file = !directory.boolValue && editFile ? url.path : nil
    }
    public static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
}
