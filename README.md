# 容器内一键启动 Clash 代理并安装 Codex

在 Linux 容器里运行一条命令。脚本读取你提供的 Clash/Mihomo YAML，在容器的回环地址启动 Mihomo，通过该代理安装官方 Codex CLI，然后打开 Codex。首次使用时按 Codex 提示登录。 [Codex CLI 官方文档](https://learn.chatgpt.com/docs/codex/cli)

## Quick Start

以下两种方式都从**你要使用 Codex 的项目目录**运行。第一次启动时，按提示登录。

### 容器能访问共享目录

在能访问 GitHub 的机器上，将源码克隆到共享目录一次。下面假设现有的 `clash-for-linux` 也位于 `/shared`：

```bash
git clone https://github.com/rascal-yang/codex-container-bootstrap.git /shared/codex-container-bootstrap
```

以后在每个新容器里运行：

```bash
BOOTSTRAP_ASSETS_DIR=/shared/clash-for-linux/runtime \
  bash /shared/codex-container-bootstrap/setup.sh /shared/clash-for-linux/runtime/config.yaml
```

### 容器连不上 GitHub，也没有共享的 Clash 运行目录

把已生成的归档复制到容器，并把现有 Clash YAML 只读挂载到 `/run/secrets/clash.yaml`。假设归档已复制到 `/tmp`：

```bash
tar -xzf /tmp/codex-container-bootstrap-linux-amd64.tar.gz -C /tmp
bash /tmp/codex-container-bootstrap/setup.sh /run/secrets/clash.yaml
```

归档的 CPU 架构须与容器匹配。Clash YAML 可能含节点凭据，请留在自己的存储里。如果它引用外部代理提供者，请确保容器能访问相应文件或地址。只有订阅链接时，先用已配置的 `clash-for-linux` 生成完整 YAML。

## 安装与登录

单独安装并显示版本：

```bash
bash /tmp/codex-container-bootstrap/setup.sh --install-only /run/secrets/clash.yaml
```

后续也用 `setup.sh` 启动 Codex，让会话走代理。可以在 YAML 路径后加上 `login --device-auth` 等 Codex 参数。脚本优先使用 PATH 上已有的 Codex。Mihomo 随该次命令退出，代理变量只在脚本及其子进程中生效。

## 从现有 clash-for-linux 制作分发包

在一个已有 `clash-for-linux` 的环境里克隆此仓库。使用与目标容器操作系统和 CPU 架构匹配的运行文件。

```bash
bash pack.sh /path/to/clash-for-linux/runtime ./codex-container-bootstrap.tar.gz
```

归档包含脚本、Mihomo、yq 和可用的 GEO 数据。Clash YAML、订阅信息和 Codex 凭据通过各自的容器挂载或登录流程提供。仓库可在有 GitHub 访问能力的设备上克隆，再将归档传入新容器。准备好的归档可在容器尚未连通 GitHub 时启动代理。下载 Codex 仍需要可用的代理出口。

## 检查

```bash
bash setup.sh --check /run/secrets/clash.yaml
```

容器需要 Bash、常用 Linux 命令、`curl` 和用户目录写权限。安装不需要 root、systemd 或 TUN。代理只监听 `127.0.0.1`，默认端口为 `17890`。端口冲突时可设置 `BOOTSTRAP_PROXY_PORT`。
