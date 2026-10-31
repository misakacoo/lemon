#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

if [ -e "/etc/os-release" ]; then
  . /etc/os-release
else
  echo "${CFAILURE}/etc/os-release does not exist! ${CEND}"
  exit 1;
fi

# Get OS Version
Platform=${ID,,}
VERSION_MAIN_ID=${VERSION_ID%%.*}
ARCH=$(arch)

if [ "${Platform}" != 'debian' ]; then
  echo "${CFAILURE}Lemon only supports Debian 12 / 13, current system: ${PRETTY_NAME:-${Platform} ${VERSION_ID}} ${CEND}"
  exit 1;
fi

Debian_ver=${VERSION_MAIN_ID}
case "${Debian_ver}" in
  12|13)
    ;;
  *)
    echo "${CFAILURE}Lemon only supports Debian 12 / 13, current system: ${PRETTY_NAME} ${CEND}"
    exit 1;
    ;;
esac

# 最小化系统上 apt 索引可能是空的，先更新再装
if ! command -v gcc > /dev/null 2>&1; then
  apt-get -y update > /dev/null 2>&1
  apt-get -y install gcc
fi
gcc_ver=$(gcc -dumpversion 2>/dev/null | awk -F. '{print $1}')
gcc_ver=${gcc_ver:-0}

# 仅支持 x86_64（AMD64）。组件二进制包、预编译工具（ois/ossutil/upx 等）
# 与测试矩阵都只覆盖 x86_64，其他架构直接拒绝，不做降级或源码编译兜底
if [ "$(uname -m)" != 'x86_64' ]; then
  echo "${CFAILURE}Lemon only supports x86_64 (AMD64), current arch: $(uname -m) ${CEND}"
  exit 1;
fi

# 下载包名里的架构段，固定为 x86_64 对应值
SYS_ARCH=amd64      # openjdk
SYS_ARCH_i=x86-64   # ioncube
SYS_ARCH_n=x64      # nodejs

if [ "$(uname -r | awk -F- '{print $3}' 2>/dev/null)" == "Microsoft" ]; then
  Wsl=true
fi

# 编译并发：先看核数，再按内存封顶（每 512M 一个并发）。
# 原来用 grep processor | sort -u | wc -l，/proc/cpuinfo 里没有 processor 字段时
# 会算出 0，make -j0 等于无限并发，直接把小机器打爆。
THREAD=$(nproc 2>/dev/null)
[ -z "${THREAD}" ] && THREAD=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)
[ -z "${THREAD}" ] && THREAD=1
mem_total_mb=$(awk '/^MemTotal:/ {print int($2/1024)}' /proc/meminfo 2>/dev/null)
if [ -n "${mem_total_mb}" ] && [ "${mem_total_mb}" -gt 0 ] 2>/dev/null; then
  mem_thread=$((mem_total_mb / 512))
  [ "${mem_thread}" -lt 1 ] && mem_thread=1
  [ "${mem_thread}" -lt "${THREAD}" ] && THREAD=${mem_thread}
fi
[ "${THREAD}" -lt 1 ] 2>/dev/null && THREAD=1
