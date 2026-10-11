import AppKit
import SwiftTerm
import VeilCore

@available(macOS 13.0, *) extension AppDelegate {
    func waitFor(_ text: String, in pane: Pane) async -> Bool {
        for _ in 0..<100 {
            if pane.text.contains(text) { return true }
            try? await Task.sleep(for: .milliseconds(30))
        }
        return false
    }
    func smokeTest(_ original: Pane) async {
        var failures: [String] = []
        func check(_ condition: Bool, _ name: String) { print("\(condition ? "PASS" : "FAIL") \(name)"); if !condition { failures.append(name) } }
        let pid = original.terminal.process.shellPid
        check(!tabBar.isHidden && tabBar.arrangedSubviews.count == 2, "single tab and new-tab button stay visible")
        original.terminal.send(txt: "printf 'VEIL_NATIVE_%s\\n' READY\r")
        check(await waitFor("VEIL_NATIVE_READY", in: original), "real PTY output")
        original.terminal.send(txt: "echo unfinished")
        check(!original.terminal.input.isEmpty && !original.isIdle, "public input path marks nonempty prompt before sending")
        original.terminal.send(txt: "\u{03}")
        check(original.terminal.input.isEmpty, "Ctrl-C clears conservative prompt tracker")
        content.layoutSubtreeIfNeeded()
        let initial = original.terminal.terminalStateSnapshot().dimensions
        let added = split(original, vertical: true, before: false, test: true)
        content.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(100))
        let splitSize = original.terminal.terminalStateSnapshot().dimensions
        check(original.terminal.process.shellPid == pid && original.text.contains("VEIL_NATIVE_READY"), "split retains PID and buffer")
        check(splitSize.cols < initial.cols && splitSize.rows == initial.rows && splitSize.rows > 24, "split geometry uses full height")
        added.terminal.send(txt: "printf 'VEIL_SECOND_%s\\n' READY\r")
        check(await waitFor("VEIL_SECOND_READY", in: added), "independent second PTY")
        original.terminal.send(txt: "printf 'VEIL_EDIT_%s\\n' reaX\u{7f}dy\r")
        check(await waitFor("VEIL_EDIT_ready", in: original), "backspace edits only intended character")
        let tab = active!
        let clickPoint = original.terminal.convert(NSPoint(x: 20, y: 20), to: nil)
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: clickPoint, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        original.terminal.mouseDown(with: click)
        check(window.firstResponder === original.terminal && tab.selected === original, "click transfers split keyboard focus")
        original.terminal.mouseUp(with: click)
        let third = newTab()
        activate(tab)
        check(window.firstResponder === original.terminal, "tab return restores clicked split focus")
        check(original.terminal.process.shellPid == pid && original.text.contains("VEIL_NATIVE_READY"), "tab round-trip retains shell and scrollback")
        remove(third)
        apply(Configuration("font-size = 11\npadding-y = 8\nglass-mode = clear\nglass-opacity = 0\n"))
        check(original.terminal.font.pointSize == 11 && original.terminal.backgroundOpacity == 0, "live font and transparent pane")
        check(!window.hasShadow, "fully clear has no outline shadow")
        original.park(); original.restore()
        check(original.terminal.process.shellPid == pid && original.text.contains("VEIL_NATIVE_READY"), "PiP parking retains terminal")
        media.float(original, show: false); media.restore()
        check(original.terminal.superview === original && original.terminal.process.shellPid == pid, "floating media returns same terminal")
        original.terminal.send(txt: "printf '\\033[?1049hVEIL_ALT_%s' READY\r")
        check(await waitFor("VEIL_ALT_READY", in: original), "alternate screen")
        let alternatePID = original.terminal.process.shellPid
        _ = split(original, vertical: false, before: true, test: true)
        check(original.terminal.process.shellPid == alternatePID && original.text.contains("VEIL_ALT_READY"), "nested split preserves alternate screen")
        original.terminal.send(txt: "printf '\\033[?1049l'\r")
        check(await waitFor("VEIL_NATIVE_READY", in: original), "alternate screen restores main buffer")
        let gif = Resources.repository.appendingPathComponent("tests/fixtures/animated.gif")
        added.terminal.send(txt: "veil image \(OpenTarget.quote(gif.path))\r")
        try? await Task.sleep(for: .milliseconds(350))
        let gifPID = tcgetpgrp(added.terminal.process.childfd)
        check(gifPID > 0 && gifPID != added.terminal.process.shellPid && !added.text.contains("VEIL_SECOND_READY"), "GIF occupies only its alternate screen")
        media.float(added, show: false); media.restore()
        check(tcgetpgrp(added.terminal.process.childfd) == gifPID, "floating GIF retains running image process")
        var timings: [Double] = []
        for index in 0..<12 {
            let start = ContinuousClock.now
            original.terminal.send(txt: "printf 'VEIL_ECHO_\(index)_%s\\n' OK\r")
            for _ in 0..<500 {
                if original.text.contains("VEIL_ECHO_\(index)_OK") { break }
                try? await Task.sleep(for: .milliseconds(1))
            }
            let elapsed = start.duration(to: .now).components
            timings.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
        }
        let p95 = timings.sorted()[11]
        check(p95 < 100, "PTY echo p95 while GIF runs: \(String(format: "%.1f", p95))ms (<100ms)")
        added.terminal.send(txt: "\u{03}")
        check(await waitFor("VEIL_SECOND_READY", in: added), "GIF Ctrl-C restores scrollback")
        original.terminal.send(txt: "command -v brew; command -v codex; printf 'VEIL_TOOLS_%s\\n' DONE\r")
        check(await waitFor("VEIL_TOOLS_DONE", in: original), "normal command lookup completes")
        check(original.text.contains("/brew") && original.text.contains("/codex"), "Finder-style PATH resolves installed brew and codex")
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("veil-native-watch-\(UUID())")
        do {
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            let url = temporary.appendingPathComponent("veil/config")
            let watcher = ConfigurationStore(url: url)
            var observed = 0.0
            watcher.changed = { observed = $0.number("font-size", default: 0) }
            watcher.start()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("font-size = 12\n".utf8).write(to: url, options: .atomic)
            for _ in 0..<100 { if observed == 12 { break }; try? await Task.sleep(for: .milliseconds(10)) }
            check(observed == 12, "config watcher follows first-time directory creation")
            try Data("font-size = 17\n".utf8).write(to: url, options: .atomic)
            for _ in 0..<100 { if observed == 17 { break }; try? await Task.sleep(for: .milliseconds(10)) }
            check(observed == 17, "config watcher follows atomic replacement")
            watcher.stop(); try FileManager.default.removeItem(at: temporary)
        } catch { check(false, "config watcher: \(error)") }
        check(original.terminal.isUsingMetalRenderer, "Metal renderer")
        panes.forEach { $0.exited = nil; $0.terminal.terminate() }
        print("Native smoke: \(failures.count) failures")
        exit(failures.isEmpty ? 0 : 1)
    }
}
