#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Install_Caddy() {

  pushd ${lemon_dir}/src > /dev/null
  id -g ${run_group} >/dev/null 2>&1
  [ $? -ne 0 ] && groupadd ${run_group}
  id -u ${run_user} >/dev/null 2>&1
  [ $? -ne 0 ] && useradd -g ${run_group} -M -s /sbin/nologin ${run_user}

  tar xzf caddy_${caddy_ver}_linux_${SYS_ARCH}.tar.gz

  #move caddy to /usr/local/caddy/bin
  [ ! -d "${caddy_install_dir}/bin" ] && mkdir -p ${caddy_install_dir}/bin
  /bin/cp caddy ${caddy_install_dir}/bin

  chmod +x ${caddy_install_dir}/bin/caddy

  [ -z "`grep ^'export PATH=' /etc/profile`" ] && echo "export PATH=${caddy_install_dir}/bin:\$PATH" >> /etc/profile
  [ -n "`grep ^'export PATH=' /etc/profile`" -a -z "`grep ${caddy_install_dir} /etc/profile`" ] && sed -i "s@^export PATH=\(.*\)@export PATH=${caddy_install_dir}/bin:\1@" /etc/profile
  . /etc/profile

  #make soft link
  # [ ! -L "/usr/local/bin/caddy" ] && ln -s ${caddy_install_dir}/bin/caddy /usr/local/bin/caddy

  #move caddyfile to /usr/local/caddy/conf
  [ ! -d "${caddy_install_dir}/conf/vhost" ] && mkdir -p ${caddy_install_dir}/conf/vhost
  # caddy 以 www 身份运行，需要一个可写的数据目录（autosave、证书缓存）
  [ ! -d "${caddy_install_dir}/data" ] && mkdir -p ${caddy_install_dir}/data
  chown -R ${run_user}:${run_group} ${caddy_install_dir}/data ${caddy_install_dir}/conf
  /bin/cp ../config/Caddyfile ${caddy_install_dir}/conf/
  sed -i "s@/usr/local/caddy@${caddy_install_dir}@g" ${caddy_install_dir}/conf/Caddyfile
  sed -i "s@/data/wwwroot/default@${wwwroot_dir}/default@" ${caddy_install_dir}/conf/Caddyfile

  #move caddy.service to /lib/systemd/system
  /bin/cp ../init.d/caddy.service /lib/systemd/system/

  #modify caddy.service
  sed -i "s@/usr/local/caddy@${caddy_install_dir}@g" /lib/systemd/system/caddy.service
  # 运行身份与上面 chown 的 data/conf 目录保持一致
  sed -i "s@^User=.*@User=${run_user}@" /lib/systemd/system/caddy.service
  sed -i "s@^Group=.*@Group=${run_group}@" /lib/systemd/system/caddy.service

  #设置caddy开机启动
  systemctl enable caddy

  #reload systemd
  systemctl daemon-reload

  #start caddy service
  systemctl start caddy

   echo "${CSUCCESS}Caddy installed successfully! ${CEND}"
}
