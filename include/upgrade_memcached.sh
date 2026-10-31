#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Upgrade_Memcached() {
  pushd ${lemon_dir}/src > /dev/null
  [ ! -e "${memcached_install_dir}/bin/memcached" ] && echo "${CWARNING}Memcached is not installed on your system! ${CEND}" && exit 1
  OLD_memcached_ver=`${memcached_install_dir}/bin/memcached -V | awk '{print $2}'`
  Latest_memcached_ver=`curl --connect-timeout 2 -m 3 -s https://github.com/memcached/memcached/wiki/ReleaseNotes | grep 'internal present.*ReleaseNotes' |  grep -oE "[0-9]\.[0-9]\.[0-9]+" | head -1`
  # 版本抓取失败不再退回写死的旧版本（1.5.12 太老），直接报错退出
  if [ -z "${Latest_memcached_ver}" ]; then
    echo "${CFAILURE}取不到 Memcached 最新版本号（请检查网络），可运行 ./upgrade.sh --memcached <版本号> 手动指定后重试${CEND}"
    exit 1
  fi
  echo "Current Memcached Version: ${CMSG}${OLD_memcached_ver}${CEND}"
  while :; do echo
    [ "${memcached_flag}" != 'y' ] && read -e -p "Please input upgrade Memcached Version(default: ${Latest_memcached_ver}): " NEW_memcached_ver
    NEW_memcached_ver=${NEW_memcached_ver:-${Latest_memcached_ver}}
    if [ "${NEW_memcached_ver}" != "${OLD_memcached_ver}" ]; then
      DOWN_ADDR=${mirror_link}/src
      [ ! -e "memcached-${NEW_memcached_ver}.tar.gz" ] && wget -c ${DOWN_ADDR}/memcached-${NEW_memcached_ver}.tar.gz > /dev/null 2>&1
      if [ -e "memcached-${NEW_memcached_ver}.tar.gz" ]; then
        echo "Download [${CMSG}memcached-${NEW_memcached_ver}.tar.gz${CEND}] successfully! "
        break
      else
        echo "${CWARNING}Memcached version does not exist! ${CEND}"
      fi
    else
      echo "${CWARNING}input error! Upgrade Memcached version is the same as the old version${CEND}"
      exit
    fi
  done

  if [ -e "memcached-${NEW_memcached_ver}.tar.gz" ]; then
    echo "[${CMSG}memcached-${NEW_memcached_ver}.tar.gz${CEND}] found"
    if [ "${memcached_flag}" != 'y' ]; then
      echo "Press Ctrl+c to cancel or Press any key to continue..."
      char=`get_char`
    fi
    tar xzf memcached-${NEW_memcached_ver}.tar.gz
    pushd memcached-${NEW_memcached_ver}
    make clean
    ./configure --prefix=${memcached_install_dir}
    make -j ${THREAD}

    if [ -e "memcached" ]; then
      echo "Restarting Memcached..."
      service memcached stop
      make install
      service memcached start
      popd > /dev/null
      echo "You have ${CMSG}successfully${CEND} upgrade from ${CWARNING}${OLD_memcached_ver}${CEND} to ${CWARNING}${NEW_memcached_ver}${CEND}"
      rm -rf memcached-${NEW_memcached_ver}
    else
      echo "${CFAILURE}Upgrade Memcached failed! ${CEND}"
    fi
  fi
  popd > /dev/null
}
