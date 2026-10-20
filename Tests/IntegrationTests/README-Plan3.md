# Plan 3 integration tests

These tests drive the real `opensim` binary and a real daemon. They need a built
binary and a full Xcode installation:

```bash
swift build
OPENSIM_INTEGRATION=1 swift test --filter Plan3DaemonIntegrationTests
```

What they cover:

- `daemon run --foreground` writes `daemon.json` (`0600`) and answers `/v1/health`; stopping removes the file.
- Restarting the daemon mints a new token and a new pid.
- A second daemon is refused by the process lock.
- `opensim device list` goes through the daemon by default and still works with `--direct`.
- A tampered token is rejected with `permission_denied`.
- `opensim mcp --stdio` answers `initialize`, `tools/list` and `tools/call`, and never prints the token.
- `opensim ui screenshot --direct` on an unknown device fails with a machine-readable error code.

Each test creates its own `OPENSIM_HOME` under `/tmp` and sets
`OPENSIM_DAEMON_AUTOSTART=0`, so no LaunchAgent is installed and the developer's
own OpenSim state is untouched.

Expected final line:

```text
Executed 6 tests, with 0 failures
```
