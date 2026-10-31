#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon
#       https://github.com/misakacoo/lemon

. ../options.conf

WebSite=$1
LogFile=${backup_dir}/web.log
NewFile=${backup_dir}/Web_${WebSite}_$(date +%Y%m%d_%H).tgz
OldFile=${backup_dir}/Web_${WebSite}_$(date +%Y%m%d --date="${expired_days} days ago")*.tgz
[ ! -e "${backup_dir}" ] && mkdir -p ${backup_dir}
[ ! -e "${wwwroot_dir}/${WebSite}" ] && { echo "[${wwwroot_dir}/${WebSite}] not exist" >> ${LogFile} ;  exit 1 ; }

if [ `du -sm "${wwwroot_dir}/${WebSite}" | awk '{print $1}'` -lt 1024 ]; then
  if [ -e "${NewFile}" ]; then
    echo "[${NewFile}] The Backup File is exists, Can't Backup" >> ${LogFile}
  else
    pushd ${wwwroot_dir} > /dev/null
    if ! tar czf ${NewFile} ./${WebSite} >> ${LogFile} 2>&1; then
      echo "[${NewFile}] tar FAILED" >> ${LogFile}
      rm -f ${NewFile}
      popd > /dev/null
      exit 1
    fi
    echo "[${NewFile}] Backup success ">> ${LogFile}
    popd > /dev/null
    # 过期备份只在本次成功之后才删
    if [ -n "`ls ${OldFile} 2>/dev/null`" ]; then
      rm -f ${OldFile}
      echo "[${OldFile}] Delete Old File Success" >> ${LogFile}
    fi
  fi
else
  if ! rsync -crazP --delete ${wwwroot_dir}/${WebSite} ${backup_dir} >> ${LogFile} 2>&1; then
    echo "[${wwwroot_dir}/${WebSite}] rsync FAILED" >> ${LogFile}
    exit 1
  fi
fi
