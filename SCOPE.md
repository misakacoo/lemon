# 支持范围（Scope）

Lemon 是面向**全新机器**的一键部署脚本。请先确认场景在范围内再执行安装。

## 支持

| 项 | 范围 |
| --- | --- |
| 操作系统 | Debian 12 (bookworm) / Debian 13 (trixie) |
| 架构 | x86_64（aarch64 **未验证**） |
| 机器状态 | **全新安装**，或明确可以清空重装的机器 |
| 内存 | 建议 ≥ 2G（源码编译；gRPC 扩展另需 ≥ 4G 或临时 swap） |
| 磁盘 | 建议 ≥ 20G（编译缓存 + 数据） |
| 网络 | 可访问 GitHub 与镜像站；80/443 可被外网访问（签发证书需要） |

## 不支持 / 未验证

- **已有业务的机器**：安装器会修改系统级配置（`/etc/ssh/sshd_config`、`sysctl.conf`、`limits.conf`、swap、时区）。
- **aarch64 / ARM**：编译参数与下载包均为 x86_64，ARM 上未做任何验证。
- **OpenVZ / LXC 等受限虚拟化**：依赖 systemd 单元、`swapon`、内核参数调整，容器内可能失败。
- **带数据的跨大版本升级**：`upgrade.sh` 已验证「同版本拒绝且环境无损」，跨大版本升级未做矩阵验证。
- **自动化备份/恢复**：`backup_setup.sh` 为交互式脚本，非 TTY 直接退出，自动化路径未验证。
- **业务程序安装**：本项目只提供运行环境，不包含 v2board / WordPress 等程序的部署。

## 生产使用建议

1. 安装前打快照（比任何回滚脚本都可靠）。
2. `--phpmyadmin_local`，不要把 phpMyAdmin 暴露到公网。
3. 保持 `--firewall`；数据库默认只监听 `127.0.0.1`，需要外部访问才加 `--db_bind_public`。
4. 上线前先跑满 48 小时，观察 `ss -s`、内存、php-fpm 慢日志。
5. 在备份路径自动化验证前，用 `mysqldump --single-transaction --all-databases` 做冷备。
