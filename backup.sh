#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

# Check if user is root
[ $(id -u) != "0" ] && { echo "Error: You must be root to run this script"; exit 1; }

lemon_dir=$(dirname "`readlink -f $0`")
pushd ${lemon_dir}/tools > /dev/null
. ../options.conf
. ../include/color.sh
# check_dir.sh 依据 options.conf 的安装路径推导 db_install_dir（纯检测，无副作用）；
# 不 source 它时下面 db_skip 检测恒为真，库里装了 MySQL 也会被跳过
. ../include/check_dir.sh
[ ! -e "${backup_dir}" ] && mkdir -p ${backup_dir}

# tools/db_bk.sh 只支持 MySQL / MariaDB / Percona。
# 装的是 PostgreSQL 或 MongoDB 时，db_install_dir 是空的，
# 后面每个 DB_*_BK 都会去调一个不存在的 mysqldump，cron 里每晚静默失败。
if [ -z "${db_install_dir}" ] || [ ! -x "${db_install_dir}/bin/mysqldump" ]; then
  echo "${CWARNING}未检测到 MySQL/MariaDB/Percona，数据库备份跳过（PostgreSQL / MongoDB 暂不支持）${CEND}"
  db_skip=y
fi

# options.conf 是运行时配置（install.sh 会把密码写进去），但它同时被 git 跟踪。
# 真机测试里出现过：git checkout / pull 把 options.conf 回退成模板，dbrootpwd 变空，
# 于是 mysqldump 连不上、db_bk.sh 只记一句 "[xxx] not exist"，看起来像备份功能坏了。
# 这里显式拦一下，别让空密码被当成「库不存在」。
if [ -z "${dbrootpwd}" ] && [ "${db_skip}" != 'y' ]; then
  echo "${CWARNING}options.conf 里的 dbrootpwd 为空（通常是被 git checkout/pull 回退成模板了），数据库备份跳过。请把密码写回 options.conf 或重跑 install.sh${CEND}"
  db_skip=y
fi

DB_Local_BK() {
  [ "${db_skip}" == 'y' ] && return 0
  for D in `echo ${db_name} | tr ',' ' '`
  do
    # db_bk.sh 失败（密码错、磁盘满、mysqldump 报错）要能被上层看见，
    # 否则备份文件没生成、cron 依旧返回 0。
    ./db_bk.sh ${D} || backup_fail=1
  done
}

DB_Remote_BK() {
  [ "${db_skip}" == 'y' ] && return 0
  for D in `echo ${db_name} | tr ',' ' '`
  do
    ./db_bk.sh ${D}
    DB_GREP="DB_${D}_`date +%Y%m%d`"
    DB_FILE=`ls -lrt ${backup_dir} | grep ${DB_GREP} | tail -1 | awk '{print $NF}'`
    # 当天备份没生成时 DB_FILE 为空，拼出来的路径是错的，跳过 push
    [ -n "${DB_FILE}" ] || continue
    echo "file:::${backup_dir}/${DB_FILE} ${backup_dir} push" >> config_backup.txt
    echo "com:::[ -e "${backup_dir}/${DB_FILE}" ] && rm -rf ${backup_dir}/DB_${D}_$(date +%Y%m%d --date="${expired_days} days ago")_*.tgz" >> config_backup.txt
  done
}

DB_OSS_BK() {
  [ "${db_skip}" == 'y' ] && return 0
  for D in `echo ${db_name} | tr ',' ' '`
  do
    ./db_bk.sh ${D}
    DB_GREP="DB_${D}_`date +%Y%m%d`"
    DB_FILE=`ls -lrt ${backup_dir} | grep ${DB_GREP} | tail -1 | awk '{print $NF}'`
    [ -n "${DB_FILE}" ] || continue
    ossutil cp -f ${backup_dir}/${DB_FILE} oss://${oss_bucket}/`date +%F`/${DB_FILE}
    if [ $? -eq 0 ]; then
      ossutil rm -rf oss://${oss_bucket}/`date +%F --date="${expired_days} days ago"`/
      [ -z "`echo ${backup_destination} | grep -ow 'local'`" ] && rm -f ${backup_dir}/${DB_FILE}
    fi
  done
}

DB_COS_BK() {
  [ "${db_skip}" == 'y' ] && return 0
  for D in `echo ${db_name} | tr ',' ' '`
  do
    ./db_bk.sh ${D}
    DB_GREP="DB_${D}_`date +%Y%m%d`"
    DB_FILE=`ls -lrt ${backup_dir} | grep ${DB_GREP} | tail -1 | awk '{print $NF}'`
    [ -n "${DB_FILE}" ] || continue
    coscli sync ${backup_dir}/${DB_FILE} cos://${cos_bucket}/`date +%F`/${DB_FILE}
    if [ $? -eq 0 ]; then
      coscli rm -rf cos://${cos_bucket}/`date +%F --date="${expired_days} days ago"` > /dev/null 2>&1
      [ -z "`echo ${backup_destination} | grep -ow 'local'`" ] && rm -f ${backup_dir}/${DB_FILE}
    fi
  done
}

DB_UPYUN_BK() {
  [ "${db_skip}" == 'y' ] && return 0
  for D in `echo ${db_name} | tr ',' ' '`
  do
    ./db_bk.sh ${D}
    DB_GREP="DB_${D}_`date +%Y%m%d`"
    DB_FILE=`ls -lrt ${backup_dir} | grep ${DB_GREP} | tail -1 | awk '{print $NF}'`
    [ -n "${DB_FILE}" ] || continue
    upx put ${backup_dir}/${DB_FILE} /`date +%F`/${DB_FILE}
    if [ $? -eq 0 ]; then
      upx rm -a `date +%F --date="${expired_days} days ago"` > /dev/null 2>&1
      [ -z "`echo ${backup_destination} | grep -ow 'local'`" ] && rm -f ${backup_dir}/${DB_FILE}
    fi
  done
}

DB_QINIU_BK() {
  [ "${db_skip}" == 'y' ] && return 0
  for D in `echo ${db_name} | tr ',' ' '`
  do
    ./db_bk.sh ${D}
    DB_GREP="DB_${D}_`date +%Y%m%d`"
    DB_FILE=`ls -lrt ${backup_dir} | grep ${DB_GREP} | tail -1 | awk '{print $NF}'`
    [ -n "${DB_FILE}" ] || continue
    qshell rput ${qiniu_bucket} /`date +%F`/${DB_FILE} ${backup_dir}/${DB_FILE}
    if [ $? -eq 0 ]; then
      qshell listbucket ${qiniu_bucket} /`date +%F --date="${expired_days} days ago"` /tmp/qiniu.txt > /dev/null 2>&1
      qshell batchdelete -force ${qiniu_bucket} /tmp/qiniu.txt > /dev/null 2>&1
      [ -z "`echo ${backup_destination} | grep -ow 'local'`" ] && rm -f ${backup_dir}/${DB_FILE}
      rm -f /tmp/qiniu.txt
    fi
  done
}

DB_S3_BK() {
  [ "${db_skip}" == 'y' ] && return 0
  for D in `echo ${db_name} | tr ',' ' '`
  do
    ./db_bk.sh ${D}
    DB_GREP="DB_${D}_`date +%Y%m%d`"
    DB_FILE=`ls -lrt ${backup_dir} | grep ${DB_GREP} | tail -1 | awk '{print $NF}'`
    # 当天备份没生成时 DB_FILE 为空，拼出来的路径是错的，跳过 push
    [ -n "${DB_FILE}" ] || continue
    aws s3 sync ${backup_dir}/${DB_FILE} s3://${s3_bucket}/`date +%F`/${DB_FILE}
    if [ $? -eq 0 ]; then
      aws s3 rm -r s3://${s3_bucket}/`date +%F --date="${expired_days} days ago"` > /dev/null 2>&1
      [ -z "`echo ${backup_destination} | grep -ow 'local'`" ] && rm -f ${backup_dir}/${DB_FILE}
    fi
  done
}

DB_DROPBOX_BK() {
  [ "${db_skip}" == 'y' ] && return 0
  for D in `echo ${db_name} | tr ',' ' '`
  do
    ./db_bk.sh ${D}
    DB_GREP="DB_${D}_`date +%Y%m%d`"
    DB_FILE=`ls -lrt ${backup_dir} | grep ${DB_GREP} | tail -1 | awk '{print $NF}'`
    [ -n "${DB_FILE}" ] || continue
    dbxcli put ${backup_dir}/${DB_FILE} `date +%F`/${DB_FILE}
    if [ $? -eq 0 ]; then
      dbxcli rm -f `date +%F --date="${expired_days} days ago"` > /dev/null 2>&1
      [ -z "`echo ${backup_destination} | grep -ow 'local'`" ] && rm -f ${backup_dir}/${DB_FILE}
    fi
  done
}

WEB_LOCAL_BK() {
  for W in `echo ${website_name} | tr ',' ' '`
  do
    ./website_bk.sh $W || backup_fail=1
  done
}

WEB_Remote_BK() {
  for W in `echo ${website_name} | tr ',' ' '`
  do
    # 阈值必须与 tools/website_bk.sh 一致（那里 < 1024 才打 tgz，否则走 rsync）：
    # 原来这里写 2048，1~2GB 的站点会进 if 分支但拿不到 tgz，Web_FILE 为空、推送一个目录必然失败
    if [ `du -sm "${wwwroot_dir}/${W}" | awk '{print $1}'` -lt 1024 ]; then
      ./website_bk.sh $W
      Web_GREP="Web_${W}_`date +%Y%m%d`"
      Web_FILE=`ls -lrt ${backup_dir} | grep ${Web_GREP} | tail -1 | awk '{print $NF}'`
      [ -n "${Web_FILE}" ] || { echo "[${W}] no backup file produced, skip remote push"; continue; }
      echo "file:::${backup_dir}/${Web_FILE} ${backup_dir} push" >> config_backup.txt
      echo "com:::[ -e "${backup_dir}/${Web_FILE}" ] && rm -rf ${backup_dir}/Web_${W}_$(date +%Y%m%d --date="${expired_days} days ago")_*.tgz" >> config_backup.txt
    else
      echo "file:::${wwwroot_dir}/$W ${backup_dir} push" >> config_backup.txt
    fi
  done
}

WEB_OSS_BK() {
  for W in `echo $website_name | tr ',' ' '`
  do
    [ ! -e "${wwwroot_dir}/${W}" ] && { echo "[${wwwroot_dir}/${W}] not exist"; continue; }
    PUSH_FILE="${backup_dir}/Web_${W}_$(date +%Y%m%d_%H).tgz"
    if [ ! -e "${PUSH_FILE}" ]; then
      pushd ${wwwroot_dir} > /dev/null
      tar czf ${PUSH_FILE} ./$W
      popd > /dev/null
    fi
    ossutil cp -f ${PUSH_FILE} oss://${oss_bucket}/`date +%F`/${PUSH_FILE##*/}
    if [ $? -eq 0 ]; then
      ossutil rm -rf oss://${oss_bucket}/`date +%F --date="${expired_days} days ago"`/
      [ -z "`echo ${backup_destination} | grep -ow 'local'`" ] && rm -f ${PUSH_FILE}
    fi
  done
}

WEB_COS_BK() {
  for W in `echo ${website_name} | tr ',' ' '`
  do
    [ ! -e "${wwwroot_dir}/${W}" ] && { echo "[${wwwroot_dir}/${W}] not exist"; continue; }
    PUSH_FILE="${backup_dir}/Web_${W}_$(date +%Y%m%d_%H).tgz"
    if [ ! -e "${PUSH_FILE}" ]; then
      pushd ${wwwroot_dir} > /dev/null
      tar czf ${PUSH_FILE} ./$W
      popd > /dev/null
    fi
    coscli sync ${PUSH_FILE} cos://${cos_bucket}/`date +%F`/${PUSH_FILE##*/}
    if [ $? -eq 0 ]; then
      coscli rm -rf cos://${cos_bucket}/`date +%F --date="${expired_days} days ago"` > /dev/null 2>&1
      [ -z "`echo ${backup_destination} | grep -ow 'local'`" ] && rm -f ${PUSH_FILE}
    fi
  done
}

WEB_UPYUN_BK() {
  for W in `echo ${website_name} | tr ',' ' '`
  do
    [ ! -e "${wwwroot_dir}/${W}" ] && { echo "[${wwwroot_dir}/${W}] not exist"; continue; }
    [ ! -e "${backup_dir}" ] && mkdir -p ${backup_dir}
    PUSH_FILE="${backup_dir}/Web_${W}_$(date +%Y%m%d_%H).tgz"
    if [ ! -e "${PUSH_FILE}" ]; then
      pushd ${wwwroot_dir} > /dev/null
      tar czf ${PUSH_FILE} ./$W
      popd > /dev/null
    fi
    upx put ${PUSH_FILE} /`date +%F`/${PUSH_FILE##*/}
    if [ $? -eq 0 ]; then
      upx rm -a `date +%F --date="${expired_days} days ago"` > /dev/null 2>&1
      [ -z "`echo ${backup_destination} | grep -ow 'local'`" ] && rm -f ${PUSH_FILE}
    fi
  done
}

WEB_QINIU_BK() {
  for W in `echo ${website_name} | tr ',' ' '`
  do
    [ ! -e "${wwwroot_dir}/${W}" ] && { echo "[${wwwroot_dir}/${W}] not exist"; continue; }
    [ ! -e "${backup_dir}" ] && mkdir -p ${backup_dir}
    PUSH_FILE="${backup_dir}/Web_${W}_$(date +%Y%m%d_%H).tgz"
    if [ ! -e "${PUSH_FILE}" ]; then
      pushd ${wwwroot_dir} > /dev/null
      tar czf ${PUSH_FILE} ./$W
      popd > /dev/null
    fi
    qshell rput ${qiniu_bucket} /`date +%F`/${PUSH_FILE##*/} ${PUSH_FILE}
    if [ $? -eq 0 ]; then
      qshell listbucket ${qiniu_bucket} /`date +%F --date="${expired_days} days ago"` /tmp/qiniu.txt > /dev/null 2>&1
      qshell batchdelete -force ${qiniu_bucket} /tmp/qiniu.txt > /dev/null 2>&1
      [ -z "`echo ${backup_destination} | grep -ow 'local'`" ] && rm -f ${PUSH_FILE}
      rm -f /tmp/qiniu.txt
    fi
  done
}

WEB_S3_BK() {
  for W in `echo ${website_name} | tr ',' ' '`
  do
    [ ! -e "${wwwroot_dir}/${W}" ] && { echo "[${wwwroot_dir}/${W}] not exist"; continue; }
    [ ! -e "${backup_dir}" ] && mkdir -p ${backup_dir}
    PUSH_FILE="${backup_dir}/Web_${W}_$(date +%Y%m%d_%H).tgz"
    if [ ! -e "${PUSH_FILE}" ]; then
      pushd ${wwwroot_dir} > /dev/null
      tar czf ${PUSH_FILE} ./$W
      popd > /dev/null
    fi
    aws s3 sync ${PUSH_FILE} s3://${s3_bucket}/`date +%F`/${PUSH_FILE##*/}
    if [ $? -eq 0 ]; then
      aws s3 rm -r s3://${s3_bucket}/`date +%F --date="${expired_days} days ago"` > /dev/null 2>&1
      [ -z "`echo ${backup_destination} | grep -ow 'local'`" ] && rm -f ${PUSH_FILE}
    fi
  done
}

WEB_DROPBOX_BK() {
  for W in `echo ${website_name} | tr ',' ' '`
  do
    [ ! -e "${wwwroot_dir}/${W}" ] && { echo "[${wwwroot_dir}/${W}] not exist"; continue; }
    [ ! -e "${backup_dir}" ] && mkdir -p ${backup_dir}
    PUSH_FILE="${backup_dir}/Web_${W}_$(date +%Y%m%d_%H).tgz"
    if [ ! -e "${PUSH_FILE}" ]; then
      pushd ${wwwroot_dir} > /dev/null
      tar czf ${PUSH_FILE} ./$W
      popd > /dev/null
    fi
    dbxcli put ${PUSH_FILE} `date +%F`/${PUSH_FILE##*/}
    if [ $? -eq 0 ]; then
      dbxcli rm -f `date +%F --date="${expired_days} days ago"` > /dev/null 2>&1
      [ -z "`echo ${backup_destination} | grep -ow 'local'`" ] && rm -f ${PUSH_FILE}
    fi
  done
}

for DEST in `echo ${backup_destination} | tr ',' ' '`
do
  if [ "${DEST}" == 'local' ]; then
    [ -n "`echo ${backup_content} | grep -ow db`" ] && DB_Local_BK
    [ -n "`echo ${backup_content} | grep -ow web`" ] && WEB_LOCAL_BK
  fi
  if [ "${DEST}" == 'remote' ]; then
    echo "com:::[ ! -e "${backup_dir}" ] && mkdir -p ${backup_dir}" > config_backup.txt
    [ -n "`echo ${backup_content} | grep -ow db`" ] && DB_Remote_BK
    [ -n "`echo ${backup_content} | grep -ow web`" ] && WEB_Remote_BK
    ./mabs.sh -c config_backup.txt -T -1 2>&1 | tee -a mabs.log
    # 管道会把 mabs.sh 的退出码吃掉（拿到的永远是 tee 的 0），这里用 PIPESTATUS 取回来。
    # 远程备份失败（密码改了 / 网络断了 / 磁盘满）必须让本脚本非 0 退出，否则 cron 静默失败。
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
      echo "${CFAILURE}远程备份失败，详情见 ${lemon_dir}/tools/mabs.log 与 ${lemon_dir}/tools/logs/<IP>.log${CEND}"
      backup_fail=1
    fi
  fi
  if [ "${DEST}" == 'oss' ]; then
    [ -n "`echo ${backup_content} | grep -ow db`" ] && DB_OSS_BK
    [ -n "`echo ${backup_content} | grep -ow web`" ] && WEB_OSS_BK
  fi
  if [ "${DEST}" == 'cos' ]; then
    [ -n "`echo ${backup_content} | grep -ow db`" ] && DB_COS_BK
    [ -n "`echo ${backup_content} | grep -ow web`" ] && WEB_COS_BK
  fi
  if [ "${DEST}" == 'upyun' ]; then
    [ -n "`echo ${backup_content} | grep -ow db`" ] && DB_UPYUN_BK
    [ -n "`echo ${backup_content} | grep -ow web`" ] && WEB_UPYUN_BK
  fi
  if [ "${DEST}" == 'qiniu' ]; then
    [ -n "`echo ${backup_content} | grep -ow db`" ] && DB_QINIU_BK
    [ -n "`echo ${backup_content} | grep -ow web`" ] && WEB_QINIU_BK
  fi
  if [ "${DEST}" == 's3' ]; then
    [ -n "`echo ${backup_content} | grep -ow db`" ] && DB_S3_BK
    [ -n "`echo ${backup_content} | grep -ow web`" ] && WEB_S3_BK
  fi
  if [ "${DEST}" == 'dropbox' ]; then
    [ -n "`echo ${backup_content} | grep -ow db`" ] && DB_DROPBOX_BK
    [ -n "`echo ${backup_content} | grep -ow web`" ] && WEB_DROPBOX_BK
  fi
done

# 结尾：默认返回 0（上面最后一条基本都是 `[ ... ] && cmd`，条件不成立时会以 1 退出，
# 自动化调用方会误判成失败）；但只要远程备份这一步真失败过，就返回非 0 让 cron 报警。
exit ${backup_fail:-0}
