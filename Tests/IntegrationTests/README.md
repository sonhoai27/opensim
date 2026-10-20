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
