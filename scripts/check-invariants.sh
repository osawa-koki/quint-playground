#!/usr/bin/env bash
# 仕様の不変条件を、quint run のランダムなシミュレーションで確かめる。表（下の CHECKS）の 1 行が 1 つの確かめ。
#
#   scripts/check-invariants.sh            # 表のすべて
#   scripts/check-invariants.sh <名前>     # 表の 1 列めの名前で絞る（いくつでも）
#
# 表の列（| で区切る）：
#   名前 | 仕様のファイル（リポジトリの根から） | step の action | 不変条件（空白で区切る） | 期待（ok か violation）
#
# - ok：破られないこと。破られたら失敗（反例のトレースが出る）
# - violation：破られること（わざと不具合のある仕様で、反例が出ることを確かめる）。破られなければ失敗
# - シミュレーションは乱数なので、ok でも「確かめた範囲で破られなかった」だけ（網羅は段階 04 の quint verify）
# - QUINT_RUN_SAMPLES（既定 10000）・QUINT_RUN_STEPS（既定 20）で、本数と長さを変えられる
set -euo pipefail

CHECKS='
bank_machine | specs/bank_machine.qnt | step | noNegativeBalance accountsFixed totalMatchesFlow | ok
bank_concurrent_unsafe | specs/bank_concurrent.qnt | stepUnsafe | moneyConserved | violation
bank_concurrent_unsafe_nonnegative | specs/bank_concurrent.qnt | stepUnsafe | noNegativeBalance | ok
bank_concurrent_locked | specs/bank_concurrent.qnt | stepLocked | noNegativeBalance moneyConserved locksHeld | ok
'

root="$(cd "$(dirname "$0")/.." && pwd)"
quint="$root/node_modules/.bin/quint"
[ -x "$quint" ] || { echo "quint がない。リポジトリの根で npm ci --ignore-scripts を動かす" >&2; exit 1; }
samples="${QUINT_RUN_SAMPLES:-10000}"
steps="${QUINT_RUN_STEPS:-20}"

trim() { sed 's/^ *//; s/ *$//' <<< "$1"; }

failed=()
count=0
while IFS='|' read -r name file step invariants expect; do
  name="$(trim "$name")"
  [ -n "$name" ] || continue
  if [ $# -gt 0 ] && ! printf '%s\n' "$@" | grep -qx "$name"; then
    continue
  fi
  file="$(trim "$file")"; step="$(trim "$step")"; invariants="$(trim "$invariants")"; expect="$(trim "$expect")"
  count=$((count + 1))
  echo "== ${name}（${file}・step=${step}・期待：${expect}）"
  # --invariants は値をいくつも取るので、ファイルの名前は前に書く。並べて渡すと、破られた不変条件に ❌ が付く。
  # --verbosity=1 は、破られなかったときの例のトレースを出さないが、反例も出さない。そこで、ok を期待するものは
  # 1 で動かし、破られたら出力の seed で 2 で動かし直して反例を出す。violation を期待するものは、反例を見るのが
  # 目的なので、はじめから 2 で動かす
  if [ "$expect" = ok ]; then verbosity=1; else verbosity=2; fi
  out="$(mktemp)"
  # shellcheck disable=SC2086 # 不変条件は空白で区切って、別々の引数にする
  if "$quint" run "$root/$file" --step="$step" --max-samples="$samples" --max-steps="$steps" --verbosity="$verbosity" --invariants $invariants > "$out" 2>&1; then
    result=ok
  else
    result=violation
  fi
  cat "$out"
  seed="$(sed -n 's/.*--seed=\(0x[0-9a-f]*\).*/\1/p' "$out" | tail -n 1)"
  rm -f "$out"
  if [ "$result" = violation ] && [ "$verbosity" = 1 ] && [ -n "$seed" ]; then
    echo "-- 反例（--seed=${seed} で動かし直した）"
    # shellcheck disable=SC2086
    "$quint" run "$root/$file" --step="$step" --max-steps="$steps" --seed="$seed" --verbosity=2 --invariants $invariants || true
  fi
  if [ "$result" != "$expect" ]; then
    failed+=("${name}（期待：${expect}、結果：${result}）")
  fi
done <<< "$CHECKS"

if [ $# -gt 0 ] && [ "$count" -eq 0 ]; then
  echo "表に、その名前がない：$*" >&2
  exit 1
fi
echo "== ${count} 件を確かめた（${samples} 本 × ${steps} 歩）。期待と違う：${#failed[@]} 件"
for f in ${failed[@]+"${failed[@]}"}; do
  echo "  ${f}"
done
[ ${#failed[@]} -eq 0 ]
