# Security Policy

## Reporting a Vulnerability

Chimlo handles authenticated local protocols and agent approval surfaces, so
security issues are taken seriously.

**Please do not open a public GitHub issue for security vulnerabilities.**

Instead, report vulnerabilities by emailing **[INSERT SECURITY EMAIL]** with:

1. A description of the vulnerability
2. Steps to reproduce (or a proof of concept)
3. The potential impact
4. Any suggested fix, if you have one

You will receive an acknowledgment within **48 hours** and a detailed response
within **5 business days** with next steps.

## Scope

The following areas are in scope for security reports:

- **ChimloProtocol** — Authenticated loopback transport, token validation,
  message framing, descriptor storage
- **ChimloCLI** — Hook payload processing, input validation, stdout response
  format
- **ChimloApp** — Runtime descriptor access, session data handling, agent
  configuration merges
- **ChimloCore** — Reducer logic affecting approval state transitions

## Out of Scope

- Issues in upstream dependencies (report those to the upstream project)
- Social engineering attacks
- Denial of service against the local loopback listener
- Issues requiring physical access to an unlocked Mac

## Supported Versions

| Version | Supported |
|:--------|:----------|
| Latest  | ✅         |
| Older   | ❌         |

## Security Design

Chimlo's security posture is documented in
[Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) under "Safety boundaries." Key
principles:

- Pending decisions are keyed by request and session, not screen position
- Duplicate messages and stale sequence numbers are ignored
- Payloads and frames have explicit size limits
- Runtime descriptors are private to the local user and short-lived
- The app being offline returns control to the native terminal interaction
- A transport error never becomes an approval
