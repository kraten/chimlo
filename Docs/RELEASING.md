# Chimlo release procedure

Chimlo's public release is built on one trusted Mac. GitHub stores and serves
the exact DMG and appcast produced there. GitHub Actions does not rebuild or
re-sign either file.

This procedure uses a long-lived self-signed code-signing certificate because
Chimlo does not have an Apple Developer Program membership. It preserves a
stable designated requirement across releases, but it does not provide Apple
notarization or normal Gatekeeper trust. New users may still need **Open
Anyway** on first launch.

## One-time setup

Choose two absolute `.p12` destinations on separate physical backup devices.
The setup command refuses two destinations on the same filesystem and never
overwrites an existing backup.

```sh
make release-signing-identity \
  BACKUP_ONE="/Volumes/Backup-A/Chimlo-Release.p12" \
  BACKUP_TWO="/Volumes/Backup-B/Chimlo-Release.p12"
```

Choose a strong backup password of at least 16 characters when prompted. Store
that password separately from both backup devices. The command creates:

- one exportable, long-lived `Chimlo Release` identity in a dedicated local
  keychain;
- two encrypted, byte-verified `.p12` backups and SHA-256 sidecars;
- `Packaging/Signing/ChimloRelease.cer`, the public certificate that must be
  reviewed and committed.

Never commit a `.p12`, private key, keychain password, or Sparkle private key.

If you prefer a generated password, run the setup command with
`CHIMLO_GENERATE_RELEASE_P12_PASSWORD=1`. The generated value is saved under
the Keychain service `dev.chimlo.release-signing-backup` and is never printed.
Copy it from Keychain Access into a separate password manager. A password kept
only on the release Mac cannot recover offline backups after that Mac is lost.

If cloud storage is replacing the second physical device, set
`CHIMLO_STAGE_SECOND_BACKUP_FOR_CLOUD=1` and point the second path at an obvious
temporary location such as the Desktop. Upload the encrypted `.p12` and its
`.sha256` sidecar, verify the cloud copy, then delete the staged local files.
Never place the backup password beside the `.p12`.

Build one signed app and freeze its designated requirement:

```sh
make release-signing-freeze
```

Review and commit these two public files before creating the first tag:

```text
Packaging/Signing/ChimloRelease.cer
Packaging/Signing/ChimloRelease.designated-requirement
```

The first update from an older ad-hoc-signed Chimlo build to this stable
self-signed identity may require the user to grant Accessibility permission
again. Subsequent builds signed by this same certificate should continue to
satisfy the frozen requirement.

## Build a release

Start from a clean worktree. The tag must already exist and point at the
checked-out commit.

```sh
git tag v0.3.0
make release TAG=v0.3.0 BUILD_NUMBER=3
```

The command runs checks and tests, builds `dev.chimlo.mac`, verifies the frozen
designated requirement, makes the final DMG, generates and verifies the signed
Sparkle appcast from that exact DMG, and records checksums and a manifest under:

```text
dist/releases/v0.3.0/
```

Do not modify, repackage, rebuild, or re-sign anything in that directory.

## Upload the exact files

```sh
make release-publish TAG=v0.3.0
```

This verifies every checksum and uploads the existing files to a draft GitHub
release. It refuses to overwrite an existing release. Review the draft and its
artifacts before publishing it.

The Sparkle private EdDSA key remains in the trusted Mac's Keychain under the
account `dev.chimlo.mac`. It is not copied to GitHub Actions.

## Restore on another Mac

Copy one `.p12` backup and its `.sha256` sidecar to the replacement Mac, then
run:

```sh
make release-signing-restore BACKUP="/Volumes/Backup-A/Chimlo-Release.p12"
```

On the original release Mac, prefix that command with
`CHIMLO_USE_STORED_RELEASE_P12_PASSWORD=1` to read a generated backup password
from Keychain instead of prompting for it.

The restore command checks the sidecar when present and refuses a backup whose
certificate differs from the committed public certificate. After restoring,
run `make release-app` and `./Scripts/verify-release-identity.sh` before making
another release.

## Invariants

- Keep the release bundle identifier fixed at `dev.chimlo.mac`.
- Sign every public `Chimlo.app` with the same `Chimlo Release` certificate.
- Keep both encrypted `.p12` backups and their password recoverable.
- Keep the frozen designated requirement under version control.
- Generate the Sparkle appcast only after the final DMG exists.
- Upload those exact bytes. Never let CI rebuild or re-sign them.
- Expect the DMG bytes and app CDHash to change between releases.
