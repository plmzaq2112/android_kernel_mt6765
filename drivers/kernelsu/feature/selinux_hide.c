#include "selinux_hide.h"
#include <linux/init.h>
#include <linux/printk.h>

void ksu_selinux_hide_init()
{
    pr_info("KernelSU: selinux_hide disabled (unavailable on 4.19 policydb build)\n");
}

void ksu_selinux_hide_exit()
{
}

void ksu_selinux_hide_drop_backup_if_unused()
{
}

void ksu_selinux_hide_handle_second_stage()
{
}

void ksu_selinux_hide_handle_post_fs_data()
{
}
