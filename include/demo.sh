#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

DEMO() {
  pushd ${lemon_dir}/src > /dev/null
  if [ ! -e ${wwwroot_dir}/default/index.html ]; then
    if [ "${OUTIP_STATE}"x == "China"x ]; then
      /bin/cp ${lemon_dir}/config/index_cn.html ${wwwroot_dir}/default/index.html
    else
      /bin/cp ${lemon_dir}/config/index.html ${wwwroot_dir}/default/index.html
    fi

    # 数据库数据目录：DEMO 跑在 check_dir.sh 之前，db_data_dir 可能还没赋值，
    # 按实际存在的数据目录兜底
    db_data="${db_data_dir}"
    if [ -z "${db_data}" ]; then
      for d in /data/mysql /data/mariadb /data/percona /data/pgsql /data/mongodb; do
        [ -d "${d}" ] && { db_data="${d}"; break; }
      done
    fi
    [ -z "${db_data}" ] && db_data=/data

    # 页面是静态模板，把安装时的实际路径填进去
    # 仅装 Caddy 时 web_install_dir 为空，此时用 Caddy 的配置目录
    # （Caddyfile 在 ${caddy_install_dir}/conf/Caddyfile，vhost 在 conf/vhost）
    web_conf="${web_install_dir}/conf"
    [ -z "${web_install_dir}" ] && web_conf="${caddy_install_dir}/conf"
    sed -i -e "s@__WWWROOT__@${wwwroot_dir}/default@g" \
           -e "s@__WEB_CONF__@${web_conf}@g" \
           -e "s@__PHP_ETC__@${php_install_dir}/etc@g" \
           -e "s@__DB_DATA__@${db_data}@g" \
           -e "s@__LOGS__@${wwwlogs_dir}@g" \
           -e "s@__INSTALL_LOG__@${lemon_dir}/install.log@g" \
           ${wwwroot_dir}/default/index.html
  fi

  if [ -e "${php_install_dir}/bin/php" ]; then
    # 不再往站点目录放 phpinfo.php / xprober.php：
    # 默认 server 是 server_name _，绑在所有 IP 的 80 上，等于把 PHP 版本、
    # disable_functions、环境变量和绝对路径直接公开给扫描器。
    # 需要看 phpinfo 时自行在站点下临时建一个，看完删掉。

    # ocp.php / apc.php 面板同样不再默认部署（无认证、公网可达，
    # 可查看/清空缓存、泄露脚本绝对路径；apc.php 还带默认凭据）。
    # 需要时从 src/apcu-*.tgz 或镜像 src/ocp.php 手动取出，配合 IP 白名单使用。
    cache_link=""
    [ -n "${cache_link}" ] && sed -i "s@<!--CACHE_LINK-->@${cache_link}@" ${wwwroot_dir}/default/index.html
  fi

  # 没装 PHP、或没有缓存面板的，清掉占位符
  sed -i -e "s@<!--PHPINFO_LINK-->@@g" -e "s@<!--CACHE_LINK-->@@g" ${wwwroot_dir}/default/index.html

  chown -R ${run_user}:${run_group} ${wwwroot_dir}/default
  [ -e /bin/systemctl ] && systemctl daemon-reload
  popd > /dev/null
}
