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
  local _f="${src_url##*/}"

  # 已有文件先校验：可能是上次中断留下的半截文件，直接解包会得到奇怪错误
  if [ -s "${_f}" ] && ! Check_file_sum "${_f}"; then
    echo "${CWARNING}${_f} 校验不通过，删除后重新下载${CEND}"
    rm -f "${_f}"
  fi

  [ -s "${_f}" ] && echo "[${CMSG}${_f}${CEND}] found" || {
    # 优先走 IPv4：不少 VPS 的 IPv6 到 downloads.percona.com 这类 CDN 是黑洞，
    # wget 会先试 AAAA，重试全耗在 Connection timed out 上
    wget -4 --limit-rate=100M --tries=3 --timeout=20 -c ${src_url} || \
      wget --limit-rate=100M --tries=3 --timeout=20 -c ${src_url}
  }

  # 下载成功不等于内容可信：镜像站是第三方静态站，被改/被劫时照样返回 200。
  if [ -s "${_f}" ] && ! Check_file_sum "${_f}"; then
    rm -f "${_f}"
    echo "${CFAILURE}${_f} 的 sha256 与 checksums.txt 不一致，已删除（镜像可能被篡改）${CEND}"
    [ "${1}" == 'no_kill' ] && return 1
    exit 1
  fi

  if [ ! -e "${src_url##*/}" ]; then
    echo "${CFAILURE}Auto download failed! You can manually download ${src_url} into the ${lemon_dir}/src directory.${CEND}"
    [ "${1}" == 'no_kill' ] && return 1
    exit 1
  fi
}

# 校验文件是否与 checksums.txt 里的 sha256 一致。
#   - 清单里没有该文件：默认只告警（新版本还没补清单时不至于装不了）；LEMON_STRICT_CHECKSUM=1 视为失败
#   - 清单里有但内容不符：一律失败（这才是真正要防的篡改）
#   - LEMON_SKIP_CHECKSUM=1 可整体跳过（应急用，不建议）
Check_file_sum() {
  local _file="$1" _expect _got
  [ "${LEMON_SKIP_CHECKSUM}" == '1' ] && return 0
  [ -f "${lemon_dir}/checksums.txt" ] || return 0
  _expect=$(awk -v n="${_file}" '$2 == n {print $1; exit}' "${lemon_dir}/checksums.txt" 2>/dev/null)
  if [ -z "${_expect}" ]; then
    echo "${CWARNING}${_file} 不在 checksums.txt 里，跳过完整性校验${CEND}"
    [ "${LEMON_STRICT_CHECKSUM}" == '1' ] && return 1
    return 0
  fi
  _got=$(sha256sum "${_file}" 2>/dev/null | awk '{print $1}')
  [ "${_got}" == "${_expect}" ] && return 0
  echo "${CFAILURE}${_file} sha256 不匹配：期望 ${_expect}，实际 ${_got}${CEND}"
  return 1
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
