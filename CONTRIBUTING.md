# Contributing to Chimlo

Thank you for your interest in contributing! Chimlo values small,
safety-backed changes.

## Getting Started

### Prerequisites

- macOS 14 or newer
- A matching Swift 6.0 toolchain (Xcode or Command Line Tools)
- Git

### Development Setup

```sh
git clone https://github.com/kraten/chimlo.git
cd chimlo

# Run the check suite (framework-independent core + loopback verification)
make check

# Run the full test suite (requires full Xcode installation)
make test

# Launch the app from source
./Scripts/swift.sh run ChimloApp
```

### Project Structure

| Directory | Purpose |
|:---|:---|
| `Sources/ChimloCore` | Pure domain values, deterministic reducer, display math |
| `Sources/ChimloProtocol` | Authenticated loopback transport and framing |
| `Sources/ChimloApp` | AppKit lifecycle, NSPanel, SwiftUI island views |
| `Sources/ChimloCLI` | Hook executable and development event injection |
| `Sources/ChimloChecks` | Framework-independent verification suite |
| `Tests/` | Swift Testing suites for Core and Protocol |
| `Integrations/` | Codex and Claude Code hook configuration fragments |
| `Docs/` | Architecture, protocol spec, and agent hook guides |

📖 See [Docs/ARCHITECTURE.md](Docs/ARCHITECTURE.md) for a detailed layer breakdown.

## Before Opening a Pull Request

1. **Keep agent-specific formats behind an adapter boundary.**
2. **Add reducer or protocol tests** for every new event path.
3. **Include asset provenance** for art, sound, or type changes.
4. **Run `make test`** with a matching Swift and macOS SDK.
5. **Exercise every changed control** with keyboard and pointer input.
6. **Check Reduce Motion, Increase Contrast,** and a display without a notch.

## What Not to Include

Do not include API keys, prompts, transcripts, terminal history, signed license
data, or extracted files from another application in issues, PRs, or fixtures.

## Issue Labels

| Label | Use for |
|:---|:---|
| `bug` | Something isn't working as expected |
| `enhancement` | New feature or improvement |
| `good-first-issue` | Approachable for new contributors |
| `documentation` | Docs improvements |
| `accessibility` | Keyboard, Reduce Motion, VoiceOver |

## Code Style

- Follow the existing Swift style in the codebase
- Use Swift's structured concurrency (`async`/`await`, actors)
- Keep layers isolated — `ChimloCore` must not import AppKit or Foundation networking

## Need Help?

Open a [Discussion](https://github.com/kraten/chimlo/discussions) for questions,
ideas, or anything that isn't a clear bug or feature request.
