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
- `LocalSessionRuntime` restores its small privacy-safe cache, publishes the
  newest Codex/Claude transcript first, then enriches recent history. Cold
  transcript reads are bounded to a metadata head plus recent tail and continue
  incrementally from EOF; terminal-process liveness remains independent.
- `AgentIntegrationManager` installs and repairs the stable helper plus marked
  Codex and Claude observer entries after a complete preview and confirmation.
  Claude's separately marked `AskUserQuestion` and `PermissionRequest` hooks are
  synchronous and route transient owner interactions through the same
  authenticated listener.

## ChimloCLI

Development event injection and the live Codex and Claude Code hook executable
boundary. Provider codecs decode only a small allowlist of status metadata. The
helper writes only the response format required by the invoking agent to stdout.

## Provider capacity

Chimlo obtains capacity only through provider-owned runtime surfaces. Codex
weekly capacity comes from the existing `codex app-server` connection through
`account/rateLimits/read` and sparse `account/rateLimits/updated` notifications;
non-weekly Codex windows are ignored. Claude's primary source is an opt-in
status-line bridge that caches only Claude Code's documented `rate_limits`
payload and configures its documented `refreshInterval` at 60 seconds. Installing
the bridge preserves and later restores any existing custom status-line
configuration, including its previous refresh interval.

When the Claude cache is more than five minutes old and the owner opens the
Usage disclosure, Chimlo may launch one bounded, tool-disabled, probe-owned
Claude Code terminal and parse the provider-owned `/usage` panel. This fallback
runs only while capacity details are disclosed, reuses one probe-owned session
identity, removes its dedicated transcript artifacts after exit, and is excluded
from local-session discovery. A failed probe cools down for five minutes.

These sources keep capacity exact without reading provider credentials,
Keychain items, browser cookies, private OAuth endpoints, historical rollout
snapshots, or token-derived estimates. The `/usage` fallback stores the exact
percentages shown by Claude Code and derives reset times only from its
provider-reported relative or timezone-qualified reset labels. A still-valid
timestamp from the status-line payload remains preferred because it is more
precise. When no trustworthy value is available, Chimlo reports Capacity
unavailable. Claude's status line continues refreshing while an otherwise idle
session remains open.

## Safety boundaries

- Pending decisions, provider permissions, and questions are keyed by request
  and session, not screen position.
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
- Claude permission paths and bounded tool previews also exist only in memory.
  Only the generic tool category reaches the persisted session reducer.

## Installer seam

Adapters expose read-only detection, a complete installation preview,
installation, removal, and health checks. Chimlo never silently modifies hook
trust or restores an old whole-file backup over newer user changes. The backup
is recovery evidence; uninstall removes only Chimlo's current marker.
