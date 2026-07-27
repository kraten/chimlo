# Launch QA — Agent Handoffs

Manual checks for completion, questions, and approvals. Each maps to a real code
path. Run against both Claude Code and Codex where the row applies.

## 1. Turn completion flips the session to `completed`

`PrivacySafeHookMapper.map` turns `Stop`, `SubagentStop`, and `TaskCompleted`
into `.completed` ("Turn complete"), and `SessionReducer` sets
`phase = .completed` with `pendingRequest = nil`
(`Sources/ChimloCore/ProviderHook.swift:110`,
`Sources/ChimloCore/SessionReducer.swift:152`).

- [ ] Let an agent finish a turn. Confirm the island shows the session as
  complete and any prior spinner clears.
- [ ] `StopFailure` shows `.failed` ("Turn stopped"), not completed.

## 2. AskUserQuestion renders the real question, not the async placeholder

`ClaudeQuestionHook` is the blocking bridge; the async observer deliberately
skips `PreToolUse`/`AskUserQuestion` so it can't race and clear pending state
(`Sources/ChimloCore/ProviderHook.swift:98`,
`Sources/ChimloCore/ClaudeQuestionHook.swift:38`).

- [ ] Trigger an AskUserQuestion with 1–4 questions, each 2–4 options. Confirm
  the actual prompt text and option labels appear (not a generic "Needs input").
- [ ] Phase is `.waitingForAnswer`; the card stays put until answered.

## 3. Answers echo back through `updatedInput` and unblock the agent

`ClaudeQuestionHook.output(for:)` only emits `permissionDecision: allow` +
`updatedInput` when the response is `.answered`, answer count matches question
count, and every answer is a valid option label; otherwise it returns `{}`
(`Sources/ChimloCore/ClaudeQuestionHook.swift:89`).

- [ ] Answer in Chimlo. Confirm the agent continues with the chosen option.
- [ ] Multi-select (`multiSelect: true`): pick several. Confirm the comma-joined
  selections all map to valid labels and no duplicate is accepted.
- [ ] Cancel / dismiss the question. Confirm fallback `{}` is written and the
  agent falls back to its own prompt (no crash, no hang).

## 4. Approvals honor once / session / deny distinctly

`ClaudePermissionHook.output(for:)` maps `.allowedOnce` to `allow`,
`.allowedForSession` to `allow` + `updatedPermissions`, and `.denied` to `deny`
with `"Denied in Chimlo"` (`Sources/ChimloCore/ClaudePermissionHook.swift:75`).

- [ ] Trigger a `PermissionRequest` (e.g. a Bash command). Confirm the card
  shows the right prompt/preview per tool (Write/Edit/Bash/WebFetch/WebSearch).
- [ ] "Allow once": agent runs the tool; the next same request prompts again.
- [ ] "Allow for session": the session-scoped rule (or `acceptEdits` for file
  mutations) is added and later matching requests don't re-prompt.
- [ ] "Deny": agent reports denial and does not run the tool.

## 5. Session approval never widens beyond the session, never bypasses

`sessionPermissionUpdate` narrows every rule to `destination: session`, falls
back to `acceptEdits` for Edit/MultiEdit/Write/NotebookEdit, and **bypass mode
is never forwarded** (`Sources/ChimloCore/ClaudePermissionHook.swift:186`).

- [ ] Approve a file edit for the session. Confirm the update is `acceptEdits`
  scoped to `session`, not a global permission change.
- [ ] Confirm no Claude-suggested `bypassPermissions`/global rule leaks through —
  only `session`-destination rules or `acceptEdits` are emitted.
- [ ] A Bash approval-for-session pins `ruleContent` to that exact command;
  a WebFetch pins to `domain:<host>`, not a blanket WebFetch allow.

## 6. A live pending request wins until explicitly resolved

`SessionCandidate` merges update visible status but **only when
`pendingRequest == nil`**; a pending approval/question is not overwritten by
newer non-hook evidence (`Sources/ChimloCore/SessionReducer.swift:33`).
`.permissionResolved` / `.questionResolved` are the only clears.

- [ ] While an approval or question is pending, let other session activity land
  (status line / discovery updates). Confirm the pending card is not replaced or
  dismissed by the newer evidence.
- [ ] After answering/approving, confirm phase returns to `.working` and the
  pending card clears exactly once (no duplicate or resurrected card).
- [ ] Resolve, then let a stale async `PermissionRequest`/`Notification` arrive.
  Confirm it does not restore the just-resolved card (the Claude async path is
  gated off at `Sources/ChimloCore/ProviderHook.swift:106`).
