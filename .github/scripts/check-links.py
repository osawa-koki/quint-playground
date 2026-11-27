#!/usr/bin/env python3
"""リポジトリの中の Markdown のリンク（ほかのファイル・見出しのアンカー）が切れていないかを確かめる。

    python3 .github/scripts/check-links.py [<ファイルかディレクトリ> ...]   # 既定はリポジトリ全体

- 外へのリンク（http・https・mailto）は確かめない（ネットワークを使わない）
- アンカー（#...）は、GitHub が見出しから作るものと同じ決まりで作って比べる：
  小文字にし、英数字（日本語などの文字を含む）・空白・`-`・`_` 以外を消し、空白を `-` にする。同じ見出しは `-1`・`-2` を付ける
- コードの塊（``` の中）とインラインのコード（`...`）の中のリンクは見ない
- 標準のライブラリだけを使う（GitHub のランナーでも手元の Mac でも動くように）
"""

import pathlib
import re
import sys
import unicodedata
from urllib.parse import unquote

ROOT = pathlib.Path(__file__).resolve().parents[2]
SKIP_DIRS = {".git", ".worktrees", "node_modules"}
LINK = re.compile(r"!?\[(?:[^\[\]]|\[[^\]]*\])*\]\(\s*<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\s*\)")
HEADING = re.compile(r"^ {0,3}(#{1,6})\s+(.*?)\s*#*\s*$")
FENCE = re.compile(r"^ {0,3}(`{3,}|~{3,})")


def markdown_files(args):
    targets = [pathlib.Path(a).resolve() for a in args] or [ROOT]
    for t in targets:
        if t.is_file():
            yield t
            continue
        for p in sorted(t.rglob("*.md")):
            if not SKIP_DIRS & set(p.relative_to(ROOT).parts):
                yield p


def body_lines(text):
    """コードの塊の外の行を、行番号と一緒に返す。"""
    fence = None
    for no, line in enumerate(text.split("\n"), 1):
        m = FENCE.match(line)
        if m:
            mark = m.group(1)
            if fence is None:
                fence = mark
            elif mark[0] == fence[0] and len(mark) >= len(fence):
                fence = None
            continue
        if fence is None:
            yield no, line


def slug(heading):
    text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", heading)  # リンクは表示の文字だけにする
    text = re.sub(r"<[^>]+>", "", text).replace("`", "").lower()  # HTML のタグ・コードの印を消す
    kept = "".join(c for c in text if c in " -_" or unicodedata.category(c)[0] in "LNM")  # 文字・数字・空白・-・_ だけを残す
    return kept.replace(" ", "-")


_anchors = {}


def anchors(path):
    if path not in _anchors:
        seen, result = {}, set()
        for _, line in body_lines(path.read_text(encoding="utf-8")):
            m = HEADING.match(line)
            if not m:
                continue
            s = slug(m.group(2))
            n = seen.get(s, 0)
            seen[s] = n + 1
            result.add(s if n == 0 else f"{s}-{n}")
        _anchors[path] = result
    return _anchors[path]


def check(path):
    errors = []
    for no, line in body_lines(path.read_text(encoding="utf-8")):
        line = re.sub(r"(`+).*?\1", "", line)  # インラインのコードの中は見ない
        for m in LINK.finditer(line):
            target = m.group(1)
            if re.match(r"^[a-z][a-z0-9+.-]*:", target, re.I):
                continue  # http:・https:・mailto: など、外へのリンク
            file_part, _, anchor = target.partition("#")
            dest = (path.parent / unquote(file_part)).resolve() if file_part else path
            where = f"{path.relative_to(ROOT)}:{no}"
            if not dest.exists():
                errors.append(f"{where}: ファイルがない：{target}")
                continue
            if anchor and dest.suffix == ".md" and unquote(anchor) not in anchors(dest):
                errors.append(f"{where}: 見出しがない：{target}")
    return errors


def main():
    files = list(markdown_files(sys.argv[1:]))
    errors = [e for f in files for e in check(f)]
    for e in errors:
        print(e)
    print(f"{len(files)} ファイルを確かめた。切れたリンク：{len(errors)} 件")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
