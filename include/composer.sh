#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

# 为什么不用 apt 的 composer：
#   1) 版本差得多 —— Debian 12 只有 2.5.5，Debian 13 是 2.8.8，而上游 phar 一直是 2.8.x。
#      composer 的版本直接影响依赖解析行为，差一条小版本线就可能装不上某些包。
#   2) apt 的 composer 依赖 php-cli，会把整套 php8.2/8.4 命令行运行时拉进来（31 个包），
#      和 Lemon 自己装在 /usr/local/php 的 PHP 重复。
#   所以维持「下载官方 phar 到 /usr/local/bin/composer」，用 Lemon 自己的 PHP 跑。

Install_composer() {
  if [ -e "${php_install_dir}/bin/phpize" ]; then
    if [ -e "/usr/local/bin/composer" ]; then
      echo "${CWARNING}PHP Composer already installed! ${CEND}"
    else
      pushd ${lemon_dir}/src > /dev/null
      # 官方 phar（镜像站不托管这个文件）。不再按出口 IP 切到阿里云镜像，
      # 更不要写 repo.packagist = packagist.phpcomposer.com —— 那个域名早已停服，
      # 配上去会让 composer 直接不可用。
      # 先下到 src 目录做完三重校验（非空 / sha256 / 试运行），全部通过才放到 /usr/local/bin
      wget -c https://getcomposer.org/composer.phar -O composer.phar > /dev/null 2>&1
      if [ -s composer.phar ]; then
        # sha256 校验：官方随 phar 发布 .sha256sum；校验文件取不到（网络问题）时打警告跳过，不阻断
        expect_sum=$(curl --connect-timeout 3 -m 10 -fsS https://getcomposer.org/download/latest-stable/composer.phar.sha256sum 2>/dev/null | awk '{print $1}')
        if [ -n "${expect_sum}" ]; then
          if [ "$(sha256sum composer.phar | awk '{print $1}')" != "${expect_sum}" ]; then
            rm -f composer.phar
            echo; echo "${CFAILURE}PHP Composer sha256 校验失败，已删除下载文件，Please try again! ${CEND}"
            popd > /dev/null
            exit 1
          fi
        else
          echo "${CWARNING}取不到 composer.phar.sha256sum，跳过 sha256 校验 ${CEND}"
        fi
        # 试运行：phar 被截断或损坏时 sha256 之外再兜一层
        if ! ${php_install_dir}/bin/php composer.phar --version > /dev/null 2>&1; then
          rm -f composer.phar
          echo; echo "${CFAILURE}PHP Composer phar 无法运行，已删除下载文件，Please try again! ${CEND}"
          popd > /dev/null
          exit 1
        fi
        /bin/mv composer.phar /usr/local/bin/composer
        chmod +x /usr/local/bin/composer
      else
        rm -f composer.phar
      fi
      if [ -e "/usr/local/bin/composer" ]; then
        mark_addon_installed composer
        echo; echo "${CSUCCESS}PHP Composer installed successfully! ${CEND}"
      else
        echo; echo "${CFAILURE}PHP Composer install failed, Please try again! ${CEND}"
      fi
      popd > /dev/null
    fi
  fi
}

Uninstall_composer() {
  addon_uninstall_guard composer "Composer" /usr/local/bin/composer || return 0
  if [ -e "/usr/local/bin/composer" ]; then
    rm -f /usr/local/bin/composer
    clear_addon_mark composer
    echo; echo "${CMSG}Composer uninstall completed${CEND}";
  else
    echo; echo "${CWARNING}Composer does not exist! ${CEND}"
  fi
}
