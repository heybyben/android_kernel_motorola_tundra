# SPDX-License-Identifier: GPL-2.0-only
# i3c-qup-trace.h sets TRACE_INCLUDE_PATH to "." and is re-included through
# include/trace/define_trace.h, so this directory must be on the include path.
ccflags-y += -I$(src)

obj-$(CONFIG_CDNS_I3C_MASTER)		+= i3c-master-cdns.o
obj-$(CONFIG_DW_I3C_MASTER)		+= dw-i3c-master.o
obj-$(CONFIG_SVC_I3C_MASTER)		+= svc-i3c-master.o
obj-$(CONFIG_MIPI_I3C_HCI)		+= mipi-i3c-hci/
obj-$(CONFIG_I3C_MASTER_MSM_GENI)	+= i3c-master-msm-geni.o
