#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Install_MongoDB() {
  pushd ${lemon_dir}/src > /dev/null
  # 正常由 check_download.sh 赋值；单独调用本函数时按版本号兜底匹配
  [ -z "${MONGODB_TARBALL}" ] && MONGODB_TARBALL=$(ls mongodb-linux-${ARCH}-*-${mongodb_ver}.tgz 2>/dev/null | head -1)
  if [ ! -f "${MONGODB_TARBALL}" ]; then
    echo "${CFAILURE}MongoDB package not found, please run the download step first! ${CEND}"
    exit 1;
  fi

  id -u mongod >/dev/null 2>&1
  [ $? -ne 0 ] && useradd -s /sbin/nologin mongod
  mkdir -p ${mongo_data_dir}
  chown -R mongod:mongod ${mongo_data_dir}

  # 5.0 起官方二进制包按发行版命名，解包后的顶层目录与包名一致
  tar xzf ${MONGODB_TARBALL}
  /bin/mv ${MONGODB_TARBALL%.tgz} ${mongo_install_dir}

  # mongosh 放进同一个 bin 目录，/etc/profile 里的 PATH 可直接命中
  tar xzf mongosh-${mongosh_ver}-linux-${SYS_ARCH_n}.tgz
  /bin/cp mongosh-${mongosh_ver}-linux-${SYS_ARCH_n}/bin/mongosh ${mongo_install_dir}/bin/mongosh
  chmod 755 ${mongo_install_dir}/bin/mongosh

  /bin/cp ${lemon_dir}/init.d/mongod.service /lib/systemd/system/
  sed -i "s@=/usr/local/mongodb@=${mongo_install_dir}@g" /lib/systemd/system/mongod.service
  systemctl daemon-reload
  systemctl enable mongod

  cat > /etc/mongod.conf << EOF
# mongod.conf

# for documentation of all options, see:
#   https://www.mongodb.com/docs/manual/reference/configuration-options/

# where to write logging data.
systemLog:
  destination: file
  logAppend: true
  path: ${mongo_data_dir}/mongod.log

# Where and how to store data.
storage:
  dbPath: ${mongo_data_dir}
#  engine: wiredTiger
#  wiredTiger:

# how the process runs
processManagement:
  fork: true  # fork and run in background
  pidFilePath: /var/run/mongodb/mongod.pid

# network interfaces
net:
  port: 27017
  bindIp: 127.0.0.1
  unixDomainSocket:
    enabled: false

#security:
#  authorization: enabled

#operationProfiling:
#replication:
#sharding:
EOF

  # 首次启动只监听回环：在创建 root 账号之前，不要把无鉴权的实例暴露到公网
  systemctl start mongod
  MongoDB_Ready=n
  for i in $(seq 1 30); do
    if ${mongo_install_dir}/bin/mongosh --host 127.0.0.1 --port 27017 --quiet \
         --eval 'db.runCommand({ping:1}).ok' 2>/dev/null | grep -q 1; then
      MongoDB_Ready=y && break
    fi
    sleep 1
  done

  [ "${MongoDB_Ready}" == 'y' ] && {
    # 密码可能带引号或反斜杠，写进 JS 之前先转义，避免 JSON 被截断
    mongo_pwd_escaped=$(printf '%s' "${dbmongopwd}" | sed -e 's/[\\"]/\\&/g')
    cat > ${lemon_dir}/src/mongo_init.js << EOF
db.getSiblingDB("admin").createUser({user:"root",pwd:"${mongo_pwd_escaped}",roles:["root"]})
EOF
    ${mongo_install_dir}/bin/mongosh --host 127.0.0.1 --port 27017 --quiet \
      ${lemon_dir}/src/mongo_init.js > /dev/null 2>&1
    rm -f ${lemon_dir}/src/mongo_init.js
  }

  # 开启鉴权并恢复对外监听，必须重启才生效（旧版脚本只改配置不重启，装完实际是免密状态）
  sed -i 's@^#security:@security:@' /etc/mongod.conf
  sed -i 's@^#  authorization:@  authorization:@' /etc/mongod.conf
  sed -i 's@^  bindIp:.*@  bindIp: 0.0.0.0@' /etc/mongod.conf
  systemctl restart mongod

  MongoDB_Auth=n
  for i in $(seq 1 30); do
    if ${mongo_install_dir}/bin/mongosh --host 127.0.0.1 --port 27017 -u root \
         -p "${dbmongopwd}" --authenticationDatabase admin --quiet \
         --eval 'db.runCommand({ping:1}).ok' 2>/dev/null | grep -q 1; then
      MongoDB_Auth=y && break
    fi
    sleep 1
  done

  if [ -e "${mongo_install_dir}/bin/mongod" ] && [ "${MongoDB_Auth}" == 'y' ]; then
    set_conf_var dbmongopwd "${dbmongopwd}" ../options.conf
    echo "${CSUCCESS}MongoDB installed successfully! ${CEND}"
    rm -rf ${MONGODB_TARBALL%.tgz} mongosh-${mongosh_ver}-linux-${SYS_ARCH_n}
  else
    systemctl stop mongod > /dev/null 2>&1
    rm -rf ${mongo_install_dir} ${mongo_data_dir}
    echo "${CFAILURE}MongoDB install failed, Please contact the author! ${CEND}" && grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
    exit 1;
  fi
  popd
  [ -z "$(grep ^'export PATH=' /etc/profile)" ] && echo "export PATH=${mongo_install_dir}/bin:\$PATH" >> /etc/profile
  [ -n "$(grep ^'export PATH=' /etc/profile)" -a -z "$(grep ${mongo_install_dir} /etc/profile)" ] && sed -i "s@^export PATH=\(.*\)@export PATH=${mongo_install_dir}/bin:\1@" /etc/profile
  . /etc/profile
}
