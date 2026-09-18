<!-- SPDX-License-Identifier: GPL-2.0 -->
# Redmi 9A (dandelion, MT6762G) 完整内核定制 — 构建与维护指南

- 仓库: https://github.com/plmzaq2112/android_kernel_mt6765
- 基础: duhenduhen/android_kernel_xiaomi_mt6765 (lineage-22.2 分支, 4.19.275)
- 分支: `main` (单提交, 含全部移植与修复)
- 上游跟踪: `git remote add upstream https://github.com/duhenduhen/android_kernel_xiaomi_mt6765.git`

---

## 1. 构建环境准备(全新机器)

```bash
# 系统依赖
sudo apt install bison bc libssl-dev        # bison >= 3.5

# 工具链 (clang 16.0.6 + LLD 16.0.6, 任意 aarch64 linux clang 均可)
#   clone 本仓库后, 工具链放 /opt/toolchain 或任意目录, 修改 build_full.sh 的 TC 变量
mkdir -p /opt/toolchain && tar -xJf toolchain-clang16.tar.xz -C /opt/toolchain

# ld.lld 依赖 libxml2.so.2(新系统只有 .so.16), 建软链接:
ln -sf /usr/lib/x86_64-linux-gnu/libxml2.so.16 /usr/lib/x86_64-linux-gnu/libxml2.so.2

# 原厂 boot.img 的 ramdisk/dtb(打包必需, 已随仓库提供 build-tools/boot/)
# 若需重新提取: 用 bootimg 工具解 boot.img, 保存 ramdisk.gz 与 dtb
```

## 2. 首次配置(生成基线 .config)

```bash
cd mt6765-4.19
export PATH="/opt/toolchain/bin:/usr/bin:/bin"
make ARCH=arm64 mt6765_defconfig    # 或 stock_defconfig, 取决于工具链
# 产物 O=out 目录由 merge_config 指定, 见下
```

> 注: 本机 out/.config 已生成并验证, 正常构建跳过此步。

## 3. 构建流程(四步)

```bash
cd mt6765-4.19

# 1. 配置: merge fragment(基线为 out/.config)
scripts/kconfig/merge_config.sh -O /home/yang/项目/kernel/out -m \
    /home/yang/项目/kernel/out/.config build-tools/fix11.config

# 2. 刷新并断言(防级联污染: CONFIG_TEE 误关曾连带清掉 ION secure heap)
export PATH="/home/yang/项目/kernel/toolchain/bin:/usr/bin:/bin"
make ARCH=arm64 O=/home/yang/项目/kernel/out CC=clang \
    CROSS_COMPILE=aarch64-linux-gnu- LD=ld.lld olddefconfig
bash build-tools/check_config.sh    # 26 must-y + 11 must-n, 任何缺失即退出

# 3. 构建
bash build-tools/build_full.sh      # 产物 out/arch/arm64/boot/Image.gz

# 4. 打包(自动移除 kpti=off, 追加 secretmem.enable=1)
python3 build-tools/repack.py /home/yang/项目/kernel/boot-4.19.275-full-v11.img
```

刷机: `adb reboot bootloader && fastboot flash boot boot-4.19.275-full-v11.img`

## 4. 配置策略(fix11.config)

- **不动的基线**: stock_defconfig(MTK 驱动生态必需)
- **必须保留**: TEE 全家(Microtrust 300, Keymaster/DRM 依赖; CONFIG_TEE
  不能关, `drivers/tee/Kconfig` 用 `if TEE` 包裹 teei/Kconfig,
  关闭会级联清掉整个 TEE 栈 → 指纹 uuid_fp 等符号链接失败)
- **必须保留**: ION secure heap 链(MTK_SECURE_MEM_SUPPORT +
  MTK_SEC_VIDEO_PATH_SUPPORT, Widevine L1; 两者均非默认 y,
  merge/olddefconfig 后必须断言, 否则 ion_sec_heap 报 "not support")
- **已关闭(生产化)**: DEBUG_PREEMPT / DEBUG_INFO / KASAN / UBSAN /
  KALLSYMS_ALL / PAGE_POISONING
- **已关闭(无硬件)**: 指纹(FPC + FOCALTECH + MICROTRUST_FP_DRIVER)、
  NFC、IKHEADERS
- **已验证开启**: KPTI(cmdline 无 kpti=off)+ CONFIG_ARM64_SW_TTBR0_PAN=y

## 5. 关键源码修改(移植记录)

| 文件 | 修改 |
|---|---|
| kernel/Makefile | config_data.gz 数据源 stock_defconfig → $(objtree)/.config(/proc/config.gz 显示真实构建配置) |
| drivers/tee/teei/300/tee/Makefile | 模块改名 tee.o → teei_tee.o(消除与主线 /module/tee 撞名 → sysfs duplicate) |
| drivers/tee/teei/300/tz_driver/switch_queue.c | teei_bind_current_cpu 用 preempt_disable/enable 包裹(4.19 无 migration_disable; 消除 154 次 smp_processor_id WARN) |
| drivers/tee/teei/300/tz_driver/sysfs.c | wake_up(&__wait_spi_wq) 加 #ifdef CONFIG_MICROTRUST_FP_DRIVER(允许关闭指纹) |
| drivers/misc/mediatek/cam_cal/src/common/v1/eeprom_driver.c | EEPROM_HW_i2c_driver4 .name 改为 CAM_CAL_I2C_DEV4_NAME(原误用 CAM_CAL_DRV_NAME → 重名 -EBUSY) |
| drivers/misc/mediatek/lens/mtk/{main,main2,main3,sub,sub2}/*_lens.c | AF_probe 仅对自有 g_stAF_device 注册 i2c(dts 共享 compatible "mediatek,camera_af_lens" 导致 probe 两次 → 重复注册) |
| fs/ntfs3/ 全套 | 5.15 NTFS3 移植(mnt_userns 15 处去参 / ACL 4.19 化 / submit_bh 三参 / BIO_MAX_VECS→BIO_MAX_PAGES / bitmap_size 重命名 / static_assert·fallthrough 宏) |
| fs/io_uring.c 等 | 5.4 io_uring 移植 |
| mm/secretmem.c | 5.14 memfd_secret 移植(cmdline 需 secretmem.enable=1) |
| include/uapi/linux/{io_uring,openat2}.h | 5.x uapi 补全 |

## 6. 设备侧验证

```bash
# 版本与构建信息
adb shell cat /proc/version
# 5.x 特性与加固确认
adb shell su -c "zcat /proc/config.gz | grep -E 'IO_URING|SECRETMEM|NTFS3|FORTIFY|ARM64_SW_TTBR0_PAN|MTK_SECURE_MEM'"
# 健康检查(应全空)
adb shell su -c "dmesg | grep -iE 'BUG|WARNING|already registered|smp_processor_id|teei_fp' | head"
```

## 7. 向 GitHub 推送更新

```bash
cd mt6765-4.19
git add -A && git commit -m "说明"
git push              # origin = git@ssh.github.com:plmzaq2112/android_kernel_mt6765.git
```

> 环境备注(本机): GitHub 直连不稳定, 采用 SSH 443 通道
> (`ssh.github.com:443`, 公钥 ~/.ssh/github_push.pub 已添加至 GitHub)。
> 仓库已配置 `core.sshCommand` 与 `http.postBuffer`, 无需额外设置。

## 8. 版本历史

- v7: memfd_secret + NTFS3 移植完成
- v8: /proc/config.gz 数据源修复(显示真实配置)
- v9: KPTI/PAN 双开、TEEI BUG 修复、teei_tee 改名、CAM_CAL_DRV 重名修复
- v10: ION secure heap 恢复(TEE 级联污染)、5 个 lens 驱动重复注册修复
- v11: 关闭无硬件噪音项(指纹/NFC/IKHEADERS) — 最终定版

最终镜像: /home/yang/项目/kernel/boot-4.19.275-full-v11.img
