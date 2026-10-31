#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

export LANG=en_US.UTF-8
export LANGUAGE=en_US:en
# free 依赖 procps，最小化系统在装依赖之前可能还没有，回退到 /proc/meminfo
Mem=$(free -m 2>/dev/null | awk '/Mem:/{print $2}')
Swap=$(free -m 2>/dev/null | awk '/Swap:/{print $2}')
if [ -z "${Mem}" ]; then
  Mem=$(( $(awk '/^MemTotal:/{print $2}' /proc/meminfo) / 1024 ))
  [ -z "${Swap}" ] && Swap=$(( $(awk '/^SwapTotal:/{print $2}' /proc/meminfo) / 1024 ))
fi
Mem=${Mem:-512}; Swap=${Swap:-0}

if [ $Mem -le 640 ]; then
  Mem_level=512M
  Memory_limit=64
  THREAD=1
elif [ $Mem -gt 640 -a $Mem -le 1280 ]; then
  Mem_level=1G
  Memory_limit=128
elif [ $Mem -gt 1280 -a $Mem -le 2500 ]; then
  Mem_level=2G
  Memory_limit=192
elif [ $Mem -gt 2500 -a $Mem -le 3500 ]; then
  Mem_level=3G
  Memory_limit=256
elif [ $Mem -gt 3500 -a $Mem -le 4500 ]; then
  Mem_level=4G
  Memory_limit=320
elif [ $Mem -gt 4500 -a $Mem -le 8000 ]; then
  Mem_level=6G
  Memory_limit=384
elif [ $Mem -gt 8000 ]; then
  Mem_level=8G
  Memory_limit=448
fi

# add swapfile
if [ ! -e ~/.lemon ] && [ "${Swap}" == '0' ] && [ ${Mem} -le 2048 ]; then
  echo "${CWARNING}Add Swap file, It may take a few minutes... ${CEND}"
  dd if=/dev/zero of=/swapfile count=2048 bs=1M
  mkswap /swapfile
  swapon /swapfile
  chmod 600 /swapfile
  [ -z "`grep swapfile /etc/fstab`" ] && echo '/swapfile    swap    swap    defaults    0 0' >> /etc/fstab
fi
