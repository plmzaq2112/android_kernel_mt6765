#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# 配置断言：防止 olddefconfig 或 Kconfig 依赖关系静默改动关键选项。
#
# 用法:  bash build-tools/check_config.sh [path/to/.config]
#        默认检查 out/.config
#
# 退出码: 0 = 全部通过, 1 = 有不符项
#
CFG=${1:-out/.config}
fail=0

if [ ! -f "$CFG" ]; then
    echo "check_config: $CFG 不存在（先执行 make <defconfig> 生成）"
    exit 1
fi

# 必须开启
must_y=(
    # 性能取向（v2.0 特性线 + io_uring / memfd_secret / wireguard 反向移植）
    DEFAULT_BFQ IOSCHED_BFQ BFQ_GROUP_IOSCHED
    IO_URING KSM PSI UCLAMP_TASK UCLAMP_TASK_GROUP SECRETMEM WIREGUARD
    PREEMPT
    # SELinux 强制
    SECURITY_SELINUX DEFAULT_SECURITY_SELINUX
    # 文件系统
    EROFS_FS FS_VERITY
    # 调度/内存基础
    CGROUPS MEMCG BLK_CGROUP CGROUP_SCHED
    # 本树固定为 built-in（不开可加载模块）：V6 树 connectivity/Makefile 只在
    # WLAN_DRV_BUILD_IN=y 时编入 WiFi 驱动，开 MODULES 会破坏驱动编入链。
    # 这与旧线（v2.0 树 MODULES=y + 钉死 tristate）不同，勿照搬。
    TCP_CONG_WESTWOOD TCP_CONG_BBR NET_SCH_FQ
    BATTERY_MT6357 SND_SOC_MT6357_ACCDET
    # 基础加固（已验证开启）
    STACKPROTECTOR_STRONG HARDENED_USERCOPY SLAB_FREELIST_HARDENED
    SLAB_FREELIST_RANDOM REFCOUNT_FULL SECCOMP
    # TEE / Keymaster / DRM 链（fix11.config 不变量 1，勿拆）
    TEE MICROTRUST_TEE_SUPPORT MICROTRUST_TZ_DRIVER
    MICROTRUST_DYNAMIC_CORE MICROTRUST_VFS_DRIVER
    MICROTRUST_KEYMASTER_DRIVER MICROTRUST_TZ_LOG
    # 安全媒体链 / Widevine L1（fix11.config 不变量 2，勿拆）
    MTK_SEC_VIDEO_PATH_SUPPORT
    MTK_DRM_KEY_MNG_SUPPORT
    MTK_ION_SEC_HEAP
    MTK_SECURE_MEM_SUPPORT
    # 真正决定 trusted_mem/*.o 编不编进内核的是 Makefile:
    #   drivers/misc/mediatek/Makefile: obj-$(CONFIG_MTK_TRUSTED_MEMORY_SUBSYSTEM)
    #   trusted_mem/Makefile:           obj-$(CONFIG_MTK_SSMR)
    # HAVE_... 没有任何 Makefile 引用, 它只是 trusted_mem/Kconfig 里
    # 后两者的 depends on 前提 —— 缺了它 Kconfig 会把后两项整条吃掉,
    # 所以这三个必须一起断（只断前两项会出现"开关 y 但 .o 没生成"）。
    HAVE_MTK_TRUSTED_MEMORY_SUBSYSTEM
    MTK_TRUSTED_MEMORY_SUBSYSTEM
    MTK_SSMR
    # 防御纵深
    ARM64_SW_TTBR0_PAN
)

# 必须关闭
must_n=(
    # 无 root（本仓库定位）。本树没有 kernelsu 源码，defconfig 里也不得
    # 残留 KSU 行（基线曾带死配置行，整合时已清除）。
    KSU KSU_SUSFS
    # dandelion 无指纹/NFC 硬件。前三项 Kconfig 为 default y, 不显式写就
    # 自动开; NFC 实为 default n, 这行只是冗余防御。
    MICROTRUST_FP_DRIVER FPC_FINGERPRINT FOCALTECH_FINGERPRINT NFC
    # 调试/性能损耗项
    KASAN UBSAN DEBUG_PREEMPT DEBUG_INFO KALLSYMS_ALL
    # 无用噪音
    IKHEADERS
)

# 精确值
must_eq=(
    "HZ=1000"
    "HZ_1000=y"
    'MICROTRUST_TEE_VERSION="300"'
    'DEFAULT_IOSCHED="bfq"'
    'DEFAULT_TCP_CONG="bbr"'
)

for c in "${must_y[@]}"; do
    if ! grep -q "^CONFIG_${c}=y" "$CFG"; then
        echo "  MISSING(y): CONFIG_${c}"
        fail=1
    fi
done

for c in "${must_n[@]}"; do
    if grep -qE "^CONFIG_${c}=" "$CFG"; then
        echo "  VIOLATION(n): CONFIG_${c} = $(grep -E "^CONFIG_${c}=" "$CFG" | head -1 | cut -d= -f2-)"
        fail=1
    fi
done

for kv in "${must_eq[@]}"; do
    if ! grep -q "^CONFIG_${kv}$" "$CFG"; then
        echo "  WRONG VALUE: expected CONFIG_${kv}, got: $(grep -E "^# CONFIG_${kv%%=*} is not set|^CONFIG_${kv%%=*}=" "$CFG" | head -1)"
        fail=1
    fi
done

n_y=${#must_y[@]}
n_n=${#must_n[@]}
n_e=${#must_eq[@]}

if [ "$fail" -eq 0 ]; then
    echo "check_config: OK ($n_y must-y, $n_n must-n, $n_e exact)"
else
    echo "check_config: FAILED — 请检查 arch/arm64/configs/blossom_defconfig"
    exit 1
fi
