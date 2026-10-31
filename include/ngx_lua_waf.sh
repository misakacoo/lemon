#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# 为什么这几样还是自己编译，而不是 apt：
#   ngx_lua + LuaJIT + lua-resty-core 是一组强耦合的运行时，版本必须互相对得上。
#   Debian 12 的 luajit 是普通 LuaJIT（2.1.0~beta3，不是 openresty 的 luajit2 分支），
#   Debian 13 的 lua-resty-core 是 0.1.31（比这里的 0.1.26 高 5 个版本，要求更新的
#   ngx_lua）。而 ngx_lua 模块只能用编译的方式进 Lemon 自己的 nginx —— Debian 的
#   libnginx-mod-http-lua 是给发行版 nginx 的动态模块，ABI 对不上。
#   混用 apt 库 + 自编 ngx_lua，最坏的情况是编译通过、运行时才报版本不符。
#   所以这一套整体保持编译，版本由 versions.txt 统一管理。
#
# Project home page:
#       https://github.com/misakacoo/lemon

Nginx_lua_waf() {
  pushd ${lemon_dir}/src > /dev/null
  [ ! -e "${nginx_install_dir}/sbin/nginx" ] && echo "${CWARNING}Nginx is not installed on your system! ${CEND}" && exit 1
  if [ ! -e "/usr/local/lib/libluajit-5.1.so.2.1.0" ]; then
    [ -e "/usr/local/lib/libluajit-5.1.so.2.0.5" ] && find /usr/local -name *luajit* | xargs rm -rf
    src_url=${mirror_link}/src/luajit2-${luajit2_ver}.tar.gz && Download_src
    tar xzf luajit2-${luajit2_ver}.tar.gz
    pushd luajit2-${luajit2_ver}
    make && make install
    [ ! -e "/usr/local/lib/libluajit-5.1.so.2.1.0" ] && { echo "${CFAILURE}LuaJIT install failed! ${CEND}"; exit 1; }
    popd > /dev/null
    rm -rf luajit2-${luajit2_ver}
  fi

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

  [ ! -h "/usr/local/share/lua/5.1" ] && { rm -rf /usr/local/share/lua/5.1 ; ln -s /usr/local/lib/lua /usr/local/share/lua/5.1; }
  if [ ! -e "/usr/local/lib/lua/5.1/cjson.so" ]; then
    src_url=${mirror_link}/src/lua-cjson-${lua_cjson_ver}.tar.gz && Download_src
    tar xzf lua-cjson-${lua_cjson_ver}.tar.gz
    pushd lua-cjson-${lua_cjson_ver}
    sed -i 's@^LUA_INCLUDE_DIR.*@&/luajit-2.1@' Makefile
    make && make install
    [ ! -e "/usr/local/lib/lua/5.1/cjson.so" ] && { echo "${CFAILURE}lua-cjson install failed! ${CEND}"; exit 1; }
    popd > /dev/null
  fi
  # $$ 作临时文件名，中途失败会残留，挂 trap 兜底
  trap 'rm -rf $$' EXIT
  ${nginx_install_dir}/sbin/nginx -V &> $$
  nginx_configure_args_tmp=`cat $$ | grep 'configure arguments:' | awk -F: '{print $2}'`
  rm -rf $$
  trap - EXIT
  nginx_configure_args=`echo ${nginx_configure_args_tmp} | sed "s@--with-openssl=../openssl-\w.\w.\w\+ @--with-openssl=../openssl-${openssl_build_ver} @" | sed "s@--with-pcre=../pcre2-[0-9.]* @--with-pcre=../pcre2-${pcre2_ver} @"`
  if [ -z "`echo ${nginx_configure_args} | grep lua-nginx-module`" ]; then
    src_url=${mirror_link}/src/nginx-${nginx_ver}.tar.gz && Download_src
    src_url=${mirror_link}/src/openssl-${openssl_build_ver}.tar.gz && Download_src
    src_url=${mirror_link}/src/pcre2-${pcre2_ver}.tar.gz && Download_src
    src_url=${mirror_link}/src/ngx_devel_kit.tar.gz && Download_src
    src_url=${mirror_link}/src/lua-nginx-module-${lua_nginx_module_ver}.tar.gz && Download_src
    tar xzf nginx-${nginx_ver}.tar.gz
    tar xzf openssl-${openssl_build_ver}.tar.gz
    tar xzf pcre2-${pcre2_ver}.tar.gz
    tar xzf ngx_devel_kit.tar.gz
    tar xzf lua-nginx-module-${lua_nginx_module_ver}.tar.gz
    pushd nginx-${nginx_ver}
    make clean
    sed -i 's@CFLAGS="$CFLAGS -g"@#CFLAGS="$CFLAGS -g"@' auto/cc/gcc # close debug
    export LUAJIT_LIB=/usr/local/lib
    export LUAJIT_INC=/usr/local/include/luajit-2.1
    ./configure ${nginx_configure_args} --with-ld-opt="-Wl,-rpath,/usr/local/lib" --add-module=../ngx_devel_kit --add-module=../lua-nginx-module-${lua_nginx_module_ver}
    make -j ${THREAD}
    if [ -f "objs/nginx" ]; then
      /bin/mv ${nginx_install_dir}/sbin/nginx{,`date +%m%d`}
      /bin/cp objs/nginx ${nginx_install_dir}/sbin/nginx
      kill -USR2 `cat /var/run/nginx.pid`
      sleep 1
      kill -QUIT `cat /var/run/nginx.pid.oldbin`
      popd > /dev/null
      echo "${CSUCCESS}lua-nginx-module installed successfully! ${CEND}"
      sed -i "s@^nginx_modules_options='\(.*\)'@nginx_modules_options=\'\1 --with-ld-opt=\"-Wl,-rpath,/usr/local/lib\" --add-module=../ngx_devel_kit --add-module=../lua-nginx-module-${lua_nginx_module_ver}\'@" ../options.conf
      rm -rf nginx-${nginx_ver}
    else
      echo "${CFAILURE}lua-nginx-module install failed! ${CEND}"
      exit 1;
    fi
  fi
  popd > /dev/null
}

Tengine_lua_waf() {
  pushd ${lemon_dir}/src > /dev/null
  [ ! -e "${tengine_install_dir}/sbin/nginx" ] && echo "${CWARNING}Tengine is not installed on your system! ${CEND}" && exit 1
  if [ ! -e "/usr/local/lib/libluajit-5.1.so.2.1.0" ]; then
    [ -e "/usr/local/lib/libluajit-5.1.so.2.0.5" ] && find /usr/local -name *luajit* | xargs rm -rf
    src_url=${mirror_link}/src/luajit2-${luajit2_ver}.tar.gz && Download_src
    tar xzf luajit2-${luajit2_ver}.tar.gz
    pushd luajit2-${luajit2_ver}
    make && make install
    [ ! -e "/usr/local/lib/libluajit-5.1.so.2.1.0" ] && { echo "${CFAILURE}LuaJIT install failed! ${CEND}"; exit 1; }
    popd > /dev/null
  fi
  if [ ! -e "/usr/local/lib/lua/5.1/cjson.so" ]; then
    src_url=${mirror_link}/src/lua-cjson-${lua_cjson_ver}.tar.gz && Download_src
    tar xzf lua-cjson-${lua_cjson_ver}.tar.gz
    pushd lua-cjson-${lua_cjson_ver}
    sed -i 's@^LUA_INCLUDE_DIR.*@&/luajit-2.1@' Makefile
    make && make install
    [ ! -e "/usr/local/lib/lua/5.1/cjson.so" ] && { echo "${CFAILURE}lua-cjson install failed! ${CEND}"; exit 1; }
    popd > /dev/null
  fi
  # $$ 作临时文件名，中途失败会残留，挂 trap 兜底
  trap 'rm -rf $$' EXIT
  ${tengine_install_dir}/sbin/nginx -V &> $$
  tengine_configure_args_tmp=`cat $$ | grep 'configure arguments:' | awk -F: '{print $2}'`
  rm -rf $$
  trap - EXIT
  tengine_configure_args=`echo ${tengine_configure_args_tmp} | sed "s@--with-openssl=../openssl-\w.\w.\w\+ @--with-openssl=../openssl-${openssl_build_ver} @" | sed "s@--with-pcre=../pcre2-[0-9.]* @--with-pcre=../pcre2-${pcre2_ver} @"`
  if [ -z "`echo ${tengine_configure_args} | grep lua`" ]; then
    src_url=${mirror_link}/src/tengine-${tengine_ver}.tar.gz && Download_src
    src_url=${mirror_link}/src/openssl-${openssl_build_ver}.tar.gz && Download_src
    src_url=${mirror_link}/src/pcre2-${pcre2_ver}.tar.gz && Download_src
    src_url=${mirror_link}/src/ngx_devel_kit.tar.gz && Download_src
    src_url=${mirror_link}/src/lua-nginx-module-${lua_nginx_module_ver}.tar.gz && Download_src
    tar xzf tengine-${tengine_ver}.tar.gz
    tar xzf openssl-${openssl_build_ver}.tar.gz
    tar xzf pcre2-${pcre2_ver}.tar.gz
    tar xzf ngx_devel_kit.tar.gz
    tar xzf lua-nginx-module-${lua_nginx_module_ver}.tar.gz
    pushd tengine-${tengine_ver}
    make clean
    export LUAJIT_LIB=/usr/local/lib
    export LUAJIT_INC=/usr/local/include/luajit-2.1
    ./configure ${tengine_configure_args} --with-ld-opt="-Wl,-rpath,/usr/local/lib" --add-module=../ngx_devel_kit --add-module=../lua-nginx-module-${lua_nginx_module_ver}
    make -j ${THREAD}
    if [ -f "objs/nginx" ]; then
      /bin/mv ${tengine_install_dir}/sbin/nginx{,`date +%m%d`}
      [ -d "${tengine_install_dir}/modules" ] && /bin/mv ${tengine_install_dir}/modules{,`date +%m%d`}
      /bin/cp objs/nginx ${tengine_install_dir}/sbin/nginx
      chmod +x ${tengine_install_dir}/sbin/*
      make install
      kill -USR2 `cat /var/run/nginx.pid`
      sleep 1
      kill -QUIT `cat /var/run/nginx.pid.oldbin`
      popd > /dev/null
      sed -i "s@^nginx_modules_options='\(.*\)'@nginx_modules_options=\'\1 --with-ld-opt=\"-Wl,-rpath,/usr/local/lib\" --add-module=../ngx_devel_kit --add-module=../lua-nginx-module-${lua_nginx_module_ver}\'@" ../options.conf
      echo "${CSUCCESS}lua_module installed successfully! ${CEND}"
      rm -rf tengine-${tengine_ver}
    else
      echo "${CFAILURE}lua_module install failed! ${CEND}"
      exit 1;
    fi
  fi
  popd > /dev/null
}

enable_lua_waf() {
  pushd ${lemon_dir}/src > /dev/null
  . ../include/check_dir.sh
  # 只认这三种：Caddy 的 conf 目录结构不同，waf 在它上面根本跑不了。
  # 不判的话 tar -C ${web_install_dir}/conf 会变成往 /conf 解包，静默写坏根目录
  if [ ! -e "${nginx_install_dir}/sbin/nginx" ] && [ ! -e "${tengine_install_dir}/sbin/nginx" ] && [ ! -e "${openresty_install_dir}/nginx/sbin/nginx" ]; then
    echo "${CWARNING}未检测到 Nginx / Tengine / OpenResty，跳过 ngx_lua_waf${CEND}"
    popd > /dev/null
    return 1
  fi
  rm -f ngx_lua_waf.tar.gz
  src_url=${mirror_link}/src/ngx_lua_waf.tar.gz && Download_src
  tar xzf ngx_lua_waf.tar.gz -C ${web_install_dir}/conf
  [ -e "${web_install_dir}/conf/resty" ] && /bin/mv ${web_install_dir}/conf/resty{,_bak}
  sed -i "s@/usr/local/nginx@${web_install_dir}@g" ${web_install_dir}/conf/waf.conf
  sed -i "s@/usr/local/nginx@${web_install_dir}@" ${web_install_dir}/conf/waf/config.lua
  sed -i "s@/data/wwwlogs@${wwwlogs_dir}@" ${web_install_dir}/conf/waf/config.lua
  [ -z "`grep 'include waf.conf;' ${web_install_dir}/conf/nginx.conf`" ] && sed -i "s@ vhost/\*.conf;@&\n  include waf.conf;@" ${web_install_dir}/conf/nginx.conf
  ${web_install_dir}/sbin/nginx -t
  if [ $? -eq 0 ]; then
    service nginx reload
    mark_addon_installed ngx_lua_waf
    echo "${CSUCCESS}ngx_lua_waf enabled successfully! ${CEND}"
    chown ${run_user}:${run_group} ${wwwlogs_dir}
  else
    echo "${CFAILURE}ngx_lua_waf enable failed! ${CEND}"
  fi
  popd > /dev/null
}

disable_lua_waf() {
  addon_uninstall_guard ngx_lua_waf "ngx_lua_waf" ${web_install_dir}/conf/waf.conf || return 0
  pushd ${lemon_dir}/src > /dev/null
  . ../include/check_dir.sh
  sed -i '/include waf.conf;/d' ${web_install_dir}/conf/nginx.conf
  ${web_install_dir}/sbin/nginx -t
  if [ $? -eq 0 ]; then
    rm -rf ${web_install_dir}/conf/{waf,waf.conf}
    service nginx reload
    clear_addon_mark ngx_lua_waf
    echo "${CSUCCESS}ngx_lua_waf disabled successfully! ${CEND}"
  else
    echo "${CFAILURE}ngx_lua_waf disable failed! ${CEND}"
  fi
  popd > /dev/null
}
