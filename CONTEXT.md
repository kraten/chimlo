# Chimlo

Chimlo is a glanceable local status surface for coding-agent activity, owner interactions, and provider capacity.

## Language

**Provider capacity**:
The allowance state of a coding-agent provider account across its applicable reset periods. It belongs to the provider account, not to any individual agent session.
_Avoid_: Session quota, session usage, credits

**Capacity remaining**:
The unused percentage of a provider capacity window. Chimlo normalizes provider data so a lower value always represents greater urgency.
_Avoid_: Usage percentage, percent used

**Capacity warning**:
The compact escalation state entered when any reported provider capacity window has 20% remaining or less. It takes precedence over the ordinary session count but never over an owner interaction or failed session; exhausted capacity uses Chimlo's failure color.
_Avoid_: Quota alert, usage badge

**Capacity unavailable**:
The neutral state used when Chimlo has no trustworthy capacity value for a provider window. It is distinct from exhausted capacity and never triggers a capacity warning.
_Avoid_: Zero capacity, exhausted, rate limited

**Stale capacity**:
The last trustworthy capacity value retained after a refresh failure and marked as approximate. Its warning state remains valid only until the capacity window's known reset time passes.
_Avoid_: Current capacity, live capacity

**Reset countdown**:
The relative time until a capacity window resets, shown compactly in the Usage disclosure. Exact local date and time remain available as supporting detail.
_Avoid_: Reset date, reset timestamp

**Capacity indicator**:
The compact Codex weekly-capacity control at the leading edge of the expanded status band. Selecting it reveals or hides the Usage disclosure directly above the activity rows.
_Avoid_: Capacity strip, capacity shelf, usage card, quota card, session meter

**Usage disclosure**:
The detailed provider-capacity region revealed downward within Chimlo's activity panel. It shows Codex weekly capacity plus Claude session and weekly capacity side by side, includes reset information, and keeps the normal activity rows visible below it. It closes with the island and yields to owner interactions. It does not estimate monetary cost or retain historical analytics.
_Avoid_: Usage tab, usage popup, separate usage panel, cost view, analytics view

**Capacity snapshot**:
A timestamped, normalized observation of one provider's supported capacity windows. It contains percentages and reset times only when they came from a trustworthy provider-owned runtime surface.
_Avoid_: Usage estimate, token estimate, inferred allowance

**Claude status-line bridge**:
The opt-in local adapter that preserves Claude Code's existing status-line behavior while caching only the officially supplied `rate_limits` payload for Chimlo.
_Avoid_: Claude probe, OAuth scraper, credential reader

**Provider credential boundary**:
The rule that Chimlo does not read provider access tokens, Keychain credentials, browser cookies, or private OAuth endpoints to obtain capacity. Missing data crosses into Capacity unavailable, never an estimate.
_Avoid_: Credential fallback, direct OAuth fallback
