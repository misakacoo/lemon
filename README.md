# Lemon

Debian 12 / 13 一键部署 Web 运行环境。一条命令装好 Web 服务器、数据库、PHP 与常用扩展，全部源码编译或官方二进制安装，装完即可建站。

## 特性

- **一条命令装全套**：Web 服务器、数据库、PHP、缓存、FTP、面板、进程守护，按需勾选，不装多余的。
- **版本自选**：PHP 7.4–8.5、MySQL 5.7–8.4、MariaDB 10.11–11.8、Percona、PostgreSQL、MongoDB 任选其一或组合。
- **源码编译**：PHP 与 Nginx 从源码编译；扩展编译成独立 ini（`/usr/local/php/etc/php.d`），随时可插拔。
- **供应链校验**：所有下载包都有 sha256 清单，下载后与复用缓存前都校验，不符即中止安装。
- **安全默认值**：数据库只监听 `127.0.0.1`；配置文件与安装日志权限 `600`；数据库口令不走命令行参数。
- **可卸载**：`uninstall.sh` 按组件卸载，`--purge` 清配置，`--purge-data` 清数据。
- **失败即中止**：任一组件失败立即停止并给出原因，不会留下「看起来装好了」的半成品。

## 组件与版本

| 类别 | 可选 |
| --- | --- |
| Web | Nginx 1.30.6 · Tengine 3.1.0 · OpenResty 1.31.1.1 · Apache 2.4.69（php-fpm / mod_php） |
| PHP | 7.4.34 · 8.0.30 · 8.1.34 · 8.2.35 · 8.3.36 · 8.4.27 · 8.5.12（可多版本共存） |
| 数据库 | MySQL 5.7.44 / 8.0.46 / 8.4.11 · MariaDB 10.11.19 / 11.4.13 / 11.8.9 · Percona 8.0.46 / 8.4.11 · PostgreSQL 18.6 · MongoDB 8.0.34 |
| 缓存 | Redis 8.10.3 · Valkey 9.1.2 · Memcached 1.6.45 |
| 附加 | phpMyAdmin 5.2.3 · Supervisor · Pure-FTPd · Node.js · ClickHouse · Fail2ban · ngx_lua_waf · Composer |
| 扩展 | redis / memcached / mongodb / swoole / xdebug / imagick / gmagick / imap / ldap / calendar / igbinary / msgpack / zstd / xlswriter / ioncube / yaf / yar / grpc |

## 环境要求

| 项 | 要求 |
| --- | --- |
| 系统 | Debian 12 (bookworm) / Debian 13 (trixie) |
| 架构 | x86_64 |
| 内存 | ≥ 2G（编译 PHP 需要；gRPC 扩展建议 ≥ 4G） |
| 磁盘 | ≥ 20G |
| 机器状态 | **全新机器**（安装器会调整系统级配置，见 [SCOPE.md](SCOPE.md)） |

## 快速开始

```bash
apt-get update && apt-get install -y git curl screen
git clone --depth 1 https://github.com/misakacoo/lemon.git /root/lemon
cd /root/lemon

# 例：Nginx + PHP 8.3 + MySQL 8.4 + redis
screen -L -Logfile /root/install.log -dmS lemon ./install.sh \
  --nginx_option 1 --php_option 5 --db_option 2 --dbrootpwd "YourPassword" \
  --php_extensions "redis" --redis --firewall
```

安装过程中用 `screen -r lemon` 观察进度。装完建站：

```bash
bash vhost.sh --add example.com --letsencrypt --dir /data/wwwroot/example.com
```

浏览器打开 `https://example.com` 看到占位页即成功，把程序放进 `/data/wwwroot/example.com` 就完成部署。

## 参数

| 参数 | 说明 |
| --- | --- |
| `--nginx_option [1-3]` | 1 Nginx（默认）· 2 Tengine · 3 OpenResty |
| `--apache` | 改装 Apache；`--apache_mode_option 1/2` 选 php-fpm / mod_php；`--apache_mpm_option 1-3` 选 MPM |
| `--php_option [1-7]` | 1 → 7.4 · 2 → 8.0 · 3 → 8.1 · 4 → 8.2 · 5 → 8.3 · 6 → 8.4 · 7 → 8.5 |
| `--mphp_ver [74~85]` | 额外再装一个 PHP 版本（如 `--mphp_ver 74`），装到 `/usr/local/php74` |
| `--phpcache_option [1-2]` | 1 启用 OPcache（默认）· 2 关闭 |
| `--php_extensions 'a,b,c'` | 编译指定 PHP 扩展，逗号分隔 |
| `--db_option [0-9]` | 0 MySQL5.7 · 1 MySQL8.0 · 2 MySQL8.4 · 3 MariaDB10.11 · 4 MariaDB11.4 · 5 MariaDB11.8 · 6 Percona8.0 · 7 PostgreSQL · 8 MongoDB · 9 Percona8.4 |
| `--dbrootpwd 'pwd'` | 数据库 root 口令（MySQL / MariaDB / Percona） |
| `--dbinstallmethod [1-2]` | 1 官方二进制（默认）· 2 源码编译 |
| `--db_bind_public` | 把数据库放开到 `0.0.0.0`（默认只监听 `127.0.0.1`，含 MySQL X 协议 33060） |
| `--redis` / `--valkey` / `--memcached` | 装对应缓存服务端（PHP 扩展另用 `--php_extensions`） |
| `--clickhouse` / `--dbclickhousepwd 'pwd'` | 装 ClickHouse 并设置默认用户口令 |
| `--phpmyadmin` / `--phpmyadmin_local` | 装 phpMyAdmin；后者只允许本机访问 |
| `--pureftpd` | 装 Pure-FTPd（FTP 用户用 `pureftpd_vhost.sh` 管理） |
| `--supervisor` | 装 Supervisor 进程守护 |
| `--nodejs` | 装 Node.js |
| `--ssh_port [端口]` | 修改 SSH 端口（改前备份 + `sshd -t` 预校验，失败自动回滚） |
| `--firewall` | 启用 ufw：放行 SSH / 80 / 443，默认拒绝入站 |

不带参数运行 `./install.sh` 会进入交互菜单。

## 建站与证书

```bash
bash vhost.sh --add 域名 [--letsencrypt|--le|--selfsigned] [--dir 目录] [--httponly]
bash vhost.sh --list      # 查看已有站点
bash vhost.sh --del 域名   # 删除站点
```

| 证书方式 | 说明 |
| --- | --- |
| `--letsencrypt`（默认） | 自动签发可信证书，默认 CA 为 **ZeroSSL**（acme.sh + EAB 自动注册） |
| `--le` | 改用 Let's Encrypt 签发 |
| `--selfsigned` | 自签证书（内网 / 测试用） |

签发失败不会删除站点：自动降级为纯 HTTP 站点，并给出重试命令。

## 运维

```bash
systemctl status nginx php-fpm mysqld redis-server supervisor
nginx -t && nginx -s reload
```

### supervisor / cron 里的 php 去哪找

| 场景 | PATH | 做法 |
| --- | --- | --- |
| Supervisor 托管程序 | 安装时已把 `/usr/local/php/bin` 写进 `supervisord.conf` 的 `environment=PATH` | 直接写 `command=php artisan horizon` |
| crontab | 只有 `/usr/bin:/bin` | 用绝对路径 `/usr/local/php/bin/php`，或在 crontab 顶部加 `PATH=` |

Laravel / ThinkPHP 这类框架的定时任务要带站点用户，否则缓存文件被写成 `root`，之后 php-fpm 写入会 500：

```bash
*/1 * * * * runuser -u www -- /usr/local/php/bin/php /data/wwwroot/example.com/artisan schedule:run
```

### 退出码

成功返回 `0`；任一组件失败返回非 `0`，并在日志末尾列出失败项。需要装完再统一排查时用 `LEMON_KEEP_GOING=1`。

## 卸载

```bash
bash uninstall.sh --all -q                        # 卸载全部组件，保留配置与数据
bash uninstall.sh --all --purge -q                # 再清掉 Lemon 写的配置
bash uninstall.sh --all --purge --purge-data -q   # 连数据目录一起删（不可恢复）
bash uninstall.sh --web|--php|--mysql|--redis -q  # 只卸单个组件
```

## 目录结构

```
install.sh              安装入口（参数解析 / 组件调度）
uninstall.sh            卸载
upgrade.sh              组件小版本升级
vhost.sh                建站 / 证书 / 删除站点
addons.sh               附加组件（composer / fail2ban / ngx_lua_waf）
pureftpd_vhost.sh       FTP 用户管理
backup_setup.sh         备份任务配置（交互式）
versions.txt            所有组件版本（唯一版本来源）
checksums.txt           下载包 sha256 清单
options.conf.example    运行时配置模板（首次安装复制为 options.conf）
include/                各组件的安装 / 卸载实现
config/                 Nginx、Apache 等配置模板
tools/                  checksum 生成与校验脚本
```

安装后：组件在 `/usr/local/<组件>`，站点在 `/data/wwwroot`，日志在 `/data/wwwlogs`，数据库数据在 `/data/<组件>`。

## 安全

- 下载包 sha256 全量校验；清单里有但内容不符 → 删除并中止安装。
- 数据库默认只监听本机；phpMyAdmin 可用 `--phpmyadmin_local` 限制为仅本机。
- `options.conf` 与 `install.log` 权限 `600`；数据库口令通过环境变量传递，不出现在 `ps`。
- 漏洞报告方式与已知风险见 [SECURITY.md](SECURITY.md)。

## 支持范围

仅支持**全新 Debian 12 / 13 x86_64**。不支持 ARM、容器、带数据跨版本升级、自动化备份等场景，详见 [SCOPE.md](SCOPE.md)。

## 许可

Apache License 2.0，见 [LICENSE](LICENSE)。
