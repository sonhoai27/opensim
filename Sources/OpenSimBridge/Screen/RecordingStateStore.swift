import Darwin
import Foundation
import OpenSimCore

public struct RecordingState: Codable, Sendable, Equatable {
    public var id: RecordingID
    public var deviceID: DeviceID
    public var path: String
    public var pid: Int32
    public var codec: VideoCodec
    public var startedAt: Date

    public init(
        id: RecordingID,
        deviceID: DeviceID,
        path: String,
        pid: Int32,
        codec: VideoCodec,
        startedAt: Date
    ) {
        self.id = id
        self.deviceID = deviceID
        self.path = path
        self.pid = pid
        self.codec = codec
        self.startedAt = startedAt
    }
}

public actor RecordingStateStore {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func save(_ state: RecordingState) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let url = fileURL(state.id)
        try OpenSimJSON.encoder(pretty: true).encode(state).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func load(_ id: RecordingID) throws -> RecordingState? {
        let url = fileURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try OpenSimJSON.decoder().decode(RecordingState.self, from: Data(contentsOf: url))
    }

    public func active(for device: DeviceID) throws -> RecordingState? {
        for state in try all() where state.deviceID == device {
            if state.pid > 0, kill(state.pid, 0) == 0 {
                return state
            }
            try? FileManager.default.removeItem(at: fileURL(state.id))
        }
        return nil
    }

    public func all() throws -> [RecordingState] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { try? OpenSimJSON.decoder().decode(RecordingState.self, from: Data(contentsOf: $0)) }
    }

    public func remove(_ id: RecordingID) throws {
        try? FileManager.default.removeItem(at: fileURL(id))
    }

    private func fileURL(_ id: RecordingID) -> URL {
        directory.appendingPathComponent("\(id.rawValue).json")
    }
}
