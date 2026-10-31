#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon
#
# Supervisor：常驻进程管理（supervisord + supervisorctl）。
# 它不属于 PHP 扩展，也不是 Web/DB 组件，归到附加组件这一类，
# 和 fail2ban 一样由 apt 提供，自带 systemd 单元和 /etc/supervisor 配置树。

Install_supervisor() {
  echo "${CMSG}Installing supervisor from apt...${CEND}"
  apt-get -y install supervisor
  if [ ! -e /etc/supervisor/supervisord.conf ]; then
    echo "${CFAILURE}supervisor 安装失败（/etc/supervisor 未生成），请检查 apt 源${CEND}"
    return 1
  fi

  [ ! -d /etc/supervisor/conf.d ] && mkdir -p /etc/supervisor/conf.d
  systemctl enable supervisor > /dev/null 2>&1
  systemctl restart supervisor
  sleep 2

  if [ "$(systemctl is-active supervisor)" == 'active' ]; then
    mark_addon_installed supervisor
    echo; echo "${CSUCCESS}supervisor installed successfully! ${CEND}"
    echo "${CMSG}托管程序写到 /etc/supervisor/conf.d/*.conf，改完执行 supervisorctl reread && supervisorctl update${CEND}"
    echo "${CMSG}查看状态：supervisorctl status${CEND}"
  else
    echo; echo "${CFAILURE}supervisor 已安装但没起来，请执行 journalctl -u supervisor 查看原因${CEND}"
    return 1
  fi
}

Uninstall_supervisor() {
  addon_uninstall_guard supervisor "supervisor" /etc/supervisor/supervisord.conf || return 0
  systemctl stop supervisor > /dev/null 2>&1
  systemctl disable supervisor > /dev/null 2>&1
  apt-get -y purge supervisor > /dev/null 2>&1
  # conf.d 里可能是用户自己的程序配置，不删；只在空的时候把目录收掉
  rmdir /etc/supervisor/conf.d > /dev/null 2>&1
  rmdir /etc/supervisor > /dev/null 2>&1
  clear_addon_mark supervisor
  echo; echo "${CMSG}supervisor uninstall completed${CEND}"
}
