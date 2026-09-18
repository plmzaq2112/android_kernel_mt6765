# Copyright (c) 2015-2020, MICROTRUST Incorporated
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# version 2 as published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.

obj-y += teei_tee.o
teei_tee-objs += tee_core.o
teei_tee-objs += tee_shm.o
teei_tee-objs += tee_shm_pool.o
teei_tee-objs += tee_client_api.o

ifeq ($(CONFIG_MICROTRUST_TEST_DRIVERS),y)
teei_tee-objs += capi_proxy.o
endif

obj-y += soter/
