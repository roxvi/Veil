import AppKit
import VeilCore

/// Screen rectangles use Accessibility's global top-left coordinates, in points.
@MainActor
struct PiPTarget {
    let id: UUID
    let rect: () -> CGRect?
    let eligible: () -> Bool
    let park: () -> Void
    let restore: () -> Void
    let resize: (CGSize) -> Void
}

@MainActor
final class PiPCoordinator {
    private let helperURL: URL
    private weak var window: NSWindow?
    private let targets: () -> [PiPTarget]
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var generation = UUID()
    private var timer: Timer?
    private var picker: NSAlert?
    private var requested: UUID?
    private var linked: PiPTarget?
    private var unbound = false
    private var selectedID: String?
    private var selectedRect: CGRect?
    private var aspect: CGFloat = 1
    private var maxWidth: CGFloat?
    private var lastWrite = Date.distantPast
    private var clampReported = false
    private var previousDown = false
    private var dragOrigin: (rect: CGRect, pointer: CGPoint)?
    private var moved = false
    private var spring: CGRect?
    private var velocity = [CGFloat](repeating: 0, count: 4)
    private var springTicks = 0
    private var reduceMotion = false
    private var lastDestination: CGRect?

    init(helperURL: URL, window: NSWindow, targets: @escaping () -> [PiPTarget]) {
        self.helperURL = helperURL; self.window = window; self.targets = targets
    }

    func connect(targetID: UUID, unbound: Bool) {
        guard let target = targets().first(where: { $0.id == targetID }), target.eligible(), target.rect() != nil else { return }
        stop()
        requested = targetID; self.unbound = unbound
        launch(prompt: false)
    }

    func stop() {
        generation = UUID()
        timer?.invalidate(); timer = nil
        if let picker, let sheet = picker.window.sheetParent { sheet.endSheet(picker.window, returnCode: .cancel) }
        picker = nil
        output?.readabilityHandler = nil; output = nil
        try? input?.close(); input = nil
        let child = process; process = nil
        if child?.isRunning == true { child?.terminate() }
        linked?.restore(); linked = nil
        requested = nil; selectedID = nil; selectedRect = nil; buffer.removeAll()
        dragOrigin = nil; previousDown = false; spring = nil; maxWidth = nil
        clampReported = false; lastDestination = nil
    }

    private func launch(prompt: Bool) {
        let child = Process(), stdin = Pipe(), stdout = Pipe()
        child.executableURL = helperURL
        child.arguments = prompt ? ["--request-access"] : []
        child.standardInput = stdin; child.standardOutput = stdout
        child.standardError = FileHandle.nullDevice
        process = child; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
        let token = generation
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            guard !bytes.isEmpty else { handle.readabilityHandler = nil; return }
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.receive(bytes)
            }
        }
        child.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                // A permission response leaves its retry sheet alive after helper exit.
                if self.picker == nil { self.stop() }
            }
        }
        do { try child.run() }
        catch { stop(); showError("PiP helper could not start: \(error.localizedDescription)"); return }
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        while let end = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: end); buffer.removeSubrange(...end)
            guard let m = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], let type = m["type"] as? String else { continue }
            switch type {
            case "windows": choose(m["windows"] as? [[String: String]] ?? [])
            case "frame": frame(m)
            case "permission": permission(m["message"] as? String ?? "Allow Veil Accessibility access in System Settings.")
            case "error": let message = m["message"] as? String ?? "The source window is unavailable."; stop(); showError(message)
            case "gone": stop()
            default: break
            }
        }
    }

    private func choose(_ windows: [[String: String]]) {
        guard picker == nil, selectedID == nil, let window else { return }
        let alert = NSAlert(); alert.messageText = "Connect a PiP window"
        alert.informativeText = windows.isEmpty ? "No movable video windows found. Open PiP in your browser or player, then refresh." : "Choose the external window to attach to this split."
        let choices = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 430, height: 28))
        choices.addItems(withTitles: windows.map { $0["title"] ?? "Untitled window" })
        alert.accessoryView = choices
        alert.addButton(withTitle: "Connect").isEnabled = !windows.isEmpty
        alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "Refresh")
        picker = alert
        let token = generation
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, self.generation == token else { return }
            self.picker = nil
            if response == .alertFirstButtonReturn, windows.indices.contains(choices.indexOfSelectedItem), let id = windows[choices.indexOfSelectedItem]["id"] {
                self.selectedID = id; self.command(["op": "select", "id": id])
            } else if response == .alertThirdButtonReturn { self.command(["op": "scan"]) }
            else { self.stop() }
        }
    }

    private func permission(_ message: String) {
        guard let window else { stop(); return }
        let target = requested, mode = unbound
        let alert = NSAlert(); alert.messageText = "Accessibility access needed"; alert.informativeText = message
        alert.addButton(withTitle: "Allow / Retry"); alert.addButton(withTitle: "Cancel")
        picker = alert
        let token = generation
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, self.generation == token else { return }
            self.picker = nil; self.stop()
            if response == .alertFirstButtonReturn, let target {
                self.requested = target; self.unbound = mode; self.launch(prompt: true)
            }
        }
    }

    private func showError(_ message: String) {
        guard let window else { return }
        let alert = NSAlert(); alert.messageText = "PiP disconnected"; alert.informativeText = message
        alert.beginSheetModal(for: window)
    }

    private func command(_ value: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: value), let input else { return }
        do { try input.write(contentsOf: data + Data([10])) } catch { stop() }
    }

    private func readRect(_ value: Any?) -> CGRect? {
        guard let r = value as? [String: Double], let x = r["x"], let y = r["y"], let w = r["width"], let h = r["height"] else { return nil }
        let rect = CGRect(x: x, y: y, width: w, height: h)
        return PiPGeometry.valid(rect) ? rect : nil
    }

    private func frame(_ m: [String: Any]) {
        guard let r = readRect(m["rect"]), let pointer = m["pointer"] as? [String: Double], let x = pointer["x"], let y = pointer["y"] else { return }
        let p = CGPoint(x: x, y: y), down = m["down"] as? Bool ?? false
        reduceMotion = m["reduceMotion"] as? Bool ?? false
        if selectedRect == nil { aspect = r.width / r.height }
        selectedRect = r
        if let id = requested {
            requested = nil
            guard let target = targets().first(where: { $0.id == id }), target.eligible(), target.rect() != nil else { stop(); return }
            attach(target, from: r)
        }
        if m["escape"] as? Bool == true { stop(); return }
        if down && !previousDown && r.contains(p) { dragOrigin = (r, p); moved = false; spring = nil }
        if down, let origin = dragOrigin {
            moved = moved || PiPGeometry.distance(origin.pointer, p) > 8
            if moved {
                let resizing = abs(r.width - origin.rect.width) + abs(r.height - origin.rect.height) > 4
                if let linked, resizing {
                    aspect = r.width / r.height; maxWidth = nil; clampReported = false
                    if !unbound { linked.resize(CGSize(width: r.width + 12, height: r.height + 12)) }
                } else if linked != nil && PiPGeometry.distance(r.origin, origin.rect.origin) > 32 {
                    linked?.restore(); linked = nil; lastDestination = nil
                }
            }
        }
        if !down && previousDown && dragOrigin != nil {
            if linked == nil && moved, let target = bestTarget(r), let rect = target.rect(), PiPGeometry.overlap(r, rect) >= 0.62 { attach(target, from: r) }
            else if linked != nil { settle(r) }
            dragOrigin = nil
        }
        if !unbound, linked != nil, !down, spring == nil, !clampReported, Date().timeIntervalSince(lastWrite) > 0.3, let to = destination(),
           PiPGeometry.distance(r.origin, to.origin) > 2 || abs(r.width - to.width) > 2 || abs(r.height - to.height) > 2 {
            clampReported = true; aspect = r.width / r.height
            if r.width < to.width - 2 { maxWidth = r.width }
            linked?.resize(CGSize(width: r.width + 12, height: r.height + 12))
            if let to = destination() { move(to) }
        }
        previousDown = down
    }

    private func bestTarget(_ rect: CGRect) -> PiPTarget? {
        targets().compactMap { target -> (PiPTarget, CGFloat)? in
            guard target.eligible(), let r = target.rect(), r.width >= 160, r.height >= 100 else { return nil }
            let strength = PiPGeometry.overlap(rect, r)
            return strength >= 0.28 ? (target, strength) : nil
        }.sorted { a, b in
            a.1 == b.1 ? a.0.id.uuidString < b.0.id.uuidString : a.1 > b.1
        }.first?.0
    }

    private func attach(_ target: PiPTarget, from: CGRect) {
        guard target.eligible(), target.rect() != nil else { return }
        target.park(); linked = target; clampReported = false
        settle(from)
    }

    private func destination() -> CGRect? {
        guard let rect = linked?.rect(), let selectedRect else { return nil }
        if unbound { return CGRect(x: rect.midX - selectedRect.width / 2, y: rect.midY - selectedRect.height / 2, width: selectedRect.width, height: selectedRect.height) }
        var result = PiPGeometry.fit(rect, aspect: aspect)
        if let maxWidth, result.width > maxWidth { result = CGRect(x: rect.midX - maxWidth / 2, y: rect.midY - maxWidth / aspect / 2, width: maxWidth, height: maxWidth / aspect) }
        return result
    }

    private func settle(_ from: CGRect) {
        if reduceMotion { if let to = destination() { move(to) }; return }
        spring = from; velocity = [CGFloat](repeating: 0, count: 4); springTicks = 0
    }

    private func move(_ rect: CGRect) {
        guard PiPGeometry.valid(rect) else { return }
        lastWrite = Date(); lastDestination = destination()
        command(["op": "set", "rect": ["x": rect.minX, "y": rect.minY, "width": rect.width, "height": rect.height], "positionOnly": unbound])
    }

    private func tick() {
        guard let window, window.isVisible, !window.isMiniaturized else { stop(); return }
        if let linked, linked.rect() == nil { stop(); return }
        if let requested, !targets().contains(where: { $0.id == requested && $0.rect() != nil }) { stop(); return }
        guard dragOrigin == nil, let to = destination() else { return }
        guard let current = spring else { if to != lastDestination { move(to) }; return }
        var values = [current.minX, current.minY, current.width, current.height]
        let desired = [to.minX, to.minY, to.width, to.height]
        var error: CGFloat = 0
        for i in 0..<4 {
            velocity[i] += (390 * (desired[i] - values[i]) - 32 * velocity[i]) / 30
            values[i] += velocity[i] / 30; error += abs(desired[i] - values[i])
        }
        let next = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        spring = next; springTicks += 1; move(next)
        if error < 1 || springTicks > 35 { move(to); spring = nil }
    }
}
