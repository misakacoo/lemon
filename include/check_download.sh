#!/bin/bash
# Author:  Alpha Eva <kaneawk AT gmail.com>
#
# Notes: Lemon for Debian 12 / 13
#
# Project home page:
#       https://github.com/misakacoo/lemon

checkDownload() {
  # src 目录可能因分发方式（打包排除 .gitkeep、手工解包）缺失，先兜底创建：
  # 所有组件脚本都假定 cwd 在 src 内取相对路径，pushd 失败会导致 cwd 漂移、
  # 后续 tar 全部找不到包（真机 d12/d13 复现过）
  [ -d "${lemon_dir}/src" ] || mkdir -p ${lemon_dir}/src
  pushd ${lemon_dir}/src > /dev/null
  # icu：Debian 12 / 13 自带的 ICU 是 72 / 76，PHP 的 intl 直接用系统库，不再下载 icu4c 自建

  # 给 nginx / tengine / openresty 静态编译用的 OpenSSL（版本见 versions.txt 的 openssl_build_ver）
  if [[ ${nginx_option} =~ ^[1-3]$ ]]; then
      echo "Download openSSL for web server..."
      src_url=${mirror_link}/src/openssl-${openssl_build_ver}.tar.gz && Download_src
  fi

  # jemalloc（MySQL 系含 Percona 8.4）
  if [[ ${nginx_option} =~ ^[1-3]$ ]] || [[ "${db_option}" =~ ^([0-6]|9)$ ]]; then
    echo "Download jemalloc..."
    src_url=${mirror_link}/src/jemalloc-${jemalloc_ver}.tar.bz2 && Download_src
  fi

  # pcre
  if [[ "${nginx_option}" =~ ^[1-3]$ ]] || [ "${apache_flag}" == 'y' ]; then
    echo "Download pcre2..."
    src_url=${mirror_link}/src/pcre2-${pcre2_ver}.tar.gz && Download_src
  fi

  # nginx 的 brotli 压缩模块（ngx_brotli）与其依赖的 brotli 源码；
  # 取不到时 nginx.sh 会跳过该模块继续编译，不影响主流程
  if [[ "${nginx_option}" =~ ^[1-3]$ ]]; then
    src_url=${mirror_link}/src/ngx_brotli.tar.gz && Download_src_soft
    src_url=${mirror_link}/src/brotli-${brotli_ver}.tar.gz && Download_src_soft
  fi

  # nginx/tengine/openresty
  case "${nginx_option}" in
    1)
      echo "Download nginx..."
      src_url=${mirror_link}/src/nginx-${nginx_ver}.tar.gz && Download_src
      ;;
    2)
      echo "Download tengine..."
      src_url=${mirror_link}/src/tengine-${tengine_ver}.tar.gz && Download_src
      ;;
    3)
      echo "Download openresty..."
      src_url=${mirror_link}/src/openresty-${openresty_ver}.tar.gz && Download_src
      ;;
  esac

  # if nginx_option=4 download caddy
  if [ "${nginx_option}" == '4' ]; then
    echo "Download caddy ${caddy_ver}"
    src_url=${mirror_link}/src/caddy_${caddy_ver}_linux_${SYS_ARCH}.tar.gz && Download_src
  fi

  # caddy
  if [ "${caddy_flag}" == 'y' ]; then
    echo "Download caddy ${caddy_ver}"
    src_url=${mirror_link}/src/caddy_${caddy_ver}_linux_${SYS_ARCH}.tar.gz && Download_src
  fi

  # apache
  if [ "${apache_flag}" == 'y' ]; then
    echo "Download apache 2.4..."
    src_url=${mirror_link}/src/httpd-${apache_ver}.tar.gz && Download_src
    src_url=${mirror_link}/src/apr-${apr_ver}.tar.gz && Download_src
    src_url=${mirror_link}/src/apr-util-${apr_util_ver}.tar.gz && Download_src
    src_url=${mirror_link}/src/nghttp2-${nghttp2_ver}.tar.gz && Download_src
  fi

  if [[ "${db_option}" =~ ^[0-9]$ ]]; then
    if [[ "${db_option}" =~ ^([0-6]|9)$ ]] && [ "${dbinstallmethod}" == "2" ]; then
      # 编号 0=MySQL5.7 1=MySQL8.0 2=MySQL8.4 6=Percona8.0 9=Percona8.4
      [[ "${db_option}" =~ ^0$ ]] && boost_ver=${boost_oldver}
      [[ "${db_option}" =~ ^1$ ]] && boost_ver=${boost_mysql80_ver}
      [[ "${db_option}" =~ ^2$ ]] && boost_ver=${boost_mysql84_ver}
      [[ "${db_option}" =~ ^6$ ]] && boost_ver=${boost_percona_ver}
      [[ "${db_option}" =~ ^9$ ]] && boost_ver=${boost_percona84_ver}
      echo "Download boost..."
      DOWN_ADDR_BOOST=${mirror_link}/src
      boostVersion2=$(echo ${boost_ver} | awk -F. '{print $1"_"$2"_"$3}')
      src_url=${DOWN_ADDR_BOOST}/boost_${boostVersion2}.tar.gz && Download_src
    fi

    case "${db_option}" in
      0)
        # MySQL 5.7（官方最终版，只提供 glibc2.12 构建，Debian 12/13 可直接用）
          DOWN_ADDR_MYSQL=${mirror_link}/src
          DOWN_ADDR_MYSQL_BK=${mirror_link}/src

        if [ "${dbinstallmethod}" == '1' ]; then
          echo "Download MySQL 5.7 binary package..."
          FILE_NAME=mysql-${mysql57_ver}-linux-glibc2.12-x86_64.tar.gz
        elif [ "${dbinstallmethod}" == '2' ]; then
          echo "Download MySQL 5.7 source package..."
          FILE_NAME=mysql-${mysql57_ver}.tar.gz
        fi
        # start download
        src_url=${DOWN_ADDR_MYSQL}/${FILE_NAME} && Download_src
        # 校验文件某些版本官方没提供（如 mysql-8.0.45），取不到就跳过校验
        src_url=${DOWN_ADDR_MYSQL}/${FILE_NAME}.md5 && Download_src_soft
        MYSQL_TAR_MD5=$(awk -v f="${FILE_NAME}" '$2 == f {print $1; exit}' ${FILE_NAME}.md5 2>/dev/null)
        if [ -n "${MYSQL_TAR_MD5}" ] && [ "$(md5sum ${FILE_NAME} | awk '{print $1}')" != "${MYSQL_TAR_MD5}" ]; then
          tryDlCount=0
          while [ "$(md5sum ${FILE_NAME} | awk '{print $1}')" != "${MYSQL_TAR_MD5}" ]; do
            wget -c ${DOWN_ADDR_MYSQL}/${FILE_NAME}
            let "tryDlCount++"
            [ "$(md5sum ${FILE_NAME} | awk '{print $1}')" == "${MYSQL_TAR_MD5}" -o "${tryDlCount}" == '6' ] && break || continue
          done
          if [ "${tryDlCount}" == '6' ]; then
            echo "${CFAILURE}${FILE_NAME} 校验失败，请检查镜像站或手动下载到 ${lemon_dir}/src${CEND}"
            exit 1;
          fi
        fi
        ;;
      1)
        # MySQL 8.0
          DOWN_ADDR_MYSQL=${mirror_link}/src
          DOWN_ADDR_MYSQL_BK=${mirror_link}/src

        if [ "${dbinstallmethod}" == '1' ]; then
          echo "Download MySQL 8.0 binary package..."
          # 8.0.45 起 Oracle 也停发了 glibc2.17 构建，只剩 glibc2.28
          # （Debian 12 是 glibc 2.36、Debian 13 是 2.41，都满足）
          FILE_NAME=mysql-${mysql80_ver}-linux-glibc2.28-x86_64.tar.xz
        elif [ "${dbinstallmethod}" == '2' ]; then
          echo "Download MySQL 8.0 source package..."
          FILE_NAME=mysql-${mysql80_ver}.tar.gz
        fi
        # start download
        src_url=${DOWN_ADDR_MYSQL}/${FILE_NAME} && Download_src
        # 校验文件某些版本官方没提供（如 mysql-8.0.45），取不到就跳过校验
        src_url=${DOWN_ADDR_MYSQL}/${FILE_NAME}.md5 && Download_src_soft
        MYSQL_TAR_MD5=$(awk -v f="${FILE_NAME}" '$2 == f {print $1; exit}' ${FILE_NAME}.md5 2>/dev/null)
        if [ -n "${MYSQL_TAR_MD5}" ] && [ "$(md5sum ${FILE_NAME} | awk '{print $1}')" != "${MYSQL_TAR_MD5}" ]; then
          tryDlCount=0
          while [ "$(md5sum ${FILE_NAME} | awk '{print $1}')" != "${MYSQL_TAR_MD5}" ]; do
            wget -c ${DOWN_ADDR_MYSQL}/${FILE_NAME}
            let "tryDlCount++"
            [ "$(md5sum ${FILE_NAME} | awk '{print $1}')" == "${MYSQL_TAR_MD5}" -o "${tryDlCount}" == '6' ] && break || continue
          done
          if [ "${tryDlCount}" == '6' ]; then
            echo "${CFAILURE}${FILE_NAME} 校验失败，请检查镜像站或手动下载到 ${lemon_dir}/src${CEND}"
            exit 1;
          fi
        fi
        ;;
      2)
        # MySQL 8.4
          DOWN_ADDR_MYSQL=${mirror_link}/src
          DOWN_ADDR_MYSQL_BK=${mirror_link}/src
          DOWN_ADDR_MYSQL_BK2=${mirror_link}/src

        if [ "${dbinstallmethod}" == '1' ]; then
          echo "Download MySQL 8.4 binary package..."
          # 8.4 线 Oracle 只提供 glibc2.28 构建（glibc2.17 已停发），
          # 因此目标系统 glibc 需 >= 2.28（Debian 12 是 2.36，满足）
          FILE_NAME=mysql-${mysql84_ver}-linux-glibc2.28-x86_64.tar.xz
        elif [ "${dbinstallmethod}" == '2' ]; then
          echo "Download MySQL 8.4 source package..."
          FILE_NAME=mysql-${mysql84_ver}.tar.gz
        fi
        # start download
        src_url=${DOWN_ADDR_MYSQL}/${FILE_NAME} && Download_src
        # 校验文件某些版本官方没提供（如 mysql-8.0.45），取不到就跳过校验
        src_url=${DOWN_ADDR_MYSQL}/${FILE_NAME}.md5 && Download_src_soft
        MYSQL_TAR_MD5=$(awk -v f="${FILE_NAME}" '$2 == f {print $1; exit}' ${FILE_NAME}.md5 2>/dev/null)
        if [ -n "${MYSQL_TAR_MD5}" ] && [ "$(md5sum ${FILE_NAME} | awk '{print $1}')" != "${MYSQL_TAR_MD5}" ]; then
          tryDlCount=0
          while [ "$(md5sum ${FILE_NAME} | awk '{print $1}')" != "${MYSQL_TAR_MD5}" ]; do
            wget -c ${DOWN_ADDR_MYSQL}/${FILE_NAME}
            let "tryDlCount++"
            [ "$(md5sum ${FILE_NAME} | awk '{print $1}')" == "${MYSQL_TAR_MD5}" -o "${tryDlCount}" == '6' ] && break || continue
          done
          if [ "${tryDlCount}" == '6' ]; then
            echo "${CFAILURE}${FILE_NAME} 校验失败，请检查镜像站或手动下载到 ${lemon_dir}/src${CEND}"
            exit 1;
          fi
        fi
        ;;
      [3-5])
	case "${db_option}" in
          3)
            mariadb_ver=${mariadb1011_ver}
	    ;;
          4)
            mariadb_ver=${mariadb114_ver}
	    ;;
          5)
            mariadb_ver=${mariadb118_ver}
	    ;;
        esac

        if [ "${dbinstallmethod}" == '1' ]; then
          FILE_NAME=mariadb-${mariadb_ver}-linux-systemd-x86_64.tar.gz
	  FILE_TYPE=bintar-linux-systemd-x86_64
        elif [ "${dbinstallmethod}" == '2' ]; then
          FILE_NAME=mariadb-${mariadb_ver}.tar.gz
	  FILE_TYPE=source
        fi

          DOWN_ADDR_MARIADB=${mirror_link}/src

        echo "Download MariaDB ${FILE_NAME} package..."
        src_url=${DOWN_ADDR_MARIADB}/${FILE_NAME} && Download_src
        # 镜像上的 .md5 是官方的 md5sums.txt，里面有多行，必须 grep 出自己那一条
        src_url=${DOWN_ADDR_MARIADB}/${FILE_NAME}.md5 && Download_src_soft
        MARAIDB_TAR_MD5=$(awk -v f="${FILE_NAME}" '$2 == f {print $1; exit}' ${FILE_NAME}.md5 2>/dev/null)
        if [ -n "${MARAIDB_TAR_MD5}" ] && [ "$(md5sum ${FILE_NAME} | awk '{print $1}')" != "${MARAIDB_TAR_MD5}" ]; then
          tryDlCount=0
          while [ "$(md5sum ${FILE_NAME} | awk '{print $1}')" != "${MARAIDB_TAR_MD5}" ]; do
            wget -c ${DOWN_ADDR_MARIADB}/${FILE_NAME}
            let "tryDlCount++"
            [ "$(md5sum ${FILE_NAME} | awk '{print $1}')" == "${MARAIDB_TAR_MD5}" -o "${tryDlCount}" == '6' ] && break || continue
          done
          if [ "${tryDlCount}" == '6' ]; then
            echo "${CFAILURE}${FILE_NAME} 校验失败，请检查镜像站或手动下载到 ${lemon_dir}/src${CEND}"
            exit 1;
          fi
        fi
        ;;
      6)
        # Percona 8.0
        if [ "${dbinstallmethod}" == '1' ]; then
          echo "Download Percona 8.0 binary package..."
          FILE_NAME=Percona-Server-${percona80_ver}-Linux.x86_64.glibc2.28.tar.gz
          DOWN_ADDR_PERCONA=${mirror_link}/src
        elif [ "${dbinstallmethod}" == '2' ]; then
          echo "Download Percona 8.0 source package..."
          FILE_NAME=percona-server-${percona80_ver}.tar.gz
            DOWN_ADDR_PERCONA=${mirror_link}/src
        fi
        # start download
        src_url=${DOWN_ADDR_PERCONA}/${FILE_NAME} && Download_src
        # Percona 只给二进制包提供 .sha256sum，源码包没有校验文件
        src_url=${mirror_link}/src/${FILE_NAME}.sha256sum && Download_src_soft
        PERCONA_TAR_SHA=$(awk -v f="${FILE_NAME}" '$2 == f {print $1; exit}' ${FILE_NAME}.sha256sum 2>/dev/null)
        if [ -n "${PERCONA_TAR_SHA}" ] && [ "$(sha256sum ${FILE_NAME} | awk '{print $1}')" != "${PERCONA_TAR_SHA}" ]; then
          tryDlCount=0
          while [ "$(sha256sum ${FILE_NAME} | awk '{print $1}')" != "${PERCONA_TAR_SHA}" ]; do
            wget -c ${DOWN_ADDR_PERCONA}/${FILE_NAME}
            let "tryDlCount++"
            [ "$(sha256sum ${FILE_NAME} | awk '{print $1}')" == "${PERCONA_TAR_SHA}" -o "${tryDlCount}" == '6' ] && break || continue
          done
          if [ "${tryDlCount}" == '6' ]; then
            echo "${CFAILURE}${FILE_NAME} 校验失败，请检查镜像站或手动下载到 ${lemon_dir}/src${CEND}"
            exit 1;
          fi
        fi
        # 同 8.4：EL8 构建的包依赖 openssl 1.1
        if [ "${dbinstallmethod}" == '1' ]; then
          src_url=${mirror_link}/src/percona-compat-openssl11.tar.gz && Download_src
        fi
        ;;
      9)
        # Percona 8.4 LTS
        if [ "${dbinstallmethod}" == '1' ]; then
          echo "Download Percona 8.4 binary package..."
          FILE_NAME=Percona-Server-${percona84_ver}-Linux.x86_64.glibc2.28.tar.gz
          DOWN_ADDR_PERCONA=${mirror_link}/src
        elif [ "${dbinstallmethod}" == '2' ]; then
          echo "Download Percona 8.4 source package..."
          FILE_NAME=percona-server-${percona84_ver}.tar.gz
          DOWN_ADDR_PERCONA=${mirror_link}/src
        fi
        src_url=${DOWN_ADDR_PERCONA}/${FILE_NAME} && Download_src
        src_url=${mirror_link}/src/${FILE_NAME}.sha256sum && Download_src_soft
        PERCONA_TAR_SHA=$(awk -v f="${FILE_NAME}" '$2 == f {print $1; exit}' ${FILE_NAME}.sha256sum 2>/dev/null)
        if [ -n "${PERCONA_TAR_SHA}" ] && [ "$(sha256sum ${FILE_NAME} | awk '{print $1}')" != "${PERCONA_TAR_SHA}" ]; then
          echo "${CFAILURE}${FILE_NAME} 校验失败，请检查镜像站或手动下载到 ${lemon_dir}/src${CEND}"
          exit 1;
        fi
        # 二进制包基于 EL8，需要 openssl 1.1 的 libssl.so.1.1；Debian 12/13 只有 3.x
        if [ "${dbinstallmethod}" == '1' ]; then
          src_url=${mirror_link}/src/percona-compat-openssl11.tar.gz && Download_src
        fi
        ;;
      7)
        FILE_NAME=postgresql-${pgsql_ver}.tar.gz
          DOWN_ADDR_PGSQL=${mirror_link}/src
          DOWN_ADDR_PGSQL_BK=${mirror_link}/src
        
        src_url=${DOWN_ADDR_PGSQL}/${FILE_NAME} && Download_src no_kill
        src_url=${DOWN_ADDR_PGSQL}/${FILE_NAME}.md5 && Download_src_soft
        PGSQL_TAR_MD5=$(awk -v f="${FILE_NAME}" '$2 == f {print $1; exit}' ${FILE_NAME}.md5 2>/dev/null)
        if [ -n "${PGSQL_TAR_MD5}" ] && [ "$(md5sum ${FILE_NAME} 2>/dev/null | awk '{print $1}')" != "${PGSQL_TAR_MD5}" ]; then
          tryDlCount=0
          while [ "$(md5sum ${FILE_NAME} 2>/dev/null | awk '{print $1}')" != "${PGSQL_TAR_MD5}" ]; do
            wget -c ${DOWN_ADDR_PGSQL}/${FILE_NAME}
            let "tryDlCount++"
            [ "$(md5sum ${FILE_NAME} 2>/dev/null | awk '{print $1}')" == "${PGSQL_TAR_MD5}" -o "${tryDlCount}" == '6' ] && break || continue
          done
          if [ "${tryDlCount}" == '6' ]; then
            echo "${CFAILURE}${FILE_NAME} 校验失败，请检查镜像站或手动下载到 ${lemon_dir}/src${CEND}"
            exit 1;
          fi
        fi
        ;;
      8)
        # MongoDB
        # 5.0 起官方不再提供通用二进制包，改按发行版区分，且要求 CPU 支持 AVX
        # 官方只出了 debian12 构建，Debian 13 的 glibc 更新，直接用 debian12 的包
        # 仅支持 x86_64（check_os.sh 已拒绝其他架构）
        MONGODB_PLATFORM=debian12
        echo "Download MongoDB binary package..."
        MONGODB_TARBALL=mongodb-linux-${ARCH}-${MONGODB_PLATFORM}-${mongodb_ver}.tgz
        DOWN_ADDR_MongoDB=${mirror_link}/src
        FILE_NAME=${MONGODB_TARBALL}
        src_url=${DOWN_ADDR_MongoDB}/${FILE_NAME} && Download_src
        src_url=${DOWN_ADDR_MongoDB}/${FILE_NAME}.md5 && Download_src_soft
        MongoDB_TAR_MD5=$(awk -v f="${FILE_NAME}" '$2 == f {print $1; exit}' ${FILE_NAME}.md5 2>/dev/null)
        if [ -n "${MongoDB_TAR_MD5}" ] && [ "$(md5sum ${FILE_NAME} | awk '{print $1}')" != "${MongoDB_TAR_MD5}" ]; then
          tryDlCount=0
          while [ "$(md5sum ${FILE_NAME} | awk '{print $1}')" != "${MongoDB_TAR_MD5}" ]; do
            wget -c ${DOWN_ADDR_MongoDB}/${FILE_NAME}
            let "tryDlCount++"
            [ "$(md5sum ${FILE_NAME} | awk '{print $1}')" == "${MongoDB_TAR_MD5}" -o "${tryDlCount}" == '6' ] && break || continue
          done
          if [ "${tryDlCount}" == '6' ]; then
            echo "${CFAILURE}${FILE_NAME} 校验失败，请检查镜像站或手动下载到 ${lemon_dir}/src${CEND}"
            exit 1;
          fi
        fi
        # 6.0 起官方移除 bin/mongo，建账号与日常管理都依赖 mongosh
        echo "Download MongoDB Shell (mongosh)..."
        src_url=${mirror_link}/src/mongosh-${mongosh_ver}-linux-${SYS_ARCH_n}.tgz && Download_src
        ;;
    esac
  fi

  # PHP（只支持 7.4 起）
  # 主版本 php_option 和第二版本 mphp_ver 可能同时存在。原来是 if/elif 链，
  # 两个都指定时只会下第一个版本，第二个装到最后才报找不到包。
  php_dl_vers=''
  case "${php_option}" in
    1) php_dl_vers="${php74_ver}" ;;
    2) php_dl_vers="${php80_ver}" ;;
    3) php_dl_vers="${php81_ver}" ;;
    4) php_dl_vers="${php82_ver}" ;;
    5) php_dl_vers="${php83_ver}" ;;
    6) php_dl_vers="${php84_ver}" ;;
    7) php_dl_vers="${php85_ver}" ;;
  esac
  case "${mphp_ver}" in
    74) php_dl_vers="${php_dl_vers} ${php74_ver}" ;;
    80) php_dl_vers="${php_dl_vers} ${php80_ver}" ;;
    81) php_dl_vers="${php_dl_vers} ${php81_ver}" ;;
    82) php_dl_vers="${php_dl_vers} ${php82_ver}" ;;
    83) php_dl_vers="${php_dl_vers} ${php83_ver}" ;;
    84) php_dl_vers="${php_dl_vers} ${php84_ver}" ;;
    85) php_dl_vers="${php_dl_vers} ${php85_ver}" ;;
  esac
  # 注意：不能写成 echo ${var} | tr '\n' ' ' —— 变量为空时 echo 只输出一个换行，
  # 转成空格后得到 " "，[ -n " " ] 依然是真，于是没选 PHP 也会去下载整套编译依赖。
  php_dl_vers=$(echo ${php_dl_vers} | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')
  # 依赖判断用主次版本（7.4.34 -> 7.4），完整版本号只能用来拼包名
  php_dl_mm=''
  for php_one_ver in ${php_dl_vers}; do
    php_dl_mm="${php_dl_mm} $(echo ${php_one_ver} | awk -F. '{print $1"."$2}')"
  done
  php_dl_mm=$(echo ${php_dl_mm} | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')

  if [ -n "${php_dl_vers}" ]; then
    echo "PHP common..."
    src_url=${mirror_link}/src/libiconv-${libiconv_ver}.tar.gz && Download_src
    src_url=${mirror_link}/src/curl-${curl_ver}.tar.gz && Download_src
    src_url=${mirror_link}/src/freetype-${freetype_ver}.tar.gz && Download_src
    # mhash 只有 7.4 还需要（`--with-mhash`）。libmcrypt / mcrypt 没有任何脚本
    # 会用它们，属于上游遗留的下载项，已移除
    if echo "${php_dl_mm}" | tr ' ' '\n' | grep -qx '7\.4'; then
      src_url=${mirror_link}/src/mhash-${mhash_ver}.tar.gz && Download_src
    fi
    for php_one_ver in ${php_dl_vers}; do
      Download_PHP_src ${php_one_ver}
    done
    # 7.4 / 8.1 都已 EOL，官方不再发新版，2026 年的 CVE-2026-109618/109619
    # （Zend bailout 状态损坏）只能靠 php-src 的 backport 补丁修：
    #   8.1 → commit 1d7dec17、7.4 → commit 712e60f9
    # 编译前由 php-7.4.sh / php-8.1.sh 判断源码里是否已有修复，缺了才打
    if echo "${php_dl_mm}" | tr ' ' '\n' | grep -qx '8\.1'; then
      src_url=${mirror_link}/src/php-8.1-CVE-2026-109618-109619.patch && Download_src
    fi
    if echo "${php_dl_mm}" | tr ' ' '\n' | grep -qx '7\.4'; then
      src_url=${mirror_link}/src/php-7.4-CVE-2026-109618-109619.patch && Download_src
    fi
    src_url=${mirror_link}/src/argon2-${argon2_ver}.tar.gz && Download_src
    src_url=${mirror_link}/src/libzip-${libzip_ver}.tar.gz && Download_src
    # libsodium 8.2 起换成新版
    if echo "${php_dl_mm}" | tr ' ' '\n' | grep -qE '^(7\.4|8\.0|8\.1)$'; then
      src_url=${mirror_link}/src/libsodium-${libsodium_ver}.tar.gz && Download_src
    fi
    if echo "${php_dl_mm}" | tr ' ' '\n' | grep -qE '^8\.[2-5]$'; then
      src_url=${mirror_link}/src/libsodium-${libsodium_up_ver}.tar.gz && Download_src
    fi
  fi

  # PHP OPCache（7.4 起只剩 OPcache / APCu；XCache 只支持 PHP 5.x）
  case "${phpcache_option}" in
    1)
      # opcache 自 PHP 5.5 起内置，7.4 / 8.x 是静态编译进 PHP 的，不需要额外下载
      ;;
    2)
      echo "Download apcu..."
      src_url=${mirror_link}/src/apcu-${apcu_ver}.tgz && Download_src
      ;;
  esac

  # ioncube
  if [ "${pecl_ioncube}" == '1' ]; then
    echo "Download ioncube..."
    src_url=${mirror_link}/src/ioncube_loaders_lin_${SYS_ARCH_i}.tar.gz && Download_src
  fi

  # imageMagick
  if [ "${pecl_imagick}" == '1' ]; then
    # ImageMagick 库改用发行版自带（libmagickwand-dev / ImageMagick-devel），
    # 上游 7.x 的源码包已不再提供稳定直链，且编译耗时很长
    echo "Download imagick..."
    src_url=${mirror_link}/src/imagick-${imagick_ver}.tgz && Download_src
  fi

  # graphicsmagick
  if [ "${pecl_gmagick}" == '1' ]; then
    echo "Download graphicsmagick..."
    src_url=${mirror_link}/src/GraphicsMagick-${graphicsmagick_ver}.tar.xz && Download_src
    src_url=${mirror_link}/src/gmagick-${gmagick_ver}.tgz && Download_src
  fi

  # redis-server
  if [ "${redis_flag}" == 'y' ]; then
    echo "Download redis-server..."
    src_url=${mirror_link}/src/redis-${redis_ver}.tar.gz && Download_src
  fi

  # valkey-server
  if [ "${valkey_flag}" == 'y' ]; then
    echo "Download valkey-server..."
    src_url=${mirror_link}/src/valkey-${valkey_ver}.tar.gz && Download_src
  fi

  # clickhouse（三个官方 tgz：common 二进制 / server 配置 / client 配置）
  if [ "${clickhouse_flag}" == 'y' ]; then
    echo "Download ClickHouse..."
    src_url=${mirror_link}/src/clickhouse-common-static-${clickhouse_ver}-${SYS_ARCH}.tgz && Download_src
    src_url=${mirror_link}/src/clickhouse-server-${clickhouse_ver}-${SYS_ARCH}.tgz && Download_src
    src_url=${mirror_link}/src/clickhouse-client-${clickhouse_ver}-${SYS_ARCH}.tgz && Download_src
  fi

  # pecl_redis
  if [ "${pecl_redis}" == '1' ]; then
    echo "Download pecl_redis..."
    src_url=${mirror_link}/src/redis-${pecl_redis_ver}.tgz && Download_src
  fi

  # memcached-server
  if [ "${memcached_flag}" == 'y' ]; then
    echo "Download memcached-server..."
    DOWN_ADDR=${mirror_link}/src
    src_url=${DOWN_ADDR}/memcached-${memcached_ver}.tar.gz
    Download_src_soft || { src_url=https://www.memcached.org/files/memcached-${memcached_ver}.tar.gz && Download_src; }
  fi

  # pecl_memcached
  if [ "${pecl_memcached}" == '1' ]; then
    # libmemcached 用发行版的 libmemcached-dev（源码包 1.0.18 在 gcc 12 下编不过）
    echo "Download pecl_memcached..."
    src_url=${mirror_link}/src/memcached-${pecl_memcached_ver}.tgz && Download_src
  fi

  # memcache 扩展由 include/memcached.sh 按实际 PHP 版本自行下载，
  # 这里不再预下载（mphp 场景下 php_option 与实际版本可能不一致，会下错包）

  # pecl_mongodb 由 include/pecl_mongodb.sh 按实际 PHP 版本自行下载
  # （驱动版本按 PHP 分档，这里按 php_option 预下载会下错）

  # 补充扩展：igbinary / msgpack / zstd / grpc / xlswriter
  if [ "${pecl_igbinary}" == '1' ]; then
    echo "Download pecl_igbinary..."
    src_url=${mirror_link}/src/igbinary-${igbinary_ver}.tgz && Download_src
  fi
  if [ "${pecl_msgpack}" == '1' ]; then
    echo "Download pecl_msgpack..."
    # 7.x 与 8.x 的 msgpack 主版本不同，按目标 PHP 版本选包
    if echo "${php_dl_mm}" | tr ' ' '\n' | grep -qE '^7\.[0-4]$'; then
      src_url=${mirror_link}/src/msgpack-${msgpack_oldver}.tgz && Download_src
    else
      src_url=${mirror_link}/src/msgpack-${msgpack_ver}.tgz && Download_src
    fi
  fi
  if [ "${pecl_zstd}" == '1' ]; then
    echo "Download pecl_zstd..."
    src_url=${mirror_link}/src/zstd-${zstd_ver}.tgz && Download_src
  fi
  if [ "${pecl_grpc}" == '1' ]; then
    echo "Download pecl_grpc..."
    src_url=${mirror_link}/src/grpc-${grpc_ver}.tgz && Download_src
  fi
  if [ "${pecl_xlswriter}" == '1' ]; then
    echo "Download pecl_xlswriter..."
    src_url=${mirror_link}/src/xlswriter-${xlswriter_ver}.tgz && Download_src
  fi

  # nodejs
  if [ "${nodejs_flag}" == 'y' ]; then
    echo "Download Nodejs..."
    # 镜像站是扁平结构，路径里没有官方的 vX.Y.Z/ 这一层
    src_url=${mirror_link}/src/node-v${nodejs_ver}-linux-${SYS_ARCH_n}.tar.gz && Download_src
  fi

  # pureftpd
  if [ "${pureftpd_flag}" == 'y' ]; then
    echo "Download pureftpd..."
    src_url=${mirror_link}/src/pure-ftpd-${pureftpd_ver}.tar.gz && Download_src
  fi

  # phpMyAdmin
  if [ "${phpmyadmin_flag}" == 'y' ]; then
    echo "Download phpMyAdmin..."
    src_url=${mirror_link}/src/phpMyAdmin-${phpmyadmin_ver}-all-languages.tar.gz && Download_src
  fi

  popd > /dev/null
}
