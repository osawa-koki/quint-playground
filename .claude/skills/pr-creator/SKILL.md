---
name: pr-creator
description: GitHub PR を5セクション形式（Close #N・概要・変更内容・動作確認手順・確認したこと）で作成する。gh pr create を実行する前、または PR 本文を考えるときに必ず使うこと。
user-invocable: false
---

# PR 作成ルール

`gh pr create` を実行するときは、必ず以下の5セクション形式で本文を書く。題名は英語、本文は日本語。

## セクション構成

| セクション | 目的 | 書くこと |
|---|---|---|
| `Close #N` | Issue との紐づけ | 本文の**先頭**に書く。これがないと Issue が自動クローズされない |
| **概要** | 1〜2 文のまとめ | この PR で何をしたか |
| **変更内容** | ファイル単位の変更リスト | `- ファイルパス：変更の内容` の形式で列挙する |
| **動作確認手順** | 再現可能な確認手順 | `quint typecheck`・`quint test`・`quint run`・markdownlint などのコマンドを含む具体的な手順。コードブロックでコマンドを示す。変更が内部的でコマンドで確かめられない場合は「（手動確認不要）」と書く |
| **確認したこと** | 著者がチェック済みの項目 | `- [x]` 形式のチェックリスト |

Issue（背景・目的）はすでに書いてある前提なので、PR 本文では「何を変えたか」と「どう確かめたか」に集中する。

## 実行コマンド

````sh
gh pr create --assignee osawa-koki --base main --head issues/<番号> \
  --title "<タイトル>" --body-file - <<'EOF'
Close #<番号>

## 概要

<概要>

## 変更内容

- `<ファイルパス>`：<変更内容>

## 動作確認手順

```sh
# <確認コマンド>
```

## 確認したこと

- [x] <確認項目1>
- [x] <確認項目2>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
````

## CLAUDE.md のルールとの対応

PR を作る際は CLAUDE.md の以下のルールも守る：

- **Assignees に必ず `osawa-koki` を設定する**
- 確認したことは、実際に確かめたものだけを `- [x]` にする。マージの後でないと確かめられないもの（main での反映など）は `- [ ]` で書き、確かめたら PR の本文を更新する
- 仕様を変えた PR では、`quint test` の結果（通ったテストの数）と、`quint run` で確かめた不変条件を「確認したこと」に書く
- CI がすべて成功してからマージする（`gh pr checks <PR番号> --watch`）
- マージは `gh pr merge <PR番号> --merge`（マージコミット）
- ブランチは消さない
