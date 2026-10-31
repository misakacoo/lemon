#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon
#       https://github.com/misakacoo/lemon

. ../options.conf
. ../include/check_dir.sh

DBname=$1
LogFile=${backup_dir}/db.log
DumpFile=${backup_dir}/DB_${DBname}_$(date +%Y%m%d_%H%M%S).sql
NewFile=${backup_dir}/DB_${DBname}_$(date +%Y%m%d_%H%M%S).tgz
OldFile=${backup_dir}/DB_${DBname}_$(date +%Y%m%d --date="${expired_days} days ago")*.tgz

[ ! -e "${backup_dir}" ] && mkdir -p ${backup_dir}

# 把 mysql 自己的报错也留在日志里：原来只写一句 "[xxx] not exist"，
# 密码为空 / 认证失败时会把人误导成「库不存在」（真机测试里就踩过）。
DB_out=`${db_install_dir}/bin/mysql -uroot --password="${dbrootpwd}" -e "show databases\G" 2>&1`
DB_tmp=`echo "${DB_out}" | grep -w "${DBname}"`
if [ -z "${DB_tmp}" ]; then
  echo "[${DBname}] not found, mysql said: $(echo "${DB_out}" | tr '\n' ' ' | cut -c1-200)" >> ${LogFile}
  exit 1
fi

if [ -e "${NewFile}" ]; then
  echo "[${NewFile}] The Backup File is exists, Can't Backup" >> ${LogFile}
else
  # dump 失败时文件照样会被创建（0 字节或半截），必须判退出码
  if ! ${db_install_dir}/bin/mysqldump -uroot --password="${dbrootpwd}" --databases ${DBname} > ${DumpFile}; then
    echo "[${DumpFile}] mysqldump FAILED" >> ${LogFile}
    rm -f ${DumpFile}
    exit 1
  fi
  pushd ${backup_dir} > /dev/null
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
    rm -f ${OldFile}
    echo "[${OldFile}] Delete Old File Success" >> ${LogFile}
  fi
fi
