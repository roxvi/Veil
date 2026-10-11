import Foundation
import CoreGraphics
import Testing
@testable import VeilCore

@Test func inputNeverTreatsEditingAsAnEmptyPrompt() {
    var input = InputState()
    input.consume("echo unsafe")
    #expect(!input.isEmpty)
    input.consume("\u{7f}")
    #expect(input.text == "echo unsaf")
    input.consume("\u{15}")
    #expect(input.isEmpty)
    input.consume("\u{1b}[A")
    #expect(!input.isEmpty)
    input.consume("\u{15}")
    #expect(!input.isEmpty)
    input.consume("\u{03}")
    #expect(input.isEmpty)
    #expect(input.consume("veil image '/tmp/pic.png'\r") == ["veil image '/tmp/pic.png'"])
    #expect(input.isEmpty)
}

@Test func pathsAndShellQuotingAreLiteral() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("veil-open-\(UUID())")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("quote' and $HOME.txt")
    try Data("example".utf8).write(to: file)
    #expect(OpenTarget(raw: file.path)?.file == file.path)
    #expect(OpenTarget(raw: file.absoluteString)?.directory == root.path)
    #expect(OpenTarget(raw: root.path)?.file == nil)
    var url = URLComponents(); url.scheme = "veil"; url.host = "open"; url.queryItems = [.init(name: "path", value: file.path)]
    #expect(OpenTarget(raw: url.string!)?.file == file.path)
    #expect(OpenTarget.quote("a'b") == "'a'\"'\"'b'")
}

@Test func boundPiPHasPaddingAndPreservesAspect() {
    let target = CGRect(x: 100, y: 200, width: 500, height: 300)
    let fit = PiPGeometry.fit(target, aspect: 16 / 9)
    #expect(abs(fit.width / fit.height - 16 / 9) < 0.001)
    #expect(fit.minX >= target.minX + 6 && fit.maxX <= target.maxX - 6)
    #expect(fit.minY >= target.minY + 6 && fit.maxY <= target.maxY - 6)
    #expect(PiPGeometry.overlap(target, target) == 1)
    #expect(PiPGeometry.overlap(target, target.offsetBy(dx: 1000, dy: 1000)) == 0)
    #expect(!PiPGeometry.valid(CGRect(x: Double.nan, y: 0, width: 10, height: 10)))
}
