import Darwin
import Foundation
import OpenSimCore

public enum PrivateFrameworkProbe {
    public static func probe(frameworks: FrameworkStatus) -> PrivateAPIStatus {
        var notes: [String: String] = [
            "policy": "class existence only; no selectors are invoked",
        ]
        let coreLoaded = loadFramework(path: frameworks.coreSimulatorPath, notes: &notes, key: "coreSimulator")
        let kitLoaded = loadFramework(path: frameworks.simulatorKitPath, notes: &notes, key: "simulatorKit")
        return PrivateAPIStatus(
            coreSimulatorLoadable: coreLoaded,
            simulatorKitLoadable: kitLoaded,
            simDisplayViewClassFound: NSClassFromString("_TtC12SimulatorKit14SimDisplayView") != nil,
            simDeviceLegacyHIDClientClassFound: NSClassFromString("_TtC12SimulatorKit24SimDeviceLegacyHIDClient") != nil,
            simAccessibilityManagerClassFound: NSClassFromString("_TtC12SimulatorKit23SimAccessibilityManager") != nil,
            notes: notes
        )
    }

    private static func loadFramework(path: String?, notes: inout [String: String], key: String) -> Bool {
        guard let path, !path.isEmpty else {
            notes[key] = "framework path missing"
            return false
        }
        guard let bundle = Bundle(path: path), let executable = bundle.executablePath else {
            notes[key] = "bundle executable missing at \(path)"
            return false
        }
        guard dlopen(executable, RTLD_LAZY | RTLD_LOCAL) != nil else {
            let message = dlerror().map { String(cString: $0) } ?? "dlopen failed"
            notes[key] = message
            return false
        }
        notes[key] = "loaded \(executable)"
        return true
    }
}
