/* SPDX-License-Identifier: GPL-2.0 */
#ifndef _LINUX_SECRETMEM_H
#define _LINUX_SECRETMEM_H

#include <linux/types.h>

struct vm_area_struct;

bool vma_is_secretmem(struct vm_area_struct *vma);
bool secretmem_active(void);

#endif /* _LINUX_SECRETMEM_H */