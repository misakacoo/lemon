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
          Install_PHP74 2>&1 | tee -a ${lemon_dir}/install.log
          ;;
        80)
          . include/php-8.0.sh
          Install_PHP80 2>&1 | tee -a ${lemon_dir}/install.log
          ;;
        81)
          . include/php-8.1.sh
          Install_PHP81 2>&1 | tee -a ${lemon_dir}/install.log
          ;;
        82)
          . include/php-8.2.sh
          Install_PHP82 2>&1 | tee -a ${lemon_dir}/install.log
          ;;
        83)
          . include/php-8.3.sh
          Install_PHP83 2>&1 | tee -a ${lemon_dir}/install.log
          ;;
        84)
          . include/php-8.4.sh
          Install_PHP84 2>&1 | tee -a ${lemon_dir}/install.log
          ;;
        85)
          . include/php-8.5.sh
          Install_PHP85 2>&1 | tee -a ${lemon_dir}/install.log
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
    # 没有 php-fpm 就没法并存版本。原来只打一句提示就继续跑完整个安装并打印 Congratulations，
    # 等于告诉用户「装好了」而实际什么都没装（真机 d13 就是这样，/usr/local/php74 根本不存在）。
    echo "${CFAILURE}--mphp_ver 需要当前 PHP 带 php-fpm（mod_php 模式下没有），并存版本未安装。${CEND}"
    echo "${CWARNING}请先 ./uninstall.sh --php --phpcache 后用 php-fpm 模式重装 PHP，再加 --mphp_ver${CEND}"
    exit 1
  fi
}
