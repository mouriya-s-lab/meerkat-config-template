# meerkat-config-template

Meerkat 部署实例的配置仓库模板：议会（[meerkat-council](https://github.com/mouriya-s-lab/meerkat-council)）、守护（[meerkat-guardians](https://github.com/mouriya-s-lab/meerkat-guardians)）、[Meerkat](https://github.com/mouriya-s-lab/meerkat) 与 omp-dispatch 的配置，议会、守护与 Meerkat web 三个 Komodo Stack 的 compose，以及镜像构建。用 GitHub 的 **Use this template** 生成实例仓库，再填入下面的占位。

## 填写占位

占位写作 `<名字>`，都不是可用的值：`<project-number>` 不能解析为数字，其余占位在程序访问 GitHub、模型或主机时失败。`grep -rn '<[a-z-]*>' --include='*.yaml' .` 列出剩下的占位。

| 占位 | 含义 | 出现位置 |
|---|---|---|
| `<owner>` | 议题、代码、设计与配置仓库所在的 GitHub owner | `shared/repos.yaml`、`guardians/bases.yaml`、`guardians/routing.yaml`、`meerkat/meerkat.yaml`、`stacks/meerkat-web/compose.yaml` |
| `<agenda-repo>` | 议会读写议题的 PM 仓库 | `shared/repos.yaml` |
| `<project-number>` | `<owner>` 下承载议题的 GitHub Project 编号，字段见 `shared/project.yaml` | `shared/repos.yaml` |
| `<code-repo>`、`<design-repo>` | 守护者代读的代码仓库与设计仓库 | `shared/repos.yaml`、`guardians/bases.yaml`、`guardians/routing.yaml` |
| `<code-repo-checkout-on-operator-mac>` | 代码仓库在操作员 Mac 上的检出目录，omp-dispatch 在这里启动实现会话 | `shared/repos.yaml` |
| `<config-repo>` | 由本模板生成的实例仓库名；Meerkat 的配置页向它提交改动 | `meerkat/meerkat.yaml`、`stacks/meerkat-web/compose.yaml` |
| `<model>` | omp 模型 id（`provider/model`），议会席位、代读与守护基座使用 | `council/seats.yaml`、`council/proxy-readers.yaml`、`guardians/bases.yaml`、`guardians/routing.yaml` |
| `<host>` | 运行三个 Stack 的 Docker 主机，在局域网或 mesh 上的地址 | `meerkat/meerkat.yaml`、`dispatch/delivery.yaml`、各 compose 的注释 |
| `<operator-mac-address>` | 操作员 Mac 在 mesh 上的地址；web 版的 `/dispatch/*` 转到它的 47593 端口 | `stacks/meerkat-web/compose.yaml` |
| `<council-hook-hostname>` | 议会 webhook 的公网主机名，Cloudflare tunnel 把 `/webhook` 回源到 `app:7420` | `stacks/meerkat-council/compose.yaml` 的注释 |

`guardians/bases.yaml` 与 `guardians/routing.yaml` 各列一个代码仓库和一个设计仓库；仓库更多时按同样的形状加条目。

## 目录

| 路径 | 内容 | 读者 |
|---|---|---|
| `shared/` | `repos.yaml`、`project.yaml` | 所有程序 |
| `council/` | 委员会配置、席位与 omp 提示词 | meerkat-council |
| `guardians/` | 守护者配置、路由与 omp 提示词 | meerkat-guardians |
| `meerkat/` | `meerkat.yaml`（配置仓库与读者、各端地址、刷新与筛选）、`theme.json`（设计 token） | Meerkat（macOS 版以 `PM_CONFIG_DIR` 指向实例仓库检出；web 版由 Stack 挂载） |
| `dispatch/` | 交付设置 | omp-dispatch（插件设置 `pmConfigDir` 指向实例仓库检出，`omp plugin config set omp-dispatch pmConfigDir <path>`） |
| `stacks/<stack>/compose.yaml` | Stack `meerkat-guardians`、`meerkat-council`、`meerkat-web` | Komodo |
| `images/<image>/` | 各镜像的 Dockerfile 与 entrypoint | `scripts/release.sh` |

Stack 把 `shared/` 和各自的配置目录只读挂进容器，配置变更随 Stack 重新部署生效。

`council/omp/config.yml`、`guardians/omp/config.yml` 设 `defaultThinkingLevel: low`；守护的代读会话从基座分叉并沿用基座会话的思考级别，所以改动这一项并重新部署后，要对每个基座重新预热（`POST /v1/bases/{id}/rewarm`）才生效。

两份 omp 配置同时设 `providers.streamFirstEventTimeoutSeconds: 20`：omp 等待模型网关的首个流事件超过 20 秒即中止该请求并重试。默认的 300 秒会让网关偶发的数十秒首字节停顿变成议会与守护会话干等，直到 `sessionTimeoutSeconds`（300 秒）耗尽。

`council/council.yaml` 与 `guardians/guardians.yaml` 的 `launchLink` 取同一个值：议会与守护建出的实现 issue 里的启动链接指向同一个 omp-dispatch，改 dispatch 的地址或前端时两处一起改。

## Meerkat

`meerkat-web` Stack 运行 `meerkat-local/meerkat-web:current`：镜像只含 Meerkat 的 web 站点、Meerkat 仓库的 `deploy/Caddyfile` 与 GitHub 凭据，不含配置。compose 把实例仓库检出的 `meerkat/`、`shared/` 只读挂到 `/config/meerkat`、`/config/shared`（`CONFIG_DIR=/config`），页面启动时从 `/config/*` 读取，所以配置改动随 Stack 重新部署、刷新页面生效，不需要重建镜像。站点在 `http://<host>:8088/`，即 `meerkat/meerkat.yaml` 的 `targets.web` 所指的源。

Meerkat 的配置页把改动提交到实例仓库 main（`config.repo`、`config.branch`）。web 版经 Caddy 的 `/gh/*` 转发 GitHub API：读请求放行，写请求只放行对 `CONFIG_REPO` 的 contents `PUT`，其余写入一律 `403`。dispatch 的配置校验也走站点同源代理：`targets.web.dispatch` 为 `http://<host>:8088/dispatch`，Caddy 把 `/dispatch/*` 转给 `DISPATCH_URL`，即操作员 Mac 上 omp-dispatch 校验监听器（omp-dispatch 的 `configCheckHost` 设为 `0.0.0.0` 才能从 mesh 访问）；macOS 版直连 `127.0.0.1:47593`。

## 发布

```sh
PM_RELEASE_HOST=<ssh 目标> KM_PROFILE=<km profile> scripts/release.sh [--load-only] meerkat-guardians meerkat-council meerkat-web
```

在操作员 Mac 上运行：从实现仓库 `origin/main` 构建镜像，带凭据的镜像经 `docker save | ssh $PM_RELEASE_HOST docker load` 直达 Docker 主机，不经 registry；不带 `--load-only` 时随后用 `km x deploy-stack` 重新部署对应 Stack（`KM_PROFILE` 未设时用 km 的默认 profile）。缺少凭据文件或构建工具时在构建前退出并列出缺少的项。

三个 Stack 在 Komodo 里各自声明，`run_directory` 指向实例仓库检出里的 `stacks/<stack>`。要让实例仓库 main 的每次 push 自动重新部署，给实例仓库加一个 push webhook，指向对这三个 Stack 执行 DeployStackIfChanged 的 Komodo Procedure。

实现仓库默认取实例仓库主 checkout 所在目录下的同名 clone（`meerkat-guardians`、`meerkat-council`、`meerkat`），`PM_SRC_ROOT` 可改。`meerkat-web` 用 `nsh package --target web` 构建站点（需要 Homebrew llvm 与 `wasm-bindgen`，见 Meerkat 的 README），镜像标签记下 Meerkat 的提交（`org.opencontainers.image.revision`）与实例仓库的提交（`meerkat-config.revision`）。

`meerkat-web` 的编译缓存在 `${XDG_CACHE_HOME:-~/.cache}/meerkat-config/meerkat`：`src/` 是每次发布重新导出的 Meerkat `origin/main`，`target/` 是 cargo 的编译产物，跨发布保留，只重编上次以来变化的部分。缓存里没有凭据；不发布时随时可删，删后下一次发布全量编译（约 5 分钟）。

## 凭据

凭据只从本机拷入镜像，构建上下文在 `/tmp` 下，退出即删：

| 镜像 | 凭据 |
|---|---|
| `meerkat-guardians`、`meerkat-council` | `~/.omp/agent/agent.db`、`~/.omp/agent/models.yml`、`gh auth token` |
| `meerkat-council` | `~/.config/meerkat-config/council-webhook-secret`（首次发布时生成；同一个值填进议题仓库 webhook 的 secret） |
| `meerkat-council-tunnel` | `~/.config/meerkat-config/council-tunnel-token`（Cloudflare tunnel 的 connector token） |
| `meerkat-web` | `gh auth token`（与议会、守护镜像同一凭据；写入范围只由 Caddy 的 `/gh/*` 守卫限制） |

议题仓库的 webhook 指向 `https://<council-hook-hostname>/webhook`，内容类型 JSON，订阅 `issues`、`issue_comment`、`issue_dependencies`、`sub_issues` 事件。
