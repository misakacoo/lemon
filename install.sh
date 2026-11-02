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
# Lemon - Debian 12/13 一键 Web 环境（Nginx/Tengine/OpenResty/Caddy） #
# https://github.com/misakacoo/lemon                                  #
#######################################################################
"
# Check if user is root
[ $(id -u) != "0" ] && { echo "${CFAILURE}Error: You must be root to run this script${CEND}"; exit 1; }

lemon_dir=$(dirname "`readlink -f $0`")
pushd "${lemon_dir}" > /dev/null
. ./versions.txt
[ -f ./options.conf ] || { cp -f ./options.conf.example ./options.conf 2>/dev/null && chmod 600 ./options.conf 2>/dev/null; }
. ./options.conf
# 口令不再走命令行参数：--password=xxx 会出现在 ps / /proc/PID/cmdline 里，
# 同机任何用户（含被黑的站点进程）都能读到数据库 root 口令。
# MYSQL_PWD 通过环境变量传给客户端，/proc/PID/environ 只有同用户可读。
export MYSQL_PWD="${dbrootpwd}"

# options.conf 里存着数据库密码，装到 /usr/local/src 这类目录时不能让其他用户读走
chmod 600 ./options.conf 2>/dev/null
. ./include/color.sh
. ./include/db_common.sh
. ./include/check_os.sh
. ./include/check_dir.sh
. ./include/php_build.sh
. ./include/download.sh
. ./include/get_char.sh

dbrootpwd=`< /dev/urandom tr -dc A-Za-z0-9 | head -c8`
dbpostgrespwd=`< /dev/urandom tr -dc A-Za-z0-9 | head -c8`
dbmongopwd=`< /dev/urandom tr -dc A-Za-z0-9 | head -c8`
dbclickhousepwd=`< /dev/urandom tr -dc A-Za-z0-9 | head -c16`
dbinstallmethod=1

version() {
  echo "version: 1.0.1"
  echo "updated date: 2026-10-31"
}

Show_Help() {
  version
  echo "Usage: $0  command ...[parameters]....
  --help, -h                  Show this help message, More: https://github.com/misakacoo/lemon
  --version, -v               Show version info
  --nginx_option [1-4]        Install Nginx server version
  --apache                    Install Apache
  --apache_mode_option [1-2]  Apache2.4 mode, 1(default): php-fpm, 2: mod_php
  --apache_mpm_option [1-3]   Apache2.4 MPM, 1(default): event, 2: prefork, 3: worker
                              (mod_php 只能用 prefork，选 --apache_mode_option 2 时会自动改成 2)
  --php_option [1-7]          Install PHP version, 1:7.4 2:8.0 3:8.1 4:8.2 5:8.3 6:8.4 7:8.5
  --mphp_ver [74~85]          Install another PHP version (PATH: ${php_install_dir}\${mphp_ver})
  --mphp_addons               Only install another PHP addons
  --phpcache_option [1-2]     Install PHP opcode cache, default: 1 opcache
  --php_extensions [ext name] Install PHP extensions, include ioncube,imagick,gmagick,fileinfo,
                              imap,ldap,calendar,phalcon,yaf,yar,redis,memcached,memcache,
                              mongodb,swoole,xdebug,igbinary,msgpack,zstd,grpc,xlswriter
  --nodejs                    Install Nodejs
  --supervisor                Install Supervisor (process control)
  --db_option [0-9]           Install DB version
  --dbinstallmethod [1-2]     DB install method, default: 1 binary install
  --dbrootpwd [password]      DB super password
  --pureftpd                  Install Pure-Ftpd
  --redis                     Install Redis
  --valkey                    Install Valkey (Redis-compatible fork)
  --clickhouse                Install ClickHouse
  --dbclickhousepwd [pass]    ClickHouse default user password
  --memcached                 Install Memcached
  --phpmyadmin                Install phpMyAdmin
  --phpmyadmin_local          Only allow 127.0.0.1 to access phpMyAdmin
  --db_bind_public            Expose MySQL/PostgreSQL/MongoDB to the network (default: listen 127.0.0.1 only)
  --db_bind_local             (deprecated) 默认已只监听本机，保留兼容，无副作用
  --ssh_port [No.]            SSH port
  --firewall                  Enable firewall
  --reboot                    Restart the server after installation
  "
}
ARG_NUM=$#
# 没有终端还走交互菜单会卡在 read 上无限循环，直接提示带参数运行
if [ "${ARG_NUM}" == '0' ] && [ ! -t 0 ]; then
  echo "非交互环境：请带上参数运行，$0 --help 查看可用参数"
  exit 1
fi
TEMP=`getopt -o hvV --long help,version,nginx_option:,apache,apache_mode_option:,apache_mpm_option:,php_option:,mphp_ver:,mphp_addons,phpcache_option:,php_extensions:,nodejs,supervisor,db_option:,dbrootpwd:,dbinstallmethod:,pureftpd,redis,valkey,clickhouse,dbclickhousepwd:,memcached,phpmyadmin,phpmyadmin_local,db_bind_local,db_bind_public,ssh_port:,firewall,reboot -- "$@" 2>/dev/null`
[ $? != 0 ] && echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
eval set -- "${TEMP}"
while :; do
  [ -z "$1" ] && break;
  case "$1" in
  -h | --help)
    Show_Help
    exit 0
    ;;
  -v | -V | --version)
    version
    exit 0
    ;;
  --nginx_option)
    nginx_option=$2
    shift 2
    [[ ! ${nginx_option} =~ ^[1-4]$ ]] && {
      echo "${CWARNING}nginx_option input error! Please only input number 1~4${CEND}"
      exit 1
    }
    [ -e "${nginx_install_dir}/sbin/nginx" ] && {
      echo "${CWARNING}Nginx already installed! ${CEND}"
      unset nginx_option
    }
    [ -e "${tengine_install_dir}/sbin/nginx" ] && {
      echo "${CWARNING}Tengine already installed! ${CEND}"
      unset nginx_option
    }
    [ -e "${openresty_install_dir}/nginx/sbin/nginx" ] && {
      echo "${CWARNING}OpenResty already installed! ${CEND}"
      unset nginx_option
    }
    [ -e "${caddy_install_dir}/bin/caddy" ] && {
      echo "${CWARNING}Caddy already installed! ${CEND}"
      unset nginx_option
    }
    ;;
  --apache)
    apache_flag=y
    shift 1
    [ -e "${apache_install_dir}/bin/httpd" ] && {
      echo "${CWARNING}Aapche already installed! ${CEND}"
      unset apache_flag
    }
    ;;
  --apache_mode_option)
    apache_mode_option=$2
    shift 2
    [[ ! ${apache_mode_option} =~ ^[1-2]$ ]] && {
      echo "${CWARNING}apache_mode_option input error! Please only input number 1~2${CEND}"
      exit 1
    }
    ;;
  --apache_mpm_option)
    apache_mpm_option=$2
    shift 2
    [[ ! ${apache_mpm_option} =~ ^[1-3]$ ]] && {
      echo "${CWARNING}apache_mpm_option input error! Please only input number 1~3${CEND}"
      exit 1
    }
    ;;
  --php_option)
    php_option=$2
    shift 2
    [[ ! ${php_option} =~ ^[1-7]$ ]] && {
      echo "${CWARNING}php_option input error! Please only input number 1~7${CEND}"
      exit 1
    }
    [ -e "${php_install_dir}/bin/phpize" ] && {
      echo "${CWARNING}PHP already installed! ${CEND}"
      unset php_option
    }
    ;;
  --mphp_ver)
    mphp_ver=$2
    mphp_flag=y
    shift 2
    [[ ! "${mphp_ver}" =~ ^74$|^8[0-5]$ ]] && {
      echo "${CWARNING}mphp_ver input error! Please only input number 74~85${CEND}"
      exit 1
    }
    ;;
  --mphp_addons)
    mphp_addons_flag=y
    shift 1
    ;;
  --phpcache_option)
    phpcache_option=$2
    shift 2
    ;;
  --php_extensions)
    php_extensions=$2
    shift 2
    [ -n "$(echo ${php_extensions} | grep -w ioncube)" ] && pecl_ioncube=1
    [ -n "$(echo ${php_extensions} | grep -w imagick)" ] && pecl_imagick=1
    [ -n "$(echo ${php_extensions} | grep -w gmagick)" ] && pecl_gmagick=1
    [ -n "$(echo ${php_extensions} | grep -w fileinfo)" ] && pecl_fileinfo=1
    [ -n "$(echo ${php_extensions} | grep -w imap)" ] && pecl_imap=1
    [ -n "$(echo ${php_extensions} | grep -w ldap)" ] && pecl_ldap=1
    [ -n "$(echo ${php_extensions} | grep -w calendar)" ] && pecl_calendar=1
    [ -n "$(echo ${php_extensions} | grep -w phalcon)" ] && pecl_phalcon=1
    [ -n "$(echo ${php_extensions} | grep -w yaf)" ] && pecl_yaf=1
    [ -n "$(echo ${php_extensions} | grep -w yar)" ] && pecl_yar=1
    [ -n "$(echo ${php_extensions} | grep -w redis)" ] && pecl_redis=1
    [ -n "$(echo ${php_extensions} | grep -w memcached)" ] && pecl_memcached=1
    [ -n "$(echo ${php_extensions} | grep -w memcache)" ] && pecl_memcache=1
    [ -n "$(echo ${php_extensions} | grep -w mongodb)" ] && pecl_mongodb=1
    [ -n "$(echo ${php_extensions} | grep -w swoole)" ] && pecl_swoole=1
    [ -n "$(echo ${php_extensions} | grep -w xdebug)" ] && pecl_xdebug=1
    [ -n "$(echo ${php_extensions} | grep -w igbinary)" ] && pecl_igbinary=1
    [ -n "$(echo ${php_extensions} | grep -w msgpack)" ] && pecl_msgpack=1
    [ -n "$(echo ${php_extensions} | grep -w zstd)" ] && pecl_zstd=1
    [ -n "$(echo ${php_extensions} | grep -w grpc)" ] && pecl_grpc=1
    [ -n "$(echo ${php_extensions} | grep -w xlswriter)" ] && pecl_xlswriter=1
    ;;
  --nodejs)
    nodejs_flag=y
    shift 1
    [ -e "${nodejs_install_dir}/bin/node" ] && {
      echo "${CWARNING}Nodejs already installed! ${CEND}"
      unset nodejs_flag
    }
    ;;
  --supervisor)
    supervisor_flag=y
    shift 1
    [ -e /etc/supervisor/supervisord.conf ] && {
      echo "${CWARNING}Supervisor already installed! ${CEND}"
      unset supervisor_flag
    }
    ;;
  --db_option)
    db_option=$2
    shift 2
    if [[ "${db_option}" =~ ^([0-6]|9)$ ]]; then
      [ -d "${db_install_dir}/support-files" ] && {
        echo "${CWARNING}MySQL already installed! ${CEND}"
        unset db_option
      }
    elif [ "${db_option}" == '7' ]; then
      [ -e "${pgsql_install_dir}/bin/psql" ] && {
        echo "${CWARNING}PostgreSQL already installed! ${CEND}"
        unset db_option
      }
    elif [ "${db_option}" == '8' ]; then
      [ -e "${mongo_install_dir}/bin/mongod" ] && {
        echo "${CWARNING}MongoDB already installed! ${CEND}"
        unset db_option
      }
    else
      echo "${CWARNING}db_option input error! Please only input number 0~9${CEND}"
      exit 1
    fi
    ;;
  --dbrootpwd)
    dbrootpwd=$2
    shift 2
    dbpostgrespwd="${dbrootpwd}"
    dbmongopwd="${dbrootpwd}"
    ;;
  --dbinstallmethod)
    dbinstallmethod=$2
    shift 2
    [[ ! ${dbinstallmethod} =~ ^[1-2]$ ]] && {
      echo "${CWARNING}dbinstallmethod input error! Please only input number 1~2${CEND}"
      exit 1
    }
    ;;
  --pureftpd)
    pureftpd_flag=y
    shift 1
    [ -e "${pureftpd_install_dir}/sbin/pure-ftpwho" ] && {
      echo "${CWARNING}Pure-FTPd already installed! ${CEND}"
      unset pureftpd_flag
    }
    ;;
  --redis)
    redis_flag=y
    shift 1
    [ -e "${redis_install_dir}/bin/redis-server" ] && {
      echo "${CWARNING}redis-server already installed! ${CEND}"
      unset redis_flag
    }
    ;;
  --valkey)
    valkey_flag=y
    shift 1
    [ -e "${valkey_install_dir}/bin/valkey-server" ] && {
      echo "${CWARNING}valkey-server already installed! ${CEND}"
      unset valkey_flag
    }
    ;;
  --clickhouse)
    clickhouse_flag=y
    shift 1
    [ -e "${clickhouse_install_dir}/bin/clickhouse" ] && {
      echo "${CWARNING}ClickHouse already installed! ${CEND}"
      unset clickhouse_flag
    }
    ;;
  --dbclickhousepwd)
    dbclickhousepwd=$2
    shift 2
    ;;
  --memcached)
    memcached_flag=y
    shift 1
    [ -e "${memcached_install_dir}/bin/memcached" ] && {
      echo "${CWARNING}memcached-server already installed! ${CEND}"
      unset memcached_flag
    }
    ;;
  --phpmyadmin)
    phpmyadmin_flag=y
    shift 1
    [ -d "${wwwroot_dir}/default/phpMyAdmin" ] && {
      echo "${CWARNING}phpMyAdmin already installed! ${CEND}"
      unset phpmyadmin_flag
    }
    # phpMyAdmin 5.2.x 官方仅支持 PHP < 8.4，要装 PHP 8.4/8.5 时直接拦下
    if [[ "${php_option}" =~ ^[6-7]$ ]]; then
      echo "${CWARNING}phpMyAdmin 5.2.x 官方仅支持 PHP < 8.4，本次要安装的 PHP 8.4/8.5 下安装会报兼容错误，已跳过 phpMyAdmin${CEND}"
      unset phpmyadmin_flag
    fi
    ;;
  --phpmyadmin_local)
    # 只要“仅本机”这一项却什么都不装是反直觉的：隐含 --phpmyadmin
    phpmyadmin_local=y
    phpmyadmin_flag=y
    shift 1
    ;;
  --db_bind_local)
    # 兼容旧参数：现在默认就只监听本机
    db_bind_local=y
    shift 1
    ;;
  --db_bind_public)
    db_bind_public=y
    shift 1
    ;;
  --ssh_port)
    ssh_port=$2
    shift 2
    ;;
  --firewall)
    firewall_flag=y
    shift 1
    ;;
  --reboot)
    reboot_flag=y
    shift 1
    ;;
  --)
    shift
    ;;
  *)
    echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
    ;;
  esac
done

# Use default SSH port 22. If you use another SSH port on your server
if [ -e "/etc/ssh/sshd_config" ]; then
  [ -z "`grep ^Port /etc/ssh/sshd_config`" ] && now_ssh_port=22 || now_ssh_port=`grep ^Port /etc/ssh/sshd_config | awk '{print $2}' | head -1`
  while :; do echo
    [ ${ARG_NUM} == 0 ] && read -e -p "Please input SSH port(Default: ${now_ssh_port}): " ssh_port
    ssh_port=${ssh_port:-${now_ssh_port}}
    if [[ "${ssh_port}" =~ ^[0-9]+$ ]] && { [ "${ssh_port}" -eq 22 ] || { [ "${ssh_port}" -gt 1024 ] && [ "${ssh_port}" -lt 65535 ]; }; }; then
      break
    else
      echo "${CWARNING}input error! Input range: 22,1025~65534${CEND}"
      exit 1
    fi
  done

  # 改 sshd 配置前先备份；改完先 sshd -t 校验，失败自动回滚
  [ -f /etc/ssh/sshd_config ] && cp -a /etc/ssh/sshd_config /etc/ssh/sshd_config.lemon.bak
  if [ -z "`grep ^Port /etc/ssh/sshd_config`" -a "${ssh_port}" != '22' ]; then
    sed -i "s@^#Port.*@&\nPort ${ssh_port}@" /etc/ssh/sshd_config
  elif [ -n "`grep ^Port /etc/ssh/sshd_config`" ]; then
    sed -i "s@^Port.*@Port ${ssh_port}@" /etc/ssh/sshd_config
  fi

  # 端口改了要真的生效：init_Debian.sh 结尾虽然会 restart ssh，但那段被
  # `~/.lemon != deps-${lemon_deps_ver}` 包着，依赖已装好的机器上会整段跳过 ——
  # 只改 sshd_config 不够：端口改成 2222 后监听仍在 22，脚本却照样 Congratulations。
  if [ "${ssh_port}" != "${now_ssh_port}" ]; then
    # ufw 已启用时先放行新端口，否则重启后会被防火墙挡在外面
    if command -v ufw > /dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
      ufw allow ${ssh_port}/tcp > /dev/null 2>&1
    fi
    echo "${CWARNING}SSH 端口已改为 ${ssh_port}，正在重启 sshd（当前连接会断开，请用新端口 ${ssh_port} 重新连接）${CEND}"
    if command -v sshd > /dev/null 2>&1 && ! sshd -t > /dev/null 2>&1; then
      echo "${CFAILURE}sshd 配置校验失败，已回滚到备份，端口未生效${CEND}"
      [ -f /etc/ssh/sshd_config.lemon.bak ] && cp -a /etc/ssh/sshd_config.lemon.bak /etc/ssh/sshd_config
      INSTALL_FAILED="${INSTALL_FAILED} ssh_config"
    else
    systemctl restart ssh > /dev/null 2>&1 || systemctl restart sshd > /dev/null 2>&1
    fi
    sleep 2
    if ss -lntp 2>/dev/null | grep -q ":${ssh_port} "; then
      echo "${CSUCCESS}sshd 已在 ${ssh_port} 端口监听${CEND}"
    else
      echo "${CFAILURE}sshd 没有在 ${ssh_port} 监听，请立即用带外方式检查 /etc/ssh/sshd_config${CEND}"
    fi
  fi
fi

if [ ${ARG_NUM} == 0 ]; then
  if [ ! -e ~/.lemon ]; then
    # check firewall
    while :; do echo
      read -e -p "Do you want to enable firewall? [y/n]: " firewall_flag
      if [[ ! ${firewall_flag} =~ ^[y,n]$ ]]; then
        echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
      else
        break
      fi
    done
  fi

  # check Web server
  while :; do echo
    read -e -p "Do you want to install Web server? [y/n]: " web_flag
    if [[ ! ${web_flag} =~ ^[y,n]$ ]]; then
      echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
    else
      if [ "${web_flag}" == 'y' ]; then
        # Nginx/Tegine/OpenResty
        while :; do
          echo
          echo 'Please select Web server type:'
          echo -e "\t${CMSG}1${CEND}. Install Nginx"
          echo -e "\t${CMSG}2${CEND}. Install Tengine"
          echo -e "\t${CMSG}3${CEND}. Install OpenResty"
          echo -e "\t${CMSG}4${CEND}. Install Caddy"
          echo -e "\t${CMSG}5${CEND}. Do not install"
          read -e -p "Please input a number:(Default 1 press Enter) " nginx_option
          nginx_option=${nginx_option:-1}
          if [[ ! ${nginx_option} =~ ^[1-5]$ ]]; then
            echo "${CWARNING}input error! Please only input number 1~5${CEND}"
          else
            [ "${nginx_option}" != '5' -a -e "${nginx_install_dir}/sbin/nginx" ] && {
              echo "${CWARNING}Nginx already installed! ${CEND}"
              unset nginx_option
            }
            [ "${nginx_option}" != '5' -a -e "${tengine_install_dir}/sbin/nginx" ] && {
              echo "${CWARNING}Tengine already installed! ${CEND}"
              unset nginx_option
            }
            [ "${nginx_option}" != '5' -a -e "${openresty_install_dir}/nginx/sbin/nginx" ] && {
              echo "${CWARNING}OpenResty already installed! ${CEND}"
              unset nginx_option
            }
            [ "${nginx_option}" != '5' -a -e "${caddy_install_dir}/bin/caddy" ] && {
              echo "${CWARNING}Caddy already installed! ${CEND}"
              unset nginx_option
            }
            break
          fi
        done
        if [[ ${nginx_option} =~ ^[1-3]$ ]]; then
          # Apache
          while :; do
            echo
            read -e -p "Do you want to install Apache? [y/n]: " apache_flag
            if [[ ! ${apache_flag} =~ ^[y,n]$ ]]; then
              echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
            else
              [ "${apache_flag}" == 'y' -a -e "${apache_install_dir}/bin/httpd" ] && {
                echo "${CWARNING}Aapche already installed! ${CEND}"
                unset apache_flag
              }
              break
            fi
          done
          # Apache2.4 mode and Apache2.4 MPM
          if [ "${apache_flag}" == 'y' -o -e "${apache_install_dir}/bin/httpd" ]; then
            while :; do
              echo
              echo 'Please select Apache mode:'
              echo -e "\t${CMSG}1${CEND}. php-fpm"
              echo -e "\t${CMSG}2${CEND}. mod_php"
              read -e -p "Please input a number:(Default 1 press Enter) " apache_mode_option
              apache_mode_option=${apache_mode_option:-1}
              if [[ ! ${apache_mode_option} =~ ^[1-2]$ ]]; then
                echo "${CWARNING}input error! Please only input number 1~2${CEND}"
              else
                break
              fi
            done
            while :; do
              echo
              echo 'Please select Apache MPM:'
              echo -e "\t${CMSG}1${CEND}. event"
              echo -e "\t${CMSG}2${CEND}. prefork"
              echo -e "\t${CMSG}3${CEND}. worker"
              read -e -p "Please input a number:(Default 1 press Enter) " apache_mpm_option
              apache_mpm_option=${apache_mpm_option:-1}
              if [[ ! ${apache_mpm_option} =~ ^[1-3]$ ]]; then
                echo "${CWARNING}input error! Please only input number 1~3${CEND}"
              else
                break
              fi
            done
          fi
        elif [ "${nginx_option}" == '4' ]; then
          # Caddy
          while :; do
            echo
            read -e -p "Do you want to install Caddy? [y/n]: " caddy_flag
            if [[ ! ${caddy_flag} =~ ^[y,n]$ ]]; then
              echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
            else
              [ "${caddy_flag}" == 'y' -a -e "${caddy_install_dir}/bin/caddy" ] && {
                echo "${CWARNING}Caddy already installed! ${CEND}"
                unset caddy_flag
              }
              break
            fi
          done
        fi
      fi
      break
    fi
  done

  # choice database
  while :; do
    echo
    read -e -p "Do you want to install Database? [y/n]: " db_flag
    if [[ ! ${db_flag} =~ ^[y,n]$ ]]; then
      echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
    else
      if [ "${db_flag}" == 'y' ]; then
        while :; do
          echo
          echo 'Please select a version of the Database:'
          echo -e "\t${CMSG} 0${CEND}. Install MySQL-5.7"
          echo -e "\t${CMSG} 1${CEND}. Install MySQL-8.0"
          echo -e "\t${CMSG} 2${CEND}. Install MySQL-8.4 (LTS)"
          echo -e "\t${CMSG} 3${CEND}. Install MariaDB-10.11 (LTS)"
          echo -e "\t${CMSG} 4${CEND}. Install MariaDB-11.4 (LTS)"
          echo -e "\t${CMSG} 5${CEND}. Install MariaDB-11.8 (LTS)"
          echo -e "\t${CMSG} 6${CEND}. Install Percona-8.0"
          echo -e "\t${CMSG} 7${CEND}. Install PostgreSQL"
          echo -e "\t${CMSG} 8${CEND}. Install MongoDB"
          echo -e "\t${CMSG} 9${CEND}. Install Percona-8.4 (LTS)"
          read -e -p "Please input a number:(Default 2 press Enter) " db_option
          db_option=${db_option:-2}
          if [[ "${db_option}" =~ ^[0-9]$ ]]; then
            if [ "${db_option}" == '7' ]; then
              [ -e "${pgsql_install_dir}/bin/psql" ] && { echo "${CWARNING}PostgreSQL already installed! ${CEND}"; unset db_option; break; }
            elif [ "${db_option}" == '8' ]; then
              [ -e "${mongo_install_dir}/bin/mongod" ] && { echo "${CWARNING}MongoDB already installed! ${CEND}"; unset db_option; break; }
            else
              [ -d "${db_install_dir}/support-files" ] && { echo "${CWARNING}MySQL already installed! ${CEND}"; unset db_option; break; }
            fi
            while :; do
              if [ "${db_option}" == '7' ]; then
                read -e -p "Please input the postgres password of PostgreSQL(default: ${dbpostgrespwd}): " dbpwd
                dbpwd=${dbpwd:-${dbpostgrespwd}}
              elif [ "${db_option}" == '8' ]; then
                read -e -p "Please input the root password of MongoDB(default: ${dbmongopwd}): " dbpwd
                dbpwd=${dbpwd:-${dbmongopwd}}
              else
                read -e -p "Please input the root password of MySQL(default: ${dbrootpwd}): " dbpwd
                dbpwd=${dbpwd:-${dbrootpwd}}
              fi
              [ -n "`echo ${dbpwd} | grep '[+|&]'`" ] && { echo "${CWARNING}input error,not contain a plus sign (+) and & ${CEND}"; continue; }
              if (( ${#dbpwd} >= 5 )); then
                if [ "${db_option}" == '7' ]; then
                  dbpostgrespwd=${dbpwd}
                elif [ "${db_option}" == '8' ]; then
                  dbmongopwd=${dbpwd}
                else
                  dbrootpwd=${dbpwd}
                fi
                break
              else
                echo "${CWARNING}password least 5 characters! ${CEND}"
              fi
            done
            # choose install methods
            if [[ "${db_option}" =~ ^[0-9]$ ]]; then
              while :; do echo
                echo "Please choose installation of the database:"
                echo -e "\t${CMSG}1${CEND}. Install database from binary package."
                echo -e "\t${CMSG}2${CEND}. Install database from source package."
                read -e -p "Please input a number:(Default 1 press Enter) " dbinstallmethod
                dbinstallmethod=${dbinstallmethod:-1}
                if [[ ! ${dbinstallmethod} =~ ^[1-2]$ ]]; then
                  echo "${CWARNING}input error! Please only input number 1~2${CEND}"
                else
                  break
                fi
              done
            fi
            break
          else
            echo "${CWARNING}input error! Please only input number 0~9${CEND}"
          fi
        done
      fi
      break
    fi
  done

  # choice php
  while :; do echo
    read -e -p "Do you want to install PHP? [y/n]: " php_flag
    if [[ ! ${php_flag} =~ ^[y,n]$ ]]; then
      echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
    else
      if [ "${php_flag}" == 'y' ]; then
        [ -e "${php_install_dir}/bin/phpize" ] && { echo "${CWARNING}PHP already installed! ${CEND}"; unset php_option; break; }
        while :; do echo
          echo 'Please select a version of the PHP (only 7.4+ is supported):'
          echo -e "\t${CMSG}1${CEND}. Install php-7.4"
          echo -e "\t${CMSG}2${CEND}. Install php-8.0"
          echo -e "\t${CMSG}3${CEND}. Install php-8.1"
          echo -e "\t${CMSG}4${CEND}. Install php-8.2"
          echo -e "\t${CMSG}5${CEND}. Install php-8.3"
          echo -e "\t${CMSG}6${CEND}. Install php-8.4"
          echo -e "\t${CMSG}7${CEND}. Install php-8.5"
          # 默认 8.3（opt 5）：与 Lemon-Shell 的默认值保持一致，8.4/8.5 太新，phpMyAdmin 与部分扩展还不跟
          read -e -p "Please input a number:(Default 5 press Enter) " php_option
          php_option=${php_option:-5}
          if [[ ! ${php_option} =~ ^[1-7]$ ]]; then
            echo "${CWARNING}input error! Please only input number 1~7${CEND}"
          else
            break
          fi
        done
      fi
      break
    fi
  done

  # check php ver
  if [ -e "${php_install_dir}/bin/phpize" ]; then
    PHP_detail_ver=$(${php_install_dir}/bin/php-config --version)
    PHP_main_ver=${PHP_detail_ver%.*}
  fi

  # PHP opcode cache and extensions
  if [[ ${php_option} =~ ^[1-7]$ ]] || [ -e "${php_install_dir}/bin/phpize" ]; then
    while :; do echo
      read -e -p "Do you want to install opcode cache of the PHP? [y/n]: " phpcache_flag
      if [[ ! ${phpcache_flag} =~ ^[y,n]$ ]]; then
        echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
      else
        if [ "${phpcache_flag}" == 'y' ]; then
          # PHP 7.4 起只剩 OPcache / APCu（XCache 只支持 PHP 5.x）
          while :; do
            echo 'Please select a opcode cache of the PHP:'
            echo -e "\t${CMSG}1${CEND}. Install Zend OPcache"
            echo -e "\t${CMSG}2${CEND}. Install APCU"
            read -e -p "Please input a number:(Default 1 press Enter) " phpcache_option
            phpcache_option=${phpcache_option:-1}
            if [[ ! ${phpcache_option} =~ ^[1-2]$ ]]; then
              echo "${CWARNING}input error! Please only input number 1~2${CEND}"
            else
              break
            fi
          done
        fi
        break
      fi
    done
    # PHP extension
    while :; do
      echo
      echo 'Please select PHP extensions:'
      echo -e "\t${CMSG} 0${CEND}. Do not install"
      echo -e "\t${CMSG} 1${CEND}. Install ioncube"
      echo -e "\t${CMSG} 2${CEND}. Install imagick"
      echo -e "\t${CMSG} 3${CEND}. Install gmagick"
      echo -e "\t${CMSG} 4${CEND}. Install fileinfo"
      echo -e "\t${CMSG} 5${CEND}. Install imap"
      echo -e "\t${CMSG} 6${CEND}. Install ldap"
      echo -e "\t${CMSG} 7${CEND}. Install phalcon"
      echo -e "\t${CMSG} 8${CEND}. Install yaf"
      echo -e "\t${CMSG} 9${CEND}. Install redis"
      echo -e "\t${CMSG}10${CEND}. Install memcached"
      echo -e "\t${CMSG}11${CEND}. Install memcache"
      echo -e "\t${CMSG}12${CEND}. Install mongodb"
      echo -e "\t${CMSG}13${CEND}. Install swoole"
      echo -e "\t${CMSG}14${CEND}. Install xdebug"
      echo -e "\t${CMSG}15${CEND}. Install calendar"
      read -e -p "Please input numbers:(Default '2 9 10' press Enter) " phpext_option
      phpext_option=${phpext_option:-'2 9 10'}
      [ "${phpext_option}" == '0' ] && break
      array_phpext=(${phpext_option})
      array_all=(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15)
      for v in ${array_phpext[@]}
      do
        [ -z "`echo ${array_all[@]} | grep -w ${v}`" ] && phpext_flag=1
      done
      if [ "${phpext_flag}" == '1' ]; then
        unset phpext_flag
        echo; echo "${CWARNING}input error! Please only input number 4 11 12 and so on${CEND}"; echo
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
        [ -n "`echo ${array_phpext[@]} | grep -w 15`" ] && pecl_calendar=1
        break
      fi
    done
  fi

  # check Nodejs
  while :; do echo
    read -e -p "Do you want to install Nodejs? [y/n]: " nodejs_flag
    if [[ ! ${nodejs_flag} =~ ^[y,n]$ ]]; then
      echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
    else
      [ "${nodejs_flag}" == 'y' -a -e "${nodejs_install_dir}/bin/node" ] && { echo "${CWARNING}Nodejs already installed! ${CEND}"; unset nodejs_flag; }
      break
    fi
  done

  # check Supervisor
  while :; do echo
    read -e -p "Do you want to install Supervisor? [y/n]: " supervisor_flag
    if [[ ! ${supervisor_flag} =~ ^[y,n]$ ]]; then
      echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
    else
      [ "${supervisor_flag}" == 'y' -a -e /etc/supervisor/supervisord.conf ] && { echo "${CWARNING}Supervisor already installed! ${CEND}"; unset supervisor_flag; }
      break
    fi
  done

  # check Pureftpd
  while :; do echo
    read -e -p "Do you want to install Pure-FTPd? [y/n]: " pureftpd_flag
    if [[ ! ${pureftpd_flag} =~ ^[y,n]$ ]]; then
      echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
    else
      [ "${pureftpd_flag}" == 'y' -a -e "${pureftpd_install_dir}/sbin/pure-ftpwho" ] && { echo "${CWARNING}Pure-FTPd already installed! ${CEND}"; unset pureftpd_flag; }
      break
    fi
  done

  # check phpMyAdmin
  if [[ ${php_option} =~ ^[1-7]$ ]] || [ -e "${php_install_dir}/bin/phpize" ]; then
    # phpMyAdmin 5.2.x 官方仅支持 PHP < 8.4：本次要装 PHP 8.4/8.5（php_option 6/7），
    # 或机器上已装的是 8.4/8.5（php_option 为空的升级场景）时直接跳过，不再询问
    pma_php_ok=y
    if [[ "${php_option}" =~ ^[6-7]$ ]]; then
      pma_php_ok=n
    elif [ -z "${php_option}" ] && [ -e "${php_install_dir}/bin/phpize" ]; then
      [[ "$(${php_install_dir}/bin/php-config --version 2>/dev/null)" =~ ^8.[45] ]] && pma_php_ok=n
    fi
    if [ "${pma_php_ok}" == 'n' ]; then
      echo "${CWARNING}phpMyAdmin 5.2.x 官方仅支持 PHP < 8.4，PHP 8.4/8.5 下安装会报兼容错误，已跳过 phpMyAdmin${CEND}"
    else
      while :; do echo
        read -e -p "Do you want to install phpMyAdmin? [y/n]: " phpmyadmin_flag
        if [[ ! ${phpmyadmin_flag} =~ ^[y,n]$ ]]; then
          echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
        else
          [ "${phpmyadmin_flag}" == 'y' -a -d "${wwwroot_dir}/default/phpMyAdmin" ] && { echo "${CWARNING}phpMyAdmin already installed! ${CEND}"; unset phpmyadmin_flag; }
          break
        fi
      done
    fi
  fi

  # check redis
  while :; do echo
    read -e -p "Do you want to install redis-server? [y/n]: " redis_flag
    if [[ ! ${redis_flag} =~ ^[y,n]$ ]]; then
      echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
    else
      [ "${redis_flag}" == 'y' -a -e "${redis_install_dir}/bin/redis-server" ] && { echo "${CWARNING}redis-server already installed! ${CEND}"; unset redis_flag; }
      break
    fi
  done

  # check memcached
  while :; do echo
    read -e -p "Do you want to install memcached-server? [y/n]: " memcached_flag
    if [[ ! ${memcached_flag} =~ ^[y,n]$ ]]; then
      echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
    else
      [ "${memcached_flag}" == 'y' -a -e "${memcached_install_dir}/bin/memcached" ] && { echo "${CWARNING}memcached-server already installed! ${CEND}"; unset memcached_flag; }
      break
    fi
  done

  # check valkey
  while :; do echo
    read -e -p "Do you want to install valkey-server? [y/n]: " valkey_flag
    if [[ ! ${valkey_flag} =~ ^[y,n]$ ]]; then
      echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
    else
      [ "${valkey_flag}" == 'y' -a -e "${valkey_install_dir}/bin/valkey-server" ] && { echo "${CWARNING}valkey-server already installed! ${CEND}"; unset valkey_flag; }
      break
    fi
  done

  # check clickhouse
  while :; do echo
    read -e -p "Do you want to install clickhouse-server? [y/n]: " clickhouse_flag
    if [[ ! ${clickhouse_flag} =~ ^[y,n]$ ]]; then
      echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
    else
      [ "${clickhouse_flag}" == 'y' -a -e "${clickhouse_install_dir}/bin/clickhouse" ] && { echo "${CWARNING}ClickHouse already installed! ${CEND}"; unset clickhouse_flag; }
      break
    fi
  done
fi

if [[ ${nginx_option} =~ ^[1-4]$ ]] || [ "${apache_flag}" == 'y' ] || [ "${caddy_flag}" == 'y' ]; then
  [ ! -d ${wwwroot_dir}/default ] && mkdir -p ${wwwroot_dir}/default
  [ ! -d ${wwwlogs_dir} ] && mkdir -p ${wwwlogs_dir}
fi
[ -d /data ] && chmod 755 /data

# install wget gcc curl
if [ ! -e ~/.lemon ]; then
  downloadDepsSrc=1
  apt-get -y update > /dev/null
  apt-get -y install wget gcc curl > /dev/null
fi

# get the IP information
# Windows 打包/解包可能丢执行位，调用前兜底补上
# 不再调用仓库里那个 2.5MB 的预编译二进制。
# 等价功能用系统工具实现。
IPADDR=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
[ -z "${IPADDR}" ] && IPADDR=$(hostname -I 2>/dev/null | awk '{print $1}')
[ -z "${IPADDR}" ] && IPADDR=127.0.0.1
# 出口归属地：只用于演示站点选择，取不到就当未知
_out=$(curl -s -m 5 https://ipinfo.io/country 2>/dev/null | tr -d '\r\n')
case "${_out}" in
  CN) OUTIP_STATE=China ;;
  *)  OUTIP_STATE=${_out:-Unknown} ;;
esac
unset _out

# openSSL
. ./include/openssl.sh

# Debian 13 上不要装 MySQL 5.7：官方 5.7.44 的 glibc2.12 tar 包里，客户端二进制硬链接
# libncurses.so.5（trixie 已无 libncurses5/libtinfo5 包），服务端能起来但 mysql 客户端
# 一调就 "error while loading shared libraries"，连 install.sh 自己设 root 密码那步都会失败 ——
# 装出来是个「服务在跑、客户端不可用、root 密码可能没设上」的半残环境。5.7 也已 EOL，直接拦住。
# 注意必须放在下载阶段之前：否则会先把 694MB 的 5.7 包下完再报错
if [ "${db_option}" == '0' ] && [ "${Debian_ver}" -ge 13 ] 2>/dev/null; then
  echo "${CFAILURE}Debian 13 不支持 MySQL 5.7：客户端依赖 libncurses.so.5，trixie 已移除该包，装完 mysql 命令不可用。请改用 --db_option 1（MySQL 8.0）或 2（MySQL 8.4）${CEND}"
  exit 1
fi

# Check download source packages
. ./include/check_download.sh

# 组件安装统一入口：输出照旧进日志，但会收集失败并透出退出码。
# 直接 `Install_X 2>&1 | tee` 时管道退出码是 tee 的 0，组件里的 exit 1 只退出子 shell，
# 于是「装失败也照样 Congratulations」。这里失败会记下来，收尾统一报错并非 0 退出。
INSTALL_FAILED=''
Run_Install() {
  local _name="$1"; shift
  "${_name}" "$@" 2>&1 | tee -a "${lemon_dir}/install.log"
  local _rc=${PIPESTATUS[0]}
  if [ "${_rc}" -ne 0 ]; then
    echo "${CFAILURE}[失败] ${_name} 退出码 ${_rc}，详见 ${lemon_dir}/install.log${CEND}"
    INSTALL_FAILED="${INSTALL_FAILED} ${_name}"
    # 默认**立刻中止**：继续往下装只会得到一个「看起来装完、其实缺组件」的半成品机器。
    # 需要跳过失败继续时设 LEMON_KEEP_GOING=1。
    if [ "${LEMON_KEEP_GOING}" != '1' ]; then
      echo "${CFAILURE}已中止后续安装（如需跳过失败继续，设 LEMON_KEEP_GOING=1）${CEND}"
      echo "${CWARNING}已完成的组件不受影响；修复原因后可直接重跑同一条 install.sh（已装组件会跳过）${CEND}"
      exit 1
    fi
  fi
  return 0
}

Run_Install checkDownload

# get OS Memory
. ./include/memory.sh

if [ ! -e ~/.lemon ] || [ "$(cat ~/.lemon 2>/dev/null)" != "deps-${lemon_deps_ver}" ]; then
  # Check binary dependencies packages
  . ./include/check_sw.sh
  Run_Install installDepsDebian
  . include/init_Debian.sh 2>&1 | tee -a ${lemon_dir}/install.log
  # 这一行若被 | tee 吞掉退出码：init_Debian 半途失败（sysctl/locale/limits/timezone）不计入失败，
  # 而 check_sw.sh 已经写了 deps 标记 → 之后每次 install 都判定“依赖已就绪”永久跳过，再也修不上
  if [ "${PIPESTATUS[0]}" != '0' ]; then
    echo "${CFAILURE}init_Debian 执行失败，已撤销依赖标记，下次重跑会重新执行${CEND}"
    INSTALL_FAILED="${INSTALL_FAILED} init_Debian"
    rm -f ~/.lemon
  fi
  # Install dependencies from source package
  Run_Install installDepsBySrc
fi
# --firewall：放在依赖安装之后，且**不受 deps 标记限制**。
# 这段不能放进 init_Debian.sh —— 它被「依赖标记」包着，
# 已经装好依赖的机器再加 --firewall 会整段跳过
if [ "${firewall_flag}" == 'y' ] && command -v ufw > /dev/null 2>&1; then
  ufw allow ${ssh_port:-22}/tcp > /dev/null 2>&1
  ufw allow 80/tcp > /dev/null 2>&1
  ufw allow 443/tcp > /dev/null 2>&1
  # 已经装过 pure-ftpd 时补上 FTP 端口（被动范围 20000-30000）；
  # 首次安装时 pureftpd.sh 自己会在装完后补这两条。
  if [ -e "${pureftpd_install_dir}/bin/pure-ftpd" ]; then
    ufw allow 21/tcp > /dev/null 2>&1
    ufw allow 20000:30000/tcp > /dev/null 2>&1
  fi
  # 先放行再改默认策略，避免把自己关在门外；
  # 显式设定默认值是因为 /etc/default/ufw 在不同镜像上可能是 ACCEPT。
  ufw default deny incoming > /dev/null 2>&1
  ufw default allow outgoing > /dev/null 2>&1
  ufw --force enable > /dev/null 2>&1
  echo "${CSUCCESS}防火墙已启用：放行 SSH(${ssh_port:-22}) / 80 / 443，默认拒绝入站${CEND}"
fi


# start Time
startTime=`date +%s`

# openSSL

# Jemalloc
if [[ ${nginx_option} =~ ^[1-3]$ ]] || [[ "${db_option}" =~ ^([0-6]|9)$ ]]; then
  . include/jemalloc.sh
  Run_Install Install_Jemalloc
fi

# Database
# 上一次安装失败（比如 my.cnf 写错导致 mariadbd Abort）会在 /tmp 留下死 socket 文件，
# 下一次启动 mysqld 就报 `Bind on unix socket: Address already in use`，看起来像新故障。
# 这里在建库前做一次预清理：只有在没有任何数据库进程运行时才删
if ! pgrep -x mysqld > /dev/null 2>&1 && ! pgrep -x mariadbd > /dev/null 2>&1 && ! pgrep -x mysqld_safe > /dev/null 2>&1; then
  [ -e /tmp/mysql.sock ] && { rm -f /tmp/mysql.sock; echo "${CWARNING}清理了上次遗留的死 socket：/tmp/mysql.sock${CEND}"; }
  rm -f /tmp/mysqlx.sock 2>/dev/null
fi
case "${db_option}" in
  0)
    . include/mysql-5.7.sh
    Run_Install Install_MySQL57
    ;;
  1)
    . include/mysql-8.0.sh
    Run_Install Install_MySQL80
    ;;
  2)
    . include/mysql-8.4.sh
    Run_Install Install_MySQL84
    ;;
  3)
    . include/mariadb-10.11.sh
    Run_Install Install_MariaDB1011
    ;;
  4)
    . include/mariadb-11.4.sh
    Run_Install Install_MariaDB114
    ;;
  5)
    . include/mariadb-11.8.sh
    Run_Install Install_MariaDB118
    ;;
  6)
    . include/percona-8.0.sh
    Run_Install Install_Percona80
    ;;
  7)
    . include/postgresql.sh
    Run_Install Install_PostgreSQL
    ;;
  8)
    . include/mongodb.sh
    Run_Install Install_MongoDB
    ;;
  9)
    . include/percona-8.4.sh
    Run_Install Install_Percona84
    ;;
esac

# 数据库监听地址：默认 127.0.0.1，加 --db_bind_public 才放开。
# 两个方向都主动写配置（幂等）：从公网态改回默认态时也要真的收回来，光打一行提示是不够的。
_db_opt="${db_option}"
if [ -z "${_db_opt}" ]; then
  # 已装过的库会把 db_option unset 掉（避免重装），按实际安装目录推断引擎
  [ -e "${percona_install_dir}/bin/mysql" ] && _db_opt=6
  [ -e "${mariadb_install_dir}/bin/mysql" ] && _db_opt=3
  [ -e "${mysql_install_dir}/bin/mysqld" ] && _db_opt=2
  [ -e "${pgsql_install_dir}/bin/psql" ] && _db_opt=7
  [ -e "${mongo_install_dir}/bin/mongod" ] && _db_opt=8
fi
if [ "${db_bind_public}" == 'y' ]; then
  _bind=0.0.0.0
  _pg_listen=*
else
  _bind=127.0.0.1
  _pg_listen=localhost
fi
case "${_db_opt}" in
  0|1|2|3|4|5|6|9)
    my_cnf=/etc/my.cnf
    [ -e "${my_cnf}" ] || my_cnf="${db_install_dir}/etc/my.cnf"
    if [ -e "${my_cnf}" ]; then
      _old=$(cat "${my_cnf}" 2>/dev/null | grep -E "^bind-address|^mysqlx-bind-address" | md5sum)
      if grep -q '^bind-address' "${my_cnf}"; then
        sed -i "s@^bind-address.*@bind-address = ${_bind}@" "${my_cnf}"
      else
        sed -i "/^\\[mysqld\\]/a bind-address = ${_bind}" "${my_cnf}"
      fi
      # X 协议端口（33060）只有 MySQL 8.0+ / Percona 8.0+ 才有。5.7 与 MariaDB 没有这个变量，
      # 写进去 mysqld 会报 "unknown variable" 直接 Abort
      case "${_db_opt}" in
        1|2|6|9)
          if grep -q '^mysqlx-bind-address' "${my_cnf}"; then
            sed -i "s@^mysqlx-bind-address.*@mysqlx-bind-address = ${_bind}@" "${my_cnf}"
          else
            sed -i "/^\\[mysqld\\]/a mysqlx-bind-address = ${_bind}" "${my_cnf}"
          fi
          ;;
        *)
          # 不支持的引擎：把历史版本可能写进去的残留删掉，否则重跑 install 会直接起不来
          sed -i '/^mysqlx-bind-address/d' "${my_cnf}"
          ;;
      esac
      _new=$(cat "${my_cnf}" 2>/dev/null | grep -E "^bind-address|^mysqlx-bind-address" | md5sum)
      if [ "${_old}" != "${_new}" ]; then
        service mysqld restart > /dev/null 2>&1
        echo "${CSUCCESS}数据库监听地址已设为 ${_bind}（重启 mysqld 生效）${CEND}"
      fi
    else
      echo "${CWARNING}没找到 my.cnf，跳过监听地址设置${CEND}"
    fi
    ;;
  7)
    if [ -e "${pgsql_data_dir}/postgresql.conf" ]; then
      sed -i "s@^listen_addresses.*@listen_addresses = '${_pg_listen}'@" "${pgsql_data_dir}/postgresql.conf"
      service postgresql restart > /dev/null 2>&1
      echo "${CSUCCESS}PostgreSQL listen_addresses=${_pg_listen}${CEND}"
    fi
    ;;
  8)
    if [ -e /etc/mongod.conf ]; then
      sed -i "s@^  bindIp:.*@  bindIp: ${_bind}@" /etc/mongod.conf
      systemctl restart mongod > /dev/null 2>&1
      echo "${CSUCCESS}MongoDB bindIp=${_bind}${CEND}"
    fi
    ;;
esac
if [ "${db_bind_public}" == 'y' ]; then
  echo "${CWARNING}数据库已按 --db_bind_public 放开监听，请务必配合防火墙白名单与强口令${CEND}"
else
  echo "${CSUCCESS}数据库只监听 127.0.0.1（需要公网连库请加 --db_bind_public）${CEND}"
fi

# ---- web server 之前先做 PHP SAPI 检查 ----
# 这条必须在装 nginx/apache **之前**：否则带 --nginx_option 时会先把 nginx 装好
# 再 exit 1，机器停在「nginx 在跑、PHP 没有 fpm → 全站 PHP 挂掉」的半状态
# mod_php 编出来的 PHP 没有 --enable-fpm；php-fpm 编出来的没有 apxs。换模式必须重装 PHP。
apache_mode_option=${apache_mode_option:-1}
if [ -e "${php_install_dir}/bin/phpize" ]; then
  php_conf_opts=$(${php_install_dir}/bin/php-config --configure-options 2>/dev/null)
  if [ "${apache_mode_option}" == '2' ] && ! echo "${php_conf_opts}" | grep -q apxs; then
    echo "${CFAILURE}当前 PHP 不是以 --with-apxs2 编译的，mod_php 模式下 Apache 会把 .php 当纯文本输出（源码泄露）。${CEND}"
    echo "${CWARNING}请改用 --apache_mode_option 1（php-fpm），或先卸载 PHP 再与 Apache 一起安装${CEND}"
    exit 1
  fi
  if [ "${apache_mode_option}" != '2' ] && ! echo "${php_conf_opts}" | grep -q 'enable-fpm'; then
    echo "${CFAILURE}当前 PHP 是以 mod_php 方式编译的（没有 php-fpm），不能直接切回 php-fpm 模式。${CEND}"
    echo "${CWARNING}请先执行 ./uninstall.sh --php --phpcache（以及 --web 卸掉 Apache），再用本次参数重装${CEND}"
    exit 1
  fi
fi

# Nginx server
case "${nginx_option}" in
1)
  . include/nginx.sh
  Run_Install Install_Nginx
  ;;
2)
  . include/tengine.sh
  Run_Install Install_Tengine
  ;;
3)
  . include/openresty.sh
  Run_Install Install_OpenResty
  ;;
4)
  . include/caddy.sh
  Run_Install Install_Caddy
  caddy_flag='y'
  ;;
esac

# Apache
if [ "${apache_flag}" == 'y' ]; then
  apache_mode_option=${apache_mode_option:-1}
  apache_mpm_option=${apache_mpm_option:-1}
  # mod_php 只能跑在 prefork 上：event / worker 是线程化 MPM，Apache 加载 php7_module 时会直接起不来
  # （httpd 报 "Module mod_php.c is not compatible with threaded MPM"）。
  # 用户显式选了 mod_php 却没指定 MPM 时，自动切到 prefork 并说明，别让他装完 Apache 起不来。
  if [ "${apache_mode_option}" == '2' ] && [ "${apache_mpm_option}" != '2' ]; then
    echo "${CWARNING}apache_mode_option=2（mod_php）只支持 prefork MPM，已自动把 apache_mpm_option 从 ${apache_mpm_option} 改成 2${CEND}"
    apache_mpm_option=2
  fi
  . include/apache.sh
  Run_Install Install_Apache
fi

# PHP（只支持 7.4 起；5.3-7.3 在 Debian 12/13 的 gcc 12/14 下编不过，已整体移除）
case "${php_option}" in
  1)
    . include/php-7.4.sh
    Run_Install Install_PHP74
    ;;
  2)
    . include/php-8.0.sh
    Run_Install Install_PHP80
    ;;
  3)
    . include/php-8.1.sh
    Run_Install Install_PHP81
    ;;
  4)
    . include/php-8.2.sh
    Run_Install Install_PHP82
    ;;
  5)
    . include/php-8.3.sh
    Run_Install Install_PHP83
    ;;
  6)
    . include/php-8.4.sh
    Run_Install Install_PHP84
    ;;
  7)
    . include/php-8.5.sh
    Run_Install Install_PHP85
    ;;
esac

PHP_addons() {
  # PHP opcode cache
  case "${phpcache_option}" in
    1)
      . include/zendopcache.sh
      Run_Install Install_ZendOPcache
      ;;
    2)
      . include/apcu.sh
      Run_Install Install_APCU
      ;;
  esac

  # ioncube
  if [ "${pecl_ioncube}" == '1' ]; then
    . include/ioncube.sh
    Run_Install Install_ionCube
  fi

  # imagick
  if [ "${pecl_imagick}" == '1' ]; then
    . include/ImageMagick.sh
    Run_Install Install_ImageMagick
    Run_Install Install_pecl_imagick
  fi

  # gmagick
  # gmagick 2.0.6RC1 在 PHP 8.4+ 上 ABI 不兼容（实测 `php -d extension=gmagick.so` 直接
  # symbol lookup error: undefined symbol: zend_exception_get_default），编出来也用不了，
  # 用户手动把 ini 改回来只会得到起不来的 PHP。所以 8.4+ 直接跳过并明确告警。
  _php_mm=$("${php_install_dir}/bin/php" -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)
  if [ "${pecl_gmagick}" == '1' ] && [ "${_php_mm}" != '8.4' ] && [ "${_php_mm}" != '8.5' ]; then
    . include/GraphicsMagick.sh
    Run_Install Install_GraphicsMagick
    Run_Install Install_pecl_gmagick
    # imagick 与 gmagick 在 PHP 层互斥（都注册同名模块依赖，先加载的生效，
    # 后加载者报 "conflicting module"）。两者都选装时默认启用 imagick，
    # 把 gmagick 的 ini 改名禁用，保留 .so 供日后切换
    if [ "${pecl_imagick}" == '1' ] && [ -e "${php_install_dir}/etc/php.d/03-gmagick.ini" ]; then
      mv ${php_install_dir}/etc/php.d/03-gmagick.ini ${php_install_dir}/etc/php.d/03-gmagick.ini.disabled
      echo "${CWARNING}imagick 与 gmagick 互斥：已默认启用 imagick，gmagick 的 ini 已改名为 03-gmagick.ini.disabled（需要换用时把两个 ini 手动对调）${CEND}"
    fi
  elif [ "${pecl_gmagick}" == '1' ]; then
    echo "${CWARNING}gmagick 在 PHP ${_php_mm} 下 ABI 不兼容（php -d extension=gmagick.so 会 undefined symbol: zend_exception_get_default），已跳过${CEND}"
  fi

  # fileinfo
  if [ "${pecl_fileinfo}" == '1' ]; then
    . include/pecl_fileinfo.sh
    Run_Install Install_pecl_fileinfo
  fi

  # imap
  if [ "${pecl_imap}" == '1' ]; then
    . include/pecl_imap.sh
    Run_Install Install_pecl_imap
  fi

  # ldap
  if [ "${pecl_ldap}" == '1' ]; then
    . include/pecl_ldap.sh
    Run_Install Install_pecl_ldap
  fi

  # calendar
  if [ "${pecl_calendar}" == '1' ]; then
    . include/pecl_calendar.sh
    Run_Install Install_pecl_calendar
  fi

  # phalcon
  if [ "${pecl_phalcon}" == '1' ]; then
    . include/pecl_phalcon.sh
    Run_Install Install_pecl_phalcon
  fi

  # yaf
  if [ "${pecl_yaf}" == '1' ]; then
    . include/pecl_yaf.sh
    Run_Install Install_pecl_yaf
  fi

  # yar
  if [ "${pecl_yar}" == '1' ]; then
    . include/pecl_yar.sh
    Run_Install Install_pecl_yar
  fi

  # pecl_memcached
  if [ "${pecl_memcached}" == '1' ]; then
    . include/memcached.sh
    Run_Install Install_pecl_memcached
  fi

  # pecl_memcache
  if [ "${pecl_memcache}" == '1' ]; then
    . include/memcached.sh
    Run_Install Install_pecl_memcache
  fi

  # pecl_redis
  if [ "${pecl_redis}" == '1' ]; then
    . include/redis.sh
    Run_Install Install_pecl_redis
  fi

  # pecl_mongodb
  if [ "${pecl_mongodb}" == '1' ]; then
    . include/pecl_mongodb.sh
    Run_Install Install_pecl_mongodb
  fi

  # swoole
  if [ "${pecl_swoole}" == '1' ]; then
    . include/pecl_swoole.sh
    Run_Install Install_pecl_swoole
  fi

  # xdebug
  if [ "${pecl_xdebug}" == '1' ]; then
    . include/pecl_xdebug.sh
    Run_Install Install_pecl_xdebug
  fi

  # igbinary（redis / memcached 的二进制序列化，装在最前供其他扩展依赖）
  if [ "${pecl_igbinary}" == '1' ]; then
    . include/pecl_igbinary.sh
    Run_Install Install_pecl_igbinary
  fi

  # msgpack
  if [ "${pecl_msgpack}" == '1' ]; then
    . include/pecl_msgpack.sh
    Run_Install Install_pecl_msgpack
  fi

  # zstd
  if [ "${pecl_zstd}" == '1' ]; then
    . include/pecl_zstd.sh
    Run_Install Install_pecl_zstd
  fi

  # grpc
  if [ "${pecl_grpc}" == '1' ]; then
    . include/pecl_grpc.sh
    Run_Install Install_pecl_grpc
  fi

  # xlswriter
  if [ "${pecl_xlswriter}" == '1' ]; then
    . include/pecl_xlswriter.sh
    Run_Install Install_pecl_xlswriter
  fi

  # pecl_pgsql：装了 PostgreSQL 就自动装 PHP 驱动
  if [ -e "${pgsql_install_dir}/bin/psql" ]; then
    . include/pecl_pgsql.sh
    Run_Install Install_pecl_pgsql
  fi

  # pecl_mongodb：与 pgsql 对齐 —— 装了 MongoDB 也自动装 PHP 驱动。
  # 否则 MongoDB 必须显式 --php_extensions mongodb 才有驱动，
  # 结果「库装好了但 PHP 连不上」，两档行为不一致
  # pecl_mongodb=1 说明用户已经通过 --php_extensions 指定过，上面那段装过就不再重复。
  if [ -e "${mongo_install_dir}/bin/mongod" ] && [ "${pecl_mongodb}" != '1' ]; then
    . include/pecl_mongodb.sh
    Run_Install Install_pecl_mongodb
  fi

  # 扩展的 ini 是 php-fpm 启动时读取的，装完不重启等于没生效：
  # 命令行 php -m 能看到，网页端却还报 Class/Function not found。
  php_svc=php-fpm
  case "${php_install_dir}" in
    */php[0-9]*) php_svc="php${php_install_dir##*/php}-fpm" ;;
  esac
  if [ -e "/lib/systemd/system/${php_svc}.service" ] && [ "$(systemctl is-active ${php_svc} 2>/dev/null)" == 'active' ]; then
    systemctl restart ${php_svc} && echo "${CMSG}已重启 ${php_svc} 让新装的扩展生效${CEND}"
  fi
}

[ "${mphp_addons_flag}" != 'y' ] && PHP_addons

if [ "${mphp_flag}" == 'y' ]; then
  . include/mphp.sh
  Run_Install Install_MPHP
  # 装失败时目录不存在，直接拼接会让扩展装到错误路径，确认存在才改
  [ -d "${php_install_dir}${mphp_ver}" ] && php_install_dir=${php_install_dir}${mphp_ver}
  PHP_addons
fi

# Nodejs
if [ "${nodejs_flag}" == 'y' ]; then
  . include/nodejs.sh
  Run_Install Install_Nodejs
fi

# Supervisor
if [ "${supervisor_flag}" == 'y' ]; then
  . include/addon_mark.sh
  . include/supervisor.sh
  Run_Install Install_supervisor
fi

# Pure-FTPd
if [ "${pureftpd_flag}" == 'y' ]; then
  . include/pureftpd.sh
  Run_Install Install_PureFTPd
fi

# phpMyAdmin
if [ "${phpmyadmin_flag}" == 'y' ]; then
  . include/phpmyadmin.sh
  Run_Install Install_phpMyAdmin
fi

# --phpmyadmin_local：面板只允许本机访问（默认它是公网可达的，只有它自己的登录页把关）
if [ -d "${wwwroot_dir}/default/phpMyAdmin" ] && [ "${phpmyadmin_local}" == 'y' ]; then
  # 只在「nginx 自己跑 PHP」时用 nginx 限制；LNMPA（nginx 反代 apache）时 PHP 由 apache 执行，
  # 用下面的 apache <Directory> 限制，不再插 nginx 的 location（否则会把反代绕过去）。
  # web_install_dir 由 check_dir.sh 赋值，而它首次 source 时机器上还没有 nginx（二次 source 在本块之后），
  # 所以全新安装时这个变量是空的 -> 整块被跳过、保护静默失效
  _pma_web=''
  for _c in "${nginx_install_dir}" "${tengine_install_dir}" "${openresty_install_dir}/nginx"; do
    [ -e "${_c}/sbin/nginx" ] && { _pma_web="${_c}"; break; }
  done
  if [ -n "${_pma_web}" ] && [ ! -e "${apache_install_dir}/bin/httpd" ]; then
    if ! grep -q 'location ^~ /phpMyAdmin/' "${_pma_web}/conf/nginx.conf"; then
      # 注意：^~ 是前缀匹配且会屏蔽正则 location，/phpMyAdmin/ 下的 .php 不再匹配
      # `location ~ [^/]\.php(/|$)`。块内必须自带 fastcgi 处理，否则 phpMyAdmin 的 .php
      # 会被当成静态文件返回源码
      _pma_snippet=$(mktemp)
      cat > "${_pma_snippet}" << 'PMAEOF'
    location ^~ /phpMyAdmin/ {
      allow 127.0.0.1;
      deny all;
      location ~ \.php$ {
        fastcgi_pass unix:/dev/shm/php-cgi.sock;
        fastcgi_index index.php;
        include fastcgi.conf;
        try_files $fastcgi_script_name =404;
      }
    }

PMAEOF
      # 用 awk 把片段插到 well-known 那一段前面（避免和 sed 的转义打架）
      awk -v f="${_pma_snippet}" '
        /^    location \/\.well-known \{/ && !done { while ((getline line < f) > 0) print line; done=1 }
        { print }
      ' "${_pma_web}/conf/nginx.conf" > "${_pma_web}/conf/nginx.conf.new" && \
        /bin/mv "${_pma_web}/conf/nginx.conf.new" "${_pma_web}/conf/nginx.conf"
      rm -f "${_pma_snippet}"
      if ${_pma_web}/sbin/nginx -t > /dev/null 2>&1; then
        ${_pma_web}/sbin/nginx -s reload > /dev/null 2>&1
      else
        echo "${CFAILURE}nginx -t 未通过，phpMyAdmin 访问限制未生效，请检查 ${_pma_web}/conf/nginx.conf${CEND}"
      fi
    fi
    if grep -q 'location ^~ /phpMyAdmin/' "${_pma_web}/conf/nginx.conf" 2>/dev/null; then
      echo "${CSUCCESS}phpMyAdmin 已限制为只允许 127.0.0.1 访问${CEND}"
    else
      echo "${CFAILURE}phpMyAdmin 访问限制未能写入 ${_pma_web}/conf/nginx.conf，请手动添加${CEND}"
    fi
  fi
  if [ -e "${apache_install_dir}/conf/httpd.conf" ]; then
    if ! grep -q 'phpMyAdmin 只允许本机' "${apache_install_dir}/conf/httpd.conf"; then
      cat >> "${apache_install_dir}/conf/httpd.conf" << EOF

# phpMyAdmin 只允许本机（Lemon --phpmyadmin_local）
<Directory "${wwwroot_dir}/default/phpMyAdmin">
  Require ip 127.0.0.1 ::1
</Directory>
EOF
      ${apache_install_dir}/bin/apachectl -k graceful > /dev/null 2>&1
    fi
    echo "${CSUCCESS}phpMyAdmin 已限制为只允许 127.0.0.1 访问（Apache）${CEND}"
  fi
fi

# redis
if [ "${redis_flag}" == 'y' ]; then
  . include/redis.sh
  Run_Install Install_redis_server
fi

# memcached
if [ "${memcached_flag}" == 'y' ]; then
  . include/memcached.sh
  Run_Install Install_memcached_server
fi

# valkey
if [ "${valkey_flag}" == 'y' ]; then
  . include/valkey.sh
  Run_Install Install_valkey
fi

# clickhouse
if [ "${clickhouse_flag}" == 'y' ]; then
  . include/clickhouse.sh
  Run_Install Install_ClickHouse
fi

# index example
if [ -d "${wwwroot_dir}/default" ]; then
  . include/demo.sh
  Run_Install DEMO
fi

# get web_install_dir and db_install_dir
. include/check_dir.sh

# Starting DB
# 目标已存在时 mv 会嵌成 /etc/mysql_bk/mysql（重跑 install 就会中招）
[ -d "/etc/mysql" ] && [ ! -e /etc/mysql_bk ] && /bin/mv /etc/mysql /etc/mysql_bk
[ -d "${db_install_dir}/support-files" ] && [ -z "`ps -ef | grep mysqld_safe | grep -v grep`" ] && service mysqld start

# reload php
[ -e "${php_install_dir}/sbin/php-fpm" ] && { [ -e "/bin/systemctl" ] && systemctl reload php-fpm || service php-fpm reload; }
[ -n "${mphp_ver}" -a -e "${php_install_dir}${mphp_ver}/sbin/php-fpm" ] && { [ -e "/bin/systemctl" ] && systemctl reload php${mphp_ver}-fpm || service php${mphp_ver}-fpm reload; }
[ -e "${apache_install_dir}/bin/apachectl" ] && ${apache_install_dir}/bin/apachectl -k graceful

# ---- 安装结果校验 ----
# 各组件的安装函数在失败分支里只 echo 一句就 return，而 install.sh 用 `... | tee -a` 调用，
# 管道的退出码永远是 tee 的 0 —— 于是「PHP 源码包没下下来」这类失败照样会打印
# Congratulations 并 exit 0。收尾前按「请求装了什么」逐个验二进制，缺一个就失败退出。
# 装完自检：用配置的 root 密码真登一次。
# 「二进制在、服务在跑，但密码没生效」是最隐蔽的半残状态：Debian 13 上装 MySQL 5.7 就是
# 客户端缺 libncurses.so.5 → 设密码的 SQL 全失败 → root 保持空密码，而安装器照样打印密码。
# 这里只告警不阻断（特殊环境可能有自定义认证），但必须让它在日志里露出来。
case "${db_option}" in
  0|1|2|3|4|5|6|9)
    # 刚装完 mysqld 可能还没 ready，直接登录会误判成失败
    # 先最多等 30 秒，再判定。
    _db_ok=0
    for _i in 1 2 3 4 5 6 7 8 9 10; do
      if MYSQL_PWD="${dbrootpwd}" ${db_install_dir}/bin/mysql -uroot -e 'select 1' > /dev/null 2>&1; then
        _db_ok=1; break
      fi
      sleep 3
    done
    if [ -x "${db_install_dir}/bin/mysql" ] && [ "${_db_ok}" != '1' ]; then
      # 二进制在 ≠ 能登录：mysqld 起不来 / 数据目录没初始化好，这里都能拦住。
      # 不能只打一行警告就继续，否则最后照样 Congratulations
      echo "${CFAILURE}数据库自检失败：用 dbrootpwd 登录不上，数据库实际不可用${CEND}"
      echo "${CWARNING}排查：systemctl status mysqld；看 error log；确认 /data/mysql 下有 mysql 系统库${CEND}"
      INSTALL_FAILED="${INSTALL_FAILED} database-check"
    fi
    ;;
  7)
    if [ -x "${pgsql_install_dir}/bin/psql" ] && ! PGPASSWORD="${dbpostgrespwd}" ${pgsql_install_dir}/bin/psql -h 127.0.0.1 -U postgres -tAc 'select 1' > /dev/null 2>&1; then
      echo "${CWARNING}PostgreSQL 自检：用 postgres 密码登录失败，请手动确认${CEND}"
    fi
    ;;
esac
post_fail=""
case "${nginx_option}" in
  1) [ -e "${nginx_install_dir}/sbin/nginx" ] || post_fail="${post_fail} nginx" ;;
  2) [ -e "${tengine_install_dir}/sbin/nginx" ] || post_fail="${post_fail} tengine" ;;
  3) [ -e "${openresty_install_dir}/nginx/sbin/nginx" ] || post_fail="${post_fail} openresty" ;;
  4) [ -e "${caddy_install_dir}/bin/caddy" ] || post_fail="${post_fail} caddy" ;;
esac
if [ "${apache_flag}" == 'y' ] && [ ! -e "${apache_install_dir}/bin/httpd" ]; then post_fail="${post_fail} apache"; fi
case "${db_option}" in
  0|1|2) [ -e "${mysql_install_dir}/bin/mysqld" ] || post_fail="${post_fail} mysql" ;;
  3|4|5) [ -e "${mariadb_install_dir}/bin/mariadbd" ] || [ -e "${mariadb_install_dir}/bin/mysqld" ] || post_fail="${post_fail} mariadb" ;;
  6|9) [ -e "${percona_install_dir}/bin/mysqld" ] || post_fail="${post_fail} percona" ;;
  7) [ -e "${pgsql_install_dir}/bin/postgres" ] || post_fail="${post_fail} postgresql" ;;
  8) [ -e "${mongo_install_dir}/bin/mongod" ] || post_fail="${post_fail} mongodb" ;;
esac
if [[ "${php_option}" =~ ^[1-7]$ ]] && [ ! -e "${php_install_dir}/bin/php" ]; then post_fail="${post_fail} php"; fi
# 并存 PHP：install.sh 上面已经把 php_install_dir 改写成 ${php_install_dir}${mphp_ver} 了，
# 所以两种拼法都要认，否则装成功也会误报失败
if [ "${mphp_flag}" == 'y' ] && [ ! -e "${php_install_dir}/bin/php" ] && [ ! -e "${php_install_dir}${mphp_ver}/bin/php" ]; then
  post_fail="${post_fail} php${mphp_ver}"
fi
if [ "${redis_flag}" == 'y' ] && [ ! -e "${redis_install_dir}/bin/redis-server" ]; then post_fail="${post_fail} redis"; fi
if [ "${valkey_flag}" == 'y' ] && [ ! -e "${valkey_install_dir}/bin/valkey-server" ]; then post_fail="${post_fail} valkey"; fi
if [ "${memcached_flag}" == 'y' ] && [ ! -e "${memcached_install_dir}/bin/memcached" ]; then post_fail="${post_fail} memcached"; fi
if [ "${clickhouse_flag}" == 'y' ] && [ ! -e "${clickhouse_install_dir}/bin/clickhouse" ]; then post_fail="${post_fail} clickhouse"; fi
if [ "${nodejs_flag}" == 'y' ] && [ ! -e "${nodejs_install_dir}/bin/node" ]; then post_fail="${post_fail} nodejs"; fi
if [ "${pureftpd_flag}" == 'y' ] && [ ! -d "${pureftpd_install_dir}" ]; then post_fail="${post_fail} pureftpd"; fi
if [ "${phpmyadmin_flag}" == 'y' ] && [ ! -d "${wwwroot_dir}/default/phpMyAdmin" ]; then post_fail="${post_fail} phpmyadmin"; fi
if [ -n "${post_fail}" ]; then
  echo
  echo "${CFAILURE}Install verification FAILED:${post_fail}${CEND}"
  echo "${CWARNING}以上组件没有真正装上，详情见 ${lemon_dir}/install.log。已中止，不要当成安装成功。${CEND}"
  exit 1
fi

# 把常用 CLI 链到 /usr/local/bin：非登录 shell（cron / CI / ssh 直接 exec）的 PATH 只含
# /usr/local/bin 这类目录，不链的话 composer 的 #!/usr/bin/env php、npm 的 #!/usr/bin/env node
# 都会报 "No such file or directory"（组件本身是好的，容易被误判成装坏）。
for _pair in "${php_install_dir}/bin/php:php" "${php_install_dir}/bin/phpize:phpize"              "${php_install_dir}/bin/php-config:php-config"              "${nodejs_install_dir}/bin/node:node" "${nodejs_install_dir}/bin/npm:npm"              "${nodejs_install_dir}/bin/npx:npx"; do
  _src="${_pair%%:*}"; _name="${_pair##*:}"
  [ -x "${_src}" ] && ln -sf "${_src}" "/usr/local/bin/${_name}"
done
unset _pair _src _name

# options.conf 里是数据库 root 密码等敏感信息：收尾再收紧一次权限
# （git reset / cp 之类会把文件还原成 644，装机过程中也可能被别的写操作冲掉）
chmod 600 ./options.conf 2>/dev/null

endTime=`date +%s`
installSecs=$((endTime-startTime))
installTime=$((installSecs/60))
if [ -n "${INSTALL_FAILED}" ]; then
  echo "${CFAILURE}以下组件安装失败：${INSTALL_FAILED}${CEND}"
  echo "${CWARNING}请查看 ${lemon_dir}/install.log；失败组件可能停在半安装状态${CEND}"
  exit 1
fi
echo "####################Congratulations########################"
# install.log 有路径与版本信息，按 600 收紧；并装 logrotate 防无限增长
chmod 600 "${lemon_dir}/install.log" 2>/dev/null
if [ -d /etc/logrotate.d ]; then
  # 路径必须跟 lemon_dir 走：写死 /root/lemon 时，仓库换位置就永远不轮转
  cat > /etc/logrotate.d/lemon <<LR
${lemon_dir}/install.log {
    weekly
    rotate 4
    missingok
    notifempty
    compress
    create 600 root root
}
LR
fi

echo "Total Lemon Install Time: ${CQUESTION}${installTime}m $((installSecs%60))s${CEND}"
[[ "${nginx_option}" =~ ^[1-3]$ ]] && echo -e "\n$(printf "%-32s" "Nginx install dir":)${CMSG}${web_install_dir}${CEND}"
[ "${apache_flag}" == 'y' ] && echo -e "\n$(printf "%-32s" "Apache install dir":)${CMSG}${apache_install_dir}${CEND}"
[ "${caddy_flag}" == 'y' ] && echo -e "\n$(printf "%-32s" "Caddy install dir":)${CMSG}${caddy_install_dir}${CEND}"
[[ "${db_option}" =~ ^([0-6]|9)$ ]] && echo -e "\n$(printf "%-32s" "Database install dir:")${CMSG}${db_install_dir}${CEND}"
[[ "${db_option}" =~ ^([0-6]|9)$ ]] && echo "$(printf "%-32s" "Database data dir:")${CMSG}${db_data_dir}${CEND}"
[[ "${db_option}" =~ ^([0-6]|9)$ ]] && echo "$(printf "%-32s" "Database user:")${CMSG}root${CEND}"
[[ "${db_option}" =~ ^([0-6]|9)$ ]] && echo "$(printf "%-32s" "Database password:")${CMSG}${dbrootpwd}${CEND}"
[ "${db_option}" == '7' ] && echo -e "\n$(printf "%-32s" "PostgreSQL install dir:")${CMSG}${pgsql_install_dir}${CEND}"
[ "${db_option}" == '7' ] && echo "$(printf "%-32s" "PostgreSQL data dir:")${CMSG}${pgsql_data_dir}${CEND}"
[ "${db_option}" == '7' ] && echo "$(printf "%-32s" "PostgreSQL user:")${CMSG}postgres${CEND}"
[ "${db_option}" == '7' ] && echo "$(printf "%-32s" "postgres password:")${CMSG}${dbpostgrespwd}${CEND}"
[ "${db_option}" == '8' ] && echo -e "\n$(printf "%-32s" "MongoDB install dir:")${CMSG}${mongo_install_dir}${CEND}"
[ "${db_option}" == '8' ] && echo "$(printf "%-32s" "MongoDB data dir:")${CMSG}${mongo_data_dir}${CEND}"
[ "${db_option}" == '8' ] && echo "$(printf "%-32s" "MongoDB user:")${CMSG}root${CEND}"
[ "${db_option}" == '8' ] && echo "$(printf "%-32s" "MongoDB password:")${CMSG}${dbmongopwd}${CEND}"
# 数据库端口默认对公网监听（bind-address/listen_addresses 为 0.0.0.0），
# 没有远程访问需求建议改回本机监听，或用 --firewall 启用防火墙
if [ "${db_bind_public}" == 'y' ]; then
  echo -e "\n$(printf "%-32s" "Database security notice:")${CWARNING}数据库按 --db_bind_public 监听在 0.0.0.0，请务必配防火墙白名单${CEND}"
else
  echo -e "\n$(printf "%-32s" "Database security notice:")${CSUCCESS}数据库只监听 127.0.0.1（需要远程连库再加 --db_bind_public）${CEND}"
fi
[[ "${php_option}" =~ ^[1-7]$ ]] && echo -e "\n$(printf "%-32s" "PHP install dir:")${CMSG}${php_install_dir}${CEND}"
[ "${phpcache_option}" == '1' ] && echo "$(printf "%-32s" "Opcache Control Panel:")${CWARNING}面板组件已改为不默认部署，如需 ocp.php 请自行手动部署（公开访问有风险）${CEND}"
[ "${phpcache_option}" == '2' ] && echo "$(printf "%-32s" "APC Control Panel:")${CWARNING}面板组件已改为不默认部署，如需 apc.php 请自行手动部署（公开访问有风险）${CEND}"
[ "${supervisor_flag}" == 'y' ] && echo -e "\n$(printf "%-32s" "Supervisor config dir:")${CMSG}/etc/supervisor/conf.d${CEND}"
[ "${pureftpd_flag}" == 'y' ] && echo -e "\n$(printf "%-32s" "Pure-FTPd install dir:")${CMSG}${pureftpd_install_dir}${CEND}"
[ "${pureftpd_flag}" == 'y' ] && echo "$(printf "%-32s" "Create FTP virtual script:")${CMSG}./pureftpd_vhost.sh${CEND}"
[ "${phpmyadmin_flag}" == 'y' ] && echo -e "\n$(printf "%-32s" "phpMyAdmin dir:")${CMSG}${wwwroot_dir}/default/phpMyAdmin${CEND}"
[ "${phpmyadmin_flag}" == 'y' ] && echo "$(printf "%-32s" "phpMyAdmin Control Panel URL:")${CMSG}http://${IPADDR}/phpMyAdmin${CEND}"
[ "${redis_flag}" == 'y' ] && echo -e "\n$(printf "%-32s" "redis install dir:")${CMSG}${redis_install_dir}${CEND}"
[ "${valkey_flag}" == 'y' ] && echo -e "\n$(printf "%-32s" "valkey install dir:")${CMSG}${valkey_install_dir}${CEND}"
[ "${clickhouse_flag}" == 'y' ] && echo -e "\n$(printf "%-32s" "ClickHouse install dir:")${CMSG}${clickhouse_install_dir}${CEND}"
[ "${clickhouse_flag}" == 'y' ] && echo "$(printf "%-32s" "ClickHouse data dir:")${CMSG}${clickhouse_data_dir}${CEND}"
[ "${clickhouse_flag}" == 'y' ] && echo "$(printf "%-32s" "ClickHouse user:")${CMSG}default${CEND}"
[ "${clickhouse_flag}" == 'y' ] && echo "$(printf "%-32s" "ClickHouse password:")${CMSG}${dbclickhousepwd}${CEND}"
[ "${memcached_flag}" == 'y' ] && echo -e "\n$(printf "%-32s" "memcached install dir:")${CMSG}${memcached_install_dir}${CEND}"
if [[ ${nginx_option} =~ ^[1-4]$ ]] || [ "${apache_flag}" == 'y' ]; then
  echo -e "\n$(printf "%-32s" "Index URL:")${CMSG}http://${IPADDR}/${CEND}"
fi
if [ ${ARG_NUM} == 0 ]; then
  while :; do echo
    echo "${CMSG}Please restart the server and see if the services start up fine.${CEND}"
    read -e -p "Do you want to restart OS ? [y/n]: " reboot_flag
    if [[ ! "${reboot_flag}" =~ ^[y,n]$ ]]; then
      echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
    else
      break
    fi
  done
fi
if [ "${reboot_flag}" == 'y' ]; then
  reboot
fi
# 最后一条语句是 [ ... ] && reboot，reboot_flag 不为 y 时它的返回码是 1，
# 会让整个脚本以「失败」退出，自动化/CI 判定全线报错。显式收尾。
exit 0
