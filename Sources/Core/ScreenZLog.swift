import Foundation

/// Simple file-based logger that appends timestamped lines to /tmp/screenz.log.
/// This lets us observe output from a bundled app that has no visible terminal.
enum ScreenZLog {
    static let path = NSHomeDirectory() + "/screenz-debug.log"

    static func write(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: path) {
                let handle = FileHandle(forWritingAtPath: path)!
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}
