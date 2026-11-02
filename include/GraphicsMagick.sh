#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Install_GraphicsMagick() {
  if [ -d "${gmagick_install_dir}" ]; then
    echo "${CWARNING}GraphicsMagick already installed! ${CEND}"
  else
    pushd ${lemon_dir}/src > /dev/null
    # 1.3.49 起官方只提供 .tar.xz，老版本是 .tar.gz，按实际拿到的后缀解压
    if [ -e "GraphicsMagick-${graphicsmagick_ver}.tar.xz" ]; then
      tar xJf GraphicsMagick-${graphicsmagick_ver}.tar.xz
    else
      tar xzf GraphicsMagick-${graphicsmagick_ver}.tar.gz
    fi
    pushd GraphicsMagick-${graphicsmagick_ver} > /dev/null
    # --without-heif / --without-jxl：1.3.49 的 coders/heif.c 依赖新版 libheif API，
    # 而 Debian 12 带的是 libheif 1.15（heif_image_handle / heif_colorspace_nonvisual 等都没有），
    # configure 会自动探测 libheif.pc 并打开该 coder，随后 make 直接失败：
    #   coders/heif.c:768: error: 'heif' undeclared
    # 真机上就是这一步把 GraphicsMagick 编挂，gmagick 扩展跟着报
    #   GraphicsMagick configuration program... not found
    # gmagick 不需要 HEIF / JPEG-XL，直接关掉（Debian 13 同理更安全）。
    ./configure --prefix=${gmagick_install_dir} --enable-shared --enable-static --enable-symbol-prefix \
      --without-heif --without-jxl
    make -j ${THREAD} && make install
    popd > /dev/null
    rm -rf GraphicsMagick-${graphicsmagick_ver}
    popd > /dev/null
  fi
}

Uninstall_GraphicsMagick() {
  if [ -d "${gmagick_install_dir}" ]; then
    rm -rf ${gmagick_install_dir}
    echo; echo "${CMSG}GraphicsMagick uninstall completed${CEND}"
  fi
}

Install_pecl_gmagick() {
  if [ -e "${php_install_dir}/bin/phpize" ]; then
    pushd ${lemon_dir}/src > /dev/null
    phpExtensionDir=`${php_install_dir}/bin/php-config --extension-dir`
    tar xzf gmagick-${gmagick_ver}.tgz
    pushd gmagick-${gmagick_ver} > /dev/null
    export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig
    # gmagick 2.0.6RC1 是 2017 年的代码，调 GmMagickSetDepth 时没有原型；
    # gcc 14 起 implicit-function-declaration 默认是 error，Debian 13 上直接编不过
    if [ "${gcc_ver:-0}" -ge 14 ] 2>/dev/null; then
      export CFLAGS="${CFLAGS} -Wno-error=implicit-function-declaration"
    fi
    ${php_install_dir}/bin/phpize
    ./configure --with-php-config=${php_install_dir}/bin/php-config --with-gmagick=${gmagick_install_dir}
    make -j ${THREAD} && make install
    popd > /dev/null
    if [ -f "${phpExtensionDir}/gmagick.so" ]; then
      echo 'extension=gmagick.so' > ${php_install_dir}/etc/php.d/03-gmagick.ini
      echo "${CSUCCESS}PHP gmagick module installed successfully! ${CEND}"
      rm -rf gmagick-${gmagick_ver}
    else
      echo "${CFAILURE}PHP gmagick module install failed, Please contact the author! ${CEND}" && grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
    fi
    popd > /dev/null
  fi
}

Uninstall_pecl_gmagick() {
  if [ -e "${php_install_dir}/etc/php.d/03-gmagick.ini" ]; then
    rm -f ${php_install_dir}/etc/php.d/03-gmagick.ini
    echo; echo "${CMSG}PHP gmagick module uninstall completed${CEND}"
  else
    echo; echo "${CWARNING}PHP gmagick module does not exist! ${CEND}"
  fi
}
