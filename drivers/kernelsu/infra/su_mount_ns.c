// SPDX-License-Identifier: GPL-2.0
#include <linux/types.h>
#include <linux/version.h>
#include "klog.h" // IWYU pragma: keep
#include "infra/su_mount_ns.h"

/*
 * Per-app mount-namespace support (open_tree / move_mount) is not
 * available on Linux 4.19 (UAPI header + syscalls are 5.12+).
 * setup_mount_ns() is therefore a no-op; requesting app profiles
 * fall back to the default kernel manager behavior.
 */
void setup_mount_ns(int32_t ns_mode)
{
    pr_info("KernelSU: setup_mount_ns(%d) skipped on 4.19\n", ns_mode);
}