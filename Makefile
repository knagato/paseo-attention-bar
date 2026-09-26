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

LABEL := com.knatrix.paseo-attention-bar
# 0.1.0 までのラベル。入れ替えのときに止めて消す（残すと新旧 2 つの LaunchAgent が同じ .app を起動し合う）
LEGACY_LABEL := com.knagato.paseo-attention-bar
AGENTS := $(HOME)/Library/LaunchAgents
GUI := gui/$(shell id -u)

# /Applications へ配置して起動する。
# 常駐は LaunchAgent($(LABEL)) が持っているので、
# pkill せず launchctl で止めて→入れ替え→bootstrap する（pkill だと KeepAlive が
# 差し替え途中のバンドルを掴んで上げ直してしまう）。plist は Resources/ から毎回配置する。
install: bundle
	-launchctl bootout $(GUI)/$(LEGACY_LABEL) 2>/dev/null || true
	rm -f $(AGENTS)/$(LEGACY_LABEL).plist
	-launchctl bootout $(GUI)/$(LABEL) 2>/dev/null || true
	-pkill -x PaseoAttentionBar || true
	rm -rf /Applications/PaseoAttentionBar.app
	cp -R dist/PaseoAttentionBar.app /Applications/
	mkdir -p $(AGENTS)
	cp Resources/$(LABEL).plist $(AGENTS)/
	launchctl bootstrap $(GUI) $(AGENTS)/$(LABEL).plist

uninstall-loginitem:
	-launchctl bootout $(GUI)/$(LABEL) 2>/dev/null || true
	-launchctl bootout $(GUI)/$(LEGACY_LABEL) 2>/dev/null || true
	rm -f $(AGENTS)/$(LABEL).plist $(AGENTS)/$(LEGACY_LABEL).plist

uninstall:
	-launchctl bootout $(GUI)/$(LABEL) 2>/dev/null || true
	-launchctl bootout $(GUI)/$(LEGACY_LABEL) 2>/dev/null || true
	-pkill -x PaseoAttentionBar || true
	rm -rf /Applications/PaseoAttentionBar.app

clean:
	swift package clean
	rm -rf dist
