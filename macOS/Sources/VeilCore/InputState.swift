import Foundation

public struct InputState: Sendable {
    public private(set) var text = ""
    public private(set) var unknown = false
    public init() {}
    public var isEmpty: Bool { text.isEmpty && !unknown }
    @discardableResult public mutating func consume(_ input: String) -> [String] {
        var submitted: [String] = []
        for character in input {
            switch character {
            case "\r", "\n", "\r\n":
                if !unknown { submitted.append(text) }; text = ""; unknown = false
            case "\u{03}": text = ""; unknown = false
            case "\u{7f}", "\u{08}": if !text.isEmpty { text.removeLast() }
            case "\u{15}": if !unknown { text = "" }
            default:
                if character.unicodeScalars.contains(where: { $0.value < 32 }) { unknown = true }
                else if text.utf8.count < 16384 { text.append(character) }
                else { unknown = true }
            }
        }
        return submitted
    }
}
