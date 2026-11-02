# 安全说明

## 报告漏洞

请**不要**用公开 issue 报告安全问题。请使用 GitHub 的 *Report a vulnerability*（Security → Advisories），或发邮件给维护者。
请附：Debian 版本、`git log --oneline -1`、复现步骤、影响面（能否远程利用 / 是否需登录）。

## 安全设计

| 面 | 措施 |
| --- | --- |
| 供应链 | `checksums.txt` 覆盖全部下载包；下载后与复用缓存前都校验 sha256，不符则删除并中止（`LEMON_STRICT_CHECKSUM=1` 把清单外文件也算失败） |
| 口令 | 数据库口令不走命令行（`/proc/PID/cmdline` 可见），用 `MYSQL_PWD`；`options.conf` 与 `install.log` 权限 600 |
| 暴露面 | 数据库默认只监听 `127.0.0.1`（MySQL/MariaDB/Percona `bind-address`、PostgreSQL `listen_addresses`、MongoDB `bindIp`，含 MySQL X 协议 33060） |
| 面板 | phpMyAdmin 支持 `--phpmyadmin_local`（nginx `^~` 块 + `allow/deny`） |
| 证书 | 默认 ZeroSSL；签发失败时站点降级 HTTP，而不是整站删除 |
| 危险操作 | 卸载前校验路径非空、拒绝 `/` 等危险目标；仅 `--purge-data` 才删数据目录 |

## 已知风险（已文档化）

- 改 SSH 端口时会写 `/etc/ssh/sshd_config`：已加备份 + `sshd -t` 预校验，失败自动回滚。
- 会写 `sysctl.conf`、`limits.conf`、swap、时区；`--purge` **不回滚**这些系统级改动。
- phpMyAdmin 默认公网可达（仅其自身登录页把关），生产请加 `--phpmyadmin_local`。
- fail2ban 附加脚本只启用 Debian 自带 sshd jail，不含 nginx jail。
