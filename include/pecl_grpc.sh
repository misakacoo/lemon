#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Install_pecl_grpc() {
  if [ -e "${php_install_dir}/bin/phpize" ]; then
    pushd ${lemon_dir}/src > /dev/null
    phpExtensionDir=$(${php_install_dir}/bin/php-config --extension-dir)
    src_url=https://pecl.php.net/get/grpc-${grpc_ver}.tgz && Download_src
    tar xzf grpc-${grpc_ver}.tgz
    pushd grpc-${grpc_ver} > /dev/null
    ${php_install_dir}/bin/phpize
    ./configure --with-php-config=${php_install_dir}/bin/php-config
    # grpc 的 C++ 编译单元单个就要 1.5-2 GB 内存，小内存机器上 make -j2 会被
    # OOM killer 杀掉（日志里是 "cc1plus: fatal error: Killed signal terminated"）。
    # 处理：内存 >= 6 GB 直接按核数并行；3.5-6 GB 先临时加 2 GB swap 再 -j2；
    # 更小的机器老实串行。swap 用完即删，不在系统里留痕。
    grpc_jobs=1
    if [ "${Mem:-0}" -ge 6000 ]; then
      grpc_jobs=${THREAD}
    elif [ "${Mem:-0}" -ge 3500 ]; then
      swap_now=$(free -m | awk '/Swap:/{print $2}')
      if [ "${swap_now:-0}" -lt 2048 ] && [ ! -e /swapfile-grpc ]; then
        dd if=/dev/zero of=/swapfile-grpc bs=1M count=2048 >/dev/null 2>&1 \
          && chmod 600 /swapfile-grpc && mkswap /swapfile-grpc >/dev/null 2>&1 \
          && swapon /swapfile-grpc 2>/dev/null
      fi
      grpc_jobs=2
    fi
    make -j ${grpc_jobs} && make install
    if [ -e /swapfile-grpc ]; then
      swapoff /swapfile-grpc >/dev/null 2>&1
      rm -f /swapfile-grpc
    fi
    popd > /dev/null
    if [ -f "${phpExtensionDir}/grpc.so" ]; then
      echo 'extension=grpc.so' > ${php_install_dir}/etc/php.d/06-grpc.ini
      echo "${CSUCCESS}PHP grpc module installed successfully! ${CEND}"
      rm -rf grpc-${grpc_ver}
    else
      echo "${CFAILURE}PHP grpc module install failed, Please contact the author! ${CEND}" && grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
    fi
    popd > /dev/null
  fi
}

Uninstall_pecl_grpc() {
  if [ -e "${php_install_dir}/etc/php.d/06-grpc.ini" ]; then
    rm -f ${php_install_dir}/etc/php.d/06-grpc.ini
    echo; echo "${CMSG}PHP grpc module uninstall completed${CEND}"
  else
    echo; echo "${CWARNING}PHP grpc module does not exist! ${CEND}"
  fi
}
