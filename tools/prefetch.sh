#!/bin/bash
# prefetch.sh —— 安装前并行预下载所有源包
#
# 背景：install.sh 的下载阶段是逐个串行的，几十个文件加起来占 5-10 分钟，
# 而这段时间 CPU 几乎全闲。Download_src 本身会跳过已存在的文件，
# 所以这里先把包并行拉到 src/，后续安装时全部命中缓存、秒过下载阶段。
#
# 代价：会把所有版本（含不用的数据库版本）都拉一遍，多占几 GB 磁盘。
# 用 --only-needed 可只拉当前 options.conf 里装过的组件（不推荐，容易漏）。

set -u
cd "$(dirname "$0")" || exit 1
lemon_dir=$(pwd)
JOBS=${JOBS:-8}

set -a
. ./options.conf 2>/dev/null || true
. ./versions.txt 2>/dev/null || true
# 这三个在 check_os.sh 里按机器架构算，x86_64 下固定为下面三值
SYS_ARCH=amd64
SYS_ARCH_i=x86-64
SYS_ARCH_n=x64
set +a

urls=/tmp/lemon-prefetch-urls.txt
grep -hoE '\$\{mirror_link\}/src/[^ "]+' include/check_download.sh 2>/dev/null \
  | sort -u | envsubst \
  | grep -E '\.(tar\.gz|tar\.xz|tgz|tar\.bz2|zip|patch|jar)$' \
  | grep -v '\${' > "$urls"

total=$(wc -l < "$urls")
[ "$total" -eq 0 ] && { echo "没提取到下载地址，检查 include/check_download.sh"; exit 1; }
echo "待处理 $total 个源包，并发 $JOBS"

mkdir -p "${lemon_dir}/src"
cd "${lemon_dir}/src" || exit 1

download_one() {
  url=$1
  f=$(basename "$url")
  [ -s "$f" ] && return 0
  # 先写 .part 再改名，避免中断留下半截文件被当成已完成
  if curl -sL --max-time 600 --retry 2 -o "$f.part" "$url"; then
    mv "$f.part" "$f"
  else
    rm -f "$f.part"
    echo "  失败: $f"
  fi
}
export -f download_one

cat "$urls" | xargs -P "$JOBS" -I{} bash -c 'download_one "$@"' _ {}

done_cnt=$(find . -maxdepth 1 -type f | wc -l)
echo "预下载结束，src/ 现有 $done_cnt 个文件"
