#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Upgrade_Lemon() {
  # 上游的镜像自升级通道已不可用；直接改本地文件又会覆盖 options.conf 里的密码，
  # 这里只给出安全的更新指引
  echo
  echo "${CWARNING}Lemon 不再内置自动更新${CEND}（旧版镜像通道已下线，自动覆盖会丢失 options.conf 中的本机配置）"
  echo
  echo "请手动执行："
  echo "  cd ${lemon_dir}"
  echo "  cp options.conf /root/options.conf.bak"
  echo "  git fetch origin && git reset --hard origin/main"
  echo "  cp /root/options.conf.bak options.conf"
  echo
  echo "版本库：https://github.com/misakacoo/lemon"
  echo
}
