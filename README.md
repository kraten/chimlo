<h1 align="center"><img src=".github/chimlo-readme-icon.png" alt="" width="48" height="60" align="absmiddle">&nbsp;&nbsp;Chimlo</h1>

<p align="center">
  <strong>The macOS activity island for coding agents.</strong>
  <br>
  Watch Codex and Claude Code work, respond when they need you, then get back to your flow.
</p>

<p align="center">
  <a href="https://github.com/kraten/chimlo#-install">Install</a> ·
  <a href="https://github.com/kraten/chimlo#-features">Features</a> ·
  <a href="https://github.com/kraten/chimlo#-connect-codex-and-claude-code">Connect agents</a> ·
  <a href="https://github.com/kraten/chimlo#%EF%B8%8F-architecture">Architecture</a> ·
  <a href="https://github.com/kraten/chimlo#-contributing">Contribute</a>
</p>

<p align="center">
  <a href="https://github.com/kraten/chimlo/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/kraten/chimlo/ci.yml?branch=main&style=flat-square&label=CI" alt="CI status"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-1b1b1b?style=flat-square&logo=apple&logoColor=white" alt="macOS 14 or newer">
  <img src="https://img.shields.io/badge/Swift-6.0-c96b42?style=flat-square&logo=swift&logoColor=white" alt="Swift 6.0">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/kraten/chimlo?style=flat-square&color=5f7f59" alt="GPL-3.0 license"></a>
  <a href="https://github.com/kraten/chimlo/stargazers"><img src="https://img.shields.io/github/stars/kraten/chimlo?style=flat-square&color=8b7d52" alt="GitHub stars"></a>
</p>

<p align="center">
  <img src=".github/social-preview.png" alt="Chimlo showing Codex and Claude coding-agent sessions in the MacBook notch">
</p>

---

Long-running agents should not make you babysit a terminal. Chimlo turns the top
of your display into a small, local control surface: active work stays visible,
questions and approvals arrive where you can act on them, and completed work is
easy to reopen.

## ✨ Features

- 🤖 **Live agent sessions.** Follow concurrent Codex and Claude Code work, including what is active, waiting, done, or failed.
- ❓ **Claude questions in place.** Read the real multiple-choice prompt and send the selected option back to the blocked session.
- 🛡️ **Scoped Claude approvals.** Inspect the requested tool action, then deny it, allow it once, or allow it for the current session. Bypass mode is never exposed.
- 📊 **Real provider capacity.** See Codex and Claude usage windows from provider-owned runtime data, without reading credentials or inventing percentages.
- 🍎 **Native macOS.** Chimlo is built with AppKit and SwiftUI. There is no Electron shell and no web view.
- 🎵 **A useful notch between tasks.** Media playback plus volume and brightness feedback share the same compact surface.
- 🖥️ **Display-aware behavior.** The island adapts to notched displays, external monitors, the menu bar, fullscreen media, Reduce Motion, and increased contrast.
- 👾 **Animated pixel companions.** Original characters make idle, working, waiting, completed, and failed states recognizable at a glance.
- 🔌 **Safe agent setup.** Previewed, marker-scoped hook installation preserves unrelated Codex and Claude Code configuration and removes only Chimlo's entries.
- 🔒 **Local and private.** Prompts, transcripts, permission previews, and session details are not sent to a Chimlo service. There is no telemetry by default.

## 📦 Install

Chimlo requires macOS 14 or newer. The current release supports Apple silicon
Macs.

1. Download the latest `Chimlo-*.dmg` from
   [GitHub Releases](https://github.com/kraten/chimlo/releases/latest).
2. Open the DMG and drag **Chimlo** into **Applications**.
3. Eject the Chimlo disk image, then open Chimlo from Applications.

### First launch

Chimlo is not yet notarized by Apple. If macOS blocks the first launch, open
**System Settings > Privacy & Security**, scroll to **Security**, then click
**Open Anyway** for Chimlo. Confirm with your Mac password when prompted.
Apple documents this process in
[Open a Mac app from an unknown developer](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac).

On first launch, complete the short onboarding tour. Chimlo then automatically
discovers supported local Codex and Claude Code sessions; no manual connection
step is required for session activity.

### Allow Accessibility permission

Accessibility permission is required for Chimlo's volume and brightness
controls and helps it recognize active fullscreen media.

1. Install Chimlo in Applications and open it from there.
2. Open **Chimlo Settings > General**.
3. Under **Volume and brightness**, enable **Show in Chimlo** and click
   **Allow**.
4. In **System Settings > Privacy & Security > Accessibility**, enable
   **Chimlo**.
5. Return to Chimlo and click **Retry** if the status has not updated.

Without this permission, agent activity remains available and macOS keeps its
native volume and brightness controls.

### Build from source

You need Xcode or the Xcode Command Line Tools with a Swift 6 toolchain.

```sh
git clone https://github.com/kraten/chimlo.git
cd chimlo

# One-time local signing setup
make signing-identity

# Package and open Chimlo.app
make app
open dist/Chimlo.app
```

<details>
<summary>Why the local signing step matters</summary>

`make signing-identity` creates a dedicated local keychain, imports a
non-exportable private key, and restricts the certificate to code signing. This
keeps Chimlo's designated code requirement stable between local builds, so macOS
does not repeatedly forget its Accessibility permission.

You can skip the step for an ad-hoc build, but permission may need to be granted
again when the executable changes. Run `make signing-check` to verify that two
separate builds keep the same designated requirement.

</details>

### Develop locally

```sh
make build
make test
make check
./Scripts/swift.sh run ChimloApp
```

`make test` runs the Swift test suites. `make check` runs Chimlo's deterministic
layout, protocol, and behavior checks.

## 🔌 Connect Codex and Claude Code

Chimlo combines app-server events, process liveness, incremental local metadata,
and command hooks. No cloud connection is required.

| Client | What Chimlo installs |
|:--|:--|
| **Codex** | Marker-scoped observers in `~/.codex/hooks.json` for task lifecycle updates. |
| **Claude Code** | Marker-scoped observers plus the blocking `AskUserQuestion` and `PermissionRequest` bridges in `~/.claude/settings.json`. |

Every install starts with a complete preview and explicit confirmation. Chimlo
preserves unrelated configuration, creates a one-time backup, validates the
result, and removes only its own marked entries during uninstall.

Read [Agent hook setup](Docs/AGENT_HOOKS.md) for the full install, recovery, and
uninstall behavior.

## 🔒 Privacy and safety

Chimlo is designed so that the terminal remains authoritative.

- Question text, answers, permission paths, and action previews exist only in memory while the interaction is active.
- The local registry deliberately omits prompt and response content.
- Hook traffic uses an authenticated loopback protocol with per-launch tokens and bounded message framing.
- A missing app, timeout, authentication failure, or transport error never implies approval. Claude Code falls back to its native terminal UI.
- Capacity comes from the existing Codex app-server connection and Claude Code's documented status-line or `/usage` surfaces. Chimlo does not read provider credentials.

See the [protocol specification](Docs/PROTOCOL.md) for the wire format and
fail-closed behavior.

## 🏗️ Architecture

Chimlo keeps its platform code, transport, and domain model in narrow modules:

```mermaid
flowchart LR
    CLI["ChimloCLI<br/>Hooks and dev events"] --> Protocol["ChimloProtocol<br/>Authenticated loopback"]
    App["ChimloApp<br/>AppKit and SwiftUI"] --> Protocol
    CLI --> Core["ChimloCore<br/>Domain values and reducer"]
    App --> Core
    Protocol --> Core
```

- **ChimloCore** owns deterministic session, interaction, retention, capacity, and layout rules.
- **ChimloProtocol** owns authenticated local transport and its wire schema.
- **ChimloApp** owns the macOS lifecycle, panel placement, discovery adapters, settings, and SwiftUI views.
- **ChimloCLI** receives agent hooks and provides development event injection.

Read the [architecture guide](Docs/ARCHITECTURE.md) for the dependency boundaries
and runtime data flow.

## 🤝 Contributing

Contributions are welcome. Start with the [contributing guide](CONTRIBUTING.md)
and [code of conduct](CODE_OF_CONDUCT.md), then open an issue or pull request.

- [Report a bug](https://github.com/kraten/chimlo/issues/new?template=bug_report.yml)
- [Request a feature](https://github.com/kraten/chimlo/issues/new?template=feature_request.yml)
- [Join a discussion](https://github.com/kraten/chimlo/discussions)

## 📜 License

Chimlo is free and open-source software licensed under
[GPL-3.0](LICENSE). Product and integration names remain the property of their
respective owners.
