# PaseoAttentionBar

English | [日本語](README.ja.md)

A macOS menu bar app that shows how many [Paseo](https://paseo.sh) agents are **waiting for you**.

```
▣ ?1 !1 ✓3 ▶2
```

Hand work off to your agents and get on with something else. The menu bar tells you at a glance
when an agent has a question, has finished and is waiting for review, or has stopped with an error.
Click one to open that agent directly in Paseo Desktop.

> [!NOTE]
> This is an unofficial, personal project and is not affiliated with the Paseo developers.
> The app's UI is currently in Japanese only.

## What the counts mean

| Indicator | Meaning | Color |
| --- | --- | --- |
| `?n` | Needs input (permission request or question) | Orange |
| `!n` | Stopped with an error | Red |
| `✓n` | Finished, waiting for review (not yet opened in Desktop) | Default |
| `▶n` | Running (can be hidden) | Smaller |
| `—` | Not connected to the daemon | |

## Usage

- **Left-click** to show the list in a popover.
  - Click a row to open that agent in Paseo Desktop. Opening it marks it as read, and it disappears from the list.
  - Hover over a row to reveal a ✓ button. Click it to mark the agent as read without opening it.
- **Right-click** for the menu:
  - Open Paseo (「Paseo を開く」)
  - Mark all as read (「すべて既読にする」)
  - Reconnect (「再接続」)
  - Show running count (「実行中の件数も表示」, toggles `▶n`)
  - Change connection (「接続先を変更…」)
  - Quit (「PaseoAttentionBar を終了」)

The app keeps no read/unread state of its own. It shows the Paseo daemon's state as is,
so it always matches what you see in Paseo Desktop and the mobile app.

## Requirements

- macOS 14 or later (Apple Silicon / Intel)
- Paseo, with its daemon running on the same Mac

## Installation

### Download (recommended)

1. Download `PaseoAttentionBar-<version>.zip` from
   [Releases](https://github.com/knagato/paseo-attention-bar/releases/latest) and unzip it.
2. Move `PaseoAttentionBar.app` to `/Applications`.
3. Register the LaunchAgent. This starts the app right away and at every login from then on.

   ```sh
   mkdir -p ~/Library/LaunchAgents
   curl -fsSL https://raw.githubusercontent.com/knagato/paseo-attention-bar/main/Resources/com.knatrix.paseo-attention-bar.plist \
     -o ~/Library/LaunchAgents/com.knatrix.paseo-attention-bar.plist
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.knatrix.paseo-attention-bar.plist
   ```

   If you don't want it to start at login, skip this step and just double-click the `.app`.

The app is signed with a Developer ID and notarized by Apple, so it opens without Gatekeeper warnings.

To update, quit the app and replace the `.app` in `/Applications` with the new one.
If you registered the LaunchAgent, you can restart it with
`launchctl kickstart gui/$(id -u)/com.knatrix.paseo-attention-bar`.

#### Upgrading from 0.1.0

The bundle ID changed from `com.knagato.PaseoAttentionBar` to `com.knatrix.PaseoAttentionBar`, and the
LaunchAgent label changed with it. Settings are carried over automatically on first launch. The old LaunchAgent
has to be removed by hand (`make install` does this for you):

```sh
launchctl bootout gui/$(id -u)/com.knagato.paseo-attention-bar
rm -f ~/Library/LaunchAgents/com.knagato.paseo-attention-bar.plist
```

Then register the new LaunchAgent as in step 3 above. If you had turned on "Launch at login", turn it on again.
Afterwards you can remove the old settings with `defaults delete com.knagato.PaseoAttentionBar`.

### Build from source

Requires Xcode 26 or later (Swift 6 toolchain). There are no external dependencies.

```sh
git clone https://github.com/knagato/paseo-attention-bar.git
cd paseo-attention-bar
make install
```

`make install` does the following:

1. Assembles the `.app`
2. Copies it to `/Applications/PaseoAttentionBar.app`
3. Registers the LaunchAgent and starts the app

To update, run `git pull` and then `make install` again.

### How the LaunchAgent behaves

Both installation methods use the same LaunchAgent settings:

- The app is restarted automatically only if it crashes. If you quit it from the menu, it stays closed until your next login.
- Logs go to `/tmp/paseo-attention-bar.log`.
- If the app starts before the Paseo daemon, it connects as soon as the daemon comes up (retrying with exponential backoff, capped at 30 seconds).

> [!IMPORTANT]
> **Leave the "Launch at login" (「ログイン時に起動」) item in the right-click menu turned off.**
> The LaunchAgent handles launching at login. That toggle uses `SMAppService`, which may fail to
> launch the app after a restart when the app is built from source with an ad-hoc signature.
> Turning both on would also mean managing login launch in two places.

## Uninstall

```sh
launchctl bootout gui/$(id -u)/com.knatrix.paseo-attention-bar   # stop the LaunchAgent
rm -f ~/Library/LaunchAgents/com.knatrix.paseo-attention-bar.plist
rm -rf /Applications/PaseoAttentionBar.app
defaults delete com.knatrix.PaseoAttentionBar   # also remove settings
```

If you built from source, `make uninstall-loginitem uninstall` does the same (except that it keeps your settings).

## Configuration

### Connection

By default the app connects to `127.0.0.1:6767`, which is also Paseo's default, so you usually don't need to change it.
If your daemon listens elsewhere, right-click → "Change connection…" (「接続先を変更…」) and enter the same
`host:port` value as `daemon.listen` in `~/.paseo/config.json`.

> [!NOTE]
> Daemons that require password authentication are not supported.

## Troubleshooting

### The icon doesn't appear in the menu bar

New menu bar items are added at the far left of the right-hand group (just right of the app menus).
When the menu bar is full, they get pushed out and aren't shown. This happens most often on Macs with a notch.

- Remove some items, or hold ⌘ and drag items to make room.
  The position you drag it to is kept across restarts.
- To check whether the app is running and its menu bar item exists, run:
  ```sh
  osascript -e 'tell application "System Events" to tell process "PaseoAttentionBar" to get {position, title} of every menu bar item of menu bar 1'
  ```

### It stays at `—` and never connects

- Make sure the Paseo daemon is running.
- Make sure the connection setting matches `daemon.listen` in `~/.paseo/config.json`.
- Try right-click → "Reconnect" (「再接続」).
- To check whether the LaunchAgent is running, run:
  ```sh
  launchctl print gui/$(id -u)/com.knatrix.paseo-attention-bar | grep -E 'state|pid'
  ```

## How it works

The Paseo daemon has a built-in notion of an agent needing attention.

- When an agent finishes a turn, it gets `requiresAttention: true` and
  `attentionReason: "finished"`.
- Opening that agent in Desktop clears the flag.

This app just subscribes to that state over the daemon's WebSocket and displays it.

It connects the same way as Paseo's CLI (`@getpaseo/client`):

1. Connect to `ws://127.0.0.1:6767/ws` (local connections need no authentication).
2. Send `{"type":"hello","clientId":...,"clientType":"cli","protocolVersion":1,"capabilities":{...}}`.
   Unless `capabilities` includes `all_providers: true`, agents from custom providers are left out of the list.
3. Once `status: server_info` arrives, send `fetch_agents_request` to fetch the list and subscribe to updates.
   This and every later request must be wrapped as `{"type":"session","message":{...}}`.
4. From then on, the list is updated from incoming `agent_update` (`upsert` / `remove`) and `agent_attention_required` messages.

Agents are classified in the same order as the daemon does it. The first rule that matches wins:

1. A permission request is pending → needs input (`?`)
2. `status` is `error` → error (`!`)
3. `status` is `running` → running (`▶`)
4. `requiresAttention` is set → finished, waiting for review (`✓`)
5. None of the above → already reviewed (not shown)

## Development

```sh
make build   # swift build -c release
make run     # run directly without a .app (launch at login is unavailable)
make bundle  # only assemble dist/PaseoAttentionBar.app (ad-hoc signed)
make release # build the distributable zip (see below)
make clean
```

```
Sources/PaseoAttentionBar/
  main.swift / AppDelegate.swift
  Model/AgentSummary.swift       # snapshot → display model, classification
  Core/PaseoClient.swift         # WebSocket connection, hello, subscription, reconnect, mark as read, deep links
  Core/Preferences.swift         # UserDefaults (connection, ▶ display, clientId)
  Core/LoginItem.swift           # SMAppService
  UI/StatusItemController.swift  # menu bar title and right-click menu
  UI/PopoverView.swift           # list popover (SwiftUI)
  UI/Formatting.swift
Resources/
  Info.plist
  com.knatrix.paseo-attention-bar.plist  # LaunchAgent (make install copies it to ~/Library/LaunchAgents)
scripts/bundle.sh                # assemble and sign the .app
scripts/release.sh               # universal build, Developer ID signing, notarization, zip
```

### Making a release

`make release` runs the following steps and produces `dist/PaseoAttentionBar-<version>.zip`:

1. Build a universal binary for arm64 and x86_64
2. Sign with a Developer ID (with the Hardened Runtime enabled)
3. Notarize with `notarytool`
4. Staple the notarization ticket to the app with `stapler`

The version is taken from `CFBundleShortVersionString` in `Resources/Info.plist`.

You need a Developer ID Application certificate in your keychain and notarization credentials registered beforehand.
Registering the credentials is a one-time step:

```sh
xcrun notarytool store-credentials paseo-notary --apple-id <Apple ID> --team-id <Team ID>
```

You can override the signing identity and profile name with the `SIGN_IDENTITY` and `NOTARY_PROFILE` environment variables.

## License

[MIT](LICENSE)
