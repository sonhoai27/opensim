import Darwin
import Foundation
import OpenSimCore

public final class ProcessLock: @unchecked Sendable {
    private let fd: Int32
    private var released = false

    public init(path: URL) throws {
        let descriptor = open(path.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else {
            throw OpenSimError(
                code: .permissionDenied,
                message: "Cannot open daemon lock file",
                details: ["path": path.path, "errno": "\(errno)"]
            )
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw OpenSimError.daemonUnavailable("Another OpenSim daemon is already running")
        }
        self.fd = descriptor
    }

    public func release() {
        guard !released else {
            return
        }
        released = true
        _ = flock(fd, LOCK_UN)
        _ = close(fd)
    }

    deinit {
        release()
    }
}
