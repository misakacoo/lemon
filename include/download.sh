#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Download_src() {
  # src 目录由分发方式决定存在与否（打包排除、手工解包都可能丢），
  # 这里兜底创建，避免下载落到 ${lemon_dir} 根目录把后续解包全部带歪
  [ -d "${lemon_dir}/src" ] || mkdir -p ${lemon_dir}/src
  [ -s "${src_url##*/}" ] && echo "[${CMSG}${src_url##*/}${CEND}] found" || { wget --limit-rate=100M --tries=6 -c ${src_url}; }
  if [ ! -e "${src_url##*/}" ]; then
    echo "${CFAILURE}Auto download failed! You can manually download ${src_url} into the ${lemon_dir}/src directory.${CEND}"
    # 传 no_kill 时只返回 1 不终止整个脚本，交给调用方自行处理
    [ "${1}" == 'no_kill' ] && return 1
    exit 1
  fi
}

# 与 Download_src 相同，但取不到时返回非 0 而不退出，交给调用方换源重试
Download_src_soft() {
  [ -s "${src_url##*/}" ] && { echo "[${CMSG}${src_url##*/}${CEND}] found"; return 0; }
  wget -q --limit-rate=100M --tries=2 -c ${src_url} > /dev/null 2>&1
  # 404 时 wget 可能留下 0 字节文件，先清掉，否则下一次会被误判为已下载
  [ -f "${src_url##*/}" ] && [ ! -s "${src_url##*/}" ] && rm -f "${src_url##*/}"
  [ -s "${src_url##*/}" ] && { echo "[${CMSG}${src_url##*/}${CEND}] downloaded"; return 0; }
  return 1
}

# PHP 源码：镜像站同步安全补丁有延迟（补丁版常常几天后才收录），
# 取不到时回退官方源。参数为版本号，如 8.5.12。
Download_PHP_src() {
  src_url=${mirror_link}/src/php-${1}.tar.gz
  Download_src_soft && return 0
  echo "${CFAILURE}php-${1} 不在镜像站上。${CEND}"
  echo "${CFAILURE}可执行 scripts/build-mirror.py 更新镜像，或手动下载后放到 ${lemon_dir}/src/。${CEND}"
  exit 1
}
