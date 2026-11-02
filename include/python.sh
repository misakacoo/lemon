#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon
#
# 这里原来叫「Python3.6」，实际是源码编译 versions.txt 里的 3.13 到 /usr/local/python。
# 它当初的用处是给源码安装的 fail2ban 提供独立运行时；fail2ban 改成 Debian 官方包
# 之后（自带 python3 依赖），这个自建 Python 就没有任何消费者了 —— 全仓只有它自己
# 引用 python_install_dir，而 Debian 12 / 13 分别自带 3.11 / 3.13，版本并不落后。
# 继续保留等于在 Debian 13 上把系统自带的同一个版本再编一遍（十几分钟、450MB），
# 所以移除安装，只留下清理逻辑，供已经装过的机器卸载。

Uninstall_Python() {
  addon_uninstall_guard python "Python" ${python_install_dir}/bin/python || return 0
  if [ -e "${python_install_dir}/bin/python" ]; then
    rm -rf ${python_install_dir}
    clear_addon_mark python
    echo "${CMSG}Python uninstall completed${CEND}"
  fi
}
