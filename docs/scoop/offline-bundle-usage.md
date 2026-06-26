# Scoop 离线 Bundle：Build、Install、Update 脚本使用与实现说明

> **适用范围**：本文对应一套“外网构建离线 Bundle → 同步到内网 → 内网首次安装/后续更新”的 Scoop 离线部署方案。
>
> **默认路径**：外网与内网均以 `D:\scoop` 作为 Scoop 根目录，以 `D:\ScoopOfflineBundle` 作为离线 Bundle 目录。路径可以通过脚本参数调整，但三个脚本应保持一致。
>
> **Bundle 格式版本**：`FormatVersion = 1`。

---

## 1. 如何使用

### 1.1 三个脚本各自应该在哪台机器执行

| 脚本 | 执行位置 | 什么时候执行 | 主要用途 |
|---|---|---|---|
| `Build-ScoopOfflineBundle.ps1` | **外网机器** | 首次部署前，以及每次准备发布新版本前 | 下载所需安装包并生成完整离线 Bundle |
| `Install-ScoopOfflineBundle.ps1` | **内网机器** | 仅第一次部署 Scoop，或确认要完全重装时 | 从 Bundle 初始化 Scoop，并安装目标软件 |
| `Update-ScoopOfflineBundle.ps1` | **内网机器** | 内网已经完成首次安装后的每次更新 | 替换 Scoop 核心、bucket、cache，并升级已安装目标软件 |

**重要原则：**

- 外网机器不运行 `Install-ScoopOfflineBundle.ps1` 或 `Update-ScoopOfflineBundle.ps1`。
- 内网机器不运行无参数的 `scoop update`，也不需要访问 GitHub / Scoop 仓库。
- `Install-ScoopOfflineBundle.ps1` 不是更新脚本。内网首次安装成功后，后续一律使用 `Update-ScoopOfflineBundle.ps1`。
- 不要在“后续更新”时带 `-Force` 重跑安装脚本；该参数会删除整个 Scoop 根目录。

### 1.2 首次部署流程

#### 第一步：外网刷新 Scoop 与 bucket

在外网机器打开 PowerShell：

```powershell
scoop update
```

这一步用于刷新 Scoop 核心和本地 `main` / `extras` bucket 的 manifest。它不等同于把所有已安装应用都升级；离线 Bundle 中目标软件的实际版本由后续 Build 脚本读取更新后的 manifest 并下载决定。

如系统执行策略禁止脚本运行，再仅对当前窗口临时放开：

```powershell
Set-ExecutionPolicy Bypass -Scope Process
```

该设置只影响当前 PowerShell 进程；关闭窗口后自动失效。

#### 第二步：外网生成 Bundle

```powershell
.\Build-ScoopOfflineBundle.ps1
```

默认输出：

```text
D:\ScoopOfflineBundle
├─ scoop-core.zip
├─ buckets.zip
├─ cache\
├─ bundle.json
└─ README.txt
```

#### 第三步：同步 Bundle 到内网

使用你现有的网络复制脚本同步**整个专用目录**：

```text
外网：D:\ScoopOfflineBundle
内网：D:\ScoopOfflineBundle
```

建议把该任务作为独立镜像目录处理：

```powershell
@{
    Title     = 'Scoop 离线安装包同步'
    Enabled   = $true
    SourceDir = "\\$client\d$\ScoopOfflineBundle"
    DestDirs  = @(
        'D:\ScoopOfflineBundle'
    )
    Mode      = 'Mirror'
}
```

`Mirror` 只适用于这个专用 Bundle 目录；**不要**对 `D:\scoop` 使用 `Mirror`。

#### 第四步：内网首次安装

确认内网 `D:\scoop` 不存在或为空后执行：

```powershell
Set-ExecutionPolicy Bypass -Scope Process
.\Install-ScoopOfflineBundle.ps1
```

如果 `D:\scoop` 只是此前首次安装失败留下的半成品，且确认其中没有要保留的数据：

```powershell
.\Install-ScoopOfflineBundle.ps1 -Force
```

`-Force` 会删除整个 `D:\scoop`，包括已安装应用、配置持久化目录和旧缓存；不要用于正常更新。

#### 第五步：关闭并重新打开 PowerShell

重新打开终端后验证：

```powershell
scoop list
scoop search vscode
scoop search cursor

where.exe scoop
where.exe code
where.exe clangd
where.exe cmake
where.exe ninja
where.exe clang
```

### 1.3 后续更新流程

每次外网准备更新时，执行以下流程：

```text
外网：scoop update
外网：Build-ScoopOfflineBundle.ps1
网络同步：覆盖内网 D:\ScoopOfflineBundle
内网：Update-ScoopOfflineBundle.ps1
重新打开 PowerShell
```

外网：

```powershell
scoop update
.\Build-ScoopOfflineBundle.ps1
```

内网：先关闭 VS Code、clangd、CMake、Ninja 及使用 LLVM 的编译进程，然后执行：

```powershell
Set-ExecutionPolicy Bypass -Scope Process
.\Update-ScoopOfflineBundle.ps1
```

若确认允许脚本自动结束这些进程：

```powershell
.\Update-ScoopOfflineBundle.ps1 -StopRunningProcesses
```

只想先同步 Scoop 核心、bucket 和 cache，暂不升级已有应用：

```powershell
.\Update-ScoopOfflineBundle.ps1 -SkipAppUpdate
```

### 1.4 新增一个软件时怎么做

假设你将来要加入 Cursor：

1. 在**外网 Build 脚本**的 `$RequestedPackages` 中添加：

   ```powershell
   'extras/cursor'
   ```

2. 外网执行：

   ```powershell
   scoop update
   .\Build-ScoopOfflineBundle.ps1
   ```

3. 同步新 Bundle 到内网。
4. 内网先运行更新脚本，使新 manifest 和 cache 到位：

   ```powershell
   .\Update-ScoopOfflineBundle.ps1
   ```

5. 再手动离线安装新包：

   ```powershell
   scoop install extras/cursor --no-update-scoop
   ```

更新脚本默认只更新**已经安装**的软件，不会自动安装新加入 Bundle 的软件。这是为了防止一次 Bundle 更新意外改变内网软件集合。

---

## 2. 整体架构与数据流

```text
┌──────────────────────────── 外网机器 ────────────────────────────┐
│                                                                    │
│  D:\scoop                                                          │
│  ├─ apps\scoop\current          Scoop 核心                        │
│  ├─ buckets\main / extras        本地 manifest                    │
│  └─ cache                        已下载的原始安装包               │
│                                                                    │
│                Build-ScoopOfflineBundle.ps1                       │
│                                  │                                 │
│                                  ▼                                 │
│  D:\ScoopOfflineBundle                                              │
│  ├─ scoop-core.zip              已压缩的 Scoop 核心                │
│  ├─ buckets.zip                 已压缩的 main / extras bucket     │
│  ├─ cache\                      仅保留所需软件及依赖的安装包       │
│  ├─ bundle.json                 版本、文件清单、哈希               │
│  └─ README.txt                                                      │
└──────────────────────────────────┬─────────────────────────────────┘
                                   │
                         网络共享 / 同步脚本
                                   │
┌──────────────────────────── 内网机器 ────────────────────────────┐
│                                  ▼                                 │
│  D:\ScoopOfflineBundle                                             │
│                                  │                                 │
│         ┌────────────────────────┴────────────────────────┐        │
│         ▼                                                 ▼        │
│ Install-ScoopOfflineBundle.ps1             Update-ScoopOfflineBundle.ps1
│ 第一次部署                                   后续版本更新            │
│         │                                                 │        │
│         └────────────────────────┬────────────────────────┘        │
│                                  ▼                                 │
│  D:\scoop                                                         │
│  ├─ apps\scoop\current          当前 Scoop 核心                    │
│  ├─ apps\<应用>\<版本>           应用实际版本目录                  │
│  ├─ apps\<应用>\current          Scoop 创建的 Junction             │
│  ├─ buckets\main / extras        离线 manifest                     │
│  ├─ cache                        可复用的离线安装包                │
│  ├─ persist                      应用持久化数据，例如 VS Code data  │
│  ├─ shims                        命令入口                          │
│  └─ offline-backups              更新前的 core / bucket 回滚备份   │
└───────────────────────────────────────────────────────────────────┘
```

核心思想是：跨网络传输的是少量压缩包和安装文件，而不是 `apps\llvm`、`apps\vscode` 等已解压的几十万小文件。

- 网络复制阶段更适合传输几个大文件或少量 cache 文件。
- 内网应用安装阶段在本机进行解压和创建文件，避免 SMB 对大量小文件的逐项开销。
- `current` Junction、应用 shims、应用目录会由内网 Scoop 正常安装流程自行创建，不迁移外网路径。

---

## 3. Bundle 内容与边界

### 3.1 Bundle 目录内容

| 项目 | 来源 | 作用 |
|---|---|---|
| `scoop-core.zip` | 外网 `apps\scoop\current` | 内网运行 Scoop 所需的核心脚本和库 |
| `buckets.zip` | 外网 `buckets\main`、`buckets\extras` | 软件 manifest，决定版本、URL、哈希、解压、环境变量等安装规则 |
| `cache\` | 外网 Scoop cache | 已下载的原始安装包，内网安装时直接命中，不走网络下载 |
| `bundle.json` | Build 脚本生成 | Bundle 格式、架构、软件清单、cache 文件长度和 SHA-256 |
| `README.txt` | Build 脚本生成 | Bundle 基本信息和部署提示 |

### 3.2 Bundle 明确不包含的内容

| 未包含内容 | 原因 |
|---|---|
| `apps\llvm`、`apps\vscode` 等已安装应用目录 | 文件数量大，跨网复制慢；内网直接从 cache 安装更可靠 |
| 应用的 `current` Junction | Junction 常绑定本机路径，不应跨机器复制 |
| 普通应用 shims | shim 可能引用旧版本、旧路径；应由内网 Scoop 重建 |
| `persist\vscode` 等用户配置 | 可能很大且包含个人设置、扩展；按需要单独同步 |
| bucket 的 `.git` 目录 | 离线 `search/install` 不需要 Git 历史；排除后 Bundle 更小 |

### 3.3 `bundle.json` 的关键字段

构建脚本生成的元数据大致包含：

```json
{
  "FormatVersion": 1,
  "CreatedAt": "2026-06-26 12:00:00",
  "Architecture": "64bit",
  "RequestedPackages": [
    "7zip",
    "clangd",
    "cmake",
    "ninja",
    "llvm",
    "extras/vscode"
  ],
  "DownloadedPackages": [
    {
      "Spec": "llvm",
      "Bucket": "main",
      "Name": "llvm",
      "Version": "...",
      "CacheFiles": ["llvm#...#..."]
    }
  ],
  "CacheFiles": [
    {
      "Name": "llvm#...#...",
      "Length": 123456789,
      "Sha256": "..."
    }
  ],
  "ScoopCoreSha256": "...",
  "BucketsSha256": "..."
}
```

内网脚本先验证 zip 的 SHA-256，再逐项验证 cache 的文件长度和 SHA-256；验证失败时不会继续安装或替换本地核心目录。

---

## 4. `Build-ScoopOfflineBundle.ps1`：外网构建脚本

### 4.1 目标

Build 脚本将外网 Scoop 环境固定成一个可复制的离线快照：

```text
当前 Scoop 核心
+ 当前 main / extras manifest
+ 与当前 manifest 对应的下载缓存
+ 目标软件及其依赖信息
= 一个可在内网安装或升级的 Bundle
```

它的输出是新的完整 Bundle，不是在旧 Bundle 上累积追加杂项文件。

### 4.2 主要参数

| 参数 | 默认值 | 说明 |
|---|---:|---|
| `ScoopRoot` | `D:\scoop` | 外网 Scoop 根目录 |
| `BundleRoot` | `D:\ScoopOfflineBundle` | 输出目录 |
| `CacheRoot` | 空 | 可覆盖默认 cache；为空时使用 `$env:SCOOP_CACHE` 或 `D:\scoop\cache` |

### 4.3 Build 脚本的执行步骤

#### 步骤 1：标准化并校验路径

脚本会：

- 解析 `ScoopRoot`、`BundleRoot`、`CacheRoot` 为绝对路径；
- 确认 `apps\scoop\current\bin\scoop.ps1` 存在；
- 确认 cache 目录存在；
- 检查 Bundle 根目录不与 Scoop 根目录相同；
- 检查系统架构。当前设计面向 x64 Windows Bundle。

这样可避免把 Bundle 生成到 Scoop 根目录内部，或把不完整 Scoop 环境误用于离线发布。

#### 步骤 2：定义目标软件集合

默认目标集合：

```powershell
$RequestedPackages = @(
    '7zip',
    'clangd',
    'cmake',
    'ninja',
    'llvm',
    'extras/vscode'
)
```

其中 `7zip` 被明确加入，是因为部分软件包需要 7-Zip 或相关解包流程。将新软件加入这个列表后，下一次构建会将其 manifest 对应的安装包带入 Bundle。

#### 步骤 3：解析依赖并下载到外网 cache

脚本调用：

```powershell
scoop depends <包名>
scoop download --no-update-scoop <包集合>
```

目的：

1. 收集目标应用的显式依赖或安装辅助工具；
2. 仅下载，不安装；
3. 将下载内容保存在外网 Scoop cache；
4. 防止 `download` 自己在构建过程中又自动更新 Scoop，避免“下载时 manifest 又发生变化”。

构建前的 `scoop update` 已经决定本次 Bundle 使用哪一版 Scoop 与 bucket；Build 阶段只按该快照下载对应安装包。

#### 步骤 4：根据 manifest 精确筛选 cache 文件

脚本读取：

```text
D:\scoop\buckets\<bucket>\bucket\<app>.json
```

并取得每个软件的 `version`。然后依据 Scoop cache 文件的命名约定，按以下前缀筛选：

```text
<应用名>#<manifest版本>#
```

例如：

```text
vscode#1.126.0#...
llvm#...
```

这一步的意义是：即使外网 cache 留有历史版本，Bundle 也只带走当前 manifest 所需要的版本，而不会把全部历史缓存打包进来。

#### 步骤 5：创建构建暂存目录

脚本不会直接在旧 `D:\ScoopOfflineBundle` 上边删边写，而是先构建到类似：

```text
D:\ScoopOfflineBundle.__building
```

这样在下载成功、压缩成功、元数据写入成功之前，旧 Bundle 仍然完整可用。

#### 步骤 6：压缩 Scoop 核心

Scoop 本身的目录特殊：

```text
D:\scoop\apps\scoop\current
```

它通常是 Scoop 核心真实目录，而不是普通应用的“版本目录 + `current` Junction”结构。因此 Build 脚本直接复制该目录到暂存区，再压缩为：

```text
scoop-core.zip
```

复制时排除 `.git`，因为离线运行 Scoop 不需要核心仓库的 Git 历史。

#### 步骤 7：压缩完整 `main` 与 `extras` bucket

脚本将外网：

```text
D:\scoop\buckets\main
D:\scoop\buckets\extras
```

复制到暂存区，并排除 `.git`，然后打包为：

```text
buckets.zip
```

选择完整 bucket 而不是只复制当前使用的几个 JSON manifest，原因是内网仍可以正常执行：

```powershell
scoop search vscode
scoop search cursor
```

但注意：**能搜索不等于能离线安装。** 只有对应安装包已经被放入 Bundle cache 的软件才能在完全断网的情况下安装。

#### 步骤 8：以硬链接或复制的方式放入 cache

如果 `CacheRoot` 和 `BundleRoot` 位于同一 NTFS 分区，脚本优先创建硬链接：

```text
D:\scoop\cache\<文件>
↕ 同一份 NTFS 文件数据
D:\ScoopOfflineBundle\cache\<文件>
```

优点：外网构建时不会因为 LLVM、VS Code 等大安装包在 D 盘额外占一份物理空间。

当 Bundle 被复制到内网时，网络同步工具会把它当作普通文件传输；硬链接这一实现细节不影响内网使用。

若不在同一磁盘或无法创建硬链接，脚本自动退化为普通 `Copy-Item`。

#### 步骤 9：生成 `bundle.json` 与 `README.txt`

脚本计算：

- `scoop-core.zip` 的 SHA-256；
- `buckets.zip` 的 SHA-256；
- 每个 cache 文件的长度和 SHA-256；
- 请求软件、依赖软件、版本、bucket、cache 文件映射；
- Bundle 的创建时间和架构。

这些信息用于内网的完整性校验和更新决策。

#### 步骤 10：原子化替换旧 Bundle

构建完成后，脚本将旧 Bundle 临时改名为备份目录，再将新的构建目录移动为正式：

```text
D:\ScoopOfflineBundle.__previous
D:\ScoopOfflineBundle
```

若替换过程中失败，脚本尝试恢复旧 Bundle。正常完成后会删除临时旧目录。

因此：

- **逻辑上**每次生成的 Bundle 都是完整新快照；
- **物理上**Build 过程会暂时保留旧 Bundle 作为替换期间的回退对象；
- 新 Bundle 不会继续积累上次 Bundle 内无关的旧 cache 文件。

---

## 5. `Install-ScoopOfflineBundle.ps1`：内网首次安装脚本

### 5.1 使用边界

该脚本只做首次部署。它要求：

```text
D:\scoop 不存在，或 D:\scoop 是空目录
```

若目录非空，脚本会停止，避免误覆盖已使用环境。只有显式传入 `-Force` 才会清空该目录。

### 5.2 主要参数

| 参数 | 默认值 | 说明 |
|---|---:|---|
| `BundleRoot` | `D:\ScoopOfflineBundle` | 同步后的 Bundle 目录 |
| `ScoopRoot` | `D:\scoop` | 内网 Scoop 安装目录 |
| `CacheRoot` | 空 | cache 位置；默认 `ScoopRoot\cache` |
| `Force` | 未启用 | 清空非空 ScoopRoot 后重新部署，仅适合首次失败恢复 |

### 5.3 Install 脚本的执行步骤

#### 步骤 1：验证 Bundle 基础文件

脚本检查以下文件是否存在：

```text
bundle.json
scoop-core.zip
buckets.zip
cache\
```

然后读取 `bundle.json`，确认：

- `FormatVersion` 为 `1`；
- Bundle 架构与内网机器一致；
- `scoop-core.zip` 的 SHA-256 匹配；
- `buckets.zip` 的 SHA-256 匹配。

任何一个检查失败都会终止，不会继续安装。

#### 步骤 2：检查目标 Scoop 根目录

- 不存在：创建目录并继续；
- 存在但为空：继续；
- 存在且非空：默认停止；
- 传入 `-Force`：删除整个 ScoopRoot 后继续。

此设计的目的，是把“首次部署”和“后续更新”严格分开。

#### 步骤 3：解压 Scoop 核心与 bucket

脚本把：

```text
scoop-core.zip → D:\scoop
buckets.zip    → D:\scoop\buckets
```

解压完成后，关键路径应存在：

```text
D:\scoop\apps\scoop\current\bin\scoop.ps1
D:\scoop\buckets\main\bucket
D:\scoop\buckets\extras\bucket
```

脚本会再次检查这些路径，确保 zip 内容层级正确。

#### 步骤 4：校验并复制 cache

对于 `bundle.json` 中每一项 `CacheFiles`：

1. 检查 Bundle 内对应文件存在；
2. 检查文件长度；
3. 校验 Bundle 文件 SHA-256；
4. 复制到本地 `CacheRoot`；
5. 再校验复制后文件的长度和 SHA-256。

若目标 cache 中已经存在同名且哈希相同的文件，则跳过复制。这样支持首次安装脚本在中断后重试时复用已成功复制的 cache。

#### 步骤 5：写入环境变量与引导 shim

脚本设置当前用户环境变量：

```text
SCOOP       = D:\scoop
SCOOP_CACHE = D:\scoop\cache
```

并把：

```text
D:\scoop\shims
```

加入用户 `Path`，且只在缺失时加入，避免重复追加。

由于此时应用还没有安装、应用 shim 还不存在，脚本先写入最小的 Scoop 引导 shim：

```text
D:\scoop\shims\scoop.cmd
D:\scoop\shims\scoop.ps1
```

它们只负责把 `scoop ...` 调度到：

```text
D:\scoop\apps\scoop\current\bin\scoop.ps1
```

普通应用的 shim（如 `code.cmd`、`clangd.exe` 对应 shim）仍由 Scoop 安装应用时创建。

#### 步骤 6：写入 `last_update`

脚本执行：

```powershell
scoop config last_update <当前时间>
```

目的是让当前 Scoop 知道本地核心和 bucket 刚刚已经同步过，减少安装流程中触发自动更新检查的可能。

#### 步骤 7：先安装 7zip，再安装请求软件

安装顺序是：

```text
7zip
→ clangd、cmake、ninja、llvm、extras/vscode
```

7zip 被先安装，是为了确保后续 `.7z`、MSI 等包的解压链路已具备。

安装命令显式带：

```powershell
--no-update-scoop
```

这表示安装时不自动更新 Scoop 核心。Scoop 会优先在 `SCOOP_CACHE` 中寻找与 manifest 匹配的缓存包；Bundle 已准备好对应 cache 时，内网无需联网下载。

### 5.4 Install 脚本会保留什么、会创建什么

| 项目 | 处理方式 |
|---|---|
| `D:\scoop\apps\scoop\current` | 从 `scoop-core.zip` 创建 |
| `D:\scoop\buckets\main/extras` | 从 `buckets.zip` 创建 |
| `D:\scoop\cache` | 从 Bundle cache 复制并校验 |
| `D:\scoop\apps\<app>` | 由 Scoop 安装创建 |
| `D:\scoop\apps\<app>\current` | 由 Scoop 安装创建为本机 Junction / 当前版本入口 |
| `D:\scoop\shims` | 先创建 Scoop 引导 shim，后由 Scoop 添加应用 shim |
| `D:\scoop\persist` | 由具体 manifest 或应用安装行为创建 |

---

## 6. `Update-ScoopOfflineBundle.ps1`：内网后续更新脚本

### 6.1 使用边界

Update 脚本要求内网已经完成首次部署，并且存在：

```text
D:\scoop\apps\scoop\current\bin\scoop.ps1
```

如果未找到该文件，脚本会明确提示应先运行首次安装脚本。

它不会删除：

```text
D:\scoop\apps\<应用>
D:\scoop\persist
D:\scoop\shims
D:\scoop\buckets\除 main/extras 外的其他 bucket
D:\scoop\cache 中已有旧文件
```

### 6.2 主要参数

| 参数 | 默认值 | 说明 |
|---|---:|---|
| `BundleRoot` | `D:\ScoopOfflineBundle` | 同步后的新 Bundle |
| `ScoopRoot` | `D:\scoop` | 已部署 Scoop 根目录 |
| `CacheRoot` | 空 | 优先读取用户 `SCOOP_CACHE`；否则使用 `ScoopRoot\cache` |
| `SkipAppUpdate` | 未启用 | 仅更新 Scoop 核心、bucket、cache，不更新应用 |
| `StopRunningProcesses` | 未启用 | 自动强制关闭 Code/clangd/clang/cmake/ninja 进程 |
| `KeepBackupCount` | `2` | 成功后保留最近多少份 core / bucket 回滚备份；`0` 为不保留 |

### 6.3 Update 脚本的执行步骤

#### 步骤 1：先验证新 Bundle，验证通过前不修改已部署 Scoop

脚本先检查：

```text
bundle.json
scoop-core.zip
buckets.zip
cache\
```

并校验：

- FormatVersion；
- CPU 架构；
- core zip 哈希；
- bucket zip 哈希；
- 每个 Bundle cache 文件的存在性、长度和 SHA-256。

这一步完成前，原有 `D:\scoop` 不会被替换。

#### 步骤 2：预解压到工作目录

脚本先解压到：

```text
D:\scoop\.offline-update\<时间戳-随机标识>\core
D:\scoop\.offline-update\<时间戳-随机标识>\buckets
```

并验证解压结构：

```text
apps\scoop\current\bin\scoop.ps1
main\bucket
extras\bucket
```

先预解压再切换，避免在正式目录里边解压边覆盖，降低中途失败风险。

#### 步骤 3：检测可能占用文件的进程

脚本检查：

```text
Code
clangd
clang
clang++
cmake
ninja
```

默认发现任意进程就停止更新，防止更新只完成一半。

- 手动关闭后重试：最安全；
- 加 `-StopRunningProcesses`：脚本调用 `Stop-Process -Force` 强制结束。

注意：强制关闭 `Code` 会丢失未保存的编辑内容，因此只在确认没有未保存文件时使用。

#### 步骤 4：先补齐新 cache，保留旧 cache

脚本将 Bundle cache 文件复制到内网 `CacheRoot`：

- 新文件：复制；
- 同名、同长度、同哈希：跳过；
- 同名但内容不同：删除后复制新文件；
- 旧版本 cache：不删除。

保留旧 cache 的好处：

- 更新失败时仍有旧版本安装包；
- 需要重装旧版时可继续复用；
- 下一次 Bundle 可能仍引用部分相同依赖包。

### 步骤 5：备份并替换 Scoop 核心与 main / extras bucket

Update 脚本只替换以下三部分：

```text
D:\scoop\apps\scoop\current
D:\scoop\buckets\main
D:\scoop\buckets\extras
```

替换前先移动旧目录到：

```text
D:\scoop\offline-backups\<时间戳-随机标识>\scoop-current
D:\scoop\offline-backups\<时间戳-随机标识>\buckets\main
D:\scoop\offline-backups\<时间戳-随机标识>\buckets\extras
```

然后将已预解压的新目录移动到正式位置。

同一分区上的目录 `Move-Item` 本质上是重命名，速度远快于逐文件覆盖，且避免了直接复制大批小文件。

#### 步骤 6：失败时回滚

若 core 或任一 bucket 切换失败，脚本会尝试：

1. 将刚放入的新目录移动到 `.offline-update\...\failed`；
2. 将备份目录移回原位置；
3. 抛出原始错误。

若回滚本身也失败，需手动检查：

```text
D:\scoop\offline-backups
D:\scoop\.offline-update
```

这些目录保留了最关键的旧目录和未完成的新目录，可作为人工恢复依据。

#### 步骤 7：重新设置环境与 Scoop 引导 shim

核心目录切换后，脚本重新确保：

```text
SCOOP
SCOOP_CACHE
D:\scoop\shims 在用户 Path 中
scoop.cmd / scoop.ps1 引导 shim
```

这样新的 Scoop 核心立即成为后续命令的执行目标。

#### 步骤 8：写入 `last_update`

脚本再次执行：

```powershell
scoop config last_update <当前时间>
```

这是离线更新流程的一部分：本地核心和 bucket 已由 Bundle 替换，脚本把当前时间写入配置，以减少应用更新前的自动同步检查触发机会。

#### 步骤 9：只更新 Bundle 中且内网已经安装的软件

脚本读取 `bundle.json` 的 `DownloadedPackages`，并逐项检查：

```text
D:\scoop\apps\<应用名>\current
```

存在才加入更新列表；不存在则输出：

```text
跳过未安装的软件：<包名>
```

然后调用类似：

```powershell
scoop update 7zip clangd cmake ninja llvm extras/vscode
```

注意两点：

1. Scoop 核心不在该列表中，因为核心已经由 `scoop-core.zip` 直接替换；
2. 新增到 Bundle 但尚未安装的软件不会自动安装，需人工使用 `scoop install <包> --no-update-scoop`。

#### 步骤 10：清理工作目录与旧备份

更新成功后：

- 删除本次 `.offline-update\...` 暂存目录；
- 根据 `KeepBackupCount` 清理过旧备份；
- 默认保留最近 2 份 core / bucket 备份。

如果磁盘空间紧张，可执行：

```powershell
.\Update-ScoopOfflineBundle.ps1 -KeepBackupCount 0
```

这会在本次更新成功后删除所有旧 core / bucket 备份；cache 旧文件仍会保留。

---

## 7. 为什么不能直接复制 `apps`、`current` 和 `shims`

### 7.1 `apps` 中存在大量解压后小文件

例如 LLVM、VS Code、MSYS2 等目录包含大量 DLL、头文件、脚本、文档、语言资源。跨 SMB 逐文件复制时，瓶颈不是总字节数，而是大量目录与文件元数据操作。

相比之下，cache 通常是少量 `.zip`、`.7z`、`.msi`、`.exe` 等压缩安装包；更适合跨网络传输。

### 7.2 `current` 是本地版本入口

普通 Scoop 应用常见结构：

```text
D:\scoop\apps\llvm\<具体版本目录>
D:\scoop\apps\llvm\current  ->  <具体版本目录>
```

`current` 往往是 NTFS Junction / reparse point。它不是普通文件内容，也不应以“递归复制目录”的方式跨机器迁移。

离线方案让内网 Scoop 在安装或更新时自行创建：

```text
版本目录
current 入口
shims
manifest 声明的环境变量
```

这样所有路径都绑定到内网实际的 `D:\scoop`，不会残留外网盘符或旧版本引用。

### 7.3 shims 应由内网 Scoop 生成

`D:\scoop\shims` 下的应用命令入口可能与具体应用版本、路径和当前版本状态有关。

这套方案只手写最小的 Scoop 引导 shim：

```text
scoop.cmd
scoop.ps1
```

它们只负责启动 Scoop 核心。普通应用 shim 由内网安装 / 更新时的 Scoop 逻辑重新创建，因此更稳。

---

## 8. 离线搜索、离线安装与离线更新的区别

| 操作 | 是否只需要 bucket | 是否还需要 cache | 说明 |
|---|---:|---:|---|
| `scoop search cursor` | 是 | 否 | 完整 `extras` bucket 中有 cursor manifest 即可 |
| `scoop install extras/cursor --no-update-scoop` | 否 | 是 | 还必须有与当前 cursor manifest 匹配的 cache 文件 |
| `scoop update vscode` | 否 | 是 | 还必须有与更新后 manifest 匹配的 cache 文件 |
| `scoop list` | 否 | 否 | 读取本地已安装应用状态 |

因此，完整 bucket 解决的是“可见性”和“软件清单”；cache 决定的是“能否真正离线安装 / 更新”。

如果内网搜索能找到 Cursor，但安装失败并提示下载地址不可访问，通常就是 Bundle 中没有 Cursor 对应 cache。解决方法是把：

```powershell
'extras/cursor'
```

添加到外网 Build 脚本的请求列表，重新 Build、同步，再在内网安装。

---

## 9. 常见问题与处理方式

### 9.1 外网构建时提示 `WARN Scoop is out of date`

这通常不是 `scoop download` 失败。Build 脚本在下载阶段使用 `--no-update-scoop`，因此 Scoop 会提示但不会自行更新。

推荐处理顺序：

```powershell
scoop update
.\Build-ScoopOfflineBundle.ps1
```

先显式更新外网核心和 bucket，再构建 Bundle。若提示出现但下载继续进行，也可让当前构建完成；下次正式发布前再执行上述更新即可。

### 9.2 内网脚本说目标 Scoop 目录不是空目录

这是 Install 脚本的保护机制。

- 内网未安装过：检查路径是否填错；
- 首次失败留下的半成品：确认无保留价值后使用 `-Force`；
- 已正常使用过：不要用 Install，改用 Update。

### 9.3 Update 检测到 `Code` 或 `clangd` 正在运行

优先手动关闭相关软件后重试：

```powershell
.\Update-ScoopOfflineBundle.ps1
```

需要自动关闭才使用：

```powershell
.\Update-ScoopOfflineBundle.ps1 -StopRunningProcesses
```

执行前保存 VS Code 中未保存文件。

### 9.4 内网更新后某个包仍是旧版本

检查：

```powershell
scoop status
scoop list
```

常见原因：

1. 外网没有先刷新 bucket；
2. Build 脚本的 `$RequestedPackages` 中没有该软件；
3. Bundle 没有被完整同步；
4. 目标应用没有关闭，更新脚本已阻止或跳过；
5. manifest 当前版本与已安装版本实际相同。

### 9.5 内网提示找不到 cache 文件或尝试联网下载

通常意味着 bundle 的 manifest 与 cache 没有成对更新，或者目标软件未加入 Build 请求列表。

处理方式：

1. 外网执行 `scoop update`；
2. 确认 Build 脚本包含该软件；
3. 重新执行 Build；
4. 重新镜像同步整个 Bundle；
5. 内网先运行 Update；
6. 需要新装的软件再执行：

   ```powershell
   scoop install <包名> --no-update-scoop
   ```

### 9.6 更新失败后如何恢复

Update 脚本会尝试自动回滚。若仍失败，先不要删除以下目录：

```text
D:\scoop\offline-backups
D:\scoop\.offline-update
```

检查最新备份目录中是否存在：

```text
scoop-current
buckets\main
buckets\extras
```

这些是更新前的核心和 bucket，可用于人工恢复。通常应先保留现场并查看脚本报错原因，而不是立即删除 `D:\scoop` 重装。

### 9.7 是否需要迁移 VS Code 配置和扩展

默认不会迁移。

若你希望内网保留外网 VS Code 的扩展、设置或 portable 数据，应单独同步：

```text
D:\scoop\persist\vscode
```

不要将它混入 Bundle 的核心更新逻辑；这样可以将“软件供应包”和“用户个性化配置”分开管理。

---

## 10. 运维建议

### 10.1 版本发布建议

建议每一次外网更新都把 Bundle 当作一个完整发布物：

```text
刷新外网 Scoop / bucket
→ 构建新的完整 Bundle
→ 完整同步到内网
→ 内网执行更新
```

不要尝试手工挑拣替换 Bundle 中某几个 JSON 或 cache 文件；manifest、版本、哈希、cache 文件必须来自同一次构建快照。

### 10.2 保留策略建议

建议保留：

- 内网 `offline-backups`：最近 2 份；
- 内网 `cache`：先不主动清理；
- 外网 `cache`：在确认内网升级稳定后，再按需要做清理；
- 外网 Bundle：只保留最新一份即可，除非你有明确回退版本管理要求。

### 10.3 安全与完整性边界

这些脚本通过 SHA-256 校验保护“同步过程中 Bundle 或 cache 文件损坏”的风险。

但哈希值本身来自外网 Build 阶段，因此仍应保证：

- 外网 Scoop / bucket 来源可信；
- Build 脚本本身经过审阅；
- 内网同步链路有访问控制；
- 不从未知来源替换 `bundle.json`、zip 或 cache 文件。

### 10.4 不建议在内网执行的命令

避免在纯内网环境直接运行：

```powershell
scoop update
scoop update *
scoop bucket add <远程地址>
```

这些命令可能尝试更新 Scoop、Git 同步 bucket 或下载远程安装包。内网应优先使用 Bundle 驱动的 `Update-ScoopOfflineBundle.ps1`。

---

## 11. 一页式操作清单

### 首次部署

```powershell
# 外网
scoop update
.\Build-ScoopOfflineBundle.ps1

# 同步：D:\ScoopOfflineBundle → 内网 D:\ScoopOfflineBundle

# 内网
Set-ExecutionPolicy Bypass -Scope Process
.\Install-ScoopOfflineBundle.ps1
```

### 后续更新

```powershell
# 外网
scoop update
.\Build-ScoopOfflineBundle.ps1

# 同步：D:\ScoopOfflineBundle → 内网 D:\ScoopOfflineBundle

# 内网：先关闭 VS Code / 编译相关进程
Set-ExecutionPolicy Bypass -Scope Process
.\Update-ScoopOfflineBundle.ps1
```

### 加入一个新软件，例如 Cursor

```powershell
# 外网：在 Build 脚本 RequestedPackages 中添加 'extras/cursor'
scoop update
.\Build-ScoopOfflineBundle.ps1

# 同步后，内网
.\Update-ScoopOfflineBundle.ps1
scoop install extras/cursor --no-update-scoop
```

---

## 12. 目录速查表

| 路径 | 管理者 | 是否跨网同步 | 说明 |
|---|---|---:|---|
| `D:\scoop\apps\scoop\current` | Bundle / Install / Update | 通过 `scoop-core.zip` | Scoop 核心 |
| `D:\scoop\apps\llvm` | 内网 Scoop | 否 | 由内网安装 / 更新生成 |
| `D:\scoop\apps\vscode` | 内网 Scoop | 否 | 由内网安装 / 更新生成 |
| `D:\scoop\buckets\main` | Bundle / Update | 通过 `buckets.zip` | 主软件清单 |
| `D:\scoop\buckets\extras` | Bundle / Update | 通过 `buckets.zip` | 扩展软件清单 |
| `D:\scoop\cache` | Bundle / Install / Update | 是，仅目标包 | 离线安装包 |
| `D:\scoop\shims` | 内网 Scoop | 否 | 只由内网生成或修复 |
| `D:\scoop\persist` | 用户 / 应用 | 默认否 | 设置、扩展、用户数据 |
| `D:\scoop\offline-backups` | Update | 否 | core / bucket 更新回滚备份 |
| `D:\ScoopOfflineBundle` | 外网 Build | 是，完整同步 | 离线发布物 |

