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
#                 FTP virtual user account management                 #
# https://github.com/misakacoo/lemon                                  #
#######################################################################
"
# Check if user is root
[ $(id -u) != "0" ] && { echo "${CFAILURE}Error: You must be root to run this script${CEND}"; exit 1; }

lemon_dir=$(dirname "`readlink -f $0`")
pushd ${lemon_dir} > /dev/null
. ./options.conf
. ./include/color.sh

[ ! -d "${pureftpd_install_dir}" ] && { echo "${CFAILURE}FTP server does not exist! ${CEND}"; exit 1; }

FTP_conf=${pureftpd_install_dir}/etc/pure-ftpd.conf
FTP_tmp_passfile=${pureftpd_install_dir}/etc/pureftpd_psss.tmp
Puredbfile=${pureftpd_install_dir}/etc/pureftpd.pdb
Passwdfile=${pureftpd_install_dir}/etc/pureftpd.passwd
FTP_bin=${pureftpd_install_dir}/bin/pure-pw
[ -z "`grep ^PureDB ${FTP_conf}`" ] && { echo "${CFAILURE}pure-ftpd is not own password database${CEND}" ; exit 1; }

ARG_NUM=$#
# 没有终端还走交互菜单会卡在 read 上无限循环，直接提示带参数运行
if [ "${ARG_NUM}" == '0' ] && [ ! -t 0 ]; then
  echo "非交互环境：请带上参数运行，$0 --help 查看可用参数"
  exit 1
fi

# USER / PASSWORD / DIRECTORY 拿到缺参数或非法值时会再问一遍。
# stdin 不是终端时 read 立即 EOF，重问就是空转烧 CPU，直接退出。
no_tty_exit() {
  [ -t 0 ] && return 0
  echo "${CFAILURE}非交互环境：$1${CEND}" >&2
  exit 1
}
Show_Help() {
  echo
  echo "Usage: $0  command ...[parameters]....
  --help, -h                          Show this help message
  --useradd,--add                     Add username
  --usermod                           Modify directory
  --passwd                            Modify password
  --userdel,--delete                  Delete User
  --listalluser,--list                List all User
  --showuser                          List User details
  --username,-u     [ftp username]    Ftp username
  --password,-p     [ftp password]    Ftp password
  --directory,-d,-D [ftp directory]   Ftp home directory
  "
}

TEMP=`getopt -o hu:p:d:D: --long help,useradd,add,usermod,passwd,userdel,delete,listalluser,list,showuser,username:,password:,directory: -- "$@" 2>/dev/null`
[ $? != 0 ] && echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
eval set -- "${TEMP}"
while :; do
  [ -z "$1" ] && break;
  case "$1" in
    -h|--help)
      Show_Help; exit 0
      ;;
    --add|--useradd)
      useradd_flag=y; shift 1
      ;;
    --usermod)
      usermod_flag=y; shift 1
      ;;
    --passwd)
      passwd_flag=y; shift 1
      ;;
    --delete|--userdel)
      userdel_flag=y; shift 1
      ;;
    --list|--listalluser)
      listalluser_flag=y; shift 1
      ;;
    --showuser)
      showuser_flag=y; shift 1
      ;;
    -u|--username)
      username_flag=y; User=$2; shift 2
      ;;
    -p|--password)
      password_flag=y; Password=$2; shift 2
      ;;
    -d|-D|--directory)
      directory_flag=y; Directory=$2; shift 2
      ;;
    --)
      shift
      ;;
    *)
      echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
      ;;
  esac
done

USER() {
  while :; do
    if [ "${username_flag}" != 'y' ]; then
      echo
      read -e -p "Please input a username: " User
    fi
    if [ -z "${User}" ]; then
      echo "${CWARNING}username can't be NULL! ${CEND}"
      # 值来自 CLI 参数时循环里不会再 read，重试只会原地打转，直接退出
      [ "${username_flag}" == 'y' ] && exit 1
      no_tty_exit "缺少 --username 参数"
    else
      break
    fi
  done
}

PASSWORD() {
  while :; do
    if [ "${password_flag}" != 'y' ]; then
      echo
      read -e -p "Please input the password: " Password
    fi
    [ -n "`echo ${Password} | grep '[+|&]'`" ] && { echo "${CWARNING}input error,not contain a plus sign (+) and &${CEND}"; [ "${password_flag}" == 'y' ] && exit 1; no_tty_exit "密码包含 +/- 等非法字符"; continue; }
    if (( ${#Password} >= 5 )); then
      umask 077; echo -e "${Password}\n${Password}" > ${FTP_tmp_passfile}
      break
    else
      echo "${CWARNING}Ftp password least 5 characters! ${CEND}"
      [ "${password_flag}" == 'y' ] && exit 1
      no_tty_exit "密码不足 5 位"
    fi
  done
}

DIRECTORY() {
  while :; do
    if [ "${directory_flag}" != 'y' ]; then
      echo
      read -e -p "Please input the directory(Default directory: ${wwwroot_dir}): " Directory
    fi
    Directory=${Directory:-${wwwroot_dir}}
    if [ ! -d "${Directory}" ]; then
      echo "${CWARNING}The directory does not exist${CEND}"
      [ "${directory_flag}" == 'y' ] && exit 1
      no_tty_exit "目录不存在：${Directory}"
    else
      break
    fi
  done
}

UserAdd() {
  USER
  [ -e "${Passwdfile}" ] && [ -n "`grep ^${User}: ${Passwdfile}`" ] && { echo "${CQUESTION}[${User}] is already existed! ${CEND}"; exit 1; }
  PASSWORD;DIRECTORY
  ${FTP_bin} useradd ${User} -f ${Passwdfile} -u ${run_user} -g ${run_group} -d ${Directory} -m < ${FTP_tmp_passfile}
  rm -f ${FTP_tmp_passfile}
  ${FTP_bin} mkdb ${Puredbfile} -f ${Passwdfile} > /dev/null 2>&1
  echo "#####################################"
  echo
  echo "[${User}] create successful! "
  echo
  echo "You user name is : ${CMSG}${User}${CEND}"
  echo "You Password is : ${CMSG}${Password}${CEND}"
  echo "You directory is : ${CMSG}${Directory}${CEND}"
  echo
}

UserMod() {
  USER
  [ -e "${Passwdfile}" ] && [ -z "`grep ^${User}: ${Passwdfile}`" ] && { echo "${CQUESTION}[${User}] was not existed! ${CEND}"; exit 1; }
  DIRECTORY
  ${FTP_bin} usermod ${User} -f ${Passwdfile} -d ${Directory} -m
  ${FTP_bin} mkdb ${Puredbfile} -f ${Passwdfile} > /dev/null 2>&1
  echo "#####################################"
  echo
  echo "[${User}] modify a successful! "
  echo
  echo "You user name is : ${CMSG}${User}${CEND}"
  echo "You new directory is : ${CMSG}${Directory}${CEND}"
  echo
}

UserPasswd() {
  USER
  [ -e "${Passwdfile}" ] && [ -z "`grep ^${User}: ${Passwdfile}`" ] && { echo "${CQUESTION}[${User}] was not existed! ${CEND}"; exit 1; }
  PASSWORD
  ${FTP_bin} passwd ${User} -f ${Passwdfile} -m < ${FTP_tmp_passfile}
  rm -f ${FTP_tmp_passfile}
  ${FTP_bin} mkdb ${Puredbfile} -f ${Passwdfile} > /dev/null 2>&1
  echo "#####################################"
  echo
  echo "[${User}] Password changed successfully! "
  echo
  echo "You user name is : ${CMSG}${User}${CEND}"
  echo "You new password is : ${CMSG}${Password}${CEND}"
  echo
}

UserDel() {
  if [ ! -e "${Passwdfile}" ]; then
    echo "${CQUESTION}User was not existed! ${CEND}"
  else
    ${FTP_bin} list
  fi

  USER
  [ -e "${Passwdfile}" ] && [ -z "`grep ^${User}: ${Passwdfile}`" ] && { echo "${CQUESTION}[${User}] was not existed! ${CEND}"; exit 1; }
  ${FTP_bin} userdel ${User} -f ${Passwdfile} -m
  ${FTP_bin} mkdb ${Puredbfile} -f ${Passwdfile} > /dev/null 2>&1
  echo
  echo "[${User}] have been deleted! "
}

ListAllUser() {
  if [ ! -e "${Passwdfile}" ]; then
    echo "${CQUESTION}User was not existed! ${CEND}"
  else
    ${FTP_bin} list
  fi
}

ShowUser() {
  USER
  [ -e "${Passwdfile}" ] && [ -z "`grep ^${User}: ${Passwdfile}`" ] && { echo "${CQUESTION}[${User}] was not existed! ${CEND}"; exit 1; }
  ${FTP_bin} show ${User}
}

Menu() {
  while :; do
    printf "
What Are You Doing?
\t${CMSG}1${CEND}. UserAdd
\t${CMSG}2${CEND}. UserMod
\t${CMSG}3${CEND}. UserPasswd
\t${CMSG}4${CEND}. UserDel
\t${CMSG}5${CEND}. ListAllUser
\t${CMSG}6${CEND}. ShowUser
\t${CMSG}q${CEND}. Exit
"
    read -e -p "Please input the correct option: " Number
    if [[ ! ${Number} =~ ^[1-6,q]$ ]]; then
      echo "${CFAILURE}input error! Please only input 1~6 and q${CEND}"
    else
      case "${Number}" in
      1)
        UserAdd
        ;;
      2)
        UserMod
        ;;
      3)
        UserPasswd
        ;;
      4)
        UserDel
        ;;
      5)
        ListAllUser
        ;;
      6)
        ShowUser
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
  [ "${useradd_flag}" == 'y' ] && UserAdd
  [ "${usermod_flag}" == 'y' ] && UserMod
  [ "${passwd_flag}" == 'y' ] && UserPasswd
  [ "${userdel_flag}" == 'y' ] && UserDel
  [ "${listalluser_flag}" == 'y' ] && ListAllUser
  [ "${showuser_flag}" == 'y' ] && ShowUser
fi

# 结尾显式返回 0：上面最后一条基本都是 `[ ... ] && cmd`，条件不成立时
# 脚本会以 1 退出，自动化调用方会误判成失败
exit 0
