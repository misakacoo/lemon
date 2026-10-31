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
#                    Install/Uninstall Extensions                     #
# https://github.com/misakacoo/lemon                                  #
#######################################################################
"
# Check if user is root
# shellcheck disable=SC2046
[ $(id -u) != '0' ] && { echo "${CFAILURE}Error: You must be root to run this script${CEND}"; exit 1; }

lemon_dir=$(dirname "`readlink -f $0`")
# shellcheck disable=SC2164
pushd ${lemon_dir} > /dev/null

. ./versions.txt
. ./options.conf
. ./include/color.sh
. ./include/check_os.sh

# 无 TTY 运行时 debconf 的 Dialog 前端会失败甚至卡住，apt 装带 postinst 的包时尤其明显
export DEBIAN_FRONTEND=noninteractive
. ./include/download.sh
. ./include/get_char.sh
# 附加组件的安装标记：卸载时用它区分「Lemon 装的」和「机器本来就有的」
. ./include/addon_mark.sh

. ./include/composer.sh

. ./include/fail2ban.sh

. ./include/ngx_lua_waf.sh

# shellcheck disable=SC2154
Show_Help() {
  echo
  echo "Usage: $0  command ...
  --help, -h                  Show this help message
  --install, -i               Install
  --uninstall, -u             Uninstall
  --composer                  Composer
  --fail2ban                  Fail2ban
  --ngx_lua_waf               Ngx_lua_waf
  "
}

ARG_NUM=$#
# 没有终端还走交互菜单会卡在 read 上无限循环，直接提示带参数运行
if [ "${ARG_NUM}" == '0' ] && [ ! -t 0 ]; then
  echo "非交互环境：请带上参数运行，$0 --help 查看可用参数"
  exit 1
fi
TEMP=`getopt -o hiu --long help,install,uninstall,composer,fail2ban,ngx_lua_waf -- "$@" 2>/dev/null`
[ $? != 0 ] && echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
eval set -- "${TEMP}"
while :; do
  [ -z "$1" ] && break;
  case "$1" in
    -h|--help)
      Show_Help; exit 0
      ;;
    -i|--install)
      install_flag=y; shift 1
      ;;
    -u|--uninstall)
      uninstall_flag=y; shift 1
      ;;
    --composer)
      composer_flag=y; shift 1
      ;;
    --fail2ban)
      fail2ban_flag=y; shift 1
      ;;
    --ngx_lua_waf)
      ngx_lua_waf_flag=y; shift 1
      ;;
    --)
      shift
      ;;
    *)
      echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
      ;;
  esac
done

ACTION_FUN() {
  while :; do
    echo
    echo "Please select an action:"
    echo -e "\t${CMSG}1${CEND}. install"
    echo -e "\t${CMSG}2${CEND}. uninstall"
    read -e -p "Please input a number:(Default 1 press Enter) " ACTION
    ACTION=${ACTION:-1}
    if [[ ! "${ACTION}" =~ ^[12]$ ]]; then
      echo "${CWARNING}input error! Please only input number 1~2${CEND}"
    else
      [ "${ACTION}" == '1' ] && install_flag=y
      [ "${ACTION}" == '2' ] && uninstall_flag=y
      break
    fi
  done
}

Menu() {
  while :;do
    printf "
What Are You Doing?
\t${CMSG}1${CEND}. Install/Uninstall PHP Composer
\t${CMSG}2${CEND}. Install/Uninstall fail2ban
\t${CMSG}3${CEND}. Install/Uninstall ngx_lua_waf
\t${CMSG}q${CEND}. Exit
"
    read -e -p "Please input the correct option: " Number
    if [[ ! "${Number}" =~ ^([1-3]|q)$ ]]; then
      echo "${CFAILURE}input error! Please only input 1~3 and q${CEND}"
    else
      case "${Number}" in
        1)
          ACTION_FUN
          if [ "${install_flag}" = 'y' ]; then
            Install_composer
          elif [ "${uninstall_flag}" = 'y' ]; then
            Uninstall_composer
          fi
          ;;
        2)
          ACTION_FUN
          if [ "${install_flag}" = 'y' ]; then
            Install_fail2ban
          elif [ "${uninstall_flag}" = 'y' ]; then
            Uninstall_fail2ban
          fi
          ;;
        3)
          ACTION_FUN
          if [ "${install_flag}" = 'y' ]; then
            . ./include/check_dir.sh
            if [ -z "${web_install_dir}" ]; then
              echo "${CWARNING}ngx_lua_waf 只支持 Nginx / Tengine / OpenResty，当前没有可用的 Web 服务器${CEND}"
            else
              [ -e "${nginx_install_dir}/sbin/nginx" ] && Nginx_lua_waf
              [ -e "${tengine_install_dir}/sbin/nginx" ] && Tengine_lua_waf
              enable_lua_waf
            fi
          elif [ "${uninstall_flag}" = 'y' ]; then
            disable_lua_waf
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
  if [ "${composer_flag}" == 'y' ]; then
    if [ "${install_flag}" = 'y' ]; then
      Install_composer
    elif [ "${uninstall_flag}" = 'y' ]; then
      Uninstall_composer
    fi
  fi
  if [ "${fail2ban_flag}" == 'y' ]; then
    if [ "${install_flag}" = 'y' ]; then
      Install_fail2ban
    elif [ "${uninstall_flag}" = 'y' ]; then
      Uninstall_fail2ban
    fi
  fi
  if [ "${ngx_lua_waf_flag}" == 'y' ]; then
    if [ "${install_flag}" = 'y' ]; then
      . ./include/check_dir.sh
      if [ -z "${web_install_dir}" ]; then
        echo "${CWARNING}ngx_lua_waf 只支持 Nginx / Tengine / OpenResty，当前没有可用的 Web 服务器${CEND}"
      else
        [ -e "${nginx_install_dir}/sbin/nginx" ] && Nginx_lua_waf
        [ -e "${tengine_install_dir}/sbin/nginx" ] && Tengine_lua_waf
        enable_lua_waf
      fi
    elif [ "${uninstall_flag}" = 'y' ]; then
      disable_lua_waf
    fi
  fi
fi

# 结尾显式返回 0：上面最后一条基本都是 `[ ... ] && cmd`，条件不成立时
# 脚本会以 1 退出，自动化调用方会误判成失败
exit 0
