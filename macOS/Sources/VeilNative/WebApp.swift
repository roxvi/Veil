import AppKit
import WebKit
import VeilCore

@MainActor final class VeilWebView: WKWebView {
    var dropFiles: [URL] = []
    var dropTime = Date.distantPast
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropFiles = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return super.draggingEntered(sender)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropTime = Date()
        return super.performDragOperation(sender)
    }
}

@MainActor final class WebAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandlerWithReply {
    var window: NSWindow!
    var web: VeilWebView!
    let glass = GlassBackground(frame: .zero)
    var store: ConfigurationStore?
    var config = Configuration()
    var sessions: [String: WebSession] = [:]
    var targets: [OpenTarget] = []
    var loaded = false
    var createdInitialTerminal = false
    let testing = CommandLine.arguments.contains("--web-smoke-test")
    var scriptErrors: [String] = []
    var helper: Process?
    var helperInput: FileHandle?
    var helperOutput: FileHandle?
    var helperToken = ""
    var helperBuffer = Data()
    var mouseMonitor: Any?
    var dragEvent: NSEvent?
    var configURL: URL { Configuration.url(environment: ProcessInfo.processInfo.environment, home: NSHomeDirectory()) }
    var client: URL {
        let bundled = Bundle.main.resourceURL!.appendingPathComponent("client")
        return FileManager.default.fileExists(atPath: bundled.appendingPathComponent("index.html").path) ? bundled : Resources.repository.appendingPathComponent(".cache/native-renderer")
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        // WebKit loads the bundled font through @font-face. Never probe the
        // developer's source directory from a Finder-launched application.
        let settings = WKWebViewConfiguration()
        if testing {
            settings.websiteDataStore = .nonPersistent()
            settings.userContentController.addUserScript(WKUserScript(source: "window.__veilTesting=true", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        settings.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "veil")
        web = VeilWebView(frame: .zero, configuration: settings)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.setValue(false, forKey: "drawsBackground")
        web.underPageBackgroundColor = .clear
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = Bundle.main.bundleIdentifier == "com.veilterminal.app" ? "Veil Terminal" : "Veil — WebKit Development"; window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false; window.delegate = self
        window.minSize = NSSize(width: 620, height: 420); window.center()
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            if event.window === self?.window { self?.dragEvent = event }
            return event
        }
        let content = NSView(); window.contentView = content
        for view in [glass, web!] { view.frame = content.bounds; view.autoresizingMask = [.width, .height]; content.addSubview(view) }
        store = ConfigurationStore(url: configURL)
        store?.changed = { [weak self] value in self?.apply(value) }; store?.start()
        installMenu()
        let args = CommandLine.arguments
        for (index, arg) in args.enumerated() {
            let raw = arg == "--working-directory" && index + 1 < args.count ? args[index + 1] : arg.hasPrefix("--working-directory=") ? String(arg.dropFirst(20)) : nil
            if let raw, let target = OpenTarget(raw: raw, editFile: false) { targets.append(target) }
        }
        web.loadFileURL(client.appendingPathComponent("index.html"), allowingReadAccessTo: client)
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func apply(_ value: Configuration) {
        config = value
        // The unchanged renderer owns the one window-wide tint. Native only
        // provides backdrop blur and shadow, never a second opacity layer.
        var effects = value.values; effects["glass-opacity"] = "0"; effects["transparent"] = "true"
        if !value.bool("transparent", default: true) { effects["glass-mode"] = "clear" }
        let source = effects.map { "\($0.key) = \($0.value)" }.joined(separator: "\n")
        glass.apply(Configuration(source), window: window)
        window.hasShadow = !(value.string("glass-mode", default: "liquid") == "clear" && value.number("glass-opacity", default: 0) <= 0)
        emit("config:changed", configObject())
    }
    func configObject() -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in config.values {
            if value == "true" || value == "false" { result[key] = value == "true" }
            else if let number = Double(value), number.isFinite { result[key] = number }
            else { result[key] = value }
        }
        if result["glass-mode"] as? String == "frost" { result["glass-mode"] = "liquid"; result["glass-blur"] = 28; result["clear-mode"] = false }
        result["configPath"] = configURL.path; return result
    }
    func emit(_ name: String, _ value: Any) {
        guard loaded, let data = try? JSONSerialization.data(withJSONObject: [name, value]), let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.__veilReceive(...\(json))") { _, error in
            if let error { NSLog("Veil delivery %@: %@", name, String(describing: error)) }
        }
    }
    func geometry() {
        guard window != nil else { return }
        let frame = window.convertToScreen(web.convert(web.bounds, to: nil))
        emit("host:geometry", ["x": frame.minX, "y": (NSScreen.screens.first?.frame.maxY ?? 0) - frame.maxY,
            "width": frame.width, "height": frame.height, "visible": window.isVisible && !NSApp.isHidden, "minimized": window.isMiniaturized])
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.isFileURL == true,
              let body = message.body as? [String: Any], let op = body["op"] as? String else { replyHandler(nil, "Untrusted request"); return }
        let value = body["value"] as? [String: Any] ?? [:]
        do { replyHandler(try handle(op, value), nil) } catch { replyHandler(nil, error.localizedDescription) }
    }
    func handle(_ op: String, _ value: [String: Any]) throws -> Any {
        let id = value["id"] as? String ?? ""
        switch op {
        case "ui:error":
            let message = value["message"] as? String ?? "Unknown script error"
            if testing { scriptErrors.append(message) }
            NSLog("Veil WebKit: %@", message); return true
        case "ui:ready": loaded = true; geometry(); return true
        case "config:get": return configObject()
        case "config:open":
            if !FileManager.default.fileExists(atPath: configURL.path) {
                try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let defaults = try Data(contentsOf: client.appendingPathComponent("default-config"))
                try defaults.write(to: configURL, options: .withoutOverwriting)
            }
            return ["ok": NSWorkspace.shared.open(configURL), "configPath": configURL.path]
        case "config:set":
            guard value["key"] as? String == "transparent", let enabled = value["value"] as? Bool else { throw bridgeError("Unsupported config key") }
            var lines = ((try? String(contentsOf: configURL, encoding: .utf8)) ?? "").components(separatedBy: .newlines)
            lines.removeAll { $0.split(separator: "=", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces) == "transparent" }
            lines.append("transparent = \(enabled)")
            try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let source = lines.joined(separator: "\n"); try source.write(to: configURL, atomically: true, encoding: .utf8)
            apply(Configuration(source)); return configObject()
        case "terminal:create":
            let target = targets.isEmpty ? nil : targets.removeFirst()
            let cwd = (value["cwd"] as? String).flatMap { OpenTarget(raw: $0, editFile: false)?.directory } ?? target?.directory ?? NSHomeDirectory()
            let candidate = config.string("shell", default: ShellEnvironment.accountShell())
            let shell = FileManager.default.isExecutableFile(atPath: candidate) ? candidate : ShellEnvironment.accountShell()
            let session = WebSession(cols: max(2, value["cols"] as? Int ?? 80), rows: max(1, value["rows"] as? Int ?? 24))
            session.output = { [weak self] name, payload in self?.emit(name, payload) }
            var env = ShellEnvironment.make(parent: ProcessInfo.processInfo.environment, home: NSHomeDirectory(), bin: Resources.bin.path, shell: shell)
            env["TERM_SESSION_ID"] = "Veil-\(session.id)"; env["PWD"] = cwd
            try session.start(shell: shell, directory: cwd, environment: env)
            sessions[session.id] = session
            if let file = target?.file { session.send("command vim -- \(OpenTarget.quote(file))\r") }
            if !createdInitialTerminal {
                createdInitialTerminal = true
                let remaining = targets.count
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    for _ in 0..<remaining { self?.addTab(nil) }
                }
            }
            return ["id": session.id, "shell": URL(fileURLWithPath: shell).lastPathComponent, "cwd": cwd]
        case "terminal:ready": sessions[id]?.ready = true; sessions[id]?.flush(); return true
        case "terminal:write": if let data = value["data"] as? String { sessions[id]?.send(data) }; return true
        case "terminal:resize": sessions[id]?.resize(cols: value["cols"] as? Int ?? 80, rows: value["rows"] as? Int ?? 24); return true
        case "terminal:close": sessions.removeValue(forKey: id)?.stop(); return true
        case "terminal:image-drop":
            guard let session = sessions[id], session.idle, Date().timeIntervalSince(session.lastDrop) > 0.3,
                  Date().timeIntervalSince(web.dropTime) < 2, web.dropFiles.count == 1, let url = web.dropFiles.first,
                  value["name"] as? String == url.lastPathComponent,
                  ["png","jpg","jpeg","gif","icns","webp","bmp","tif","tiff","heic","heif","avif"].contains(url.pathExtension.lowercased()),
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                return ["ok": false, "error": "Drop one image at an empty shell prompt."]
            }
            web.dropFiles = []; session.lastDrop = Date(); session.send("veil image \(OpenTarget.quote(url.path))\r"); return ["ok": true]
        case "window:drag":
            if let event = dragEvent, NSEvent.pressedMouseButtons & 1 != 0,
               ProcessInfo.processInfo.systemUptime - event.timestamp < 0.5 { window.performDrag(with: event) }
            dragEvent = nil; return true
        case "pip:start": startHelper(token: value["token"] as? String ?? "", prompt: value["prompt"] as? Bool ?? false); return true
        case "pip:command":
            if value["token"] as? String == helperToken, let line = value["line"] as? String { try helperInput?.write(contentsOf: Data(line.utf8)) }; return true
        case "pip:stop": if value["token"] as? String == helperToken { stopHelper() }; return true
        default: throw bridgeError("Unknown host operation: \(op)")
        }
    }
    func bridgeError(_ message: String) -> NSError { NSError(domain: "Veil", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    func startHelper(token: String, prompt: Bool) {
        stopHelper(); helperToken = token
        let child = Process(), input = Pipe(), output = Pipe()
        child.executableURL = Resources.pip; child.arguments = prompt ? ["--request-access"] : []
        child.standardInput = input; child.standardOutput = output; child.standardError = FileHandle.nullDevice
        helper = child; helperInput = input.fileHandleForWriting; helperOutput = output.fileHandleForReading
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            // One FIFO for lines and EOF: a short-lived permission helper must
            // deliver its last JSON response before the frontend sees exit.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.helperToken == token else { return }
                if data.isEmpty { self.emit("pip:exit", ["token": token]); return }
                self.helperBuffer.append(data)
                while let end = self.helperBuffer.firstIndex(of: 10) {
                    let line = String(decoding: self.helperBuffer.prefix(upTo: end), as: UTF8.self)
                    self.helperBuffer.removeSubrange(...end); self.emit("pip:line", ["token": token, "line": line])
                }
            }
        }
        do { try child.run() } catch { emit("pip:line", ["token": token, "line": "{\"type\":\"error\",\"message\":\"Could not start PiP helper\"}"]) }
    }
    func stopHelper() {
        helperToken = ""; helperOutput?.readabilityHandler = nil; helperOutput = nil
        try? helperInput?.close(); helperInput = nil
        if helper?.isRunning == true { helper?.terminate() }; helper = nil; helperBuffer.removeAll()
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.isFileURL && url.standardizedFileURL.path.hasPrefix(client.standardizedFileURL.path + "/") { decisionHandler(.allow) }
        else { if navigationAction.navigationType == .linkActivated && ["https", "http"].contains(url.scheme) { NSWorkspace.shared.open(url) }; decisionHandler(.cancel) }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        stopHelper()
        let alert = NSAlert(); alert.messageText = "Veil’s interface stopped"; alert.informativeText = "Your shells are still running. Quit only after saving any recoverable work."
        alert.beginSheetModal(for: window)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, ["https", "http", "mailto"].contains(url.scheme) { NSWorkspace.shared.open(url) }
        return nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if testing { if #available(macOS 13.0, *) { Task { await webSmokeTest() } } else { exit(2) } }
    }
    func application(_ sender: NSApplication, open urls: [URL]) {
        for url in urls { if let target = OpenTarget(raw: url.absoluteString) { targets.append(target); if loaded && createdInitialTerminal { addTab(nil) } } }
        window?.makeKeyAndOrderFront(nil)
    }
    @objc func addTab(_ sender: Any?) { web.evaluateJavaScript("window.dispatchEvent(new KeyboardEvent('keydown',{key:'t',metaKey:true,bubbles:true}))", completionHandler: nil) }
    func windowDidMove(_ notification: Notification) { geometry() }
    func windowDidResize(_ notification: Notification) { geometry() }
    func windowDidMiniaturize(_ notification: Notification) { geometry() }
    func windowDidDeminiaturize(_ notification: Notification) { geometry() }
    func applicationDidHide(_ notification: Notification) { geometry() }
    func applicationDidUnhide(_ notification: Notification) { geometry() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard sessions.values.contains(where: { $0.process.running }) else { return .terminateNow }
        let alert = NSAlert(); alert.messageText = "Quit Veil?"; alert.informativeText = "Running terminal sessions will end."
        alert.addButton(withTitle: "Quit"); alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { applicationShouldTerminate(NSApp) == .terminateNow }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        stopHelper(); store?.stop(); sessions.values.forEach { $0.stop() }
    }
    func installMenu() {
        let main = NSMenu()
        for (title, entries) in [("Veil", [("Quit Veil", #selector(NSApplication.terminate(_:)), "q")]),
            ("Shell", [("New Tab", #selector(addTab(_:)), "t")]),
            ("Edit", [("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")])] {
            let item = NSMenuItem(); let menu = NSMenu(title: title)
            for (name, action, key) in entries { menu.addItem(withTitle: name, action: action, keyEquivalent: key) }; item.submenu = menu; main.addItem(item)
        }
        NSApp.mainMenu = main
    }
}
