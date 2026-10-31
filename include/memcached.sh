#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Install_memcached_server() {
  pushd ${lemon_dir}/src > /dev/null
  # memcached server
  id -u memcached >/dev/null 2>&1
  [ $? -ne 0 ] && useradd -M -s /sbin/nologin memcached

  tar xzf memcached-${memcached_ver}.tar.gz
  pushd memcached-${memcached_ver} > /dev/null
  [ ! -d "${memcached_install_dir}" ] && mkdir -p ${memcached_install_dir}
  ./configure --prefix=${memcached_install_dir}
  make -j ${THREAD} && make install
  popd > /dev/null
  if [ -f "${memcached_install_dir}/bin/memcached" ]; then
    echo "${CSUCCESS}memcached installed successfully! ${CEND}"
    rm -rf memcached-${memcached_ver}
    ln -s ${memcached_install_dir}/bin/memcached /usr/bin/memcached
    /bin/cp ../init.d/memcached.service /lib/systemd/system/
    systemctl enable memcached
    systemctl start memcached
    rm -rf memcached-${memcached_ver}
  else
    rm -rf ${memcached_install_dir}
    echo "${CFAILURE}memcached-server install failed, Please contact the author! ${CEND}" && grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
    exit 1;
  fi
  popd > /dev/null
}

Install_pecl_memcache() {
  if [ -e "${php_install_dir}/bin/phpize" ]; then
    pushd ${lemon_dir}/src > /dev/null
    phpExtensionDir=$(${php_install_dir}/bin/php-config --extension-dir)
    PHP_detail_ver=$(${php_install_dir}/bin/php-config --version)
    PHP_main_ver=${PHP_detail_ver%.*}
    PHP_short_ver=$(echo ${PHP_detail_ver} | awk -F. '{print $1$2}')
    # pecl 的 memcache 扩面上游已停更：8.2 只支持到 PHP 8.1，8.2 起头文件被移除，
    # 编译必然报 ext/standard/php_smart_string.h: No such file。直接跳过而不是编失败。
    if [ "${PHP_short_ver}" -ge 82 ] 2>/dev/null; then
      echo "${CWARNING}PHP ${PHP_detail_ver} 不再被 memcache 扩展支持（上游只到 8.1），跳过 memcache${CEND}"
      popd > /dev/null
      return 0
    fi
    # 按实际 PHP 版本选包，并自行下载：
    # 原来靠 check_download 预先下好，但那边是按 php_option 判断的，
    # mphp 场景（--mphp_ver 74，没给 php_option）会下成 8.x 的包，
    # 到这里 tar 找不到文件直接失败。
    memcache_pkg=${pecl_memcache_ver}
    src_url=${mirror_link}/src/memcache-${memcache_pkg}.tgz && Download_src
    tar xzf memcache-${memcache_pkg}.tgz
    pushd memcache-${memcache_pkg} > /dev/null
    ${php_install_dir}/bin/phpize
    ./configure --with-php-config=${php_install_dir}/bin/php-config
    make -j ${THREAD} && make install
    popd > /dev/null
    if [ -f "${phpExtensionDir}/memcache.so" ]; then
      echo "extension=memcache.so" > ${php_install_dir}/etc/php.d/05-memcache.ini
      echo "${CSUCCESS}PHP memcache module installed successfully! ${CEND}"
      rm -rf memcache-${memcache_pkg} memcache-${pecl_memcache_ver}
    else
      echo "${CFAILURE}PHP memcache module install failed, Please contact the author! ${CEND}" && grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
    fi
    popd > /dev/null
  fi
}

Install_pecl_memcached() {
  if [ -e "${php_install_dir}/bin/phpize" ]; then
    pushd ${lemon_dir}/src > /dev/null
    phpExtensionDir=$(${php_install_dir}/bin/php-config --extension-dir)
    # php memcached extension
    # 1.0.18 在 gcc 12 下会因 C++ 类型比较报错，改用发行版提供的 libmemcached。
    # apt 偶发失败（dpkg 锁/源抖动）会让后面 configure 报 "Unable to find memcached.h"，
    # 所以重试并校验头文件
    if ! dpkg -s libmemcached-dev >/dev/null 2>&1; then
      apt-get --no-install-recommends -y install libmemcached-dev >/dev/null 2>&1
      if ! dpkg -s libmemcached-dev >/dev/null 2>&1; then
        apt-get update -qq >/dev/null 2>&1
        apt-get -y install libmemcached-dev >/dev/null 2>&1
      fi
    fi
    if ! ls /usr/include/libmemcached/memcached.h >/dev/null 2>&1; then
      echo "${CFAILURE}libmemcached-dev 安装失败，memcached 扩展无法编译${CEND}"
    fi

    tar xzf memcached-${pecl_memcached_ver}.tgz
    pushd memcached-${pecl_memcached_ver} > /dev/null
    ${php_install_dir}/bin/phpize
    ./configure --with-php-config=${php_install_dir}/bin/php-config --with-libmemcached-dir=/usr
    make -j ${THREAD} && make install
    popd > /dev/null
    if [ -f "${phpExtensionDir}/memcached.so" ]; then
      cat > ${php_install_dir}/etc/php.d/05-memcached.ini << EOF
extension=memcached.so
memcached.use_sasl=1
EOF
      echo "${CSUCCESS}PHP memcached module installed successfully! ${CEND}"
      rm -rf memcached-${pecl_memcached_ver}
    else
      echo "${CFAILURE}PHP memcached module install failed, Please contact the author! ${CEND}" && grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
    fi
    popd > /dev/null
  fi
}

Uninstall_pecl_memcache() {
  if [ -e "${php_install_dir}/etc/php.d/05-memcache.ini" ]; then
    rm -f ${php_install_dir}/etc/php.d/05-memcache.ini
    echo; echo "${CMSG}PHP memcache module uninstall completed${CEND}"
  else
    echo; echo "${CWARNING}PHP memcache module does not exist! ${CEND}"
  fi
}

Uninstall_pecl_memcached() {
  if [ -e "${php_install_dir}/etc/php.d/05-memcached.ini" ]; then
    rm -f ${php_install_dir}/etc/php.d/05-memcached.ini
    echo; echo "${CMSG}PHP memcached module uninstall completed${CEND}"
  else
    echo; echo "${CWARNING}PHP memcached module does not exist! ${CEND}"
  fi
}
