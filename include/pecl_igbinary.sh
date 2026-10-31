#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Install_pecl_igbinary() {
  if [ -e "${php_install_dir}/bin/phpize" ]; then
    pushd ${lemon_dir}/src > /dev/null
    phpExtensionDir=$(${php_install_dir}/bin/php-config --extension-dir)
    PHP_detail_ver=$(${php_install_dir}/bin/php-config --version)
    PHP_main_ver=${PHP_detail_ver%.*}
    src_url=https://pecl.php.net/get/igbinary-${igbinary_ver}.tgz && Download_src
    tar xzf igbinary-${igbinary_ver}.tgz
    pushd igbinary-${igbinary_ver} > /dev/null
    # PHP 8.5 把 ext/standard/php_smart_string.h 挪到了 Zend/zend_smart_string.h，
    # igbinary 3.2.16（PECL 最新）还引用旧路径，直接编会
    # "fatal error: ext/standard/php_smart_string.h: No such file or directory"
    if [[ "${PHP_main_ver}" =~ ^8\.[5-9]$|^9\. ]] && [ -f src/php7/php_igbinary.h ]; then
      sed -i 's@ext/standard/php_smart_string.h@Zend/zend_smart_string.h@' src/php7/php_igbinary.h
    fi
    ${php_install_dir}/bin/phpize
    ./configure --with-php-config=${php_install_dir}/bin/php-config
    make -j ${THREAD} && make install
    popd > /dev/null
    if [ -f "${phpExtensionDir}/igbinary.so" ]; then
      echo 'extension=igbinary.so' > ${php_install_dir}/etc/php.d/04-igbinary.ini
      echo "${CSUCCESS}PHP igbinary module installed successfully! ${CEND}"
      rm -rf igbinary-${igbinary_ver}
    else
      echo "${CFAILURE}PHP igbinary module install failed, Please contact the author! ${CEND}" && grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
    fi
    popd > /dev/null
  fi
}

Uninstall_pecl_igbinary() {
  if [ -e "${php_install_dir}/etc/php.d/04-igbinary.ini" ]; then
    rm -f ${php_install_dir}/etc/php.d/04-igbinary.ini
    echo; echo "${CMSG}PHP igbinary module uninstall completed${CEND}"
  else
    echo; echo "${CWARNING}PHP igbinary module does not exist! ${CEND}"
  fi
}
