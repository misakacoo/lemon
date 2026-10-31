# Lemon

Debian 12 / 13 一键部署 Web 运行环境的 Shell 脚本集。一条命令装好 Web 服务器、数据库、PHP 与常用扩展，全部源码编译或官方二进制安装，装完即用。

## 环境要求

| 项目 | 要求 |
| --- | --- |
| 系统 | Debian 12 (bookworm) / Debian 13 (trixie) |
| 架构 | x86_64 |
| 权限 | root |
| 内存 | ≥ 1 GB（PHP 编译高峰约 1.5 GB，小内存机器建议开 swap） |
| 磁盘 | ≥ 10 GB（源码包缓存在 `src/`） |

## 快速开始

```bash
apt-get update && apt-get install -y git
git clone https://github.com/misakacoo/lemon.git /root/lemon
cd /root/lemon && bash install.sh
```

交互模式下依次选择 Web 服务器、数据库、PHP 与附加组件，一路回车即得
**Nginx + MySQL 8.4 + PHP 8.3 + OPcache**。编译耗时较长，建议放进 screen：

```bash
screen -S lemon
cd /root/lemon && bash install.sh --nginx_option 1 --db_option 2 --dbrootpwd 'YourPassword' --php_option 5 --phpcache_option 1
```

无人值守示例：

```bash
bash install.sh \
  --nginx_option 1 --apache --apache_mode_option 1 \
  --db_option 2 --dbrootpwd 'YourPassword' \
  --php_option 5 --phpcache_option 1 \
  --php_extensions redis,memcached,imagick \
  --redis --memcached --phpmyadmin --firewall
```

装完会打印各组件的安装路径、面板地址与数据库密码位置。

## 组件与版本

| 分类 | 组件 |
| --- | --- |
| Web 服务器 | Nginx 1.30.6 · Tengine 3.1.0 · OpenResty 1.31.1.1 · Caddy 2.11.7 · Apache 2.4.69 |
| 数据库 | MySQL 5.7.44 / 8.0.46 / 8.4.11 · MariaDB 10.11.19 / 11.4.13 / 11.8.9 · Percona 8.0.46 / 8.4.11 |
| | PostgreSQL 18.6 · MongoDB 8.0.34 · ClickHouse 26.8.34.13 |
| PHP | 7.4.34 · 8.0.30 · 8.1.34 · 8.2.35 · 8.3.36 · 8.4.27 · 8.5.12（可并存第二版本） |
| 缓存 / 队列 | Redis 8.10.3 · Valkey 9.1.2 · Memcached 1.6.45 |
| 其他 | Node.js 24.22.0 · Pure-FTPd 1.0.54 · Supervisor · phpMyAdmin 5.2.3 |

版本集中在 [`versions.txt`](versions.txt)，改版本只改这一个文件。

## 参数

组件选择：

| 参数 | 说明 |
| --- | --- |
| `--nginx_option [1-4]` | 1 Nginx · 2 Tengine · 3 OpenResty · 4 Caddy |
| `--apache` | 同时安装 Apache 2.4 |
| `--apache_mode_option [1-2]` | 1 php-fpm（默认）· 2 mod_php（自动切 prefork） |
| `--apache_mpm_option [1-3]` | 1 event · 2 prefork · 3 worker |
| `--db_option [0-9]` | 0 MySQL 5.7 · 1 MySQL 8.0 · 2 MySQL 8.4 · 3 MariaDB 10.11 · 4 MariaDB 11.4 · 5 MariaDB 11.8 · 6 Percona 8.0 · 7 PostgreSQL · 8 MongoDB · 9 Percona 8.4 |
| `--dbrootpwd [密码]` | 数据库 root 密码 |
| `--dbinstallmethod [1-2]` | 1 二进制安装（默认）· 2 源码编译 |
| `--php_option [1-7]` | 1 7.4 · 2 8.0 · 3 8.1 · 4 8.2 · 5 8.3 · 6 8.4 · 7 8.5 |
| `--mphp_ver [74-85]` | 并存第二个 PHP 版本（需要 php-fpm） |
| `--phpcache_option [1-2]` | 1 OPcache（默认）· 2 APCu |
| `--php_extensions [列表]` | ioncube imagick gmagick fileinfo imap ldap calendar phalcon yaf yar redis memcached memcache mongodb swoole xdebug igbinary msgpack zstd grpc xlswriter |

附加服务与系统：

| 参数 | 说明 |
| --- | --- |
| `--nodejs` `--supervisor` `--pureftpd` | 附加组件 |
| `--redis` `--valkey` `--memcached` `--clickhouse` | 缓存 / 列式数据库 |
| `--phpmyadmin` | 安装 phpMyAdmin |
| `--ssh_port [端口]` | 修改 SSH 端口 |
| `--firewall` | 启用 ufw，仅放行 SSH 与 80/443 |
| `--reboot` | 装完重启 |

安全相关：

| 参数 | 说明 |
| --- | --- |
| `--db_bind_local` | 数据库只监听 `127.0.0.1` |
| `--phpmyadmin_local` | phpMyAdmin 只允许本机访问 |

默认数据库监听 `0.0.0.0`、phpMyAdmin 公网可达，只需要本机访问时请显式加上这两个参数。

## 目录结构

```
install.sh              安装入口
versions.txt            全部组件版本
options.conf            本机安装状态（运行期会被改写，含数据库密码）
vhost.sh                站点管理（新增/删除、签发 Let's Encrypt 证书）
backup.sh               备份执行入口（本地 / 远程 / 对象存储）
backup_setup.sh         备份配置向导
upgrade.sh              组件升级
uninstall.sh            卸载
addons.sh / pureftpd_vhost.sh / reset_db_root_password.sh
include/                各组件安装逻辑（每个组件一个脚本）
config/                 Nginx / Apache / Caddy 模板与伪静态规则
init.d/                 服务启动脚本模板
tools/                  工具脚本（见下）
src/                    下载缓存（运行期生成，不入库）
```

## 运维命令

```bash
bash vhost.sh --add sample.com          # 新建站点
bash vhost.sh --add --letsencrypt x.com # 新建站点并签发证书
bash vhost.sh --del                     # 删除站点
bash backup_setup.sh                    # 配置备份目标后，backup.sh 交给 cron 跑
bash upgrade.sh --nginx                 # 升级单个组件
bash uninstall.sh --web                 # 卸载组件
bash tools/pull.sh                      # 安全更新脚本（自动处理 options.conf）
python3 tools/audit.py                  # 三仓一致性自检
```

`options.conf` 记录本机实际安装的组件与密码，运行时会改写它。更新代码请用 `tools/pull.sh`，
不要直接 `git pull`，更不要 `git checkout -- options.conf`（会把密码清空）。

## 服务管理

```bash
systemctl {start,stop,restart,status} nginx|httpd|caddy|php-fpm|redis-server|memcached|pureftpd|postgresql|mongod
service mysqld {start,stop,restart}      # MySQL / MariaDB / Percona 沿用 sysv 脚本
```

## 链接

- 在线命令生成器：[Lemon-Shell](https://github.com/misakacoo/Lemon-Shell)
- 下载镜像：[Lemon-Mirror](https://github.com/misakacoo/Lemon-Mirror)

## 许可

见 [LICENSE](LICENSE)。
