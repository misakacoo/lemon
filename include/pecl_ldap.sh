#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Install_pecl_ldap() {
  if [ -e "${php_install_dir}/bin/phpize" ]; then
    pushd ${lemon_dir}/src > /dev/null
    phpExtensionDir=$(${php_install_dir}/bin/php-config --extension-dir)
    PHP_detail_ver=$(${php_install_dir}/bin/php-config --version)
    src_url=${mirror_link}/src/php-${PHP_detail_ver}.tar.gz && Download_src
    tar xzf php-${PHP_detail_ver}.tar.gz
    pushd php-${PHP_detail_ver}/ext/ldap > /dev/null
    apt-get -y install libldap2-dev
    ln -sf /usr/lib/${ARCH}-linux-gnu/libldap.so /usr/lib/
    ln -sf /usr/lib/${ARCH}-linux-gnu/liblber.so /usr/lib/
    ${php_install_dir}/bin/phpize
    # Debian 的库在 lib/x86_64-linux-gnu，不传 --with-libdir（RHEL 的 lib64 会让
    # configure 报 "Cannot find ldap libraries in /usr/lib64"）；让 configure 自己探测
    ./configure --with-php-config=${php_install_dir}/bin/php-config --with-ldap
    make -j ${THREAD} && make install
    popd > /dev/null
    if [ -f "${phpExtensionDir}/ldap.so" ]; then
      echo 'extension=ldap.so' > ${php_install_dir}/etc/php.d/04-ldap.ini
      echo "${CSUCCESS}PHP ldap module installed successfully! ${CEND}"
      rm -rf php-${PHP_detail_ver}
    else
      echo "${CFAILURE}PHP ldap module install failed, Please contact the author! ${CEND}" && grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
    fi
    popd > /dev/null
  fi
}

Uninstall_pecl_ldap() {
  if [ -e "${php_install_dir}/etc/php.d/04-ldap.ini" ]; then
    rm -f ${php_install_dir}/etc/php.d/04-ldap.ini
    echo; echo "${CMSG}PHP ldap module uninstall completed${CEND}"
  else
    echo; echo "${CWARNING}PHP ldap module does not exist! ${CEND}"
  fi
}
