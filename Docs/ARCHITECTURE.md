# Architecture

Chimlo has four deliberately narrow layers.

## ChimloCore

Pure `Codable` domain values, a deterministic session reducer, display-layout
math, and the privacy-safe projection from hooks and local JSONL metadata into
one `SessionCandidate` vocabulary. It knows nothing about AppKit, sockets, hook
file locations, or vendor configuration files. Hook events, process evidence,
Codex app-server updates, cache restores, and JSONL metadata all merge through
the same reducer. A live actionable request cannot be overwritten by weaker
metadata. Onboarding demo events pass through this exact reducer too.

## ChimloProtocol

Authenticated loopback transport, bounded message framing, runtime descriptor
storage, and request correlation. A helper discovers a descriptor owned by the
current user and proves possession of a per-launch token. A transport error
never becomes an approval.

## ChimloApp

AppKit owns the accessory-app lifecycle, top-center `NSPanel`, screen geometry,
and menu-bar fallback. SwiftUI renders the island, sessions, onboarding, and
settings. The panel is non-activating until an interaction requires keyboard
focus. The app runtime has three narrow adapters:

- `CodexDesktopSessionAdapter` launches the installed Codex app-server by bundle
  identifier, synchronizes loaded plus bounded recent tasks, and listens for
  lifecycle notifications.
- `LocalSessionRuntime` incrementally scans privacy-safe JSONL metadata, detects
  terminal processes, reconciles liveness, and persists a small local cache.
- `AgentIntegrationManager` installs and repairs the stable helper plus marked
  Codex and Claude observer entries after a complete preview and confirmation.
  Claude's separately marked `AskUserQuestion` hook is synchronous and routes
  transient choices through the same authenticated listener.

## ChimloCLI

Development event injection and the live Codex and Claude Code hook executable
boundary. Provider codecs decode only a small allowlist of status metadata. The
helper writes only the response format required by the invoking agent to stdout.

## Safety boundaries

- Pending decisions and questions are keyed by request and session, not screen
  position.
- Duplicate messages and stale per-session sequence numbers are ignored.
- Payloads and frames have explicit size limits.
- Runtime descriptors are private to the local user and short lived.
- The app being offline returns control to the native terminal interaction.
- Agent configuration changes require a preview, semantic validation, atomic
  replacement, marker-scoped uninstall, and an explicit user action.
- Persisted session entries contain only provider, title, generic status, model,
  project path, terminal label, jump URL, phase, and timestamps.
- Claude question text, option descriptions, and selected answers exist only in
  memory for the lifetime of the blocking hook request.

## Installer seam

Adapters expose read-only detection, a complete installation preview,
installation, removal, and health checks. Chimlo never silently modifies hook
trust or restores an old whole-file backup over newer user changes. The backup
is recovery evidence; uninstall removes only Chimlo's current marker.
