#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

# 附加组件的安装标记。
#
# 卸载时必须能分清「Lemon 装的」和「机器上本来就有的」：后者一律不碰。
# 典型例子是 supervisor / fail2ban / python —— 很多镜像自带，或者在装 Lemon
# 之前就被装上了，按名字直接 apt purge 会把用户的运行环境搞坏。
#
# 标记落在 /etc/lemon/installed/<name>，内容写安装时间，方便事后排查。

lemon_mark_dir=/etc/lemon/installed

mark_addon_installed() {
  [ -z "$1" ] && return 1
  mkdir -p ${lemon_mark_dir}
  date '+%F %T' > ${lemon_mark_dir}/$1 2>/dev/null
}

addon_installed_by_lemon() {
  [ -n "$1" ] && [ -e "${lemon_mark_dir}/$1" ]
}

clear_addon_mark() {
  [ -n "$1" ] && rm -f ${lemon_mark_dir}/$1
}

# 卸载守卫：没有标记就不动，返回非 0 让调用方 return
#   $1 标记名  $2 显示名  $3 探针路径（这台机器上到底有没有装）
# 探针不存在说明本来就没装，静默返回，避免 --all 在干净机器上刷五条提示
addon_uninstall_guard() {
  local name="$1"
  local label="$2"
  local probe="$3"
  if addon_installed_by_lemon "${name}"; then
    return 0
  fi
  if [ -n "${probe}" ] && [ ! -e "${probe}" ]; then
    return 1
  fi
  echo
  echo "${CWARNING}${label} 没有 Lemon 的安装标记（${lemon_mark_dir}/${name}）${CEND}"
  echo "${CWARNING}它可能是机器上原本就装好的，Lemon 不会卸载它${CEND}"
  echo "${CMSG}确认要卸载请手动处理；若确定是 Lemon 装的，可先执行 mkdir -p ${lemon_mark_dir} && date > ${lemon_mark_dir}/${name} 再重试${CEND}"
  return 1
}
