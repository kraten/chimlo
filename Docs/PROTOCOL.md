# Local protocol

Chimlo receives normalized events over authenticated loopback TCP. The transport
is local only. Agent-specific helpers translate documented vendor input into the
wire types below.

## Runtime discovery

The app chooses an available `127.0.0.1` port at launch and writes a runtime
descriptor beneath `~/Library/Application Support/Chimlo/`. The descriptor
contains:

- protocol major and minor version
- loopback host and port
- app process identifier
- creation time
- a random per-launch bearer token

The descriptor and its directory must only be readable by the current user.
Clients reject descriptors with an unexpected owner, broad permissions, stale
process identifier, unsupported major version, or non-loopback host.

## Envelope

Every message is a bounded JSON envelope. The transport adds a four-byte,
big-endian payload length before the JSON bytes.

```json
{
  "version": { "major": 1, "minor": 0 },
  "messageID": "7D5EFC0B-42F7-47BD-B356-7F9D37D0DD16",
  "token": "per-launch-secret",
  "sentAt": "2026-07-20T08:00:00Z",
  "body": {
    "kind": "event",
    "event": {
      "sessionID": "demo-codex",
      "sequence": 3,
      "kind": "activity",
      "agent": "codex",
      "title": "Tighten cache boundaries",
      "detail": "Running focused tests"
    }
  }
}
```

The exact `Codable` schema in `ChimloProtocol` is authoritative. Examples here
illustrate intent and may omit optional fields.

## Session ordering

- `messageID` deduplicates transport retries.
- `sessionID` identifies one originating agent session.
- `sequence` increases within a session.
- Short-lived provider hook processes send sequence zero; the app assigns their
  next sequence after authenticated receipt so concurrent hooks need no shared
  counter or lock.
- The reducer ignores an event whose sequence is not newer than the last applied
  sequence for that session.
- A missing earlier activity event must not block a newer permission request.

## Decisions

Interactive requests carry a unique request identifier and expiry. A response is
valid only when its message, request, session, and unexpired pending entry all
match. The adapter translates that decision back into the documented format for
the invoking agent.

Safety rules are absolute:

- A timeout is no decision.
- A disconnect is no decision.
- A malformed response is no decision.
- An app that is not running is no decision.
- A late response cannot resolve a newer request.
- The native terminal interaction remains available.

## Claude Code questions

`question_request` carries one to four provider-authored questions with bounded
labels, descriptions, and choices. The app keeps this payload in memory and
keys the visible form to the originating session. A correlated
`question_response` contains an explicit answer map or an unavailable outcome.

The blocking Claude helper accepts only `PreToolUse:AskUserQuestion`. On an
explicit answer it echoes Claude's original `questions` array and adds the
answer map to `updatedInput`. Any cancellation, invalid option, timeout, app
shutdown, authentication failure, or transport error returns `{}` so Claude
Code presents its native question instead. Question payloads and answers never
enter Chimlo's persisted session registry.

## Claude Code permissions

`permission_request` carries one bounded, transient `PermissionRequest`
presentation: the originating session, tool category, human-readable prompt,
optional path or description, optional action preview, and whether Claude
can receive a session-scoped allow update. A correlated
`permission_response` is one of allow once, allow for session, deny, cancel, or
unavailable.

The blocking helper returns Claude's documented `PermissionRequest` decision
object only after an explicit choice. Allow once returns `behavior: allow` with
no permission update. Allow All prefers a validated Claude-authored rule,
narrows it to `destination: session`, and falls back to `acceptEdits` for file
changes or a bounded matching tool rule for other permissions. Deny returns
`behavior: deny`. Bypass mode and persistent destinations are discarded.
Cancellation, timeout, shutdown, authentication failure, or transport error
returns `{}` so Claude Code presents its native permission UI. Tool input and
the action preview never enter Chimlo's persisted session registry.

## Payload limits

The implementation bounds frames before allocation. Adapters should further cap
individual text fields and option counts. Oversized or deeply nested JSON is
rejected without showing a partial permission card.

## Adapter behavior

The hook helper must reserve stdout for the invoking agent's documented response
format. Diagnostics go to stderr or a private rotating log. Adapter installation
is outside this transport and requires a complete config preview plus explicit
approval.

## Development CLI

With Chimlo running:

```sh
chimlo demo
chimlo emit --session local-1 --sequence 1 --agent codex --kind sessionStarted \
  --title "Audit the cache" --detail "Reading request paths"
chimlo decision --title "Run project checks" \
  --message "swift test --filter LighthouseTests" \
  --approve-label "Allow once" --timeout 60
```

The CLI exits nonzero when it cannot authenticate or deliver the event. Commands
that request a decision print a correlated JSON response. Approval and denial
are explicit human outcomes; cancellation, expiry, or transport failure also
exit nonzero and never imply permission.
