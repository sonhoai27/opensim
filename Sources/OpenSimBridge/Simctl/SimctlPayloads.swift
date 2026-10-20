import Foundation
import OpenSimCore

struct SimctlDeviceListPayload: Decodable {
    let devices: [String: [SimctlDevicePayload]]
}

struct SimctlDevicePayload: Decodable {
    let udid: String
    let name: String
    let state: String
    let isAvailable: Bool?
    let deviceTypeIdentifier: String?
    let dataPath: String?
    let lastBootedAt: Date?
}

struct SimctlRuntimeListPayload: Decodable {
    let runtimes: [SimctlRuntimePayload]
}

struct SimctlRuntimePayload: Decodable {
    let identifier: String
    let name: String
    let version: String
    let buildversion: String?
    let isAvailable: Bool?
    let platform: String?
    let bundlePath: String?
    let runtimeRoot: String?
}
