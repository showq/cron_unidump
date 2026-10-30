# cron_unidump

自动化 MySQL 数据库和文件备份工具

## 功能特性

- ✅ 支持多种 MySQL 备份引擎 (mydumper/mysqldump/mysqlhotcopy)
- ✅ 支持文件增量备份（使用 tar 快照）
- ✅ 多配置文件管理
- ✅ 备份文件自动压缩和验证
- ✅ 安全的密码存储方案
- ✅ 详细的日志记录
- ✅ 可配置的备份保留策略

## 系统要求

- Linux/Unix 系统
- Bash 4.0+
- MySQL/MariaDB
- 备份工具（至少一个）：
  - mydumper (推荐，用于 InnoDB)
  - mysqldump (通用)
  - mysqlhotcopy (用于 MyISAM)

## 快速开始

### 1. 安装

```bash
# 克隆仓库
git clone <repository_url>
cd cron_unidump

# 运行安装脚本
./cron_unidump.sh install
```

安装脚本会：
- 创建配置目录 `~/.cron_unidump.d/`
- 复制全局配置文件到 `~/.cron_unidump.conf`
- 设置执行权限

### 2. 配置

#### 方法一：使用密码文件（推荐 - 更安全）

1. 创建 MySQL 配置文件：

```bash
cp mysql_backup.cnf.example ~/.mysql_backup.cnf
chmod 600 ~/.mysql_backup.cnf
```

2. 编辑 `~/.mysql_backup.cnf`：

```ini
[client]
user=root
password=your_actual_password
host=localhost
```

3. 编辑 `~/.cron_unidump.conf`，添加：

```bash
BACKUP_MYSQL_DEFAULTS_FILE="$HOME/.mysql_backup.cnf"
```

#### 方法二：使用配置文件密码（简单但不够安全）

编辑 `~/.cron_unidump.conf`：

```bash
BACKUP_HOST="localhost"
BACKUP_USER="root"
BACKUP_PASS="your_password"  # ⚠️ 替换为实际密码
```

### 3. 创建备份配置

```bash
# 添加新的备份任务
cron_unidump add myproject

# 编辑配置文件
vim ~/.cron_unidump.d/myproject.conf
```

配置文件示例：

```bash
# 文件备份
SOURCE='/var/www/html/myproject'
EXCLUDE="--exclude=*.tmp"
EXTRA_SOURCE="/etc/nginx"

# MySQL 备份
DBHOST='localhost'
DBNAME='mydb'
DBENGINE='innodb'  # 或 'myisam', 'mysqldump'
```

### 4. 验证配置

```bash
# 检查配置是否正确
cron_unidump check
```

### 5. 执行备份

```bash
# 备份数据库
cron_unidump backup db myproject

# 备份文件
cron_unidump backup file myproject

# 同时备份数据库和文件
cron_unidump backup all myproject
```

## 命令参考

### 基本命令

| 命令 | 说明 |
|------|------|
| `cron_unidump install` | 安装脚本 |
| `cron_unidump uninstall` | 卸载脚本 |
| `cron_unidump list` | 列出所有配置 |
| `cron_unidump add <name>` | 创建新配置 |
| `cron_unidump edit <name>` | 编辑配置 |
| `cron_unidump show <name>` | 显示配置内容 |
| `cron_unidump check` | 验证配置 |

### 备份命令

```bash
# 备份类型：db, file, all
cron_unidump backup <type> <config_name>

# 示例
cron_unidump backup db myproject
cron_unidump backup file myproject
cron_unidump backup all myproject
```

### 恢复命令

```bash
cron_unidump restore <config_name> [date]
```

## 配置文件说明

### 全局配置 (`~/.cron_unidump.conf`)

```bash
# 文件所有者
BACKUP_FILEOWN='user:group'

# MySQL 连接（使用 MySQL 配置文件）
BACKUP_MYSQL_DEFAULTS_FILE="$HOME/.mysql_backup.cnf"

# 或使用密码（不推荐）
BACKUP_HOST="localhost"
BACKUP_USER="root"
BACKUP_PASS="password"

# 邮件通知
BACKUP_MAIL=n
BACKUP_EMAILS="admin@example.com"

# 备份保留策略
BACKUP_DELETE=y

# 文件备份：完整备份间隔（天）与模式
BACKUP_INTERVAL_DAYS=30
BACKUP_FILE_MODE=incremental  # incremental | differential
```

### 任务配置 (`~/.cron_unidump.d/<name>.conf`)

```bash
# 文件备份配置
SOURCE='/path/to/backup'
EXCLUDE="--exclude=*.log --exclude=cache/"
EXTRA_SOURCE="/additional/path"
INTERVAL_DAYS=30  # 完整备份间隔（天），覆盖全局
FILE_MODE=incremental  # incremental | differential，覆盖全局

# 数据库备份配置
DBHOST='localhost'
DBNAME='database_name'
DBENGINE='innodb'  # 选项: innodb, myisam, mysqldump
DBOPTIONS='--single-transaction'  # 额外选项
```

## 增量 / 差异备份

文件备份基于 GNU tar 的 `-g` 快照（listed-incremental），支持两种模式：

| 模式 | `FILE_MODE` | 每次备份包含 | 恢复需要 |
|------|-------------|--------------|----------|
| 增量（默认） | `incremental` | 自上一次备份以来的变化 | 最近的 full + 之后所有 inc |
| 差异 | `differential` | 自最近一次完整备份以来的全部变化 | 最近的 full + 最近一个 diff |

每 `INTERVAL_DAYS` 天自动做一次完整备份；基准快照或上一次的快照丢失时也会自动转为完整备份。

```
Day 1:      full  → 创建基准快照
Day 2-14:   inc   → 只包含前一天之后的变化
Day 15:     full  → 更新基准快照，开始新的链   (INTERVAL_DAYS=14)
```

**备份文件命名**：文件名末尾带类型，便于识别恢复链：

```
FILE-myapp-2024-12-01-19-51-01-full.tar.bz2
FILE-myapp-2024-12-02-19-51-01-inc.tar.bz2
FILE-myapp-2024-12-03-19-51-01-inc.tar.bz2
```

**可靠性**：

- tar 返回码 1（备份过程中有文件被修改）视为成功，归档可用
- tar 失败时快照自动回滚到运行前的状态，下次运行不会漏掉这些变化
- 每次运行前的快照保存为 `snapshot-<name>-incremental-YYMMDD.log`
- tar 以 `nice` / `ionice` 低优先级运行，减少对线上服务的影响

快照文件（自动管理，位于 `logBaseDir`）：
- `snapshot-<name>-incremental` - 当前快照（增量链的状态）
- `snapshot-<name>-incremental-intervalBase` - 最近一次完整备份的基准快照

⚠️ **tar 以 ctime 判断变化**：`chown -R` / `chmod -R` 等只改属性的操作也会更新 ctime，下一次备份会把这些文件全部重新打包。增量模式下只影响一次；差异模式下会持续到下一次完整备份。

**恢复**：按时间顺序先解开最近的 `*-full`，再依次解开之后的每个 `*-inc`（差异模式只需最近一个 `*-diff`）。`-g /dev/null` 让 tar 同步删除在备份之间被删除的文件：

```bash
cd /restore/path
tar -xjf FILE-myapp-2024-12-01-19-51-01-full.tar.bz2 -g /dev/null
tar -xjf FILE-myapp-2024-12-02-19-51-01-inc.tar.bz2  -g /dev/null
tar -xjf FILE-myapp-2024-12-03-19-51-01-inc.tar.bz2  -g /dev/null
```

清理旧备份时，不要删除仍在使用中的 `*-full`，否则其后的 `*-inc` 无法恢复。

## 自动化备份

### 使用 Crontab

```bash
# 编辑 crontab
crontab -e

# 每天凌晨 2 点备份
0 2 * * * /usr/bin/cron_unidump backup all myproject >> /var/log/backup/cron.log 2>&1

# 每周日凌晨 3 点备份
0 3 * * 0 /usr/bin/cron_unidump backup all myproject
```

## 安全建议

### 🔐 保护敏感信息

1. **使用 MySQL 配置文件**（推荐）：
   ```bash
   chmod 600 ~/.mysql_backup.cnf
   ```

2. **不要提交敏感配置到版本控制**：
   - 已添加 `.gitignore` 保护
   - 使用 `.example` 文件作为模板

3. **限制文件权限**：
   ```bash
   chmod 600 ~/.cron_unidump.conf
   chmod 600 ~/.cron_unidump.d/*.conf
   ```

4. **定期更新密码**并使用强密码

### 🔒 备份文件安全

1. **设置正确的文件权限**：
   ```bash
   chmod 700 /var/backup
   ```

2. **考虑加密备份**（可选）：
   ```bash
   # 在脚本中添加加密步骤
   openssl enc -aes-256-cbc -salt -in backup.tar.gz -out backup.tar.gz.enc
   ```

## 备份验证

脚本会自动验证：
- ✅ tar 归档文件完整性
- ✅ MySQL 连接可用性
- ✅ 备份目录权限
- ✅ 必要的工具是否安装

手动验证备份：

```bash
# 测试 tar 文件
tar -tzf /path/to/backup.tar.gz > /dev/null

# 测试数据库连接
mysql --defaults-file=~/.mysql_backup.cnf -e "SELECT 1;"
```

## 故障排查

### 常见问题

1. **MySQL 连接失败**
   ```bash
   # 检查配置
   cron_unidump check

   # 测试连接
   mysql --defaults-file=~/.mysql_backup.cnf -e "SELECT 1;"
   ```

2. **权限不足**
   ```bash
   # 检查目录权限
   ls -la /var/backup

   # 设置正确的所有者
   sudo chown -R your_user:your_group /var/backup
   ```

3. **备份工具未找到**
   ```bash
   # 安装 mydumper
   sudo apt-get install mydumper  # Debian/Ubuntu
   sudo yum install mydumper      # CentOS/RHEL
   ```

4. **增量备份问题**
   - 检查快照文件权限
   - 验证 `INTERVAL_DAYS` 设置

### 日志位置

- 全局日志：`/var/log/backup/`
- 任务日志：由 `logBaseDir` 指定（默认 `/var/log/backup/<config_name>/`）

## 更新日志

### v2.2 (2026)
- ✅ 真正的增量备份：每次基于上一次的快照（之前每天都基于周期基准，实际是差异备份）
- ✅ 新增 `FILE_MODE` / `BACKUP_FILE_MODE`：`incremental`（默认）或 `differential`
- ✅ 备份文件名带类型后缀：`-full` / `-inc` / `-diff`
- ✅ tar 失败时快照回滚；tar 返回码 1 视为成功
- ✅ tar 以 nice / ionice 低优先级运行

### v2.1 (2024)
- ✅ 修复逻辑错误 (CHECKTYPE 判断)
- ✅ 添加 MySQL 配置文件支持
- ✅ 改进错误处理机制
- ✅ 添加备份验证功能
- ✅ 改进日志系统
- ✅ 更新安全配置
- ✅ 移除敏感信息

### v2.0 (2014/11/10)
- 支持多种备份引擎

### v1.0 (2014/10/23)
- 初始版本

## 许可证

请查看 LICENSE 文件

## 作者

Author: Ryanlau <showq#qq.com>

## 贡献

欢迎提交 Issue 和 Pull Request！

## 相关链接

- [mydumper 文档](https://github.com/mydumper/mydumper)
- [MySQL 备份最佳实践](https://dev.mysql.com/doc/refman/8.0/en/backup-and-recovery.html)
