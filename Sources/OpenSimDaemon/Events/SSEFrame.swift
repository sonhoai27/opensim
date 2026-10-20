import Foundation
import OpenSimCore
import OpenSimProtocol

public enum SSEFrame {
    public static func encode(_ event: DaemonEvent) throws -> String {
        let data = try OpenSimJSON.encoder(pretty: false).encode(event)
        let payload = String(decoding: data, as: UTF8.self)
        return "id: \(event.id)\nevent: \(event.type.rawValue)\ndata: \(payload)\n\n"
    }

    public static func comment(_ text: String) -> String {
        ": \(text)\n\n"
    }
}
