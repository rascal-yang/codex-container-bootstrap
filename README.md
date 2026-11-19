# 容器内一键启动 Clash 代理并安装 Codex

从空的 Linux amd64 或 arm64 容器开始。输入 Clash/Mihomo 订阅链接，脚本就会下载配置、启动本地代理并安装 Codex CLI。首次使用时按 Codex 提示登录。 [Codex CLI 官方文档](https://learn.chatgpt.com/docs/codex/cli)

## Quick Start

运行 `setup.sh` 后，在提示处粘贴 **Clash/Mihomo 订阅链接**并按回车。终端会隐藏输入。链接需要返回包含代理节点或代理提供者的 Clash/Mihomo YAML，并且订阅服务器要能在代理启动前访问。

### 容器能访问 GitHub

容器需要 Git、Bash、curl、gzip 和常用 Linux 命令。从你要使用 Codex 的项目目录运行：

```bash
git clone https://github.com/rascal-yang/codex-container-bootstrap.git /tmp/codex-container-bootstrap
bash /tmp/codex-container-bootstrap/prepare-assets.sh &&
  bash /tmp/codex-container-bootstrap/setup.sh
```

准备脚本从上游 GitHub Releases 下载 Mihomo、yq 和 GEO 数据，保存在仓库的 `assets/` 目录。之后直接运行 `setup.sh` 即可。 [Mihomo](https://github.com/MetaCubeX/mihomo/releases) · [yq](https://github.com/mikefarah/yq/releases) · [GEO 数据](https://github.com/MetaCubeX/meta-rules-dat/releases)

### 容器起初连不上 GitHub

在能访问 GitHub 的机器上克隆仓库并制作归档。按目标容器的架构选 `amd64` 或 `arm64`：

```bash
git clone https://github.com/rascal-yang/codex-container-bootstrap.git
cd codex-container-bootstrap
bash prepare-assets.sh amd64
bash pack.sh ./assets ./codex-container-bootstrap-linux-amd64.tar.gz
```

把归档复制到新容器的 `/tmp`，从要使用 Codex 的项目目录运行：

```bash
tar -xzf /tmp/codex-container-bootstrap-linux-amd64.tar.gz -C /tmp
bash /tmp/codex-container-bootstrap/setup.sh
```

归档包含脚本、Mihomo、yq 和 GEO 数据。新容器需要 Bash、curl、tar 及常用 Linux 命令。只要 Clash 配置能连通代理出口，Codex 安装器就会通过代理下载。

### 使用本地 YAML

如果容器连不上订阅服务器，先在能访问订阅的机器上下载 Clash/Mihomo YAML，再将它只读挂载到容器：

```bash
bash /tmp/codex-container-bootstrap/setup.sh /run/secrets/clash.yaml
```

订阅链接和 YAML 中可能有节点凭据，请保存在自己的存储里。YAML 引用的外部代理提供者也需要能从容器访问。

## 安装与排查

- 用 `setup.sh --install-only` 安装并显示 Codex 版本。
- 用 `setup.sh --check` 下载并检查配置，无需启动代理。也可以在选项后指定本地 YAML。
- 用 `setup.sh --subscription login --device-auth` 使用设备码登录。
- 后续仍可用 `setup.sh` 打开 Codex。脚本优先使用 PATH 上已有的 Codex。
- Mihomo 随本次命令退出，代理变量只在脚本及子进程中生效。默认监听 `127.0.0.1:17890`，端口冲突时可设置 `BOOTSTRAP_PROXY_PORT`。
- 已有 `clash-for-linux` 运行目录时，可将 `BOOTSTRAP_ASSETS_DIR` 指向该目录以复用组件。
