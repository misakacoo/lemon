#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Upgrade_PHP() {
  pushd ${lemon_dir}/src > /dev/null
  [ ! -e "${php_install_dir}" ] && echo "${CWARNING}PHP is not installed on your system! ${CEND}" && exit 1
  OLD_php_ver=`${php_install_dir}/bin/php-config --version`
  pythonCtl=python
  command -v python3 > /dev/null 2>&1 && pythonCtl=python3
  Latest_php_ver=`curl --connect-timeout 2 -m 3 -s https://www.php.net/releases/active.php | ${pythonCtl} -mjson.tool | awk '/version/{print $2}' | sed 's/"//g' | grep "${OLD_php_ver%.*}"`
  # 查不到线上的最新补丁版就沿用当前版本，别再写死 5.5.38（那是上游遗留的默认值）
  Latest_php_ver=${Latest_php_ver:-${OLD_php_ver}}
  echo
  echo "Current PHP Version: ${CMSG}$OLD_php_ver${CEND}"
  while :; do echo
    read -e -p "Please input upgrade PHP Version(Default: $Latest_php_ver): " NEW_php_ver
    NEW_php_ver=${NEW_php_ver:-${Latest_php_ver}}
    if [ "${NEW_php_ver%.*}" == "${OLD_php_ver%.*}" ]; then
      # 先走镜像（7.4 是仓库自建包，php.net 上根本没有），取不到再回官方源
      if [ ! -e "php-${NEW_php_ver}.tar.gz" ]; then
        src_url=${mirror_link}/src/php-${NEW_php_ver}.tar.gz
        Download_src_soft || wget -q -c https://www.php.net/distributions/php-${NEW_php_ver}.tar.gz > /dev/null 2>&1
      fi
      if [ -e "php-${NEW_php_ver}.tar.gz" ]; then
        echo "Download [${CMSG}php-${NEW_php_ver}.tar.gz${CEND}] successfully! "
      else
        echo "${CWARNING}PHP ${NEW_php_ver} 取不到：镜像站与 php.net 都没有这个版本${CEND}"
        echo "${CWARNING}若刚发布了新补丁版，需要先跑一次 Lemon-Mirror 的 scripts/build-mirror.py${CEND}"
        [ "${php_flag}" == 'y' ] && exit 1
      fi
      break
    else
      echo "${CWARNING}input error! ${CEND}Please only input '${CMSG}${OLD_php_ver%.*}.xx${CEND}'"
      [ "${php_flag}" == 'y' ] && exit
    fi
  done

  if [ -e "php-${NEW_php_ver}.tar.gz" ]; then
    echo "[${CMSG}php-${NEW_php_ver}.tar.gz${CEND}] found"
    if [ "${php_flag}" != 'y' ]; then
      echo "Press Ctrl+c to cancel or Press any key to continue..."
      char=`get_char`
    fi
    tar xzf php-${NEW_php_ver}.tar.gz
    # fpm-race-condition.patch 只针对 PHP 7.4（7.4 是仓库自建的 EOL 分支包），更高版本不打
    if [ "${OLD_php_ver%.*}" == '7.4' ]; then
      src_url=${mirror_link}/src/fpm-race-condition.patch && Download_src
      patch -d php-${NEW_php_ver} -p0 < fpm-race-condition.patch || echo "${CWARNING}fpm-race-condition.patch 应用失败，继续执行（可能已包含该修复）${CEND}"
    fi
    pushd php-${NEW_php_ver}
    if [[ "${OLD_php_ver%.*}" =~ ^7.[1-4]$|^8.[0-1]$ ]] && [ -e ext/openssl/openssl.c ] && ! grep -Eqi '^#ifdef RSA_SSLV23_PADDING' ext/openssl/openssl.c; then
      sed -i '/OPENSSL_SSLV23_PADDING/i#ifdef RSA_SSLV23_PADDING' ext/openssl/openssl.c
      sed -i '/OPENSSL_SSLV23_PADDING/a#endif' ext/openssl/openssl.c
    fi
    make clean
    export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig/:$PKG_CONFIG_PATH
    # 与全新安装保持一致（见 php-7.4.sh / php_build.sh）：
    # gcc14 警告升错误的兼容 flag 只 7.4 需要，configure 前导出 CFLAGS；
    # intl 的 C++ 标准修正 7.4-8.5 都要，configure 之后改 Makefile
    [ "${OLD_php_ver%.*}" == '7.4' ] && fix_php_gcc14_flags
    ${php_install_dir}/bin/php -i |grep 'Configure Command' | awk -F'=>' '{print $2}' | bash
    fix_php_intl_cxx_std
    # 编译失败必须停在这里：原来不判退出码，php-fpm 已经 stop 了还继续 make install，
    # 半成品覆盖到 ${php_install_dir} 之后服务起不来，脚本却打印 successfully upgrade
    if ! make ZEND_EXTRA_LIBS='-liconv' -j ${THREAD}; then
      echo "${CFAILURE}make failed, upgrade aborted${CEND}"
      service php-fpm start > /dev/null 2>&1
      popd > /dev/null
      return 1
    fi
    if [ -e "${apache_install_dir}/bin/httpd" ]; then
      echo "Stoping apache..."
      service httpd stop
      if ! make install; then echo "${CFAILURE}make install failed${CEND}"; service httpd start > /dev/null 2>&1; popd > /dev/null; return 1; fi
      echo "Starting apache..."
      service httpd start
    else
      echo "Stoping php-fpm..."
      service php-fpm stop
      if ! make install; then echo "${CFAILURE}make install failed${CEND}"; service php-fpm start > /dev/null 2>&1; popd > /dev/null; return 1; fi
      echo "Starting php-fpm..."
      service php-fpm start
    fi
    # 装完再验一次二进制，避免「装了个空的」
    if [ ! -e "${php_install_dir}/bin/php" ]; then
      echo "${CFAILURE}php binary missing after upgrade${CEND}"
      popd > /dev/null
      return 1
    fi
    popd > /dev/null
    echo "You have ${CMSG}successfully${CEND} upgrade from ${CWARNING}$OLD_php_ver${CEND} to ${CWARNING}${NEW_php_ver}${CEND}"
    rm -rf php-${NEW_php_ver}
  fi
  popd > /dev/null
}
