# PaseoAttentionBar

ローカルの [Paseo](https://paseo.sh) デーモンで、**タスクが完了してユーザーの確認待ちになっている
エージェント**を macOS のメニューバーに常駐表示するアプリ。

```
▣ ?1 !1 ✓3 ▶2
```

| 表示 | 意味 | 色 |
| --- | --- | --- |
| `?n` | 入力待ち（権限確認・質問） | 橙 |
| `!n` | エラーで止まった | 赤 |
| `✓n` | **完了・確認待ち**（Desktop でまだ開いていない） | 通常色 |
| `▶n` | 実行中（右クリックメニューで非表示にできる） | 小さめ |
| `—` | デーモンに接続できていない | |

- 左クリックでポップオーバー。行をクリックすると **Paseo Desktop でそのエージェントを開く**
  （`paseo://h/<serverId>/agent/<agentId>` の deep link。開くと Desktop 側が既読にするので一覧から消える）。
- 行にホバーすると ✓ ボタンが出る。押すと開かずに既読にする（`clear_agent_attention`）。
- 右クリックで「Paseo を開く」「すべて既読」「再接続」「ログイン時に起動」「接続先の変更」。

## しくみ

Paseo デーモンには「要確認（attention）」の概念が組み込まれている。エージェントが 1 ターン終えると
`requiresAttention: true, attentionReason: "finished"` が付き、Desktop でそのエージェントを開くと
クリアされる。このアプリはその状態をデーモンの WebSocket から購読して表示しているだけで、
独自に既読状態を持たない（Desktop・モバイルアプリと常に同じ見え方になる）。

接続手順は CLI（`@getpaseo/client`）と同じ:

1. `ws://127.0.0.1:6767/ws` に接続（ローカルはパスワード不要）
2. 最初に `{"type":"hello","clientId":...,"clientType":"cli","protocolVersion":1,"capabilities":{...}}` を送る。
   **`capabilities` に `all_providers: true` を含めないと、カスタムプロバイダの
   エージェントが一覧から落ちる**（実測: running 中の 2 件が丸ごと消えた）。
3. サーバから `status: server_info`（`serverId` 入り）が届いたら
   `{"type":"session","message":{"type":"fetch_agents_request", "subscribe":{"subscriptionId":...}}}`
   で一覧と購読を開始。以降のリクエストはすべて `{"type":"session","message":{...}}` で包む
   （素で送ると `invalid_message`）。
4. 以後 `agent_update`（`kind: upsert | remove`）と `agent_attention_required` が流れてくる。

分類は デーモンの `deriveAgentStateBucket` と同じ順序:
`pendingPermissions > 0 || reason=permission → 入力待ち` → `status=error → エラー` →
`status=running → 実行中` → `requiresAttention → 完了・確認待ち` → それ以外は確認済み。

プロトコルの参照元は `/Applications/Paseo.app/Contents/Resources/app.asar` 内の
`node_modules/@getpaseo/protocol/dist/messages.js`（`pnpm dlx @electron/asar extract` で展開できる）。

## ビルド・インストール

```sh
make build      # swift build -c release
make run        # 直接起動（開発用。ログイン時起動は .app でないと設定できない）
make install    # dist/PaseoAttentionBar.app を組み立てて /Applications へ配置し、LaunchAgent で起動
make uninstall
```

Xcode 26 / Swift 6（strict concurrency）、macOS 14 以上。依存パッケージなし。

## ログイン時に起動（LaunchAgent）

右クリックメニューの「ログイン時に起動」は `SMAppService.mainApp` を使うが、この .app は
**ad-hoc 署名**（`codesign --sign -`）なので BTM への登録が残らず、再起動しても起動しなかった
（実測 2026-09-23: `sfltool dumpbtm` にエントリ無し）。`make install` のたびに cdhash が変わるのも効く。

代わりに LaunchAgent で起動する。こちらは BTM に `legacy agent` として残り、再ビルドの影響も受けない。
`make install` が plist の配置と登録までやるので、手で操作する必要はない。状態は次で確認できる:

```sh
launchctl print gui/$(id -u)/com.knagato.paseo-attention-bar | grep -E 'state|pid'
```

- plist: `Resources/com.knagato.paseo-attention-bar.plist` を `~/Library/LaunchAgents/` へコピーして使う
  （`RunAtLoad` + `KeepAlive: SuccessfulExit=false` = クラッシュ時だけ再起動。メニューから終了したら上がってこない）
- ログ: `/tmp/paseo-attention-bar.log`
- デーモン（`ws://127.0.0.1:6767`）より先に上がっても、指数バックオフ（最大30秒）で再接続するので問題ない
- `make install` は bootout → 差し替え → plist 配置 → bootstrap まで面倒を見る（`make uninstall-loginitem` で LaunchAgent ごと外す）
- **この方式にした以上、アプリ内の「ログイン時に起動」トグルは使わない**（二重管理になる）

## 注意: メニューバーが満杯だと見えない

新しいステータス項目は一番左（アプリメニューの直後）に入る。メニューバーが既に埋まっていると
アプリメニューの下に押し出されて描画されない（ノッチ機で起きやすい。Say No to Notch 等で
ノッチ無し解像度にしていても、幅が足りなければ同じ）。

- ⌘ を押しながら他の項目を左右にドラッグして場所を空けるか、この項目を右へ寄せる
  （位置は `autosaveName` で保存されるので再起動しても維持される）
- 項目が存在するかは次で確認できる:
  ```sh
  osascript -e 'tell application "System Events" to tell process "PaseoAttentionBar" to get {position, title} of every menu bar item of menu bar 1'
  ```

## 構成

```
Sources/PaseoAttentionBar/
  main.swift / AppDelegate.swift
  Model/AgentSummary.swift       # スナップショット → 表示用モデル、bucket 分類
  Core/PaseoClient.swift         # WebSocket 接続・hello・購読・再接続・既読・deep link
  Core/Preferences.swift         # UserDefaults（接続先、▶表示、clientId）
  Core/LoginItem.swift           # SMAppService
  UI/StatusItemController.swift  # NSStatusItem のタイトル生成・右クリックメニュー
  UI/PopoverView.swift           # 一覧ポップオーバー（SwiftUI）
  UI/Formatting.swift
Resources/
  Info.plist
  com.knagato.paseo-attention-bar.plist  # LaunchAgent（make install が ~/Library/LaunchAgents へ配置）
```

## ライセンス

[MIT](LICENSE)
