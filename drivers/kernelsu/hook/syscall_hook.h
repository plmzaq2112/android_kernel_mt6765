#ifndef __KSU_H_KSU_SYSCALL_HOOK
#define __KSU_H_KSU_SYSCALL_HOOK
#include <asm/syscall.h>

#if defined(__x86_64__)
typedef sys_call_ptr_t syscall_fn_t;
#endif

extern syscall_fn_t *ksu_syscall_table;
// Pristine, unpatched copy of sys_call_table (indexed by syscall nr).
extern syscall_fn_t *ksu_syscall_table_orig;

// Dispatcher slot number in syscall table
extern int ksu_dispatcher_nr;

// Syscall hook handler type.
// orig_nr: the original syscall number before redirection
// regs: the original pt_regs from userspace
// Handler is responsible for calling ksu_syscall_table[orig_nr](regs) if needed.
typedef long (*ksu_syscall_hook_fn)(int orig_nr, const struct pt_regs *regs);

// --- Dispatcher-based hook API (register/unregister) ---
// Register a handler into the dispatcher's routing table for syscall @nr.
// When a marked process invokes syscall @nr, the sys_enter tracepoint redirects
// it to the unified dispatcher, which looks up @fn by @nr and calls it.
// Does NOT modify the syscall table itself — the dispatcher slot is shared.
// Returns 0 on success, -EEXIST if already registered, -EINVAL if nr invalid.
int ksu_register_syscall_hook(int nr, ksu_syscall_hook_fn fn);

// Remove a handler from the dispatcher's routing table for syscall @nr.
// The syscall table is not touched — only the dispatcher stops routing @nr.
void ksu_unregister_syscall_hook(int nr);

// Check if a handler is registered in the dispatcher for syscall @nr.
bool ksu_has_syscall_hook(int nr);

// --- Direct syscall table patching API (hook/unhook) ---
// Directly overwrite syscall_table[@nr] with @fn using fixmap + stop_machine.
// Saves the original handler to *@old (if non-NULL) and records the entry
// for restoration at module exit. Use this for boot-time hooks that replace
// a real syscall entry (e.g. ksud hooking __NR_execve/__NR_read/__NR_fstat).
void ksu_syscall_table_hook(int nr, syscall_fn_t fn, syscall_fn_t *old);

// Restore syscall_table[@nr] to its original value recorded by
// ksu_syscall_table_hook(), and remove the entry from the tracking list.
// Use this to cleanly undo a direct hook when it is no longer needed
// (e.g. ksud unhooking __NR_read after init.rc injection is done).
void ksu_syscall_table_unhook(int nr);

void ksu_syscall_hook_init(void);
void ksu_syscall_hook_exit(void);

// Directly patch the real syscall table slots for all registered hooks.
// Only for kernels built WITHOUT CONFIG_FTRACE_SYSCALLS.
void ksu_direct_patch_syscalls(void);
void ksu_direct_patch_sucompat_syscalls(void);
long ksu_direct_reboot_entry(int orig_nr, const struct pt_regs *regs);

#endif
