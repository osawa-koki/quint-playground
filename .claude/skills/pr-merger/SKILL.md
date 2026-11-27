---
name: pr-merger
description: PR をマージする前の確認を8ステップで行い、安全にマージする。gh pr merge を実行する前、またはマージしてよいか判断するときに必ず使うこと。
user-invocable: false
---

# PR マージ確認ルール

`gh pr merge` を実行する前に、以下の8ステップを順番に確認する。1つでも失敗したらマージせず、ユーザーに報告する。

## ステップ1：Issue の課題を把握する

PR 本文の先頭にある `Close #N` から Issue 番号を特定し、Issue の内容を読む。

```sh
gh issue view <番号>
```

確認するもの：

- この Issue が解決しようとしている課題・ゴールは何か
- 達成条件（完了の定義）は何か

## ステップ2：PR の変更内容を把握する

```sh
gh pr diff <PR番号>
```

確認するもの：

- どのファイルが変わったか
- 各ファイルで何が変わったか

## ステップ3：Issue × PR の整合性を確認する

ステップ1で把握した Issue の達成条件と、ステップ2で把握した変更内容を照らし合わせる。

判断基準：

- Issue の TODO がすべて PR の差分に含まれているか
- PR の変更が Issue の課題を解決しているか
- 仕様の PR では、達成条件のテスト・不変条件が、差分の中に実際にあるか（`run` の名前・`val` の不変条件の名前で探す）

整合しない場合はマージせずにユーザーに報告する。

## ステップ4：CI が全て pass しているか確認する

```sh
gh pr checks <PR番号> --watch
```

すべてのジョブが `pass` になっていない場合はマージしない。`--watch` で、動いている途中のジョブが終わるのを待つ。

- その PR で動くワークフローがないときは `no checks reported` と出る。PR の変更したファイルが、どのワークフローの `paths` にも入らないことを確かめてから、次へ進む
- ジョブが始まらずに失敗したとき（課金の問題など）は、成功とみなさない。マージせずにユーザーに報告する。支払い・spending limit の設定は変えない

## ステップ5：未解決のレビュー指摘がないか確認する

PR のコメントと、行ごとのレビューコメント（スレッド）を読む：

```sh
gh pr view <PR番号> --comments
```

解決済みになっていないスレッドを数える：

```sh
gh api graphql -F owner=osawa-koki -F repo=quint-playground -F pr=<PR番号> -f query='
  query($owner:String!,$repo:String!,$pr:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$pr){
    reviewThreads(first:100){nodes{id isResolved path line comments(first:1){nodes{author{login} body}}}}}}}' \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved|not) | "\(.path):\(.line) \(.comments.nodes[0].author.login): \(.comments.nodes[0].body|.[0:80])"'
```

- 1 行でも出たら、マージしない。出た指摘（ファイル・行・内容）をユーザーに報告する
- 指摘に対応するときは：
  - 直したら、直したコミットを push し、スレッドを解決済みにする
  - 直さないと判断したら、理由をスレッドに返信してから解決済みにする。理由のない解決済みにはしない
- スレッドを解決済みにするコマンド（スレッドの `id` は、上の query で調べる）：

  ```sh
  gh api graphql -F id=<スレッドの id> -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}'
  ```

## ステップ6：差分に余計な変更がないか確認する

ステップ2の差分を再確認する。

判断基準：

- Issue のスコープ外のファイルが変更されていないか
- デバッグ用コード・一時ファイル（`_apalache-out/`・`*.itf.json` のトレースなど）が混入していないか

余計な変更がある場合はマージせずにユーザーに報告する。

## ステップ7：CLAUDE.md のルールに準拠しているか確認する

以下を確認する：

| 項目 | 確認方法 |
|---|---|
| Assignees に `osawa-koki` が設定されているか | `gh pr view <PR番号>` |
| PR 本文が5セクション形式（Close #N・概要・変更内容・動作確認手順・確認したこと）になっているか | `gh pr view <PR番号>` |
| ブランチ名が `issues/<番号>` になっているか | `gh pr view <PR番号> --json headRefName` |
| コミットメッセージが「英語の件名＋日本語の本文」になっているか | `gh pr view <PR番号> --json commits` |

## ステップ8：マージしてから main の CI を確認する

すべてのステップが通過したらマージする：

```sh
gh pr merge <PR番号> --merge
```

マージ後、main で動くワークフローがあれば、成功することを確認する（なければ、ないことを確かめる）：

```sh
gh run list --branch main --limit 5
gh run watch --exit-status <run-id>
```

main の CI が失敗した場合はユーザーに報告する。

main の CI を確かめたら、worktree を片付け、メインの作業ツリーの main を進める（ブランチは消さない）：

```sh
git -C /Users/osawa-koki/d/quint-playground worktree remove .worktrees/issues-<番号>
git -C /Users/osawa-koki/d/quint-playground fetch origin && git -C /Users/osawa-koki/d/quint-playground merge --ff-only origin/main
```

## NG 時の報告フォーマット

マージできない場合は、以下の形式でユーザーに伝える：

```text
マージを中断しました。

理由：<ステップ番号>「<ステップ名>」で問題が見つかりました。
詳細：<具体的に何が問題か>
対応：<何をすれば解決するか>
```
