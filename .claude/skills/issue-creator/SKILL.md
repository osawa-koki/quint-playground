---
name: issue-creator
description: GitHub Issue を5セクション形式（概要・背景・目的・達成条件・TODO）で作成する。gh issue create を実行する前、または新しい作業を Issue としてまとめるときに必ず使うこと。タスクの整理・分割・Issue 本文の起草にも使う。
user-invocable: false
---

# Issue 作成ルール

GitHub Issue を作成するときは、必ず以下の5セクション形式で本文を書く。題名は英語、本文は日本語。

## セクション構成

| セクション | 目的 | 書くこと |
|---|---|---|
| **概要** | 一言でまとめ | 何をするかを1〜2文で |
| **背景** | 文脈・動機 | なぜ今これが必要か。学ぶ上での意義・きっかけ |
| **目的** | ゴール | これが完了したら何ができるようになるか |
| **達成条件** | 完了の定義 | テスト・確認が可能な基準をチェックリストで |
| **TODO** | 実装ステップ | 作業を具体的なチェックリストに分解する |

背景と目的はあえて分ける。

- **背景**：「なぜ今これをやるか」（過去・現状の文脈）
- **目的**：「これが終わると何が変わるか」（未来の状態）

達成条件は「`specs/bank.qnt` に、口座と送金が `pure def` で書いてある」「`transferTest` などの `run` のテストが `scripts/check-specs.sh` で通る」「`quint run --invariant=noNegativeBalance` で反例が出ない」「CI が通る」のような確認可能な形で書く。TODO は実装手順の箇条書き。

## 実行コマンド

```sh
gh issue create --assignee osawa-koki --label <ラベル> --type <種類> [--milestone "<マイルストーン>"] \
  --title "<タイトル>" --body-file - <<'EOF'
## 概要

<概要>

## 背景

<背景>

## 目的

<目的>

## 達成条件

- [ ] <達成条件1>

## TODO

- [ ] <TODO1>
EOF
```

## Issue Type（CLAUDE.md より）

Issue Type（種類）は、作るときに必ず 1 つ付ける（`gh issue create --type <種類>`）。使えるのは `Feature`・`Bug`・`Task` の 3 つ：

| 種類 | 付ける Issue | 例 |
|---|---|---|
| `Feature` | 新しくできることを足す | 新しい仕様とテスト・新しい題材 |
| `Bug` | 動かないところ・まちがいを直す | 仕様の誤り・通らないテスト・README の誤り |
| `Task` | それ以外 | CI の手入れ・開発環境・Quint の版上げ・進め方のルール |

- 迷ったら、「新しくできることが増えるか（`Feature`）」「直すか（`Bug`）」「どちらでもないか（`Task`）」で決める
- 付け忘れたときは `gh issue edit <番号> --type <種類>` で付ける
- 使える種類は `gh api graphql -f query='query{repository(owner:"osawa-koki",name:"quint-playground"){issueTypes(first:10){nodes{name}}}}'` で確かめる

## ラベルとマイルストーン（CLAUDE.md より）

Issue は、ラベルとマイルストーンで仕分けして見るので、作るときに必ず付ける。

- ラベルは、`.github/custom-data/label.json` に定義してある。`name` がラベルの名前、`description` が付ける Issue の説明。書く前に読んで、作業の種類に合うものを選ぶ
- 複数に当てはまるときは、複数付けてよい（例：仕様を足して、そのために CI のジョブも直す → `spec`・`ci`）
- マイルストーンは、`.github/custom-data/milestone.json` に定義してある（README の「進み具合」の段階）。`state` が `open` の段階に入る作業なら、その `title` を付ける。どの段階にも入らない作業（CI・開発環境の手入れなど）には付けない
- 合うラベルやマイルストーンがないときは、`gh` で作らない。`label.json`・`milestone.json` に足す作業として、ユーザーに相談する（ファイルを変える PR がマージされると、GitHub に反映される）

## 粒度のルール（CLAUDE.md より）

Issue は「1つの PR でレビューできて、それだけで意味のあるまとまり」になるよう作る。

- 大きすぎる例：「銀行の仕様を全部書く」「段階 02 を全部やる」
- 細かすぎる例：「テストを 1 つ足す」「入金の関数を 1 つ書く」
- 適切な例：「口座と送金を関数として書き、テストする」「銀行の操作を状態機械にする」「CI に quint test を足す」
- 段階（マイルストーン）の中の作業が多いときは、親の Issue を作り、`gh issue edit <親> --add-sub-issue <子>` でサブ Issue としてつなぐ
