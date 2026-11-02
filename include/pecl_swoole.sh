#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Install_pecl_swoole() {
  if [ -e "${php_install_dir}/bin/phpize" ]; then
    pushd ${lemon_dir}/src > /dev/null
    phpExtensionDir=$(${php_install_dir}/bin/php-config --extension-dir)
    PHP_detail_ver=$(${php_install_dir}/bin/php-config --version)
    PHP_main_ver=${PHP_detail_ver%.*}
    if [[ "${PHP_main_ver}" =~ ^7.[2-4]$ ]]; then
      # 7.2-7.4 用老版 4.8.12
      src_url=${mirror_link}/src/swoole-${swoole_oldver}.tgz && Download_src
      tar xzf swoole-${swoole_oldver}.tgz
      pushd swoole-${swoole_oldver} > /dev/null
    elif [[ "${PHP_main_ver}" =~ ^8.[01]$ ]]; then
      # Swoole 6.x 仅支持 PHP 8.2+，8.0/8.1 用 5.1 线
      src_url=${mirror_link}/src/swoole-${swoole_51_ver}.tgz && Download_src
      tar xzf swoole-${swoole_51_ver}.tgz
      pushd swoole-${swoole_51_ver} > /dev/null
    else
      src_url=${mirror_link}/src/swoole-${swoole_ver}.tgz && Download_src
      tar xzf swoole-${swoole_ver}.tgz
      pushd swoole-${swoole_ver} > /dev/null
    fi
    ${php_install_dir}/bin/phpize
    # gcc13+ 的 C++ 标准库不再隐式包含 <cstdint>，swoole 4.8.x 的
    # include/swoole_proxy.h 用了 uint8_t 却未包含（Debian 13 的 gcc14 必现），
    # 编译前给头文件补上
    if [ "$(gcc -dumpversion 2>/dev/null | cut -d. -f1)" -ge 13 ] 2>/dev/null; then
      [ -e include/swoole_proxy.h ] && sed -i '1i #include <cstdint>' include/swoole_proxy.h
    fi
    # 不再传 --with-openssl-dir=/usr/local/openssl：那个目录只有自建 OpenSSL 时才有，
    # 现在一律用系统 OpenSSL，让 configure 自己探测即可
    ./configure --with-php-config=${php_install_dir}/bin/php-config --enable-openssl --enable-http2 --enable-swoole-json --enable-swoole-curl
    make -j ${THREAD} && make install
    popd > /dev/null
    if [ -f "${phpExtensionDir}/swoole.so" ]; then
      echo 'extension=swoole.so' > ${php_install_dir}/etc/php.d/06-swoole.ini
      echo "${CSUCCESS}PHP swoole module installed successfully! ${CEND}"
      rm -rf swoole-${swoole_ver} swoole-${swoole_51_ver} swoole-${swoole_oldver} swoole-1.10.5 swoole-4.5.2
    else
      echo "${CFAILURE}PHP swoole module install failed, Please contact the author! ${CEND}" && grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
    fi
    popd > /dev/null
  fi
}

Uninstall_pecl_swoole() {
  if [ -e "${php_install_dir}/etc/php.d/06-swoole.ini" ]; then
    rm -f ${php_install_dir}/etc/php.d/06-swoole.ini
    echo; echo "${CMSG}PHP swoole module uninstall completed${CEND}"
  else
    echo; echo "${CWARNING}PHP swoole module does not exist! ${CEND}"
  fi
}
