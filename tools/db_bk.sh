#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon
#       https://github.com/misakacoo/lemon

. ../options.conf
# 口令不再走命令行参数：--password=xxx 会出现在 ps / /proc/PID/cmdline 里，
# 同机任何用户（含被黑的站点进程）都能读到数据库 root 口令。
# MYSQL_PWD 通过环境变量传给客户端，/proc/PID/environ 只有同用户可读。
export MYSQL_PWD="${dbrootpwd}"

. ../include/check_dir.sh

DBname=$1
LogFile=${backup_dir}/db.log
DumpFile=${backup_dir}/DB_${DBname}_$(date +%Y%m%d_%H%M%S).sql
NewFile=${backup_dir}/DB_${DBname}_$(date +%Y%m%d_%H%M%S).tgz
# expired_days 必须校验再进 date：非数字会让 date 输出空，
# OldFile 退化成 DB_x_*.tgz，rm -f 会删光该库的全部历史备份
if [[ ! "${expired_days}" =~ ^[0-9]+$ ]] || [ "${expired_days}" -lt 1 ]; then
  echo "[${DBname}] expired_days='${expired_days}' 非法（需 >=1 的整数），本次跳过过期清理" >> "${LogFile}"
  OldFile=''
else
  OldFile="${backup_dir}/DB_${DBname}_$(date +%Y%m%d --date="${expired_days} days ago")"*.tgz
fi

[ ! -e "${backup_dir}" ] && mkdir -p ${backup_dir}

# 把 mysql 自己的报错也留在日志里
# 密码为空 / 认证失败时会把人误导成「库不存在」
DB_out=`${db_install_dir}/bin/mysql -uroot -e "show databases\G" 2>&1`
DB_tmp=`echo "${DB_out}" | grep -w "${DBname}"`
if [ -z "${DB_tmp}" ]; then
  echo "[${DBname}] not found, mysql said: $(echo "${DB_out}" | tr '\n' ' ' | cut -c1-200)" >> ${LogFile}
  exit 1
fi

if [ -e "${NewFile}" ]; then
  echo "[${NewFile}] The Backup File is exists, Can't Backup" >> ${LogFile}
else
  # dump 失败时文件照样会被创建（0 字节或半截），必须判退出码
  # dump 是数据库明文（含所有数据），先按 600 建文件再写，避免中途被同机其他用户读到
  ( umask 077; : > ${DumpFile} )
  if ! ${db_install_dir}/bin/mysqldump -uroot --databases ${DBname} > ${DumpFile}; then
    echo "[${DumpFile}] mysqldump FAILED" >> ${LogFile}
    rm -f ${DumpFile}
    exit 1
  fi
  pushd ${backup_dir} > /dev/null
  ( umask 077; touch ${NewFile} )
  if ! tar czf ${NewFile} ${DumpFile##*/} >> ${LogFile} 2>&1; then
    echo "[${NewFile}] tar FAILED" >> ${LogFile}
    rm -f ${NewFile} ${DumpFile}
    popd > /dev/null
    exit 1
  fi
  echo "[${NewFile}] Backup success ">> ${LogFile}
  rm -f ${DumpFile}
  popd > /dev/null
  # 过期备份只在本次成功之后才删：先删旧的再产出坏的，等于把唯一可用的备份弄没了
  if [ -n "`ls ${OldFile} 2>/dev/null`" ]; then
    [ -n "${OldFile}" ] && rm -f ${OldFile}
    echo "[${OldFile}] Delete Old File Success" >> ${LogFile}
  fi
fi
