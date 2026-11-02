#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

# PHP 7.4 起都能直接吃系统的 OpenSSL 3.x：
#   - 7.4 的源码包由本仓库自行构建，已经带了 OpenSSL 3.x 的编译兼容修复
#   - 8.x 原生支持
# Debian 12 / 13 的系统 OpenSSL 都是 3.x，所以这里不再需要按版本分支，
# 也不再自建 /usr/local/openssl。上游那段 1.0.2 / 1.1 / 3.x 的矩阵已整体删除
# （它还会给 7.4 拼出 --with-openssl-dir，PHP 7.4 根本不认这个参数）。
php74_with_openssl="--with-openssl"
php80_with_openssl="--with-openssl"
php81_with_openssl="--with-openssl"
php82_with_openssl="--with-openssl"
php83_with_openssl="--with-openssl"
php84_with_openssl="--with-openssl"
php85_with_openssl="--with-openssl"

php74_with_ssl="--with-ssl"
php80_with_ssl="--with-ssl"
php81_with_ssl="--with-ssl"
php82_with_ssl="--with-ssl"
php83_with_ssl="--with-ssl"
php84_with_ssl="--with-ssl"
php85_with_ssl="--with-ssl"

php74_with_curl="--with-curl"
php80_with_curl="--with-curl"
php81_with_curl="--with-curl"
php82_with_curl="--with-curl"
php83_with_curl="--with-curl"
php84_with_curl="--with-curl"
php85_with_curl="--with-curl"
