#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Install_APCU() {
  if [ -e "${php_install_dir}/bin/phpize" ]; then
    pushd ${lemon_dir}/src > /dev/null
    phpExtensionDir=`${php_install_dir}/bin/php-config --extension-dir`
    tar xzf apcu-${apcu_ver}.tgz
    pushd apcu-${apcu_ver} > /dev/null
    ${php_install_dir}/bin/phpize
    ./configure --with-php-config=${php_install_dir}/bin/php-config
    make -j ${THREAD} && make install
    if [ -f "${phpExtensionDir}/apcu.so" ]; then
      cat > ${php_install_dir}/etc/php.d/02-apcu.ini << EOF
[apcu]
extension=apcu.so
apc.enabled=1
apc.shm_size=32M
apc.ttl=7200
apc.enable_cli=1
EOF
      popd > /dev/null
      echo "${CSUCCESS}PHP apcu module installed successfully! ${CEND}"
      # apc.php 管理面板不再自动部署到 default 站点（会公开暴露 PHP 环境信息），需要时手动部署
      echo "apc.php 位于 apcu 源码包内：${lemon_dir}/src/apcu-${apcu_ver}.tgz"
      echo "手动部署示例：tar xzf ${lemon_dir}/src/apcu-${apcu_ver}.tgz -C /tmp && /bin/cp /tmp/apcu-${apcu_ver}/apc.php ${wwwroot_dir}/default/"
      echo "${CWARNING}注意：apc.php 会暴露 PHP 环境信息，公开访问有风险，部署后建议加访问控制或用完即删${CEND}"
      rm -rf apcu-${apcu_ver} package.xml
    else
      echo "${CFAILURE}PHP apcu module install failed, Please contact the author! ${CEND}" && grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
    fi
    popd > /dev/null
  fi
}

Uninstall_APCU() {
  if [ -e "${php_install_dir}/etc/php.d/02-apcu.ini" ]; then
    rm -rf ${php_install_dir}/etc/php.d/02-apcu.ini ${wwwroot_dir}/default/apc.php
    echo; echo "${CMSG}PHP apcu module uninstall completed${CEND}"
  else
    echo; echo "${CWARNING}PHP apcu module does not exist! ${CEND}"
  fi
}
