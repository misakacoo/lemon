#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Install_redis_server() {
  pushd ${lemon_dir}/src > /dev/null
  tar xzf redis-${redis_ver}.tar.gz
  pushd redis-${redis_ver} > /dev/null
  # Redis 8 的 make 默认目标会连带编译 modules/ 下的 redisearch / redisjson 等，
  # 这些模块需要 Rust 与 python3（readies 构建链），装出来也用不上。
  # `make build core` 只编 Redis 本体，正是缓存服务需要的那部分。
  make build core -j ${THREAD}
  if [ -f "src/redis-server" ]; then
    mkdir -p ${redis_install_dir}/{bin,etc,var}
    /bin/cp src/{redis-benchmark,redis-check-aof,redis-check-rdb,redis-cli,redis-sentinel,redis-server} ${redis_install_dir}/bin/
    /bin/cp redis.conf ${redis_install_dir}/etc/
    ln -s ${redis_install_dir}/bin/* /usr/local/bin/
    sed -i 's@pidfile.*@pidfile /var/run/redis/redis.pid@' ${redis_install_dir}/etc/redis.conf
    sed -i "s@logfile.*@logfile ${redis_install_dir}/var/redis.log@" ${redis_install_dir}/etc/redis.conf
    sed -i "s@^dir.*@dir ${redis_install_dir}/var@" ${redis_install_dir}/etc/redis.conf
    sed -i 's@daemonize no@daemonize yes@' ${redis_install_dir}/etc/redis.conf
    # Redis 8 默认配置会 loadmodule ./modules/*.so，源码编译并不生成这些模块，
    # 保留会导致 redis 启动即退出
    sed -i '/^loadmodule \.\/modules\//s@^@#@' ${redis_install_dir}/etc/redis.conf
    sed -i "s@^# bind 127.0.0.1@bind 127.0.0.1@" ${redis_install_dir}/etc/redis.conf
    redis_maxmemory=`expr $Mem / 8`000000
    [ -z "`grep ^maxmemory ${redis_install_dir}/etc/redis.conf`" ] && sed -i "s@maxmemory <bytes>@maxmemory <bytes>\nmaxmemory `expr $Mem / 8`000000@" ${redis_install_dir}/etc/redis.conf
    echo "${CSUCCESS}Redis-server installed successfully! ${CEND}"
    popd > /dev/null
    rm -rf redis-${redis_ver}
    id -u redis >/dev/null 2>&1
    [ $? -ne 0 ] && useradd -M -s /sbin/nologin redis
    chown -R redis:redis ${redis_install_dir}/{var,etc}

    /bin/cp ../init.d/redis-server.service /lib/systemd/system/
    sed -i "s@/usr/local/redis@${redis_install_dir}@g" /lib/systemd/system/redis-server.service
    systemctl enable redis-server
    #[ -z "`grep 'vm.overcommit_memory' /etc/sysctl.conf`" ] && echo 'vm.overcommit_memory = 1' >> /etc/sysctl.conf
    #sysctl -p
    systemctl start redis-server
    sleep 1
    [ "$(systemctl is-active redis-server)" != 'active' ] && echo "${CFAILURE}redis-server 启动失败，请执行 journalctl -u redis-server 查看原因${CEND}"
  else
    rm -rf ${redis_install_dir}
    echo "${CFAILURE}Redis-server install failed, Please contact the author! ${CEND}" && grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
    exit 1;
  fi
  popd > /dev/null
}

Install_pecl_redis() {
  if [ -e "${php_install_dir}/bin/phpize" ]; then
    pushd ${lemon_dir}/src > /dev/null
    phpExtensionDir=`${php_install_dir}/bin/php-config --extension-dir`
    tar xzf redis-${pecl_redis_ver}.tgz
    pushd redis-${pecl_redis_ver} > /dev/null
    ${php_install_dir}/bin/phpize
    ./configure --with-php-config=${php_install_dir}/bin/php-config
    make -j ${THREAD} && make install
    popd > /dev/null
    if [ -f "${phpExtensionDir}/redis.so" ]; then
      echo 'extension=redis.so' > ${php_install_dir}/etc/php.d/05-redis.ini
      echo "${CSUCCESS}PHP Redis module installed successfully! ${CEND}"
      rm -rf redis-${pecl_redis_ver} redis-4.3.0 redis-5.3.7
    else
      echo "${CFAILURE}PHP Redis module install failed, Please contact the author! ${CEND}" && grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
    fi
    popd > /dev/null
  fi
}

Uninstall_pecl_redis() {
  if [ -e "${php_install_dir}/etc/php.d/05-redis.ini" ]; then
    rm -f ${php_install_dir}/etc/php.d/05-redis.ini
    echo; echo "${CMSG}PHP redis module uninstall completed${CEND}"
  else
    echo; echo "${CWARNING}PHP redis module does not exist! ${CEND}"
  fi
}
