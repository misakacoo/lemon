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
[ $(id -u) != '0' ] && { echo "${CFAILURE}Error: You must be root to run this script${CEND}"; exit 1; }

lemon_dir=$(dirname "`readlink -f $0`")
pushd ${lemon_dir} > /dev/null
[ -f ./options.conf ] || { cp -f ./options.conf.example ./options.conf 2>/dev/null && chmod 600 ./options.conf 2>/dev/null; }
. ./options.conf
. ./include/color.sh
. ./include/check_dir.sh
. ./include/check_os.sh
. ./include/get_char.sh
. ./include/openssl.sh

Show_Help() {
  echo
  echo "Usage: $0  command ...[parameters]....
  --help, -h                  Show this help message
  --quiet, -q                 quiet operation
  --list, -l                  List Virtualhost
  --mphp_ver [74~85]          Use another PHP version (PATH: /usr/local/php${mphp_ver})
  --proxy                     Use proxy
  --add                       Add Virtualhost
  --delete, --del             Delete Virtualhost
  --dir <path>                Virtual host root directory (skip the interactive prompt)
  --httponly                  Use HTTP Only
  --selfsigned                Generate a self-signed SSL Certificate and Key on the fly
  --letsencrypt               Auto-issue a trusted cert via acme.sh (default CA: ZeroSSL)
  --zerossl                   Same as --letsencrypt (ZeroSSL is the default CA)
  --le                        Force Let's Encrypt as the CA
  --dnsapi                    Use dns API to automatically issue Let's Encrypt Cert
  "
}

ARG_NUM=$#
# 没有终端还走交互菜单会卡在 read 上无限循环，直接提示带参数运行
if [ "${ARG_NUM}" == '0' ] && [ ! -t 0 ]; then
  echo "非交互环境：请带上参数运行，$0 --help 查看可用参数"
  exit 1
fi
TEMP=`getopt -o hql --long help,quiet,list,proxy,mphp_ver:,add,delete,del,dir:,httponly,selfsigned,letsencrypt,zerossl,le,dnsapi -- "$@" 2>/dev/null`
[ $? != 0 ] && echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
eval set -- "${TEMP}"
while :; do
  [ -z "$1" ] && break;
  case "$1" in
    -h|--help)
      Show_Help; exit 0
      ;;
    -q|--quiet)
      quiet_flag=y; shift 1
      ;;
    -l|--list)
      list_flag=y; shift 1
      ;;
    --mphp_ver)
      mphp_ver=$2; mphp_flag=y; shift 2
      [[ ! "${mphp_ver}" =~ ^74$|^8[0-5]$ ]] && { echo "${CWARNING}mphp_ver input error! Please only input number 74~85${CEND}"; unset mphp_ver mphp_flag; }
      ;;
    --proxy)
      proxy_flag=y; shift 1
      ;;
    --add)
      add_flag=y; shift 1
      ;;
    --delete|--del)
      delete_flag=y; shift 1
      ;;
    --httponly)
      sslquiet_flag=y
      httponly_flag=y
      Domian_Mode=1
      shift 1
      ;;
    --selfsigned)
      sslquiet_flag=y
      selfsigned_flag=y
      Domian_Mode=2
      shift 1
      ;;
    --letsencrypt|--zerossl)
      # 默认 CA 是 ZeroSSL：Let's Encrypt 对同一组域名硬限流 168h/5 张，反复建站极易撞 429；
      # ZeroSSL 走 EAB 自动注册，实测宽松得多。
      sslquiet_flag=y
      letsencrypt_flag=y
      acme_ca=${acme_ca:-zerossl}
      Domian_Mode=3
      shift 1
      ;;
    --le)
      sslquiet_flag=y
      letsencrypt_flag=y
      acme_ca=letsencrypt
      Domian_Mode=3
      shift 1
      ;;
    --dir)
      vhostdir=$2
      shift 2
      ;;
    --dnsapi)
      sslquiet_flag=y
      dnsapi_flag=y
      letsencrypt_flag=y
      shift 1
      ;;
    --)
      shift
      # `--` 之后的位置参数当域名用：getopt 会把 `--add sample.com` /
      # `--letsencrypt sample.com` 里的域名放到 `--` 后面，原来这里直接落进
      # 下面的 *) 分支报 unknown argument（README 里那两条用法其实一直不能用）。
      [ -n "${1}" ] && { ARG_DOMAIN="${1}"; shift; }
      ;;
    *)
      echo "${CWARNING}ERROR: unknown argument! ${CEND}" && Show_Help && exit 1
      ;;
  esac
done

# 删除站点目录前的兜底：只允许删 ${wwwroot_dir} 下面的路径。
# Directory 是从 vhost 配置里 parse 出来的（root / <Directory / caddy root），
# 路径含空格时会被 awk/sed 切碎，直接 rm -rf 一个残缺路径可能删到别的东西。
Safe_Rm_Dir() {
  local d="$1" real root
  if [ -z "${d}" ]; then
    echo "${CWARNING}目录为空，跳过删除${CEND}"
    return 1
  fi
  # 必须先规范化再比前缀：只比字符串的话 "$wwwroot_dir/../../tmp/x" 也能过，
  # 真机审计已实测把 wwwroot 之外的目录删掉。符号链接同样拒绝（可指向别处）。
  if [ -L "${d}" ]; then
    echo "${CWARNING}${d} 是符号链接，拒绝删除${CEND}"
    return 1
  fi
  real=$(realpath -m -- "${d}" 2>/dev/null) || return 1
  root=$(realpath -m -- "${wwwroot_dir}" 2>/dev/null) || return 1
  case "${real}" in
    "${root}"/?*) ;;
    *)
      echo "${CWARNING}${real} 不在 ${root} 下，拒绝删除（避免误删系统目录）${CEND}"
      return 1
      ;;
  esac
  [ -d "${real}" ] && rm -rf -- "${real}"
}

Choose_ENV() {
  if [ -e "${apache_install_dir}/bin/apachectl" ];then
    [ "$(${apache_install_dir}/bin/apachectl -v | awk -F'.' /version/'{print $2}')" == '4' ] && { Apache_main_ver=24; Apache_grant='Require all granted'; }
    [ "$(${apache_install_dir}/bin/apachectl -v | awk -F'.' /version/'{print $2}')" == '2' ] && Apache_main_ver=22
  fi
  # Tomcat 已从项目移除：环境只有「有 PHP」和「没有 PHP」两种
  NGX_FLAG=php
  if [ -e "${php_install_dir}/bin/phpize" ]; then
    Number=10
  else
    Number=00
    NGX_FLAG=php
  fi
}

Create_SSL() {
  if [ "${Domian_Mode}" == '2' ]; then
    printf "
You are about to be asked to enter information that will be incorporated
into your certificate request.
What you are about to enter is what is called a Distinguished Name or a DN.
There are quite a few fields but you can leave some blank
For some fields there will be a default value,
If you enter '.', the field will be left blank.
"
    echo
    read -e -p "Country Name (2 letter code) [CN]: " SELFSIGNEDSSL_C \
      || die_eof
    SELFSIGNEDSSL_C=${SELFSIGNEDSSL_C:-CN}
    # shellcheck disable=SC2104
    [ ${#SELFSIGNEDSSL_C} != 2 ] && { echo "${CWARNING}input error, You must input 2 letter code country name${CEND}"; return 1; }
    echo
    read -e -p "State or Province Name (full name) [Shanghai]: " SELFSIGNEDSSL_ST \
      || die_eof
    SELFSIGNEDSSL_ST=${SELFSIGNEDSSL_ST:-Shanghai}
    echo
    read -e -p "Locality Name (eg, city) [Shanghai]: " SELFSIGNEDSSL_L \
      || die_eof
    SELFSIGNEDSSL_L=${SELFSIGNEDSSL_L:-Shanghai}
    echo
    read -e -p "Organization Name (eg, company) [Example Inc.]: " SELFSIGNEDSSL_O \
      || die_eof
    SELFSIGNEDSSL_O=${SELFSIGNEDSSL_O:-"Example Inc."}
    echo
    read -e -p "Organizational Unit Name (eg, section) [IT Dept.]: " SELFSIGNEDSSL_OU \
      || die_eof
    SELFSIGNEDSSL_OU=${SELFSIGNEDSSL_OU:-"IT Dept."}

    openssl req -utf8 -new -newkey rsa:2048 -sha256 -nodes -out ${PATH_SSL}/${domain}.csr -keyout ${PATH_SSL}/${domain}.key -subj "/C=${SELFSIGNEDSSL_C}/ST=${SELFSIGNEDSSL_ST}/L=${SELFSIGNEDSSL_L}/O=${SELFSIGNEDSSL_O}/OU=${SELFSIGNEDSSL_OU}/CN=${domain}" > /dev/null 2>&1
    openssl x509 -req -days 36500 -sha256 -in ${PATH_SSL}/${domain}.csr -signkey ${PATH_SSL}/${domain}.key -out ${PATH_SSL}/${domain}.crt > /dev/null 2>&1
  elif [ "${Domian_Mode}" == '3' -o "${dnsapi_flag}" == 'y' ]; then
      while :; do echo
        echo 'Please select domain cert key length.'
        echo "${CMSG}Enter one of 2048, 3072, 4096, 8192 will issue a RSA cert.${CEND}"
        echo "${CMSG}Enter one of ec-256, ec-384, ec-521 will issue a ECC cert.${CEND}"
        echo
        read -e -p "Please enter your cert key length (default 2048): " CERT_KEYLENGTH \
          || die_eof
        if [ "${CERT_KEYLENGTH}" == "" ]; then
          CERT_KEYLENGTH="2048"
          break
        elif [[ "${CERT_KEYLENGTH}" =~ ^2048$|^3072$|^4096$|^8192$|^ec-256$|^ec-384$|^ec-521$ ]]; then
          break
        else
          echo "${CWARNING}input error!${CEND}"
        fi
      done
  if [ "${Domian_Mode}" == '3' -o "${dnsapi_flag}" == 'y' ] && [ ! -e ~/.acme.sh/acme.sh ]; then
    pushd ${lemon_dir}/src > /dev/null
    [ ! -e acme.sh-master.tar.gz ] && wget -qc ${mirror_link}/src/acme.sh-master.tar.gz
    tar xzf acme.sh-master.tar.gz
    pushd acme.sh-master > /dev/null
    ./acme.sh --install > /dev/null 2>&1
    popd > /dev/null
    # 源码树安装完就没用了（tar 包留作缓存）
    rm -rf acme.sh-master
    popd > /dev/null
    acme_ca=${acme_ca:-zerossl}
    ~/.acme.sh/acme.sh --set-default-ca --server "${acme_ca}" > /dev/null 2>&1
    if [ "${acme_ca}" == 'zerossl' ]; then
      # ZeroSSL 需要先注册账号（acme.sh 会自动取 EAB），用 admin@<域名> 兜底
      ~/.acme.sh/acme.sh --register-account -m "admin@${domain}" > /dev/null 2>&1
    fi
  fi
  [ -e ~/.acme.sh/account.conf ] && sed -i '/^CERT_HOME=/d' ~/.acme.sh/account.conf
    if [ "${moredomain}" == "*.${domain}" -o "${dnsapi_flag}" == 'y' ]; then
      while :; do echo
        echo 'Please select DNS provider:'
        echo "${CMSG}dp${CEND},${CMSG}cx${CEND},${CMSG}ali${CEND},${CMSG}cf${CEND},${CMSG}aws${CEND},${CMSG}linode${CEND},${CMSG}he${CEND},${CMSG}namesilo${CEND},${CMSG}dgon${CEND},${CMSG}freedns${CEND},${CMSG}gd${CEND},${CMSG}namecom${CEND} and so on."
        echo "${CMSG}More: https://github.com/misakacoo/lemon"
        read -e -p "Please enter your DNS provider: " DNS_PRO \
          || die_eof
        if [ -e ~/.acme.sh/dnsapi/dns_${DNS_PRO}.sh ]; then
          break
        else
          echo "${CWARNING}You DNS api mode is not supported${CEND}"
        fi
      done
      while :; do echo
        echo "Syntax: export Key1=Value1 ; export Key2=Value1"
        read -e -p "Please enter your dnsapi parameters: " DNS_PAR \
          || die_eof
        echo
        # 以前这里直接 eval ${DNS_PAR}：输入什么就执行什么（打成 export A=1; rm -rf / 也会照做），
        # 等于把用户输入交给 shell 解析器。现在只接受 KEY=VALUE / export KEY=VALUE，
        # 变量名过白名单后直接 export，不再经过 eval。
        _dns_ok=1
        for _kv in ${DNS_PAR}; do
          [ "${_kv}" = "export" ] && continue
          case "${_kv}" in
            [A-Za-z_]*=*)
              # 原来写成 ${_kv%%%%=*}（多转义），变量名会原样带上 "Ali_Key=xxx"
              # → 白名单校验必失败 → _dns_ok 永远 0 → --dnsapi 死循环（静态审计 #3）
              _k=${_kv%%=*}
              _v=${_kv#*=}
              if [[ "${_k}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
                export "${_k}=${_v}"
              else
                _dns_ok=0
                echo "${CWARNING}变量名不合法：${_k}${CEND}"
              fi
              ;;
            *)
              _dns_ok=0
              echo "${CWARNING}只接受 KEY=VALUE（可用空格分隔多个，例如：export Ali_Key=xx Ali_Secret=yy）${CEND}"
              ;;
          esac
        done
        if [ "${_dns_ok}" == '1' ]; then
          break
        fi
      done
      [ "${moredomainame_flag}" == 'y' ] && moredomainame_D="$(for D in ${moredomainame}; do echo -d ${D}; done)"
      ~/.acme.sh/acme.sh --force --issue -k ${CERT_KEYLENGTH} --dns dns_${DNS_PRO} -d ${domain} ${moredomainame_D}
    else
      if [ "${nginx_ssl_flag}" == 'y' ]; then
        [ ! -d ${web_install_dir}/conf/vhost ] && mkdir ${web_install_dir}/conf/vhost
        if [ -n "`ifconfig | grep inet6`" ]; then
          echo "server {  listen 80;  listen [::]:80;  server_name ${domain}${moredomainame};  root ${vhostdir};  access_log off; }" > ${web_install_dir}/conf/vhost/${domain}.conf
        else
          echo "server {  listen 80;  server_name ${domain}${moredomainame};  root ${vhostdir};  access_log off; }" > ${web_install_dir}/conf/vhost/${domain}.conf
        fi
        ${web_install_dir}/sbin/nginx -s reload
      fi
      if [ "${caddy_ssl_flag}" == 'y' ]; then
        [ ! -d ${caddy_install_dir}/conf/vhost ] && mkdir -p ${caddy_install_dir}/conf/vhost
        # 同上：地址要逗号分隔 + 显式 http://，否则 Caddy 会自动申请证书并跳 HTTPS
        caddy_site_addrs=''
        for one_domain in ${domain} ${moredomainame}; do
          caddy_site_addrs="${caddy_site_addrs}http://${one_domain}, "
        done
        caddy_site_addrs=${caddy_site_addrs%, }
        cat > ${caddy_install_dir}/conf/vhost/${domain}.conf << EOF
${caddy_site_addrs} {
  root * ${vhostdir}
  file_server
}
EOF
        Reload_Caddy
      fi
      if [ "${apache_ssl_flag}" == 'y' ]; then
        [ ! -d ${apache_install_dir}/conf/vhost ] && mkdir ${apache_install_dir}/conf/vhost
        cat > ${apache_install_dir}/conf/vhost/${domain}.conf << EOF
<VirtualHost *:80>
  ServerAdmin admin@example.com
  DocumentRoot "${vhostdir}"
  ServerName ${domain}
  ${Apache_Domain_alias}
<Directory "${vhostdir}">
  SetOutputFilter DEFLATE
  Options FollowSymLinks ExecCGI
  ${Apache_grant}
  AllowOverride All
  Order allow,deny
  Allow from all
  DirectoryIndex index.html index.php
</Directory>
</VirtualHost>
EOF
        ${apache_install_dir}/bin/apachectl -k graceful
      fi
      # 临时 HTTP vhost 刚写完，先 reload 再自检；不 reload 时 curl 打到默认站点，
      # 必然取不到 challenge 文件，于是把「没 reload」误报成 NXDOMAIN（真机踩到）。
      if [ -e "${web_install_dir}/sbin/nginx" ]; then
        ${web_install_dir}/sbin/nginx -t > /dev/null 2>&1 && ${web_install_dir}/sbin/nginx -s reload > /dev/null 2>&1
      fi
      [ -e "${apache_install_dir}/bin/httpd" ] && ${apache_install_dir}/bin/apachectl -k graceful > /dev/null 2>&1
      sleep 1
      auth_file="`< /dev/urandom tr -dc A-Za-z0-9 | head -c8`".html
      auth_str='lemon'; echo ${auth_str} > ${vhostdir}/${auth_file}
      for D in ${domain} ${moredomainame}
      do
        curl_str=`curl --connect-timeout 30 -4 -s $D/${auth_file} 2>&1`
        [ "${curl_str}" != "${auth_str}" ] && { echo; echo "${CWARNING}自检提示：http://$D/${auth_file} 没取到预期内容（DNS 未生效或 80 不通），仍会继续签发${CEND}"; }
      done
      rm -f ${vhostdir}/${auth_file}
      [ "${moredomainame_flag}" == 'y' ] && moredomainame_D="$(for D in ${moredomainame}; do echo -d ${D}; done)"
      # 已有有效证书就别再 --force --issue：Let's Encrypt 对同一组域名限制「168 小时 5 张」，
      # 反复建站/重跑会把配额烧光（真机实测撞 429 too many certificates），而且完全没必要。
      _reuse_cert='n'
      if [ -s ~/.acme.sh/${domain}/fullchain.cer ]; then
        _end=`openssl x509 -in ~/.acme.sh/${domain}/fullchain.cer -noout -enddate 2>/dev/null | cut -d= -f2`
        if [ -n "${_end}" ]; then
          _left=$(( ( $(date -d "${_end}" +%s 2>/dev/null || echo 0) - $(date +%s) ) / 86400 ))
          [ "${_left}" -gt 30 ] && _reuse_cert='y'
        fi
      fi
      if [ "${_reuse_cert}" == 'y' ]; then
        echo "${CSUCCESS}已有有效期 ${_left} 天的证书，跳过签发（不消耗 Let's Encrypt 配额）${CEND}"
      else
        # 签发前再确认一次 CA：acme.sh 的默认 CA 可能被别的脚本/上次安装改成 LE，
      # 而 ZeroSSL 需要账号已注册（EAB）。
      acme_ca=${acme_ca:-zerossl}
      ~/.acme.sh/acme.sh --set-default-ca --server "${acme_ca}" > /dev/null 2>&1
      if [ "${acme_ca}" == 'zerossl' ]; then
        ~/.acme.sh/acme.sh --register-account -m "admin@${domain}" > /dev/null 2>&1
      fi
      ~/.acme.sh/acme.sh --force --issue -k ${CERT_KEYLENGTH} -w ${vhostdir} -d ${domain} ${moredomainame_D}
      fi
    fi
      [ -e "${PATH_SSL}/${domain}.crt" ] && rm -f ${PATH_SSL}/${domain}.{crt,key}
      Nginx_cmd="/bin/systemctl restart nginx"
      Apache_cmd="${apache_install_dir}/bin/apachectl -k graceful"
      [ -e /usr/bin/systemctl ] && Caddy_cmd="systemctl reload caddy" || Caddy_cmd="service caddy reload"
      if [ -e "${web_install_dir}/sbin/nginx" -a -e "${apache_install_dir}/bin/httpd" ]; then
        Command="${Nginx_cmd};${Apache_cmd}"
      elif [ -e "${web_install_dir}/sbin/nginx" -a ! -e "${apache_install_dir}/bin/httpd" ]; then
        Command="${Nginx_cmd}"
      elif [ ! -e "${web_install_dir}/sbin/nginx" -a -e "${apache_install_dir}/bin/httpd" ]; then
        Command="${Apache_cmd}"
      elif [ -e "${caddy_install_dir}/bin/caddy" ]; then
        Command="${Caddy_cmd}"
      fi
    # 按“哪个目录真有 fullchain.cer”决定要不要 --ecc，而不是看 CERT_KEYLENGTH：
    # CA 可能按自己的默认值签发（ZeroSSL 默认 ec-256），两者不一致时原来会 cat 到不存在的
    # RSA 目录 → 写出 0 字节证书 → nginx 起不来（真机踩到）。
    if [ -s ~/.acme.sh/${domain}/fullchain.cer ]; then
      ~/.acme.sh/acme.sh --force --install-cert -d ${domain} --fullchain-file ${PATH_SSL}/${domain}.crt --key-file ${PATH_SSL}/${domain}.key --reloadcmd "${Command}" > /dev/null
    elif [ -s ~/.acme.sh/${domain}_ecc/fullchain.cer ]; then
      ~/.acme.sh/acme.sh --force --install-cert --ecc -d ${domain} --fullchain-file ${PATH_SSL}/${domain}.crt --key-file ${PATH_SSL}/${domain}.key --reloadcmd "${Command}" > /dev/null
    else
      # 证书失败（限流 / DNS 未生效 / 80 不通）不应该把站点一起删掉再 exit：
      # 用户拿到的应该是「站点能跑（HTTP）、证书待补」，而不是什么都没有（真机：LE 限流时站点 conf 被删光）。
      echo "${CFAILURE}证书签发失败（CA: ${acme_ca:-zerossl}），站点已按 HTTP 方式保留${CEND}"
      echo "${CWARNING}常见原因：CA 限流、DNS 未指向本机、80 端口不通${CEND}"
      echo "${CWARNING}稍后可用 ~/.acme.sh/acme.sh --issue -d ${domain} -w ${vhostdir} 重试，再 --install-cert${CEND}"
      # 把已写好的 HTTPS server 块里的 443 监听与证书指令去掉，保留 80，确保 nginx -t 通过
      if [ -e "${web_install_dir}/conf/vhost/${domain}.conf" ]; then
        sed -i '/listen .*443.*/d; /ssl_certificate/d; /ssl_protocols/d; /ssl_ciphers/d; /ssl_prefer/d; /ssl_session/d; /ssl_buffer/d; /ssl_ecdh/d; /ssl_conf_command/d; /ssl_stapling/d; /add_header Strict-Transport/d; /return 301 https/d' "${web_install_dir}/conf/vhost/${domain}.conf"
        ${web_install_dir}/sbin/nginx -t > /dev/null 2>&1 && ${web_install_dir}/sbin/nginx -s reload > /dev/null 2>&1
      fi
      [ -e "${apache_install_dir}/bin/httpd" ] && ${apache_install_dir}/bin/apachectl -k graceful > /dev/null 2>&1
    fi
  fi
}

Print_SSL() {
  if [ "${Domian_Mode}" == '2' ]; then
    echo "$(printf "%-30s" "Self-signed SSL Certificate:")${CMSG}${PATH_SSL}/${domain}.crt${CEND}"
    echo "$(printf "%-30s" "SSL Private Key:")${CMSG}${PATH_SSL}/${domain}.key${CEND}"
    echo "$(printf "%-30s" "SSL CSR File:")${CMSG}${PATH_SSL}/${domain}.csr${CEND}"
  elif [ "${Domian_Mode}" == '3' -o "${dnsapi_flag}" == 'y' ]; then
    echo "$(printf "%-30s" "Let's Encrypt SSL Certificate:")${CMSG}${PATH_SSL}/${domain}.crt${CEND}"
    echo "$(printf "%-30s" "SSL Private Key:")${CMSG}${PATH_SSL}/${domain}.key${CEND}"
  fi
}

Input_Add_proxy() {
  # 非交互时 read 兜底层永远返回空串，这个 while 没有默认出口 → 100% CPU 空转（审计实测 rc=124）
  [ -t 0 ] || { echo "${CFAILURE}--proxy 需要交互输入 proxy_pass（非交互环境不支持）${CEND}"; exit 1; }
  while :; do echo
    read -e -p "Please input the correct proxy_pass: " Proxy_Pass \
      || die_eof
    if [ -z "$(echo $Proxy_Pass | grep -E '^http://|https://')" ]; then
      echo "${CFAILURE}input error! Please only input example http://192.168.1.1:8080${CEND}"
    else
      echo "proxy_pass=${Proxy_Pass}"
      break
    fi
  done
}

Input_Add_domain() {
  if [ "${sslquiet_flag}" != 'y' ]; then
    if [ ! -t 0 ]; then
      echo "${CFAILURE}非交互环境无法选择证书类型，请加 --httponly / --selfsigned / --letsencrypt${CEND}"
      exit 1
    fi
    while :;do
      printf "
What Are You Doing?
\t${CMSG}1${CEND}. Use HTTP Only
\t${CMSG}2${CEND}. Use your own SSL Certificate and Key
\t${CMSG}3${CEND}. Use Let's Encrypt to Create SSL Certificate and Key
\t${CMSG}q${CEND}. Exit
"
      read -e -p "Please input the correct option: " Domian_Mode \
        || die_eof
      if [[ ! "${Domian_Mode}" =~ ^[1-3,q]$ ]]; then
        echo "${CFAILURE}input error! Please only input 1~3 and q${CEND}"
      else
        break
      fi
    done
  fi

  #Multiple_PHP
  # 只列真实存在 socket 的版本，编号按出现顺序重排。
  # 原来是一张写死的 5.3-8.5 表格（1=5.3 … 15=8.5），Lemon 把 PHP 下限提到 7.4
  # 并重新编号后，选「1」会指向早已不存在的 php53 socket，最后被 unset 掉，
  # 站点静默回落到默认 PHP —— 用户以为选了版本，其实没生效。
  if [ -e "${php_install_dir}/bin/php-config" ] && [ $(ls /dev/shm/php*-cgi.sock 2> /dev/null | wc -l) -ge 2 ]; then
    if [ "${mphp_flag}" != 'y' ]; then
      PHP_detail_ver=`${php_install_dir}/bin/php-config --version`
      PHP_main_ver=${PHP_detail_ver%.*}
      avail_php=()
      for one_ver in 74 80 81 82 83 84 85; do
        [ -e "/dev/shm/php${one_ver}-cgi.sock" ] && avail_php+=("${one_ver}")
      done
      while :; do
        # 非交互（参数化建站）时不刷菜单：read 拿到空串后走默认 0 = 主 PHP
        if [ -t 0 ]; then
          echo
          echo 'Please select a version of the PHP:'
          echo -e "\t${CMSG} 0${CEND}. PHP ${PHP_main_ver} (default)"
          php_idx=0
          for one_ver in "${avail_php[@]}"; do
            php_idx=$((php_idx + 1))
            echo -e "\t${CMSG}${php_idx}${CEND}. PHP ${one_ver:0:1}.${one_ver:1}"
          done
        fi
        read -e -p "Please input a number:(Default 0 press Enter) " php_option \
          || die_eof
        php_option=${php_option:-0}
        if [[ ! "${php_option}" =~ ^[0-9]+$ ]] || [ "${php_option}" -gt "${#avail_php[@]}" ]; then
          echo "${CWARNING}input error! Please only input number 0~${#avail_php[@]}${CEND}"
        else
          break
        fi
      done
      [ "${php_option}" != '0' ] && mphp_ver=${avail_php[$((php_option - 1))]}
    fi
    [ -n "${mphp_ver}" ] && [ ! -e "/dev/shm/php${mphp_ver}-cgi.sock" ] && unset mphp_ver
  fi

  case "${NGX_FLAG}" in
    "php")
      NGX_CONF=$(echo -e "location ~ [^/]\.php(/|$) {\n    #fastcgi_pass remote_php_ip:9000;\n    fastcgi_pass unix:/dev/shm/php${mphp_ver}-cgi.sock;\n    fastcgi_index index.php;\n    include fastcgi.conf;\n    try_files \$fastcgi_script_name =404;\n  }")
      ;;
    "java")
      NGX_CONF=$(echo -e "location ~ {\n    proxy_pass http://127.0.0.1:8080;\n    include proxy.conf;\n  }")
      ;;
  esac

  if [ "${Domian_Mode}" == '3' -o "${dnsapi_flag}" == 'y' ] && [ ! -e ~/.acme.sh/acme.sh ]; then
    pushd ${lemon_dir}/src > /dev/null
    [ ! -e acme.sh-master.tar.gz ] && wget -qc ${mirror_link}/src/acme.sh-master.tar.gz
    tar xzf acme.sh-master.tar.gz
    pushd acme.sh-master > /dev/null
    ./acme.sh --install > /dev/null 2>&1
    popd > /dev/null
    popd > /dev/null
    acme_ca=${acme_ca:-zerossl}
    ~/.acme.sh/acme.sh --set-default-ca --server "${acme_ca}" > /dev/null 2>&1
    if [ "${acme_ca}" == 'zerossl' ]; then
      ~/.acme.sh/acme.sh --register-account -m "admin@${domain}" > /dev/null 2>&1
    fi
  fi
  [ -e ~/.acme.sh/account.conf ] && sed -i '/^CERT_HOME=/d' ~/.acme.sh/account.conf
  if [[ "${Domian_Mode}" =~ ^[2-3]$ ]] || [ "${dnsapi_flag}" == 'y' ]; then
    if [ -e "${web_install_dir}/sbin/nginx" ]; then
      nginx_ssl_flag=y
      PATH_SSL=${web_install_dir}/conf/ssl
      [ ! -d "${PATH_SSL}" ] && mkdir -p ${PATH_SSL}
    elif [ -e "${caddy_install_dir}/bin/caddy" ]; then
      caddy_ssl_flag=y
      PATH_SSL=${caddy_install_dir}/conf/ssl
      [ ! -d "${PATH_SSL}" ] && mkdir -p ${PATH_SSL}
    elif [ -e "${apache_install_dir}/bin/httpd" ]; then
      apache_ssl_flag=y
      PATH_SSL=${apache_install_dir}/conf/ssl
      [ ! -d "${PATH_SSL}" ] && mkdir -p ${PATH_SSL}
    fi
  elif [ "${Domian_Mode}" == 'q' ]; then
    exit 1
  fi

  while :; do echo
    # 命令行给了域名就不问（脚本化用），没给才交互
    if [ -n "${ARG_DOMAIN}" ]; then
      domain="${ARG_DOMAIN}"
        # 参数化传进来的域名要当场校验：后面这个 while 循环不会再有 read，
        # 非法值会原地无限刷 invalid（真机实测 rc=124 卡死）
        if ! Is_Valid_Domain "${domain}"; then
          echo "${CFAILURE}域名不合法：${domain}${CEND}" >&2
          exit 1
        fi
      echo "Domain: ${CMSG}${domain}${CEND}"
    else
      read -e -p "Please input domain(example: www.example.com): " domain \
        || die_eof
    fi
    # 只接受常规域名：域名会被拼进 nginx 配置和 ${wwwroot_dir}/${domain} 路径，
    # 放行 "a.b; } server {...}" 或 "../../etc" 这类输入等于开放配置注入与路径穿越
    if ! Is_Valid_Domain "${domain}"; then
      echo "${CWARNING}Your ${domain} is invalid! ${CEND}"
    else
      break
    fi
  done

  if [ -e "${web_install_dir}/conf/vhost/${domain}.conf" -o -e "${caddy_install_dir}/conf/vhost/${domain}.conf" -o -e "${apache_install_dir}/conf/vhost/${domain}.conf" ]; then
    [ -e "${web_install_dir}/conf/vhost/${domain}.conf" ] && echo -e "${domain} in the Nginx/Tengine/OpenResty already exist! \nYou can delete ${CMSG}${web_install_dir}/conf/vhost/${domain}.conf${CEND} and re-create"
    [ -e "${caddy_install_dir}/conf/vhost/${domain}.conf" ] && echo -e "${domain} in the Caddy already exist! \nYou can delete ${CMSG}${caddy_install_dir}/conf/vhost/${domain}.conf${CEND} and re-create"
    [ -e "${apache_install_dir}/conf/vhost/${domain}.conf" ] && echo -e "${domain} in the Apache already exist! \nYou can delete ${CMSG}${apache_install_dir}/conf/vhost/${domain}.conf${CEND} and re-create"
    echo "${CWARNING}要重建请先删掉它：bash vhost.sh --del ${domain}${CEND}"
    exit 1
  else
    echo "domain=${domain}"
  fi
  if [[ -z ${proxy_flag} || "${proxy_flag}" != 'y' ]]; then
    # 命令行给了 --dir 就不再追问（自动化/screen 里跑时没有输入源，会一直卡在提示上）
    if [ -n "${vhostdir}" ]; then
      echo "Virtual Host Directory=${CMSG}${vhostdir}${CEND}"
    else
    while :; do echo
      echo "Please input the directory for the domain:${domain} :"
      read -e -p "(Default directory: ${wwwroot_dir}/${domain}): " vhostdir \
        || die_eof
      if [ -n "${vhostdir}" -a -z "$(echo ${vhostdir} | grep '^/')" ]; then
        echo "${CWARNING}input error! Press Enter to continue...${CEND}"
      else
        if [ -z "${vhostdir}" ]; then
          vhostdir="${wwwroot_dir}/${domain}"
          echo "Virtual Host Directory=${CMSG}${vhostdir}${CEND}"
        fi
        break
      fi
    done
    fi
    # 建目录/占位页/权限：--dir 与交互两条路都要走（否则 --dir 建出来的站点是 403，真机踩到）
    echo
    echo "Create Virtul Host directory......"
    [ -d "${vhostdir}" ] || { CREATED_VHOSTDIR="${vhostdir}"; CREATED_VHOST_DOMAIN="${domain}"; }
    mkdir -p "${vhostdir}"
    if [ -z "$(ls -A "${vhostdir}" 2>/dev/null)" ]; then
      printf '%s\n' "<!doctype html><meta charset=\"utf-8\"><title>${domain}</title>" "<h1>${domain}</h1><p>站点已创建，请把程序上传到 ${vhostdir}</p>" > "${vhostdir}/index.html"
    fi
    echo "set permissions of Virtual Host directory......"
    chown -R ${run_user}:${run_group} "${vhostdir}"
  else
    # proxy 模式跳过目录询问，但 Create_SSL 的 HTTP-01 验证文件和 acme.sh -w 都需要 webroot
    vhostdir="${wwwroot_dir}/${domain}"
    echo "Virtual Host Directory=${CMSG}${vhostdir}${CEND}"
    [ -d "${vhostdir}" ] || { CREATED_VHOSTDIR="${vhostdir}"; CREATED_VHOST_DOMAIN="${domain}"; }
    mkdir -p "${vhostdir}"
    if [ -z "$(ls -A "${vhostdir}" 2>/dev/null)" ]; then
      printf '%s\n' "<!doctype html><meta charset=\"utf-8\"><title>${domain}</title>" "<h1>${domain}</h1><p>站点已创建。</p>" > "${vhostdir}/index.html"
    fi
    chown -R ${run_user}:${run_group} "${vhostdir}"
  fi

  while :; do echo
    read -e -p "Do you want to add more domain name? [y/n]: " moredomainame_flag || die_eof
    [ -z "${moredomainame_flag}" ] && moredomainame_flag=n
    if [[ ! ${moredomainame_flag} =~ ^[y,n]$ ]]; then
      echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
    else
      break
    fi
  done

  if [ "${moredomainame_flag}" == 'y' ]; then
    while :; do echo
      read -e -p "Type domainname or IP(example: example.com other.example.com): " moredomain \
        || die_eof
      _bad=''
      for _d in ${moredomain}; do
        Is_Valid_Domain "${_d}" || _bad="${_d}"
      done
      if [ -n "${_bad}" ]; then
        echo "${CWARNING}域名不合法：${_bad}（只允许常规域名/子域）${CEND}"
      else
        [ "${moredomain}" == "${domain}" ] && echo "${CWARNING}Domain name already exists! ${CEND}" && continue
        echo domain list="$moredomain"
        moredomainame=" $moredomain"
        break
      fi
    done
    Apache_Domain_alias=ServerAlias${moredomainame}

    if [ -e "${web_install_dir}/sbin/nginx" ]; then
      while :; do echo
        read -e -p "Do you want to redirect from ${moredomain} to ${domain}? [y/n]: " redirect_flag || die_eof
        [ -z "${redirect_flag}" ] && redirect_flag=n
        if [[ ! ${redirect_flag} =~ ^[y,n]$ ]]; then
          echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
        else
          break
        fi
      done
      [ "${redirect_flag}" == 'y' ] && Nginx_redirect="if (\$host != ${domain}) {  return 301 \$scheme://${domain}\$request_uri;  }"
    fi
  fi

  # 三个 ssl_flag 是互斥的（见上面 393-405 的 if/elif）。这里只能判 nginx/caddy；
  # 把 apache_ssl_flag 也或进来会让下面的 `elif apache_ssl_flag` 永远不可达，
  # 结果 Apache 独占时只写 <VirtualHost *:443> 却不加 `Listen 443`，443 静默不监听（d13 真机复现）。
  if [ "${nginx_ssl_flag}" == 'y' -o "${caddy_ssl_flag}" == 'y' ]; then
    while :; do echo
      read -e -p "Do you want to redirect all HTTP requests to HTTPS? [y/n]: " https_flag || die_eof
      [ -z "${https_flag}" ] && https_flag=n
      if [[ ! ${https_flag} =~ ^[y,n]$ ]]; then
        echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
      else
        break
      fi
    done

    # 仅装 Caddy 时 web_install_dir 为空，跳过 nginx http2/版本探测（Caddy 默认支持 HTTP/2/3）
    if [ -n "${web_install_dir}" ] && [[ "$(${web_install_dir}/sbin/nginx -V 2>&1 | grep -Eo 'with-http_v2_module')" = 'with-http_v2_module' ]]; then
        # 获取nginx版本号
        nginx_version=$(${web_install_dir}/sbin/nginx -v 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
        # 转换版本号为可比较的数字
        version_number=$(echo $nginx_version | awk -F. '{ printf("%d%02d%02d\n", $1,$2,$3); }')
        
        if [ "$version_number" -lt 12501 ]; then
          # nginx版本小于1.25.1
          LISTENOPT="443 ssl http2"
          HTTP2OPT=""
        else
          # nginx版本大于等于1.25.1
          LISTENOPT="443 ssl"
          HTTP2OPT="http2 on;"
        fi
    else
      LISTENOPT="443 ssl spdy"
      HTTP2OPT=""
    fi
    Create_SSL
    if [ -n "`ifconfig | grep inet6`" ]; then
      # Let's Encrypt 的新中间证书（YR1/YR2 起）不再带 OCSP 地址，nginx 会对 ssl_stapling
      # 报 "no OCSP responder URL in the certificate" 并忽略它 —— 每次 reload 都刷警告。
      # 只有证书真的带 OCSP 地址时才写这两行。
      stapling_opt=''
      if openssl x509 -in "${PATH_SSL}/${domain}.crt" -noout -ocsp_uri 2>/dev/null | grep -q http; then
        stapling_opt='  ssl_stapling on;\n  ssl_stapling_verify on;\n'
      fi
      Nginx_conf=$(echo -e "listen 80;\n  listen [::]:80;\n  listen ${LISTENOPT};\n  listen [::]:${LISTENOPT};\n  ${HTTP2OPT}\n  ssl_certificate ${PATH_SSL}/${domain}.crt;\n  ssl_certificate_key ${PATH_SSL}/${domain}.key;\n  ssl_protocols TLSv1.2 TLSv1.3;\n  ssl_ecdh_curve X25519:prime256v1:secp384r1:secp521r1;\n  ssl_ciphers ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256;\n  ssl_conf_command Ciphersuites TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256;\n  ssl_conf_command Options PrioritizeChaCha;\n  ssl_prefer_server_ciphers on;\n  ssl_session_timeout 10m;\n  ssl_session_cache shared:SSL:10m;\n  ssl_buffer_size 2k;\n  add_header Strict-Transport-Security max-age=15768000;\n${stapling_opt}")
    else
      Nginx_conf=$(echo -e "listen 80;\n  listen ${LISTENOPT};\n  ${HTTP2OPT}\n  ssl_certificate ${PATH_SSL}/${domain}.crt;\n  ssl_certificate_key ${PATH_SSL}/${domain}.key;\n  ssl_protocols TLSv1.2 TLSv1.3;\n  ssl_ecdh_curve X25519:prime256v1:secp384r1:secp521r1;\n  ssl_ciphers ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256;\n  ssl_conf_command Ciphersuites TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256;\n  ssl_conf_command Options PrioritizeChaCha;\n  ssl_prefer_server_ciphers on;\n  ssl_session_timeout 10m;\n  ssl_session_cache shared:SSL:10m;\n  ssl_buffer_size 2k;\n  add_header Strict-Transport-Security max-age=15768000;\n${stapling_opt}")
    fi
    Apache_SSL=$(echo -e "SSLEngine on\n  SSLCertificateFile \"${PATH_SSL}/${domain}.crt\"\n  SSLCertificateKeyFile \"${PATH_SSL}/${domain}.key\"")
  elif [ "${apache_ssl_flag}" == 'y' ]; then
    Create_SSL
    Apache_SSL=$(echo -e "SSLEngine on\n  SSLCertificateFile \"${PATH_SSL}/${domain}.crt\"\n  SSLCertificateKeyFile \"${PATH_SSL}/${domain}.key\"")
    [ -z "$(grep 'Listen 443' ${apache_install_dir}/conf/httpd.conf)" ] && sed -i "s@Listen 80@&\nListen 443@" ${apache_install_dir}/conf/httpd.conf
    [ -z "$(grep 'ServerName 0.0.0.0:443' ${apache_install_dir}/conf/httpd.conf)" ] && sed -i "s@ServerName 0.0.0.0:80@&\nServerName 0.0.0.0:443@" ${apache_install_dir}/conf/httpd.conf
  else
    if [ -n "`ifconfig | grep inet6`" ]; then
      Nginx_conf=$(echo -e "listen 80;\n  listen [::]:80;")
    else
      Nginx_conf=$(echo -e "listen 80;")
    fi
  fi
}

Nginx_anti_hotlinking() {
  while :; do echo
    read -e -p "Do you want to add hotlink protection? [y/n]: " anti_hotlinking_flag || die_eof
    [ -z "${anti_hotlinking_flag}" ] && anti_hotlinking_flag=n
    if [[ ! ${anti_hotlinking_flag} =~ ^[y,n]$ ]]; then
      echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
    else
      break
    fi
  done

  if [ -n "$(echo ${domain} | grep '.*\..*\..*')" ]; then
    domain_allow="*.${domain#*.} ${domain}"
  else
    domain_allow="*.${domain} ${domain}"
  fi

  if [ "${anti_hotlinking_flag}" == 'y' ]; then
    if [ "${moredomainame_flag}" == 'y' -a "${moredomain}" != "*.${domain}" ]; then
      domain_allow_all=${domain_allow}${moredomainame}
    else
      domain_allow_all=${domain_allow}
    fi
    domain_allow_all=`echo ${domain_allow_all} | tr ' ' '\n' | awk '!a[$1]++' | xargs`
    anti_hotlinking=$(echo -e "location ~ .*\.(wma|wmv|asf|mp3|mmf|zip|rar|jpg|gif|png|swf|flv|mp4)$ {\n    valid_referers none blocked ${domain_allow_all};\n    if (\$invalid_referer) {\n        return 403;\n    }\n  }")
  fi
}

Nginx_rewrite() {
  [ ! -d "${web_install_dir}/conf/rewrite" ] && mkdir ${web_install_dir}/conf/rewrite
  while :; do echo
    read -e -p "Allow Rewrite rule? [y/n]: " rewrite_flag || die_eof
    [ -z "${rewrite_flag}" ] && rewrite_flag=n
    if [[ ! "${rewrite_flag}" =~ ^[y,n]$ ]]; then
      echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
    else
      break
    fi
  done
  if [ "${rewrite_flag}" == 'n' ]; then
    rewrite="none"
    touch "${web_install_dir}/conf/rewrite/${rewrite}.conf"
  else
    echo
    echo "Please input the rewrite of programme :"
    echo "${CMSG}wordpress${CEND},${CMSG}opencart${CEND},${CMSG}magento2${CEND},${CMSG}drupal${CEND},${CMSG}joomla${CEND},${CMSG}codeigniter${CEND},${CMSG}laravel${CEND}"
    echo "${CMSG}thinkphp${CEND},${CMSG}pathinfo${CEND},${CMSG}discuz${CEND},${CMSG}typecho${CEND},${CMSG}ecshop${CEND},${CMSG}nextcloud${CEND},${CMSG}zblog${CEND},${CMSG}whmcs${CEND} rewrite was exist."
    read -e -p "(Default rewrite: other): " rewrite \
      || die_eof
    if [ "${rewrite}" == "" ]; then
      rewrite="other"
    fi
    echo "You choose rewrite=${CMSG}$rewrite${CEND}"
    [ "${NGX_FLAG}" == 'php' -a "${rewrite}" == "joomla" ] && NGX_CONF=$(echo -e "location ~ \\.php\$ {\n    #fastcgi_pass remote_php_ip:9000;\n    fastcgi_pass unix:/dev/shm/php${mphp_ver}-cgi.sock;\n    fastcgi_index index.php;\n    include fastcgi.conf;\n    try_files \$fastcgi_script_name =404;\n  }")
    [ "${NGX_FLAG}" == 'php' ] && [[ "${rewrite}" =~ ^codeigniter$|^thinkphp$|^pathinfo$ ]] && NGX_CONF=$(echo -e "location ~ [^/]\.php(/|\$) {\n    #fastcgi_pass remote_php_ip:9000;\n    fastcgi_pass unix:/dev/shm/php${mphp_ver}-cgi.sock;\n    fastcgi_index index.php;\n    include fastcgi.conf;\n    fastcgi_split_path_info ^(.+?\.php)(/.*)\$;\n    set \$path_info \$fastcgi_path_info;\n    fastcgi_param PATH_INFO \$path_info;\n    try_files \$fastcgi_script_name =404;    \n  }")
    [ "${NGX_FLAG}" == 'php' -a "${rewrite}" == "typecho" ] && NGX_CONF=$(echo -e "location ~ .*\.php(\/.*)*\$ {\n    #fastcgi_pass remote_php_ip:9000;\n    fastcgi_pass unix:/dev/shm/php${mphp_ver}-cgi.sock;\n    fastcgi_index index.php;\n    include fastcgi.conf;\n    set \$path_info \"\";\n    set \$real_script_name \$fastcgi_script_name;\n    if (\$fastcgi_script_name ~ \"^(.+?\.php)(/.+)\$\") {\n      set \$real_script_name \$1;\n      set \$path_info \$2;\n    }\n    fastcgi_param SCRIPT_FILENAME \$document_root\$real_script_name;\n    fastcgi_param SCRIPT_NAME \$real_script_name;\n    fastcgi_param PATH_INFO \$path_info;\n  }")
    if [[ ! "${rewrite}" =~ ^magento2$|^pathinfo$ ]]; then
      if [ -e "config/${rewrite}.conf" ]; then
        /bin/cp config/${rewrite}.conf ${web_install_dir}/conf/rewrite/${rewrite}.conf
      else
        touch "${web_install_dir}/conf/rewrite/${rewrite}.conf"
      fi
    fi
  fi
}

Nginx_log() {
  while :; do echo
    read -e -p "Allow Nginx/Tengine/OpenResty access_log? [y/n]: " access_flag || die_eof
    [ -z "${access_flag}" ] && access_flag=n
    if [[ ! "${access_flag}" =~ ^[y,n]$ ]]; then
      echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
    else
      break
    fi
  done
  if [ "${access_flag}" == 'n' ]; then
    Nginx_log="access_log off;"
  else
    Nginx_log="access_log ${wwwlogs_dir}/${domain}_nginx.log combined;"
    echo "You access log file=${CMSG}${wwwlogs_dir}/${domain}_nginx.log${CEND}"
  fi
}

Caddy_log() {
  while :; do echo
    read -e -p "Allow Caddy access_log? [y/n]: " access_flag || die_eof
    [ -z "${access_flag}" ] && access_flag=n
    if [[ ! "${access_flag}" =~ ^[y,n]$ ]]; then
      echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
    else
      break
    fi
  done
  if [ "${access_flag}" == 'n' ]; then
    Caddy_log=""
  else
    Caddy_log="log {
        output file ${wwwlogs_dir}/${domain}_caddy.log
    }"
    echo "You access log file=${CMSG}${wwwlogs_dir}/${domain}_caddy.log${CEND}"
  fi
}

Create_nginx_phpfpm_conf() {
  [ ! -d ${web_install_dir}/conf/vhost ] && mkdir ${web_install_dir}/conf/vhost
  cat > ${web_install_dir}/conf/vhost/${domain}.conf << EOF
server {
  ${Nginx_conf}
  server_name ${domain}${moredomainame};
  ${Nginx_log}
  index index.html index.htm index.php;
  root ${vhostdir};
  ${Nginx_redirect}
  include ${web_install_dir}/conf/rewrite/${rewrite}.conf;
  #error_page 404 /404.html;
  #error_page 502 /502.html;
  ${anti_hotlinking}
  ${NGX_CONF}

  location ~ .*\.(gif|jpg|jpeg|png|bmp|swf|flv|mp4|ico)$ {
    expires 30d;
    access_log off;
  }
  location ~ \.(js|css)$ {
    expires 7d;
    access_log off;
  }
  location ~ /(\.user\.ini|\.ht|\.git|\.svn|\.project|LICENSE|README\.md) {
    deny all;
  }
  location /.well-known {
    allow all;
  }
}
EOF

  [ "${rewrite}" == 'pathinfo' ] && sed -i '/pathinfo.conf;$/d' ${web_install_dir}/conf/vhost/${domain}.conf
  if [ "${rewrite}" == 'magento2' -a -e "config/${rewrite}.conf" ]; then
    /bin/cp config/${rewrite}.conf ${web_install_dir}/conf/vhost/${domain}.conf
    sed -i "s@/dev/shm/php-cgi.sock@/dev/shm/php${mphp_ver}-cgi.sock@g" ${web_install_dir}/conf/vhost/${domain}.conf
    sed -i "s@^  set \$MAGE_ROOT.*;@  set \$MAGE_ROOT ${vhostdir};@" ${web_install_dir}/conf/vhost/${domain}.conf
    # root 行若保留 $MAGE_ROOT 字面量，Del_NGX_Vhost 按行提取目录时会拿到死变量，一并替换成实际路径
    sed -i "s@^  root \$MAGE_ROOT/pub;@  root ${vhostdir}/pub;@" ${web_install_dir}/conf/vhost/${domain}.conf
    sed -i "s@^  server_name.*;@  server_name ${domain}${moredomainame};@" ${web_install_dir}/conf/vhost/${domain}.conf
    sed -i "s@^  server_name.*;@&\n  ${Nginx_log}@" ${web_install_dir}/conf/vhost/${domain}.conf
    if [ "${anti_hotlinking_flag}" == 'y' ]; then
      sed -i "s@^  root.*;@&\n  }@" ${web_install_dir}/conf/vhost/${domain}.conf
      sed -i "s@^  root.*;@&\n    }@" ${web_install_dir}/conf/vhost/${domain}.conf
      sed -i "s@^  root.*;@&\n      return 403;@" ${web_install_dir}/conf/vhost/${domain}.conf
      sed -i "s@^  root.*;@&\n    if (\$invalid_referer) {@" ${web_install_dir}/conf/vhost/${domain}.conf
      sed -i "s@^  root.*;@&\n    valid_referers none blocked ${domain_allow_all};@" ${web_install_dir}/conf/vhost/${domain}.conf
      sed -i "s@^  root.*;@&\n  location ~ .*\.(wma|wmv|asf|mp3|mmf|zip|rar|jpg|gif|png|swf|flv|mp4)\$ {@" ${web_install_dir}/conf/vhost/${domain}.conf
    fi

    [ "${redirect_flag}" == 'y' ] && sed -i "s@^  root.*;@&\n  if (\$host != ${domain}) {  return 301 \$scheme://${domain}\$request_uri;  }@" ${web_install_dir}/conf/vhost/${domain}.conf

    if [ "${nginx_ssl_flag}" == 'y' ]; then
      sed -i "s@^  listen 80;@&\n  listen ${LISTENOPT};@" ${web_install_dir}/conf/vhost/${domain}.conf

      sed -i "s@^  server_name.*;@&\n  add_header Strict-Transport-Security max-age=15768000;@" ${web_install_dir}/conf/vhost/${domain}.conf
      sed -i "s@^  server_name.*;@&\n  ssl_buffer_size 2k;@" ${web_install_dir}/conf/vhost/${domain}.conf
      sed -i "s@^  server_name.*;@&\n  ssl_session_cache shared:SSL:10m;@" ${web_install_dir}/conf/vhost/${domain}.conf
      sed -i "s@^  server_name.*;@&\n  ssl_session_timeout 10m;@" ${web_install_dir}/conf/vhost/${domain}.conf
      sed -i "s@^  server_name.*;@&\n  ssl_prefer_server_ciphers on;@" ${web_install_dir}/conf/vhost/${domain}.conf
      sed -i "s@^  server_name.*;@&\n  ssl_conf_command Options PrioritizeChaCha;@" ${web_install_dir}/conf/vhost/${domain}.conf
      sed -i "s@^  server_name.*;@&\n  ssl_conf_command Ciphersuites TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_128_GCM_SHA256;@" ${web_install_dir}/conf/vhost/${domain}.conf
      sed -i "s@^  server_name.*;@&\n  ssl_ciphers ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256;@" ${web_install_dir}/conf/vhost/${domain}.conf
      sed -i "s@^  server_name.*;@&\n  ssl_ecdh_curve X25519:prime256v1:secp384r1:secp521r1;@" ${web_install_dir}/conf/vhost/${domain}.conf
      sed -i "s@^  server_name.*;@&\n  ssl_protocols TLSv1.2 TLSv1.3;@" ${web_install_dir}/conf/vhost/${domain}.conf
      sed -i "s@^  server_name.*;@&\n  ssl_certificate_key ${PATH_SSL}/${domain}.key;@" ${web_install_dir}/conf/vhost/${domain}.conf
      sed -i "s@^  server_name.*;@&\n  ssl_certificate ${PATH_SSL}/${domain}.crt;@" ${web_install_dir}/conf/vhost/${domain}.conf
    fi
  fi

  [ "${https_flag}" == 'y' ] && sed -i "s@^  root.*;@&\n  if (\$ssl_protocol = \"\") { return 301 https://\$host\$request_uri; }@" ${web_install_dir}/conf/vhost/${domain}.conf

  # 证书没签下来（CA 限流 / 域名未解析 / 80 不通）时，必须把 conf 降级成 HTTP-only 再测。
  # 否则 nginx -t 会报 "cannot load certificate ... BIO_new_file() failed" → 站点被整份删掉，
  # 用户拿到的是“什么都没有”，而不是“站点能用、证书待补”（真机复现：ZeroSSL 限流时）。
  if [ -e "${web_install_dir}/conf/vhost/${domain}.conf" ] && grep -q 'ssl_certificate ' "${web_install_dir}/conf/vhost/${domain}.conf" 2>/dev/null      && { [ ! -s "${PATH_SSL}/${domain}.crt" ] || [ ! -s "${PATH_SSL}/${domain}.key" ]; }; then
    echo "${CWARNING}证书不可用，站点降级为 HTTP（仅 80 端口）${CEND}"
    sed -i '/listen .*443.*/d; /listen .*${LISTENOPT}.*/d; /ssl_certificate/d; /ssl_protocols/d; /ssl_ciphers/d; /ssl_prefer/d; /ssl_session/d; /ssl_buffer/d; /ssl_ecdh/d; /ssl_conf_command/d; /ssl_stapling/d; /add_header Strict-Transport/d; /return 301 https/d; /if (.*ssl_protocol/d; /http2/d' "${web_install_dir}/conf/vhost/${domain}.conf"
    https_flag=n
    nginx_ssl_flag=n
  fi
  echo
  ${web_install_dir}/sbin/nginx -t
  if [ $? == 0 ]; then
    echo "Reload Nginx......"
    ${web_install_dir}/sbin/nginx -s reload
  else
    rm -f ${web_install_dir}/conf/vhost/${domain}.conf
    echo "Create virtualhost ... [${CFAILURE}FAILED${CEND}]"
    exit 1
  fi

  printf "
#######################################################################
# Lemon - Debian 12/13 一键 Web 环境（Nginx/Tengine/OpenResty/Caddy） #
# https://github.com/misakacoo/lemon                                  #
#######################################################################
"
  echo "$(printf "%-30s" "Your domain:")${CMSG}${domain}${CEND}"
  echo "$(printf "%-30s" "Virtualhost conf:")${CMSG}${web_install_dir}/conf/vhost/${domain}.conf${CEND}"
  echo "$(printf "%-30s" "Directory of:")${CMSG}${vhostdir}${CEND}"
  [ "${rewrite_flag}" == 'y' -a "${rewrite}" != 'magento2' -a "${rewrite}" != 'pathinfo' ] && echo "$(printf "%-30s" "Rewrite rule:")${CMSG}${web_install_dir}/conf/rewrite/${rewrite}.conf${CEND}"
  Print_SSL
}

Create_nginx_proxy_conf() {
  [ ! -d ${web_install_dir}/conf/vhost ] && mkdir ${web_install_dir}/conf/vhost
  cat > ${web_install_dir}/conf/vhost/${domain}.conf << EOF
server {
  ${Nginx_conf}
  server_name ${domain}${moredomainame};
  ${Nginx_log}
  index index.html index.htm index.php;
  ${Nginx_redirect}
  location / {
    proxy_pass ${Proxy_Pass};
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header Host \$http_host;
    proxy_set_header X-NginX-Proxy true;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_max_temp_file_size 0;
  }

  #error_page 404 /404.html;
  #error_page 502 /502.html;
  ${anti_hotlinking}

  location ~ .*\.(gif|jpg|jpeg|png|bmp|swf|flv|mp4|ico)$ {
    expires 30d;
    access_log off;
  }
  location ~ \.(js|css)$ {
    expires 7d;
    access_log off;
  }
  location ~ /(\.user\.ini|\.ht|\.git|\.svn|\.project|LICENSE|README\.md) {
    deny all;
  }
  # ACME HTTP-01 验证必须由本地 webroot 提供，否则会被上面的 location / 代理到后端返回 404
  location ^~ /.well-known/acme-challenge/ {
    root ${vhostdir};
    allow all;
  }
  location /.well-known {
    allow all;
  }
}
EOF

  [ "${redirect_flag}" == 'y' ] && sed -i "s@^  root.*;@&\n  if (\$host != ${domain}) {  return 301 \$scheme://${domain}\$request_uri;  }@" ${web_install_dir}/conf/vhost/${domain}.conf

  if [ "${anti_hotlinking_flag}" == 'y' ]; then
      sed -i "s@^  root.*;@&\n  }@" ${web_install_dir}/conf/vhost/${domain}.conf
      sed -i "s@^  root.*;@&\n    }@" ${web_install_dir}/conf/vhost/${domain}.conf
      sed -i "s@^  root.*;@&\n      return 403;@" ${web_install_dir}/conf/vhost/${domain}.conf
      sed -i "s@^  root.*;@&\n    if (\$invalid_referer) {@" ${web_install_dir}/conf/vhost/${domain}.conf
      sed -i "s@^  root.*;@&\n    valid_referers none blocked ${domain_allow_all};@" ${web_install_dir}/conf/vhost/${domain}.conf
      sed -i "s@^  root.*;@&\n  location ~ .*\.(wma|wmv|asf|mp3|mmf|zip|rar|jpg|gif|png|swf|flv|mp4)\$ {@" ${web_install_dir}/conf/vhost/${domain}.conf
    fi

  [ "${https_flag}" == 'y' ] && sed -i "s@^  root.*;@&\n  if (\$ssl_protocol = \"\") { return 301 https://\$host\$request_uri; }@" ${web_install_dir}/conf/vhost/${domain}.conf

  echo
  ${web_install_dir}/sbin/nginx -t
  if [ $? == 0 ]; then
    echo "Reload Nginx......"
    ${web_install_dir}/sbin/nginx -s reload
  else
    rm -f ${web_install_dir}/conf/vhost/${domain}.conf
    echo "Create virtualhost ... [${CFAILURE}FAILED${CEND}]"
    exit 1
  fi

  printf "
#######################################################################
# Lemon - Debian 12/13 一键 Web 环境（Nginx/Tengine/OpenResty/Caddy） #
# https://github.com/misakacoo/lemon                                  #
#######################################################################
"
  echo "$(printf "%-30s" "Your domain:")${CMSG}${domain}${CEND}"
  echo "$(printf "%-30s" "Virtualhost conf:")${CMSG}${web_install_dir}/conf/vhost/${domain}.conf${CEND}"
  #echo "$(printf "%-30s" "Directory of:")${CMSG}${vhostdir}${CEND}"
  [ "${rewrite_flag}" == 'y' -a "${rewrite}" != 'magento2' -a "${rewrite}" != 'pathinfo' ] && echo "$(printf "%-30s" "Rewrite rule:")${CMSG}${web_install_dir}/conf/rewrite/${rewrite}.conf${CEND}"
  Print_SSL
}

Reload_Caddy() {
  if [ -e /usr/bin/systemctl ]; then
    systemctl reload caddy
  else
    service caddy reload
  fi
}

Create_caddy_php_conf() {
  [ ! -d ${caddy_install_dir}/conf/vhost ] && mkdir -p ${caddy_install_dir}/conf/vhost
  # Caddy 的站点地址必须**逗号分隔**，而 moredomainame 是空格分隔的（给 nginx 用）。
  # 另外不写 http:// 前缀时 Caddy 会给该主机名自动申请证书并 308 跳到 HTTPS，
  # 纯 HTTP 站点必须显式写 http://。
  caddy_http_addrs=''
  caddy_https_addrs=''
  for one_domain in ${domain} ${moredomainame}; do
    caddy_http_addrs="${caddy_http_addrs}http://${one_domain}, "
    caddy_https_addrs="${caddy_https_addrs}https://${one_domain}, "
  done
  caddy_http_addrs=${caddy_http_addrs%, }
  caddy_https_addrs=${caddy_https_addrs%, }
  if [ "${https_flag}" == 'y' ]; then
    cat > ${caddy_install_dir}/conf/vhost/${domain}.conf << EOF
${caddy_http_addrs} {
  redir https://{host}{uri}
}

${caddy_https_addrs} {
  root * ${vhostdir}
  php_fastcgi unix//dev/shm/php${mphp_ver}-cgi.sock
  file_server
  ${Caddy_log}
  tls ${PATH_SSL}/${domain}.crt ${PATH_SSL}/${domain}.key
  handle_errors {
    rewrite * /{err.status_code}.html
    file_server
  }
}
EOF
  else
    cat > ${caddy_install_dir}/conf/vhost/${domain}.conf << EOF
${caddy_http_addrs} {
  root * ${vhostdir}
  php_fastcgi unix//dev/shm/php${mphp_ver}-cgi.sock
  file_server
  ${Caddy_log}
  $( [ -e "${PATH_SSL}/${domain}.crt" ] && echo "tls ${PATH_SSL}/${domain}.crt ${PATH_SSL}/${domain}.key" )
  handle_errors {
    rewrite * /{err.status_code}.html
    file_server
  }
}
EOF
  fi

  # Caddy 以 www 身份运行，但日志目录是 root:root 755、证书私钥是 root:600，
  # 它读不了 → reload 报 permission denied → 443 起不来，而 vhost.sh 之前不检查 reload 结果。
  # 真机 d13 复现：/data/wwwlogs/d13.5mm.xyz_caddy.log permission denied。
  [ -d "${wwwlogs_dir}" ] && chown -R ${run_user}:${run_group} ${wwwlogs_dir} 2>/dev/null
  for _f in ${PATH_SSL}/${domain}.key; do
    [ -e "${_f}" ] && { chgrp ${run_group} "${_f}" 2>/dev/null; chmod 640 "${_f}"; }
  done

  echo
  ${caddy_install_dir}/bin/caddy validate --config ${caddy_install_dir}/conf/Caddyfile
  if [ $? == 0 ]; then
    echo "Reload Caddy......"
    if ! systemctl reload caddy; then
      echo "${CFAILURE}Caddy reload 失败，443 不会生效${CEND}"
      echo "${CWARNING}常见原因：${wwwlogs_dir} 或 ${PATH_SSL}/${domain}.key 属主不是 ${run_user}${CEND}"
      journalctl -u caddy -n 5 --no-pager 2>/dev/null
      exit 1
    fi
  else
    rm -f ${caddy_install_dir}/conf/vhost/${domain}.conf
    echo "Create virtualhost ... [${CFAILURE}FAILED${CEND}]"
    exit 1
  fi

  printf "
#######################################################################
# Lemon - Debian 12/13 一键 Web 环境（Nginx/Tengine/OpenResty/Caddy） #
# https://github.com/misakacoo/lemon                                  #
#######################################################################
"
  echo "$(printf "%-30s" "Your domain:")${CMSG}${domain}${CEND}"
  echo "$(printf "%-30s" "Caddy Virtualhost conf:")${CMSG}${caddy_install_dir}/conf/vhost/${domain}.conf${CEND}"
  echo "$(printf "%-30s" "Directory of:")${CMSG}${vhostdir}${CEND}"
}

Create_caddy_proxy_conf() {
  [ ! -d ${caddy_install_dir}/conf/vhost ] && mkdir -p ${caddy_install_dir}/conf/vhost
  # 与 Create_caddy_php_conf 一致：站点地址必须**逗号分隔**（moredomainame 是给 nginx 用的空格分隔），
  # 且不写协议前缀时 Caddy 会自动申请证书并 308 跳 HTTPS
  caddy_http_addrs=''
  caddy_https_addrs=''
  for one_domain in ${domain} ${moredomainame}; do
    caddy_http_addrs="${caddy_http_addrs}http://${one_domain}, "
    caddy_https_addrs="${caddy_https_addrs}https://${one_domain}, "
  done
  caddy_http_addrs=${caddy_http_addrs%, }
  caddy_https_addrs=${caddy_https_addrs%, }
  if [ "${https_flag}" == 'y' ]; then
    cat > ${caddy_install_dir}/conf/vhost/${domain}.conf << EOF
${caddy_http_addrs} {
  redir https://{host}{uri}
}

${caddy_https_addrs} {
  reverse_proxy ${Proxy_Pass}
  ${Caddy_log}
  tls ${PATH_SSL}/${domain}.crt ${PATH_SSL}/${domain}.key
}
EOF
  else
    cat > ${caddy_install_dir}/conf/vhost/${domain}.conf << EOF
${caddy_http_addrs} {
  reverse_proxy ${Proxy_Pass}
  ${Caddy_log}
  $( [ -e "${PATH_SSL}/${domain}.crt" ] && echo "tls ${PATH_SSL}/${domain}.crt ${PATH_SSL}/${domain}.key" )
}
EOF
  fi

  echo
  ${caddy_install_dir}/bin/caddy validate --config ${caddy_install_dir}/conf/Caddyfile
  if [ $? == 0 ]; then
    echo "Reload Caddy......"
    Reload_Caddy
  else
    rm -f ${caddy_install_dir}/conf/vhost/${domain}.conf
    echo "Create virtualhost ... [${CFAILURE}FAILED${CEND}]"
    exit 1
  fi

  printf "
#######################################################################
# Lemon - Debian 12/13 一键 Web 环境（Nginx/Tengine/OpenResty/Caddy） #
# https://github.com/misakacoo/lemon                                  #
#######################################################################
"
  echo "$(printf "%-30s" "Your domain:")${CMSG}${domain}${CEND}"
  echo "$(printf "%-30s" "Caddy Virtualhost conf:")${CMSG}${caddy_install_dir}/conf/vhost/${domain}.conf${CEND}"
}

Apache_log() {
  while :; do echo
    read -e -p "Allow Apache access_log? [y/n]: " access_flag || die_eof
    [ -z "${access_flag}" ] && access_flag=n
    if [[ ! "${access_flag}" =~ ^[y,n]$ ]]; then
      echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
    else
      break
    fi
  done

  if [ "${access_flag}" == 'n' ]; then
    Apache_log='CustomLog "/dev/null" common'
  else
    Apache_log="CustomLog \"${wwwlogs_dir}/${domain}_apache.log\" common"
    echo "You access log file=${wwwlogs_dir}/${domain}_apache.log"
  fi
}

Create_apache_conf() {
  if [ "${Apache_main_ver}" == '24' ]; then
    if [ -e "${php_install_dir}/sbin/php-fpm" ] && [ -n "`grep -E ^LoadModule.*mod_proxy_fcgi.so ${apache_install_dir}/conf/httpd.conf`" ]; then
      Apache_fcgi=$(echo -e "<Files ~ (\\.user.ini|\\.htaccess|\\.git|\\.svn|\\.project|LICENSE|README.md)\$>\n    Order allow,deny\n    Deny from all\n  </Files>\n  <FilesMatch \\.php\$>\n    SetHandler \"proxy:unix:/dev/shm/php${mphp_ver}-cgi.sock|fcgi://localhost\"\n  </FilesMatch>")
    fi
  fi
  [ ! -d ${apache_install_dir}/conf/vhost ] && mkdir ${apache_install_dir}/conf/vhost
  cat > ${apache_install_dir}/conf/vhost/${domain}.conf << EOF
<VirtualHost *:80>
  ServerAdmin admin@example.com
  DocumentRoot "${vhostdir}"
  ServerName ${domain}
  ${Apache_Domain_alias}
  ErrorLog "${wwwlogs_dir}/${domain}_error_apache.log"
  ${Apache_log}
  ${Apache_fcgi}
<Directory "${vhostdir}">
  SetOutputFilter DEFLATE
  Options FollowSymLinks ExecCGI
  ${Apache_grant}
  AllowOverride All
  Order allow,deny
  Allow from all
  DirectoryIndex index.html index.php
</Directory>
</VirtualHost>
EOF
  [ "${apache_ssl_flag}" == 'y' ] && cat >> ${apache_install_dir}/conf/vhost/${domain}.conf << EOF
<VirtualHost *:443>
  ServerAdmin admin@example.com
  DocumentRoot "${vhostdir}"
  ServerName ${domain}
  ${Apache_Domain_alias}
  ${Apache_SSL}
  ErrorLog "${wwwlogs_dir}/${domain}_error_apache.log"
  ${Apache_log}
  ${Apache_fcgi}
<Directory "${vhostdir}">
  SetOutputFilter DEFLATE
  Options FollowSymLinks ExecCGI
  ${Apache_grant}
  AllowOverride All
  Order allow,deny
  Allow from all
  DirectoryIndex index.html index.php
</Directory>
</VirtualHost>
EOF

  echo
  ${apache_install_dir}/bin/apachectl -t
  if [ $? == 0 ]; then
    echo "Restart Apache......"
    ${apache_install_dir}/bin/apachectl -k graceful
  else
    rm -f ${apache_install_dir}/conf/vhost/${domain}.conf
    echo "Create virtualhost ... [${CFAILURE}FAILED${CEND}]"
    exit 1
  fi

  printf "
#######################################################################
# Lemon - Debian 12/13 一键 Web 环境（Nginx/Tengine/OpenResty/Caddy） #
# https://github.com/misakacoo/lemon                                  #
#######################################################################
"
  echo "$(printf "%-30s" "Your domain:")${CMSG}${domain}${CEND}"
  echo "$(printf "%-30s" "Virtualhost conf:")${CMSG}${apache_install_dir}/conf/vhost/${domain}.conf${CEND}"
  echo "$(printf "%-30s" "Directory of:")${CMSG}${vhostdir}${CEND}"
  Print_SSL
}

Create_nginx_apache_modphp_conf() {
  # Nginx/Tengine/OpenResty
  [ ! -d ${web_install_dir}/conf/vhost ] && mkdir ${web_install_dir}/conf/vhost
  cat > ${web_install_dir}/conf/vhost/${domain}.conf << EOF
server {
  ${Nginx_conf}
  server_name ${domain}${moredomainame};
  ${Nginx_log}
  index index.html index.htm index.php;
  root ${vhostdir};
  ${Nginx_redirect}
  ${anti_hotlinking}
  location / {
    try_files \$uri @apache;
  }
  location @apache {
    proxy_pass http://127.0.0.1:88;
    include proxy.conf;
  }
  location ~ .*\.(php|php5|cgi|pl)?$ {
    proxy_pass http://127.0.0.1:88;
    include proxy.conf;
  }
  location ~ .*\.(gif|jpg|jpeg|png|bmp|swf|flv|mp4|ico)$ {
    expires 30d;
    access_log off;
  }
  location ~ \.(js|css)$ {
    expires 7d;
    access_log off;
  }
  location ~ /(\.user\.ini|\.ht|\.git|\.svn|\.project|LICENSE|README\.md) {
    deny all;
  }
  location /.well-known {
    allow all;
  }
}
EOF

  [ "${https_flag}" == 'y' ] && sed -i "s@^  root.*;@&\n  if (\$ssl_protocol = \"\") { return 301 https://\$host\$request_uri; }@" ${web_install_dir}/conf/vhost/${domain}.conf

  echo
  ${web_install_dir}/sbin/nginx -t
  if [ $? == 0 ]; then
    echo "Reload Nginx......"
    ${web_install_dir}/sbin/nginx -s reload
  else
    rm -f ${web_install_dir}/conf/vhost/${domain}.conf
    echo "Create virtualhost ... [${CFAILURE}FAILED${CEND}]"
  fi

  # Apache
  if [ "${Apache_main_ver}" == '24' ]; then
    if [ -e "${php_install_dir}/sbin/php-fpm" ] && [ -n "`grep -E ^LoadModule.*mod_proxy_fcgi.so ${apache_install_dir}/conf/httpd.conf`" ]; then
      Apache_fcgi=$(echo -e "<Files ~ (\\.user.ini|\\.htaccess|\\.git|\\.svn|\\.project|LICENSE|README.md)\$>\n    Order allow,deny\n    Deny from all\n  </Files>\n  <FilesMatch \\.php\$>\n    SetHandler \"proxy:unix:/dev/shm/php${mphp_ver}-cgi.sock|fcgi://localhost\"\n  </FilesMatch>")
    fi
  fi
  [ ! -d ${apache_install_dir}/conf/vhost ] && mkdir ${apache_install_dir}/conf/vhost
  cat > ${apache_install_dir}/conf/vhost/${domain}.conf << EOF
<VirtualHost *:88>
  ServerAdmin admin@example.com
  DocumentRoot "${vhostdir}"
  ServerName ${domain}
  ${Apache_Domain_alias}
  ${Apache_SSL}
  ErrorLog "${wwwlogs_dir}/${domain}_error_apache.log"
  ${Apache_log}
  ${Apache_fcgi}
<Directory "${vhostdir}">
  SetOutputFilter DEFLATE
  Options FollowSymLinks ExecCGI
  ${Apache_grant}
  AllowOverride All
  Order allow,deny
  Allow from all
  DirectoryIndex index.html index.php
</Directory>
</VirtualHost>
EOF

  echo
  ${apache_install_dir}/bin/apachectl -t
  if [ $? == 0 ]; then
    echo "Restart Apache......"
    ${apache_install_dir}/bin/apachectl -k graceful
  else
    rm -f ${apache_install_dir}/conf/vhost/${domain}.conf
    exit 1
  fi

  printf "
#######################################################################
# Lemon - Debian 12/13 一键 Web 环境（Nginx/Tengine/OpenResty/Caddy） #
# https://github.com/misakacoo/lemon                                  #
#######################################################################
"
  echo "$(printf "%-30s" "Your domain:")${CMSG}${domain}${CEND}"
  echo "$(printf "%-30s" "Nginx Virtualhost conf:")${CMSG}${web_install_dir}/conf/vhost/${domain}.conf${CEND}"
  echo "$(printf "%-30s" "Apache Virtualhost conf:")${CMSG}${apache_install_dir}/conf/vhost/${domain}.conf${CEND}"
  echo "$(printf "%-30s" "Directory of:")${CMSG}${vhostdir}${CEND}"
  Print_SSL
}

Add_Vhost() {
  if [ -e "${caddy_install_dir}/bin/caddy" ] && [[ "${web_install_dir}" =~ caddy || ! -e "${web_install_dir}/sbin/nginx" ]]; then
    Choose_ENV
    Input_Add_domain
    if [ "${proxy_flag}" == "y" ]; then
      Input_Add_proxy
      Caddy_log
      Create_caddy_proxy_conf
    else
      Caddy_log
      Create_caddy_php_conf
    fi
  elif [ -e "${web_install_dir}/sbin/nginx" -a ! -e "${apache_install_dir}/bin/httpd" ]; then
    Choose_ENV
    Input_Add_domain
    Nginx_anti_hotlinking
    if [ "${proxy_flag}" == "y" ]; then
        Input_Add_proxy
        Create_nginx_proxy_conf
      else
        Nginx_rewrite
        Nginx_log
        Create_nginx_phpfpm_conf
    fi
  elif [ ! -e "${web_install_dir}/sbin/nginx" -a -e "${apache_install_dir}/bin/httpd" ]; then
    Choose_ENV
    Input_Add_domain
    Apache_log
    Create_apache_conf
  elif [ -e "${web_install_dir}/sbin/nginx" -a -e "${apache_install_dir}/bin/httpd" ]; then
    Choose_ENV
    Input_Add_domain
    Nginx_anti_hotlinking
    Nginx_log
    Apache_log
    Create_nginx_apache_modphp_conf
  elif [ -e "${caddy_install_dir}/bin/caddy" ]; then
    Choose_ENV
    Input_Add_domain
    if [ "${proxy_flag}" == "y" ]; then
      Input_Add_proxy
      Caddy_log
      Create_caddy_proxy_conf
    else
      Caddy_log
      Create_caddy_php_conf
    fi
  else
    echo "Error! ${CFAILURE}Web server${CEND} not found!"
  fi
}

Del_NGX_Vhost() {
  if [ -e "${web_install_dir}/sbin/nginx" ]; then
    [ -d "${web_install_dir}/conf/vhost" ] && Domain_List=$(ls ${web_install_dir}/conf/vhost | sed "s@.conf@@g")
    if [ -n "${Domain_List}" ]; then
      echo
      echo "Virtualhost list:"
      echo ${CMSG}${Domain_List}${CEND}
        while :; do echo
          if [ -n "${ARG_DOMAIN}" ]; then
            domain="${ARG_DOMAIN}"
              # 参数化传进来的域名要当场校验：后面这个 while 循环不会再有 read，
              # 非法值会原地无限刷 invalid（真机实测 rc=124 卡死）
              if ! Is_Valid_Domain "${domain}"; then
                echo "${CFAILURE}域名不合法：${domain}${CEND}" >&2
                exit 1
              fi
          else
            read -e -p "Please input a domain you want to delete: " domain \
              || die_eof
          fi
          if ! Is_Valid_Domain "${domain}"; then
            echo "${CWARNING}域名不合法：${domain}${CEND}"
          else
            if [ -e "${web_install_dir}/conf/vhost/${domain}.conf" ]; then
              Directory=$(grep '^  root' ${web_install_dir}/conf/vhost/${domain}.conf | head -1 | awk -F'[ ;]' '{print $(NF-1)}')
              # magento2 的 root 指向站点内 pub 子目录，站点根是其父目录
              [ "$(basename "${Directory}")" == 'pub' ] && Directory=$(dirname "${Directory}")
              rm -f ${web_install_dir}/conf/vhost/${domain}.conf
              [ -e "${web_install_dir}/conf/ssl/${domain}.crt" ] && rm -f ${web_install_dir}/conf/ssl/${domain}.{crt,key,csr}
              ${web_install_dir}/sbin/nginx -s reload
              while :; do echo
                read -e -p "Do you want to delete Virtul Host directory? [y/n]: " Del_Vhost_wwwroot_flag || die_eof
                [ -z "${Del_Vhost_wwwroot_flag}" ] && Del_Vhost_wwwroot_flag=n
                if [[ ! ${Del_Vhost_wwwroot_flag} =~ ^[y,n]$ ]]; then
                  echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
                else
                  break
                fi
              done
              if [ "${Del_Vhost_wwwroot_flag}" == 'y' ]; then
		if [ "${quiet_flag}" != 'y' ]; then
                  echo "Press Ctrl+c to cancel or Press any key to continue..."
                  char=$(get_char)
		fi
                if ! Safe_Rm_Dir "${Directory}"; then
                  echo "${CWARNING}站点目录未删除（原因见上），站点配置已删除${CEND}"
                fi
              fi
              echo
              [ -d ~/.acme.sh/${domain} ] && ~/.acme.sh/acme.sh --force --remove -d ${domain} > /dev/null 2>&1
              [ -d ~/.acme.sh/${domain}_ecc ] && ~/.acme.sh/acme.sh --force --remove --ecc -d ${domain} > /dev/null 2>&1
              echo "${CMSG}Domain: ${domain} has been deleted.${CEND}"
              echo
            else
              echo "${CWARNING}Virtualhost: ${domain} was not exist! ${CEND}"
            fi
            break
          fi
        done
    else
      echo "${CWARNING}Virtualhost was not exist! ${CEND}"
    fi
  fi
}

Del_Caddy_Vhost() {
  if [ -e "${caddy_install_dir}/bin/caddy" ]; then
    [ -d "${caddy_install_dir}/conf/vhost" ] && Domain_List=$(ls ${caddy_install_dir}/conf/vhost | sed "s@.conf@@g")
    if [ -n "${Domain_List}" ]; then
      echo
      echo "Virtualhost list:"
      echo ${CMSG}${Domain_List}${CEND}
      while :; do echo
        if [ -n "${ARG_DOMAIN}" ]; then
            domain="${ARG_DOMAIN}"
              # 参数化传进来的域名要当场校验：后面这个 while 循环不会再有 read，
              # 非法值会原地无限刷 invalid（真机实测 rc=124 卡死）
              if ! Is_Valid_Domain "${domain}"; then
                echo "${CFAILURE}域名不合法：${domain}${CEND}" >&2
                exit 1
              fi
          else
            read -e -p "Please input a domain you want to delete: " domain \
              || die_eof
          fi
        if ! Is_Valid_Domain "${domain}"; then
          echo "${CWARNING}域名不合法：${domain}${CEND}"
        else
          if [ -e "${caddy_install_dir}/conf/vhost/${domain}.conf" ]; then
            Directory=$(grep 'root \*' ${caddy_install_dir}/conf/vhost/${domain}.conf | head -1 | sed 's@^.*root \* @@g')
            rm -f ${caddy_install_dir}/conf/vhost/${domain}.conf
            # 与 nginx/apache 分支一致：一并清理签发时落盘的证书私钥
            [ -e "${caddy_install_dir}/conf/ssl/${domain}.crt" ] && rm -f ${caddy_install_dir}/conf/ssl/${domain}.{crt,key,csr}
            Reload_Caddy
            if [ -n "${Directory}" -a -d "${Directory}" ]; then
              while :; do echo
                read -e -p "Do you want to delete Virtul Host directory? [y/n]: " Del_Vhost_wwwroot_flag || die_eof
                [ -z "${Del_Vhost_wwwroot_flag}" ] && Del_Vhost_wwwroot_flag=n
                if [[ ! ${Del_Vhost_wwwroot_flag} =~ ^[y,n]$ ]]; then
                  echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
                else
                  break
                fi
              done

              if [ "${Del_Vhost_wwwroot_flag}" == 'y' ]; then
                if [ "${quiet_flag}" != 'y' ]; then
                  echo "Press Ctrl+c to cancel or Press any key to continue..."
                  char=$(get_char)
                fi
                if ! Safe_Rm_Dir "${Directory}"; then
                  echo "${CWARNING}站点目录未删除（原因见上），站点配置已删除${CEND}"
                fi
              fi
            fi
            echo
            [ -d ~/.acme.sh/${domain} ] && ~/.acme.sh/acme.sh --force --remove -d ${domain} > /dev/null 2>&1
            [ -d ~/.acme.sh/${domain}_ecc ] && ~/.acme.sh/acme.sh --force --remove --ecc -d ${domain} > /dev/null 2>&1
            echo "${CSUCCESS}Domain: ${domain} has been deleted.${CEND}"
            echo
          else
            echo "${CWARNING}Virtualhost: ${domain} was not exist! ${CEND}"
          fi
          break
        fi
      done
    fi
  fi
}

Del_Apache_Vhost() {
  if [ -e "${apache_install_dir}/bin/httpd" ]; then
    if [ -e "${web_install_dir}/sbin/nginx" ]; then
      rm -f ${apache_install_dir}/conf/vhost/${domain}.conf
      ${apache_install_dir}/bin/apachectl -k graceful
    else
      Domain_List=$(ls ${apache_install_dir}/conf/vhost | grep -v '0.conf' | sed "s@.conf@@g")
      if [ -n "${Domain_List}" ]; then
        echo
        echo "Virtualhost list:"
        echo ${CMSG}${Domain_List}${CEND}
        while :; do echo
          if [ -n "${ARG_DOMAIN}" ]; then
            domain="${ARG_DOMAIN}"
              # 参数化传进来的域名要当场校验：后面这个 while 循环不会再有 read，
              # 非法值会原地无限刷 invalid（真机实测 rc=124 卡死）
              if ! Is_Valid_Domain "${domain}"; then
                echo "${CFAILURE}域名不合法：${domain}${CEND}" >&2
                exit 1
              fi
          else
            read -e -p "Please input a domain you want to delete: " domain \
              || die_eof
          fi
          if ! Is_Valid_Domain "${domain}"; then
            echo "${CWARNING}域名不合法：${domain}${CEND}"
          else
            if [ -e "${apache_install_dir}/conf/vhost/${domain}.conf" ]; then
              Directory=$(grep '^<Directory ' ${apache_install_dir}/conf/vhost/${domain}.conf | head -1 | awk -F'"' '{print $2}')
              rm -f ${apache_install_dir}/conf/vhost/${domain}.conf
              [ -e "${apache_install_dir}/conf/ssl/${domain}.crt" ] && rm -f ${apache_install_dir}/conf/ssl/${domain}.{crt,key,csr}
              ${apache_install_dir}/bin/apachectl -k graceful
              while :; do echo
                read -e -p "Do you want to delete Virtul Host directory? [y/n]: " Del_Vhost_wwwroot_flag || die_eof
                [ -z "${Del_Vhost_wwwroot_flag}" ] && Del_Vhost_wwwroot_flag=n
                if [[ ! ${Del_Vhost_wwwroot_flag} =~ ^[y,n]$ ]]; then
                  echo "${CWARNING}input error! Please only input 'y' or 'n'${CEND}"
                else
                  break
                fi
              done

              if [ "${Del_Vhost_wwwroot_flag}" == 'y' ]; then
		if [ "${quiet_flag}" != 'y' ]; then
                  echo "Press Ctrl+c to cancel or Press any key to continue..."
                  char=$(get_char)
		fi
                if ! Safe_Rm_Dir "${Directory}"; then
                  echo "${CWARNING}站点目录未删除（原因见上），站点配置已删除${CEND}"
                fi
              fi
              [ -d ~/.acme.sh/${domain} ] && ~/.acme.sh/acme.sh --force --remove -d ${domain} > /dev/null 2>&1
              [ -d ~/.acme.sh/${domain}_ecc ] && ~/.acme.sh/acme.sh --force --remove --ecc -d ${domain} > /dev/null 2>&1
              echo "${CSUCCESS}Domain: ${domain} has been deleted.${CEND}"
            else
              echo "${CWARNING}Virtualhost: ${domain} was not exist! ${CEND}"
            fi
            break
          fi
        done

      else
        echo "${CWARNING}Virtualhost was not exist! ${CEND}"
      fi
    fi
  fi
}

List_Vhost() {
  Domain_List_Nginx=$( [ -d "${web_install_dir}/conf/vhost" ] && ls ${web_install_dir}/conf/vhost | sed "s@.conf@@g" )
  Domain_List_Caddy=$( [ -d "${caddy_install_dir}/conf/vhost" ] && ls ${caddy_install_dir}/conf/vhost | sed "s@.conf@@g" )
  Domain_List_Apache=$( [ -e "${apache_install_dir}/bin/httpd" ] && ls ${apache_install_dir}/conf/vhost | grep -v '0.conf' | sed "s@.conf@@g" )
  
  Domain_List=$(echo "${Domain_List_Nginx} ${Domain_List_Caddy} ${Domain_List_Apache} " | tr ' ' '\n' | sort | uniq | xargs)
  
  if [ -n "${Domain_List}" ]; then
    echo
    echo "Virtualhost list:"
    for D in ${Domain_List}; do echo ${CMSG}${D}${CEND}; done
  else
    echo "${CWARNING}Virtualhost was not exist! ${CEND}"
  fi
}

# 添加 / 删除虚拟主机全程靠 read 收集信息，没有可以一次性给全的命令行参数。
# stdin 不是终端时（重定向、管道、nohup、自动化调用）read 会立刻返回 EOF，
# 下面那些 while : 循环拿不到值又不 break，就变成空转 —— 实测能烧满一个核跑一小时。
# 非交互（管道 / 重定向 / 非 tty）时把 read 变成「返回空串」：
# 各提示会落到下面的默认值，而不是卡在 EOF 上反复刷 input error。
# 参数化用法：bash vhost.sh --add foo.com --httponly
if [ ! -t 0 ]; then
  read() {
    local _last="${!#}"
    case "${_last}" in
      -*) return 0 ;;
    esac
    printf -v "${_last}" '%s' ''
    return 0
  }
fi

# 域名白名单：只允许常规域名/子域，总长 <=253。
# 域名会被拼进 nginx 配置、$wwwroot_dir/$domain 路径、sed 表达式与 acme.sh 参数，
# 放行 "../../etc" 或 "a.com; } server{" 这类输入等于开放路径穿越与配置注入。
# 原来只有「新增站点」用严格正则，多域名与三处「删除站点」都只判断「含不含点」，是缺口。
Is_Valid_Domain() {
  local d="$1" n
  [ -n "${d}" ] || return 1
  n=$(printf '%s' "${d}" | wc -c)
  [ "${n}" -le 253 ] || return 1
  [[ "${d}" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$ ]]
}

need_tty() {
  [ -t 0 ] && return 0
  echo "${CFAILURE}非交互环境：${1}需要终端输入，请在 SSH 终端里执行${CEND}" >&2
  exit 1
}

# 交互中断（EOF）统一出口：文案一致 + 顺手清掉本次新建但没配上 conf 的站点目录，
# 避免留下「目录在、配置没写」的半成品（真机实测 Ctrl-D 后会留孤儿目录）。
CREATED_VHOSTDIR=''
CREATED_VHOST_DOMAIN=''
die_eof() {
  echo
  echo "${CFAILURE}输入已耗尽（EOF），无法继续交互。${CEND}"
  echo "${CWARNING}参数化用法：bash vhost.sh --add <域名> --httponly${CEND}"
  if [ -n "${CREATED_VHOSTDIR}" ] && [ -d "${CREATED_VHOSTDIR}" ]; then
    if [ ! -e "${web_install_dir}/conf/vhost/${CREATED_VHOST_DOMAIN}.conf" ] &&        [ ! -e "${caddy_install_dir}/conf/vhost/${CREATED_VHOST_DOMAIN}.conf" ] &&        [ ! -e "${apache_install_dir}/conf/vhost/${CREATED_VHOST_DOMAIN}.conf" ]; then
      rm -rf "${CREATED_VHOSTDIR}"
      echo "${CWARNING}已清理未完成的站点目录：${CREATED_VHOSTDIR}${CEND}"
    fi
  fi
  exit 1
}

if [ ${ARG_NUM} == 0 ]; then
    [ -z "${ARG_DOMAIN}" ] && need_tty "添加虚拟主机"
    Add_Vhost
else
  if [ "${add_flag}" == 'y' -o "${proxy_flag}" == 'y' -o "${sslquiet_flag}" == 'y' ]; then
    [ -z "${ARG_DOMAIN}" ] && need_tty "添加虚拟主机"
    Add_Vhost
  fi
  [ "${list_flag}" == 'y' ] && List_Vhost
  if [ "${delete_flag}" == 'y' ]; then
    [ -z "${ARG_DOMAIN}" ] && need_tty "删除虚拟主机"
    Del_NGX_Vhost; Del_Apache_Vhost; Del_Caddy_Vhost
  fi
fi

# 结尾显式返回 0：上面最后一条基本都是 `[ ... ] && cmd`，条件不成立时
# 脚本会以 1 退出，自动化调用方会误判成失败
exit 0
