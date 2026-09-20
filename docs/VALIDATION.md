# Validation

## Automated / isolated

The test suite exercises stable identity across token rotation; separate users in one workspace; invalid and mixed API-key credentials; missing and multiple quota buckets; private permissions; symlink refusal; exclusive instance locks; backup ordering; shutdown-time token rotation; refused termination; failed backup; failed relaunch; concurrent credential changes; guarded restoration; wrong-directory refusal; and a previously absent credential file.

The opt-in CLI smoke test starts the actual locally installed Codex binary with an empty private home, verifies initialization, signed-out account state and file-storage config, then shuts down and removes the isolated directory. It does not log in, switch the desktop or query a real account's quota.

The release script verifies its ad-hoc signature and scans executable strings for builder home paths. UI checks use synthetic demo data only. Intel and older macOS versions still need real-device testing.

## Manual acceptance before daily use

Use two of your own accounts and pause work in every client sharing the credential directory.

1. Save the currently logged-in account A; add B through the OpenAI browser flow. Confirm the desktop still shows A.
2. Verify B shows cached/unknown quota and its refresh control is disabled. Refresh A and verify only its timestamp changes.
3. Switch A → B. Confirm the desktop closes normally, reopens, and its account screen shows B. Only then confirm success in the utility.
4. Use recovery. Confirm the desktop returns to A. Then test a normal B → A switch.
5. Verify preferences and existing local tasks remain usable; restart the utility during a pending confirmation and confirm recovery is still available.

Do not claim real-account end-to-end validation based on unit tests or a demo screenshot. Record only client versions and anonymized outcomes; keep real email addresses, tokens, home paths and private workspace details out of this repository.

## 0.2 UI verification

Checked synthetic light, dark, empty-account and pending-confirmation windows on Apple Silicon. Checked the menu panel target confirmation, pause-task checkbox and cancellation. The demo final action remains disabled even after confirmation. Presentation tests cover email masking without data mutation, case-insensitive trimmed search, current-account ordering with more than five accounts, quota freshness, switch eligibility and future timestamps. The 30-test local run included the actual CLI in an empty isolated home; all passed. This does not replace the real-account acceptance above.

## 0.2.1 quota labels

Regression coverage checks official display names, missing/opaque labels, all-window preservation, old cache decoding without refresh, dotted bucket IDs, the legacy response, and the minimum remaining Codex window used in summaries. Demo quota fixtures are synthetic and do not reproduce account usage screenshots. Real account login and switching acceptance remains unchanged.

Verified the default collapsed state, recognized display names, unknown group expansion and raw-ID information popover using the isolated quota demo. All 35 local tests passed, including the opt-in signed-out CLI test. No live account was accessed for UI verification.

## 0.3.0 updates and automatic refresh

43 local tests passed, including the signed-out real-CLI smoke test. New tests cover five-minute cadence, per-account backoff, wakeups, disabled/busy guards, new/removed accounts, manual cadence reset, demo inactivity, and release verification flags/public-key format. The settings UI was inspected with a separate demo bundle; no live account was loaded.

The standalone Sparkle integration fixture uses disposable apps and a temporary test signing key. A valid signed update replaced version 1 with version 2 and relaunched successfully. A modified archive was rejected before installation (4005); a modified signed feed was rejected (1000). Both rejection tests retained version 1. The fixture never opens the real utility or Codex desktop and never reads the production signing key. Real account periodic refresh and real-account upgrade continuity still require user acceptance.

The arm64 and x86_64 release archives and appcast feeds were signed with the production key held in the local macOS Keychain, then verified with Sparkle. The corresponding public key matches the key embedded in the app. No private key was exported or added to the repository.

## 0.3.0 DMG packaging and README

Both architecture-specific DMGs passed disk-image checksum verification, deep app code-signature verification, and a file-by-file plus symlink comparison against the already published signed ZIPs. The Applications link targets the standard system folder. Installer contents were scanned for local home paths; no additional runtime data was included. The Apple Silicon DMG was opened normally in Finder to verify the icon arrangement, Chinese instructions and Retina background rendering. The README screenshot uses a separate demo bundle with synthetic accounts only. This packaging change does not alter the app or extend the real-account validation claims above.

## 0.3.1 current-account refresh

Historical validation only: the startup authorization assumption below proved insufficient and was superseded by the 0.3.2 regression fix described in the next section.

50 local tests passed, including the isolated signed-out real-CLI smoke test. New regressions cover current-only scheduling, external account changes, logout and unsaved identities, reuse of the latest matching token, rejection of another user in the same workspace, and noninteractive Keychain queries retaining authorization failures as errors. Quota refresh has no vault-read fallback and skips post-operation recovery reads. A startup recovery read that cannot authorize blocks switching until the user explicitly checks the record. Saved credentials and backups are not migrated. Real-account periodic refresh and upgrade continuity still require local user acceptance.

The inactive-account cache notice and recovery-authorization banner were visually inspected in isolated demo bundles. Both arm64 and x86_64 DMGs match their signed ZIP contents and pass deep code-signature verification. Production update feeds and ZIPs were signed and verified locally without exporting the private key. No real account or live Codex desktop was used for these checks.

## 0.3.2 startup Keychain regression

The 0.3.1 query-flag unit test only checked dictionary construction; it did not prove that macOS suppressed login-Keychain UI. The reported launch prompt invalidated that assumption. That test has been removed along with the noninteractive-read API.

Eight new tests execute the non-demo AppModel with temporary account metadata, synthetic login files, isolated preferences, a deliberately absent desktop application and a spy replacing SecItemCopyMatching. They cover startup including service scheduling, manual and automatic quota refresh entry/failure, ordinary operation failure, pending recovery after relaunch, denied access with no background retry, malformed records, transaction failure and explicit restoration. Startup and quota paths make zero vault queries; a pending or unreadable journal stops switching before target credentials are read. Failed transactions retain a conservative recovery guard without reading the vault again. No live Keychain item or real desktop is accessed by these regressions.

57 local tests passed, including the opt-in signed-out CLI smoke test. Real-account launch, quota fetching and switching remain user acceptance items; the automated evidence establishes application call paths and isolated protocol behavior, not live account success.

The confirmation sheet was visually checked in a separate synthetic demo bundle, including the authorization explanation and disabled demo action. Both architecture-specific DMGs passed checksum, app signature, ZIP-content and privacy checks. Production archive/feed signatures were generated and verified without exporting the update key.

## 0.4.0 local candidate (build 7, not published)

71 local tests passed with zero failures and zero skips, including the trusted official CLI started signed out in an empty isolated home. New coverage exercises file-backed CRUD and token rotation, full metadata/recovery migration, empty legacy lists with recovery, denied or missing credentials, wrong identities, malformed and denied journals, failed atomic commits, symlink refusal, interrupted staging and retry, instance locking, and corrupt-active-store refusal without Keychain fallback. Non-demo AppModel tests confirm that deferred operations never read Keychain and that only explicit migration does. A file-backed switch harness verifies shutdown-time token rotation, persistence across store relaunch, restoration, and failed-launch rollback without any desktop process.

Status-bar tests cover the lowest Codex window without merging unrelated pools, privacy masking, unknown/pending versus 0%/100%, stale-cache markers, logout/unsaved identity and preference persistence. Reminder state tests distinguish passive availability from an active update session and clear cancelled/finished session hints. The disposable Sparkle integration test passed valid signed replacement/relaunch and rejected both a changed archive and a changed feed; no publishing key or account credential was used.

A first local UI candidate exposed a launch-time MenuBarExtra redraw loop with a TimelineView inside the status label. Process sampling located the repeated status-button image updates. That candidate was rejected. The final label uses the model's existing 15-second clock instead; the fixed synthetic app launched successfully and its native settings toggles, light/dark menu, current-account highlight, quota bars, cache text, available-update row, empty account menu, pending confirmation and migration explanation/“later” dismissal were inspected. Demo mutation controls remained disabled. UI checks used preview-only bundle IDs and no real account store, Keychain or RPC. The system menu-bar tooltip and actual display on other macOS versions remain part of manual acceptance.

Both arm64 and x86_64 final apps passed ad-hoc code-signature and embedded-path checks. Both DMGs passed checksum, full app-file/symlink equality against their respective ZIPs, Applications shortcut and privacy checks. Source privacy scanning passed. Public verification keys are unchanged; production feeds and archive signatures were not generated or published for this candidate. Existing installed apps were not replaced, and all opened demo apps were closed after inspection.

Real old-account migration, browser login, live quota refresh, desktop A/B switching and restoration remain untested in this version. The user must pause their own Codex work before those checks; isolated tests do not establish a real Desktop login. Intel hardware and older supported macOS versions also remain untested. This candidate is ready for local acceptance, not a claim of completed public release.

## 0.4.1 (build 8): pre-release validation

83 tests passed, including the opt-in real Codex CLI smoke test in a fresh, signed-out isolated home. New coverage exercises all saved accounts, latest matching live credentials, a maximum of two concurrent readers, independent failures and backoff, cache retention, identity/source changes during a query, cancellation without immediate restart, persisted re-login pauses, recovery after live token replacement, deferred migration without Keychain access, and pending-recovery guards. A synthetic stdio server requests token renewal with a string request ID; the real transport classifies it as requiring login and removes its temporary session. No real account credentials were queried, migrated or switched.

Apple Silicon and Intel release apps and DMGs were built locally. Both installers passed app-signature verification, exact app-file/symlink comparison with the corresponding ZIP, Applications-shortcut validation and private-home-path scanning. The source privacy scan and whitespace checks passed. These local checks did not access the production update signing key or publish a release.

A preview-only bundle with synthetic accounts was inspected: a non-current account shows freshly updated quota; the More menu includes refresh-all; settings explain all-account refresh; an expired account shows a re-login label and its old quota timestamp. Preview mutation controls remain disabled. The preview was closed after inspection. UI automation lost its window connection after closing Settings; process sampling showed an idle main run loop (0% CPU, about 136 MiB resident), and relaunching only the disposable preview restored inspection. No status-label redraw loop was observed.

Real multi-account OpenAI quota responses, long-running expiry/re-login behavior, legacy data migration and Intel UI still require local acceptance. Access-token expiry pauses the affected account; this version intentionally does not automatically renew saved refresh tokens. The status-bar value remains the current account only.

### 0.4.1 distribution checks

The release archives and both appcast feeds were signed with the existing publishing identity. Independent Ed25519 verification using the public key shipped in 0.3.2 passed for both archives and both feeds; the key is unchanged. GitHub's SHA-256 digests and byte counts match all four local DMG/ZIP assets. The private key was not exported.

## 0.4.2 branding and upgrade continuity

Renamed the app's display and bundle names to Codex Switcher, including window/menu/about labels, installer title and release titles. Kept the bundle identifier, executable, storage and preferences locations, signing key, appcast URLs, repository URL, archive root and download filenames. The original copyright attribution is retained.

83 local tests passed, including the signed-out real CLI smoke test. The disposable Sparkle integration fixture changes both CFBundleName and CFBundleDisplayName from the former name to the new name while retaining one installed bundle; signed replacement and relaunch succeeded, and changed archives/feeds were rejected. No real user app, account store or credential was used. Both architectures built and passed DMG/ZIP equality, application signature and private-path checks.

An isolated synthetic preview verified the window, menu and About name plus version 0.4.2. The new README illustration was visually inspected in a browser and is explicitly marked as fictional; it does not imply an English app interface. The English README states that the current interface is Chinese. The English X copy fits a standard 280-character post (228 characters with the URL counted as 23); it is provided as a draft and was not posted.

## 0.4.3 compact quota rows

89 local tests passed with zero failures and zero skips, including the opt-in signed-out real Codex CLI smoke test in an empty isolated home. Six new presentation tests cover timezone date boundaries, DST offsets, cross-year formatting, missing and elapsed reset times, stale cache labels, and using percentage/reset from the same quota window.

Both Apple Silicon and Intel release apps and DMGs were built. Both installers passed app signature, exact app-file/symlink comparison against the corresponding ZIP, Applications-shortcut and private-path checks. The archives and local appcast feeds were signed and verified with the existing publishing key without exporting it. Bundle identity, installed archive root, signing public key and feed URLs remain unchanged.

The native menu component was inspected in an isolated synthetic preview on Apple Silicon after explicit permission to launch it. Remaining percentages, local reset dates and progress bars fit without truncation; the current-account highlight, stale-cache wording and re-login warning were visible. Accessibility help/value exposed the quota window, reset countdown, full reset timestamp with Asia/Shanghai and UTC+08:00, and last query time. The preview did not load real accounts or run account operations. Intel UI and real-account operations remain outside this isolated validation.

GitHub CI passed for the source change, including privacy scanning, unit tests, native build and installer verification. All four uploaded release assets matched local SHA-256 digests and byte counts. Public feeds are published only after the release assets become available.

## 0.4.4 main-window layout

89 local tests passed with zero failures and zero skips, including the signed-out real Codex CLI smoke test in an isolated home. No authentication, storage, quota scheduling or updater logic changed. A preview-only fixture provides one Codex window for the current synthetic account and two windows for another account.

The native main window was inspected with fictional accounts at its default geometry, minimum size after attempted shrinking, system-zoomed size and with the sidebar collapsed/reopened. Active-window titlebar continuity, single/two-window quota cards, header actions, light and dark appearances, and the unchanged compact menu were checked. Search filtering, zero results, clearing and Command-F reopening/focusing the sidebar were exercised. The moved switch button opened the existing confirmation sheet; the final demo operation remained disabled and cancellation returned to the same account. These checks do not establish real-account switching or Intel/older-macOS visual acceptance.

Both final architecture builds and DMG/ZIP content, application signatures and private-path checks passed. Production update signatures use the existing key; stable bundle identity, archive roots and feed URLs remain unchanged. No real account, migration or desktop switching was performed.
