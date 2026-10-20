import Foundation

public enum BridgeService: String, Codable, Sendable, CaseIterable {
    case screen
    case input
    case accessibility
}

public protocol SimulatorBridge: Sendable {
    var capabilities: BridgeCapabilities { get async }
    var devices: any DeviceControlling { get }
    var runtimes: any RuntimeControlling { get }
    var apps: any AppControlling { get }
    var logs: any LogControlling { get }
    var screen: (any ScreenControlling)? { get }
    var input: (any InputControlling)? { get }
    var accessibility: (any AccessibilityReading)? { get }
}

public extension SimulatorBridge {
    func supports(_ service: BridgeService) -> Bool {
        switch service {
        case .screen:
            return screen != nil
        case .input:
            return input != nil
        case .accessibility:
            return accessibility != nil
        }
    }
}
