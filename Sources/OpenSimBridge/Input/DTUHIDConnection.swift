import Darwin
import Foundation
import OpenSimCore
import XPC

public final class DTUHIDConnection: @unchecked Sendable {
    public static let digitizerService = "com.apple.coredevice.feature.remote.hid.digitizer"

    private let connection: xpc_connection_t
    private let queue = DispatchQueue(label: "dev.opensim.dtuhid")
    private let state = State()

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var invalidated = false

        var isInvalidated: Bool {
            lock.lock()
            defer { lock.unlock() }
            return invalidated
        }

        func invalidate() {
            lock.lock()
            invalidated = true
            lock.unlock()
        }
    }

    public init(deviceObject: AnyObject, deviceID: DeviceID) throws {
        let port = try CoreSimulatorDeviceLookup.lookupPort(
            Self.digitizerService,
            device: deviceObject,
            deviceID: deviceID
        )
        guard let handle = dlopen(nil, RTLD_NOW) else {
            throw Self.transportError("Could not open the XPC runtime")
        }
        guard
            let endpointSymbol = dlsym(handle, "xpc_endpoint_create_mach_port_4sim"),
            let connectionSymbol = dlsym(handle, "xpc_connection_create_from_endpoint"),
            let sim2hostSymbol = dlsym(handle, "xpc_connection_enable_sim2host_4sim")
        else {
            throw Self.transportError("The simulator XPC bridge symbols are unavailable")
        }
        typealias EndpointFunction = @convention(c) (UInt32, UInt64, UInt64) -> Unmanaged<AnyObject>?
        typealias ConnectionFunction = @convention(c) (xpc_object_t) -> Unmanaged<AnyObject>?
        typealias Sim2HostFunction = @convention(c) (xpc_connection_t) -> Void
        let endpointFunction = unsafeBitCast(endpointSymbol, to: EndpointFunction.self)
        let connectionFunction = unsafeBitCast(connectionSymbol, to: ConnectionFunction.self)
        let sim2hostFunction = unsafeBitCast(sim2hostSymbol, to: Sim2HostFunction.self)

        guard let endpoint = endpointFunction(port, 0, 0)?.takeRetainedValue() as? xpc_object_t else {
            throw Self.transportError("Could not create the simulator XPC endpoint")
        }
        guard let rawConnection = connectionFunction(endpoint)?.takeRetainedValue(),
              let connection = rawConnection as? xpc_connection_t else {
            throw Self.transportError("Could not create the simulator XPC connection")
        }
        sim2hostFunction(connection)
        self.connection = connection
        xpc_connection_set_target_queue(connection, queue)
        let state = self.state
        xpc_connection_set_event_handler(connection) { event in
            if xpc_get_type(event) == XPC_TYPE_ERROR {
                state.invalidate()
            }
        }
        xpc_connection_resume(connection)
        try confirmLiveness()
    }

    deinit {
        close()
    }

    public var isInvalidated: Bool {
        state.isInvalidated
    }

    public func close() {
        xpc_connection_cancel(connection)
    }

    public func sendDigitizer(
        first: CGPoint,
        second: CGPoint? = nil,
        eventType: UInt64
    ) throws {
        guard !isInvalidated else {
            throw Self.transportError("The simulator HID connection is closed")
        }
        let payload = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_value(payload, "pointOne", point(first))
        if let second {
            xpc_dictionary_set_value(payload, "pointTwo", point(second))
        }
        xpc_dictionary_set_uint64(payload, "eventType", eventType)
        xpc_dictionary_set_uint64(payload, "edge", 0)
        xpc_dictionary_set_uint64(payload, "target", 0)
        xpc_connection_send_message(
            connection,
            envelope(messageType: "IndigoDigitizerEvent", isBarrier: false, payload: payload)
        )
    }

    public func sendKeyboard(usage: UInt64, state: UInt64) throws {
        guard !isInvalidated else {
            throw Self.transportError("The simulator HID connection is closed")
        }
        let payload = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_uint64(payload, "usageCode", usage)
        xpc_dictionary_set_uint64(payload, "state", state)
        xpc_connection_send_message(
            connection,
            envelope(messageType: "IndigoKeyboardButtonEvent", isBarrier: false, payload: payload)
        )
    }

    public func sendButton(page: UInt64, code: UInt64, state: UInt64) throws {
        guard !isInvalidated else {
            throw Self.transportError("The simulator HID connection is closed")
        }
        let payload = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_uint64(payload, "usagePage", page)
        xpc_dictionary_set_uint64(payload, "usageCode", code)
        xpc_dictionary_set_uint64(payload, "state", state)
        xpc_connection_send_message(
            connection,
            envelope(messageType: "IndigoButtonEvent", isBarrier: false, payload: payload)
        )
    }

    private func point(_ point: CGPoint) -> xpc_object_t {
        let object = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_double(object, "x", point.x)
        xpc_dictionary_set_double(object, "y", point.y)
        return object
    }

    private func envelope(
        messageType: String,
        isBarrier: Bool,
        payload: xpc_object_t
    ) -> xpc_object_t {
        let object = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_string(object, "messageType", messageType)
        xpc_dictionary_set_bool(object, "isBarrier", isBarrier)
        xpc_dictionary_set_string(object, "featureIdentifier", Self.digitizerService)
        xpc_dictionary_set_value(object, "payload", payload)
        return object
    }

    private func confirmLiveness() throws {
        let payload = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_uint64(payload, "usageCode", 0)
        xpc_dictionary_set_uint64(payload, "state", 2)
        let message = envelope(
            messageType: "IndigoKeyboardButtonEvent",
            isBarrier: true,
            payload: payload
        )
        let semaphore = DispatchSemaphore(value: 0)
        let replyBox = ReplyBox()
        xpc_connection_send_message_with_reply(connection, message, queue) { reply in
            replyBox.ok = xpc_get_type(reply) != XPC_TYPE_ERROR
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 5) == .timedOut {
            throw Self.transportError("The dtuhidd liveness probe timed out")
        }
        guard replyBox.ok else {
            throw Self.transportError("The dtuhidd liveness probe failed")
        }
        usleep(100_000)
    }

    private static func transportError(_ message: String) -> OpenSimError {
        OpenSimError(
            code: .capabilityUnavailable,
            message: message,
            details: ["service": digitizerService],
            recovery: "Use Xcode 27 with a booted iOS 26+ simulator"
        )
    }
}

private final class ReplyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var ok: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }
}
