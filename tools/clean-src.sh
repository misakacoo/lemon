#!/bin/bash
# 清理 src/ 下的解压残留与下载缓存
#
#   bash tools/clean-src.sh             只清解压出来的源码目录（tar 包保留，重装/升级可直接复用）
#   bash tools/clean-src.sh --tarballs  连 tar 包一起清（磁盘紧张时用，下次安装会重新下载）
#
# src/ 里有两类东西：
#   - <组件>.tar.gz  下载缓存，一次安装可能占几个 G，清掉后重装要重新下载
#   - <组件>/        解压出来的源码树，编译完就没用了（openssl 解压后接近 2G）
set -u
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1

src=./src
[ -d "$src" ] || { echo "没有 $src 目录，无需清理"; exit 0; }

before=$(du -sm "$src" 2>/dev/null | cut -f1)
shopt -s nullglob

n=0
for d in "$src"/*/; do
  rm -rf "$d" && n=$((n+1))
done
echo "已清理解压目录：${n} 个"

if [ "${1:-}" = "--tarballs" ]; then
  m=0
  for f in "$src"/*; do
    [ -f "$f" ] || continue
    rm -f "$f" && m=$((m+1))
  done
  echo "已清理下载缓存：${m} 个文件"
fi

after=$(du -sm "$src" 2>/dev/null | cut -f1)
echo "src 占用：${before}M → ${after}M"
