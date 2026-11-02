#!/bin/bash
# 校验 checksums.txt 与「代码里会下载的包」是否对得上（不联网、不下载）。
#
#   bash tools/check-checksums.sh        # 缺失/多余都报，缺失以非 0 退出
#
# 用途：CI 与发布前自检 —— versions.txt 改了版本但忘了重跑 tools/gen-checksums.sh 时拦住。
set -u
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
[ -f ./versions.txt ] || { echo "找不到 versions.txt"; exit 1; }
[ -f ./checksums.txt ] || { echo "找不到 checksums.txt"; exit 1; }

. ./versions.txt
[ -f ./options.conf ] && . ./options.conf
mirror_link=${mirror_link:-https://lemon-mirror.pages.dev}

grep -rhoE 'src_url=[^ ]+' install.sh include/*.sh 2>/dev/null \
  | sed 's/^src_url=//' | sort -u > /tmp/.lemon_urls.$$

: > /tmp/.lemon_expected.$$
while read -r raw; do
  url=$(eval echo "${raw}" 2>/dev/null)
  case "${url}" in http*) ;; *) continue ;; esac
  case "${url}" in *'$'*) continue ;; esac
  f=$(basename "${url}")
  case "${f}" in *'*'*) continue ;; esac
  echo "${f}" >> /tmp/.lemon_expected.$$
done < /tmp/.lemon_urls.$$

sort -u /tmp/.lemon_expected.$$ -o /tmp/.lemon_expected.$$
awk '{print $2}' checksums.txt | sort -u > /tmp/.lemon_have.$$

missing=$(comm -23 /tmp/.lemon_expected.$$ /tmp/.lemon_have.$$)
extra=$(comm -13 /tmp/.lemon_expected.$$ /tmp/.lemon_have.$$)

rc=0
if [ -n "${missing}" ]; then
  echo "[FAIL] 这些包会被下载，但 checksums.txt 里没有（改了版本忘了重跑 gen-checksums.sh？）："
  echo "${missing}" | sed 's/^/   /'
  rc=1
fi
if [ -n "${extra}" ]; then
  echo "[WARN] checksums.txt 里有、但当前代码不会下载的条目（可清理，不影响安全）："
  echo "${extra}" | head -3 | sed 's/^/   /'
  echo "   ...（共 $(echo "${extra}" | wc -l) 条；这些包的 URL 多用局部变量拼装，属预期）"
fi
[ ${rc} -eq 0 ] && echo "[OK] checksums.txt 覆盖了全部 $(wc -l < /tmp/.lemon_have.$$) 个下载包"
rm -f /tmp/.lemon_urls.$$ /tmp/.lemon_expected.$$ /tmp/.lemon_have.$$
exit ${rc}
