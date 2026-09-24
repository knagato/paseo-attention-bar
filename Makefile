.PHONY: build run bundle release install uninstall uninstall-loginitem clean

build:
	swift build -c release

# バンドルせず直接起動（開発用）。ログイン時起動の設定は .app でないと効かない。
run:
	swift run

# dist/PaseoAttentionBar.app を作る
bundle:
	./scripts/bundle.sh

# 配布用: ユニバーサルビルド → Developer ID 署名 → 公証 → dist/PaseoAttentionBar-<version>.zip
release:
	./scripts/release.sh

# /Applications へ配置して起動する。
# 常駐は LaunchAgent(com.knagato.paseo-attention-bar) が持っているので、
# pkill せず launchctl で止めて→入れ替え→bootstrap する（pkill だと KeepAlive が
# 差し替え途中のバンドルを掴んで上げ直してしまう）。plist は Resources/ から毎回配置する。
install: bundle
	-launchctl bootout gui/$(shell id -u)/com.knagato.paseo-attention-bar 2>/dev/null || true
	-pkill -x PaseoAttentionBar || true
	rm -rf /Applications/PaseoAttentionBar.app
	cp -R dist/PaseoAttentionBar.app /Applications/
	mkdir -p $(HOME)/Library/LaunchAgents
	cp Resources/com.knagato.paseo-attention-bar.plist $(HOME)/Library/LaunchAgents/
	launchctl bootstrap gui/$(shell id -u) $(HOME)/Library/LaunchAgents/com.knagato.paseo-attention-bar.plist

uninstall-loginitem:
	-launchctl bootout gui/$(shell id -u)/com.knagato.paseo-attention-bar 2>/dev/null || true
	rm -f $(HOME)/Library/LaunchAgents/com.knagato.paseo-attention-bar.plist

uninstall:
	-launchctl bootout gui/$(shell id -u)/com.knagato.paseo-attention-bar 2>/dev/null || true
	-pkill -x PaseoAttentionBar || true
	rm -rf /Applications/PaseoAttentionBar.app

clean:
	swift package clean
	rm -rf dist
