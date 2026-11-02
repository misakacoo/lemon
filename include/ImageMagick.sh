#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Install_ImageMagick() {
  # ImageMagick 库改用发行版自带（上游 7.x 源码包已无稳定直链，编译也很耗时）
  # apt 偶尔会因为 dpkg 锁/源抖动失败，重试两次；装完必须校验，
  # 否则会出现「打印 ready 但 imagick 扩展 configure 找不到 MagickWand」的假成功
  if ! dpkg -s libmagickwand-dev >/dev/null 2>&1; then
    apt-get --no-install-recommends -y install libmagickwand-dev >/dev/null 2>&1
    if ! dpkg -s libmagickwand-dev >/dev/null 2>&1; then
      apt-get update -qq >/dev/null 2>&1
      apt-get -y install libmagickwand-dev >/dev/null 2>&1
    fi
  fi
  if pkg-config --exists MagickWand 2>/dev/null || [ -x /usr/bin/MagickWand-config ]; then
    echo "${CSUCCESS}ImageMagick (system package) is ready! ${CEND}"
  else
    echo "${CFAILURE}ImageMagick 安装失败：libmagickwand-dev 没装上，imagick 扩展会编译失败${CEND}"
  fi
}

Uninstall_ImageMagick() {
  if [ -d "${imagick_install_dir}" ]; then
    rm -rf ${imagick_install_dir}
    echo; echo "${CMSG}ImageMagick uninstall completed${CEND}"
  fi
}

Install_pecl_imagick() {
  if [ -e "${php_install_dir}/bin/phpize" ]; then
    pushd ${lemon_dir}/src > /dev/null
    PHP_detail_ver=$(${php_install_dir}/bin/php-config --version)
    PHP_main_ver=${PHP_detail_ver%.*}
    phpExtensionDir=`${php_install_dir}/bin/php-config --extension-dir`
    tar xzf imagick-${imagick_ver}.tgz
    pushd imagick-${imagick_ver} > /dev/null
    export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH
    ${php_install_dir}/bin/phpize
    ./configure --with-php-config=${php_install_dir}/bin/php-config
    make -j ${THREAD} && make install
    popd > /dev/null
    if [ -f "${phpExtensionDir}/imagick.so" ]; then
      echo 'extension=imagick.so' > ${php_install_dir}/etc/php.d/03-imagick.ini
      echo "${CSUCCESS}PHP imagick module installed successfully! ${CEND}"
      rm -rf imagick-${imagick_ver}
    else
      echo "${CFAILURE}PHP imagick module install failed, Please contact the author! ${CEND}" && grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
    fi
    popd > /dev/null
  fi
}

Uninstall_pecl_imagick() {
  if [ -e "${php_install_dir}/etc/php.d/03-imagick.ini" ]; then
    rm -f ${php_install_dir}/etc/php.d/03-imagick.ini
    echo; echo "${CMSG}PHP imagick module uninstall completed${CEND}"
  else
    echo; echo "${CWARNING}PHP imagick module does not exist! ${CEND}"
  fi
}
