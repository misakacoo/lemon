#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

# PHP 的 intl 扩展是 C++ 写的，8.0 及更早的版本固定用 -std=c++11 编译，
# 而 ICU 75 起的头文件用到了 std::u16string_view / std::is_convertible_v，
# 这些要 C++17。在 Debian 13（ICU 76）这类系统上会报几十个
# "is_convertible_v is not a member of std" 然后中断。
#
# 判断以实际安装的 ICU 版本为准：configure 之后调用，把 Makefile 里的
# C++ 标准换掉。老系统（ICU < 75）什么都不做。
fix_php_intl_cxx_std() {
  local icu_major
  icu_major=$(pkg-config --modversion icu-i18n 2>/dev/null | cut -d. -f1)
  [ -n "${icu_major}" ] || return 0
  [ "${icu_major}" -ge 75 ] 2>/dev/null || return 0
  [ -f Makefile ] || return 0
  grep -q -- '-std=c++11' Makefile || return 0
  sed -i 's/-std=c++11/-std=c++17/g' Makefile
  echo "${CMSG}ICU ${icu_major} 要求 C++17，已将 PHP 的 intl 编译标准调整为 c++17${CEND}"
}

# gcc 14 起把 incompatible-pointer-types、implicit-function-declaration 这类警告
# 默认当成错误。PHP 7.4 的 ext/iconv 里 iconv(cd, (const char **) &in_p, ...)
# 与系统 libiconv 的 char ** 原型不一致，在 Debian 13 上直接编译失败。
# 这两类差异只在类型层面，ABI 不变，降级回警告即可。
# configure 之前调用（CFLAGS 要在 configure 时生效）。
fix_php_gcc14_flags() {
  [ "${gcc_ver:-0}" -ge 14 ] 2>/dev/null || return 0
  case " ${CFLAGS} " in
    *-Wno-error=incompatible-pointer-types*) return 0 ;;
  esac
  export CFLAGS="${CFLAGS} -Wno-error=incompatible-pointer-types -Wno-error=implicit-function-declaration"
}
