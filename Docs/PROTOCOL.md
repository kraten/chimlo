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
