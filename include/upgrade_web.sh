#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Upgrade_Nginx() {
  pushd ${lemon_dir}/src > /dev/null
  [ ! -e "${nginx_install_dir}/sbin/nginx" ] && echo "${CWARNING}Nginx is not installed on your system! ${CEND}" && exit 1
  OLD_nginx_ver_tmp=`${nginx_install_dir}/sbin/nginx -v 2>&1`
  OLD_nginx_ver=${OLD_nginx_ver_tmp##*/}
  Latest_nginx_ver=`curl -s https://nginx.org/en/download.html | grep -o 'nginx-[0-9\.]*\.tar\.gz' | head -n 1 | sed 's/nginx-\(.*\)\.tar\.gz/\1/'`
  echo
  echo "Current Nginx Version: ${CMSG}${OLD_nginx_ver}${CEND}"
  while :; do echo
    [ "${nginx_flag}" != 'y' ] && read -e -p "Please input upgrade Nginx Version(default: ${Latest_nginx_ver}): " NEW_nginx_ver
    NEW_nginx_ver=${NEW_nginx_ver:-${Latest_nginx_ver}}
    if [ "${NEW_nginx_ver}" != "${OLD_nginx_ver}" ]; then
      [ ! -e "nginx-${NEW_nginx_ver}.tar.gz" ] && wget -c https://nginx.org/download/nginx-${NEW_nginx_ver}.tar.gz > /dev/null 2>&1
      if [ -e "nginx-${NEW_nginx_ver}.tar.gz" ]; then
        src_url=${mirror_link}/src/openssl-${openssl_build_ver}.tar.gz && Download_src
        src_url=${mirror_link}/src/pcre2-${pcre2_ver}.tar.gz && Download_src
        src_url=${mirror_link}/src/ngx_devel_kit.tar.gz && Download_src
        src_url=${mirror_link}/src/lua-nginx-module-${lua_nginx_module_ver}.tar.gz && Download_src
        tar xzf openssl-${openssl_build_ver}.tar.gz
        tar xzf pcre2-${pcre2_ver}.tar.gz
        tar xzf ngx_devel_kit.tar.gz
        tar xzf lua-nginx-module-${lua_nginx_module_ver}.tar.gz
        echo "Download [${CMSG}nginx-${NEW_nginx_ver}.tar.gz${CEND}] successfully! "
        break
      else
        echo "${CWARNING}Nginx version does not exist! ${CEND}"
        # --nginx <版本> 是非交互调用：包下不到还回到 while 顶部会无限刷屏（真机 15 秒刷 14 次）
        [ "${nginx_flag}" == 'y' ] && exit 1
      fi
    else
      echo "${CWARNING}input error! Upgrade Nginx version is the same as the old version${CEND}"
      exit
    fi
  done

  if [ -e "nginx-${NEW_nginx_ver}.tar.gz" ]; then
    echo "[${CMSG}nginx-${NEW_nginx_ver}.tar.gz${CEND}] found"
    if [ "${nginx_flag}" != 'y' ]; then
      echo "Press Ctrl+c to cancel or Press any key to continue..."
      char=`get_char`
    fi
    ${nginx_install_dir}/sbin/nginx -V &> $$
    nginx_configure_args_tmp=`cat $$ | grep 'configure arguments:' | awk -F: '{print $2}'`
    rm -rf $$
    nginx_configure_args=`echo ${nginx_configure_args_tmp} | sed "s@lua-nginx-module-\w.\w\+.\w\+ @lua-nginx-module-${lua_nginx_module_ver} @" | sed "s@lua-nginx-module @lua-nginx-module-${lua_nginx_module_ver} @" | sed "s@--with-openssl=../openssl-\w.\w.\w\+ @--with-openssl=../openssl-${openssl_build_ver} @" | sed "s@--with-pcre=../pcre-\w.\w\+ @--with-pcre=../pcre2-${pcre2_ver} @"`
    if [ -n "`echo $nginx_configure_args | grep lua-nginx-module`" ]; then
      ${lemon_dir}/upgrade.sh --lemon > /dev/null
      src_url=${mirror_link}/src/luajit2-${luajit2_ver}.tar.gz && Download_src
      tar xzf luajit2-${luajit2_ver}.tar.gz
      pushd luajit2-${luajit2_ver}
      make && make install
      popd > /dev/null
      rm -rf luajit2-${luajit2_ver}

      src_url=${mirror_link}/src/lua-resty-core-${lua_resty_core_ver}.tar.gz && Download_src
      tar xzf lua-resty-core-${lua_resty_core_ver}.tar.gz
      pushd lua-resty-core-${lua_resty_core_ver}
      make install
      popd > /dev/null
      rm -rf lua-resty-core-${lua_resty_core_ver}

      src_url=${mirror_link}/src/lua-resty-lrucache-${lua_resty_lrucache_ver}.tar.gz && Download_src
      tar xzf lua-resty-lrucache-${lua_resty_lrucache_ver}.tar.gz
      pushd lua-resty-lrucache-${lua_resty_lrucache_ver}
      make install
      popd > /dev/null
      rm -rf lua-resty-lrucache-${lua_resty_lrucache_ver}
    fi

    tar xzf nginx-${NEW_nginx_ver}.tar.gz
    pushd nginx-${NEW_nginx_ver}
    make clean
    sed -i 's@CFLAGS="$CFLAGS -g"@#CFLAGS="$CFLAGS -g"@' auto/cc/gcc # close debug
    export LUAJIT_LIB=/usr/local/lib
    export LUAJIT_INC=/usr/local/include/luajit-2.1
    ./configure ${nginx_configure_args}
    make -j ${THREAD}
    if [ -f "objs/nginx" ]; then
      /bin/mv ${nginx_install_dir}/sbin/nginx{,`date +%m%d`}
      /bin/cp objs/nginx ${nginx_install_dir}/sbin/nginx
      kill -USR2 `cat /var/run/nginx.pid`
      sleep 1
      kill -QUIT `cat /var/run/nginx.pid.oldbin`
      popd > /dev/null
      echo "You have ${CMSG}successfully${CEND} upgrade from ${CWARNING}${OLD_nginx_ver}${CEND} to ${CWARNING}${NEW_nginx_ver}${CEND}"
      rm -rf nginx-${NEW_nginx_ver}
    else
      echo "${CFAILURE}Upgrade Nginx failed! ${CEND}"
    fi
  fi
  popd > /dev/null
}

Upgrade_Tengine() {
  pushd ${lemon_dir}/src > /dev/null
  [ ! -e "${tengine_install_dir}/sbin/nginx" ] && echo "${CWARNING}Tengine is not installed on your system! ${CEND}" && exit 1
  OLD_tengine_ver_tmp=`${tengine_install_dir}/sbin/nginx -v 2>&1`
  OLD_tengine_ver="`echo ${OLD_tengine_ver_tmp#*/} | awk '{print $1}'`"
  Latest_tengine_ver=`curl --connect-timeout 2 -m 3 -s https://tengine.taobao.org/download.html | grep -oE "tengine-[0-9]\.[0-9]\.[0-9]+\.tar\.gz" | grep -oE "[0-9]\.[0-9]\.[0-9]+" | head -1`
  echo
  echo "Current Tengine Version: ${CMSG}${OLD_tengine_ver}${CEND}"
  while :; do echo
    [ "${tengine_flag}" != 'y' ] && read -e -p "Please input upgrade Tengine Version(default: ${Latest_tengine_ver}): " NEW_tengine_ver
    NEW_tengine_ver=${NEW_tengine_ver:-${Latest_tengine_ver}}
    if [ "${NEW_tengine_ver}" != "${OLD_tengine_ver}" ]; then
      [ ! -e "tengine-${NEW_tengine_ver}.tar.gz" ] && wget -c https://tengine.taobao.org/download/tengine-${NEW_tengine_ver}.tar.gz > /dev/null 2>&1
      if [ -e "tengine-${NEW_tengine_ver}.tar.gz" ]; then
        src_url=${mirror_link}/src/openssl-${openssl_build_ver}.tar.gz && Download_src
        src_url=${mirror_link}/src/pcre2-${pcre2_ver}.tar.gz && Download_src
        tar xzf openssl-${openssl_build_ver}.tar.gz
        tar xzf pcre2-${pcre2_ver}.tar.gz
        echo "Download [${CMSG}tengine-${NEW_tengine_ver}.tar.gz${CEND}] successfully! "
        break
      else
        echo "${CWARNING}Tengine version does not exist! ${CEND}"
      fi
    else
      echo "${CWARNING}input error! Upgrade Tengine version is the same as the old version${CEND}"
      exit
    fi
  done

  if [ -e "tengine-${NEW_tengine_ver}.tar.gz" ]; then
    echo "[${CMSG}tengine-${NEW_tengine_ver}.tar.gz${CEND}] found"
    if [ "${tengine_flag}" != 'y' ]; then
      echo "Press Ctrl+c to cancel or Press any key to continue..."
      char=`get_char`
    fi
    tar xzf tengine-${NEW_tengine_ver}.tar.gz
    pushd tengine-${NEW_tengine_ver}
    make clean
    ${tengine_install_dir}/sbin/nginx -V &> $$
    tengine_configure_args_tmp=`cat $$ | grep 'configure arguments:' | awk -F: '{print $2}'`
    rm -rf $$
    tengine_configure_args=`echo ${tengine_configure_args_tmp} | sed "s@--with-openssl=../openssl-\w.\w.\w\+ @--with-openssl=../openssl-${openssl_build_ver} @" | sed "s@--with-pcre=../pcre-\w.\w\+ @--with-pcre=../pcre2-${pcre2_ver} @"`
    export LUAJIT_LIB=/usr/local/lib
    export LUAJIT_INC=/usr/local/include/luajit-2.1
    ./configure ${tengine_configure_args}
    make
    if [ -f "objs/nginx" ]; then
      /bin/mv ${tengine_install_dir}/sbin/nginx{,`date +%m%d`}
      /bin/mv ${tengine_install_dir}/modules{,`date +%m%d`}
      /bin/cp objs/nginx ${tengine_install_dir}/sbin/nginx
      chmod +x ${tengine_install_dir}/sbin/*
      make install
      kill -USR2 `cat /var/run/nginx.pid`
      sleep 1
      kill -QUIT `cat /var/run/nginx.pid.oldbin`
      popd > /dev/null
      echo "You have ${CMSG}successfully${CEND} upgrade from ${CWARNING}$OLD_tengine_ver${CEND} to ${CWARNING}${NEW_tengine_ver}${CEND}"
      rm -rf tengine-${NEW_tengine_ver}
    else
      echo "${CFAILURE}Upgrade Tengine failed! ${CEND}"
    fi
  fi
  popd > /dev/null
}

Upgrade_OpenResty() {
  pushd ${lemon_dir}/src > /dev/null
  [ ! -e "${openresty_install_dir}/nginx/sbin/nginx" ] && echo "${CWARNING}OpenResty is not installed on your system! ${CEND}" && exit 1
  OLD_openresty_ver_tmp=`${openresty_install_dir}/nginx/sbin/nginx -v 2>&1`
  OLD_openresty_ver="`echo ${OLD_openresty_ver_tmp#*/} | awk '{print $1}'`"
  Latest_openresty_ver=`curl --connect-timeout 2 -m 3 -s https://openresty.org/en/download.html | awk '/download\/openresty-/{print $0}' |  grep -oE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | head -1`
  echo
  echo "Current OpenResty Version: ${CMSG}${OLD_openresty_ver}${CEND}"
  while :; do echo
    [ "${openresty_flag}" != 'y' ] && read -e -p "Please input upgrade OpenResty Version(default: ${Latest_openresty_ver}): " NEW_openresty_ver
    NEW_openresty_ver=${NEW_openresty_ver:-${Latest_openresty_ver}}
    if [ "${NEW_openresty_ver}" != "${OLD_openresty_ver}" ]; then
      [ ! -e "openresty-${NEW_openresty_ver}.tar.gz" ] && wget -c https://openresty.org/download/openresty-${NEW_openresty_ver}.tar.gz > /dev/null 2>&1
      if [ -e "openresty-${NEW_openresty_ver}.tar.gz" ]; then
        src_url=${mirror_link}/src/openssl-${openssl_build_ver}.tar.gz && Download_src
        src_url=${mirror_link}/src/pcre2-${pcre2_ver}.tar.gz && Download_src
        tar xzf openssl-${openssl_build_ver}.tar.gz
        tar xzf pcre2-${pcre2_ver}.tar.gz
        echo "Download [${CMSG}openresty-${NEW_openresty_ver}.tar.gz${CEND}] successfully! "
        break
      else
        echo "${CWARNING}OpenResty version does not exist! ${CEND}"
      fi
    else
      echo "${CWARNING}input error! Upgrade OpenResty version is the same as the old version${CEND}"
      exit
    fi
  done

  if [ -e "openresty-${NEW_openresty_ver}.tar.gz" ]; then
    echo "[${CMSG}openresty-${NEW_openresty_ver}.tar.gz${CEND}] found"
    if [ "${openresty_flag}" != 'y' ]; then
      echo "Press Ctrl+c to cancel or Press any key to continue..."
      char=`get_char`
    fi
    tar xzf openresty-${NEW_openresty_ver}.tar.gz
    pushd openresty-${NEW_openresty_ver}
    make clean
    sed -i 's@CFLAGS="$CFLAGS -g"@#CFLAGS="$CFLAGS -g"@' bundle/nginx-${NEW_openresty_ver%.*}/auto/cc/gcc # close debug
    ${openresty_install_dir}/nginx/sbin/nginx -V &> $$
    ./configure --prefix=${openresty_install_dir} --user=${run_user} --group=${run_user} --with-http_stub_status_module --with-http_sub_module --with-http_v2_module --with-http_ssl_module --with-http_gzip_static_module --with-http_realip_module --with-http_flv_module --with-http_mp4_module --with-openssl=../openssl-${openssl_build_ver} --with-pcre=../pcre2-${pcre2_ver} --with-pcre-jit --with-ld-opt='-ljemalloc -Wl,-u,pcre_version' ${nginx_modules_options}
    make -j ${THREAD}
    if [ -f "build/nginx-${NEW_openresty_ver%.*}/objs/nginx" ]; then
      /bin/mv ${openresty_install_dir}/nginx/sbin/nginx{,`date +%m%d`}
      make install
      kill -USR2 `cat /var/run/nginx.pid`
      sleep 1
      kill -QUIT `cat /var/run/nginx.pid.oldbin`
      popd > /dev/null
      echo "You have ${CMSG}successfully${CEND} upgrade from ${CWARNING}${OLD_openresty_ver}${CEND} to ${CWARNING}${NEW_openresty_ver}${CEND}"
      rm -rf openresty-${NEW_openresty_ver}
    else
      echo "${CFAILURE}Upgrade OpenResty failed! ${CEND}"
    fi
  fi
  popd > /dev/null
}

Upgrade_Apache() {
  pushd ${lemon_dir}/src > /dev/null
  [ ! -e "${apache_install_dir}/bin/httpd" ] && echo "${CWARNING}Apache is not installed on your system! ${CEND}" && exit 1
  OLD_apache_ver="`${apache_install_dir}/bin/httpd -v | grep version | awk -F'/| ' '{print $4}'`"
  Latest_apache_ver=`curl --connect-timeout 2 -m 3 -s http://httpd.apache.org/download.cgi | awk "/#apache24/{print $2}" | head -1 | grep -oE "2\.[24]\.[0-9]+"`
  Latest_apache_ver=${Latest_apache_ver:-${apache_ver}}
  echo
  echo "Current Apache Version: ${CMSG}${OLD_apache_ver}${CEND}"
  while :; do echo
    [ "${apache_flag}" != 'y' ] && read -e -p "Please input upgrade Apache Version(Default: ${Latest_apache_ver}): " NEW_apache_ver
    NEW_apache_ver=${NEW_apache_ver:-${Latest_apache_ver}}
    if [ "`echo ${NEW_apache_ver} | awk -F. '{print $1$2}'`" = "24" ]; then
      if [ "${NEW_apache_ver}" != "${OLD_apache_ver}" ]; then
        src_url=${mirror_link}/src/apr-${apr_ver}.tar.gz && Download_src
        src_url=${mirror_link}/src/apr-util-${apr_util_ver}.tar.gz && Download_src
        [ ! -e "httpd-${NEW_apache_ver}.tar.gz" ] && wget -c https://archive.apache.org/dist/httpd/httpd-${NEW_apache_ver}.tar.gz > /dev/null 2>&1
        if [ -e "httpd-${NEW_apache_ver}.tar.gz" ]; then
          echo "Download [${CMSG}apache-${NEW_apache_ver}.tar.gz${CEND}] successfully! "
          break
        else
          echo "${CWARNING}Apache version does not exist! ${CEND}"
        fi
      else
        echo "${CWARNING}input error! Upgrade Apache version is the same as the old version${CEND}"
        exit
      fi
    else
      echo "${CWARNING}input error! ${CEND}Please only input '${CMSG}${OLD_apache_ver%.*}.xx${CEND}'"
      [ "${apache_flag}" == 'y' ] && exit
    fi
  done

  if [ -e "httpd-${NEW_apache_ver}.tar.gz" ]; then
    echo "[${CMSG}httpd-${NEW_apache_ver}.tar.gz${CEND}] found"
    if [ "${apache_flag}" != 'y' ]; then
      echo "Press Ctrl+c to cancel or Press any key to continue..."
      char=`get_char`
    fi
    # install apr
    if [ ! -e "${apr_install_dir}/bin/apr-1-config" ]; then
      tar xzf apr-${apr_ver}.tar.gz
      pushd apr-${apr_ver} > /dev/null
      ./configure --prefix=${apr_install_dir}
      make -j ${THREAD} && make install
      popd > /dev/null
      rm -rf apr-${apr_ver}
    fi
    # install apr-util
    if [ ! -e "${apr_install_dir}/bin/apu-1-config" ]; then
      tar xzf apr-util-${apr_util_ver}.tar.gz
      pushd apr-util-${apr_util_ver} > /dev/null
      ./configure --prefix=${apr_install_dir} --with-apr=${apr_install_dir}
      make -j ${THREAD} && make install
      popd > /dev/null
      rm -rf apr-util-${apr_util_ver}
    fi
    tar xzf httpd-${NEW_apache_ver}.tar.gz
    pushd httpd-${NEW_apache_ver}
    make clean
    LDFLAGS=-ldl ./configure --prefix=${apache_install_dir} --enable-mpms-shared=all --with-pcre --with-apr=${apr_install_dir} --with-apr-util=${apr_install_dir} --enable-headers --enable-mime-magic --enable-deflate --enable-proxy --enable-so --enable-dav --enable-rewrite --enable-remoteip --enable-expires --enable-static-support --enable-suexec --enable-mods-shared=most --enable-nonportable-atomics=yes --enable-ssl --with-ssl --enable-http2 --with-nghttp2=/usr/local
    make -j ${THREAD}
    if [ -e 'httpd' ]; then
      [[ -d ${apache_install_dir}_bak && -d ${apache_install_dir} ]] && rm -rf ${apache_install_dir}_bak
      service httpd stop
      /bin/cp -R ${apache_install_dir}{,_bak}
      make install && unset LDFLAGS
      # make install 的 install-conf 会用发行包原版覆盖 conf/httpd.conf，
      # Lemon 打的补丁（Listen 127.0.0.1:88 / Include vhost / LoadModule / DocumentRoot）会全丢，
      # nginx+apache 模式下 88 端口不再监听 → 站点全 502。用升级前的备份把 conf 盖回来。
      if [ -d "${apache_install_dir}_bak/conf" ]; then
        /bin/cp -a ${apache_install_dir}_bak/conf/. ${apache_install_dir}/conf/
      fi
      service httpd start
      popd > /dev/null
      echo "You have ${CMSG}successfully${CEND} upgrade from ${CWARNING}${OLD_apache_ver}${CEND} to ${CWARNING}${NEW_apache_ver}${CEND}"
      rm -rf httpd-${NEW_apache_ver}
    else
      echo "${CFAILURE}Upgrade Apache failed! ${CEND}"
    fi
  fi
  popd > /dev/null
}
