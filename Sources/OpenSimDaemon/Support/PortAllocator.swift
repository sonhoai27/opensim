import Darwin
import Foundation
import OpenSimCore

public enum PortAllocator {
    public static func freePort() throws -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw OpenSimError(
                code: .internalError,
                message: "Cannot create socket for port allocation",
                details: ["errno": "\(errno)"]
            )
        }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw OpenSimError(
                code: .internalError,
                message: "Cannot bind loopback socket",
                details: ["errno": "\(errno)"]
            )
        }

        var assigned = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &assigned) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(descriptor, socketAddress, &length)
            }
        }
        guard nameResult == 0 else {
            throw OpenSimError(
                code: .internalError,
                message: "Cannot read allocated port",
                details: ["errno": "\(errno)"]
            )
        }
        return Int(UInt16(bigEndian: assigned.sin_port))
    }
}
