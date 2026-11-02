#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Install_pecl_xdebug() {
  if [ -e "${php_install_dir}/bin/phpize" ]; then
    pushd ${lemon_dir}/src > /dev/null
    phpExtensionDir=$(${php_install_dir}/bin/php-config --extension-dir)
    PHP_detail_ver=$(${php_install_dir}/bin/php-config --version)
    PHP_main_ver=${PHP_detail_ver%.*}
    # 注意 PHP_main_ver 是 "8.5" 这种带点的形式，写成 ^8[0-9]$ 永远匹配不上，
    # PHP 8 下会直接报 "does not support xdebug"（真机在 8.5 上复现）
    if [[ "${PHP_main_ver}" =~ ^7\.4$|^8\.[0-9]$ ]]; then
      # xdebug 3.2 起要求 PHP >= 8.0，7.4 只能用 3.1.6
      if [[ "${PHP_main_ver}" =~ ^7.4$ ]]; then
        xdebug_pkg=${xdebug_php7_ver}
      else
        xdebug_pkg=${xdebug_ver}
      fi
      src_url=${mirror_link}/src/xdebug-${xdebug_pkg}.tgz && Download_src
      tar xzf xdebug-${xdebug_pkg}.tgz
      pushd xdebug-${xdebug_pkg} > /dev/null
      ${php_install_dir}/bin/phpize
      ./configure --with-php-config=${php_install_dir}/bin/php-config
      make -j ${THREAD} && make install
      popd > /dev/null
      if [ -f "${phpExtensionDir}/xdebug.so" ]; then
        [ ! -e /tmp/xdebug ] && { mkdir /tmp/xdebug; chown ${run_user}:${run_group} /tmp/xdebug; }
        # xdebug 3 用 xdebug.mode 统一控制，老写法（profiler_enable / *_output_dir）
        # 在 3.x 上完全无效，写进 ini 只会让 webgrind 一直空着
        cat > ${php_install_dir}/etc/php.d/08-xdebug.ini << EOF
[xdebug]
zend_extension=xdebug.so
xdebug.mode = profile,trace
xdebug.start_with_request = trigger
xdebug.output_dir = /tmp/xdebug
xdebug.profiler_output_name = cachegrind.out.%p
xdebug.trace_output_name = trace.%c
EOF
        echo "${CSUCCESS}PHP xdebug module installed successfully! ${CEND}"
        # webgrind 不再自动部署到 default 站点（会把性能分析入口暴露到公网），需要时手动部署
        echo "webgrind 未自动部署：如需分析 profile 结果，请从 https://github.com/jokkedk/webgrind 下载后部署到 ${wwwroot_dir}/default/webgrind"
        echo "部署后需将 config.php 中 \$storageDir 指向 /tmp/webgrind、\$profilerDir 指向 /tmp/xdebug（/tmp/webgrind 目录需自行创建并授权给 ${run_user}）"
        echo "${CWARNING}注意：webgrind 会暴露性能剖析数据，公开访问有风险，建议仅临时开启并加访问控制${CEND}"
        rm -rf xdebug-${xdebug_pkg}
      else
        echo "${CFAILURE}PHP xdebug module install failed, Please contact the author! ${CEND}" && grep -Ew 'NAME|ID|ID_LIKE|VERSION_ID|PRETTY_NAME' /etc/os-release
      fi
    else
      echo "${CWARNING}Your php ${PHP_detail_ver} does not support xdebug! ${CEND}";
    fi
    popd > /dev/null
  fi
}

Uninstall_pecl_xdebug() {
  if [ -e "${php_install_dir}/etc/php.d/08-xdebug.ini" ]; then
    rm -rf ${php_install_dir}/etc/php.d/08-xdebug.ini /tmp/{xdebug,webgrind} ${wwwroot_dir}/default/webgrind
    echo; echo "${CMSG}PHP xdebug module uninstall completed${CEND}"
  else
    echo; echo "${CWARNING}PHP xdebug module does not exist! ${CEND}"
  fi
}
