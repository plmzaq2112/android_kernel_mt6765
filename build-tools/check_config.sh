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
    # 性能取向
    DEFAULT_BFQ IOSCHED_BFQ BFQ_GROUP_IOSCHED
    IO_URING KSM PSI UCLAMP_TASK UCLAMP_TASK_GROUP
    PREEMPT
    # SELinux 强制
    SECURITY_SELINUX DEFAULT_SECURITY_SELINUX
    # 文件系统
    EROFS_FS FS_VERITY SECRETMEM
    # 调度/内存基础
    CGROUPS MEMCG BLK_CGROUP CGROUP_SCHED
    # 基础加固（已验证开启）
    STACKPROTECTOR_STRONG HARDENED_USERCOPY SLAB_FREELIST_HARDENED
    SLAB_FREELIST_RANDOM REFCOUNT_FULL SECCOMP
)

# 必须关闭
must_n=(
    # 无 root（本仓库定位）
    KSU
    # 调试/性能损耗项
    KASAN UBSAN DEBUG_PREEMPT DEBUG_INFO KALLSYMS_ALL
    # 无用噪音
    IKHEADERS
)

# 精确值
must_eq=(
    "HZ=1000"
    "HZ_1000=y"
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
