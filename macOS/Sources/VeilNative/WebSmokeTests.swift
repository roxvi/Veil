import AppKit

@available(macOS 13.0, *) extension WebAppDelegate {
    func testJS(_ code: String) async -> String {
        await withCheckedContinuation { continuation in
            web.evaluateJavaScript("JSON.stringify((()=>{\(code)})())") { result, error in
                continuation.resume(returning: error.map { "ERROR: \($0)" } ?? (result as? String ?? "null"))
            }
        }
    }
    func testWait(_ condition: String) async -> Bool {
        for _ in 0..<100 {
            if await testJS("return !!(\(condition))") == "true" { return true }
            try? await Task.sleep(for: .milliseconds(30))
        }
        return false
    }
    func webSmokeTest() async {
        var failures = 0
        func check(_ yes: Bool, _ label: String) { print("\(yes ? "PASS" : "FAIL") WebKit \(label)"); if !yes { failures += 1 } }
        let ready = await testWait("window.__veilTest?.entries().some(e=>e.id&&e.id!=='demo')")
        check(ready, "renderer creates native PTY through bridge")
        guard ready, let original = sessions.values.first else {
            print(await testJS("return {body:document.body.innerText,bridge:!!window.veil,test:!!window.__veilTest}")); exit(1)
        }
        let pid = original.process.shellPid
        _ = await testJS("window.retained=window.__veilTest.entries()[0];return true")
        original.send("printf 'VEIL_WEB_%s\\n' READY\r")
        check(await testWait("document.body.textContent.includes('VEIL_WEB_READY')"), "native shell bytes reach xterm")
        _ = await testJS("document.querySelector('.terminal-pane').dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,clientX:160,clientY:160}));return true")
        _ = await testWait("document.querySelector('.split-menu')")
        _ = await testJS("Array.from(document.querySelectorAll('.split-menu button')).find(b=>b.textContent==='Split right').click();return true")
        check(await testWait("window.__veilTest.entries().filter(e=>e.id).length===2"), "right split creates second live PTY")
        check(original.process.shellPid == pid, "split preserves original process")
        check(await testJS("return window.retained===window.__veilTest.entries()[0]&&window.retained.terminal.element.isConnected") == "true", "split preserves xterm and scrollback")
        let second = sessions.values.first { $0 !== original }!
        _ = await testJS("document.querySelectorAll('.pane-leaf')[0].dispatchEvent(new MouseEvent('mousedown',{bubbles:true}));return true")
        check(await testWait("document.activeElement===window.retained.terminal.textarea"), "click switches split input focus")
        addTab(nil)
        check(await testWait("window.__veilTest.entries().filter(e=>e.id).length===3"), "Command-T adds a tab")
        _ = await testJS("document.querySelector('.tab').click();return true")
        check(await testWait("document.activeElement===window.retained.terminal.textarea"), "tab return remembers focused split")
        original.send("printf 'VEIL_UNICODE_%s\\n' '猫🙂é'; printf 'VEIL_EDIT_%s\\n' reaX\u{7f}dy\r")
        check(await testWait("document.body.textContent.includes('VEIL_UNICODE_猫🙂é')&&document.body.textContent.includes('VEIL_EDIT_ready')"), "UTF-8 and backspace survive transport")
        window.setContentSize(NSSize(width: 860, height: 540))
        try? await Task.sleep(for: .milliseconds(250))
        check(await testJS("return Array.from(document.querySelectorAll('.tab-workspace.is-active .terminal-pane')).every(p=>{const r=p.querySelector('.xterm'),s=p.querySelector('.xterm-screen'),c=getComputedStyle(r);return s.getBoundingClientRect().height<=p.clientHeight-parseFloat(c.paddingTop)-parseFloat(c.paddingBottom)+1})") == "true", "resized split last row stays visible")
        original.send("printf '\\033[?1049hVEIL_ALT_%s' SCREEN\r")
        check(await testWait("document.body.textContent.includes('VEIL_ALT_SCREEN')"), "alternate screen renders")
        original.send("printf '\\033[?1049l'\r")
        check(await testWait("document.body.textContent.includes('VEIL_WEB_READY')"), "alternate screen restores scrollback")
        let gif = Resources.repository.appendingPathComponent("tests/fixtures/animated.gif")
        second.send("veil image '\(gif.path)'\r")
        try? await Task.sleep(for: .milliseconds(300))
        check(tcgetpgrp(second.process.childfd) != second.process.shellPid, "GIF runs in independent split")
        var timings: [Double] = []
        for index in 0..<12 {
            let start = ContinuousClock.now
            original.send("printf 'WEB_ECHO_\(index)_%s\\n' OK\r")
            for _ in 0..<200 {
                if await testJS("return document.body.textContent.includes('WEB_ECHO_\(index)_OK')") == "true" { break }
                try? await Task.sleep(for: .milliseconds(1))
            }
            let elapsed = start.duration(to: .now).components
            timings.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
        }
        print("WebKit DOM echo max during GIF: \(timings.max() ?? 0) ms")
        check((timings.max() ?? 1000) < 100, "echo under GIF load <100ms")
        second.send("\u{03}")
        for _ in 0..<100 {
            if second.idle { break }
            try? await Task.sleep(for: .milliseconds(30))
        }
        // Supply the native drag metadata, then exercise the real DOM drop
        // handler/bridge. Physical Finder dragging remains a separate UI check.
        web.dropFiles = [gif]; web.dropTime = Date()
        _ = await testJS("const e=window.__veilTest.entries().find(e=>e.id==='\(second.id)');window.mediaRetained=e;const d=new DataTransfer();d.items.add(new File(['fixture'],'animated.gif',{type:'image/gif'}));e.terminal.element.closest('.veil-media-host').dispatchEvent(new DragEvent('drop',{bubbles:true,dataTransfer:d}));return true")
        check(await testWait("window.mediaRetained.hasImage===true"), "image drop invokes CLI at empty prompt")
        check(await testWait("window.mediaRetained.terminal.element.closest('.veil-media-host')?.querySelector('.veil-image-move')"), "image move control committed")
        check(await testJS("window.mediaRetained.terminal.element.closest('.veil-media-host').querySelector('.veil-image-move').click();return true") == "true", "image move action succeeds")
        check(await testWait("window.mediaRetained.terminal.element.closest('.veil-floating-media')"), "ASCII pane floats with original xterm")
        check(await testJS("document.querySelector('.veil-floating-media button').click();return true") == "true", "image return action succeeds")
        check(await testWait("window.mediaRetained.terminal.element.closest('.veil-media-host')") && second.process.running,
              "ASCII pane returns without replacing PTY")
        second.send("\u{03}")
        original.send("veil mac text\r")
        check(await testWait("window.retained.terminal.options.fontSize===11"), "live CLI font configuration")
        original.send("veil default text\r")
        check(await testWait("window.retained.terminal.options.fontSize===14"), "default typography restored")
        original.send("printf '\\033]777;veil-pip\\007'\r")
        check(await testWait("document.querySelector('.veil-pip-pane')"), "PiP command parks invoking split")
        _ = await testJS("Array.from(document.querySelectorAll('.veil-pip-pane button')).find(b=>b.textContent==='Return to terminal').click();return true")
        check(await testWait("window.retained.terminal.element.closest('.veil-media-host')") && original.process.shellPid == pid, "PiP restore keeps original shell")
        original.send("brew --version; codex --version; printf 'WEB_TOOLS_%s\\n' DONE\r")
        check(await testWait("document.body.textContent.includes('WEB_TOOLS_DONE')"), "brew and codex run from native host")
        do {
            let file = configURL.deletingLastPathComponent().appendingPathComponent("open ' literal.txt")
            try "VEIL_VIM_FILE_CONTENT\n".write(to: file, atomically: true, encoding: .utf8)
            let previous = Set(sessions.keys)
            application(NSApp, open: [file])
            check(await testWait("document.body.textContent.includes('VEIL_VIM_FILE_CONTENT')"), "file-open launches Vim with literal filename")
            if let opened = sessions.values.first(where: { !previous.contains($0.id) }) {
                let openPID = opened.process.shellPid
                opened.send("\u{1b}:q!\r")
                for _ in 0..<100 {
                    if tcgetpgrp(opened.process.childfd) == openPID { break }
                    try? await Task.sleep(for: .milliseconds(30))
                }
                check(tcgetpgrp(opened.process.childfd) == openPID, "Vim releases foreground PTY to shell")
                opened.send("printf 'WEB_VIM_RETURN_%s\\n' OK\r")
                check(await testWait("document.body.textContent.includes('WEB_VIM_RETURN_OK')") && opened.process.shellPid == openPID,
                    "leaving Vim returns to original login shell")
                if failures > 0 {
                    print(await testJS("return document.body.innerText.slice(-2000)"))
                    print(await testJS("return window.__veilTest.entries().map(e=>({id:e.id,rows:Array.from({length:e.terminal.buffer.active.length},(_,i)=>e.terminal.buffer.active.getLine(i).translateToString()).slice(-10)}))"))
                }
            } else { check(false, "file-open creates new tab") }
            try FileManager.default.removeItem(at: file)
        } catch { check(false, "file-open test: \(error)") }
        check(scriptErrors.isEmpty, "no unhandled renderer exceptions")
        sessions.values.forEach { $0.stop() }; stopHelper(); store?.stop()
        print("WebKit smoke: \(failures) failures"); exit(failures == 0 ? 0 : 1)
    }
}
