#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Install_MPHP() {
  if [ -e "${php_install_dir}/sbin/php-fpm" ]; then
    if [ -e "${php_install_dir}${mphp_ver}/bin/phpize" ]; then
      echo "${CWARNING}PHP${mphp_ver} already installed! ${CEND}"
    else
      [ -e "/lib/systemd/system/php-fpm.service" ] && /bin/mv /lib/systemd/system/php-fpm.service{,_bk}
      php_install_dir=${php_install_dir}${mphp_ver}
      case "${mphp_ver}" in
        74)
          . include/php-7.4.sh
          Run_Install Install_PHP74
          ;;
        80)
          . include/php-8.0.sh
          Run_Install Install_PHP80
          ;;
        81)
          . include/php-8.1.sh
          Run_Install Install_PHP81
          ;;
        82)
          . include/php-8.2.sh
          Run_Install Install_PHP82
          ;;
        83)
          . include/php-8.3.sh
          Run_Install Install_PHP83
          ;;
        84)
          . include/php-8.4.sh
          Run_Install Install_PHP84
          ;;
        85)
          . include/php-8.5.sh
          Run_Install Install_PHP85
          ;;
      esac
      if [ -e "${php_install_dir}/sbin/php-fpm" ]; then
        systemctl stop php-fpm
        sed -i "s@/dev/shm/php-cgi.sock@/dev/shm/php${mphp_ver}-cgi.sock@" ${php_install_dir}/etc/php-fpm.conf
        [ -e "/lib/systemd/system/php-fpm.service" ] && /bin/mv /lib/systemd/system/php-fpm.service /lib/systemd/system/php${mphp_ver}-fpm.service
        [ -e "/lib/systemd/system/php-fpm.service_bk" ] && /bin/mv /lib/systemd/system/php-fpm.service{_bk,}
        systemctl enable php${mphp_ver}-fpm
        systemctl enable php-fpm
        systemctl start php-fpm
        systemctl start php${mphp_ver}-fpm
        sed -i "s@${php_install_dir}/bin:@@" /etc/profile
      fi
    fi
  else
    # 没有 php-fpm 就没法并存版本。
    # 等于告诉用户「装好了」而实际什么都没装
    echo "${CFAILURE}--mphp_ver 需要当前 PHP 带 php-fpm（mod_php 模式下没有），并存版本未安装。${CEND}"
    echo "${CWARNING}请先 ./uninstall.sh --php --phpcache 后用 php-fpm 模式重装 PHP，再加 --mphp_ver${CEND}"
    exit 1
  fi
}
