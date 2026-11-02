#!/bin/bash
# 生成 checksums.txt：把 Lemon 会下载的每个包取一遍并算 sha256。
#
#   bash tools/gen-checksums.sh            # 缺什么下什么（src/ 与缓存里已有的不重复下）
#   bash tools/gen-checksums.sh --refresh  # 强制重新下载并重算
#
# 输出写到仓库根目录的 checksums.txt，格式与 sha256sum -c 兼容：<sha256>  <文件名>
#
# 什么时候要重跑：versions.txt 里任何 *_ver 变了（新增/升级版本）之后。
# 没收录的文件安装时只告警（LEMON_STRICT_CHECKSUM=1 则视为失败）；
# 但**清单里有的文件内容不符一律失败** —— 那才是镜像被篡改的信号。
set -u
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
[ -f ./versions.txt ] || { echo "找不到 versions.txt，请在 Lemon 仓库根目录运行"; exit 1; }

REFRESH=0
[ "${1:-}" == "--refresh" ] && REFRESH=1

. ./versions.txt
[ -f ./options.conf ] && . ./options.conf
mirror_link=${mirror_link:-https://lemon-mirror.pages.dev}

mkdir -p src .checksum-cache
OUT=checksums.txt
: > "${OUT}.tmp"

grep -rhoE 'src_url=[^ ]+' install.sh include/*.sh 2>/dev/null \
  | sed 's/^src_url=//' | sort -u > .checksum-cache/urls.txt

n=0; ok=0; skip=0
while read -r raw; do
  n=$((n+1))
  url=$(eval echo "${raw}" 2>/dev/null)
  case "${url}" in
    http*) ;;
    *) skip=$((skip+1)); echo "  [skip] 变量没能展开：${raw}" >&2; continue ;;
  esac
  case "${url}" in *'$'*) skip=$((skip+1)); echo "  [skip] 仍有未展开变量：${url}" >&2; continue ;; esac
  f=$(basename "${url}")
  case "${f}" in *'*'*) skip=$((skip+1)); echo "  [skip] 文件名含通配：${f}" >&2; continue ;; esac

  path=""
  [ "${REFRESH}" -eq 0 ] && [ -s "src/${f}" ] && path="src/${f}"
  [ -z "${path}" ] && [ -s ".checksum-cache/${f}" ] && path=".checksum-cache/${f}"
  if [ -z "${path}" ]; then
    if ! wget -4 -q --tries=2 --timeout=30 -O ".checksum-cache/${f}.part" "${url}"; then
      rm -f ".checksum-cache/${f}.part"
      skip=$((skip+1)); echo "  [skip] 下载失败：${f}" >&2; continue
    fi
    mv ".checksum-cache/${f}.part" ".checksum-cache/${f}"
    path=".checksum-cache/${f}"
  fi

  echo "$(sha256sum "${path}" | awk '{print $1}')  ${f}" >> "${OUT}.tmp"
  ok=$((ok+1))
done < .checksum-cache/urls.txt

sort -u -k2 "${OUT}.tmp" -o "${OUT}"
rm -f "${OUT}.tmp"
echo "已写入 ${OUT}：$(wc -l < "${OUT}") 条（候选 ${n}，成功 ${ok}，跳过 ${skip}）"
echo "提醒：这是当前各版本的快照，versions.txt 改动后请重跑本脚本。"
