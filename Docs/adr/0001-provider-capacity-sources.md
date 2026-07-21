# Obtain provider capacity through provider-owned runtime surfaces

Chimlo reads Codex weekly capacity from its existing `codex app-server` connection through `account/rateLimits/read` and sparse `account/rateLimits/updated` notifications, and reads Claude session and weekly capacity from an opt-in status-line bridge that caches only Claude Code's documented `rate_limits` payload. These sources keep values exact without depending on CodexBar or reading provider credentials, Keychain items, browser cookies, private OAuth endpoints, historical rollout snapshots, or token-derived estimates; when a trustworthy value is absent, Chimlo reports Capacity unavailable.

## Consequences

Codex ignores non-weekly capacity windows in this feature. Claude capacity can remain unavailable until a Claude.ai subscriber session produces its first assistant response, and installing the bridge must preserve and later restore any existing custom status-line configuration.
