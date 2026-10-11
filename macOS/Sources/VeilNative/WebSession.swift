import Foundation
import SwiftTerm
import VeilCore

/// Owns one real PTY. Delivery is serialized on the main queue, with at most a
/// 4ms batching deadline; xterm receives bytes, including split UTF-8 sequences.
@MainActor final class WebSession: @preconcurrency LocalProcessDelegate {
    let id = UUID().uuidString
    lazy var process = LocalProcess(delegate: self, dispatchQueue: .main)
    var size: winsize
    var input = InputState()
    var ready = false
    var pending = Data()
    var timer: DispatchWorkItem?
    var ended: Int32?
    var lastDrop = Date.distantPast
    var output: ((String, [String: Any]) -> Void)?
    init(cols: Int, rows: Int) {
        size = winsize(ws_row: UInt16(clamping: max(1, min(1000, rows))), ws_col: UInt16(clamping: max(2, min(1000, cols))), ws_xpixel: 0, ws_ypixel: 0)
    }
    func getWindowSize() -> winsize { size }
    func start(shell: String, directory: String, environment: [String: String]) throws {
        let result = process.startProcessChecked(executable: shell, args: ShellEnvironment.arguments(for: shell),
            environment: environment.map { "\($0.key)=\($0.value)" }, currentDirectory: directory)
        if case .failure(let error) = result { throw error }
    }
    func send(_ text: String) { _ = input.consume(text); process.send(data: Array(text.utf8)[...]) }
    func resize(cols: Int, rows: Int) {
        size.ws_col = UInt16(clamping: max(2, min(1000, cols))); size.ws_row = UInt16(clamping: max(1, min(1000, rows)))
        _ = process.updateWindowSize(&size)
    }
    var idle: Bool { process.running && input.isEmpty && tcgetpgrp(process.childfd) == process.shellPid }
    func dataReceived(slice: ArraySlice<UInt8>) {
        pending.append(contentsOf: slice)
        if ready && pending.count >= 65536 { flush(); return }
        guard ready, timer == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        timer = work; DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(4), execute: work)
    }
    func flush() {
        timer?.cancel(); timer = nil
        guard ready else { return }
        if !pending.isEmpty {
            output?("terminal:bytes", ["id": id, "base64": pending.base64EncodedString()]); pending.removeAll(keepingCapacity: true)
        }
        if let ended { output?("terminal:exit", ["id": id, "exitCode": ended]); self.ended = nil }
    }
    func processTerminated(_ source: LocalProcess, exitCode: Int32?) { ended = exitCode ?? -1; flush() }
    func stop() { timer?.cancel(); timer = nil; output = nil; process.terminate() }
}
