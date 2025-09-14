
# FZU Router Login Scripts

该文件夹用于在路由器（如小米路由器 / OpenWrt）上实现 **福州大学校园网自动登录**。

因为部分路由器无法更新 `opkg` 软件库，同时也无法下载其他软件，只能使用系统自带的软件。

## 依赖说明

该脚本仍然需要 `curl`、`sed`、`awk` 等必要软件，请在运行此脚本前自测是否有相关依赖。

## 文件说明

- **`fzu-router-login.sh`**
  - 实现校园网登录逻辑。
  - 会根据 `/etc/fzu-login.conf` 中的配置（学号、密码）自动完成认证。如果位于其他路径，请修改脚本中的 `CONFIG_FILE` 。
  - 可手动执行：
    ```bash
    sh /etc/fzu-router-login.sh
    ```

- **`fzu-login.conf`**
  - 配置文件，保存登录所需的信息。
  - 示例：
    ```ini
    username=""
    password=""
    user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0"
    ```

## 在 OpenWrt 上使用

由于 OpenWrt 没有 `systemd`，请使用 `crontab` 来周期性执行 `fzu-router-login.sh`：

1. 编辑定时任务（一般为vim编辑器，自行学习相关操作）：
   ```bash
   crontab -e
    ````

2. 添加以下内容（每 30 分钟执行一次，有无日志二选一）：

   ```cron
   # 无日志
   */30 * * * * /bin/sh /etc/fzu-router-login.sh
   # 有日志
   */30 * * * * /bin/sh /etc/fzu-router-login.sh >> /tmp/fzu-login.log 2>&1
   ```
3. 保存并重启 cron：

   ```bash
   /etc/init.d/cron restart
   ```

## 调试

* 查看日志输出，确认登录是否成功：

  ```bash
  # 首次使用
  /etc/fzu-router-login.sh >> /tmp/fzu-login.log 2>&1
  # 查看日志
  tail -n 200 /tmp/fzu-login.log
  ```
* 若提示 `Already online. Exiting.`，表示已经登录成功。

* 如果一切正常，再把脚本加入定时任务（cron），以便定期检测并登录。

## 注意事项

* 脚本需放置在 `/etc/` 或其他可执行目录下，并赋予执行权限：

  ```bash
  chmod +x /etc/fzu-router-login.sh
  ```
* 请确保路由器已正确配置 WAN 接口（能获取校园网分配的 IP/MAC）。

## 上传文件

### FTP
若路由器已配置好FTP，则可以在Windows资源管理器中输入路径 `ftp://{ip}:{port}/path` 使用。

### SFTP
如果路由器的ssh使用的是 `openssh`，一般可以使用 `sftp` 进行文件传输，建议借助 `xftp`、`winscp` 等软件进行可视化的文件管理。

### TFTP
如果路由器的ssh使用的是 `busybox`，则一般只能进行 `tftp` 传输，可使用 `tftpd64` 进行文件传输。

### HTTP + curl

1. 先安装 `Python` 等可以在本机上开启http服务的软件

    ```sh
    # 在本机含有 fzu-router-login.sh 和 fzu-login.conf 的目录运行：
    python -m http.server 8000
    ```

2. 在路由器上执行：

    ```sh
    curl -o /etc/fzu-router-login.sh http:/{本机局域网ip}:8000/fzu-router-login.sh
    chmod +x /etc/fzu-router-login.sh
    curl -o /etc/fzu-login.conf http://{本机局域网ip}:8000/fzu-login.conf
    chmod 600 /etc/fzu-login.conf
    ```
