#!/usr/bin/env bash
# quint test・quint run が使う Rust の評価器を、認証付きの gh で取ってきて置く。
#
#   scripts/install-quint-evaluator.sh
#
# なぜ：Quint（0.33.1）は、評価器がなければ GitHub の API から認証なしで取ってくる。
# 認証なしの API は IP ごとに回数の上限があり、IP を共有する GitHub のランナーでは
# "rate limit exceeded" で失敗することがある（#9）。Quint にトークンを渡す設定はないので、
# 先に gh（GH_TOKEN か gh auth）で取ってきて、Quint が探す場所に置く。置いてあれば Quint は取りに行かない。
#
# - 版：node_modules の Quint が使う版（binaryManager.js の QUINT_EVALUATOR_VERSION）。先に npm ci --ignore-scripts で入れる
# - 置き場所：${QUINT_HOME:-~/.quint}/rust-evaluator-<版>/quint_evaluator（Quint の config.js と同じ）
# - 取ってきたファイルは、リリースに載っている SHA-256 で確かめる
# - Linux と macOS（x86_64・arm64）で動く（macOS の bash 3.2・BSD のコマンドでも動くように書く）
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
manager="$root/node_modules/@informalsystems/quint/dist/src/rust/binaryManager.js"
[ -f "$manager" ] || { echo "Quint がない。リポジトリの根で npm ci --ignore-scripts を動かす" >&2; exit 1; }

version="$(sed -n "s/.*QUINT_EVALUATOR_VERSION = '\(v[0-9.]*\)'.*/\1/p" "$manager")"
[ -n "$version" ] || { echo "評価器の版を ${manager} から読めない（Quint の版を上げたときは、このスクリプトを見直す）" >&2; exit 1; }

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) asset=quint_evaluator-x86_64-unknown-linux-gnu.tar.gz ;;
  Linux-aarch64 | Linux-arm64) asset=quint_evaluator-aarch64-unknown-linux-gnu.tar.gz ;;
  Darwin-x86_64) asset=quint_evaluator-x86_64-apple-darwin.tar.gz ;;
  Darwin-arm64) asset=quint_evaluator-aarch64-apple-darwin.tar.gz ;;
  *) echo "この OS・CPU の評価器はない：$(uname -s) $(uname -m)" >&2; exit 1 ;;
esac

dir="${QUINT_HOME:-$HOME/.quint}/rust-evaluator-${version}"
if [ -x "$dir/quint_evaluator" ]; then
  echo "評価器 ${version} はもうある：${dir}/quint_evaluator"
  exit 0
fi

repo=quint-co/quint
tag="evaluator/${version}"
digest="$(gh release view "$tag" --repo "$repo" --json assets --jq ".assets[] | select(.name == \"$asset\") | .digest")"
case "$digest" in
  sha256:*) want="${digest#sha256:}" ;;
  *) echo "リリース ${tag} に ${asset} の SHA-256 がない（digest：${digest:-なし}）" >&2; exit 1 ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
gh release download "$tag" --repo "$repo" --pattern "$asset" --dir "$tmp"

if command -v sha256sum > /dev/null; then
  got="$(sha256sum "$tmp/$asset" | cut -d ' ' -f 1)"
else
  got="$(shasum -a 256 "$tmp/$asset" | cut -d ' ' -f 1)"
fi
[ "$got" = "$want" ] || { echo "SHA-256 が合わない：${asset}（期待：${want}、実際：${got}）" >&2; exit 1; }

mkdir -p "$dir"
tar -xzf "$tmp/$asset" -C "$dir"
chmod +x "$dir/quint_evaluator"
echo "評価器 ${version} を置いた：${dir}/quint_evaluator（SHA-256 を確かめた）"
