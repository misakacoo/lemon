#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Install_ClickHouse() {
  pushd ${lemon_dir}/src > /dev/null

  id -u clickhouse >/dev/null 2>&1
  [ $? -ne 0 ] && useradd -M -s /sbin/nologin clickhouse

  mkdir -p ${clickhouse_install_dir}/{bin,etc/clickhouse-server,etc/clickhouse-client}
  mkdir -p ${clickhouse_data_dir}/{tmp,user_files,format_schemas}
  mkdir -p /var/log/clickhouse-server /etc/clickhouse-server /etc/clickhouse-client

  # 重跑 install.sh 时 ClickHouse 可能还在跑，cp 覆盖正在使用的二进制会报
  # "Text file busy"（cp: cannot create regular file ...: Text file bus）
  systemctl stop clickhouse-server >/dev/null 2>&1
  pkill -f 'clickhouse-server' >/dev/null 2>&1
  sleep 1

  # Extract prebuilt static binaries
  tar xzf clickhouse-common-static-${clickhouse_ver}-${SYS_ARCH}.tgz
  tar xzf clickhouse-server-${clickhouse_ver}-${SYS_ARCH}.tgz
  tar xzf clickhouse-client-${clickhouse_ver}-${SYS_ARCH}.tgz

  if [ -f "clickhouse-common-static-${clickhouse_ver}/usr/bin/clickhouse" ]; then
    /bin/cp clickhouse-common-static-${clickhouse_ver}/usr/bin/clickhouse ${clickhouse_install_dir}/bin/
    chmod +x ${clickhouse_install_dir}/bin/clickhouse

    # Create symlinks for clickhouse components
    ln -sf clickhouse ${clickhouse_install_dir}/bin/clickhouse-server
    ln -sf clickhouse ${clickhouse_install_dir}/bin/clickhouse-client
    ln -sf clickhouse ${clickhouse_install_dir}/bin/clickhouse-local
    ln -sf clickhouse ${clickhouse_install_dir}/bin/clickhouse-benchmark

    ln -sf ${clickhouse_install_dir}/bin/clickhouse /usr/local/bin/clickhouse
    ln -sf ${clickhouse_install_dir}/bin/clickhouse-server /usr/local/bin/clickhouse-server
    ln -sf ${clickhouse_install_dir}/bin/clickhouse-client /usr/local/bin/clickhouse-client

    # Copy and setup configuration files
    if [ -d "clickhouse-server-${clickhouse_ver}/etc/clickhouse-server" ]; then
      /bin/cp -R clickhouse-server-${clickhouse_ver}/etc/clickhouse-server/* ${clickhouse_install_dir}/etc/clickhouse-server/
      /bin/cp -R clickhouse-server-${clickhouse_ver}/etc/clickhouse-server/* /etc/clickhouse-server/
    fi

    if [ -d "clickhouse-client-${clickhouse_ver}/etc/clickhouse-client" ]; then
      /bin/cp -R clickhouse-client-${clickhouse_ver}/etc/clickhouse-client/* ${clickhouse_install_dir}/etc/clickhouse-client/
      /bin/cp -R clickhouse-client-${clickhouse_ver}/etc/clickhouse-client/* /etc/clickhouse-client/
    fi

    # Adjust paths in config.xml
    if [ -f "/etc/clickhouse-server/config.xml" ]; then
      # 一次性把所有 /var/lib/clickhouse 换到数据目录。只换 <path> 不够：
      # user_directories/local_directory 指向 /var/lib/clickhouse/access/，
      # 漏掉它 clickhouse-server 会以 "Couldn't create directory ... Permission denied"
      # (Code 83) 起来就退出；format_schema_path 等也是同一批默认路径
      sed -i "s@/var/lib/clickhouse@${clickhouse_data_dir}@g" /etc/clickhouse-server/config.xml
      sed -i "s@<!-- <listen_host>::</listen_host> -->@<listen_host>127.0.0.1</listen_host>@g" /etc/clickhouse-server/config.xml
      sed -i "s@<!-- <listen_host>0.0.0.0</listen_host> -->@<listen_host>127.0.0.1</listen_host>@g" /etc/clickhouse-server/config.xml
    fi

    # Set password if specified
    if [ -n "${dbclickhousepwd}" ] && [ -f "/etc/clickhouse-server/users.xml" ]; then
      sed -i "s@<!-- <password></password> -->@<password>${dbclickhousepwd}</password>@g" /etc/clickhouse-server/users.xml
      sed -i "s@<password></password>@<password>${dbclickhousepwd}</password>@g" /etc/clickhouse-server/users.xml
    fi

    # Set permissions
    chown -R clickhouse:clickhouse ${clickhouse_install_dir} ${clickhouse_data_dir} /var/log/clickhouse-server /etc/clickhouse-server /etc/clickhouse-client

    # Systemd service
    cat > /lib/systemd/system/clickhouse-server.service << EOF
[Unit]
Description=ClickHouse Server (analytical database management system)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=clickhouse
Group=clickhouse
Restart=always
RestartSec=30
RuntimeMaxSec=86400
ExecStart=${clickhouse_install_dir}/bin/clickhouse-server --config-file=/etc/clickhouse-server/config.xml
LimitNOFILE=500000
LimitNPROC=500000
LimitMEMLOCK=infinity
CapabilityBoundingSet=CAP_NET_ADMIN CAP_IPC_LOCK CAP_SYS_NICE

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable clickhouse-server
    systemctl start clickhouse-server

    sleep 3
    if systemctl is-active clickhouse-server >/dev/null 2>&1 || [ -n "`pgrep clickhouse-server`" ]; then
      if grep -q '^dbclickhousepwd' ${lemon_dir}/options.conf; then
        sed -i "s+^dbclickhousepwd.*+dbclickhousepwd='${dbclickhousepwd}'+" ${lemon_dir}/options.conf
      else
        echo "dbclickhousepwd='${dbclickhousepwd}'" >> ${lemon_dir}/options.conf
      fi
      echo "${CSUCCESS}ClickHouse server installed successfully! ${CEND}"
    else
      echo "${CWARNING}ClickHouse server started with warnings, please check log: /var/log/clickhouse-server/clickhouse-server.err.log ${CEND}"
    fi

    rm -rf clickhouse-common-static-${clickhouse_ver} clickhouse-server-${clickhouse_ver} clickhouse-client-${clickhouse_ver}
  else
    rm -rf ${clickhouse_install_dir}
    echo "${CFAILURE}ClickHouse install failed, Please contact the author! ${CEND}"
    kill -9 $$; exit 1;
  fi

  popd > /dev/null
}

Uninstall_ClickHouse() {
  if [ -d "${clickhouse_install_dir}" ] || [ -f "/lib/systemd/system/clickhouse-server.service" ]; then
    systemctl stop clickhouse-server >/dev/null 2>&1
    systemctl disable clickhouse-server >/dev/null 2>&1
    rm -f /lib/systemd/system/clickhouse-server.service
    systemctl daemon-reload
    rm -rf ${clickhouse_install_dir} /etc/clickhouse-server /etc/clickhouse-client /var/log/clickhouse-server
    rm -f /usr/local/bin/clickhouse /usr/local/bin/clickhouse-server /usr/local/bin/clickhouse-client
    echo; echo "${CMSG}ClickHouse uninstall completed! ${CEND}"
  else
    echo; echo "${CWARNING}ClickHouse does not exist! ${CEND}"
  fi
}
