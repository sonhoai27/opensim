import Foundation
import OpenSimCore

public struct OutputRenderer: Sendable {
    public let json: Bool
    private let writeOut: @Sendable (String) -> Void
    private let writeErr: @Sendable (String) -> Void

    public init(
        json: Bool,
        writeOut: @escaping @Sendable (String) -> Void = { text in
            FileHandle.standardOutput.write(Data(text.utf8))
        },
        writeErr: @escaping @Sendable (String) -> Void = { text in
            FileHandle.standardError.write(Data(text.utf8))
        }
    ) {
        self.json = json
        self.writeOut = writeOut
        self.writeErr = writeErr
    }

    public func success<T: Codable & Sendable>(
        _ data: T,
        table: Table?,
        durationMs: Int
    ) throws {
        if json {
            let envelope = Envelope<T>.success(
                data,
                requestId: RequestID.make(),
                durationMs: durationMs
            )
            let encoded = try OpenSimJSON.encoder(pretty: true).encode(envelope)
            writeOut(String(decoding: encoded, as: UTF8.self) + "\n")
            return
        }
        if let table {
            writeOut(table.rendered() + "\n")
        } else {
            writeOut(String(describing: data) + "\n")
        }
    }

    public func failure(_ error: OpenSimError, durationMs: Int) {
        if json {
            let envelope = Envelope<EmptyPayload>.failure(
                error,
                requestId: RequestID.make(),
                durationMs: durationMs
            )
            if let encoded = try? OpenSimJSON.encoder(pretty: true).encode(envelope) {
                writeErr(String(decoding: encoded, as: UTF8.self) + "\n")
            }
            return
        }
        writeErr("error[\(error.code)]: \(error.message)\n")
        if let recovery = error.recovery {
            writeErr("recovery: \(recovery)\n")
        }
    }

    public func line(_ text: String) {
        writeOut(text + "\n")
    }
}
