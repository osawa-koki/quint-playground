#!/usr/bin/env bash
# .github/custom-data/label.json・milestone.json に合わせて、GitHub のラベルとマイルストーンを直す。
#
#   sync-labels-milestones.sh           何が変わるかを表示するだけ（書き換えない）
#   sync-labels-milestones.sh --apply   GitHub に反映する
#
# ラベル：ファイルにないものは消す。previous_names に書いた名前のラベルがあれば、名前の変更として扱う
#         （消して作り直すと、Issue からラベルが外れるため）
# マイルストーン：消さない（消すと Issue から外れるため）。終わった段階は、ファイルの state を closed にする。
#                previous_titles に書いた名前があれば、名前の変更として扱う
#
# 使うもの：gh（GH_TOKEN か gh auth）・jq・bash（macOS の 3.2 でも動くよう、全角の文字の前の変数は ${} で囲む）。リポジトリは GITHUB_REPOSITORY か、gh repo view で決める
set -euo pipefail

apply=false
case "${1:-}" in
  --apply) apply=true ;;
  "") ;;
  *) echo "usage: $0 [--apply]" >&2; exit 2 ;;
esac

repo="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
dir="$(cd "$(dirname "$0")/../custom-data" && pwd)"
label_file="$dir/label.json"
milestone_file="$dir/milestone.json"
changes=0

# 変える内容を表示し、--apply のときだけ実行する
run() {
  changes=$((changes + 1))
  echo "  $*"
  if $apply; then
    "$@" < /dev/null > /dev/null
  fi
}

uri() { jq -rn --arg s "$1" '$s | @uri'; }

# ---- ファイルの中身を確かめる ----
jq -e '
  type == "array"
  and all(.[]; (.name | type == "string" and length > 0)
             and (.color | type == "string" and test("^[0-9a-f]{6}$"))
             and ((.description // "") | length <= 100)
             and ((.previous_names // []) | type == "array"))
  and ([.[].name] | length == (unique | length))
' "$label_file" > /dev/null || {
  echo "label.json の形が正しくない（name は重複なし・color は小文字の 6 桁の 16 進・description は 100 文字まで）" >&2
  exit 1
}
jq -e '
  type == "array"
  and all(.[]; (.title | type == "string" and length > 0)
             and ((.state // "open") | IN("open", "closed"))
             and ((.previous_titles // []) | type == "array"))
  and ([.[].title] | length == (unique | length))
' "$milestone_file" > /dev/null || {
  echo "milestone.json の形が正しくない（title は重複なし・state は open か closed）" >&2
  exit 1
}

# ---- ラベル ----
echo "== ラベル（${repo}）"
current_labels="$(gh api --paginate "repos/$repo/labels?per_page=100" --jq '.[] | {name, color, description: (.description // "")}' | jq -s .)"
renamed_from='[]'

while IFS= read -r want; do
  name="$(jq -r .name <<< "$want")"
  color="$(jq -r .color <<< "$want")"
  desc="$(jq -r '.description // ""' <<< "$want")"
  have="$(jq -c --arg n "$name" '.[] | select(.name == $n)' <<< "$current_labels")"

  if [ -n "$have" ]; then
    if [ "$(jq -r .color <<< "$have")" != "$color" ] || [ "$(jq -r .description <<< "$have")" != "$desc" ]; then
      echo "直す：${name}"
      run gh api -X PATCH "repos/$repo/labels/$(uri "$name")" -f color="$color" -f description="$desc"
    fi
    continue
  fi

  old="$(jq -r --argjson cur "$current_labels" 'first((.previous_names // [])[] as $p | $cur[] | select(.name == $p) | .name) // empty' <<< "$want")"
  if [ -n "$old" ]; then
    echo "名前を変える：${old} → ${name}"
    run gh api -X PATCH "repos/$repo/labels/$(uri "$old")" -f new_name="$name" -f color="$color" -f description="$desc"
    renamed_from="$(jq -c --arg o "$old" '. + [$o]' <<< "$renamed_from")"
  else
    echo "作る：${name}"
    run gh api -X POST "repos/$repo/labels" -f name="$name" -f color="$color" -f description="$desc"
  fi
done < <(jq -c '.[]' "$label_file")

while IFS= read -r name; do
  [ -z "$name" ] && continue
  echo "消す：${name}"
  run gh api -X DELETE "repos/$repo/labels/$(uri "$name")"
done < <(jq -r --slurpfile want "$label_file" --argjson renamed "$renamed_from" \
  '.[].name | select(. as $n | ($want[0] | map(.name) | index($n)) == null and ($renamed | index($n)) == null)' <<< "$current_labels")

# ---- マイルストーン ----
echo "== マイルストーン（${repo}）"
current_milestones="$(gh api --paginate "repos/$repo/milestones?state=all&per_page=100" --jq '.[] | {number, title, state, description: (.description // "")}' | jq -s .)"
used='[]'

while IFS= read -r want; do
  title="$(jq -r .title <<< "$want")"
  state="$(jq -r '.state // "open"' <<< "$want")"
  desc="$(jq -r '.description // ""' <<< "$want")"
  have="$(jq -c --arg t "$title" '.[] | select(.title == $t)' <<< "$current_milestones")"

  if [ -n "$have" ]; then
    number="$(jq -r .number <<< "$have")"
    used="$(jq -c --argjson n "$number" '. + [$n]' <<< "$used")"
    if [ "$(jq -r .state <<< "$have")" != "$state" ] || [ "$(jq -r .description <<< "$have")" != "$desc" ]; then
      echo "直す：${title}"
      run gh api -X PATCH "repos/$repo/milestones/$number" -f state="$state" -f description="$desc"
    fi
    continue
  fi

  old="$(jq -c --argjson cur "$current_milestones" 'first((.previous_titles // [])[] as $p | $cur[] | select(.title == $p)) // empty' <<< "$want")"
  if [ -n "$old" ]; then
    number="$(jq -r .number <<< "$old")"
    used="$(jq -c --argjson n "$number" '. + [$n]' <<< "$used")"
    echo "名前を変える：$(jq -r .title <<< "$old") → ${title}"
    run gh api -X PATCH "repos/$repo/milestones/$number" -f title="$title" -f state="$state" -f description="$desc"
  else
    echo "作る：${title}"
    run gh api -X POST "repos/$repo/milestones" -f title="$title" -f state="$state" -f description="$desc"
  fi
done < <(jq -c '.[]' "$milestone_file")

while IFS= read -r title; do
  [ -z "$title" ] && continue
  echo "ファイルにないマイルストーン（消さない）：${title}"
done < <(jq -r --argjson used "$used" '.[] | select(.number as $n | $used | index($n) | not) | .title' <<< "$current_milestones")

if $apply; then
  echo "== ${changes} 件を反映した"
else
  echo "== ${changes} 件の変更がある（表示だけ。反映するときは --apply）"
fi
