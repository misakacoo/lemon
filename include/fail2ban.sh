#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Install_fail2ban() {
  # Debian 12/13 官方源里就有 fail2ban，自带 systemd 单元、/etc/fail2ban 目录树
  # 和 python3 依赖。源码安装要自己拼数据文件与 service 单元，反而容易踩坑
  # （pip 装出来的 fail2ban.service 里 ExecStart 还是构建目录里的相对路径）。
  echo "${CMSG}Installing fail2ban from apt...${CEND}"
  apt-get -y install fail2ban
  if [ ! -e /etc/fail2ban/jail.conf ]; then
    echo "${CFAILURE}fail2ban 安装失败（/etc/fail2ban 未生成），请检查 apt 源${CEND}"
    return 1
  fi

  [ -z "`grep ^Port /etc/ssh/sshd_config`" ] && now_ssh_port=22 || now_ssh_port=`grep ^Port /etc/ssh/sshd_config | awk '{print $2}' | head -1`

  # 防火墙没开就先开（允许所有入站，封禁由 fail2ban 自己的 iptables 规则接管）
  if ufw status | grep -wq inactive; then
    ufw default allow incoming
    ufw --force enable
  fi

  cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
ignoreip = 127.0.0.1/8
bantime  = 86400
findtime = 600
maxretry = 5
backend = auto
# 封禁动作用默认的 iptables-multiport；action_mwl = 封禁 + 邮件通知（whois + mail），
# 无邮件环境时 whois/mail 部分会报错，属预期
action = %(action_mwl)s

[sshd]
enabled = true
filter  = sshd
port    = ${now_ssh_port}
action = %(action_mwl)s
logpath = /var/log/auth.log
bantime  = 86400
findtime = 600
maxretry = 5
EOF

  # 发行版包自己会装 logrotate 规则，这里只在缺失时补一份，避免覆盖 dpkg 的文件
  if [ ! -e /etc/logrotate.d/fail2ban ]; then
    cat > /etc/logrotate.d/fail2ban << EOF
/var/log/fail2ban.log {
    missingok
    notifempty
    postrotate
      fail2ban-client flushlogs >/dev/null 2>&1 || true
    endscript
}
EOF
  fi

  systemctl enable fail2ban > /dev/null 2>&1
  systemctl restart fail2ban
  sleep 2
  if [ "$(systemctl is-active fail2ban)" == 'active' ]; then
    mark_addon_installed fail2ban
    echo; echo "${CSUCCESS}fail2ban installed successfully! ${CEND}"
  else
    echo; echo "${CFAILURE}fail2ban 已安装但启动失败，请执行 journalctl -u fail2ban 查看原因${CEND}"
    return 1
  fi
}

Uninstall_fail2ban() {
  addon_uninstall_guard fail2ban "fail2ban" /etc/fail2ban/jail.conf || return 0
  systemctl stop fail2ban > /dev/null 2>&1
  systemctl disable fail2ban > /dev/null 2>&1
  apt-get -y purge fail2ban > /dev/null 2>&1
  rm -rf /etc/fail2ban /etc/logrotate.d/fail2ban /var/log/fail2ban.* /var/run/fail2ban
  clear_addon_mark fail2ban
  echo; echo "${CMSG}fail2ban uninstall completed${CEND}";
}
