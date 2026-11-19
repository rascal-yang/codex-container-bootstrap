# 容器内一键启动 Clash 代理并安装 Codex

在 Linux 容器里运行一条命令。脚本读取你提供的 Clash/Mihomo YAML，在容器的回环地址启动 Mihomo，通过该代理安装官方 Codex CLI，然后打开 Codex。首次使用时按 Codex 提示登录。 [Codex CLI 官方文档](https://learn.chatgpt.com/docs/codex/cli)

## 在新容器中使用

把打包文件解压到共享目录，或复制进容器后解压。将现有的完整 Clash YAML 通过共享目录或只读挂载提供给容器。已有 `clash-for-linux` 用户可使用其 `runtime/config.yaml`。如果 YAML 引用了外部代理提供者，请确保引用能在容器中访问。只有订阅链接时，可先在已配置的环境中生成完整 YAML。

从要交给 Codex 的工作目录运行：

```bash
bash /opt/codex-container-bootstrap/setup.sh /run/secrets/clash.yaml
```

单独安装并显示版本：

```bash
bash /opt/codex-container-bootstrap/setup.sh --install-only /run/secrets/clash.yaml
```

要让后续 Codex 会话继续走代理，用第一条命令启动，也可以在 YAML 路径后加上 `login --device-auth` 等 Codex 参数。每次运行会使用 PATH 上已有的 Codex，找不到时才安装。Mihomo 随该次命令退出，代理变量只在脚本及其子进程中生效。

## 从现有 clash-for-linux 制作分发包

在一个已有 `clash-for-linux` 的环境里克隆此仓库。使用与目标容器操作系统和 CPU 架构匹配的运行文件。

```bash
bash pack.sh /path/to/clash-for-linux/runtime ./codex-container-bootstrap.tar.gz
```

归档包含脚本、Mihomo、yq 和可用的 GEO 数据。Clash YAML、订阅信息和 Codex 凭据通过各自的容器挂载或登录流程提供。仓库可在有 GitHub 访问能力的设备上克隆，再将归档传入新容器。准备好的归档可在容器尚未连通 GitHub 时启动代理。下载 Codex 仍需要可用的代理出口。

如果目标容器已挂载完整的 `clash-for-linux/runtime`，亦可用仓库中的脚本直接运行：

```bash
BOOTSTRAP_ASSETS_DIR=/path/to/clash-for-linux/runtime \
  bash setup.sh /run/secrets/clash.yaml
```

## 检查

```bash
bash setup.sh --check /run/secrets/clash.yaml
```

容器需要 Bash、常用 Linux 命令、`curl` 和用户目录写权限。安装不需要 root、systemd 或 TUN。代理只监听 `127.0.0.1`，默认端口为 `17890`。端口冲突时可设置 `BOOTSTRAP_PROXY_PORT`。
