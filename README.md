# quint-playground

🔁🔁🔁 Quint で仕様を書いてテストしながら学ぶリポジトリ！

[Quint](https://quint-lang.org/) は、Informal Systems が作っている仕様記述言語。TLA+ と同じ考え方（状態と遷移で系を書き、性質を確かめる）を、プログラミング言語に近い書き方でできる。このリポジトリでは、段階ごとに小さな仕様を書き、テスト（`quint test`）・ランダムなシミュレーション（`quint run`）・モデル検査（`quint verify`）で確かめながら、Quint の書き方と考え方を身につける。

## 全体の流れ

```text
手元の Mac（VS Code ＋ Claude Code ＋ quint）
 │  仕様（.qnt）とテストを書く
 │  quint typecheck / test / run / verify で確かめる
 │  git push
 ▼
GitHub（osawa-koki/quint-playground）
    Issue と PR・CI（GitHub Actions）
```

## 構成

| ディレクトリ・ファイル | 役割 |
|---|---|
| `.vscode/` | VS Code の推奨の拡張（EditorConfig・markdownlint・Quint） |
| `.editorconfig` | インデント・改行などのそろえ方 |
| `.markdownlint-cli2.jsonc` | markdownlint の設定 |
| `.github/` | GitHub Actions のワークフロー（`workflows/`。ラベルの同期）・ワークフローが使うスクリプト（`scripts/`）と、ラベル・マイルストーンの定義（`custom-data/label.json`・`milestone.json`。main にマージされると、`scripts/sync-labels-milestones.sh` が GitHub に反映する） |
| `.claude/` | Claude Code のスキル（Issue・PR の作り方・マージ前の確認）と、メインの作業ツリーでブランチを切り替えさせないフック |
| `CLAUDE.md` | 開発の約束ごと（絶対に守ること・開発フロー・決めたこと） |

## 進み具合

- [x] リポジトリの土台（CLAUDE.md・README・エディタ設定・ラベルとマイルストーン・Claude Code のフックと開発フローのスキル）
- [ ] CI（Markdown の lint・リンクの確認・`quint typecheck`・`quint test`）と、Quint の版の固定
- [ ] 01. 基本の文法とテスト：型・演算子・集合・マップ・リスト・レコード・`pure def` と、`run` によるテスト・REPL
- [ ] 02. 状態と遷移：`var`・`action`・`init` と `step`・`nondet`・`any` と `all`
- [ ] 03. 不変条件とシミュレーション：不変条件・`quint run`・反例のトレースの読み方
- [ ] 04. モデル検査：Apalache を使った `quint verify`・時相の性質
- [ ] 05. 題材の仕様：相互排除・2 フェーズコミット・合意のプロトコルなど

01〜05 は、それぞれ GitHub のマイルストーンになっている（`.github/custom-data/milestone.json`）。

## セットアップ

### Claude Code を使う

1. 手元のリポジトリで `claude` を起動する。開発フローは `CLAUDE.md` とスキル（`.claude/skills/`）に書いてある
2. 作業は Issue ごとの worktree（`.worktrees/issues-<番号>`）で行う。メインの作業ツリーは `main` のままにする
   - メインの作業ツリーでのブランチの切り替えと `git stash` は、`.claude/settings.json` のフックが止める（Claude Code が動かすコマンドだけ。人がターミナルで打つものは止まらない）。設定を変えたあとは、Claude Code を起動し直すか `/hooks` を開くと読み込まれる
   - フックは `python3` で動く（macOS に入っているもので足りる。ほかのパッケージは使わない）

### Markdown を手元で確かめる

コミットの前に、markdownlint を手元で動かす（Node.js が要る。Homebrew などで入れたもの）：

```sh
npx -y markdownlint-cli2@0.24.2   # 設定は .markdownlint-cli2.jsonc
```

- VS Code では、markdownlint の拡張（`.vscode/extensions.json` の推奨）が、書いている間に同じ設定で指摘する
