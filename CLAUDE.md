# CLAUDE.md

[Quint](https://quint-lang.org/)（Informal Systems の仕様記述言語）を、実際に仕様を書いてテストしながら学ぶためのリポジトリ。段階ごとに小さな仕様を書き、`quint test`・`quint run`・`quint verify` で確かめて、最後にまとまった題材（相互排除・2 フェーズコミット・合意のプロトコルなど）を仕様にする。概要と進み具合は [README.md](README.md) を参照。

## 絶対に守ること

- **ユーザーへの応答は、すべて日本語で書く**（説明・報告・質問・途中の短い知らせも。英語で書かない）。コミットの件名・PR の題名・Quint のコードの識別子など、このファイルで英語と決めたものだけは英語のまま
- **書いた仕様は、必ずツールで確かめてからコミットする。** 少なくとも `quint typecheck` と `quint test` を通す。不変条件を書いたら `quint run --invariant=<名前>` でも確かめる。通らないもの・確かめていないものを「動く」と書かない
- **Quint の文法・挙動は、記憶で決めつけない。** 公式のドキュメントか、実際に `quint` で動かした結果で確かめる。確かめられないことは、事実として書かず「確かめられなかった」と書く
  - 出典にしてよいもの：Quint の公式サイト（<https://quint-lang.org/docs>）、Quint のリポジトリ（<https://github.com/informalsystems/quint>。`docs/`・`examples/`・リリースノート）、Apalache の公式ドキュメント（<https://apalache-mc.org/docs/>）、TLA+ の公式の資料（<https://lamport.azurewebsites.net/tla/tla.html>）。版がわかるものは、版がわかる形で書く
  - 出典にしないもの：個人のブログ・解説記事（Qiita・Zenn・Medium など）・動画・まとめのページ。読み比べて参考にするのはよいが、事実の出典にはしない
- **料金がかかるもの（GitHub の有料の機能・API・クラウドなど）を使う・変えるときは、その前に必ず料金を見積もる**
  - 公式の料金のページで、無料枠と単価を確かめる。見積もりの根拠（出典）を、ユーザーに見せる
  - GitHub の Free プランの無料枠の中で収まる前提で進める（リポジトリは public なので、標準の GitHub ホストランナーの Actions は無料）。**無料枠を超えそうなとき、または料金がわからないときは、止めてユーザーに確かめる**
- 本物の鍵や認証情報を、リポジトリ・Issue・PR・会話に書かない。リポジトリは public なので、手元の環境の情報（ユーザー名以外のパス・トークンなど）もコミットしない

## 構成

追加したら、ここと README の「構成」を更新する。

| ディレクトリ・ファイル | 役割 |
|---|---|
| `.vscode/` | VS Code の推奨の拡張（`extensions.json`：EditorConfig・markdownlint・Quint） |
| `.editorconfig` | インデント・改行などのそろえ方 |
| `.markdownlint-cli2.jsonc` | markdownlint の設定（CI と VS Code の拡張が読む）。日本語の文は 1 段落を 1 行で書くので、行の長さ（MD013）と表の列の幅（MD060）は見ない |
| `.github/custom-data/` | GitHub の設定を表すデータ。`label.json`（ラベルの名前・色・説明・前の名前）・`milestone.json`（マイルストーンの名前・状態・説明・前の名前）。`.github/scripts/sync-labels-milestones.sh` が GitHub に同期する（`.github/` の下で GitHub が読むものとぶつからないよう、`custom-data/` に分けた） |
| `.github/scripts/` | ワークフローが使うスクリプト。`sync-labels-milestones.sh`（`label.json`・`milestone.json` と GitHub を比べる。`--apply` で反映する） |
| `.claude/` | Claude Code の設定。`skills/`（開発フローのスキル：issue-creator・pr-creator・pr-merger）・`settings.json`（PreToolUse のフックで `hooks/guard-main-worktree.py` を呼ぶ） |

## 決めたこと

- **進め方**：README の「進み具合」の段階（マイルストーン）の順に進める。段階ごとに、小さな仕様とそのテストを書き、わかったこと・つまずいた点を、仕様のファイルのコメントか README に残す。対話で教わる形（解説・クイズのスキル）は使わない
- **リポジトリは public**。GitHub の標準のランナーで Actions を動かす（セルフホストランナーは使わない）
- 手元の Mac のディスクの空きが少ない。大きなファイル（`quint run`・`verify` の出力・Apalache の作業用のファイルなど）は使い終わったら消し、リポジトリにコミットしない（`.gitignore`）
- **手作業の手順・前提は、すべて README に書く**：ツールの入れ方、ログイン、コードから読み取れないもの。ユーザーに手作業を頼んだら、その手順を README の「セットアップ」に足す
- VS Code の拡張は、`.vscode/extensions.json` に書く

## 開発フロー

作業は必ず **Issue → ブランチ → PR → CI → マージ** の順で進める。小さな修正でも同じ。

1. **Issue を作る**
   - `gh issue create --assignee osawa-koki --label <ラベル> --type <種類> [--milestone "<マイルストーン>"] --title "..." --body-file -`
   - Issue Type（種類）は、必ず 1 つ付ける（`--type`）。このリポジトリで使えるのは `Feature`・`Bug`・`Task` の 3 つ：`Feature` は新しくできることを足す（新しい仕様とテスト・題材など）、`Bug` はまちがいを直す（仕様・テスト・README の誤りも含む）、`Task` はそれ以外（CI・開発環境・Quint の版上げ・進め方）。付け忘れたときは `gh issue edit <番号> --type <種類>` で付ける
   - ラベルは、作業の種類で 1 つ以上付ける。どれがあり、どの Issue に付けるかは `.github/custom-data/label.json` の `name` と `description` を見る
   - README の「進み具合」の段階（「01. 基本の文法とテスト」〜「05. 題材の仕様」）に入る作業なら、そのマイルストーンを付ける。段階の中の作業が多いときは、親の Issue を作り、`gh issue edit <親> --add-sub-issue <子>` でサブ Issue としてつなぐ。新しい段階を始めるときは、`.github/custom-data/milestone.json` に足し、README の「進み具合」にも足す
   - ラベルとマイルストーンは、`.github/custom-data/label.json`・`milestone.json` で管理する。`gh label create` や `gh api .../milestones` で直接変えない。ファイルを変える PR では、`sync-labels-milestones.yml` が何が変わるかを表示し、main にマージされると GitHub に反映する。ラベルの名前を変えるときは `previous_names`、マイルストーンは `previous_titles` に前の名前を書く（書かないと、消して作り直す動きになり、Issue から外れる）。マイルストーンは消さず、終わった段階は `"state": "closed"` にする
   - 題名は英語、本文は日本語で、**概要・背景・目的・達成条件・TODO** の 5 セクションで書く。issue-creator スキル（`.claude/skills/issue-creator/SKILL.md`）に従う
   - Issue は適切な粒度で作る。1 つの Issue は、1 つの PR でレビューできて、それだけで意味のあるまとまり（例：「集合とマップの演算子を試す」「カウンターの状態機械と不変条件を書く」「CI」は別々）。「Quint 全体」のような大きすぎる Issue も、テスト 1 つごとのような細かすぎる Issue も作らない
2. **Issue に紐づくブランチと、作業用の worktree を作る**
   - `gh issue develop <番号> --name issues/<番号> --base main`
   - `git fetch origin issues/<番号> && git worktree add --track -b issues/<番号> .worktrees/issues-<番号> origin/issues/<番号>`
   - ブランチ名は `issues/<番号>`。`git switch -c` や `git worktree add -b` だけでローカルに作らない（Issue の Development 欄に紐づかないため）
   - **作業（ファイルの編集・実行・コミット・push）は、毎回 `.worktrees/issues-<番号>` の中で行う。** 複数のセッションが同時に作業しても、ブランチの切り替えや pull がぶつからないようにするため
   - メインの作業ツリー（`/Users/osawa-koki/d/quint-playground`）は `main` のままにし、`git switch`・`git checkout` でブランチを切り替えない。そこでは作業しない（読むだけ）。最新の main は `git fetch` して `origin/main` で見る
   - `git stash` は使わない（stash は、すべての worktree で共有されるので、ほかのセッションのものを取り出してしまうことがある）。作業を一時的によけるときは、途中のコミット（本文に `Refs #<番号>`）にする
   - この 2 つは、Claude Code の PreToolUse フック（`.claude/settings.json` から `.claude/hooks/guard-main-worktree.py`）で止めている：メインの作業ツリーでの `git switch`・`git checkout`（`git checkout -- <file>` も）・`gh pr checkout`・`gh issue develop --checkout` と、どこでもの `git stash`。動く場所は、cwd・`cd <dir> &&`・`git -C <dir>` から決め、わからないとき（変数・`cd -` など）は止める。止まるのは Claude Code が動かすコマンドだけで、人がターミナルで打つものは止まらない
3. **書いてコミットする**
   - コミットと push の直前に、`git -C .worktrees/issues-<番号> branch --show-current` で `issues/<番号>` にいるかを確かめる。違っていたら、コミットも push もせずに止まり、ユーザーに伝える
   - push は `git push origin issues/<番号>` のように、ブランチ名を書いて行う（`git push` だけにしない）
   - コミットメッセージは「英語の件名＋日本語の本文」。最後のコミットの本文に `Close #<番号>`、途中のコミットには `Refs #<番号>` を入れる
4. **PR を作る**
   - `gh pr create --assignee osawa-koki --base main --head issues/<番号> --title "..." --body-file -`
   - **Assignees には必ず `osawa-koki` を設定する。**
   - 題名は英語、本文は日本語で、**Close #N・概要・変更内容・動作確認手順・確認したこと** の 5 セクションで書く。pr-creator スキル（`.claude/skills/pr-creator/SKILL.md`）に従う
5. **CI を確認する**
   - `gh pr checks <PR番号> --watch` で、すべてのジョブの成功を確認する（その PR で動くワークフローがなければ、ないことを確かめる）
6. **自分で確認してマージする**
   - PR を作ったら、ユーザーの指示を待たずにマージまで進める
   - マージは pr-merger スキル（`.claude/skills/pr-merger/SKILL.md`）に従い、次を順番に確かめる：Issue の課題把握・PR の変更内容・Issue × PR 整合性・CI 全 pass・未解決のレビュー指摘なし・余計な変更なし・CLAUDE.md ルール準拠・マージ後の main の CI。1 つでも問題があればマージせずにユーザーに伝える
   - `gh pr merge <PR番号> --merge`（マージコミット）。ブランチは消さない
   - マージ後の main の CI を確かめたら、`git worktree remove .worktrees/issues-<番号>` で worktree を片付ける（ブランチは残る）

PR は役割ごとに分ける。前の PR に依存する場合は、マージ後の `main` から次のブランチを切る。

## CI（GitHub Actions）

ワークフローを足したら、この表に書く。

| ワークフロー | トリガー | 内容 |
|---|---|---|
| `.github/workflows/sync-labels-milestones.yml` | `.github/custom-data/**`・同期のスクリプト・このワークフローが変わった PR と `main` プッシュ、手で動かす（`workflow_dispatch`。`main` だけ反映） | `.github/scripts/sync-labels-milestones.sh` で、`label.json`・`milestone.json` と GitHub のラベル・マイルストーンを比べる。PR の `plan` のジョブは差分を表示するだけ（`issues: read`）。`main` の `apply` のジョブが反映する（`--apply`、`issues: write`）。ラベルはファイルにないものを消し、マイルストーンは消さない。`gh` と `jq` だけを使う。料金：public のリポジトリの標準のランナーなので無料 |

- actions は、すべてコミットの SHA で固定し、行の終わりにバージョンを書く（例：`uses: actions/checkout@<40 文字の SHA> # v7.0.1`）。SHA は `gh api repos/<owner>/<repo>/commits/<タグ> --jq .sha` で調べる
- ワークフローを変えたら actionlint で確認する（`docker run --rm -v "$PWD:/repo:ro" -w /repo rhysd/actionlint:1.7.7 -no-color`）
- ジョブの `runs-on` は `ubuntu-24.04` に固定する（`ubuntu-latest` にしない）
  - 料金：public のリポジトリでは、標準の GitHub ホストランナーは無料（<https://docs.github.com/en/billing/concepts/product-billing/github-actions> の "The use of standard GitHub-hosted runners is free: … In public repositories"）。larger runners は public でも有料なので使わない。spending limit・支払いの設定は変えない
- すべてのジョブに `timeout-minutes` を付ける。`${{ }}` を `run:` に直接埋め込まない（環境変数で渡す）
