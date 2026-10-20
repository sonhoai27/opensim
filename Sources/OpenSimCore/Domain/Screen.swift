import Foundation

public enum ScreenRotation: String, Codable, Sendable, CaseIterable {
    case portrait
    case landscapeLeft
    case portraitUpsideDown
    case landscapeRight

    public var degrees: Int {
        switch self {
        case .portrait:
            return 0
        case .landscapeLeft:
            return 90
        case .portraitUpsideDown:
            return 180
        case .landscapeRight:
            return 270
        }
    }

    public var isSideways: Bool {
        degrees == 90 || degrees == 270
    }
}

public struct ScreenInfo: Codable, Sendable, Identifiable, Equatable {
    public let id: UInt32
    public var width: Int
    public var height: Int
    public var scale: Double
    public var rotation: Double
    public var displayClass: Int

    public init(id: UInt32, width: Int, height: Int, scale: Double, rotation: Double, displayClass: Int) {
        self.id = id
        self.width = width
        self.height = height
        self.scale = scale
        self.rotation = rotation
        self.displayClass = displayClass
    }
}

public enum ScreenshotFormat: String, Codable, Sendable, CaseIterable {
    case png
    case jpeg
}

public struct Screenshot: Codable, Sendable, Equatable {
    public var path: String?
    public var data: Data?
    public var format: ScreenshotFormat
    public var width: Int
    public var height: Int
    public var scale: Double
    public var capturedAt: Date

    public init(
        path: String?,
        data: Data?,
        format: ScreenshotFormat,
        width: Int,
        height: Int,
        scale: Double,
        capturedAt: Date
    ) {
        self.path = path
        self.data = data
        self.format = format
        self.width = width
        self.height = height
        self.scale = scale
        self.capturedAt = capturedAt
    }
}
