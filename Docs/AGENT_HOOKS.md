# Codex and Claude Code sessions

Chimlo combines four local signals so a running session does not disappear just
because one integration is unavailable:

- Codex app-server task metadata while the Codex desktop app is running
- terminal process liveness and working-directory discovery
- incremental metadata-only reads of recent Codex and Claude JSONL records
- documented Codex and Claude Code command hooks

All reconciliation happens on this Mac. Chimlo does not use Keychain, upload
session data, or replace either agent's native approval surface.

The packaged helper is:

```text
~/Library/Application Support/Chimlo/bin/chimlo
```

The app refreshes this stable copy from the signed app bundle, so moving or
renaming `Chimlo.app` does not break an installed observer.

The helper reads one hook payload from standard input, keeps only the opaque
session ID, provider, project basename, model label, hook kind, and safe tool
category, and sends that small event to Chimlo's authenticated loopback
listener. Prompt text, assistant text, transcript paths, tool inputs, tool
outputs, environment values, and file contents are not retained. The one
deliberate exception is Claude Code's `AskUserQuestion`: its question and
choices live in memory only while Claude is blocked for an answer. They are
never written to Chimlo's session cache or archive.

The JSONL scanner follows the same boundary. It extracts only session ID,
workspace path, model label, timestamp, and lifecycle record type. Reads are
incremental after the first bounded scan. Prompt bodies, assistant content,
tool arguments, tool results, and file contents never enter Chimlo's session
model or local session cache.

## Configure Codex

Use **Connect** in Chimlo Settings to preview and add Chimlo's marked observers
to `~/.codex/hooks.json`. The merge preserves every existing hook, keeps one
pre-Chimlo backup, validates the result, and can remove only Chimlo's marked
entries. [`Integrations/codex-hooks.json`](../Integrations/codex-hooks.json) is
also available as a manual merge fragment. Do not replace an existing file.
Review and trust new definitions with `/hooks` in Codex when prompted.

Codex invokes observers synchronously, so the helper has a one-second local
delivery deadline and always returns an empty JSON response. If Chimlo is not
running, Codex continues normally.

## Configure Claude Code

Use **Connect** beside Claude Code in Chimlo Settings to preview and add Chimlo's
marked observers to `~/.claude/settings.json`. The same preservation, backup,
validation, repair, and marker-scoped removal rules used for Codex apply here.
[`Integrations/claude-hooks.json`](../Integrations/claude-hooks.json) remains
available as a manual merge fragment. Replace `/Users/YOU` with the local home
path and never replace the whole settings file. Observation hooks are
asynchronous where Claude supports it. Chimlo also adds one narrow, synchronous
`PreToolUse` hook matching only `AskUserQuestion`. It waits for a choice in
Chimlo and returns the original question plus the selected answer through Claude
Code's documented `updatedInput` contract. If Chimlo is closed, unreachable, or
times out, the hook returns no decision and Claude Code shows its native
question UI.

## Questions and permission behavior

Claude Code multiple-choice questions can be answered directly in Chimlo. A
single-select choice is sent immediately; multi-select questions require an
explicit Send action. **Answer in Claude Code** releases the hook without an
answer so the native prompt takes over.

Tool permissions remain mirror-only. Chimlo shows that Codex or Claude Code is
waiting, while the complete action and the authoritative Allow or Deny control
remain in the provider's own terminal UI. A missing app, timeout, malformed
payload, or transport error can never imply approval or fabricate an answer.

The helper reserves stdout for the provider's hook response. It emits `{}` for
observation and for any unanswered question fallback, and exits successfully
even when Chimlo is unavailable.
