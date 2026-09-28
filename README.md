<!-- SPDX-License-Identifier: GPL-2.0 -->
# Android 内核 · Redmi 9A（dandelion）

[![kernel](https://img.shields.io/badge/kernel-4.19.325-brightgreen)](https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.19.325.tar.xz)
[![device](https://img.shields.io/badge/device-Redmi%209A%20dandelion-blue)](https://wiki.lineageos.org/devices/dandelion/)
[![license](https://img.shields.io/badge/license-GPL--2.0-lightgrey)](COPYING)
[![root](https://img.shields.io/badge/root-none-important)](#不包含的内容)

Redmi 9A（联发科 Helio G25，平台代号 MT6765）的 Android 内核源码。
内核版本 **4.19.325** —— Linux 4.19 LTS 的**最后一个稳定版**（2024-12-05 发布，随后进入 EOL），
即本仓库已包含 4.19 系列全部 325 次稳定更新。

> **定位：性能取向 · SELinux 强制 · 默认无 root。**
> 本仓库不提供预编译镜像，需自行编译刷入。

---

## 目录

- [这个仓库是什么](#这个仓库是什么)
- [特性](#特性)
- [不包含的内容](#不包含的内容)
- [构建](#构建)
- [打包与刷入](#打包与刷入)
- [设备验证](#设备验证)
- [仓库结构](#仓库结构)
- [提交历史](#提交历史)
- [免责声明](#免责声明)
- [许可](#许可)
- [English summary](#english-summary)

---

## 这个仓库是什么

| 项目 | 内容 |
|---|---|
| 设备 | Redmi 9A，代号 `dandelion`，型号 M2006C3LI |
| SoC | 联发科 Helio G25（`ro.board.platform=mt6765`，`ro.hardware=mt6762`） |
| 内核 | Linux **4.19.325**（由 4.19.275 升级而来），`UTS_RELEASE=4.19.325-mt6765` |
| 内核时钟 | `CONFIG_HZ=1000`（1 ms 调度粒度），`CONFIG_PREEMPT=y` |
| 工具链 | Clang / LLVM 18 + LLD，`aarch64-linux-gnu-` 交叉前缀 |
| 构建配置 | [`arch/arm64/configs/blossom_defconfig`](arch/arm64/configs/blossom_defconfig) |
| 许可 | GPL-2.0（同 Linux 内核） |

**验证环境**：Redmi 9A 实机，Android 16（API 36）ROM，ADB 可连接、无 root。

### 分支

| 分支 | 说明 |
|---|---|
| `main` | 当前主线：4.19.325、无 root、性能特性开启 |
| `archive/pre-325` | 升级到 4.19.325 **之前**的 4.19.275 状态快照，用于对比与回溯 |

---

## 特性

以下全部在**实机运行的内核**上通过 `/proc/config.gz` 核对，不是纸面配置：

| 特性 | 配置项 | 作用 |
|---|---|---|
| BFQ I/O 调度器（默认） | `CONFIG_DEFAULT_BFQ=y`、`CONFIG_IOSCHED_BFQ=y` | 用 BFQ 替代 mq-deadline 作为默认调度器，交互场景响应更好 |
| BFQ 按 cgroup 分层 | `CONFIG_BFQ_GROUP_IOSCHED=y` | 每个 blkio cgroup 拥有独立的 BFQ 层级，后台应用的大量 I/O 不会饿死前台 |
| io_uring | `CONFIG_IO_URING=y` | 高性能异步 I/O 接口，减少系统调用开销 |
| KSM | `CONFIG_KSM=y` | 内核同页合并，降低内存占用 |
| PSI | `CONFIG_PSI=y` | 压力失量信息（CPU/内存/IO 压力可读） |
| UCLAMP | `CONFIG_UCLAMP_TASK=y`、`CONFIG_UCLAMP_TASK_GROUP=y` | 调度器利用率钳制，可限制任务最高/最低算力档位 |
| 1000 Hz 时钟 | `CONFIG_HZ=1000` | 调度与定时精度 1 ms |
| 抢占式内核 | `CONFIG_PREEMPT=y` | 降低任务切换延迟 |
| **SELinux 强制** | `CONFIG_SECURITY_SELINUX=y`、`CONFIG_DEFAULT_SECURITY_SELINUX=y`、`CONFIG_DEFAULT_SECURITY="selinux"` | 默认 `Enforcing`；已移除 `androidboot.selinux=permissive` 启动参数 |
| memfd_secret | `CONFIG_SECRETMEM=y` | `memfd_secret()` 系统调用 |
| EROFS / FS Verity | `CONFIG_EROFS_FS=y`、`CONFIG_FS_VERITY=y` | 只读压缩文件系统 / 文件完整性校验 |

内核的 `CONFIG_SECURITY_SELINUX_BOOTPARAM` 为 **未开启**，因此无法通过内核启动参数把
SELinux 退回 permissive —— 强制状态由内核配置和镜像 cmdline 共同保证。

---

## 不包含的内容

如实说明，避免误解：

- **不含任何 root 方案**：`CONFIG_KSU` 未定义（`# CONFIG_KSU is not set`），
  构建产物中没有 KernelSU 符号，`su` 不可用。本仓库就是"不 root 的日常内核"。
- **不提供预编译镜像**：仓库没有 Release，`boot.img` 需自行编译 + 打包。
- **未开启部分加固选项**：`FORTIFY_SOURCE`、`INIT_ON_ALLOC_DEFAULT_ON`、
  `INIT_ON_FREE_DEFAULT_ON`、`MODULE_SIG` 当前为未开启状态。
  本仓库的取舍是"稳定 + 性能 + SELinux 强制"，加固项可自行在 defconfig 中开启。
- **NTFS3 未开启**（源码已在树内，`CONFIG_NTFS3_FS is not set`）。
- 不针对非 dandelion 机型做适配。

---

## 构建

完整说明见 [`build-tools/BUILD.md`](build-tools/BUILD.md)。核心流程：

### 1. 依赖

```bash
sudo apt install build-essential bison bc flex libssl-dev libelf-dev \
                 clang lld llvm binutils-aarch64-linux-gnu python3
```

本仓库实测使用 **LLVM/Clang 18**。若发行版版本不同，只要 `clang`、`ld.lld`、
`llvm-nm`、`llvm-ar` 等齐全即可。

### 2. 生成配置

```bash
export PATH=/usr/lib/llvm-18/bin:/usr/bin:/bin:/usr/local/bin:$PATH

make O=out ARCH=arm64 \
     CC=clang CROSS_COMPILE=aarch64-linux-gnu- \
     LD=ld.lld NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump \
     STRIP=llvm-strip AR=llvm-ar \
     blossom_defconfig
```

### 3. 编译

```bash
make -j"$(nproc)" O=out ARCH=arm64 \
     CC=clang CROSS_COMPILE=aarch64-linux-gnu- \
     LD=ld.lld NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump \
     STRIP=llvm-strip AR=llvm-ar \
     Image.gz
```

产物：`out/arch/arm64/boot/Image.gz`

> `O=` 输出目录已加入 `.gitignore`（`out*/`），不会污染仓库。

---

## 打包与刷入

`boot.img` 的打包策略是：**只替换 kernel，ramdisk / dtb / 头部字段一律沿用基准镜像**。
这样做的好处是不改动 ROM 自带的 ramdisk，兼容性最好。

### 1. 重打包

```bash
KERNEL_IMG=out/arch/arm64/boot/Image.gz \
  python3 build-tools/pack_boot.py <基准boot.img> <输出boot.img>
```

- `<基准boot.img>`：与你当前 ROM 匹配的 boot 镜像（建议自行备份后使用）
- 工具解析 header v1/v2，按 page 对齐重排 kernel / ramdisk / dtb 三段

### 2. 让 SELinux 保持强制

原厂镜像的 header cmdline 带有 `androidboot.selinux=permissive`，打包后需要移除：

```bash
python3 build-tools/strip-selinux-permissive.py <输出boot.img>
```

脚本会在 header 的 `cmdline`（偏移 64，512 字节）与 `extra_cmdline`（偏移 608，
1024 字节，header v1+）中删除该参数，并在改写后回显结果。

### 3. 刷入

```bash
adb reboot bootloader
fastboot flash boot <输出boot.img>
fastboot reboot
```

> **刷入前务必备份原 boot 镜像。** 刷错镜像会导致无法开机，
> 需要通过 fastboot / recovery 恢复。

---

## 设备验证

```bash
# 内核版本
adb shell uname -r
#   4.19.325-mt6765

# 完整构建信息（含编译时间与编译器）
adb shell uname -a
#   Linux localhost 4.19.325-mt6765 #3 SMP PREEMPT ...

# SELinux 必须是 Enforcing
adb shell getenforce
#   Enforcing

# 无 root
adb shell "which su || echo su-absent"
#   su-absent

# 直接读取正在运行内核的配置（可确认特性确实编入）
adb shell "zcat /proc/config.gz | grep -E 'BFQ|IO_URING|KSM|CONFIG_PSI=|UCLAMP|CONFIG_HZ=|CONFIG_KSU'"
```

`/proc/config.gz` 是最可靠的核对手段：它来自内核自身嵌入的构建配置，
不依赖外部文件。若 SELinux 拒绝 shell 读取某些 `/sys` 节点，属正常现象（强制模式生效的表现）。

---

## 仓库结构

```
.
├── README.md                         本文件
├── arch/arm64/configs/
│   └── blossom_defconfig             本仓库的构建配置（460 行）
├── build-tools/
│   ├── BUILD.md                      详细构建与维护指南
│   ├── pack_boot.py                  boot.img 重打包（只换 kernel）
│   ├── strip-selinux-permissive.py   移除 cmdline 中的 permissive
│   ├── build_full.sh                 一键构建
│   ├── check_config.sh               配置断言（防止配置被静默改动）
│   ├── fix11.config                  历史配置片段，仅作 TEE/ION 不变量参考
│   └── boot/dtb                      原厂 dtb 备份
├── Documentation/                    Linux 内核自带文档
├── arch/ block/ drivers/ fs/ mm/ net/ kernel/ security/ ...
│                                     Linux 内核源码本体
└── Makefile                          VERSION=4 PATCHLEVEL=19 SUBLEVEL=325
```

仓库共约 6.8 万个受版本控制的文件，除 `build-tools/` 与 `blossom_defconfig` 外
均为 Linux 内核与 MediaTek 平台源码本体。

---

## 提交历史

`main` 分支共 8 个提交，按时间顺序：

| 提交 | 说明 |
|---|---|
| `bootstrap` | 仓库初始化 |
| `import: Android 4.19.275-mt6765 (dandelion) kernel source` | 导入 4.19.275 内核源码基线 |
| `v11ksu: KernelSU direct kernel for dandelion (stable V5/V6 build lineage)` | V5/V6 构建线的整理 |
| `gitignore: keep stock exclusions, add v11ksu build artifacts` | 忽略规则整理 |
| `upgrade: 4.19.275 -> 4.19.325 (3-way merge against vanilla)` | **核心提交**：与 vanilla 4.19.325 三方合并，3494 个文件变更 |
| `blossom_defconfig: no-root + performance features` | 关闭 KernelSU，开启 HZ=1000 / KSM / BFQ |
| `chore: remove leftover backup files from tree` | 清理 37 个残留备份文件 |
| `blossom_defconfig: enable BFQ hierarchical (per-cgroup) scheduling` | 开启 BFQ 分层调度 |

---

## 免责声明

- 本项目为个人学习与研究用途，与 Xiaomi、Google、MediaTek 无任何关联。
- 刷写第三方内核存在风险，可能造成数据丢失或设备无法启动。
  **刷入前请备份原 boot 镜像**，并确保你有恢复手段（fastboot / recovery）。
- 本仓库不对使用本代码造成的任何损失负责。
- 请遵守当地法律法规与设备保修条款。

---

## 许可

本仓库中的内核源码遵循 Linux 内核的许可条款：

```
SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note
```

详见 [`COPYING`](COPYING) 与 [`LICENSES/`](LICENSES/)。
`build-tools/` 下的辅助脚本同样以 **GPL-2.0** 授权。

---

## English summary

**Android kernel source for the Redmi 9A** (codename *dandelion*, MediaTek Helio G25 / MT6765 platform),
running **Linux 4.19.325** — the final release of the 4.19 LTS series (2024-12-05, now EOL),
upgraded from the 4.19.275 base this tree started at.

**Positioning: performance-oriented, SELinux enforcing, no root by default.**
No prebuilt images are published; build and pack it yourself.

**Highlights** (all verified against `/proc/config.gz` on a live device):

| Feature | Config |
|---|---|
| BFQ as default I/O scheduler | `CONFIG_DEFAULT_BFQ=y`, `CONFIG_IOSCHED_BFQ=y` |
| BFQ per-cgroup hierarchy | `CONFIG_BFQ_GROUP_IOSCHED=y` |
| io_uring | `CONFIG_IO_URING=y` |
| KSM (page merging) | `CONFIG_KSM=y` |
| PSI (pressure stall info) | `CONFIG_PSI=y` |
| Utilization clamping | `CONFIG_UCLAMP_TASK=y`, `CONFIG_UCLAMP_TASK_GROUP=y` |
| 1000 Hz tick, preemptible kernel | `CONFIG_HZ=1000`, `CONFIG_PREEMPT=y` |
| SELinux enforcing by default | `CONFIG_DEFAULT_SECURITY_SELINUX=y` |
| **No root** | `CONFIG_KSU` not set |

**Build**

```bash
export PATH=/usr/lib/llvm-18/bin:/usr/bin:/bin:/usr/local/bin:$PATH
make O=out ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu- \
     LD=ld.lld NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump \
     STRIP=llvm-strip AR=llvm-ar blossom_defconfig
make -j"$(nproc)" O=out ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu- \
     LD=ld.lld NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump \
     STRIP=llvm-strip AR=llvm-ar Image.gz
```

**Pack & flash** — only the kernel is replaced; ramdisk and dtb are taken from your
own base `boot.img`, and `androidboot.selinux=permissive` is stripped from the
kernel command line so SELinux stays enforcing:

```bash
KERNEL_IMG=out/arch/arm64/boot/Image.gz \
  python3 build-tools/pack_boot.py <base_boot.img> <out_boot.img>
python3 build-tools/strip-selinux-permissive.py <out_boot.img>
fastboot flash boot <out_boot.img>
```

Details, configuration strategy and troubleshooting: [`build-tools/BUILD.md`](build-tools/BUILD.md).

**Disclaimer**: personal research project, not affiliated with Xiaomi, Google or
MediaTek. Flashing a custom kernel can brick your device — back up your original
`boot.img` first. Licensed under GPL-2.0.
