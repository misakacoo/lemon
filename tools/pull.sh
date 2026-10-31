#!/bin/bash
# Lemon 仓库拉取助手
#
# 为什么需要它：options.conf 记录的是「这台机器实际装了什么」（含数据库密码），
# 而 install.sh / backup_setup.sh / uninstall.sh 运行时会改写它。于是它长期处于
# 「本地已修改」状态，直接 git pull 会被挡：
#     error: Your local changes to the following files would be overwritten by merge: options.conf
# 更糟的是有人用 git checkout -- options.conf 清掉改动，密码跟着被清空，
# 备份脚本随后连不上数据库，表现成「备份坏了」。
#
# 这个脚本的做法：只 stash options.conf → pull → 再 pop 回来。

set -u
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1

if [ ! -d .git ]; then
  echo "[!] 当前目录不是 git 仓库：$(pwd)"
  exit 1
fi

changed=$(git status --porcelain -- options.conf 2>/dev/null)
if [ -n "${changed}" ]; then
  echo "[*] options.conf 有本地改动，先 stash 起来"
  git stash push -m "lemon: options.conf before pull $(date +%F_%T)" -- options.conf || exit 1
  stashed=1
else
  stashed=0
fi

echo "[*] git pull --ff-only"
if ! git pull --ff-only; then
  echo "[!] 拉取失败（本地有其它改动，或远端历史被改写）"
  if [ "${stashed}" = "1" ]; then
    echo "[*] 把 options.conf 恢复回去"
    git stash pop || true
  fi
  exit 1
fi

if [ "${stashed}" = "1" ]; then
  echo "[*] 恢复本机的 options.conf"
  if ! git stash pop; then
    echo "[!] stash pop 冲突了：options.conf 在远端也变了"
    echo "    用 git stash show -p 看差异，手工合并后 git stash drop"
    exit 1
  fi
fi

echo "[+] 完成，当前版本：$(git log --oneline -1)"
