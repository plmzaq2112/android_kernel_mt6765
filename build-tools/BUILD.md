<!-- SPDX-License-Identifier: GPL-2.0 -->
# 构建与维护指南 · Redmi 9A（dandelion）

面向**想要自己编译、修改并刷入本内核**的人。项目概述、特性与免责声明见
根目录的 [`README.md`](../README.md)。

- 仓库：https://github.com/plmzaq2112/android_kernel_mt6765
- 分支：`main`（4.19.325 / 无 root）；升级前状态保留在 `archive/pre-325`
- 实测环境：Ubuntu + WSL2，LLVM/Clang 18，Redmi 9A 实机（Android 16 / API 36）

---

## 1. 环境要求

```bash
sudo apt install build-essential bison bc flex libssl-dev libelf-dev \
                 clang lld llvm binutils-aarch64-linux-gnu python3
```

需要的东西：

| 组件 | 用途 | 实测版本 |
|---|---|---|
| `clang` / `ld.lld` / `llvm-nm` `llvm-ar` `llvm-objcopy` `llvm-objdump` `llvm-strip` | 编译内核本体 | LLVM 18 |
| `aarch64-linux-gnu-` 前缀工具 | 交叉编译前缀（`CROSS_COMPILE`） | binutils |
| `bison` `flex` `bc` `libssl-dev` `libelf-dev` | kbuild 依赖 | — |
| `python3` | 打包脚本 | 3.x |

> **重要：这台机器上装了两个 clang。** 默认 PATH 下 `clang` 指向 `/usr/bin/clang`
> （21.x），而本项目实测用的是 `/usr/lib/llvm-18/bin/`（18.x）。因此
> **先设 PATH，再看版本**，且之后每条 `make` 前都要带上这一行：
>
> ```bash
> export PATH=/usr/lib/llvm-18/bin:/usr/bin:/bin:/usr/local/bin:$PATH
> ```
>
> 少了它，你会在毫无提示的情况下用 clang 21 编出一个与实测环境不同的内核。
> 编译完可复核实际使用的编译器（见 §3 产物表）。

确认工具链（在上面 `export` 之后执行）：

```bash
clang --version      # 期望 Ubuntu clang version 18.1.8
ld.lld --version     # 期望 Ubuntu LLD 18.1.8
aarch64-linux-gnu-ld --version
```

---

## 2. 构建配置：`blossom_defconfig`

**位置**：[`arch/arm64/configs/blossom_defconfig`](../arch/arm64/configs/blossom_defconfig)（460 行）

这是本仓库唯一的构建入口。同目录下还有 `stock_defconfig`、`gki_defconfig`、
`v11ksu_defconfig`、`v11noksu_defconfig` 等历史配置，**均不用于当前构建**，
保留仅供对照。

### 2.1 相对基线追加的选项

以下几项是本项目显式追加的，也是"性能 + 无 root"定位的来源：

| 配置行 | 含义 |
|---|---|
| `CONFIG_HZ_1000=y` | 1 ms 调度粒度（取代默认 250 / 300 Hz） |
| `CONFIG_KSM=y` | 内核同页合并，降低内存占用 |
| `CONFIG_IOSCHED_BFQ=y` | BFQ I/O 调度器 |
| `CONFIG_BFQ_GROUP_IOSCHED=y` | BFQ 按 cgroup 分层（本树 Kconfig 中为 `default n`，必须显式写） |
| `# CONFIG_KSU is not set` | 关闭 KernelSU —— "无 root"定位的来源 |

> **注意**：`# CONFIG_KSU is not set` 必须**原样、单独一行**写进 defconfig，
> 行内不要追加注释。只要这一行缺失，`olddefconfig` 就会依据
> `drivers/kernelsu/Kconfig` 中的 `default y` 重新把它打开。

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
#   #define LINUX_COMPILER "Ubuntu clang version 18.1.8, Ubuntu LLD 18.1.8"
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

---

## 4. 配置断言：`check_config.sh`

历史教训：`olddefconfig` / 级联依赖可能**静默关掉**某些选项——尤其是 TEE / ION
secure heap 这类一关就整条链被清除的项（`build-tools/fix11.config` 正是为此保留的
参考片段）。因此每次改配置后都要跑断言。

```bash
bash build-tools/check_config.sh out/.config
```

脚本会检查：

- **必须开启**（`must_y`）：BFQ 三件套、io_uring、KSM、PSI、UCLAMP、
  HZ=1000、PREEMPT、SELinux 默认强制等
- **必须关闭**（`must_n`）：`CONFIG_KSU`（无 root）、调试选项（KASAN / UBSAN /
  DEBUG_PREEMPT / DEBUG_INFO）

任何一项不符即返回非零退出码。**把它接在构建前**，可以避免编出一个"看起来
成功、实际配置错了"的镜像。

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
- `KERNEL_IMG` 未指定时，默认取 `~/android-kernel/out/arch/arm64/boot/Image.gz`
- 第二个参数省略时，输出默认为 `~/android-kernel/boot-4.19.275-stock.img`
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
print("uts_325   =", b"4.19.325-mt6765" in dec)
print("compiler  =", b"clang version" in dec)
PY

# 无 root：不要在镜像里 grep 字符串（kallsyms 压缩，会假阴性），看符号表
grep -ciE '\bksu' out/System.map          # 期望 0
grep -E '^# CONFIG_KSU is not set' out/.config
```

- `md5_match` 必须为 `True` —— 它证明写进镜像的确实是你刚编出来的内核，
  而不是基准镜像里原来那个。
- `uts_325` 必须为 `True` —— `linux_banner` 是普通字符串（不参与 kallsyms 压缩），
  这一条可以放心用字符串匹配。
- `grep ksu` 必须是 **0** —— 见 §3.1 的踩坑提示，这只能用 `System.map` 判定。

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
| `extra_cmdline` | 608 | 1024 字节 | header v1+ |

删除该参数后回写（原子替换，先写 `.new` 再 rename），并回显修改前后的完整内容：

```
patching out.img -> out.img
  patched region @64: removed androidboot.selinux=permissive
  old: ... androidboot.selinux=permissive androidboot.debuggable=1
  new: ... androidboot.debuggable=1
verify header cmdline: '...'
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
# 内核版本（应为 4.19.325-mt6765）
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
| `kernel/Makefile`（约 128 行） | `config_data.gz` 数据源改为 `$(objtree)/.config`，使 `/proc/config.gz` 显示真实构建配置 |
| `drivers/tee/teei/300/tee/Makefile` | 模块命名 `teei_tee.o`，避免与主线 `tee` 撞名导致 sysfs duplicate |
| `drivers/misc/mediatek/lens/mtk/*/` | `if (pdev != &g_stAF_device)` 守卫，避免 dts 共享 compatible 导致重复 probe |
| `fs/ntfs3/`（21 个 `.c`） | NTFS3 已适配 4.19 接口；当前 `CONFIG_NTFS3_FS is not set` |
| `fs/io_uring.c`（4022 行）+ `include/uapi/linux/io_uring.h` | io_uring 移植 |
| `mm/secretmem.c`（272 行）+ `include/uapi/linux/openat2.h` | `memfd_secret` / `openat2` 移植 |
| `drivers/tee/teei/300/tz_driver/switch_queue.c` | `teei_bind_current_cpu()` 存在于 `CONFIG_MICROTRUST_DYNAMIC_CORE` 分支内 |

> `build-tools/fix11.config` 是早期的配置片段，记录了 TEE / ION secure heap
> 的不变量（这些选项**不可随意关闭**，否则会级联清掉 Keymaster / Widevine 依赖）。
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
用下面命令自查（当前树应为 7 : 7）：

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
