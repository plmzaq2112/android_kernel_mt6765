<!-- SPDX-License-Identifier: GPL-2.0 -->
# Android 内核 · Redmi 9A（dandelion）

[![kernel](https://img.shields.io/badge/kernel-4.19.325-brightgreen)](https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.19.325.tar.xz)
[![device](https://img.shields.io/badge/device-Redmi%209A%20dandelion-blue)](https://wiki.lineageos.org/devices/dandelion/)
[![release](https://img.shields.io/github/v/release/plmzaq2112/android_kernel_mt6765)](https://github.com/plmzaq2112/android_kernel_mt6765/releases)
[![license](https://img.shields.io/badge/license-GPL--2.0-lightgrey)](COPYING)
[![root](https://img.shields.io/badge/root-none-important)](#不包含的内容)

Redmi 9A（联发科 Helio G25，平台代号 MT6765）的 Android 内核源码。
内核版本 **4.19.325** —— Linux 4.19 LTS 的**最后一个稳定版**（2024-12-05 发布，随后进入 EOL），
即本仓库已包含 4.19 系列全部 325 次稳定更新。

> **定位：性能取向 · SELinux 强制 · 默认无 root。**
> 源码是本体，推荐自行编译；[Releases](https://github.com/plmzaq2112/android_kernel_mt6765/releases)
> 另提供已实机验证的 `boot.img`。

---

## 目录

- [这个仓库是什么](#这个仓库是什么)
- [特性](#特性)
- [不包含的内容](#不包含的内容)
- [下载镜像](#下载镜像)
- [构建](#构建)
- [打包与刷入](#打包与刷入)
- [设备验证](#设备验证)
- [仓库结构](#仓库结构)
- [血统与提交历史](#血统与提交历史)
- [旧项目档案](docs/old-project.md)
- [免责声明](#免责声明)
- [许可](#许可)
- [English summary](#english-summary)

---

## 这个仓库是什么

| 项目 | 内容 |
|---|---|
| 设备 | Redmi 9A，代号 `dandelion`，型号 M2006C3LI |
| SoC | 联发科 Helio G25（`ro.board.platform=mt6765`，`ro.hardware=mt6762`） |
| 内核 | Linux **4.19.325**，`UTS_RELEASE=4.19.325-dandelion` |
| 内核时钟 | `CONFIG_HZ=1000`（1 ms 调度粒度），`CONFIG_PREEMPT=y` |
| 工具链 | **LLVM/Clang 21** + LLD（ThinLTO），`aarch64-linux-gnu-` 交叉前缀 |
| 构建配置 | [`arch/arm64/configs/blossom_defconfig`](arch/arm64/configs/blossom_defconfig) |
| 许可 | GPL-2.0（同 Linux 内核） |

**验证环境**：Redmi 9A 实机，Android 16（API 36）ROM，ADB 可连接、无 root。

---

## 特性

以下全部在**实机运行的内核**上通过 `/proc/config.gz` 核对，不是纸面配置：

| 特性 | 配置项 | 作用 |
|---|---|---|
| BFQ I/O 调度器（默认） | `CONFIG_DEFAULT_BFQ=y`、`CONFIG_IOSCHED_BFQ=y` | 用 BFQ 替代 mq-deadline 作为默认调度器，交互场景响应更好 |
| BFQ 按 cgroup 分层 | `CONFIG_BFQ_GROUP_IOSCHED=y` | 每个 blkio cgroup 拥有独立的 BFQ 层级，后台应用的大量 I/O 不会饿死前台 |
| io_uring | `CONFIG_IO_URING=y` | 高性能异步 I/O 接口（5.x 特性反向移植），减少系统调用开销。含凭据修复：强制 SELinux 下缓冲写不再被拒（读写/落盘/轮询/超时均经真机调用级测试） |
| memfd_secret | `CONFIG_SECRETMEM=y` | `memfd_secret()` 系统调用（反向移植）。上游默认 opt-in，本树默认开启（否则运行时 ENOSYS）；用法为 `ftruncate` 后 mmap |
| WireGuard | `CONFIG_WIREGUARD=y` | 内核态 WireGuard VPN（反向移植） |
| BBR 拥塞控制 + FQ 队列 | `CONFIG_TCP_CONG_BBR=y`、`CONFIG_NET_SCH_FQ=y`、`CONFIG_DEFAULT_BBR=y` | 默认拥塞控制 + 默认 qdisc，弱网吞吐/延迟更优。遗留 BIC/WESTWOOD 已移除，厂商 init 强写 bic 无害失败后 BBR 直接生效（实机 `tcp_congestion_control=bbr`） |
| KSM | `CONFIG_KSM=y` | 内核同页合并，降低内存占用 |
| PSI | `CONFIG_PSI=y` | 压力失量信息（CPU/内存/IO 压力可读） |
| UCLAMP | `CONFIG_UCLAMP_TASK=y`、`CONFIG_UCLAMP_TASK_GROUP=y` | 调度器利用率钳制，可限制任务最高/最低算力档位 |
| 1000 Hz 时钟 | `CONFIG_HZ=1000` | 调度与定时精度 1 ms |
| 抢占式内核 | `CONFIG_PREEMPT=y` | 降低任务切换延迟 |
| **SELinux 强制** | `CONFIG_SECURITY_SELINUX=y`、`CONFIG_DEFAULT_SECURITY_SELINUX=y`、`CONFIG_DEFAULT_SECURITY="selinux"` | 默认 `Enforcing`；已移除 `androidboot.selinux=permissive` 启动参数 |
| EROFS / FS Verity | `CONFIG_EROFS_FS=y`、`CONFIG_FS_VERITY=y` | 只读压缩文件系统 / 文件完整性校验 |

另有平台钉子（TEE/Keymaster/Widevine 依赖链、`ARM64_SW_TTBR0_PAN` 等）由
`check_config.sh` 断言，详见 [`build-tools/BUILD.md`](build-tools/BUILD.md)。

内核的 `CONFIG_SECURITY_SELINUX_BOOTPARAM` 为**未开启**，因此无法通过内核启动参数把
SELinux 退回 permissive —— 强制状态由内核配置和镜像 cmdline 共同保证。

---

## 不包含的内容

如实说明，避免误解：

- **不含任何 root 方案**：本树没有 KernelSU 源码，基线残留的 `CONFIG_KSU=y`
  等死配置行已在整合时清除，`check_config.sh` 会断言 KSU 必须缺席。
  构建产物中没有 KernelSU 符号，`su` 不可用。
- **不开可加载模块**（`MODULES is not set`）：全树 built-in，体积与攻击面更小；
  代价是无法单独替换 `.ko`。
- **预编译镜像不作担保**：[Releases](https://github.com/plmzaq2112/android_kernel_mt6765/releases)
  里的 `boot.img` 只是**某一提交的快照**；源码才是本体，
  改了配置或代码后请自行编译（见 [构建](#构建)）。
- **未开启部分加固选项**：`FORTIFY_SOURCE`、`INIT_ON_ALLOC_DEFAULT_ON`、
  `INIT_ON_FREE_DEFAULT_ON`、`MODULE_SIG` 当前为未开启状态，可自行在 defconfig 开启。
- 不针对非 dandelion 机型做适配。

---

## 下载镜像

不想自行编译时，从 [Releases](https://github.com/plmzaq2112/android_kernel_mt6765/releases)
取已在 Redmi 9A 实机开机验证过的 `boot.img`：

| 版本 | 资产 | 说明 |
|---|---|---|
| **[v2.2](https://github.com/plmzaq2112/android_kernel_mt6765/releases/tag/v2.2)**（当前） | `boot-4.19.325-dandelion-llvm21.img` | LLVM 21 整合版：修复旧线三问题（memfd_secret ENOSYS / io_uring 写在强制 SELinux 下失效 / config.gz 数据源），BBR+FQ 默认，冗余清理 |
| **[v2.1](https://github.com/plmzaq2112/android_kernel_mt6765/releases/tag/v2.1)** | `boot-4.19.325-dandelion-perf.img` | 4.19.325 + BFQ 分层 / io_uring / memfd_secret / KSM / PSI / UCLAMP，无 root、SELinux 强制 |
| [v1.1](https://github.com/plmzaq2112/android_kernel_mt6765/releases/tag/v1.1) | `boot-4.19.275-perf-v2.img` | 4.19.275 干净基线（旧版） |
| [v1.0](https://github.com/plmzaq2112/android_kernel_mt6765/releases/tag/v1.0) | `boot-4.19.275-full-v11.img` | 4.19.275 v11（旧版） |

镜像由同一套脚本产出——**仅替换 kernel**，ramdisk 与 dtb 继续沿用基底镜像，
因此刷入前的备份与刷入步骤见 [`build-tools/BUILD.md`](build-tools/BUILD.md) 第 7 节。

---

## 构建

完整说明见 [`build-tools/BUILD.md`](build-tools/BUILD.md)。核心流程：

### 1. 依赖

```bash
sudo apt install build-essential bison bc flex libssl-dev libelf-dev \
                 clang lld llvm binutils-aarch64-linux-gnu python3
```

本仓库实测使用 **LLVM/Clang 21**（Ubuntu clang 21.1.8 / LLD 21.1.8，ThinLTO）。
若发行版版本不同，只要 `clang`、`ld.lld`、`llvm-nm`、`llvm-ar` 等齐全即可。

### 2. 一键构建（推荐）

```bash
bash build-tools/build_full.sh
```

自动完成：`blossom_defconfig` → `check_config.sh` 断言 → 编译 `Image.gz`。
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
#   4.19.325-dandelion

# 完整构建信息（含编译时间与编译器）
adb shell uname -a
#   Linux localhost 4.19.325-dandelion #6 SMP PREEMPT ...

# SELinux 必须是 Enforcing
adb shell getenforce
#   Enforcing

# 无 root
adb shell "which su || echo su-absent"
#   su-absent

# 直接读取正在运行内核的配置（可确认特性确实编入）
adb shell "zcat /proc/config.gz | grep -E 'BFQ|IO_URING|SECRETMEM|WIREGUARD|KSM|CONFIG_PSI=|UCLAMP|CONFIG_HZ=|KSU'"

# 拥塞控制与队列默认值（BBR + FQ）
adb shell "cat /proc/sys/net/ipv4/tcp_congestion_control; cat /proc/sys/net/core/default_qdisc"
#   bbr
#   fq
```

`/proc/config.gz` 是最可靠的核对手段：它来自内核自身嵌入的构建配置，
不依赖外部文件（本树已修正基线把 `stock_defconfig` 压缩进去的错误，
数据源为实际构建的 `.config`）。若 SELinux 拒绝 shell 读取某些 `/sys` 节点，
属正常现象（强制模式生效的表现）。

---

## 仓库结构

```
.
├── README.md                         本文件
├── arch/arm64/configs/
│   └── blossom_defconfig             本仓库唯一的构建配置
├── build-tools/
│   ├── BUILD.md                      详细构建与维护指南
│   ├── pack_boot.py                  boot.img 重打包（只换 kernel）
│   ├── strip-selinux-permissive.py   移除 cmdline 中的 permissive
│   ├── build_full.sh                 一键构建（defconfig→断言→Image.gz）
│   ├── check_config.sh               配置断言（防止配置被静默改动）
│   └── fix11.config                  历史配置片段，仅作 TEE/ION 不变量参考
├── fs/io_uring.c                     io_uring（反向移植自 v2.0 特性线）
├── mm/secretmem.c                    memfd_secret（反向移植）
├── drivers/net/wireguard/            WireGuard（反向移植）
├── Documentation/                    Linux 内核自带文档
├── arch/ block/ drivers/ fs/ mm/ net/ kernel/ security/ ...
│                                     Linux 内核与 MediaTek 平台源码本体
└── Makefile                          VERSION=4 PATCHLEVEL=19 SUBLEVEL=325
```

---

## 血统与提交历史

本树不是单一来源，而是三段血统的合流：

| 来源 | 内容 |
|---|---|
| **Juggutsu V6 基线** | MT6765 平台源码主体（gen4m WiFi、TEE、安全媒体链等） |
| **vanilla 4.19.325** | 与主线 4.19.325 三方合并，含全部 LTS 稳定修复 |
| **v2.0 特性线**（本仓库前代 `main`） | HZ=1000 / BFQ 默认 + 分层 / io_uring / memfd_secret / WireGuard 反向移植、打包与断言工具链、SELinux 强制策略 |

整合后基线残留的 KernelSU 死配置行已清除，`blossom_noksu_defconfig` 与
`blossom_defconfig` 合并为单一 `blossom_defconfig`；
`/proc/config.gz` 数据源、teei sysfs 守卫等前代修复一并移植（明细见
[`build-tools/BUILD.md`](build-tools/BUILD.md) 第 9 节）。

v2.2 起，两条线的整合从"代码并入"推进到"调用级实测"：逐项真机验证后修复了
旧线自身也存在的三个隐藏问题——`memfd_secret` 因上游 opt-in 默认而运行时
ENOSYS、io_uring 缓冲写在强制 SELinux 下被凭据问题全灭、`/proc/config.gz`
嵌入的是 defconfig 而非真实 `.config`；同时启用 BBR+FQ 为默认网络栈并移除
遗留拥塞控制（明细见 [`build-tools/BUILD.md`](build-tools/BUILD.md) 第 9 节）。

前代项目（v1.x–v2.0 线）的完整历史、弃用清单与 GCC 已知问题，
见 [docs/old-project.md](docs/old-project.md)。

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
running **Linux 4.19.325** — the final release of the 4.19 LTS series (2024-12-05, now EOL).

The tree is a three-way merge: the Juggutsu V6 MT6765 platform baseline, vanilla
4.19.325 LTS fixes, and the performance feature line from this repo's earlier
`main` (HZ=1000, BFQ default + per-cgroup, io_uring / memfd_secret / WireGuard
backports, pack/assert tooling).

**Positioning: performance-oriented, SELinux enforcing, no root by default.**
Build with LLVM/Clang 21 + LLD (ThinLTO). Prebuilt, device-verified `boot.img`
snapshots are published on
[Releases](https://github.com/plmzaq2112/android_kernel_mt6765/releases)
(currently **v2.2** = `boot-4.19.325-dandelion-llvm21.img`).

v2.2 fixes three latent issues inherited from the old line (memfd_secret
returning ENOSYS due to upstream's opt-in default, io_uring buffered writes
failing under enforcing SELinux, and config.gz embedding the wrong file) and
defaults to BBR + FQ.

**Highlights** (verified on a live device, config + syscall level):

| Feature | Config |
|---|---|
| BFQ as default I/O scheduler | `CONFIG_DEFAULT_BFQ=y`, `CONFIG_IOSCHED_BFQ=y` |
| BFQ per-cgroup hierarchy | `CONFIG_BFQ_GROUP_IOSCHED=y` |
| io_uring / memfd_secret / WireGuard | `CONFIG_IO_URING=y`, `CONFIG_SECRETMEM=y`, `CONFIG_WIREGUARD=y` |
| KSM (page merging) | `CONFIG_KSM=y` |
| PSI (pressure stall info) | `CONFIG_PSI=y` |
| Utilization clamping | `CONFIG_UCLAMP_TASK=y`, `CONFIG_UCLAMP_TASK_GROUP=y` |
| 1000 Hz tick, preemptible kernel | `CONFIG_HZ=1000`, `CONFIG_PREEMPT=y` |
| SELinux enforcing by default | `CONFIG_DEFAULT_SECURITY_SELINUX=y` |
| BBR congestion control + FQ qdisc | `CONFIG_TCP_CONG_BBR=y`, `CONFIG_NET_SCH_FQ=y` |
| **No root** | KernelSU absent (asserted by `check_config.sh`) |

**Build / pack / flash**

```bash
bash build-tools/build_full.sh
KERNEL_IMG=out/arch/arm64/boot/Image.gz \
  python3 build-tools/pack_boot.py <base_boot.img> <out_boot.img>
python3 build-tools/strip-selinux-permissive.py <out_boot.img>
fastboot flash boot <out_boot.img>
```

Details, configuration strategy and troubleshooting: [`build-tools/BUILD.md`](build-tools/BUILD.md).

**Disclaimer**: personal research project, not affiliated with Xiaomi, Google or
MediaTek. Flashing a custom kernel can brick your device — back up your original
`boot.img` first. Licensed under GPL-2.0.
