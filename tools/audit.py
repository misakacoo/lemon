#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Lemon 三仓一致性自检。

用法：
    python3 tools/audit.py                # 自动找 ../Lemon-Shell 与 ../Lemon-Mirror
    python3 tools/audit.py --shell DIR --mirror DIR

检查的都是「改一处、忘另一处」会导致真机失败的地方：
  1. install.sh 的 getopt 选项 与 --help 文本是否一一对应
  2. include/*.sh 引用的版本变量（形如 xxx_ver）是否都在 versions.txt 里
  3. Lemon 下载的每个 /src/文件 是否都能在 Mirror 的映射表或 public/src 里找到
  4. Lemon-Shell 生成的参数是否都被 install.sh 接受
  5. 所有 .sh 是否有可执行位
  6. Shell 的默认 PHP 版本是否与 install.sh 的菜单默认一致

退出码：有 FAIL 返回 1，只有 WARN 返回 0。
"""
import argparse
import os
import re
import sys

FAILS = []
WARNS = []


def ok(msg):
    print("  OK   " + msg)


def fail(msg):
    print("  FAIL " + msg)
    FAILS.append(msg)


def warn(msg):
    print("  WARN " + msg)
    WARNS.append(msg)


def read(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read()


def find_repo(start, name):
    cur = os.path.abspath(start)
    for _ in range(4):
        cand = os.path.join(os.path.dirname(cur), name)
        if os.path.isdir(cand):
            return cand
        cur = os.path.dirname(cur)
    return None


def check_help_options(lemon):
    print("[1] install.sh getopt 与 --help 文本")
    src = read(os.path.join(lemon, "install.sh"))
    m = re.search(r"getopt -o [^ ]+ --long ([^ ]+)", src)
    if not m:
        fail("install.sh 里找不到 getopt --long 列表")
        return
    longs = [o.strip().rstrip(":") for o in m.group(1).split(",") if o.strip()]
    h0 = src.find("Show_Help() {")
    h1 = src.find("\n}", h0)
    help_txt = src[h0:h1] if h0 >= 0 and h1 > h0 else src
    missing = [o for o in longs if ("--" + o) not in help_txt]
    if missing:
        fail("--help 没写这些选项：" + ", ".join(missing))
    else:
        ok("%d 个长选项全部在 --help 里有说明" % len(longs))


def check_versions(lemon):
    print("[2] include/*.sh 用到的版本变量是否都在 versions.txt")
    vtxt = read(os.path.join(lemon, "versions.txt"))
    defined = set(re.findall(r"^([A-Za-z0-9_]+)=", vtxt, re.M))
    used = set()
    inc = os.path.join(lemon, "include")
    for fn in sorted(os.listdir(inc)):
        if not fn.endswith(".sh"):
            continue
        body = read(os.path.join(inc, fn))
        # 允许 ${var} 与 ${var:-default} 两种写法
        for name in re.findall(r"\$\{([a-z0-9_]+_ver)(?::-[^}]*)?\}", body):
            used.add(name)
    assigned = set()
    for root, _, names in os.walk(lemon):
        if ".git" in root or "tools" in root.split(os.sep)[-1:]:
            pass
        for n in names:
            if not n.endswith(".sh"):
                continue
            body = read(os.path.join(root, n))
            assigned |= set(re.findall(r"(?:^|[\s;])([a-z0-9_]+)=", body, re.M))
            assigned |= set(re.findall(r"for ([a-z0-9_]+) in", body))
    missing = sorted(u for u in used if u not in defined and u not in assigned)
    if missing:
        fail("这些版本变量没有定义：" + ", ".join(missing))
    else:
        ok("%d 个版本变量都在 versions.txt 里" % len(used))
    unused = sorted(d for d in defined if d.endswith("_ver") and d not in used)
    if unused:
        warn("versions.txt 里有没人用的变量：" + ", ".join(unused))


def resolve_filename(raw, versions):
    name = raw.split("/")[-1]
    for _ in range(3):
        m = re.search(r"\$\{([A-Za-z0-9_]+)\}", name)
        if not m:
            break
        key = m.group(1)
        if key not in versions:
            return None
        name = name.replace(m.group(0), versions[key])
    return None if "$" in name else name


def check_mirror(lemon, mirror):
    print("[3] Lemon 下载的文件是否都能在 Mirror 里找到")
    if not mirror:
        warn("没找到 Lemon-Mirror，跳过")
        return
    versions = dict(re.findall(r"^([A-Za-z0-9_]+)=(.*)$", read(os.path.join(lemon, "versions.txt")), re.M))
    files = set()
    for fn in ["install.sh"] + ["include/" + f for f in os.listdir(os.path.join(lemon, "include"))]:
        if not fn.endswith(".sh"):
            continue
        body = read(os.path.join(lemon, fn))
        for line in body.splitlines():
            if "/src/" not in line or "lemon_dir" in line:
                continue
            for raw in re.findall(r"/src/([^\"' \n)]+)", line):
                files.add(raw)
    map_txt = read(os.path.join(mirror, "functions", "src", "[[path]].js"))
    mapped = set(re.findall(r'^\s{2}"([^"]+)":', map_txt, re.M))
    src_dir = os.path.join(mirror, "public", "src")
    hosted = set(os.listdir(src_dir)) if os.path.isdir(src_dir) else set()
    resolved, dynamic, missing = 0, 0, []
    for raw in files:
        name = resolve_filename(raw, versions)
        if name is None:
            dynamic += 1
            continue
        if name in mapped or name in hosted:
            resolved += 1
        else:
            missing.append(name)
    if missing:
        fail("镜像里没有这些文件：" + ", ".join(sorted(set(missing))[:10]))
    else:
        ok("可解析的 %d 个文件全部有映射（另有 %d 个依赖运行时变量，跳过）" % (resolved, dynamic))


def check_shell_args(lemon, shell):
    print("[4] Lemon-Shell 生成的参数是否都被 install.sh 接受")
    if not shell:
        warn("没找到 Lemon-Shell，跳过")
        return
    src = read(os.path.join(lemon, "install.sh"))
    m = re.search(r"getopt -o [^ ]+ --long ([^ ]+)", src)
    longs = set(o.strip().rstrip(":") for o in m.group(1).split(",") if o.strip()) if m else set()
    js = read(os.path.join(shell, "public", "assets", "app.js"))
    used = set(re.findall(r"'(--[a-z_]+)", js))
    bad = sorted(u for u in used if u.lstrip("-") not in longs)
    if bad:
        fail("Shell 会生成但 install.sh 不认识的参数：" + ", ".join(bad))
    else:
        ok("%d 个参数两边一致" % len(used))


def check_exec(lemon):
    print("[5] .sh 可执行位")
    bad = []
    for root, _, names in os.walk(lemon):
        if ".git" in root:
            continue
        for n in names:
            if n.endswith(".sh"):
                p = os.path.join(root, n)
                if not os.access(p, os.X_OK):
                    bad.append(os.path.relpath(p, lemon))
    if bad:
        fail("缺可执行位：" + ", ".join(bad))
    else:
        ok("全部 .sh 都有可执行位")


def check_defaults(lemon, shell):
    print("[6] Shell 默认 PHP 版本 vs install.sh 菜单默认")
    if not shell:
        warn("没找到 Lemon-Shell，跳过")
        return
    js = read(os.path.join(shell, "public", "assets", "app.js"))
    m = re.search(r"var PHP_DEFAULT_OPT\s*=\s*(\d+)", js)
    if not m:
        warn("Shell 里没找到 PHP_DEFAULT_OPT")
        return
    src = read(os.path.join(lemon, "install.sh"))
    m2 = re.search(r'Default (\d+) press Enter\) " php_option[\s\S]{0,80}?php_option=\$\{php_option:-(\d+)\}', src)
    if not m2:
        warn("install.sh 里没找到 PHP 菜单默认值")
        return
    if m.group(1) != m2.group(2):
        fail("Shell 默认 php_option=%s，install.sh 菜单默认 %s，两边不一致" % (m.group(1), m2.group(2)))
    else:
        ok("默认 PHP 编号一致：%s（菜单提示 Default %s）" % (m.group(1), m2.group(1)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--lemon", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--shell", default=None)
    ap.add_argument("--mirror", default=None)
    a = ap.parse_args()
    lemon = os.path.abspath(a.lemon)
    shell = a.shell or find_repo(lemon, "Lemon-Shell")
    mirror = a.mirror or find_repo(lemon, "Lemon-Mirror")

    print("lemon  = " + lemon)
    print("shell  = " + str(shell))
    print("mirror = " + str(mirror))
    print()
    check_help_options(lemon)
    check_versions(lemon)
    check_mirror(lemon, mirror)
    check_shell_args(lemon, shell)
    check_exec(lemon)
    check_defaults(lemon, shell)
    print()
    print("FAIL: %d   WARN: %d" % (len(FAILS), len(WARNS)))
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
