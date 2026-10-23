# SparkTop

A native macOS **menu bar app** that shows your [sparkDash](https://github.com/MiaAI-Lab/sparkDash) fleet at a glance: a live `⚡` item in the menu bar and a rich fleet overview in the popover.

<p align="center">
  <img src="docs/screenshot-overview.png" width="380" alt="SparkTop popover — live fleet overview">
</p>
<p align="center">
  <em>Menu bar icon — live decode rate while a model is serving, and idle. The item keeps a sticky width (grows for wider values, never shrinks back), and the value is right-aligned so the unit never moves.</em><br><br>
  <img src="docs/screenshot-menubar.png" height="37" alt="Menu bar: live decode rate">
  &nbsp;&nbsp;
  <img src="docs/screenshot-menubar-idle.png" height="37" alt="Menu bar: idle, 0 t/s">
</p>

SparkTop is a **thin client** — sparkDash stays the single source of truth. It connects to your sparkDash server over WebSocket (`/ws`), renders the live snapshot natively in SwiftUI, and polls a couple of REST endpoints (`/api/llm-token-totals/history`, `/api/events`) for fleet-level stats. No SSH credentials ever leave the sparkDash server.

## Features

- **Menu bar item** with a live metric of your choice (Settings → *Menu bar shows*):
  - Fleet power (GPU draw, e.g. `⚡ 267W`)
  - Busiest GPU `94%`
  - Decode `82 t/s`
  - Memory in use `290G`
  - Icon only
- **Color states**: amber when a unit is offline or has health findings, red on critical findings or when sparkDash is unreachable.
- **Fleet overview popover**: per-unit cards (GPU/temp/power, unified-memory split GPU/CPU/free, CPU, network, disk, LLM backend/model/tok/s/KV-cache/requests, health findings) plus a fleet strip (power · decode · memory · tokens today) and the last activity events.
- **Right-click menu** on the bolt: *Open sparkDash*, *Settings…*, *Quit*. Left-click toggles the popover (the footer's `↗ sparkDash` also opens the full dashboard in your browser).
- **Robust connection**: WebSocket with exponential-backoff reconnect, stale-stream watchdog, ping keepalive; a rejected token is detected via `GET /api/health` and shown as *auth failed* instead of retrying forever.
- **Settings** (gear icon): server URL, access token (Keychain-backed, with an on-disk cache so startup never blocks), menu bar metric, popover behavior (*keep in front* vs *auto-hide on losing focus*), launch at login (SMAppService).
- Fully native AppKit + SwiftUI, ~900 KB binary, no Electron/webview.

## Build

```bash
./build.sh              # → dist/SparkTop.app (ad-hoc signed)
./build.sh --install    # → /Applications/SparkTop.app
./build.sh --open       # build & launch with the popover open (debug)
./build.sh --open --pin # same, but the popover stays pinned (screenshots)
```

Requires Xcode/Swift toolchain (macOS 13+ target).

## iOS & iPadOS

A native SwiftUI app built on the same data layer (`Sources/Core`): fleet overview, per-unit detail (GPU, unified memory, CPU, network, storage, LLM endpoints, health findings), and settings — over the sparkDash WebSocket like the menubar app.

```bash
brew install xcodegen
cd ios && xcodegen generate --spec project.yml && cd ..
open ios/SparkTopIOS.xcodeproj     # pick your team, run on device/simulator
```

**Installing without the App Store** (personal use):

1. Grab `SparkTop-unsigned-<version>.ipa` from a release (CI builds it on every tag), or build as above.
2. Sideload with [AltStore](https://altstore.io)/[SideStore](https://sidestore.io) (free Apple ID, 7-day re-sign) or [Sideloadly]; with a paid developer account the signature lasts a year.
3. Alternatively open `ios/SparkTopIOS.xcodeproj` in Xcode and press Run — free accounts work for your own devices.
4. On first launch iOS asks for **Local Network** permission — required to reach `http://<your-sparkdash>:5555`.

> The sparkDash web PWA (installed from the browser over HTTPS) remains the zero-install mobile option; the native app adds the fleet overview, per-unit detail and Face-ID-protected token storage.

## Configure

First launch: click the bolt → gear → set the sparkDash URL (e.g. `http://hai:5555`) and paste the access token (`SPARKDASH_TOKEN` of your server). *Test* verifies reachability and auth mode; *Save & Reconnect* applies.

<p align="center">
  <img src="docs/screenshot-settings.png" width="280" alt="SparkTop settings">
</p>

The token is stored in the login Keychain (with a fast startup cache in `defaults` domain `com.sparktop.menubar`). To pre-seed it:

```bash
defaults write com.sparktop.menubar sparkdash-token-cache '<token>'
```

## Layout

```
Sources/
├── Core/                     # platform-neutral data layer (macOS + iOS)
│   ├── Models.swift          # sparkDash snapshot/event decoding (tolerant, optional fields)
│   ├── ServerConfig.swift    # URL/token persistence, Keychain wrapper, ATS-safe requests
│   ├── SnapshotStore.swift   # WebSocket client (reconnect/watchdog) + REST polls
│   └── Fmt.swift             # shared value formatters
└── SparkTop/                 # macOS menubar app (AppKit + SwiftUI)
    ├── main.swift            # NSApplication + NSPopover wiring
    ├── Settings.swift        # menu-bar metric, popover pinning
    ├── StatusItem.swift      # NSStatusItem: metric canvas, tints, right-click menu
    └── Views/
        ├── OverviewView.swift   # fleet strip, cards, activity, footer
        ├── SparkCardView.swift  # per-unit card
        ├── SettingsView.swift   # settings pane
        └── Components.swift     # bars, chips, colors
ios/
├── project.yml               # XcodeGen spec (compiles Sources/Core + ios/SparkTopIOS)
└── SparkTopIOS/              # SwiftUI iOS/iPadOS app (list + detail + settings)
```

## Notes

- Plain-HTTP servers are supported (sparkDash on the LAN / over Tailscale); `NSAllowsArbitraryLoads` is enabled for that reason.
- The `reference/ws-snapshot-sample.json` file documents the snapshot shape the UI decodes.
- sparkDash ≥ 2.x with the standard `/ws` + REST API. Anything missing in the payload degrades to `—` rather than breaking.
