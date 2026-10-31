#!/bin/bash
# Author:  Alpha Eva <kaneawk AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

# Debian 13 起 libaio 因 t64 迁移改了 SONAME（libaio.so.1 -> libaio.so.1t64），
# 而 MySQL/MariaDB/Percona 的官方二进制仍然写死链接 libaio.so.1，缺了就是启动时
# "error while loading shared libraries: libaio.so.1"。这里补一个兼容软链。
fix_libaio_soname() {
  ldconfig 2>/dev/null
  if ! ldconfig -p 2>/dev/null | grep -q 'libaio\.so\.1 '; then
    local so
    so=$(ldconfig -p 2>/dev/null | awk '/libaio\.so\.1t64/ {print $NF; exit}')
    if [ -n "${so}" ] && [ -e "${so}" ]; then
      ln -sf "${so}" "$(dirname "${so}")/libaio.so.1"
      ldconfig 2>/dev/null
      echo "${CMSG}已为 libaio1t64 补上 libaio.so.1 兼容链接${CEND}"
    fi
  fi
}

installDepsDebian() {
  echo "${CMSG}Removing the conflicting packages...${CEND}"
  if [ "${apache_flag}" == 'y' ]; then
    killall apache2
    # 装 Apache 前清掉 apt 版 apache2，避免 80 端口和模块冲突。
    # 原来的 apache2.2-*、apache2-mpm-*、php5-* 在 Debian 12/13 里已不存在，不再列出
    pkgList="apache2 apache2-doc apache2-utils"
    for Package in ${pkgList};do
      apt-get -y purge ${Package}
    done
    dpkg -l | grep ^rc | awk '{print $2}' | xargs -r dpkg -P
  fi

  # MySQL 系（含 Percona）都要先清系统包；9 = Percona 8.4 原来漏了，会和系统 mariadb 冲突
  if [[ "${db_option}" =~ ^([0-6]|9)$ ]]; then
    pkgList="mysql-client mysql-server mysql-common mariadb-client mariadb-server mariadb-common"
    for Package in ${pkgList};do
      apt-get -y purge ${Package}
    done
    dpkg -l | grep ^rc | awk '{print $2}' | xargs -r dpkg -P
  fi

  echo "${CMSG}Installing dependencies packages...${CEND}"
  apt-get -y update
  apt-get -y autoremove
  apt-get -yf install
  export DEBIAN_FRONTEND=noninteractive

  # critical security updates
  # Debian 13 改用 deb822（/etc/apt/sources.list.d/*.sources），
  # 老的单文件 sources.list 可能不存在，存在才做这一步
  if [ -e /etc/apt/sources.list ] && grep -q security /etc/apt/sources.list; then
    grep security /etc/apt/sources.list > /tmp/security.sources.list
    apt-get -y upgrade -o Dir::Etc::SourceList=/tmp/security.sources.list
  else
    echo "${CWARNING}/etc/apt/sources.list 不存在（Debian 13 使用 deb822 格式），跳过安全源升级${CEND}"
  fi

  # Install needed packages
  case "${Debian_ver}" in
    12)
      # Debian 12 (bookworm)
      #   libidn11/libidn11-dev 已被移除 -> libidn12/libidn-dev
      #   补 libtinfo6：MySQL 8.x 官方二进制链接 libtinfo.so.6
      #   补 pkg-config：PHP/扩展的 configure 依赖它探测 freetype、icu 等
      pkgList="debian-keyring debian-archive-keyring build-essential gcc g++ make cmake autoconf pkg-config libjpeg62-turbo-dev libjpeg-dev libpng-dev libgd-dev libxml2 libxml2-dev zlib1g zlib1g-dev libc6 libc6-dev libc-client2007e-dev libglib2.0-0 libglib2.0-dev bzip2 libzip-dev libbz2-1.0 libncurses5 libncurses5-dev libtinfo6 libaio1 libaio-dev numactl libreadline-dev curl libcurl3-gnutls libcurl4-openssl-dev libpsl-dev e2fsprogs libkrb5-3 libkrb5-dev libltdl-dev libidn12 libidn-dev openssl net-tools libssl-dev libtool libevent-dev bison flex re2c libsasl2-dev libldap2-dev libmemcached-dev libzstd-dev libpcre2-dev libxslt1-dev libicu-dev locales patch vim zip unzip tmux htop bc dc expect libexpat1-dev libonig-dev libtirpc-dev rsync git lsof lrzsz rsyslog cron logrotate chrony libsqlite3-dev psmisc wget sysv-rc apt-transport-https ca-certificates gnupg ufw"
      ;;
    13)
      # Debian 13 (trixie)，t64 时间类型迁移后一批库换了名字：
      #   libaio1 -> libaio1t64        libcurl3-gnutls -> libcurl3t64-gnutls
      #   libglib2.0-0 -> libglib2.0-0t64
      #   libncurses5 -> libncurses6   libncurses5-dev -> libncurses-dev
      #   software-properties-common 已移除
      #   libc-client2007e-dev 已移除（trixie 撤了 uw-imap，imap 扩展在 pecl_imap.sh 里跳过）
      pkgList="debian-keyring debian-archive-keyring build-essential gcc g++ make cmake autoconf pkg-config libjpeg62-turbo-dev libjpeg-dev libpng-dev libgd-dev libxml2 libxml2-dev zlib1g zlib1g-dev libc6 libc6-dev libglib2.0-0t64 libglib2.0-dev bzip2 libzip-dev libbz2-1.0 libncurses6 libncurses-dev libtinfo6 libaio1t64 libaio-dev numactl libreadline-dev curl libcurl3t64-gnutls libcurl4-openssl-dev libpsl-dev e2fsprogs libkrb5-3 libkrb5-dev libltdl-dev libidn12 libidn-dev openssl net-tools libssl-dev libtool libevent-dev bison flex re2c libsasl2-dev libldap2-dev libmemcached-dev libzstd-dev libpcre2-dev libxslt1-dev libicu-dev locales patch vim zip unzip tmux htop bc dc expect libexpat1-dev libonig-dev libtirpc-dev rsync git lsof lrzsz rsyslog cron logrotate chrony libsqlite3-dev psmisc wget sysv-rc apt-transport-https ca-certificates gnupg ufw"
      ;;
  esac
  # 一次装完，省掉 90 次 apt 的读索引与抢锁开销（每次 0.4-1.5 秒）；
  # 万一某个包在当前版本被移除导致整批失败，再退回逐个安装定位
  apt-get --no-install-recommends -y install ${pkgList} || {
    for Package in ${pkgList}; do
      apt-get --no-install-recommends -y install ${Package}
    done
  }
  fix_libaio_soname
}

installDepsBySrc() {
  pushd ${lemon_dir}/src > /dev/null
  # Debian 12 / 13 自带的 ICU 分别是 72 / 76，都远高于 PHP 的 intl 需要的 60，
  # 不再自建 ICU。这里原来靠 pkg-config 探测版本，但它在装依赖之前往往还不存在。
  if command -v lsof >/dev/null 2>&1; then
    # 标记里带上依赖清单版本，改了 pkgList 之后老机器重跑也能自动补包
    echo "deps-${lemon_deps_ver:-1}" > ~/.lemon
  else
    echo "${CFAILURE}apt-get 依赖安装失败（lsof 未就绪），请检查上方的安装日志${CEND}"
    exit 1;
  fi

  popd > /dev/null
}
