#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Upgrade_Redis() {
  pushd ${lemon_dir}/src > /dev/null
  [ ! -d "$redis_install_dir" ] && echo "${CWARNING}Redis is not installed on your system! ${CEND}" && exit 1
  OLD_redis_ver=`$redis_install_dir/bin/redis-cli --version | awk '{print $2}'`
  Latest_redis_ver=`curl --connect-timeout 2 -m 3 -s https://download.redis.io/redis-stable/00-RELEASENOTES | awk '/Released/{print $2}' | head -1`
  # 版本抓取失败不再退回写死的旧版本（6.0.4 太老），直接报错退出
  if [ -z "${Latest_redis_ver}" ]; then
    echo "${CFAILURE}取不到 Redis 最新版本号（请检查网络），可运行 ./upgrade.sh --redis <版本号> 手动指定后重试${CEND}"
    exit 1
  fi
  echo "Current Redis Version: ${CMSG}$OLD_redis_ver${CEND}"
  while :; do echo
    [ "${redis_flag}" != 'y' ] && read -e -p "Please input upgrade Redis Version(default: ${Latest_redis_ver}): " NEW_redis_ver
    NEW_redis_ver=${NEW_redis_ver:-${Latest_redis_ver}}
    if [ "$NEW_redis_ver" != "$OLD_redis_ver" ]; then
      [ ! -e "redis-$NEW_redis_ver.tar.gz" ] && wget -c https://download.redis.io/releases/redis-$NEW_redis_ver.tar.gz > /dev/null 2>&1
      if [ -e "redis-$NEW_redis_ver.tar.gz" ]; then
        echo "Download [${CMSG}redis-$NEW_redis_ver.tar.gz${CEND}] successfully! "
        break
      else
        echo "${CWARNING}Redis version does not exist! ${CEND}"
      fi
    else
      echo "${CWARNING}input error! Upgrade Redis version is the same as the old version${CEND}"
      exit
    fi
  done

  if [ -e "redis-$NEW_redis_ver.tar.gz" ]; then
    echo "[${CMSG}redis-$NEW_redis_ver.tar.gz${CEND}] found"
    if [ "${redis_flag}" != 'y' ]; then
      echo "Press Ctrl+c to cancel or Press any key to continue..."
      char=`get_char`
    fi
    tar xzf redis-$NEW_redis_ver.tar.gz
    pushd redis-$NEW_redis_ver
    make clean
    # 与 include/redis.sh 的全新安装一致：Redis 8 的 make 默认目标会连带编译 modules/
    # （需要 Rust 与 python3），`make build core` 只编 Redis 本体
    make build core -j ${THREAD}

    if [ -f "src/redis-server" ]; then
      echo "Restarting Redis..."
      service redis-server stop
      /bin/cp src/{redis-benchmark,redis-check-aof,redis-check-rdb,redis-cli,redis-sentinel,redis-server} $redis_install_dir/bin/
      service redis-server start
      popd > /dev/null
      echo "You have ${CMSG}successfully${CEND} upgrade from ${CWARNING}$OLD_redis_ver${CEND} to ${CWARNING}$NEW_redis_ver${CEND}"
      rm -rf redis-$NEW_redis_ver
    else
      echo "${CFAILURE}Upgrade Redis failed! ${CEND}"
    fi
  fi
  popd > /dev/null
}
