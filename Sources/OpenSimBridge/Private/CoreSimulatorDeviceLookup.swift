import Darwin
import Foundation
import ObjectiveC
import OpenSimCore

public enum CoreSimulatorDeviceLookup {
    public static func device(_ id: DeviceID, developerDir: String? = nil) throws -> AnyObject {
        let directory: String
        if let developerDir {
            directory = developerDir
        } else {
            directory = try XcodeLocator().developerDir()
        }
        let framework = "/Library/Developer/PrivateFrameworks/CoreSimulator.framework"
        guard let executable = DynamicFramework.executablePath(for: framework),
              DynamicFramework.load(executable) else {
            throw privateAPIError("Could not load CoreSimulator", selector: nil)
        }
        guard let contextClass = NSClassFromString("SimServiceContext") else {
            throw privateAPIError("SimServiceContext is not available", selector: nil)
        }

        let context = try callClass(
            contextClass,
            selector: "sharedServiceContextForDeveloperDir:error:",
            stringArgument: directory
        )
        let deviceSet = try callObject(context, selector: "defaultDeviceSetWithError:")
        let devices = try objectProperty(deviceSet, selector: "devices")

        let entries: [AnyObject]
        if let array = devices as? [AnyObject] {
            entries = array
        } else if let set = devices as? NSSet {
            entries = set.allObjects.map { $0 as AnyObject }
        } else if let dictionary = devices as? NSDictionary {
            entries = dictionary.allValues.map { $0 as AnyObject }
        } else {
            throw privateAPIError("SimDeviceSet.devices returned an unsupported type", selector: "devices")
        }

        for entry in entries {
            guard let object = entry as? NSObject else { continue }
            let udid = object.value(forKey: "UDID")
            let rawValue: String?
            if let uuid = udid as? UUID {
                rawValue = uuid.uuidString
            } else if let string = udid as? String {
                rawValue = string
            } else {
                rawValue = nil
            }
            if rawValue?.caseInsensitiveCompare(id.rawValue) == .orderedSame {
                return entry
            }
        }
        throw OpenSimError.deviceNotFound(id)
    }

    public static func lookupPort(
        _ service: String,
        device: AnyObject,
        deviceID: DeviceID
    ) throws -> UInt32 {
        let selector = NSSelectorFromString("lookup:error:")
        guard let cls = object_getClass(device),
              let method = class_getInstanceMethod(cls, selector) else {
            throw privateAPIError("SimDevice.lookup:error: is missing", selector: "lookup:error:")
        }
        typealias LookupFunction = @convention(c) (
            AnyObject,
            Selector,
            NSString,
            UnsafeMutablePointer<NSError?>?
        ) -> UInt32
        var error: NSError?
        let port = unsafeBitCast(method_getImplementation(method), to: LookupFunction.self)(
            device,
            selector,
            service as NSString,
            &error
        )
        guard port != 0 else {
            if let error, error.domain == "com.apple.CoreSimulator.SimError", error.code == 405 {
                throw OpenSimError(
                    code: .capabilityUnavailable,
                    message: "Simulator does not vend \(service)",
                    details: ["udid": deviceID.rawValue, "service": service],
                    recovery: "Use Xcode 27 / iOS 26 or newer"
                )
            }
            throw privateAPIError(
                "Could not look up \(service)",
                selector: "lookup:error:",
                error: error
            )
        }
        return port
    }

    private typealias StringErrorFunction = @convention(c) (
        AnyObject,
        Selector,
        NSString,
        UnsafeMutablePointer<NSError?>?
    ) -> Unmanaged<AnyObject>?

    private typealias ErrorFunction = @convention(c) (
        AnyObject,
        Selector,
        UnsafeMutablePointer<NSError?>?
    ) -> Unmanaged<AnyObject>?

    private typealias GetterFunction = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?

    private static func callClass(
        _ cls: AnyClass,
        selector name: String,
        stringArgument: String
    ) throws -> AnyObject {
        let selector = NSSelectorFromString(name)
        guard let method = class_getClassMethod(cls, selector) else {
            throw privateAPIError("Missing class method \(name)", selector: name)
        }
        let function = unsafeBitCast(method_getImplementation(method), to: StringErrorFunction.self)
        var error: NSError?
        guard let result = function(cls as AnyObject, selector, stringArgument as NSString, &error)?
            .takeUnretainedValue() else {
            throw privateAPIError("\(name) returned nil", selector: name, error: error)
        }
        return result
    }

    private static func callObject(_ object: AnyObject, selector name: String) throws -> AnyObject {
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(object_getClass(object), selector) else {
            throw privateAPIError("Missing instance method \(name)", selector: name)
        }
        let function = unsafeBitCast(method_getImplementation(method), to: ErrorFunction.self)
        var error: NSError?
        guard let result = function(object, selector, &error)?.takeUnretainedValue() else {
            throw privateAPIError("\(name) returned nil", selector: name, error: error)
        }
        return result
    }

    private static func objectProperty(_ object: AnyObject, selector name: String) throws -> AnyObject {
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(object_getClass(object), selector) else {
            throw privateAPIError("Missing property \(name)", selector: name)
        }
        let function = unsafeBitCast(method_getImplementation(method), to: GetterFunction.self)
        guard let result = function(object, selector)?.takeUnretainedValue() else {
            throw privateAPIError("\(name) returned nil", selector: name)
        }
        return result
    }

    private static func privateAPIError(
        _ message: String,
        selector: String?,
        error: NSError? = nil
    ) -> OpenSimError {
        var details = [
            "framework": "/Library/Developer/PrivateFrameworks/CoreSimulator.framework",
        ]
        if let selector {
            details["selector"] = selector
        }
        if let error {
            details["error"] = error.localizedDescription
        }
        return OpenSimError(
            code: .privateApiUnavailable,
            message: message,
            details: details,
            recovery: "Use Xcode 27.1 with the CoreSimulator private framework installed"
        )
    }
}
