import AppKit
import SwiftTerm
import VeilCore

private final class TrackedInput: @unchecked Sendable {
    private let lock = NSLock()
    private var state = InputState()
    var value: InputState { lock.withLock { state } }
    func consume(_ bytes: [UInt8]) -> [String] { lock.withLock { state.consume(String(decoding: bytes, as: UTF8.self)) } }
}

@MainActor final class VeilTerminalView: LocalProcessTerminalView {
    private nonisolated let tracked = TrackedInput()
    var input: InputState { tracked.value }
    var submitted: ((String) -> Void)?
    var dropped: ((URL) -> Bool)?
    var focused: (() -> Void)?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        focused?()
        super.mouseDown(with: event)
    }
    func trackUserInput() {
        let deliver: @MainActor @Sendable ([String]) -> Void = { [weak self] commands in
            for command in commands { self?.submitted?(command) }
        }
        setVeilInputObserver { [tracked, deliver] bytes in
            let commands = tracked.consume(bytes)
            if !commands.isEmpty { Task { @MainActor in deliver(commands) } }
        }
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : [] }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], urls.count == 1 else { return false }
        return dropped?(urls[0]) ?? false
    }
}

@MainActor final class Pane: NSView, LocalProcessTerminalViewDelegate {
    let id = UUID()
    let terminal: VeilTerminalView
    var config: Configuration
    var directory: String
    var splitAction: ((Bool, Bool) -> Void)?
    var pipAction: ((Bool) -> Void)?
    var moveAction: (() -> Void)?
    var exited: (() -> Void)?
    var titleChanged: ((String) -> Void)?
    var started = false
    var parked = false
    var floating = false
    var observation: TerminalOscObservation?
    private var lastDrop = Date.distantPast
    private let moveButton = NSButton(title: "Move image / GIF", target: nil, action: nil)
    private let restoreButton = NSButton(title: "Restore terminal", target: nil, action: nil)
    var restoreAction: (() -> Void)?
    var text: String { String(decoding: terminal.getBufferAsData(), as: UTF8.self) }
    var isIdle: Bool {
        let fd = terminal.process.childfd
        return !floating && !parked && terminal.input.isEmpty && fd >= 0 && tcgetpgrp(fd) == terminal.process.shellPid
    }
    init(config: Configuration, directory: String) {
        self.config = config; self.directory = directory
        terminal = VeilTerminalView(frame: NSRect(x: 0, y: 0, width: 960, height: 600), font: veilFont(config), options: TerminalOptions(scrollback: 10000))
        super.init(frame: NSRect(x: 0, y: 0, width: 1000, height: 650))
        autoresizingMask = [.width, .height]; addSubview(terminal)
        terminal.processDelegate = self; terminal.optionAsMetaKey = true
        terminal.trackUserInput()
        terminal.registerForDraggedTypes([.fileURL])
        terminal.dropped = { [weak self] url in self?.drop(url) ?? false }
        terminal.submitted = { [weak self] command in
            if command.trimmingCharacters(in: .whitespaces).hasPrefix("veil image ") { self?.moveButton.isHidden = false }
        }
        do { try terminal.setUseMetal(true) } catch { NSLog("Veil Metal: %@", error.localizedDescription) }
        let menu = NSMenu()
        for (title, tag) in [("Split Above", 0), ("Split Left", 1), ("Split Right", 2), ("Split Below", 3)] {
            let item = NSMenuItem(title: title, action: #selector(splitFromMenu(_:)), keyEquivalent: "")
            item.target = self; item.tag = tag; menu.addItem(item)
        }
        terminal.menu = menu
        moveButton.target = self; moveButton.action = #selector(moveImage); moveButton.isBordered = false; moveButton.font = .systemFont(ofSize: 10)
        moveButton.isHidden = true; addSubview(moveButton)
        restoreButton.target = self; restoreButton.action = #selector(restoreClicked); restoreButton.isHidden = true; addSubview(restoreButton)
        observation = terminal.observeOscEvents { [weak self] event in
            guard event.code == 777 else { return }
            let payload = String(decoding: event.payload, as: UTF8.self)
            guard payload == "veil-pip" || payload == "veil-pip;unbound" else { return }
            Task { @MainActor [weak self] in
                // The CLI exits immediately after OSC; allow its foreground PTY
                // ownership to return to the shell without racing that exit.
                for _ in 0..<30 {
                    guard let self else { return }
                    if self.isIdle { self.pipAction?(payload.hasSuffix(";unbound")); return }
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
            }
        }
        apply(config)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func mouseDown(with event: NSEvent) {
        guard !parked, !floating else { return }
        window?.makeFirstResponder(terminal)
        terminal.focused?()
    }
    func apply(_ config: Configuration) {
        self.config = config
        terminal.nativeForegroundColor = veilColor(config.string("foreground", default: "#eef3ea"))
        terminal.nativeBackgroundColor = veilColor(config.string("background", default: "#080c0c")); terminal.backgroundOpacity = 0
        terminal.caretColor = veilColor(config.string("cursor-color", default: "#79f26f"))
        terminal.selectedTextBackgroundColor = veilColor(config.string("selection", default: "#5f745f88"))
        terminal.fontSmoothing = config.bool("text-antialias", default: true)
        terminal.lineSpacing = max(0.8, min(3, config.number("line-height", default: 1.18)))
        terminal.applyVeilAppearance(normalFont: veilFont(config), boldFont: veilFont(config, bold: true),
            useBold: config.bool("use-bold-font", default: true), boldForeground: veilColor(config.string("bold-foreground", default: "#eef3ea")),
            ansiColors: config.bool("ansi-colors", default: true), allowBlink: config.bool("allow-blinking-text", default: true),
            dynamicForeground: config.bool("dynamic-foreground", default: true), brightBold: config.bool("bright-bold", default: false))
        let names = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
        let defaults = ["#1d2422", "#f08c86", "#79f26f", "#e8cb78", "#86aee8", "#dba1e8", "#7ed3c4", "#eef3ea"]
        let palette = (0..<16).map { index -> SwiftTerm.Color in
            let fallback = index == 8 ? "#68706c" : index == 15 ? "#ffffff" : defaults[index % 8]
            let color = veilColor(config.string((index >= 8 ? "bright-" : "") + names[index % 8], default: fallback)).usingColorSpace(.sRGB)!
            return SwiftTerm.Color(red: UInt16(color.redComponent * 65535), green: UInt16(color.greenComponent * 65535), blue: UInt16(color.blueComponent * 65535))
        }
        terminal.installColors(palette)
        let blink = config.bool("cursor-blink", default: true)
        let style: CursorStyle
        switch config.string("cursor-style", default: "block") {
        case "underline": style = blink ? .blinkUnderline : .steadyUnderline
        case "bar": style = blink ? .blinkBar : .steadyBar
        default: style = blink ? .blinkBlock : .steadyBlock
        }
        terminal.setCursorStyle(style); needsLayout = true; layoutSubtreeIfNeeded()
    }
    override func layout() {
        super.layout()
        if !floating {
            let x = max(0, min(100, config.number("padding-x", default: 18))), y = max(0, min(100, config.number("padding-y", default: 16)))
            terminal.frame = NSRect(x: x, y: y, width: max(1, bounds.width - 2 * x), height: max(1, bounds.height - 2 * y))
        }
        moveButton.frame = NSRect(x: max(0, bounds.width - 126), y: max(0, bounds.height - 22), width: 120, height: 20)
        restoreButton.frame = NSRect(x: max(0, bounds.midX - 75), y: max(0, bounds.midY - 12), width: 150, height: 24)
    }
    @objc func splitFromMenu(_ sender: NSMenuItem) { splitAction?(sender.tag == 1 || sender.tag == 2, sender.tag < 2) }
    @objc func moveImage() { moveAction?() }
    @objc func restoreClicked() { restoreAction?() }
    func park() { parked = true; terminal.isHidden = true; restoreButton.isHidden = false; moveButton.isHidden = true }
    func restore() { parked = false; terminal.isHidden = false; restoreButton.isHidden = true; window?.makeFirstResponder(terminal) }
    func resizeSplit(to size: CGSize) {
        var child: NSView = self
        var resizedWidth = false, resizedHeight = false
        while let split = child.superview as? NSSplitView {
            let handled = split.isVertical ? resizedWidth : resizedHeight
            if !handled, split.arrangedSubviews.count == 2, let index = split.arrangedSubviews.firstIndex(of: child) {
                let total = split.isVertical ? split.bounds.width : split.bounds.height
                let requested = split.isVertical ? size.width : size.height
                let length = min(max(100, requested), max(100, total - 100))
                split.setPosition(index == 0 ? length : total - length - split.dividerThickness, ofDividerAt: 0)
                if split.isVertical { resizedWidth = true } else { resizedHeight = true }
            }
            child = split
        }
    }
    func drop(_ url: URL) -> Bool {
        let supported = ["png", "jpg", "jpeg", "gif", "icns", "webp", "bmp", "tif", "tiff", "heic", "heif", "avif"]
        guard isIdle, Date().timeIntervalSince(lastDrop) > 0.3, supported.contains(url.pathExtension.lowercased()),
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { NSSound.beep(); return false }
        lastDrop = Date(); terminal.send(txt: "veil image \(OpenTarget.quote(url.path))\r")
        moveButton.isHidden = false; window?.makeFirstResponder(terminal); return true
    }
    func start(test: Bool = false, file: String? = nil) {
        guard !started else { return }; started = true; layoutSubtreeIfNeeded()
        let parent = ProcessInfo.processInfo.environment
        let candidate = config.string("shell", default: parent["SHELL"] ?? "/bin/zsh")
        let shell = FileManager.default.isExecutableFile(atPath: candidate) ? candidate : "/bin/zsh"
        let environment = ShellEnvironment.make(parent: parent, home: NSHomeDirectory(), bin: Resources.bin.path, shell: shell)
        terminal.startProcess(executable: test ? "/bin/zsh" : shell, args: test ? ["-f", "-i"] : ShellEnvironment.arguments(for: shell),
            environment: environment.map { "\($0.key)=\($0.value)" }, currentDirectory: directory)
        if let file { terminal.send(txt: "vim -- \(OpenTarget.quote(file))\r") }
    }
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) { titleChanged?(title) }
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        if let directory, let url = URL(string: directory), url.isFileURL { self.directory = url.path }
    }
    func processTerminated(source: TerminalView, exitCode: Int32?) { exited?() }
    func processFailedToStart(source: TerminalView, error: LocalProcessError) {
        let alert = NSAlert(); alert.messageText = "Could not start the shell"; alert.informativeText = String(describing: error); alert.runModal()
    }
}
