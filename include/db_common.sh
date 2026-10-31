#!/bin/bash
# Author:  yeho <lj2007331 AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

# 把密码转义成能安全放进 SQL 单引号字符串里的形式。
# MySQL / MariaDB / Percona 都按 反斜杠 转义：\ -> \\，' -> \'
# 用法：mysql -e "alter user root@'localhost' identified by '$(esc_sql "${dbrootpwd}")';"
# 密码以变量形式传入，变量内容不会被二次展开，所以里面的 $(...) 或反引号不会被执行。
esc_sql() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\'/\\\'}
  printf '%s' "$s"
}

# 把值转义成可以放进 options.conf 单引号字符串里的形式（bash 语法）
conf_escape() {
  local s=$1
  s=${s//\'/\'\\\'\'}
  printf '%s' "$s"
}

# 安全改写 options.conf 里的某个变量，避免 sed 的 & / + / 引号被当成元字符。
# 改完统一收紧到 600，因为里面有数据库密码。
set_conf_var() {
  local key=$1 val=$2 file=$3 line tmp
  [ -f "${file}" ] || return 1
  line="${key}='$(conf_escape "${val}")'"
  tmp=$(mktemp "${file}.XXXXXX") || return 1
  LINE="${line}" awk -v k="${key}" '
    BEGIN { line = ENVIRON["LINE"]; done = 0 }
    index($0, k"=") == 1 { print line; done = 1; next }
    { print }
    END { if (!done) print line }
  ' "${file}" > "${tmp}" && cat "${tmp}" > "${file}"
  rm -f "${tmp}"
  chmod 600 "${file}" 2>/dev/null
}
