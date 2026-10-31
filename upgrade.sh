#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
# 没有 TTY（nohup、CI、管道）时 clear 会报 TERM 未设置，纯噪音
[ -t 1 ] && clear
printf "
#######################################################################
# Lemon - One-click Linux web stack (Nginx/MySQL/PHP)                 #
#                 Upgrade Software versions for Lemon                 #
# https://github.com/misakacoo/lemon                                  #
#######################################################################
"
# Check if user is root
[ $(id -u) != "0" ] && { echo "${CFAILURE}Error: You must be root to run this script${CEND}"; exit 1; }

lemon_dir=$(dirname "`readlink -f $0`")
pushd ${lemon_dir} > /dev/null
. ./versions.txt
. ./options.conf
. ./include/color.sh
. ./include/check_os.sh
. ./include/check_dir.sh
. ./include/php_build.sh
. ./include/download.sh
. ./include/get_char.sh
# upgrade_db.sh 里的 set_conf_var 定义在 db_common.sh，缺了它升级后写不回 options.conf
. ./include/db_common.sh
. ./include/upgrade_web.sh
. ./include/upgrade_db.sh
. ./include/upgrade_php.sh
. ./include/upgrade_redis.sh
. ./include/upgrade_memcached.sh
. ./include/upgrade_phpmyadmin.sh
. ./include/upgrade_lemon.sh

Show_Help() {
  echo
  echo "Usage: $0  command ...[version]....
  --help, -h                  Show this help message
  --nginx        [version]    Upgrade Nginx
  --tengine      [version]    Upgrade Tengine
  --openresty    [version]    Upgrade OpenResty
  --apache       [version]    Upgrade Apache
  --db           [version]    Upgrade MySQL/MariaDB/Percona
  --php          [version]    Upgrade PHP
  --redis        [version]    Upgrade Redis
  --memcached    [version]    Upgrade Memcached
  --phpmyadmin   <version>    Upgrade phpMyAdmin（必填；写 latest 表示自动取最新）
  --lemon                Upgrade Lemon latest
  --acme.sh                   Upgrade acme.sh latest
  "
}

ARG_NUM=$#
# 无参数时进交互菜单；stdin 不是终端时 read 会立刻返回 EOF，
# Menu 里的 while : 拿不到值又不 break，会空转把 CPU 烧满。
if [ "${ARG_NUM}" == '0' ] && [ ! -t 0 ]; then
  echo "非交互环境：请带上参数运行，$0 --help 查看可用参数"
  exit 1
fi
TEMP=`getopt -o h --long help,nginx:,tengine:,openresty:,apache:,db:,php:,redis:,memcached:,phpmyadmin:,lemon,acme.sh -- "$@" 2>/dev/null`
[ $? != 0 ] && echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
eval set -- "${TEMP}"
while :; do
  [ -z "$1" ] && break;
  case "$1" in
    -h|--help)
      Show_Help; exit 0
      ;;
    --nginx)
      nginx_flag=y; NEW_nginx_ver=$2; shift 2
      ;;
    --tengine)
      tengine_flag=y; NEW_tengine_ver=$2; shift 2
      ;;
    --openresty)
      openresty_flag=y; NEW_openresty_ver=$2; shift 2
      ;;
    --apache)
      apache_flag=y; NEW_apache_ver=$2; shift 2
      ;;
    --db)
      db_flag=y; NEW_db_ver=$2; shift 2
      ;;
    --php)
      php_flag=y; NEW_php_ver=$2; shift 2
      ;;
    --redis)
      redis_flag=y; NEW_redis_ver=$2; shift 2
      ;;
    --memcached)
      memcached_flag=y; NEW_memcached_ver=$2; shift 2
      ;;
    --phpmyadmin)
      phpmyadmin_flag=y; NEW_phpmyadmin_ver=$2; shift 2
      # latest = 由 include/upgrade_phpmyadmin.sh 去官网抓最新版本号
      [ "${NEW_phpmyadmin_ver}" == 'latest' ] && NEW_phpmyadmin_ver=''
      ;;
    --lemon)
      NEW_lemon_ver=latest; shift 1
      ;;
    --acme.sh)
      NEW_acme_ver=latest; shift 1
      ;;
    --)
      shift
      ;;
    *)
      echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
      ;;
  esac
done

# 版本号会直接拼进下载 URL 与文件名（tar zxf nginx-${NEW_nginx_ver}.tar.gz 等），
# 必须只允许数字和点；否则 `--nginx 'x; rm -rf /'` 这类输入会进入未加引号的命令。
for _v in "${NEW_nginx_ver}" "${NEW_tengine_ver}" "${NEW_openresty_ver}" "${NEW_apache_ver}" \
          "${NEW_db_ver}" "${NEW_php_ver}" "${NEW_redis_ver}" "${NEW_memcached_ver}" \
          "${NEW_phpmyadmin_ver}"; do
  [ -z "${_v}" ] && continue
  if [[ ! "${_v}" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    echo "${CFAILURE}版本号格式非法：${_v}（只允许数字和点，例如 1.30.6）${CEND}"
    exit 1
  fi
done
unset _v

Menu() {
  while :; do
    printf "
What Are You Doing?
\t${CMSG} 1${CEND}. Upgrade Nginx/Tengine/OpenResty
\t${CMSG} 2${CEND}. Upgrade Apache
\t${CMSG} 4${CEND}. Upgrade MySQL/MariaDB/Percona
\t${CMSG} 5${CEND}. Upgrade PHP
\t${CMSG} 6${CEND}. Upgrade Redis
\t${CMSG} 7${CEND}. Upgrade Memcached
\t${CMSG} 8${CEND}. Upgrade phpMyAdmin
\t${CMSG} 9${CEND}. Upgrade Lemon latest
\t${CMSG}10${CEND}. Upgrade acme.sh latest
\t${CMSG} q${CEND}. Exit
"
    echo
    read -e -p "Please input the correct option: " Upgrade_flag
    if [[ ! "${Upgrade_flag}" =~ ^[1-9,q]$|^10$ ]]; then
      echo "${CWARNING}input error! Please only input 1~10 and q${CEND}"
    else
      case "${Upgrade_flag}" in
        1)
          [ -e "${nginx_install_dir}/sbin/nginx" ] && Upgrade_Nginx
          [ -e "${tengine_install_dir}/sbin/nginx" ] && Upgrade_Tengine
          [ -e "${openresty_install_dir}/nginx/sbin/nginx" ] && Upgrade_OpenResty
          ;;
        2)
          Upgrade_Apache
          ;;
        3)
          ;;
        4)
          Upgrade_DB
          ;;
        5)
          Upgrade_PHP
          ;;
        6)
          Upgrade_Redis
          ;;
        7)
          Upgrade_Memcached
          ;;
        8)
          Upgrade_phpMyAdmin
          ;;
        9)
          Upgrade_Lemon
          ;;
        10)
          if [ -e ~/.acme.sh/acme.sh ]; then
            ~/.acme.sh/acme.sh --force --upgrade; ~/.acme.sh/acme.sh --version;
          elif [ -e /usr/local/acme.sh/acme.sh ]; then
            /usr/local/acme.sh/acme.sh --force --upgrade; /usr/local/acme.sh/acme.sh --version;
          elif [ -e /opt/acme.sh/acme.sh ]; then
            /opt/acme.sh/acme.sh --force --upgrade; /opt/acme.sh/acme.sh --version;
          elif command -v acme.sh >/dev/null 2>&1; then
            acme.sh --force --upgrade; acme.sh --version;
          else
            echo "${CWARNING}acme.sh not found!${CEND}"
          fi
          ;;
        q)
          exit
          ;;
      esac
    fi
  done
}

if [ ${ARG_NUM} == 0 ]; then
  Menu
else
  [ "${nginx_flag}" == 'y' ] && Upgrade_Nginx
  [ "${tengine_flag}" == 'y' ] && Upgrade_Tengine
  [ "${openresty_flag}" == 'y' ] && Upgrade_OpenResty
  [ "${apache_flag}" == 'y' ] && Upgrade_Apache
  [ "${db_flag}" == 'y' ] && Upgrade_DB
  [ "${php_flag}" == 'y' ] && Upgrade_PHP
  [ "${redis_flag}" == 'y' ] && Upgrade_Redis
  [ "${memcached_flag}" == 'y' ] && Upgrade_Memcached
  [ "${phpmyadmin_flag}" == 'y' ] && Upgrade_phpMyAdmin
  [ "${NEW_lemon_ver}" == 'latest' ] && Upgrade_Lemon
  if [ "${NEW_acme_ver}" == 'latest' ]; then
    if [ -e ~/.acme.sh/acme.sh ]; then
      ~/.acme.sh/acme.sh --force --upgrade; ~/.acme.sh/acme.sh --version;
    elif [ -e /usr/local/acme.sh/acme.sh ]; then
      /usr/local/acme.sh/acme.sh --force --upgrade; /usr/local/acme.sh/acme.sh --version;
    elif [ -e /opt/acme.sh/acme.sh ]; then
      /opt/acme.sh/acme.sh --force --upgrade; /opt/acme.sh/acme.sh --version;
    elif command -v acme.sh >/dev/null 2>&1; then
      acme.sh --force --upgrade; acme.sh --version;
    else
      echo "${CWARNING}acme.sh not found!${CEND}"
    fi
  fi
fi

# 结尾显式返回 0：上面最后一条基本都是 `[ ... ] && cmd`，条件不成立时
# 脚本会以 1 退出，自动化调用方会误判成失败
exit 0
