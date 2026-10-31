#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Install_ionCube() {
  if [ -e "${php_install_dir}/bin/phpize" ]; then
    pushd ${lemon_dir}/src > /dev/null
    PHP_detail_ver=`${php_install_dir}/bin/php-config --version`
    PHP_main_ver=${PHP_detail_ver%.*}
    phpExtensionDir=`${php_install_dir}/bin/php-config --extension-dir`
    [ ! -d "${phpExtensionDir}" ] && mkdir -p ${phpExtensionDir}
    [ -e "ioncube_loaders_lin_${SYS_ARCH_i}.tar.gz" ] && tar xzf ioncube_loaders_lin_${SYS_ARCH_i}.tar.gz
    if [ -z "`echo ${phpExtensionDir} | grep 'non-zts'`" ]; then
      loader_src=ioncube/ioncube_loader_lin_${PHP_main_ver}_ts.so
      zend_extension="${phpExtensionDir}/ioncube_loader_lin_${PHP_main_ver}_ts.so"
    else
      loader_src=ioncube/ioncube_loader_lin_${PHP_main_ver}.so
      zend_extension="${phpExtensionDir}/ioncube_loader_lin_${PHP_main_ver}.so"
    fi
    # ionCube 官方的新版 loader 包不是每个 PHP 小版本都给：实测 7.4 之后直接跳到 8.1，
    # 没有 8.0 的 loader。原来无条件 mv，文件不存在时只打一行 mv 报错，
    # .so 没落地、ini 不生成、php -m 里也没有，install.sh 却照样 rc=0 —— 静默失败。
    if [ ! -f "${loader_src}" ]; then
      echo "${CWARNING}ionCube 官方未提供 PHP ${PHP_main_ver} 的 loader（包内现有：$(ls ioncube/ioncube_loader_lin_*.so 2>/dev/null | sed 's@.*_lin_@@;s@\.so@@' | tr '\n' ' ')），跳过该扩展${CEND}"
      rm -rf ioncube
      popd > /dev/null
      return 0
    fi
    /bin/mv ${loader_src} ${phpExtensionDir}

    if [ -f "${zend_extension}" ]; then
      echo "zend_extension=${zend_extension}" > ${php_install_dir}/etc/php.d/00-ioncube.ini
      echo "${CSUCCESS}PHP ionCube module installed successfully! ${CEND}"
      rm -rf ioncube
    fi
    popd > /dev/null
  fi
}

Uninstall_ionCube() {
  if [ -e "${php_install_dir}/etc/php.d/00-ioncube.ini" ]; then
    rm -f ${php_install_dir}/etc/php.d/00-ioncube.ini
    echo; echo "${CMSG}PHP ionCube module uninstall completed${CEND}"
  else
    echo; echo "${CWARNING}PHP ionCube module does not exist! ${CEND}"
  fi
}
