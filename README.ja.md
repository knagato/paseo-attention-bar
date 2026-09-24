# PaseoAttentionBar

[English](README.md) | 日本語

[Paseo](https://paseo.sh) のエージェントのうち、**あなたの対応を待っているもの**を
macOS のメニューバーに件数で表示する常駐アプリです。

```
▣ ?1 !1 ✓3 ▶2
```

エージェントに作業を任せて別のことをしていても、「質問が来ている」「終わって確認待ち」
「エラーで止まった」がメニューバーを見るだけで分かります。クリックすればそのエージェントを
Paseo Desktop で直接開けます。

> [!NOTE]
> 個人が作った非公式ツールです。Paseo の開発元とは関係ありません。

## 表示の見方

| 表示 | 意味 | 色 |
| --- | --- | --- |
| `?n` | 入力待ち（権限の確認・質問） | 橙 |
| `!n` | エラーで止まった | 赤 |
| `✓n` | 完了して確認待ち（Desktop でまだ開いていない） | 通常 |
| `▶n` | 実行中（非表示にできる） | 小さめ |
| `—` | デーモンに接続できていない | |

## 使い方

- **左クリック**: 一覧をポップオーバーで表示します。
  - 行をクリックすると、そのエージェントを Paseo Desktop で開きます。開いたものは既読になり、一覧から消えます。
  - 行にマウスを重ねると ✓ ボタンが出ます。押すと、開かずに既読にします。
- **右クリック**: 次のメニューを表示します。
  - Paseo を開く
  - すべて既読にする
  - 再接続
  - 実行中の件数も表示（`▶n` の表示・非表示）
  - 接続先を変更
  - 終了

既読・未読の状態はアプリ側では持たず、Paseo デーモンの状態をそのまま表示します。
そのため Paseo Desktop やモバイルアプリと常に同じ見え方になります。

## 必要なもの

- macOS 14 以上（Apple Silicon / Intel）
- Paseo（デーモンがこの Mac で動いていること）

## インストール

### ダウンロードする（おすすめ）

1. [Releases](https://github.com/knagato/paseo-attention-bar/releases/latest) から
   `PaseoAttentionBar-<バージョン>.zip` をダウンロードして展開します。
2. `PaseoAttentionBar.app` を `/Applications` に移動します。
3. LaunchAgent を登録します。登録するとすぐに起動し、次回以降のログイン時も自動で起動します。

   ```sh
   mkdir -p ~/Library/LaunchAgents
   curl -fsSL https://raw.githubusercontent.com/knagato/paseo-attention-bar/main/Resources/com.knagato.paseo-attention-bar.plist \
     -o ~/Library/LaunchAgents/com.knagato.paseo-attention-bar.plist
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.knagato.paseo-attention-bar.plist
   ```

   自動起動が不要なら、この手順は飛ばして `.app` をダブルクリックで起動してください。

アプリは Developer ID で署名し、Apple の公証を受けています。そのため、警告なしで起動できます。

更新するときは、アプリを終了してから、新しい `.app` で `/Applications` のものを置き換えてください。
LaunchAgent を登録している場合は、`launchctl kickstart gui/$(id -u)/com.knagato.paseo-attention-bar` で起動し直せます。

### ソースからビルドする

Xcode 26 以上（Swift 6 ツールチェーン）が必要です。外部の依存パッケージはありません。

```sh
git clone https://github.com/knagato/paseo-attention-bar.git
cd paseo-attention-bar
make install
```

`make install` で次のことを行います。

1. `.app` を組み立てる
2. `/Applications/PaseoAttentionBar.app` に配置する
3. LaunchAgent を登録して起動する

更新するときは、`git pull` してからもう一度 `make install` を実行してください。

### LaunchAgent の動き

どちらの方法でも、LaunchAgent の設定は次のとおりです。

- アプリが異常終了したときだけ自動で再起動します。メニューから「終了」した場合は、次のログインまで起動しません。
- ログは `/tmp/paseo-attention-bar.log` に出ます。
- Paseo デーモンより先に起動しても、デーモンが上がりしだい自動で接続します（再接続の間隔は最大 30 秒）。

> [!IMPORTANT]
> 右クリックメニューの「ログイン時に起動」は**オンにしないでください**。
> 自動起動は LaunchAgent が担当します。このトグル（`SMAppService`）は、ソースからビルドした
> ad-hoc 署名のアプリでは再起動後に起動しないことがあります。また、両方を有効にすると二重に管理することになります。

## アンインストール

```sh
launchctl bootout gui/$(id -u)/com.knagato.paseo-attention-bar   # LaunchAgent を停止
rm -f ~/Library/LaunchAgents/com.knagato.paseo-attention-bar.plist
rm -rf /Applications/PaseoAttentionBar.app
defaults delete com.knagato.PaseoAttentionBar   # 設定も消す場合
```

ソースからビルドした場合は、`make uninstall-loginitem uninstall` でも同じことができます（設定は残ります）。

## 設定

### 接続先

既定の接続先は `127.0.0.1:6767` です。Paseo の既定値と同じなので、通常は変更不要です。
デーモンの待ち受けアドレスを変えている場合は、右クリック →「接続先を変更…」で
`~/.paseo/config.json` の `daemon.listen` と同じ値（`host:port`）を入力してください。

> [!NOTE]
> パスワード認証が必要な接続先には対応していません。

## トラブルシューティング

### メニューバーにアイコンが出ない

新しいメニューバー項目は、並びの一番左（アプリのメニューのすぐ右）に追加されます。
メニューバーが埋まっていると押し出されて表示されません。ノッチのある Mac で特に起きやすい症状です。

- 他の項目を減らすか、⌘ を押しながら項目をドラッグして場所を空けてください。
  並べ替えた位置は、再起動後も維持されます。
- アプリが動いていて項目自体は存在するかどうかは、次のコマンドで確認できます。
  ```sh
  osascript -e 'tell application "System Events" to tell process "PaseoAttentionBar" to get {position, title} of every menu bar item of menu bar 1'
  ```

### `—` のまま接続されない

- Paseo デーモンが起動しているか確認してください。
- 接続先が `~/.paseo/config.json` の `daemon.listen` と一致しているか確認してください。
- 右クリック →「再接続」を試してください。
- 常駐状態は次のコマンドで確認できます。
  ```sh
  launchctl print gui/$(id -u)/com.knagato.paseo-attention-bar | grep -E 'state|pid'
  ```

## しくみ

Paseo デーモンには「要確認（attention）」の状態がもともと組み込まれています。

- エージェントが 1 ターンを終えると、`requiresAttention: true` と
  `attentionReason: "finished"` が付きます。
- Desktop でそのエージェントを開くと、この状態はクリアされます。

このアプリは、その状態をデーモンの WebSocket で購読して表示しているだけです。

接続手順は Paseo の CLI（`@getpaseo/client`）と同じです。

1. `ws://127.0.0.1:6767/ws` に接続します（ローカル接続では認証不要）。
2. `{"type":"hello","clientId":...,"clientType":"cli","protocolVersion":1,"capabilities":{...}}` を送ります。
   `capabilities` に `all_providers: true` を含めないと、カスタムプロバイダのエージェントが一覧から漏れます。
3. `status: server_info` が届いたら、`fetch_agents_request` で一覧を取得し、購読を始めます。
   このリクエストを含め、以降のリクエストはすべて `{"type":"session","message":{...}}` で包みます。
4. 以降は `agent_update`（`upsert` / `remove`）と `agent_attention_required` を受け取って、一覧を更新します。

各エージェントは、デーモンと同じ優先順位で分類します。上から順に判定し、最初に当てはまったものになります。

1. 権限確認が保留中 → 入力待ち（`?`）
2. `status` が `error` → エラー（`!`）
3. `status` が `running` → 実行中（`▶`）
4. `requiresAttention` が立っている → 完了・確認待ち（`✓`）
5. どれにも当てはまらない → 確認済み（表示しない）

## 開発

```sh
make build   # swift build -c release
make run     # .app にせず直接起動（ログイン時起動の設定は無効）
make bundle  # dist/PaseoAttentionBar.app を組み立てるだけ（ad-hoc 署名）
make release # 配布用 zip を作る（下記）
make clean
```

```
Sources/PaseoAttentionBar/
  main.swift / AppDelegate.swift
  Model/AgentSummary.swift       # スナップショット → 表示用モデル、分類
  Core/PaseoClient.swift         # WebSocket 接続・hello・購読・再接続・既読・deep link
  Core/Preferences.swift         # UserDefaults（接続先、▶表示、clientId）
  Core/LoginItem.swift           # SMAppService
  UI/StatusItemController.swift  # メニューバー項目のタイトル・右クリックメニュー
  UI/PopoverView.swift           # 一覧ポップオーバー（SwiftUI）
  UI/Formatting.swift
Resources/
  Info.plist
  com.knagato.paseo-attention-bar.plist  # LaunchAgent（make install が ~/Library/LaunchAgents へ配置）
scripts/bundle.sh                # .app の組み立てと署名
scripts/release.sh               # ユニバーサルビルド・Developer ID 署名・公証・zip 化
```

### リリースの作り方

`make release` を実行すると、次の処理を順に行い、`dist/PaseoAttentionBar-<バージョン>.zip` を作ります。

1. arm64 と x86_64 のユニバーサルバイナリでビルドする
2. Developer ID で署名する（Hardened Runtime を付ける）
3. `notarytool` で公証する
4. `stapler` で公証結果をアプリに添付する

バージョンは `Resources/Info.plist` の `CFBundleShortVersionString` から取ります。

事前に、キーチェーンに Developer ID Application の証明書を入れておき、公証用の認証情報も登録しておく必要があります。
認証情報の登録は 1 度だけで済みます。

```sh
xcrun notarytool store-credentials paseo-notary --apple-id <Apple ID> --team-id <Team ID>
```

署名 ID や profile 名は、環境変数 `SIGN_IDENTITY` / `NOTARY_PROFILE` で変えられます。

## ライセンス

[MIT](LICENSE)
