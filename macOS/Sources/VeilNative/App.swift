import AppKit
import SwiftTerm
import VeilCore

@main struct VeilNativeMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate: any NSApplicationDelegate = CommandLine.arguments.contains("--smoke-test") || CommandLine.arguments.contains("--native-renderer") ? AppDelegate() : WebAppDelegate()
        app.delegate = delegate; app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class TerminalTab {
    let host = NSView()
    var panes: [Pane] = []
    var title = "Terminal"
    var selected: Pane?
    init() { host.autoresizingMask = [.width, .height] }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    let content = NSView(), workspace = NSView()
    let glass = GlassBackground(frame: .zero)
    let tabBar = NSStackView()
    var tabs: [TerminalTab] = []
    var active: TerminalTab!
    var panes: [Pane] { tabs.flatMap(\.panes) }
    var focused: Pane? { active?.panes.first { $0.terminal.window?.firstResponder === $0.terminal } ?? active?.selected ?? active?.panes.first }
    var configuration = Configuration()
    var store: ConfigurationStore?
    var pip: PiPCoordinator!
    var media: MediaController!
    var pendingTargets: [OpenTarget] = []
    let testing = CommandLine.arguments.contains("--smoke-test")

    func applicationDidFinishLaunching(_ notification: Notification) {
        Resources.registerFonts()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Veil — Native Development"; window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true; window.delegate = self; window.isReleasedWhenClosed = false
        window.center(); window.contentView = content
        for view in [glass, tabBar, workspace] { content.addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        tabBar.orientation = .horizontal; tabBar.spacing = 8
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: content.leadingAnchor), glass.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            glass.topAnchor.constraint(equalTo: content.topAnchor), glass.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            tabBar.topAnchor.constraint(equalTo: content.topAnchor, constant: 2), tabBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 84),
            tabBar.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -8), tabBar.heightAnchor.constraint(equalToConstant: 26),
            workspace.topAnchor.constraint(equalTo: content.topAnchor, constant: 30), workspace.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            workspace.leadingAnchor.constraint(equalTo: content.leadingAnchor), workspace.trailingAnchor.constraint(equalTo: content.trailingAnchor)
        ])
        pip = PiPCoordinator(helperURL: Resources.pip, window: window, targets: { [weak self] in self?.pipTargets() ?? [] })
        media = MediaController(owner: self)
        if !testing {
            let env = ProcessInfo.processInfo.environment
            let url = env["VEIL_NATIVE_CONFIG"].map { URL(fileURLWithPath: $0) } ?? Configuration.url(environment: env, home: NSHomeDirectory())
            store = ConfigurationStore(url: url)
            store?.changed = { [weak self] config in self?.apply(config) }
            store?.failed = { error in NSLog("Veil config: %@", error.localizedDescription) }
            store?.start()
        }
        installMenu()
        var arguments = CommandLine.arguments.dropFirst().makeIterator()
        while let argument = arguments.next() {
            if argument == "--working-directory", let path = arguments.next(), let target = OpenTarget(raw: path, editFile: false) { pendingTargets.append(target) }
            else if argument.hasPrefix("--working-directory="), let target = OpenTarget(raw: String(argument.dropFirst(20)), editFile: false) { pendingTargets.append(target) }
        }
        if pendingTargets.isEmpty { _ = newTab() }
        else { for target in pendingTargets { _ = newTab(target: target) }; pendingTargets.removeAll() }
        content.layoutSubtreeIfNeeded(); apply(configuration)
        if testing { if #available(macOS 13.0, *) { Task { await smokeTest(active.panes[0]) } } else { exit(2) } }
        else { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); window.makeFirstResponder(focused?.terminal) }
    }
    func apply(_ config: Configuration) {
        configuration = config; panes.forEach { $0.apply(config) }
        if window != nil { glass.apply(config, window: window) }; media?.apply(config)
    }
    @discardableResult func newTab(target: OpenTarget? = nil) -> Pane {
        let tab = TerminalTab(); tabs.append(tab)
        let pane = makePane(in: tab, directory: target?.directory ?? NSHomeDirectory())
        tab.host.addSubview(pane); activate(tab); pane.frame = tab.host.bounds
        pane.start(test: testing, file: target?.file)
        return pane
    }
    func makePane(in tab: TerminalTab, directory: String) -> Pane {
        let pane = Pane(config: configuration, directory: directory)
        pane.splitAction = { [weak self, weak pane] vertical, before in
            guard let self, let pane else { return }; _ = self.split(pane, vertical: vertical, before: before)
        }
        pane.titleChanged = { [weak self, weak tab] title in tab?.title = title; self?.updateTabs() }
        pane.terminal.focused = { [weak tab, weak pane] in tab?.selected = pane }
        pane.pipAction = { [weak self, weak pane] unbound in guard let self, let pane else { return }; self.pip.connect(targetID: pane.id, unbound: unbound) }
        pane.moveAction = { [weak self, weak pane] in guard let pane else { return }; self?.media.float(pane) }
        pane.restoreAction = { [weak self] in self?.pip.stop(); self?.media.restore() }
        pane.exited = { [weak self, weak pane] in guard let pane else { return }; self?.remove(pane) }
        tab.panes.append(pane); tab.selected = pane
        return pane
    }
    func activate(_ tab: TerminalTab) {
        if let active, let focused { active.selected = focused }
        if active !== tab { pip?.stop(); media?.restore() }
        workspace.subviews.forEach { $0.removeFromSuperview() }; active = tab
        tab.host.frame = workspace.bounds; workspace.addSubview(tab.host)
        tab.host.subviews.first?.frame = tab.host.bounds; tab.host.layoutSubtreeIfNeeded()
        updateTabs(); window.makeFirstResponder(tab.selected?.terminal ?? tab.panes.first?.terminal)
    }
    func updateTabs() {
        tabBar.arrangedSubviews.forEach { tabBar.removeArrangedSubview($0); $0.removeFromSuperview() }
        for (index, tab) in tabs.enumerated() {
            let button = NSButton(title: String(tab.title.prefix(22)), target: self, action: #selector(selectTab(_:)))
            button.tag = index; button.isBordered = false
            button.font = .systemFont(ofSize: 11, weight: tab === active ? .semibold : .regular)
            button.contentTintColor = tab === active ? .labelColor : .secondaryLabelColor; tabBar.addArrangedSubview(button)
        }
        let add = NSButton(title: "+", target: self, action: #selector(addTab(_:)))
        add.isBordered = false; add.toolTip = "New Tab (⌘T)"
        add.setAccessibilityLabel("New Tab")
        tabBar.addArrangedSubview(add)
        tabBar.isHidden = false
    }
    @objc func selectTab(_ sender: NSButton) { guard tabs.indices.contains(sender.tag) else { return }; activate(tabs[sender.tag]) }
    @objc func addTab(_ sender: Any?) { _ = newTab(target: focused.flatMap { OpenTarget(raw: $0.directory, editFile: false) }) }
    @objc func nextTab(_ sender: Any?) { guard let index = tabs.firstIndex(where: { $0 === active }), !tabs.isEmpty else { return }; activate(tabs[(index + 1) % tabs.count]) }
    @objc func closePane(_ sender: Any?) {
        guard let pane = focused else { return }
        let alert = NSAlert(); alert.messageText = "Close this terminal?"; alert.informativeText = "Running commands in this split will end."
        alert.addButton(withTitle: "Close"); alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { remove(pane) }
    }
    func remove(_ pane: Pane) {
        guard let tab = tabs.first(where: { $0.panes.contains(where: { $0 === pane }) }) else { return }
        pip.stop(); media.restore(); pane.terminal.terminate()
        let parent = pane.superview as? NSSplitView; pane.removeFromSuperview()
        tab.panes.removeAll { $0 === pane }; tab.selected = tab.panes.first
        if let parent, parent.arrangedSubviews.count == 1, let survivor = parent.arrangedSubviews.first {
            survivor.removeFromSuperview(); replace(parent, with: survivor)
        }
        if tab.panes.isEmpty {
            tabs.removeAll { $0 === tab }
            if tabs.isEmpty { window.close(); return }
            if active === tab { activate(tabs[0]) }
        }
        updateTabs(); window.makeFirstResponder(focused?.terminal)
    }
    func replace(_ old: NSView, with new: NSView) {
        guard let parent = old.superview else { return }; let frame = old.frame
        if let split = parent as? NSSplitView, let index = split.arrangedSubviews.firstIndex(of: old) {
            old.removeFromSuperview(); split.insertArrangedSubview(new, at: index); split.adjustSubviews()
        } else { old.removeFromSuperview(); new.frame = frame; new.autoresizingMask = [.width, .height]; parent.addSubview(new) }
    }
    @discardableResult func split(_ pane: Pane, vertical: Bool, before: Bool, test: Bool = false) -> Pane {
        let tab = tabs.first { $0.panes.contains { $0 === pane } }!
        let split = NSSplitView(frame: pane.frame)
        split.isVertical = vertical; split.dividerStyle = .thin; split.autoresizingMask = [.width, .height]
        replace(pane, with: split)
        let added = makePane(in: tab, directory: pane.directory)
        split.addArrangedSubview(before ? added : pane); split.addArrangedSubview(before ? pane : added)
        split.adjustSubviews(); split.setPosition((vertical ? split.bounds.width : split.bounds.height) / 2, ofDividerAt: 0)
        added.start(test: test || testing); window.makeFirstResponder(added.terminal)
        return added
    }
    func swap(_ source: Pane, _ target: Pane) {
        let placeholder = NSView(frame: source.frame)
        replace(source, with: placeholder); replace(target, with: source); replace(placeholder, with: target)
        window.makeFirstResponder(source.terminal)
    }
    func pipTargets() -> [PiPTarget] {
        panes.map { pane in
            PiPTarget(id: pane.id, rect: { [weak self, weak pane] in
                guard let self, let pane, self.active.panes.contains(where: { $0 === pane }), pane.window != nil,
                      !self.window.isMiniaturized, self.window.isVisible else { return nil }
                let frame = self.window.convertToScreen(pane.convert(pane.bounds, to: nil))
                return CGRect(x: frame.minX, y: (NSScreen.screens.first?.frame.maxY ?? 0) - frame.maxY, width: frame.width, height: frame.height)
            }, eligible: { [weak pane] in guard let pane, !pane.floating else { return false }; return pane.isIdle || pane.parked },
            park: { [weak pane] in pane?.park() }, restore: { [weak pane] in pane?.restore() },
            resize: { [weak pane] size in pane?.resizeSplit(to: size) })
        }
    }
    func application(_ sender: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let target = OpenTarget(raw: url.absoluteString) else { continue }
            if window == nil { pendingTargets.append(target) } else { _ = newTab(target: target) }
        }; window?.makeKeyAndOrderFront(nil)
    }
    func windowDidMiniaturize(_ notification: Notification) { pip.stop(); media.restore() }
    func applicationDidHide(_ notification: Notification) { pip?.stop(); media?.restore() }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if testing || !panes.contains(where: { $0.terminal.process.running }) { return .terminateNow }
        let alert = NSAlert(); alert.messageText = "Quit Veil?"; alert.informativeText = "All running terminal sessions will end."
        alert.addButton(withTitle: "Quit"); alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { applicationShouldTerminate(NSApp) == .terminateNow }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { store?.stop(); pip?.stop(); media?.restore(); panes.forEach { $0.terminal.terminate() } }
    func installMenu() {
        let main = NSMenu()
        func menu(_ title: String, items: [(String, Selector, String)]) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: ""); let submenu = NSMenu(title: title)
            for (name, action, key) in items { submenu.addItem(withTitle: name, action: action, keyEquivalent: key) }
            item.submenu = submenu; main.addItem(item)
        }
        menu("Veil", items: [("Quit Veil Native", #selector(NSApplication.terminate(_:)), "q")])
        menu("Shell", items: [("New Tab", #selector(addTab(_:)), "t"), ("Close Split", #selector(closePane(_:)), "w"), ("Next Tab", #selector(nextTab(_:)), "}")])
        menu("Edit", items: [("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")])
        NSApp.mainMenu = main
    }
}
