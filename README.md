<!-- SPDX-License-Identifier: GPL-2.0 -->
# Android 内核 · Redmi 9A（dandelion）

[![device](https://img.shields.io/badge/device-Redmi%209A%20dandelion-blue)](https://wiki.lineageos.org/devices/dandelion/)
[![license](https://img.shields.io/badge/license-GPL--2.0-lightgrey)](COPYING)
[![root](https://img.shields.io/badge/root-none-important)](#不包含的内容)

Redmi 9A（联发科 Helio G25，平台代号 MT6765）的 Android 内核源码。

> **定位：性能取向 · SELinux 强制 · 默认无 root。**
> 源码是本体，推荐自行编译；[Releases](https://github.com/plmzaq2112/android_kernel_mt6765/releases)
> 另提供已实机验证的 `boot.img`。

---

## 这个仓库是什么

- **设备**：Redmi 9A，代号 `dandelion`（不针对其他机型适配）
- **内容**：Android 内核源码本体 + 构建 / 打包 / 配置断言工具链（`build-tools/`）
- **构建配置**：[`arch/arm64/configs/blossom_defconfig`](arch/arm64/configs/blossom_defconfig)
- **许可**：GPL-2.0（同 Linux 内核）

## 特性

性能与功能取向的配置：BFQ 默认 I/O 调度（含 cgroup 分层）、io_uring、
memfd_secret、WireGuard、BBR + FQ、KSM、PSI、UCLAMP、高精度时钟与抢占式内核，
以及强制 SELinux 策略。具体清单与设计说明见
[`build-tools/BUILD.md`](build-tools/BUILD.md)。

## 不包含的内容

- **不含任何 root 方案**：树内没有 KernelSU 源码，配置断言会持续保证这一点。
- **不开可加载模块**：全树 built-in，体积与攻击面更小，代价是无法单独替换 `.ko`。
- **预编译镜像不作担保**：[Releases](https://github.com/plmzaq2112/android_kernel_mt6765/releases)
  里的 `boot.img` 只是某一提交的快照，源码才是本体。

## 构建

完整说明见 [`build-tools/BUILD.md`](build-tools/BUILD.md)。核心流程：

```bash
# 依赖（Debian/Ubuntu）
sudo apt install build-essential bison bc flex libssl-dev libelf-dev \
                 clang lld llvm binutils-aarch64-linux-gnu python3

# 一键构建：defconfig → 配置断言 → Image.gz
bash build-tools/build_full.sh
```

产物：`out/arch/arm64/boot/Image.gz`（输出目录已加入 `.gitignore`）。

## 打包与刷入

只替换 kernel，ramdisk / dtb / 头部字段沿用基准镜像：

```bash
KERNEL_IMG=out/arch/arm64/boot/Image.gz \
  python3 build-tools/pack_boot.py <基准boot.img> <输出boot.img>
python3 build-tools/strip-selinux-permissive.py <输出boot.img>

adb reboot bootloader
fastboot flash boot <输出boot.img>
fastboot reboot
```

> **刷入前务必备份原 boot 镜像。** 刷错镜像会导致无法开机，
> 需要通过 fastboot / recovery 恢复。

## 仓库结构

```
.
├── README.md                    本文件
├── arch/arm64/configs/
│   └── blossom_defconfig        构建配置
├── build-tools/                 构建 / 打包 / 断言工具（详见 BUILD.md）
├── Documentation/               Linux 内核自带文档
└── arch/ block/ drivers/ fs/ mm/ net/ kernel/ security/ ...
│                                内核源码本体
```

## 免责声明

- 本项目为个人学习与研究用途，与 Xiaomi、Google、MediaTek 无任何关联。
- 刷写第三方内核存在风险，可能造成数据丢失或设备无法开机。
  **刷入前请备份原 boot 镜像**，并确保有恢复手段（fastboot / recovery）。
- 本仓库不对使用本代码造成的任何损失负责。

## 许可

内核源码遵循 Linux 内核的许可条款：

```
SPDX-License-Identifier: GPL-2.0 WITH Linux-syscall-note
```

详见 [`COPYING`](COPYING) 与 [`LICENSES/`](LICENSES/)。
`build-tools/` 下的辅助脚本同样以 **GPL-2.0** 授权。

---

## English summary

Android kernel source for the Redmi 9A (codename *dandelion*, MediaTek MT6765).
**Positioning: performance-oriented, SELinux enforcing, no root by default.**
The source is the primary artifact; prebuilt, device-verified `boot.img`
snapshots are published on
[Releases](https://github.com/plmzaq2112/android_kernel_mt6765/releases).
Build / pack / flash: see [`build-tools/BUILD.md`](build-tools/BUILD.md).
GPL-2.0.
