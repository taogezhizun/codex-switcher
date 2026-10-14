# Security and local data

## Data boundary

This project is intended for a person's own authorized ChatGPT accounts. Credentials are never sent to a project-operated server. Update checks and package downloads connect to the public GitHub project, with Sparkle system profiling disabled. No account credentials are attached to update requests. Login and quota actions communicate with OpenAI through the locally installed official Codex executable. There is no analytics backend, credential export feature, automatic warmup, account selling or shared-account service.

Runtime data is outside the source repository:

| Data | Storage |
| --- | --- |
| Account snapshots, metadata, quota cache and one recovery journal | `~/Library/Application Support/CodexAccounts/local-store-v1.json`, mode 0600, parent directory 0700 |
| Legacy records retained after migration | Old `accounts.json` and Keychain service `org.codexaccounts.local-vault.v1`; no longer read or written after migration |
| App selection and credential-directory selection | App preferences |
| Temporary browser login data | UUID directory in the app's private Application Support `Sessions` directory; removed after the operation and reaped on next launch after a crash |
| Active Codex credential | The selected `CODEX_HOME/auth.json`, mode 0600 when written |

In 0.4.0, new installations and migrated stores use a private local file. The file contains reusable credentials with JSON/base64 encoding, not application-layer encryption. Unix permissions restrict other macOS users but do not provide per-application access control for processes running as the same user. System backups may include these files depending on backup settings. A fully compromised user session or root can access them.

Legacy startup reads only metadata and offers an optional migration. Only clicking “Start migration” reads registered old Keychain items and the recovery journal; it never enumerates unrelated credentials. Every credential identity and the recovery structure is checked, staged privately and read back before a complete versioned snapshot is atomically activated. Missing items, denial, malformed data and write failure leave migration incomplete; retries do not activate partial data. Incomplete staging is reaped on restart. The instance lock and operation guard prevent overlapping tools, credential operations or update installation during migration.

Old Keychain entries and metadata remain untouched after migration and are not synchronized with new changes. They are not a safe downgrade target. Do not run old and new versions against the same data directory. A corrupt or unsupported active store fails closed without falling back to the Keychain. Removing old records is a separate explicit operation, not part of this migration.

Account JWT payloads are decoded to label and distinguish snapshots and to detect an already-expired access-token hint. They are **not** treated as verified cryptographic identity. Only successful authentication in the desktop app confirms the intended runtime identity.

## Quota refresh

Version 0.4.1 queries all saved accounts, with at most two isolated app-server children at a time. The current account uses its matching live credentials; inactive accounts use their saved file snapshot. Helpers receive access tokens only, not saved refresh tokens, and never overwrite the desktop auth file. The model revalidates identity and credential source before storing results. Expired credentials pause automatic queries until renewed by login/import or manually retried; this version does not automatically rotate refresh tokens. Legacy users who defer migration can query only the live account, without a Keychain fallback.

## Switching and recovery

The app requires the user to pause work before requesting desktop shutdown. After the user confirms a switch, it checks the durable recovery journal before reading the target snapshot or stopping the desktop. A pending, unreadable or malformed journal stops that switch. The initial confirmation offers a normal action and an explicitly labeled destructive action that ends Codex and continues. The latter skips the normal-exit wait and repeated confirmation: SIGTERM, a bounded wait of approximately five seconds, then SIGKILL if necessary. Approval is scoped to that operation and is never persisted.

The normal action gives Codex approximately 15 seconds, including any quit confirmation. If the selected instance or its proven CLI descendants remain, a separate unchecked confirmation offers the same bounded termination sequence. Refusing confirmation leaves credentials unchanged. This behavior is available from 0.4.8; 0.4.7 only waits and reports failure.

Termination is restricted to processes identified during that same attempt by PID, microsecond start time, executable path and user ID. Identity is checked again before signaling; orphaned children remain tracked, zombies do not block, and a restarted instance or an unrelated CLI blocks switching instead of being killed. macOS does not provide an atomic pidfd signal operation, so this reduces but cannot eliminate the check-to-signal race. Process enumeration reads metadata only, not command arguments, environments or task content. The app does not stop shared daemons or every independently installed CLI using the same credential directory.

Every live credential write, including recovery and failed-launch rollback, checks that the selected desktop and its bundled CLI remain stopped. A failed quit reloads the file-backed journal so an operation that never wrote credentials does not create a false recovery requirement. Existing pending or unreadable journals remain blocked.

After shutdown it re-reads the departing credentials, archives that fresh snapshot, and writes a durable private-file recovery journal before changing the live file. New data is written to an exclusive 0600 temporary file, fsynced, and renamed in the same directory. Symlinks in the live credential path are rejected. A file re-read detects changes between backup and write. This narrows concurrency risk but is not a cross-process compare-and-swap guarantee; all clients sharing the directory should be idle.

A failed launch restores the prior file only while the file still equals the expected old or new bytes. Recovery rejects a different directory or unrelated account. The last recovery snapshot remains after confirmation. A pending journal blocks another switch until the user acknowledges or recovers the operation.

On restart, file-backed recovery is loaded with the active store, without Keychain access. A pending journal or failed switch/restore transaction activates the recovery guard, pausing further switching and quota refresh until resolved. While migration is deferred, current-file quota reads remain available and credential mutations are blocked. Removing an account does not delete its recovery backup or log the desktop out.

## Repository hygiene

All committed accounts, email addresses and quota values must be synthetic. Use `example.com` addresses. Do not commit screenshots of real account lists, authentication files, Keychain exports, local configuration, logs or debug dumps. `scripts/privacy-check.py` scans candidate tracked files; review images manually, since a text scanner cannot inspect their content. The build script removes debug information and rejects embedded user-home paths in the distributed executable.

Do not paste access tokens, refresh tokens or credential JSON into GitHub issues. Report a suspected vulnerability with a minimal synthetic reproduction and affected version. No real credential is needed to reproduce file handling or transaction-ordering bugs.

## Signed updates

Sparkle 2.9.6 verifies Ed25519 signatures on both the feed and archive, with validation before extraction. Only the public verification key is shipped in Info.plist. The publishing key remains in the maintainer’s macOS login Keychain under the dedicated Sparkle account `org.codexaccounts.updates`; publishing scripts do not export it or store it in CI. Public keys are safe to publish and cannot be used to sign new updates. Loss of the private key requires a carefully planned migration or manual installation for existing ad-hoc-signed users; do not casually rotate the embedded key.

These checks authenticate the project’s update channel; they do not provide Apple Developer ID signing or notarization. Installation remains user-confirmed. Keep the GitHub account and signing Mac secure. Upstream third-party copyright notices are preserved exactly; their public author information is distinct from private user information.
