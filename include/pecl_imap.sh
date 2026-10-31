#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Install_pecl_imap() {
  if [ -e "${php_install_dir}/bin/phpize" ]; then
    pushd ${lemon_dir}/src > /dev/null
    # Debian 13 起 uw-imap 被移除，系统不再提供 libc-client，imap 扩展无法编译
    if [ "${Debian_ver}" -ge 13 ] 2>/dev/null; then
      echo "${CWARNING}Debian 13 已移除 uw-imap（无 libc-client），跳过 imap 扩展${CEND}"
      popd > /dev/null
      return 0
    fi
    # PHP 8.4 起官方移除了 ext/imap（Unbundle ext/imap），源码包里已经没有这个目录，
    # 再往下走会在 pushd php-*/ext/imap 处失败。与 Lemon-Shell 里 imap 只到 8.3 的置灰规则一致。
    imap_php_ver=$(${php_install_dir}/bin/php-config --version)
    imap_php_main=${imap_php_ver%.*}
    if [ "${imap_php_main%%.*}" -eq 8 ] && [ "${imap_php_main#*.}" -ge 4 ]; then
      echo "${CWARNING}PHP ${imap_php_ver} 已移除 ext/imap（8.4 起），跳过 imap 扩展${CEND}"
      popd > /dev/null
      return 0
    fi
    apt-get -y install libc-client2007e-dev
    # Debian 12 的 libc-client2007e-dev 把头文件放在 /usr/include/c-client/ 下，
    # 老版本才是 /usr/include/imap/，两种都要认；后者要显式把目录加进 CPPFLAGS
    if [ -e /usr/include/imap/c-client.h ] || [ -e /usr/include/c-client.h ]; then
      :
    elif [ -e /usr/include/c-client/c-client.h ]; then
      export CPPFLAGS="-I/usr/include/c-client ${CPPFLAGS}"
    else
      echo "${CWARNING}系统未提供 libc-client，跳过 imap 扩展${CEND}"
      popd > /dev/null
      return 0
    fi
    phpExtensionDir=$(${php_install_dir}/bin/php-config --extension-dir)
    PHP_detail_ver=$(${php_install_dir}/bin/php-config --version)
    src_url=${mirror_link}/src/php-${PHP_detail_ver}.tar.gz && Download_src
    tar xzf php-${PHP_detail_ver}.tar.gz
    pushd php-${PHP_detail_ver}/ext/imap > /dev/null
    ${php_install_dir}/bin/phpize
    ./configure --with-php-config=${php_install_dir}/bin/php-config --with-kerberos --with-imap --with-imap-ssl
    make -j ${THREAD} && make install
    popd > /dev/null
    if [ -f "${phpExtensionDir}/imap.so" ]; then
      echo 'extension=imap.so' > ${php_install_dir}/etc/php.d/04-imap.ini
      echo "${CSUCCESS}PHP imap module installed successfully! ${CEND}"
      rm -rf php-${PHP_detail_ver}
    else
      echo "${CFAILURE}PHP imap module install failed, Please contact the author! ${CEND}" && grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
    fi
    popd > /dev/null
  fi
}

Uninstall_pecl_imap() {
  if [ -e "${php_install_dir}/etc/php.d/04-imap.ini" ]; then
    rm -f ${php_install_dir}/etc/php.d/04-imap.ini
    echo; echo "${CMSG}PHP imap module uninstall completed${CEND}"
  else
    echo; echo "${CWARNING}PHP imap module does not exist! ${CEND}"
  fi
}
