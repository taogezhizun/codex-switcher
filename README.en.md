<p align="center"><img src="docs/images/app-icon.png" width="88" height="88" alt="Codex Switcher icon"></p>
<h1 align="center">Codex Switcher</h1>
<p align="center">Switch Codex accounts. See what's left.</p>
<p align="center"><a href="README.md">简体中文</a> · English</p>
<p align="center">
  <a href="https://github.com/taogezhizun/codex-accounts-mac/releases/latest/download/Codex-Accounts-macOS-arm64.dmg">Download for Apple Silicon</a> ·
  <a href="https://github.com/taogezhizun/codex-accounts-mac/releases/latest/download/Codex-Accounts-macOS-x86_64.dmg">Download for Intel</a>
</p>
<p align="center"><sub>macOS 14+ · Native SwiftUI · Free and open source</sub></p>
<p align="center"><img src="docs/images/app-overview.svg" width="960" alt="Illustration of account switching and remaining usage; all data is fictional."></p>

A native macOS menu bar utility for managing your own Codex desktop accounts.

- **Switch accounts** with confirmation and a normal restart of Codex. A recovery snapshot lets you restore the previous credentials.
- **Check remaining usage** across saved accounts, with automatic refresh every five minutes and manual refresh controls.
- **See your active account's remaining usage** in the menu bar.
- **Update in place** through the app's signed update channel.

**Version 0.4.4:** A continuous title bar fixes the sidebar seam. A compact account header keeps open/switch actions close, removes repeated status text and gives single-window quotas a bounded card width. Local-time reset summaries remain in the menu. Existing accounts, settings and update URLs are preserved. The repository URL and legacy installer filenames remain unchanged for compatibility.

## Get started

1. Install the official Codex desktop app, then download the DMG matching your Mac.
2. Drag the utility into Applications. Existing users should use **Settings → App updates → Check for updates** in the app; the interface is currently in Chinese.
3. Save your current account or add another through the browser login flow.
4. Pause your Codex work before switching. Check the account inside the reopened Codex app, then confirm the switch in the utility.

The on-disk app is still named `Codex Accounts.app` so existing installations can update in place. You do not need a second copy.

## Local data and compatibility

Credentials are stored in a private local file, without application-layer encryption. Existing Keychain records are read only when you explicitly start migration. Daily operations after migration do not access the Keychain. Login and quota queries connect to OpenAI; there is no project-operated credential server.

An expired credential pauses that account's automatic refresh and asks you to sign in again. Old usage data remains visible. Saved refresh tokens are not renewed automatically.

Requires macOS 14+ and ChatGPT file-based authentication. API keys and managed authentication are not supported. Builds are ad-hoc signed and not Apple notarized. Automated tests and packaging checks do not replace real-account or Intel hardware acceptance. See [validation](docs/VALIDATION.md), [security](SECURITY.md) and the [usage guide in Chinese](docs/USAGE.md).

## Development and credits

```sh
./scripts/build-app.sh
swift test
python3 scripts/privacy-check.py
```

Built and maintained by [taogezhizun](https://github.com/taogezhizun). Contributions and feedback are welcome.

Independently implemented for macOS, inspired by [cjg1995/codex-account-switcher](https://github.com/cjg1995/codex-account-switcher), with interaction and refresh ideas from [liuzhao1225/codex-account-switcher](https://github.com/liuzhao1225/codex-account-switcher) and [OpenUsage](https://github.com/robinebers/openusage). Updates use [Sparkle](https://sparkle-project.org/). No upstream switcher code or artwork was copied. See the [full attribution and licensing notes](README.md#致谢与许可).

[MIT License](LICENSE). An independent community project, not affiliated with or endorsed by OpenAI.
