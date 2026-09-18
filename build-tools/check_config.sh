# SPDX-License-Identifier: GPL-2.0
#!/bin/bash
# 配置断言:merge_config + olddefconfig 后运行,防止级联污染静默丢选项(ION 教训)
CFG=${1:-/home/yang/项目/kernel/out/.config}
fail=0

must_y=(
  # 加固组
  FORTIFY_SOURCE INIT_ON_ALLOC_DEFAULT_ON INIT_ON_FREE_DEFAULT_ON
  MODULE_SIG STACKPROTECTOR_STRONG HARDENED_USERCOPY REFCOUNT_FULL
  SLAB_FREELIST_HARDENED SLAB_FREELIST_RANDOM KALLSYMS
  ARM64_SW_TTBR0_PAN SECCOMP SECURITY_PERF_EVENTS_RESTRICT
  # TEE 组(Keymaster/DRM 依赖)
  TEE MICROTRUST_TEE_SUPPORT MICROTRUST_TZ_DRIVER
  MICROTRUST_KEYMASTER_DRIVER MICROTRUST_VFS_DRIVER
  # ION secure heap 组(Widevine L1)
  MTK_ION_SEC_HEAP MTK_SECURE_MEM_SUPPORT MTK_SEC_VIDEO_PATH_SUPPORT
  # 5.x 功能组
  IO_URING SECRETMEM NTFS3_FS EROFS_FS FS_VERITY
)
must_n=(
  # 生产化:调试项必须关闭
  DEBUG_PREEMPT DEBUG_INFO KASAN UBSAN KALLSYMS_ALL PAGE_POISONING
  # 无硬件噪音项
  MICROTRUST_FP_DRIVER FPC_FINGERPRINT FOCALTECH_FINGERPRINT
  NFC IKHEADERS
)

for c in "${must_y[@]}"; do
  if ! grep -q "^CONFIG_${c}=y" "$CFG"; then
    echo "MISSING(y): $c"; fail=1
  fi
done
for c in "${must_n[@]}"; do
  if grep -qE "^CONFIG_${c}=y" "$CFG"; then
    echo "MISSING(n): $c"; fail=1
  fi
done

if [ "$fail" -eq 0 ]; then
  echo "config check OK (${#must_y[@]} must-y, ${#must_n[@]} must-n)"
else
  echo "config check FAILED"; exit 1
fi