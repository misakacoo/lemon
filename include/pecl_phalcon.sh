#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Install_pecl_phalcon() {
  if [ -e "${php_install_dir}/bin/phpize" ]; then
    pushd ${lemon_dir}/src > /dev/null
    PHP_detail_ver=$(${php_install_dir}/bin/php-config --version)
    PHP_main_ver=${PHP_detail_ver%.*}
    phpExtensionDir=$(${php_install_dir}/bin/php-config --extension-dir)
    # phalcon 5.x 支持 PHP 8.0 及以上，7.2-7.4 走 4.1.2
    if [[ "${PHP_main_ver}" =~ ^7.[2-4]$|^8\. ]]; then
      # phalcon 5.x 要求 PHP >= 8.0，7.2-7.4 只能装 4.1.2
      if [[ "${PHP_main_ver}" =~ ^7.[2-4]$ ]]; then
        phalcon_pkg=${phalcon_74_ver}
        # phalcon 4.x 硬依赖 psr 扩展，缺了会
        # "Cannot load module 'phalcon' because required module 'psr' is not loaded"
        if [ ! -e "${phpExtensionDir}/psr.so" ]; then
          src_url=${mirror_link}/src/psr-${psr_ver}.tgz && Download_src
          tar xzf psr-${psr_ver}.tgz
          pushd psr-${psr_ver} > /dev/null
          ${php_install_dir}/bin/phpize
          ./configure --with-php-config=${php_install_dir}/bin/php-config
          make -j ${THREAD} && make install
          popd > /dev/null
          rm -rf psr-${psr_ver}
          [ -e "${phpExtensionDir}/psr.so" ] && echo 'extension=psr.so' > ${php_install_dir}/etc/php.d/03-psr.ini
        fi
      else
        phalcon_pkg=${phalcon_ver}
      fi
      src_url=${mirror_link}/src/phalcon-${phalcon_pkg}.tgz && Download_src
      tar xzf phalcon-${phalcon_pkg}.tgz
      pushd phalcon-${phalcon_pkg} > /dev/null
      ${php_install_dir}/bin/phpize
      echo "${CMSG}It may take a few minutes... ${CEND}"
      ./configure --with-php-config=${php_install_dir}/bin/php-config
      # phalcon 是单个巨大的 amalgamation 编译单元（phalcon.zep.c 十几 MB），
      # -O2 下单文件峰值 5G+：4.9G 内存的机器照样被 OOM killer 干掉
      # （cc: fatal error: Killed signal terminated program cc1），
      # 所以 8G 以下一律降到 -O0，并在内存 < 5G 时补 2G 临时 swap 兜底
      phalcon_cflags=""
      if [ "${Mem:-4096}" -ge 8000 ] 2>/dev/null; then
        phalcon_cflags=""
      else
        phalcon_cflags="-O0 -fPIC"
        swap_now=$(free -m | awk '/Swap:/{print $2}')
        if [ "${Mem:-4096}" -lt 5000 ] && [ "${swap_now:-0}" -lt 2048 ] && [ ! -e /swapfile-phalcon ]; then
          dd if=/dev/zero of=/swapfile-phalcon bs=1M count=2048 >/dev/null 2>&1 \
            && chmod 600 /swapfile-phalcon && mkswap /swapfile-phalcon >/dev/null 2>&1 \
            && swapon /swapfile-phalcon 2>/dev/null
        fi
      fi
      if [ -n "${phalcon_cflags}" ]; then
        make -j 1 CFLAGS="${phalcon_cflags}" && make install
      else
        make -j 1 && make install
      fi
      if [ -e /swapfile-phalcon ]; then
        swapoff /swapfile-phalcon >/dev/null 2>&1
        rm -f /swapfile-phalcon
      fi
      popd > /dev/null
    else
      echo "${CWARNING}Your php ${PHP_detail_ver} does not support phalcon! ${CEND}"
    fi
    if [ -f "${phpExtensionDir}/phalcon.so" ]; then
      echo 'extension=phalcon.so' > ${php_install_dir}/etc/php.d/04-phalcon.ini
      echo "${CSUCCESS}PHP phalcon module installed successfully! ${CEND}"
      rm -rf phalcon-${phalcon_pkg} phalcon-${phalcon_ver}
    else
      echo "${CFAILURE}PHP phalcon module install failed, Please contact the author! ${CEND}" && grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
    fi
    popd > /dev/null
  fi
}

Uninstall_pecl_phalcon() {
  if [ -e "${php_install_dir}/etc/php.d/04-phalcon.ini" ]; then
    rm -f ${php_install_dir}/etc/php.d/04-phalcon.ini
    echo; echo "${CMSG}PHP phalcon module uninstall completed${CEND}"
  else
    echo; echo "${CWARNING}PHP phalcon module does not exist! ${CEND}"
  fi
}
