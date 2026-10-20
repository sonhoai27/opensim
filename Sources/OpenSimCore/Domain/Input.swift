import Foundation

public struct Point: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct Rect: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct Key: Codable, Sendable, Equatable {
    public var name: String
    public var keyCode: UInt16?

    public init(name: String, keyCode: UInt16? = nil) {
        self.name = name
        self.keyCode = keyCode
    }
}

public struct KeyModifiers: Codable, Sendable, Equatable {
    public var command: Bool
    public var shift: Bool
    public var option: Bool
    public var control: Bool

    public init(command: Bool = false, shift: Bool = false, option: Bool = false, control: Bool = false) {
        self.command = command
        self.shift = shift
        self.option = option
        self.control = control
    }
}

public enum HardwareButton: String, Codable, Sendable, CaseIterable {
    case home
    case lock
    case side
    case volumeUp
    case volumeDown
    case back
    case overview
    case power
    case rotate
    case appleTVSelect
    case appleTVMenu
    case appleTVHome
}

public enum VideoCodec: String, Codable, Sendable, CaseIterable {
    case h264
    case hevc
}
