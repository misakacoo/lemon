#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Upgrade_DB() {
  pushd ${lemon_dir}/src > /dev/null
  [ ! -e "${db_install_dir}/bin/mysql" ] && echo "${CWARNING}MySQL/MariaDB/Percona is not installed on your system! ${CEND}" && exit 1

  # check db passwd
  while :; do
    ${db_install_dir}/bin/mysql -uroot --password="${dbrootpwd}" -e "quit" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
      break
    else
      echo
      read -e -p "Please input the root password of database: " NEW_dbrootpwd
      ${db_install_dir}/bin/mysql -uroot -p${NEW_dbrootpwd} -e "quit" >/dev/null 2>&1
      if [ $? -eq 0 ]; then
        dbrootpwd=${NEW_dbrootpwd}
        set_conf_var dbrootpwd "${dbrootpwd}" ../options.conf
        break
      else
        echo "${CFAILURE}${DB} root password incorrect,Please enter again! ${CEND}"
      fi
    fi
  done

  OLD_db_ver_tmp=`${db_install_dir}/bin/mysql -uroot --password="${dbrootpwd}" -e 'select version()\G;' | grep version | awk '{print $2}'`
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

  #backup
  echo
  echo "${CSUCCESS}Starting ${DB} backup${CEND}......"
  # 备份文件名固定成变量：跨零点时 $(date) 会变，后续恢复就可能读到另一个文件
  DB_dump_file=DB_all_backup_$(date +"%Y%m%d").sql
  ${db_install_dir}/bin/mysqldump -uroot --password="${dbrootpwd}" --opt --all-databases > ${DB_dump_file}
  # 只判断「文件存在」不够：mysqldump 出错时文件照样存在（可能是空文件或半截）
  # 这里必须在动 datadir 之前拦住，否则旧库已被 mv 走、新库是空的
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
      [ "${db_flag}" == 'y' ] && exit
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
      mv ${mariadb_install_dir}{,_old_`date +"%Y%m%d_%H%M%S"`}
      mv ${mariadb_data_dir}{,_old_`date +"%Y%m%d_%H%M%S"`}
      [ ! -d "${mariadb_install_dir}" ] && mkdir -p ${mariadb_install_dir}
      mkdir -p ${mariadb_data_dir};chown mysql:mysql -R ${mariadb_data_dir}
      mv ${DB_filename}/* ${mariadb_install_dir}/
      sed -i 's@executing mysqld_safe@executing mysqld_safe\nexport LD_PRELOAD=/usr/local/lib/libjemalloc.so@' ${mariadb_install_dir}/bin/mysqld_safe
      ${mariadb_install_dir}/scripts/mysql_install_db --user=mysql --basedir=${mariadb_install_dir} --datadir=${mariadb_data_dir}
      chown mysql:mysql -R ${mariadb_data_dir}
      service mysqld start
      ${mariadb_install_dir}/bin/mysql < ${DB_dump_file}
      service mysqld restart
      ${mariadb_install_dir}/bin/mysql -uroot --password="${dbrootpwd}" -e "drop database test;" >/dev/null 2>&1
      ${mariadb_install_dir}/bin/mysql -uroot --password="${dbrootpwd}" -e "reset master;" >/dev/null 2>&1
      ${mariadb_install_dir}/bin/mysql_upgrade -uroot --password="${dbrootpwd}" >/dev/null 2>&1
      [ $? -eq 0 ] &&  echo "You have ${CMSG}successfully${CEND} upgrade from ${CMSG}${OLD_db_ver}${CEND} to ${CMSG}${NEW_db_ver}${CEND}"
    elif [ "${DB}" == 'Percona' ]; then
      tar xzf ${DB_filename}.tar.gz
      service mysqld stop
      mv ${percona_install_dir}{,_old_`date +"%Y%m%d_%H%M%S"`}
      mv ${percona_data_dir}{,_old_`date +"%Y%m%d_%H%M%S"`}
      [ ! -d "${percona_install_dir}" ] && mkdir -p ${percona_install_dir}
      mkdir -p ${percona_data_dir};chown mysql:mysql -R ${percona_data_dir}
      mv ${DB_filename}/* ${percona_install_dir}/
      sed -i 's@executing mysqld_safe@executing mysqld_safe\nexport LD_PRELOAD=/usr/local/lib/libjemalloc.so@' ${percona_install_dir}/bin/mysqld_safe
      sed -i "s@/usr/local/${DB_filename}@${percona_install_dir}@g" ${percona_install_dir}/bin/mysqld_safe
      ${percona_install_dir}/bin/mysqld --initialize-insecure --user=mysql --basedir=${percona_install_dir} --datadir=${percona_data_dir}
      chown mysql:mysql -R ${percona_data_dir}
      service mysqld start
      ${percona_install_dir}/bin/mysql < ${DB_dump_file}
      service mysqld restart
      ${percona_install_dir}/bin/mysql -uroot --password="${dbrootpwd}" -e "drop database test;" >/dev/null 2>&1
      ${percona_install_dir}/bin/mysql -uroot --password="${dbrootpwd}" -e "reset master;" >/dev/null 2>&1
      ${percona_install_dir}/bin/mysql_upgrade -uroot --password="${dbrootpwd}" >/dev/null 2>&1
      [ $? -eq 0 ] &&  echo "You have ${CMSG}successfully${CEND} upgrade from ${CMSG}${OLD_db_ver}${CEND} to ${CMSG}${NEW_db_ver}${CEND}"
    elif [ "${DB}" == 'MySQL' ]; then
      if [[ "${NEW_db_ver}" =~ ^8\. ]]; then
        tar xJf ${DB_filename}.tar.xz
      else
        tar xzf ${DB_filename}.tar.gz
      fi
      service mysqld stop
      mv ${mysql_install_dir}{,_old_`date +"%Y%m%d_%H%M%S"`}
      mv ${mysql_data_dir}{,_old_`date +"%Y%m%d_%H%M%S"`}
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
      ${mysql_install_dir}/bin/mysql < ${DB_dump_file}
      service mysqld restart
      ${mysql_install_dir}/bin/mysql -uroot --password="${dbrootpwd}" -e "drop database test;" >/dev/null 2>&1
      ${mysql_install_dir}/bin/mysql -uroot --password="${dbrootpwd}" -e "reset master;" >/dev/null 2>&1
      # MySQL 8.0.16 起 mysql_upgrade 已内置进 server，8.4 更是直接没有这个二进制；
      # 原来无条件调用再判 $?，导致 8.4 升级成功也永远不打印成功信息（看起来像失败）。
      if [ -x "${mysql_install_dir}/bin/mysql_upgrade" ]; then
        ${mysql_install_dir}/bin/mysql_upgrade -uroot --password="${dbrootpwd}" >/dev/null 2>&1
      fi
      echo "You have ${CMSG}successfully${CEND} upgrade from ${CMSG}${OLD_db_ver}${CEND} to ${CMSG}${NEW_db_ver}${CEND}"
    fi
  fi
}
