#!/usr/bin/env bash
# specs/ の下のすべての .qnt に、quint typecheck と quint test を動かす。1 つでも失敗したら、終了コード 1。
#
#   scripts/check-specs.sh [<ファイルかディレクトリ> ...]   # 既定は specs/
#
# Quint は package.json で固定した版（node_modules/.bin/quint）を使う。先に npm ci --ignore-scripts で入れる。
# quint test は、名前が Test で終わる run をテストとして動かす。テストのないファイルは typecheck だけになる。
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
quint="$root/node_modules/.bin/quint"
[ -x "$quint" ] || { echo "quint がない。リポジトリの根で npm ci --ignore-scripts を動かす" >&2; exit 1; }

if [ $# -eq 0 ]; then
  [ -d "$root/specs" ] || { echo "確かめる .qnt がない（specs/ がない）"; exit 0; }
  set -- "$root/specs"
fi
files=()
for target in "$@"; do
  if [ -d "$target" ]; then
    while IFS= read -r f; do files+=("$f"); done < <(find "$target" -name '*.qnt' -not -path '*/node_modules/*' | sort)
  elif [ -f "$target" ]; then
    files+=("$target")
  else
    echo "見つからない：${target}" >&2
    exit 1
  fi
done

if [ ${#files[@]} -eq 0 ]; then
  echo "確かめる .qnt がない"
  exit 0
fi

echo "Quint $("$quint" --version)"
failed=()
for f in "${files[@]}"; do
  rel="${f#"$root"/}"
  echo "== ${rel}"
  if ! "$quint" typecheck "$f"; then
    failed+=("${rel}（typecheck）")
    continue # 型が通らなければ、テストは動かさない
  fi
  if ! "$quint" test "$f"; then
    failed+=("${rel}（test）")
  fi
done

echo "== ${#files[@]} ファイルを確かめた。失敗：${#failed[@]} 件"
for f in ${failed[@]+"${failed[@]}"}; do
  echo "  ${f}"
done
[ ${#failed[@]} -eq 0 ]
