import Foundation
import Darwin
import VeilCore

@MainActor
final class ConfigurationStore {
    let url: URL
    var changed: ((Configuration) -> Void)?
    var failed: ((Error) -> Void)?
    private var watcher: DispatchSourceFileSystemObject?
    private var watched: URL?
    private var pending: DispatchWorkItem?
    private var previous: String?

    init(url: URL) { self.url = url }
    func start() { reload(); watch() }
    func stop() { pending?.cancel(); watcher?.cancel(); watcher = nil }

    private func reload() {
        do {
            let source: String
            if FileManager.default.fileExists(atPath: url.path) { source = try String(contentsOf: url, encoding: .utf8) }
            else { source = "" }
            guard source != previous else { return }
            previous = source
            changed?(Configuration(source))
        } catch { failed?(error) }
    }

    private func watch() {
        // Watch the parent: the CLI replaces config atomically. If it does not
        // exist yet, watch the nearest existing ancestor without creating data.
        var directory = url.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: directory.path), directory.path != "/" {
            directory.deleteLastPathComponent()
        }
        guard watched != directory else { return }
        watcher?.cancel()
        watched = directory
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
            eventMask: [.write, .rename, .delete], queue: .main)
        source.setCancelHandler { close(fd) }
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let flags = self.watcher?.data, !flags.intersection([.rename, .delete]).isEmpty {
                    self.watcher?.cancel(); self.watcher = nil; self.watched = nil
                }
                self.pending?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated { self?.reload(); self?.watch() }
                }
                self.pending = work
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(25), execute: work)
            }
        }
        watcher = source
        source.resume()
    }
}
