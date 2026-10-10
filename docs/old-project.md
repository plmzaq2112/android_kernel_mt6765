<!-- SPDX-License-Identifier: GPL-2.0 -->
# 旧项目档案 · v1.x–v2.0 线

> 本文件是前代项目（曾作为本仓库 `main` 的 4.19.275/4.19.325 纯净内核线，
> 源码本地保留于 `~/android_kernel_mt6765`，已停止维护）的完整存档。
> 其可移植成果已全部并入当前树；此处记录历史、决策与已知问题，供回溯。

## 版本时间线

| 版本 | 内核 | 产物 | 说明 |
|---|---|---|---|
| v1.0 | 4.19.275 | `boot-4.19.275-full-v11.img` | v11 线全量版（仓库尚带 KernelSU 配置痕迹的年代） |
| v1.1 | 4.19.275 | `boot-4.19.275-perf-v2.img` | 关闭 root 的干净基线 |
| v2.0 | 4.19.325 | `boot-4.19.325-dandelion-perf.img` | 与 vanilla 4.19.325 三方合并 + 性能特性；**GCC15 构建，后发现 WiFi 缺陷，tag 已从 GitHub 删除** |

当前仓库的 **v2.2**（Latest）不属于旧线：它由当前树（Juggutsu 基线）用 Clang 21 构建，
在 v2.1（Clang 18，实机验证 WiFi 正常，取代 v2.0）的基础上修复了旧线三个隐藏问题
（`memfd_secret` ENOSYS、io_uring 写在强制 SELinux 下失效、`config.gz` 数据源）并启用 BBR+FQ。

旧线共 11 个提交，关键节点：

```
bootstrap
import: Android 4.19.275-mt6765 (dandelion) kernel source
v11ksu: KernelSU direct kernel for dandelion (stable V5/V6 build lineage)
upgrade: 4.19.275 -> 4.19.325 (3-way merge against vanilla)   # 3494 文件
blossom_defconfig: no-root + performance features
blossom_defconfig: enable BFQ hierarchical scheduling
build-tools: pack_boot.py + 配置断言
docs: README + BUILD.md
```

## 与当前树的关系

两树血统不同：

| | 旧项目 | 当前树 |
|---|---|---|
| 基线 | MTK BSP 导入 "Android 4.19.275-mt6765" | Juggutsu V6（`cc5ffee71`） |
| 升级方式 | 与 vanilla 4.19.325 三方合并 | merge vanilla 4.19.325 + 13 项审计修复 |
| 品牌 | `UTS=4.19.325-mt6765` | `UTS=4.19.325-dandelion` |
| 模块策略 | `MODULES=y`（电池/音频/westwood 等为模块） | built-in-only |
| 工具链终点 | GCC15（v2.0） | LLVM 21 + ThinLTO |

当前树 = Juggutsu 基线 + vanilla 4.19.325 + **旧线经验的手术式移植**
（逐文件清单见 [`build-tools/BUILD.md`](../build-tools/BUILD.md) 第 9 节）。
移植的只有验证过的特性与修复；两树的 git 历史没有合并。

## 保留下来的成果

- **特性**：HZ=1000、BFQ 默认 + cgroup 分层、io_uring、memfd_secret、
  KSM、PSI、UCLAMP、SELinux 强制（strip permissive cmdline）
- **工具**：`pack_boot.py`（只换 kernel 的重打包）、
  `strip-selinux-permissive.py`、配置断言脚本（现升级为
  `check_config.sh`，断言项从旧线踩坑沉淀而来）
- **修复**：`/proc/config.gz` 数据源改为真实 `.config`、teei sysfs
  `FP_DRIVER` 守卫
- **决策**：无 root 定位、不动 ramdisk 的打包策略、实机 `/proc/config.gz`
  核对习惯

## 弃用不带入的

| 项 | 原因 |
|---|---|
| KernelSU（v11 线时代） | 定位是无 root 日常内核；当前树无 kernelsu 源码，基线残留的 `CONFIG_KSU=y` 死行已清除 |
| `MODULES=y` | 当前树全部 built-in，更小攻击面；代价是不可换 `.ko` |
| ntfs3（21 个 .c，旧树未启用） | 新树无此代码，`CONFIG_NTFS3_FS` 从未开启 |
| openat2 反向移植 | 未启用，收益小 |
| gen4m Makefile 的 `-Wno-error`、gl_kal.c suspend 同步块 | 旧树为 GCC 兼容所做的让步，当前树 clang 构建无此需求 |
| 37 个 `*.orig` / `*~` 备份文件 | 垃圾 |

## 已知问题存档：GCC15 版 WiFi 缺陷（v2.0）

**症状**：开启 WiFi 后偶发卡死；扫描入口返回 -EINVAL。

**定位**（pstore `console-ramoops-0` 实录）：

- 挂死于 `scanGetCurrentEssChnlList()`（ap_selection.c 排空循环，
  `LINK_PEEK_HEAD` / `container_of` 索引 `rLinkEntryEss[ucBssIndex]`）——
  BSS 索引错乱时 `linkDel` 删错节点，链表排空条件永不满足 → 死循环；
- `nl80211_trigger_scan` 等待链最终超时；
- 扫描 -EINVAL 源于 `wlanGetBssIdx != 0`（`KAL_AIS_NUM=1` 时合法索引只有 0）。

两症状同源：GCC15 代码生成下驱动 BSS 索引/状态被写歪（疑涉未定义行为），
**非源码逻辑错误**——同一份源码 Clang 18/21 构建实机 WiFi 正常。

**处置**：归档为已知问题，不修；v2.0 的 GitHub tag 已删除防止误用。
v2.1 及之后的 clang 构建不受影响。

## 经验教训（已固化进流程）

1. defconfig 里"看起来关掉了"的选项会被 `default y` 的 Kconfig 重新打开
   → `check_config.sh` 对关键项做强制断言；
2. tristate 默认值随 `MODULES` 开关漂移 → 新树直接不开模块，钉子项全部 `=y`；
3. 基线的 `config_data.gz` 可能压错文件（曾压 `stock_defconfig`）→
   已改为 `$(objtree)/.config`，`/proc/config.gz` 以实机核对为准；
4. 跨编译器的未定义行为（GCC15 WiFi）只能靠换编译器实测暴露 →
   重要改动必须实机验证，不能只看编译通过。

---

*档案整理于 2026-10-10；旧项目源码快照仅存本地，不再接受更新。*
