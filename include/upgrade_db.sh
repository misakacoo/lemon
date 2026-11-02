#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

# 升级失败回滚：停服 → 删掉半装的新目录 → 把 *_old_<stamp> 换回来 → 重新启动。
# 失败时自动回滚，不需要人工去 /data 里翻 *_old_* 恢复。
DB_Rollback() {
  local inst="$1" data="$2" stamp="$3" svc="$4"
  echo "${CWARNING}开始回滚到升级前状态…${CEND}"
  service "${svc}" stop > /dev/null 2>&1
  if [ -n "${inst}" ] && [ -d "${inst}_old_${stamp}" ]; then
    rm -rf "${inst}"
    /bin/mv "${inst}_old_${stamp}" "${inst}"
  fi
  if [ -n "${data}" ] && [ -d "${data}_old_${stamp}" ]; then
    rm -rf "${data}"
    /bin/mv "${data}_old_${stamp}" "${data}"
  fi
  service "${svc}" start > /dev/null 2>&1
  if service "${svc}" status > /dev/null 2>&1 || pgrep -x mysqld > /dev/null 2>&1; then
    echo "${CSUCCESS}已自动回滚到升级前的版本与数据${CEND}"
  else
    echo "${CFAILURE}回滚后服务仍未起来，请手工检查 ${data}_old_${stamp} 与 error log${CEND}"
  fi
}

Upgrade_DB() {
  pushd ${lemon_dir}/src > /dev/null
  [ ! -e "${db_install_dir}/bin/mysql" ] && echo "${CWARNING}MySQL/MariaDB/Percona is not installed on your system! ${CEND}" && exit 1

  # check db passwd
  while :; do
    ${db_install_dir}/bin/mysql -uroot -e "quit" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
      break
    else
      # 非交互（--db <版本>）时不能进交互重试：stdin 是 EOF，read 立刻返回空，
      # 空密码必然连不上，于是这个 while 会无限刷下去。直接失败更安全。
      if [ "${db_flag}" == 'y' ]; then
        echo "${CFAILURE}options.conf 里的 dbrootpwd 连不上数据库；非交互模式无法交互输入密码，已退出${CEND}"
        exit 1
      fi
      echo
      read -e -p "Please input the root password of database: " NEW_dbrootpwd
      MYSQL_PWD="${NEW_dbrootpwd}" ${db_install_dir}/bin/mysql -uroot -e "quit" >/dev/null 2>&1
      if [ $? -eq 0 ]; then
        dbrootpwd=${NEW_dbrootpwd}
        set_conf_var dbrootpwd "${dbrootpwd}" ../options.conf
        break
      else
        echo "${CFAILURE}${DB} root password incorrect,Please enter again! ${CEND}"
      fi
    fi
  done

  OLD_db_ver_tmp=`${db_install_dir}/bin/mysql -uroot -e 'select version()\G;' | grep version | awk '{print $2}'`
  if [ -n "`${db_install_dir}/bin/mysql -V | grep -o MariaDB`" ]; then
    DOWN_ADDR=${mirror_link}/src
    DB=MariaDB
    OLD_db_ver=`echo ${OLD_db_ver_tmp} | awk -F'-' '{print $1}'`
  elif [ -n "`${db_install_dir}/bin/mysql -V | grep -o Percona`" ]; then
    DB=Percona
    OLD_db_ver=${OLD_db_ver_tmp}
  else
    DOWN_ADDR=${mirror_link}/src
    DB=MySQL
    OLD_db_ver=${OLD_db_ver_tmp%%-log}
  fi

  # 非交互给了「当前版本」：不必先 dump 整库
  if [ "${db_flag}" == 'y' ] && [ -n "${NEW_db_ver}" ] && [ "${NEW_db_ver}" == "${OLD_db_ver}" ]; then
    echo "${CWARNING}input error! Upgrade ${DB} version is the same as the old version${CEND}"
    exit 1
  fi

  #backup
  echo
  echo "${CSUCCESS}Starting ${DB} backup${CEND}......"
  # 备份文件名固定成变量：跨零点时 $(date) 会变，后续恢复就可能读到另一个文件
  DB_dump_file=DB_all_backup_$(date +"%Y%m%d").sql
  ${db_install_dir}/bin/mysqldump -uroot --opt --all-databases > ${DB_dump_file}
  # 只判断「文件存在」不够：mysqldump 出错时文件照样存在（可能是空文件或半截）
  # 这里必须在动 datadir
  if [ $? -ne 0 ] || [ ! -s "${DB_dump_file}" ] || ! grep -q 'CREATE DATABASE' "${DB_dump_file}"; then
    echo "${CFAILURE}${DB} backup failed, abort before touching data dir.${CEND}"
    exit 1
  fi
  echo "${DB} backup success, Backup file: ${MSG}`pwd`/${DB_dump_file}${CEND}"

  #upgrade
  echo
  echo "Current ${DB} Version: ${CMSG}${OLD_db_ver}${CEND}"
  while :; do echo
    [ "${db_flag}" != 'y' ] && read -e -p "Please input upgrade ${DB} Version(example: ${OLD_db_ver}): " NEW_db_ver
    # 同版本没有「升级」可言
    # 重新下载重装一次，最后打印 "successfully upgrade from 8.4.11 to 8.4.11"
    if [ "${NEW_db_ver}" == "${OLD_db_ver}" ]; then
      echo "${CWARNING}input error! Upgrade ${DB} version is the same as the old version${CEND}"
      [ "${db_flag}" == 'y' ] && exit 1
      continue
    fi
    if [ `echo ${NEW_db_ver} | awk -F. '{print $1"."$2}'` == `echo ${OLD_db_ver} | awk -F. '{print $1"."$2}'` ]; then
      if [ "${DB}" == 'MariaDB' ]; then
        DB_filename=mariadb-${NEW_db_ver}-linux-systemd-x86_64
        DB_URL=${DOWN_ADDR}/${DB_filename}.tar.gz
      elif [ "${DB}" == 'Percona' ]; then
        # Percona 只收录 8.0（-rel 后缀是 5.5/5.6 时代的包名，5.7/ssl102 档位随之不再需要）
        DB_filename=Percona-Server-${NEW_db_ver}-Linux.x86_64.glibc2.28
        DB_URL=${DOWN_ADDR}/${DB_filename}.tar.gz
      elif [ "${DB}" == 'MySQL' ]; then
        # 包名按目标版本定：8.0/8.4 官方只发 glibc2.28 构建（.tar.xz），5.7 是 glibc2.12（.tar.gz）
        if [[ "${NEW_db_ver}" =~ ^8\. ]]; then
          DB_filename=mysql-${NEW_db_ver}-linux-glibc2.28-x86_64
          DB_URL=${DOWN_ADDR}/${DB_filename}.tar.xz
        elif [[ "${NEW_db_ver}" =~ ^5\.7\. ]]; then
          DB_filename=mysql-${NEW_db_ver}-linux-glibc2.12-x86_64
          DB_URL=${DOWN_ADDR}/${DB_filename}.tar.gz
        fi
      fi
      [ ! -e "`ls ${DB_filename}.tar.?z 2>/dev/null`" ] && wget -c ${DB_URL} > /dev/null 2>&1
      if [ -e "`ls ${DB_filename}.tar.?z 2>/dev/null`" ]; then
        echo "Download [${CMSG}`ls ${DB_filename}.tar.?z 2>/dev/null`${CEND}] successfully! "
      else
        echo "${CWARNING}${DB} version does not exist! ${CEND}"
        # 包没下到还继续往下走，会拿不到 tar 包、数据目录却被 mv 掉；这里直接失败
        echo "${CFAILURE}${DB} ${NEW_db_ver} 取不到，已中止，数据未改动${CEND}"
        echo "${CWARNING}Lemon 的升级包只从镜像站取（${mirror_link}/src），没有的版本不会去官方源拉。"
        echo "需要升到该版本时：把 ${DB_filename}.tar.?z 放到 ${lemon_dir}/src/ 下再重跑本命令。${CEND}"
        exit 1
      fi
      break
    else
      echo "${CWARNING}input error! ${CEND}Please only input '${CMSG}${OLD_db_ver%.*}.xx${CEND}'"
      [ "${db_flag}" == 'y' ] && exit 1
    fi
  done

  if [ -e "`ls ${DB_filename}.tar.?z 2>/dev/null`" ]; then
    echo "[${CMSG}`ls ${DB_filename}.tar.?z 2>/dev/null`${CEND}] found"
    if [ "${db_flag}" != 'y' ]; then
      echo "Press Ctrl+c to cancel or Press any key to continue..."
      char=`get_char`
    fi
    if [ "${DB}" == 'MariaDB' ]; then
      tar xzf ${DB_filename}.tar.gz
      service mysqld stop
      _stamp=`date +"%Y%m%d_%H%M%S"`
      mv ${mariadb_install_dir}{,_old_${_stamp}}
      mv ${mariadb_data_dir}{,_old_${_stamp}}
      [ ! -d "${mariadb_install_dir}" ] && mkdir -p ${mariadb_install_dir}
      mkdir -p ${mariadb_data_dir};chown mysql:mysql -R ${mariadb_data_dir}
      mv ${DB_filename}/* ${mariadb_install_dir}/
      sed -i 's@executing mysqld_safe@executing mysqld_safe\nexport LD_PRELOAD=/usr/local/lib/libjemalloc.so@' ${mariadb_install_dir}/bin/mysqld_safe
      ${mariadb_install_dir}/scripts/mysql_install_db --user=mysql --basedir=${mariadb_install_dir} --datadir=${mariadb_data_dir}
      chown mysql:mysql -R ${mariadb_data_dir}
      service mysqld start
      # 导入必须判失败
      # 失败时线上就是一个空库，日志却说成功。
      if ! ${mariadb_install_dir}/bin/mysql < ${DB_dump_file}; then
        echo "${CFAILURE}导入备份失败，开始自动回滚${CEND}"
        echo "${CWARNING}备份文件：$(pwd)/${DB_dump_file}${CEND}"
        DB_Rollback "${mariadb_install_dir}" "${mariadb_data_dir}" "${_stamp}" mysqld
        exit 1
      fi
      service mysqld restart
      ${mariadb_install_dir}/bin/mysql -uroot -e "drop database test;" >/dev/null 2>&1
      ${mariadb_install_dir}/bin/mysql -uroot -e "reset master;" >/dev/null 2>&1
      ${mariadb_install_dir}/bin/mysql_upgrade -uroot >/dev/null 2>&1
      [ $? -eq 0 ] &&  echo "You have ${CMSG}successfully${CEND} upgrade from ${CMSG}${OLD_db_ver}${CEND} to ${CMSG}${NEW_db_ver}${CEND}"
    elif [ "${DB}" == 'Percona' ]; then
      tar xzf ${DB_filename}.tar.gz
      service mysqld stop
      _stamp=`date +"%Y%m%d_%H%M%S"`
      mv ${percona_install_dir}{,_old_${_stamp}}
      mv ${percona_data_dir}{,_old_${_stamp}}
      [ ! -d "${percona_install_dir}" ] && mkdir -p ${percona_install_dir}
      mkdir -p ${percona_data_dir};chown mysql:mysql -R ${percona_data_dir}
      mv ${DB_filename}/* ${percona_install_dir}/
      sed -i 's@executing mysqld_safe@executing mysqld_safe\nexport LD_PRELOAD=/usr/local/lib/libjemalloc.so@' ${percona_install_dir}/bin/mysqld_safe
      sed -i "s@/usr/local/${DB_filename}@${percona_install_dir}@g" ${percona_install_dir}/bin/mysqld_safe
      ${percona_install_dir}/bin/mysqld --initialize-insecure --user=mysql --basedir=${percona_install_dir} --datadir=${percona_data_dir}
      chown mysql:mysql -R ${percona_data_dir}
      service mysqld start
      # 导入必须判失败
      # 失败时线上就是一个空库，日志却说成功。
      if ! ${percona_install_dir}/bin/mysql < ${DB_dump_file}; then
        echo "${CFAILURE}导入备份失败，开始自动回滚${CEND}"
        echo "${CWARNING}备份文件：$(pwd)/${DB_dump_file}${CEND}"
        DB_Rollback "${percona_install_dir}" "${percona_data_dir}" "${_stamp}" mysqld
        exit 1
      fi
      service mysqld restart
      ${percona_install_dir}/bin/mysql -uroot -e "drop database test;" >/dev/null 2>&1
      ${percona_install_dir}/bin/mysql -uroot -e "reset master;" >/dev/null 2>&1
      ${percona_install_dir}/bin/mysql_upgrade -uroot >/dev/null 2>&1
      [ $? -eq 0 ] &&  echo "You have ${CMSG}successfully${CEND} upgrade from ${CMSG}${OLD_db_ver}${CEND} to ${CMSG}${NEW_db_ver}${CEND}"
    elif [ "${DB}" == 'MySQL' ]; then
      if [[ "${NEW_db_ver}" =~ ^8\. ]]; then
        tar xJf ${DB_filename}.tar.xz
      else
        tar xzf ${DB_filename}.tar.gz
      fi
      service mysqld stop
      _stamp=`date +"%Y%m%d_%H%M%S"`
      mv ${mysql_install_dir}{,_old_${_stamp}}
      mv ${mysql_data_dir}{,_old_${_stamp}}
      [ ! -d "${mysql_install_dir}" ] && mkdir -p ${mysql_install_dir}
      mkdir -p ${mysql_data_dir};chown mysql:mysql -R ${mysql_data_dir}
      mv ${DB_filename}/* ${mysql_install_dir}/
      sed -i 's@executing mysqld_safe@executing mysqld_safe\nexport LD_PRELOAD=/usr/local/lib/libjemalloc.so@' ${mysql_install_dir}/bin/mysqld_safe
      sed -i "s@/usr/local/mysql@${mysql_install_dir}@g" ${mysql_install_dir}/bin/mysqld_safe
      ${mysql_install_dir}/bin/mysqld --initialize-insecure --user=mysql --basedir=${mysql_install_dir} --datadir=${mysql_data_dir}

      chown mysql:mysql -R ${mysql_data_dir}
      [ -e "${mysql_install_dir}/my.cnf" ] && rm -rf ${mysql_install_dir}/my.cnf
      sed -i '/myisam_repair_threads/d' /etc/my.cnf
      service mysqld start
      # 导入必须判失败
      # 失败时线上就是一个空库，日志却说成功。
      if ! ${mysql_install_dir}/bin/mysql < ${DB_dump_file}; then
        echo "${CFAILURE}导入备份失败，开始自动回滚${CEND}"
        echo "${CWARNING}备份文件：$(pwd)/${DB_dump_file}${CEND}"
        DB_Rollback "${mysql_install_dir}" "${mysql_data_dir}" "${_stamp}" mysqld
        exit 1
      fi
      service mysqld restart
      ${mysql_install_dir}/bin/mysql -uroot -e "drop database test;" >/dev/null 2>&1
      ${mysql_install_dir}/bin/mysql -uroot -e "reset master;" >/dev/null 2>&1
      # MySQL 8.0.16 起 mysql_upgrade 已内置进 server，8.4 更是直接没有这个二进制；
      # 无条件调用再判 $? 不行：8.4 没有这个二进制，升级成功也永远不打印成功信息（看起来像失败）。
      if [ -x "${mysql_install_dir}/bin/mysql_upgrade" ]; then
        ${mysql_install_dir}/bin/mysql_upgrade -uroot >/dev/null 2>&1
      fi
      echo "You have ${CMSG}successfully${CEND} upgrade from ${CMSG}${OLD_db_ver}${CEND} to ${CMSG}${NEW_db_ver}${CEND}"
    fi
  fi
}
