import Foundation
import Hummingbird
import OpenSimCore
import OpenSimProtocol

public enum DeviceRoutes {
    public static func register(on router: Router<BasicRequestContext>, services: DaemonServices) {
        router.get("/v1/devices") { request, _ in
            let result = try await services.dispatcher.dispatch(
                OperationRequest(operation: "device_list", parameters: queryParams(of: request))
            )
            return try DaemonHTTP.json(try result.decoded([Device].self))
        }

        router.get("/v1/devices/:udid") { _, context in
            let device = try await services.dispatcher.dispatch(
                OperationRequest(operation: "device_get", parameters: ["device": requiredParameter(context, "udid")])
            )
            return try DaemonHTTP.json(try device.decoded(Device.self))
        }

        router.post("/v1/devices/:udid/actions") { request, context in
            let body = try await DaemonHTTP.decode(request, as: DeviceActionRequest.self)
            return try await performAction(udid: requiredParameter(context, "udid"), body: body, services: services)
        }
    }

    private static func requiredParameter(_ context: BasicRequestContext, _ name: String) throws -> String {
        guard let value = context.parameters.get(name), !value.isEmpty else {
            throw OpenSimError.invalidArgument("Missing parameter: \(name)")
        }
        return value
    }

    private static func queryParams(of request: Request) -> [String: String] {
        let items = URLComponents(string: "?\(request.uri.query ?? "")")?.queryItems ?? []
        var parameters: [String: String] = [:]
        for item in items {
            parameters[item.name] = item.value
        }
        return parameters
    }

    private static func performAction(
        udid: String,
        body: DeviceActionRequest,
        services: DaemonServices
    ) async throws -> Response {
        let operation: String
        var parameters: [String: String] = ["device": udid]
        switch body.action {
        case "boot":
            operation = "device_boot"
            parameters["wait"] = body.wait == true ? "true" : "false"
        case "shutdown":
            operation = "device_shutdown"
            parameters["wait"] = body.wait == true ? "true" : "false"
        case "erase":
            operation = "device_erase"
            parameters["confirm"] = body.confirm == true ? "true" : "false"
        case "delete":
            operation = "device_delete"
            parameters["confirm"] = body.confirm == true ? "true" : "false"
        case "rename":
            operation = "device_rename"
            guard let name = body.name else {
                throw OpenSimError.invalidArgument("rename requires name")
            }
            parameters["name"] = name
        default:
            throw OpenSimError.invalidArgument("Unknown device action: \(body.action)")
        }
        let result = try await services.dispatcher.dispatch(OperationRequest(
            operation: operation,
            parameters: parameters,
            sessionID: body.sessionID,
            leaseID: body.leaseID
        ))
        if operation == "device_delete" {
            let ack = try result.decoded(OperationAck.self)
            return try DaemonHTTP.json(DeviceActionResponse(action: body.action, device: nil, ack: ack))
        }
        let device = try result.decoded(Device.self)
        return try DaemonHTTP.json(DeviceActionResponse(action: body.action, device: device, ack: nil))
    }
}
