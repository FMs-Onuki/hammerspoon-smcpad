#!/bin/sh
# インストールスクリプト
# 設定ファイルへのシンボリックリンクを作成する。
# 既存の実ファイルがあれば .bak に退避してからリンクを貼る。
set -eu

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

# link <リポジトリ内の実体> <貼り付け先>
link() {
  src="$REPO_DIR/$1"
  dst="$2"

  mkdir -p "$(dirname "$dst")"

  # 既に正しいリンクなら何もしない
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    echo "ok    : $dst"
    return
  fi

  # 既存の実ファイル/別リンクは退避
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    mv "$dst" "$dst.bak"
    echo "backup: $dst -> $dst.bak"
  fi

  ln -s "$src" "$dst"
  echo "link  : $dst -> $src"
}

# ---- リンク定義 ----
link "hammerspoon/init.lua" "$HOME/.hammerspoon/init.lua"

echo "done. Hammerspoon を起動し、コンソールで hs.reload() を実行してください。"
