# OpenSim

**Local, agent-first control plane for Apple Simulator.**

OpenSim is an open-source replacement for the workflow lost when Xcode 27 removed `Simulator.app`. It exposes one simulator engine through a CLI, an MCP server, and a native macOS app, with deterministic leases and an audit trail for humans and AI agents.

> **Status:** design and implementation plans are complete; no runnable build yet. The repository currently contains the design spec, phased implementation plans, and UI prototypes.

## Why OpenSim

Xcode 27 replaced Simulator.app with Device Hub. `simctl` still handles device lifecycle, screenshots, video, install, launch, and logs, but it has no tap, swipe, type, or accessibility-tree commands. Agents can boot a simulator but cannot reliably operate it.

OpenSim fills that gap without writing another emulator. It controls Apple's simulator runtimes locally and keeps the agent-facing surface small, deterministic, and inspectable.

## What it will do

- Full device lifecycle: create, clone, boot, shutdown, erase, delete, rename.
- Live screen rendering in a native macOS window.
- Gestures, keyboard, hardware buttons, and paste.
- Semantic accessibility tree and selector-based actions.
- Structured screenshots, video, logs, and app install/launch.
- Runtime management, including multiple versions and importing `.dmg` runtimes.
- Disk management for simulators, runtimes, DerivedData, Archives, and caches.
- CPU and memory metrics per simulator.
- Session leases, takeover, and audit for multi-agent use.
- One engine shared by CLI, MCP, and the macOS app.

Supported platforms: iOS/iPadOS, watchOS, and tvOS. visionOS and physical devices are planned as later phases.

## Architecture

```text
OpenSimApp ─┐
OpenSimCLI ─┼── OpenSimDaemon ── OpenSimCore
OpenSimMCP ─┘          │
                    OpenSimBridge ── CoreSimulator / SimulatorKit / simctl
```

- **OpenSimCore** — domain model, operation catalog, leases, storage rules, metrics aggregation.
- **OpenSimBridge** — the only module that touches CoreSimulator, SimulatorKit, and `simctl`.
- **OpenSimDaemon** — loopback HTTP/SSE control plane, sessions, leases, audit, storage, metrics.
- **OpenSimCLI** — JSON-first `opensim` CLI.
- **OpenSimMCP** — MCP stdio and loopback HTTP server.
- **OpenSimApp** — native SwiftUI + AppKit macOS app.

## Repository layout

```text
docs/superpowers/specs/   Design spec and UI audit
docs/superpowers/plans/   Phased implementation plans (0–9) and reviews
proto/ui/                 HTML UI prototypes and screenshots
```

## Documentation

- [Design spec](docs/superpowers/specs/2026-10-19-open-simulator-design.md)
- [Plan map and shared interfaces](docs/superpowers/plans/2026-10-20-plan-map-and-interfaces.md)
- Implementation plans: [Plan 0](docs/superpowers/plans/2026-10-19-opensim-plan-0-private-api-spike.md) through [Plan 9](docs/superpowers/plans/2026-10-20-opensim-plan-9-physical-devices.md)
- [UI prototype](proto/ui/devices-v2.html)
- [UI audit](docs/superpowers/specs/2026-10-20-opensim-ui-audit.md)

## Requirements

- macOS 27.0 or later, arm64.
- Full Xcode 27.1 or later (Command Line Tools alone are not enough).
- An installed iOS simulator runtime for the core workflow.
- watchOS/tvOS runtimes for those platforms.

## Getting started

There is no installable release yet. Implementation follows the plans in order: private-API spike, core + bridge + CLI, screen/input/accessibility, daemon + MCP, macOS app, storage/performance, watchOS/tvOS, hardening/release, then visionOS and physical devices.

When Plan 1 lands, the first build target will be:

```bash
swift build
.build/debug/opensim doctor
```

## Security and Apple private APIs

OpenSim runs locally and binds its daemon to loopback only. The daemon uses a random bearer token stored with `0600` permissions, short-lived leases, and an audit log.

Live rendering, HID input, and accessibility rely on Apple private frameworks. That makes OpenSim unsuitable for the Mac App Store and sensitive to Xcode updates. Compatibility is checked at runtime and reported by `opensim doctor`; unsupported builds fall back or disable the affected capability instead of crashing.

No telemetry, screenshots, or logs are uploaded anywhere.

## Contributing

The design is intentionally documented before implementation. For now, open an issue to discuss a design or plan change before sending code. Keep the private-API boundary in `OpenSimBridge`, keep CLI/MCP behavior behind the operation catalog, and add tests with every behavior change.

## License

MIT. See [LICENSE](LICENSE).
