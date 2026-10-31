#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

Upgrade_phpMyAdmin() {
  pushd ${lemon_dir}/src > /dev/null
  [ ! -e "${wwwroot_dir}/default/phpMyAdmin" ] && echo "${CWARNING}phpMyAdmin is not installed on your system! ${CEND}" && exit 1
  OLD_phpmyadmin_ver=`grep Version ${wwwroot_dir}/default/phpMyAdmin/README | awk '{print $2}'`
  # 页面结构是 <a href="/files/5.2.3/">5.2.3</a>：直接抓 /files/<版本>/ 片段最稳。
  # 原来用 awk -F'>|<' '{print $5}'，在当前 HTML 下恒为空，守卫会无条件 exit 1（真机复现）。
  Latest_phpmyadmin_ver=`curl --connect-timeout 2 -m 5 -s https://www.phpmyadmin.net/files/ | grep -oE '/files/[0-9]+\.[0-9]+(\.[0-9]+)?/' | sed 's@/files/@@; s@/$@@' | sort -V | tail -1`
  # 版本抓取失败不再退回写死的旧版本（5.0.4 太老，phpMyAdmin 不支持原地降级），直接报错退出
  if [ -z "${Latest_phpmyadmin_ver}" ]; then
    echo "${CFAILURE}取不到 phpMyAdmin 最新版本号（请检查网络），可运行 ./upgrade.sh --phpmyadmin <版本号> 手动指定后重试${CEND}"
    exit 1
  fi
  echo "Current phpMyAdmin Version: ${CMSG}${OLD_phpmyadmin_ver}${CEND}"
  while :; do echo
    [ "${phpmyadmin_flag}" != 'y' ] && read -e -p "Please input upgrade phpMyAdmin Version(default: ${Latest_phpmyadmin_ver}): " NEW_phpmyadmin_ver
    NEW_phpmyadmin_ver=${NEW_phpmyadmin_ver:-${Latest_phpmyadmin_ver}}
    if [ "${NEW_phpmyadmin_ver}" != "${OLD_phpmyadmin_ver}" ]; then
      [ ! -e "phpMyAdmin-${NEW_phpmyadmin_ver}-all-languages.tar.gz" ] && wget -c https://files.phpmyadmin.net/phpMyAdmin/${NEW_phpmyadmin_ver}/phpMyAdmin-${NEW_phpmyadmin_ver}-all-languages.tar.gz > /dev/null 2>&1
      if [ -e "phpMyAdmin-${NEW_phpmyadmin_ver}-all-languages.tar.gz" ]; then
        echo "Download [${CMSG}phpMyAdmin-${NEW_phpmyadmin_ver}-all-languages.tar.gz${CEND}] successfully! "
        break
      else
        echo "${CWARNING}phpMyAdmin version does not exist! ${CEND}"
        [ "${phpmyadmin_flag}" == 'y' ] && exit 1
      fi
    else
      echo "${CWARNING}input error! Upgrade phpMyAdmin version is the same as the old version${CEND}"
      exit
    fi
  done

  if [ -e "phpMyAdmin-${NEW_phpmyadmin_ver}-all-languages.tar.gz" ]; then
    echo "[${CMSG}phpMyAdmin-${NEW_phpmyadmin_ver}-all-languages.tar.gz${CEND}] found"
    if [ "${phpmyadmin_flag}" != 'y' ]; then
      echo "Press Ctrl+c to cancel or Press any key to continue..."
      char=`get_char`
    fi
    tar xzf phpMyAdmin-${NEW_phpmyadmin_ver}-all-languages.tar.gz
    rm -rf ${wwwroot_dir}/default/phpMyAdmin
    /bin/mv phpMyAdmin-${NEW_phpmyadmin_ver}-all-languages ${wwwroot_dir}/default/phpMyAdmin
    /bin/cp ${wwwroot_dir}/default/phpMyAdmin/{config.sample.inc.php,config.inc.php}
    mkdir ${wwwroot_dir}/default/phpMyAdmin/{upload,save}
    sed -i "s@UploadDir.*@UploadDir'\] = 'upload';@" ${wwwroot_dir}/default/phpMyAdmin/config.inc.php
    sed -i "s@SaveDir.*@SaveDir'\] = 'save';@" ${wwwroot_dir}/default/phpMyAdmin/config.inc.php
    sed -i "s@host'\].*@host'\] = '127.0.0.1';@" ${wwwroot_dir}/default/phpMyAdmin/config.inc.php
    sed -i "s@blowfish_secret.*;@blowfish_secret\'\] = \'$(cat /dev/urandom | head -1 | base64 | head -c 45)\';@" ${wwwroot_dir}/default/phpMyAdmin/config.inc.php
    chown -R ${run_user}:${run_group} ${wwwroot_dir}/default/phpMyAdmin
    echo "You have ${CMSG}successfully${CEND} upgrade from ${CWARNING}$OLD_phpmyadmin_ver${CEND} to ${CWARNING}$NEW_phpmyadmin_ver${CEND}"
  fi
  popd > /dev/null
}
