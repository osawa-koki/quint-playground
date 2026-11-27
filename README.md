# quint-playground

🔁🔁🔁 Quint で仕様を書いてテストしながら学ぶリポジトリ！

[Quint](https://quint.sh/) は、TLA+ と同じ考え方（状態と遷移で系を書き、性質を確かめる）を、プログラミング言語に近い書き方でできる仕様記述言語。このリポジトリでは、簡単な銀行システムを題材に、仕様を書いて、テスト（`quint test`）・ランダムなシミュレーション（`quint run`）・モデル検査（`quint verify`）で確かめながら、Quint の書き方と考え方を身につける。そのあと Rails で銀行を作り、仕様から作ったトレースで実装を確かめる。

## 全体の流れ

```text
手元の Mac（VS Code ＋ Claude Code ＋ quint）
 │  1. 銀行の仕様（specs/*.qnt）とテストを書く
 │     quint typecheck / test / run / verify で確かめる
 │  2. Rails で銀行を作り、quint run のトレースを流して確かめる
 │  git push
 ▼
GitHub（osawa-koki/quint-playground）
    Issue と PR・CI（GitHub Actions）
```

## 構成

| ディレクトリ・ファイル | 役割 |
|---|---|
| `specs/` | Quint の仕様（`.qnt`）とテスト |
| `scripts/` | 手で動かすスクリプト。`check-specs.sh`（`specs/` のすべての `.qnt` に `quint typecheck` と `quint test` を動かす。CI も同じものを呼ぶ） |
| `package.json`・`package-lock.json`・`.node-version` | Quint の版の固定と、CI の Node.js の版 |
| `.vscode/` | VS Code の推奨の拡張（EditorConfig・markdownlint・Quint） |
| `.editorconfig` | インデント・改行などのそろえ方 |
| `.markdownlint-cli2.jsonc` | markdownlint の設定 |
| `.github/` | GitHub Actions のワークフロー（`workflows/`。CI・ラベルの同期）・ワークフローが使うスクリプト（`scripts/`。リンクの確認・ラベルの同期）と、ラベル・マイルストーンの定義（`custom-data/label.json`・`milestone.json`。main にマージされると、`scripts/sync-labels-milestones.sh` が GitHub に反映する） |
| `.claude/` | Claude Code のスキル（Issue・PR の作り方・マージ前の確認）と、メインの作業ツリーでブランチを切り替えさせないフック |
| `CLAUDE.md` | 開発の約束ごと（絶対に守ること・開発フロー・決めたこと） |

## 進み具合

- [x] リポジトリの土台（CLAUDE.md・README・エディタ設定・ラベルとマイルストーン・Claude Code のフックと開発フローのスキル）
- [x] CI（Markdown の lint・リンクの確認・`quint typecheck`・`quint test`）と、Quint の版の固定
- [ ] 01. 口座と取引の基本：型・レコード・マップ・`pure def` で、口座と入金・出金・送金を関数として書き、`run` でテストする
- [ ] 02. 銀行の状態機械：`var`・`action`・`init` と `step`・`nondet` で、銀行の操作を状態の遷移として書く
- [ ] 03. 不変条件と並行の送金：残高が負にならない・総額が変わらないを `quint run` で確かめ、同時の送金の不具合を反例で見る
- [ ] 04. モデル検査：Apalache を使った `quint verify` で、銀行の性質を網羅的に確かめる
- [ ] 05. Rails の実装と突き合わせる：Rails の銀行に `quint run` のトレース（ITF）を流して確かめる（モデルベースのテスト）
- [ ] 06. 題材を広げる：2 フェーズコミット・相互排除・合意のプロトコルなど

01〜06 は、それぞれ GitHub のマイルストーンになっている（`.github/custom-data/milestone.json`）。

## セットアップ

### Quint を入れる

Node.js（18 以上。CI は `.node-version` の 24）が要る。Homebrew などで入れたものでよい。Quint は `package.json` で版を固定している（いまは 0.33.1）ので、グローバルには入れず、リポジトリの中に入れる：

```sh
npm ci --ignore-scripts   # node_modules/ に入る（約 40 MB）。install スクリプトは動かさない
npx quint --version       # 0.33.1
```

- `quint test`・`quint run` が使う Rust の評価器は、初めて動かしたときに GitHub から `~/.quint/` に取ってくる（数 MB）
- `quint verify` は Apalache（Java 17 以上が要る）を使う。使うのは段階 04 から。入れ方はそのときに足す
- VS Code では、Quint の拡張（`.vscode/extensions.json` の推奨）が、書いている間に型のエラーを示す

### 仕様を確かめる

コミットの前に、CI と同じ確認を手元で動かす：

```sh
scripts/check-specs.sh                    # specs/ のすべての .qnt に quint typecheck と quint test
scripts/check-specs.sh specs/bank.qnt     # ファイルを絞る
npx quint run --invariant=<名前> specs/<ファイル>.qnt   # 不変条件をランダムなシミュレーションで確かめる
```

### Markdown を手元で確かめる

```sh
npx -y markdownlint-cli2@0.24.2           # lint（CI の action と同じ版。設定は .markdownlint-cli2.jsonc）
python3 -I .github/scripts/check-links.py # リポジトリの中のリンク（ファイル・見出しのアンカー）
```

- VS Code では、markdownlint の拡張（`.vscode/extensions.json` の推奨）が、書いている間に同じ設定で指摘する

### Claude Code を使う

1. 手元のリポジトリで `claude` を起動する。開発フローは `CLAUDE.md` とスキル（`.claude/skills/`）に書いてある
2. 作業は Issue ごとの worktree（`.worktrees/issues-<番号>`）で行う。メインの作業ツリーは `main` のままにする
   - worktree を作ったら、その中で `npm ci --ignore-scripts` を動かす（`node_modules/` は worktree ごと）。使い終わった worktree は `git worktree remove` で消す
   - メインの作業ツリーでのブランチの切り替えと `git stash` は、`.claude/settings.json` のフックが止める（Claude Code が動かすコマンドだけ。人がターミナルで打つものは止まらない）。設定を変えたあとは、Claude Code を起動し直すか `/hooks` を開くと読み込まれる
   - フックは `python3` で動く（macOS に入っているもので足りる。ほかのパッケージは使わない）
