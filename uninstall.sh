#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
# 没有 TTY（nohup、CI、管道）时 clear 会报 TERM 未设置，纯噪音
[ -t 1 ] && clear
printf "
#######################################################################
# Lemon - One-click Linux web stack (Nginx/MySQL/PHP)                 #
#                           Uninstall Lemon                           #
# https://github.com/misakacoo/lemon                                  #
#######################################################################
"
# Check if user is root
[ $(id -u) != "0" ] && { echo "${CFAILURE}Error: You must be root to run this script${CEND}"; exit 1; }

lemon_dir=$(dirname "`readlink -f $0`")
pushd ${lemon_dir} > /dev/null
. ./options.conf
. ./include/color.sh
. ./include/get_char.sh
. ./include/check_dir.sh

Show_Help() {
  echo
  echo "Usage: $0  command ...[parameters]....
  --help, -h                    Show this help message, More: https://github.com/misakacoo/lemon
  --quiet, -q                   quiet operation
  --all                         Uninstall All
  --purge                       在 --all 基础上清掉 Lemon 自己的配置与标记（不碰系统包）
  --purge-data                  在 --purge 基础上连 /data 一起删除（数据不可恢复）
  --web                         Uninstall Nginx/Tengine/OpenResty/Apache/Caddy
  --mysql                       Uninstall MySQL/MariaDB/Percona
  --postgresql                  Uninstall PostgreSQL
  --mongodb                     Uninstall MongoDB
  --php                         Uninstall PHP (PATH: ${php_install_dir})
  --mphp_ver [74~85]            Uninstall another PHP version (PATH: ${php_install_dir}\${mphp_ver})
  --allphp                      Uninstall all PHP
  --phpcache                    Uninstall PHP opcode cache
  --php_extensions [ext name]   Uninstall PHP extensions, include ioncube,imagick,gmagick,
                                fileinfo,imap,ldap,calendar,phalcon,yaf,yar,redis,memcached,
                                memcache,mongodb,swoole,xdebug
  --pureftpd                    Uninstall PureFtpd
  --redis                       Uninstall Redis-server
  --valkey                      Uninstall Valkey-server
  --memcached                   Uninstall Memcached-server
  --clickhouse                  Uninstall ClickHouse
  --phpmyadmin                  Uninstall phpMyAdmin
  --nodejs                      Uninstall Nodejs (PATH: ${nodejs_install_dir})
  --supervisor                  卸载 Supervisor（仅当是 Lemon 装的时候）
  --addons                      卸载 Lemon 装过的附加组件：supervisor/composer/
                                fail2ban/ngx_lua_waf/python（没有标记的一律跳过）
  "
}

ARG_NUM=$#
# 无参数时进交互菜单；stdin 不是终端时 read 会立刻返回 EOF，
# Menu 里的 while : 拿不到值又不 break，会空转把 CPU 烧满。
if [ "${ARG_NUM}" == '0' ] && [ ! -t 0 ]; then
  echo "非交互环境：请带上参数运行，$0 --help 查看可用参数"
  exit 1
fi
TEMP=`getopt -o hq --long help,version,quiet,all,purge,purge-data,supervisor,addons,web,mysql,postgresql,mongodb,php,mphp_ver:,allphp,phpcache,php_extensions:,pureftpd,redis,valkey,memcached,phpmyadmin,nodejs,clickhouse -- "$@" 2>/dev/null`
[ $? != 0 ] && echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
# 全量卸载的组件组合，--all / --purge / --purge-data 共用
Set_All_Flags() {
  all_flag=y
  web_flag=y
  mysql_flag=y
  postgresql_flag=y
  mongodb_flag=y
  allphp_flag=y
  nodejs_flag=y
  pureftpd_flag=y
  redis_flag=y
  memcached_flag=y
  valkey_flag=y
  clickhouse_flag=y
  phpmyadmin_flag=y
  # 附加组件也一起走，但每一项在 Uninstall_* 内部都要先查 Lemon 的安装标记
  # （/etc/lemon/installed/<name>）。没有标记的一律跳过——它们可能是机器上
  # 本来就装好的，删掉会破坏用户原有环境。
  addons_flag=y
}

eval set -- "${TEMP}"
while :; do
  [ -z "$1" ] && break;
  case "$1" in
    -h|--help)
      Show_Help; exit 0
      ;;
    -q|--quiet)
      quiet_flag=y
      uninstall_flag=y
      shift 1
      ;;
    --all)
      Set_All_Flags
      shift 1
      ;;
    --purge)
      Set_All_Flags
      purge_flag=y
      shift 1
      ;;
    --purge-data)
      Set_All_Flags
      purge_flag=y
      purge_data_flag=y
      shift 1
      ;;
    --supervisor)
      supervisor_flag=y
      shift 1
      ;;
    --addons)
      addons_flag=y
      shift 1
      ;;
    --web)
      web_flag=y; shift 1
      ;;
    --mysql)
      mysql_flag=y; shift 1
      ;;
    --postgresql)
      postgresql_flag=y; shift 1
      ;;
    --mongodb)
      mongodb_flag=y; shift 1
      ;;
    --php)
      php_flag=y; shift 1
      ;;
    --mphp_ver)
      mphp_ver=$2; mphp_flag=y; shift 2
      [[ ! "${mphp_ver}" =~ ^74$|^8[0-5]$ ]] && { echo "${CWARNING}mphp_ver input error! Please only input number 74~85${CEND}"; exit 1; }
      ;;
    --allphp)
      allphp_flag=y; shift 1
      ;;
    --phpcache)
      phpcache_flag=y; shift 1
      ;;
    --php_extensions)
      php_extensions=$2; shift 2
      [ -n "`echo ${php_extensions} | grep -w ioncube`" ] && pecl_ioncube=1
      [ -n "`echo ${php_extensions} | grep -w imagick`" ] && pecl_imagick=1
      [ -n "`echo ${php_extensions} | grep -w gmagick`" ] && pecl_gmagick=1
      [ -n "`echo ${php_extensions} | grep -w fileinfo`" ] && pecl_fileinfo=1
      [ -n "`echo ${php_extensions} | grep -w imap`" ] && pecl_imap=1
      [ -n "`echo ${php_extensions} | grep -w ldap`" ] && pecl_ldap=1
      [ -n "`echo ${php_extensions} | grep -w calendar`" ] && pecl_calendar=1
      [ -n "`echo ${php_extensions} | grep -w phalcon`" ] && pecl_phalcon=1
      [ -n "`echo ${php_extensions} | grep -w yaf`" ] && pecl_yaf=1
      [ -n "`echo ${php_extensions} | grep -w yar`" ] && pecl_yar=1
      [ -n "`echo ${php_extensions} | grep -w redis`" ] && pecl_redis=1
      [ -n "`echo ${php_extensions} | grep -w memcached`" ] && pecl_memcached=1
      [ -n "`echo ${php_extensions} | grep -w memcache`" ] && pecl_memcache=1
      [ -n "`echo ${php_extensions} | grep -w mongodb`" ] && pecl_mongodb=1
      [ -n "`echo ${php_extensions} | grep -w swoole`" ] && pecl_swoole=1
      [ -n "`echo ${php_extensions} | grep -w xdebug`" ] && pecl_xdebug=1
      ;;
    --nodejs)
      nodejs_flag=y; shift 1
      ;;
    --pureftpd)
      pureftpd_flag=y; shift 1
      ;;
    --redis)
      redis_flag=y; shift 1
      ;;
    --valkey)
      valkey_flag=y; shift 1
      ;;
    --memcached)
      memcached_flag=y; shift 1
      ;;
    --clickhouse)
      clickhouse_flag=y; shift 1
      ;;
    --phpmyadmin)
      phpmyadmin_flag=y; shift 1
      ;;
    --)
      shift
      ;;
    *)
      echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
      ;;
  esac
done

Uninstall_status() {
  if [ "${quiet_flag}" != 'y' ]; then
    # 没有终端（CI、管道、nohup）时 read 会一直拿到 EOF，无限打印 input error 卡死。
    # 直接告诉调用方加 -q。
    if [ ! -t 0 ]; then
      echo "${CFAILURE}非交互环境：确认要卸载请加 -q 参数重新执行${CEND}"
      exit 1
    fi
    while :; do echo
      read -e -p "Do you want to uninstall? [y/n]: " uninstall_flag
      if [[ ! ${uninstall_flag} =~ ^[y,n]$ ]]; then
        echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
      else
        break
      fi
    done
  fi
}

# 卸载时数据目录只改名、不删除。用秒级时间戳，撞名再加 PID 兜底——
# 原来用 %Y%m%d%H，同一小时内卸载两次会 mv 到已存在的目录，报
# "Directory not empty"，数据既没备份到位、也没提示失败。
move_data_aside() {
  local src="$1" bak
  [ -e "${src}" ] || return 0
  bak="${src}_$(date +%Y%m%d%H%M%S)"
  [ -e "${bak}" ] && bak="${bak}_$$"
  /bin/mv "${src}" "${bak}"
}

Print_Warn() {
  echo
  echo "${CWARNING}You will uninstall Lemon, Please backup your configure files and DB data! ${CEND}"
}

Print_web() {
  [ -d "${nginx_install_dir}" ] && echo ${nginx_install_dir}
  [ -d "${tengine_install_dir}" ] && echo ${tengine_install_dir}
  [ -d "${openresty_install_dir}" ] && echo ${openresty_install_dir}
  [ -e "/etc/init.d/nginx" ] && echo /etc/init.d/nginx
  [ -e "/lib/systemd/system/nginx.service" ] && echo /lib/systemd/system/nginx.service
  [ -e "/etc/logrotate.d/nginx" ] && echo /etc/logrotate.d/nginx

  [ -d "${caddy_install_dir}" ] && echo ${caddy_install_dir}
  [ -e "/lib/systemd/system/caddy.service" ] && echo /lib/systemd/system/caddy.service

  [ -d "${apache_install_dir}" ] && echo ${apache_install_dir}
  [ -e "/lib/systemd/system/httpd.service" ] && echo /lib/systemd/system/httpd.service
  [ -e "/etc/init.d/httpd" ] && echo /etc/init.d/httpd
  [ -e "/etc/logrotate.d/apache" ] && echo /etc/logrotate.d/apache

  [ -d "/usr/java" ] && echo /usr/java
  [ -d "${apr_install_dir}" ] && echo ${apr_install_dir}
}

Uninstall_Web() {
  [ -d "${nginx_install_dir}" ] && { killall nginx > /dev/null 2>&1; rm -rf ${nginx_install_dir} /etc/init.d/nginx /etc/logrotate.d/nginx; sed -i "s@${nginx_install_dir}/sbin:@@" /etc/profile; echo "${CMSG}Nginx uninstall completed! ${CEND}"; }
  [ -d "${tengine_install_dir}" ] && { killall nginx > /dev/null 2>&1; rm -rf ${tengine_install_dir} /etc/init.d/nginx /etc/logrotate.d/nginx; sed -i "s@${tengine_install_dir}/sbin:@@" /etc/profile; echo "${CMSG}Tengine uninstall completed! ${CEND}"; }
  [ -d "${openresty_install_dir}" ] && { killall nginx > /dev/null 2>&1; rm -rf ${openresty_install_dir} /etc/init.d/nginx /etc/logrotate.d/nginx; sed -i "s@${openresty_install_dir}/nginx/sbin:@@" /etc/profile; echo "${CMSG}OpenResty uninstall completed! ${CEND}"; }
  [ -d "${caddy_install_dir}" ] && { killall caddy > /dev/null 2>&1; rm -rf ${caddy_install_dir} /etc/init.d/caddy /etc/logrotate.d/caddy; sed -i "s@${caddy_install_dir}/bin:@@" /etc/profile; echo "${CMSG}Caddy uninstall completed! ${CEND}"; }
  [ -e "/lib/systemd/system/nginx.service" ] && { systemctl disable nginx > /dev/null 2>&1; rm -f /lib/systemd/system/nginx.service; }
  [ -e "/lib/systemd/system/caddy.service" ] && { systemctl disable caddy > /dev/null 2>&1; rm -f /lib/systemd/system/caddy.service; }
  [ -d "${apache_install_dir}" ] && { service httpd stop > /dev/null 2>&1; rm -rf ${apache_install_dir} /etc/init.d/httpd /etc/logrotate.d/apache; sed -i "s@${apache_install_dir}/bin:@@" /etc/profile; echo "${CMSG}Apache uninstall completed! ${CEND}"; }
  [ -e "/lib/systemd/system/httpd.service" ] && { systemctl disable httpd > /dev/null 2>&1; rm -f /lib/systemd/system/httpd.service; }
  [ -d "/usr/java" ] && { rm -rf /usr/java; sed -i '/export JAVA_HOME=/d' /etc/profile; sed -i '/export CLASSPATH=/d' /etc/profile; sed -i 's@\$JAVA_HOME/bin:@@' /etc/profile; }
  move_data_aside "${wwwroot_dir}"
  # 只删 Lemon 自己写的登录配置。www 账号不删：它可能是机器上原有的
  # （很多镜像自带 www 用户），删掉会让原有站点全部失去属主
  rm -f /etc/profile.d/lemon.sh
  sed -i 's@^website_name=.*@website_name=@' ./options.conf
  sed -i 's@^backup_content=.*@backup_content=@' ./options.conf
  [ -d "${apr_install_dir}" ] && rm -rf ${apr_install_dir}
}

Print_MySQL() {
  [ -e "${db_install_dir}" ] && echo ${db_install_dir}
  [ -e "/etc/init.d/mysqld" ] && echo /etc/init.d/mysqld
  [ -e "/etc/my.cnf" ] && echo /etc/my.cnf
}

Print_PostgreSQL() {
  [ -e "${pgsql_install_dir}" ] && echo ${pgsql_install_dir}
  [ -e "/etc/init.d/postgresql" ] && echo /etc/init.d/postgresql
  [ -e "/lib/systemd/system/postgresql.service" ] && echo /lib/systemd/system/postgresql.service
}

Print_MongoDB() {
  [ -e "${mongo_install_dir}" ] && echo ${mongo_install_dir}
  [ -e "/etc/init.d/mongod" ] && echo /etc/init.d/mongod
  [ -e "/lib/systemd/system/mongod.service" ] && echo /lib/systemd/system/mongod.service
  [ -e "/etc/mongod.conf" ] && echo /etc/mongod.conf
}

Uninstall_MySQL() {
  # uninstall mysql,mariadb,percona
  if [ -d "${db_install_dir}/support-files" ]; then
    service mysqld stop > /dev/null 2>&1
    # stop 是异步返回的；只要还有以 mysql 身份运行的进程（mysqld / mariadbd / mysqld_safe），
    # userdel 就会报 "user is currently used by process"，账号留在机器上。
    for i in 1 2 3 4 5 6 7 8 9 10; do
      pgrep -u mysql > /dev/null 2>&1 || break
      sleep 1
    done
    rm -rf ${db_install_dir} /etc/init.d/mysqld /etc/my.cnf* /etc/ld.so.conf.d/*{mysql,mariadb,percona}*.conf
    id -u mysql >/dev/null 2>&1 ; [ $? -eq 0 ] && userdel mysql
    move_data_aside "${db_data_dir}"
    sed -i 's@^dbrootpwd=.*@dbrootpwd=@' ./options.conf
    sed -i "s@${db_install_dir}/bin:@@" /etc/profile
    echo "${CMSG}MySQL uninstall completed! ${CEND}"
  fi
}

Uninstall_PostgreSQL() {
  # uninstall postgresql
  if [ -e "${pgsql_install_dir}/bin/psql" ]; then
    service postgresql stop > /dev/null 2>&1
    rm -rf ${pgsql_install_dir} /etc/init.d/postgresql
    [ -e "/lib/systemd/system/postgresql.service" ] && { systemctl disable postgresql > /dev/null 2>&1; rm -f /lib/systemd/system/postgresql.service; }
    [ -e "${php_install_dir}/etc/php.d/07-pgsql.ini" ] && rm -f ${php_install_dir}/etc/php.d/07-pgsql.ini
    id -u postgres >/dev/null 2>&1 ; [ $? -eq 0 ] && userdel postgres
    move_data_aside "${pgsql_data_dir}"
    sed -i 's@^dbpostgrespwd=.*@dbpostgrespwd=@' ./options.conf
    sed -i "s@${pgsql_install_dir}/bin:@@" /etc/profile
    echo "${CMSG}PostgreSQL uninstall completed! ${CEND}"
  fi
}

Uninstall_MongoDB() {
  # uninstall mongodb
  if [ -e "${mongo_install_dir}/bin/mongod" ]; then
    systemctl stop mongod > /dev/null 2>&1
    rm -rf ${mongo_install_dir} /etc/mongod.conf /etc/init.d/mongod /tmp/mongo*.sock
    [ -e "/lib/systemd/system/mongod.service" ] && { systemctl disable mongod > /dev/null 2>&1; rm -f /lib/systemd/system/mongod.service; }
    [ -e "${php_install_dir}/etc/php.d/07-mongo.ini" ] && rm -f ${php_install_dir}/etc/php.d/07-mongo.ini
    [ -e "${php_install_dir}/etc/php.d/07-mongodb.ini" ] && rm -f ${php_install_dir}/etc/php.d/07-mongodb.ini
    id -u mongod > /dev/null 2>&1 ; [ $? -eq 0 ] && userdel mongod
    move_data_aside "${mongo_data_dir}"
    sed -i 's@^dbmongopwd=.*@dbmongopwd=@' ./options.conf
    sed -i "s@${mongo_install_dir}/bin:@@" /etc/profile
    echo "${CMSG}MongoDB uninstall completed! ${CEND}"
  fi
}

Print_PHP() {
  [ -e "${php_install_dir}" ] && echo ${php_install_dir}
  [ -e "/etc/init.d/php-fpm" ] && echo /etc/init.d/php-fpm
  [ -e "/lib/systemd/system/php-fpm.service" ] && echo /lib/systemd/system/php-fpm.service
}

Print_MPHP() {
  [ -e "${php_install_dir}${mphp_ver}" ] && echo ${php_install_dir}${mphp_ver}
  [ -e "/etc/init.d/php${mphp_ver}-fpm" ] && echo /etc/init.d/php${mphp_ver}-fpm
  [ -e "/lib/systemd/system/php${mphp_ver}-fpm.service" ] && echo /lib/systemd/system/php${mphp_ver}-fpm.service
}

Print_ALLPHP() {
  [ -e "${php_install_dir}" ] && echo ${php_install_dir}
  [ -e "/etc/init.d/php-fpm" ] && echo /etc/init.d/php-fpm
  [ -e "/lib/systemd/system/php-fpm.service" ] && echo /lib/systemd/system/php-fpm.service
  for php_ver in 74 80 81 82 83 84 85; do
    [ -e "${php_install_dir}${php_ver}" ] && echo ${php_install_dir}${php_ver}
    [ -e "/etc/init.d/php${php_ver}-fpm" ] && echo /etc/init.d/php${php_ver}-fpm
    [ -e "/lib/systemd/system/php${php_ver}-fpm.service" ] && echo /lib/systemd/system/php${php_ver}-fpm.service
  done
  [ -e "${imagick_install_dir}" ] && echo ${imagick_install_dir}
  [ -e "${gmagick_install_dir}" ] && echo ${gmagick_install_dir}
  [ -e "${curl_install_dir}" ] && echo ${curl_install_dir}
  [ -e "${freetype_install_dir}" ] && echo ${freetype_install_dir}
}

Uninstall_PHP() {
  [ -e "/etc/init.d/php-fpm" ] && { service php-fpm stop > /dev/null 2>&1; rm -f /etc/init.d/php-fpm; }
  [ -e "/lib/systemd/system/php-fpm.service" ] && { systemctl stop php-fpm > /dev/null 2>&1; systemctl disable php-fpm > /dev/null 2>&1; rm -f /lib/systemd/system/php-fpm.service; }
  [ -e "${apache_install_dir}/conf/httpd.conf" ] && [ -n "`grep libphp ${apache_install_dir}/conf/httpd.conf`" ] && sed -i '/libphp/d' ${apache_install_dir}/conf/httpd.conf
  [ -e "${php_install_dir}" ] && { rm -rf ${php_install_dir}; echo "${CMSG}PHP uninstall completed! ${CEND}"; }
  sed -i "s@${php_install_dir}/bin:@@" /etc/profile
}

Uninstall_MPHP() {
  [ -e "/etc/init.d/php${mphp_ver}-fpm" ] && { service php${mphp_ver}-fpm stop > /dev/null 2>&1; rm -f /etc/init.d/php${mphp_ver}-fpm; }
  [ -e "/lib/systemd/system/php${mphp_ver}-fpm.service" ] && { systemctl stop php${mphp_ver}-fpm > /dev/null 2>&1; systemctl disable php${mphp_ver}-fpm > /dev/null 2>&1; rm -f /lib/systemd/system/php${mphp_ver}-fpm.service; }
  [ -e "${php_install_dir}${mphp_ver}" ] && { rm -rf ${php_install_dir}${mphp_ver}; echo "${CMSG}PHP${mphp_ver} uninstall completed! ${CEND}"; }
}

Uninstall_ALLPHP() {
  [ -e "/etc/init.d/php-fpm" ] && { service php-fpm stop > /dev/null 2>&1; rm -f /etc/init.d/php-fpm; }
  [ -e "/lib/systemd/system/php-fpm.service" ] && { systemctl stop php-fpm > /dev/null 2>&1; systemctl disable php-fpm > /dev/null 2>&1; rm -f /lib/systemd/system/php-fpm.service; }
  [ -e "${apache_install_dir}/conf/httpd.conf" ] && [ -n "`grep libphp ${apache_install_dir}/conf/httpd.conf`" ] && sed -i '/libphp/d' ${apache_install_dir}/conf/httpd.conf
  [ -e "${php_install_dir}" ] && { rm -rf ${php_install_dir}; echo "${CMSG}PHP uninstall completed! ${CEND}"; }
  sed -i "s@${php_install_dir}/bin:@@" /etc/profile
  for php_ver in 74 80 81 82 83 84 85; do
    [ -e "/etc/init.d/php${php_ver}-fpm" ] && { service php${php_ver}-fpm stop > /dev/null 2>&1; rm -f /etc/init.d/php${php_ver}-fpm; }
    [ -e "/lib/systemd/system/php${php_ver}-fpm.service" ] && { systemctl stop php${php_ver}-fpm > /dev/null 2>&1; systemctl disable php${php_ver}-fpm > /dev/null 2>&1; rm -f /lib/systemd/system/php${php_ver}-fpm.service; }
    [ -e "${php_install_dir}${php_ver}" ] && { rm -rf ${php_install_dir}${php_ver}; echo "${CMSG}PHP${php_ver} uninstall completed! ${CEND}"; }
  done
  [ -e "${imagick_install_dir}" ] && rm -rf ${imagick_install_dir}
  [ -e "${gmagick_install_dir}" ] && rm -rf ${gmagick_install_dir}
  [ -e "${curl_install_dir}" ] && rm -rf ${curl_install_dir}
  [ -e "${freetype_install_dir}" ] && rm -rf ${freetype_install_dir}
}

Uninstall_PHPcache() {
  # mphp 卸载时真正的目标目录是 php_install_dir+mphp_ver。在函数内自己切换、结束前还原，
  # 不靠调用方改写全局 php_install_dir——否则与扩展卸载连用会把 mphp_ver 拼两遍（/usr/local/php8080）
  local base_dir="${php_install_dir}"
  [ "${mphp_flag}" == 'y' ] && php_install_dir="${base_dir}${mphp_ver}"
  . include/zendopcache.sh
  . include/apcu.sh
  Uninstall_ZendOPcache
  Uninstall_APCU
  # reload php：先还原成主目录，主 PHP 与 mPHP 各自按自己的路径判断
  php_install_dir="${base_dir}"
  [ -e "${php_install_dir}/sbin/php-fpm" ] && { [ -e "/bin/systemctl" ] && systemctl reload php-fpm || service php-fpm reload; }
  [ -n "${mphp_ver}" -a -e "${php_install_dir}${mphp_ver}/sbin/php-fpm" ] && { [ -e "/bin/systemctl" ] && systemctl reload php${mphp_ver}-fpm || service php${mphp_ver}-fpm reload; }
  [ -e "${apache_install_dir}/bin/apachectl" ] && ${apache_install_dir}/bin/apachectl -k graceful
}

Uninstall_PHPext() {
  # mphp 卸载时真正的目标目录是 php_install_dir+mphp_ver。在函数内自己切换、结束前还原，
  # 不靠调用方改写全局 php_install_dir——否则与 opcode cache 卸载连用会拼出 /usr/local/php8080
  local base_dir="${php_install_dir}"
  [ "${mphp_flag}" == 'y' ] && php_install_dir="${base_dir}${mphp_ver}"

  # ioncube
  if [ "${pecl_ioncube}" == '1' ]; then
    . include/ioncube.sh
    Uninstall_ionCube
  fi

  # imagick
  if [ "${pecl_imagick}" == '1' ]; then
    . include/ImageMagick.sh
    Uninstall_ImageMagick
    Uninstall_pecl_imagick
  fi

  # gmagick
  if [ "${pecl_gmagick}" == '1' ]; then
    . include/GraphicsMagick.sh
    Uninstall_GraphicsMagick
    Uninstall_pecl_gmagick
  fi

  # fileinfo
  if [ "${pecl_fileinfo}" == '1' ]; then
    . include/pecl_fileinfo.sh
    Uninstall_pecl_fileinfo
  fi

  # imap
  if [ "${pecl_imap}" == '1' ]; then
    . include/pecl_imap.sh
    Uninstall_pecl_imap
  fi

  # ldap
  if [ "${pecl_ldap}" == '1' ]; then
    . include/pecl_ldap.sh
    Uninstall_pecl_ldap
  fi

  # calendar
  if [ "${pecl_calendar}" == '1' ]; then
    . include/pecl_calendar.sh
    Uninstall_pecl_calendar
  fi

  # phalcon
  if [ "${pecl_phalcon}" == '1' ]; then
    . include/pecl_phalcon.sh
    Uninstall_pecl_phalcon
  fi

  # yaf
  if [ "${pecl_yaf}" == '1' ]; then
    . include/pecl_yaf.sh
    Uninstall_pecl_yaf 2>&1 | tee -a ${lemon_dir}/install.log
  fi

  # yar
  if [ "${pecl_yar}" == '1' ]; then
    . include/pecl_yar.sh
    Uninstall_pecl_yar 2>&1 | tee -a ${lemon_dir}/install.log
  fi

  # pecl_memcached
  if [ "${pecl_memcached}" == '1' ]; then
    . include/memcached.sh
    Uninstall_pecl_memcached
  fi

  # pecl_memcache
  if [ "${pecl_memcache}" == '1' ]; then
    . include/memcached.sh
    Uninstall_pecl_memcache
  fi

  # pecl_redis
  if [ "${pecl_redis}" == '1' ]; then
    . include/redis.sh
    Uninstall_pecl_redis
  fi

  # pecl_mongodb
  if [ "${pecl_mongodb}" == '1' ]; then
    . include/pecl_mongodb.sh
    Uninstall_pecl_mongodb
  fi

  # swoole
  if [ "${pecl_swoole}" == '1' ]; then
    . include/pecl_swoole.sh
    Uninstall_pecl_swoole
  fi

  # xdebug
  if [ "${pecl_xdebug}" == '1' ]; then
    . include/pecl_xdebug.sh
    Uninstall_pecl_xdebug
  fi

  # reload php
  php_install_dir="${base_dir}"
  [ -e "${php_install_dir}/sbin/php-fpm" ] && { [ -e "/bin/systemctl" ] && systemctl reload php-fpm || service php-fpm reload; }
  [ -n "${mphp_ver}" -a -e "${php_install_dir}${mphp_ver}/sbin/php-fpm" ] && { [ -e "/bin/systemctl" ] && systemctl reload php${mphp_ver}-fpm || service php${mphp_ver}-fpm reload; }
  [ -e "${apache_install_dir}/bin/apachectl" ] && ${apache_install_dir}/bin/apachectl -k graceful
}

Menu_PHPext() {
  while :; do
    echo 'Please select uninstall PHP extensions:'
    echo -e "\t${CMSG} 0${CEND}. Do not uninstall"
    echo -e "\t${CMSG} 1${CEND}. Uninstall ioncube"
    echo -e "\t${CMSG} 2${CEND}. Uninstall imagick"
    echo -e "\t${CMSG} 3${CEND}. Uninstall gmagick"
    echo -e "\t${CMSG} 4${CEND}. Uninstall fileinfo"
    echo -e "\t${CMSG} 5${CEND}. Uninstall imap"
    echo -e "\t${CMSG} 6${CEND}. Uninstall ldap"
    echo -e "\t${CMSG} 7${CEND}. Uninstall phalcon"
    echo -e "\t${CMSG} 8${CEND}. Uninstall yaf"
    echo -e "\t${CMSG} 9${CEND}. Uninstall redis"
    echo -e "\t${CMSG}10${CEND}. Uninstall memcached"
    echo -e "\t${CMSG}11${CEND}. Uninstall memcache"
    echo -e "\t${CMSG}12${CEND}. Uninstall mongodb"
    echo -e "\t${CMSG}13${CEND}. Uninstall swoole"
    echo -e "\t${CMSG}14${CEND}. Uninstall xdebug"
    read -e -p "Please input a number:(Default 0 press Enter) " phpext_option
    phpext_option=${phpext_option:-0}
    [ "${phpext_option}" == '0' ] && break
    array_phpext=(${phpext_option})
    array_all=(1 2 3 4 5 6 7 8 9 10 11 12 13 14)
    for v in ${array_phpext[@]}
    do
      [ -z "`echo ${array_all[@]} | grep -w ${v}`" ] && phpext_flag=1
    done
    if [ "${phpext_flag}" == '1' ]; then
      unset phpext_flag
      echo; echo "${CWARNING}input error! Please only input number 1 2 3 14 and so on${CEND}"; echo
      continue
    else
      [ -n "`echo ${array_phpext[@]} | grep -w 1`" ] && pecl_ioncube=1
      [ -n "`echo ${array_phpext[@]} | grep -w 2`" ] && pecl_imagick=1
      [ -n "`echo ${array_phpext[@]} | grep -w 3`" ] && pecl_gmagick=1
      [ -n "`echo ${array_phpext[@]} | grep -w 4`" ] && pecl_fileinfo=1
      [ -n "`echo ${array_phpext[@]} | grep -w 5`" ] && pecl_imap=1
      [ -n "`echo ${array_phpext[@]} | grep -w 6`" ] && pecl_ldap=1
      [ -n "`echo ${array_phpext[@]} | grep -w 7`" ] && pecl_phalcon=1
      [ -n "`echo ${array_phpext[@]} | grep -w 8`" ] && pecl_yaf=1
      [ -n "`echo ${array_phpext[@]} | grep -w 9`" ] && pecl_redis=1
      [ -n "`echo ${array_phpext[@]} | grep -w 10`" ] && pecl_memcached=1
      [ -n "`echo ${array_phpext[@]} | grep -w 11`" ] && pecl_memcache=1
      [ -n "`echo ${array_phpext[@]} | grep -w 12`" ] && pecl_mongodb=1
      [ -n "`echo ${array_phpext[@]} | grep -w 13`" ] && pecl_swoole=1
      [ -n "`echo ${array_phpext[@]} | grep -w 14`" ] && pecl_xdebug=1
      break
    fi
  done
}

Print_PureFtpd() {
  [ -e "${pureftpd_install_dir}" ] && echo ${pureftpd_install_dir}
  [ -e "/etc/init.d/pureftpd" ] && echo /etc/init.d/pureftpd
  [ -e "/lib/systemd/system/pureftpd.service" ] && echo /lib/systemd/system/pureftpd.service
}

Uninstall_PureFtpd() {
  [ -e "${pureftpd_install_dir}" ] && { service pureftpd stop > /dev/null 2>&1; rm -rf ${pureftpd_install_dir} /etc/init.d/pureftpd; echo "${CMSG}Pureftpd uninstall completed! ${CEND}"; }
  [ -e "/lib/systemd/system/pureftpd.service" ] && { systemctl disable pureftpd > /dev/null 2>&1; rm -f /lib/systemd/system/pureftpd.service; }
}

Print_Redis_server() {
  [ -e "${redis_install_dir}" ] && echo ${redis_install_dir}
  [ -e "/etc/init.d/redis-server" ] && echo /etc/init.d/redis-server
  [ -e "/lib/systemd/system/redis-server.service" ] && echo /lib/systemd/system/redis-server.service
}

Uninstall_Redis_server() {
  [ -e "${redis_install_dir}" ] && { service redis-server stop > /dev/null 2>&1; rm -rf ${redis_install_dir} /etc/init.d/redis-server /usr/local/bin/redis-*; echo "${CMSG}Redis uninstall completed! ${CEND}"; }
  [ -e "/lib/systemd/system/redis-server.service" ] && { systemctl disable redis-server > /dev/null 2>&1; rm -f /lib/systemd/system/redis-server.service; }
}

Print_Valkey() {
  [ -e "${valkey_install_dir}" ] && echo ${valkey_install_dir}
  [ -e "/lib/systemd/system/valkey-server.service" ] && echo /lib/systemd/system/valkey-server.service
}

Uninstall_Valkey() {
  [ -e "${valkey_install_dir}" ] && {
    systemctl stop valkey-server > /dev/null 2>&1
    systemctl disable valkey-server > /dev/null 2>&1
    rm -rf ${valkey_install_dir} /usr/local/bin/valkey-* /var/run/valkey
    echo "${CMSG}Valkey uninstall completed! ${CEND}"
  }
  [ -e "/lib/systemd/system/valkey-server.service" ] && { rm -f /lib/systemd/system/valkey-server.service; systemctl daemon-reload > /dev/null 2>&1; }
}

Print_ClickHouse() {
  [ -e "${clickhouse_install_dir}" ] && echo ${clickhouse_install_dir}
  [ -e "/lib/systemd/system/clickhouse-server.service" ] && echo /lib/systemd/system/clickhouse-server.service
}

Uninstall_ClickHouse() {
  [ -e "${clickhouse_install_dir}" ] && {
    systemctl stop clickhouse-server > /dev/null 2>&1
    systemctl disable clickhouse-server > /dev/null 2>&1
    rm -rf ${clickhouse_install_dir} /etc/clickhouse-server /etc/clickhouse-client /var/log/clickhouse-server
    rm -f /usr/local/bin/clickhouse /usr/local/bin/clickhouse-server /usr/local/bin/clickhouse-client
    echo "${CMSG}ClickHouse uninstall completed! ${CEND}"
  }
  [ -e "/lib/systemd/system/clickhouse-server.service" ] && { rm -f /lib/systemd/system/clickhouse-server.service; systemctl daemon-reload > /dev/null 2>&1; }
}

Print_Memcached_server() {
  [ -e "${memcached_install_dir}" ] && echo ${memcached_install_dir}
  [ -e "/etc/init.d/memcached" ] && echo /etc/init.d/memcached
  [ -e "/usr/bin/memcached" ] && echo /usr/bin/memcached
}

Uninstall_Memcached_server() {
  if [ -e "${memcached_install_dir}" ] || [ -e "/lib/systemd/system/memcached.service" ]; then
    systemctl stop memcached > /dev/null 2>&1
    systemctl disable memcached > /dev/null 2>&1
    rm -rf ${memcached_install_dir} /etc/init.d/memcached /usr/bin/memcached
    # 单元文件是 Lemon 从 init.d/ 拷过去的，不删会留下一个指向已删除二进制的
    # 悬空 unit，systemctl --failed 里一直有一条
    rm -f /lib/systemd/system/memcached.service
    systemctl daemon-reload > /dev/null 2>&1
    echo "${CMSG}Memcached uninstall completed! ${CEND}"
  fi
}

Print_phpMyAdmin() {
  [ -d "${wwwroot_dir}/default/phpMyAdmin" ] && echo ${wwwroot_dir}/default/phpMyAdmin
}

Uninstall_phpMyAdmin() {
  [ -d "${wwwroot_dir}/default/phpMyAdmin" ] && rm -rf ${wwwroot_dir}/default/phpMyAdmin
}

Print_Nodejs() {
  [ -e "${nodejs_install_dir}" ] && echo ${nodejs_install_dir}
  [ -e "/etc/profile.d/nodejs.sh" ] && echo /etc/profile.d/nodejs.sh
}

Menu() {
while :; do
  printf "
What Are You Doing?
\t${CMSG} 0${CEND}. Uninstall All
\t${CMSG} 1${CEND}. Uninstall Nginx/Tengine/OpenResty/Apache/Caddy
\t${CMSG} 2${CEND}. Uninstall MySQL/MariaDB/Percona
\t${CMSG} 3${CEND}. Uninstall PostgreSQL
\t${CMSG} 4${CEND}. Uninstall MongoDB
\t${CMSG} 5${CEND}. Uninstall all PHP
\t${CMSG} 6${CEND}. Uninstall PHP opcode cache
\t${CMSG} 7${CEND}. Uninstall PHP extensions
\t${CMSG} 8${CEND}. Uninstall PureFtpd
\t${CMSG} 9${CEND}. Uninstall Redis
\t${CMSG}10${CEND}. Uninstall Memcached
\t${CMSG}11${CEND}. Uninstall phpMyAdmin
\t${CMSG}12${CEND}. Uninstall Nodejs (PATH: ${nodejs_install_dir})
\t${CMSG} q${CEND}. Exit
"
  echo
  read -e -p "Please input the correct option: " Number
  if [[ ! "${Number}" =~ ^[0-9,q]$|^1[0-3]$ ]]; then
    echo "${CWARNING}input error! Please only input 0~12 and q${CEND}"
  else
    case "$Number" in
    0)
      Print_Warn
      Print_web
      Print_MySQL
      Print_PostgreSQL
      Print_MongoDB
      Print_ALLPHP
      Print_PureFtpd
      Print_Redis_server
      Print_Valkey
      Print_ClickHouse
      Print_Memcached_server
      Print_phpMyAdmin
      Print_Nodejs
      Uninstall_status
      if [ "${uninstall_flag}" == 'y' ]; then
        Uninstall_Web
        Uninstall_MySQL
        Uninstall_PostgreSQL
        Uninstall_MongoDB
        Uninstall_ALLPHP
        Uninstall_PureFtpd
        Uninstall_Redis_server
        Uninstall_Memcached_server
        Uninstall_phpMyAdmin
        . include/nodejs.sh; Uninstall_Nodejs
      else
        exit
      fi
      ;;
    1)
      Print_Warn
      Print_web
      Uninstall_status
      [ "${uninstall_flag}" == 'y' ] && Uninstall_Web || exit
      ;;
    2)
      Print_Warn
      Print_MySQL
      Uninstall_status
      [ "${uninstall_flag}" == 'y' ] && Uninstall_MySQL || exit
      ;;
    3)
      Print_Warn
      Print_PostgreSQL
      Uninstall_status
      [ "${uninstall_flag}" == 'y' ] && Uninstall_PostgreSQL || exit
      ;;
    4)
      Print_Warn
      Print_MongoDB
      Uninstall_status
      [ "${uninstall_flag}" == 'y' ] && Uninstall_MongoDB || exit
      ;;
    5)
      Print_ALLPHP
      Uninstall_status
      [ "${uninstall_flag}" == 'y' ] && Uninstall_ALLPHP || exit
      ;;
    6)
      Uninstall_status
      [ "${uninstall_flag}" == 'y' ] && Uninstall_PHPcache || exit
      ;;
    7)
      Menu_PHPext
      # 选 0 表示不卸载：置回 uninstall_flag（防止沿用上一轮的 y），回到菜单而不是退出
      if [ "${phpext_option}" == '0' ]; then
        uninstall_flag='n'
        continue
      fi
      Uninstall_status
      [ "${uninstall_flag}" == 'y' ] && Uninstall_PHPext || exit
      ;;
    8)
      Print_PureFtpd
      Uninstall_status
      [ "${uninstall_flag}" == 'y' ] && Uninstall_PureFtpd || exit
      ;;
    9)
      Print_Redis_server
      Uninstall_status
      [ "${uninstall_flag}" == 'y' ] && Uninstall_Redis_server || exit
      ;;
    10)
      Print_Memcached_server
      Uninstall_status
      [ "${uninstall_flag}" == 'y' ] && Uninstall_Memcached_server || exit
      ;;
    11)
      Print_phpMyAdmin
      Uninstall_status
      [ "${uninstall_flag}" == 'y' ] && Uninstall_phpMyAdmin || exit
      ;;
    12)
      Print_Nodejs
      Uninstall_status
      [ "${uninstall_flag}" == 'y' ] && { . include/nodejs.sh; Uninstall_Nodejs; } || exit
      ;;
    q)
      exit
      ;;
    esac
  fi
done
}


# 附加组件。每个 Uninstall_* 内部都会调 addon_uninstall_guard，
# 没有 Lemon 标记的直接 return，不会碰系统里原有的同类软件。
Uninstall_Addons() {
  . include/addon_mark.sh
  . include/supervisor.sh
  Uninstall_supervisor
  . include/composer.sh
  Uninstall_composer
  . include/fail2ban.sh
  Uninstall_fail2ban
  . include/python.sh
  Uninstall_Python
  # ngx_lua_waf 要在 nginx 目录还在的时候关掉，必须排在 Uninstall_Web 前面
  . include/ngx_lua_waf.sh
  disable_lua_waf
}

# ---------- --purge / --purge-data ----------
#
# 原则：只删 Lemon 自己写出来的文件。系统包、/usr/local 下的公共库、系统账号
# 一律不碰 —— 脚本无法区分哪些是 Lemon 装的、哪些是机器上本来就有的，
# 误删会直接破坏用户原有环境。组件目录由各自的 Uninstall_* 负责。

Purge_Lemon_Artifacts() {
  echo "${CMSG}Purging Lemon's own config files...${CEND}"
  # Lemon 自己在 /etc/profile.d 里写的登录配置
  rm -f /etc/profile.d/lemon.sh
  # 依赖安装标记：留着它下次装会跳过依赖
  rm -f ~/.lemon
  rm -rf /etc/lemon
  echo "${CMSG}Lemon config files purged! ${CEND}"
  echo "${CMSG}注意：apt 依赖包、/usr/local 下的公共库、系统账号都保持原样${CEND}"
}

# 数据目录。默认保留（--all 只是改名），只有 --purge-data 才删。
Purge_Data() {
  echo "${CFAILURE}即将删除 ${wwwroot_dir} ${wwwlogs_dir} ${db_data_dir} ${pgsql_data_dir} ${mongo_data_dir} 等所有数据${CEND}"
  if [ "${quiet_flag}" != 'y' ]; then
    if [ ! -t 0 ]; then
      echo "${CFAILURE}非交互环境：确认删除请加 -q 重新执行${CEND}"
      return
    fi
    read -e -p "确认删除所有数据目录？不可恢复 [y/n]: " purge_data_confirm
    [ "${purge_data_confirm}" != 'y' ] && { echo "${CMSG}已跳过数据目录${CEND}"; return; }
  fi
  # 按 options.conf 里真实配置的目录逐个删，并拒绝空值与危险路径。
  # 原来直接 `rm -rf /data`：把目录改到 /www 的用户数据一个没删，却把 /data 上
  # 与本项目无关的内容（挂载盘、别的业务文件）清空了。
  for d in "${wwwroot_dir}" "${wwwlogs_dir}" "${mysql_data_dir}" "${mariadb_data_dir}" \
           "${percona_data_dir}" "${pgsql_data_dir}" "${mongo_data_dir}" "${clickhouse_data_dir}" \
           "${backup_dir}"; do
    case "${d}" in
      ''|'/'|'/usr'|'/usr/local'|'/etc'|'/var'|'/root'|'/home'|'/data')
        [ -n "${d}" ] && [ "${d}" != '/data' ] && echo "${CWARNING}skip unsafe path: ${d}${CEND}"
        [ "${d}" = '/data' ] && rm -rf "${d}"
        ;;
      *)
        [ -n "${d}" ] && [ -d "${d}" ] && rm -rf "${d}"
        ;;
    esac
  done
  echo "${CMSG}All data removed! ${CEND}"
}

if [ ${ARG_NUM} == 0 ]; then
  Menu
else
  [ "${web_flag}" == 'y' ] && Print_web
  [ "${mysql_flag}" == 'y' ] && Print_MySQL
  [ "${postgresql_flag}" == 'y' ] && Print_PostgreSQL
  [ "${mongodb_flag}" == 'y' ] && Print_MongoDB
  if [ "${allphp_flag}" == 'y' ]; then
    Print_ALLPHP
  else
    [ "${php_flag}" == 'y' ] && Print_PHP
    [ "${mphp_flag}" == 'y' ] && [ "${phpcache_flag}" != 'y' ] && [ -z "${php_extensions}" ] && Print_MPHP
  fi
  [ "${pureftpd_flag}" == 'y' ] && Print_PureFtpd
  [ "${redis_flag}" == 'y' ] && Print_Redis_server
  [ "${memcached_flag}" == 'y' ] && Print_Memcached_server
  [ "${phpmyadmin_flag}" == 'y' ] && Print_phpMyAdmin
  [ "${nodejs_flag}" == 'y' ] && Print_Nodejs
  Uninstall_status
  if [ "${uninstall_flag}" == 'y' ]; then
    if [ "${addons_flag}" == 'y' ]; then
      Uninstall_Addons
    elif [ "${supervisor_flag}" == 'y' ]; then
      . include/addon_mark.sh
      . include/supervisor.sh
      Uninstall_supervisor
    fi
    [ "${web_flag}" == 'y' ] && Uninstall_Web
    [ "${mysql_flag}" == 'y' ] && Uninstall_MySQL
    [ "${postgresql_flag}" == 'y' ] && Uninstall_PostgreSQL
    [ "${mongodb_flag}" == 'y' ] && Uninstall_MongoDB
    if [ "${allphp_flag}" == 'y' ]; then
      Uninstall_ALLPHP
    else
      [ "${php_flag}" == 'y' ] && Uninstall_PHP
      [ "${phpcache_flag}" == 'y' ] && Uninstall_PHPcache
      [ -n "${php_extensions}" ] && Uninstall_PHPext
      [ "${mphp_flag}" == 'y' ] && [ "${phpcache_flag}" != 'y' ] && [ -z "${php_extensions}" ] && Uninstall_MPHP
      # 目标目录由 Uninstall_PHPcache / Uninstall_PHPext 内部切换处理，这里不再改写 php_install_dir
      [ "${mphp_flag}" == 'y' ] && [ "${phpcache_flag}" == 'y' ] && Uninstall_PHPcache
      [ "${mphp_flag}" == 'y' ] && [ -n "${php_extensions}" ] && Uninstall_PHPext
    fi
    [ "${pureftpd_flag}" == 'y' ] && Uninstall_PureFtpd
    [ "${redis_flag}" == 'y' ] && Uninstall_Redis_server
    [ "${valkey_flag}" == 'y' ] && Uninstall_Valkey
    [ "${clickhouse_flag}" == 'y' ] && Uninstall_ClickHouse
    [ "${memcached_flag}" == 'y' ] && Uninstall_Memcached_server
    [ "${phpmyadmin_flag}" == 'y' ] && Uninstall_phpMyAdmin
    [ "${nodejs_flag}" == 'y' ] && { . include/nodejs.sh; Uninstall_Nodejs; }
    # 组件卸载里删了 /lib/systemd/system/*.service，但不一定都 daemon-reload。
    # 不 reload 的话 systemd 仍会把已删的 unit 报成 inactive（而不是 not-found），
    # 外部脚本/监控看到「服务还在」就会误判卸载失败（真机轮换测试里踩到过）。
    [ -e "/bin/systemctl" ] && systemctl daemon-reload > /dev/null 2>&1
    # 切换 Web/数据库时，被删掉的旧 unit 会残留在 failed 状态（systemctl is-active 返回 failed），
    # 外部监控/脚本会以为「服务坏了」。只复位本脚本管理的这几个 unit，不动系统里其它服务。
    if [ -e "/bin/systemctl" ]; then
      for u in nginx httpd caddy mysqld php-fpm redis-server valkey-server memcached pureftpd clickhouse-server supervisor supervisord; do
        systemctl reset-failed "$u" > /dev/null 2>&1
      done
    fi
    [ "${purge_flag}" == 'y' ] && Purge_Lemon_Artifacts
    [ "${purge_data_flag}" == 'y' ] && Purge_Data
  fi
fi

# 结尾显式返回 0：上面最后一条基本都是 `[ ... ] && cmd`，条件不成立时
# 脚本会以 1 退出，自动化调用方会误判成失败
exit 0
