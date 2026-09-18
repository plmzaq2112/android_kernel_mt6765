// KernelSU kprobe-free direct hook (syscall-table) for MT6765 4.19 kernel.
// Replaces the CONFIG_KPROBES path: on this MTK tree CONFIG_KPROBES crashes
// (deterministic bootloop on A53), so we install execve/execveat handlers
// straight into sys_call_table (requires CONFIG_KALLSYMS_ALL to locate it).

#include <linux/fs.h>
#include <linux/namei.h>
#include <linux/uaccess.h>
#include <linux/sched.h>
#include <linux/sched/task.h>
#include <linux/cred.h>
#include <linux/kallsyms.h>
#include <linux/version.h>
#include <linux/compat.h>
#include <linux/ptrace.h>
#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 14, 0)
#include <linux/sched/task_stack.h>
#endif
#include <linux/set_memory.h>

#include "ksud.h"
#include "kernel_compat.h"
#include "klog.h"

#define SU_PATH "/system/bin/su"
#define KSUD_PATH_STR "/data/adb/ksud"

struct user_arg_ptr {
#ifdef CONFIG_COMPAT
	bool is_compat;
#endif
	union {
		const char __user *const __user *native;
#ifdef CONFIG_COMPAT
		const compat_uptr_t __user *compat;
#endif
	} ptr;
};

extern int ksu_handle_execveat_ksud(int *fd, struct filename **filename_ptr,
				    struct user_arg_ptr *argv,
				    struct user_arg_ptr *envp, int *flags);
extern int ksu_handle_execveat_sucompat(int *fd, struct filename **filename_ptr,
					void *argv, void *envp, int *flags);
extern int ksu_handle_execve_sucompat(int *fd, const char __user **filename_user,
				      void *argv, void *envp, int *flags);

typedef asmlinkage long (*ksu_syscall_fn)(const struct pt_regs *regs);
typedef void *ksu_syscall_cell_t;

static ksu_syscall_cell_t *sys_call_table;
static ksu_syscall_fn orig_sys_execve;
static ksu_syscall_fn orig_sys_execveat;

#ifndef __NR_execve
#define __NR_execve 221
#endif
#ifndef __NR_execveat
#define __NR_execveat 281
#endif

static int ksu_direct_patch(ksu_syscall_fn *slot, ksu_syscall_fn newfn)
{
	unsigned long page = (unsigned long)slot & PAGE_MASK;
	int ret;

	/* MTK maps the kernel image with block entries: pageattr returns
	 * -EINVAL. sys_call_table sits in .data/.bss which is writable, so
	 * try set_memory_rw as best effort and write regardless. */
	ret = set_memory_rw(page, 1);
	if (ret)
		pr_info("ksu_direct: set_memory_rw skipped (%d), writing directly\n",
			ret);
	*slot = newfn;
	return 0;
}

static void __user *ksu_direct_user_path(const char *path)
{
	int len = strlen(path) + 1;
	const struct pt_regs *regs = task_pt_regs(current);
	char __user *p = (void __user *)(regs->sp - len);

	if (copy_to_user(p, path, len))
		return NULL;
	return p;
}

/* returns true when /data/adb/ksud is present (executable next step) */
static bool ksu_direct_ksud_present(void)
{
	struct file *f = filp_open(KSUD_PATH_STR, O_RDONLY, 0);

	if (IS_ERR(f))
		return false;
	filp_close(f, NULL);
	return true;
}

static asmlinkage long ksu_sys_execve(const struct pt_regs *regs)
{
	const char __user *filename_user = (const char __user *)regs->regs[0];
	const char __user *saved_filename = filename_user;
	int fd = AT_FDCWD;
	int flags = 0;
	struct filename *filename = getname(filename_user);

	if (!IS_ERR(filename)) {
		struct user_arg_ptr argv = {
#ifdef CONFIG_COMPAT
			.is_compat = false,
#endif
			.ptr.native =
				(const char __user *const __user *)regs->regs[1],
		};
		struct user_arg_ptr envp = {
#ifdef CONFIG_COMPAT
			.is_compat = false,
#endif
			.ptr.native =
				(const char __user *const __user *)regs->regs[2],
		};
		ksu_handle_execveat_ksud(&fd, &filename, &argv, &envp, &flags);
		putname(filename);
	}

	ksu_handle_execve_sucompat(&fd, &filename_user, NULL, NULL, NULL);

	if (filename_user != saved_filename && filename_user) {
		/* su -> KSUD was requested; ksud may not be installed on very
		 * first boot, fall back to a plain root shell so the Manager
		 * can bootstrap itself. */
		char pbuf[sizeof(KSUD_PATH_STR)] = {0};

		ksu_strncpy_from_user_nofault(pbuf, filename_user,
					      sizeof(pbuf));
		if (!strcmp(pbuf, KSUD_PATH_STR) &&
		    !ksu_direct_ksud_present()) {
			pr_info("ksu_direct: ksud missing, execve su -> /system/bin/sh\n");
			filename_user =
				ksu_direct_user_path("/system/bin/sh");
		}
		((struct pt_regs *)regs)->regs[0] = (u64)filename_user;
	}

	return orig_sys_execve(regs);
}

static asmlinkage long ksu_sys_execveat(const struct pt_regs *regs)
{
	int fd = (int)regs->regs[0];
	int flags = (int)regs->regs[4];
	const char __user *pathname_user = (const char __user *)regs->regs[1];
	unsigned long new_pathname = 0;

	if (pathname_user) {
		struct filename *filename = getname(pathname_user);
		if (!IS_ERR(filename)) {
			struct user_arg_ptr argv = {
#ifdef CONFIG_COMPAT
				.is_compat = false,
#endif
				.ptr.native = (const char __user *const __user *)
					      regs->regs[2],
			};
			struct user_arg_ptr envp = {
#ifdef CONFIG_COMPAT
				.is_compat = false,
#endif
				.ptr.native = (const char __user *const __user *)
					      regs->regs[3],
			};
			ksu_handle_execveat_ksud(&fd, &filename, &argv, &envp,
						 &flags);

			ksu_handle_execveat_sucompat(&fd, &filename, NULL, NULL,
						     &flags);

			if (!strncmp(filename->name, KSUD_PATH_STR,
				     sizeof(KSUD_PATH_STR))) {
				/* sucompat redirected su -> KSUD_PATH, also
				 * rewrite the user-space pointer so the
				 * original syscall resolves the new path. */
				if (!ksu_direct_ksud_present()) {
					pr_info("ksu_direct: ksud missing, execveat su -> /system/bin/sh\n");
					new_pathname = (unsigned long)
						ksu_direct_user_path(
							"/system/bin/sh");
				} else {
					new_pathname = (unsigned long)
						ksu_direct_user_path(
							KSUD_PATH_STR);
				}
			}

			putname(filename);
		}
	}

	if (new_pathname) {
		((struct pt_regs *)regs)->regs[1] = new_pathname;
	}

	return orig_sys_execveat(regs);
}

int ksu_direct_init(void)
{
	unsigned long table;

	table = kallsyms_lookup_name("sys_call_table");
	if (!table) {
		pr_alert("ksu_direct: failed to locate sys_call_table!\n");
		return -ENXIO;
	}
	sys_call_table = (ksu_syscall_cell_t *)table;
	pr_info("ksu_direct: sys_call_table @ 0x%lx\n", table);

	orig_sys_execve = (ksu_syscall_fn)sys_call_table[__NR_execve];
	orig_sys_execveat = (ksu_syscall_fn)sys_call_table[__NR_execveat];

	ksu_direct_patch((ksu_syscall_fn *)&sys_call_table[__NR_execve],
			 ksu_sys_execve);
	ksu_direct_patch((ksu_syscall_fn *)&sys_call_table[__NR_execveat],
			 ksu_sys_execveat);

	pr_alert("KSU ksu_direct enabled (kprobe-free): execve/execveat hooked\n");
	return 0;
}