# PreToolUse（Bash）のフック。メインの作業ツリーでの git switch・git checkout・gh pr checkout と、どこでもの git stash を、終了コード 2 で止める。
import json
import os
import re
import shlex
import subprocess
import sys

SEPARATORS = {"&&", "||", ";", ";;", "|", "|&", "&"}  # 次のコマンドに移る記号（cd の効き目は && ; でそのまま続くとみなす）
WRAPPERS = {"env", "command", "exec", "time", "nohup", "sudo", "nice"}  # 後ろに本当のコマンドが続くもの
UNKNOWN = None  # 動く場所がわからない（変数・cd - など）ことを表す


def main_root():
    here = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))  # このスクリプトがある作業ツリーの根
    try:
        common = subprocess.run(["git", "-C", here, "rev-parse", "--path-format=absolute", "--git-common-dir"],
                                capture_output=True, text=True, timeout=5, check=True).stdout.strip()  # どの worktree からでも、メインの .git を指す
        return os.path.realpath(os.path.dirname(common))  # .git の親がメインの作業ツリー
    except Exception:
        return os.path.realpath(os.environ.get("CLAUDE_PROJECT_DIR") or here)  # git で調べられないときの代わり


def in_main_worktree(path, root):
    if path is UNKNOWN:
        return True  # 場所がわからないときは、安全側（止める）に倒す。止まったら -C に絶対パスを書けば通る
    p = os.path.realpath(path)
    if p != root and not p.startswith(root + os.sep):
        return False  # メインの作業ツリーの外（ほかのリポジトリなど）は対象にしない
    rel = os.path.relpath(p, root).split(os.sep)
    return not (len(rel) >= 2 and rel[0] == ".worktrees")  # .worktrees/<名前> の下だけ許す（.worktrees そのものはメインの中）


def join(base, target):
    if base is UNKNOWN or target is UNKNOWN or re.search(r"[$`*?]", target):
        return UNKNOWN  # 変数・コマンド置換・ワイルドカードは、展開しないとわからない
    target = os.path.expanduser(target)
    return os.path.normpath(os.path.join(base, target))  # 絶対パスなら base は無視される


def strip_heredocs(cmd):
    out, lines, i = [], cmd.split("\n"), 0
    while i < len(lines):
        out.append(lines[i])
        tags = re.findall(r"<<(-?)\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\2", lines[i])  # <<EOF・<<'EOF'・<<-EOF の終わりの印
        i += 1
        for dash, _, tag in tags:
            while i < len(lines) and (lines[i].strip() if dash else lines[i]) != tag:
                i += 1  # ヒアドキュメントの中身（コミットメッセージなど）は、コマンドとして読まない
            i += 1
    return "\n".join(out)


def tokenize(cmd):
    cmd = strip_heredocs(cmd).replace("\\\n", "")  # 行の終わりの \ で続く行をつなぐ
    lex = shlex.shlex(cmd.replace("\n", " ; "), posix=True, punctuation_chars=True)  # 改行はコマンドの区切り。引用符の中は 1 つの語になる
    lex.whitespace_split = True
    return list(lex)


def check(cmd, cwd, root, depth=0):
    try:
        tokens = tokenize(cmd)
    except ValueError:
        if re.search(r"\bgit\b[^\n]*\b(switch|checkout|stash)\b", cmd):
            return "コマンドを読み取れなかった（引用符の閉じ忘れなど）ため、git switch・checkout・stash が含まれるものを止めた"  # 読めないときは安全側
        return None
    dirs, here, seg = [], cwd, []
    for tok in tokens + [";"]:
        if tok == "(":
            dirs.append(here)  # サブシェルの中の cd は、閉じたら戻る
            continue
        if tok == ")":
            reason = run_segment(seg, here, root, depth)
            if reason:
                return reason
            seg, here = [], dirs.pop() if dirs else here
            continue
        if tok not in SEPARATORS:
            seg.append(tok)
            continue
        reason = run_segment(seg, here, root, depth)
        if reason:
            return reason
        if seg and seg[0] in ("cd", "pushd"):
            here = cd_target(seg, here)  # 続くコマンドは cd の先で動く
        seg = []
    return None


def cd_target(seg, here):
    args = [a for a in seg[1:] if a not in ("-L", "-P", "-e", "--")]
    if not args:
        return os.path.expanduser("~")  # cd だけはホームへ
    if args[0] == "-":
        return UNKNOWN  # cd - は前の場所で、ここではわからない
    return join(here, args[0])


def run_segment(seg, here, root, depth):
    unknown_env = False
    while seg and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", seg[0]):
        unknown_env |= seg[0].startswith(("GIT_DIR=", "GIT_WORK_TREE="))  # git の場所を環境変数で変えているときは、場所がわからない
        seg = seg[1:]
    while seg and seg[0] in WRAPPERS:
        seg = [a for a in seg[1:] if not a.startswith("-")] if seg[0] in ("env", "sudo", "nice") else seg[1:]  # env -i などの - の付く引数は飛ばす
        while seg and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", seg[0]):
            unknown_env |= seg[0].startswith(("GIT_DIR=", "GIT_WORK_TREE="))
            seg = seg[1:]
    if not seg:
        return None
    name = os.path.basename(seg[0])
    if name in ("bash", "sh", "zsh", "dash") and "-c" in seg[1:] and depth < 3:
        i = seg.index("-c")
        return check(seg[i + 1], here, root, depth + 1) if i + 1 < len(seg) else None  # bash -c "…" の中も同じように読む
    if name == "eval" and depth < 3:
        return check(" ".join(seg[1:]), here, root, depth + 1)
    if name == "gh":
        return check_gh(seg[1:], here, root)
    if name != "git":
        return None  # echo "git switch" のように、git が引数の文字列の中にあるだけのものは許す
    return check_git(seg[1:], UNKNOWN if unknown_env else here, root)


def check_git(args, here, root):
    i = 0
    while i < len(args):
        a = args[i]
        if a == "-C" and i + 1 < len(args):
            here, i = join(here, args[i + 1]), i + 2  # -C は重ねると、前の場所からの相対になる
        elif a in ("-c", "--config-env", "--namespace", "--exec-path") and i + 1 < len(args):
            i += 2  # 値を 1 つ取るオプション
        elif a in ("--git-dir", "--work-tree") or a.startswith(("--git-dir=", "--work-tree=")):
            here = UNKNOWN  # リポジトリの場所を直接変えているときは、どこで動くかわからない
            i += 2 if "=" not in a else 1
        elif a.startswith("-"):
            i += 1  # --no-pager などの値を取らないオプション
        else:
            break
    sub = args[i] if i < len(args) else ""
    if sub == "stash":
        return "git stash は、すべての worktree で共有されるので使わない（CLAUDE.md の開発フロー）。作業をよけるときは、途中のコミット（本文に Refs #<番号>）にする"
    if sub in ("switch", "checkout") and in_main_worktree(here, root):
        where = "わからない場所（変数・cd - など）" if here is UNKNOWN else os.path.realpath(here)
        return f"メインの作業ツリー（{root}）で git {sub} をしようとした（動く場所：{where}）。メインの作業ツリーは main のままにし、ブランチの切り替え・ファイルの戻しは .worktrees/issues-<番号> の中で行う（例：git -C {root}/.worktrees/issues-<番号> {sub} …）"
    return None


def check_gh(args, here, root):
    words = [a for a in args if not a.startswith("-")]
    switches = words[:2] == ["pr", "checkout"] or (words[:2] == ["issue", "develop"] and ({"--checkout", "-c"} & set(args)))  # gh もブランチを切り替えるもの
    if switches and in_main_worktree(here, root):
        return f"メインの作業ツリー（{root}）で、ブランチを切り替える gh {' '.join(words[:2])} をしようとした。ブランチは gh issue develop（--checkout なし）で作り、git worktree add で .worktrees/issues-<番号> に取り出して、その中で作業する"
    return None


def run():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0  # 入力が読めないときは、ほかのツールを止めないよう通す
    if data.get("tool_name") != "Bash":
        return 0
    cmd = (data.get("tool_input") or {}).get("command") or ""
    cwd = data.get("cwd") or os.getcwd()
    reason = check(cmd, cwd, main_root())
    if reason:
        print(f"[guard-main-worktree] {reason}", file=sys.stderr)  # 終了コード 2 のとき、stderr が Claude に返る
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(run())
