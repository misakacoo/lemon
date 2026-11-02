# Lemon

> **English summary**: Lemon is a one-command installer for a full web stack on **fresh Debian 12/13 (x86_64)** machines — Nginx/Tengine/OpenResty/Apache, PHP 7.4–8.5 (source build), MySQL / MariaDB / Percona / PostgreSQL / MongoDB, Redis / Valkey / Memcached, phpMyAdmin, Supervisor, Pure-FTPd. All download packages are sha256-pinned (`checksums.txt`). **Scope: fresh machines only**, see [SCOPE.md](SCOPE.md) for what is *not* supported (ARM, in-place upgrades with existing data, automated backup). Security policy: [SECURITY.md](SECURITY.md). License: Apache-2.0.

Debian 12 / 13 一键部署 Web 运行环境的 Shell 脚本集。一条命令装好 Web 服务器、数据库、PHP 与常用扩展，全部源码编译或官方二进制安装，装完即用。

**先读这两个文件再动手**：[SCOPE.md](SCOPE.md)（支持范围与不支持场景）、[SECURITY.md](SECURITY.md)（安全设计与已知风险）。

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
src/                    下载缓存与解压目录（运行期生成，不入库；可用 tools/clean-src.sh 清理）
```

## 备份与恢复

`backup_setup.sh` 配好目标后，`backup.sh` 会生成两类包（都放在 `backup_dir`，默认 `/data/backup`）：

| 文件 | 内容 |
| --- | --- |
| `DB_<库名>_<时间戳>.tgz` | 里面是 `<库名>.sql`，由 `mysqldump --databases` 导出 |
| `Web_<站点>_<时间戳>.tgz` | 站点目录（`wwwroot`）打包 |

**恢复数据库时注意**：dump 里自带 `CREATE DATABASE` / `USE <原库名>`，所以

```bash
tar xzf DB_lemondb_20261101_204629.tgz

# 情况一：恢复回原来的库（最常见）——直接导入，会覆盖同名库
mysql -uroot -p'密码' < DB_lemondb_20261101_204629.sql

# 情况二：恢复到另一个库名——先把 dump 里的库名替换掉，否则数据会全部回到原库
sed 's/`lemondb`/`restore_test`/g' DB_lemondb_20261101_204629.sql > restore_test.sql
mysql -uroot -p'密码' -e 'create database restore_test'
mysql -uroot -p'密码' restore_test < restore_test.sql
```

两种情况下 `mysql` 都会返回 0，**不能只看退出码判断是否真的恢复了**：情况二如果不做替换，
目标库会是 0 张表、数据其实回到了原库。恢复后请核对表数与行数：

```bash
mysql -uroot -p'密码' -N -e "select count(*) from information_schema.tables where table_schema='restore_test'"
```

恢复站点：把 `Web_<站点>_*.tgz` 解到 `wwwroot` 对应目录，再 `chown -R www:www` 并重载 Web 服务器。
## 运维命令

```bash
bash vhost.sh --add sample.com          # 新建站点
bash vhost.sh --add --letsencrypt x.com # 新建站点并签发证书
bash vhost.sh --del                     # 删除站点
bash backup_setup.sh                    # 配置备份目标后，backup.sh 交给 cron 跑
bash upgrade.sh --nginx                 # 升级单个组件
bash uninstall.sh --web                 # 卸载组件
bash tools/pull.sh                      # 安全更新脚本（自动处理 options.conf）
bash tools/clean-src.sh                 # 清理解压残留（加 --tarballs 连下载缓存一起清）
python3 tools/audit.py                  # 三仓一致性自检
```

`options.conf` 记录本机实际安装的组件与密码，运行时会改写它。更新代码请用 `tools/pull.sh`，
不要直接 `git pull`，更不要 `git checkout -- options.conf`（会把密码清空）。

### 退出码

`upgrade.sh` 与 `backup.sh` 可以直接放进自动化流程，退出码含义：

| 退出码 | 含义 |
| --- | --- |
| `0` | 升级/备份真的执行成功 |
| `1` | **没有升成**：目标版本与当前相同、版本号格式非法、包取不到、编译或安装失败 |

也就是说「什么都没做」不会被当成成功。典型用法：

```bash
if bash upgrade.sh --nginx 1.31.8; then echo 升级成功; else echo 未升级或失败; fi
```

## 服务管理

```bash
systemctl {start,stop,restart,status} <单元名>
service mysqld {start,stop,restart}      # MySQL / MariaDB / Percona 沿用 sysv 脚本
```

单元名对照（按错名字查会显示 inactive，容易误判成没装）：

| 组件 | systemd 单元 |
| --- | --- |
| Nginx / Tengine / OpenResty | `nginx.service` |
| Apache | `httpd.service` |
| Caddy | `caddy.service` |
| PHP-FPM | `php-fpm.service`（并存版本为 `php74-fpm.service` 等） |
| MySQL / MariaDB / Percona | sysv 脚本：`service mysqld status`；三者的 systemd 单元名都是 `mysql`，**没有** `mariadb.service` / `percona.service` |
| PostgreSQL | `postgresql.service` |
| MongoDB | `mongod.service` |
| ClickHouse | `clickhouse-server.service` |
| Redis | `redis-server.service` |
| Valkey | `valkey-server.service` |
| Memcached | `memcached.service` |
| Pure-FTPd | `pureftpd.service` |
| Supervisor | `supervisor.service` |
| Node.js | 无服务，仅 CLI（`/usr/local/node/bin`） |

## 已知限制

- **仅支持 Debian 12 / 13 + x86_64**，没有做 aarch64 验证。
- **数据库默认只监听 `127.0.0.1`**（MySQL/MariaDB/Percona 的 `bind-address`、PostgreSQL `listen_addresses`、MongoDB `bindIp`）。
  需要从外部连库时加 `--db_bind_public`（MySQL 的 X 协议端口 33060 也会一并放开），并自行配防火墙白名单。
- **建站证书默认走 ZeroSSL**：`bash vhost.sh --add <域名>` 自动用 acme.sh 签发（EAB 自动注册）；
  需要 Let's Encrypt 时加 `--le`，只签自签证书用 `--selfsigned`。签发失败不会删站点，而是保留 HTTP 站点并给出重试命令。
- **phpMyAdmin 默认公网可达**，只有它自己的登录页把关；加 `--phpmyadmin_local` 限制为仅本机。
- **phpMyAdmin 5.2.x 只支持 PHP < 8.4**，装 PHP 8.4/8.5 时会被自动跳过。
- **Apache 的 mod_php 与 php-fpm 是两套编译产物**：mod_php 版 PHP 不含 `php-fpm`，php-fpm 版不含 `libphp.so`。
  切换模式必须先 `uninstall.sh --php --phpcache` 再装；安装脚本会前置检查并拒绝不匹配的组合。
- **MySQL 5.7 只能在 Debian 12 安装**（Debian 13 的 glibc 不兼容官方二进制，脚本会直接拒绝）。
- **Redis / Valkey 只监听 `127.0.0.1`、不设密码**（靠 bind + protected-mode）。需要远程访问时请自行加 `requirepass` 并放行防火墙。
- **升级包只从镜像站取**：`upgrade.sh` 升级到镜像未收录的补丁版本时，需要先把 tar 包放进 `src/`（脚本会明确提示）。
- **非交互 SSH 的 PATH 不含 `/usr/local/*/bin`**（PATH 只写在 `/etc/profile`）。自动化脚本请用绝对路径（如 `/usr/local/php/bin/php`）或 `bash -lc '...'`。
- **组件失败默认立即中止**（`Run_Install` 收集失败后 `exit 1`，并在结尾用真实登录/服务状态做校验），
  避免留下“半安装”却报成功的状态；需要装完再统一排查时用 `LEMON_KEEP_GOING=1`。

### supervisor / cron 里的 `php` 怎么被找到

`supervisor` 和 `cron` 都不读 `/etc/profile`，它们的 PATH 与登录 shell 不同，这是「`command=php artisan horizon` 起不来」的根因：

| 场景 | 实际 PATH | 处理方式 |
| --- | --- | --- |
| supervisor 托管程序 | 继承 systemd：`/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin` | 安装 supervisor 时会往 `/etc/supervisor/supervisord.conf` 写入 `environment=PATH="…:/usr/local/php/bin:…"`，所以裸写 `php` 也能用；也可以直接写绝对路径 `/usr/local/php/bin/php` |
| root / 用户 crontab | 只有 `/usr/bin:/bin` | **用绝对路径**：`*/1 * * * * /usr/local/php/bin/php /data/wwwroot/x/artisan schedule:run`；或在 crontab 顶部加 `PATH=/usr/local/php/bin:/usr/local/bin:/usr/bin:/bin` |

Laravel / ThinkPHP 这类框架的定时任务还有一层坑：**cron 以 root 跑会把 `storage`、`runtime` 缓存写成 `root:root`，
随后 php-fpm（www 用户）写这些文件就 500**。正确写法是带上站点用户：

```bash
*/1 * * * * runuser -u www -- /usr/local/php/bin/php /data/wwwroot/example.com/artisan schedule:run
```

## 已验证矩阵（改动后请按此复跑）

在**全新 Debian 12 / Debian 13** 各一台（6 核 16G）上按 18 个场景实跑，每格都是「清空 → 安装 → 建站 → 断言集 → （部分）卸载 → 残留断言」：

| 场景 | 组合 | 结果 |
| --- | --- | --- |
| S1 | D12 nginx + PHP7.4 + MySQL5.7 + redis + supervisor + phpMyAdmin(本机) + pureftpd | 32/0 |
| S2 | D13 nginx + PHP8.3 + MySQL8.4 + 同套附加 | 32/0 |
| S3 | D12 nginx + PHP8.4 + MariaDB11.8 + valkey + memcached | 19/0 |
| S4 | D13 nginx + PHP8.2 + MariaDB10.11 + ClickHouse | 19/0 |
| S5 | D12 apache(php-fpm) + PHP7.4 + MySQL8.0 + phpMyAdmin(公网) | 18/0 |
| S6 | D13 apache(mod_php) + PHP8.1 + MySQL8.0 | 15/0（修 harness 后） |
| S7 | D12 nginx + PHP8.5 + MySQL8.0 + 15 个 pecl 扩展 | 33/0 |
| S8 | D13 nginx + PHP8.0 + PostgreSQL + nodejs + supervisor | 15/0 |
| S9 | D12 nginx + PHP8.3 + MongoDB | 12/0 |
| S10 | D13 nginx + PHP8.3 + Percona8.4 | 16/0（修 harness 后） |
| S11 | D12 OpenResty + PHP8.3 + MySQL8.4 | 14/0（修 harness 后） |
| S12 | D13 Tengine + PHP8.3 + MariaDB11.4 | 22/1 → 剩一条 harness 版本断言 |
| S13 | D12 多版本 PHP 8.3 + 7.4 + MySQL8.4 | 18/0 |
| S14 | D13 nginx + PHP8.3 + MySQL8.4 + `--db_bind_public` | 18/0（3306/33060 均 0.0.0.0） |
| S15 | 卸载矩阵（`--web/--php/--mysql/--all --purge --purge-data`） | 通过，暴露并修复 D7/D8 |
| S16 | 同参数重复安装（幂等） | 6/6 |
| S17 | `upgrade.sh` 同版本 | 拒绝且环境无损（无修复重装路径，见已知限制） |
| S18 | addons：fail2ban + composer + ngx_lua_waf | 4/4 |

复跑方法：机器上放 `clean.sh`（统一清理 + 7 条自断言）、`check.sh`（40+ 条断言，按 `/root/exp/<场景>.env` 取期望值）、`site.sh`（建站 + 证书）。

### 已知限制（矩阵确认，暂不修）

- `upgrade.sh` 只支持「升到更高版本」，没有 `--force` 修复重装路径；同版本会被拒绝（exit 1，环境不受影响）。
- `backup_setup.sh` 是纯交互脚本，非 TTY 直接退出，无法自动化测试。
- fail2ban 只启用 Debian 自带的 sshd jail，没有生成 nginx 相关 jail。
- 不传 `--clickhouse` 时，`options.conf` 里仍会写入 `dbclickhousepwd` 一行（无害）。
## 安全与完整性

**安装包校验**：仓库根目录的 `checksums.txt` 记录了每个下载包的 sha256。
`Download_src` 在下载后（以及复用 `src/` 里的缓存前）都会核对：

- 清单里**有**这个文件但内容不符 → 删除并中止安装（这是镜像被改/被劫的信号）；
- 清单里**没有** → 只告警（新版本还没补清单时不至于装不了），要严格模式可设 `LEMON_STRICT_CHECKSUM=1`；
- `LEMON_SKIP_CHECKSUM=1` 可整体跳过（应急用）。

`versions.txt` 里任何版本号改动后，请重跑 `bash tools/gen-checksums.sh` 更新清单。

**数据库监听地址**：默认只监听 `127.0.0.1`。需要从外部连库时显式加 `--db_bind_public`，
并自行配防火墙白名单（脚本只负责放开监听，不会替你开端口）。

**失败即中止**：任何组件安装失败都会立即停止后续安装并非 0 退出 —— 避免得到一台「看起来装完、
其实缺组件」的机器。需要跳过失败继续装时设 `LEMON_KEEP_GOING=1`。
已装好的组件重跑时会跳过，修完原因可直接重跑同一条命令。

**升级回滚**：`upgrade.sh --db` 会把版本目录与数据目录改名成 `*_old_<时间戳>` 留存；
导入失败时自动停服、换回旧目录、重新启动，无需手工恢复。
## 链接

- 在线命令生成器：[Lemon-Shell](https://github.com/misakacoo/Lemon-Shell)
- 下载镜像：[Lemon-Mirror](https://github.com/misakacoo/Lemon-Mirror)

## 许可

见 [LICENSE](LICENSE)。
