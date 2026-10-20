import XCTest
@testable import OpenSimBridge
@testable import OpenSimCore

final class Plan2GateProbeTests: XCTestCase {
    func testPrintGateProbe() throws {
        guard ProcessInfo.processInfo.environment["OPENSIM_GATE"] == "1" else {
            throw XCTSkip("set OPENSIM_GATE=1 to run the capability probe")
        }
        let loader = SimulatorKitLoader.live()
        let capabilities = Plan2CapabilityGate.evaluate(checker: loader, helperConfigured: false)
        let json = try OpenSimJSON.encoder().encode(capabilities)
        print("PLAN2_GATE=\(String(decoding: json, as: UTF8.self))")
        let symbols = loader.indigoSymbols()
        let sends = loader.sendSelectors(className: "SimDeviceLegacyHIDClient")
        print("PLAN2_INDIGO=\(symbols.joined(separator: ","))")
        print("PLAN2_SEND=\(sends.joined(separator: ","))")
        let screenSelectors = loader.selectors(className: "SimDeviceScreen")
            .filter { $0.localizedCaseInsensitiveContains("surface") || $0.localizedCaseInsensitiveContains("screen") }
        let displaySelectors = loader.selectors(className: "SimDisplayView")
            .filter { $0.localizedCaseInsensitiveContains("screen") || $0.localizedCaseInsensitiveContains("pixel") || $0.localizedCaseInsensitiveContains("surface") }
        print("PLAN2_SCREEN_SEL=\(screenSelectors.joined(separator: ","))")
        print("PLAN2_DISPLAY_SEL=\(displaySelectors.joined(separator: ","))")
        print("PLAN2_PROXY_CLASS=\(String(describing: NSClassFromString("ROCKRemoteProxy")))")
        print("PLAN2_PROXY_FRAMEBUFFER=\(loader.responds("ROCKRemoteProxy", "framebufferSurface"))")
        XCTAssertTrue(loader.hasClass("SimServiceContext"))
        XCTAssertTrue(loader.hasClass("SimDeviceScreen"))
    }

    func testCoreSimulatorLookupFindsBootedDevice() async throws {
        guard ProcessInfo.processInfo.environment["OPENSIM_GATE"] == "1" else {
            throw XCTSkip("set OPENSIM_GATE=1 to run the CoreSimulator lookup probe")
        }
        let service = SimctlDeviceService(executor: ProcessSimctlExecutor(), timeout: .seconds(30))
        guard let booted = try await service.listDevices().first(where: { $0.state == .booted }) else {
            throw XCTSkip("no booted simulator")
        }
        let device = try CoreSimulatorDeviceLookup.device(booted.id)
        let udid = (device as? NSObject)?.value(forKey: "UDID") as? UUID
        XCTAssertEqual(udid, UUID(uuidString: booted.id.rawValue))
        print("PLAN2_LOOKUP=\(booted.id.rawValue)")
    }
}
