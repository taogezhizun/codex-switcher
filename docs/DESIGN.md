# Design

A small native utility using Sparkle for signed in-place app updates. SwiftUI supplies the window, menu-bar panel, settings, system typography, semantic colors and controls; AppKit supplies application discovery, normal termination and launch.

## Modules

- `AccountsCore`: snapshot identity, quota parsing, private file I/O, storage guards and switch/recovery transaction ordering.
- `CodexAccounts`: atomic local-file storage and read-only legacy Keychain migration, app-server transport, isolated sessions, desktop lifecycle and SwiftUI presentation.
- `AccountsCoreTests`: synthetic credentials, file permissions and injected lifecycle failures.
- `CodexAccountsTests`: UI presentation, all-account refresh scheduling and bounded concurrency, recovery lifecycle with an injected Keychain query spy, and an opt-in real-CLI smoke test in a fresh empty home.

The account fingerprint combines the workspace/account ID with the subject from the ID token, so token rotation does not change identity and different users sharing a workspace do not collide. These local claims are labels, not verified login evidence.

All saved accounts can refresh independently of the active desktop login. `QuotaCredentials` prefers matching live credentials and otherwise loads the saved file snapshot, with no Keychain fallback. Before applying an asynchronous result it verifies the same identity, source and exact credential bytes. `QuotaReader` uses one isolated external-token session per account, without refresh-token rotation or changes to the live auth file. An expired access-token hint or a server token-refresh request marks the account as needing login; the rejected credential fingerprint and paused state persist with the account. A new live credential or reimport enables recovery.

Quota reads use `rateLimitsByLimitId` when present, with the legacy `rateLimits` fallback. Each named bucket and its actual window duration remain visible. Missing windows remain unknown. A failed refresh retains the previous timestamp and marks the cache stale.

A login helper receives a newly allocated private home and a small allowlist of process environment variables. API keys, auth-issuer overrides and unrelated provider settings are not inherited. Browser destinations must use HTTPS on the OpenAI auth host. RPC errors are deliberately summarized; raw stderr and server diagnostic bodies are not displayed or logged.

## Recovery lifecycle

`AccountStore` owns a versioned `local-store-v1.json` snapshot containing account metadata, full credentials and the recovery journal. Mutations validate and atomically replace the whole snapshot; in-memory state changes only after a successful commit. The 64 MiB total size limit is checked before writing and reading. Per-credential validation retains the 1 MiB limit. No account identity or email appears in runtime filenames.

If the active file is absent but legacy `accounts.json` exists (even if empty), startup enters migration-required state without querying Keychain. Explicit migration reads only registered account keys and `switch-recovery`, validates all identities and backup fields, writes and rereads a private staging file, then commits one coherent snapshot. Failure never activates partial data. Old records remain unused. A single atomic snapshot avoids partial activation across separate metadata, credential and recovery files.

File-backed startup reads the journal without a system authorization prompt. A pending journal stops switching and refreshing until confirmed or restored. A user-confirmed switch checks the journal before target credentials or desktop shutdown. Before the switch/restore transaction the model conservatively invalidates recovery state; failure reloads the durable file-backed journal. A failed quit with no pending journal allows retry; an existing pending or unreadable journal retains the recovery guard. Migration runs off the main thread while the model operation guard blocks all store mutations and update installation.

`DesktopShutdown` retains the selected instance and proven CLI descendants through normal quit, explicit termination confirmation and bounded TERM/KILL waits. It follows birth-time identities through reparenting, ignores zombies, and blocks on unrelated or restarted CLI instances. Both UI entry points offer direct termination in the initial confirmation; selecting it grants one-operation approval and skips the normal-exit wait and repeat prompt. The default action still requests normal quit, and awaits any later decision within that same busy operation rather than beginning a second switch. `Desktop.writeLive` checks the shutdown proof again before switching, recovery or rollback; independently installed clients and shared daemons remain outside this adapter.

## Compatibility

File storage is a deliberate initial boundary. The app does not copy another application's Keychain records, change authentication policies, patch the desktop bundle or depend on a hidden desktop endpoint. Managed authentication configurations and shared app-server daemons need separate, explicitly tested adapters before they can be supported.

Desktop launch success is not authentication success. The UI says “credential file matches” and asks the user to verify the account inside the reopened desktop. It never presents a file write as proof of a new desktop session.

## Provenance

The original Windows project was reviewed during feasibility assessment. The implementation here is independently authored from requirements and the official app-server protocol, using Swift, with no copied/translated account-switcher source or assets. The app icon is a simple original vector drawing generated by the build script. See the README for attribution and the upstream licensing boundary.

## Presentation

`Presentation.swift` contains masking, ordering, quota freshness and original icon geometry. The main window, account details, menu panel and dialogs live in separate view files. Both switching entry points share the same target confirmation component and eligibility checks. UI preferences use local UserDefaults; demo mode does not persist them or initialize the credential store. See [UI design](UI-DESIGN.md).

`StatusBarQuota` projects the current saved identity to its lowest Codex remaining percentage, with distinct pending/unknown and stale states. The menu-bar label observes model state without additional network or Keychain calls.

`RefreshSchedule` tracks each eligible account independently, excluding credentials awaiting login. `QuotaBatch` processes at most two accounts at once under one operation guard; each completion is committed separately on the main actor. Cancellation defers remaining work by five minutes. Legacy migration keeps eligibility limited to the matching live account. `AppUpdates` wraps Sparkle; active update dialogs/installations and account operations cannot start concurrently; a passive gentle reminder does not block account work. Downloaded archives and feeds require EdDSA signatures. See [update design](UPDATES.md).
