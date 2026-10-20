import HTTPTypes
import Hummingbird
import NIOCore
import OpenSimProtocol

public enum EventRoutes {
    public static func register(on router: Router<BasicRequestContext>, services: DaemonServices) {
        router.get("/v1/events") { request, _ -> Response in
            let lastEventID = HTTPField.Name("last-event-id").flatMap { request.headers[$0] }
            let (initial, stream) = await services.events.subscribe(after: lastEventID)
            return makeResponse(initial: initial, stream: stream)
        }
    }

    private static func makeResponse(initial: [DaemonEvent], stream: AsyncStream<DaemonEvent>) -> Response {
        let body = AsyncThrowingStream<ByteBuffer, Error> { continuation in
            let task = Task {
                do {
                    for event in initial {
                        continuation.yield(ByteBuffer(string: try SSEFrame.encode(event)))
                    }
                    for await event in stream {
                        continuation.yield(ByteBuffer(string: try SSEFrame.encode(event)))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
        return Response(
            status: .ok,
            headers: [
                .contentType: "text/event-stream",
                .cacheControl: "no-cache",
            ],
            body: .init(asyncSequence: body)
        )
    }
}
