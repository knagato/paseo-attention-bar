.PHONY: build run bundle install uninstall clean

build:
	swift build -c release

# バンドルせず直接起動（開発用）。ログイン時起動の設定は .app でないと効かない。
run:
	swift run

# dist/PaseoAttentionBar.app を作る
bundle:
	./scripts/bundle.sh

# /Applications へ配置して起動する
install: bundle
	-pkill -x PaseoAttentionBar || true
	rm -rf /Applications/PaseoAttentionBar.app
	cp -R dist/PaseoAttentionBar.app /Applications/
	open /Applications/PaseoAttentionBar.app

uninstall:
	-pkill -x PaseoAttentionBar || true
	rm -rf /Applications/PaseoAttentionBar.app

clean:
	swift package clean
	rm -rf dist
