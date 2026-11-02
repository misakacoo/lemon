#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Install_PostgreSQL() {
  pushd ${lemon_dir}/src > /dev/null
  id -u postgres >/dev/null 2>&1
  [ $? -ne 0 ] && useradd -d ${pgsql_install_dir} -s /bin/bash postgres
  mkdir -p ${pgsql_data_dir};chown postgres.postgres -R ${pgsql_data_dir}
  tar xzf postgresql-${pgsql_ver}.tar.gz
  pushd postgresql-${pgsql_ver}
  ./configure --prefix=$pgsql_install_dir
  make -j ${THREAD}
  make install
  chmod 755 ${pgsql_install_dir}
  chown -R postgres.postgres ${pgsql_install_dir}
  /bin/cp ${lemon_dir}/init.d/postgresql.service /lib/systemd/system/
  sed -i "s@=/usr/local/pgsql@=${pgsql_install_dir}@g" /lib/systemd/system/postgresql.service
  sed -i "s@PGDATA=.*@PGDATA=${pgsql_data_dir}@" /lib/systemd/system/postgresql.service
  systemctl enable postgresql
  popd
  su - postgres -c "${pgsql_install_dir}/bin/initdb -D ${pgsql_data_dir}"
  systemctl start postgresql
  sleep 5
  # 密码写进临时 SQL 文件再执行：直接用 su -c 双引号拼接，遇到 ' 要么语法错、
  # 要么在 root shell 里被展开（$() 会真的执行）
  pgsql_pw_sql="alter user postgres with password '${dbpostgrespwd//\'/\'\'}';"
  # mktemp：固定名 /tmp/.lemon-pg-pw.sql 可被本地用户预置成符号链接，root 的 > 会写到链接目标
  _pg_pw_sql=$(mktemp) || _pg_pw_sql=''
  if [ -z "${_pg_pw_sql}" ]; then
    echo "${CFAILURE}创建临时文件失败，无法设置 postgres 密码${CEND}"; return 1
  fi
  printf '%s\n' "${pgsql_pw_sql}" > "${_pg_pw_sql}"
  chown postgres:postgres "${_pg_pw_sql}"
  chmod 600 "${_pg_pw_sql}"
  su - postgres -c "${pgsql_install_dir}/bin/psql -f ${_pg_pw_sql}"
  rm -f "${_pg_pw_sql}"
  sed -i 's@^host.*@#&@g' ${pgsql_data_dir}/pg_hba.conf
  sed -i 's@^local.*@#&@g' ${pgsql_data_dir}/pg_hba.conf
  echo 'local   all             all                                     scram-sha-256' >> ${pgsql_data_dir}/pg_hba.conf
  echo 'host    all             all             0.0.0.0/0               scram-sha-256' >> ${pgsql_data_dir}/pg_hba.conf
  sed -i "s@^#listen_addresses.*@listen_addresses = 'localhost'@" ${pgsql_data_dir}/postgresql.conf
  # listen_addresses 是 postmaster 级参数，reload 不生效，必须重启才会开始监听外部地址
  systemctl restart postgresql

  if [ -e "${pgsql_install_dir}/bin/psql" ]; then
    set_conf_var dbpostgrespwd "${dbpostgrespwd}" ../options.conf
    # 清理解压出来的源码树（PostgreSQL 源码树 100M+，编译完就没用了）；tar 包保留作缓存
    rm -rf postgresql-${pgsql_ver}
    echo "${CSUCCESS}PostgreSQL installed successfully! ${CEND}"
  else
    # 只删安装目录，数据目录保留（失败一次就清空数据目录等于删库）
    rm -rf ${pgsql_install_dir}
    echo "${CFAILURE}PostgreSQL install failed, Please contact the author! ${CEND}" && grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
    exit 1;
  fi
  popd
  [ -z "$(grep ^'export PATH=' /etc/profile)" ] && echo "export PATH=${pgsql_install_dir}/bin:\$PATH" >> /etc/profile
  [ -n "$(grep ^'export PATH=' /etc/profile)" -a -z "$(grep ${pgsql_install_dir} /etc/profile)" ] && sed -i "s@^export PATH=\(.*\)@export PATH=${pgsql_install_dir}/bin:\1@" /etc/profile
  . /etc/profile
}
