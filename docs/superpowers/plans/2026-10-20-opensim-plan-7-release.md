# OpenSim Plan 7 — Hardening và Release Simulator Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Đưa phạm vi simulator iOS/iPadOS/watchOS/tvOS từ trạng thái chạy được sang bản phát hành open-source cài được: security review có bằng chứng, CI xanh, ký và notarize, Homebrew tap, `opensim setup`/`doctor`, tài liệu sinh từ catalog, checklist release và rollback.

**Architecture:** Không thêm feature sản phẩm. Plan này khóa bề mặt tấn công bằng test hồi quy ở ranh giới daemon, thêm lớp kiểm tra path/compatibility, dựng pipeline release gồm GitHub-hosted unit/lint và self-hosted macOS 27 + Xcode 27.1 cho integration, rồi đóng gói app/CLI bằng Developer ID, Hardened Runtime và notarytool. Tài liệu CLI/MCP sinh trực tiếp từ `OperationCatalog`, nên tài liệu và hành vi không lệch nhau.

**Tech Stack:** Swift 6, SwiftPM, XcodeGen, XCTest, Hummingbird 2.x, swift-argument-parser, GitHub Actions, self-hosted macOS 27 runner, Developer ID + `notarytool` + `stapler`, `hdiutil`, Homebrew formula/cask, `launchctl`, `jq`, `zsh`.

**Spec:** `docs/superpowers/specs/2026-10-19-open-simulator-design.md`

**Plan phụ thuộc:** `docs/superpowers/plans/2026-10-20-opensim-plan-1-core-bridge-cli.md`, `docs/superpowers/plans/2026-10-20-opensim-plan-2-screen-input-a11y.md`, `docs/superpowers/plans/2026-10-20-opensim-plan-3-daemon-session-mcp.md`, `docs/superpowers/plans/2026-10-20-opensim-plan-4-macos-app.md`, `docs/superpowers/plans/2026-10-20-opensim-plan-5-storage-performance.md`, `docs/superpowers/plans/2026-10-20-opensim-plan-6-watchos-tvos.md`.

## Global Constraints

- macOS 27.0+; arm64; Xcode 27.1 là bản chính, Xcode 27.0 chỉ best-effort khi fingerprint khớp.
- Không thêm feature sản phẩm, không đổi tên type/protocol trong `docs/superpowers/plans/2026-10-20-plan-map-and-interfaces.md`; chỉ thêm type mới hoặc field có default.
- Daemon chỉ bind `127.0.0.1`, port động; token 32 byte ngẫu nhiên, file state `0600`, thư mục `0700`.
- Kiểm tra `Host` và `Origin`; không CORS; từ chối request không phải loopback.
- Không dùng shell string; mọi tiến trình chạy bằng `Process` với argument array.
- Validate UDID theo UUID, bundle ID theo regex, path theo allowlist root; destructive operation cần `confirm` hoặc plan token và phải ghi audit.
- Không telemetry, không upload log/screenshot; app tắt App Sandbox, bật Hardened Runtime; chỉ thêm `disable-library-validation` khi có bằng chứng và owner chấp thuận.
- Ký Developer ID và notarize mọi artifact phát hành; không Mac App Store.
- Version SemVer; JSON envelope `schemaVersion` bằng `1`; exit code `0, 2, 3, 4, 5, 6, 7, 10`.
- Unit/lint chạy trên GitHub-hosted macOS; integration chạy trên self-hosted macOS 27 + Xcode 27.1; nightly và release gate dùng cùng runner.
- Mọi task kết thúc bằng commit; plan author không chạy commit.
- Văn xuôi tiếng Việt; code, identifier, command tiếng Anh; không ký tự CJK; không dùng Chrome.

---

## File Structure

| File | Trách nhiệm | Task |
|---|---|---|
| `Tests/SecurityTests/Support/DaemonHarness.swift` | Khởi động daemon trong `HOME` tạm, gọi HTTP/CLI, dọn sạch | 1 |
| `Tests/SecurityTests/NetworkBoundaryTests.swift` | Host/Origin/auth/loopback | 1 |
| `Scripts/security/check-loopback.sh` | Bằng chứng listener chỉ ở loopback | 1 |
| `Tests/SecurityTests/TokenFileSecurityTests.swift` | Quyền file, độ dài token, rotation | 2 |
| `Scripts/security/check-token-permissions.sh` | Kiểm tra `0600`/`0700` trên máy thật | 2 |
| `Sources/OpenSimCore/Security/PathAllowlist.swift` | Allowlist path, chống symlink escape | 3 |
| `Sources/OpenSimBridge/Private/DeveloperDirPolicy.swift` | Chỉ chấp nhận developer dir dưới `/Applications` hoặc `/Library/Developer` | 3 |
| `Tests/SecurityTests/PathAllowlistTests.swift` | Test traversal, symlink, path không tồn tại | 3 |
| `Tests/SecurityTests/DeveloperDirPolicyTests.swift` | Test developer dir hợp lệ và giả | 3 |
| `Scripts/security/check-no-shell-strings.sh` | Chặn `/bin/sh`, `zsh -c`, `bash -c` trong `Sources/` | 3 |
| `Tests/SecurityTests/DestructiveOperationTests.swift` | Confirm bắt buộc, audit JSONL | 4 |
| `Scripts/security/check-audit-coverage.sh` | Validate audit JSONL sau test | 4 |
| `docs/security-review-checklist.md` | Checklist review với lệnh bằng chứng | 5 |
| `Scripts/security/check-no-telemetry.sh` | Chặn host ngoài loopback và SDK telemetry | 5 |
| `Sources/OpenSimCore/Compatibility/CompatibilityMatrix.swift` | Ma trận Xcode 27.0/27.1 và runtime | 6 |
| `Sources/OpenSimBridge/Capabilities/CapabilityPolicy.swift` | Suy giảm capability theo compat mode | 6 |
| `Tests/OpenSimCoreTests/CompatibilityMatrixTests.swift` | Test tra mode | 6 |
| `Tests/OpenSimBridgeTests/CapabilityPolicyTests.swift` | Test degrade | 6 |
| `docs/compatibility.md` | Ma trận và hành vi suy giảm | 6 |
| `.github/workflows/ci.yml` | Unit/lint trên GitHub-hosted macOS | 7 |
| `.swiftlint.yml` | Rule lint | 7 |
| `Scripts/ci/run-unit.sh` | Chạy unit + lint + docs check cục bộ | 7 |
| `.github/workflows/integration.yml` | Integration trên self-hosted | 8 |
| `.github/workflows/nightly.yml` | Nightly integration | 8 |
| `.github/workflows/release-gate.yml` | Gate trước phát hành | 8 |
| `Scripts/ci/run-integration.sh` | Build fixture, chạy integration | 8 |
| `App/OpenSim.entitlements` | Entitlements app | 9 |
| `Packaging/dev.opensim.daemon.plist` | LaunchAgent template | 9 |
| `Scripts/release/build-app.sh` | Build Release, ký app và helper | 9 |
| `Scripts/release/notarize.sh` | Submit, staple, verify | 9 |
| `Scripts/release/verify-signature.sh` | Kiểm tra entitlement, hardened runtime, Gatekeeper | 9 |
| `Scripts/release/package-dmg.sh` | Tạo DMG và tarball CLI | 10 |
| `Homebrew/Casks/opensim-app.rb` | Cask app (sinh từ script) | 10 |
| `Homebrew/Formula/opensim.rb` | Formula CLI/daemon (sinh từ script) | 10 |
| `Scripts/release/update-tap.sh` | Sinh và đẩy cask/formula sang tap | 10 |
| `Tests/Release/test-brew-install.sh` | Kiểm tra cài từ tap | 10 |
| `Sources/OpenSimCLI/Commands/SetupCommand.swift` | `opensim setup` | 11 |
| `Sources/OpenSimCLI/Commands/UninstallCommand.swift` | `opensim uninstall` | 11 |
| `Sources/OpenSimCLI/Commands/VersionCommand.swift` | `opensim --version` | 11 |
| `Sources/OpenSimDaemon/LaunchAgent/LaunchAgentManager.swift` | Mở rộng `uninstall(purge:)`, dùng lại manager của Plan 3 | 11 |
| `Sources/OpenSimCore/Security/OwnedDeviceRegistry.swift` | Registry device do OpenSim tạo, dùng cho `--purge` | 11 |
| `Sources/OpenSimCore/Support/OpenSimVersion.swift` | Version dùng chung, Plan 1 đã tạo; Plan 7 chỉ cập nhật khi bump | 11 |
| `Tests/OpenSimCLITests/UninstallCommandTests.swift` | Test registry và `--purge` | 11 |
| `Sources/OpenSimCLI/Commands/DocsCommand.swift` | `opensim docs` sinh tài liệu | 12 |
| `Sources/OpenSimCLI/Output/DocsRenderer.swift` | Render Markdown từ catalog | 12 |
| `Tests/OpenSimCLITests/DocsCommandTests.swift` | Golden test renderer | 12 |
| `docs/cli-reference.md` | Sinh từ catalog | 12 |
| `docs/mcp-tools-reference.md` | Sinh từ catalog | 12 |
| `README.md` | Cài đặt, cảnh báo private API | 12 |
| `docs/README.md` | Mục lục tài liệu | 12 |
| `docs/architecture.md` | Kiến trúc tầng và process | 12 |
| `docs/troubleshooting.md` | Lỗi thường gặp | 12 |
| `docs/security.md` | Mô hình bảo mật và private API | 12 |
| `docs/contributing.md` | Quy trình đóng góp | 12 |
| `docs/release-checklist.md` | Checklist release | 13 |
| `docs/release-rollback.md` | Rollback | 13 |
| `docs/known-issues-template.md` | Mẫu known issues | 13 |
| `CHANGELOG.md` | Lịch sử phát hành | 13 |
| `Scripts/release/changelog.sh` | Sinh changelog từ git log | 13 |
| `VERSION` | Version nguồn | 13 |
| `Tests/Release/run-release-gate.sh` | Chạy toàn bộ gate | 14 |
| `Tests/Release/test-clean-install.sh` | Cài trên máy sạch | 14 |
| `Tests/Release/test-notarization.sh` | Notarization + Gatekeeper | 14 |
| `Tests/Release/test-doctor.sh` | Doctor trên máy cài | 14 |
| `Tests/Release/test-e2e-agent.sh` | Kịch bản agent CLI + MCP | 14 |
| `Tests/Release/test-ui-smoke.sh` | XCUITest smoke | 14 |
| `Scripts/release/verify-versions.sh` | Đồng bộ version | 15 |
| `Scripts/release/publish.sh` | Tag, GitHub release, tap | 15 |

---

### Task 1: Ranh giới mạng của daemon

**Files:**
- Create: `Tests/SecurityTests/Support/DaemonHarness.swift`
- Create: `Tests/SecurityTests/NetworkBoundaryTests.swift`
- Create: `Scripts/security/check-loopback.sh`
- Modify: `Sources/OpenSimDaemon/Server/DaemonServer.swift` (gọi validator trước router)
- Modify: `Package.swift` (thêm test target `SecurityTests`)

**Interfaces:**
- Consumes: state file `~/Library/Application Support/OpenSim/daemon.json` với `port`, `token` (contract mục 6); endpoint `/v1/health`, `/v1/devices`.
- Produces: `DaemonHarness` với `start()`, `stop()`, `run(_:)`, `httpStatus(path:headers:)`, `state`; script `check-loopback.sh` in `OK loopback` kèm số port.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/SecurityTests/Support/DaemonHarness.swift`:

```swift
import Foundation
import XCTest

struct ProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

enum ProcessRunner {
    static func run(_ executable: String, _ arguments: [String], environment: [String: String]? = nil, stdin: Data? = nil) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let input = Pipe()
        process.standardInput = input
        try process.run()
        if let stdin {
            input.fileHandleForWriting.write(stdin)
        }
        input.fileHandleForWriting.closeFile()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }
}

final class DaemonHarness {
    let home: URL
    let binary: URL
    private(set) var state: [String: Any] = [:]

    var stateURL: URL {
        home.appendingPathComponent("Library/Application Support/OpenSim/daemon.json")
    }

    var auditURL: URL {
        home.appendingPathComponent("Library/Application Support/OpenSim/audit.jsonl")
    }

    var port: Int {
        state["port"] as? Int ?? 0
    }

    var token: String {
        state["token"] as? String ?? ""
    }

    init() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("opensim-security-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        binary = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/opensim")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            throw XCTSkip("Build the CLI first: swift build")
        }
    }

    func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = home.path
        env["OPENSIM_NO_LAUNCHAGENT"] = "1"
        return env
    }

    func run(_ arguments: [String]) throws -> ProcessResult {
        try ProcessRunner.run(binary.path, arguments, environment: environment(), stdin: Data())
    }

    func start() throws {
        _ = try run(["daemon", "start"])
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: stateURL.path),
               let data = try? Data(contentsOf: stateURL),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let port = object["port"] as? Int, port > 0 {
                state = object
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw XCTSkip("Daemon did not become ready")
    }

    func stop() {
        _ = try? run(["daemon", "stop"])
        try? FileManager.default.removeItem(at: home)
    }

    func httpStatus(path: String, headers: [String]) throws -> Int {
        var arguments = ["-s", "-o", "/dev/null", "-w", "%{http_code}", "-X", "GET"]
        for header in headers {
            arguments.append(contentsOf: ["-H", header])
        }
        arguments.append("http://127.0.0.1:\(port)\(path)")
        let result = try ProcessRunner.run("/usr/bin/curl", arguments)
        return Int(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    func authHeader() -> String {
        "Authorization: Bearer \(token)"
    }
}
```

Create `Tests/SecurityTests/NetworkBoundaryTests.swift`:

```swift
import XCTest

final class NetworkBoundaryTests: XCTestCase {
    private var harness: DaemonHarness!

    override func setUpWithError() throws {
        harness = try DaemonHarness()
        try harness.start()
    }

    override func tearDownWithError() throws {
        harness.stop()
        harness = nil
    }

    func testHealthAllowsLoopbackHost() throws {
        XCTAssertEqual(try harness.httpStatus(path: "/v1/health", headers: ["Host: 127.0.0.1:\(harness.port)"]), 200)
    }

    func testHealthRejectsForeignHost() throws {
        XCTAssertEqual(try harness.httpStatus(path: "/v1/health", headers: ["Host: evil.example"]), 403)
    }

    func testHealthRejectsForeignOrigin() throws {
        XCTAssertEqual(
            try harness.httpStatus(
                path: "/v1/health",
                headers: ["Host: 127.0.0.1:\(harness.port)", "Origin: https://evil.example"]
            ),
            403
        )
    }

    func testDevicesRequiresBearerToken() throws {
        XCTAssertEqual(try harness.httpStatus(path: "/v1/devices", headers: []), 401)
    }

    func testDevicesRejectsWrongToken() throws {
        XCTAssertEqual(
            try harness.httpStatus(
                path: "/v1/devices",
                headers: ["Authorization: Bearer not-the-token"]
            ),
            401
        )
    }

    func testDevicesAcceptsValidToken() throws {
        XCTAssertEqual(
            try harness.httpStatus(path: "/v1/devices", headers: [harness.authHeader()]),
            200
        )
    }

    func testListenerIsLoopbackOnly() throws {
        let output = try ProcessRunner.run(
            "/usr/sbin/lsof",
            ["-nP", "-iTCP:\(harness.port)", "-sTCP:LISTEN"]
        ).stdout
        XCTAssertTrue(output.contains("127.0.0.1:\(harness.port)"), output)
        XCTAssertFalse(output.contains("*:\(harness.port)"), output)
        XCTAssertFalse(output.contains("0.0.0.0:\(harness.port)"), output)
    }
}
```

Create `Scripts/security/check-loopback.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
STATE="$HOME/Library/Application Support/OpenSim/daemon.json"
PORT="$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["port"])' "$STATE")"
OUT="$(/usr/sbin/lsof -nP -iTCP:"$PORT" -sTCP:LISTEN)"
print -r -- "$OUT"
if print -r -- "$OUT" | grep -qE '\*:|0\.0\.0\.0:|\[::\]:'; then
  print -u2 "daemon is not loopback-only"
  exit 1
fi
if ! print -r -- "$OUT" | grep -q "127.0.0.1:$PORT"; then
  print -u2 "loopback listener missing"
  exit 1
fi
print "OK loopback $PORT"
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift build --product opensim
swift test --filter NetworkBoundaryTests
```

Expected: `ProcessResult` chưa được dùng bởi module test nên compile fail, hoặc test `Host`/`Origin` trả `200` thay vì `403`.

- [ ] **Step 3: Thêm validator và gọi từ server**

Create `Sources/OpenSimDaemon/Server/RequestValidator.swift`:

```swift
import Foundation
import OpenSimCore

public struct RequestValidator: Sendable {
    public let allowedHosts: Set<String>
    public let allowedOrigins: Set<String>

    public init(port: UInt16) {
        let hosts = ["127.0.0.1:\(port)", "localhost:\(port)"]
        let origins = ["http://127.0.0.1:\(port)", "http://localhost:\(port)"]
        allowedHosts = Set(hosts)
        allowedOrigins = Set(origins)
    }

    public func validate(host: String?, origin: String?) throws {
        guard let host, allowedHosts.contains(host.lowercased()) else {
            throw OpenSimError(
                code: "permission_denied",
                message: "Host is not allowed",
                details: ["host": host ?? "missing"],
                recovery: "Connect through 127.0.0.1 or localhost",
                retryable: false
            )
        }
        if let origin, !allowedOrigins.contains(origin.lowercased()) {
            throw OpenSimError(
                code: "permission_denied",
                message: "Origin is not allowed",
                details: ["origin": origin],
                recovery: "Use the loopback Origin of the daemon",
                retryable: false
            )
        }
    }
}
```

Trong `Sources/OpenSimDaemon/Server/DaemonServer.swift`, tạo validator một lần khi server start và gọi trước khi route:

```swift
let validator = RequestValidator(port: boundPort)
try validator.validate(
    host: request.headers[.host],
    origin: request.headers[.origin]
)
```

Nếu `OpenSimError` chưa có public initializer, thêm extension sau vào `Sources/OpenSimCore/Errors/OpenSimError+Convenience.swift`:

```swift
import Foundation

public extension OpenSimError {
    init(
        code: String,
        message: String,
        details: [String: String] = [:],
        recovery: String? = nil,
        retryable: Bool = false
    ) {
        self.code = code
        self.message = message
        self.details = details
        self.recovery = recovery
        self.retryable = retryable
    }
}
```

Thêm test target vào `Package.swift`:

```swift
.testTarget(
    name: "SecurityTests",
    dependencies: ["OpenSimCore", "OpenSimBridge", "OpenSimDaemon"],
    path: "Tests/SecurityTests"
),
```

- [ ] **Step 4: Chạy test để thấy pass**

Run:

```bash
chmod +x Scripts/security/check-loopback.sh
swift test --filter NetworkBoundaryTests
swift build --product opensim
export OPENSIM_TEST_HOME="$(mktemp -d)"
HOME="$OPENSIM_TEST_HOME" OPENSIM_NO_LAUNCHAGENT=1 .build/debug/opensim daemon start
HOME="$OPENSIM_TEST_HOME" Scripts/security/check-loopback.sh
HOME="$OPENSIM_TEST_HOME" .build/debug/opensim daemon stop
```

Expected: `Executed 7 tests, with 0 failures`; script in `OK loopback` kèm số port.

- [ ] **Step 5: Commit**

```bash
git add Tests/SecurityTests Scripts/security/check-loopback.sh Sources/OpenSimDaemon/Server Sources/OpenSimCore/Errors/OpenSimError+Convenience.swift
git commit -m "test(security): enforce loopback and host validation"
```

---

### Task 2: Quyền token và state file

**Files:**
- Create: `Tests/SecurityTests/TokenFileSecurityTests.swift`
- Create: `Scripts/security/check-token-permissions.sh`

**Interfaces:**
- Consumes: `DaemonHarness`, `stateURL` từ Task 1.
- Produces: test khẳng định `0600` file, `0700` thư mục, token decode đúng 32 byte, token đổi sau restart, token cũ bị từ chối.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/SecurityTests/TokenFileSecurityTests.swift`:

```swift
import XCTest

final class TokenFileSecurityTests: XCTestCase {
    private var harness: DaemonHarness!

    override func setUpWithError() throws {
        harness = try DaemonHarness()
        try harness.start()
    }

    override func tearDownWithError() throws {
        harness.stop()
        harness = nil
    }

    func testStateFilePermissions() throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: harness.stateURL.path)
        let fileMode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(fileMode, 0o600)

        let directory = harness.stateURL.deletingLastPathComponent()
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        let directoryMode = (directoryAttributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(directoryMode, 0o700)
    }

    func testTokenIs32RandomBytes() throws {
        let data = try XCTUnwrap(decodeBase64URL(harness.token))
        XCTAssertEqual(data.count, 32)
        XCTAssertNotEqual(harness.token, String(repeating: "A", count: harness.token.count))
    }

    func testTokenRotatesOnRestart() throws {
        let oldToken = harness.token
        let restart = try harness.run(["daemon", "restart"])
        XCTAssertEqual(restart.status, 0, restart.stderr)

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let data = try? Data(contentsOf: harness.stateURL),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let newToken = object["token"] as? String,
               newToken != oldToken {
                harness.state = object
                XCTAssertEqual(
                    try harness.httpStatus(path: "/v1/devices", headers: ["Authorization: Bearer \(oldToken)"]),
                    401
                )
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTFail("Token did not rotate after restart")
    }

    private func decodeBase64URL(_ value: String) -> Data? {
        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while normalized.count % 4 != 0 {
            normalized.append("=")
        }
        return Data(base64Encoded: normalized)
    }
}
```

Create `Scripts/security/check-token-permissions.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
STATE="$HOME/Library/Application Support/OpenSim/daemon.json"
DIR="$(dirname "$STATE")"
FILE_MODE="$(stat -f '%Lp' "$STATE")"
DIR_MODE="$(stat -f '%Lp' "$DIR")"
if [[ "$FILE_MODE" != "600" ]]; then
  print -u2 "state file mode is $FILE_MODE, expected 600"
  exit 1
fi
if [[ "$DIR_MODE" != "700" ]]; then
  print -u2 "state directory mode is $DIR_MODE, expected 700"
  exit 1
fi
print "OK token permissions"
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter TokenFileSecurityTests
```

Expected: FAIL nếu daemon ghi state bằng default umask (`644`) hoặc thư mục `755`.

- [ ] **Step 3: Sửa writer**

Trong nơi daemon ghi state (Plan 3), set quyền sau khi ghi atomically:

```swift
try FileManager.default.setAttributes(
    [.posixPermissions: 0o600],
    ofItemAtPath: stateURL.path
)
try FileManager.default.setAttributes(
    [.posixPermissions: 0o700],
    ofItemAtPath: stateURL.deletingLastPathComponent().path
)
```

Set thư mục `0700` ngay sau `createDirectory`:

```swift
try FileManager.default.createDirectory(
    at: stateDirectory,
    withIntermediateDirectories: true,
    attributes: [.posixPermissions: 0o700]
)
try FileManager.default.setAttributes(
    [.posixPermissions: 0o700],
    ofItemAtPath: stateDirectory.path
)
```

- [ ] **Step 4: Chạy test để thấy pass**

Run:

```bash
chmod +x Scripts/security/check-token-permissions.sh
swift test --filter TokenFileSecurityTests
export OPENSIM_TEST_HOME="$(mktemp -d)"
HOME="$OPENSIM_TEST_HOME" OPENSIM_NO_LAUNCHAGENT=1 .build/debug/opensim daemon start
HOME="$OPENSIM_TEST_HOME" Scripts/security/check-token-permissions.sh
HOME="$OPENSIM_TEST_HOME" .build/debug/opensim daemon stop
```

Expected: `Executed 3 tests, with 0 failures`; `OK token permissions`.

- [ ] **Step 5: Commit**

```bash
git add Tests/SecurityTests/TokenFileSecurityTests.swift Scripts/security/check-token-permissions.sh Sources/OpenSimDaemon
git commit -m "test(security): enforce token and state file permissions"
```

---

### Task 3: Path allowlist và developer dir

**Files:**
- Create: `Sources/OpenSimCore/Security/PathAllowlist.swift`
- Create: `Sources/OpenSimBridge/Private/DeveloperDirPolicy.swift`
- Create: `Tests/SecurityTests/PathAllowlistTests.swift`
- Create: `Tests/SecurityTests/DeveloperDirPolicyTests.swift`
- Create: `Scripts/security/check-no-shell-strings.sh`

**Interfaces:**
- Produces: `PathAllowlist(roots:)` với `validate(_:mustExist:) throws -> URL`; `DeveloperDirPolicy` với `validate(_:) throws -> URL`; script trả `OK no shell strings`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/SecurityTests/PathAllowlistTests.swift`:

```swift
import Foundation
import XCTest
@testable import OpenSimCore

final class PathAllowlistTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("opensim-path-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAcceptsPathInsideRoot() throws {
        let file = root.appendingPathComponent("Build/MyApp.app")
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        let validated = try PathAllowlist(roots: [root]).validate(file)
        XCTAssertEqual(validated.standardizedFileURL.path, file.standardizedFileURL.path)
    }

    func testRejectsParentTraversal() throws {
        let outside = root.deletingLastPathComponent().appendingPathComponent("outside.txt")
        try Data("x".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let candidate = root.appendingPathComponent("../outside.txt")
        XCTAssertThrowsError(try PathAllowlist(roots: [root]).validate(candidate)) { error in
            XCTAssertEqual((error as? OpenSimError)?.code, "permission_denied")
        }
    }

    func testRejectsSymlinkEscape() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("opensim-outside-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let link = root.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertThrowsError(try PathAllowlist(roots: [root]).validate(link)) { error in
            XCTAssertEqual((error as? OpenSimError)?.code, "permission_denied")
        }
    }

    func testRejectsMissingPathWhenRequired() throws {
        let missing = root.appendingPathComponent("missing.app")
        XCTAssertThrowsError(try PathAllowlist(roots: [root]).validate(missing, mustExist: true)) { error in
            XCTAssertEqual((error as? OpenSimError)?.code, "invalid_argument")
        }
    }

    func testSiblingWithSharedPrefixIsRejected() throws {
        let sibling = root.deletingLastPathComponent()
            .appendingPathComponent(root.lastPathComponent + "-evil")
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: sibling) }
        XCTAssertThrowsError(try PathAllowlist(roots: [root]).validate(sibling)) { error in
            XCTAssertEqual((error as? OpenSimError)?.code, "permission_denied")
        }
    }
}
```

Create `Tests/SecurityTests/DeveloperDirPolicyTests.swift`:

```swift
import Foundation
import XCTest
@testable import OpenSimBridge

final class DeveloperDirPolicyTests: XCTestCase {
    private func policy(existing: Set<String> = []) -> DeveloperDirPolicy {
        DeveloperDirPolicy(exists: { existing.contains($0) })
    }

    func testAcceptsApplicationsXcode() throws {
        let path = "/Applications/Xcode.app/Contents/Developer"
        let result = try policy(existing: [path, "/Applications/Xcode.app/Contents/SharedFrameworks/SimulatorKit.framework"]).validate(path)
        XCTAssertEqual(result.path, path)
    }

    func testRejectsTemporaryDeveloperDir() throws {
        XCTAssertThrowsError(try policy().validate("/tmp/Xcode.app/Contents/Developer")) { error in
            XCTAssertEqual((error as? OpenSimError)?.code, "permission_denied")
        }
    }

    func testRejectsTraversalIntoTemporary() throws {
        XCTAssertThrowsError(try policy().validate("/Applications/../tmp/Xcode.app/Contents/Developer")) { error in
            XCTAssertEqual((error as? OpenSimError)?.code, "permission_denied")
        }
    }

    func testRejectsCommandLineToolsWithoutSimulatorKit() throws {
        let path = "/Library/Developer/CommandLineTools"
        XCTAssertThrowsError(try policy(existing: [path]).validate(path)) { error in
            XCTAssertEqual((error as? OpenSimError)?.code, "unsupported_xcode")
        }
    }
}
```

Create `Scripts/security/check-no-shell-strings.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
MATCHES="$(rg -n --glob '*.swift' \
  -e '"/bin/(sh|bash|zsh)"' \
  -e "'/bin/(sh|bash|zsh)'" \
  -e 'launchPath\s*=\s*"/bin/(sh|bash|zsh)"' \
  -e 'executableURL\s*=.*(sh|bash|zsh).*-c' \
  "$ROOT/Sources" || true)"
if [[ -n "$MATCHES" ]]; then
  print -r -- "$MATCHES"
  print -u2 "shell string usage is forbidden; pass an argument array instead"
  exit 1
fi
print "OK no shell strings"
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter PathAllowlistTests
swift test --filter DeveloperDirPolicyTests
chmod +x Scripts/security/check-no-shell-strings.sh
Scripts/security/check-no-shell-strings.sh
```

Expected: FAIL vì `PathAllowlist` và `DeveloperDirPolicy` chưa tồn tại; script có thể PASS trước khi implement, đây là check bảo vệ hồi quy.

- [ ] **Step 3: Implement**

Create `Sources/OpenSimCore/Security/PathAllowlist.swift`:

```swift
import Foundation

public struct PathAllowlist: Sendable {
    public let roots: [URL]

    public init(roots: [URL]) {
        self.roots = roots.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
    }

    public func validate(_ candidate: URL, mustExist: Bool = true) throws -> URL {
        let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath()
        if mustExist {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory) else {
                throw OpenSimError(
                    code: "invalid_argument",
                    message: "Path does not exist",
                    details: ["path": resolved.path],
                    recovery: "Pass an existing path",
                    retryable: false
                )
            }
        }
        let isAllowed = roots.contains { root in
            resolved.path == root.path || resolved.path.hasPrefix(root.path + "/")
        }
        guard isAllowed else {
            throw OpenSimError(
                code: "permission_denied",
                message: "Path is outside allowed roots",
                details: ["path": resolved.path],
                recovery: "Choose a path under an allowed root",
                retryable: false
            )
        }
        return resolved
    }
}
```

Create `Sources/OpenSimBridge/Private/DeveloperDirPolicy.swift`:

```swift
import Foundation
import OpenSimCore

public struct DeveloperDirPolicy: Sendable {
    public static let allowedRoots = ["/Applications", "/Library/Developer"]

    private let exists: @Sendable (String) -> Bool

    public init(exists: @escaping @Sendable (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) {
        self.exists = exists
    }

    public func validate(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let isAllowed = Self.allowedRoots.contains { root in
            url.path == root || url.path.hasPrefix(root + "/")
        }
        guard isAllowed else {
            throw OpenSimError(
                code: "permission_denied",
                message: "Developer directory is outside allowed roots",
                details: ["path": url.path],
                recovery: "Point xcode-select to /Applications/Xcode.app/Contents/Developer",
                retryable: false
            )
        }
        let simulatorKit = url
            .deletingLastPathComponent()
            .appendingPathComponent("SharedFrameworks/SimulatorKit.framework")
        guard exists(url.path), exists(simulatorKit.path) else {
            throw OpenSimError(
                code: "unsupported_xcode",
                message: "Full Xcode with SimulatorKit is required",
                details: ["path": url.path],
                recovery: "Install Xcode 27.1 and run xcode-select -s",
                retryable: false
            )
        }
        return url
    }
}
```

Gọi `DeveloperDirPolicy().validate(developerDir)` trong loader trước `dlopen`; không nhận path từ client.

Dùng `PathAllowlist` tại các điểm nhận path từ client: `app install`, `app data import`, `runtime install` với root lần lượt là thư mục build của người dùng, thư mục export do người dùng chọn, và `~/Downloads`; mọi path phải resolve symlink trước khi so khớp.

- [ ] **Step 4: Chạy test để thấy pass**

Run:

```bash
swift test --filter PathAllowlistTests
swift test --filter DeveloperDirPolicyTests
Scripts/security/check-no-shell-strings.sh
```

Expected: `Executed 5 tests, with 0 failures`; `Executed 4 tests, with 0 failures`; `OK no shell strings`.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenSimCore/Security Sources/OpenSimBridge/Private Tests/SecurityTests Scripts/security/check-no-shell-strings.sh
git commit -m "feat(security): validate paths and developer directory"
```

---

### Task 4: Xác nhận phá huỷ và audit

**Files:**
- Create: `Tests/SecurityTests/DestructiveOperationTests.swift`
- Create: `Scripts/security/check-audit-coverage.sh`

**Interfaces:**
- Consumes: `DaemonHarness.run`, CLI `device create`, `device delete`, `--yes`, `--json`.
- Produces: test exit code `7` khi thiếu `--yes`, exit `0` khi có, audit JSONL có `action`, `actor`, `result`, `durationMs`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/SecurityTests/DestructiveOperationTests.swift`:

```swift
import XCTest

final class DestructiveOperationTests: XCTestCase {
    private var harness: DaemonHarness!
    private var udid: String!

    override func setUpWithError() throws {
        harness = try DaemonHarness()
        try harness.start()
        let deviceType = try firstIPhoneDeviceType()
        let created = try harness.run([
            "device", "create", "OpenSim Security Delete",
            "--type", deviceType,
            "--json"
        ])
        XCTAssertEqual(created.status, 0, created.stderr)
        let object = try JSONSerialization.jsonObject(with: Data(created.stdout.utf8)) as! [String: Any]
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        udid = try XCTUnwrap(data["id"] as? String)
    }

    override func tearDownWithError() throws {
        if let udid {
            _ = try? harness.run(["device", "delete", "--device", udid, "--yes", "--json"])
        }
        harness.stop()
        harness = nil
    }

    func testDeleteWithoutConfirmationExitsWithSeven() throws {
        let result = try harness.run(["device", "delete", udid, "--json"])
        XCTAssertEqual(result.status, 7)
        let object = try JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as! [String: Any]
        let error = try XCTUnwrap(object["error"] as? [String: Any])
        XCTAssertEqual(error["code"] as? String, "confirmation_required")
    }

    func testDeleteWithConfirmationWritesAudit() throws {
        let result = try harness.run(["device", "delete", udid, "--yes", "--json"])
        XCTAssertEqual(result.status, 0, result.stderr)
        udid = nil

        let audit = try String(contentsOf: harness.auditURL, encoding: .utf8)
        let line = try XCTUnwrap(audit.split(separator: "\n").last)
        let event = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
        XCTAssertEqual(event["action"] as? String, "device.delete")
        XCTAssertNotNil(event["actor"])
        XCTAssertTrue(["success", "ok"].contains(event["result"] as? String))
        XCTAssertNotNil(event["durationMs"])
    }

    private func firstIPhoneDeviceType() throws -> String {
        let result = try ProcessRunner.run("/usr/bin/xcrun", ["simctl", "list", "devicetypes", "-j"])
        let object = try JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as! [String: Any]
        let types = try XCTUnwrap(object["devicetypes"] as? [[String: Any]])
        let match = try XCTUnwrap(types.first { ($0["name"] as? String)?.hasPrefix("iPhone") == true })
        return try XCTUnwrap(match["identifier"] as? String)
    }
}
```

Create `Scripts/security/check-audit-coverage.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
AUDIT="$HOME/Library/Application Support/OpenSim/audit.jsonl"
if [[ ! -s "$AUDIT" ]]; then
  print -u2 "audit log missing: $AUDIT"
  exit 1
fi
COUNT="$(wc -l < "$AUDIT" | tr -d ' ')"
if [[ "$COUNT" -lt 1 ]]; then
  print -u2 "audit log is empty"
  exit 1
fi
if ! tail -n 20 "$AUDIT" | jq -e -s 'all(.[]; has("action") and has("actor") and has("result") and has("durationMs"))' >/dev/null; then
  print -u2 "audit event missing required fields"
  exit 1
fi
print "OK audit coverage $COUNT"
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
chmod +x Scripts/security/check-audit-coverage.sh
swift test --filter DestructiveOperationTests
```

Expected: FAIL vì `device delete` không có `--yes` vẫn chạy hoặc trả exit code khác `7`.

- [ ] **Step 3: Siết confirm ở CLI và daemon**

Trong command `device delete` (`Sources/OpenSimCLI/Commands/DeviceCommand.swift`), từ chối trước khi gọi daemon khi thiếu `--yes` và stdin không phải TTY:

```swift
guard yes || isatty(STDIN_FILENO) == 1 else {
    throw OpenSimError(
        code: "confirmation_required",
        message: "device delete requires --yes in non-interactive mode",
        details: ["operation": "device.delete"],
        recovery: "Re-run with --yes after verifying the target device",
        retryable: false
    )
}
```

Trong daemon, mọi operation có `destructive == true` phải kiểm tra `confirm == "true"` trước khi thực thi:

```swift
if operation.destructive, parameters["confirm"] != "true" {
    throw OpenSimError(
        code: "confirmation_required",
        message: "Destructive operation requires confirm",
        details: ["operation": operation.mcpName],
        recovery: "Send confirm=true or a valid plan token",
        retryable: false
    )
}
```

Ghi audit sau khi operation kết thúc, kể cả khi lỗi, với `actor`, `action`, `target`, `result`, `durationMs`.

- [ ] **Step 4: Chạy test để thấy pass**

Run:

```bash
swift test --filter DestructiveOperationTests
export OPENSIM_TEST_HOME="$(mktemp -d)"
HOME="$OPENSIM_TEST_HOME" OPENSIM_NO_LAUNCHAGENT=1 .build/debug/opensim daemon start
HOME="$OPENSIM_TEST_HOME" .build/debug/opensim device create "OpenSim Audit" --type "iPhone 17" --json > /tmp/audit-create.json
UDID="$(jq -r '.data.id' /tmp/audit-create.json)"
HOME="$OPENSIM_TEST_HOME" .build/debug/opensim device delete --device "$UDID" --yes --json > /dev/null
HOME="$OPENSIM_TEST_HOME" Scripts/security/check-audit-coverage.sh
HOME="$OPENSIM_TEST_HOME" .build/debug/opensim daemon stop
```

Expected: `Executed 2 tests, with 0 failures`; `OK audit coverage` kèm số event.

- [ ] **Step 5: Commit**

```bash
git add Tests/SecurityTests/DestructiveOperationTests.swift Scripts/security/check-audit-coverage.sh Sources/OpenSimCLI Sources/OpenSimDaemon
git commit -m "test(security): require confirmation and audit destructive operations"
```

---

### Task 5: Checklist security review và chặn telemetry

**Files:**
- Create: `docs/security-review-checklist.md`
- Create: `Scripts/security/check-no-telemetry.sh`
- Create: `Tests/SecurityTests/Fixtures/telemetry-offender/Telemetry.swift`
- Create: `Tests/Release/test-security-scripts.sh`

**Interfaces:**
- Consumes: các script `Scripts/security/check-loopback.sh`, `check-token-permissions.sh`, `check-no-shell-strings.sh`, `check-audit-coverage.sh` từ Task 1-4.
- Produces: checklist có 10 mục với lệnh bằng chứng; script telemetry fail khi thấy upload; test script xác nhận script bắt được offender và repo sạch.

- [ ] **Step 1: Viết fixture và test thất bại**

Create `Tests/SecurityTests/Fixtures/telemetry-offender/Telemetry.swift`:

```swift
import Foundation

enum TelemetryOffender {
    static func upload(payload: Data) {
        var request = URLRequest(url: URL(string: "https://analytics.example.com/collect")!)
        request.httpMethod = "POST"
        request.httpBody = payload
        URLSession.shared.dataTask(with: request).resume()
    }
}
```

Create `Tests/Release/test-security-scripts.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
OFFENDER="$ROOT/Tests/SecurityTests/Fixtures/telemetry-offender"

if "$ROOT/Scripts/security/check-no-telemetry.sh" "$OFFENDER"; then
  print -u2 "telemetry scanner missed the offender fixture"
  exit 1
fi

"$ROOT/Scripts/security/check-no-telemetry.sh" "$ROOT"
print "OK telemetry scanner"
```

Run:

```bash
chmod +x Tests/Release/test-security-scripts.sh
Tests/Release/test-security-scripts.sh
```

Expected: FAIL vì `Scripts/security/check-no-telemetry.sh` chưa tồn tại.

- [ ] **Step 2: Viết scanner**

Create `Scripts/security/check-no-telemetry.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${1:-${0:A:h:h:h}}"
SCAN_DIRS=()
for candidate in \
  "$ROOT/Sources/OpenSimCore" \
  "$ROOT/Sources/OpenSimBridge" \
  "$ROOT/Sources/OpenSimDaemon" \
  "$ROOT/App/Sources"; do
  if [[ -d "$candidate" ]]; then
    SCAN_DIRS+=("$candidate")
  fi
done
if [[ "${#SCAN_DIRS[@]}" -eq 0 ]]; then
  print -u2 "no source directories found under $ROOT"
  exit 1
fi
MATCHES="$(rg -n --glob '*.swift' \
  -e 'https?://' \
  -e 'Sentry' \
  -e 'Firebase' \
  -e 'Mixpanel' \
  -e 'Amplitude' \
  "${SCAN_DIRS[@]}" | rg -v 'https?://(127\.0\.0\.1|localhost)' || true)"
if [[ -n "$MATCHES" ]]; then
  print -r -- "$MATCHES"
  print -u2 "external network or telemetry usage found in a local-only module"
  exit 1
fi
print "OK no telemetry"
```

- [ ] **Step 3: Viết checklist**

Create `docs/security-review-checklist.md`:

```markdown
# OpenSim Security Review Checklist

- Ngày review: ghi ngày chạy thực tế
- Người review: ghi tên người ký
- Version: đọc từ `VERSION`
- Runner: macOS 27, Xcode 27.1

## Bảng kiểm

Đặt `export OPENSIM_TEST_HOME="$(mktemp -d)"` trước khi chạy các lệnh có `HOME="$OPENSIM_TEST_HOME"`.

| Mục | Bằng chứng | Điều kiện pass |
|---|---|---|
| Daemon chỉ bind loopback | `HOME="$OPENSIM_TEST_HOME" opensim daemon start && HOME="$OPENSIM_TEST_HOME" Scripts/security/check-loopback.sh` | In `OK loopback` kèm số port |
| Token 32 byte, file `0600`, thư mục `0700` | `HOME="$OPENSIM_TEST_HOME" Scripts/security/check-token-permissions.sh` | In `OK token permissions` |
| Host lạ bị từ chối | `swift test --filter NetworkBoundaryTests` | 7 test pass, `Host: evil.example` trả 403 |
| Origin lạ bị từ chối | `swift test --filter NetworkBoundaryTests` | `Origin: https://evil.example` trả 403 |
| Không dùng shell string | `Scripts/security/check-no-shell-strings.sh` | In `OK no shell strings` |
| Path allowlist và symlink escape | `swift test --filter PathAllowlistTests` | 5 test pass |
| Developer dir chỉ dưới root cho phép | `swift test --filter DeveloperDirPolicyTests` | 4 test pass |
| Destructive cần confirm | `swift test --filter DestructiveOperationTests` | Exit 7 khi thiếu `--yes`, audit có `device.delete` |
| Audit đủ trường | `HOME="$OPENSIM_TEST_HOME" Scripts/security/check-audit-coverage.sh` | In `OK audit coverage` kèm số event |
| Không telemetry | `Scripts/security/check-no-telemetry.sh` | In `OK no telemetry` |
| Private framework path không nhận từ client | `swift test --filter DeveloperDirPolicyTests` | Path `/tmp` và traversal bị từ chối |
| Library validation | `Scripts/release/verify-signature.sh` sau Task 9 | Entitlement `disable-library-validation` là `false` hoặc có biên bản chấp thuận |

## Ký

- [ ] Owner xác nhận không có telemetry trong binary: `strings build/release/OpenSim.app/Contents/MacOS/OpenSim | rg -i 'analytics|sentry|firebase'` không có kết quả.
- [ ] Owner xác nhận cảnh báo private API trong `README.md` và `docs/security.md`.
- [ ] Reviewer xác nhận không có endpoint ngoài loopback trong `Sources/` và `App/Sources/`.
```

- [ ] **Step 4: Chạy test để thấy pass**

Run:

```bash
chmod +x Scripts/security/check-no-telemetry.sh
Tests/Release/test-security-scripts.sh
Scripts/security/check-no-shell-strings.sh
```

Expected: offender fixture làm script exit `1`; repo sạch in `OK no telemetry`; test in `OK telemetry scanner`; `OK no shell strings`.

- [ ] **Step 5: Commit**

```bash
git add docs/security-review-checklist.md Scripts/security/check-no-telemetry.sh Tests/SecurityTests/Fixtures Tests/Release/test-security-scripts.sh
git commit -m "docs(security): add review checklist and telemetry guard"
```

---

### Task 6: Ma trận tương thích và suy giảm capability

**Files:**
- Create: `Sources/OpenSimCore/Compatibility/CompatibilityMatrix.swift`
- Create: `Sources/OpenSimBridge/Capabilities/CapabilityPolicy.swift`
- Create: `Tests/OpenSimCoreTests/CompatibilityMatrixTests.swift`
- Create: `Tests/OpenSimBridgeTests/CapabilityPolicyTests.swift`
- Create: `Tests/SecurityTests/DoctorCompatibilityTests.swift`
- Create: `docs/compatibility.md`
- Modify: `Sources/OpenSimCLI/Commands/DoctorCommand.swift`

**Interfaces:**
- Consumes: `BridgeCapabilities`, `Capability` từ contract mục 5; `OpenSimError` từ Core.
- Produces: `CompatibilityMode` (`supported`, `bestEffort`, `unknown`, `unsupported`); `CompatibilityMatrix.release`; `CompatibilityMatrix.mode(forXcodeVersion:)`; `CapabilityPolicy.degrade(_:compatibility:)`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimCoreTests/CompatibilityMatrixTests.swift`:

```swift
import XCTest
@testable import OpenSimCore

final class CompatibilityMatrixTests: XCTestCase {
    func testXcode271IsSupported() {
        XCTAssertEqual(CompatibilityMatrix.release.mode(forXcodeVersion: "27.1"), .supported)
        XCTAssertEqual(CompatibilityMatrix.release.mode(forXcodeVersion: "27.1.1"), .supported)
    }

    func testXcode270IsBestEffort() {
        XCTAssertEqual(CompatibilityMatrix.release.mode(forXcodeVersion: "27.0"), .bestEffort)
    }

    func testUnknownPatchOf27IsUnknown() {
        XCTAssertEqual(CompatibilityMatrix.release.mode(forXcodeVersion: "27.2"), .unknown)
    }

    func testOlderMajorIsUnsupported() {
        XCTAssertEqual(CompatibilityMatrix.release.mode(forXcodeVersion: "26.4"), .unsupported)
    }

    func testMatrixPinsIOSTwentySevenRuntime() {
        let entry = CompatibilityMatrix.release.entries.first { $0.xcodeVersion == "27.1" }
        XCTAssertEqual(entry?.testedRuntimes, ["iOS 27.0", "watchOS 27.0", "tvOS 27.0"])
    }
}
```

Create `Tests/OpenSimBridgeTests/CapabilityPolicyTests.swift`:

```swift
import XCTest
@testable import OpenSimBridge

final class CapabilityPolicyTests: XCTestCase {
    private var allAvailable: BridgeCapabilities {
        BridgeCapabilities(
            render: .available,
            hid: .available,
            accessibility: .available,
            screenshot: .available,
            video: .available,
            watch: .available,
            tv: .available
        )
    }

    func testSupportedLeavesCapabilitiesUntouched() {
        let result = CapabilityPolicy.degrade(allAvailable, compatibility: .supported)
        XCTAssertEqual(result.render, .available)
        XCTAssertEqual(result.accessibility, .available)
    }

    func testBestEffortLeavesCapabilitiesUntouched() {
        let result = CapabilityPolicy.degrade(allAvailable, compatibility: .bestEffort)
        XCTAssertEqual(result.hid, .available)
        XCTAssertEqual(result.tv, .available)
    }

    func testUnknownDisablesUncertainPrivateCapabilities() {
        let result = CapabilityPolicy.degrade(allAvailable, compatibility: .unknown)
        XCTAssertEqual(result.render, .unavailable)
        XCTAssertEqual(result.hid, .unavailable)
        XCTAssertEqual(result.accessibility, .unavailable)
        XCTAssertEqual(result.screenshot, .available)
        XCTAssertEqual(result.video, .available)
        XCTAssertEqual(result.watch, .available)
        XCTAssertEqual(result.tv, .available)
    }

    func testUnsupportedDisablesEverything() {
        let result = CapabilityPolicy.degrade(allAvailable, compatibility: .unsupported)
        XCTAssertEqual(result.render, .unavailable)
        XCTAssertEqual(result.hid, .unavailable)
        XCTAssertEqual(result.accessibility, .unavailable)
        XCTAssertEqual(result.screenshot, .unavailable)
        XCTAssertEqual(result.video, .unavailable)
        XCTAssertEqual(result.watch, .unavailable)
        XCTAssertEqual(result.tv, .unavailable)
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter CompatibilityMatrixTests
swift test --filter CapabilityPolicyTests
```

Expected: FAIL vì `CompatibilityMatrix`, `CompatibilityMode`, `CapabilityPolicy` chưa tồn tại.

- [ ] **Step 3: Implement**

Create `Sources/OpenSimCore/Compatibility/CompatibilityMatrix.swift`:

```swift
import Foundation

public enum CompatibilityMode: String, Codable, Sendable {
    case supported
    case bestEffort
    case unknown
    case unsupported
}

public struct CompatibilityMatrix: Codable, Sendable {
    public struct Entry: Codable, Sendable, Equatable {
        public var xcodeVersion: String
        public var mode: CompatibilityMode
        public var testedRuntimes: [String]

        public init(xcodeVersion: String, mode: CompatibilityMode, testedRuntimes: [String]) {
            self.xcodeVersion = xcodeVersion
            self.mode = mode
            self.testedRuntimes = testedRuntimes
        }
    }

    public var entries: [Entry]

    public init(entries: [Entry]) {
        self.entries = entries
    }

    public static let release = CompatibilityMatrix(entries: [
        Entry(
            xcodeVersion: "27.1",
            mode: .supported,
            testedRuntimes: ["iOS 27.0", "watchOS 27.0", "tvOS 27.0"]
        ),
        Entry(
            xcodeVersion: "27.0",
            mode: .bestEffort,
            testedRuntimes: ["iOS 27.0"]
        )
    ])

    public func mode(forXcodeVersion version: String) -> CompatibilityMode {
        let normalized = Self.majorMinor(version)
        if let entry = entries.first(where: { $0.xcodeVersion == normalized }) {
            return entry.mode
        }
        guard let major = Int(normalized.split(separator: ".").first ?? "") else {
            return .unknown
        }
        return major == 27 ? .unknown : .unsupported
    }

    private static func majorMinor(_ version: String) -> String {
        let parts = version.split(separator: ".")
        guard parts.count >= 2 else {
            return version
        }
        return "\(parts[0]).\(parts[1])"
    }
}
```

Create `Sources/OpenSimBridge/Capabilities/CapabilityPolicy.swift`:

```swift
import Foundation
import OpenSimCore

public extension BridgeCapabilities {
    init(
        render: Capability,
        hid: Capability,
        accessibility: Capability,
        screenshot: Capability,
        video: Capability,
        watch: Capability,
        tv: Capability
    ) {
        self.render = render
        self.hid = hid
        self.accessibility = accessibility
        self.screenshot = screenshot
        self.video = video
        self.watch = watch
        self.tv = tv
    }
}

public struct CapabilityPolicy: Sendable {
    public static func degrade(
        _ capabilities: BridgeCapabilities,
        compatibility: CompatibilityMode
    ) -> BridgeCapabilities {
        switch compatibility {
        case .supported, .bestEffort:
            return capabilities
        case .unknown:
            var result = capabilities
            result.render = .unavailable
            result.hid = .unavailable
            result.accessibility = .unavailable
            return result
        case .unsupported:
            return BridgeCapabilities(
                render: .unavailable,
                hid: .unavailable,
                accessibility: .unavailable,
                screenshot: .unavailable,
                video: .unavailable,
                watch: .unavailable,
                tv: .unavailable
            )
        }
    }
}
```

`BridgeCapabilities` giữ nguyên memberwise initializer do Plan 1 tạo; extension trên chỉ thêm initializer public đầy đủ tham số.

Trong `Sources/OpenSimCLI/Commands/DoctorCommand.swift`, thêm block JSON:

```swift
let compatibility = CompatibilityMatrix.release.mode(forXcodeVersion: xcodeVersion)
let compatibilityJSON: [String: String] = [
    "xcodeVersion": xcodeVersion,
    "mode": compatibility.rawValue
]
```

Ghi `compatibilityJSON` vào `data.compatibility`, và dùng `CapabilityPolicy.degrade` trước khi in `capabilities`.

Create `Tests/SecurityTests/DoctorCompatibilityTests.swift`:

```swift
import XCTest

final class DoctorCompatibilityTests: XCTestCase {
    func testDoctorReportsCompatibilityMode() throws {
        let binary = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/opensim")
        let result = try ProcessRunner.run(binary.path, ["doctor", "--json"])
        XCTAssertEqual(result.status, 0, result.stderr)
        let object = try JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as! [String: Any]
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let compatibility = try XCTUnwrap(data["compatibility"] as? [String: Any])
        XCTAssertNotNil(compatibility["xcodeVersion"])
        XCTAssertTrue(["supported", "bestEffort", "unknown", "unsupported"].contains(compatibility["mode"] as? String))
    }
}
```

- [ ] **Step 4: Viết tài liệu compatibility**

Create `docs/compatibility.md` với nội dung:

```markdown
# OpenSim Compatibility

- macOS 27.0 trở lên, arm64.
- Xcode 27.1 là bản chính; Xcode 27.0 là best-effort.
- Runtime đã test: iOS 27.0, watchOS 27.0, tvOS 27.0.

## Ma trận

| Xcode | Mode | Runtime | Hành vi |
|---|---|---|---|
| 27.1 | supported | iOS/watchOS/tvOS 27.0 | Đầy đủ capability |
| 27.0 | bestEffort | iOS 27.0 | Chạy, doctor cảnh báo, không chặn |
| 27.x khác | unknown | Không cam kết | Tắt render/HID/accessibility private, giữ screenshot/video/watch/tv |
| 26.x trở xuống | unsupported | Không | Từ chối start, trả `unsupported_xcode` |

## Suy giảm capability

- `unknown`: `render`, `hid`, `accessibility` là `unavailable`; app hiện banner và dùng screenshot polling; CLI trả `capability_unavailable` cho thao tác cần private API.
- `unsupported`: mọi capability `unavailable`; daemon trả `unsupported_xcode` kèm recovery cài Xcode 27.1.
- `bestEffort`: giữ capability đã dò được, doctor ghi `mode=bestEffort` và release notes ghi rõ chưa test đầy đủ.
```

- [ ] **Step 5: Chạy test để thấy pass**

Run:

```bash
swift test --filter CompatibilityMatrixTests
swift test --filter CapabilityPolicyTests
swift build --product opensim
swift test --filter DoctorCompatibilityTests
```

Expected: `Executed 5 tests, with 0 failures`; `Executed 4 tests, with 0 failures`; `Executed 1 test, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenSimCore/Compatibility Sources/OpenSimBridge/Capabilities Sources/OpenSimCLI/Commands/DoctorCommand.swift Tests/OpenSimCoreTests/CompatibilityMatrixTests.swift Tests/OpenSimBridgeTests/CapabilityPolicyTests.swift Tests/SecurityTests/DoctorCompatibilityTests.swift docs/compatibility.md
git commit -m "feat(compat): gate capabilities by Xcode compatibility mode"
```

---

### Task 7: CI unit và lint

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `.swiftlint.yml`
- Create: `Scripts/ci/run-unit.sh`

**Interfaces:**
- Consumes: `swift build`, `swift test`, `swiftlint`, các script security từ Task 1-5.
- Produces: workflow `ci` chạy trên `macos-27`; script `run-unit.sh` tái lập cùng bước ở máy local.

- [ ] **Step 1: Viết workflow và script**

Create `.github/workflows/ci.yml`:

```yaml
name: ci

on:
  push:
    branches: [main]
  pull_request:

jobs:
  unit:
    runs-on: macos-27
    timeout-minutes: 45
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Select Xcode 27.1
        run: sudo xcode-select -s /Applications/Xcode_27.1.app

      - name: Install tools
        run: brew install swiftlint jq xcodegen

      - name: Build
        run: swift build

      - name: Unit tests
        run: swift test --parallel

      - name: Lint
        run: swiftlint lint --strict

      - name: Security scripts
        run: |
          Scripts/security/check-no-shell-strings.sh
          Scripts/security/check-no-telemetry.sh

      - name: Verify version consistency
        run: Scripts/release/verify-versions.sh
```

Create `.swiftlint.yml`:

```yaml
included:
  - Sources
  - App/Sources
  - Tests

excluded:
  - .build
  - build

line_length:
  warning: 140
  error: 200

identifier_name:
  min_length: 2
  excluded:
    - id
    - x
    - y
    - tv

type_body_length:
  warning: 400
  error: 600
```

Create `Scripts/ci/run-unit.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
cd "$ROOT"
swift build
swift test --parallel
swiftlint lint --strict
Scripts/security/check-no-shell-strings.sh
Scripts/security/check-no-telemetry.sh
Scripts/release/verify-versions.sh
print "OK unit"
```

- [ ] **Step 2: Chạy local để thấy fail**

Run:

```bash
chmod +x Scripts/ci/run-unit.sh
Scripts/ci/run-unit.sh
```

Expected: FAIL vì `Scripts/release/verify-versions.sh` chưa tồn tại (Task 15 tạo); các bước trước pass.

- [ ] **Step 3: Tạo script version tối thiểu để CI chạy được**

Create `Scripts/release/verify-versions.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
if [[ -z "$VERSION" ]]; then
  print -u2 "VERSION is empty"
  exit 1
fi
INFO="$ROOT/build/release/OpenSim.app/Contents/Info.plist"
if [[ -f "$INFO" ]]; then
  SHORT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO")"
  if [[ "$SHORT" != "$VERSION" ]]; then
    print -u2 "app version $SHORT does not match VERSION $VERSION"
    exit 1
  fi
fi
CASK="$ROOT/Homebrew/Casks/opensim-app.rb"
if [[ -f "$CASK" ]]; then
  CASK_VERSION="$(sed -n 's/^  version "\(.*\)"$/\1/p' "$CASK")"
  if [[ "$CASK_VERSION" != "$VERSION" ]]; then
    print -u2 "cask version $CASK_VERSION does not match VERSION $VERSION"
    exit 1
  fi
fi
print "OK versions $VERSION"
```

Create `VERSION` với nội dung `0.1.0`.

- [ ] **Step 4: Chạy local để thấy pass**

Run:

```bash
chmod +x Scripts/release/verify-versions.sh
Scripts/ci/run-unit.sh
```

Expected: toàn bộ unit pass; `OK no shell strings`; `OK no telemetry`; `OK versions 0.1.0`; `OK unit`.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ci.yml .swiftlint.yml Scripts/ci/run-unit.sh Scripts/release/verify-versions.sh VERSION
git commit -m "ci: add unit lint and security workflow"
```

---

### Task 8: Integration, nightly và release gate trên self-hosted runner

**Files:**
- Create: `.github/workflows/integration.yml`
- Create: `.github/workflows/nightly.yml`
- Create: `.github/workflows/release-gate.yml`
- Create: `Scripts/ci/build-fixtures.sh`
- Create: `Scripts/ci/run-integration.sh`

**Interfaces:**
- Consumes: fixture projects `Fixtures/OpenSimFixture`, `Fixtures/OpenSimFixtureWatch`, `Fixtures/OpenSimFixtureTV`; test target `IntegrationTests`; biến `OPENSIM_INTEGRATION=1`.
- Produces: ba workflow dùng label self-hosted `[self-hosted, macOS, arm64, opensim-xcode-27.1]`; script build fixture và chạy integration.

- [ ] **Step 1: Viết script và workflow**

Create `Scripts/ci/build-fixtures.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
cd "$ROOT"
for fixture in OpenSimFixture OpenSimFixtureWatch OpenSimFixtureTV; do
  SPEC="$ROOT/Fixtures/$fixture/project.yml"
  if [[ ! -f "$SPEC" ]]; then
    continue
  fi
  xcodegen generate --spec "$SPEC"
done
xcodebuild -project "$ROOT/Fixtures/OpenSimFixture/OpenSimFixture.xcodeproj" \
  -scheme OpenSimFixture \
  -configuration Debug \
  -sdk iphonesimulator \
  -derivedDataPath "$ROOT/build/fixtures" \
  build
if [[ -f "$ROOT/Fixtures/OpenSimFixtureWatch/project.yml" ]]; then
  xcodebuild -project "$ROOT/Fixtures/OpenSimFixtureWatch/OpenSimFixtureWatch.xcodeproj" \
    -scheme OpenSimFixtureWatch \
    -configuration Debug \
    -sdk watchsimulator \
    -derivedDataPath "$ROOT/build/fixtures" \
    build
fi
if [[ -f "$ROOT/Fixtures/OpenSimFixtureTV/project.yml" ]]; then
  xcodebuild -project "$ROOT/Fixtures/OpenSimFixtureTV/OpenSimFixtureTV.xcodeproj" \
    -scheme OpenSimFixtureTV \
    -configuration Debug \
    -sdk tvsimulator \
    -derivedDataPath "$ROOT/build/fixtures" \
    build
fi
print "OK fixtures"
```

Create `Scripts/ci/run-integration.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
cd "$ROOT"
export OPENSIM_INTEGRATION=1
export OPENSIM_FIXTURE_DIR="$ROOT/build/fixtures/Build/Products/Debug-iphonesimulator"
swift test --filter IntegrationTests
print "OK integration"
```

Create `.github/workflows/integration.yml`:

```yaml
name: integration

on:
  workflow_dispatch:
  pull_request:
    types: [labeled]

jobs:
  integration:
    if: github.event_name == 'workflow_dispatch' || github.event.label.name == 'run-integration'
    runs-on: [self-hosted, macOS, arm64, opensim-xcode-27.1]
    timeout-minutes: 90
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Verify runner toolchain
        run: |
          sw_vers
          xcodebuild -version
          test "$(xcodebuild -version | head -1)" = "Xcode 27.1"

      - name: Build fixtures
        run: Scripts/ci/build-fixtures.sh

      - name: Integration tests
        run: Scripts/ci/run-integration.sh

      - name: Upload daemon log on failure
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: integration-daemon-log
          path: ~/Library/Logs/OpenSim/daemon.log
          if-no-files-found: ignore
```

Create `.github/workflows/nightly.yml`:

```yaml
name: nightly

on:
  schedule:
    - cron: "0 18 * * *"
  workflow_dispatch:

jobs:
  nightly:
    runs-on: [self-hosted, macOS, arm64, opensim-xcode-27.1]
    timeout-minutes: 120
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Build fixtures
        run: Scripts/ci/build-fixtures.sh

      - name: Integration tests
        run: Scripts/ci/run-integration.sh

      - name: Security scripts
        run: |
          Scripts/security/check-no-shell-strings.sh
          Scripts/security/check-no-telemetry.sh

      - name: Upload results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: nightly-results
          path: |
            build/fixtures
            ~/Library/Logs/OpenSim/daemon.log
          if-no-files-found: ignore
```

Create `.github/workflows/release-gate.yml`:

```yaml
name: release-gate

on:
  workflow_dispatch:
    inputs:
      version:
        description: "Version to verify, for example 0.1.0"
        required: true
        type: string
  release:
    types: [published]

jobs:
  gate:
    runs-on: [self-hosted, macOS, arm64, opensim-xcode-27.1]
    timeout-minutes: 180
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Verify version input
        if: github.event_name == 'workflow_dispatch'
        run: |
          test "$(cat VERSION)" = "${{ inputs.version }}"

      - name: Run release gate
        env:
          OPENSIM_RELEASE_VERSION: ${{ inputs.version }}
          OPENSIM_CLEAN_MAC: "0"
        run: Tests/Release/run-release-gate.sh
```

- [ ] **Step 2: Chạy script local để thấy fail**

Run:

```bash
chmod +x Scripts/ci/build-fixtures.sh Scripts/ci/run-integration.sh
Scripts/ci/build-fixtures.sh
```

Expected: PASS với fixture đã có, hoặc FAIL rõ ràng nếu thiếu `Fixtures/OpenSimFixture/project.yml`; không được bỏ qua âm thầm khi thiếu fixture iOS.

- [ ] **Step 3: Viết check runner label**

Create `Scripts/ci/check-runner.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
XCODE="$(xcodebuild -version | head -1)"
if [[ "$XCODE" != "Xcode 27.1" ]]; then
  print -u2 "runner has $XCODE, expected Xcode 27.1"
  exit 1
fi
ARCH="$(uname -m)"
if [[ "$ARCH" != "arm64" ]]; then
  print -u2 "runner has $ARCH, expected arm64"
  exit 1
fi
print "OK runner $XCODE $ARCH"
```

- [ ] **Step 4: Chạy check**

Run:

```bash
chmod +x Scripts/ci/check-runner.sh
Scripts/ci/check-runner.sh
```

Expected trên runner chuẩn: `OK runner Xcode 27.1 arm64`. Trên máy khác: exit `1` với thông báo version.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/integration.yml .github/workflows/nightly.yml .github/workflows/release-gate.yml Scripts/ci
git commit -m "ci: add self-hosted integration nightly and release gate"
```

---

### Task 9: Ký, Hardened Runtime và notarization

**Files:**
- Create: `App/OpenSim.entitlements`
- Create: `Packaging/dev.opensim.daemon.plist`
- Create: `Scripts/release/build-app.sh`
- Create: `Scripts/release/notarize.sh`
- Create: `Scripts/release/verify-signature.sh`
- Modify: `App/project.yml` (embed CLI helper)

**Interfaces:**
- Consumes: `VERSION`, `App/project.yml` từ Plan 4; `.build/release/opensim` từ SwiftPM.
- Produces: `build/release/OpenSim.app` đã ký; `notarize.sh build/release/OpenSim.app` submit/staple; `verify-signature.sh` kiểm tra entitlement, runtime, Gatekeeper và in `OK signature`.

- [ ] **Step 1: Viết script verify thất bại**

Create `Scripts/release/verify-signature.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
APP="${1:-$ROOT/build/release/OpenSim.app}"
if [[ ! -d "$APP" ]]; then
  print -u2 "app not found: $APP"
  exit 1
fi

codesign --verify --strict --verbose=2 "$APP"
codesign --verify --strict --verbose=2 "$APP/Contents/Helpers/opensim"

OPTIONS="$(codesign -d --verbose=4 "$APP" 2>&1)"
if ! print -r -- "$OPTIONS" | grep -q "Runtime Version"; then
  print -u2 "hardened runtime flag is missing"
  exit 1
fi

ENTITLEMENTS="$(codesign -d --entitlements :- "$APP" 2>/dev/null)"
if ! print -r -- "$ENTITLEMENTS" | grep -q "com.apple.security.app-sandbox"; then
  print -u2 "app-sandbox entitlement is missing"
  exit 1
fi
if print -r -- "$ENTITLEMENTS" | grep -A1 "com.apple.security.app-sandbox" | grep -q "<true/>"; then
  print -u2 "app sandbox must be disabled"
  exit 1
fi
if print -r -- "$ENTITLEMENTS" | grep -A1 "disable-library-validation" | grep -q "<true/>"; then
  print -u2 "library validation is disabled without a recorded decision"
  exit 1
fi

SPCTL="$(/usr/sbin/spctl -a -vvv -t exec "$APP" 2>&1)"
if ! print -r -- "$SPCTL" | grep -q "accepted"; then
  print -u2 "$SPCTL"
  exit 1
fi
xmllint --noout "$APP/Contents/Info.plist"
print "OK signature"
```

Run:

```bash
chmod +x Scripts/release/verify-signature.sh
Scripts/release/verify-signature.sh
```

Expected: FAIL với `app not found` hoặc `code object is not signed at all`.

- [ ] **Step 2: Viết entitlements và plist**

Create `App/OpenSim.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.cs.allow-jit</key>
    <false/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <false/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <false/>
</dict>
</plist>
```

Create `Packaging/dev.opensim.daemon.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>dev.opensim.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/homebrew/bin/opensim</string>
        <string>daemon</string>
        <string>run</string>
        <string>--foreground</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ProcessType</key>
    <string>Background</string>
    <key>StandardOutPath</key>
    <string>/Users/Shared/OpenSim/daemon.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/Shared/OpenSim/daemon.err.log</string>
</dict>
</plist>
```

`StandardOutPath` trong `/Users/Shared` không phù hợp quyền user; Task 11 sinh plist với `~/Library/Logs/OpenSim/daemon.log`. File này chỉ dùng làm mẫu cấu trúc cho cask; `opensim setup` là đường cài chính. Thêm ghi chú vào đầu file bằng comment XML:

```xml
<!-- Reference template for packaged installs. opensim setup writes the user LaunchAgent with absolute log paths. -->
```

- [ ] **Step 3: Viết build script**

Create `Scripts/release/build-app.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
: "${OPENSIM_TEAM_ID:?set OPENSIM_TEAM_ID to the Apple Developer team identifier}"
IDENTITY="${OPENSIM_SIGNING_IDENTITY:-Developer ID Application}"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
cd "$ROOT"

swift build -c release --product opensim
xcodegen generate --spec App/project.yml

xcodebuild \
  -project App/OpenSim.xcodeproj \
  -scheme OpenSim \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  -destination "platform=macOS,arch=arm64" \
  DEVELOPMENT_TEAM="$OPENSIM_TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  ENABLE_HARDENED_RUNTIME=YES \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION=1 \
  build

APP="$ROOT/build/DerivedData/Build/Products/Release/OpenSim.app"
rm -rf "$ROOT/build/release/OpenSim.app"
mkdir -p "$ROOT/build/release"
ditto "$APP" "$ROOT/build/release/OpenSim.app"
APP="$ROOT/build/release/OpenSim.app"

mkdir -p "$APP/Contents/Helpers"
ditto "$ROOT/.build/release/opensim" "$APP/Contents/Helpers/opensim"

codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/Helpers/opensim"
codesign --force --options runtime --timestamp --entitlements App/OpenSim.entitlements --sign "$IDENTITY" "$APP"

codesign --verify --strict --verbose=2 "$APP"
print "OK build $VERSION"
```

Trong `App/project.yml`, thêm build phase copy helper để bản build của Xcode cũng có CLI:

```yaml
postBuildScripts:
  - name: Embed opensim CLI
    script: |
      set -euo pipefail
      mkdir -p "$TARGET_BUILD_DIR/$WRAPPER_NAME/Contents/Helpers"
      ditto "$SRCROOT/../.build/release/opensim" "$TARGET_BUILD_DIR/$WRAPPER_NAME/Contents/Helpers/opensim"
    basedOnDependencyAnalysis: false
```

- [ ] **Step 4: Viết notarize script**

Create `Scripts/release/notarize.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
TARGET="${1:?pass an app or dmg path}"
PROFILE="${OPENSIM_NOTARY_PROFILE:-opensim-notary}"
if [[ ! -e "$TARGET" ]]; then
  print -u2 "target not found: $TARGET"
  exit 1
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
if [[ "$TARGET" == *.dmg ]]; then
  ARCHIVE="$TARGET"
else
  ARCHIVE="$WORK/$(basename "$TARGET").zip"
  ditto -c -k --keepParent "$TARGET" "$ARCHIVE"
fi
xcrun notarytool submit "$ARCHIVE" --keychain-profile "$PROFILE" --wait
if [[ "$TARGET" == *.app || "$TARGET" == *.dmg ]]; then
  xcrun stapler staple "$TARGET"
  xcrun stapler validate "$TARGET"
fi
print "OK notarized $TARGET"
```

- [ ] **Step 5: Build, ký và kiểm tra**

Run:

```bash
chmod +x Scripts/release/build-app.sh Scripts/release/notarize.sh
OPENSIM_TEAM_ID="<team-id-thuc-te>" Scripts/release/build-app.sh
Scripts/release/verify-signature.sh
```

Expected: `OK build 0.1.0`; `OK signature`. Với `spctl` trước notarize có thể trả `rejected`; chạy `Scripts/release/notarize.sh build/release/OpenSim.app` rồi chạy lại `verify-signature.sh` để nhận `accepted`.

- [ ] **Step 6: Quyết định library validation**

Chạy helper đã ký trong môi trường Hardened Runtime:

```bash
build/release/OpenSim.app/Contents/Helpers/opensim doctor --json | jq -e '.ok == true'
```

Expected: `true`. Nếu `dlopen` fail với `code signature invalid` hoặc `mapped file has no Team ID`, thực hiện đúng biên bản sau, không thêm entitlement mặc định:

1. Ghi lý do, log `codesign -dv --verbose=4` của SimulatorKit, và ngày quyết định vào `docs/security.md` mục "Library validation decision".
2. Đổi `com.apple.security.cs.disable-library-validation` trong `App/OpenSim.entitlements` thành `true`.
3. Chạy lại `Scripts/release/build-app.sh`, `Scripts/release/notarize.sh`, `Scripts/release/verify-signature.sh`.
4. Ghi commit message `release: allow library validation exception for SimulatorKit` và owner ký tên trong tài liệu.

Không thêm exception khi helper chạy được với validation bật.

- [ ] **Step 7: Commit**

```bash
git add App/OpenSim.entitlements App/project.yml Packaging/dev.opensim.daemon.plist Scripts/release/build-app.sh Scripts/release/notarize.sh Scripts/release/verify-signature.sh
git commit -m "release: sign app with hardened runtime and notarize"
```

---

### Task 10: DMG, tarball CLI và Homebrew tap

**Files:**
- Create: `Scripts/release/package-dmg.sh`
- Create: `Scripts/release/update-tap.sh`
- Create: `Homebrew/Casks/opensim-app.rb`
- Create: `Homebrew/Formula/opensim.rb`
- Create: `Tests/Release/test-brew-install.sh`

**Interfaces:**
- Consumes: `build/release/OpenSim.app` từ Task 9; `VERSION`.
- Produces: `build/release/OpenSim-$VERSION.dmg`, `build/release/opensim-$VERSION-arm64.tar.gz`, cask/formula có SHA256 thật; test cài từ tap in `OK brew install`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/Release/test-brew-install.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
CHANNEL="${OPENSIM_RELEASE_CHANNEL:-local}"

if [[ "$CHANNEL" == "local" ]]; then
  ruby -c "$ROOT/Homebrew/Casks/opensim-app.rb"
  ruby -c "$ROOT/Homebrew/Formula/opensim.rb"
  brew style "$ROOT/Homebrew/Casks/opensim-app.rb" "$ROOT/Homebrew/Formula/opensim.rb"
  print "OK brew metadata"
  exit 0
fi

if ! brew tap | grep -q '^opensim/tap$'; then
  brew tap opensim/tap "https://github.com/opensim/homebrew-tap"
fi
brew install --cask opensim-app
brew install opensim
test -x "$(brew --prefix)/bin/opensim"
"$(brew --prefix)/bin/opensim" doctor --json | jq -e '.ok == true'
brew uninstall --cask opensim-app
brew uninstall opensim
print "OK brew install"
```

Run:

```bash
chmod +x Tests/Release/test-brew-install.sh
Tests/Release/test-brew-install.sh
```

Expected: FAIL vì `Homebrew/Casks/opensim-app.rb` và `Homebrew/Formula/opensim.rb` chưa tồn tại.

- [ ] **Step 2: Viết script đóng gói**

Create `Scripts/release/package-dmg.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
APP="$ROOT/build/release/OpenSim.app"
OUT="$ROOT/build/release"
if [[ ! -d "$APP" ]]; then
  print -u2 "missing signed app: $APP"
  exit 1
fi

STAGE="$OUT/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/OpenSim.app"
ln -s /Applications "$STAGE/Applications"

DMG="$OUT/OpenSim-$VERSION.dmg"
rm -f "$DMG"
hdiutil create \
  -volname "OpenSim $VERSION" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"
codesign --force --timestamp --sign "${OPENSIM_SIGNING_IDENTITY:-Developer ID Application}" "$DMG"

TAR_STAGE="$OUT/tar-stage"
rm -rf "$TAR_STAGE"
mkdir -p "$TAR_STAGE"
ditto "$APP/Contents/Helpers/opensim" "$TAR_STAGE/opensim"
TARBALL="$OUT/opensim-$VERSION-arm64.tar.gz"
rm -f "$TARBALL"
tar -czf "$TARBALL" -C "$TAR_STAGE" opensim

print "OK package $DMG"
print "OK package $TARBALL"
```

- [ ] **Step 3: Viết script sinh tap**

Create `Scripts/release/update-tap.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
DMG="$ROOT/build/release/OpenSim-$VERSION.dmg"
TARBALL="$ROOT/build/release/opensim-$VERSION-arm64.tar.gz"
CASK="$ROOT/Homebrew/Casks/opensim-app.rb"
FORMULA="$ROOT/Homebrew/Formula/opensim.rb"
if [[ ! -f "$DMG" || ! -f "$TARBALL" ]]; then
  print -u2 "run Scripts/release/package-dmg.sh first"
  exit 1
fi
DMG_SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
TAR_SHA="$(shasum -a 256 "$TARBALL" | awk '{print $1}')"
mkdir -p "$ROOT/Homebrew/Casks" "$ROOT/Homebrew/Formula"

cat > "$CASK" <<RUBY
cask "opensim-app" do
  version "$VERSION"
  sha256 "$DMG_SHA"

  url "https://github.com/opensim/open-simulator/releases/download/v#{version}/OpenSim-#{version}.dmg"
  name "OpenSim"
  desc "Local simulator control for AI agents"
  homepage "https://github.com/opensim/open-simulator"

  depends_on arch: :arm64
  depends_on macos: ">= :tahoe"

  app "OpenSim.app"

  uninstall launchctl: "dev.opensim.daemon",
            quit:      "dev.opensim.app"

  zap trash: [
    "~/Library/Application Support/OpenSim",
    "~/Library/Logs/OpenSim",
    "~/Library/LaunchAgents/dev.opensim.daemon.plist"
  ]
end
RUBY

cat > "$FORMULA" <<RUBY
class Opensim < Formula
  desc "Local simulator control for AI agents"
  homepage "https://github.com/opensim/open-simulator"
  url "https://github.com/opensim/open-simulator/releases/download/v$VERSION/opensim-$VERSION-arm64.tar.gz"
  sha256 "$TAR_SHA"
  version "$VERSION"
  license "MIT"

  depends_on arch: :arm64
  depends_on macos: ">= :tahoe"

  def install
    bin.install "opensim"
  end

  service do
    run [opt_bin/"opensim", "daemon", "run", "--foreground"]
    keep_alive successful_exit: false
    process_type :background
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/opensim --version")
  end
end
RUBY

ruby -c "$CASK"
ruby -c "$FORMULA"
print "OK tap $VERSION"
print "cask sha256 $DMG_SHA"
print "formula sha256 $TAR_SHA"
```

- [ ] **Step 4: Chạy để thấy pass**

Run:

```bash
chmod +x Scripts/release/package-dmg.sh Scripts/release/update-tap.sh
Scripts/release/package-dmg.sh
Scripts/release/update-tap.sh
Tests/Release/test-brew-install.sh
```

Expected: `OK package build/release/OpenSim-0.1.0.dmg`; `OK tap 0.1.0`; SHA256 khớp `shasum -a 256`; `OK brew metadata`.

- [ ] **Step 5: Kiểm tra cài thật trước phát hành**

Trên runner release, sau khi DMG đã notarize:

```bash
OPENSIM_RELEASE_CHANNEL=local Tests/Release/test-brew-install.sh
brew install --cask ./Homebrew/Casks/opensim-app.rb
/opt/homebrew/bin/opensim doctor --json | jq -e '.ok == true'
brew uninstall --cask opensim-app
```

Expected: cask cài app vào `/Applications/OpenSim.app`, `opensim doctor` trả `ok=true`, gỡ sạch.

- [ ] **Step 6: Commit**

```bash
git add Scripts/release/package-dmg.sh Scripts/release/update-tap.sh Homebrew Tests/Release/test-brew-install.sh
git commit -m "release: package dmg and generate homebrew cask and formula"
```

---

### Task 11: `opensim setup`, `doctor`, uninstall và versioning

**Files:**
- Create: `Sources/OpenSimCLI/Commands/SetupCommand.swift`
- Create: `Sources/OpenSimCLI/Commands/UninstallCommand.swift`
- Create: `Sources/OpenSimCLI/Commands/VersionCommand.swift`
- Create: `Sources/OpenSimCore/Security/OwnedDeviceRegistry.swift`
- Modify: `Sources/OpenSimCore/Support/OpenSimVersion.swift` (thêm `current = version`)
- Create: `Tests/OpenSimCLITests/UninstallCommandTests.swift`
- Modify: `Sources/OpenSimDaemon/LaunchAgent/LaunchAgentManager.swift` (thêm `uninstall(purge:)`)
- Modify: `Sources/OpenSimCLI/OpenSimCommand.swift` (đăng ký subcommand)
- Modify: `Sources/OpenSimDaemon/Operations/OperationDispatcher.swift` (ghi registry khi create/delete)

**Interfaces:**
- Consumes: `VERSION`; `LaunchAgentManager.install/bootstrap/kickstart/isLoaded` và `OpenSimPaths` từ Plan 3; daemon state file.
- Produces: `opensim setup [--yes] [--json]`, `opensim uninstall [--yes] [--purge] [--json]`, `opensim --version`; `LaunchAgentManager.uninstall(purge:)`; `OwnedDeviceRegistry.record(_:)`, `.remove(_:)`, `.all()`.

- [ ] **Step 1: Viết test thất bại**

Plan 3 đã có `Tests/OpenSimDaemonTests/LaunchAgentTests.swift` cho plist và bootstrap; task này không viết lại test đó. Chỉ thêm test registry:

Create `Tests/OpenSimCLITests/UninstallCommandTests.swift`:

```swift
import Foundation
import XCTest
@testable import OpenSimCore

final class UninstallCommandTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("opensim-owned-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func testRegistryRoundTrip() throws {
        let registry = OwnedDeviceRegistry(home: home)
        try registry.record("11111111-1111-1111-1111-111111111111")
        try registry.record("22222222-2222-2222-2222-222222222222")
        XCTAssertEqual(
            Set(registry.all()),
            Set(["11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222"])
        )
        try registry.remove("11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(registry.all(), ["22222222-2222-2222-2222-222222222222"])
    }

    func testRegistryRejectsNonUUID() throws {
        let registry = OwnedDeviceRegistry(home: home)
        XCTAssertThrowsError(try registry.record("not-a-udid"))
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter UninstallCommandTests
```

Expected: FAIL vì `OwnedDeviceRegistry` chưa tồn tại.

- [ ] **Step 3: Implement LaunchAgent và registry**

Mở rộng `Sources/OpenSimDaemon/LaunchAgent/LaunchAgentManager.swift` bằng hàm uninstall (dùng lại manager của Plan 3, không tạo plist thứ hai):

```swift
public extension LaunchAgentManager {
    func uninstall(purge: Bool) throws {
        if isLoaded() {
            try? bootout()
        }
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
        if purge {
            try? FileManager.default.removeItem(at: paths.baseDirectory)
        }
    }
}
```

Create `Sources/OpenSimCore/Security/OwnedDeviceRegistry.swift`:

```swift
import Foundation
import OpenSimCore

public struct OwnedDeviceRegistry: @unchecked Sendable {
    private let home: URL
    private let fileManager: FileManager

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, fileManager: FileManager = .default) {
        self.home = home
        self.fileManager = fileManager
    }

    private var fileURL: URL {
        home.appendingPathComponent("Library/Application Support/OpenSim/owned-devices.json")
    }

    public func all() -> [String] {
        guard let data = try? Data(contentsOf: fileURL),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values.sorted()
    }

    public func record(_ udid: String) throws {
        try validate(udid)
        var values = Set(all())
        values.insert(udid.lowercased())
        try write(Array(values).sorted())
    }

    public func remove(_ udid: String) throws {
        try validate(udid)
        let values = all().filter { $0 != udid.lowercased() }
        try write(values)
    }

    private func validate(_ udid: String) throws {
        guard UUID(uuidString: udid) != nil else {
            throw OpenSimError(
                code: "invalid_argument",
                message: "Device identifier must be a UUID",
                details: ["udid": udid],
                recovery: "Pass the UDID returned by device create",
                retryable: false
            )
        }
    }

    private func write(_ values: [String]) throws {
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(values)
        try data.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
```

Modify `Sources/OpenSimCore/Support/OpenSimVersion.swift` (file Plan 1 đã tạo): thêm alias, không khai báo lại enum.

```swift
public static let current = version
```

- [ ] **Step 4: Implement commands**

Create `Sources/OpenSimCLI/Commands/SetupCommand.swift`:

```swift
import ArgumentParser
import Foundation
import OpenSimCore
import OpenSimDaemon

struct SetupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Install the OpenSim LaunchAgent and verify the local environment"
    )

    @Flag(name: .long, help: "Skip interactive confirmation")
    var yes = false

    @Flag(name: .long, help: "Emit JSON envelope")
    var json = false

    func run() async throws {
        let executable = CommandLine.arguments[0]
        guard executable.hasPrefix("/") else {
            throw OpenSimError(
                code: "invalid_argument",
                message: "opensim must run from an absolute path",
                details: ["path": executable],
                recovery: "Install with Homebrew or run the built binary directly",
                retryable: false
            )
        }
        let manager = LaunchAgentManager(opensimPath: executable, paths: OpenSimPaths())
        try manager.install()
        if manager.isLoaded() {
            try manager.kickstart()
        } else {
            try manager.bootstrap()
        }
        let loaded = manager.isLoaded()
        if json {
            let payload: [String: Any] = [
                "plistPath": manager.plistURL.path,
                "loaded": loaded,
                "version": OpenSimVersion.current
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        } else {
            print("Installed LaunchAgent at \(manager.plistURL.path)")
            print("Loaded: \(loaded)")
            print("Next: opensim doctor --json")
        }
    }
}
```

Create `Sources/OpenSimCLI/Commands/UninstallCommand.swift`:

```swift
import ArgumentParser
import Foundation
import OpenSimCore
import OpenSimDaemon

struct UninstallCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Remove the LaunchAgent, app and OpenSim state"
    )

    @Flag(name: .long, help: "Skip interactive confirmation")
    var yes = false

    @Flag(name: .long, help: "Also remove OpenSim state, logs and owned simulator devices")
    var purge = false

    @Flag(name: .long, help: "Emit JSON envelope")
    var json = false

    func run() async throws {
        guard yes else {
            throw OpenSimError(
                code: "confirmation_required",
                message: "uninstall requires --yes",
                details: ["purge": String(purge)],
                recovery: "Re-run with --yes",
                retryable: false
            )
        }
        let removedDevices: [String]
        if purge {
            let registry = OwnedDeviceRegistry()
            removedDevices = registry.all()
            for udid in removedDevices {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
                process.arguments = ["simctl", "delete", udid]
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    try registry.remove(udid)
                }
            }
        } else {
            removedDevices = []
        }
        let manager = LaunchAgentManager(opensimPath: CommandLine.arguments[0], paths: OpenSimPaths())
        try manager.uninstall(purge: purge)
        let result: [String: Any] = [
            "purged": purge,
            "removedDevices": removedDevices,
            "version": OpenSimVersion.current
        ]
        if json {
            let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        } else {
            print("Removed LaunchAgent")
            print("Purged: \(purge)")
        }
    }
}
```

Create `Sources/OpenSimCLI/Commands/VersionCommand.swift`:

```swift
import ArgumentParser
import OpenSimCore

struct VersionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Print the OpenSim version"
    )

    func run() {
        print("opensim \(OpenSimVersion.current)")
    }
}
```

Đăng ký trong `OpenSimCommand`:

```swift
static let configuration = CommandConfiguration(
    commandName: "opensim",
    abstract: "Control Apple simulators from the command line",
    version: OpenSimVersion.current,
    subcommands: [
        DeviceCommand.self,
        RuntimeCommand.self,
        AppCommand.self,
        UICommand.self,
        LogCommand.self,
        SessionCommand.self,
        StorageCommand.self,
        PerformanceCommand.self,
        DoctorCommand.self,
        DaemonCommand.self,
        MCPCommand.self,
        SetupCommand.self,
        UninstallCommand.self,
        VersionCommand.self
    ]
)
```

Trong `Sources/OpenSimDaemon/Operations/OperationDispatcher.swift`, sau `device create` thành công:

```swift
try OwnedDeviceRegistry().record(device.id.rawValue)
```

Sau `device delete` thành công:

```swift
try? OwnedDeviceRegistry().remove(id.rawValue)
```

- [ ] **Step 5: Chạy test để thấy pass**

Run:

```bash
swift test --filter UninstallCommandTests
swift test --filter LaunchAgentTests
swift build --product opensim
.build/debug/opensim --version
```

Expected: `Executed 2 tests, with 0 failures`; test LaunchAgent của Plan 3 vẫn pass; `opensim 0.1.0`.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenSimCLI/Commands Sources/OpenSimDaemon/LaunchAgent Sources/OpenSimCore/Security/OwnedDeviceRegistry.swift Sources/OpenSimCore/Support/OpenSimVersion.swift Sources/OpenSimDaemon/Operations/OperationDispatcher.swift Tests/OpenSimCLITests
git commit -m "feat(cli): add setup uninstall and version commands"
```

---

### Task 12: Tài liệu sinh từ catalog

**Files:**
- Create: `Sources/OpenSimCLI/Output/DocsRenderer.swift`
- Create: `Sources/OpenSimCLI/Commands/DocsCommand.swift`
- Create: `Sources/OpenSimCLI/Commands/OpenSimCommandCatalog.swift`
- Create: `Tests/OpenSimCLITests/DocsCommandTests.swift`
- Create: `docs/cli-reference.md` (sinh)
- Create: `docs/mcp-tools-reference.md` (sinh)
- Create: `README.md`
- Create: `docs/README.md`
- Create: `docs/architecture.md`
- Create: `docs/troubleshooting.md`
- Create: `docs/security.md`
- Create: `docs/contributing.md`
- Modify: `Sources/OpenSimCLI/OpenSimCommand.swift` (dùng `OpenSimCommandCatalog.make()`)
- Modify: `.github/workflows/ci.yml` (thêm docs check)

**Interfaces:**
- Consumes: `OperationCatalog`, `Operation`, `OperationParameter` từ contract mục 7.
- Produces: `DocsRenderer.cliReference(catalog:version:) -> String`, `DocsRenderer.mcpToolsReference(catalog:version:) -> String`; `opensim docs --out <dir> [--check]`.

- [ ] **Step 1: Viết test thất bại**

Create `Tests/OpenSimCLITests/DocsCommandTests.swift`:

```swift
import XCTest
@testable import OpenSimCLI
@testable import OpenSimCore

final class DocsCommandTests: XCTestCase {
    private func catalog() -> OperationCatalog {
        var catalog = OperationCatalog()
        catalog.register(Operation(
            cliPath: ["device", "boot"],
            mcpName: "device_boot",
            summary: "Boot a device and wait for the Booted state",
            requiresControlLease: true,
            destructive: false,
            readOnly: false,
            parameters: [
                OperationParameter(name: "device", type: "string", required: true, defaultValue: nil),
                OperationParameter(name: "wait", type: "bool", required: false, defaultValue: "false")
            ]
        ))
        catalog.register(Operation(
            cliPath: ["device", "delete"],
            mcpName: "device_delete",
            summary: "Delete a device",
            requiresControlLease: true,
            destructive: true,
            readOnly: false,
            parameters: [
                OperationParameter(name: "device", type: "string", required: true, defaultValue: nil),
                OperationParameter(name: "confirm", type: "bool", required: true, defaultValue: nil)
            ]
        ))
        return catalog
    }

    func testCLIReferenceIsSortedAndComplete() {
        let markdown = DocsRenderer().cliReference(catalog: catalog(), version: "0.1.0")
        XCTAssertTrue(markdown.contains("# OpenSim CLI Reference 0.1.0"))
        XCTAssertTrue(markdown.contains("`opensim device boot`"))
        XCTAssertTrue(markdown.contains("`opensim device delete`"))
        XCTAssertLessThan(
            markdown.range(of: "opensim device boot")!.lowerBound,
            markdown.range(of: "opensim device delete")!.lowerBound
        )
    }

    func testMCPReferenceMarksDestructiveTools() {
        let markdown = DocsRenderer().mcpToolsReference(catalog: catalog(), version: "0.1.0")
        XCTAssertTrue(markdown.contains("`device_boot`"))
        XCTAssertTrue(markdown.contains("`device_delete`"))
        XCTAssertTrue(markdown.contains("| `device_delete` | write | destructive | `device`, `confirm` |"))
    }

    func testReferenceEscapesPipesInSummary() {
        var catalog = OperationCatalog()
        catalog.register(Operation(
            cliPath: ["ui", "act"],
            mcpName: "ui_act",
            summary: "Run steps | stop on error",
            requiresControlLease: true,
            destructive: false,
            readOnly: false,
            parameters: []
        ))
        let markdown = DocsRenderer().cliReference(catalog: catalog, version: "0.1.0")
        XCTAssertTrue(markdown.contains("Run steps \\| stop on error"))
        XCTAssertFalse(markdown.contains("Run steps | stop on error"))
    }
}
```

- [ ] **Step 2: Chạy test để thấy fail**

Run:

```bash
swift test --filter DocsCommandTests
```

Expected: FAIL vì `DocsRenderer` chưa tồn tại.

- [ ] **Step 3: Implement renderer và command**

Create `Sources/OpenSimCLI/Output/DocsRenderer.swift`:

```swift
import Foundation
import OpenSimCore

public struct DocsRenderer: Sendable {
    public init() {}

    public func cliReference(catalog: OperationCatalog, version: String) -> String {
        var lines: [String] = [
            "# OpenSim CLI Reference \(version)",
            "",
            "Generated from OperationCatalog. Do not edit by hand.",
            "",
            "| CLI | MCP | Lease | Destructive | Summary |",
            "|---|---|---|---|---|"
        ]
        for operation in sorted(catalog) {
            let cli = "`opensim \(operation.cliPath.joined(separator: " "))`"
            let lease = operation.requiresControlLease ? "control" : "none"
            let destructive = operation.destructive ? "yes" : "no"
            lines.append("| \(cli) | `\(operation.mcpName)` | \(lease) | \(destructive) | \(escape(operation.summary)) |")
        }
        lines.append("")
        lines.append("## Parameters")
        lines.append("")
        for operation in sorted(catalog) {
            lines.append("### opensim \(operation.cliPath.joined(separator: " "))")
            lines.append("")
            if operation.parameters.isEmpty {
                lines.append("No parameters.")
            } else {
                lines.append("| Name | Type | Required | Default |")
                lines.append("|---|---|---|---|")
                for parameter in operation.parameters {
                    lines.append("| `\(parameter.name)` | \(parameter.type) | \(parameter.required ? "yes" : "no") | \(parameter.defaultValue ?? "-") |")
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    public func mcpToolsReference(catalog: OperationCatalog, version: String) -> String {
        var lines: [String] = [
            "# OpenSim MCP Tools Reference \(version)",
            "",
            "Generated from OperationCatalog. Do not edit by hand.",
            "",
            "| Tool | Mode | Destructive | Parameters |",
            "|---|---|---|---|"
        ]
        for operation in sorted(catalog) {
            let mode = operation.readOnly ? "read" : "write"
            let destructive = operation.destructive ? "destructive" : "normal"
            let parameters = operation.parameters.map { "`\($0.name)`" }.joined(separator: ", ")
            lines.append("| `\(operation.mcpName)` | \(mode) | \(destructive) | \(parameters) |")
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private func sorted(_ catalog: OperationCatalog) -> [Operation] {
        catalog.operations.values.sorted {
            $0.cliPath.joined(separator: " ") < $1.cliPath.joined(separator: " ")
        }
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
    }
}
```

Create `Sources/OpenSimCLI/Commands/DocsCommand.swift`:

```swift
import ArgumentParser
import Foundation
import OpenSimCore

struct DocsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "docs",
        abstract: "Generate CLI and MCP reference from OperationCatalog"
    )

    @Option(name: .long, help: "Output directory")
    var out = "docs"

    @Flag(name: .long, help: "Fail when generated files differ from disk")
    var check = false

    func run() throws {
        let catalog = OpenSimCommandCatalog.make()
        let renderer = DocsRenderer()
        let files: [String: String] = [
            "cli-reference.md": renderer.cliReference(catalog: catalog, version: OpenSimVersion.current),
            "mcp-tools-reference.md": renderer.mcpToolsReference(catalog: catalog, version: OpenSimVersion.current)
        ]
        let directory = URL(fileURLWithPath: out, isDirectory: true)
        var stale: [String] = []
        for (name, content) in files.sorted(by: { $0.key < $1.key }) {
            let url = directory.appendingPathComponent(name)
            if check {
                let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                if existing != content {
                    stale.append(name)
                }
            } else {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try content.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        if check, !stale.isEmpty {
            print("Stale documentation: \(stale.joined(separator: ", "))")
            throw ExitCode(10)
        }
        print(check ? "OK docs" : "Generated \(files.count) files in \(out)")
    }
}
```

Create `Sources/OpenSimCLI/Commands/OpenSimCommandCatalog.swift` bằng cách gộp các catalog đã có từ Plan 1-5:

```swift
import OpenSimCore

enum OpenSimCommandCatalog {
    static func make() -> OperationCatalog {
        OperationCatalog.openSim()
    }
}
```

`OperationCatalog.openSim()` là factory duy nhất: `plan5()` (Plan 2 `ui_*` + storage/perf) và các platform registration được thêm bởi Plan 9/10. Không có `registerUIOperations()` và không đăng ký operation ở Plan 7.

Đăng ký command:

```swift
DocsCommand.self,
```

Trong `OpenSimCommand`, thay phần dựng catalog bằng `OpenSimCommandCatalog.make()`.

- [ ] **Step 4: Sinh tài liệu và thêm check CI**

Run:

```bash
swift build --product opensim
.build/debug/opensim docs --out docs
.build/debug/opensim docs --check
```

Expected: `Generated 2 files in docs`; `OK docs`.

Thêm bước vào `.github/workflows/ci.yml` sau `Unit tests`:

```yaml
      - name: Docs freshness
        run: .build/debug/opensim docs --check
```

- [ ] **Step 5: Viết README và tài liệu tĩnh**

Create `README.md`:

````markdown
# OpenSim

OpenSim điều khiển simulator của Apple cho iOS, iPadOS, watchOS và tvOS qua CLI, MCP và app macOS. OpenSim không viết lại emulator; nó dùng runtime của Apple.

## Yêu cầu

- macOS 27.0 trở lên, Apple Silicon.
- Full Xcode 27.1 (không hỗ trợ Command Line Tools-only).
- Runtime iOS 27.0; watchOS/tvOS 27.0 cho test đa nền tảng.

## Cài đặt

```bash
brew install opensim/tap/opensim
brew install --cask opensim/tap/opensim-app
opensim setup
opensim doctor --json
```

Nếu chưa có Developer ID build, cài từ source:

```bash
git clone https://github.com/opensim/open-simulator.git
cd open-simulator
swift build -c release
.build/release/opensim setup
```

## Bắt đầu

```bash
opensim device boot --device "iPhone Air" --wait
opensim app install ./Build/MyApp.app --device "iPhone Air"
opensim app launch com.example.myapp --device "iPhone Air"
opensim ui tree --device "iPhone Air" --json
opensim ui tap --on 'id=fixture-primary-button' --device "iPhone Air"
opensim ui screenshot --device "iPhone Air" --out /tmp/screen.png
```

MCP stdio:

```bash
opensim mcp --stdio
```

MCP HTTP loopback dùng chung daemon tại `/mcp` với Bearer token trong state file.

## Cảnh báo private API

OpenSim dùng private framework `SimulatorKit` và `CoreSimulator` đã có trên máy, chỉ trong tiến trình local. OpenSim không phân phối qua Mac App Store, không upload dữ liệu, không telemetry. Private API có thể đổi giữa các bản Xcode; xem `docs/compatibility.md` và chạy `opensim doctor` sau mỗi lần nâng Xcode.

## Tài liệu

- `docs/README.md`: mục lục.
- `docs/cli-reference.md`: sinh từ catalog.
- `docs/mcp-tools-reference.md`: sinh từ catalog.
- `docs/security.md`: mô hình bảo mật và quyết định ký.
- `docs/troubleshooting.md`: lỗi thường gặp.
- `docs/contributing.md`: quy trình đóng góp.

## License

MIT.
````

Create `docs/README.md`:

```markdown
# OpenSim Documentation

| Tài liệu | Nội dung |
|---|---|
| `architecture.md` | Tầng module, process model, ranh giới private API |
| `cli-reference.md` | Sinh từ catalog |
| `mcp-tools-reference.md` | Sinh từ catalog |
| `compatibility.md` | Ma trận Xcode/runtime và suy giảm capability |
| `security.md` | Loopback, token, path, private API, ký |
| `security-review-checklist.md` | Checklist review có bằng chứng |
| `troubleshooting.md` | Lỗi và cách xử lý |
| `release-checklist.md` | Các bước phát hành |
| `release-rollback.md` | Rollback |
| `known-issues-template.md` | Mẫu known issues |
| `contributing.md` | Build, test, commit, review |
```

Create `docs/architecture.md` với các mục bắt buộc:

```markdown
# OpenSim Architecture

## Tầng

- `OpenSimCore`: domain, protocol, catalog, error, envelope; không AppKit, không private framework.
- `OpenSimBridge`: nơi duy nhất chạm CoreSimulator/SimulatorKit, dynamic load, capability, fallback `simctl`.
- `OpenSimBridgeUI`: NSView wrapper cho screen và gesture.
- `OpenSimProtocol`: Codable request/response/event.
- `OpenSimDaemon`: HTTP/SSE loopback, session/lease, storage, metrics.
- `OpenSimCLI`: parse argument, gọi daemon, render bảng/JSON.
- `OpenSimMCP`: JSON-RPC stdio và HTTP, adapter từ catalog.
- `OpenSimApp`: SwiftUI shell, cửa sổ device, lease UX.

## Process model

- Daemon chạy trong user session qua LaunchAgent `dev.opensim.daemon`.
- State file `~/Library/Application Support/OpenSim/daemon.json`, quyền `0600`.
- App render in-process; CLI/MCP đi qua daemon.
- App đóng không làm chết daemon.

## Ranh giới private API

- Chỉ `OpenSimBridge` được `dlopen` CoreSimulator/SimulatorKit.
- Mọi private API có capability check và fallback `simctl`.
- Developer dir chỉ chấp nhận dưới `/Applications` hoặc `/Library/Developer`.

## Dữ liệu

- Audit JSONL: `~/Library/Application Support/OpenSim/audit.jsonl`.
- Daemon log: `~/Library/Logs/OpenSim/daemon.log`, rotate 10 MB x 5.
- Không có database, không telemetry.
```

Create `docs/troubleshooting.md`:

```markdown
# Troubleshooting

| Triệu chứng | Nguyên nhân | Cách xử lý |
|---|---|---|
| `xcode_not_found` | Chưa chọn full Xcode | `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` |
| `unsupported_xcode` | Xcode cũ hoặc CLT-only | Cài Xcode 27.1; chạy `opensim doctor --json` |
| `private_api_unavailable` | SimulatorKit đổi API | Chạy `opensim doctor`; xem `docs/compatibility.md`; dùng screenshot polling |
| `daemon_unavailable` | Daemon chết hoặc state cũ | `opensim daemon restart`; kiểm tra `~/Library/Logs/OpenSim/daemon.log` |
| `lease_conflict` | Agent khác giữ control | Chờ TTL 5 phút hoặc dùng `Take control` trong app |
| `confirmation_required` | Thiếu `--yes` hoặc `confirm` | Chạy lại với `--yes` sau khi kiểm tra target |
| `input_failed` | HID không khả dụng | Chạy `opensim doctor`; kiểm tra capability `hid` |
| `a11y_unavailable` | Private accessibility không dùng được | Dùng `ui_find` theo tọa độ hoặc XCUITest helper |
| Notarization bị từ chối | Thiếu timestamp hoặc quyền | Chạy `Scripts/release/verify-signature.sh`; xem log `notarytool` |
| Gatekeeper chặn CLI | Chưa staple hoặc tải bằng trình duyệt | Cài qua Homebrew; chạy `spctl -a -vvv -t exec` |
```

Create `docs/security.md`:

```markdown
# Security Model

## Bề mặt

- Daemon bind `127.0.0.1`, port động, kiểm tra `Host` và `Origin`, không CORS.
- Bearer token 32 byte sinh mỗi lần start; file `0600`, thư mục `0700`.
- CLI/MCP đọc state file; không có endpoint LAN.

## Input

- Không shell string; mọi process dùng argument array.
- UDID validate theo UUID; bundle ID theo regex; path theo allowlist root và resolve symlink.
- Developer dir chỉ dưới `/Applications` hoặc `/Library/Developer`; từ chối path từ client.
- Destructive operation cần `confirm` hoặc plan token; audit mọi lần.

## Private API

- Chỉ `OpenSimBridge` dynamic load CoreSimulator/SimulatorKit.
- Không dùng private API để vượt quyền hệ thống hoặc đọc dữ liệu ngoài simulator.
- OpenSim chỉ dùng local, open-source, không Mac App Store.

## Ký và notarization

- Developer ID Application, Hardened Runtime, timestamp.
- App Sandbox tắt; `disable-library-validation` mặc định `false`.
- Library validation decision: chỉ bật khi helper `opensim doctor` fail với lỗi chữ ký SimulatorKit; ghi lý do, ngày, log `codesign -dv --verbose=4` và owner ký tên vào mục này.

## Dữ liệu

- Không telemetry, không upload log/screenshot.
- Log có thể chứa dữ liệu app; cảnh báo trước khi export.
- Audit rotate 50 MB; state/log không chứa token sau khi daemon stop.
```

Create `docs/contributing.md`:

````markdown
# Contributing

## Build

```bash
swift build
swift test
xcodegen generate --spec App/project.yml
```

## Test

```bash
Scripts/ci/run-unit.sh
OPENSIM_INTEGRATION=1 swift test --filter IntegrationTests
```

## Quy ước

- Swift 6 language mode; không thêm dependency ngoài `swift-argument-parser`, `swift-log`, Hummingbird 2.x.
- Không gọi private API ngoài `OpenSimBridge`.
- Không shell string; dùng `Process` với argument array.
- Mỗi thay đổi hành vi có test; mỗi commit nhỏ, message theo conventional commits.
- Chạy `opensim docs --check` sau khi đổi catalog.

## Pull request

- Mô tả hành vi, test đã chạy, ảnh hưởng compatibility.
- Không commit `build/`, `.build/`, artifact notarization, token, state file.
- Reviewer chạy `Scripts/security/check-no-telemetry.sh` và `Scripts/security/check-no-shell-strings.sh`.
````

- [ ] **Step 6: Chạy check và commit**

Run:

```bash
.build/debug/opensim docs --out docs
.build/debug/opensim docs --check
swift test --filter DocsCommandTests
```

Expected: `OK docs`; `Executed 3 tests, with 0 failures`.

```bash
git add Sources/OpenSimCLI Sources/OpenSimCLITests/DocsCommandTests.swift docs README.md .github/workflows/ci.yml
git commit -m "docs: generate cli and mcp references from catalog"
```

---

### Task 13: Release checklist, rollback, known issues và changelog

**Files:**
- Create: `docs/release-checklist.md`
- Create: `docs/release-rollback.md`
- Create: `docs/known-issues-template.md`
- Create: `CHANGELOG.md`
- Create: `Scripts/release/changelog.sh`
- Create: `Tests/Release/test-changelog.sh`

**Interfaces:**
- Consumes: `VERSION`, git history theo conventional commits.
- Produces: checklist có thứ tự gate; rollback từng giai đoạn; `Scripts/release/changelog.sh [--from <ref>] [--write]` in Markdown.

- [ ] **Step 1: Viết test changelog thất bại**

Create `Tests/Release/test-changelog.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cd "$WORK"
git init -q
git config user.email "test@opensim.dev"
git config user.name "OpenSim Test"
printf "init\n" > README.md
git add README.md
git commit -q -m "chore: initial"
printf "a\n" > file.txt
git add file.txt
git commit -q -m "feat(cli): add device boot"
printf "b\n" >> file.txt
git add file.txt
git commit -q -m "fix(daemon): reject foreign host"
printf "c\n" >> file.txt
git add file.txt
git commit -q -m "docs: update readme"

OUT="$("$ROOT/Scripts/release/changelog.sh" --from "$(git rev-list --max-parents=0 HEAD)")"
print -r -- "$OUT" | grep -q "### Features"
print -r -- "$OUT" | grep -q "add device boot"
print -r -- "$OUT" | grep -q "### Bug Fixes"
print -r -- "$OUT" | grep -q "reject foreign host"
if print -r -- "$OUT" | grep -q "update readme"; then
  print -u2 "docs commit leaked into changelog"
  exit 1
fi
print "OK changelog"
```

Run:

```bash
chmod +x Tests/Release/test-changelog.sh
Tests/Release/test-changelog.sh
```

Expected: FAIL vì `Scripts/release/changelog.sh` chưa tồn tại.

- [ ] **Step 2: Viết script changelog**

Create `Scripts/release/changelog.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
FROM=""
WRITE="0"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from)
      FROM="$2"
      shift 2
      ;;
    --write)
      WRITE="1"
      shift
      ;;
    *)
      print -u2 "unknown argument: $1"
      exit 2
      ;;
  esac
done
cd "$ROOT"
if [[ -z "$FROM" ]]; then
  FROM="$(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)"
fi
VERSION="$(tr -d '[:space:]' < VERSION)"

emit_group() {
  local title="$1"
  local pattern="$2"
  local lines
  lines="$(git log --no-merges --pretty=format:'%s' "$FROM"..HEAD | grep -E "$pattern" || true)"
  if [[ -n "$lines" ]]; then
    print "### $title"
    print ""
    print -r -- "$lines" | while IFS= read -r subject; do
      print "- ${subject#*: }"
    done
    print ""
  fi
}

OUTPUT="# Changelog

## $VERSION

"
OUTPUT+="$(emit_group "Features" '^feat(\(.+\))?: ')"
OUTPUT+="$(emit_group "Bug Fixes" '^fix(\(.+\))?: ')"
OUTPUT+="$(emit_group "Performance" '^perf(\(.+\))?: ')"
OUTPUT+="$(emit_group "Security" '^(security|fix\(security\))')"

if [[ "$WRITE" == "1" ]]; then
  print -r -- "$OUTPUT" > CHANGELOG.md
  print "Wrote CHANGELOG.md"
else
  print -r -- "$OUTPUT"
fi
```

- [ ] **Step 3: Viết checklist, rollback, known issues**

Create `docs/release-checklist.md`:

```markdown
# Release Checklist

- Version: đọc từ `VERSION`
- Runner: self-hosted macOS 27, Xcode 27.1
- Người release: ghi tên
- Ngày: ghi ngày

## Trước build

- [ ] `Scripts/release/verify-versions.sh` in `OK versions`.
- [ ] `Scripts/ci/run-unit.sh` in `OK unit`.
- [ ] `Scripts/ci/run-integration.sh` in `OK integration`.
- [ ] Nightly gần nhất xanh trên nhánh `main`.
- [ ] `docs/security-review-checklist.md` được owner ký.
- [ ] `docs/compatibility.md` khớp Xcode/runtime đã test.
- [ ] `CHANGELOG.md` có mục version hiện tại.

## Build và ký

- [ ] `OPENSIM_TEAM_ID="$OPENSIM_TEAM_ID" Scripts/release/build-app.sh` in `OK build`.
- [ ] `Scripts/release/notarize.sh build/release/OpenSim.app` in `OK notarized`.
- [ ] `Scripts/release/verify-signature.sh` in `OK signature`.
- [ ] `Scripts/release/package-dmg.sh` in `OK package` cho DMG và tarball.
- [ ] `Scripts/release/notarize.sh build/release/OpenSim-$VERSION.dmg` in `OK notarized`.
- [ ] `Tests/Release/test-notarization.sh` in `OK notarization`.

## Cài đặt

- [ ] `Tests/Release/test-brew-install.sh` với `OPENSIM_RELEASE_CHANNEL=local` in `OK brew metadata`.
- [ ] Trên máy sạch: `Tests/Release/test-clean-install.sh` in `OK clean install`.
- [ ] `opensim setup` in `Loaded: true`.
- [ ] `opensim doctor --json` trả `ok=true` và `capabilities.hid=available`.
- [ ] `Tests/Release/test-e2e-agent.sh` in `OK agent scenario`.
- [ ] `Tests/Release/test-ui-smoke.sh` in `OK ui smoke`.
- [ ] `Tests/Release/test-visionos.sh` skip hợp lệ vì visionOS ngoài phạm vi release này.

## Phát hành

- [ ] `Scripts/release/publish.sh` tạo tag, GitHub release, upload DMG/tarball/checksum.
- [ ] `Scripts/release/update-tap.sh` sinh cask/formula với SHA256 của artifact vừa upload.
- [ ] Mở PR tap, merge sau khi `brew audit --cask opensim-app` pass.
- [ ] `brew install --cask opensim/tap/opensim-app` và `brew install opensim/tap/opensim` trên máy sạch thứ hai.
- [ ] Ghi known issues từ `docs/known-issues-template.md`.

## Sau phát hành

- [ ] Đợi 24 giờ, kiểm tra issue mới và nightly.
- [ ] Nếu có regression, làm theo `docs/release-rollback.md`.
```

Create `docs/release-rollback.md`:

```markdown
# Release Rollback

## Trước khi publish

1. Dừng pipeline, không upload artifact.
2. Xoá tag cục bộ: `git tag -d "v$VERSION"`.
3. Sửa lỗi, tăng patch version, chạy lại checklist từ đầu.

## Sau khi publish, trước khi merge tap

1. Yank GitHub release: `gh release delete "v$VERSION" --yes --cleanup-tag`.
2. Xoá artifact trên release cũ nếu còn.
3. Chạy `Scripts/release/update-tap.sh` với version trước đó, mở PR tap revert.
4. Thông báo trong issue pinned: version lỗi, triệu chứng, version thay thế.

## Sau khi merge tap

1. Revert PR tap về commit trước; merge ngay.
2. `brew update && brew uninstall --cask opensim-app && brew install --cask opensim/tap/opensim-app` để hạ version.
3. `brew uninstall opensim && brew install opensim/tap/opensim`.
4. Chạy `opensim setup` lại để nạp LaunchAgent đúng binary.
5. Giữ release lỗi ở trạng thái draft, không xoá lịch sử issue.

## Rollback do private API

1. Chạy `opensim doctor --json`; xác định capability mất.
2. Phát hành patch chỉ hạ compatibility mode, không hạ version Xcode yêu cầu.
3. Nếu không thể sửa trong 24 giờ, ghi known issue và hướng dẫn dùng screenshot polling.
```

Create `docs/known-issues-template.md`:

```markdown
# Known Issues for $VERSION

## Môi trường

- macOS:
- Xcode:
- Runtime:
- Mode compatibility:

## Vấn đề

### Short title

- Triệu chứng:
- Phạm vi ảnh hưởng:
- Nguyên nhân:
- Workaround:
- Theo dõi:

## Không hỗ trợ trong bản này

- visionOS: ngoài phạm vi, xem Plan 8.
- Thiết bị thật: ngoài phạm vi, xem Plan 9.
- LLDB/debugger: ngoài phạm vi.
```

- [ ] **Step 4: Chạy test để thấy pass**

Run:

```bash
chmod +x Scripts/release/changelog.sh
Tests/Release/test-changelog.sh
Scripts/release/changelog.sh --write
head -20 CHANGELOG.md
```

Expected: `OK changelog`; `Wrote CHANGELOG.md`; `CHANGELOG.md` có `## 0.1.0` và ít nhất một mục feature/fix.

- [ ] **Step 5: Commit**

```bash
git add docs/release-checklist.md docs/release-rollback.md docs/known-issues-template.md CHANGELOG.md Scripts/release/changelog.sh Tests/Release/test-changelog.sh
git commit -m "docs(release): add checklist rollback and changelog"
```

---

### Task 14: Bộ kiểm chứng phát hành

**Files:**
- Create: `Tests/Release/run-release-gate.sh`
- Create: `Tests/Release/test-clean-install.sh`
- Create: `Tests/Release/test-notarization.sh`
- Create: `Tests/Release/test-doctor.sh`
- Create: `Tests/Release/test-e2e-agent.sh`
- Create: `Tests/Release/test-ui-smoke.sh`
- Create: `Tests/OpenSimAppUITests/ReleaseSmokeTests.swift`
- Modify: `App/project.yml` (thêm UI test target `OpenSimAppUITests`)

**Interfaces:**
- Consumes: artifact `build/release/OpenSim-$VERSION.dmg`, app đã ký, fixture `build/fixtures/Build/Products/Debug-iphonesimulator/OpenSimFixture.app`, CLI trong app helper.
- Produces: `run-release-gate.sh` chạy toàn bộ gate và in `OK release gate` kèm version; mỗi script con in `OK` kèm tên script.

- [ ] **Step 1: Viết UI smoke test thất bại**

Create `Tests/OpenSimAppUITests/ReleaseSmokeTests.swift`:

```swift
import XCTest

final class ReleaseSmokeTests: XCTestCase {
    func testAppLaunchesWithMainWindow() {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
        let screenshot = XCTAttachment(screenshot: window.screenshot())
        screenshot.name = "release-smoke-main-window"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testDevicePaletteOpens() {
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 20))
        app.typeKey("k", modifierFlags: .command)
        let palette = app.sheets.firstMatch
        let window = app.windows.firstMatch
        XCTAssertTrue(palette.waitForExistence(timeout: 5) || window.exists)
    }
}
```

Thêm target vào `App/project.yml`:

```yaml
  OpenSimAppUITests:
    type: bundle.ui-testing
    platform: macOS
    sources:
      - path: ../Tests/OpenSimAppUITests
    dependencies:
      - target: OpenSim
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dev.opensim.app.uitests

schemes:
  OpenSim:
    build:
      targets:
        OpenSim: all
        OpenSimAppUITests: [test]
    test:
      targets:
        - OpenSimAppUITests
```

Create `Tests/Release/test-ui-smoke.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
cd "$ROOT"
xcodebuild test \
  -project App/OpenSim.xcodeproj \
  -scheme OpenSim \
  -destination "platform=macOS" \
  -derivedDataPath build/uitest \
  -only-testing:OpenSimAppUITests/ReleaseSmokeTests
print "OK ui smoke"
```

Run:

```bash
chmod +x Tests/Release/test-ui-smoke.sh
xcodegen generate --spec App/project.yml
Tests/Release/test-ui-smoke.sh
```

Expected: FAIL nếu target UI test chưa có trong project; sau khi thêm target, test PASS và in `OK ui smoke`.

- [ ] **Step 2: Viết các script kiểm chứng**

Create `Tests/Release/test-notarization.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
DMG="$ROOT/build/release/OpenSim-$VERSION.dmg"
APP="$ROOT/build/release/OpenSim.app"
if [[ ! -f "$DMG" ]]; then
  print -u2 "missing dmg: $DMG"
  exit 1
fi
xcrun stapler validate "$DMG"
xcrun stapler validate "$APP"
SPCTL="$(/usr/sbin/spctl -a -vvv -t open --context context:primary-signature "$DMG" 2>&1)"
if ! print -r -- "$SPCTL" | grep -q "accepted"; then
  print -r -- "$SPCTL"
  exit 1
fi
MOUNT="$(mktemp -d)"
hdiutil attach -nobrowse -quiet -mountpoint "$MOUNT" "$DMG"
trap 'hdiutil detach "$MOUNT" -quiet || true; rm -rf "$MOUNT"' EXIT
codesign --verify --strict --verbose=2 "$MOUNT/OpenSim.app"
"$MOUNT/OpenSim.app/Contents/Helpers/opensim" --version | grep -q "$VERSION"
print "OK notarization"
```

Create `Tests/Release/test-doctor.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
CLI="${OPENSIM_CLI:-$ROOT/build/release/OpenSim.app/Contents/Helpers/opensim}"
REPORT="$("$CLI" doctor --json)"
print -r -- "$REPORT" | jq -e '.ok == true' >/dev/null
print -r -- "$REPORT" | jq -e '.data.capabilities | has("render") and has("hid") and has("accessibility") and has("screenshot") and has("video") and has("watch") and has("tv")' >/dev/null
"$CLI" --version | grep -q "$VERSION"
"$CLI" daemon stop >/dev/null 2>&1 || true
print "OK doctor"
```

Create `Tests/Release/test-e2e-agent.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
CLI="${OPENSIM_CLI:-$ROOT/build/release/OpenSim.app/Contents/Helpers/opensim}"
FIXTURE="${OPENSIM_FIXTURE_PATH:-$ROOT/build/fixtures/Build/Products/Debug-iphonesimulator/OpenSimFixture.app}"
OUT="$ROOT/build/release/e2e"
mkdir -p "$OUT"
if [[ ! -d "$FIXTURE" ]]; then
  print -u2 "missing fixture: $FIXTURE"
  exit 1
fi

DEVICE_TYPE="$(xcrun simctl list devicetypes -j | jq -r '[.devicetypes[] | select(.name | startswith("iPhone"))][0].identifier')"
UDID="$("$CLI" device create "OpenSim Release E2E" --type "$DEVICE_TYPE" --json | jq -r '.data.id')"
cleanup() {
  "$CLI" app terminate dev.opensim.fixture --device "$UDID" >/dev/null 2>&1 || true
  "$CLI" device shutdown --device "$UDID" >/dev/null 2>&1 || true
  "$CLI" device delete --device "$UDID" --yes >/dev/null 2>&1 || true
}
trap cleanup EXIT

"$CLI" device boot --device "$UDID" --wait --json | jq -e '.ok == true' >/dev/null
"$CLI" app install "$FIXTURE" --device "$UDID" --json | jq -e '.ok == true' >/dev/null
"$CLI" app launch dev.opensim.fixture --device "$UDID" --json | jq -e '.ok == true' >/dev/null

TREE="$("$CLI" ui tree --device "$UDID" --json)"
print -r -- "$TREE" | jq -e '[.. | objects | select(.identifier? == "fixture-primary-button")] | length > 0' >/dev/null
"$CLI" ui screenshot --device "$UDID" --out "$OUT/before.png" >/dev/null
"$CLI" ui tap --on 'id=fixture-primary-button' --device "$UDID" --json | jq -e '.ok == true' >/dev/null
sleep 1
"$CLI" ui screenshot --device "$UDID" --out "$OUT/after-tap.png" >/dev/null
if [[ "$(shasum -a 256 "$OUT/before.png" | awk '{print $1}')" == "$(shasum -a 256 "$OUT/after-tap.png" | awk '{print $1}')" ]]; then
  print -u2 "screen did not change after tap"
  exit 1
fi

"$CLI" ui tap --on 'id=fixture-text-field' --device "$UDID" --json >/dev/null
"$CLI" ui type "agent@opensim.dev" --device "$UDID" --json | jq -e '.ok == true' >/dev/null
"$CLI" ui tree --device "$UDID" --json | jq -e '[.. | objects | select(.identifier? == "fixture-text-field")][0].value == "agent@opensim.dev"' >/dev/null

printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"release-gate","version":"1.0"}}}' \
  | "$CLI" mcp --stdio \
  | jq -e '.result.serverInfo.name == "opensim"' >/dev/null

print "OK agent scenario"
```

Create `Tests/Release/test-clean-install.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
DMG="$ROOT/build/release/OpenSim-$VERSION.dmg"
if [[ "${OPENSIM_CLEAN_MAC:-0}" != "1" ]]; then
  print -u2 "refusing to run: set OPENSIM_CLEAN_MAC=1 on a clean macOS 27 machine"
  exit 1
fi
if [[ -d /Applications/OpenSim.app ]]; then
  print -u2 "OpenSim.app already exists; this is not a clean machine"
  exit 1
fi
if brew list --cask opensim-app >/dev/null 2>&1; then
  print -u2 "opensim-app cask already installed; this is not a clean machine"
  exit 1
fi

MOUNT="$(mktemp -d)"
cleanup() {
  hdiutil detach "$MOUNT" -quiet || true
  rm -rf "$MOUNT"
  rm -rf /Applications/OpenSim.app
  "$ROOT/build/release/OpenSim.app/Contents/Helpers/opensim" uninstall --yes --purge >/dev/null 2>&1 || true
}
trap cleanup EXIT

hdiutil attach -nobrowse -quiet -mountpoint "$MOUNT" "$DMG"
ditto "$MOUNT/OpenSim.app" /Applications/OpenSim.app
/usr/sbin/spctl -a -vvv -t exec /Applications/OpenSim.app 2>&1 | grep -q "accepted"
/Applications/OpenSim.app/Contents/Helpers/opensim setup --yes --json | jq -e '.loaded == true' >/dev/null
/Applications/OpenSim.app/Contents/Helpers/opensim doctor --json | jq -e '.ok == true' >/dev/null
/Applications/OpenSim.app/Contents/Helpers/opensim uninstall --yes --purge --json | jq -e '.purged == true' >/dev/null
test ! -e "$HOME/Library/LaunchAgents/dev.opensim.daemon.plist"
print "OK clean install"
```

Create `Tests/Release/run-release-gate.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
cd "$ROOT"
VERSION="$(tr -d '[:space:]' < VERSION)"
if [[ -n "${OPENSIM_RELEASE_VERSION:-}" && "$OPENSIM_RELEASE_VERSION" != "$VERSION" ]]; then
  print -u2 "release version $OPENSIM_RELEASE_VERSION does not match VERSION $VERSION"
  exit 1
fi

Scripts/release/verify-versions.sh
Scripts/ci/run-unit.sh
Scripts/security/check-no-shell-strings.sh
Scripts/security/check-no-telemetry.sh
Tests/Release/test-security-scripts.sh
Tests/Release/test-changelog.sh
.build/debug/opensim docs --check
OPENSIM_TEAM_ID="${OPENSIM_TEAM_ID:?set OPENSIM_TEAM_ID}" Scripts/release/build-app.sh
Scripts/release/notarize.sh build/release/OpenSim.app
Scripts/release/verify-signature.sh
Scripts/release/package-dmg.sh
Scripts/release/notarize.sh "build/release/OpenSim-$VERSION.dmg"
Tests/Release/test-notarization.sh
Tests/Release/test-brew-install.sh
Tests/Release/test-doctor.sh
Scripts/ci/build-fixtures.sh
Tests/Release/test-e2e-agent.sh
Tests/Release/test-ui-smoke.sh

if [[ "${OPENSIM_CLEAN_MAC:-0}" == "1" ]]; then
  Tests/Release/test-clean-install.sh
else
  print "SKIP clean install: set OPENSIM_CLEAN_MAC=1 on a dedicated clean runner"
fi

print "OK release gate $VERSION"
```

- [ ] **Step 3: Chạy từng script để thấy trạng thái**

Run:

```bash
chmod +x Tests/Release/run-release-gate.sh Tests/Release/test-clean-install.sh Tests/Release/test-notarization.sh Tests/Release/test-doctor.sh Tests/Release/test-e2e-agent.sh Tests/Release/test-ui-smoke.sh
Tests/Release/test-clean-install.sh
```

Expected: FAIL với `refusing to run: set OPENSIM_CLEAN_MAC=1` khi chưa đặt biến.

Run trên runner đã build artifact:

```bash
OPENSIM_TEAM_ID="$OPENSIM_TEAM_ID" Tests/Release/run-release-gate.sh
```

Expected: `OK release gate 0.1.0`; dòng `SKIP clean install` khi `OPENSIM_CLEAN_MAC=0`.

- [ ] **Step 4: Commit**

```bash
git add Tests/Release Tests/OpenSimAppUITests App/project.yml
git commit -m "test(release): add gate scripts and ui smoke"
```

---

### Task 15: Release candidate và publish

**Files:**
- Create: `Scripts/release/bump-version.sh`
- Create: `Scripts/release/publish.sh`
- Modify: `docs/release-checklist.md` (điền version thực tế khi chạy)

**Interfaces:**
- Consumes: `VERSION`, `OpenSimVersion.current`, `Tests/Release/run-release-gate.sh`, `Scripts/release/update-tap.sh`.
- Produces: tag `v$VERSION`, GitHub release với DMG/tarball/checksum, tap commit.

- [ ] **Step 1: Viết script bump version**

Create `Scripts/release/bump-version.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
NEW="${1:?usage: bump-version.sh <major.minor.patch>}"
if ! print -r -- "$NEW" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  print -u2 "version must be SemVer major.minor.patch"
  exit 2
fi
print -r -- "$NEW" > "$ROOT/VERSION"
sed -i '' "s/public static let current = \".*\"/public static let current = \"$NEW\"/" \
  "$ROOT/Sources/OpenSimCore/Support/OpenSimVersion.swift"
"$ROOT/Scripts/release/verify-versions.sh"
git -C "$ROOT" add VERSION Sources/OpenSimCore/Support/OpenSimVersion.swift
git -C "$ROOT" commit -m "release: bump version to $NEW"
print "OK bump $NEW"
```

- [ ] **Step 2: Viết script publish**

Create `Scripts/release/publish.sh`:

```zsh
#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h:h}"
cd "$ROOT"
VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v$VERSION"
DMG="build/release/OpenSim-$VERSION.dmg"
TARBALL="build/release/opensim-$VERSION-arm64.tar.gz"

if [[ -n "$(git status --porcelain)" ]]; then
  print -u2 "working tree is not clean"
  exit 1
fi
if git rev-parse "$TAG" >/dev/null 2>&1; then
  print -u2 "tag $TAG already exists"
  exit 1
fi

Tests/Release/run-release-gate.sh
Scripts/release/update-tap.sh
shasum -a 256 "$DMG" "$TARBALL" > build/release/SHA256SUMS

git tag -a "$TAG" -m "OpenSim $VERSION"
git push origin "$TAG"
gh release create "$TAG" \
  "$DMG" \
  "$TARBALL" \
  build/release/SHA256SUMS \
  --title "OpenSim $VERSION" \
  --notes-file CHANGELOG.md \
  --verify-tag

if [[ -n "${OPENSIM_TAP_DIR:-}" ]]; then
  cp Homebrew/Casks/opensim-app.rb "$OPENSIM_TAP_DIR/Casks/opensim-app.rb"
  cp Homebrew/Formula/opensim.rb "$OPENSIM_TAP_DIR/Formula/opensim.rb"
  git -C "$OPENSIM_TAP_DIR" add Casks/opensim-app.rb Formula/opensim.rb
  git -C "$OPENSIM_TAP_DIR" commit -m "opensim $VERSION"
  git -C "$OPENSIM_TAP_DIR" push
  print "OK tap $VERSION"
else
  print "Tap files generated; set OPENSIM_TAP_DIR to commit them to the tap checkout"
fi
print "OK publish $VERSION"
```

- [ ] **Step 3: Chạy dry-run cục bộ**

Run:

```bash
chmod +x Scripts/release/bump-version.sh Scripts/release/publish.sh
Scripts/release/verify-versions.sh
git status --porcelain
```

Expected: `OK versions 0.1.0`; working tree sạch trước khi bump. Không chạy `publish.sh` trong môi trường soạn plan hoặc khi chưa có artifact đã notarize.

- [ ] **Step 4: Commit**

```bash
git add Scripts/release/bump-version.sh Scripts/release/publish.sh docs/release-checklist.md
git commit -m "release: add version bump and publish scripts"
```

---

## Spec coverage

| Mục spec | Nội dung | Task |
|---|---|---|
| 5.4 | Ranh giới private API, developer dir allowlist | 3, 6 |
| 5.6 | Tương thích macOS/Xcode/runtime, compat mode | 6 |
| 9.3 | UI disable feature khi capability thiếu, banner | 6 |
| 12 | Loopback, token, Host/Origin, shell, path, confirm, audit, library validation, no telemetry | 1, 2, 3, 4, 5, 9 |
| 13 | Doctor, log, audit, crash/restart | 2, 4, 6, 11 |
| 14.1 | Unit test domain, catalog, path, envelope | 3, 6, 7 |
| 14.2 | Integration lifecycle, input, a11y, lease, daemon, storage, perf, CLI/MCP contract | 8, 14 |
| 14.3 | UI test app, checklist thị giác | 14 |
| 14.4 | CI unit/lint, integration self-hosted, nightly, release gate, matrix, UI smoke | 7, 8, 14 |
| 15 | SwiftPM/XcodeGen, dependencies, bundle ID, Homebrew tap, Developer ID, setup, doctor, uninstall, update, MIT, README | 9, 10, 11, 12 |
| 17.1 mục 1 | Máy sạch cài Homebrew, doctor pass | 10, 14 |
| 17.1 mục 2-6 | Boot, install, launch, tree, tap, type, screenshot fixture | 14 |
| 17.1 mục 7 | MCP stdio và HTTP | 14 |
| 17.1 mục 8 | Hai agent, lease conflict | 8 (integration có sẵn từ Plan 3), 14 |
| 17.1 mục 9 | App device window, gesture, switch, take control | 14 |
| 17.1 mục 10-11 | Storage và performance | 8 (integration có sẵn từ Plan 5) |
| 17.1 mục 12 | watchOS/tvOS boot, render, screenshot, tap | 8, 14 |
| 17.1 mục 13 | Doctor phát hiện thiếu Xcode/sai version | 6, 11 |
| 18 | Rủi ro private API, version gate, chính sách Apple | 5, 6, 12 |
| 19 | Release simulator gồm iOS/iPadOS/watchOS/tvOS; visionOS ngoài phạm vi | 6, 14 |

## Exit criteria

1. `Scripts/ci/run-unit.sh` in `OK unit`; workflow `ci` xanh trên `macos-27`.
2. `Scripts/security/check-loopback.sh`, `check-token-permissions.sh`, `check-no-shell-strings.sh`, `check-no-telemetry.sh`, `check-audit-coverage.sh` đều in `OK`; `docs/security-review-checklist.md` được owner ký.
3. `swift test --filter NetworkBoundaryTests` pass 7 test; `PathAllowlistTests` pass 5; `DeveloperDirPolicyTests` pass 4; `DestructiveOperationTests` pass 2.
4. `opensim doctor --json` trả `ok=true`, `compatibility.mode=supported` trên Xcode 27.1, và `mode=bestEffort` trên Xcode 27.0.
5. `opensim docs --check` in `OK docs`; `docs/cli-reference.md` và `docs/mcp-tools-reference.md` khớp catalog.
6. `Scripts/release/build-app.sh` in `OK build 0.1.0`; `Scripts/release/verify-signature.sh` in `OK signature`; `Tests/Release/test-notarization.sh` in `OK notarization`.
7. `Tests/Release/test-clean-install.sh` in `OK clean install` trên máy macOS 27 sạch; `Tests/Release/test-brew-install.sh` với `OPENSIM_RELEASE_CHANNEL=published` in `OK brew install`.
8. `Tests/Release/test-doctor.sh` in `OK doctor`; `Tests/Release/test-e2e-agent.sh` in `OK agent scenario`; `Tests/Release/test-ui-smoke.sh` in `OK ui smoke`.
9. `Tests/Release/run-release-gate.sh` in `OK release gate 0.1.0`; GitHub release có DMG, tarball, SHA256SUMS; tap cask/formula cài được trên máy sạch thứ hai.
10. `CHANGELOG.md` có mục `## 0.1.0`; `docs/release-checklist.md` đã tick đủ; `docs/release-rollback.md` và `docs/known-issues-template.md` tồn tại và được tham chiếu từ checklist.
