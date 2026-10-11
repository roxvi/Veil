import Testing
import Foundation
@testable import VeilCore

@Test func existingConfigSyntax() {
    let config = Configuration("""
    # comment
    font-family = "JetBrains Mono, SFMono-Regular, Menlo, monospace"
    font-size = 14
    glass-color = '#14171c'
    transparent = true
    unknown = "a=b"
    font-size = 11
    """)
    #expect(config.number("font-size", default: 14) == 11)
    #expect(config.string("glass-color", default: "") == "#14171c")
    #expect(config.bool("transparent", default: false))
    #expect(config.values["unknown"] == "a=b")
    #expect(Configuration("font-size = nan").number("font-size", default: 14) == 14)
}

@Test func finderEnvironmentAndLoginShell() {
    let env = ShellEnvironment.make(parent: ["PATH": "/usr/bin:/bin:/usr/bin", "KEEP": "yes"],
                                    home: "/Users/test", bin: "/app/bin", shell: "/bin/zsh")
    let paths = env["PATH"]!.split(separator: ":").map(String.init)
    #expect(paths.first == "/app/bin")
    #expect(paths.contains("/Users/test/.local/bin"))
    #expect(paths.contains("/opt/homebrew/bin"))
    #expect(paths.contains("/usr/local/bin"))
    #expect(paths.count == Set(paths).count)
    #expect(env["KEEP"] == "yes")
    #expect(env["TERM_PROGRAM"] == "Veil")
    #expect(ShellEnvironment.arguments(for: "/bin/zsh") == ["-l", "-i"])
}

@Test func configLocationUsesExistingXDGContract() {
    #expect(Configuration.url(environment: [:], home: "/Users/test").path == "/Users/test/.config/veil/config")
    #expect(Configuration.url(environment: ["XDG_CONFIG_HOME": "/tmp/test"], home: "/Users/test").path == "/tmp/test/veil/config")
}

@Test func readsActualCLIOutputWithoutRewritingIt() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("veil-native-config-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    func run(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = repository.appendingPathComponent("bin/veil")
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["XDG_CONFIG_HOME"] = directory.path
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
    try run(["deafault"])
    let url = directory.appendingPathComponent("veil/config")
    let before = try Data(contentsOf: url)
    let defaults = Configuration(String(decoding: before, as: UTF8.self))
    #expect(defaults.number("font-size", default: 0) == 14)
    #expect(defaults.number("font-weight", default: 0) == 450)
    #expect(defaults.string("glass-color", default: "") == "#14171c")
    #expect(try Data(contentsOf: url) == before)
    try run(["mac", "text"])
    let mac = Configuration(try String(contentsOf: url, encoding: .utf8))
    #expect(mac.number("font-size", default: 0) == 11)
    try run(["liquid", "70"])
    let liquid = Configuration(try String(contentsOf: url, encoding: .utf8))
    #expect(liquid.number("glass-opacity", default: -1) == 0.3)
    #expect(liquid.number("glass-blur", default: -1) == 28)
}
