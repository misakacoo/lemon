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
#                Reset Database root password for Lemon               #
# https://github.com/misakacoo/lemon                                  #
#######################################################################
"
# Check if user is root（此时 color.sh 尚未 source，只用纯文本）
[ $(id -u) != '0' ] && { echo "Error: You must be root to run this script"; exit 1; }

lemon_dir=$(dirname "`readlink -f $0`")
pushd ${lemon_dir} > /dev/null
. ./options.conf
. ./include/color.sh
. ./include/db_common.sh
. ./include/check_dir.sh
[ ! -d "${db_install_dir}" ] && { echo "${CFAILURE}Database is not installed on your system! ${CEND}"; exit 1; }

Show_Help() {
  echo "Usage: $0  command ...[parameters]....
  -h,  --help                  print this help.
  -q,  --quiet                 quiet operation.
  -f,  --force                 Lost Database Password? Forced reset password.
  -p,  --password [pass]       DB super password.
  "
}

New_dbrootpwd="`< /dev/urandom tr -dc A-Za-z0-9 | head -c8`"
TEMP=`getopt -o hqfp: --long help,quiet,force,password: -- "$@" 2>/dev/null`
[ $? != 0 ] && echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
eval set -- "${TEMP}"
while :; do
  [ -z "$1" ] && break;
  case "$1" in
    -h|--help)
      Show_Help; exit 0
      ;;
    -q|--quiet)
      quiet_flag=y; shift 1
      ;;
    -f|--force)
      force_flag=y; shift 1
      ;;
    -p|--password)
      New_dbrootpwd=$2; shift 2
      password_flag=y
      ;;
    --)
      shift
      ;;
    *)
      echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
      ;;
  esac
done

Input_dbrootpwd() {
  # 非交互时 read 立刻返回 EOF，密码永远是空，下面的 while 会一直空转。
  [ -t 0 ] || { echo "${CFAILURE}非交互环境：请用 -q 静默执行，或用 -p 直接指定新密码${CEND}"; exit 1; }
  while :; do echo
    read -e -p "Please input the root password of database: " New_dbrootpwd
    [ -n "`echo ${New_dbrootpwd} | grep '[+|&]'`" ] && { echo "${CWARNING}input error,not contain a plus sign (+) and &${CEND}"; continue; }
    (( ${#New_dbrootpwd} >= 5 )) && break || echo "${CWARNING}database root password least 5 characters! ${CEND}"
  done
}

Reset_Interaction_dbrootpwd() {
  MYSQL_PWD="${dbrootpwd}" ${db_install_dir}/bin/mysqladmin -uroot password "${New_dbrootpwd}" -h localhost > /dev/null 2>&1
  status_Localhost=`echo $?`
  MYSQL_PWD="${dbrootpwd}" ${db_install_dir}/bin/mysqladmin -uroot password "${New_dbrootpwd}" -h 127.0.0.1 > /dev/null 2>&1
  status_127=`echo $?`
  if [ ${status_Localhost} == '0' -a ${status_127} == '0' ]; then
    set_conf_var dbrootpwd "${New_dbrootpwd}" ./options.conf
    echo
    echo "Password reset succesfully! "
    echo "The new password: ${CMSG}${New_dbrootpwd}${CEND}"
    echo
  else
    echo "${CFAILURE}Reset Database root password failed! ${CEND}"
  fi
}

# 从 skip-grant 状态恢复正常运行：先杀 mysqld_safe 再杀 mysqld（否则 mysqld_safe
# 会立刻把 mysqld 重新拉起），并按正常方式启动，无论改密成败都不能留在免密状态
Stop_skip_grant_and_start() {
  killall mysqld_safe 2>/dev/null
  killall mysqld 2>/dev/null
  while [ -n "`ps -ef | grep mysqld | grep -v grep | awk '{print $2}'`" ]; do
    [ -n "`ps -ef | grep mysqld_safe | grep -v grep | awk '{print $2}'`" ] && killall mysqld_safe 2>/dev/null
    sleep 1
  done
  [ -n "`ps -ef | grep mysqld | grep -v grep | awk '{print $2}'`" ] && ps -ef | grep mysqld | grep -v grep | awk '{print $2}' | xargs kill -9 > /dev/null 2>&1
  service mysqld start > /dev/null 2>&1
}

Reset_force_dbrootpwd() {
  DB_Ver="`${db_install_dir}/bin/mysql_config --version`"
  echo "${CMSG}Stopping MySQL...${CEND}"
  service mysqld stop > /dev/null 2>&1
  while [ -n "`ps -ef | grep mysqld | grep -v grep | awk '{print $2}'`" ]; do
    # mysqld_safe 会自动拉起被停掉的 mysqld，发现它还活着就一并杀掉，否则循环永不退出
    [ -n "`ps -ef | grep mysqld_safe | grep -v grep | awk '{print $2}'`" ] && killall mysqld_safe 2>/dev/null
    sleep 1
  done
  echo "${CMSG}skip grant tables...${CEND}"
  ${db_install_dir}/bin/mysqld_safe --skip-grant-tables > /dev/null 2>&1 &
  sleep 5
  while [ -z "`ps -ef | grep 'mysqld ' | grep -v grep | awk '{print $2}'`" ]; do
    sleep 1
  done
  # 密码必须过 esc_sql 并用单引号：双引号拼接时含 " 或 \ 的密码会被截断/转义，
  # 库里存的与 options.conf 记的对不上，等于把 root 锁在门外
  safe_pwd=`esc_sql "${New_dbrootpwd}"`
  if echo "${DB_Ver}" | grep -Eqi '^8\.|^5\.7\.|^10\.'; then
    ${db_install_dir}/bin/mysql -uroot -hlocalhost << EOF
flush privileges;
alter user 'root'@'localhost' identified by '${safe_pwd}';
alter user 'root'@'127.0.0.1' identified by '${safe_pwd}';
EOF
  else
    # 未知版本兜底：更老的版本 user 表还是 Password 字段
    ${db_install_dir}/bin/mysql -uroot -hlocalhost << EOF
update mysql.user set password = Password('${safe_pwd}') where User = 'root';
EOF
  fi
  if [ $? -eq 0 ]; then
    Stop_skip_grant_and_start
    set_conf_var dbrootpwd "${New_dbrootpwd}" ./options.conf
    # 密码可能含 + & 等字符，sed 的分隔符和 & 引用都会被打穿，改用 awk 传参
    [ -e ~/ReadMe ] && awk -v p="${New_dbrootpwd}" '{if ($0 ~ /^MySQL root password:/) print "MySQL root password: " p; else print}' ~/ReadMe > ~/ReadMe.tmp && /bin/mv ~/ReadMe.tmp ~/ReadMe
    echo
    echo "Password reset succesfully! "
    echo "The new password: ${CMSG}${New_dbrootpwd}${CEND}"
    echo
  else
    echo "${CFAILURE}Reset failed: SQL 执行失败，数据库可能仍处于 skip-grant 免密状态，正在尝试恢复正常启动！ ${CEND}"
    Stop_skip_grant_and_start
    exit 1
  fi
}

[ "${password_flag}" == 'y' ] && quiet_flag=y
if [ "${quiet_flag}" == 'y' ]; then
  if [ "${force_flag}" == 'y' ]; then
    Reset_force_dbrootpwd
  else
    sleep 2 && [ ! -e /tmp/mysql.sock ] && service mysqld start
    Reset_Interaction_dbrootpwd
  fi
else
  Input_dbrootpwd
  if [ "${force_flag}" == 'y' ]; then
    Reset_force_dbrootpwd
  else
    Reset_Interaction_dbrootpwd
  fi
fi
popd > /dev/null

# 结尾显式返回 0：上面最后一条基本都是 `[ ... ] && cmd`，条件不成立时
# 脚本会以 1 退出，自动化调用方会误判成失败
exit 0
