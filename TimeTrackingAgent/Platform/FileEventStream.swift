// FileEventStream: an FSEvents stream on the watched roots
// (spec_activity_tracking.md §3.4). FSEvents delivers on a dispatch queue,
// so this glue file uses the main queue.

import CoreServices
import Foundation

/// Reports modified files below `roots` on the main actor.
@MainActor
final class FileEventStream {
    private var stream: FSEventStreamRef?
    private let box: Box

    private final class Box {
        let handler: @MainActor ([String]) -> Void

        init(handler: @escaping @MainActor ([String]) -> Void) {
            self.handler = handler
        }
    }

    init(handler: @escaping @MainActor ([String]) -> Void) {
        self.box = Box(handler: handler)
    }

    /// Starts watching `roots` (absolute paths); restarting replaces the stream.
    func start(roots: [String]) {
        stop()
        let existing = roots.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else {
            return
        }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(box).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else {
                return
            }
            let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
            // With kFSEventStreamCreateFlagUseCFTypes the paths are a CFArray of CFString.
            // swiftlint:disable:next legacy_objc_type
            let list = unsafeBitCast(paths, to: NSArray.self)
            var modified: [String] = []
            for index in 0 ..< count {
                let flag = Int(flags[index])
                let isFile = flag & kFSEventStreamEventFlagItemIsFile != 0
                let changed = flag &
                    (kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRenamed) != 0
                if isFile, changed, let path = list[index] as? String {
                    modified.append(path)
                }
            }
            MainActor.assumeIsolated { box.handler(modified) }
        }
        let flags =
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(
            nil,
            callback,
            &context,
            existing as CFArray,
            // The SDK spells these with "Id".
            // swiftformat:disable:next acronyms
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2,
            flags
        ) else {
            return
        }
        FSEventStreamSetDispatchQueue(created, DispatchQueue.main)
        FSEventStreamStart(created)
        stream = created
    }

    func stop() {
        guard let stream else {
            return
        }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
