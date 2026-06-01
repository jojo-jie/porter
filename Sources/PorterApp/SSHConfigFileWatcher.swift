import Foundation

@MainActor
final class SSHConfigFileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var debounceTask: Task<Void, Never>?
    private var configURL: URL?

    func watch(configURL: URL) {
        stop()
        self.configURL = configURL
        guard FileManager.default.fileExists(atPath: configURL.path) else { return }
        openWatch(for: configURL)
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        source?.cancel()
        source = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    private func openWatch(for configURL: URL) {
        let fd = open(configURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .link, .rename, .revoke],
            queue: DispatchQueue.global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.handleFileEvent()
            }
        }
        source.setCancelHandler { [fd] in
            close(fd)
        }
        self.source = source
        source.resume()
    }

    private func handleFileEvent() {
        scheduleRefresh()
        guard let configURL else { return }
        if !FileManager.default.fileExists(atPath: configURL.path) {
            stop()
            watch(configURL: configURL)
            return
        }
        if fileDescriptor < 0 {
            openWatch(for: configURL)
        }
    }

    private func scheduleRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            NotificationCenter.default.post(name: .porterRefreshHosts, object: nil)
        }
    }
}
