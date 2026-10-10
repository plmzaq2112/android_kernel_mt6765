<!-- SPDX-License-Identifier: GPL-2.0 -->
# 构建与维护指南 · Redmi 9A（dandelion）

面向**想要自己编译、修改并刷入本内核**的人。项目概述、特性与免责声明见
根目录的 [`README.md`](../README.md)。

- 仓库：https://github.com/plmzaq2112/android_kernel_mt6765
- 分支：`main`（4.19.325 / 无 root）；升级前状态保留在 `archive/4.19.275`
- 实测环境：Ubuntu + WSL2，LLVM/Clang 21，Redmi 9A 实机（Android 16 / API 36）

> **只想刷镜像、不需要改源码？**
> 直接去 [Releases](https://github.com/plmzaq2112/android_kernel_mt6765/releases) 下载
> 已实机验证的 `boot.img`（当前 **v2.0** = `boot-4.19.325-dandelion-perf.img`），
> sha256 与分段 md5 见 release notes。下面的流程是给要改配置、改代码的人看的。

---

## 1. 环境要求

```bash
sudo apt install build-essential bison bc flex libssl-dev libelf-dev \
                 clang lld llvm binutils-aarch64-linux-gnu python3
```

需要的东西：

| 组件 | 用途 | 实测版本 |
|---|---|---|
| `clang` / `ld.lld` / `llvm-nm` `llvm-ar` `llvm-objcopy` `llvm-objdump` `llvm-strip` | 编译内核本体 | LLVM 21 |
| `aarch64-linux-gnu-` 前缀工具 | 交叉编译前缀（`CROSS_COMPILE`） | binutils |
| `bison` `flex` `bc` `libssl-dev` `libelf-dev` | kbuild 依赖 | — |
| `python3` | 打包脚本 | 3.x |

> **重要：这台机器上装了两个 clang。** 默认 PATH 下 `clang` 指向 `/usr/bin/clang`
> （21.x），而本项目实测用的是 `/usr/lib/llvm-18/bin/`（18.x）。因此
> **先设 PATH，再看版本**，且之后每条 `make` 前都要带上这一行：
>
> ```bash
> export PATH=/usr/lib/llvm-21/bin:/usr/bin:/bin:/usr/local/bin:$PATH
> ```
>
> 少了它，你会在毫无提示的情况下用 clang 21 编出一个与实测环境不同的内核。
> 编译完可复核实际使用的编译器（见 §3 产物表）。

确认工具链（在上面 `export` 之后执行）：

```bash
clang --version      # 期望 Ubuntu clang version 21.1.8
ld.lld --version     # 期望 Ubuntu LLD 21.1.8
aarch64-linux-gnu-ld --version
```

---

## 2. 构建配置：`blossom_defconfig`

**位置**：[`arch/arm64/configs/blossom_defconfig`](../arch/arm64/configs/blossom_defconfig)

这是本仓库唯一的构建入口。同目录的 `stock_defconfig` / `gki_defconfig` /
`defconfig` 为基线自带配置，**不用于当前构建**，仅作对照。

### 2.1 相对基线追加的选项

以下几项是本项目显式追加的，也是"性能 + 无 root"定位的来源：

| 配置行 | 含义 |
|---|---|
| `CONFIG_HZ_1000=y` | 1 ms 调度粒度（取代默认 250 / 300 Hz） |
| `CONFIG_IOSCHED_BFQ=y` + `CONFIG_BFQ_GROUP_IOSCHED=y` + `CONFIG_DEFAULT_BFQ=y` | BFQ I/O 调度器、按 cgroup 分层、并设为默认 |
| `CONFIG_IO_URING=y` | io_uring（5.x 特性反向移植，见 §9） |
| `CONFIG_SECRETMEM=y` | `memfd_secret()`（反向移植） |
| `CONFIG_WIREGUARD=y` | WireGuard VPN（反向移植） |
| `CONFIG_KSM=y` | 内核同页合并，降低内存占用 |
| `CONFIG_MICROTRUST_TZ_LOG=y` + 安全媒体链 7 项 | TEE/Keymaster/Widevine 依赖，见 `fix11.config` |
| `# CONFIG_MICROTRUST_FP_DRIVER is not set` | dandelion 无指纹硬件，关闭噪音驱动 |

> 本树**没有** KernelSU 源码；基线 defconfig 曾残留 `CONFIG_KSU=y` 等死配置行
> （olddefconfig 阶段被静默丢弃），整合时已清除，`check_config.sh` 会断言
> `KSU` / `KSU_SUSFS` 必须缺席。

### 2.3 已知惰性项：`CONFIG_CMDLINE`

`blossom_defconfig` 里的 `CONFIG_CMDLINE="ramoops_memreserve=4M"` **在本内核上
不产生任何效果**，原因有两层：

1. `arch/arm64/Kconfig` 的 cmdline type choice 是
   `default CMDLINE_FROM_BOOTLOADER`，defconfig 没写 `CONFIG_CMDLINE_EXTEND`，
   生成的 `.config` 是 `CONFIG_CMDLINE_FROM_BOOTLOADER=y` —— Android bootloader
   必然传自己的 cmdline，内建值被整体覆盖。
2. 全树 grep 确认**没有任何 `.c` 解析 `ramoops_memreserve`**（它只出现在
   defconfig 与生成的 `autoconf.h` 里）。即便打开 `CMDLINE_EXTEND`，也只是
   追加一个没人读的参数。

实测 `/sys/fs/pstore` 正常（`console-ramoops-0`、`pmsg-ramoops-0` 都在），
说明 DT 已预留 ramoops 内存，这行**留着无害、删了也无妨**，本项目选择不动它。

### 2.2 修改配置的正确做法

```bash
# 1. 直接编辑 defconfig（不要编辑 out/.config）
$EDITOR arch/arm64/configs/blossom_defconfig

# 2. 重新生成 .config
make O=out ARCH=arm64 CC=clang CROSS_COMPILE=aarch64-linux-gnu- \
     LD=ld.lld NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump \
     STRIP=llvm-strip AR=llvm-ar blossom_defconfig

# 3. 跑断言，确认没有被静默改动
bash build-tools/check_config.sh out/.config
```

**永远不要直接改 `out/.config`** —— 下次执行 `blossom_defconfig` 会被覆盖，
而且这类改动不会进入版本控制，容易出现"我本地能跑、别人编不出来"的问题。

---

## 3. 编译

```bash
export PATH=/usr/lib/llvm-18/bin:/usr/bin:/bin:/usr/local/bin:$PATH

make O=out ARCH=arm64 \
     CC=clang CROSS_COMPILE=aarch64-linux-gnu- \
     LD=ld.lld NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump \
     STRIP=llvm-strip AR=llvm-ar \
     blossom_defconfig

make -j"$(nproc)" O=out ARCH=arm64 \
     CC=clang CROSS_COMPILE=aarch64-linux-gnu- \
     LD=ld.lld NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump \
     STRIP=llvm-strip AR=llvm-ar \
     Image.gz
```

产物：

| 文件 | 说明 |
|---|---|
| `out/arch/arm64/boot/Image.gz` | 内核镜像，打包时用它 |
| `out/System.map` | 符号表，用于确认某选项是否真的编入 |
| `out/.config` | 实际生效的配置 |
| `out/include/generated/utsrelease.h` | `UTS_RELEASE`，形如 `4.19.325-mt6765` |
| `out/include/generated/compile.h` | `LINUX_COMPILER`，记录本次实际使用的编译器 |

复核编译器（确认没被默认 PATH 的另一个 clang 偷偷替换）：

```bash
grep LINUX_COMPILER out/include/generated/compile.h
#   #define LINUX_COMPILER "Ubuntu clang version 21.1.8, Ubuntu LLD 21.1.8"
```

或直接用一键脚本（`defconfig` → 断言 → `Image.gz` 三步，日志写到 `build.log`）：

```bash
bash build-tools/build_full.sh
# O=out-test bash build-tools/build_full.sh   # 指定输出目录
```

> `out*/` 已在 `.gitignore` 中，编译产物不会进入版本控制。

### 3.1 确认选项确实编入了内核

Kconfig 打开只是必要条件，还需要确认代码真的被编译进镜像：

```bash
# 看符号（最直接）
grep -E 'bfq_(find_set_group|create_group_hierarchy)' out/System.map

# 看构建配置
grep -E '^CONFIG_(IOSCHED_BFQ|BFQ_GROUP_IOSCHED)=' out/.config
grep BFQ out/include/generated/autoconf.h
```

> **踩坑提示**：在 `Image.gz` 解压后的二进制里 grep 符号名是**不可靠**的，
> 因为 kallsyms 名称在镜像中是压缩存储的，字符串匹配会得到假阴性。
> 请用 `System.map` 或设备上的 `/proc/config.gz`。

### 3.2 产物不是逐字节可复现的（2026-09-30 实测）

同源码、同 `.config`、同工具链，**两次全新清编得到的 `Image.gz` sha256 不同**：

| 构建 | `Image.gz` sha256 前 8 | `Image`(未压缩) | `System.map` 行数 |
|---|---|---|---|
| `out-325noksu`（出货 #8） | `7569cba0` | 24485904 | 104267 |
| `out-325r2`（本次） | `3fedfc40` | 24485904 | 104267 |
| `out-325r3`（同源码复编） | `c905b036` | 24485904 | 104267 |

- `.config` 三者 **sha256 完全相同**（`cee71a24…`），`check_config` 三者 OK
- 符号**集合**完全相同：104267 行 / 33543 全局符号 / 55405 `.text` 符号 / `Image` 大小字节相同
- 但**地址有漂移**：`r2` vs `r3`（同源码！）就已有 **1330 条全局符号地址差异**、
  130 条 `.text` 差异；`r2` vs `#8` 也是 1330 条
- 根因是 LTO：`System.map` 里局部符号叫 `.llvm.<hash>`，**两次构建的 hash 不同**
  （例 `…11507468323379073849` → `…5950583517903573380`，20 位 vs 19 位），
  名字长度不同 → kallsyms 字符串表尺寸不同 → 其后数据地址整体位移

> **结论**：核对产物**不要比 `Image.gz` 的 sha256**，要比
> `.config` 的 sha256 + `check_config.sh` 的输出 + `System.map` 的**符号集与
> 行数**。逐字节相同只在配置层成立，不在镜像层成立。
> 顺带：`System.map` 里 LTO 局部符号的 `.llvm.<hash>` 会让
> `sed 's/\.llvm\.[0-9]+//'` 规范化后仍不相等——因为差异已传播到真实数据地址。

---

## 4. 配置断言：`check_config.sh`

历史教训：`olddefconfig` / 级联依赖可能**静默关掉**某些选项——尤其是 TEE / ION
secure heap 这类一关就整条链被清除的项（`build-tools/fix11.config` 正是为此保留的
参考片段）。因此每次改配置后都要跑断言。

```bash
bash build-tools/check_config.sh out/.config
```

脚本会检查：

- **必须开启**（`must_y`，45 项）：BFQ 三件套、io_uring、KSM、PSI、UCLAMP、
  BBR/FQ、KALLSYMS_BASE_RELATIVE、SECRETMEM、WireGuard、PREEMPT、SELinux 默认强制，以及
  **fix11 的两处不变量** —— TEE 全家 7 项、安全媒体链
  （`MTK_SEC_VIDEO_PATH_SUPPORT` / `MTK_DRM_KEY_MNG_SUPPORT` / `MTK_ION_SEC_HEAP` /
  `MTK_SECURE_MEM_SUPPORT` + trusted_mem 编入链 3 项）、`ARM64_SW_TTBR0_PAN`。
  本树为 built-in-only（不开 `MODULES`），旧线的模块钉子不适用
- **必须关闭**（`must_n`，14 项）：`CONFIG_KSU` / `CONFIG_KSU_SUSFS`（无 root）、指纹/NFC 四项
  （`MICROTRUST_FP_DRIVER` / `FPC_FINGERPRINT` / `FOCALTECH_FINGERPRINT` / `NFC`
  —— 前三项 Kconfig 是 `default y`，不显式写就自动开；`NFC` 实为 `default n`）、
  调试与性能损耗项（`KASAN` / `UBSAN` / `DEBUG_PREEMPT` / `DEBUG_INFO` /
  `KALLSYMS_ALL`）、无用噪音（`IKHEADERS`）、
  遗留拥塞控制（`TCP_CONG_BIC` / `TCP_CONG_WESTWOOD`，BBR+CUBIC 足够）
- **精确值**（`must_eq`，5 项）：`HZ=1000`、`HZ_1000=y`、
  `MICROTRUST_TEE_VERSION="300"`、`DEFAULT_IOSCHED="bfq"`、
  `DEFAULT_TCP_CONG="bbr"`

任何一项不符即返回非零退出码。**把它接在构建前**，可以避免编出一个"看起来
成功、实际配置错了"的镜像。

> **踩坑：断言必须断到 Makefile 实际使用的符号。**
> 曾经 `CONFIG_MTK_SECURE_MEM_SUPPORT=y` 断言通过，但
> `drivers/misc/mediatek/Makefile` 认的是 `obj-$(CONFIG_MTK_TRUSTED_MEMORY_SUBSYSTEM)`，
> 而它依赖的 `HAVE_MTK_TRUSTED_MEMORY_SUBSYSTEM` **全树无人 `select`**
> （Kconfig 注释写着"auto selected by other option"，实际没有），
> 只能手动写。结果 Kconfig 层显示"已开"，`trusted_mem/` 却一个 `.o` 都没生成，
> Keymaster 依赖的 secure memory 通路照断。所以那三项必须一起断。
>
> 反向验证：`sed` 把任一项改成 `is not set` 再跑断言，必须返回 1。

---

## 5. 打包：`pack_boot.py`

### 5.1 原理

Android `boot.img` 是分段布局（header v1/v2，按 `page_size` 对齐）：

```
+------------+----------------+-----------+--------+-----+
|  header    |  kernel        |  ramdisk  | (sec)  | dtb |
+------------+----------------+-----------+--------+-----+
 page        page             page                  page
```

`pack_boot.py` 的策略是**只替换 kernel 段**：

1. 读取基准 `boot.img` 的 header（保留 `kernel_addr`、`ramdisk_addr`、
   `tags_addr`、`dtb_size` 等全部字段）
2. 从文件偏移定位原 ramdisk 与 dtb，原样拷贝
3. 写入新的 `Image.gz`，更新 header 的 `kernel_size`
4. 各段按 `page_size` 重新对齐；若结果短于原文件则补齐到**等长**（分区对齐要求）

这样 ramdisk 与 dtb 完全继承你的 ROM，不引入任何兼容性变量。

### 5.2 用法

```bash
KERNEL_IMG=out/arch/arm64/boot/Image.gz \
  python3 build-tools/pack_boot.py <基准boot.img> <输出boot.img>
```

- `<基准boot.img>`：**必须与当前 ROM 匹配**，建议自行 `adb shell` 备份一份
- 可选 `RAMDISK_IMG=<file>` 环境变量替换 ramdisk（一般不需要）
- `KERNEL_IMG` 未指定时，默认取 `<树根>/out/arch/arm64/boot/Image.gz`
  （对应 `build_full.sh` 的默认 `O=out`；用别的 `O=` 时请显式传 `KERNEL_IMG`）
- 第二个参数省略时，输出默认为 `<树根>/out/boot-repacked.img`
  —— **建议始终显式指定输出文件名**，遵循 `boot-{ver}-{device}-{variant}.img` 命名

输出示例：

```
page_size=2048 header_version=2
原 kernel: 11123566 bytes
ramdisk:   737009 bytes @0xa9c800
dtb:       126985 bytes @0xb50800
kernel:    10940634 bytes
output:    ... (67108864 bytes) vs 原 67108864 bytes
```

### 5.3 打包后必须做的校验

```bash
IMG=<输出boot.img>
BUILT=out/arch/arm64/boot/Image.gz

# 注意：`python3 - a b <<'PY'` 里的 a b 会成为 sys.argv[1] sys.argv[2]
python3 - "$IMG" "$BUILT" <<'PY'
import struct, sys, zlib, hashlib
img, built = sys.argv[1], sys.argv[2]
d = open(img, "rb").read()
page = struct.unpack_from("<I", d, 36)[0]
ks   = struct.unpack_from("<I", d, 8)[0]
kern = d[page:page+ks]
dec  = zlib.decompressobj(31).decompress(kern)
print("md5_match =", hashlib.md5(kern).hexdigest() ==
                   hashlib.md5(open(built, "rb").read()).hexdigest())
print("uts_325   =", b"4.19.325-dandelion" in dec)
print("compiler  =", b"clang version" in dec)
PY

# 无 root：不要在镜像里 grep 字符串（kallsyms 压缩，会假阴性），看符号表
grep -cE '\bksu' out/System.map          # 期望 0
grep -ic kernelsu out/System.map         # 期望 0
grep -E '^# CONFIG_KSU is not set' out/.config
```

- `md5_match` 必须为 `True` —— 它证明写进镜像的确实是你刚编出来的内核，
  而不是基准镜像里原来那个。
- `uts_325` 必须为 `True` —— `linux_banner` 是普通字符串（不参与 kallsyms 压缩），
  这一条可以放心用字符串匹配。
- `grep ksu` 必须是 **0** —— 见 §3.1 的踩坑提示，这只能用 `System.map` 判定。
  **`\b` 不能省**：少了词首锚定，`ksu` 会匹配到 56 个 `checksum` / `chksum` 符号
  （`ch`**`ksu`**`m`），把一台干净机器误报成"装了 KernelSU"。
  实测：`grep -E '\bksu'` = 0，`grep -E 'ksu'` = 56 —— 差别全在 checksum。

---

## 6. SELinux：移除 permissive 启动参数

原厂 `boot.img` 的 header cmdline 带有：

```
androidboot.selinux=permissive
```

只要这个参数在，即使内核配置是强制模式，启动后仍会进入 permissive。
所以打包后必须移除：

```bash
python3 build-tools/strip-selinux-permissive.py <输出boot.img>
```

脚本读取 header 的两段命令行：

| 字段 | 偏移 | 长度 | 适用 |
|---|---|---|---|
| `cmdline` | 64 | 512 字节 | 所有版本 |
| `extra_cmdline` | 608 | 1024 字节 | 所有版本（`boot_img_hdr_v0` 里就有，不是 v1+ 才有） |

删除该参数后回写（原子替换，先写 `.new` 再 rename），并回显**两段**修改前后的
完整内容；`verify` 阶段两段都查，任一段仍残留即 `exit 1`：

```
patching out.img -> out.img
  patched region @64: removed androidboot.selinux=permissive
  old: ... androidboot.selinux=permissive androidboot.debuggable=1
  new: ... androidboot.debuggable=1
verify cmdline @64: '...'
verify cmdline @608: '...'
still has permissive: False
```

> 内核侧的配合：`CONFIG_SECURITY_SELINUX_BOOTPARAM` 为未开启，
> 因此不存在 `selinux=0/1` 内核参数可以覆盖，强制状态是稳的。
> 若你的 ROM 里还有 `androidboot.selinux=permissive`，刷入后请务必
> `adb shell getenforce` 复查。

---

## 7. 刷入

```bash
adb reboot bootloader
fastboot flash boot <输出boot.img>
fastboot reboot
```

**刷前必备份**（可逆的前提）：

```bash
adb shell "dd if=/dev/block/bootdevice/by-name/boot of=/sdcard/boot-backup.img"
adb pull /sdcard/boot-backup.img
```

刷完不开机时的恢复手段：`fastboot flash boot <原厂boot.img>` 回滚。

---

## 8. 验证

```bash
# 内核版本（应为 4.19.325-dandelion）
adb shell uname -r

# SELinux（应为 Enforcing）
adb shell getenforce

# 无 root
adb shell "which su || echo su-absent"

# 运行内核的真实配置（最权威的核对）
adb shell "zcat /proc/config.gz | grep -E 'BFQ|IO_URING|^CONFIG_KSM=|^CONFIG_PSI=|UCLAMP|^CONFIG_HZ=|CONFIG_KSU'"
```

`/proc/config.gz` 来自内核自身嵌入的配置（由 `kernel/Makefile` 从
`$(objtree)/.config` 生成），因此它反映的一定是**正在运行的这份内核**。

> SELinux 强制模式下，非特权 shell 读取部分 `/sys`、`/proc/kallsyms`
> 会被拒绝 —— 这是正常现象，恰恰说明强制模式生效了。
> 此时用 `/proc/config.gz` 与 `uname -r` 即可完成验证。

---

## 9. 源码移植记录（在当前树中可见）

以下移植/修复在当前源码树中可以查到，供排查问题时定位：

| 位置 | 内容 |
|---|---|
| `kernel/Makefile`（约 128 行） | `config_data.gz` 数据源改为 `$(objtree)/.config`，使 `/proc/config.gz` 显示真实构建配置（基线错误地压缩 `stock_defconfig`） |
| `fs/io_uring.c` + `include/uapi/linux/io_uring.h` + `unistd` 425-427 | io_uring 移植（整合自 v2.0 线） |
| `mm/secretmem.c` + `unistd` 447 | `memfd_secret` 移植（整合自 v2.0 线） |
| `drivers/net/wireguard/` | WireGuard 移植（整合自 v2.0 线）。`compat/` 为承重移植层（Kbuild 无条件 include，垫 5.x API 到 4.19）；`tests/` 与 `dkms.conf` 为树外打包残留，已删 |
| `block/Kconfig.iosched` | 新增 `DEFAULT_BFQ` 选项，BFQ 可设为默认调度器 |
| `include/uapi/asm-generic/unistd.h` | io_uring 425-427、memfd_secret 447，`__NR_syscalls` 442→448 |
| `include/linux/socket.h` + `net/socket.c` | `struct socket` 前置声明 + `__sys_sendmsg/recvmsg_sock`（clang 严格拒绝原型私有结构体） |
| `kernel/signal.c` + `sched/signal.h` + `compat.h` | `set_user_sigmask` 系列（io_uring 信号掩码） |
| `fs/sync.c` | `sync_file_range(struct file *)` 拆分（io_uring sync，配套 ksys 重构） |
| `include/linux/ioprio.h` | `get_current_ioprio()` 内联 |
| `mm/mmap.c` + `mm.h` | `mlock_future_check` 非静态化 |
| `include/uapi/linux/magic.h` | `SECRETMEM_MAGIC` |
| `drivers/tee/teei/300/tz_driver/sysfs.c` | `wake_up(&__wait_spi_wq)` 加 `FP_DRIVER` 守卫（基线漏守卫，FP 关闭时链接失败） |
| `fs/io_uring.c`（`io_kiocb.creds` + `io_sq_wq_submit_work`） | io-wq 凭据修复：请求保存提交者凭据、工作线程 `override_creds`/`revert_creds`（5.3 快照缓冲写一律踢给内核线程，强制 SELinux 下被静默拒写；上游同款修法） |
| `mm/secretmem.c`（`secretmem_enable`） | `memfd_secret` 默认开启（上游原为 opt-in，默认关则运行时 ENOSYS——旧线即如此，只验配置未验调用） |
| `net/sched/sch_generic.c` + `net/sched/sch_fq.c` + `drivers/misc/mediatek/Kconfig.default` + defconfig | BBR+FQ 默认：`fq_qdisc_ops` 去 static、默认 qdisc 换 fq；移除 MTK `select TCP_CONG_BIC` 并关闭 BIC/WESTWOOD（厂商 init 强写 bic 无害失败，BBR 默认值生效） |
| `arch/arm64/configs/blossom_defconfig` | 删除 `KALLSYMS_BASE_RELATIVE` 无解释关闭钉子（恢复 arm64 默认开） |

> `build-tools/fix11.config` 是早期的配置片段，记录了 TEE / ION secure heap
> 的**两处不变量**（这些选项**不可随意关闭**，否则会级联清掉 Keymaster / Widevine
> 依赖——症状是校园网类 APP 报"密钥过期"，因为它绑的是设备硬件密钥）：
>
> 1. **TEE 全家**：`CONFIG_TEE` + `MICROTRUST_{TEE_SUPPORT,TZ_DRIVER,DYNAMIC_CORE,
>    VFS_DRIVER,KEYMASTER_DRIVER,TZ_LOG}`
> 2. **ION secure heap**：`CONFIG_MTK_SECURE_MEM_SUPPORT=y`，且必须连带
>    `HAVE_MTK_TRUSTED_MEMORY_SUBSYSTEM` / `MTK_TRUSTED_MEMORY_SUBSYSTEM` /
>    `MTK_SSMR`（后三项才是 Makefile 真正看的，见 §4 踩坑）
>
> 同一片段还关掉了指纹/NFC 四项（`MICROTRUST_FP_DRIVER`、`FPC_FINGERPRINT`、
> `FOCALTECH_FINGERPRINT`、`NFC`）——dandelion 没有指纹硬件，前三项
> Kconfig 是 `default y`，不关就白留一个驱动挂在那。
> **措辞更正**：这不是"指纹风暴"的已知来源 —— 实测当前 `.config` 里
> 框架开关 `CONFIG_MTK_FINGERPRINT_SUPPORT=y` 仍在，而 dmesg 指纹命中 **0**、
> `/sys/class/fingerprint` 不存在、无日志噪音。关这三项是"无硬件不白编"，
> 不是"止血"。若真出现指纹日志刷屏，再把 `MTK_FINGERPRINT_SUPPORT` 一并关掉
> （会改变 `.config`，需要重编译+重刷）。
>
> 当前流程**不使用** `merge_config.sh`，该文件仅作参考保留。

---

## 10. 变更流程

改配置或改代码时，按这个顺序走，可以避免大部分"编过了但不对"的问题：

```
1. 改 arch/arm64/configs/blossom_defconfig   （不要改 out/.config）
2. make blossom_defconfig                    重新生成
3. bash build-tools/check_config.sh out/.config   断言
4. make Image.gz                             编译
5. 校验 System.map / autoconf.h              确认选项真编进去了
6. pack_boot.py 打包 → md5_match 必须 True
7. strip-selinux-permissive.py 去 permissive
8. 刷入 → uname -r / getenforce / zcat /proc/config.gz 验证
9. 提交（配置改动必须和代码一起提交，说明动机）
```

提交信息建议沿用仓库现有风格：**英文单行、`模块: 动作` 前缀**，例如
`blossom_defconfig: enable BFQ hierarchical (per-cgroup) scheduling`。

---

## 11. 常见问题

**Q：编译报 `drivers/iio/Kconfig: can't open file`**
A：源码不完整，缺少 `drivers/iio/addac/` 等目录。重新同步完整源码树。

**Q：编译报 `include/net/netns/netfilter.h` 头尾不匹配**
A：这是三方合并最容易出的问题——`#if*` 与 `#endif` 数量不相等。
用下面命令自查（当前树应为 6 : 6）：

```bash
awk '/^#if/{i++} /^#endif/{e++} END{print i, e}' include/net/netns/netfilter.h
```

**Q：改了 defconfig 但 `out/.config` 没变**
A：`blossom_defconfig` 目标才会重新生成 `.config`；只跑 `make` 不会。

**Q：`getenforce` 还是 Permissive**
A：镜像的 header cmdline 里还有 `androidboot.selinux=permissive`，
执行第 6 节的 strip 脚本后重新刷入。

**Q：在 `Image.gz` 里 grep 不到 `kernelsu` / `bfq_find_set_group`**
A：不能据此下结论——kallsyms 名称在镜像中是压缩存储的，字符串匹配会**假阴性**。
改用 `out/System.map`（`grep -ciE '\bksu'` 应为 0）或设备端 `/proc/config.gz`。
