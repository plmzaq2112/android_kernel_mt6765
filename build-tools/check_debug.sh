#!/bin/bash
# Debug 断言：调试项生效 + 重型调试项未被连带 + 正式基线保留
# 用法: check_debug.sh <.config>
cfg=${1:?usage: check_debug.sh <.config>}

fail=0

# —— 必须生效的 debug 项 ——
must_y=(
    DEBUG_FS DYNAMIC_DEBUG DETECT_HUNG_TASK SOFTLOCKUP_DETECTOR WQ_WATCHDOG
    # 正式基线在 debug 版同样必须在（防 merge 意外丢失）
    IKCONFIG_PROC PSTORE_RAM PSTORE_CONSOLE PSTORE_PMSG PRINTK KALLSYMS FTRACE
)
for k in "${must_y[@]}"; do
    grep -q "^CONFIG_$k=y" "$cfg" || { echo "FAIL: CONFIG_$k 应为 y"; fail=1; }
done

# —— 版本串区分 ——
grep -q '^CONFIG_LOCALVERSION="-dandelion-debug"' "$cfg" \
    || { echo "FAIL: LOCALVERSION 应为 -dandelion-debug"; fail=1; }

# —— 重型/未批准项必须保持关闭（批3 未点名）——
must_n=(
    KASAN UBSAN DEBUG_PREEMPT DEBUG_INFO KALLSYMS_ALL IKHEADERS
    PROVE_LOCKING LOCKDEP FUNCTION_TRACER FUNCTION_GRAPH_TRACER
    SLUB_DEBUG PAGE_OWNER DEBUG_FS_ALLOW_NONE
)
for k in "${must_n[@]}"; do
    grep -q "^CONFIG_$k=y" "$cfg" && { echo "FAIL: CONFIG_$k 不应启用（重型/未批准）"; fail=1; }
done

if [ $fail -eq 0 ]; then
    echo "check_debug: PASS (debug 项生效, 重型项关闭, 正式基线保留)"
else
    echo "check_debug: FAILED"
    exit 1
fi
