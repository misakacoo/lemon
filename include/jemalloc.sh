#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Install_Jemalloc() {
  if [ ! -e "/usr/local/lib/libjemalloc.so" ]; then
    pushd ${lemon_dir}/src > /dev/null
    tar xjf jemalloc-${jemalloc_ver}.tar.bz2
    pushd jemalloc-${jemalloc_ver} > /dev/null
    ./configure
    make -j ${THREAD} && make install
    popd > /dev/null
    if [ -f "/usr/local/lib/libjemalloc.so" ]; then
      ln -s /usr/local/lib/libjemalloc.so.2 /usr/lib/libjemalloc.so.1
      [ -z "`grep /usr/local/lib /etc/ld.so.conf.d/*.conf`" ] && echo '/usr/local/lib' > /etc/ld.so.conf.d/local.conf
      ldconfig
      echo "${CSUCCESS}jemalloc module installed successfully! ${CEND}"
      rm -rf jemalloc-${jemalloc_ver}
    else
      echo "${CFAILURE}jemalloc install failed, Please contact the author! ${CEND}" && grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
      exit 1;
    fi
    popd > /dev/null
  fi
}
