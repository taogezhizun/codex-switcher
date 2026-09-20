# UI design — 0.2

## Direction

A quiet native Mac utility: the current account, remaining quota and next action should be readable at a glance. Account management uses a sidebar; everyday switching happens inside the menu-bar panel. System materials, controls, SF typography and semantic colors adapt to macOS appearance.

The original identity is a pair of rounded exchange arrows on a cobalt plate. White and ice-blue arrows remain recognizable at small sizes. The icon is generated from editable AppKit vector geometry at exact 1× and 2× pixel dimensions; the menu-bar template uses the same motif. No upstream artwork or third-party icon assets are included.

## Interaction decisions

- Current credentials appear first. Search covers all accounts, and filtering updates the detail selection.
- Quota cards distinguish window duration, remaining percentage and reset time. Unknown values stay unknown; stale or failed reads keep a visible cache indicator.
- The main window and menu panel share a confirmation view that names the source and destination. A pause-task checkbox precedes the action.
- Pending verification stays prominent, with confirmation and recovery actions. A replaced credential file is never described as verified desktop login.
- Email visibility defaults to hidden; nicknames remain visible. Appearance and visibility preferences persist locally. Public visuals use synthetic demo accounts only.

## References and provenance

Design work used the frontend-design skill for critique and visual hierarchy. Reference patterns were studied, not copied:

- [Apple App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons/): a simple recognizable concept and clarity at small sizes.
- [Apple Icons](https://developer.apple.com/design/human-interface-guidelines/icons): consistent, understandable symbols.
- [SwiftUI MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra): native menu-bar utility presentation.
- [Raycast Action Panel](https://manual.raycast.com/action-panel): actions close to the selected item.
- [Raycast Keyboard Shortcuts](https://manual.raycast.com/keyboard-shortcuts): discoverable, repeatable keyboard actions.

The flattened `.icns` supports the existing macOS 14+ build path without requiring Icon Composer or a paid developer account. It is not a layered Liquid Glass icon. Platform-specific layered assets can be evaluated separately.

## Review

See [validation](VALIDATION.md) for checked states and the remaining real-account acceptance boundary. The icon review board is rendered entirely from original drawing code and contains no account, device or workspace information.

## 0.2.1 quota naming

Use the optional `limitName` from the [official rate-limit response](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt). Empty names, names identical to the raw ID, and machine-style underscore labels fall back to an unidentified group; do not guess a model from its code name. Show recognized Codex first, keep unknown pools in a collapsed disclosure, and expose IDs only in the information popover. Summaries use the tightest Codex window, never an unrelated full pool. Old cache IDs and period labels are projected without a destructive migration.

## Download page and installer

The README opens with a small app icon, one sentence describing its purpose, and architecture-specific DMG downloads. A native app screenshot replaces the icon sizing board; the screenshot is captured from an isolated demo bundle containing only synthetic accounts. Detailed compatibility and validation notes stay available below the installation steps and in the usage guide.

The installer uses a quiet blue-gray background (#F6F7FB), dark headings (#20283D), secondary text (#657087), and a single blue directional arrow (#5572D8). System semibold type introduces installation; regular system type explains the drag action. The real app and Applications icons are Finder items, with fixed positions in a 640 by 400 window. Original AppKit artwork includes 1x and 2x representations. No account data or third-party artwork is used.

## 0.4.0 menu and status bar

Keep the existing native SF type, semantic light/dark colors and original cobalt exchange mark. Current credentials get a restrained accent background and an explicit label. Each menu row has its real Codex period, remaining percentage, 3-point meter and cache age; inactive accounts always say “last record”. Scrolling and search stay available. Recovery moves into More, while pending recovery remains prominent.

The menu-bar template icon gains a monospaced percentage (13-point semibold). Unknown/pending is a dash, stale cache has a tilde; the tooltip names the selected period and actual timestamp with the same email masking preference. A small setting can hide the percentage. A passive update row is shown only while Sparkle has a valid reminder; no animation or extra network loop is added.

The non-blocking migration banner opens a native explanation sheet. It states the unencrypted-file tradeoff, possible old Keychain prompts, deferred behavior and downgrade boundary before the user starts migration. Busy migration disables dismissal and account mutations; errors stay visible and can be retried.

Menu layout and local-file storage ideas also reference [liuzhao1225/codex-account-switcher](https://github.com/liuzhao1225/codex-account-switcher). All implementation and artwork here remain independently authored. See the [source review](research/liuzhao1225-experience-review.md).

## 0.4.1 all-account refresh

Inactive accounts can now display freshly queried quota. Use cache wording only when data is stale or a query failed; show “需要重新登录” for expired credentials. Both More menus expose “刷新全部账号额度”; the account detail and context menu refresh the selected account. A batch shows its account count, cancellation and final success count. The status-bar percentage still represents only the active saved account.

## 0.4.3 compact quota rows (candidate)

The menu shows remaining percentage and the selected quota window's reset time above its meter. Plan, window duration, countdown, full local timestamp/timezone and last query move into the row tooltip and accessibility value. Formatting follows the system's autoupdating timezone and locale, including the offset applicable at the reset instant and cross-year dates. Missing dates remain unknown; elapsed reset times do not imply restored quota. Stale cached percentages remain visibly marked. The existing model clock drives freshness; no additional status-label timer is introduced.
