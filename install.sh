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
pushd ${lemon_dir} > /dev/null
. ./versions.txt
. ./options.conf
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
  --db_bind_local             Make MySQL/PostgreSQL/MongoDB listen on 127.0.0.1 only
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
TEMP=`getopt -o hvV --long help,version,nginx_option:,apache,apache_mode_option:,apache_mpm_option:,php_option:,mphp_ver:,mphp_addons,phpcache_option:,php_extensions:,nodejs,supervisor,db_option:,dbrootpwd:,dbinstallmethod:,pureftpd,redis,valkey,clickhouse,dbclickhousepwd:,memcached,phpmyadmin,phpmyadmin_local,db_bind_local,ssh_port:,firewall,reboot -- "$@" 2>/dev/null`
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
    phpmyadmin_local=y
    shift 1
    ;;
  --db_bind_local)
    db_bind_local=y
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

  if [ -z "`grep ^Port /etc/ssh/sshd_config`" -a "${ssh_port}" != '22' ]; then
    sed -i "s@^#Port.*@&\nPort ${ssh_port}@" /etc/ssh/sshd_config
  elif [ -n "`grep ^Port /etc/ssh/sshd_config`" ]; then
    sed -i "s@^Port.*@Port ${ssh_port}@" /etc/ssh/sshd_config
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
[ -x ./include/ois.${ARCH} ] || chmod +x ./include/ois.${ARCH} 2>/dev/null
IPADDR=$(./include/ois.${ARCH} ip_local)
OUTIP_STATE=$(./include/ois.${ARCH} ip_state)

# openSSL
. ./include/openssl.sh

# Debian 13 上不要装 MySQL 5.7：官方 5.7.44 的 glibc2.12 tar 包里，客户端二进制硬链接
# libncurses.so.5（trixie 已无 libncurses5/libtinfo5 包），服务端能起来但 mysql 客户端
# 一调就 "error while loading shared libraries"，连 install.sh 自己设 root 密码那步都会失败 ——
# 装出来是个「服务在跑、客户端不可用、root 密码可能没设上」的半残环境。5.7 也已 EOL，直接拦住。
# 注意必须放在下载阶段之前：否则会先把 694MB 的 5.7 包下完再报错（真机验证时踩到）。
if [ "${db_option}" == '0' ] && [ "${Debian_ver}" -ge 13 ] 2>/dev/null; then
  echo "${CFAILURE}Debian 13 不支持 MySQL 5.7：客户端依赖 libncurses.so.5，trixie 已移除该包，装完 mysql 命令不可用。请改用 --db_option 1（MySQL 8.0）或 2（MySQL 8.4）${CEND}"
  exit 1
fi

# Check download source packages
. ./include/check_download.sh

checkDownload 2>&1 | tee -a ${lemon_dir}/install.log

# get OS Memory
. ./include/memory.sh

if [ ! -e ~/.lemon ] || [ "$(cat ~/.lemon 2>/dev/null)" != "deps-${lemon_deps_ver}" ]; then
  # Check binary dependencies packages
  . ./include/check_sw.sh
  installDepsDebian 2>&1 | tee -a ${lemon_dir}/install.log
  . include/init_Debian.sh 2>&1 | tee -a ${lemon_dir}/install.log
  # Install dependencies from source package
  installDepsBySrc 2>&1 | tee -a ${lemon_dir}/install.log
fi

# start Time
startTime=`date +%s`

# openSSL

# Jemalloc
if [[ ${nginx_option} =~ ^[1-3]$ ]] || [[ "${db_option}" =~ ^([0-6]|9)$ ]]; then
  . include/jemalloc.sh
  Install_Jemalloc | tee -a ${lemon_dir}/install.log
fi

# Database
case "${db_option}" in
  0)
    . include/mysql-5.7.sh
    Install_MySQL57 2>&1 | tee -a ${lemon_dir}/install.log
    ;;
  1)
    . include/mysql-8.0.sh
    Install_MySQL80 2>&1 | tee -a ${lemon_dir}/install.log
    ;;
  2)
    . include/mysql-8.4.sh
    Install_MySQL84 2>&1 | tee -a ${lemon_dir}/install.log
    ;;
  3)
    . include/mariadb-10.11.sh
    Install_MariaDB1011 2>&1 | tee -a ${lemon_dir}/install.log
    ;;
  4)
    . include/mariadb-11.4.sh
    Install_MariaDB114 2>&1 | tee -a ${lemon_dir}/install.log
    ;;
  5)
    . include/mariadb-11.8.sh
    Install_MariaDB118 2>&1 | tee -a ${lemon_dir}/install.log
    ;;
  6)
    . include/percona-8.0.sh
    Install_Percona80 2>&1 | tee -a ${lemon_dir}/install.log
    ;;
  7)
    . include/postgresql.sh
    Install_PostgreSQL 2>&1 | tee -a ${lemon_dir}/install.log
    ;;
  8)
    . include/mongodb.sh
    Install_MongoDB 2>&1 | tee -a ${lemon_dir}/install.log
    ;;
  9)
    . include/percona-8.4.sh
    Install_Percona84 2>&1 | tee -a ${lemon_dir}/install.log
    ;;
esac

# --db_bind_local：数据库只监听 127.0.0.1。
# 默认是 0.0.0.0 / '*'（方便远程连），但直接暴露在公网是高危默认值；
# 只需要本机访问的场景（绝大多数站点）应当显式收紧。
if [ "${db_bind_local}" == 'y' ]; then
  case "${db_option}" in
    0|1|2|3|4|5|6|9)
      # MySQL / MariaDB / Percona：改 my.cnf 的 bind-address。
      # 注意路径是 /etc/my.cnf（各 db 脚本都写这里），不是 ${db_install_dir}/etc/my.cnf
      my_cnf=/etc/my.cnf
      [ -e "${my_cnf}" ] || my_cnf="${db_install_dir}/etc/my.cnf"
      if [ -e "${my_cnf}" ]; then
        if grep -q '^bind-address' "${my_cnf}"; then
          sed -i 's@^bind-address.*@bind-address = 127.0.0.1@' "${my_cnf}"
        else
          sed -i '/^\[mysqld\]/a bind-address = 127.0.0.1' "${my_cnf}"
        fi
        service mysqld restart > /dev/null 2>&1
        echo "${CSUCCESS}MySQL 已改为只监听 127.0.0.1（${my_cnf}）${CEND}"
      else
        echo "${CWARNING}没找到 my.cnf，跳过 bind-address 修改${CEND}"
      fi
      ;;
    7)
      if [ -e "${pgsql_data_dir}/postgresql.conf" ]; then
        sed -i "s@^listen_addresses.*@listen_addresses = 'localhost'@" ${pgsql_data_dir}/postgresql.conf
        service postgresql restart > /dev/null 2>&1
        echo "${CSUCCESS}PostgreSQL 已改为只监听 localhost${CEND}"
      fi
      ;;
    8)
      # mongodb.sh 开鉴权后会把 bindIp 改成 0.0.0.0，这里再收回去
      [ -e /etc/mongod.conf ] && sed -i 's@^  bindIp:.*@  bindIp: 127.0.0.1@' /etc/mongod.conf && systemctl restart mongod > /dev/null 2>&1
      echo "${CSUCCESS}MongoDB 已改为只监听 127.0.0.1${CEND}"
      ;;
  esac
fi

# Nginx server
case "${nginx_option}" in
1)
  . include/nginx.sh
  Install_Nginx 2>&1 | tee -a ${lemon_dir}/install.log
  ;;
2)
  . include/tengine.sh
  Install_Tengine 2>&1 | tee -a ${lemon_dir}/install.log
  ;;
3)
  . include/openresty.sh
  Install_OpenResty 2>&1 | tee -a ${lemon_dir}/install.log
  ;;
4)
  . include/caddy.sh
  Install_Caddy 2>&1 | tee -a ${lemon_dir}/install.log
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
  # mod_php 还要求 PHP 是以 --with-apxs2 编译的。常见坑：先建 LNMP、再回头补 Apache 时
  # PHP 会被「already installed」跳过，Apache 里没有 php 模块，于是 .php 被当纯文本输出
  # （源码泄露，真机 d13 复现过）。这种情况直接拒绝，不装一个会泄露源码的站点。
  if [ "${apache_mode_option}" == '2' ] && [ -e "${php_install_dir}/bin/php-config" ]; then
    if ! ${php_install_dir}/bin/php-config --configure-options 2>/dev/null | grep -q apxs; then
      echo "${CFAILURE}当前 PHP 不是以 --with-apxs2 编译的，mod_php 模式下 Apache 会把 .php 当纯文本输出（源码泄露）。${CEND}"
      echo "${CWARNING}请改用 --apache_mode_option 1（php-fpm），或先卸载 PHP 再与 Apache 一起安装${CEND}"
      exit 1
    fi
  fi
  . include/apache.sh
  Install_Apache 2>&1 | tee -a ${lemon_dir}/install.log
fi

# 已装 PHP 的 SAPI 与本次运行模式不匹配时直接拒绝。
# mod_php 编出来的 PHP 没有 --enable-fpm（没有 php-fpm 二进制和 unit），
# php-fpm 编出来的没有 apxs（没有 libphp.so）。换模式必须重装 PHP，
# 否则会停在「以为切回 LNMP、其实 php-fpm 根本不存在」的假状态（真机 d13 踩到，还把 mphp 堵死了）。
if [ -e "${php_install_dir}/bin/phpize" ]; then
  php_conf_opts=$(${php_install_dir}/bin/php-config --configure-options 2>/dev/null)
  if [ "${apache_mode_option}" != '2' ] && ! echo "${php_conf_opts}" | grep -q 'enable-fpm'; then
    echo "${CFAILURE}当前 PHP 是以 mod_php 方式编译的（没有 php-fpm），不能直接切回 php-fpm 模式。${CEND}"
    echo "${CWARNING}请先执行 ./uninstall.sh --php --phpcache（以及 --web 卸掉 Apache），再用本次参数重装${CEND}"
    exit 1
  fi
fi

# PHP（只支持 7.4 起；5.3-7.3 在 Debian 12/13 的 gcc 12/14 下编不过，已整体移除）
case "${php_option}" in
  1)
    . include/php-7.4.sh
    Install_PHP74 2>&1 | tee -a ${lemon_dir}/install.log
    ;;
  2)
    . include/php-8.0.sh
    Install_PHP80 2>&1 | tee -a ${lemon_dir}/install.log
    ;;
  3)
    . include/php-8.1.sh
    Install_PHP81 2>&1 | tee -a ${lemon_dir}/install.log
    ;;
  4)
    . include/php-8.2.sh
    Install_PHP82 2>&1 | tee -a ${lemon_dir}/install.log
    ;;
  5)
    . include/php-8.3.sh
    Install_PHP83 2>&1 | tee -a ${lemon_dir}/install.log
    ;;
  6)
    . include/php-8.4.sh
    Install_PHP84 2>&1 | tee -a ${lemon_dir}/install.log
    ;;
  7)
    . include/php-8.5.sh
    Install_PHP85 2>&1 | tee -a ${lemon_dir}/install.log
    ;;
esac

PHP_addons() {
  # PHP opcode cache
  case "${phpcache_option}" in
    1)
      . include/zendopcache.sh
      Install_ZendOPcache 2>&1 | tee -a ${lemon_dir}/install.log
      ;;
    2)
      . include/apcu.sh
      Install_APCU 2>&1 | tee -a ${lemon_dir}/install.log
      ;;
  esac

  # ioncube
  if [ "${pecl_ioncube}" == '1' ]; then
    . include/ioncube.sh
    Install_ionCube 2>&1 | tee -a ${lemon_dir}/install.log
  fi

  # imagick
  if [ "${pecl_imagick}" == '1' ]; then
    . include/ImageMagick.sh
    Install_ImageMagick 2>&1 | tee -a ${lemon_dir}/install.log
    Install_pecl_imagick 2>&1 | tee -a ${lemon_dir}/install.log
  fi

  # gmagick
  if [ "${pecl_gmagick}" == '1' ]; then
    . include/GraphicsMagick.sh
    Install_GraphicsMagick 2>&1 | tee -a ${lemon_dir}/install.log
    Install_pecl_gmagick 2>&1 | tee -a ${lemon_dir}/install.log
    # imagick 与 gmagick 在 PHP 层互斥（都注册同名模块依赖，先加载的生效，
    # 后加载者报 "conflicting module"）。两者都选装时默认启用 imagick，
    # 把 gmagick 的 ini 改名禁用，保留 .so 供日后切换
    if [ "${pecl_imagick}" == '1' ] && [ -e "${php_install_dir}/etc/php.d/03-gmagick.ini" ]; then
      mv ${php_install_dir}/etc/php.d/03-gmagick.ini ${php_install_dir}/etc/php.d/03-gmagick.ini.disabled
      echo "${CWARNING}imagick 与 gmagick 互斥：已默认启用 imagick，gmagick 的 ini 已改名为 03-gmagick.ini.disabled（需要换用时把两个 ini 手动对调）${CEND}"
    fi
  fi

  # fileinfo
  if [ "${pecl_fileinfo}" == '1' ]; then
    . include/pecl_fileinfo.sh
    Install_pecl_fileinfo 2>&1 | tee -a ${lemon_dir}/install.log
  fi

  # imap
  if [ "${pecl_imap}" == '1' ]; then
    . include/pecl_imap.sh
    Install_pecl_imap 2>&1 | tee -a ${lemon_dir}/install.log
  fi

  # ldap
  if [ "${pecl_ldap}" == '1' ]; then
    . include/pecl_ldap.sh
    Install_pecl_ldap 2>&1 | tee -a ${lemon_dir}/install.log
  fi

  # calendar
  if [ "${pecl_calendar}" == '1' ]; then
    . include/pecl_calendar.sh
    Install_pecl_calendar 2>&1 | tee -a ${lemon_dir}/install.log
  fi

  # phalcon
  if [ "${pecl_phalcon}" == '1' ]; then
    . include/pecl_phalcon.sh
    Install_pecl_phalcon 2>&1 | tee -a ${lemon_dir}/install.log
  fi

  # yaf
  if [ "${pecl_yaf}" == '1' ]; then
    . include/pecl_yaf.sh
    Install_pecl_yaf 2>&1 | tee -a ${lemon_dir}/install.log
  fi

  # yar
  if [ "${pecl_yar}" == '1' ]; then
    . include/pecl_yar.sh
    Install_pecl_yar 2>&1 | tee -a ${lemon_dir}/install.log
  fi

  # pecl_memcached
  if [ "${pecl_memcached}" == '1' ]; then
    . include/memcached.sh
    Install_pecl_memcached 2>&1 | tee -a ${lemon_dir}/install.log
  fi

  # pecl_memcache
  if [ "${pecl_memcache}" == '1' ]; then
    . include/memcached.sh
    Install_pecl_memcache 2>&1 | tee -a ${lemon_dir}/install.log
  fi

  # pecl_redis
  if [ "${pecl_redis}" == '1' ]; then
    . include/redis.sh
    Install_pecl_redis 2>&1 | tee -a ${lemon_dir}/install.log
  fi

  # pecl_mongodb
  if [ "${pecl_mongodb}" == '1' ]; then
    . include/pecl_mongodb.sh
    Install_pecl_mongodb 2>&1 | tee -a ${lemon_dir}/install.log
  fi

  # swoole
  if [ "${pecl_swoole}" == '1' ]; then
    . include/pecl_swoole.sh
    Install_pecl_swoole 2>&1 | tee -a ${lemon_dir}/install.log
  fi

  # xdebug
  if [ "${pecl_xdebug}" == '1' ]; then
    . include/pecl_xdebug.sh
    Install_pecl_xdebug 2>&1 | tee -a ${lemon_dir}/install.log
  fi

  # igbinary（redis / memcached 的二进制序列化，装在最前供其他扩展依赖）
  if [ "${pecl_igbinary}" == '1' ]; then
    . include/pecl_igbinary.sh
    Install_pecl_igbinary 2>&1 | tee -a ${lemon_dir}/install.log
  fi

  # msgpack
  if [ "${pecl_msgpack}" == '1' ]; then
    . include/pecl_msgpack.sh
    Install_pecl_msgpack 2>&1 | tee -a ${lemon_dir}/install.log
  fi

  # zstd
  if [ "${pecl_zstd}" == '1' ]; then
    . include/pecl_zstd.sh
    Install_pecl_zstd 2>&1 | tee -a ${lemon_dir}/install.log
  fi

  # grpc
  if [ "${pecl_grpc}" == '1' ]; then
    . include/pecl_grpc.sh
    Install_pecl_grpc 2>&1 | tee -a ${lemon_dir}/install.log
  fi

  # xlswriter
  if [ "${pecl_xlswriter}" == '1' ]; then
    . include/pecl_xlswriter.sh
    Install_pecl_xlswriter 2>&1 | tee -a ${lemon_dir}/install.log
  fi

  # pecl_pgsql
  if [ -e "${pgsql_install_dir}/bin/psql" ]; then
    . include/pecl_pgsql.sh
    Install_pecl_pgsql 2>&1 | tee -a ${lemon_dir}/install.log
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
  Install_MPHP 2>&1 | tee -a ${lemon_dir}/install.log
  # 装失败时目录不存在，直接拼接会让扩展装到错误路径，确认存在才改
  [ -d "${php_install_dir}${mphp_ver}" ] && php_install_dir=${php_install_dir}${mphp_ver}
  PHP_addons
fi

# Nodejs
if [ "${nodejs_flag}" == 'y' ]; then
  . include/nodejs.sh
  Install_Nodejs 2>&1 | tee -a ${lemon_dir}/install.log
fi

# Supervisor
if [ "${supervisor_flag}" == 'y' ]; then
  . include/addon_mark.sh
  . include/supervisor.sh
  Install_supervisor 2>&1 | tee -a ${lemon_dir}/install.log
fi

# Pure-FTPd
if [ "${pureftpd_flag}" == 'y' ]; then
  . include/pureftpd.sh
  Install_PureFTPd 2>&1 | tee -a ${lemon_dir}/install.log
fi

# phpMyAdmin
if [ "${phpmyadmin_flag}" == 'y' ]; then
  . include/phpmyadmin.sh
  Install_phpMyAdmin 2>&1 | tee -a ${lemon_dir}/install.log
fi

# --phpmyadmin_local：面板只允许本机访问（默认它是公网可达的，只有它自己的登录页把关）
if [ -d "${wwwroot_dir}/default/phpMyAdmin" ] && [ "${phpmyadmin_local}" == 'y' ]; then
  if [ -e "${web_install_dir}/conf/nginx.conf" ]; then
    if ! grep -q 'location ^~ /phpMyAdmin/' "${web_install_dir}/conf/nginx.conf"; then
      sed -i 's@^    location /.well-known {@    location ^~ /phpMyAdmin/ {\n      allow 127.0.0.1;\n      deny all;\n    }\n\n    location /.well-known {@' "${web_install_dir}/conf/nginx.conf"
      ${web_install_dir}/sbin/nginx -t > /dev/null 2>&1 && ${web_install_dir}/sbin/nginx -s reload > /dev/null 2>&1
    fi
    echo "${CSUCCESS}phpMyAdmin 已限制为只允许 127.0.0.1 访问${CEND}"
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
  Install_redis_server 2>&1 | tee -a ${lemon_dir}/install.log
fi

# memcached
if [ "${memcached_flag}" == 'y' ]; then
  . include/memcached.sh
  Install_memcached_server 2>&1 | tee -a ${lemon_dir}/install.log
fi

# valkey
if [ "${valkey_flag}" == 'y' ]; then
  . include/valkey.sh
  Install_valkey 2>&1 | tee -a ${lemon_dir}/install.log
fi

# clickhouse
if [ "${clickhouse_flag}" == 'y' ]; then
  . include/clickhouse.sh
  Install_ClickHouse 2>&1 | tee -a ${lemon_dir}/install.log
fi

# index example
if [ -d "${wwwroot_dir}/default" ]; then
  . include/demo.sh
  DEMO 2>&1 | tee -a ${lemon_dir}/install.log
fi

# get web_install_dir and db_install_dir
. include/check_dir.sh

# Starting DB
[ -d "/etc/mysql" ] && /bin/mv /etc/mysql{,_bk}
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
    if [ -x "${db_install_dir}/bin/mysql" ] && ! ${db_install_dir}/bin/mysql -uroot -p"${dbrootpwd}" -e 'select 1' > /dev/null 2>&1; then
      echo "${CWARNING}数据库自检：用 dbrootpwd 登录失败，请手动确认（客户端缺库或密码未生效都会这样）${CEND}"
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

endTime=`date +%s`
((installTime=($endTime-$startTime)/60))
echo "####################Congratulations########################"
echo "Total Lemon Install Time: ${CQUESTION}${installTime}${CEND} minutes"
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
[[ "${db_option}" =~ ^[0-9]$ ]] && echo -e "\n$(printf "%-32s" "Database security notice:")${CWARNING}DB port listens on 0.0.0.0 by default, change bind-address or enable firewall if no remote access is needed${CEND}"
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
