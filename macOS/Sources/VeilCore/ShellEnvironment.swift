import Foundation

public enum ShellEnvironment {
    public static func accountShell() -> String {
        if let account = getpwuid(getuid()), let path = account.pointee.pw_shell {
            let shell = String(cString: path)
            if FileManager.default.isExecutableFile(atPath: shell) { return shell }
        }
        return "/bin/zsh"
    }
    public static func make(parent: [String: String], home: String, bin: String, shell: String) -> [String: String] {
        var result = parent
        let candidates = [bin, "\(home)/.local/bin", "\(home)/bin", "\(home)/.cargo/bin",
                          "\(home)/.bun/bin", "\(home)/.deno/bin", "\(home)/.volta/bin",
                          "\(home)/.pyenv/bin", "\(home)/.npm-global/bin", "/opt/homebrew/bin",
                          "/opt/homebrew/sbin", "/usr/local/bin", "/usr/local/sbin",
                          "/opt/local/bin", "/opt/local/sbin",
                          "/Applications/Docker.app/Contents/Resources/bin"]
            + (parent["PATH"] ?? "").components(separatedBy: ":")
            + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var seen = Set<String>()
        result["PATH"] = candidates.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
        result["HOME"] = home
        result["SHELL"] = shell
        result["TERM"] = "xterm-256color"
        result["COLORTERM"] = "truecolor"
        result["TERM_PROGRAM"] = "Veil"
        result["TERM_PROGRAM_VERSION"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        result["USER"] = parent["USER"] ?? NSUserName()
        result["LOGNAME"] = parent["LOGNAME"] ?? NSUserName()
        result["LANG"] = parent["LANG"] ?? "en_US.UTF-8"
        return result
    }

    public static func arguments(for shell: String) -> [String] {
        switch URL(fileURLWithPath: shell).lastPathComponent {
        case "fish": return ["--login", "--interactive"]
        case "zsh", "bash", "sh", "ksh": return ["-l", "-i"]
        default: return []
        }
    }
}
