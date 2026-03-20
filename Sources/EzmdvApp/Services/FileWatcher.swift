import Foundation

final class FileWatcher {
    private var streams: [FSEventStreamRef] = []
    private let callback: (String) -> Void

    init(callback: @escaping (String) -> Void) {
        self.callback = callback
    }

    deinit {
        stopAll()
    }

    func watch(directory path: String) {
        let pathsToWatch = [path] as CFArray
        var context = FSEventStreamContext()

        // Store callback reference via pointer
        let callbackBox = CallbackBox(callback: callback)
        let pointer = Unmanaged.passRetained(callbackBox).toOpaque()
        context.info = pointer

        guard let stream = FSEventStreamCreate(
            nil,
            fsEventCallback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // latency in seconds
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else { return }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        streams.append(stream)
    }

    private func stopAll() {
        for stream in streams {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        streams.removeAll()
    }
}

private final class CallbackBox {
    let callback: (String) -> Void
    init(callback: @escaping (String) -> Void) {
        self.callback = callback
    }
}

private func fsEventCallback(
    stream: ConstFSEventStreamRef,
    clientInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientInfo = clientInfo else { return }
    let box = Unmanaged<CallbackBox>.fromOpaque(clientInfo).takeUnretainedValue()
    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]

    for path in paths where path.lowercased().hasSuffix(".md") {
        box.callback(path)
    }
}
