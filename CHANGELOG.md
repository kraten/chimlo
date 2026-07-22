# Changelog

All notable changes to Chimlo will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/2.0.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-07-22

Chimlo's first public release puts your local coding agents, media, and system
controls in the MacBook notch.

### Highlights

- Watch Codex and Claude Code sessions as they work, wait for input, finish, or
  fail.
- See recent agent activity, completion details, and how long each session has
  been active. Archive finished sessions or jump back into current work.
- Answer Claude Code questions and approve or deny requested actions without
  returning to the terminal.
- Check your real Codex and Claude usage windows without connecting another
  account or sharing credentials.
- View Now Playing information and control media from the notch. Chimlo gets
  out of the way during fullscreen playback and returns automatically.
- Replace the standard volume and brightness display with compact pixel-art
  feedback that matches Chimlo.
- Recognize idle, working, waiting, completed, and failed states through
  animated pixel companions.
- Follow a guided setup for Codex, Claude Code, Accessibility access, media,
  appearance, and updates.
- Check for new versions from Settings, then download, install, and relaunch
  Chimlo in one flow.
- Use Chimlo across notched displays, external monitors, fullscreen apps,
  Reduce Motion, and increased contrast settings.

### Privacy and reliability

- Chimlo runs locally and has no telemetry by default. Agent prompts,
  responses, questions, and permission details are not sent to a Chimlo
  service.
- Connecting or disconnecting an agent preserves your existing Codex and
  Claude Code configuration.
- If Chimlo is unavailable, questions and approvals return to the terminal.
  A connection problem never counts as approval.
- Updates are verified before installation, and existing Chimlo preferences
  stay in place after updating.

### Before you install

- Chimlo requires macOS 14 or newer on an Apple silicon Mac.
- Chimlo is not notarized by Apple yet. On first launch, macOS may require you
  to approve it with **Open Anyway** in **System Settings > Privacy &
  Security**.
- Accessibility permission is needed for Chimlo's volume and brightness
  controls. Agent activity remains available without it.

[Unreleased]: https://github.com/kraten/chimlo/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/kraten/chimlo/releases/tag/v0.1.0
