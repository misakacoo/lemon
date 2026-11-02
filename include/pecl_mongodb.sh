#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Install_pecl_mongodb() {
  if [ -e "${php_install_dir}/bin/phpize" ]; then
    pushd ${lemon_dir}/src > /dev/null
    phpExtensionDir=$(${php_install_dir}/bin/php-config --extension-dir)
    php_short=$(${php_install_dir}/bin/php-config --version | awk -F. '{print $1$2}')
    # 新版驱动要求 PHP 8.1+，7.4 / 8.0 必须回退到 1.19.4，否则 configure 直接报版本不符
    if [[ "${php_short}" =~ ^74$|^80$ ]]; then
      mongodb_ext_ver=${pecl_mongodb_80_ver}
    else
      mongodb_ext_ver=${pecl_mongodb_ver}
    fi
    src_url=${mirror_link}/src/mongodb-${mongodb_ext_ver}.tgz && Download_src
    tar xzf mongodb-${mongodb_ext_ver}.tgz
    pushd mongodb-${mongodb_ext_ver} > /dev/null
    ${php_install_dir}/bin/phpize
    ./configure --with-php-config=${php_install_dir}/bin/php-config
    make -j ${THREAD} && make install
    popd > /dev/null
    if [ -f "${phpExtensionDir}/mongodb.so" ]; then
      echo 'extension=mongodb.so' > ${php_install_dir}/etc/php.d/07-mongodb.ini
      echo "${CSUCCESS}PHP mongodb module installed successfully! ${CEND}"
      rm -rf mongodb-${mongodb_ext_ver}
    else
      echo "${CFAILURE}PHP mongodb module install failed, Please contact the author! ${CEND}" && grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
    fi
    popd > /dev/null
  fi
}

Uninstall_pecl_mongodb() {
  if [ -e "${php_install_dir}/etc/php.d/07-mongo.ini" ]; then
    rm -f ${php_install_dir}/etc/php.d/07-mongo.ini
    echo; echo "${CMSG}PHP mongo module uninstall completed${CEND}"
  else
    echo; echo "${CWARNING}PHP mongo module does not exist! ${CEND}"
  fi
  if [ -e "${php_install_dir}/etc/php.d/07-mongodb.ini" ]; then
    rm -f ${php_install_dir}/etc/php.d/07-mongodb.ini
    echo; echo "${CMSG}PHP mongodb module uninstall completed${CEND}"
  else
    echo; echo "${CWARNING}PHP mongodb module does not exist! ${CEND}"
  fi
}
