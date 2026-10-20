import Foundation

public protocol DeviceControlling: Sendable {
    func listDevices() async throws -> [Device]
    func device(_ id: DeviceID) async throws -> Device
    func createDevice(name: String, deviceType: String, runtime: RuntimeID?) async throws -> Device
    func cloneDevice(_ id: DeviceID, name: String) async throws -> Device
    func boot(_ id: DeviceID, wait: Bool) async throws -> Device
    func shutdown(_ id: DeviceID, wait: Bool) async throws -> Device
    func erase(_ id: DeviceID) async throws -> Device
    func delete(_ id: DeviceID) async throws
    func rename(_ id: DeviceID, to name: String) async throws -> Device
    func pair(watch: DeviceID, phone: DeviceID) async throws
}

public protocol RuntimeControlling: Sendable {
    func listRuntimes() async throws -> [Runtime]
    func installRuntime(at path: String) async throws -> Runtime
    func deleteRuntime(_ id: RuntimeID) async throws
    func verifyRuntime(_ id: RuntimeID) async throws
}

public protocol AppControlling: Sendable {
    func listApps(on device: DeviceID, filter: String?) async throws -> [AppInfo]
    func installApp(on device: DeviceID, at path: String) async throws -> AppInfo
    func uninstallApp(on device: DeviceID, bundleID: String) async throws
    func launchApp(on device: DeviceID, bundleID: String, args: [String], environment: [String: String]) async throws -> Int32
    func terminateApp(on device: DeviceID, bundleID: String) async throws
    func appInfo(on device: DeviceID, bundleID: String) async throws -> AppInfo
    func containerPath(on device: DeviceID, bundleID: String, kind: ContainerKind) async throws -> String
}

public protocol LogControlling: Sendable {
    func tailLogs(on device: DeviceID, cursor: String?, limit: Int, filter: String?) async throws -> LogPage
}

public protocol ScreenControlling: Sendable {
    func screens(for device: DeviceID) async throws -> [ScreenInfo]
    func screenshot(on device: DeviceID, format: ScreenshotFormat, scale: Double, quality: Int?) async throws -> Screenshot
    func startRecording(on device: DeviceID, to path: String?, codec: VideoCodec) async throws -> RecordingID
    func stopRecording(_ id: RecordingID) async throws -> String
}

public protocol InputControlling: Sendable {
    func tap(on device: DeviceID, at point: Point, settle: Bool) async throws
    func swipe(on device: DeviceID, from: Point, to: Point, durationMs: Int) async throws
    func longPress(on device: DeviceID, at point: Point, durationMs: Int) async throws
    func drag(on device: DeviceID, from: Point, to: Point, durationMs: Int) async throws
    func pinch(on device: DeviceID, center: Point, scale: Double, durationMs: Int) async throws
    func rotate(on device: DeviceID, center: Point, angle: Double, durationMs: Int) async throws
    func scroll(on device: DeviceID, deltaX: Double, deltaY: Double, at point: Point?) async throws
    func typeText(on device: DeviceID, text: String) async throws
    func key(on device: DeviceID, key: Key, modifiers: KeyModifiers) async throws
    func button(on device: DeviceID, button: HardwareButton) async throws
}

public protocol AccessibilityReading: Sendable {
    func tree(on device: DeviceID, maxDepth: Int, maxNodes: Int) async throws -> UITree
    func find(on device: DeviceID, selector: ElementSelector) async throws -> [UIElement]
}

public protocol StorageManaging: Sendable {
    func scanStorage(refresh: Bool) async throws -> StorageScan
    func storageItems(scanID: String, parentID: String?) async throws -> [StorageItem]
    func planClean(scanID: String, itemIDs: [String]) async throws -> CleanPlan
    func applyClean(planToken: String, itemIDs: [String]) async throws -> [CleanResultItem]
}

public protocol MetricsReading: Sendable {
    func deviceMetrics(since: Date?) async throws -> [MetricSample]
    func processes(on device: DeviceID) async throws -> [ProcessSample]
}

public protocol DoctorReporting: Sendable {
    func doctorReport() async throws -> DoctorReport
}

public protocol CrashReportReading: Sendable {
    func crashReports(on device: DeviceID, limit: Int) async throws -> [CrashReport]
}
