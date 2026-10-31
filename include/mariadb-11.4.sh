#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Install_MariaDB114() {
  pushd ${lemon_dir}/src > /dev/null
  id -u mysql >/dev/null 2>&1
  [ $? -ne 0 ] && useradd -M -s /sbin/nologin mysql

  [ ! -d "${mariadb_install_dir}" ] && mkdir -p ${mariadb_install_dir}
  mkdir -p ${mariadb_data_dir};chown mysql.mysql -R ${mariadb_data_dir}

  if [ "${dbinstallmethod}" == "1" ]; then
    tar zxf mariadb-${mariadb114_ver}-linux-systemd-x86_64.tar.gz
    mv mariadb-${mariadb114_ver}-linux-systemd-x86_64/* ${mariadb_install_dir}
    sed -i 's@executing mysqld_safe@executing mysqld_safe\nexport LD_PRELOAD=/usr/local/lib/libjemalloc.so@' ${mariadb_install_dir}/bin/mariadbd-safe 2>/dev/null
    sed -i "s@/usr/local/mysql@${mariadb_install_dir}@g" ${mariadb_install_dir}/bin/mariadbd-safe 2>/dev/null
  elif [ "${dbinstallmethod}" == "2" ]; then
    tar xzf mariadb-${mariadb114_ver}.tar.gz
    pushd mariadb-${mariadb114_ver}
    # MariaDB 11.x 把存储引擎全部换成插件形式（-DPLUGIN_xxx），老参数会直接报错；
    # embedded server 与 query cache 已在 11.0 移除，不能再传
    cmake . -DCMAKE_INSTALL_PREFIX=${mariadb_install_dir} \
    -DMYSQL_DATADIR=${mariadb_data_dir} \
    -DSYSCONFDIR=/etc \
    -DPLUGIN_INNOBASE=STATIC \
    -DPLUGIN_PARTITION=STATIC \
    -DPLUGIN_FEDERATED=STATIC \
    -DPLUGIN_BLACKHOLE=STATIC \
    -DPLUGIN_MYISAM=STATIC \
    -DENABLE_DTRACE=0 \
    -DENABLED_LOCAL_INFILE=1 \
    -DDEFAULT_CHARSET=utf8mb4 \
    -DDEFAULT_COLLATION=utf8mb4_general_ci \
    -DEXTRA_CHARSETS=all \
    -DCMAKE_EXE_LINKER_FLAGS='-ljemalloc'
    make -j ${THREAD}
    make install
    popd
  fi

  if [ -d "${mariadb_install_dir}/support-files" ]; then
    set_conf_var dbrootpwd "${dbrootpwd}" ../options.conf
    echo "${CSUCCESS}MariaDB installed successfully! ${CEND}"
    if [ "${dbinstallmethod}" == "1" ]; then
      rm -rf mariadb-${mariadb114_ver}-linux-systemd-x86_64
    elif [ "${dbinstallmethod}" == "2" ]; then
      rm -rf mariadb-${mariadb114_ver}
    fi
  else
    rm -rf ${mariadb_install_dir}
    echo "${CFAILURE}MariaDB install failed, Please contact the author! ${CEND}" && grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
    exit 1;
  fi

  /bin/cp ${mariadb_install_dir}/support-files/mysql.server /etc/init.d/mysqld
  sed -i "s@^basedir=.*@basedir=${mariadb_install_dir}@" /etc/init.d/mysqld
  sed -i "s@^datadir=.*@datadir=${mariadb_data_dir}@" /etc/init.d/mysqld
  chmod +x /etc/init.d/mysqld
  update-rc.d mysqld defaults
  popd

  # my.cnf
  # 注意：MariaDB 11.x 已移除 query cache（query_cache_* 会导致启动失败）、
  # performance_schema 是 MySQL 侧参数、expire_logs_days 换成 binlog_expire_logs_seconds
  cat > /etc/my.cnf << EOF
[client]
port = 3306
socket = /tmp/mysql.sock
default-character-set = utf8mb4

[mysqld]
port = 3306
socket = /tmp/mysql.sock

basedir = ${mariadb_install_dir}
datadir = ${mariadb_data_dir}
pid-file = ${mariadb_data_dir}/mysql.pid
user = mysql
bind-address = 0.0.0.0
server-id = 1

init-connect = 'SET NAMES utf8mb4'
character-set-server = utf8mb4

skip-name-resolve
#skip-networking
back_log = 300

max_connections = 1000
max_connect_errors = 6000
open_files_limit = 65535
table_open_cache = 128
max_allowed_packet = 500M
binlog_cache_size = 1M
max_heap_table_size = 8M
tmp_table_size = 16M

read_buffer_size = 2M
read_rnd_buffer_size = 8M
sort_buffer_size = 8M
join_buffer_size = 8M
key_buffer_size = 4M

thread_cache_size = 8

ft_min_word_len = 4

log_bin = mysql-bin
binlog_format = mixed
binlog_expire_logs_seconds = 604800

log_error = ${mariadb_data_dir}/mysql-error.log
slow_query_log = 1
long_query_time = 1
slow_query_log_file = ${mariadb_data_dir}/mysql-slow.log

#lower_case_table_names = 1

default_storage_engine = InnoDB
innodb_file_per_table = 1
innodb_open_files = 500
innodb_buffer_pool_size = 64M
innodb_write_io_threads = 4
innodb_read_io_threads = 4
innodb_purge_threads = 1
innodb_flush_log_at_trx_commit = 2
innodb_log_buffer_size = 2M
innodb_log_file_size = 32M
innodb_max_dirty_pages_pct = 90
innodb_lock_wait_timeout = 120

bulk_insert_buffer_size = 8M
myisam_sort_buffer_size = 8M
myisam_max_sort_file_size = 10G

interactive_timeout = 28800
wait_timeout = 28800

[mysqldump]
quick
max_allowed_packet = 500M

[myisamchk]
key_buffer_size = 8M
sort_buffer_size = 8M
read_buffer = 4M
write_buffer = 4M
EOF

  sed -i "s@max_connections.*@max_connections = $((${Mem}/3))@" /etc/my.cnf
  if [ ${Mem} -gt 1500 -a ${Mem} -le 2500 ]; then
    sed -i 's@^thread_cache_size.*@thread_cache_size = 16@' /etc/my.cnf
    sed -i 's@^myisam_sort_buffer_size.*@myisam_sort_buffer_size = 16M@' /etc/my.cnf
    sed -i 's@^key_buffer_size.*@key_buffer_size = 16M@' /etc/my.cnf
    sed -i 's@^innodb_buffer_pool_size.*@innodb_buffer_pool_size = 128M@' /etc/my.cnf
    sed -i 's@^tmp_table_size.*@tmp_table_size = 32M@' /etc/my.cnf
    sed -i 's@^table_open_cache.*@table_open_cache = 256@' /etc/my.cnf
  elif [ ${Mem} -gt 2500 -a ${Mem} -le 3500 ]; then
    sed -i 's@^thread_cache_size.*@thread_cache_size = 32@' /etc/my.cnf
    sed -i 's@^myisam_sort_buffer_size.*@myisam_sort_buffer_size = 32M@' /etc/my.cnf
    sed -i 's@^key_buffer_size.*@key_buffer_size = 64M@' /etc/my.cnf
    sed -i 's@^innodb_buffer_pool_size.*@innodb_buffer_pool_size = 512M@' /etc/my.cnf
    sed -i 's@^tmp_table_size.*@tmp_table_size = 64M@' /etc/my.cnf
    sed -i 's@^table_open_cache.*@table_open_cache = 512@' /etc/my.cnf
  elif [ ${Mem} -gt 3500 ]; then
    sed -i 's@^thread_cache_size.*@thread_cache_size = 64@' /etc/my.cnf
    sed -i 's@^myisam_sort_buffer_size.*@myisam_sort_buffer_size = 64M@' /etc/my.cnf
    sed -i 's@^key_buffer_size.*@key_buffer_size = 256M@' /etc/my.cnf
    sed -i 's@^innodb_buffer_pool_size.*@innodb_buffer_pool_size = 1024M@' /etc/my.cnf
    sed -i 's@^tmp_table_size.*@tmp_table_size = 128M@' /etc/my.cnf
    sed -i 's@^table_open_cache.*@table_open_cache = 1024@' /etc/my.cnf
  fi

  # 11.x 起初始化工具是 mariadb-install-db（mysql_install_db 仍保留为兼容 symlink）
  ${mariadb_install_dir}/scripts/mariadb-install-db --user=mysql --basedir=${mariadb_install_dir} --datadir=${mariadb_data_dir}

  [ "${Wsl}" == true ] && chmod 600 /etc/my.cnf
  chown mysql.mysql -R ${mariadb_data_dir}
  [ -d "/etc/mysql" ] && /bin/mv /etc/mysql{,_bk}
  service mysqld start
  [ -z "$(grep ^'export PATH=' /etc/profile)" ] && echo "export PATH=${mariadb_install_dir}/bin:\$PATH" >> /etc/profile
  [ -n "$(grep ^'export PATH=' /etc/profile)" -a -z "$(grep ${mariadb_install_dir} /etc/profile)" ] && sed -i "s@^export PATH=\(.*\)@export PATH=${mariadb_install_dir}/bin:\1@" /etc/profile
  . /etc/profile

  ${mariadb_install_dir}/bin/mysql -e "grant all privileges on *.* to root@'127.0.0.1' identified by '$(esc_sql "${dbrootpwd}")' with grant option;"
  ${mariadb_install_dir}/bin/mysql -e "grant all privileges on *.* to root@'localhost' identified by '$(esc_sql "${dbrootpwd}")' with grant option;"
  ${mariadb_install_dir}/bin/mysql -uroot --password="${dbrootpwd}" -e "delete from mysql.user where Password='' and User not like 'mariadb.%';"
  ${mariadb_install_dir}/bin/mysql -uroot --password="${dbrootpwd}" -e "delete from mysql.db where User='';"
  ${mariadb_install_dir}/bin/mysql -uroot --password="${dbrootpwd}" -e "delete from mysql.proxies_priv where Host!='localhost';"
  ${mariadb_install_dir}/bin/mysql -uroot --password="${dbrootpwd}" -e "drop database test;"
  ${mariadb_install_dir}/bin/mysql -uroot --password="${dbrootpwd}" -e "reset master;"
  rm -rf /etc/ld.so.conf.d/{mysql,mariadb,percona}*.conf
  echo "${mariadb_install_dir}/lib" > /etc/ld.so.conf.d/z-mariadb.conf
  ldconfig
  service mysqld stop
}
