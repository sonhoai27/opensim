# Integration tests

Plan 1 integration tests use the real simulator and are disabled by default.

- `testSettingsAppFlow` requires one booted iOS 27 simulator and the system app `com.apple.Preferences`.
- `testTemporaryDeviceLifecycle` creates a device named `OpenSim IT <suffix>`, boots it, shuts it down, erases it, then deletes it. The test deletes the device on failure as well.

Run:

```bash
swift build
OPENSIM_INTEGRATION=1 swift test --filter Plan1SettingsIntegrationTests
```

Expected: `Executed 2 tests, with 0 failures`.

## Plan 2 fixture integration

- Requires `OPENSIM_INTEGRATION=1`, a booted iOS simulator (the test boots one if needed), and `xcodegen` for the fixture/UI-test build. The XCUITest helper uses a persistent TCP session on loopback.
- `testFixtureInputAccessibilityAndScreenshot` covers framebuffer screenshot, accessibility tree/find, tap → counter, type, long-press, swipe (pan), and `ui act`.
- `testFixtureRecording` starts/stops `simctl recordVideo`; on headless simulators this currently times out and the test is skipped with the error message.
- `testCapabilityUnavailableWithoutServices` does not require a simulator.

Run:

```bash
swift build
OPENSIM_INTEGRATION=1 swift test --filter Plan2FixtureIntegrationTests
```
